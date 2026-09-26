import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceRepository occurrenceRepo;
  late OccurrenceEventRepository eventRepo;
  late SignatureRepository signatureRepo;
  late OccurrenceViewModel occurrenceVM;

  final now = DateTime(2026, 9, 12, 10, 30);
  const occurrenceId = 'occ_multi_device_100';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    occurrenceRepo = OccurrenceRepository(fakeFirestore);
    eventRepo = OccurrenceEventRepository(fakeFirestore);
    signatureRepo = SignatureRepository(firestore: fakeFirestore);
    occurrenceVM = OccurrenceViewModel(
      repository: occurrenceRepo,
      eventRepository: eventRepo,
      signatureRepository: signatureRepo,
      sendTeamNotifications: false,
    );
  });

  group('D2 — Cross-Device Propagation Tests (Family A & Family B)', () {
    test('Family A: parent occurrence document update streams to independent observer', () async {
      // 1. Initial occurrence created by Device 1
      final initialOccurrence = Occurrence(
        id: occurrenceId,
        shiftId: 'shift-001',
        primaryHandlerId: '990001',
        primaryHandlerRa: '990001',
        dogId: 'dog-01',
        typeCode: 'TC01',
        typeName: 'Apoio Policial',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        locationAddress: 'Rua Inicial, 100',
        initialObservation: 'Primeira observação',
      );
      await occurrenceRepo.create(initialOccurrence);

      // 2. Device 2 starts watching this occurrence by ID
      final observedSnapshots = <Occurrence?>[];
      final subscription = occurrenceRepo.watchById(occurrenceId).listen(observedSnapshots.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(observedSnapshots.isNotEmpty, isTrue);
      expect(observedSnapshots.last?.locationAddress, equals('Rua Inicial, 100'));
      expect(observedSnapshots.last?.initialObservation, equals('Primeira observação'));

      // 3. Device 1 updates parent occurrence fields
      await occurrenceRepo.update(occurrenceId, {
        'location_address': 'Avenida Atualizada, 500',
        'initial_observation': 'Observação corrigida pelo condutor',
        'type_code': 'TC02',
        'type_name': 'Patrulhamento',
      });

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4. Device 2 must receive the updated projection without manual reload
      expect(observedSnapshots.last?.locationAddress, equals('Avenida Atualizada, 500'));
      expect(observedSnapshots.last?.initialObservation, equals('Observação corrigida pelo condutor'));
      expect(observedSnapshots.last?.typeCode, equals('TC02'));
      expect(observedSnapshots.last?.typeName, equals('Patrulhamento'));

      await subscription.cancel();
    });

    test('Family B: existing timeline event update streams to independent observer', () async {
      // 1. Initial event created on Device 1
      final event1 = OccurrenceEvent(
        id: 'evt_001',
        occurrenceId: occurrenceId,
        title: 'Chegada ao Local',
        description: 'Viatura no local da chamada',
        category: OccurrenceEventCategory.arrival,
        timestamp: now,
        createdAt: now,
        updatedAt: now,
      );
      // create parent occurrence so _ensureOccurrenceMutable passes
      final initialOccurrence = Occurrence(
        id: occurrenceId,
        shiftId: 'shift-001',
        primaryHandlerId: '990001',
        primaryHandlerRa: '990001',
        dogId: 'dog-01',
        typeCode: 'TC01',
        typeName: 'Apoio Policial',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
      );
      await occurrenceRepo.create(initialOccurrence);

      await eventRepo.create(event1);

      // 2. Device 2 watches events
      final observedEventsList = <List<OccurrenceEvent>>[];
      final subscription = eventRepo.watchByOccurrence(occurrenceId).listen(observedEventsList.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(observedEventsList.isNotEmpty, isTrue);
      expect(observedEventsList.last.length, equals(1));
      expect(observedEventsList.last.first.description, equals('Viatura no local da chamada'));

      // 3. Device 1 updates the existing timeline event (e.g. edited details)
      await eventRepo.update(occurrenceId, 'evt_001', {
        'title': 'Chegada ao Local Confirmada',
        'description': 'Viatura posicionada no portão principal',
      });

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4. Device 2 receives the updated event projection without manual reload
      expect(observedEventsList.last.length, equals(1));
      expect(observedEventsList.last.first.title, equals('Chegada ao Local Confirmada'));
      expect(observedEventsList.last.first.description, equals('Viatura posicionada no portão principal'));

      await subscription.cancel();
    });

    test('OccurrenceViewModel.watchById returns reactive stream that updates on parent doc change', () async {
      final initialOccurrence = Occurrence(
        id: occurrenceId,
        shiftId: 'shift-001',
        primaryHandlerId: '990001',
        primaryHandlerRa: '990001',
        dogId: 'dog-01',
        typeCode: 'TC01',
        typeName: 'Apoio Policial',
        startedAt: now,
        createdAt: now,
        updatedAt: now,
        status: OccurrenceStatus.inProgress,
        locationAddress: 'Rua Alfa, 10',
      );
      await occurrenceRepo.create(initialOccurrence);

      final snapshots = <Occurrence?>[];
      final sub = occurrenceVM.watchById(occurrenceId).listen(snapshots.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(snapshots.isNotEmpty, isTrue);
      expect(snapshots.last?.locationAddress, equals('Rua Alfa, 10'));

      // Device A modifies address
      await occurrenceRepo.update(occurrenceId, {
        'location_address': 'Rua Beta, 20',
      });

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(snapshots.last?.locationAddress, equals('Rua Beta, 20'));

      await sub.cancel();
    });
  });
}
