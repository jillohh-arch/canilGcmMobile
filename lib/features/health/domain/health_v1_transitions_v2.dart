import 'health_v1_enums.dart';
import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';

import 'dose_administration.dart';
import 'exam_process.dart';
import 'health_schedule_item.dart';
import 'operational_restriction.dart';
import 'treatment_protocol.dart';
import 'vaccination_record.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Máquinas de estado puras para os novos agregados da Fase 1C.
// Cada máquina declara sua matriz de transições permitidas como constante
// estática, rejeita transições proibidas e exige metadados documentados.
// Sem persistência, sem clock global, sem side-effects.
// ─────────────────────────────────────────────────────────────────────────────

/// Transições do ciclo de vida de um ExamProcess (Domain Model §2.3).
abstract final class ExamProcessTransitions {
  static const Map<ExamStage, Set<ExamStage>> _allowed = {
    ExamStage.requested: {ExamStage.collected, ExamStage.cancelled},
    ExamStage.collected: {ExamStage.resulted, ExamStage.cancelled},
    ExamStage.resulted: {ExamStage.interpreted, ExamStage.cancelled},
    ExamStage.interpreted: {ExamStage.impactAssessed, ExamStage.cancelled},
    ExamStage.impactAssessed: {},
    ExamStage.cancelled: {},
  };

  static bool canTransition(ExamStage from, ExamStage to) =>
      _allowed[from]?.contains(to) ?? false;

  static ExamProcess transition(
    ExamProcess current,
    ExamStage destination, {
    DateTime? occurredAt,
    RecordedBy? occurredBy,
    String? stageReason,
  }) {
    if (!canTransition(current.stage, destination)) {
      throw HealthDomainException(
        'invalid_exam_transition',
        'Transição ${current.stage.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == ExamStage.cancelled) {
      if (stageReason == null || stageReason.trim().isEmpty) {
        throw const HealthDomainException(
          'missing_cancel_reason',
          'cancel_reason é obrigatório para cancelar exame',
        );
      }
      if (occurredAt == null || occurredBy == null) {
        throw const HealthDomainException(
          'missing_cancellation_metadata',
          'cancelamento exige instante e autoria',
        );
      }
    }
    // Recriar ExamProcess com novo estágio e metadados mínimos.
    return ExamProcess(
      id: current.id,
      caseId: current.caseId,
      dogId: current.dogId,
      examType: current.examType,
      stage: destination,
      urgency: current.urgency,
      title: current.title,
      createdAt: current.createdAt,
      recordedBy: current.recordedBy,
      schemaVersion: current.schemaVersion,
      requestedAt: current.requestedAt,
      requestedBy: current.requestedBy,
      requestProfessional: current.requestProfessional,
      requestReason: current.requestReason,
      labName: current.labName,
      collectedAt: destination == ExamStage.collected
          ? occurredAt
          : current.collectedAt,
      collectedBy: destination == ExamStage.collected
          ? occurredBy
          : current.collectedBy,
      collectionSite: current.collectionSite,
      collectionNotes: stageReason != null && destination == ExamStage.collected
          ? stageReason
          : current.collectionNotes,
      resultedAt: destination == ExamStage.resulted
          ? occurredAt
          : current.resultedAt,
      resultReceivedBy: destination == ExamStage.resulted
          ? occurredBy
          : current.resultReceivedBy,
      resultDocument: current.resultDocument,
      resultSummary: current.resultSummary,
      interpretedAt: destination == ExamStage.interpreted
          ? occurredAt
          : current.interpretedAt,
      interpretedBy: destination == ExamStage.interpreted
          ? occurredBy
          : current.interpretedBy,
      interpretationProfessional: current.interpretationProfessional,
      interpretationText: current.interpretationText,
      interpretationDocument: current.interpretationDocument,
      impactAssessedAt: destination == ExamStage.impactAssessed
          ? occurredAt
          : current.impactAssessedAt,
      impactAssessedBy: destination == ExamStage.impactAssessed
          ? occurredBy
          : current.impactAssessedBy,
      operationalImpact: current.operationalImpact,
      cancelledAt: destination == ExamStage.cancelled
          ? occurredAt
          : current.cancelledAt,
      cancelledBy: destination == ExamStage.cancelled
          ? occurredBy
          : current.cancelledBy,
      cancelReason: destination == ExamStage.cancelled
          ? stageReason
          : current.cancelReason,
    );
  }
}

/// Transições do TreatmentProtocol (Domain Model §2.4).
abstract final class TreatmentProtocolTransitions {
  static const Map<TreatmentStatus, Set<TreatmentStatus>> _allowed = {
    TreatmentStatus.active: {
      TreatmentStatus.paused,
      TreatmentStatus.completed,
      TreatmentStatus.cancelled,
    },
    TreatmentStatus.paused: {TreatmentStatus.active, TreatmentStatus.cancelled},
    TreatmentStatus.completed: {},
    TreatmentStatus.cancelled: {},
  };

