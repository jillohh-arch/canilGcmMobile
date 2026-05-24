import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_formation_session.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_line.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';
import 'package:canil_gcm/features/training/domain/detection/training_attempt.dart';

class DetectionService {
  DetectionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _linesCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('detection_lines');

  CollectionReference<Map<String, dynamic>> _sessionsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('training_sessions');

  CollectionReference<Map<String, dynamic>> _attemptsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('training_attempts');

  Stream<List<DetectionLine>> watchLines(String dogId) {
    return _linesCol(dogId).snapshots().map(
      (snap) =>
          snap.docs
              .map((doc) => DetectionLine.fromJson(doc.data(), docId: doc.id))
              .where((line) => !line.isDeleted)
              .toList()
            ..sort(_sortLines),
    );
  }

  Future<List<DetectionLine>> getLines(String dogId) async {
    final snap = await _linesCol(dogId).get();
    final lines =
        snap.docs
            .map((doc) => DetectionLine.fromJson(doc.data(), docId: doc.id))
            .where((line) => !line.isDeleted)
            .toList()
          ..sort(_sortLines);
    return lines;
  }

  Future<List<DetectionLine>> getOrCreateDefaultLines({
    required String dogId,
    required String handlerId,
    required String handlerName,
  }) async {
    final existing = await getLines(dogId);
    if (existing.isNotEmpty) return existing;

    final now = DateTime.now();
    final defaults = [
      DetectionLine(
        id: 'drogas',
        type: 'drogas',
        status: 'in_formation',
        currentPhase: '1b',
        startedAt: now,
        updatedAt: now,
        auditTrail: [
          _auditEntry(
            action: 'created',
            handlerId: handlerId,
            handlerName: handlerName,
            reason: 'Linha padrão criada para início da formação.',
          ),
        ],
      ),
      DetectionLine(
        id: 'armas',
        type: 'armas',
        status: 'not_started',
        currentPhase: '1b',
        updatedAt: now,
        auditTrail: [
          _auditEntry(
            action: 'created',
            handlerId: handlerId,
            handlerName: handlerName,
            reason: 'Linha padrão disponível para formação futura.',
          ),
        ],
      ),
      DetectionLine(
        id: 'cadaver',
        type: 'cadaver',
        status: 'not_started',
        currentPhase: '1b',
        updatedAt: now,
        auditTrail: [
          _auditEntry(
            action: 'created',
            handlerId: handlerId,
            handlerName: handlerName,
            reason: 'Linha padrão disponível para formação futura.',
          ),
        ],
      ),
    ];

    final batch = _firestore.batch();
    for (final line in defaults) {
      batch.set(_linesCol(dogId).doc(line.id), line.toJson());
    }
    await batch.commit();

    await AuditService.log(
      action: 'created',
      entityType: 'detection_line',
      entityId: dogId,
      summary: 'Linhas padrão de detecção criadas',
      after: {
        'dogId': dogId,
        'lines': defaults.map((line) => line.type).toList(),
      },
    );

    return defaults;
  }

  Future<String> addLine(String dogId, DetectionLine line) async {
    final docId = line.id ?? line.normalizedType;
    await _linesCol(dogId).doc(docId).set(line.toJson());
    return docId;
  }

  Future<void> updateLine(String dogId, DetectionLine line) async {
    if (line.id == null) return;
    await _linesCol(dogId)
        .doc(line.id)
        .set(
          line.copyWith(updatedAt: DateTime.now()).toJson(),
          SetOptions(merge: true),
        );
  }

