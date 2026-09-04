import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/exam_process.dart';
import 'package:canil_gcm/features/health/domain/exam_process_command.dart';
import 'package:canil_gcm/features/health/domain/exam_process_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/presentation/clinical/exam_process_flow_screen.dart';

class MockExamProcessGateway implements ExamProcessGateway {
  List<ClinicalCaseOption> casesToReturn = [];
  List<ExamProcess> examsToReturn = [];

  List<dynamic> recordedCommands = [];

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    return casesToReturn;
  }

  @override
  Future<List<ExamProcess>> loadCaseExams({
    required String dogId,
    required String caseId,
  }) async {
    return examsToReturn;
  }

  @override
  Future<ExamProcessResult> requestExam(RequestExamCommand command) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: 'exam-req-1',
      caseId: command.caseId,
      dogId: command.dogId,
      examType: command.examType,
      stage: ExamStage.requested,
      title: command.title,
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
    );
    return ExamProcessSuccess(exam);
  }

  @override
  Future<ExamProcessResult> recordCollection(
    RecordExamCollectionCommand command,
  ) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: command.examId,
      caseId: command.caseId,
      dogId: command.dogId,
      examType: ExamType.bloodWork,
      stage: ExamStage.collected,
      title: 'Hemograma',
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
      collectedAt: command.collectedAt,
    );
    return ExamProcessSuccess(exam);
  }

  @override
  Future<ExamProcessResult> recordResult(RecordExamResultCommand command) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: command.examId,
      caseId: command.caseId,
      dogId: command.dogId,
      examType: ExamType.bloodWork,
      stage: ExamStage.resulted,
      title: 'Hemograma',
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
      collectedAt: DateTime.now(),
      resultedAt: command.resultedAt,
      resultSummary: command.resultSummary,
    );
    return ExamProcessSuccess(exam);
  }

  @override
  Future<ExamProcessResult> recordInterpretation(
    RecordExamInterpretationCommand command,
  ) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: command.examId,
      caseId: command.caseId,
      dogId: command.dogId,
      examType: ExamType.bloodWork,
      stage: ExamStage.interpreted,
      title: 'Hemograma',
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
      collectedAt: DateTime.now(),
      resultedAt: DateTime.now(),
      interpretedAt: command.interpretedAt,
      interpretationProfessional: command.professional,
      interpretationText: command.interpretationText,
    );
    return ExamProcessSuccess(exam);
  }

  @override
  Future<ExamProcessResult> assessImpact(AssessExamImpactCommand command) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: command.examId,
      caseId: command.caseId,
      dogId: command.dogId,
      examType: ExamType.bloodWork,
      stage: ExamStage.impactAssessed,
      title: 'Hemograma',
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
      collectedAt: DateTime.now(),
      resultedAt: DateTime.now(),
      interpretedAt: DateTime.now(),
      impactAssessedAt: command.impactAssessedAt,
      operationalImpact: command.operationalImpact,
    );
    return ExamProcessSuccess(exam);
  }

  @override
  Future<ExamProcessResult> cancelExam(CancelExamCommand command) async {
    recordedCommands.add(command);
    final exam = ExamProcess(
      id: command.examId,
      caseId: command.caseId,
      dogId: command.dogId,
      examType: ExamType.bloodWork,
      stage: ExamStage.cancelled,
      title: 'Hemograma',
      createdAt: DateTime.now(),
      recordedBy: RecordedBy(uid: 'u1', name: 'User 1', internalRole: 'condutor'),
      schemaVersion: 1,
      requestedAt: DateTime.now(),
      cancelledAt: DateTime.now(),
      cancelReason: command.cancelReason,
    );
    return ExamProcessSuccess(exam);
  }
}

void main() {
  group('ExamProcessFlowScreen Widget Tests', () {
    late MockExamProcessGateway mockGateway;

    setUp(() {
      mockGateway = MockExamProcessGateway();
    });

    testWidgets('exibe aviso quando o cão não tem casos utilizáveis',
        (tester) async {
      mockGateway.casesToReturn = [];

      await tester.pumpWidget(
        MaterialApp(
          home: ExamProcessFlowScreen(
            dogId: 'dog-1',
            gateway: mockGateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhum caso clínico ativo encontrado'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('seleciona caso único e renderiza exames existentes',
        (tester) async {
      mockGateway.casesToReturn = [
        const ClinicalCaseOption(
          caseId: 'case-alpha',
          title: 'Caso Claudicação',
          statusWireName: 'open',
          revision: 1,
        ),
      ];

      mockGateway.examsToReturn = [
        ExamProcess(
          id: 'exam-1',
          caseId: 'case-alpha',
          dogId: 'dog-1',
          examType: ExamType.imaging,
          stage: ExamStage.requested,
          title: 'Raio-X Membro Pélvico',
          createdAt: DateTime(2026, 9, 1),
          recordedBy: RecordedBy(
            uid: 'u1',
            name: 'Veterinário',
            internalRole: 'veterinario',
          ),
          schemaVersion: 1,
          requestedAt: DateTime(2026, 9, 1),
          requestReason: 'Suspeita de fratura ou luxação',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ExamProcessFlowScreen(
            dogId: 'dog-1',
            gateway: mockGateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Raio-X Membro Pélvico'), findsOneWidget);
      expect(find.text('Solicitado'), findsWidgets);
      expect(find.text('Registrar Coleta'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('exibe botão Registrar Resultado para exame coletado',
        (tester) async {
      mockGateway.casesToReturn = [
        const ClinicalCaseOption(
          caseId: 'case-alpha',
          title: 'Caso Claudicação',
          statusWireName: 'under_investigation',
          revision: 2,
        ),
      ];

      mockGateway.examsToReturn = [
        ExamProcess(
          id: 'exam-2',
          caseId: 'case-alpha',
          dogId: 'dog-1',
          examType: ExamType.bloodWork,
          stage: ExamStage.collected,
          title: 'Hemograma Completo',
          createdAt: DateTime(2026, 9, 2),
          recordedBy: RecordedBy(
            uid: 'u1',
            name: 'Veterinário',
            internalRole: 'veterinario',
          ),
          schemaVersion: 1,
          requestedAt: DateTime(2026, 9, 2),
          collectedAt: DateTime(2026, 9, 2, 14, 30),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ExamProcessFlowScreen(
            dogId: 'dog-1',
            gateway: mockGateway,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hemograma Completo'), findsOneWidget);
      expect(find.text('Coletado'), findsWidgets);
      expect(find.text('Registrar Resultado'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });
  });
}
