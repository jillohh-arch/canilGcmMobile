import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_readiness_convergence.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_cancel_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_convergence_coordinator.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_end_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart';

/// B4-R.C3 — convergência causal nos três controllers de restrição.
///
/// Autoridade: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`.
///
/// A invariante mais consequente aqui: uma falha de CONVERGÊNCIA nunca pode
/// repetir a mutation nem apresentar o comando como não aplicado.
const _dogId = 'dog-1';
const _otherDogId = 'dog-2';

/// Conta chamadas do callable de refresh e permite mutar o summary entre a
/// resposta e a releitura — é assim que as corridas são provadas sem sleep.
final class _RefreshStub {
  int refreshCount = 0;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  /// Resposta causal a devolver. `null` = sem `convergence` (backend antigo).
  Map<String, Object?>? convergence = {
    'status': 'confirmed',
    'requiredGeneration': 42,
    'observedGeneration': 42,
  };
  bool omitConvergenceKey = false;
  Object? throwOnRefresh;

  /// Executado após a resposta e ANTES da releitura do Mobile.
  Future<void> Function()? betweenResponseAndReread;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    refreshCount += 1;
    payloads.add(payload);
    final boom = throwOnRefresh;
    if (boom != null) throw boom;

    await betweenResponseAndReread?.call();

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
        if (!omitConvergenceKey) 'convergence': convergence,
      },
    };
  }
}

final class _FakeIssueGateway implements HealthRestrictionIssueGateway {
  int count = 0;
  HealthRestrictionFlowFailure? failure;

