import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_end_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart'
    show HealthEvidenceIntent;
import 'package:flutter_test/flutter_test.dart';

/// Registra a ordem exata das chamadas para provar que nenhuma etapa é refeita.
final class _Recorder {
  final List<String> calls = <String>[];
}

final class _FakeDocumentGateway implements HealthDocumentGateway {
  _FakeDocumentGateway(this.recorder);

  final _Recorder recorder;
  HealthRestrictionFlowFailure? prepareFailure;
  HealthRestrictionFlowFailure? finalizeFailure;
  int prepareCount = 0;
  int finalizeCount = 0;
  bool finalizeWasNoOp = false;
  String referenceId = 'hd_release';
  final List<String> prepareOperationIds = <String>[];
  final List<String> finalizeOperationIds = <String>[];

  @override
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  ) async {
    prepareCount += 1;
    prepareOperationIds.add(command.operationId);
    recorder.calls.add('prepare');
    final f = prepareFailure;
    if (f != null) return PrepareHealthDocumentError(f);
    return PrepareHealthDocumentSuccess(
      PreparedHealthDocumentUpload(
        dogId: command.dogId,
        documentId: 'hd_release',
        uploadPath: 'health_document_uploads/${command.dogId}/hd_release',
        maxBytes: 20 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<FinalizeHealthDocumentResult> finalizeUpload(
    FinalizeHealthDocumentCommand command,
  ) async {
    finalizeCount += 1;
    finalizeOperationIds.add(command.operationId);
    recorder.calls.add('finalize');
    final f = finalizeFailure;
    if (f != null) return FinalizeHealthDocumentError(f);
    return FinalizeHealthDocumentSuccess(
      FinalizedHealthDocument(
        dogId: command.dogId,
        documentId: 'hd_release',
        reference: HealthDocumentRef(healthDocumentId: referenceId),
        wasNoOp: finalizeWasNoOp,
      ),
    );
  }
}

final class _FakeUploader implements HealthEvidenceUploader {
  _FakeUploader(this.recorder);

  final _Recorder recorder;
  HealthRestrictionFlowFailure? failure;
  int count = 0;
  final List<String> paths = <String>[];

  @override
  Future<void> upload({
    required SelectedHealthEvidenceFile file,
    required String uploadPath,
  }) async {
    count += 1;
    paths.add(uploadPath);
    recorder.calls.add('upload');
    final f = failure;
    if (f != null) throw f;
  }
}

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  _FakeLifecycleGateway(this.recorder);

  final _Recorder recorder;
  HealthRestrictionFlowFailure? failure;
  bool wasNoOp = false;
  int endCount = 0;
  int cancelCount = 0;
  final List<EndOperationalRestrictionCommand> commands =
      <EndOperationalRestrictionCommand>[];

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
    commands.add(command);
    recorder.calls.add('end');
    final f = failure;
    if (f != null) return HealthRestrictionTerminalError(f);
    return HealthRestrictionTerminalSuccess(
      HealthRestrictionTerminalResult(
        dogId: command.dogId,
        restrictionId: command.restrictionId,
        status: HealthRestrictionTerminalStatus.ended,
        wasNoOp: wasNoOp,
      ),
    );
  }

  @override
  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  ) async {
    cancelCount += 1;
    throw StateError('END controller nunca deve chamar cancel()');
  }
}

