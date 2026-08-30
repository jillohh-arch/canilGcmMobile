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
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_cancel_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_end_controller.dart';

/// B4-C.4 — invalidação administrativa (CANCEL) + UX causal.
///
/// ```text
/// CANCEL não commitou    → ATIVA               → erro de invalidação
/// CANCEL + convergiu     → CANCELADA           → prontidão confirmada
/// CANCEL + NÃO convergiu → CANCELADA           → não confirmada
///                                              → retry causal
///                                              → CANCEL count == 1
/// ```
///
/// CANCEL é invalidação de registro, NUNCA liberação clínica.
const _dogId = 'dog-1';
const _restrictionId = 'or_abc123';

RecordedBy _actor([String name = 'Cb. Silva']) =>
    RecordedBy(uid: 'uid-1', name: name, internalRole: 'condutor');

ProfessionalIdentity _professional() => ProfessionalIdentity(
  name: 'Dra. Ana Souza',
  registrationType: ProfessionalRegistrationType.crmv,
  registrationNumber: 'SP-12345',
  clinic: 'Clínica Central',
);

/// Exclusividade terminal do aggregate: `cancelled` exige os três campos de
/// cancelamento e nenhum metadata de encerramento.
OperationalRestriction _restrictionWith(
  RestrictionStatus status, {
  String cancelReason = 'Registro aberto por engano',
  String cancelledByName = 'Ten. Rocha',
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
    endedBy: ended ? _actor('Sgt. Costa') : null,
    endReason: ended ? 'Alta clínica confirmada' : null,
    endProfessional: ended ? _professional() : null,
    endSourceDocument: ended
        ? const HealthDocumentRef(healthDocumentId: 'hd_end')
        : null,
    cancelledAt: cancelled ? DateTime.utc(2026, 8, 5, 8) : null,
    cancelledBy: cancelled ? _actor(cancelledByName) : null,
    cancelReason: cancelled ? cancelReason : null,
  );
}

final class _ReadGateway implements HealthRestrictionReadGateway {
  int calls = 0;
  RestrictionStatus status = RestrictionStatus.active;

  /// Permite a releitura canônica devolver aggregate diferente do submetido.
  OperationalRestriction Function(int call)? canonicalOverride;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async {
    calls += 1;
    final builder = canonicalOverride;
    if (builder != null) return HealthRestrictionReadSuccess(builder(calls));
    return HealthRestrictionReadSuccess(_restrictionWith(status));
  }
}

