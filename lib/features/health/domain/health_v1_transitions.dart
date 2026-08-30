import 'health_v1_enums.dart';
import 'health_v1_models.dart';

final class ClinicalCaseReopenEventData {
  const ClinicalCaseReopenEventData({
    required this.reason,
    required this.destination,
    required this.occurredAt,
    required this.recordedBy,
  });

  final String reason;
  final ClinicalCaseStatus destination;
  final DateTime occurredAt;
  final RecordedBy recordedBy;
}

final class ClinicalCaseReopenResult {
  const ClinicalCaseReopenResult({
    required this.clinicalCase,
    required this.event,
  });

  final ClinicalCase clinicalCase;
  final ClinicalCaseReopenEventData event;
}

abstract final class ClinicalCaseTransitions {
  static const _normalTransitions =
      <ClinicalCaseStatus, Set<ClinicalCaseStatus>>{
        ClinicalCaseStatus.open: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.underInvestigation: {
          ClinicalCaseStatus.open,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.underTreatment: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.monitoring: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.discharged: {},
        ClinicalCaseStatus.cancelled: {},
      };

  static const reopenDestinations = {
    ClinicalCaseStatus.open,
    ClinicalCaseStatus.underInvestigation,
    ClinicalCaseStatus.underTreatment,
    ClinicalCaseStatus.monitoring,
  };

  static ClinicalCase transition(
    ClinicalCase current,
    ClinicalCaseStatus destination,
  ) {
    if (!(_normalTransitions[current.status]?.contains(destination) ?? false)) {
      throw HealthDomainException(
        'invalid_case_transition',
        'Transição ${current.status.wireName} → ${destination.wireName} não permitida',
      );
    }
    return current.copyWith(status: destination);
  }

  static ClinicalCaseReopenResult reopen(
    ClinicalCase current, {
    required ClinicalCaseStatus destination,
    required String reason,
    required RecordedBy reopenedBy,
    required DateTime reopenedAt,
  }) {
    if (current.status != ClinicalCaseStatus.discharged ||
        !reopenDestinations.contains(destination)) {
      throw const HealthDomainException(
        'invalid_case_reopen',
        'Somente caso discharged pode ser reaberto para destino permitido',
      );
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const HealthDomainException(
        'missing_reopen_reason',
        'reopen_reason é obrigatório',
      );
    }
    final changed = current.copyWith(
      status: destination,
      reopenedAt: reopenedAt,
      reopenedBy: reopenedBy,
      previousStatus: current.status,
      reopenReason: normalizedReason,
      reopenedCount: current.reopenedCount + 1,
    );
    return ClinicalCaseReopenResult(
      clinicalCase: changed,
      event: ClinicalCaseReopenEventData(
        reason: normalizedReason,
        destination: destination,
        occurredAt: reopenedAt,
        recordedBy: reopenedBy,
      ),
    );
  }
}

abstract final class ClinicalEventTransitions {
  static const _allowedTransitions =
      <ClinicalEventStatus, Set<ClinicalEventStatus>>{
        ClinicalEventStatus.draft: {
          ClinicalEventStatus.finalised,
          ClinicalEventStatus.cancelled,
        },
        ClinicalEventStatus.finalised: {ClinicalEventStatus.cancelled},
        ClinicalEventStatus.cancelled: {},
      };

  static ClinicalEvent transition(
    ClinicalEvent current,
    ClinicalEventStatus destination, {
    String? cancelReason,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
  }) {
    if (!(_allowedTransitions[current.status]?.contains(destination) ??
        false)) {
      throw HealthDomainException(
        'invalid_event_transition',
        'Transição ${current.status.wireName} → ${destination.wireName} não permitida',
      );
    }
    if (destination == ClinicalEventStatus.cancelled) {
      if (cancelReason == null || cancelReason.trim().isEmpty) {
        throw const HealthDomainException(
          'missing_cancel_reason',
          'cancel_reason é obrigatório',
        );
      }
      if (cancelledAt == null || cancelledBy == null) {
        throw const HealthDomainException(
          'missing_cancellation_metadata',
          'Cancelamento exige instante e autoria',
        );
      }
      return current.copyWith(
        status: destination,
        cancelReason: cancelReason.trim(),
        cancelledAt: cancelledAt,
        cancelledBy: cancelledBy,
      );
    }
    if (cancelReason != null || cancelledAt != null || cancelledBy != null) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'Metadados de cancelamento só são aceitos ao cancelar',
      );
    }
    return current.copyWith(status: destination);
  }
}
