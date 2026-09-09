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
    required this.expectedCaseRevision,
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

  /// Precondição de concorrência OBRIGATÓRIA do ClinicalCase pai.
  ///
  /// Solicitar um exame pode transicionar o caso (`open → under_investigation`),
  /// e essa transição é executada pela autoridade de ciclo de vida do
  /// ClinicalCase. O chamador precisa declarar em qual revisão do caso acredita
  /// estar operando: o backend rejeita ausência com `invalid-argument` e
  /// divergência com `failed-precondition`.
  ///
  /// Deve vir da leitura real do caso. Nunca sintetize `1`, nunca reenvie com um
  /// valor atualizado após uma falha de OCC — uma rejeição de stale precisa
  /// chegar à interface para que o operador recarregue o prontuário.
  final int expectedCaseRevision;

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