  Future<DetectionLine> ensureLineStarted({
    required String dogId,
    required DetectionLine line,
    required String handlerId,
    required String handlerName,
  }) async {
    if (line.status != 'not_started') return line;

    final now = DateTime.now();
    final docId = line.id ?? line.normalizedType;
    final entry = _auditEntry(
      action: 'started',
      handlerId: handlerId,
      handlerName: handlerName,
      reason: 'Formação iniciada no Protocolo Ragonha.',
    );
    final updated = line.copyWith(
      id: docId,
      status: 'in_formation',
      currentPhase: '1b',
      startedAt: line.startedAt ?? now,
      updatedAt: now,
      auditTrail: [...line.auditTrail, entry],
    );

    await _linesCol(
      dogId,
    ).doc(docId).set(updated.toJson(), SetOptions(merge: true));
    await AuditService.log(
      action: 'updated',
      entityType: 'detection_line',
      entityId: docId,
      summary: 'Linha ${updated.displayName} iniciada para formação',
      before: {'status': line.status, 'current_phase': line.currentPhase},
      after: {'status': updated.status, 'current_phase': updated.currentPhase},
    );

    return updated;
  }

  Future<DetectionFormationSession> saveFormationSession({
    required String dogId,
    required String dogName,
    required DetectionLine line,
    required DetectionPhaseConfig phase,
    required DateTime startedAt,
    required DetectionSessionRecorder recorder,
    required bool advancePhase,
    required String handlerId,
    required String handlerName,
    String notes = '',
    String? odorMaterial,
  }) async {
    final endedAt = DateTime.now();
    final sessionRef = _sessionsCol(dogId).doc();
    final lineDocId = line.id ?? line.normalizedType;
    final nextPhase = advancePhase
        ? DetectionPhaseCatalog.nextAfter(phase.code)
        : null;

    final createEntry = _auditEntry(
      action: 'created',
      handlerId: handlerId,
      handlerName: handlerName,
      reason: 'Sessão de formação registrada.',
      metadata: {
        'phase': phase.code,
        'line': line.displayName,
        'total_reps': recorder.totalReps,
      },
    );

    final session = DetectionFormationSession.fromRecorder(
      id: sessionRef.id,
      dogId: dogId,
      dogName: dogName,
      lineId: lineDocId,
      lineName: line.displayName,
      lineType: line.normalizedType,
      phase: phase,
      startedAt: startedAt,
      endedAt: endedAt,
      recorder: recorder,
      phaseAdvanced: advancePhase,
      advancedTo: nextPhase?.code,
      handlerId: handlerId,
      handlerName: handlerName,
      notes: notes,
      odorMaterial: odorMaterial,
      auditTrail: [createEntry],
    );

    final batch = _firestore.batch();
    batch.set(sessionRef, session.toJson());

    final lineRef = _linesCol(dogId).doc(lineDocId);
    final lineUpdates = <String, dynamic>{
      'best_streak': recorder.longestStreak > line.bestStreak
          ? recorder.longestStreak
          : line.bestStreak,
      'consecutive_hits': 0,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([
        _auditEntry(
          action: advancePhase ? 'phase_advanced' : 'session_recorded',
          handlerId: handlerId,
          handlerName: handlerName,
          reason: advancePhase
              ? 'Critério atingido e avanço manual confirmado.'
              : 'Sessão registrada sem avanço de fase.',
          metadata: {
            'session_id': sessionRef.id,
            'phase': phase.code,
            'current_streak': recorder.currentStreak,
            'longest_streak': recorder.longestStreak,
          },
        ),
      ]),
    };

    if (advancePhase && nextPhase != null) {
      final completed = {...line.phasesCompleted, phase.code}.toList();
      lineUpdates.addAll({
        'current_phase': nextPhase.code,
        'phases_completed': completed,
        'status': nextPhase.code == 'final'
            ? 'operational_ready'
            : 'in_formation',
        'phase_history': FieldValue.arrayUnion([
          {
            'from_phase': phase.code,
            'to_phase': nextPhase.code,
            'session_id': sessionRef.id,
            'at': Timestamp.fromDate(DateTime.now()),
            'by': handlerId,
            'by_ra': handlerId,
            'by_name': handlerName,
          },
        ]),
      });
    }

    batch.set(lineRef, lineUpdates, SetOptions(merge: true));
    await batch.commit();

    await AuditService.log(
      action: 'created',
      entityType: 'training_session',
      entityId: sessionRef.id,
      summary:
          'Sessão de formação ${line.displayName} ${phase.code} registrada para $dogName',
      after: session.toJson(),
    );

    if (advancePhase && nextPhase != null) {
      await AuditService.log(
        action: 'updated',
        entityType: 'detection_line',
        entityId: lineDocId,
        summary:
            'Linha ${line.displayName} avançou de ${phase.code} para ${nextPhase.code}',
        before: {'current_phase': phase.code},
        after: {'current_phase': nextPhase.code, 'session_id': sessionRef.id},
      );
    }

    return session;
  }

