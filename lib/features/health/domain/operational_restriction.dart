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
    this.cancelledAt,
    this.cancelledBy,
    String? cancelReason,
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
       cancelReason = cancelReason?.trim(),
       status = status {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (this.description.isEmpty) {
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
    if (cancelledAt != null && cancelledAt!.isBefore(issuedAt)) {
      throw const HealthDomainException(
        'inconsistent_cancelled_at',
        'cancelled_at não pode ser anterior a issued_at',
      );
    }
    // Conjuntos terminais conforme o patch persistido pelo B2: END grava
    // `actual_end`, `ended_by`, `end_reason`, `end_professional` e
    // `end_source_document`; CANCEL grava `cancelled_at`, `cancelled_by` e
    // `cancel_reason`. Nenhum dos dois é parcial no backend, então um agregado
    // parcial só existe por corrupção — e é recusado.
    final endMetadata = [
      actualEnd,
      endedBy,
      this.endReason,
      endProfessional,
      endSourceDocument,
    ];
    final endAny = endMetadata.any((v) => v != null);
    final endAll = endMetadata.every((v) => v != null);
    final cancelMetadata = [cancelledAt, cancelledBy, this.cancelReason];
    final cancelAny = cancelMetadata.any((v) => v != null);
    final cancelAll = cancelMetadata.every((v) => v != null);
    if (endAny && !endAll) {
      throw const HealthDomainException(
        'incomplete_ending_metadata',
        'ended exige actual_end, ended_by, end_reason, end_professional e '
            'end_source_document',
      );
    }
    if (cancelAny && !cancelAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'cancelled exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    // Exclusividade terminal (backend: `assertNoTerminalMetadata`). Um agregado
    // com metadata dos dois lados seria um terminal híbrido sem significado
    // clínico — nunca é interpretado, é recusado.
    if (endAny && cancelAny) {
      throw const HealthDomainException(
        'hybrid_terminal_metadata',
        'metadados de encerramento e de cancelamento não podem coexistir',
      );
    }
    if (status == RestrictionStatus.ended && !endAll) {
      throw const HealthDomainException(
        'missing_ending_metadata',
        'ended exige actual_end, ended_by, end_reason, end_professional e '
            'end_source_document',
      );
    }
    if (status == RestrictionStatus.cancelled && !cancelAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelled exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    if (status != RestrictionStatus.ended && endAny) {
      throw const HealthDomainException(
        'unexpected_ending_metadata',
        'restrição não encerrada não pode ter metadados de encerramento',
      );
    }
    if (status != RestrictionStatus.cancelled && cancelAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'restrição não cancelada não pode ter metadados de cancelamento',
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

  /// Metadata de CANCEL (invalidação administrativa). NÃO afirma liberação
  /// clínica: por contrato do backend não carrega profissional nem documento.
  final DateTime? cancelledAt;
  final RecordedBy? cancelledBy;
  final String? cancelReason;
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
