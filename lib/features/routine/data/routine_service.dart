import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/routine/domain/routine_model.dart';

class RoutineService {
  RoutineService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<RoutineModel> addRoutine(RoutineModel routine) async {
    final docRef = _firestore.collection('routines').doc();
    final data = routine.toJson()..['id'] = docRef.id;
    await docRef.set(data);
    return RoutineModel.fromJson(data, docRef.id);
  }

  Future<void> updateRoutine(RoutineModel routine) async {
    if (routine.id == null) return;
    await _firestore
        .collection('routines')
        .doc(routine.id)
        .set(routine.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteRoutine(String id) {
    return _firestore.collection('routines').doc(id).delete();
  }

  Future<List<RoutineModel>> getRoutinesForDog(String dogId) async {
    final snapshot = await _firestore
        .collection('routines')
        .where('dogId', isEqualTo: dogId)
        .get();

    final routines = snapshot.docs
        .map((doc) => RoutineModel.fromJson(doc.data(), doc.id))
        .toList();
    routines.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return routines;
  }
}
