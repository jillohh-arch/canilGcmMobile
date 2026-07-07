import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/training/domain/training_model.dart';

class TrainingRepository {
  TrainingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<TrainingHubSession>> watchSessionsForDog(String dogId) {
    final streams = [
      _watchSessionCollection('training_sessions', 'dogId', dogId),
      _watchSessionCollection('training_sessions', 'dog_id', dogId),
      _watchSessionCollection('trainings', 'dogId', dogId),
      _watchSessionCollection('trainings', 'dog_id', dogId),
      _watchDogTrainingSessions(dogId),
    ];

    return _combineLatestLists<TrainingHubSession>(streams, (lists) {
      final byId = <String, TrainingHubSession>{};
      for (final session in lists.expand((items) => items)) {
        final key = session.id.isNotEmpty
            ? session.id
            : '${session.dogId}_${session.date.toIso8601String()}_${session.trainingType}';
        byId[key] = session;
      }
      final result = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return result;
    });
  }

  Stream<List<TrainingSpecialtyModel>> watchSpecialtiesForDog(String dogId) {
    final streams = [_watchRootSpecialties(dogId), _watchDogSpecialties(dogId)];

    return _combineLatestLists<TrainingSpecialtyModel>(streams, (lists) {
      final byName = <String, TrainingSpecialtyModel>{};
      for (final specialty in lists.expand((items) => items)) {
        final key = normalizeTrainingKey(specialty.name);
        final current = byName[key];
        if (current == null ||
            specialty.progressPercentage > current.progressPercentage ||
            specialty.lastTrainingDate != null &&
                current.lastTrainingDate == null) {
          byName[key] = specialty;
        }
      }
      final result = byName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return result;
    });
  }

  Stream<List<TrainingHubSession>> _watchSessionCollection(
    String collection,
    String dogField,
    String dogId,
  ) {
    // limit(100): um cão não terá mais de 100 sessões ativas na coleção raiz;
    // cap safety para evitar scan ilimitado conforme o histórico cresce.
    final query = _firestore
        .collection(collection)
        .where(dogField, isEqualTo: dogId)
        .limit(100);
    return query
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => !_isSoftDeleted(doc.data()))
              .map((doc) => TrainingHubSession.fromJson(doc.data(), doc.id))
              .where((session) => session.dogId == dogId)
              .toList(),
        )
        .handleError((_) => <TrainingHubSession>[]);
  }

  Stream<List<TrainingHubSession>> _watchDogTrainingSessions(String dogId) {
    // limit(100): subcoleção por cão; cap safety para histórico crescente.
    final query = _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('training_sessions')
        .limit(100);
    return query
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => !_isSoftDeleted(doc.data()))
              .map((doc) => TrainingHubSession.fromJson(doc.data(), doc.id))
              .where(
                (session) => session.dogId == dogId || session.dogId.isEmpty,
              )
              .toList(),
        )
        .handleError((_) => <TrainingHubSession>[]);
  }

  Stream<List<TrainingSpecialtyModel>> _watchRootSpecialties(String dogId) {
    // limit(20): especialidades são estáveis; um cão raramente tem mais de 5.
    return _firestore
        .collection('training_specialties')
        .where('dogId', isEqualTo: dogId)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => !_isSoftDeleted(doc.data()))
              .map((doc) => TrainingSpecialtyModel.fromJson(doc.data(), doc.id))
              .where(
                (specialty) =>
                    specialty.dogId.isEmpty || specialty.dogId == dogId,
              )
              .toList(),
        )
        .handleError((_) => <TrainingSpecialtyModel>[]);
  }

  Stream<List<TrainingSpecialtyModel>> _watchDogSpecialties(String dogId) {
    // limit(20): subcoleção de especialidades por cão; conjunto pequeno.
    return _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('specialties')
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => !_isSoftDeleted(doc.data()))
              .map(
                (doc) => TrainingSpecialtyModel.fromDogSpecialty(
                  doc.data(),
                  doc.id,
                  dogId,
                ),
              )
              .toList(),
        )
        .handleError((_) => <TrainingSpecialtyModel>[]);
  }

  Stream<List<T>> _combineLatestLists<T>(
    List<Stream<List<T>>> streams,
    List<T> Function(List<List<T>> lists) merge,
  ) {
    late final StreamController<List<T>> controller;
    final latest = List<List<T>>.generate(streams.length, (_) => <T>[]);
    final subscriptions = <StreamSubscription<List<T>>>[];

    void emit() {
      if (!controller.isClosed) {
        controller.add(merge(latest));
      }
    }

    controller = StreamController<List<T>>(
      onListen: () {
        emit();
        for (var i = 0; i < streams.length; i++) {
          subscriptions.add(
            streams[i].listen(
              (items) {
                latest[i] = items;
                emit();
              },
              onError: (_) {
                latest[i] = <T>[];
                emit();
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  bool _isSoftDeleted(Map<String, dynamic> data) {
    return data['deleted_at'] != null ||
        data['archived_at'] != null ||
        data['active'] == false;
  }
}
