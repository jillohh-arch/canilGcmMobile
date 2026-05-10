part of 'active_shift_dashboard_screen.dart';

const Set<String> _routineTrainingTypes = {
  'Passeio',
  'Lazer/Brincadeira',
  'Brincadeira',
  'Condicionamento Físico',
  'Alimentação',
  'Limpeza',
  'Descanso',
  'Escovação',
  'Outros',
};

class _ActivityEntry {
  final DateTime time;
  final String label;
  final IconData icon;
  final Color color;

  const _ActivityEntry({
    required this.time,
    required this.label,
    required this.icon,
    required this.color,
  });
}

List<_ActivityEntry> _collectTodayActivityEntries(
  BuildContext context,
  String dogId,
) {
  final tVM = Provider.of<TrainingViewModel>(context);
  final iVM = Provider.of<IncidentViewModel>(context);
  final hVM = Provider.of<HealthViewModel>(context);

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));
  final entries = <_ActivityEntry>[];

  for (final training in tVM.trainings) {
    if (training.dogId != dogId) continue;
    if (!_isTodayRecord(training.date, startOfDay, endOfDay)) {
      continue;
    }

    final isRoutine = _routineTrainingTypes.contains(training.trainingType);
    entries.add(
      _ActivityEntry(
        time: training.date,
        label: training.trainingType,
        icon: isRoutine ? Icons.pets_rounded : Icons.track_changes_rounded,
        color: isRoutine ? const Color(0xFF43A047) : const Color(0xFFFFB300),
      ),
    );
  }

  for (final incident in iVM.incidents) {
    if (incident.dogId != dogId) continue;
    if (!_isTodayRecord(incident.date, startOfDay, endOfDay)) {
      continue;
    }

    entries.add(
      _ActivityEntry(
        time: incident.date,
        label: incident.type ?? 'Ocorrência',
        icon: Icons.shield_outlined,
        color: const Color(0xFFE53935),
      ),
    );
  }

  for (final healthLog in hVM.healthLogs) {
    if (healthLog.dogId != dogId) continue;
    if (!_isTodayRecord(healthLog.date, startOfDay, endOfDay)) {
      continue;
    }

    entries.add(
      _ActivityEntry(
        time: healthLog.date,
        label: healthLog.logType,
        icon: Icons.vaccines_rounded,
        color: const Color(0xFF8E24AA),
      ),
    );
  }

  entries.sort((a, b) => b.time.compareTo(a.time));
  return entries;
}

bool _isTodayRecord(DateTime value, DateTime startOfDay, DateTime endOfDay) {
  return !value.isBefore(startOfDay) && value.isBefore(endOfDay);
}