  @override
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  ) async {
    count += 1;
    final f = failure;
    if (f != null) return IssueOperationalRestrictionError(f);
    return IssueOperationalRestrictionSuccess(
      IssuedOperationalRestriction(
        dogId: command.dogId,
        restrictionId: 'or_xyz',
        wasNoOp: false,
      ),
    );
  }
}

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  int cancelCount = 0;
  int endCount = 0;
  HealthRestrictionFlowFailure? failure;

  @override
  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  ) async {
    cancelCount += 1;
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

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
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
        uploadPath: 'health_document_uploads/$_dogId/hd_abc',
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

void main() {
  const dogId = _dogId;
  const otherDogId = _otherDogId;

  late FakeFirebaseFirestore firestore;
  late _RefreshStub refresh;

  Future<void> seedSummary({
    String forDog = dogId,
    required String projectionStatus,
    int? generation,
  }) async {
    await firestore
        .collection('dogs')
        .doc(forDog)
        .collection('health_summary')
        .doc('current')
        .set(<String, Object?>{
          'projection_status': projectionStatus,
          'schema_version': 1,
          // Chave omitida (não `null`) reproduz o summary legado.
          ...generation == null
              ? const <String, Object?>{}
              : <String, Object?>{'projection_generation': generation},
        });
  }

  HealthReadinessConvergenceGateway buildGateway() =>
      HealthReadinessConvergenceGateway(
        invoke: refresh.call,
        firestore: firestore,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    refresh = _RefreshStub();
  });

  // ── Intenções ──────────────────────────────────────────────────────────────

  const file = SelectedHealthEvidenceFile(
    name: 'laudo.pdf',
    path: '/tmp/laudo.pdf',
    sizeBytes: 4096,
    mimeType: 'application/pdf',
  );

  final evidence = HealthEvidenceIntent(
    file: file,
    nature: HealthEvidenceNature.certificate,
    title: 'Atestado veterinário',
  );

  final professional = ProfessionalIdentity(
    name: 'Dra. Ana Souza',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-12345',
    clinic: 'Clínica Central',
  );

  final issueIntent = HealthRestrictionIntent(
    dogId: dogId,
    level: RestrictionLevel.absolute,
    category: RestrictionCategory.injury,
    description: 'Lesão em membro anterior',
    professional: professional,
    activitiesRestricted: const <String>[],
  );

  HealthRestrictionCancelIntent cancelIntent({String dog = dogId}) =>
      HealthRestrictionCancelIntent(
        dogId: dog,
        restrictionId: 'or_xyz',
        cancelReason: 'Registro criado por engano',
      );

  HealthRestrictionEndIntent endIntent() => HealthRestrictionEndIntent(
    dogId: dogId,
    restrictionId: 'or_xyz',
    endReason: 'Alta clínica confirmada',
    endProfessional: professional,
  );

  // ── CANCEL: o caminho mais simples ─────────────────────────────────────────

  group('CANCEL — convergência', () {
    late _FakeLifecycleGateway lifecycle;
    late HealthRestrictionCancelController controller;

    setUp(() {
      lifecycle = _FakeLifecycleGateway();
      var seq = 0;
      controller = HealthRestrictionCancelController(
        gateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'cancel-op-${++seq}',
      );
    });

    test('sucesso + prova local -> converged', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);

      final ok = await controller.submit(cancelIntent());

      expect(ok, isTrue);
      expect(controller.stage, HealthRestrictionCancelStage.success);
      expect(lifecycle.cancelCount, 1);
      expect(controller.convergence.mutationCommitted, isTrue);
      expect(controller.convergence.isConverged, isTrue);
      expect(
        controller.convergence.phase,
        HealthRestrictionConvergencePhase.converged,
      );
      expect(refresh.refreshCount, 1);
    });

    test('falha de convergência preserva o comando commitado', () async {
      await seedSummary(projectionStatus: 'unavailable', generation: 41);

      final ok = await controller.submit(cancelIntent());

      // O comando foi aplicado; apenas a projeção não foi provada.
      expect(ok, isTrue);
      expect(controller.stage, HealthRestrictionCancelStage.success);
      expect(controller.result, isNotNull);
      expect(controller.failure, isNull, reason: 'não é falha de cancelamento');
      expect(controller.convergence.mutationCommitted, isTrue);
      expect(controller.convergence.convergenceFailed, isTrue);
      expect(controller.convergence.needsConvergenceRetry, isTrue);
      expect(
        controller.convergence.result!.outcome,
        HealthReadinessConvergenceOutcome.unavailable,
      );
    });

    test('retryConvergence NÃO repete o cancelamento', () async {
      await seedSummary(projectionStatus: 'unavailable', generation: 41);
      await controller.submit(cancelIntent());
      expect(lifecycle.cancelCount, 1);

      // Servidor agora consegue projetar.
      await seedSummary(projectionStatus: 'ready', generation: 42);
      await controller.convergence.retryConvergence();

      expect(controller.convergence.isConverged, isTrue);
      expect(
        lifecycle.cancelCount,
        1,
        reason: 'CANCEL jamais pode ser reenviado por retry de convergência',
      );
      expect(refresh.refreshCount, 2);
    });

    test('mutation falha -> nenhuma convergência é tentada', () async {
      lifecycle.failure = const HealthRestrictionFlowConflict(
        HealthRestrictionFlowStep.restrictionCancel,
        'conflito',
      );

      final ok = await controller.submit(cancelIntent());

      expect(ok, isFalse);
      expect(controller.convergence.mutationCommitted, isFalse);
      expect(
        controller.convergence.phase,
        HealthRestrictionConvergencePhase.idle,
      );
      expect(refresh.refreshCount, 0);
    });

    test('já convergido: retry é no-op sem chamar backend', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);
      await controller.submit(cancelIntent());
      expect(controller.convergence.isConverged, isTrue);

      await controller.convergence.retryConvergence();

      expect(refresh.refreshCount, 1, reason: 'nenhum refresh adicional');
      expect(lifecycle.cancelCount, 1);
    });

    test('convergência fica ligada ao cão da mutation', () async {
      // O cão da mutation tem prova; outro cão tem estado indisponível.
      await seedSummary(forDog: otherDogId, projectionStatus: 'ready', generation: 99);
      await seedSummary(projectionStatus: 'ready', generation: 42);

      await controller.submit(cancelIntent());

      expect(refresh.payloads.single['dogId'], dogId);
      expect(controller.convergence.isConverged, isTrue);
    });
  });

  // ── ISSUE: R-01 safety ─────────────────────────────────────────────────────

  group('ISSUE — R-01 safety', () {
    late _FakeIssueGateway issue;
    late _FakeDocumentGateway doc;
    late _FakeUploader uploader;
    late HealthRestrictionIssueController controller;

    setUp(() {
      issue = _FakeIssueGateway();
      doc = _FakeDocumentGateway();
      uploader = _FakeUploader();
      var seq = 0;
      controller = HealthRestrictionIssueController(
        documentGateway: doc,
        uploader: uploader,
        restrictionGateway: issue,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'op-${++seq}',
      );
    });

    test('sucesso + prova local -> converged', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);

      final ok = await controller.submit(
        evidence: evidence,
        restriction: issueIntent,
      );

      expect(ok, isTrue);
      expect(controller.stage, HealthRestrictionIssueStage.success);
      expect(controller.restrictionId, 'or_xyz');
      expect(controller.convergence.isConverged, isTrue);
      expect(issue.count, 1);
    });

    test(
      'retryConvergence NÃO reemite a restrição nem refaz o pipeline documental',
      () async {
        await seedSummary(projectionStatus: 'unavailable', generation: 41);
        await controller.submit(evidence: evidence, restriction: issueIntent);

        expect(issue.count, 1);
        expect(doc.prepareCount, 1);
        expect(doc.finalizeCount, 1);
        expect(uploader.count, 1);
        expect(controller.convergence.needsConvergenceRetry, isTrue);

        await seedSummary(projectionStatus: 'ready', generation: 42);
        await controller.convergence.retryConvergence();

        expect(controller.convergence.isConverged, isTrue);
        // R-01 permanece aberto: C3 não pode piorá-lo criando uma segunda
        // restrição por causa de uma falha de projeção.
        expect(issue.count, 1, reason: 'ISSUE jamais reenviado');
        expect(doc.prepareCount, 1, reason: 'PREPARE jamais refeito');
        expect(doc.finalizeCount, 1, reason: 'FINALIZE jamais refeito');
        expect(uploader.count, 1, reason: 'upload jamais refeito');
        // O restrictionId canônico sobrevive à falha de convergência.
        expect(controller.restrictionId, 'or_xyz');
      },
    );

    test('restrictionId sobrevive à falha de convergência', () async {
      await seedSummary(projectionStatus: 'unavailable', generation: 41);
      await controller.submit(evidence: evidence, restriction: issueIntent);

      expect(controller.restrictionId, 'or_xyz');
      expect(controller.documentReference, isNotNull);
      expect(controller.stage, HealthRestrictionIssueStage.success);
      expect(controller.failure, isNull);
    });
  });

  // ── END: retry safety ──────────────────────────────────────────────────────

  group('END — retry safety', () {
    late _FakeLifecycleGateway lifecycle;
    late _FakeDocumentGateway doc;
    late _FakeUploader uploader;
    late HealthRestrictionEndController controller;

    setUp(() {
      lifecycle = _FakeLifecycleGateway();
      doc = _FakeDocumentGateway();
      uploader = _FakeUploader();
      var seq = 0;
      controller = HealthRestrictionEndController(
        documentGateway: doc,
        uploader: uploader,
        lifecycleGateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'end-op-${++seq}',
      );
    });

    test('sucesso + prova local -> converged', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);

      final ok = await controller.submit(
        evidence: evidence,
        end: endIntent(),
      );

      expect(ok, isTrue);
      expect(controller.stage, HealthRestrictionEndStage.success);
      expect(lifecycle.endCount, 1);
      expect(controller.convergence.isConverged, isTrue);
    });

    test(
      'retryConvergence NÃO reencerra nem refaz o pipeline documental',
      () async {
        await seedSummary(projectionStatus: 'unavailable', generation: 41);
        await controller.submit(evidence: evidence, end: endIntent());

        expect(lifecycle.endCount, 1);
        expect(doc.prepareCount, 1);
        expect(doc.finalizeCount, 1);
        expect(uploader.count, 1);
        expect(controller.result, isNotNull);

        await seedSummary(projectionStatus: 'ready', generation: 42);
        await controller.convergence.retryConvergence();

        expect(controller.convergence.isConverged, isTrue);
        expect(lifecycle.endCount, 1, reason: 'END jamais reenviado');
        expect(doc.prepareCount, 1, reason: 'PREPARE jamais refeito');
        expect(doc.finalizeCount, 1, reason: 'FINALIZE jamais refeito');
        expect(uploader.count, 1, reason: 'upload jamais refeito');
        expect(controller.result, isNotNull, reason: 'resultado terminal vive');
      },
    );
  });

  // ── Corridas: a prova local é a autoridade final ───────────────────────────

  group('corridas entre resposta e releitura', () {
    late _FakeLifecycleGateway lifecycle;
    late HealthRestrictionCancelController controller;

    setUp(() {
      lifecycle = _FakeLifecycleGateway();
      controller = HealthRestrictionCancelController(
        gateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'cancel-op',
      );
    });

    test(
      'UPGRADE — servidor unavailable, mas READY 43 commita antes da releitura',
      () async {
        await seedSummary(projectionStatus: 'unavailable', generation: 41);
        refresh.convergence = {
          'status': 'unavailable',
          'requiredGeneration': 42,
          'observedGeneration': 41,
        };
        // Outra entrada aplica READY 43 no intervalo.
        refresh.betweenResponseAndReread = () =>
            seedSummary(projectionStatus: 'ready', generation: 43);

        await controller.submit(cancelIntent());

        expect(
          controller.convergence.isConverged,
          isTrue,
          reason: '43 >= 42 com estado ready é prova causal válida',
        );
        // A resposta do servidor é preservada para diagnóstico.
        expect(
          controller.convergence.result!.serverReport!.status,
          HealthReadinessServerConvergence.unavailable,
        );
        expect(
          controller.convergence.result!.observedMarker!.generation,
          43,
        );
      },
    );

    test(
      'DOWNGRADE — servidor confirmed, mas UNAVAILABLE commita antes da releitura',
      () async {
        await seedSummary(projectionStatus: 'ready', generation: 42);
        refresh.convergence = {
          'status': 'confirmed',
          'requiredGeneration': 42,
          'observedGeneration': 42,
        };
        // Geração mais nova aplica unavailable, preservando o marcador 42.
        refresh.betweenResponseAndReread = () =>
            seedSummary(projectionStatus: 'unavailable', generation: 42);

        await controller.submit(cancelIntent());

        expect(
          controller.convergence.isConverged,
          isFalse,
          reason: 'não renderizar convergido com fotografia HTTP antiga',
        );
        expect(
          controller.convergence.result!.outcome,
          HealthReadinessConvergenceOutcome.unavailable,
        );
        // E o cancelamento continua commitado.
        expect(controller.stage, HealthRestrictionCancelStage.success);
      },
    );
  });

  // ── Rollout e integridade ──────────────────────────────────────────────────

  group('rollout e integridade do contrato', () {
    late _FakeLifecycleGateway lifecycle;
    late HealthRestrictionCancelController controller;

    setUp(() {
      lifecycle = _FakeLifecycleGateway();
      controller = HealthRestrictionCancelController(
        gateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'cancel-op',
      );
    });

    test('backend antigo (ok true, sem convergence) -> contractUnavailable', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);
      refresh.omitConvergenceKey = true;

      await controller.submit(cancelIntent());

      expect(controller.convergence.mutationCommitted, isTrue);
      expect(controller.convergence.isConverged, isFalse);
      expect(
        controller.convergence.result!.outcome,
        HealthReadinessConvergenceOutcome.contractUnavailable,
      );
      // Mutation permanece commitada; retry de convergência é permitido.
      expect(controller.stage, HealthRestrictionCancelStage.success);
      expect(controller.convergence.needsConvergenceRetry, isTrue);
      expect(lifecycle.cancelCount, 1);
    });

    test('wire malformado -> integrityFailure, fail closed', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);
      refresh.convergence = {
        'status': 'confirmed',
        'requiredGeneration': 0, // inválido
        'observedGeneration': 42,
      };

      await controller.submit(cancelIntent());

      expect(
        controller.convergence.result!.outcome,
        HealthReadinessConvergenceOutcome.integrityFailure,
      );
      expect(controller.convergence.isConverged, isFalse);
      expect(controller.stage, HealthRestrictionCancelStage.success);
    });

    test('exceção no refresh -> readFailure, mutation intacta', () async {
      await seedSummary(projectionStatus: 'ready', generation: 42);
      refresh.throwOnRefresh = StateError('canal caiu');

      await controller.submit(cancelIntent());

      expect(
        controller.convergence.result!.outcome,
        HealthReadinessConvergenceOutcome.readFailure,
      );
      expect(controller.convergence.mutationCommitted, isTrue);
      expect(controller.stage, HealthRestrictionCancelStage.success);
      expect(controller.failure, isNull);
    });

    test('summary ausente -> não converge, sem inventar generation', () async {
      // Nenhum seed: documento não existe.
      await controller.submit(cancelIntent());

      expect(controller.convergence.isConverged, isFalse);
      expect(
        controller.convergence.result!.observedMarker!.generation,
        isNull,
      );
      expect(controller.stage, HealthRestrictionCancelStage.success);
    });

    test('summary sem marcador causal -> notConfirmed', () async {
      await seedSummary(projectionStatus: 'ready'); // sem generation

      await controller.submit(cancelIntent());

      expect(
        controller.convergence.result!.outcome,
        HealthReadinessConvergenceOutcome.notConfirmed,
      );
      expect(
        controller.convergence.result!.observedMarker!.generation,
        isNull,
      );
    });

    test('retry sem mutation commitada é no-op', () async {
      await controller.convergence.retryConvergence();
      expect(refresh.refreshCount, 0);
    });
  });

  // ── C3.R: exatamente UMA tentativa automática, sem bypass possível ─────────
  //
  // A dependência causal é obrigatória nos três controllers, então não existe
  // caminho de produção em que a mutation commita e nenhuma tentativa acontece.
  // Estes testes provam a contagem exata em cada vertical.

  group('C3.R — tentativa automática obrigatória', () {
    test('CANCEL: sucesso dispara exatamente 1 convergência', () async {
      final lifecycle = _FakeLifecycleGateway();
      final controller = HealthRestrictionCancelController(
        gateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'cancel-op',
      );
      await seedSummary(projectionStatus: 'ready', generation: 42);

      await controller.submit(cancelIntent());

      expect(refresh.refreshCount, 1, reason: 'nem zero, nem duas');
      expect(
        controller.convergence.phase,
        isNot(HealthRestrictionConvergencePhase.idle),
        reason: 'idle após commit seria bypass silencioso',
      );
    });

    test('ISSUE: sucesso dispara exatamente 1 convergência', () async {
      final controller = HealthRestrictionIssueController(
        documentGateway: _FakeDocumentGateway(),
        uploader: _FakeUploader(),
        restrictionGateway: _FakeIssueGateway(),
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'op',
      );
      await seedSummary(projectionStatus: 'ready', generation: 42);

      await controller.submit(evidence: evidence, restriction: issueIntent);

      expect(refresh.refreshCount, 1);
      expect(controller.convergence.isConverged, isTrue);
    });

    test('END: sucesso dispara exatamente 1 convergência', () async {
      final controller = HealthRestrictionEndController(
        documentGateway: _FakeDocumentGateway(),
        uploader: _FakeUploader(),
        lifecycleGateway: _FakeLifecycleGateway(),
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'end-op',
      );
      await seedSummary(projectionStatus: 'ready', generation: 42);

      await controller.submit(evidence: evidence, end: endIntent());

      expect(refresh.refreshCount, 1);
      expect(controller.convergence.isConverged, isTrue);
    });

    test('falha de mutation não dispara convergência em nenhuma vertical', () async {
      final failure = const HealthRestrictionFlowConflict(
        HealthRestrictionFlowStep.restrictionCancel,
        'conflito',
      );

      final lifecycle = _FakeLifecycleGateway()..failure = failure;
      final cancel = HealthRestrictionCancelController(
        gateway: lifecycle,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'cancel-op',
      );
      await cancel.submit(cancelIntent());

      final issueGateway = _FakeIssueGateway()..failure = failure;
      final issue = HealthRestrictionIssueController(
        documentGateway: _FakeDocumentGateway(),
        uploader: _FakeUploader(),
        restrictionGateway: issueGateway,
        convergenceGateway: buildGateway(),
        operationIdFactory: () => 'op',
      );
      await issue.submit(evidence: evidence, restriction: issueIntent);

      expect(refresh.refreshCount, 0, reason: 'writer não confirmou');
      expect(cancel.convergence.mutationCommitted, isFalse);
      expect(issue.convergence.mutationCommitted, isFalse);
    });
  });
}
