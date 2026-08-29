import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_readiness_convergence.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_form_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart';

/// B4-C.5 — reconciliação causal do ISSUE.
///
/// ```text
/// 1. ISSUE não commitou      → erro de cadastro
/// 2. ISSUE + convergiu       → registrada + prontidão sincronizada
/// 3. ISSUE + NÃO convergiu   → registrada ✅ + prontidão pendente ⚠️
///                              → retry só da prontidão
///                              → ISSUE/documentos count == 1
/// 4. ISSUE + contrato causal ausente → registrada ✅, sem replay
/// ```
///
/// A verdade da mutation e a convergência da Prontidão são fatos distintos.
const _dogId = 'dog-1';
const _restrictionId = 'or_new_123';

const _validFile = SelectedHealthEvidenceFile(
  name: 'laudo.pdf',
  path: '/tmp/laudo.pdf',
  sizeBytes: 4096,
  mimeType: 'application/pdf',
);

/// Wire causal confirmado: generation observada >= requerida.
Map<String, Object?> _convergenceConfirmed({int required = 42}) =>
    <String, Object?>{
      'status': 'confirmed',
      'requiredGeneration': required,
      'observedGeneration': required,
    };

void main() {
  late _FakeDocumentGateway doc;
  late _FakeUploader uploader;
  late _FakeIssueGateway issue;
  late _RefreshSpy refresh;
  late FakeFirebaseFirestore firestore;
  late HealthRestrictionIssueController controller;

  setUp(() {
    doc = _FakeDocumentGateway();
    uploader = _FakeUploader();
    issue = _FakeIssueGateway();
    refresh = _RefreshSpy();
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedSummary({int? generation}) async {
    await firestore
        .collection('dogs')
        .doc(_dogId)
        .collection('health_summary')
        .doc('current')
        .set(<String, Object?>{
          'projection_status': 'ready',
          'schema_version': 1,
          ...generation == null
              ? const <String, Object?>{}
              : <String, Object?>{'projection_generation': generation},
        });
  }

  void buildController() {
    var seq = 0;
    controller = HealthRestrictionIssueController(
      documentGateway: doc,
      uploader: uploader,
      restrictionGateway: issue,
      convergenceGateway: HealthReadinessConvergenceGateway(
        invoke: refresh.call,
        firestore: firestore,
      ),
      operationIdFactory: () => 'op-${++seq}',
    );
  }

  /// Monta a tela e captura o resultado tipado da navegação.
  Future<List<HealthRestrictionIssueOutcome?>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    buildController();
    addTearDown(controller.dispose);

    final popped = <HealthRestrictionIssueOutcome?>[];
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const SizedBox.shrink()),
    );
    navKey.currentState!
        .push<HealthRestrictionIssueOutcome>(
          MaterialPageRoute<HealthRestrictionIssueOutcome>(
            builder: (_) => HealthRestrictionFormScreen(
              dogId: _dogId,
              dogName: 'Bono',
              controller: controller,
              evidencePicker: () async =>
                  const HealthEvidenceFileAccepted(_validFile),
            ),
          ),
        )
        .then(popped.add);
    await tester.pumpAndSettle();
    return popped;
  }

  /// Preenche tudo o que é obrigatório, deixando a tela válida.
  ///
  /// Selecionadores por `Key`, iguais aos do suite de emissão já homologado:
  /// `find.text('ABSOLUTA')`/`find.text('Lesão')` não casam com os chips reais.
  Future<void> fillValid(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('restriction_level_absolute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restriction_category_injury')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('restriction_description')),
      'Lesão em membro anterior',
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('restriction_professional_name')),
      'Dra. Ana Souza',
    );
    await tester.pumpAndSettle();
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

    final pick = find.byKey(const Key('restriction_pick_file'));
    await tester.ensureVisible(pick);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();

    final nature = find.byKey(const Key('restriction_nature_certificate'));
    await tester.ensureVisible(nature);
    await tester.pumpAndSettle();
    await tester.tap(nature);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final cta = find.text('REGISTRAR RESTRIÇÃO');
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();
  }

  final pendingPanel = find.byKey(
    const Key('restriction_issue_convergence_pending'),
  );
  final retryCta = find.byKey(
    const Key('restriction_issue_retry_convergence'),
  );
  final finishCta = find.byKey(const Key('restriction_issue_finish'));

  // ───────────────────────────────────────────────────────────────────────────
  // §43 — ISSUE NÃO COMMITOU
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§43 pré-commit falho: nenhum sucesso, nenhuma convergência', (
    tester,
  ) async {
    issue.failure = const HealthRestrictionFlowIntegrity(
      HealthRestrictionFlowStep.restrictionIssue,
    );
    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(issue.count, 1);
    expect(controller.convergence.mutationCommitted, isFalse);
    expect(refresh.count, 0, reason: 'sem mutation não há barreira causal');
    expect(popped, isEmpty, reason: 'falha mantém o formulário');
    // Nenhum painel pós-commit: a restrição NÃO existe.
    expect(pendingPanel, findsNothing);
    expect(find.textContaining('Restrição registrada'), findsNothing);
    // O formulário continua disponível para correção.
    expect(find.text('REGISTRAR RESTRIÇÃO'), findsOneWidget);
  });

  testWidgets('§53 permission-denied antes do commit', (tester) async {
    issue.failure = const HealthRestrictionFlowPermissionDenied(
      HealthRestrictionFlowStep.restrictionIssue,
    );
    await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(controller.convergence.mutationCommitted, isFalse);
    expect(refresh.count, 0);
    expect(pendingPanel, findsNothing);
    expect(
      controller.failure?.code,
      HealthRestrictionFlowErrorCode.permissionDenied,
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §44 — COMMITTED + CONVERGED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§44 ISSUE commitou e convergiu: registrada e sincronizada', (
    tester,
  ) async {
    refresh.convergence = _convergenceConfirmed();
    await seedSummary(generation: 42);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
    expect(issue.count, 1);
    expect(controller.convergence.mutationCommitted, isTrue);
    expect(controller.convergence.isConverged, isTrue);

    // Convergiu: conclui imediatamente com os dois eixos verdadeiros.
    expect(popped.length, 1);
    expect(popped.single!.mutationCommitted, isTrue);
    expect(popped.single!.convergenceConfirmed, isTrue);
    expect(popped.single!.restrictionId, _restrictionId);
    // Sem painel de pendência.
    expect(pendingPanel, findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §45 — COMMITTED + CONVERGENCE FAILED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§45 ISSUE commitou e NÃO convergiu: registrada + pendente', (
    tester,
  ) async {
    // Generation observada anterior à requerida: não há prova causal.
    refresh.convergence = _convergenceConfirmed(required: 42);
    await seedSummary(generation: 41);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    // A RESTRIÇÃO EXISTE.
    expect(issue.count, 1);
    expect(controller.convergence.mutationCommitted, isTrue);
    expect(controller.convergence.isConverged, isFalse);
    expect(controller.convergence.needsConvergenceRetry, isTrue);
    expect(controller.restrictionId, _restrictionId);

    // A tela permanece viva — é o que preserva o retryConvergence().
    expect(popped, isEmpty, reason: 'não popa com convergência pendente');
    expect(pendingPanel, findsOneWidget);
    expect(find.text('Restrição registrada.'), findsOneWidget);
    expect(
      find.textContaining('prontidão ainda não foi confirmada'),
      findsOneWidget,
    );
    expect(retryCta, findsOneWidget);

    // Negativas obrigatórias.
    expect(find.textContaining('Falha ao registrar'), findsNothing);
    expect(find.textContaining('Restrição não registrada'), findsNothing);
    expect(find.textContaining('Tente registrar novamente'), findsNothing);
    // E o formulário não pode reaparecer: reenviar criaria OUTRA restrição.
    expect(find.text('REGISTRAR RESTRIÇÃO'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §46 — CONTRATO CAUSAL AUSENTE (rollout backend-first)
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§46 contrato causal ausente: registrada, sem replay', (
    tester,
  ) async {
    // Backend antigo: response sem o objeto `convergence`.
    refresh.convergence = null;
    await seedSummary(generation: 42);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    // Ausência do contrato causal NÃO é ausência da mutation.
    expect(controller.convergence.mutationCommitted, isTrue);
    expect(controller.convergence.isConverged, isFalse);
    expect(
      controller.convergence.result?.outcome,
      HealthReadinessConvergenceOutcome.contractUnavailable,
    );

    // Writer e pipeline documental executados exatamente uma vez.
    expect(issue.count, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);

    // Aviso causal controlado, sem sugerir novo cadastro.
    expect(popped, isEmpty);
    expect(pendingPanel, findsOneWidget);
    expect(find.text('Restrição registrada.'), findsOneWidget);
    expect(find.textContaining('Falha ao registrar'), findsNothing);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §47/§48 — RETRY CAUSAL
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§47 retry causal converge sem repetir writer nem documento', (
    tester,
  ) async {
    refresh.convergence = _convergenceConfirmed(required: 42);
    await seedSummary(generation: 41);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(refresh.count, 1);
    expect(pendingPanel, findsOneWidget);

    // Servidor agora consegue projetar.
    await seedSummary(generation: 42);
    await tester.tap(retryCta);
    await tester.pumpAndSettle();

    expect(controller.convergence.isConverged, isTrue);
    // NADA foi repetido.
    expect(issue.count, 1, reason: 'retry causal jamais reenvia ISSUE');
    expect(doc.prepareCount, 1, reason: 'PREPARE jamais refeito');
    expect(uploader.count, 1, reason: 'upload jamais refeito');
    expect(doc.finalizeCount, 1, reason: 'FINALIZE jamais refeito');
    expect(refresh.count, 2, reason: 'apenas o refresh repetiu');

    // Convergiu no retry: conclui com os dois eixos verdadeiros.
    expect(popped.length, 1);
    expect(popped.single!.mutationCommitted, isTrue);
    expect(popped.single!.convergenceConfirmed, isTrue);
    expect(popped.single!.restrictionId, _restrictionId);
  });

  testWidgets('§48 segunda falha de retry preserva a verdade da mutation', (
    tester,
  ) async {
    refresh.convergence = _convergenceConfirmed(required: 42);
    await seedSummary(generation: 41);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);
    expect(refresh.count, 1);

    // Retry explícito falha de novo (generation continua atrasada).
    await tester.tap(retryCta);
    await tester.pumpAndSettle();

    expect(controller.convergence.mutationCommitted, isTrue);
    expect(controller.convergence.isConverged, isFalse);
    expect(issue.count, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
    expect(refresh.count, 2, reason: 'nenhuma terceira tentativa automática');

    // Sem loop automático: frames extras não disparam refresh.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(refresh.count, 2);

    // Continua vivo, com retry explícito disponível.
    expect(popped, isEmpty);
    expect(pendingPanel, findsOneWidget);
    expect(retryCta, findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §49 — DOUBLE SUBMIT
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§49 duplo submit não inicia segundo pipeline', (tester) async {
    refresh.convergence = _convergenceConfirmed();
    await seedSummary(generation: 42);
    final gate = Completer<void>();
    issue.gate = gate;

    await pump(tester);
    await fillValid(tester);

    final cta = find.text('REGISTRAR RESTRIÇÃO');
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pump();

    expect(issue.count, 1);

    // Segunda tentativa com o ISSUE em voo.
    final submitting = find.text('REGISTRANDO...');
    expect(submitting, findsOneWidget);
    await tester.tap(submitting, warnIfMissed: false);
    await tester.pump();

    expect(issue.count, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);

    gate.complete();
    await tester.pumpAndSettle();

    expect(issue.count, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
    expect(refresh.count, 1, reason: 'uma única convergência');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §54 — SAIR APÓS COMMIT COM CONVERGÊNCIA PENDENTE
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§54 concluir com pendência preserva a verdade da mutation', (
    tester,
  ) async {
    refresh.convergence = _convergenceConfirmed(required: 42);
    await seedSummary(generation: 41);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(pendingPanel, findsOneWidget);

    // O operador conclui aceitando a pendência.
    await tester.tap(finishCta);
    await tester.pumpAndSettle();

    expect(popped.length, 1);
    expect(
      popped.single!.mutationCommitted,
      isTrue,
      reason: 'sair jamais apaga a mutation',
    );
    expect(popped.single!.convergenceConfirmed, isFalse);
    expect(popped.single!.restrictionId, _restrictionId);

    // Nenhum writer repetido pela saída.
    expect(issue.count, 1);
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
  });

  testWidgets('§54 back do sistema após commit também preserva a verdade', (
    tester,
  ) async {
    refresh.convergence = _convergenceConfirmed(required: 42);
    await seedSummary(generation: 41);

    final popped = await pump(tester);
    await fillValid(tester);
    await submit(tester);

    expect(pendingPanel, findsOneWidget);

    // Gesto de voltar do sistema, via botão do scaffold.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(popped.length, 1);
    expect(popped.single!.mutationCommitted, isTrue);
    expect(popped.single!.convergenceConfirmed, isFalse);
    expect(issue.count, 1);
  });
}

final class _FakeIssueGateway implements HealthRestrictionIssueGateway {
  int count = 0;
  HealthRestrictionFlowFailure? failure;
  Completer<void>? gate;
  final commands = <IssueOperationalRestrictionCommand>[];

  @override
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  ) async {
    count += 1;
    commands.add(command);
    final pending = gate;
    if (pending != null) await pending.future;
    final f = failure;
    if (f != null) return IssueOperationalRestrictionError(f);
    return const IssueOperationalRestrictionSuccess(
      IssuedOperationalRestriction(
        dogId: _dogId,
        restrictionId: _restrictionId,
        wasNoOp: false,
      ),
    );
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
        documentId: 'hd_abc',
        uploadPath: 'health_document_uploads/dog-1/hd_abc',
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
        documentId: 'hd_abc',
        reference: const HealthDocumentRef(healthDocumentId: 'hd_abc'),
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

/// Espia o refresh causal e permite omitir o contrato (backend antigo).
final class _RefreshSpy {
  int count = 0;
  Map<String, Object?>? convergence;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    count += 1;
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
        if (convergence != null) 'convergence': convergence,
      },
    };
  }
}
