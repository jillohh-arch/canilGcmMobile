import 'health_v1_value_objects.dart';

/// Comandos fortemente tipados para operações do ciclo de vida de TreatmentProtocol e DoseAdministration.
/// Cada comando exige os metadados necessários e um operationId determinístico
/// para idempotência no backend.

final class CreateTreatmentProtocolCommand {
  const CreateTreatmentProtocolCommand({
    required this.dogId,
    required this.caseId,
    required this.medicationName,
    required this.dose,
    required this.schedule,
    required this.startDate,
    this.durationDays,
    this.endDate,
    required this.professional,
    required this.sourceDocument,
    this.instructions,
    this.dosageDisplay,
    this.frequencyDisplay,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String medicationName;
  final DoseBlock dose;
  final ScheduleBlock schedule;
  final DateTime startDate;
  final int? durationDays;
  final DateTime? endDate;
  final ProfessionalIdentity professional;
  final HealthDocumentRef sourceDocument;
  final String? instructions;
  final String? dosageDisplay;
  final String? frequencyDisplay;
  final String operationId;
}

final class PauseTreatmentProtocolCommand {
  const PauseTreatmentProtocolCommand({
    required this.dogId,
    required this.protocolId,
    required this.pauseReason,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String pauseReason;
  final String operationId;
}

final class ResumeTreatmentProtocolCommand {
  const ResumeTreatmentProtocolCommand({
    required this.dogId,
    required this.protocolId,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String operationId;
}

final class CompleteTreatmentProtocolCommand {
  const CompleteTreatmentProtocolCommand({
    required this.dogId,
    required this.protocolId,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String operationId;
}

final class CancelTreatmentProtocolCommand {
  const CancelTreatmentProtocolCommand({
    required this.dogId,
    required this.protocolId,
    required this.cancelReason,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String cancelReason;
  final String operationId;
}

final class AdministerDoseCommand {
  const AdministerDoseCommand({
    required this.dogId,
    required this.protocolId,
    required this.plannedDoseId,
    this.scheduleItemId,
    this.administeredAt,
    this.observations,
    this.sideEffects,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String plannedDoseId;
  final String? scheduleItemId;
  final DateTime? administeredAt;
  final String? observations;
  final String? sideEffects;
  final String operationId;
}

final class SkipDoseCommand {
  const SkipDoseCommand({
    required this.dogId,
    required this.protocolId,
    required this.plannedDoseId,
    required this.skipReason,
    this.scheduleItemId,
    this.observations,
    required this.operationId,
  });

  final String dogId;
  final String protocolId;
  final String plannedDoseId;
  final String skipReason;
  final String? scheduleItemId;
  final String? observations;
  final String operationId;
}
