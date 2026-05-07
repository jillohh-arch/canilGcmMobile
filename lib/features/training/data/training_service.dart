import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/training/domain/training_session_model.dart';

class TrainingService {
  TrainingService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<TrainingSessionModel> addTrainingSession(
    TrainingSessionModel session,
  ) async {
    final docRef = await _firestore
        .collection('trainings')
        .add(session.toJson());
    return TrainingSessionModel.fromJson(session.toJson(), docRef.id);
  }

  Future<void> updateTrainingSession(TrainingSessionModel session) async {
    if (session.id == null) return;
    await _firestore
        .collection('trainings')
        .doc(session.id)
        .set(session.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteTrainingSession(String id) {
    return _firestore.collection('trainings').doc(id).delete();
  }

  Future<List<TrainingSessionModel>> getTrainingsForDog(String dogId) async {
    final snapshot = await _firestore
        .collection('trainings')
        .where('dogId', isEqualTo: dogId)
        .get();

    final trainings = snapshot.docs
        .map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id))
        .toList();
    trainings.sort((a, b) => b.date.compareTo(a.date));
    return trainings;
  }

  Future<List<TrainingSessionModel>> getAllTrainings() async {
    final snapshot = await _firestore.collection('trainings').get();
    final trainings = snapshot.docs
        .map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id))
        .toList();
    trainings.sort((a, b) => b.date.compareTo(a.date));
    return trainings;
  }
}
