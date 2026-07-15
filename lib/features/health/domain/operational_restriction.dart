import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OperationalRestriction — restrição clínica que afeta prontidão (Domain Model §2.11).
// ─────────────────────────────────────────────────────────────────────────────

final class OperationalRestriction {
  OperationalRestriction({
    required this.id,
    required this.dogId,
    required this.level,
    required this.category,
    required String description,
    required DateTime issuedAt,
    required this.recordedBy,
    required this.professional,
    required this.sourceDocument,
    required RestrictionStatus status,
    required this.schemaVersion,
    List<String>? activitiesRestricted,
    this.expectedEnd,
    this.actualEnd,
    this.endedBy,
    this.endProfessional,
    this.endSourceDocument,
    String? endReason,
    this.evidence,
    this.caseId,
    this.eventId,
    this.examId,
  }) : issuedAt = issuedAt,
       description = description.trim(),
       activitiesRestricted = List.unmodifiable(
         List<String>.of(activitiesRestricted ?? const []),
       ),
       endReason = endReason?.trim(),
       status = status {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (description.isEmpty) {
      throw const HealthDomainException(
        'missing_restriction_description',
        'description é obrigatória',
      );
    }
    if (actualEnd != null && actualEnd!.isBefore(issuedAt)) {
      throw const HealthDomainException(
        'inconsistent_actual_end',
        'actual_end não pode ser anterior a issued_at',
      );
    }
    final endMetadata = [actualEnd, endedBy, endReason];
    final endAny = endMetadata.any((v) => v != null);
    final endAll = endMetadata.every((v) => v != null);
    if (endAny && !endAll) {
      throw const HealthDomainException(
        'incomplete_ending_metadata',
        'Metadados de encerramento devem ser completos',
      );
    }
    if (status == RestrictionStatus.ended && !endAll) {
      throw const HealthDomainException(
        'missing_ending_metadata',
        'ended exige actual_end, ended_by e end_reason',
      );
    }
    if (status != RestrictionStatus.ended && endAny) {
      throw const HealthDomainException(
        'unexpected_ending_metadata',
        'restrição não encerrada não pode ter metadados de encerramento',
      );
    }
    if (status == RestrictionStatus.cancelled && endAny) {
      throw const HealthDomainException(
        'inconsistent_cancelled_state',
        'cancelled não pode coexistir com metadados de encerramento',
      );
    }
    final restrictions = List.unmodifiable(activitiesRestricted ?? const []);
    if (level == RestrictionLevel.partial && restrictions.isEmpty) {
      throw const HealthDomainException(
        'missing_activities_restricted',
        'partial exige activities_restricted não vazio',
      );
    }
  }

  final String id;
  final String dogId;
  final RestrictionLevel level;
  final RestrictionCategory category;
  final String description;
  final DateTime issuedAt;
  final RecordedBy recordedBy;
  final ProfessionalIdentity professional;
  final HealthDocumentRef sourceDocument;
  final RestrictionStatus status;
  final int schemaVersion;
  final List<String> activitiesRestricted;
  final DateTime? expectedEnd;
  final DateTime? actualEnd;
  final RecordedBy? endedBy;
  final ProfessionalIdentity? endProfessional;
  final HealthDocumentRef? endSourceDocument;
  final String? endReason;
  final RestrictionEvidence? evidence;
  final String? caseId;
  final String? eventId;
  final String? examId;

  /// `is_overdue` derivado (Domain Model §2.11). NÃO persistido.
  bool isOverdueAt(DateTime reference) =>
      status == RestrictionStatus.active &&
      expectedEnd != null &&
      reference.isAfter(expectedEnd!);
}
