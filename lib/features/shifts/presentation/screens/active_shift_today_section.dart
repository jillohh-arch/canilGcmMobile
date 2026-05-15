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

    final displayEntries = todayEntries.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label com linha
        Row(
          children: [
            Text(
              'ATIVIDADES DE HOJE',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: AppTheme.primary.withAlpha(30)),
            ),
            if (todayEntries.length > 5) ...[
              const SizedBox(width: 8),
              Text(
                '${todayEntries.length}',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (displayEntries.isEmpty)
          _buildEmptyState(context)
        else
          ...displayEntries.map((entry) => _ActivityTile(entry: entry)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withAlpha(40),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.wb_sunny_outlined, color: AppTheme.primary.withAlpha(100), size: 28),
          const SizedBox(height: 10),
          Text(
            'Comece o dia',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Registre a primeira atividade do turno',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ),
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
            // Tempo à esquerda
            SizedBox(
              width: 40,
              child: Text(
                timeStr,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Ícone circular colorido
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: entry.color.withAlpha(15),
                shape: BoxShape.circle,
                border: Border.all(color: entry.color.withAlpha(60), width: 1.5),
              ),
              child: Icon(entry.icon, color: entry.color, size: 15),
            ),
            const SizedBox(width: 10),
            // Título
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
          ],
        ),
      ),
    );
  }
}
