import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/clinical/firebase_clinical_event_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_event_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_event_read_model.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirebaseClinicalEventGateway gateway;

  const dogId = 'dog-k9-01';
  const caseId = 'case-clin-100';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    gateway = FirebaseClinicalEventGateway(firestore: fakeFirestore);
  });

  group('FirebaseClinicalEventGateway — Events Query & Ordering', () {
    test('1. Retorna lista vazia quando o caso não possui eventos', () async {
      final events = await gateway.readCaseEvents(dogId: dogId, caseId: caseId);
      expect(events, isEmpty);

      final streamEvents = await gateway
          .watchCaseEvents(dogId: dogId, caseId: caseId)
          .first;
      expect(streamEvents, isEmpty);
    });

    test(
      '2. Path e ordenação: lê eventos no caminho canônico ordenados por occurred_at DESC',
      () async {
        final t1 = DateTime.utc(2026, 9, 1, 10, 0);
        final t2 = DateTime.utc(2026, 9, 3, 15, 0);
        final t3 = DateTime.utc(2026, 9, 2, 12, 0);

        final eventsRef = fakeFirestore
            .collection('dogs')
            .doc(dogId)
            .collection('clinical_cases')
            .doc(caseId)
            .collection('clinical_events');

        await eventsRef.doc('evt-1').set({
          'entity_kind': 'clinical_event',
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': Timestamp.fromDate(t1),
          'recorded_at': Timestamp.fromDate(t1),
          'recorded_by': {
            'uid': 'u1',
            'name': 'Vet 1',
            'internal_role': 'veterinario',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'diagnosis': 'Primeiro'},
        });

        await eventsRef.doc('evt-2').set({
          'entity_kind': 'clinical_event',
          'event_type': 'vaccination',
          'status': 'final',
          'occurred_at': Timestamp.fromDate(t2),
          'recorded_at': Timestamp.fromDate(t2),
          'recorded_by': {
            'uid': 'u2',
            'name': 'Vet 2',
            'internal_role': 'veterinario',
          },
          'payload_type': 'vaccination_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'vaccine': 'Mais recente'},
        });

        await eventsRef.doc('evt-3').set({
          'entity_kind': 'clinical_event',
          'event_type': 'general_note',
          'status': 'final',
          'occurred_at': Timestamp.fromDate(t3),
          'recorded_at': Timestamp.fromDate(t3),
          'recorded_by': {
            'uid': 'u3',
            'name': 'GCM 3',
            'internal_role': 'operador',
          },
          'payload_type': 'general_note_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {'note': 'Intermediário'},
        });

        final results = await gateway.readCaseEvents(
          dogId: dogId,
          caseId: caseId,
        );

        expect(results, hasLength(3));
        // Ordem decrescente de occurred_at: t2 (Sep 3) > t3 (Sep 2) > t1 (Sep 1)
        expect(results[0].id, 'evt-2');
        expect(results[0].occurredAt, t2);
        expect(results[1].id, 'evt-3');
        expect(results[1].occurredAt, t3);
        expect(results[2].id, 'evt-1');
        expect(results[2].occurredAt, t1);
      },
    );

    test(
      '3. Documento parcial/corrompido é retornado com qualidade degradada sem quebrar a lista',
      () async {
        final eventsRef = fakeFirestore
            .collection('dogs')
            .doc(dogId)
            .collection('clinical_cases')
            .doc(caseId)
            .collection('clinical_events');

        await eventsRef.doc('evt-good').set({
          'event_type': 'consultation',
          'status': 'final',
          'occurred_at': Timestamp.fromDate(DateTime.utc(2026, 9, 5)),
          'recorded_at': Timestamp.fromDate(DateTime.utc(2026, 9, 5)),
          'recorded_by': {'uid': 'u1', 'name': 'Dr. A', 'internal_role': 'vet'},
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'revision': 1,
          'content': {},
        });

        // Documento malformado sem campos requeridos
        await eventsRef.doc('evt-broken').set({
          'status': 'corrompido_desconhecido',
          'content': 'não é mapa',
        });

        final results = await gateway.readCaseEvents(
          dogId: dogId,
          caseId: caseId,
        );

        expect(results, hasLength(2));
        final good = results.firstWhere((e) => e.id == 'evt-good');
        final broken = results.firstWhere((e) => e.id == 'evt-broken');

        expect(good.hasQualityIssues, isFalse);
        expect(broken.hasQualityIssues, isTrue);
        expect(broken.dataQualityIssues, contains('missing_event_type'));
        expect(
          broken.dataQualityIssues,
          contains('unknown_event_status:corrompido_desconhecido'),
        );
      },
    );

    test('4. Argumentos inválidos lançam ClinicalEventReadException', () async {
      expect(
        () => gateway.readCaseEvents(dogId: '', caseId: 'case-1'),
        throwsA(isA<ClinicalEventReadException>()),
      );
      expect(
        () => gateway.readCaseEvents(dogId: 'dog-1', caseId: '  '),
        throwsA(isA<ClinicalEventReadException>()),
      );
    });
  });

  group('FirebaseClinicalEventGateway — Amendments Query & Ordering', () {
    const eventId = 'evt-parent-01';

    test('1. Retorna lista vazia quando o evento não tem emendas', () async {
      final list = await gateway.readEventAmendments(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
      );
      expect(list, isEmpty);
    });

    test(
      '2. Path e ordenação: lê emendas no caminho canônico ordenadas por recorded_at ASC com ordinal',
      () async {
        final t1 = DateTime.utc(2026, 9, 6, 10, 0);
        final t2 = DateTime.utc(2026, 9, 6, 11, 30);

        final amendsRef = fakeFirestore
            .collection('dogs')
            .doc(dogId)
            .collection('clinical_cases')
            .doc(caseId)
            .collection('clinical_events')
            .doc(eventId)
            .collection('clinical_amendments');

        await amendsRef.doc('ca_second').set({
          'type': 'addendum',
          'reason': 'Segundo adendo cronológico',
          'recorded_at': Timestamp.fromDate(t2),
          'recorded_by': {
            'uid': 'u1',
            'name': 'Vet 1',
            'internal_role': 'veterinario',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'content': {},
        });

        await amendsRef.doc('ca_first').set({
          'type': 'correction',
          'reason': 'Primeira correção cronológica',
          'recorded_at': Timestamp.fromDate(t1),
          'recorded_by': {
            'uid': 'u1',
            'name': 'Vet 1',
            'internal_role': 'veterinario',
          },
          'payload_type': 'consultation_v1',
          'payload_version': 1,
          'schema_version': 1,
          'content': {},
        });

        final results = await gateway.readEventAmendments(
          dogId: dogId,
          caseId: caseId,
          eventId: eventId,
        );

        expect(results, hasLength(2));
        // Ordenação cronológica crescente: t1 (10:00) < t2 (11:30)
        expect(results[0].id, 'ca_first');
        expect(results[0].type.value, ClinicalAmendmentType.correction);
        expect(results[0].recordedAt, t1);

        expect(results[1].id, 'ca_second');
        expect(results[1].type.value, ClinicalAmendmentType.addendum);
        expect(results[1].recordedAt, t2);
      },
    );

    test(
      '3. readEvent busca documento específico ou retorna null se inexistente',
      () async {
        final notFound = await gateway.readEvent(
          dogId: dogId,
          caseId: caseId,
          eventId: 'non-existent',
        );
        expect(notFound, isNull);

        await fakeFirestore
            .collection('dogs')
            .doc(dogId)
            .collection('clinical_cases')
            .doc(caseId)
            .collection('clinical_events')
            .doc('evt-spec')
            .set({
              'event_type': 'discharge',
              'status': 'final',
              'occurred_at': Timestamp.fromDate(DateTime.utc(2026, 9, 6)),
              'recorded_at': Timestamp.fromDate(DateTime.utc(2026, 9, 6)),
              'recorded_by': {
                'uid': 'u1',
                'name': 'Vet',
                'internal_role': 'vet',
              },
              'payload_type': 'discharge_v1',
              'payload_version': 1,
              'schema_version': 1,
              'revision': 1,
              'content': {},
            });

        final found = await gateway.readEvent(
          dogId: dogId,
          caseId: caseId,
          eventId: 'evt-spec',
        );

        expect(found, isNotNull);
        expect(found!.id, 'evt-spec');
        expect(found.type.value, ClinicalEventType.discharge);
      },
    );
  });
}
