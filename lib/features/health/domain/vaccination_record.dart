import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VaccinationRecord — 13º agregado canônico (Domain Model §7; Schema §2.13).
// Obrigatórios: vaccine_name, applied_at, recorded_by, record_status,
// schema_version. `dose` é string opcional — não há VaccinationDose.
// Transição: final → cancelled com cancelled_at/by/reason.
// ─────────────────────────────────────────────────────────────────────────────

final class VaccinationRecord {
  VaccinationRecord({
    required this.id,
    required this.dogId,
    required String vaccineName,
    required this.appliedAt,
    required this.recordedBy,
    required this.recordStatus,
    required this.schemaVersion,
    this.vaccineType,
    String? manufacturer,
    String? batchNumber,
    String? dose,
    this.administeredBy,
    this.nextDueAt,
    this.validityUntil,
    this.caseId,
    this.professional,
    this.sourceDocument,
    String? notes,
    this.cancelledAt,
    this.cancelledBy,
    String? cancelReason,
  }) : vaccineName = _requireTrimmed(vaccineName, 'vaccine_name'),
       manufacturer = manufacturer?.trim(),
       batchNumber = batchNumber?.trim(),
       dose = dose?.trim(),
       notes = notes?.trim(),
       cancelReason = cancelReason?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (validityUntil != null && validityUntil!.isBefore(appliedAt)) {
      throw const HealthDomainException(
        'inconsistent_validity',
        'validity_until não pode ser anterior a applied_at',
      );
    }
    if (nextDueAt != null && nextDueAt!.isBefore(appliedAt)) {
      throw const HealthDomainException(
        'inconsistent_next_due',
        'next_due_at não pode ser anterior a applied_at',
      );
    }

    final cancelAny =
        cancelledAt != null || cancelledBy != null || this.cancelReason != null;
    final cancelAll =
        cancelledAt != null &&
        cancelledBy != null &&
        this.cancelReason != null &&
        this.cancelReason!.isNotEmpty;

    if (recordStatus == VaccinationStatus.cancelled) {
      if (!cancelAll) {
        throw const HealthDomainException(
          'missing_cancellation_metadata',
          'cancelled exige cancelled_at, cancelled_by e cancel_reason',
        );
      }
    } else if (cancelAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'registro final não pode ter metadados de cancelamento',
      );
    }
  }

  static String _requireTrimmed(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw HealthDomainException(
        'missing_${field.toLowerCase()}',
        '$field é obrigatório',
      );
    }
    return trimmed;
  }

  final String id;
  final String dogId;
  final String vaccineName;
  final DateTime appliedAt;
  final RecordedBy recordedBy;
  final VaccinationStatus recordStatus;
  final int schemaVersion;
  final String? vaccineType;
  final String? manufacturer;
  final String? batchNumber;

  /// Apresentação textual da dose (Schema §2.13: string opcional).
  final String? dose;
  final RecordedBy? administeredBy;
  final DateTime? nextDueAt;
  final DateTime? validityUntil;
  final String? caseId;
  final ProfessionalIdentity? professional;
  final HealthDocumentRef? sourceDocument;
  final String? notes;
  final DateTime? cancelledAt;
  final RecordedBy? cancelledBy;
  final String? cancelReason;
}
