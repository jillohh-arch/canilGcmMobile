import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_payload_builder.dart';

void main() {
  group('Incident', () {
    test('writes date as Firestore Timestamp', () {
      final date = DateTime.utc(2026, 4, 20, 10, 30);
      final incident = Incident(
        id: 'incident-1',
        dogId: 'dog-1',
        handlerId: '12345',
        date: date,
        location: 'Base GCM',
        description: 'Apoio operacional',
        result: 'Realizado',
      );

      final json = incident.toJson();

      expect(json['date'], isA<Timestamp>());
      expect((json['date'] as Timestamp).toDate().toUtc(), date);
    });

    test('reads legacy ISO string dates', () {
      final incident = Incident.fromJson({
        'id': 'incident-legacy',
        'dogId': 'dog-1',
        'handlerId': '12345',
        'date': '2026-04-20T10:30:00.000Z',
        'location': 'Base GCM',
        'description': 'Registro legado',
        'result': 'Realizado',
      });

      expect(incident.date.toUtc(), DateTime.utc(2026, 4, 20, 10, 30));
    });

    test('reads Firestore Timestamp dates', () {
      final date = DateTime.utc(2026, 4, 20, 10, 30);
      final incident = Incident.fromJson({
        'id': 'incident-new',
        'dogId': 'dog-1',
        'handlerId': '12345',
        'date': Timestamp.fromDate(date),
        'location': 'Base GCM',
        'description': 'Registro novo',
        'result': 'Realizado',
      });

      expect(incident.date.toUtc(), date);
    });

    test('reads enriched incident workflow fields', () {
      final startedAt = DateTime.utc(2026, 4, 20, 10, 30);
      final updatedAt = DateTime.utc(2026, 4, 20, 14, 45);
      final incident = Incident.fromJson({
        'id': 'incident-enriched',
        'dogId': 'dog-1',
        'handlerId': '12345',
        'date': Timestamp.fromDate(startedAt),
        'startedAt': Timestamp.fromDate(startedAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'status': 'Em andamento',
        'operationalSuccess': true,
        'outcomes': ['Droga apreendida', 'Indivíduo detido'],
        'progressUpdates': [
          {
            'title': 'Registro inicial',
            'description': 'Localização inicial do material.',
            'timestamp': Timestamp.fromDate(startedAt),
            'location': 'Odecio Degan',
            'authorId': '12345',
            'authorName': 'Ragonha',
          },
        ],
        'location': 'Odecio Degan',
        'description': 'Ocorrência ainda em evolução',
        'result': 'Em andamento',
      });

      expect(incident.status, 'Em andamento');
      expect(incident.operationalSuccess, isTrue);
      expect(
        incident.outcomes,
        containsAll(['Droga apreendida', 'Indivíduo detido']),
      );
      expect(incident.progressUpdates, hasLength(1));
      expect(incident.progressUpdates.first.location, 'Odecio Degan');
      expect(incident.progressUpdates.first.authorId, '12345');
      expect(incident.progressUpdates.first.authorName, 'Ragonha');
      expect(incident.updatedAt.toUtc(), updatedAt);
    });

    test('preserves existing extra fields while saving incident progress', () {
      final extraFields = OccurrencePayloadBuilder.buildExtraFields(
        nature: 'Busca de Entorpecentes',
        manualNature: '',
        formData: const {},
        team: 'Ragonha, João e Fernanda',
        bo: '',
        supportedTeam: '',
        situation: '',
        interventionOutcome: '',
        odorSource: '',
        missingTime: '',
        searchDuration: '',
        terrainCondition: '',
        serviceOrderNumber: '',
        drugRows: const [],
        detainedIndividuals: const [],
        seizedObjects: const [],
        detainedVehicles: const [],
        existingExtraFields: const {
          'bo': '123/2026',
          'drogas': [
            {'tipo': 'Cocaína', 'quantidade': '150 g'},
          ],
          'locationLat': -22.56,
          'locationLng': -47.40,
        },
      );

      expect(extraFields['bo'], '123/2026');
      expect(extraFields['equipe'], 'Ragonha, João e Fernanda');
      expect(extraFields['drogas'], isA<List>());
      expect((extraFields['drogas'] as List).first['tipo'], 'Cocaína');
      expect(extraFields['locationLat'], -22.56);
      expect(extraFields['locationLng'], -47.40);
    });

    test('generates a safe incident id when document id is blank', () {
      final incident = OccurrencePayloadBuilder.buildIncident(
        documentId: '   ',
        dogId: 'dog-1',
        dogName: 'Apolo',
        handlerId: '12345',
        startedAt: DateTime.utc(2026, 5, 6, 10),
        updatedAt: DateTime.utc(2026, 5, 6, 11),
        location: 'Base GCM',
        description: 'Ocorrencia registrada',
        result: 'Em andamento',
        type: 'Averiguacao',
        extraFields: const {},
        mediaAttachments: const [],
        status: 'Em andamento',
        operationalSuccess: null,
        outcomes: const [],
        progressUpdates: const [],
      );

      expect(incident.id.trim(), isNotEmpty);
      expect(incident.id, isNot(''));
    });
  });
}
