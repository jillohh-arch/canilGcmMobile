import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog_specialty.dart';

/// Service para gerenciar especialidades do cão.
/// Subcoleção: /dogs/{dogId}/specialties
class DogSpecialtyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('specialties');

  /// Stream de todas as especialidades do cão.
  Stream<List<DogSpecialty>> watchSpecialties(String dogId) {
    return _collection(dogId).snapshots().map(
      (snap) => snap.docs
          .map((doc) => DogSpecialty.fromJson(doc.data(), docId: doc.id))
          .toList(),
    );
  }

  /// Busca todas as especialidades (one-shot).
  Future<List<DogSpecialty>> getSpecialties(String dogId) async {
    final snap = await _collection(dogId).get();
    return snap.docs
        .map((doc) => DogSpecialty.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Busca especialidade por tipo.
  Future<DogSpecialty?> getByType(String dogId, String type) async {
    final snap = await _collection(
      dogId,
    ).where('type', isEqualTo: type).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return DogSpecialty.fromJson(
      snap.docs.first.data(),
      docId: snap.docs.first.id,
    );
  }

  /// Inicia nova especialidade.
  Future<String> addSpecialty(String dogId, DogSpecialty specialty) async {
    final docRef = _collection(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    await docRef.set({
      ...specialty.toJson(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': [entry],
    });
    return docRef.id;
  }

  /// Atualiza especialidade (ex: mudar status para operational).
  Future<void> updateSpecialty(String dogId, DogSpecialty specialty) async {
    if (specialty.id == null) return;
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await _collection(dogId).doc(specialty.id).set({
      ...specialty.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
  }

  /// Conta especialidades ativas (in_formation ou operational).
  Future<int> countActive(String dogId) async {
    final specialties = await getSpecialties(dogId);
    return specialties.where((s) => s.isOperational || s.isInFormation).length;
  }
}
