import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/users/domain/user.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

  Stream<List<UserModel>> getUsers() {
    return _db.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => !_isDeleted(doc.data()))
          .map((doc) => UserModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  Future<void> saveUser(UserModel user) async {
    final docRef = _db.collection('users').doc(user.ra);
    final snapshot = await docRef.get();
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await docRef.set({
      ...user.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': snapshot.exists ? FieldValue.arrayUnion([entry]) : [entry],
    }, SetOptions(merge: true));
  }

  Future<void> deleteUser(
    String ra, {
    String reason = 'Exclusao administrativa do cadastro do usuario',
  }) async {
    final docRef = _db.collection('users').doc(ra);
    final snapshot = await docRef.get();
    final before = snapshot.data();
    if (!snapshot.exists || before == null) return;

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'active': false,
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': FirebaseAuth.instance.currentUser?.uid,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    await AuditService.log(
      action: 'deleted',
      entityType: 'user',
      entityId: ra,
      summary: 'Usuario removido do cadastro ativo: $reason',
      before: before,
      reason: reason,
    );
  }

  Future<UserModel?> getUser(String ra) async {
    final doc = await _db.collection('users').doc(ra).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    if (_isDeleted(data)) return null;
    return UserModel.fromJson({...data, 'id': doc.id});
  }

  Future<Map<String, dynamic>> setK9InstructorRole({
    required String ra,
    required bool enabled,
  }) async {
    final callable = _functions.httpsCallable('setK9InstructorRole');
    final result = await callable.call<Map<String, dynamic>>({
      'ra': ra,
      'enabled': enabled,
    });
    final currentRa = FirebaseAuth.instance.currentUser?.email
        ?.replaceAll('@canilgcm.com', '')
        .replaceAll('@gcm.com.br', '')
        .trim();
    if (currentRa == ra) {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    }
    return result.data;
  }

  bool _isDeleted(Map<String, dynamic> data) {
    return data['deleted_at'] != null || data['active'] == false;
  }
}
