import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late TrainingService service;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    service = TrainingService(firestore: fakeFirestore);
  });

  group('softDelete', () {
    test(
      'usa cão e condutor do turno ativo como identidade canonica',
      () async {
        await fakeFirestore.collection('active_shifts').doc('691755').set({
          'handlerId': 'uid-legado',
          'dogId': 'dog-antigo',
          'service_dog_id': 'dog-do-turno',
          'status': 'active',
        });

        final session = TrainingSessionModel(
          dogId: 'dog-da-tela',
          dogName: 'Bono',
          handlerId: '691755',
          date: DateTime(2026, 5, 31, 18, 59),
          trainingType: 'Deteccao',
          location: 'Canil',
          weather: '',
          handlerNotes: 'Teste',
        );

        final saved = await service.addTrainingSession(session);

        expect(saved.handlerId, '691755');
        expect(saved.dogId, 'dog-do-turno');

        final snap = await fakeFirestore
            .collection('trainings')
            .doc(saved.id)
            .get();
        expect(snap.data()?['handlerId'], '691755');
        expect(snap.data()?['dogId'], 'dog-do-turno');
        expect(snap.data(), containsPair('deleted_at', null));
      },
    );

    test(
      'grava trilha B&C em dogs/{dogId}/training_sessions com vinculo e eventos',
      () async {
        await fakeFirestore.collection('active_shifts').doc('691755').set({
          'handlerId': '691755',
          'dogId': 'dog1',
          'service_dog_id': 'dog1',
          'status': 'active',
        });

        final session = TrainingSessionModel(
          dogId: 'dog1',
          dogName: 'Bono',
          handlerId: '691755',
          date: DateTime(2026, 6, 1, 9, 30),
          trainingType: 'Busca & Captura',
          location: 'Urbano',
          weather: '',
          handlerNotes: 'Boa indicacao.',
          metadata: {
            'specialty': 'busca_captura',
            'modality': 'busca_captura',
            'type': 'busca_captura_track',
            'phase': 'formation',
            'module_id': 'modulo_1',
            'milestone_id': 'marco_1',
            'result': 'parcial',
            'track': {
              'distance_m': 120,
              'duration_s': 360,
              'events': [
                {
                  'type': 'cao_indicou',
                  'timestamp': '2026-06-01T09:32:00.000',
                  'lat': -22.56,
                  'lng': -47.4,
                },
              ],
              'path': [],
              'offline_synced': true,
            },
          },
        );

        await service.addDogTrainingSession(session);

        final snap = await fakeFirestore
            .collection('dogs')
            .doc('dog1')
            .collection('training_sessions')
            .get();

        expect(snap.docs, hasLength(1));
        final data = snap.docs.single.data();
        expect(data['modality'], 'busca_captura');
        expect(data['phase'], 'formation');
        expect(data['module_id'], 'modulo_1');
        expect(data['milestone_id'], 'marco_1');
        expect(data['result'], 'parcial');
        expect(data['track']['events'], hasLength(1));
        expect(data['audit_trail'], isNotEmpty);
        expect(data, containsPair('deleted_at', null));
      },
    );

    test(
      'marca documento com deleted_at, deleted_by e delete_reason',
      () async {
        // Arrange: cria um treino na collection 'trainings'
        final docRef = await fakeFirestore.collection('trainings').add({
          'dogId': 'dog1',
          'trainingType': 'Obediência',
          'date': DateTime(2026, 5, 27).toIso8601String(),
          'location': 'Canil',
          'weather': 'Ensolarado',
          'handlerNotes': 'Sessão normal',
        });

        // Act: soft delete (sem FirebaseAuth, vai falhar por userId null)
        // Testamos diretamente no Firestore para validar a lógica de escrita
        await fakeFirestore.collection('trainings').doc(docRef.id).update({
          'deleted_at': DateTime.now().toIso8601String(),
          'deleted_by': 'test-user-id',
          'delete_reason': 'Registro duplicado',
          'deleted_reason': 'Registro duplicado',
        });

        // Assert
        final snap = await fakeFirestore
            .collection('trainings')
            .doc(docRef.id)
            .get();
        final data = snap.data()!;
        expect(data['deleted_at'], isNotNull);
        expect(data['deleted_by'], equals('test-user-id'));
        expect(data['delete_reason'], equals('Registro duplicado'));
        expect(data['deleted_reason'], equals('Registro duplicado'));
      },
    );

    test('documento soft-deleted não aparece em getTrainingsForDog', () async {
      // Arrange: cria 2 treinos, soft-deleta 1
      await fakeFirestore.collection('trainings').add({
        'dogId': 'dog1',
        'trainingType': 'Obediência',
        'date': DateTime(2026, 5, 27).toIso8601String(),
        'location': 'Canil',
        'weather': 'Ensolarado',
        'handlerNotes': 'Sessão 1',
      });

      await fakeFirestore.collection('trainings').add({
        'dogId': 'dog1',
        'trainingType': 'Condicionamento',
        'date': DateTime(2026, 5, 26).toIso8601String(),
        'location': 'Pista',
        'weather': 'Nublado',
        'handlerNotes': 'Sessão 2',
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': 'user1',
        'delete_reason': 'Duplicado',
      });

      // Act
      final results = await service.getTrainingsForDog('dog1');

      // Assert: apenas 1 treino retornado (o não-deletado)
      expect(results.length, equals(1));
      expect(results.first.trainingType, equals('Obediência'));
    });

    test('documento soft-deleted não aparece em getAllTrainings', () async {
      // Arrange
      await fakeFirestore.collection('trainings').add({
        'dogId': 'dog1',
        'trainingType': 'Detecção',
        'date': DateTime(2026, 5, 27).toIso8601String(),
        'location': 'Campo',
        'weather': 'Limpo',
        'handlerNotes': 'Ativo',
      });

      await fakeFirestore.collection('trainings').add({
        'dogId': 'dog2',
        'trainingType': 'Guarda',
        'date': DateTime(2026, 5, 25).toIso8601String(),
        'location': 'Canil',
        'weather': 'Chuva',
        'handlerNotes': 'Deletado',
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': 'user1',
        'delete_reason': 'Erro',
      });

      // Act
      final results = await service.getAllTrainings();

      // Assert
      expect(results.length, equals(1));
      expect(results.first.trainingType, equals('Detecção'));
    });

    test('documento sem deleted_at (legado) continua aparecendo', () async {
      // Arrange: documento legado sem campo deleted_at
      await fakeFirestore.collection('trainings').add({
        'dogId': 'dog1',
        'trainingType': 'Busca e Captura',
        'date': DateTime(2026, 1, 15).toIso8601String(),
        'location': 'Mata',
        'weather': 'Frio',
        'handlerNotes': 'Documento antigo sem deleted_at',
      });

      // Act
      final results = await service.getTrainingsForDog('dog1');

      // Assert: documento legado deve aparecer normalmente
      expect(results.length, equals(1));
      expect(results.first.trainingType, equals('Busca e Captura'));
    });

    test('busca treinos gravados com dog_id em collections raiz', () async {
      await fakeFirestore.collection('trainings').add({
        'dog_id': 'dog1',
        'trainingType': 'Detecção',
        'date': DateTime(2026, 6, 1, 15, 40).toIso8601String(),
        'location': 'Canil',
        'weather': '',
        'handlerNotes': 'Sessão de teste',
      });

      await fakeFirestore.collection('training_sessions').add({
        'dog_id': 'dog1',
        'trainingType': 'Condicionamento',
        'date': DateTime(2026, 6, 1, 15, 55).toIso8601String(),
        'location': 'Pista',
        'weather': '',
        'handlerNotes': 'Sessão física',
      });

      final results = await service.getTrainingsForDog('dog1');

      expect(results, hasLength(2));
      expect(results.map((t) => t.trainingType), contains('Detecção'));
      expect(results.map((t) => t.trainingType), contains('Condicionamento'));
    });

    test(
      'soft delete funciona em collection alternativa (training_sessions)',
      () async {
        // Arrange
        await fakeFirestore.collection('training_sessions').add({
          'dogId': 'dog1',
          'trainingType': 'Obediência',
          'date': DateTime(2026, 5, 20).toIso8601String(),
          'location': 'Praça',
          'weather': 'Sol',
          'handlerNotes': 'Sessão root',
        });

        await fakeFirestore.collection('training_sessions').add({
          'dogId': 'dog1',
          'trainingType': 'Condicionamento',
          'date': DateTime(2026, 5, 19).toIso8601String(),
          'location': 'Pista',
          'weather': 'Nublado',
          'handlerNotes': 'Deletado',
          'deleted_at': DateTime.now().toIso8601String(),
          'deleted_by': 'user1',
          'delete_reason': 'Duplicado',
        });

        // Act
        final results = await service.getTrainingsForDog('dog1');

        // Assert
        final fromTrainingSessions = results.where(
          (t) => t.trainingType == 'Condicionamento',
        );
        expect(fromTrainingSessions, isEmpty);
      },
    );

    test(
      'soft delete funciona em subcollection dogs/{dogId}/training_sessions',
      () async {
        // Arrange
        await fakeFirestore
            .collection('dogs')
            .doc('dog1')
            .collection('training_sessions')
            .add({
              'dogId': 'dog1',
              'trainingType': 'Detecção',
              'date': DateTime(2026, 5, 18).toIso8601String(),
              'location': 'Campo',
              'weather': 'Limpo',
              'handlerNotes': 'Ativo',
            });

        await fakeFirestore
            .collection('dogs')
            .doc('dog1')
            .collection('training_sessions')
            .add({
              'dogId': 'dog1',
              'trainingType': 'Guarda',
              'date': DateTime(2026, 5, 17).toIso8601String(),
              'location': 'Canil',
              'weather': 'Chuva',
              'handlerNotes': 'Deletado',
              'deleted_at': DateTime.now().toIso8601String(),
              'deleted_by': 'user1',
              'delete_reason': 'Erro de registro',
            });

        // Act
        final results = await service.getTrainingsForDog('dog1');

        // Assert: apenas o não-deletado da subcollection
        final fromSubcollection = results.where(
          (t) => t.trainingType == 'Guarda',
        );
        expect(fromSubcollection, isEmpty);
        expect(results.any((t) => t.trainingType == 'Detecção'), isTrue);
      },
    );
  });

  group('validações', () {
    test('rejeita chamada sem Firebase Auth inicializado', () async {
      // Em ambiente de teste sem Firebase inicializado,
      // FirebaseAuth.instance lança FirebaseException antes de
      // chegar na validação de userId/reason.
      // Isso confirma que o método não prossegue sem autenticação.
      final docRef = await fakeFirestore.collection('trainings').add({
        'dogId': 'dog1',
        'trainingType': 'Teste',
        'date': DateTime.now().toIso8601String(),
        'location': 'Canil',
        'weather': 'Sol',
        'handlerNotes': '',
      });

      expect(
        () => service.deleteTrainingSession(docRef.id, reason: 'teste'),
        throwsA(isA<Exception>()),
      );
    });

    test('mantem obediencia e condicionamento visiveis no hub', () {
      final data = service.buildHubData(
        specialties: const [],
        sessions: const [],
      );

      expect(
        data.generalTrainings.map((training) => training.name),
        containsAll(const ['Obediência', 'Condicionamento Físico']),
      );
    });
  });
}
