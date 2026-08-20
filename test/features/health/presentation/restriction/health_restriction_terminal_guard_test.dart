import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
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

/// B4-C.4.R — guarda de commit terminal + falha de reload canônico.
///
/// Dois invariantes do lifecycle-host, agora que o detalhe hospeda DOIS
/// controllers terminais:
///
/// ```text
/// A. mutation terminal commitada ⇒ ações ACTIVE nunca reaparecem,
///    mesmo se o reload canônico falhar.
///
/// B. END e CANCEL nunca executam simultaneamente.
/// ```
///
/// O backend rejeitaria a segunda operação por conflito, mas conflito de
/// backend NÃO é o mecanismo primário de proteção da UX.
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

OperationalRestriction _restrictionWith(RestrictionStatus status) {
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
    cancelledBy: cancelled ? _actor('Ten. Rocha') : null,
    cancelReason: cancelled ? 'Registro aberto por engano' : null,
  );
}

/// Read gateway com falha programável por chamada.
final class _ReadGateway implements HealthRestrictionReadGateway {
  int calls = 0;
  RestrictionStatus status = RestrictionStatus.active;

  /// Número de leituras que devem falhar, a partir da próxima.
  int failNext = 0;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async {
    calls += 1;
    if (failNext > 0) {
      failNext -= 1;
      return const HealthRestrictionReadError(
        HealthRestrictionReadFailure(
          code: HealthRestrictionReadErrorCode.unavailable,
          message: 'Sem conexão.',
        ),
      );
    }
    return HealthRestrictionReadSuccess(_restrictionWith(status));
  }
}

