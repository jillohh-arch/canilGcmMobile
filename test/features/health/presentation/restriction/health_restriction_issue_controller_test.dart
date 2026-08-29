import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'convergence_test_gateway.dart';

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
  String uploadPath = 'health_document_uploads/dog-1/hd_abc';
  String referenceId = 'hd_abc';
  bool finalizeWasNoOp = false;
  final List<String> prepareOperationIds = <String>[];
  final List<String> finalizeOperationIds = <String>[];

  @override
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  ) async {
    prepareCount += 1;
    prepareOperationIds.add(command.operationId);
    recorder.calls.add('prepare');
    final failure = prepareFailure;
    if (failure != null) return PrepareHealthDocumentError(failure);
    return PrepareHealthDocumentSuccess(
      PreparedHealthDocumentUpload(
        dogId: command.dogId,
        documentId: 'hd_abc',
        uploadPath: uploadPath,
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
    final failure = finalizeFailure;
    if (failure != null) return FinalizeHealthDocumentError(failure);
    return FinalizeHealthDocumentSuccess(
      FinalizedHealthDocument(
        dogId: command.dogId,
        documentId: 'hd_abc',
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

final class _FakeIssueGateway implements HealthRestrictionIssueGateway {
  _FakeIssueGateway(this.recorder);

  final _Recorder recorder;
  HealthRestrictionFlowFailure? failure;
  int count = 0;
  bool wasNoOp = false;
  final List<IssueOperationalRestrictionCommand> commands =
      <IssueOperationalRestrictionCommand>[];

  @override
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  ) async {
    count += 1;
    commands.add(command);
    recorder.calls.add('issue');
    final f = failure;
    if (f != null) return IssueOperationalRestrictionError(f);
    return IssueOperationalRestrictionSuccess(
      IssuedOperationalRestriction(
        dogId: command.dogId,
        restrictionId: 'or_xyz',
        wasNoOp: wasNoOp,
      ),
    );
  }
}

void main() {
  const file = SelectedHealthEvidenceFile(
    name: 'laudo.pdf',
    path: '/tmp/laudo.pdf',
    sizeBytes: 4096,
    mimeType: 'application/pdf',
  );

  HealthEvidenceIntent evidenceIntent({
    SelectedHealthEvidenceFile selected = file,
    HealthEvidenceNature nature = HealthEvidenceNature.certificate,
    String title = 'Atestado veterinário — Bono',
  }) => HealthEvidenceIntent(
    file: selected,
    nature: nature,
    title: title,
  );

  ProfessionalIdentity professional({String number = 'SP-12345'}) =>
      ProfessionalIdentity(
        name: 'Dra. Ana Souza',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: number,
        clinic: 'Clínica Central',
      );

  HealthRestrictionIntent restrictionIntent({
    RestrictionLevel level = RestrictionLevel.absolute,
    String description = 'Lesão em membro anterior',
    List<String> activities = const <String>[],
    ProfessionalIdentity? prof,
  }) => HealthRestrictionIntent(
    dogId: 'dog-1',
    level: level,
    category: RestrictionCategory.injury,
    description: description,
    professional: prof ?? professional(),
    activitiesRestricted: activities,
  );

  ({
    HealthRestrictionIssueController controller,
    _FakeDocumentGateway doc,
    _FakeUploader uploader,
    _FakeIssueGateway issue,
    _Recorder recorder,
  })
  build() {
    final recorder = _Recorder();
    final doc = _FakeDocumentGateway(recorder);
    final uploader = _FakeUploader(recorder);
    final issue = _FakeIssueGateway(recorder);
    var seq = 0;
    final controller = HealthRestrictionIssueController(
      documentGateway: doc,
      uploader: uploader,
      restrictionGateway: issue,
      convergenceGateway: convergenceTestGateway(),
      operationIdFactory: () => 'op-${++seq}',
    );
    return (
      controller: controller,
      doc: doc,
      uploader: uploader,
      issue: issue,
      recorder: recorder,
    );
  }

  group('happy path', () {
    test('ordem exata PREPARE → upload → FINALIZE → ISSUE', () async {
      final h = build();
      final ok = await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      expect(ok, isTrue);
      expect(h.recorder.calls, ['prepare', 'upload', 'finalize', 'issue']);
      expect(h.controller.stage, HealthRestrictionIssueStage.success);
      expect(h.controller.restrictionId, 'or_xyz');
    });

    test('operationIds do documento e da restrição são distintos', () async {
      final h = build();
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      final docOp = h.controller.documentOperationIdForTest;
      final resOp = h.controller.restrictionOperationIdForTest;
      expect(docOp, isNotNull);
      expect(resOp, isNotNull);
      expect(docOp, isNot(resOp), reason: 'nunca reutilizar um como o outro');
    });

    test('upload usa exatamente o path devolvido pelo PREPARE', () async {
      final h = build();
      h.doc.uploadPath = 'health_document_uploads/dog-1/hd_derivado';
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      expect(h.uploader.paths, ['health_document_uploads/dog-1/hd_derivado']);
    });

    test('FINALIZE reusa o mesmo docOperationId do PREPARE', () async {
      final h = build();
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      expect(h.doc.prepareOperationIds.single, h.doc.finalizeOperationIds.single);
    });

    test('ISSUE recebe exatamente a reference do FINALIZE', () async {
      final h = build();
      h.doc.referenceId = 'hd_do_finalize';
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      expect(
        h.issue.commands.single.sourceDocument.healthDocumentId,
        'hd_do_finalize',
      );
    });

    test('partial envia atividades; outros níveis não', () async {
      final partial = build();
      await partial.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(
          level: RestrictionLevel.partial,
          activities: const ['busca'],
        ),
      );
      expect(partial.issue.commands.single.activitiesRestricted, ['busca']);

      final absolute = build();
      await absolute.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(activities: const ['busca']),
      );
      expect(
        absolute.issue.commands.single.activitiesRestricted,
        isEmpty,
        reason: 'atividades só são materiais em partial',
      );
    });
  });

  group('retry por etapa', () {
    test('PREPARE falha → retry usa o MESMO docOperationId', () async {
      final h = build();
      h.doc.prepareFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentPrepare,
      );
      final first = await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      expect(first, isFalse);
      expect(h.controller.stage, HealthRestrictionIssueStage.failure);
      final opId = h.controller.documentOperationIdForTest;

      h.doc.prepareFailure = null;
      final second = await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      expect(second, isTrue);
      expect(h.controller.documentOperationIdForTest, opId);
      expect(h.doc.prepareOperationIds, [opId, opId]);
    });

    test('upload falha → retry NÃO repete PREPARE e usa o mesmo path', () async {
      final h = build();
      h.uploader.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentUpload,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isFalse,
      );
      expect(h.doc.prepareCount, 1);

      h.uploader.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );
      expect(h.doc.prepareCount, 1, reason: 'PREPARE não é refeito');
      expect(h.uploader.count, 2);
      expect(h.uploader.paths.first, h.uploader.paths.last);
    });

    test('FINALIZE falha → retry NÃO re-uploada', () async {
      final h = build();
      h.doc.finalizeFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentFinalize,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isFalse,
      );
      expect(h.uploader.count, 1);

      h.doc.finalizeFailure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );
      expect(
        h.uploader.count,
        1,
        reason: 'não re-uploadar antes de tentar o replay do FINALIZE',
      );
      expect(h.doc.prepareCount, 1);
      expect(h.doc.finalizeCount, 2);
      // Mesmo docOperationId nas duas tentativas → replay possível no backend.
      expect(
        h.doc.finalizeOperationIds.first,
        h.doc.finalizeOperationIds.last,
      );
    });

    test('ISSUE falha → retry NÃO recria o documento', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isFalse,
      );
      expect(h.controller.documentReference, isNotNull);
      final resOp = h.controller.restrictionOperationIdForTest;

      h.issue.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );
      expect(h.doc.prepareCount, 1, reason: 'documento já é canônico');
      expect(h.uploader.count, 1);
      expect(h.doc.finalizeCount, 1);
      expect(h.issue.count, 2);
      expect(
        h.controller.restrictionOperationIdForTest,
        resOp,
        reason: 'mesma intenção → mesma chave → replay idempotente',
      );
    });
  });

  group('resposta perdida', () {
    test('FINALIZE replay devolve a mesma reference', () async {
      final h = build();
      h.doc.finalizeFailure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.documentFinalize,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );

      // Backend já havia commitado: o replay responde wasNoOp com o mesmo ref.
      h.doc.finalizeFailure = null;
      h.doc.finalizeWasNoOp = true;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );
      expect(h.controller.documentReference!.healthDocumentId, 'hd_abc');
      expect(h.uploader.count, 1, reason: 'sem upload redundante');
    });

    test('ISSUE replay não gera nova mutation', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final resOp = h.controller.restrictionOperationIdForTest;

      h.issue.failure = null;
      h.issue.wasNoOp = true;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );
      expect(h.controller.restrictionId, 'or_xyz');
      expect(h.issue.commands.last.operationId, resOp);
    });
  });

  group('invalidação de intenção', () {
    test('dados da restrição mudam → novo restrictionOperationId, documento preservado', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final firstResOp = h.controller.restrictionOperationIdForTest;
      final ref = h.controller.documentReference;

      h.issue.failure = null;
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(description: 'Descrição corrigida'),
        ),
        isTrue,
      );

      expect(
        h.controller.restrictionOperationIdForTest,
        isNot(firstResOp),
        reason: 'payload diferente exige chave nova',
      );
      expect(h.controller.documentReference, ref, reason: 'documento intacto');
      expect(h.doc.prepareCount, 1);
      expect(h.uploader.count, 1);
      expect(h.doc.finalizeCount, 1);
    });

    test('profissional muda → novo restrictionOperationId', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final first = h.controller.restrictionOperationIdForTest;

      h.issue.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(prof: professional(number: 'SP-99999')),
      );
      expect(h.controller.restrictionOperationIdForTest, isNot(first));
    });

    test('arquivo muda após FINALIZE → novo documento completo', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final firstDocOp = h.controller.documentOperationIdForTest;

      h.issue.failure = null;
      const outro = SelectedHealthEvidenceFile(
        name: 'outro.pdf',
        path: '/tmp/outro.pdf',
        sizeBytes: 9000,
        mimeType: 'application/pdf',
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(selected: outro),
          restriction: restrictionIntent(),
        ),
        isTrue,
      );

      expect(h.controller.documentOperationIdForTest, isNot(firstDocOp));
      expect(h.doc.prepareCount, 2, reason: 'novo documento exige novo PREPARE');
      expect(h.uploader.count, 2);
      expect(h.doc.finalizeCount, 2);
    });

    test('natureza ou título mudam → novo documento', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final firstDocOp = h.controller.documentOperationIdForTest;

      h.issue.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(nature: HealthEvidenceNature.report),
        restriction: restrictionIntent(),
      );
      expect(h.controller.documentOperationIdForTest, isNot(firstDocOp));
      expect(h.doc.prepareCount, 2);
    });

    test('nada muda → todas as chaves estáveis', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final docOp = h.controller.documentOperationIdForTest;
      final resOp = h.controller.restrictionOperationIdForTest;

      h.issue.failure = null;
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      expect(h.controller.documentOperationIdForTest, docOp);
      expect(h.controller.restrictionOperationIdForTest, resOp);
    });
  });

  group('fail-closed', () {
    test('upload falho não avança para FINALIZE nem ISSUE', () async {
      final h = build();
      h.uploader.failure = const HealthRestrictionFlowIntegrity(
        HealthRestrictionFlowStep.documentUpload,
      );
      expect(
        await h.controller.submit(
          evidence: evidenceIntent(),
          restriction: restrictionIntent(),
        ),
        isFalse,
      );

      expect(h.recorder.calls, ['prepare', 'upload']);
      expect(h.doc.finalizeCount, 0);
      expect(h.issue.count, 0);
      expect(h.controller.failure, isA<HealthRestrictionFlowIntegrity>());
    });

    test('PREPARE falho não faz upload', () async {
      final h = build();
      h.doc.prepareFailure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.documentPrepare,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      expect(h.recorder.calls, ['prepare']);
      expect(h.uploader.count, 0);
    });

    test('falha preserva a etapa para a UI', () async {
      final h = build();
      h.issue.failure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      expect(
        h.controller.failure!.step,
        HealthRestrictionFlowStep.restrictionIssue,
      );
      expect(h.controller.failure!.message, contains('autorização'));
    });

    test('submit concorrente é bloqueado', () async {
      final h = build();
      final a = h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final b = h.controller.submit(
        evidence: evidenceIntent(),
        restriction: restrictionIntent(),
      );
      final results = await Future.wait([a, b]);
      expect(results.where((r) => r).length, 1, reason: 'um único submit corre');
      expect(h.doc.prepareCount, 1);
    });
  });
}
