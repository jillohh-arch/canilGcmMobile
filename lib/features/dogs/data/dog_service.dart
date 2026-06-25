import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

class DogService {
  DogService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<Dog>> getDogs() {
    return _db.collection('dogs').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => !_isDeleted(doc.data()))
          .map((doc) => _dogFromData(doc.data(), doc.id))
          .toList();
    });
  }

  Stream<Dog?> watchDog(String id) {
    return _db.collection('dogs').doc(id).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      if (_isDeleted(data)) return null;
      return _dogFromData(data, doc.id);
    });
  }

  Future<void> saveDog(Dog dog) async {
    final docRef = _db.collection('dogs').doc(dog.id);
    final snapshot = await docRef.get();
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await docRef.set({
      ...dog.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
      'audit_trail': snapshot.exists ? FieldValue.arrayUnion([entry]) : [entry],
    }, SetOptions(merge: true));
  }

  Future<void> updateDogWeight(String id, double weight) async {
    final entry = AuditService.buildInlineEntry(
      action: 'updated',
      fieldName: 'weight',
      newValue: weight,
    );
    await _db.collection('dogs').doc(id).set({
      'weight': weight,
      'updatedAt': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDog(
    String id, {
    String reason = 'Exclusao administrativa do cadastro do cao',
  }) async {
    final docRef = _db.collection('dogs').doc(id);
    final snapshot = await docRef.get();
    final before = snapshot.data();
    if (!snapshot.exists || before == null) return;

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'active': false,
      'status': 'Inativo',
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': FirebaseAuth.instance.currentUser?.uid,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    await AuditService.log(
      action: 'deleted',
      entityType: 'dog',
      entityId: id,
      summary: 'Cao removido do cadastro ativo: $reason',
      before: before,
      reason: reason,
    );
  }

  Future<void> updateDogDates(
    String id, {
    DateTime? lastTrainingDate,
    DateTime? lastVaccineDate,
    DateTime? lastBathDate,
    double? weight,
  }) async {
    final data = <String, dynamic>{};
    if (lastTrainingDate != null) {
      data['lastTrainingDate'] = lastTrainingDate.toIso8601String();
    }
    if (lastVaccineDate != null) {
      data['lastVaccineDate'] = lastVaccineDate.toIso8601String();
    }
    if (lastBathDate != null) {
      data['lastBathDate'] = lastBathDate.toIso8601String();
    }
    if (weight != null) {
      data['weight'] = weight;
    }

    if (data.isNotEmpty) {
      final entry = AuditService.buildInlineEntry(action: 'updated');
      await _db.collection('dogs').doc(id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
        'audit_trail': FieldValue.arrayUnion([entry]),
      }, SetOptions(merge: true));
    }
  }

  Dog _dogFromData(Map<String, dynamic> data, String id) {
    final json = Map<String, dynamic>.from(data);
    json['id'] = id;
    return Dog.fromJson(json);
  }

  bool _isDeleted(Map<String, dynamic> data) {
    return data['deleted_at'] != null || data['active'] == false;
  }
}
