import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';

class SignatureRepository {
  SignatureRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _signatures(String occurrenceId) {
    return _firestore
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('signatures');
  }

  DocumentReference<Map<String, dynamic>> _occurrence(String occurrenceId) {
    return _firestore.collection('occurrences').doc(occurrenceId);
  }

  /// Adiciona ou atualiza a assinatura canonica em
  /// occurrences/{occurrenceId}/signatures/{ra}.
  Future<void> addSignature({
    required String occurrenceId,
    required OccurrenceSignature signature,
  }) async {
    debugPrint(
      '[SignatureRepository] Salvando assinatura de ${signature.handlerId} em $occurrenceId',
    );

    await _signatures(occurrenceId).doc(signature.handlerId).set({
      ...signature.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _occurrence(occurrenceId).update({
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSignature({
    required String occurrenceId,
    required String handlerId,
    required OccurrenceSignature signature,
  }) async {
    await addSignature(
      occurrenceId: occurrenceId,
      signature: signature.copyWith(handlerId: handlerId),
    );
  }

  Future<List<OccurrenceSignature>> getSignatures(String occurrenceId) async {
    final snapshot = await _signatures(occurrenceId).orderBy('handler_id').get();
    return snapshot.docs
        .map((doc) => OccurrenceSignature.fromJson(doc.data()))
        .toList();
  }

  Stream<List<OccurrenceSignature>> watchSignatures({
    required String occurrenceId,
  }) {
    return _signatures(occurrenceId).orderBy('handler_id').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => OccurrenceSignature.fromJson(doc.data()))
              .toList(),
        );
  }

  Stream<bool> hasUserSigned({
    required String occurrenceId,
    required String handlerId,
  }) {
    return _signatures(occurrenceId).doc(handlerId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return false;
      return OccurrenceSignature.fromJson(data).status == SignatureStatus.signed;
    });
  }

  Stream<int> getPendingSignaturesCount({
    required String occurrenceId,
    required int teamSize,
  }) {
    return watchSignatures(occurrenceId: occurrenceId).map((signatures) {
      final signedCount = signatures
          .where((signature) => signature.status == SignatureStatus.signed)
          .length;
      return ((teamSize - 1) - signedCount).clamp(0, teamSize).toInt();
    });
  }

  Stream<bool> areAllSignaturesCollected({
    required String occurrenceId,
    required int teamSize,
  }) {
    return watchSignatures(occurrenceId: occurrenceId).map((signatures) {
      final signedCount = signatures
          .where((signature) => signature.status == SignatureStatus.signed)
          .length;
      return signedCount >= teamSize - 1;
    });
  }

  Future<void> markSignatureExpired({
    required String occurrenceId,
    required String handlerId,
    String? reason,
  }) async {
    debugPrint(
      '[SignatureRepository] Marcando assinatura expirada para $handlerId em $occurrenceId',
    );

    await _signatures(occurrenceId).doc(handlerId).set({
      ...OccurrenceSignature(
        handlerId: handlerId,
        status: SignatureStatus.expired,
        reason: reason,
      ).toJson(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _occurrence(occurrenceId).update({
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearAllSignatures({required String occurrenceId}) async {
    debugPrint('[SignatureRepository] Limpando assinaturas de $occurrenceId');

    final snapshot = await _signatures(occurrenceId).get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.update(_occurrence(occurrenceId), {
      'signature_request_at': null,
      'signature_deadline': null,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
