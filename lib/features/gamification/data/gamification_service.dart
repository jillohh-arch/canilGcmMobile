import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:canil_gcm/features/gamification/domain/badge_progress.dart';
import 'package:canil_gcm/features/gamification/domain/level_progress.dart';
import 'package:canil_gcm/features/gamification/domain/weekly_mission_progress.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

part 'gamification_weekly_models.dart';
part 'gamification_rules.dart';
part 'gamification_badge_progress.dart';

class GamificationService {
  final FirebaseFirestore _db;

  // Singleton pattern for easy global access
  static final GamificationService _instance = GamificationService._internal(
    FirebaseFirestore.instance,
  );
  factory GamificationService({FirebaseFirestore? firestore}) {
    if (firestore != null) return GamificationService._internal(firestore);
    return _instance;
  }
  GamificationService._internal(this._db);

  /// Calcula o nível baseado no XP.
  /// Inicia precisando de 500 XP para subir, aumentando a dificuldade em 25%.
  static int calculateLevel(int xp) => getLevelProgress(xp).level;

  static LevelProgress getLevelProgress(int xp) => _calculateLevelProgress(xp);

  DateTime getCurrentWeekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  String getCurrentWeekKey() {
    final weekStart = getCurrentWeekStart();
    return '${weekStart.year.toString().padLeft(4, '0')}-'
        '${weekStart.month.toString().padLeft(2, '0')}-'
        '${weekStart.day.toString().padLeft(2, '0')}';
  }

  /// Utility to add XP and potentially a badge
  Future<void> _grantReward(String ra, int xpAmount, {String? badgeId}) async {
    try {
      if (xpAmount <= 0 && badgeId == null) return;

      var awardedXp = 0;
      var awardedBadge = false;

      await _db.runTransaction((transaction) async {
        final userRef = _db.collection('users').doc(ra);
        final userDoc = await transaction.get(userRef);
        if (!userDoc.exists || userDoc.data() == null) return;

        final user = UserModel.fromJson(userDoc.data()!);
        final updatedBadges = List<String>.from(user.userBadges);
        final updates = <String, dynamic>{};

        if (xpAmount > 0) {
          updates['xp'] = user.xp + xpAmount;
          awardedXp = xpAmount;
        }

        if (badgeId != null && !updatedBadges.contains(badgeId)) {
          updatedBadges.add(badgeId);
          updates['userBadges'] = updatedBadges;
          awardedBadge = true;
        }

        if (updates.isEmpty) return;
        transaction.update(userRef, updates);
      });

      if (awardedBadge) {
        developer.log(
          'Concedendo badge $badgeId para $ra',
          name: 'Gamification',
        );
      }

      if (awardedXp > 0) {
        developer.log(
          'Usuário $ra recebeu $awardedXp XP.',
          name: 'Gamification',
        );
      }
    } catch (e) {
      developer.log(
        'Erro ao processar reward: $e',
        name: 'Gamification',
        error: e,
      );
    }
  }

  /// Avalia saúde e cuidado.
  /// Saúde e cuidado: 10 XP (check-in diário), 20 XP (higiene), 50 XP (vacinas/exames).
  Future<void> evaluateHealthLog(String dogId, String logType) async {
    try {
      final dogDoc = await _db.collection('dogs').doc(dogId).get();
      if (!dogDoc.exists) return;

      final dogData = dogDoc.data()!;
      final dog = Dog.fromJson(dogData);

      final ra = dog.conductorRa;
      if (ra == null || ra.isEmpty) return;

      final xpReward = _xpForHealthLog(logType);

      await _grantReward(ra, xpReward);
      await syncWeeklyMissions(ra);
    } catch (e) {
      developer.log(
        'Erro ao avaliar prontidao corporativa: $e',
        name: 'Gamification',
        error: e,
      );
    }
  }

  /// Avalia treinamento.
  /// 40 XP por cada 30 min de faro. 30 XP para outros. 1,5x com distração.
  Future<void> evaluateTrainingSession(
    String ra,
    String trainingType,
    int durationSeconds,
    bool hasDistraction,
  ) async {
    final xpAmount = _xpForTrainingSession(
      trainingType: trainingType,
      durationSeconds: durationSeconds,
      hasDistraction: hasDistraction,
    );

    await _grantReward(ra, xpAmount);
    await syncWeeklyMissions(ra);

    try {
      final snapshot = await _db
          .collection('trainings')
          .where('handlerId', isEqualTo: ra)
          .get();
      final totalDurationSeconds = snapshot.docs.fold<int>(0, (total, doc) {
        final data = doc.data();
        final rawDuration = data['searchDuration'];
        final duration = rawDuration is num ? rawDuration.toInt() : 0;
        return total + duration;
      });

      if (totalDurationSeconds >= 180000) {
        await _grantReward(ra, 0, badgeId: 'mestre_do_adestramento');
      }
    } catch (e) {
      developer.log('Erro badge treino: $e', name: 'Gamification', error: e);
    }
  }

