import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
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
  /// Valida que o usuário atual é o handler original da ocorrência.
  /// Não toca no documento da ocorrência (hash original intacto).
  Future<Amendment> create({
    required String occurrenceId,
    required String reason,
    required Map<String, AmendmentCorrection> corrections,
  }) async {
    // Validar que o usuário é o handler original
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }

    final occDoc = await _firestore
        .collection('occurrences')
        .doc(occurrenceId)
        .get();

    if (!occDoc.exists) {
      throw StateError('Ocorrência não encontrada.');
    }

    final occData = occDoc.data()!;
    final primaryHandlerId = occData['primary_handler_id'] as String?;

    if (primaryHandlerId != user.uid) {
      throw StateError(
        'Apenas o condutor titular pode criar retificações.',
      );
    }

    // Verificar que a ocorrência está finalizada
    final status = occData['status'] as String?;
    if (status != 'finalized') {
      throw StateError(
        'Retificações só podem ser criadas em ocorrências finalizadas.',
      );
    }

    // Determinar o próximo sequence_number
    final existingAmendments = await _amendmentsCollection(occurrenceId)
        .orderBy('sequence_number', descending: true)
        .limit(1)
        .get();

    final nextSequence = existingAmendments.docs.isEmpty
        ? 1
        : ((existingAmendments.docs.first.data()['sequence_number'] as num?)
                    ?.toInt() ??
                0) +
            1;

    final now = DateTime.now();
    final email = user.email ?? 'desconhecido';
    final ra = email.contains('@') ? email.split('@')[0] : email;
    final name = user.displayName ?? ra;

    // Calcular hash de integridade do aditamento
    final hash = Amendment.computeHash(
      occurrenceId: occurrenceId,
      reason: reason,
      corrections: corrections,
      createdBy: user.uid,
      createdAt: now,
      sequenceNumber: nextSequence,
    );

    final amendment = Amendment(
      id: '', // será preenchido pelo Firestore
      occurrenceId: occurrenceId,
      reason: reason,
      corrections: corrections,
      createdBy: user.uid,
      createdByName: name,
      createdByRa: ra,
      createdAt: now,
      integrityHash: hash,
      sequenceNumber: nextSequence,
    );

    // Gravar na subcoleção
    final docRef = await _amendmentsCollection(occurrenceId).add(
      amendment.toMap(),
    );

    // Log de auditoria (fire-and-forget)
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
      createdBy: user.uid,
      createdByName: name,
      createdByRa: ra,
      createdAt: now,
      integrityHash: hash,
      sequenceNumber: nextSequence,
    );
  }

  /// Lista todos os aditamentos de uma ocorrência, ordenados cronologicamente.
  Future<List<Amendment>> listByOccurrence(String occurrenceId) async {
    final snapshot = await _amendmentsCollection(occurrenceId)
        .orderBy('sequence_number')
        .get();

    return snapshot.docs
        .map((doc) => Amendment.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Obtém um aditamento específico.
  Future<Amendment?> getById(String occurrenceId, String amendmentId) async {
    final doc =
        await _amendmentsCollection(occurrenceId).doc(amendmentId).get();
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
}
