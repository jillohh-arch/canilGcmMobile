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
    final docRef = _firestore
        .collection('dogs')
        .doc(log.dogId)
        .collection('health_events')
        .doc(log.id);
    final before = (await docRef.get()).data();
    final after = log.toJson();
    final entry = AuditService.buildInlineEntry(
      action: 'updated',
      oldValue: before == null ? null : _auditHealthSnapshot(before),
      newValue: _auditHealthSnapshot(after),
    );
    await docRef.set({
      ...after,
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

  Map<String, dynamic> _auditHealthSnapshot(Map<String, dynamic> data) {
    return {
      if (data['dogId'] != null) 'dogId': data['dogId'],
      if (data['dogName'] != null) 'dogName': data['dogName'],
      if (data['date'] != null) 'date': data['date'],
      if (data['type'] != null) 'type': data['type'],
      if (data['subtype'] != null) 'subtype': data['subtype'],
      if (data['weight'] != null) 'weight': data['weight'],
      if (data['healthObservations'] != null)
        'healthObservations': data['healthObservations'],
      if (data['nextDueDate'] != null) 'nextDueDate': data['nextDueDate'],
      if (data['professionalCrmv'] != null)
        'professionalCrmv': data['professionalCrmv'],
      if (data['professionalClinic'] != null)
        'professionalClinic': data['professionalClinic'],
      if (data['attachmentUrl'] != null) 'attachmentUrl': data['attachmentUrl'],
      if (data['costBrl'] != null) 'costBrl': data['costBrl'],
      if (data['createdBy'] != null) 'createdBy': data['createdBy'],
      if (data['vetName'] != null) 'vetName': data['vetName'],
      if (data['mediaAttachments'] != null)
        'mediaAttachments': data['mediaAttachments'],
    };
  }
}
