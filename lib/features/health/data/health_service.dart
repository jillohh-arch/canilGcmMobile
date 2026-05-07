import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/domain/health_log_model.dart';

class HealthService {
  HealthService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<HealthLogModel> addHealthLog(HealthLogModel log) async {
    final docRef = await _firestore.collection('health_logs').add(log.toJson());
    return HealthLogModel.fromJson(log.toJson(), docRef.id);
  }

  Future<void> updateHealthLog(HealthLogModel log) async {
    if (log.id == null) return;
    await _firestore
        .collection('health_logs')
        .doc(log.id)
        .set(log.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteHealthLog(String id) {
    return _firestore.collection('health_logs').doc(id).delete();
  }

  Future<List<HealthLogModel>> getHealthLogsForDog(String dogId) async {
    final snapshot = await _firestore
        .collection('health_logs')
        .where('dogId', isEqualTo: dogId)
        .get();

    final logs = snapshot.docs
        .map((doc) => HealthLogModel.fromJson(doc.data(), doc.id))
        .toList();
    logs.sort((a, b) => b.date.compareTo(a.date));
    return logs;
  }
}
