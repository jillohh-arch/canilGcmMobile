import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/domain/exam_process.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
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

    test('parse do payload factual do exame fisico', () {
      final payload = <String, dynamic>{
        'exam_id': 'exam_ade5a7b2a922c5e8',
        'case_id': 'cc_94bf654056e135b5e077c71ed66c',
        'dog_id': 'stg-dog-nutrition-unlinked-001',
        'exam_type': 'blood_work',
        'current_stage': 'requested',
        'title': 'Hemograma teste de homologação',
        'urgency': 'routine',
        'created_at': '2026-09-05T00:58:49.028Z',
        'requested_at': '2026-09-05T00:58:49.028Z',
        'recorded_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'requested_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'schema_version': 1,
        'revision': 1,
        'lab_name': 'lab previsto homologação',
        'request_reason': 'sem justificativa',
      };

      final parsed = ExamProcess.fromMap(payload);
      expect(parsed.id, 'exam_ade5a7b2a922c5e8');
      expect(parsed.title, 'Hemograma teste de homologação');
      expect(parsed.stage, ExamStage.requested);
      expect(parsed.examType, ExamType.bloodWork);
      expect(parsed.urgency, ExamUrgency.routine);
      expect(parsed.labName, 'lab previsto homologação');
      expect(parsed.requestReason, 'sem justificativa');
    });

    test('parse do payload factual do exame historico com Timestamps', () {
      final payload = <String, dynamic>{
        'exam_id': 'exam_248862333f8057af',
        'case_id': 'cc_94bf654056e135b5e077c71ed66c',
        'dog_id': 'stg-dog-nutrition-unlinked-001',
        'exam_type': 'blood_work',
        'title': 'Hemograma - Homologação EXAM-V1',
        'urgency': 'routine',
        'created_at': Timestamp.fromMillisecondsSinceEpoch(1788552207554),
        'requested_at': Timestamp.fromMillisecondsSinceEpoch(1788552207554),
        'recorded_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'requested_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'schema_version': 1,
        'collection_notes': 'Coleta estéril de sangue venoso cefálico.',
        'collected_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'collection_site': 'Clínica Veterinária Central',
        'collected_at': Timestamp.fromMillisecondsSinceEpoch(1788562801792),
        'result_summary': 'Hemograma completo com contagem de plaquetas e leucograma dentro dos parâmetros normais da espécie.',
        'result_received_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'resulted_at': Timestamp.fromMillisecondsSinceEpoch(1788562817993),
        'interpretation_professional': {
          'name': 'Dr. Homologador Veterinário',
          'registrationNumber': 'CRMV-SP 12345',
          'registrationType': 'crmv',
          'clinic': 'Clínica Veterinária Central',
        },
        'interpreted_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'interpreted_at': Timestamp.fromMillisecondsSinceEpoch(1788562835189),
        'interpretation_text': 'Exame hematológico compatível com higidez clínica, sem sinais de anemia ou infecção ativa.',
        'impact_assessed_at': Timestamp.fromMillisecondsSinceEpoch(1788562851563),
        'impact_assessed_by': {
          'uid': 'stg-homolog-990002',
          'name': 'Homologacao Nutrition Manager 990002',
          'internal_role': 'condutor',
        },
        'current_stage': 'impact_assessed',
        'operational_impact': {
          'level': 'none',
          'description': 'Cão liberado para todas as atividades operacionais sem qualquer restrição clínica.',
          'restrictionsIssued': [],
        },
        'revision': 5,
      };

      final parsed = ExamProcess.fromMap(payload);
      expect(parsed.id, 'exam_248862333f8057af');
      expect(parsed.stage, ExamStage.impactAssessed);
      expect(parsed.title, 'Hemograma - Homologação EXAM-V1');
      expect(parsed.operationalImpact?.level, OperationalImpactLevel.none);
    });
  });
}
