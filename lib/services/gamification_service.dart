import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import '../models/badge_progress.dart';
import '../models/level_progress.dart';
import '../models/weekly_mission_progress.dart';
import '../models/user.dart';
import '../models/dog.dart';

class GamificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const List<_WeeklyMissionDefinition> _weeklyMissions = [
    _WeeklyMissionDefinition(
      id: 'treino_da_semana',
      title: 'Treino em Dia',
      description: 'Acumule 2 horas de treino na semana.',
      target: 2,
      unitLabel: 'horas',
      rewardXp: 80,
    ),
    _WeeklyMissionDefinition(
      id: 'turno_da_semana',
      title: 'Presença em Campo',
      description: 'Registre 2 turnos operacionais nesta semana.',
      target: 2,
      unitLabel: 'turnos',
      rewardXp: 60,
    ),
    _WeeklyMissionDefinition(
      id: 'ocorrencia_da_semana',
      title: 'Resposta Operacional',
      description: 'Conclua 1 ocorrência com resultado registrado na semana.',
      target: 1,
      unitLabel: 'ocorrência',
      rewardXp: 120,
    ),
    _WeeklyMissionDefinition(
      id: 'cuidado_da_semana',
      title: 'Cuidado Constante',
      description: 'Registre 2 ações de saúde ou manejo do K9 na semana.',
      target: 2,
      unitLabel: 'ações',
      rewardXp: 50,
    ),
  ];

  // Singleton pattern for easy global access
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();

  /// Calcula o nível baseado no XP.
  /// Inicia precisando de 500 XP para subir, aumentando a dificuldade em 25%.
  static int calculateLevel(int xp) => getLevelProgress(xp).level;

  static LevelProgress getLevelProgress(int xp) {
    int level = 1;
    int currentLevelFloorXp = 0;
    int xpRequired = 500;
    int remainingXp = xp;

    while (remainingXp >= xpRequired) {
      remainingXp -= xpRequired;
      currentLevelFloorXp += xpRequired;
      level++;
      xpRequired = (xpRequired * 1.25).toInt();
    }

    return LevelProgress(
      level: level,
      currentXp: xp,
      currentLevelFloorXp: currentLevelFloorXp,
      nextLevelXp: currentLevelFloorXp + xpRequired,
    );
  }

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

      int xpReward = 10; // Cuidado padrão/check-in
      if (logType.toLowerCase().contains('vacina') ||
          logType.toLowerCase().contains('exame') ||
          logType.toLowerCase().contains('emerg')) {
        xpReward = 50;
      } else if (logType.toLowerCase().contains('higiene') ||
          logType.toLowerCase().contains('banho')) {
        xpReward = 20;
      }

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
    double xpAmount = 30.0; // Padrão

    if (trainingType.toLowerCase().contains('faro')) {
      // 40 XP por cada 30 min (1800 seg)
      if (durationSeconds > 0) {
        double blocksOf30Min = durationSeconds / 1800;
        xpAmount =
            40.0 *
            (blocksOf30Min < 1
                ? 1
                : blocksOf30Min); // Garante mínimo de 40 caso seja curto
      } else {
        xpAmount = 40.0; // Se faltar info de tempo, pontua o mínimo do tipo
      }
    }

    if (hasDistraction) {
      xpAmount *= 1.5;
    }

    await _grantReward(ra, xpAmount.toInt());
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
    int xpReward = 0;
    final normalizedResult = _normalizeText(result);
    final normalizedType = _normalizeText(type);
    final isPersonSearchSuccess =
        normalizedResult.contains('pessoa localizada') ||
        normalizedResult.contains('localizacao de pessoa') ||
        normalizedResult.contains('localizacao pessoa') ||
        normalizedResult.contains('desaparecido localizado');

    if (normalizedResult.contains('apreensao positiva') ||
        normalizedResult.contains('apreensao positiva') ||
        normalizedResult.contains('droga apreendida')) {
      xpReward = 100;
    } else if (isPersonSearchSuccess ||
        ((normalizedType.contains('busca de pessoa') ||
                normalizedType.contains('desaparecimento') ||
                normalizedType.contains('localizacao de pessoa')) &&
            normalizedResult.contains('sucesso'))) {
      xpReward = 150;
    } else {
      xpReward = 25; // default para atendimento simples
    }

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
        final docResult = _normalizeText(data['result'] as String? ?? '');
        final docType = _normalizeText(data['type'] as String? ?? '');
        final outcomes = data['outcomes'] is List
            ? List<String>.from(
                data['outcomes'] as List,
              ).map(_normalizeText).toList()
            : const <String>[];

        final hasDrugApreensao =
            docResult.contains('apreensao positiva') ||
            outcomes.contains('droga apreendida');
        final hasMissingPersonSuccess =
            outcomes.contains('pessoa localizada') ||
            docResult.contains('pessoa localizada') ||
            ((docType.contains('busca de pessoa') ||
                    docType.contains('desaparecimento') ||
                    docType.contains('localizacao de pessoa')) &&
                docResult.contains('sucesso'));

        if (hasDrugApreensao) apreensaoCount++;
        if (hasMissingPersonSuccess) buscaPessoaSucessoCount++;
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

  Future<Map<String, BadgeProgress>> getBadgeProgress(String ra) async {
    final shiftSnapshot = await _db
        .collection('shift_logs')
        .where('handlerId', isEqualTo: ra)
        .get();
    final trainingSnapshot = await _db
        .collection('trainings')
        .where('handlerId', isEqualTo: ra)
        .get();
    final incidentSnapshot = await _db
        .collection('incidents')
        .where('handlerId', isEqualTo: ra)
        .get();
    final dogSnapshot = await _db
        .collection('dogs')
        .where('conductorRa', isEqualTo: ra)
        .get();

    final shiftCount = shiftSnapshot.docs.length;
    final totalTrainingSeconds = trainingSnapshot.docs.fold<int>(0, (
      total,
      doc,
    ) {
      final data = doc.data();
      final rawDuration = data['searchDuration'];
      final duration = rawDuration is num ? rawDuration.toInt() : 0;
      return total + duration;
    });
    final totalTrainingHours = totalTrainingSeconds ~/ 3600;

    var apreensaoCount = 0;
    var buscaPessoaSucessoCount = 0;
    for (final doc in incidentSnapshot.docs) {
      final data = doc.data();
      final docResult = _normalizeText(data['result'] as String? ?? '');
      final docType = _normalizeText(data['type'] as String? ?? '');
      final outcomes = data['outcomes'] is List
          ? List<String>.from(
              data['outcomes'] as List,
            ).map(_normalizeText).toList()
          : const <String>[];

      final hasDrugApreensao =
          docResult.contains('apreensao positiva') ||
          outcomes.contains('droga apreendida');
      final hasMissingPersonSuccess =
          outcomes.contains('pessoa localizada') ||
          docResult.contains('pessoa localizada') ||
          ((docType.contains('busca de pessoa') ||
                  docType.contains('desaparecimento') ||
                  docType.contains('localizacao de pessoa')) &&
              docResult.contains('sucesso'));

      if (hasDrugApreensao) {
        apreensaoCount++;
      }
      if (hasMissingPersonSuccess) {
        buscaPessoaSucessoCount++;
      }
    }

    var readinessDays90 = 0;
    var readinessDays95 = 0;
    for (final doc in dogSnapshot.docs) {
      final dog = Dog.fromJson(doc.data());
      final streak = dog.readinessStreak ?? const <String, dynamic>{};
      final days90 =
          (streak['days90'] as int?) ?? (streak['days'] as int?) ?? 0;
      final days95 = (streak['days95'] as int?) ?? 0;
      if (days90 > readinessDays90) {
        readinessDays90 = days90;
      }
      if (days95 > readinessDays95) {
        readinessDays95 = days95;
      }
    }

    return {
      'pe_na_estrada': BadgeProgress(
        badgeId: 'pe_na_estrada',
        current: shiftCount,
        target: 1,
        unitLabel: 'turno',
        summary: _formatProgress(
          current: shiftCount,
          target: 1,
          singular: 'turno registrado',
          plural: 'turnos registrados',
        ),
      ),
      'binomio_de_ferro': BadgeProgress(
        badgeId: 'binomio_de_ferro',
        current: shiftCount,
        target: 30,
        unitLabel: 'turnos',
        summary: _formatProgress(
          current: shiftCount,
          target: 30,
          singular: 'turno registrado',
          plural: 'turnos registrados',
        ),
      ),
      'faro_afiado': BadgeProgress(
        badgeId: 'faro_afiado',
        current: apreensaoCount,
        target: 1,
        unitLabel: 'apreensão',
        summary: _formatProgress(
          current: apreensaoCount,
          target: 1,
          singular: 'apreensão positiva',
          plural: 'apreensões positivas',
        ),
      ),
      'faro_de_elite': BadgeProgress(
        badgeId: 'faro_de_elite',
        current: apreensaoCount,
        target: 10,
        unitLabel: 'apreensões',
        summary: _formatProgress(
          current: apreensaoCount,
          target: 10,
          singular: 'apreensão positiva',
          plural: 'apreensões positivas',
        ),
      ),
      'mestre_do_adestramento': BadgeProgress(
        badgeId: 'mestre_do_adestramento',
        current: totalTrainingHours,
        target: 50,
        unitLabel: 'horas',
        summary: _formatProgress(
          current: totalTrainingHours,
          target: 50,
          singular: 'hora de treino',
          plural: 'horas de treino',
        ),
      ),
      'guardiao': BadgeProgress(
        badgeId: 'guardiao',
        current: readinessDays90,
        target: 30,
        unitLabel: 'dias',
        summary: _formatProgress(
          current: readinessDays90,
          target: 30,
          singular: 'dia com prontidão acima de 90%',
          plural: 'dias com prontidão acima de 90%',
        ),
      ),
      'sentinela_da_saude': BadgeProgress(
        badgeId: 'sentinela_da_saude',
        current: readinessDays95,
        target: 90,
        unitLabel: 'dias',
        summary: _formatProgress(
          current: readinessDays95,
          target: 90,
          singular: 'dia com prontidão acima de 95%',
          plural: 'dias com prontidão acima de 95%',
        ),
      ),
      'rastro_perfeito': BadgeProgress(
        badgeId: 'rastro_perfeito',
        current: buscaPessoaSucessoCount,
        target: 3,
        unitLabel: 'missões',
        summary: _formatProgress(
          current: buscaPessoaSucessoCount,
          target: 3,
          singular: 'missão de busca concluída com sucesso',
          plural: 'missões de busca concluídas com sucesso',
        ),
      ),
    };
  }

  String _formatProgress({
    required int current,
    required int target,
    required String singular,
    required String plural,
  }) {
    final label = target == 1 ? singular : plural;
    return '$current de $target $label';
  }

  String _normalizeText(String value) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    return value.toLowerCase().split('').map((char) {
      return accents[char] ?? char;
    }).join();
  }

  Future<_WeeklyMetrics> _loadWeeklyMetrics(String ra) async {
    final weekStart = getCurrentWeekStart();
    final weekKey = getCurrentWeekKey();

    final shiftSnapshot = await _db
        .collection('shift_logs')
        .where('handlerId', isEqualTo: ra)
        .get();
    final trainingSnapshot = await _db
        .collection('trainings')
        .where('handlerId', isEqualTo: ra)
        .get();
    final incidentSnapshot = await _db
        .collection('incidents')
        .where('handlerId', isEqualTo: ra)
        .get();
    final dogSnapshot = await _db
        .collection('dogs')
        .where('conductorRa', isEqualTo: ra)
        .get();
    final missionDoc = await _db
        .collection('users')
        .doc(ra)
        .collection('weekly_missions')
        .doc(weekKey)
        .get();

    final dogIds = dogSnapshot.docs.map((doc) => doc.id).toSet();

    final weeklyShiftCount = shiftSnapshot.docs.where((doc) {
      final data = doc.data();
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
      final data = doc.data();
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
      final data = doc.data();
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

    final claimedMissionIds = missionDoc.data()?['completedMissionIds'] is List
        ? List<String>.from(missionDoc.data()!['completedMissionIds'] as List)
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

  DateTime? _resolveDate(
    dynamic primary, [
    dynamic secondary,
    dynamic tertiary,
  ]) {
    for (final value in [primary, secondary, tertiary]) {
      final resolved = _parseDynamicDate(value);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  DateTime? _parseDynamicDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final date = DateTime.tryParse(value);
      return date;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is Map<String, dynamic> && value['seconds'] is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value['seconds'] as num).toInt() * 1000,
      );
    }
    return null;
  }

  bool _isDateInCurrentWeek(DateTime? date, DateTime weekStart) {
    if (date == null) return false;
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(weekStart);
  }
}

class _WeeklyMissionDefinition {
  final String id;
  final String title;
  final String description;
  final int target;
  final String unitLabel;
  final int rewardXp;

  const _WeeklyMissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.unitLabel,
    required this.rewardXp,
  });
}

class _WeeklyMetrics {
  final DateTime weekStart;
  final String weekKey;
  final int weeklyShiftCount;
  final int weeklyTrainingHours;
  final int weeklyConcludedIncidents;
  final int weeklyHealthActions;
  final List<String> claimedMissionIds;

  const _WeeklyMetrics({
    required this.weekStart,
    required this.weekKey,
    required this.weeklyShiftCount,
    required this.weeklyTrainingHours,
    required this.weeklyConcludedIncidents,
    required this.weeklyHealthActions,
    required this.claimedMissionIds,
  });
}
