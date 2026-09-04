import 'clinical_consultation_gateway.dart';
import 'exam_process.dart';
import 'exam_process_command.dart';

sealed class ExamProcessResult {
  const ExamProcessResult();
}

final class ExamProcessSuccess extends ExamProcessResult {
  const ExamProcessSuccess(this.exam);
  final ExamProcess exam;
}

final class ExamProcessFailure extends ExamProcessResult {
  const ExamProcessFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ExamProcessFailure($code: $message)';
}

abstract interface class ExamProcessGateway {
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId);

  Future<List<ExamProcess>> loadCaseExams({
    required String dogId,
    required String caseId,
  });

  Future<ExamProcessResult> requestExam(RequestExamCommand command);

  Future<ExamProcessResult> recordCollection(RecordExamCollectionCommand command);

  Future<ExamProcessResult> recordResult(RecordExamResultCommand command);

  Future<ExamProcessResult> recordInterpretation(
    RecordExamInterpretationCommand command,
  );

  Future<ExamProcessResult> assessImpact(AssessExamImpactCommand command);

  Future<ExamProcessResult> cancelExam(CancelExamCommand command);
}
