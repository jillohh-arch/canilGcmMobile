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
        color: AppTheme.textPrimary.withAlpha(7),
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

class _OperationalPulseSection extends StatelessWidget {
  const _OperationalPulseSection();

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);
    final today = _dayOnly(DateTime.now());
    final days = List.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
    final feedingDates = [
      ...nutritionVM.historyFeedings.map((feeding) => feeding.fedAt),
      ...nutritionVM.todayFeedings.map((feeding) => feeding.fedAt),
    ];
    final buckets = days
        .map(
          (day) => _PulseDay(
            day: day,
            occurrences: _countOnDay(
              occurrenceVM.occurrences.map((o) => o.startedAt),
              day,
            ),
            trainings: _countOnDay(
              trainingVM.trainings.map((training) => training.date),
              day,
            ),
            health: _countOnDay(
              healthVM.healthLogs.map((log) => log.date),
              day,
            ),
            nutrition: _countOnDay(feedingDates, day),
          ),
        )
        .toList(growable: false);
    final maxWeight = buckets.fold<int>(
      1,
      (max, day) => day.weightedTotal > max ? day.weightedTotal : max,
    );
    final totalRecords = buckets.fold<int>(
      0,
      (total, day) => total + day.totalRecords,
    );
    final peak = buckets.fold<_PulseDay>(
      buckets.first,
      (best, day) => day.weightedTotal > best.weightedTotal ? day : best,
    );
    final todayBucket = buckets.last;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashboardPanelTitle(
            icon: Icons.insights_rounded,
            title: 'Pulso do binômio',
            subtitle:
                'Ocorrências, treinos, saúde e nutrição nos últimos 7 dias',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PulseMetricChip(
                  label: '7 dias',
                  value: '$totalRecords',
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PulseMetricChip(
                  label: 'Pico',
                  value: _weekdayShort(peak.day),
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PulseMetricChip(
                  label: 'Hoje',
                  value: '${todayBucket.totalRecords}',
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets
                  .map(
                    (day) => Expanded(
                      child: _PulseBar(day: day, maxWeight: maxWeight),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: const [
              _PulseLegendItem(color: AppTheme.attention, label: 'Ocorrência'),
              _PulseLegendItem(color: AppTheme.warning, label: 'Treino'),
              _PulseLegendItem(color: AppTheme.success, label: 'Saúde'),
              _PulseLegendItem(color: AppTheme.primary, label: 'Nutrição'),
            ],
          ),
        ],
      ),
    );
  }

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _countOnDay(Iterable<DateTime> dates, DateTime day) {
    return dates.where((date) => _isSameDay(date, day)).length;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekdayShort(DateTime day) {
    const labels = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
    return labels[day.weekday - 1];
  }
}

class _PulseDay {
  final DateTime day;
  final int occurrences;
  final int trainings;
  final int health;
  final int nutrition;

  const _PulseDay({
    required this.day,
    required this.occurrences,
    required this.trainings,
    required this.health,
    required this.nutrition,
  });

  int get totalRecords => occurrences + trainings + health + nutrition;

  int get weightedTotal =>
      (occurrences * 3) + (trainings * 2) + health + nutrition;
}

class _PulseMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PulseMetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexMono(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: _kTextMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseBar extends StatelessWidget {
  final _PulseDay day;
  final int maxWeight;

  const _PulseBar({required this.day, required this.maxWeight});

  @override
  Widget build(BuildContext context) {
    final empty = day.weightedTotal == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 104,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: empty
                  ? Container(
                      width: 16,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.textPrimary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _PulseSegment(
                          color: AppTheme.attention,
                          height: _height(day.occurrences, 3),
                        ),
                        _PulseSegment(
                          color: AppTheme.warning,
                          height: _height(day.trainings, 2),
                        ),
                        _PulseSegment(
                          color: AppTheme.success,
                          height: _height(day.health, 1),
                        ),
                        _PulseSegment(
                          color: AppTheme.primary,
                          height: _height(day.nutrition, 1),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _OperationalPulseSection._weekdayShort(day.day),
            style: GoogleFonts.ibmPlexMono(
              color: _kTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  double _height(int count, int weight) {
    if (count == 0) return 0;
    final height = 94 * ((count * weight) / maxWeight);
    return height.clamp(5.0, 94.0);
  }
}

class _PulseSegment extends StatelessWidget {
  final Color color;
  final double height;

  const _PulseSegment({required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    return Container(
      width: 18,
      height: height,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(40),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _PulseLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _PulseLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            color: _kTextMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
        color: AppTheme.textPrimary.withAlpha(6),
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
