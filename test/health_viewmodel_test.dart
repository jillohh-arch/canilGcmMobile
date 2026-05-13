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
    return HealthLogModel(
      id: id,
      dogId: dogId,
      logType: logType,
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
      final snapshot = await fakeFirestore.collection('health_logs').get();
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
        logType: 'Vacina',
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

      await viewModel.deleteHealthLog(savedId);

      expect(viewModel.healthLogs, isEmpty);
      final doc = await fakeFirestore.collection('health_logs').doc(savedId).get();
      expect(doc.exists, isFalse);
    });

    test('fetchHealthLogsForDog loads logs for given dog', () async {
      // Add logs directly to Firestore
      await fakeFirestore.collection('health_logs').add({
        'dogId': 'dog-1',
        'logType': 'Banho',
        'date': Timestamp.fromDate(DateTime(2026, 5, 8)),
        'healthObservations': 'Banho completo',
      });
      await fakeFirestore.collection('health_logs').add({
        'dogId': 'dog-1',
        'logType': 'Consulta',
        'date': Timestamp.fromDate(DateTime(2026, 5, 10)),
        'healthObservations': 'Consulta rotina',
      });
      await fakeFirestore.collection('health_logs').add({
        'dogId': 'dog-2',
        'logType': 'Vacina',
        'date': Timestamp.fromDate(DateTime(2026, 5, 9)),
        'healthObservations': 'Vacina outro cao',
      });

      await viewModel.fetchHealthLogsForDog('dog-1');

      expect(viewModel.healthLogs, hasLength(2));
      // Should be sorted by date descending
      expect(viewModel.healthLogs.first.logType, 'Consulta');
      expect(viewModel.healthLogs.last.logType, 'Banho');
    });

    test('isLoading is false after operation completes', () async {
      await viewModel.addHealthLog(createLog());
      expect(viewModel.isLoading, isFalse);
    });
  });
}
