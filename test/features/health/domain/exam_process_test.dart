import 'package:canil_gcm/features/health/domain/exam_process.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final now = DateTime.utc(2026, 7, 14, 10);

  ExamProcess build({
    ExamStage stage = ExamStage.requested,
    DateTime? requestedAt,
    DateTime? collectedAt,
    DateTime? resultedAt,
    DateTime? interpretedAt,
    DateTime? impactAssessedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    RecordedBy? cancelledBy,
  }) => ExamProcess(
    id: 'exam-1',
    caseId: 'case-1',
    dogId: 'dog-1',
    examType: ExamType.bloodWork,
    stage: stage,
    urgency: ExamUrgency.routine,
    title: 'Hemograma',
    createdAt: now,
    recordedBy: actor,
    schemaVersion: 1,
    requestedAt: requestedAt,
    collectedAt: collectedAt,
    resultedAt: resultedAt,
    interpretedAt: interpretedAt,
    impactAssessedAt: impactAssessedAt,
    cancelledAt: cancelledAt,
    cancelReason: cancelReason,
    cancelledBy: cancelledBy,
  );

  group('ExamProcess', () {
    test('rejeita schema_version inválido', () {
      expect(
        () => ExamProcess(
          id: 'e',
          caseId: 'c',
          dogId: 'd',
          examType: ExamType.bloodWork,
          stage: ExamStage.requested,
          title: 't',
          createdAt: now,
          recordedBy: actor,
          schemaVersion: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita resultado sem coleta', () {
      expect(
        () => build(stage: ExamStage.resulted, resultedAt: now),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita interpretação sem texto', () {
      expect(
        () => build(
          stage: ExamStage.interpreted,
          resultedAt: now,
          interpretedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita impact_assessed sem operational_impact', () {
      expect(
        () => ExamProcess(
          id: 'e',
          caseId: 'c',
          dogId: 'd',
          examType: ExamType.bloodWork,
          stage: ExamStage.impactAssessed,
          title: 't',
          createdAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          resultedAt: now,
          interpretedAt: now,
          interpretationText: 'Texto',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita metadata de cancelamento incompleto', () {
      expect(
        () => build(stage: ExamStage.cancelled, cancelledAt: now),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('matriz completa de transições com origem/destino na mensagem', () {
      const expected = <ExamStage, Set<ExamStage>>{
        ExamStage.requested: {ExamStage.collected, ExamStage.cancelled},
        ExamStage.collected: {ExamStage.resulted, ExamStage.cancelled},
        ExamStage.resulted: {ExamStage.interpreted, ExamStage.cancelled},
        ExamStage.interpreted: {ExamStage.impactAssessed, ExamStage.cancelled},
        ExamStage.impactAssessed: {},
        ExamStage.cancelled: {},
      };
      for (final origin in ExamStage.values) {
        for (final destination in ExamStage.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          if (allowed) {
            expect(
              ExamProcessTransitions.canTransition(origin, destination),
              isTrue,
              reason: reason,
            );
          } else {
            expect(
              ExamProcessTransitions.canTransition(origin, destination),
              isFalse,
              reason: reason,
            );
          }
        }
      }
    });

    test('transição collect→result exige metadata', () {
      final exam = build(requestedAt: now);
      expect(
        () => ExamProcessTransitions.transition(exam, ExamStage.resulted),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('serialização e deserialização preservam todos os campos (round-trip)', () {
      final exam = build(
        requestedAt: now,
        collectedAt: now.add(const Duration(hours: 1)),
        resultedAt: now.add(const Duration(hours: 4)),
      );
      final map = exam.toMap();
      final restored = ExamProcess.fromMap(map);

      expect(restored.id, exam.id);
      expect(restored.caseId, exam.caseId);
      expect(restored.dogId, exam.dogId);
      expect(restored.title, exam.title);
      expect(restored.examType, exam.examType);
      expect(restored.stage, exam.stage);
      expect(restored.urgency, exam.urgency);
      expect(restored.requestedAt, exam.requestedAt);
      expect(restored.collectedAt, exam.collectedAt);
      expect(restored.resultedAt, exam.resultedAt);
    });
  });
}
