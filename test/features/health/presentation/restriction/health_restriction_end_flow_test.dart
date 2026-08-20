import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_end_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_end_form_screen.dart';

/// B4-C.3 — os três cenários do encerramento clínico, mais a matriz de
/// validação exigida pelo B4-C.3.R/V.
///
/// ```text
/// 1. END não commitou   → ATIVA        → erro de encerramento
/// 2. END + convergiu    → ENCERRADA    → prontidão confirmada    → reload
/// 3. END + NÃO convergiu → ENCERRADA   → não confirmada          → reload
///                                       → retry disponível
///                                       → END/pipeline count == 1
/// ```
const _dogId = 'dog-1';
const _restrictionId = 'or_abc123';

RecordedBy _actor([String name = 'Cb. Silva']) =>
    RecordedBy(uid: 'uid-1', name: name, internalRole: 'condutor');

ProfessionalIdentity _professional({String name = 'Dra. Ana Souza'}) =>
    ProfessionalIdentity(
      name: name,
      registrationType: ProfessionalRegistrationType.crmv,
      registrationNumber: 'SP-12345',
      clinic: 'Clínica Central',
    );

/// Respeita a exclusividade terminal do aggregate: `ended` exige os cinco
/// campos de encerramento juntos e `cancelled` os três de cancelamento, sem
/// metadata cruzada.
OperationalRestriction _restrictionWith(
  RestrictionStatus status, {
  String endReason = 'Alta clínica confirmada',
  String endProfessionalName = 'Dra. Ana Souza',
  String endedByName = 'Sgt. Costa',
}) {
  final ended = status == RestrictionStatus.ended;
  final cancelled = status == RestrictionStatus.cancelled;
  return OperationalRestriction(
    id: _restrictionId,
    dogId: _dogId,
    level: RestrictionLevel.absolute,
    category: RestrictionCategory.injury,
    description: 'Lesão em membro anterior',
    issuedAt: DateTime.utc(2026, 8, 1, 10),
    recordedBy: _actor(),
    professional: _professional(),
    sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_abc'),
    status: status,
    schemaVersion: 1,
    activitiesRestricted: const <String>[],
    actualEnd: ended ? DateTime.utc(2026, 8, 10, 9) : null,
    endedBy: ended ? _actor(endedByName) : null,
    endReason: ended ? endReason : null,
    endProfessional: ended
        ? _professional(name: endProfessionalName)
        : null,
    endSourceDocument: ended
        ? const HealthDocumentRef(healthDocumentId: 'hd_end')
        : null,
    cancelledAt: cancelled ? DateTime.utc(2026, 8, 5, 8) : null,
    cancelledBy: cancelled ? _actor('Ten. Rocha') : null,
    cancelReason: cancelled ? 'Registro aberto por engano' : null,
  );
}

/// Gateway de leitura que muda de ACTIVE para ENDED após o END commitar, como o
/// documento canônico real faria.
final class _ReadGateway implements HealthRestrictionReadGateway {
  int calls = 0;
  RestrictionStatus status = RestrictionStatus.active;

  /// Permite que a releitura canônica devolva um aggregate diferente do que o
  /// formulário enviou — usado para provar `canonical > form state`.
  ///
  /// Não se chama `override`: um campo com esse nome é lido como anotação
  /// `@override` pelo analisador na declaração seguinte.
  OperationalRestriction Function(int call)? canonicalOverride;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async {
    calls += 1;
    final builder = canonicalOverride;
    if (builder != null) {
      return HealthRestrictionReadSuccess(builder(calls));
    }
    return HealthRestrictionReadSuccess(_restrictionWith(status));
  }
}

