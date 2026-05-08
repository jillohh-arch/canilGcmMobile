part of 'gamification_service.dart';

Future<Map<String, BadgeProgress>> _loadBadgeProgress(
  FirebaseFirestore db,
  String ra,
) async {
  final shiftSnapshot = await db
      .collection('shift_logs')
      .where('handlerId', isEqualTo: ra)
      .get();
  final trainingSnapshot = await db
      .collection('trainings')
      .where('handlerId', isEqualTo: ra)
      .get();
  final incidentSnapshot = await db
      .collection('incidents')
      .where('handlerId', isEqualTo: ra)
      .get();
  final dogSnapshot = await db
      .collection('dogs')
      .where('conductorRa', isEqualTo: ra)
      .get();

  final metrics = _BadgeProgressMetrics.fromSnapshots(
    shiftSnapshot: shiftSnapshot,
    trainingSnapshot: trainingSnapshot,
    incidentSnapshot: incidentSnapshot,
    dogSnapshot: dogSnapshot,
  );

  return {
    'pe_na_estrada': BadgeProgress(
      badgeId: 'pe_na_estrada',
      current: metrics.shiftCount,
      target: 1,
      unitLabel: 'turno',
      summary: _formatProgress(
        current: metrics.shiftCount,
        target: 1,
        singular: 'turno registrado',
        plural: 'turnos registrados',
      ),
    ),
    'binomio_de_ferro': BadgeProgress(
      badgeId: 'binomio_de_ferro',
      current: metrics.shiftCount,
      target: 30,
      unitLabel: 'turnos',
      summary: _formatProgress(
        current: metrics.shiftCount,
        target: 30,
        singular: 'turno registrado',
        plural: 'turnos registrados',
      ),
    ),
    'faro_afiado': BadgeProgress(
      badgeId: 'faro_afiado',
      current: metrics.apreensaoCount,
      target: 1,
      unitLabel: 'apreensão',
      summary: _formatProgress(
        current: metrics.apreensaoCount,
        target: 1,
        singular: 'apreensão positiva',
        plural: 'apreensões positivas',
      ),
    ),
    'faro_de_elite': BadgeProgress(
      badgeId: 'faro_de_elite',
      current: metrics.apreensaoCount,
      target: 10,
      unitLabel: 'apreensões',
      summary: _formatProgress(
        current: metrics.apreensaoCount,
        target: 10,
        singular: 'apreensão positiva',
        plural: 'apreensões positivas',
      ),
    ),
    'mestre_do_adestramento': BadgeProgress(
      badgeId: 'mestre_do_adestramento',
      current: metrics.totalTrainingHours,
      target: 50,
      unitLabel: 'horas',
      summary: _formatProgress(
        current: metrics.totalTrainingHours,
        target: 50,
        singular: 'hora de treino',
        plural: 'horas de treino',
      ),
    ),
    'guardiao': BadgeProgress(
      badgeId: 'guardiao',
      current: metrics.readinessDays90,
      target: 30,
      unitLabel: 'dias',
      summary: _formatProgress(
        current: metrics.readinessDays90,
        target: 30,
        singular: 'dia com prontidão acima de 90%',
        plural: 'dias com prontidão acima de 90%',
      ),
    ),
    'sentinela_da_saude': BadgeProgress(
      badgeId: 'sentinela_da_saude',
      current: metrics.readinessDays95,
      target: 90,
      unitLabel: 'dias',
      summary: _formatProgress(
        current: metrics.readinessDays95,
        target: 90,
        singular: 'dia com prontidão acima de 95%',
        plural: 'dias com prontidão acima de 95%',
      ),
    ),
    'rastro_perfeito': BadgeProgress(
      badgeId: 'rastro_perfeito',
      current: metrics.buscaPessoaSucessoCount,
      target: 3,
      unitLabel: 'missões',
      summary: _formatProgress(
        current: metrics.buscaPessoaSucessoCount,
        target: 3,
        singular: 'missão de busca concluída com sucesso',
        plural: 'missões de busca concluídas com sucesso',
      ),
    ),
  };
}

class _BadgeProgressMetrics {
  final int shiftCount;
  final int totalTrainingHours;
  final int apreensaoCount;
  final int buscaPessoaSucessoCount;
  final int readinessDays90;
  final int readinessDays95;

  const _BadgeProgressMetrics({
    required this.shiftCount,
    required this.totalTrainingHours,
    required this.apreensaoCount,
    required this.buscaPessoaSucessoCount,
    required this.readinessDays90,
    required this.readinessDays95,
  });

  factory _BadgeProgressMetrics.fromSnapshots({
    required QuerySnapshot<Map<String, dynamic>> shiftSnapshot,
    required QuerySnapshot<Map<String, dynamic>> trainingSnapshot,
    required QuerySnapshot<Map<String, dynamic>> incidentSnapshot,
    required QuerySnapshot<Map<String, dynamic>> dogSnapshot,
  }) {
    return _BadgeProgressMetrics(
      shiftCount: shiftSnapshot.docs.length,
      totalTrainingHours: _totalTrainingHours(trainingSnapshot),
      apreensaoCount: _countIncidentMatches(
        incidentSnapshot,
        _hasDrugApreensao,
      ),
      buscaPessoaSucessoCount: _countIncidentMatches(
        incidentSnapshot,
        _hasMissingPersonSuccess,
      ),
      readinessDays90: _maxReadinessDays(dogSnapshot, 'days90'),
      readinessDays95: _maxReadinessDays(dogSnapshot, 'days95'),
    );
  }
}

int _totalTrainingHours(QuerySnapshot<Map<String, dynamic>> snapshot) {
  final totalTrainingSeconds = snapshot.docs.fold<int>(0, (total, doc) {
    final data = doc.data();
    final rawDuration = data['searchDuration'];
    final duration = rawDuration is num ? rawDuration.toInt() : 0;
    return total + duration;
  });
  return totalTrainingSeconds ~/ 3600;
}

int _countIncidentMatches(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  bool Function(Map<String, dynamic> data) matches,
) {
  return snapshot.docs.where((doc) => matches(doc.data())).length;
}

int _maxReadinessDays(
  QuerySnapshot<Map<String, dynamic>> dogSnapshot,
  String key,
) {
  var maxDays = 0;
  for (final doc in dogSnapshot.docs) {
    final dog = Dog.fromJson(doc.data());
    final streak = dog.readinessStreak ?? const <String, dynamic>{};
    final days =
        (streak[key] as int?) ??
        (key == 'days90' ? streak['days'] as int? : null) ??
        0;
    if (days > maxDays) {
      maxDays = days;
    }
  }
  return maxDays;
}