void main() {
  const file = SelectedHealthEvidenceFile(
    name: 'liberacao.pdf',
    path: '/tmp/liberacao.pdf',
    sizeBytes: 5120,
    mimeType: 'application/pdf',
  );

  HealthEvidenceIntent evidenceIntent({
    SelectedHealthEvidenceFile selected = file,
    HealthEvidenceNature nature = HealthEvidenceNature.certificate,
    String title = 'Atestado de liberação — Bono',
  }) => HealthEvidenceIntent(file: selected, nature: nature, title: title);

  ProfessionalIdentity professional({String number = 'SP-54321'}) =>
      ProfessionalIdentity(
        name: 'Dr. Carlos Lima',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: number,
        clinic: 'Hospital Veterinário Central',
      );

  HealthRestrictionEndIntent endIntent({
    String reason = 'Reavaliação clínica concluída',
    ProfessionalIdentity? prof,
    String restrictionId = 'or_xyz',
  }) => HealthRestrictionEndIntent(
    dogId: 'dog-1',
    restrictionId: restrictionId,
    endReason: reason,
    endProfessional: prof ?? professional(),
  );

  ({
    HealthRestrictionEndController controller,
    _FakeDocumentGateway doc,
    _FakeUploader uploader,
    _FakeLifecycleGateway lifecycle,
    _Recorder recorder,
  })
  build() {
    final recorder = _Recorder();
    final doc = _FakeDocumentGateway(recorder);
    final uploader = _FakeUploader(recorder);
    final lifecycle = _FakeLifecycleGateway(recorder);
    var seq = 0;
    final controller = HealthRestrictionEndController(
      documentGateway: doc,
      uploader: uploader,
      lifecycleGateway: lifecycle,
      operationIdFactory: () => 'op-${++seq}',
    );
    return (
      controller: controller,
      doc: doc,
      uploader: uploader,
      lifecycle: lifecycle,
      recorder: recorder,
    );
  }

  group('happy path', () {
    test('ordem exata PREPARE → upload → FINALIZE → END', () async {
      final h = build();
      final ok = await h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(),
      );

      expect(ok, isTrue);
      expect(h.recorder.calls, ['prepare', 'upload', 'finalize', 'end']);
      expect(h.controller.stage, HealthRestrictionEndStage.success);
      expect(
        h.controller.result!.status,
        HealthRestrictionTerminalStatus.ended,
      );
    });

    test('operationIds de documento e de END são distintos', () async {
      final h = build();
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());

      final docOp = h.controller.documentOperationIdForTest;
      final endOp = h.controller.endOperationIdForTest;
      expect(docOp, isNotNull);
      expect(endOp, isNotNull);
      expect(docOp, isNot(endOp), reason: 'nunca reutilizar um como o outro');
    });

    test('upload usa exatamente o path do PREPARE', () async {
      final h = build();
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(
        h.uploader.paths.single,
        'health_document_uploads/dog-1/hd_release',
      );
    });

    test('END recebe a reference do FINALIZE e a razão normalizada', () async {
      final h = build();
      h.doc.referenceId = 'hd_do_finalize';
      await h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(reason: '  Alta clínica  '),
      );

      final command = h.lifecycle.commands.single;
      expect(command.endSourceDocument.healthDocumentId, 'hd_do_finalize');
      expect(command.endReason, 'Alta clínica');
      expect(command.restrictionId, 'or_xyz');
      expect(command.endProfessional.registrationNumber, 'SP-54321');
    });

    test('nunca chama cancel()', () async {
      final h = build();
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.lifecycle.cancelCount, 0);
    });
  });

  group('validação local', () {
    test('razão vazia bloqueia antes de qualquer rede', () async {
      final h = build();
      final ok = await h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(reason: '   '),
      );

      expect(ok, isFalse);
      expect(h.controller.failure, isA<HealthRestrictionFlowValidation>());
      expect(h.recorder.calls, isEmpty, reason: 'nada sai para a rede');
    });
  });

  group('retry por etapa', () {
    test('PREPARE falha → retry com o MESMO docOperationId', () async {
      final h = build();
      h.doc.prepareFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentPrepare,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isFalse,
      );
      final opId = h.controller.documentOperationIdForTest;

      h.doc.prepareFailure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );
      expect(h.doc.prepareOperationIds, [opId, opId]);
    });

    test('upload falha → retry sem repetir PREPARE, mesmo path', () async {
      final h = build();
      h.uploader.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentUpload,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.doc.prepareCount, 1);

      h.uploader.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );
      expect(h.doc.prepareCount, 1, reason: 'PREPARE não é refeito');
      expect(h.uploader.count, 2);
      expect(h.uploader.paths.first, h.uploader.paths.last);
    });

    test('FINALIZE falha → retry sem re-upload', () async {
      final h = build();
      h.doc.finalizeFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentFinalize,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.uploader.count, 1);

      h.doc.finalizeFailure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );
      expect(h.uploader.count, 1, reason: 'sem staging redundante');
      expect(h.doc.prepareCount, 1);
      expect(h.doc.finalizeCount, 2);
      expect(
        h.doc.finalizeOperationIds.first,
        h.doc.finalizeOperationIds.last,
        reason: 'mesma chave permite replay do receipt',
      );
    });

    test('END falha → retry sem recriar o documento', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.controller.documentReference, isNotNull);
      final endOp = h.controller.endOperationIdForTest;

      h.lifecycle.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );

      expect(h.doc.prepareCount, 1, reason: 'documento já é canônico');
      expect(h.uploader.count, 1);
      expect(h.doc.finalizeCount, 1);
      expect(h.lifecycle.endCount, 2);
      expect(h.controller.endOperationIdForTest, endOp);
    });
  });

  group('resposta perdida', () {
    test('FINALIZE replay devolve a mesma reference, sem re-upload', () async {
      final h = build();
      h.doc.finalizeFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentFinalize,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());

      h.doc.finalizeFailure = null;
      h.doc.finalizeWasNoOp = true;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );
      expect(
        h.controller.documentReference!.healthDocumentId,
        'hd_release',
      );
      expect(h.uploader.count, 1);
    });

    test('END replay conclui success sem recriar documento', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final endOp = h.controller.endOperationIdForTest;

      // Backend já havia commitado o END: replay do receipt.
      h.lifecycle.failure = null;
      h.lifecycle.wasNoOp = true;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isTrue,
      );

      expect(h.lifecycle.commands.last.operationId, endOp);
      expect(h.controller.result!.wasNoOp, isTrue);
      expect(
        h.controller.result!.status,
        HealthRestrictionTerminalStatus.ended,
      );
      expect(h.doc.prepareCount, 1);
      expect(h.uploader.count, 1);
      expect(h.doc.finalizeCount, 1);
    });
  });

  group('invalidação de intenção documental', () {
    test('arquivo muda → novo documento completo', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final firstDocOp = h.controller.documentOperationIdForTest;

      h.lifecycle.failure = null;
      const outro = SelectedHealthEvidenceFile(
        name: 'outra_liberacao.pdf',
        path: '/tmp/outra.pdf',
        sizeBytes: 8000,
        mimeType: 'application/pdf',
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(selected: outro),
          end: endIntent(),
        ),
        isTrue,
      );

      expect(h.controller.documentOperationIdForTest, isNot(firstDocOp));
      expect(h.doc.prepareCount, 2);
      expect(h.uploader.count, 2);
      expect(h.doc.finalizeCount, 2);
    });

    test('natureza muda → novo documento', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final first = h.controller.documentOperationIdForTest;

      h.lifecycle.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(nature: HealthEvidenceNature.report),
        end: endIntent(),
      );
      expect(h.controller.documentOperationIdForTest, isNot(first));
      expect(h.doc.prepareCount, 2);
    });

    test('título muda → novo documento', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final first = h.controller.documentOperationIdForTest;

      h.lifecycle.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(title: 'Laudo de liberação — Bono'),
        end: endIntent(),
      );
      expect(h.controller.documentOperationIdForTest, isNot(first));
      expect(h.doc.prepareCount, 2);
    });
  });

  group('invalidação de intenção terminal', () {
    test('só a razão muda → documento preservado, novo endOpId', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final firstEndOp = h.controller.endOperationIdForTest;
      final ref = h.controller.documentReference;

      h.lifecycle.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(reason: 'Alta com restrição de carga'),
        ),
        isTrue,
      );

      expect(h.controller.endOperationIdForTest, isNot(firstEndOp));
      expect(h.controller.documentReference, ref, reason: 'documento intacto');
      expect(h.doc.prepareCount, 1);
      expect(h.uploader.count, 1);
      expect(h.doc.finalizeCount, 1);
    });

    test('só o profissional muda → documento preservado, novo endOpId', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final first = h.controller.endOperationIdForTest;

      h.lifecycle.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(prof: professional(number: 'SP-00000')),
      );

      expect(h.controller.endOperationIdForTest, isNot(first));
      expect(h.doc.prepareCount, 1, reason: 'documento não é recriado');
      expect(h.doc.finalizeCount, 1);
    });

    test('documento novo também troca a chave terminal', () async {
      // A evidência entra no fingerprint do END: mudar o documento muda o
      // payload, então a chave precisa mudar.
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final firstEndOp = h.controller.endOperationIdForTest;

      h.lifecycle.failure = null;
      h.doc.referenceId = 'hd_outro';
      const outro = SelectedHealthEvidenceFile(
        name: 'outra.pdf',
        path: '/tmp/outra.pdf',
        sizeBytes: 7000,
        mimeType: 'application/pdf',
      );
      await h.controller.submit(
        evidence: evidenceIntent(selected: outro),
        end: endIntent(),
      );

      expect(h.controller.endOperationIdForTest, isNot(firstEndOp));
      expect(
        h.lifecycle.commands.last.endSourceDocument.healthDocumentId,
        'hd_outro',
      );
    });

    test('nada muda → todas as chaves estáveis', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      final docOp = h.controller.documentOperationIdForTest;
      final endOp = h.controller.endOperationIdForTest;

      h.lifecycle.failure = null;
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.controller.documentOperationIdForTest, docOp);
      expect(h.controller.endOperationIdForTest, endOp);
    });
  });

  group('fail-closed', () {
    test('upload falho não avança para FINALIZE nem END', () async {
      final h = build();
      h.uploader.failure = const HealthRestrictionFlowIntegrity(
        HealthRestrictionFlowStep.documentUpload,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isFalse,
      );

      expect(h.recorder.calls, ['prepare', 'upload']);
      expect(h.doc.finalizeCount, 0);
      expect(h.lifecycle.endCount, 0);
    });

    test('PREPARE falho não faz upload', () async {
      final h = build();
      h.doc.prepareFailure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.documentPrepare,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());
      expect(h.recorder.calls, ['prepare']);
      expect(h.uploader.count, 0);
    });

    test('conflito terminal preserva erro tipado', () async {
      final h = build();
      h.lifecycle.failure = const HealthRestrictionFlowConflict(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          end: endIntent(),
        ),
        isFalse,
      );

      expect(h.controller.failure, isA<HealthRestrictionFlowConflict>());
      expect(h.controller.result, isNull, reason: 'nunca vira sucesso');
      // O documento permanece canônico e simplesmente não citado.
      expect(h.controller.documentReference, isNotNull);
    });

    test('permission-denied de END preserva etapa', () async {
      final h = build();
      // Falha construída direto (sem passar pelo mapper): o default é neutro
      // quanto à etapa, então aqui só a etapa é verificável. A frase por
      // comando é contrato do mapper, coberta no teste do gateway.
      h.lifecycle.failure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.restrictionEnd,
      );
      await h.controller.submit(evidence: evidenceIntent(), end: endIntent());

      expect(
        h.controller.failure!.step,
        HealthRestrictionFlowStep.restrictionEnd,
      );
      // Default neutro nunca afirma o comando errado.
      expect(h.controller.failure!.message, contains('autorização'));
      expect(h.controller.failure!.message, isNot(contains('registrar')));
    });

    test('submit concorrente é bloqueado', () async {
      final h = build();
      final a = h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(),
      );
      final b = h.controller.submit(
        evidence: evidenceIntent(),
        end: endIntent(),
      );
      final results = await Future.wait([a, b]);

      expect(results.where((r) => r).length, 1);
      expect(h.doc.prepareCount, 1);
    });
  });
}