void main() {
  const dogId = _dogId;
  const restrictionId = _restrictionId;

  late _ReadGateway readGateway;
  late _FakeLifecycleGateway lifecycle;
  late _RefreshStub refresh;
  late FakeFirebaseFirestore firestore;
  late _SpyDocumentGateway doc;
  late _SpyUploader uploader;

  setUp(() {
    readGateway = _ReadGateway();
    lifecycle = _FakeLifecycleGateway();
    refresh = _RefreshStub();
    firestore = FakeFirebaseFirestore();
    doc = _SpyDocumentGateway();
    uploader = _SpyUploader();
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

  late HealthRestrictionCancelController cancelController;
  late HealthRestrictionEndController endController;

  Future<void> pumpDetail(
    WidgetTester tester, {
    bool withCancel = true,
    bool withEnd = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final detail = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: readGateway,
    );
    addTearDown(detail.dispose);

    cancelController = HealthRestrictionCancelController(
      gateway: lifecycle,
      convergenceGateway: HealthReadinessConvergenceGateway(
        invoke: refresh.call,
        firestore: firestore,
      ),
      operationIdFactory: () => 'cancel-op',
    );
    // Seams documentais ligados ao END apenas para provar que o CANCEL nunca os
    // toca. Se o CANCEL tocasse o pipeline documental, estes contadores subiriam.
    endController = HealthRestrictionEndController(
      documentGateway: doc,
      uploader: uploader,
      lifecycleGateway: lifecycle,
      convergenceGateway: HealthReadinessConvergenceGateway(
        invoke: refresh.call,
        firestore: firestore,
      ),
      operationIdFactory: () => 'end-op',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HealthRestrictionDetailScreen(
          controller: detail,
          dogName: 'Thor',
          endControllerFactory: withEnd ? () => endController : null,
          cancelControllerFactory: withCancel ? () => cancelController : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCancelSheet(WidgetTester tester) async {
    final cta = find.byKey(const Key('restriction_open_cancel_sheet'));
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();
  }

  Future<void> submitCancel(
    WidgetTester tester, {
    String reason = 'Registro aberto por engano',
    bool typeReason = true,
  }) async {
    await openCancelSheet(tester);
    if (typeReason) {
      await tester.enterText(
        find.byKey(const Key('restriction_cancel_reason')),
        reason,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('restriction_cancel_confirm')));
    await tester.pumpAndSettle();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // §39 — VISIBILIDADE
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§39 ACTIVE oferece END e CANCEL', (tester) async {
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsOneWidget);
    expect(
      find.byKey(const Key('restriction_open_cancel_sheet')),
      findsOneWidget,
    );
  });

  testWidgets('§39 ENDED não oferece END nem CANCEL', (tester) async {
    readGateway.status = RestrictionStatus.ended;
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsNothing);
    expect(find.byKey(const Key('restriction_open_cancel_sheet')), findsNothing);
  });

  testWidgets('§39 CANCELLED não oferece END nem CANCEL', (tester) async {
    readGateway.status = RestrictionStatus.cancelled;
    await pumpDetail(tester);

    expect(find.byKey(const Key('restriction_open_end_form')), findsNothing);
    expect(find.byKey(const Key('restriction_open_cancel_sheet')), findsNothing);
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
  });

  testWidgets('§6 CANCEL semanticamente distinto de liberação clínica', (
    tester,
  ) async {
    await pumpDetail(tester);

    // A ação nunca se apresenta como liberação/encerramento.
    expect(find.text('Invalidar registro'), findsOneWidget);
    expect(find.textContaining('Não é liberação clínica'), findsOneWidget);
    expect(find.textContaining('Liberar cão'), findsNothing);
    expect(find.textContaining('Remover restrição'), findsNothing);

    // Dentro da sheet a distinção é reafirmada e aponta o caminho clínico.
    // Texto exato: `textContaining('lançado')` casaria também com o subtítulo da
    // ação no detalhe e com o hint do campo, virando asserção ambígua.
    await openCancelSheet(tester);
    expect(
      find.text(
        'Use quando o registro de restrição tiver sido lançado '
        'indevidamente. Não é liberação clínica: para alta clínica, '
        'utilize Encerrar restrição.',
      ),
      findsOneWidget,
    );
    expect(find.text('INVALIDAR REGISTRO'), findsOneWidget);
    // O título da sheet reafirma invalidação, nunca encerramento.
    expect(find.text('Invalidar registro'), findsWidgets);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §40 — VALIDAÇÃO DO MOTIVO
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§40 motivo vazio não alcança o CANCEL writer', (tester) async {
    await pumpDetail(tester);
    await submitCancel(tester, typeReason: false);

    expect(lifecycle.cancelCount, 0);
    expect(refresh.refreshCount, 0);
    expect(find.textContaining('Informe o motivo'), findsOneWidget);
  });

  testWidgets('§40 motivo só com espaços não alcança o CANCEL writer', (
    tester,
  ) async {
    await pumpDetail(tester);
    await submitCancel(tester, reason: '     ');

    expect(lifecycle.cancelCount, 0);
    expect(refresh.refreshCount, 0);
    expect(find.textContaining('Informe o motivo'), findsOneWidget);
  });

  testWidgets('§40 desistir da sheet não é mutation nem erro', (tester) async {
    await pumpDetail(tester);
    await openCancelSheet(tester);
    await tester.tap(find.byKey(const Key('restriction_cancel_dismiss')));
    await tester.pumpAndSettle();

    expect(lifecycle.cancelCount, 0);
    expect(refresh.refreshCount, 0);
    expect(find.textContaining('Não foi possível'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §41 — COMMITTED + CONVERGED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§41 CANCEL commitou e convergiu: CANCELADA, confirmada, reload', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);
    final readsBefore = readGateway.calls;
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);

    expect(lifecycle.cancelCount, 1);
    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(cancelController.convergence.isConverged, isTrue);
    expect(refresh.refreshCount, 1);
    // Reload canônico da MESMA identidade.
    expect(readGateway.calls, readsBefore + 1);
    expect(lifecycle.lastCancelDogId, dogId);
    expect(lifecycle.lastCancelRestrictionId, restrictionId);
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    // Sem banner de pendência.
    expect(
      find.byKey(const Key('restriction_convergence_pending')),
      findsNothing,
    );
    // Zero pipeline documental.
    expect(doc.prepareCount, 0);
    expect(doc.finalizeCount, 0);
    expect(uploader.count, 0);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §42 — COMMITTED + CONVERGENCE FAILED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§42 CANCEL commitou e NÃO convergiu: CANCELADA + pendência', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    final readsBefore = readGateway.calls;
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);

    // O comando É fato canônico.
    expect(lifecycle.cancelCount, 1);
    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(cancelController.convergence.isConverged, isFalse);
    expect(cancelController.convergence.needsConvergenceRetry, isTrue);
    // Reload aconteceu mesmo sem convergência.
    expect(readGateway.calls, readsBefore + 1);
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);

    // Banner com linguagem de invalidação aplicada — nunca de falha.
    //
    // Escopado ao banner: a mesma frase também aparece no SnackBar de feedback,
    // então um `textContaining` global casaria duas vezes e a asserção deixaria
    // de provar que é O BANNER que carrega a copy correta.
    final banner = find.byKey(const Key('restriction_convergence_pending'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: banner,
        matching: find.text(
          'Registro invalidado. Prontidão ainda não sincronizada.',
        ),
      ),
      findsOneWidget,
    );
    // E nunca a copy do END.
    expect(find.textContaining('Encerramento aplicado'), findsNothing);

    // Negativas obrigatórias.
    expect(find.textContaining('Falha ao cancelar'), findsNothing);
    expect(find.textContaining('não foi invalidado'), findsNothing);
    expect(find.text('ATIVA'), findsNothing);
    expect(find.textContaining('liberação clínica confirmada'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §43 — RETRY
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§43 retry causal converge sem repetir CANCEL', (tester) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);
    expect(refresh.refreshCount, 1);

    await seedSummary(projectionStatus: 'ready', generation: 42);
    await tester.tap(find.byKey(const Key('restriction_retry_convergence')));
    await tester.pumpAndSettle();

    expect(cancelController.convergence.isConverged, isTrue);
    expect(
      lifecycle.cancelCount,
      1,
      reason: 'retry causal jamais reenvia CANCEL',
    );
    expect(refresh.refreshCount, 2, reason: 'apenas o refresh repetiu');
    // Pipeline documental jamais existiu neste fluxo.
    expect(doc.prepareCount, 0);
    expect(doc.finalizeCount, 0);
    expect(uploader.count, 0);
    expect(cancelController.result, isNotNull);
  });

  testWidgets('§43 segunda falha de retry preserva mutationCommitted', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);
    expect(refresh.refreshCount, 1);

    // Retry explícito, projeção continua indisponível.
    await tester.tap(find.byKey(const Key('restriction_retry_convergence')));
    await tester.pumpAndSettle();

    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(cancelController.convergence.isConverged, isFalse);
    expect(cancelController.convergence.needsConvergenceRetry, isTrue);
    expect(lifecycle.cancelCount, 1);
    expect(
      refresh.refreshCount,
      2,
      reason: 'nenhuma terceira tentativa automática',
    );
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    expect(
      find.byKey(const Key('restriction_retry_convergence')),
      findsOneWidget,
    );
    expect(find.textContaining('Falha ao cancelar'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §44 — AUTORIDADE CANÔNICA X vs Y
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§44 canônico Y sobrepõe o motivo X da sheet', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.canonicalOverride = (_) => _restrictionWith(
      RestrictionStatus.cancelled,
      cancelReason: 'Duplicidade confirmada pela chefia administrativa',
      cancelledByName: 'Maj. Pereira',
    );

    // X = 'Registro aberto por engano'
    await submitCancel(tester, reason: 'Registro aberto por engano');

    expect(lifecycle.cancelCount, 1);
    // Y é autoridade de exibição.
    expect(
      find.text('Duplicidade confirmada pela chefia administrativa'),
      findsOneWidget,
    );
    expect(find.text('Maj. Pereira'), findsOneWidget);
    // X não sobrevive.
    expect(
      find.text('Registro aberto por engano'),
      findsNothing,
      reason: 'input da sheet jamais é autoridade terminal',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §45 — PERMISSION DENIED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§45 permission-denied: ATIVA, sem convergência, sem sucesso', (
    tester,
  ) async {
    lifecycle.failure = const HealthRestrictionFlowPermissionDenied(
      HealthRestrictionFlowStep.restrictionCancel,
    );
    await pumpDetail(tester);
    final readsBefore = readGateway.calls;

    await submitCancel(tester);

    expect(lifecycle.cancelCount, 1);
    expect(cancelController.convergence.mutationCommitted, isFalse);
    expect(refresh.refreshCount, 0);
    // Nenhum reload: o canônico não mudou.
    expect(readGateway.calls, readsBefore);
    expect(
      cancelController.failure?.code,
      HealthRestrictionFlowErrorCode.permissionDenied,
    );
    expect(find.text('ATIVA'), findsOneWidget);
    expect(find.textContaining('Registro invalidado'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §46 — TERMINAL CONFLICT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§46 conflito terminal: sem sucesso, sem replay, sem convergência', (
    tester,
  ) async {
    lifecycle.failure = const HealthRestrictionFlowConflict(
      HealthRestrictionFlowStep.restrictionCancel,
      'Restrição já encerrada.',
    );
    await pumpDetail(tester);

    await submitCancel(tester);

    expect(lifecycle.cancelCount, 1, reason: 'nenhum replay automático');
    expect(cancelController.convergence.mutationCommitted, isFalse);
    // Convergência jamais usada como recuperação de conflito.
    expect(refresh.refreshCount, 0);
    expect(cancelController.failure, isNotNull);
    expect(find.textContaining('Registro invalidado'), findsNothing);
  });

  testWidgets('§46 canônico ENDED é exibido como ENCERRADA', (tester) async {
    // Estado terminal factual divergente do que o operador tentou.
    readGateway.status = RestrictionStatus.ended;
    await pumpDetail(tester);

    expect(find.text('ENCERRADA'), findsOneWidget);
    // Terminal não oferece CANCEL, então o writer nunca é alcançado.
    expect(find.byKey(const Key('restriction_open_cancel_sheet')), findsNothing);
    expect(lifecycle.cancelCount, 0);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §29 — DOUBLE SUBMIT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§29 duplo submit não executa segunda mutation', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    final gate = Completer<void>();
    lifecycle.gate = gate;

    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await openCancelSheet(tester);
    await tester.enterText(
      find.byKey(const Key('restriction_cancel_reason')),
      'Registro aberto por engano',
    );
    await tester.pumpAndSettle();

    // Primeira confirmação: a sheet fecha e o CANCEL fica preso no gate.
    //
    // `pumpAndSettle` é obrigatório aqui: a sheet sai por animação, e com um
    // único `pump` o campo de motivo ainda está na árvore durante a transição —
    // a asserção de reentrada abaixo mediria a PRIMEIRA sheet saindo, não uma
    // segunda abrindo. O gate pendente não bloqueia frames.
    await tester.tap(find.byKey(const Key('restriction_cancel_confirm')));
    await tester.pumpAndSettle();

    expect(lifecycle.cancelCount, 1);
    expect(cancelController.isSubmitting, isTrue);
    expect(
      find.byKey(const Key('restriction_cancel_reason')),
      findsNothing,
      reason: 'a primeira sheet já saiu antes da asserção de reentrada',
    );

    // Segunda tentativa enquanto o comando está em voo.
    //
    // Desde o B4-C.4.R a garantia é mais forte que "reentrada bloqueada": a
    // própria ação DESAPARECE enquanto uma mutation terminal está em voo
    // (`_canOfferTerminalActions`), então não existe superfície para um segundo
    // submit. O guard de `isSubmitting` no host permanece como defesa em
    // profundidade para o caso de a ação ser alcançada por outra rota.
    final cta = find.byKey(const Key('restriction_open_cancel_sheet'));
    expect(
      cta,
      findsNothing,
      reason: 'ação terminal indisponível enquanto o CANCEL está em voo',
    );
    expect(
      find.byKey(const Key('restriction_cancel_reason')),
      findsNothing,
      reason: 'nenhuma segunda sheet pode ser aberta',
    );

    // O guard do host impede a segunda mutation, e nenhum erro espúrio de
    // "não foi possível invalidar" é apresentado.
    expect(lifecycle.cancelCount, 1);
    expect(find.textContaining('Não foi possível invalidar'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(lifecycle.cancelCount, 1);
    expect(refresh.refreshCount, 1);
    expect(cancelController.convergence.mutationCommitted, isTrue);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §47 — BACK / POP APÓS COMMIT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§47 sair após commit sem convergência preserva a verdade', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);

    // A sheet já fechou; o host é o detalhe.
    expect(find.byKey(const Key('restriction_cancel_reason')), findsNothing);

    // Verdade da mutation preservada no controller hospedado.
    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(cancelController.result, isNotNull);
    expect(lifecycle.cancelCount, 1);
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);

    // Sem rollback wording e sem aprisionar o operador.
    expect(find.textContaining('revertid'), findsNothing);
    expect(find.textContaining('Falha ao cancelar'), findsNothing);
    expect(
      find.byKey(const Key('restriction_retry_convergence')),
      findsOneWidget,
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §33 — ZERO CROSS-RETRY entre END e CANCEL
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§33 retry do CANCEL nunca toca o controller de END', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);
    await tester.tap(find.byKey(const Key('restriction_retry_convergence')));
    await tester.pumpAndSettle();

    // O END jamais foi commitado nem convergido nesta sessão.
    expect(lifecycle.endCount, 0);
    expect(endController.convergence.mutationCommitted, isFalse);
    expect(endController.result, isNull);
    // E nenhum pipeline documental foi tocado.
    expect(doc.prepareCount, 0);
    expect(doc.finalizeCount, 0);
    expect(uploader.count, 0);
    // Apenas o CANCEL avançou.
    expect(lifecycle.cancelCount, 1);
    expect(cancelController.convergence.mutationCommitted, isTrue);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §12/§13 — ZERO DOCUMENTO, ZERO PROFISSIONAL
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§13 a sheet não pede profissional nem documento', (tester) async {
    await pumpDetail(tester);
    await openCancelSheet(tester);

    expect(
      find.byKey(const Key('restriction_professional_name')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('restriction_registration_CRMV')),
      findsNothing,
    );
    expect(find.byKey(const Key('restriction_end_pick_file')), findsNothing);
    expect(find.textContaining('Anexe'), findsNothing);
    expect(find.textContaining('Atestado'), findsNothing);
    expect(find.textContaining('Natureza do documento'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §38 — REGRESSÃO B4-C.3: END permanece disponível e distinto
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§38 sem factory de CANCEL o detalhe segue funcional', (
    tester,
  ) async {
    await pumpDetail(tester, withCancel: false);

    expect(find.byKey(const Key('restriction_open_end_form')), findsOneWidget);
    expect(find.byKey(const Key('restriction_open_cancel_sheet')), findsNothing);
  });
}

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  int endCount = 0;
  int cancelCount = 0;
  HealthRestrictionFlowFailure? failure;
  Completer<void>? gate;

  String? lastCancelDogId;
  String? lastCancelRestrictionId;
  String? lastCancelReason;

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
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
    lastCancelDogId = command.dogId;
    lastCancelRestrictionId = command.restrictionId;
    lastCancelReason = command.cancelReason;
    final pending = gate;
    if (pending != null) await pending.future;
    final f = failure;
    if (f != null) return HealthRestrictionTerminalError(f);
    return HealthRestrictionTerminalSuccess(
      HealthRestrictionTerminalResult(
        dogId: command.dogId,
        restrictionId: command.restrictionId,
        status: HealthRestrictionTerminalStatus.cancelled,
        wasNoOp: false,
      ),
    );
  }
}

/// Espião: qualquer chamada aqui durante um CANCEL é falha arquitetural.
final class _SpyDocumentGateway implements HealthDocumentGateway {
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
        documentId: 'hd_x',
        uploadPath: 'health_document_uploads/dog-1/hd_x',
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
        documentId: 'hd_x',
        reference: const HealthDocumentRef(healthDocumentId: 'hd_x'),
        wasNoOp: false,
      ),
    );
  }
}

final class _SpyUploader implements HealthEvidenceUploader {
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
