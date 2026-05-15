import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_line.dart';
import 'package:canil_gcm/features/training/domain/detection/training_attempt.dart';

/// Service para gerenciar linhas de detecção e tentativas.
class DetectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Detection Lines ──────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _linesCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('detection_lines');

  /// Stream de todas as linhas de detecção do cão.
  Stream<List<DetectionLine>> watchLines(String dogId) {
    return _linesCol(dogId).snapshots().map((snap) => snap.docs
        .map((doc) => DetectionLine.fromJson(doc.data(), docId: doc.id))
        .toList());
  }

  /// Busca todas as linhas (one-shot).
  Future<List<DetectionLine>> getLines(String dogId) async {
    final snap = await _linesCol(dogId).get();
    return snap.docs
        .map((doc) => DetectionLine.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Cria nova linha de detecção.
  Future<String> addLine(String dogId, DetectionLine line) async {
    final docRef = await _linesCol(dogId).add(line.toJson());
    return docRef.id;
  }

  /// Atualiza linha existente.
  Future<void> updateLine(String dogId, DetectionLine line) async {
    if (line.id == null) return;
    await _linesCol(dogId).doc(line.id).update(line.toJson());
  }

  /// Registra acerto — incrementa contador, verifica progressão.
  Future<DetectionLine> registerHit(String dogId, DetectionLine line) async {
    final newConsecutive = line.consecutiveHits + 1;
    final newBest =
        newConsecutive > line.bestStreak ? newConsecutive : line.bestStreak;

    String newPhase = line.currentPhase;
    String newStatus = line.status;
    DateTime? operationalSince = line.operationalSince;

    // Verifica se atingiu critério de progressão
    if (newConsecutive >= line.requiredConsecutiveHits) {
      final currentIndex = DetectionLine.phases.indexOf(line.currentPhase);
      if (currentIndex < DetectionLine.phases.length - 1) {
        newPhase = DetectionLine.phases[currentIndex + 1];
        // Se passou da fase 5, torna-se operacional
        if (newPhase == 'fase_5' &&
            newConsecutive >= 5 &&
            line.currentPhase == 'fase_5') {
          newStatus = 'operational';
          operationalSince = DateTime.now();
        }
      }
    }

    final updated = line.copyWith(
      consecutiveHits: newConsecutive,
      bestStreak: newBest,
      currentPhase: newPhase,
      status: newStatus,
      operationalSince: operationalSince,
    );

    await updateLine(dogId, updated);
    return updated;
  }

  /// Registra erro — RESET do contador a 0 (regra crítica do Protocolo Ragonha).
  Future<DetectionLine> registerMiss(String dogId, DetectionLine line) async {
    final updated = line.copyWith(consecutiveHits: 0);
    await updateLine(dogId, updated);
    return updated;
  }

  // ─── Training Attempts ────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _attemptsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('training_attempts');

  /// Registra uma tentativa individual.
  Future<String> addAttempt(String dogId, TrainingAttempt attempt) async {
    final docRef = await _attemptsCol(dogId).add(attempt.toJson());
    return docRef.id;
  }

  /// Busca tentativas de uma sessão específica.
  Future<List<TrainingAttempt>> getAttemptsForSession(
    String dogId,
    String sessionId,
  ) async {
    final snap = await _attemptsCol(dogId)
        .where('session_id', isEqualTo: sessionId)
        .orderBy('attempt_number')
        .get();
    return snap.docs
        .map((doc) => TrainingAttempt.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Stream de tentativas ao vivo (para sessão em andamento).
  Stream<List<TrainingAttempt>> watchAttemptsForSession(
    String dogId,
    String sessionId,
  ) {
    return _attemptsCol(dogId)
        .where('session_id', isEqualTo: sessionId)
        .orderBy('attempt_number')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => TrainingAttempt.fromJson(doc.data(), docId: doc.id))
            .toList());
  }
}