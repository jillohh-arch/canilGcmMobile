import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final measuredAt = DateTime.utc(2026, 8, 6, 10, 32);
  final recordedAt = DateTime.utc(2026, 8, 6, 10, 33);
  final recorder = WeightRecorder(
    uid: 'user-masked',
    name: 'Operator',
    internalRole: 'future_role',
  );

  WeightAssessment quick({
    int revision = 1,
    WeightRecorder? originalRecorder,
  }) => WeightAssessment.targetV2(
    entityId: 'weight-1',
    dogId: 'dog-1',
    weight: WeightKg(33.3),
    measuredAt: measuredAt,
    recordedAt: recordedAt,
    recorder: originalRecorder ?? recorder,
    recordType: WeightRecordTypeWire.parse('quick'),
    originRecordType: WeightRecordTypeWire.parse('quick'),
    status: WeightAssessmentStatusWire.parse('valid'),
    revision: revision,
    officialDetails: null,
  );

  group('WeightAssessment aggregate', () {
    test('API v1 anterior permanece disponível pelo barrel', () {
      final actor = RecordedBy(
        uid: 'user-masked',
        name: 'Operator',
        internalRole: 'condutor',
      );
      final assessment = WeightAssessment(
        id: 'weight-legacy',
        dogId: 'dog-1',
        weight: WeightKg(32.523),
        measuredAt: measuredAt,
        recordedBy: actor,
        schemaVersion: 1,
      );
      expect(assessment.id, 'weight-legacy');
      // ignore: deprecated_member_use_from_same_package
      expect(assessment.recordedBy, actor);
      expect(assessment.recordType.value, WeightRecordType.legacySimple);
    });

    test('target v2 exige décimos sem vulnerabilidade de arredondamento', () {
      expect(quick().weightKg, 33.3);
      expect(
        () => WeightAssessment.targetV2(
          entityId: 'weight-1',
          dogId: 'dog-1',
          weight: WeightKg(32.523),
          measuredAt: measuredAt,
          recordedAt: recordedAt,
          recorder: recorder,
          recordType: WeightRecordTypeWire.parse('quick'),
          originRecordType: WeightRecordTypeWire.parse('quick'),
          status: WeightAssessmentStatusWire.parse('valid'),
          revision: 1,
          officialDetails: null,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('legacy_simple não pode ser construído como target v2', () {
      expect(
        () => WeightRecordType.legacySimple.targetWireName,
        throwsStateError,
      );
      expect(
        () => WeightAssessment.targetV2(
          entityId: 'weight-1',
          dogId: 'dog-1',
          weight: WeightKg(33.3),
          measuredAt: measuredAt,
          recordedAt: recordedAt,
          recorder: recorder,
          recordType: WeightRecordTypeWire.parse('legacy_simple'),
          originRecordType: WeightRecordTypeWire.parse('legacy_simple'),
          status: WeightAssessmentStatusWire.parse('valid'),
          revision: 1,
          officialDetails: null,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('known/raw inconsistente não possui construtor público', () {
      final known = WeightRecordTypeWire.parse('quick');
      final unknown = WeightRecordTypeWire.parse('future_type');
      expect(known.value, WeightRecordType.quick);
      expect(known.raw, 'quick');
      expect(unknown.isUnknown, isTrue);
      expect(unknown.raw, 'future_type');
    });
  });

  group('WeightAssessmentRevision', () {
    test('revision schema 1 separa ator da autoria original', () {
      final revision = WeightAssessmentRevision(
        entityId: 'weight-1',
        revisionNumber: 1,
        revisionSchemaVersion: 1,
        operationType: WeightAssessmentOperationType.createQuick,
        before: null,
        after: quick(),
        operationActor: WeightRecorder(
          uid: 'operation-actor',
          name: 'Other Operator',
          internalRole: 'admin',
        ),
        serverTimestamp: recordedAt,
        operationId: 'operation-1',
        receiptReference: 'weight_operations/operation-1',
      );
      expect(revision.after.recorder, recorder);
      expect(revision.operationActor.uid, 'operation-actor');
    });

    test('correção exige before e reason', () {
      expect(
        () => WeightAssessmentRevision(
          entityId: 'weight-1',
          revisionNumber: 2,
          revisionSchemaVersion: 1,
          operationType: WeightAssessmentOperationType.correct,
          before: quick(),
          after: quick(revision: 2),
          operationActor: recorder,
          serverTimestamp: recordedAt,
          operationId: 'operation-2',
          receiptReference: 'weight_operations/operation-2',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('recorded_by original não pode ser substituído', () {
      final changedRecorder = WeightRecorder(
        uid: 'other',
        name: 'Other',
        internalRole: 'condutor',
      );
      expect(
        () => WeightAssessmentRevision(
          entityId: 'weight-1',
          revisionNumber: 2,
          revisionSchemaVersion: 1,
          operationType: WeightAssessmentOperationType.correct,
          before: quick(),
          after: quick(revision: 2, originalRecorder: changedRecorder),
          operationActor: changedRecorder,
          serverTimestamp: recordedAt,
          operationId: 'operation-2',
          receiptReference: 'weight_operations/operation-2',
          correctionReason: WeightCorrectionReasonWire.parse(
            'data_entry_error',
          ),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('operações de configuração e follow-up ficam em tipos separados', () {
      expect(
        WeightAssessmentOperationTypeWire.parse(
          'set_reference_range',
        ).isUnknown,
        isTrue,
      );
      expect(
        WeightAssessmentOperationTypeWire.parse('create_follow_up').isUnknown,
        isTrue,
      );
      expect(
        WeightConfigurationOperationType.setReferenceRange.wireName,
        'set_reference_range',
      );
      expect(
        WeightFollowUpOperationType.createFollowUp.wireName,
        'create_follow_up',
      );
    });
  });
}
