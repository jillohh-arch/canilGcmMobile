import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/data/incident_service.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late IncidentService service;
  late IncidentViewModel viewModel;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    service = IncidentService(firestore: fakeFirestore);
    viewModel = IncidentViewModel.withService(service);
  });

  Incident createIncident({
    String id = 'inc-1',
    String dogId = 'dog-1',
    String status = 'Finalizada',
    DateTime? date,
  }) {
    return Incident(
      id: id,
      dogId: dogId,
      handlerId: 'handler-1',
      date: date ?? DateTime(2026, 5, 10),
      location: 'Base GCM',
      description: 'Teste',
      result: 'Apoio prestado',
      status: status,
    );
  }

  group('IncidentViewModel', () {
    test('fetchIncidentsForDog returns incidents for given dog', () async {
      final incident = createIncident();
      await fakeFirestore
          .collection('incidents')
          .doc(incident.id)
          .set(incident.toJson());

      await viewModel.fetchIncidentsForDog('dog-1');

      expect(viewModel.incidents, hasLength(1));
      expect(viewModel.incidents.first.id, 'inc-1');
      expect(viewModel.incidents.first.dogId, 'dog-1');
    });

    test('fetchIncidentsForDog does not return incidents for other dogs', () async {
      final incident = createIncident(dogId: 'dog-2');
      await fakeFirestore
          .collection('incidents')
          .doc(incident.id)
          .set(incident.toJson());

      await viewModel.fetchIncidentsForDog('dog-1');

      expect(viewModel.incidents, isEmpty);
    });

    test('saveIncident adds new incident to state', () async {
      final incident = createIncident();

      await viewModel.saveIncident(incident);

      expect(viewModel.incidents, hasLength(1));
      expect(viewModel.incidents.first.id, 'inc-1');

      // Verify persisted in Firestore
      final doc = await fakeFirestore.collection('incidents').doc('inc-1').get();
      expect(doc.exists, isTrue);
    });

    test('saveIncident updates existing incident in state', () async {
      final incident = createIncident();
      await viewModel.saveIncident(incident);

      final updated = Incident(
        id: 'inc-1',
        dogId: 'dog-1',
        handlerId: 'handler-1',
        date: DateTime(2026, 5, 10),
        location: 'Local atualizado',
        description: 'Atualizado',
        result: 'BO elaborado',
        status: 'Finalizada',
      );
      await viewModel.saveIncident(updated);

      expect(viewModel.incidents, hasLength(1));
      expect(viewModel.incidents.first.location, 'Local atualizado');
    });

    test('deleteIncident removes from state and Firestore', () async {
      final incident = createIncident();
      await viewModel.saveIncident(incident);
      expect(viewModel.incidents, hasLength(1));

      await viewModel.deleteIncident('inc-1');

      expect(viewModel.incidents, isEmpty);
      final doc = await fakeFirestore.collection('incidents').doc('inc-1').get();
      expect(doc.exists, isFalse);
    });

    test('findOpenIncident returns most recent open incident', () async {
      final open1 = Incident(
        id: 'inc-open-1',
        dogId: 'dog-1',
        handlerId: 'handler-1',
        date: DateTime(2026, 5, 8),
        location: 'Local A',
        description: 'Primeira',
        result: '',
        status: 'Em andamento',
        updatedAt: DateTime(2026, 5, 8),
      );
      final open2 = Incident(
        id: 'inc-open-2',
        dogId: 'dog-1',
        handlerId: 'handler-1',
        date: DateTime(2026, 5, 10),
        location: 'Local B',
        description: 'Segunda',
        result: '',
        status: 'Em andamento',
        updatedAt: DateTime(2026, 5, 10),
      );

      await fakeFirestore
          .collection('incidents')
          .doc(open1.id)
          .set(open1.toJson());
      await fakeFirestore
          .collection('incidents')
          .doc(open2.id)
          .set(open2.toJson());

      final found = await viewModel.findOpenIncident(dogId: 'dog-1');

      expect(found, isNotNull);
      expect(found!.id, 'inc-open-2');
    });

    test('fetchNatures returns occurrence natures from Firestore', () async {
      await fakeFirestore.collection('occurrence_natures').doc('N001').set({
        'code': 'N001',
        'name': 'Busca de Entorpecentes',
        'label': 'Busca de Entorpecentes',
        'active': true,
      });
      await fakeFirestore.collection('occurrence_natures').doc('N002').set({
        'code': 'N002',
        'name': 'Pessoa Desaparecida',
        'label': 'Pessoa Desaparecida',
        'active': true,
      });

      final natures = await viewModel.fetchNatures();

      expect(natures, hasLength(2));
      expect(viewModel.natures, hasLength(2));
      expect(natures.first.code, 'N001');
    });

    test('incidents are sorted by date descending', () async {
      final older = createIncident(id: 'inc-old', date: DateTime(2026, 5, 1));
      final newer = createIncident(id: 'inc-new', date: DateTime(2026, 5, 10));

      await viewModel.saveIncident(older);
      await viewModel.saveIncident(newer);

      expect(viewModel.incidents.first.id, 'inc-new');
      expect(viewModel.incidents.last.id, 'inc-old');
    });
  });
}
