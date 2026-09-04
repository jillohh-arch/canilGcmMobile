import 'exam_process.dart';
import 'health_v1_enums_ext.dart';
import 'health_v1_value_objects.dart';

/// Comandos fortemente tipados para cada transição do ciclo de vida de ExamProcess.
/// Cada comando exige os metadados necessários e um operationId determinístico
/// para idempotência no backend.

final class RequestExamCommand {
  const RequestExamCommand({
    required this.dogId,
    required this.caseId,
    required this.title,
    required this.examType,
    this.urgency = ExamUrgency.routine,
    this.labName,
    this.requestReason,
    this.professional,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String title;
  final ExamType examType;
  final ExamUrgency urgency;
  final String? labName;
  final String? requestReason;
  final ProfessionalIdentity? professional;
  final String operationId;
}

final class RecordExamCollectionCommand {
  const RecordExamCollectionCommand({
    required this.dogId,
    required this.caseId,
    required this.examId,
    required this.collectedAt,
    this.collectionSite,
    this.collectionNotes,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String examId;
  final DateTime collectedAt;
  final String? collectionSite;
  final String? collectionNotes;
  final String operationId;
}

final class RecordExamResultCommand {
  const RecordExamResultCommand({
    required this.dogId,
    required this.caseId,
    required this.examId,
    required this.resultedAt,
    required this.resultSummary,
    this.resultDocumentId,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String examId;
  final DateTime resultedAt;
  final String resultSummary;
  final String? resultDocumentId;
  final String operationId;
}

final class RecordExamInterpretationCommand {
  const RecordExamInterpretationCommand({
    required this.dogId,
    required this.caseId,
    required this.examId,
    required this.interpretedAt,
    required this.interpretationText,
    required this.professional,
    this.interpretationDocumentId,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String examId;
  final DateTime interpretedAt;
  final String interpretationText;
  final ProfessionalIdentity professional;
  final String? interpretationDocumentId;
  final String operationId;
}

final class AssessExamImpactCommand {
  const AssessExamImpactCommand({
    required this.dogId,
    required this.caseId,
    required this.examId,
    required this.impactAssessedAt,
    required this.operationalImpact,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String examId;
  final DateTime impactAssessedAt;
  final OperationalImpact operationalImpact;
  final String operationId;
}

final class CancelExamCommand {
  const CancelExamCommand({
    required this.dogId,
    required this.caseId,
    required this.examId,
    required this.cancelReason,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String examId;
  final String cancelReason;
  final String operationId;
}
