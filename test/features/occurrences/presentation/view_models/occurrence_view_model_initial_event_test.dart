import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceRepository occurrenceRepo;
  late OccurrenceEventRepository eventRepo;
  late OccurrenceViewModel vm;

  setUp(() {
    WidgetsFlutterBinding.ensureInitialized();
    fakeFirestore = FakeFirebaseFirestore();
    occurrenceRepo = OccurrenceRepository(fakeFirestore);
    eventRepo = OccurrenceEventRepository(fakeFirestore);
    vm = OccurrenceViewModel(
      repository: occurrenceRepo,
      eventRepository: eventRepo,
    );
  });

  group('createOccurrence — evento inicial opening', () {
    test('cria evento opening na subcoleção /events após criar ocorrência',
        () async {
      final occId = const Uuid().v4();

      await vm.createOccurrence(
        id: occId,
        shiftId: 'shift-001',
        dogId: 'dog-001',
        primaryHandlerId: 'handler-001',
        typeCode: 'patrulhamento',
        typeName: 'Patrulhamento',
        locationAddress: 'Rua Teste, 123',
        gpsLat: -22.5642,
        gpsLng: -47.4019,
        gpsAccuracy: 5.0,
      );

      final eventsSnap = await fakeFirestore
          .collection('occurrences')
          .doc(occId)
          .collection('events')
          .get();

      expect(eventsSnap.docs, hasLength(1));

      final eventData = eventsSnap.docs.first.data();
      expect(eventData['category'], 'opening');
      expect(eventData['title'], 'Registro de ocorrência aberto');
      expect(eventData['description'], contains('Binômio em local'));
      expect(eventData['description'], contains('GPS capturado'));
      expect(eventData['gps_lat'], -22.5642);
      expect(eventData['gps_lng'], -47.4019);
    });

    test('evento opening tem mesmo timestamp que startedAt da ocorrência',
        () async {
      final occId = const Uuid().v4();

      final created = await vm.createOccurrence(
        id: occId,
        shiftId: 'shift-001',
        dogId: 'dog-001',
        primaryHandlerId: 'handler-001',
        typeCode: 'busca',
        typeName: 'Busca',
      );

      final eventsSnap = await fakeFirestore
          .collection('occurrences')
          .doc(occId)
          .collection('events')
          .get();

      expect(eventsSnap.docs, hasLength(1));

      final eventData = eventsSnap.docs.first.data();
      final eventTimestamp = DateTime.parse(eventData['timestamp'] as String);
      expect(eventTimestamp, created.startedAt);
    });

    test('evento opening sem GPS quando coordenadas não disponíveis',
        () async {
      final occId = const Uuid().v4();

      await vm.createOccurrence(
        id: occId,
        shiftId: 'shift-001',
        dogId: 'dog-001',
        primaryHandlerId: 'handler-001',
        typeCode: 'apoio',
        typeName: 'Apoio',
      );

      final eventsSnap = await fakeFirestore
          .collection('occurrences')
          .doc(occId)
          .collection('events')
          .get();

      final eventData = eventsSnap.docs.first.data();
      expect(eventData['gps_lat'], isNull);
      expect(eventData['gps_lng'], isNull);
      expect(eventData['description'], isNot(contains('GPS capturado')));
      expect(eventData['description'], contains('Binômio em local'));
    });

    test('audit_trail do evento marca automatic: true', () async {
      final occId = const Uuid().v4();

      await vm.createOccurrence(
        id: occId,
        shiftId: 'shift-001',
        dogId: 'dog-001',
        primaryHandlerId: 'handler-001',
        typeCode: 'patrulhamento',
        typeName: 'Patrulhamento',
      );

      final eventsSnap = await fakeFirestore
          .collection('occurrences')
          .doc(occId)
          .collection('events')
          .get();

      final eventData = eventsSnap.docs.first.data();
      final auditTrail = eventData['audit_trail'] as List;
      expect(auditTrail, hasLength(greaterThanOrEqualTo(1)));

      final creationEntry = auditTrail.first as Map<String, dynamic>;
      expect(creationEntry['action'], 'created');
      expect(creationEntry['automatic'], true);
    });
  });
}