void main() {
  const dogId = _dogId;
  const restrictionId = _restrictionId;

  late _ReadGateway readGateway;
  late _FakeLifecycleGateway lifecycle;
  late _FakeDocumentGateway doc;
  late _FakeUploader uploader;
  late _RefreshStub refresh;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    readGateway = _ReadGateway();
    lifecycle = _FakeLifecycleGateway();
    doc = _FakeDocumentGateway();
    uploader = _FakeUploader();
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

  late HealthRestrictionCancelController cancelController;
  late HealthRestrictionEndController endController;

  Future<void> pumpDetail(WidgetTester tester) async {
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
          endControllerFactory: () => endController,
          cancelControllerFactory: () => cancelController,
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

  final endCta = find.byKey(const Key('restriction_open_end_form'));
  final cancelCta = find.byKey(const Key('restriction_open_cancel_sheet'));
  final canonicalRetry = find.byKey(const Key('restriction_reload_canonical'));

  Future<void> submitCancel(WidgetTester tester) async {
    await tester.ensureVisible(cancelCta);
    await tester.pumpAndSettle();
    await tester.tap(cancelCta);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_cancel_reason')),
      'Registro aberto por engano',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restriction_cancel_confirm')));
    await tester.pumpAndSettle();
  }

  Future<void> submitEnd(WidgetTester tester) async {
    await tester.ensureVisible(endCta);
    await tester.pumpAndSettle();
    await tester.tap(endCta);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('restriction_end_reason')),
      'Alta clínica confirmada',
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
    await tester.tap(find.byKey(const Key('restriction_end_pick_file')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atestado veterinário'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_end_document_title')),
      'Atestado de alta',
    );
    await tester.pumpAndSettle();

    final submit = find.text('ENCERRAR RESTRIÇÃO');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // §12 — CANCEL COMMITTED + RELOAD FAILED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§12 CANCEL commitado + reload falho: ações não reaparecem', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.cancelled;
    readGateway.failNext = 1; // o reload pós-commit falha

    await submitCancel(tester);

    // A mutation É fato canônico.
    expect(lifecycle.cancelCount, 1);
    expect(cancelController.convergence.mutationCommitted, isTrue);

    // INVARIANTE A: nenhuma ação terminal reaparece.
    expect(endCta, findsNothing, reason: 'END não pode reaparecer');
    expect(cancelCta, findsNothing, reason: 'CANCEL não pode reaparecer');

    // Nenhum metadata terminal fabricado localmente.
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsNothing);
    expect(find.text('Registro aberto por engano'), findsNothing);

    // Estado controlado: diz que invalidou E que os detalhes não atualizaram.
    // Texto exato — `textContaining` minúsculo não casaria com a copy real.
    expect(find.textContaining('Registro invalidado'), findsWidgets);
    expect(
      find.text('Não foi possível atualizar os detalhes da restrição.'),
      findsOneWidget,
    );
    expect(canonicalRetry, findsOneWidget);

    // Retry canônico bem-sucedido: agora o aggregate real aparece.
    await tester.tap(canonicalRetry);
    await tester.pumpAndSettle();

    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    expect(find.text('Registro aberto por engano'), findsOneWidget);
    expect(lifecycle.cancelCount, 1, reason: 'retry canônico não remuta');
    expect(refresh.refreshCount, 1, reason: 'retry canônico não converge');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §13 — END COMMITTED + RELOAD FAILED
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§13 END commitado + reload falho: ações não reaparecem', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.ended;
    readGateway.failNext = 1;

    await submitEnd(tester);

    expect(lifecycle.endCount, 1);
    expect(endController.convergence.mutationCommitted, isTrue);

    // INVARIANTE A.
    expect(endCta, findsNothing);
    expect(cancelCta, findsNothing);

    // Sem metadata terminal fabricado.
    expect(find.text('ENCERRADA'), findsNothing);

    expect(find.textContaining('Encerramento registrado'), findsWidgets);
    expect(canonicalRetry, findsOneWidget);

    await tester.tap(canonicalRetry);
    await tester.pumpAndSettle();

    expect(find.text('ENCERRADA'), findsOneWidget);
    // Pipeline documental intacto.
    expect(doc.prepareCount, 1);
    expect(uploader.count, 1);
    expect(doc.finalizeCount, 1);
    expect(lifecycle.endCount, 1);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §14 — RELOAD FALHA DUAS VEZES
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§14 reload falha duas vezes: sem loop, sem remutação', (
    tester,
  ) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.cancelled;
    readGateway.failNext = 2; // reload pós-commit + primeiro retry

    await submitCancel(tester);

    expect(lifecycle.cancelCount, 1);
    expect(canonicalRetry, findsOneWidget);
    final readsAfterCommit = readGateway.calls;

    // Primeiro retry explícito falha.
    await tester.tap(canonicalRetry);
    await tester.pumpAndSettle();

    expect(readGateway.calls, readsAfterCommit + 1);
    expect(lifecycle.cancelCount, 1, reason: 'nenhuma remutação');
    expect(endCta, findsNothing);
    expect(cancelCta, findsNothing);
    // Retry continua explícito e disponível.
    expect(canonicalRetry, findsOneWidget);

    // Sem loop automático: mais frames não disparam leituras.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      readGateway.calls,
      readsAfterCommit + 1,
      reason: 'nenhuma releitura automática',
    );

    // Segundo retry funciona.
    await tester.tap(canonicalRetry);
    await tester.pumpAndSettle();
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    expect(lifecycle.cancelCount, 1);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §15/§16 — EXCLUSÃO MÚTUA ENTRE TERMINAIS
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§16 CANCEL em voo: END não pode começar', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    final gate = Completer<void>();
    lifecycle.cancelGate = gate;

    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.cancelled;

    await submitCancel(tester);

    // CANCEL preso no gate.
    expect(cancelController.isSubmitting, isTrue);
    expect(lifecycle.cancelCount, 1);

    // INVARIANTE B: END indisponível enquanto o CANCEL está em voo.
    expect(endCta, findsNothing, reason: 'END não pode iniciar durante CANCEL');
    expect(lifecycle.endCount, 0);

    gate.complete();
    await tester.pumpAndSettle();

    expect(lifecycle.endCount, 0);
    expect(lifecycle.cancelCount, 1);
  });

  testWidgets('§15 END em voo: CANCEL não pode começar', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    final gate = Completer<void>();
    lifecycle.endGate = gate;

    await pumpDetail(tester);
    readGateway.status = RestrictionStatus.ended;

    // Submete o END; ele fica preso no gate com o formulário ainda aberto.
    await tester.ensureVisible(endCta);
    await tester.pumpAndSettle();
    await tester.tap(endCta);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_end_reason')),
      'Alta clínica confirmada',
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
    await tester.tap(find.byKey(const Key('restriction_end_pick_file')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atestado veterinário'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_end_document_title')),
      'Atestado de alta',
    );
    await tester.pumpAndSettle();
    final submit = find.text('ENCERRAR RESTRIÇÃO');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();

    // END em voo.
    expect(endController.isSubmitting, isTrue);
    expect(lifecycle.endCount, 1);

    // Volta ao detalhe com o END ainda em voo (gesto de voltar do Android).
    //
    // `tester.pageBack()` não serve aqui: procura o botão de voltar padrão, e o
    // `HealthFormScaffold` usa um `leading` próprio. Fazemos o pop pelo
    // Navigator, que é exatamente o efeito do gesto de sistema.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    // INVARIANTE B: CANCEL indisponível enquanto o END está em voo.
    expect(
      cancelCta,
      findsNothing,
      reason: 'CANCEL não pode iniciar durante END',
    );
    expect(lifecycle.cancelCount, 0);

    gate.complete();
    await tester.pumpAndSettle();

    expect(lifecycle.cancelCount, 0);
    expect(lifecycle.endCount, 1);
  });

  testWidgets('§9 END commitado: CANCEL nunca inicia', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.ended;
    readGateway.failNext = 1; // força o pior caso: reload falho

    await submitEnd(tester);

    expect(endController.convergence.mutationCommitted, isTrue);
    expect(cancelCta, findsNothing);
    expect(lifecycle.cancelCount, 0);
  });

  testWidgets('§9 CANCEL commitado: END nunca inicia', (tester) async {
    await seedSummary(projectionStatus: 'ready', generation: 42);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.cancelled;
    readGateway.failNext = 1;

    await submitCancel(tester);

    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(endCta, findsNothing);
    expect(lifecycle.endCount, 0);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // §11 — SEPARAÇÃO ENTRE OS DOIS RETRIES
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('§11 retry canônico e retry causal são separados', (
    tester,
  ) async {
    // Convergência falha E reload falha: os dois pendentes ao mesmo tempo.
    await seedSummary(projectionStatus: 'unavailable', generation: 41);
    await pumpDetail(tester);

    readGateway.status = RestrictionStatus.cancelled;
    readGateway.failNext = 1;

    await submitCancel(tester);

    expect(cancelController.convergence.mutationCommitted, isTrue);
    expect(cancelController.convergence.needsConvergenceRetry, isTrue);
    expect(refresh.refreshCount, 1);
    final readsAfterCommit = readGateway.calls;

    // Retry canônico NÃO dispara convergência.
    await tester.tap(canonicalRetry);
    await tester.pumpAndSettle();
    expect(readGateway.calls, readsAfterCommit + 1);
    expect(refresh.refreshCount, 1, reason: 'retry canônico não converge');
    expect(lifecycle.cancelCount, 1);

    // Agora o canônico está carregado e o banner causal aparece.
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    final causalRetry = find.byKey(
      const Key('restriction_retry_convergence'),
    );
    expect(causalRetry, findsOneWidget);

    // Retry causal NÃO dispara leitura canônica.
    final readsBeforeCausal = readGateway.calls;
    await tester.tap(causalRetry);
    await tester.pumpAndSettle();
    expect(refresh.refreshCount, 2);
    expect(
      readGateway.calls,
      readsBeforeCausal,
      reason: 'retry causal não relê o canônico',
    );
    expect(lifecycle.cancelCount, 1);
  });
}

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  int endCount = 0;
  int cancelCount = 0;
  Completer<void>? endGate;
  Completer<void>? cancelGate;

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
    final gate = endGate;
    if (gate != null) await gate.future;
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
    final gate = cancelGate;
    if (gate != null) await gate.future;
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