void main() {
  const dogId = _dogId;
  const restrictionId = _restrictionId;

  late _ReadGateway readGateway;
  late _FakeDocumentGateway doc;
  late _FakeUploader uploader;
  late _FakeLifecycleGateway lifecycle;
  late _RefreshStub refresh;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    readGateway = _ReadGateway();
    doc = _FakeDocumentGateway();
    uploader = _FakeUploader();
    lifecycle = _FakeLifecycleGateway();
    refresh = _RefreshStub();
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedSummary({
    required String projectionStatus,
    int? generation,
  }) async {
    await firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_summary')
        .doc('current')
        .set(<String, Object?>{
          'projection_status': projectionStatus,
          'schema_version': 1,
          ...generation == null
              ? const <String, Object?>{}
              : <String, Object?>{'projection_generation': generation},
        });
  }

  HealthRestrictionEndController buildEndController() =>
      HealthRestrictionEndController(
        documentGateway: doc,
        uploader: uploader,
        lifecycleGateway: lifecycle,
        convergenceGateway: HealthReadinessConvergenceGateway(
          invoke: refresh.call,
          firestore: firestore,
        ),
        operationIdFactory: () => 'end-op',
      );

  late HealthRestrictionEndController endController;

  Future<void> pumpDetail(WidgetTester tester) async {
    // Superfície alta: o formulário de encerramento é mais longo que a viewport
    // padrão de teste, e taps em widgets fora dela erram o alvo silenciosamente.
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final detail = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: readGateway,
    );
    addTearDown(detail.dispose);
    endController = buildEndController();

    await tester.pumpWidget(
      MaterialApp(
        home: HealthRestrictionDetailScreen(
          controller: detail,
          dogName: 'Thor',
          endControllerFactory: () => endController,
          evidencePicker: () async => const HealthEvidenceFileAccepted(
            SelectedHealthEvidenceFile(
              name: 'alta.pdf',
              path: '/tmp/alta.pdf',
              sizeBytes: 2048,
              mimeType: 'application/pdf',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Abre o formulário de encerramento a partir do detalhe.
  Future<void> openEndForm(WidgetTester tester) async {
    // O botão fica no fim de um corpo rolável: sem trazer à viewport o tap
    // erra o alvo e o formulário nunca abre.
    final openEnd = find.byKey(const Key('restriction_open_end_form'));
    await tester.ensureVisible(openEnd);
    await tester.pumpAndSettle();
    await tester.tap(openEnd);
    await tester.pumpAndSettle();
  }

  /// Preenche o formulário. Cada campo omitido serve à matriz de validação.
  Future<void> fillEndForm(
    WidgetTester tester, {
    bool reason = true,
    bool professional = true,
    bool evidence = true,
    bool nature = true,
    bool documentTitle = true,
    String reasonText = 'Alta clínica confirmada',
  }) async {
    if (reason) {
      await tester.enterText(
        find.byKey(const Key('restriction_end_reason')),
        reasonText,
      );
      await tester.pumpAndSettle();
    }

    if (professional) {
      // Mesma sequência do teste de emissão: `pumpAndSettle` após CADA campo.
      // O draft do profissional é reconstruído no `onChanged`, e sem o settle a
      // entrada seguinte opera sobre um widget obsoleto e o valor é descartado.
      await tester.enterText(
        find.byKey(const Key('restriction_professional_name')),
        'Dra. Ana Souza',
      );
      await tester.pumpAndSettle();
      // Tipo de conselho é afirmação do operador: nunca pré-selecionado.
      // A key usa `wireName`, que para CRMV é maiúsculo.
      await tester.tap(find.byKey(const Key('restriction_registration_CRMV')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('restriction_professional_number')),
        'SP-12345',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('restriction_professional_clinic')),
        'Clínica Central',
      );
      await tester.pumpAndSettle();
    }

    if (evidence) {
      await tester.tap(find.byKey(const Key('restriction_end_pick_file')));
      await tester.pumpAndSettle();
    }

    if (nature) {
      await tester.tap(find.text('Atestado veterinário'));
      await tester.pumpAndSettle();
    }

    if (documentTitle) {
      await tester.enterText(
        find.byKey(const Key('restriction_end_document_title')),
        'Atestado de alta',
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    final submit = find.text('ENCERRAR RESTRIÇÃO');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  /// Preenche e submete o formulário de encerramento completo.
  Future<void> submitEndForm(WidgetTester tester) async {
    await openEndForm(tester);
    await fillEndForm(tester);
    await tapSubmit(tester);

    // Guarda contra falso negativo: se a validação barrar o submit, o motivo
    // aparece explícito em vez de virar um `endCount == 0` silencioso.
    expect(
      find.textContaining('Informe'),
      findsNothing,
      reason: 'formulário deveria estar completo antes do submit',
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // §6 — ACTIVE-ONLY END ACTION (matriz completa)
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§6 ACTIVE oferece a ação de encerrar', (tester) async {
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsOneWidget);
    expect(find.textContaining('CANCELAR RESTRIÇÃO'), findsNothing);
  });

  testWidgets('§6 ENDED não oferece a ação de encerrar', (tester) async {
    readGateway.status = RestrictionStatus.ended;
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsNothing);
    expect(find.textContaining('CANCELAR RESTRIÇÃO'), findsNothing);
  });

  testWidgets('§6 CANCELLED não oferece a ação de encerrar', (tester) async {
    readGateway.status = RestrictionStatus.cancelled;
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsNothing);
    expect(find.textContaining('CANCELAR RESTRIÇÃO'), findsNothing);
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §5 — INPUT VALIDATION MATRIX: nada inválido alcança o END writer
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§5 motivo ausente não alcança o END writer', (tester) async {
    await pumpDetail(tester);
    await openEndForm(tester);
    await fillEndForm(tester, reason: false);
    await tapSubmit(tester);

    expect(lifecycle.endCount, 0);
    expect(doc.prepareCount, 0);
    expect(uploader.count, 0);
    expect(doc.finalizeCount, 0);
    expect(refresh.refreshCount, 0);
    expect(endController.convergence.mutationCommitted, isFalse);
    expect(find.textContaining('Informe o motivo'), findsOneWidget);
  });

  testWidgets('§5 profissional ausente não alcança o END writer', (
    tester,
  ) async {
    await pumpDetail(tester);
    await openEndForm(tester);
    await fillEndForm(tester, professional: false);
    await tapSubmit(tester);

    expect(lifecycle.endCount, 0);
    expect(doc.prepareCount, 0);
    expect(uploader.count, 0);
    expect(doc.finalizeCount, 0);
    expect(endController.convergence.mutationCommitted, isFalse);
  });

  testWidgets('§5 evidência ausente não alcança o END writer', (tester) async {
    await pumpDetail(tester);
    await openEndForm(tester);
    await fillEndForm(tester, evidence: false, nature: false);
    await tapSubmit(tester);

    expect(lifecycle.endCount, 0);
    expect(doc.prepareCount, 0);
    expect(uploader.count, 0);
    expect(doc.finalizeCount, 0);
    expect(endController.convergence.mutationCommitted, isFalse);
    expect(find.textContaining('Anexe o documento'), findsOneWidget);
  });

  testWidgets('§5 título do documento ausente não alcança o END writer', (
    tester,
  ) async {
    await pumpDetail(tester);
    await openEndForm(tester);
    await fillEndForm(tester, documentTitle: false);
    await tapSubmit(tester);

    expect(lifecycle.endCount, 0);
    expect(doc.prepareCount, 0);
    expect(endController.convergence.mutationCommitted, isFalse);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CENÁRIOS CENTRAIS
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets(
    'CENÁRIO 1 — END não commitou: restrição segue ATIVA, erro de encerramento',
    (tester) async {
      lifecycle.failure = const HealthRestrictionFlowConflict(
        HealthRestrictionFlowStep.restrictionEnd,
        'Restrição já encerrada.',
      );
      await pumpDetail(tester);
      final readsBefore = readGateway.calls;

      await submitEndForm(tester);

      expect(lifecycle.endCount, 1);
      // Mutation não confirmada: nada de mutationCommitted, nada de convergência.
      expect(endController.convergence.mutationCommitted, isFalse);
      expect(refresh.refreshCount, 0);
      // Sem reload canônico: o documento não mudou.
      expect(readGateway.calls, readsBefore);
      expect(endController.failure, isNotNull);
    },
  );

  testWidgets(
    'CENÁRIO 2 — END commitou e convergiu: ENCERRADA, confirmada, reload',
    (tester) async {
      await seedSummary(projectionStatus: 'ready', generation: 42);
      await pumpDetail(tester);
      final readsBefore = readGateway.calls;
      // O documento canônico passa a ENDED após o commit.
      readGateway.status = RestrictionStatus.ended;

      await submitEndForm(tester);

      expect(lifecycle.endCount, 1);
      expect(endController.convergence.mutationCommitted, isTrue);
      expect(endController.convergence.isConverged, isTrue);
      // Reload canônico aconteceu.
      expect(readGateway.calls, greaterThan(readsBefore));
      // Sem banner de pendência.
      expect(
        find.byKey(const Key('restriction_convergence_pending')),
        findsNothing,
      );
      expect(find.text('ENCERRADA'), findsOneWidget);
    },
  );

  testWidgets(
    'CENÁRIO 3 — END commitou e NÃO convergiu: ENCERRADA, pendente, retry',
    (tester) async {
      // Projeção indisponível: convergência não pode ser provada.
      await seedSummary(projectionStatus: 'unavailable', generation: 41);
      await pumpDetail(tester);
      final readsBefore = readGateway.calls;
      readGateway.status = RestrictionStatus.ended;

      await submitEndForm(tester);

      // O comando É fato canônico.
      expect(lifecycle.endCount, 1);
      expect(endController.convergence.mutationCommitted, isTrue);
      expect(endController.convergence.isConverged, isFalse);
      expect(endController.convergence.needsConvergenceRetry, isTrue);
      // Detalhe recarregado mesmo sem convergência.
      expect(readGateway.calls, greaterThan(readsBefore));
      expect(find.text('ENCERRADA'), findsOneWidget);
      // Banner presente, com linguagem de sincronização — nunca de falha.
      expect(
        find.byKey(const Key('restriction_convergence_pending')),
        findsOneWidget,
      );
      expect(find.textContaining('Encerramento aplicado'), findsOneWidget);
      expect(find.textContaining('Falha ao encerrar'), findsNothing);
      expect(find.textContaining('não foi encerrada'), findsNothing);

      // Pipeline documental e END executados exatamente uma vez.
      expect(doc.prepareCount, 1);
      expect(uploader.count, 1);
      expect(doc.finalizeCount, 1);
      expect(lifecycle.endCount, 1);

      // Retry causal: servidor agora consegue projetar.
      await seedSummary(projectionStatus: 'ready', generation: 42);
      await tester.tap(
        find.byKey(const Key('restriction_retry_convergence')),
      );
      await tester.pumpAndSettle();

      expect(endController.convergence.isConverged, isTrue);
      // NADA foi repetido: nem END, nem PREPARE, nem upload, nem FINALIZE.
      expect(
        lifecycle.endCount,
        1,
        reason: 'retry causal jamais reenvia END',
      );
      expect(doc.prepareCount, 1, reason: 'PREPARE jamais refeito');
      expect(uploader.count, 1, reason: 'upload jamais refeito');
      expect(doc.finalizeCount, 1, reason: 'FINALIZE jamais refeito');
      expect(refresh.refreshCount, 2, reason: 'apenas o refresh repetiu');
      // Resultado terminal preservado.
      expect(endController.result, isNotNull);
    },
  );

  // ───────────────────────────────────────────────────────────────────────────
  // §8 — SEGUNDA FALHA DE RETRY CAUSAL
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§8 retry causal falha de novo: mutation permanece commitada', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.ended;

    await submitEndForm(tester);

    expect(endController.convergence.mutationCommitted, isTrue);
    expect(endController.convergence.convergenceFailed, isTrue);
    expect(refresh.refreshCount, 1);

    // Retry explícito, projeção segue indisponível.
    await tester.tap(find.byKey(const Key('restriction_retry_convergence')));
    await tester.pumpAndSettle();

    // Fato durável preservado.
    expect(endController.convergence.mutationCommitted, isTrue);
    expect(endController.convergence.isConverged, isFalse);
    expect(endController.convergence.needsConvergenceRetry, isTrue);

    // Writer jamais reexecutado.
    expect(lifecycle.endCount, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);

    // Exatamente duas tentativas: nenhum terceiro refresh automático.
    expect(
      refresh.refreshCount,
      2,
      reason: 'nenhum refresh automático além do retry explícito',
    );

    // Canônico segue ENDED e o operador continua com retry à disposição.
    expect(find.text('ENCERRADA'), findsOneWidget);
    expect(
      find.byKey(const Key('restriction_retry_convergence')),
      findsOneWidget,
    );
    expect(find.textContaining('Falha ao encerrar'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §9 — CANONICAL AUTHORITY X vs Y
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§9 canônico Y sobrepõe os valores X do formulário', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    // Após o commit, a releitura canônica devolve valores Y — diferentes dos
    // valores X digitados no formulário.
    readGateway.canonicalOverride = (call) => _restrictionWith(
      RestrictionStatus.ended,
      endReason: 'Liberacao homologada pelo veterinario responsavel',
      endProfessionalName: 'Dr. Bruno Lima',
      endedByName: 'Maj. Pereira',
    );

    // X = 'Alta clínica confirmada'
    await submitEndForm(tester);

    expect(lifecycle.endCount, 1);
    expect(endController.convergence.mutationCommitted, isTrue);

    // Y é a autoridade exibida.
    expect(
      find.text('Liberacao homologada pelo veterinario responsavel'),
      findsOneWidget,
    );
    expect(find.text('Dr. Bruno Lima'), findsOneWidget);
    expect(find.text('Maj. Pereira'), findsOneWidget);

    // X NÃO permanece como autoridade terminal.
    expect(
      find.text('Alta clínica confirmada'),
      findsNothing,
      reason: 'form state jamais sobrevive à releitura canônica',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §10 — PERMISSION DENIED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§10 permission-denied: nenhuma prontidão, nenhum ENDED', (
    tester,
  ) async {
    lifecycle.failure = const HealthRestrictionFlowPermissionDenied(
      HealthRestrictionFlowStep.restrictionEnd,
    );
    await pumpDetail(tester);
    final readsBefore = readGateway.calls;

    await submitEndForm(tester);

    expect(lifecycle.endCount, 1);
    expect(endController.convergence.mutationCommitted, isFalse);
    expect(refresh.refreshCount, 0);
    // Nenhum reload: o canônico não mudou.
    expect(readGateway.calls, readsBefore);
    // UX controlada, sem sucesso clínico fabricado.
    expect(
      endController.failure?.code,
      HealthRestrictionFlowErrorCode.permissionDenied,
    );
    expect(find.textContaining('Restrição encerrada'), findsNothing);
    expect(find.text('ENCERRADA'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §11 — TERMINAL CONFLICT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§11 conflito terminal: sem sucesso e sem replay de END', (
    tester,
  ) async {
    lifecycle.failure = const HealthRestrictionFlowConflict(
      HealthRestrictionFlowStep.restrictionEnd,
      'Restrição já encerrada.',
    );
    await pumpDetail(tester);

    await submitEndForm(tester);

    expect(lifecycle.endCount, 1, reason: 'nenhum replay automático de END');
    expect(endController.convergence.mutationCommitted, isFalse);
    // Convergência jamais usada como recuperação de conflito.
    expect(refresh.refreshCount, 0);
    expect(endController.failure, isNotNull);
    expect(find.textContaining('Restrição encerrada'), findsNothing);
  });

  testWidgets('§11 conflito terminal: canônico CANCELLED renderiza CANCELADA', (
    tester,
  ) async {
    lifecycle.failure = const HealthRestrictionFlowConflict(
      HealthRestrictionFlowStep.restrictionEnd,
      'Restrição já encerrada.',
    );
    // O canônico revela o estado terminal factual atual: CANCELLED.
    readGateway.status = RestrictionStatus.cancelled;
    await pumpDetail(tester);

    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    // CANCELLED não oferece END, então o writer nunca é alcançado.
    expect(find.byKey(const Key('restriction_open_end_form')), findsNothing);
    expect(lifecycle.endCount, 0);
    expect(refresh.refreshCount, 0);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §7 — DOUBLE SUBMIT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§7 duplo submit não inicia segundo pipeline', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    final gate = Completer<void>();
    lifecycle.gate = gate;

    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.ended;

    await openEndForm(tester);
    await fillEndForm(tester);

    final submit = find.text('ENCERRAR RESTRIÇÃO');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();

    // Primeira submissão: fica presa no END até liberarmos o gate.
    await tester.tap(submit);
    await tester.pump();

    expect(lifecycle.endCount, 1);

    // Segunda tentativa durante o pipeline em voo.
    final submittingCta = find.text('ENCERRANDO...');
    expect(
      submittingCta,
      findsOneWidget,
      reason: 'CTA deve refletir submissão em voo',
    );
    await tester.tap(submittingCta, warnIfMissed: false);
    await tester.pump();

    // Nada duplicou.
    expect(lifecycle.endCount, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);

    gate.complete();
    await tester.pumpAndSettle();

    // Depois de concluir, ainda exatamente uma execução de cada etapa.
    expect(lifecycle.endCount, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
    expect(refresh.refreshCount, 1, reason: 'uma única convergência');
    expect(endController.convergence.mutationCommitted, isTrue);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §12 — SAÍDA APÓS COMMIT + CONVERGENCE FAILED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§12 sair após commit sem convergência preserva a verdade', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.ended;

    await submitEndForm(tester);

    // O formulário já fechou (saída do fluxo de END) e o detalhe é o host.
    expect(find.byKey(const Key('restriction_end_reason')), findsNothing);

    // Verdade da mutation preservada no host, que sobreviveu ao formulário.
    expect(endController.convergence.mutationCommitted, isTrue);
    expect(endController.convergence.isConverged, isFalse);
    expect(endController.result, isNotNull);

    // Canônico recarregado e visível como ENDED.
    expect(find.text('ENCERRADA'), findsOneWidget);

    // Pipeline intacto.
    expect(lifecycle.endCount, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);

    // Sem linguagem de rollback, e o operador não fica preso: retry disponível.
    expect(find.textContaining('Falha ao encerrar'), findsNothing);
    expect(find.textContaining('não foi encerrada'), findsNothing);
    expect(find.textContaining('revertida'), findsNothing);
    expect(
      find.byKey(const Key('restriction_retry_convergence')),
      findsOneWidget,
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §13 — DISTINÇÃO ENTRE EVIDÊNCIA DE ORIGEM E DE LIBERAÇÃO
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§13 ENDED distingue documento de origem e de liberação', (
    tester,
  ) async {
    readGateway.status = RestrictionStatus.ended;
    await pumpDetail(tester);

    // Origem: evidência que fundamentou a restrição.
    expect(find.text('Vinculado ao registro'), findsOneWidget);
    // Liberação: evidência clínica do encerramento.
    expect(find.text('Vinculado ao encerramento'), findsOneWidget);
    // Rótulos distintos, sem colapso semântico.
    expect(find.text('DOCUMENTO CLÍNICO'), findsOneWidget);
    expect(find.text('DOCUMENTO DE LIBERAÇÃO'), findsOneWidget);
  });

  testWidgets('§13 ACTIVE não anuncia documento de liberação', (tester) async {
    await pumpDetail(tester);

    expect(find.text('Vinculado ao registro'), findsOneWidget);
    expect(find.text('DOCUMENTO DE LIBERAÇÃO'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §14 — RESULTADO DE NAVEGAÇÃO
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§14 resultado distingue commit de convergência', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Convergência falha, mas o END commita.
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    endController = buildEndController();

    HealthRestrictionEndOutcome? outcome;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await Navigator.of(context)
                  .push<HealthRestrictionEndOutcome>(
                    MaterialPageRoute(
                      builder: (_) => HealthRestrictionEndFormScreen(
                        controller: endController,
                        dogId: dogId,
                        dogName: 'Thor',
                        restrictionId: restrictionId,
                        evidencePicker: () async =>
                            const HealthEvidenceFileAccepted(
                              SelectedHealthEvidenceFile(
                                name: 'alta.pdf',
                                path: '/tmp/alta.pdf',
                                sizeBytes: 2048,
                                mimeType: 'application/pdf',
                              ),
                            ),
                      ),
                    ),
                  );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await fillEndForm(tester);
    await tapSubmit(tester);

    // Os dois eixos chegam separados ao host: commitado, não convergido.
    expect(outcome, isNotNull);
    expect(outcome!.mutationCommitted, isTrue);
    expect(
      outcome!.convergenceConfirmed,
      isFalse,
      reason: 'um bool único colapsaria estes dois eixos',
    );
    expect(lifecycle.endCount, 1);
  });

  testWidgets('CANCEL permanece fora de escopo neste gate', (tester) async {
    await pumpDetail(tester);

    expect(find.textContaining('CANCELAR RESTRIÇÃO'), findsNothing);
    expect(lifecycle.cancelCount, 0);
  });
}

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  int endCount = 0;
  int cancelCount = 0;
  HealthRestrictionFlowFailure? failure;

  /// Quando presente, segura o END em voo até ser completado — usado para
  /// provar a proteção contra duplo submit.
  Completer<void>? gate;

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    final f = failure;
    if (f != null) return HealthRestrictionTerminalError(f);
    return HealthRestrictionTerminalSuccess(
      HealthRestrictionTerminalResult(
        dogId: command.dogId,
        restrictionId: command.restrictionId,
        status: HealthRestrictionTerminalStatus.ended,
        wasNoOp: false,
      ),
    );
  }

  @override
  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  ) async {
    cancelCount += 1;
    throw StateError('CANCEL está fora do escopo do B4-C.3');
  }
}

final class _FakeDocumentGateway implements HealthDocumentGateway {
  int prepareCount = 0;
  int finalizeCount = 0;

  @override
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  ) async {
    prepareCount += 1;
    return PrepareHealthDocumentSuccess(
      PreparedHealthDocumentUpload(
        dogId: command.dogId,
        documentId: 'hd_end',
        uploadPath: 'health_document_uploads/dog-1/hd_end',
        maxBytes: 20 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<FinalizeHealthDocumentResult> finalizeUpload(
    FinalizeHealthDocumentCommand command,
  ) async {
    finalizeCount += 1;
    return FinalizeHealthDocumentSuccess(
      FinalizedHealthDocument(
        dogId: command.dogId,
        documentId: 'hd_end',
        reference: const HealthDocumentRef(healthDocumentId: 'hd_end'),
        wasNoOp: false,
      ),
    );
  }
}

final class _FakeUploader implements HealthEvidenceUploader {
  int count = 0;

  @override
  Future<void> upload({
    required SelectedHealthEvidenceFile file,
    required String uploadPath,
  }) async {
    count += 1;
  }
}

final class _RefreshStub {
  int refreshCount = 0;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    refreshCount += 1;
    return {
      'ok': true,
      'result': {
        'dogId': payload['dogId'],
        'projectionStatus': 'ready',
        'readinessStatus': 'operational',
        'readinessLabel': 'Apto',
        'readinessReasonCode': 'none',
        'technicalBlockers': <String>[],
        'operation': 'ready',
        'convergence': {
          'status': 'confirmed',
          'requiredGeneration': 42,
          'observedGeneration': 42,
        },
      },
    };
  }
}
