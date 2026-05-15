import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/conditioning/domain/conditioning_session.dart';

/// Service para gerenciar sessões de condicionamento físico.
class ConditioningService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('conditioning_sessions');

  /// Stream de sessões recentes.
  Stream<List<ConditioningSession>> watchRecentSessions(
    String dogId, {
    int limit = 10,
  }) {
    return _collection(dogId)
        .orderBy('performed_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) =>
                ConditioningSession.fromJson(doc.data(), docId: doc.id))
            .toList());
  }

  /// Busca sessões por período.
  Future<List<ConditioningSession>> getSessions(
    String dogId, {
    DateTime? from,
    DateTime? to,
    String? exerciseType,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query =
        _collection(dogId).orderBy('performed_at', descending: true);

    if (from != null) {
      query = query.where('performed_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
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
    final docRef = await _collection(dogId).add(session.toJson());
    return docRef.id;
  }

  /// Atualiza sessão existente.
  Future<void> updateSession(String dogId, ConditioningSession session) async {
    if (session.id == null) return;
    await _collection(dogId).doc(session.id).update(session.toJson());
  }

  /// Resumo semanal (total sessões, horas, km).
  Future<Map<String, dynamic>> getWeeklySummary(String dogId) async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final sessions = await getSessions(dogId, from: start);

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
}