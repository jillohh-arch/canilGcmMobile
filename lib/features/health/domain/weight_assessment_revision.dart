import 'health_v1_enums.dart';
import 'health_v1_models.dart' show HealthDomainException;
import 'weight_assessment.dart';

final class WeightAssessmentRevision {
  WeightAssessmentRevision({
    required String entityId,
    required this.revisionNumber,
    required this.revisionSchemaVersion,
    required this.operationType,
    required this.before,
    required this.after,
    required this.operationActor,
    required this.serverTimestamp,
    required String operationId,
    required String receiptReference,
    String? justification,
    this.correctionReason,
    this.invalidationReason,
  }) : entityId = _required(entityId, 'entity_id'),
       operationId = _required(operationId, 'operation_id'),
       receiptReference = _required(receiptReference, 'receipt_reference'),
       justification = _optional(justification) {
    if (revisionSchemaVersion != 1) {
      throw const HealthDomainException(
        'unsupported_weight_revision_schema',
        'revision_schema_version suportada é 1',
      );
    }
    if (revisionNumber < 1) {
      throw const HealthDomainException(
        'invalid_weight_revision_number',
        'revision_number deve ser positivo',
      );
    }
    if (after.entityId != this.entityId ||
        (before != null && before!.entityId != this.entityId)) {
      throw const HealthDomainException(
        'weight_revision_entity_mismatch',
        'before/after devem pertencer ao mesmo WeightAssessment',
      );
    }
    if (after.schemaVersion != 2 ||
        (before != null && before!.schemaVersion != 2)) {
      throw const HealthDomainException(
        'invalid_weight_revision_snapshot_schema',
        'Revisions pertencem ao aggregate target schema v2',
      );
    }
    if (after.revision != revisionNumber) {
      throw const HealthDomainException(
        'weight_revision_counter_mismatch',
        'after.revision deve coincidir com revision_number',
      );
    }
    final isCreate =
        operationType == WeightAssessmentOperationType.createQuick ||
        operationType == WeightAssessmentOperationType.createOfficial;
    if (isCreate != (before == null)) {
      throw const HealthDomainException(
        'invalid_weight_revision_snapshots',
        'Create não possui before; demais operações exigem before',
      );
    }
    if (isCreate && revisionNumber != 1) {
      throw const HealthDomainException(
        'invalid_weight_create_revision',
        'Create deve produzir revision 1',
      );
    }
    if (before != null && revisionNumber != before!.revision + 1) {
      throw const HealthDomainException(
        'invalid_weight_revision_increment',
        'Operações posteriores devem incrementar exatamente uma revision',
      );
    }
    if (before != null && before!.recorder != after.recorder) {
      throw const HealthDomainException(
        'weight_original_recorder_changed',
        'recorded_by original deve permanecer imutável',
      );
    }
    if (operationType == WeightAssessmentOperationType.correct &&
        (correctionReason == null || correctionReason!.isAbsent)) {
      throw const HealthDomainException(
        'missing_weight_correction_reason',
        'Correção exige correction_reason',
      );
    }
    if (operationType == WeightAssessmentOperationType.invalidate &&
        (invalidationReason == null || invalidationReason!.isAbsent)) {
      throw const HealthDomainException(
        'missing_weight_invalidation_reason',
        'Invalidação exige invalidation_reason',
      );
    }
  }

  final String entityId;
  final int revisionNumber;
  final int revisionSchemaVersion;
  final WeightAssessmentOperationType operationType;
  final WeightAssessment? before;
  final WeightAssessment after;
  final WeightRecorder operationActor;
  final DateTime serverTimestamp;
  final String operationId;
  final String receiptReference;
  final String? justification;
  final ParsedHealthEnum<WeightCorrectionReason>? correctionReason;
  final ParsedHealthEnum<WeightInvalidationReason>? invalidationReason;
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw HealthDomainException('missing_$field', '$field é obrigatório');
  }
  return normalized;
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
