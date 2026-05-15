part of 'active_shift_dashboard_screen.dart';

/// Seção "Atividades de hoje" com timeline de registros do dia.
class _TodayActivitiesSection extends StatelessWidget {
  final String dogId;
  const _TodayActivitiesSection({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final routineVM = Provider.of<RoutineViewModel>(context);

    final todayEntries = _buildTodayEntries(
      trainingVM, healthVM, incidentVM, routineVM,
    );

    final displayEntries = todayEntries.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ATIVIDADES DE HOJE',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        if (displayEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A1F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppTheme.textTertiary, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Nenhum registro hoje. Comece pelo botão acima.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...displayEntries.map((entry) => _ActivityTile(entry: entry)),
      ],
    );
  }

  List<_ActivityEntry> _buildTodayEntries(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
  ) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final entries = <_ActivityEntry>[];

    for (final t in trainingVM.trainings) {
      if (t.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'treino',
          title: t.trainingType,
          time: t.date,
          icon: Icons.fitness_center_rounded,
          color: AppTheme.primary,
        ));
      }
    }

    for (final h in healthVM.healthLogs) {
      if (h.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'saude',
          title: h.logType,
          time: h.date,
          icon: Icons.medical_services_outlined,
          color: AppTheme.success,
        ));
      }
    }

    for (final i in incidentVM.incidents) {
      if (i.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'ocorrencia',
          title: i.type ?? 'Ocorrência',
          time: i.date,
          icon: Icons.assignment_outlined,
          color: AppTheme.error,
        ));
      }
    }

    for (final r in routineVM.routines) {
      if (r.timestamp.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'rotina',
          title: r.activityType,
          time: r.timestamp,
          icon: Icons.schedule_rounded,
          color: AppTheme.attention,
        ));
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }
}

class _ActivityEntry {
  final String type;
  final String title;
  final DateTime time;
  final IconData icon;
  final Color color;

  _ActivityEntry({
    required this.type,
    required this.title,
    required this.time,
    required this.icon,
    required this.color,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;

  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF1D2C33), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: entry.color.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(entry.icon, color: entry.color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              timeStr,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}