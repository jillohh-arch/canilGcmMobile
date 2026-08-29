import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TreatmentProtocol — protocolo de medicação/terapia (Domain Model §2.4).
// ─────────────────────────────────────────────────────────────────────────────

final class TreatmentProtocol {
  TreatmentProtocol({
    required this.id,
    required this.dogId,
    required this.caseId,
    required this.medicationName,
    required this.dose,
    required this.schedule,
    required this.startDate,
    required this.recordedBy,
    required this.professional,
    required this.sourceDocument,
    required TreatmentStatus status,
    required this.schemaVersion,
    String? instructions,
    this.endDate,
    this.durationDays,
    String? dosageDisplay,
    String? frequencyDisplay,
    this.pausedAt,
    String? pauseReason,
    this.completedAt,
    this.cancelledAt,
    String? cancelReason,
  }) : status = status,
       instructions = instructions?.trim(),
       dosageDisplay = dosageDisplay?.trim(),
       frequencyDisplay = frequencyDisplay?.trim(),
       pauseReason = pauseReason?.trim(),
       cancelReason = cancelReason?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (durationDays != null && durationDays! <= 0) {
      throw const HealthDomainException(
        'invalid_duration_days',
        'duration_days deve ser positivo',
      );
    }
    if (endDate != null && endDate!.isBefore(startDate)) {
      throw const HealthDomainException(
        'inconsistent_end_date',
        'end_date não pode ser anterior a start_date',
      );
    }
    if (status == TreatmentStatus.completed && completedAt == null) {
      throw const HealthDomainException(
        'missing_completion_metadata',
        'completed exige completed_at',
      );
    }
    if (status == TreatmentStatus.paused &&
        (pausedAt == null || pauseReason == null)) {
      throw const HealthDomainException(
        'missing_pause_metadata',
        'paused exige paused_at e pause_reason',
      );
    }
    final cancelAny = cancelledAt != null || cancelReason != null;
    final cancelAll = cancelledAt != null && cancelReason != null;
    if (cancelAny && !cancelAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'Metadados de cancelamento devem ser completos',
      );
    }
    if (status == TreatmentStatus.cancelled && !cancelAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelled exige cancelled_at e cancel_reason',
      );
    }
    if (status != TreatmentStatus.cancelled && cancelAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'protocolo não cancelado não pode ter metadados de cancelamento',
      );
    }
    if (status == TreatmentStatus.active &&
        (pausedAt != null || pauseReason != null || completedAt != null)) {
      throw const HealthDomainException(
        'inconsistent_active_state',
        'active não pode ter metadados paused/completed/cancelled',
      );
    }
  }

  final String id;
  final String dogId;
  final String caseId;
  final String medicationName;
  final DoseBlock dose;
  final ScheduleBlock schedule;
  final DateTime startDate;
  final RecordedBy recordedBy;
  final ProfessionalIdentity professional;
  final HealthDocumentRef sourceDocument;
  final TreatmentStatus status;
  final int schemaVersion;
  final String? instructions;
  final DateTime? endDate;
  final int? durationDays;
  final String? dosageDisplay;
  final String? frequencyDisplay;
  final DateTime? pausedAt;
  final String? pauseReason;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  @override
  bool operator ==(Object other) =>
      other is TreatmentProtocol &&
      other.id == id &&
      other.dogId == dogId &&
      other.caseId == caseId &&
      other.medicationName == medicationName &&
      other.dose == dose &&
      other.schedule == schedule &&
      other.startDate == startDate &&
      other.recordedBy == recordedBy &&
      other.professional == professional &&
      other.sourceDocument == sourceDocument &&
      other.status == status &&
      other.schemaVersion == schemaVersion &&
      other.instructions == instructions &&
      other.endDate == endDate &&
      other.durationDays == durationDays &&
      other.dosageDisplay == dosageDisplay &&
      other.frequencyDisplay == frequencyDisplay &&
      other.pausedAt == pausedAt &&
      other.pauseReason == pauseReason &&
      other.completedAt == completedAt &&
      other.cancelledAt == cancelledAt &&
      other.cancelReason == cancelReason;

  @override
  int get hashCode => Object.hashAll([
    id,
    dogId,
    caseId,
    medicationName,
    dose,
    schedule,
    startDate,
    recordedBy,
    professional,
    sourceDocument,
    status,
    schemaVersion,
    instructions,
    endDate,
    durationDays,
    dosageDisplay,
    frequencyDisplay,
    pausedAt,
    pauseReason,
    completedAt,
    cancelledAt,
    cancelReason,
  ]);
}