  Future<void> softDeleteFormationSession({
    required String dogId,
    required String sessionId,
    required String reason,
    required String handlerId,
    required String handlerName,
  }) async {
    final ref = _sessionsCol(dogId).doc(sessionId);
    final before = await ref.get();
    await ref.set({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': handlerId,
      'deleted_reason': reason,
      'delete_reason': reason,
      'audit_trail': FieldValue.arrayUnion([
        _auditEntry(
          action: 'deleted',
          handlerId: handlerId,
          handlerName: handlerName,
          reason: reason,
        ),
      ]),
    }, SetOptions(merge: true));

    await AuditService.log(
      action: 'deleted',
      entityType: 'training_session',
      entityId: sessionId,
      summary: 'Sessão de formação excluída: $reason',
      before: before.data(),
      reason: reason,
    );
  }

  Future<DetectionLine> registerHit(String dogId, DetectionLine line) async {
    final newConsecutive = line.consecutiveHits + 1;
    final newBest = newConsecutive > line.bestStreak
        ? newConsecutive
        : line.bestStreak;
    final updated = line.copyWith(
      consecutiveHits: newConsecutive,
      bestStreak: newBest,
      updatedAt: DateTime.now(),
    );
    await updateLine(dogId, updated);
    return updated;
  }

  Future<DetectionLine> registerMiss(String dogId, DetectionLine line) async {
    final updated = line.copyWith(
      consecutiveHits: 0,
      updatedAt: DateTime.now(),
    );
    await updateLine(dogId, updated);
    return updated;
  }

  Future<String> addAttempt(String dogId, TrainingAttempt attempt) async {
    final docRef = await _attemptsCol(dogId).add(attempt.toJson());
    return docRef.id;
  }

  Future<List<TrainingAttempt>> getAttemptsForSession(
    String dogId,
    String sessionId,
  ) async {
    final snap = await _attemptsCol(
      dogId,
    ).where('session_id', isEqualTo: sessionId).orderBy('attempt_number').get();
    return snap.docs
        .map((doc) => TrainingAttempt.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  Stream<List<TrainingAttempt>> watchAttemptsForSession(
    String dogId,
    String sessionId,
  ) {
    return _attemptsCol(dogId)
        .where('session_id', isEqualTo: sessionId)
        .orderBy('attempt_number')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => TrainingAttempt.fromJson(doc.data(), docId: doc.id))
              .toList(),
        );
  }

  Map<String, dynamic> _auditEntry({
    required String action,
    required String handlerId,
    required String handlerName,
    String? reason,
    Map<String, dynamic>? metadata,
  }) {
    final entry = <String, dynamic>{
      'action': action,
      'at': Timestamp.fromDate(DateTime.now()),
      'by': handlerId,
      'by_ra': handlerId,
      'by_name': handlerName,
    };
    if (reason != null) entry['reason'] = reason;
    if (metadata != null) entry['metadata'] = metadata;
    return entry;
  }

  int _sortLines(DetectionLine a, DetectionLine b) {
    const order = {'drogas': 0, 'armas': 1, 'cadaver': 2};
    final aOrder = order[a.normalizedType] ?? 99;
    final bOrder = order[b.normalizedType] ?? 99;
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);
    return a.displayName.compareTo(b.displayName);
  }
}
