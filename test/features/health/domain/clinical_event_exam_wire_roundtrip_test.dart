import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

void main() {
  group('ClinicalEvent Exam Wire Contract & Round-Trip', () {
    test('1. exam_request: wire map → ClinicalEvent → toMap preserves contract', () {
      final wireMap = <String, dynamic>{
        'entity_kind': 'clinical_event',
        'event_id': 'evt-req-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'exam_id': 'exam-1',
        'event_type': 'exam_request',
        'payload_type': 'exam_request_v1',
        'payload_version': 1,
        'status': 'final',
        'occurred_at': '2026-09-04T12:00:00.000Z',
        'recorded_at': '2026-09-04T12:00:00.000Z',
        'recorded_by': {
          'uid': 'vet-1',
          'name': 'Dra. Ana',
          'internal_role': 'veterinario',
        },
        'content': {
          'exam_id': 'exam-1',
          'exam_type': 'blood',
          'title': 'Hemograma Completo',
          'urgency': 'routine',
          'if_request_reason': 'Suspeita infecciosa',
        },
        'revision': 1,
        'schema_version': 1,
      };

      final event = ClinicalEvent.fromMap(wireMap);

      expect(event.id, 'evt-req-1');
      expect(event.caseId, 'case-1');
      expect(event.type, ClinicalEventType.examRequest);
      expect(event.type.wireName, 'exam_request');
      expect(event.status, ClinicalEventStatus.finalised);
      expect(event.payloadType, 'exam_request_v1');
      expect(event.payloadVersion, 1);
      expect(event.schemaVersion, 1);
      expect(event.recordedBy.uid, 'vet-1');
      expect(event.recordedBy.name, 'Dra. Ana');
      expect(event.content['exam_id'], 'exam-1');
      expect(event.content['title'], 'Hemograma Completo');

      final roundTrip = event.toMap();
      expect(roundTrip['event_id'], 'evt-req-1');
      expect(roundTrip['case_id'], 'case-1');
      expect(roundTrip['event_type'], 'exam_request');
      expect(roundTrip['payload_type'], 'exam_request_v1');
      expect(roundTrip['status'], 'final');
    });

    test('2. exam_collection: wire map → ClinicalEvent → round-trip proves NO exception, NO loss, typed as examCollection', () {
      final wireMap = <String, dynamic>{
        'entity_kind': 'clinical_event',
        'event_id': 'evt-col-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'exam_id': 'exam-1',
        'event_type': 'exam_collection',
        'payload_type': 'exam_collection_v1',
        'payload_version': 1,
        'status': 'final',
        'occurred_at': '2026-09-04T13:00:00.000Z',
        'recorded_at': '2026-09-04T13:00:00.000Z',
        'recorded_by': {
          'uid': 'cond-1',
          'name': 'Condutor Silva',
          'internal_role': 'operador',
        },
        'content': {
          'exam_id': 'exam-1',
          'if_collection_site': 'Veia cefálica esquerda',
          'if_collection_notes': 'Coleta sem intercorrências',
        },
        'revision': 1,
        'schema_version': 1,
      };

      // Prova 1: Não lança exceção
      expect(() => ClinicalEvent.fromMap(wireMap), returnsNormally);

      final event = ClinicalEvent.fromMap(wireMap);

      // Prova 2: Não vira outro tipo e não vira unknown silenciosamente
      expect(event.type, equals(ClinicalEventType.examCollection));
      expect(event.type.wireName, equals('exam_collection'));

      // Prova 3: Não é descartado e preserva identidade
      expect(event.id, 'evt-col-1');
      expect(event.caseId, 'case-1');
      expect(event.payloadType, 'exam_collection_v1');
      expect(event.status, ClinicalEventStatus.finalised);
      expect(event.recordedBy.uid, 'cond-1');
      expect(event.recordedBy.internalRole, 'operador');

      // Prova 4: Conteúdo de coleta é preservado integralmente
      expect(event.content['exam_id'], 'exam-1');
      expect(event.content['if_collection_site'], 'Veia cefálica esquerda');
      expect(event.content['if_collection_notes'], 'Coleta sem intercorrências');

      // Prova 5: Serialização de volta para wire é simétrica
      final roundTrip = event.toMap();
      expect(roundTrip['event_type'], 'exam_collection');
      expect(roundTrip['payload_type'], 'exam_collection_v1');
      expect(roundTrip['status'], 'final');
    });

    test('3. exam_result: wire map → ClinicalEvent → round-trip preserves attachments and summary', () {
      final wireMap = <String, dynamic>{
        'entity_kind': 'clinical_event',
        'event_id': 'evt-res-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'exam_id': 'exam-1',
        'event_type': 'exam_result',
        'payload_type': 'exam_result_v1',
        'payload_version': 1,
        'status': 'final',
        'occurred_at': '2026-09-04T14:00:00.000Z',
        'recorded_at': '2026-09-04T14:00:00.000Z',
        'recorded_by': {
          'uid': 'vet-1',
          'name': 'Dra. Ana',
          'internal_role': 'veterinario',
        },
        'content': {
          'exam_id': 'exam-1',
          'result_summary': 'Plaquetas e leucócitos normais',
          'if_result_document_id': 'doc-laudo-001',
        },
        'attachment_refs': ['doc-laudo-001'],
        'revision': 1,
        'schema_version': 1,
      };

      final event = ClinicalEvent.fromMap(wireMap);

      expect(event.id, 'evt-res-1');
      expect(event.type, ClinicalEventType.examResult);
      expect(event.type.wireName, 'exam_result');
      expect(event.payloadType, 'exam_result_v1');
      expect(event.content['result_summary'], 'Plaquetas e leucócitos normais');
      expect(event.attachmentRefs, contains('doc-laudo-001'));

      final roundTrip = event.toMap();
      expect(roundTrip['event_type'], 'exam_result');
      expect(roundTrip['attachment_refs'], ['doc-laudo-001']);
    });

    test('4. exam_interpretation: wire map → ClinicalEvent → round-trip preserves professional identity & text', () {
      final wireMap = <String, dynamic>{
        'entity_kind': 'clinical_event',
        'event_id': 'evt-int-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'exam_id': 'exam-1',
        'event_type': 'exam_interpretation',
        'payload_type': 'exam_interpretation_v1',
        'payload_version': 1,
        'status': 'final',
        'occurred_at': '2026-09-04T15:00:00.000Z',
        'recorded_at': '2026-09-04T15:00:00.000Z',
        'recorded_by': {
          'uid': 'vet-1',
          'name': 'Dra. Ana',
          'internal_role': 'veterinario',
        },
        'content': {
          'exam_id': 'exam-1',
          'interpretation_text': 'Sem indícios de infecção ativa.',
          'if_interpretation_document_id': 'doc-interp-001',
        },
        'attachment_refs': ['doc-interp-001'],
        'revision': 1,
        'schema_version': 1,
      };

      final event = ClinicalEvent.fromMap(wireMap);

      expect(event.id, 'evt-int-1');
      expect(event.type, ClinicalEventType.examInterpretation);
      expect(event.type.wireName, 'exam_interpretation');
      expect(event.payloadType, 'exam_interpretation_v1');
      expect(event.content['interpretation_text'], 'Sem indícios de infecção ativa.');

      final roundTrip = event.toMap();
      expect(roundTrip['event_type'], 'exam_interpretation');
    });

    test('5. reevaluation: wire map → ClinicalEvent → round-trip preserves operational_impact for exam', () {
      final wireMap = <String, dynamic>{
        'entity_kind': 'clinical_event',
        'event_id': 'evt-imp-1',
        'case_id': 'case-1',
        'dog_id': 'dog-1',
        'exam_id': 'exam-1',
        'event_type': 'reevaluation',
        'payload_type': 'reevaluation_v1',
        'payload_version': 1,
        'status': 'final',
        'occurred_at': '2026-09-04T16:00:00.000Z',
        'recorded_at': '2026-09-04T16:00:00.000Z',
        'recorded_by': {
          'uid': 'vet-1',
          'name': 'Dra. Ana',
          'internal_role': 'veterinario',
        },
        'content': {
          'exam_id': 'exam-1',
          'evaluation_type': 'exam_impact_assessment',
          'operational_impact': {
            'level': 'low',
            'description': 'Apto com restrição de saltos de altura',
            'restrictions_issued': ['rest-001'],
          },
        },
        'revision': 1,
        'schema_version': 1,
      };

      final event = ClinicalEvent.fromMap(wireMap);

      expect(event.id, 'evt-imp-1');
      expect(event.type, ClinicalEventType.reevaluation);
      expect(event.type.wireName, 'reevaluation');
      expect(event.payloadType, 'reevaluation_v1');
      expect(event.content['exam_id'], 'exam-1');
      expect(event.content['evaluation_type'], 'exam_impact_assessment');
      final impact = event.content['operational_impact'] as Map;
      expect(impact['level'], 'low');
      expect(impact['description'], 'Apto com restrição de saltos de altura');

      final roundTrip = event.toMap();
      expect(roundTrip['event_type'], 'reevaluation');
      expect(roundTrip['payload_type'], 'reevaluation_v1');
    });

    test('6. Unknown wire value handling: parse gracefully returns unknown, fromMap fails fast', () {
      final parsed = ClinicalEventTypeWire.parse('future_exotic_exam_event');
      expect(parsed.isKnown, false);
      expect(parsed.isUnknown, true);
      expect(parsed.raw, 'future_exotic_exam_event');
      expect(parsed.value, isNull);

      final unknownMap = <String, dynamic>{
        'event_id': 'evt-unk-1',
        'case_id': 'case-1',
        'event_type': 'future_exotic_exam_event',
        'status': 'final',
        'content': <String, dynamic>{},
      };

      expect(
        () => ClinicalEvent.fromMap(unknownMap),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
