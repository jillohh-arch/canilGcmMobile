part of 'active_shift_dashboard_screen.dart';

class _LatestRecordsSection extends StatelessWidget {
  const _LatestRecordsSection();

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final rows = [
      _LatestRecordRowData(
        icon: Icons.shield_rounded,
        color: AppTheme.attention,
        title: 'Ocorrência',
        when: _lastAgo(
          _latestDate(occurrenceVM.occurrences.map((o) => o.startedAt)),
        ),
      ),
      _LatestRecordRowData(
        icon: Icons.local_hospital_rounded,
        color: AppTheme.success,
        title: 'Saúde',
        when: _lastAgo(_latestDate(healthVM.healthLogs.map((h) => h.date))),
      ),
      _LatestRecordRowData(
        icon: Icons.restaurant_rounded,
        color: AppTheme.primary,
        title: 'Nutrição',
        when: _lastAgo(
          _latestDate([
            ...nutritionVM.historyFeedings.map((f) => f.fedAt),
            ...nutritionVM.todayFeedings.map((f) => f.fedAt),
          ]),
        ),
      ),
      _LatestRecordRowData(
        icon: Icons.fitness_center_rounded,
        color: AppTheme.warning,
        title: 'Treino',
        when: _lastAgo(_latestDate(trainingVM.trainings.map((t) => t.date))),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashboardPanelTitle(
            icon: Icons.schedule_rounded,
            title: 'Últimos registros',
          ),
          const SizedBox(height: 14),
          ...rows.map((row) => _LatestRecordRow(data: row)),
        ],
      ),
    );
  }

  DateTime? _latestDate(Iterable<DateTime> dates) {
    DateTime? latest;
    for (final date in dates) {
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }
    return latest;
  }

  String _lastAgo(DateTime? date) {
    if (date == null) return 'sem registro';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'última agora';
    if (diff.inMinutes < 60) return 'última há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'última há ${diff.inHours}h';
    if (diff.inDays == 1) return 'última há 1d';
    return 'última há ${diff.inDays}d';
  }
}

class _LatestRecordRowData {
  final IconData icon;
  final Color color;
  final String title;
  final String when;

  const _LatestRecordRowData({
    required this.icon,
    required this.color,
    required this.title,
    required this.when,
  });
}

class _LatestRecordRow extends StatelessWidget {
  final _LatestRecordRowData data;

  const _LatestRecordRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderSubtle),
      ),
      child: Row(
        children: [
          Icon(data.icon, color: data.color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              data.title,
              style: GoogleFonts.inter(
                color: _kTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            data.when,
            style: GoogleFonts.inter(
              color: _kTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
