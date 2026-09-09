import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart'
    show ClinicalCaseOption;
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_errors.dart';

sealed class IncidentSaveResult {
  const IncidentSaveResult();
}

final class IncidentOpenedCase extends IncidentSaveResult {
  const IncidentOpenedCase({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.wasNoOp,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String eventId;
  final bool wasNoOp;
  final String operationId;
}

final class IncidentAppendedToCase extends IncidentSaveResult {
  const IncidentAppendedToCase({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.wasNoOp,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String eventId;
  final bool wasNoOp;
  final String operationId;
}

final class IncidentPendingFinalization extends IncidentSaveResult {
  const IncidentPendingFinalization({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.finalizeOperationId,
    required this.expectedRevision,
    required this.openedNewCase,
    required this.failure,
  });

  final String dogId;
  final String caseId;
  final String eventId;
  final String finalizeOperationId;
  final int expectedRevision;
  final bool openedNewCase;
  final ClinicalIncidentFailure failure;
}

final class IncidentSaveFailure extends IncidentSaveResult {
  const IncidentSaveFailure(this.failure);

  final ClinicalIncidentFailure failure;
}

final class ClinicalIncidentRecordView {
  const ClinicalIncidentRecordView({
    required this.caseId,
    required this.eventId,
    required this.occurredAt,
    required this.category,
    required this.severity,
    required this.description,
    this.initialConduct,
    required this.statusWireName,
    required this.isFinal,
  });

  final String caseId;
  final String eventId;
  final DateTime occurredAt;
  final IncidentCategory category;
  final IncidentSeverity severity;
  final String description;
  final String? initialConduct;
  final String statusWireName;
  final bool isFinal;
}

abstract interface class ClinicalIncidentGateway {
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId);

  Future<IncidentSaveResult> saveIncident(ClinicalIncidentCommand command);

  Future<IncidentSaveResult> retryFinalization(
    IncidentPendingFinalization pending,
  );

  Future<List<ClinicalIncidentRecordView>> loadCaseIncidents({
    required String dogId,
    required String caseId,
  });
}
