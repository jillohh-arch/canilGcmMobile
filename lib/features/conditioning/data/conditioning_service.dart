import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/active_shift_identity_service.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/conditioning/domain/conditioning_session.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service para gerenciar sessões de condicionamento físico.
class ConditioningService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore
          .collection('dogs')
          .doc(dogId)
          .collection('conditioning_sessions');

  /// Stream de sessões recentes.
  Stream<List<ConditioningSession>> watchRecentSessions(
    String dogId, {
    int limit = 10,
  }) {
    return _collection(dogId)
        .orderBy('performed_at', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    ConditioningSession.fromJson(doc.data(), docId: doc.id),
              )
              .toList(),
        );
  }

  /// Busca sessões por período.
  Future<List<ConditioningSession>> getSessions(
    String dogId, {
    DateTime? from,
    DateTime? to,
    String? exerciseType,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = _collection(
      dogId,
    ).orderBy('performed_at', descending: true);

    if (from != null) {
      query = query.where(
        'performed_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where('performed_at', isLessThan: Timestamp.fromDate(to));
    }
    if (exerciseType != null) {
      query = query.where('exercise_type', isEqualTo: exerciseType);
    }
    if (limit != null) {
      query = query.limit(limit);
    }

    final snap = await query.get();
    return snap.docs
        .map((doc) => ConditioningSession.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Registra nova sessão de condicionamento.
  Future<String> addSession(String dogId, ConditioningSession session) async {
    final docRef = _collection(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    await docRef.set({
      ...await _sessionPayload(dogId, session),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': [entry],
    });
    return docRef.id;
  }

  /// Atualiza sessão existente.
  Future<void> updateSession(String dogId, ConditioningSession session) async {
    if (session.id == null) return;
    final entry = AuditService.buildInlineEntry(action: 'updated');
    await _collection(dogId).doc(session.id).set({
      ...await _sessionPayload(dogId, session),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));
  }

  /// Resumo semanal (total sessões, horas, km).
  Future<Map<String, dynamic>> getWeeklySummary(String dogId) async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    final sessions = await getSessions(dogId, from: start, limit: 50);

    int totalMinutes = 0;
    double totalDistance = 0;

    for (final s in sessions) {
      totalMinutes += s.durationMinutes ?? 0;
      totalDistance += s.distanceMeters ?? 0;
    }

    return {
      'session_count': sessions.length,
      'total_minutes': totalMinutes,
      'total_distance_meters': totalDistance,
    };
  }

  Future<Map<String, dynamic>> _sessionPayload(
    String dogId,
    ConditioningSession session,
  ) async {
    final activeShift = await ActiveShiftIdentityService.resolve(
      firestore: _firestore,
      preferredRa: session.performedBy,
    );
    final handlerRa =
        activeShift?.handlerId ??
        _currentHandlerRa() ??
        session.performedBy.trim();
    final payload = Map<String, dynamic>.from(session.toJson());
    payload['dogId'] = dogId;
    payload['dog_id'] = dogId;
    if (handlerRa.isNotEmpty) {
      payload['handlerId'] = handlerRa;
      payload['handler_id'] = handlerRa;
      payload['performed_by'] = handlerRa;
    }
    return payload;
  }

  String? _currentHandlerRa() {
    try {
      return HandlerIdentityService.raFromUser(
        FirebaseAuth.instance.currentUser,
      );
    } catch (_) {
      return null;
    }
  }
}
