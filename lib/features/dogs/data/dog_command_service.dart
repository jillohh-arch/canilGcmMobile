import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/dogs/domain/dog_command.dart';

/// Service para gerenciar a biblioteca de comandos do cão.
/// Subcoleção: /dogs/{dogId}/commands
class DogCommandService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('commands');

  /// Stream de todos os comandos do cão.
  Stream<List<DogCommand>> watchCommands(String dogId) {
    return _collection(dogId)
        .orderBy('category')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DogCommand.fromJson(doc.data(), docId: doc.id))
            .toList());
  }

  /// Busca todos os comandos do cão (one-shot).
  Future<List<DogCommand>> getCommands(String dogId) async {
    final snap = await _collection(dogId).orderBy('category').get();
    return snap.docs
        .map((doc) => DogCommand.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Adiciona um novo comando à biblioteca.
  Future<String> addCommand(String dogId, DogCommand command) async {
    final docRef = await _collection(dogId).add(command.toJson());
    return docRef.id;
  }

  /// Atualiza um comando existente.
  Future<void> updateCommand(String dogId, DogCommand command) async {
    if (command.id == null) return;
    await _collection(dogId).doc(command.id).update(command.toJson());
  }

  /// Remove um comando (soft delete via audit, hard delete aqui).
  Future<void> deleteCommand(String dogId, String commandId) async {
    await _collection(dogId).doc(commandId).delete();
  }

  /// Verifica se já existe comando com o mesmo nome.
  Future<bool> commandExists(String dogId, String name) async {
    final snap = await _collection(dogId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }
}