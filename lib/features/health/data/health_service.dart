import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'package:canil_gcm/core/services/audit_service.dart';

class HealthService {
  HealthService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<HealthLogModel> addHealthLog(HealthLogModel log) async {
    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = {
      ...log.toJson(),
      'audit_trail': [entry],
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    final docRef = await _firestore
        .collection('dogs')
        .doc(log.dogId)
        .collection('health_events')
        .add(data);
    return HealthLogModel.fromJson(data, docRef.id);
  }

  Future<void> updateHealthLog(HealthLogModel log) async {
    if (log.id == null) return;
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await _firestore
        .collection('dogs')
        .doc(log.dogId)
        .collection('health_events')
        .doc(log.id)
        .set({
          ...log.toJson(),
          'updated_at': FieldValue.serverTimestamp(),
          'audit_trail': FieldValue.arrayUnion([entry]),
        }, SetOptions(merge: true));
  }

  Future<void> deleteHealthLog({
    required String dogId,
    required String id,
    required String userId,
    required String reason,
  }) async {
    final docRef = _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events')
        .doc(id);

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': userId,
      'delete_reason': reason,
      'deleted_reason': reason,
      'audit_trail': FieldValue.arrayUnion([entry]),
    });
  }

  Future<List<HealthLogModel>> getHealthLogsForDog(String dogId) async {
    final query = _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events');

    final activeQuery = SoftDeletable.activeOnly(query);
    final snapshot = await activeQuery.get();

    final logs = snapshot.docs
        .map((doc) => HealthLogModel.fromJson(doc.data(), doc.id))
        .toList();
    logs.sort((a, b) => b.date.compareTo(a.date));
    return logs;
  }
}
