part of 'gamification_service.dart';

Future<List<WeeklyMissionProgress>> _getWeeklyMissionProgress(
  GamificationService service,
  String ra,
) async {
  final metrics = await _loadWeeklyMetrics(service, ra);
  return _buildWeeklyMissionProgress(
    metrics,
    claimedMissionIds: metrics.claimedMissionIds,
  );
}

Future<void> _syncWeeklyMissions(GamificationService service, String ra) async {
  final db = service._db;

  try {
    final metrics = await _loadWeeklyMetrics(service, ra);
    final completedUnclaimed = _buildWeeklyMissionProgress(
      metrics,
      claimedMissionIds: metrics.claimedMissionIds,
    ).where((mission) => mission.completed && !mission.claimed).toList();

    if (completedUnclaimed.isEmpty) return;

    await db.runTransaction((transaction) async {
      final userRef = db.collection('users').doc(ra);
      final missionRef = db
          .collection('users')
          .doc(ra)
          .collection('weekly_missions')
          .doc(metrics.weekKey);

      final userDoc = await transaction.get(userRef);
      final missionDoc = await transaction.get(missionRef);

      if (!userDoc.exists || userDoc.data() == null) return;

      final currentBadges = missionDoc.data()?['completedMissionIds'] is List
          ? List<String>.from(missionDoc.data()!['completedMissionIds'] as List)
          : <String>[];

      final newMissionIds = completedUnclaimed
          .map((mission) => mission.missionId)
          .where((missionId) => !currentBadges.contains(missionId))
          .toList();

      if (newMissionIds.isEmpty) return;

      final xpBonus = completedUnclaimed
          .where((mission) => newMissionIds.contains(mission.missionId))
          .fold<int>(0, (total, mission) => total + mission.rewardXp);

      final user = UserModel.fromJson(userDoc.data()!);
      transaction.update(userRef, {'xp': user.xp + xpBonus});
      transaction.set(missionRef, {
        'weekStart': Timestamp.fromDate(metrics.weekStart),
        'completedMissionIds': [...currentBadges, ...newMissionIds],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  } catch (e) {
    developer.log(
      'Erro ao sincronizar missões semanais: $e',
      name: 'Gamification',
      error: e,
    );
  }
}

Future<_WeeklyMetrics> _loadWeeklyMetrics(
  GamificationService service,
  String ra,
) async {
  final db = service._db;
  final weekStart = service.getCurrentWeekStart();
  final weekKey = service.getCurrentWeekKey();

  final results = await Future.wait([
    db.collection('shift_logs').where('handlerId', isEqualTo: ra).get(),
    db.collection('trainings').where('handlerId', isEqualTo: ra).get(),
    db.collection('incidents').where('handlerId', isEqualTo: ra).get(),
    db.collection('dogs').where('conductorRa', isEqualTo: ra).get(),
    db
            .collection('users')
            .doc(ra)
            .collection('weekly_missions')
            .doc(weekKey)
            .get()
        as Future<Object>,
  ]);

  final shiftSnapshot = results[0] as QuerySnapshot;
  final trainingSnapshot = results[1] as QuerySnapshot;
  final incidentSnapshot = results[2] as QuerySnapshot;
  final dogSnapshot = results[3] as QuerySnapshot;
  final missionDocResult = results[4] as DocumentSnapshot;

  final dogIds = dogSnapshot.docs.map((doc) => doc.id).toSet();

  final weeklyShiftCount = shiftSnapshot.docs.where((doc) {
    final data = doc.data() as Map<String, dynamic>;
    final date = _resolveDate(
      data['startedAt'],
      data['createdAt'],
      data['updatedAt'],
    );
    return _isDateInCurrentWeek(date, weekStart);
  }).length;

  final weeklyTrainingSeconds = trainingSnapshot.docs.fold<int>(0, (
    total,
    doc,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final date = _resolveDate(
      data['date'],
      data['createdAt'],
      data['timestamp'],
    );
    if (!_isDateInCurrentWeek(date, weekStart)) {
      return total;
    }
    final rawDuration = data['searchDuration'];
    final duration = rawDuration is num ? rawDuration.toInt() : 0;
    return total + duration;
  });

  final weeklyConcludedIncidents = incidentSnapshot.docs.where((doc) {
    final data = doc.data() as Map<String, dynamic>;
    final date = _resolveDate(
      data['endedAt'],
      data['updatedAt'],
      data['createdAt'],
    );
    if (!_isDateInCurrentWeek(date, weekStart)) {
      return false;
    }
    final status = (data['status'] as String? ?? '').toLowerCase();
    final hasResult =
        (data['result'] as String? ?? '').trim().isNotEmpty ||
        (data['outcomes'] is List && (data['outcomes'] as List).isNotEmpty);
    return status.contains('conclu') && hasResult;
  }).length;

  final healthLogsSnapshot = await db.collection('health_logs').get();
  final weeklyHealthActions = healthLogsSnapshot.docs.where((doc) {
    final data = doc.data();
    final dogId = data['dogId'] as String?;
    if (dogId == null || !dogIds.contains(dogId)) {
      return false;
    }
    final date = _resolveDate(
      data['date'],
      data['createdAt'],
      data['timestamp'],
    );
    return _isDateInCurrentWeek(date, weekStart);
  }).length;

  final missionData = missionDocResult.data() as Map<String, dynamic>?;
  final claimedMissionIds = missionData?['completedMissionIds'] is List
      ? List<String>.from(missionData!['completedMissionIds'] as List)
      : <String>[];

  return _WeeklyMetrics(
    weekStart: weekStart,
    weekKey: weekKey,
    weeklyShiftCount: weeklyShiftCount,
    weeklyTrainingHours: weeklyTrainingSeconds ~/ 3600,
    weeklyConcludedIncidents: weeklyConcludedIncidents,
    weeklyHealthActions: weeklyHealthActions,
    claimedMissionIds: claimedMissionIds,
  );
}

List<WeeklyMissionProgress> _buildWeeklyMissionProgress(
  _WeeklyMetrics metrics, {
  required List<String> claimedMissionIds,
}) {
  return _weeklyMissions.map((mission) {
    final current = switch (mission.id) {
      'treino_da_semana' => metrics.weeklyTrainingHours,
      'turno_da_semana' => metrics.weeklyShiftCount,
      'ocorrencia_da_semana' => metrics.weeklyConcludedIncidents,
      'cuidado_da_semana' => metrics.weeklyHealthActions,
      _ => 0,
    };

    return WeeklyMissionProgress(
      missionId: mission.id,
      title: mission.title,
      description: mission.description,
      current: current,
      target: mission.target,
      unitLabel: mission.unitLabel,
      rewardXp: mission.rewardXp,
      claimed: claimedMissionIds.contains(mission.id),
    );
  }).toList();
}
