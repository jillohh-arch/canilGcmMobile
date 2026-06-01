import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog_command.dart';

/// Service para gerenciar a biblioteca de comandos do cão.
/// Subcoleção: /dogs/{dogId}/commands
class DogCommandService {
  DogCommandService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('commands');

  /// Stream de todos os comandos do cão.
  Stream<List<DogCommand>> watchCommands(String dogId) {
    return _collection(dogId)
        .orderBy('category')
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => DogCommand.fromJson(doc.data(), docId: doc.id))
              .where((command) => !command.isDeleted)
              .toList(),
        );
  }

  /// Busca todos os comandos do cão (one-shot).
  Future<List<DogCommand>> getCommands(String dogId) async {
    final snap = await _collection(dogId).orderBy('category').get();
    return snap.docs
        .map((doc) => DogCommand.fromJson(doc.data(), docId: doc.id))
        .where((command) => !command.isDeleted)
        .toList();
  }

  /// Adiciona um novo comando à biblioteca.
  Future<String> addCommand(String dogId, DogCommand command) async {
    final docRef = _collection(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    await docRef.set({
      ...command.toJson(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': [entry],
    });
    return docRef.id;
  }

  /// Atualiza um comando existente.
  Future<void> updateCommand(String dogId, DogCommand command) async {
    if (command.id == null) return;
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await _collection(dogId).doc(command.id).set({
      ...command.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
  }

  /// Remove um comando sem apagar o histórico operacional do cão.
  Future<void> deleteCommand(
    String dogId,
    String commandId, {
    String reason = 'Comando removido da biblioteca operacional do K9.',
  }) async {
    final docRef = _collection(dogId).doc(commandId);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': 'mobile',
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    await AuditService.log(
      action: 'deleted',
      entityType: 'dog_command',
      entityId: commandId,
      summary: 'Comando do K9 removido: $reason',
      reason: reason,
      before: {...?snap.data(), 'dog_id': dogId},
    );
  }

  /// Verifica se já existe comando com o mesmo nome.
  Future<bool> commandExists(String dogId, String name) async {
    final snap = await _collection(dogId).where('name', isEqualTo: name).get();
    return snap.docs.any((doc) => doc.data()['deleted_at'] == null);
  }
}