  /// Avalia operações e rotina.
  /// 25 XP (ronda/rotina), 100 XP (apreensão), 150 XP (busca).
  Future<void> evaluateRoutine(String ra, {bool isShift = false}) async {
    // 25 XP por Ronda
    await _grantReward(ra, 25);
    await syncWeeklyMissions(ra);
  }

  Future<void> evaluateShiftStart(String ra) async {
    try {
      final snapshot = await _db
          .collection('shift_logs')
          .where('handlerId', isEqualTo: ra)
          .get();
      final shiftCount = snapshot.docs.length;

      if (shiftCount >= 1) {
        await _grantReward(ra, 0, badgeId: 'pe_na_estrada');
      }
      if (shiftCount >= 30) {
        await _grantReward(ra, 0, badgeId: 'binomio_de_ferro');
      }
      await syncWeeklyMissions(ra);
    } catch (e) {
      developer.log(
        'Erro ao avaliar badge de turno: $e',
        name: 'Gamification',
        error: e,
      );
    }
  }

  Future<void> evaluateIncidents(String ra, String result, String type) async {
    final xpReward = _xpForIncident(result: result, type: type);

    await _grantReward(ra, xpReward);
    await syncWeeklyMissions(ra);

    try {
      final snapshot = await _db
          .collection('incidents')
          .where('handlerId', isEqualTo: ra)
          .get();
      int apreensaoCount = 0;
      int buscaPessoaSucessoCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (_hasDrugApreensao(data)) apreensaoCount++;
        if (_hasMissingPersonSuccess(data)) buscaPessoaSucessoCount++;
      }

      if (apreensaoCount >= 1) {
        await _grantReward(ra, 0, badgeId: 'faro_afiado');
      }
      if (apreensaoCount >= 10) {
        await _grantReward(ra, 0, badgeId: 'faro_de_elite');
      }
      if (buscaPessoaSucessoCount >= 3) {
        await _grantReward(ra, 0, badgeId: 'rastro_perfeito');
      }
    } catch (_) {
      // Mantém a pontuação principal mesmo se a checagem de badges falhar.
    }
  }

  Future<List<WeeklyMissionProgress>> getWeeklyMissionProgress(
    String ra,
  ) async {
    final metrics = await _loadWeeklyMetrics(ra);
    return _buildWeeklyMissionProgress(
      metrics,
      claimedMissionIds: metrics.claimedMissionIds,
    );
  }

  Future<void> syncWeeklyMissions(String ra) async {
    try {
      final metrics = await _loadWeeklyMetrics(ra);
      final completedUnclaimed = _buildWeeklyMissionProgress(
        metrics,
        claimedMissionIds: metrics.claimedMissionIds,
      ).where((mission) => mission.completed && !mission.claimed).toList();

      if (completedUnclaimed.isEmpty) return;

      await _db.runTransaction((transaction) async {
        final userRef = _db.collection('users').doc(ra);
        final missionRef = _db
            .collection('users')
            .doc(ra)
            .collection('weekly_missions')
            .doc(metrics.weekKey);

        final userDoc = await transaction.get(userRef);
        final missionDoc = await transaction.get(missionRef);

        if (!userDoc.exists || userDoc.data() == null) return;

        final currentBadges = missionDoc.data()?['completedMissionIds'] is List
            ? List<String>.from(
                missionDoc.data()!['completedMissionIds'] as List,
              )
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

  Future<Map<String, BadgeProgress>> getBadgeProgress(String ra) {
    return _loadBadgeProgress(_db, ra);
  }

  Future<_WeeklyMetrics> _loadWeeklyMetrics(String ra) async {
    final weekStart = getCurrentWeekStart();
    final weekKey = getCurrentWeekKey();

    // P7: Executar todas as queries em paralelo para reduzir latência
    final results = await Future.wait([
      _db.collection('shift_logs').where('handlerId', isEqualTo: ra).get(),
      _db.collection('trainings').where('handlerId', isEqualTo: ra).get(),
      _db.collection('incidents').where('handlerId', isEqualTo: ra).get(),
      _db.collection('dogs').where('conductorRa', isEqualTo: ra).get(),
      _db
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

    // health_logs ainda precisa de query separada pois filtra por dogId do set
    final healthLogsSnapshot = await _db.collection('health_logs').get();
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
}
