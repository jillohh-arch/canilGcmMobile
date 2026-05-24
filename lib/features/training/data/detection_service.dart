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

  Future<DetectionFormationSession?> getOpenFormationSession({
    required String dogId,
    required String lineId,
    required String phase,
  }) async {
    final snap = await _sessionsCol(dogId)
        .where('type', isEqualTo: 'detection_formation')
        .where('status', isEqualTo: DetectionFormationStatus.inProgress)
        .get();

    final sessions =
        snap.docs
            .map(
              (doc) =>
                  DetectionFormationSession.fromJson(doc.data(), docId: doc.id),
            )
            .where(
              (session) =>
                  session.lineId == lineId &&
                  session.phase == phase &&
                  session.deletedAt == null,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return sessions.isEmpty ? null : sessions.first;
  }

  Future<DetectionFormationSession> startFormationSession({
    required String dogId,
    required String dogName,
    required DetectionLine line,
    required DetectionPhaseConfig phase,
    required String odorMaterial,
    required String handlerId,
    required String handlerName,
  }) async {
    final lineDocId = line.id ?? line.normalizedType;
    final open = await getOpenFormationSession(
      dogId: dogId,
      lineId: lineDocId,
      phase: phase.code,
    );
    if (open != null) return open;

    final sessionRef = _sessionsCol(dogId).doc();
    final now = DateTime.now();
    final auditTrail = [
      _auditEntry(
        action: 'created',
        handlerId: handlerId,
        handlerName: handlerName,
        reason: 'Sessão de formação iniciada.',
        metadata: {'phase': phase.code, 'line': line.displayName},
      ),
    ];
    final session = DetectionFormationSession.fromRecorder(
      id: sessionRef.id,
      dogId: dogId,
      dogName: dogName,
      lineId: lineDocId,
      lineName: line.displayName,
      lineType: line.normalizedType,
      phase: phase,
      startedAt: now,
      recorder: DetectionSessionRecorder(phase: phase),
      status: DetectionFormationStatus.inProgress,
      phaseAdvanced: false,
      handlerId: handlerId,
      handlerName: handlerName,
      odorMaterial: odorMaterial,
      auditTrail: auditTrail,
    );

    await sessionRef.set(session.toJson());
    await AuditService.log(
      action: 'created',
      entityType: 'training_session',
      entityId: sessionRef.id,
      summary: 'Sessão de formação ${line.displayName} ${phase.code} iniciada',
      after: session.toJson(),
    );

    return session;
  }

  Future<DetectionFormationSession> autosaveFormationProgress({
    required DetectionFormationSession session,
    required DetectionPhaseConfig phase,
    required DetectionSessionRecorder recorder,
    required String handlerId,
    required String handlerName,
  }) async {
    final updated = _buildSessionFromRecorder(
      session: session,
      phase: phase,
      recorder: recorder,
      status: DetectionFormationStatus.inProgress,
      phaseAdvanced: false,
      auditTrail: session.auditTrail,
    );

    await _sessionsCol(
      session.dogId,
    ).doc(session.id).set(updated.toJson(), SetOptions(merge: true));
    return updated;
  }

  Future<DetectionFormationSession> completeFormationByCriterion({
    required DetectionFormationSession session,
    required DetectionLine line,
    required DetectionPhaseConfig phase,
    required DetectionSessionRecorder recorder,
    required String handlerId,
    required String handlerName,
  }) async {
    final verifiedRecorder = DetectionSessionRecorder(
      phase: phase,
      initialRepetitions: recorder.repetitions,
    );
    if (!verifiedRecorder.criterionMet) {
      throw StateError(
        'Critério da fase ${phase.code} ainda não foi atingido.',
      );
    }

    final nextPhase = DetectionPhaseCatalog.nextAfter(phase.code);
    final canAdvanceLine =
        line.normalizedCurrentPhase == phase.code &&
        !line.phasesCompleted.contains(phase.code) &&
        nextPhase != null;
    final completedAuditEntry = _auditEntry(
      action: 'completed_by_criterion',
      handlerId: handlerId,
      handlerName: handlerName,
      reason: 'Critério objetivo atingido dentro da sessão.',
      metadata: {
        'phase': phase.code,
        'total_reps': verifiedRecorder.totalReps,
        'misses': verifiedRecorder.missCount,
      },
    );
    final updatedTrail = [...session.auditTrail, completedAuditEntry];
    final updated = _buildSessionFromRecorder(
      session: session,
      phase: phase,
      recorder: verifiedRecorder,
      status: DetectionFormationStatus.completedByCriterion,
      phaseAdvanced: canAdvanceLine,
      advancedTo: canAdvanceLine ? nextPhase.code : null,
      auditTrail: updatedTrail,
    );

    final batch = _firestore.batch();
    final sessionRef = _sessionsCol(session.dogId).doc(session.id);
    batch.set(sessionRef, updated.toJson(), SetOptions(merge: true));

    if (canAdvanceLine) {
      final advancedPhase = nextPhase;
      final completed = _mergeCompletedPhases(line.phasesCompleted, phase.code);
      final lineRef = _linesCol(
        session.dogId,
      ).doc(line.id ?? line.normalizedType);
      batch.set(lineRef, {
        'current_phase': advancedPhase.code,
        'phases_completed': completed,
        'status': advancedPhase.code == 'final'
            ? 'in_formation'
            : 'in_formation',
        'best_streak': verifiedRecorder.longestStreak > line.bestStreak
            ? verifiedRecorder.longestStreak
            : line.bestStreak,
        'consecutive_hits': 0,
        'updated_at': FieldValue.serverTimestamp(),
        'phase_history': FieldValue.arrayUnion([
          {
            'phase': phase.code,
            'completed_at': Timestamp.fromDate(DateTime.now()),
            'session_id': session.id,
            'to_phase': advancedPhase.code,
          },
        ]),
        'audit_trail': FieldValue.arrayUnion([
          _auditEntry(
            action: 'phase_advanced',
            handlerId: handlerId,
            handlerName: handlerName,
            reason: 'Critério da fase atingido automaticamente.',
            metadata: {
              'session_id': session.id,
              'from_phase': phase.code,
              'to_phase': advancedPhase.code,
            },
          ),
        ]),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    await AuditService.log(
      action: 'updated',
      entityType: 'training_session',
      entityId: session.id ?? '',
      summary:
          'Fase ${phase.code} concluída por critério para ${session.dogName}',
      after: updated.toJson(),
    );

    return updated;
  }

  Future<DetectionFormationSession> endFormationWithoutCriterion({
    required DetectionFormationSession session,
    required DetectionPhaseConfig phase,
    required DetectionSessionRecorder recorder,
    required String handlerId,
    required String handlerName,
  }) async {
    final verifiedRecorder = DetectionSessionRecorder(
      phase: phase,
      initialRepetitions: recorder.repetitions,
    );
    final updatedTrail = [
      ...session.auditTrail,
      _auditEntry(
        action: 'ended_without_criterion',
        handlerId: handlerId,
        handlerName: handlerName,
        reason: 'Sessão encerrada antes de atingir o critério da fase.',
        metadata: {
          'phase': phase.code,
          'total_reps': verifiedRecorder.totalReps,
        },
      ),
    ];
    final updated = _buildSessionFromRecorder(
      session: session,
      phase: phase,
      recorder: verifiedRecorder,
      status: DetectionFormationStatus.endedWithoutCriterion,
      phaseAdvanced: false,
      auditTrail: updatedTrail,
    );

    await _sessionsCol(
      session.dogId,
    ).doc(session.id).set(updated.toJson(), SetOptions(merge: true));
    await AuditService.log(
      action: 'updated',
      entityType: 'training_session',
      entityId: session.id ?? '',
      summary: 'Sessão ${phase.code} encerrada sem critério',
      after: updated.toJson(),
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
    final session = await startFormationSession(
      dogId: dogId,
      dogName: dogName,
      line: line,
      phase: phase,
      odorMaterial: odorMaterial ?? DetectionOdorMaterials.noseMp,
      handlerId: handlerId,
      handlerName: handlerName,
    );

    final updated = session.copyWith(
      auditTrail: [
        ...session.auditTrail,
        _auditEntry(
          action: 'created',
          handlerId: handlerId,
          handlerName: handlerName,
          reason: 'Sessão de formação registrada.',
        ),
      ],
    );

    if (advancePhase || recorder.criterionMet) {
      return completeFormationByCriterion(
        session: updated,
        line: line,
        phase: phase,
        recorder: recorder,
        handlerId: handlerId,
        handlerName: handlerName,
      );
    }

    return endFormationWithoutCriterion(
      session: updated,
      phase: phase,
      recorder: recorder,
      handlerId: handlerId,
      handlerName: handlerName,
    );
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

  DetectionFormationSession _buildSessionFromRecorder({
    required DetectionFormationSession session,
    required DetectionPhaseConfig phase,
    required DetectionSessionRecorder recorder,
    required String status,
    required bool phaseAdvanced,
    String? advancedTo,
    required List<Map<String, dynamic>> auditTrail,
  }) {
    return DetectionFormationSession.fromRecorder(
      id: session.id,
      dogId: session.dogId,
      dogName: session.dogName,
      lineId: session.lineId,
      lineName: session.lineName,
      lineType: session.lineType,
      phase: phase,
      startedAt: session.startedAt,
      endedAt: DateTime.now(),
      recorder: recorder,
      status: status,
      phaseAdvanced: phaseAdvanced,
      advancedTo: advancedTo,
      handlerId: session.handlerId,
      handlerName: session.handlerName,
      odorMaterial: session.odorMaterial,
      notes: session.notes,
      auditTrail: auditTrail,
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

  List<String> _mergeCompletedPhases(List<String> current, String completed) {
    final normalized = {
      ...current.map(DetectionPhaseCatalog.normalizePhaseCode),
      DetectionPhaseCatalog.normalizePhaseCode(completed),
    };
    return DetectionPhaseCatalog.phases
        .map((phase) => phase.code)
        .where(normalized.contains)
        .toList();
  }
}
