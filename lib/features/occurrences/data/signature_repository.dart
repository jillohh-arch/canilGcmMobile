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

  String _signatureDocId(OccurrenceSignature signature) {
    return signature.round <= 1
        ? signature.handlerId
        : 'round_${signature.round}_${signature.handlerId}';
  }

  Future<int> _currentRound(String occurrenceId) async {
    final snapshot = await _occurrence(occurrenceId).get();
    final raw = snapshot.data()?['signature_round'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw) ?? 1;
    return 1;
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

    await _signatures(occurrenceId).doc(_signatureDocId(signature)).set({
      ...signature.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await _occurrence(
        occurrenceId,
      ).update({'updated_at': FieldValue.serverTimestamp()});
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      debugPrint(
        '[SignatureRepository] Assinatura salva; metadado da ocorrencia bloqueado por rules.',
      );
    }
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

  Future<List<OccurrenceSignature>> getSignatures(
    String occurrenceId, {
    bool activeRoundOnly = true,
  }) async {
    final snapshot = await _signatures(
      occurrenceId,
    ).orderBy('handler_id').get();
    final signatures = snapshot.docs
        .map((doc) => OccurrenceSignature.fromJson(doc.data()))
        .toList();
    if (!activeRoundOnly) return signatures;
    final round = await _currentRound(occurrenceId);
    return signatures
        .where(
          (signature) =>
              signature.round == round &&
              signature.status != SignatureStatus.obsolete,
        )
        .toList();
  }

  Future<List<OccurrenceSignature>> getAllSignatures(String occurrenceId) {
    return getSignatures(occurrenceId, activeRoundOnly: false);
  }

  Stream<List<OccurrenceSignature>> watchSignatures({
    required String occurrenceId,
  }) {
    return _signatures(occurrenceId)
        .orderBy('handler_id')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OccurrenceSignature.fromJson(doc.data()))
              .where(
                (signature) => signature.status != SignatureStatus.obsolete,
              )
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
      final signature = OccurrenceSignature.fromJson(data);
      return signature.status == SignatureStatus.signed;
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

    final round = await _currentRound(occurrenceId);
    final signature = OccurrenceSignature(
      handlerId: handlerId,
      status: SignatureStatus.expired,
      reason: reason,
      round: round,
    );

    await _signatures(occurrenceId).doc(_signatureDocId(signature)).set({
      ...OccurrenceSignature(
        handlerId: handlerId,
        status: SignatureStatus.expired,
        reason: reason,
        round: round,
      ).toJson(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _occurrence(
      occurrenceId,
    ).update({'updated_at': FieldValue.serverTimestamp()});
  }

  Future<void> invalidateCurrentRound({
    required String occurrenceId,
    required String invalidatedBy,
    required String reason,
  }) async {
    debugPrint('[SignatureRepository] Invalidando rodada de $occurrenceId');

    final round = await _currentRound(occurrenceId);
    final snapshot = await _signatures(
      occurrenceId,
    ).where('round', isEqualTo: round).get();
    final batch = _firestore.batch();
    final invalidatedAt = FieldValue.serverTimestamp();
    for (final doc in snapshot.docs) {
      batch.set(doc.reference, {
        'status': SignatureStatus.obsolete.toMap(),
        'invalidated_at': invalidatedAt,
        'invalidated_by': invalidatedBy,
        'invalidation_reason': reason,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    batch.update(_occurrence(occurrenceId), {
      'signature_request_at': null,
      'signature_deadline': null,
      'signature_round': round + 1,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
