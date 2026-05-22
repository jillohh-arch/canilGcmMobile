import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/health_service.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late HealthService healthService;
  late DogService dogService;
  late HealthViewModel viewModel;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    healthService = HealthService(firestore: fakeFirestore);
    dogService = DogService(firestore: fakeFirestore);
    viewModel = HealthViewModel.withServices(healthService, dogService);
  });

  HealthLogModel createLog({
    String? id,
    String dogId = 'dog-1',
    String logType = 'Consulta',
    DateTime? date,
  }) {
    String typeVal = 'other';
    if (logType == 'Vacina') typeVal = 'vaccination';
    if (logType == 'Consulta') typeVal = 'consultation';
    if (logType == 'Exame') typeVal = 'exam';
    if (logType == 'Medicação') typeVal = 'medication';
    if (logType == 'Banho') typeVal = 'other';
    if (logType == 'Pesagem') typeVal = 'other';

    return HealthLogModel(
      id: id,
      dogId: dogId,
      type: typeVal,
      subtype: logType,
      date: date ?? DateTime(2026, 5, 10),
      healthObservations: 'Observacao teste',
    );
  }

  group('HealthViewModel', () {
    test('addHealthLog inserts log into state and Firestore', () async {
      final log = createLog();

      await viewModel.addHealthLog(log);

      expect(viewModel.healthLogs, hasLength(1));
      expect(viewModel.healthLogs.first.logType, 'Consulta');
      expect(viewModel.healthLogs.first.id, isNotNull);

      // Verify persisted
      final snapshot = await fakeFirestore
          .collection('dogs')
          .doc('dog-1')
          .collection('health_events')
          .get();
      expect(snapshot.docs, hasLength(1));
    });

    test('updateHealthLog updates existing log in state', () async {
      // First add a log
      await viewModel.addHealthLog(createLog());
      final savedId = viewModel.healthLogs.first.id!;

      // Update it
      final updated = HealthLogModel(
        id: savedId,
        dogId: 'dog-1',
        type: 'vaccination',
        subtype: 'Vacina',
        date: DateTime(2026, 5, 10),
        healthObservations: 'Vacina aplicada',
      );
      await viewModel.updateHealthLog(updated);

      expect(viewModel.healthLogs, hasLength(1));
      expect(viewModel.healthLogs.first.logType, 'Vacina');
      expect(viewModel.healthLogs.first.healthObservations, 'Vacina aplicada');
    });

    test('deleteHealthLog removes from state and Firestore', () async {
      await viewModel.addHealthLog(createLog());
      final savedId = viewModel.healthLogs.first.id!;

      await viewModel.deleteHealthLog(
        id: savedId,
        userId: 'test-user',
        reason: 'Teste de exclusão',
      );

      expect(viewModel.healthLogs, isEmpty);
      final doc = await fakeFirestore
          .collection('dogs')
          .doc('dog-1')
          .collection('health_events')
          .doc(savedId)
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['deleted_at'], isNotNull);
    });

    test('fetchHealthLogsForDog loads logs for given dog', () async {
      // Add logs directly to Firestore
      await fakeFirestore
          .collection('dogs')
          .doc('dog-1')
          .collection('health_events')
          .add({
        'dogId': 'dog-1',
        'type': 'other',
        'subtype': 'Banho',
        'date': Timestamp.fromDate(DateTime(2026, 5, 8)),
        'healthObservations': 'Banho completo',
      });
      await fakeFirestore
          .collection('dogs')
          .doc('dog-1')
          .collection('health_events')
          .add({
        'dogId': 'dog-1',
        'type': 'consultation',
        'subtype': 'Consulta',
        'date': Timestamp.fromDate(DateTime(2026, 5, 10)),
        'healthObservations': 'Consulta rotina',
      });
      await fakeFirestore
          .collection('dogs')
          .doc('dog-2')
          .collection('health_events')
          .add({
        'dogId': 'dog-2',
        'type': 'vaccination',
        'subtype': 'Vacina',
        'date': Timestamp.fromDate(DateTime(2026, 5, 9)),
        'healthObservations': 'Vacina outro cao',
      });

      await viewModel.fetchHealthLogsForDog('dog-1');

      expect(viewModel.healthLogs, hasLength(2));
      // Should be sorted by date descending
      expect(viewModel.healthLogs.first.logType, 'Consulta');
      expect(viewModel.healthLogs.last.subtype, 'Banho');
    });

    test('isLoading is false after operation completes', () async {
      await viewModel.addHealthLog(createLog());
      expect(viewModel.isLoading, isFalse);
    });
  });
}
