import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/occurrences/domain/amendment.dart';

/// Repositório para operações CRUD na subcoleção
/// `occurrences/{occurrenceId}/amendments/{amendmentId}`.
class AmendmentRepository {
  final FirebaseFirestore _firestore;

  AmendmentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _amendmentsCollection(
    String occurrenceId,
  ) {
    return _firestore
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('amendments');
  }

  /// Cria um aditamento na subcoleção.
  /// Valida que o usuário atual é o titular original ou um integrante que
  /// assinou a ocorrência pela subcoleção canônica de assinaturas.
  /// Não toca no documento da ocorrência; o hash original permanece intacto.
  Future<Amendment> create({
    required String occurrenceId,
    required String reason,
    required Map<String, AmendmentCorrection> corrections,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final authorRa = HandlerIdentityService.raFromUser(user);
    if (authorRa == null || authorRa.isEmpty) {
      throw StateError('Não foi possível identificar o RA do usuário.');
    }

    final occRef = _firestore.collection('occurrences').doc(occurrenceId);
    final occDoc = await occRef.get();
    if (!occDoc.exists) {
      throw StateError('Ocorrência não encontrada.');
    }

    final occData = occDoc.data()!;
    final status = occData['status'] as String?;
    if (status != 'finalized' && status != 'finalized_with_pending') {
      throw StateError(
        'Retificações só podem ser criadas em ocorrências finalizadas.',
      );
    }

    final primaryHandlerId = occData['primary_handler_id']?.toString();
    final primaryHandlerRa = occData['primary_handler_ra']?.toString();
    final teamHandlerIds = _teamHandlerIdsFrom(occData);

    final userIsHandlerOriginal =
        primaryHandlerId == user.uid || primaryHandlerRa == authorRa;
    final userIsSignedMember =
        !userIsHandlerOriginal &&
        teamHandlerIds.contains(authorRa) &&
        await _hasSignedOccurrence(occurrenceId, authorRa);

    if (!userIsHandlerOriginal && !userIsSignedMember) {
      throw StateError(
        'Apenas o condutor titular ou integrantes que assinaram podem criar retificações.',
      );
    }

    final existingAmendments = await _amendmentsCollection(
      occurrenceId,
    ).orderBy('sequence_number', descending: true).limit(1).get();

    final nextSequence = existingAmendments.docs.isEmpty
        ? 1
        : ((existingAmendments.docs.first.data()['sequence_number'] as num?)
                      ?.toInt() ??
                  0) +
              1;

    final now = DateTime.now();
    final name = user.displayName ?? 'Condutor $authorRa';
    final hash = Amendment.computeHash(
      occurrenceId: occurrenceId,
      reason: reason,
      corrections: corrections,
      createdBy: authorRa,
      createdAt: now,
      sequenceNumber: nextSequence,
    );

    final amendment = Amendment(
      id: '',
      occurrenceId: occurrenceId,
      reason: reason,
      corrections: corrections,
      createdBy: authorRa,
      createdByName: name,
      createdByRa: authorRa,
      createdAt: now,
      integrityHash: hash,
      sequenceNumber: nextSequence,
    );

    final docRef = await _amendmentsCollection(
      occurrenceId,
    ).add(amendment.toMap());

    AuditService.log(
      action: 'amendment_created',
      entityType: 'occurrence',
      entityId: occurrenceId,
      summary: 'Retificação #$nextSequence criada: $reason',
      after: {
        'amendment_id': docRef.id,
        'sequence_number': nextSequence,
        'integrity_hash': hash,
        'corrections_count': corrections.length,
      },
    );

    return Amendment(
      id: docRef.id,
      occurrenceId: occurrenceId,
      reason: reason,
      corrections: corrections,
      createdBy: authorRa,
      createdByName: name,
      createdByRa: authorRa,
      createdAt: now,
      integrityHash: hash,
      sequenceNumber: nextSequence,
    );
  }

  /// Lista todos os aditamentos de uma ocorrência, ordenados cronologicamente.
  Future<List<Amendment>> listByOccurrence(String occurrenceId) async {
    final snapshot = await _amendmentsCollection(
      occurrenceId,
    ).orderBy('sequence_number').get();

    return snapshot.docs
        .map((doc) => Amendment.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Obtém um aditamento específico.
  Future<Amendment?> getById(String occurrenceId, String amendmentId) async {
    final doc = await _amendmentsCollection(
      occurrenceId,
    ).doc(amendmentId).get();
    if (!doc.exists) return null;
    return Amendment.fromMap(doc.data()!, doc.id);
  }

  /// Stream de aditamentos para escuta em tempo real.
  Stream<List<Amendment>> watchByOccurrence(String occurrenceId) {
    return _amendmentsCollection(occurrenceId)
        .orderBy('sequence_number')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Amendment.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<bool> _hasSignedOccurrence(
    String occurrenceId,
    String handlerId,
  ) async {
    final doc = await _firestore
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('signatures')
        .doc(handlerId)
        .get();
    final data = doc.data();
    if (data == null) return false;
    return OccurrenceSignature.fromJson(data).status == SignatureStatus.signed;
  }

  static Set<String> _teamHandlerIdsFrom(Map<String, dynamic> occData) {
    final explicitIds = occData['team_handler_ids'];
    if (explicitIds is List) {
      return explicitIds.map((value) => value.toString()).toSet();
    }

    final team = occData['team'];
    if (team is! List) return const {};
    return team
        .whereType<Map>()
        .map(
          (member) =>
              member['handler_id']?.toString() ??
              member['handlerId']?.toString(),
        )
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet();
  }
}