  static bool canTransition(TreatmentStatus from, TreatmentStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  static TreatmentProtocol transition(
    TreatmentProtocol current,
    TreatmentStatus destination, {
    DateTime? pausedAt,
    String? pauseReason,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
  }) {
    if (!canTransition(current.status, destination)) {
      throw HealthDomainException(
        'invalid_treatment_transition',
        'Transição ${current.status.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == TreatmentStatus.paused &&
        (pauseReason == null || pauseReason.trim().isEmpty)) {
      throw const HealthDomainException(
        'missing_pause_reason',
        'pause_reason é obrigatório para pausar protocolo',
      );
    }
    if (destination == TreatmentStatus.cancelled &&
        (cancelReason == null || cancelReason.trim().isEmpty)) {
      throw const HealthDomainException(
        'missing_cancel_reason',
        'cancel_reason é obrigatório para cancelar protocolo',
      );
    }
    return TreatmentProtocol(
      id: current.id,
      dogId: current.dogId,
      caseId: current.caseId,
      medicationName: current.medicationName,
      dose: current.dose,
      schedule: current.schedule,
      startDate: current.startDate,
      recordedBy: current.recordedBy,
      professional: current.professional,
      sourceDocument: current.sourceDocument,
      status: destination,
      schemaVersion: current.schemaVersion,
      instructions: current.instructions,
      endDate: current.endDate,
      durationDays: current.durationDays,
      dosageDisplay: current.dosageDisplay,
      frequencyDisplay: current.frequencyDisplay,
      pausedAt: destination == TreatmentStatus.paused ? pausedAt : null,
      pauseReason: destination == TreatmentStatus.paused ? pauseReason : null,
      completedAt: destination == TreatmentStatus.completed
          ? completedAt
          : current.completedAt,
      cancelledAt: destination == TreatmentStatus.cancelled
          ? cancelledAt
          : current.cancelledAt,
      cancelReason: destination == TreatmentStatus.cancelled
          ? cancelReason
          : current.cancelReason,
    );
  }
}

/// Transições do OperationalRestriction (Domain Model §2.11).
abstract final class OperationalRestrictionTransitions {
  static const Map<RestrictionStatus, Set<RestrictionStatus>> _allowed = {
    RestrictionStatus.active: {
      RestrictionStatus.ended,
      RestrictionStatus.cancelled,
    },
    RestrictionStatus.ended: {},
    RestrictionStatus.cancelled: {},
  };

  static bool canTransition(RestrictionStatus from, RestrictionStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  static OperationalRestriction transition(
    OperationalRestriction current,
    RestrictionStatus destination, {
    DateTime? actualEnd,
    RecordedBy? endedBy,
    String? endReason,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) {
    if (!canTransition(current.status, destination)) {
      throw HealthDomainException(
        'invalid_restriction_transition',
        'Transição ${current.status.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == RestrictionStatus.ended &&
        (actualEnd == null || endedBy == null || endReason == null)) {
      throw const HealthDomainException(
        'missing_ending_metadata',
        'encerramento exige actual_end, ended_by e end_reason',
      );
    }
    if (destination == RestrictionStatus.cancelled &&
        (cancelledAt == null || cancelledBy == null || cancelReason == null)) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelamento exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    return OperationalRestriction(
      id: current.id,
      dogId: current.dogId,
      level: current.level,
      category: current.category,
      description: current.description,
      issuedAt: current.issuedAt,
      recordedBy: current.recordedBy,
      professional: current.professional,
      sourceDocument: current.sourceDocument,
      status: destination,
      schemaVersion: current.schemaVersion,
      activitiesRestricted: current.activitiesRestricted,
      expectedEnd: current.expectedEnd,
      actualEnd: destination == RestrictionStatus.ended
          ? actualEnd
          : current.actualEnd,
      endedBy: destination == RestrictionStatus.ended
          ? endedBy
          : current.endedBy,
      endReason: destination == RestrictionStatus.ended
          ? endReason
          : current.endReason,
      evidence: current.evidence,
      caseId: current.caseId,
      eventId: current.eventId,
      examId: current.examId,
    );
  }
}

/// Transições do HealthScheduleItem (Domain Model §2.12 e ADR-004 §13).
abstract final class HealthScheduleItemTransitions {
  static const Map<ScheduleLifecycleStatus, Set<ScheduleLifecycleStatus>>
  _allowed = {
    ScheduleLifecycleStatus.open: {
      ScheduleLifecycleStatus.completed,
      ScheduleLifecycleStatus.cancelled,
    },
    ScheduleLifecycleStatus.completed: {},
    ScheduleLifecycleStatus.cancelled: {},
  };

  static bool canTransition(
    ScheduleLifecycleStatus from,
    ScheduleLifecycleStatus to,
  ) => _allowed[from]?.contains(to) ?? false;

  static HealthScheduleItem transition(
    HealthScheduleItem current,
    ScheduleLifecycleStatus destination, {
    DateTime? completedAt,
    RecordedBy? completedBy,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) {
    if (!canTransition(current.lifecycleStatus, destination)) {
      throw HealthDomainException(
        'invalid_schedule_transition',
        'Transição ${current.lifecycleStatus.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == ScheduleLifecycleStatus.completed &&
        (completedAt == null || completedBy == null)) {
      throw const HealthDomainException(
        'missing_completion_metadata',
        'conclusão exige completed_at e completed_by',
      );
    }
    if (destination == ScheduleLifecycleStatus.cancelled &&
        (cancelledAt == null ||
            cancelledBy == null ||
            cancelReason == null ||
            cancelReason.trim().isEmpty)) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelamento exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    return HealthScheduleItem(
      id: current.id,
      dogId: current.dogId,
      scheduleType: current.scheduleType,
      title: current.title,
      scheduledFor: current.scheduledFor,
      timezone: current.timezone,
      lifecycleStatus: destination,
      sourceType: current.sourceType,
      createdAt: current.createdAt,
      recordedBy: current.recordedBy,
      schemaVersion: current.schemaVersion,
      dueUntil: current.dueUntil,
      completedAt: destination == ScheduleLifecycleStatus.completed
          ? completedAt
          : current.completedAt,
      completedBy: destination == ScheduleLifecycleStatus.completed
          ? completedBy
          : current.completedBy,
      cancelledAt: destination == ScheduleLifecycleStatus.cancelled
          ? cancelledAt
          : current.cancelledAt,
      cancelledBy: destination == ScheduleLifecycleStatus.cancelled
          ? cancelledBy
          : current.cancelledBy,
      cancelReason: destination == ScheduleLifecycleStatus.cancelled
          ? cancelReason
          : current.cancelReason,
      sourceId: current.sourceId,
      caseId: current.caseId,
      notes: current.notes,
      recurrenceRule: current.recurrenceRule,
      assignedToUid: current.assignedToUid,
      assignedToName: current.assignedToName,
    );
  }
}

/// DoseAdministration não possui máquina de estado — Domain Model §2.5
/// afirma que criação é direta no estado final. Esta classe existe apenas
/// para documentar o invariante e expor a identidade determinística.
abstract final class DoseAdministrationTransitions {
  /// Cria uma dose validando o invariante de identidade (DoseIdentity estável).
  static DoseAdministration create({
    required String protocolId,
    required String plannedDoseId,
    required String dogId,
    required DateTime scheduledFor,
    required DoseStatus status,
    required RecordedBy recordedBy,
    required DateTime recordedAt,
    required int schemaVersion,
    DateTime? administeredAt,
    RecordedBy? administeredBy,
    String? skipReason,
    String? observations,
    List<String> attachmentRefs = const [],
    String? scheduleItemId,
  }) {
    final identity = DoseIdentity(
      protocolId: protocolId,
      plannedDoseId: plannedDoseId,
    );
    return DoseAdministration(
      identity: identity,
      protocolId: protocolId,
      dogId: dogId,
      scheduledFor: scheduledFor,
      status: status,
      recordedBy: recordedBy,
      recordedAt: recordedAt,
      schemaVersion: schemaVersion,
      administeredAt: administeredAt,
      administeredBy: administeredBy,
      skipReason: skipReason,
      observations: observations,
      attachmentRefs: attachmentRefs,
      scheduleItemId: scheduleItemId,
    );
  }

  static bool canTransition(DoseStatus from, DoseStatus to) => false;
}

/// Transições de VaccinationRecord (Domain Model §7; Schema §2.13).
/// Única transição persistida: `final → cancelled` com metadados obrigatórios.
abstract final class VaccinationRecordTransitions {
  static const Map<VaccinationStatus, Set<VaccinationStatus>> _allowed = {
    VaccinationStatus.finalised: {VaccinationStatus.cancelled},
    VaccinationStatus.cancelled: {},
  };

  static bool canTransition(VaccinationStatus from, VaccinationStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  static VaccinationRecord transition(
    VaccinationRecord current,
    VaccinationStatus destination, {
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) {
    if (!canTransition(current.recordStatus, destination)) {
      throw HealthDomainException(
        'invalid_vaccination_transition',
        'Transição ${current.recordStatus.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == VaccinationStatus.cancelled &&
        (cancelledAt == null ||
            cancelledBy == null ||
            cancelReason == null ||
            cancelReason.trim().isEmpty)) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelamento exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    return VaccinationRecord(
      id: current.id,
      dogId: current.dogId,
      vaccineName: current.vaccineName,
      appliedAt: current.appliedAt,
      recordedBy: current.recordedBy,
      recordStatus: destination,
      schemaVersion: current.schemaVersion,
      vaccineType: current.vaccineType,
      manufacturer: current.manufacturer,
      batchNumber: current.batchNumber,
      dose: current.dose,
      administeredBy: current.administeredBy,
      nextDueAt: current.nextDueAt,
      validityUntil: current.validityUntil,
      caseId: current.caseId,
      professional: current.professional,
      sourceDocument: current.sourceDocument,
      notes: current.notes,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancelReason: cancelReason,
    );
  }
}
