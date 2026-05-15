part of 'active_shift_dashboard_screen.dart';

/// Card horizontal com indicadores dinâmicos: registros, alertas, temperatura, status.
class _ShiftIndicatorsCard extends StatelessWidget {
  final Dog dog;
  final int totalAlerts;
  final WeatherData? weatherData;

  const _ShiftIndicatorsCard({
    required this.dog,
    required this.totalAlerts,
    this.weatherData,
  });

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final routineVM = Provider.of<RoutineViewModel>(context);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final todayRecords = _countTodayRecords(
      trainingVM, healthVM, incidentVM, routineVM, startOfDay,
    );

    final tempLabel = weatherData != null
        ? '${weatherData!.temperatura.round()}°C'
        : '--°C';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _IndicatorChip(
            icon: Icons.description_outlined,
            label: '$todayRecords',
            subtitle: 'Registros',
            color: AppTheme.primary,
          ),
          _IndicatorChip(
            icon: Icons.notifications_active_outlined,
            label: '$totalAlerts',
            subtitle: 'Alertas',
            color: totalAlerts > 0 ? AppTheme.warning : AppTheme.textTertiary,
          ),
          _IndicatorChip(
            icon: Icons.thermostat_outlined,
            label: tempLabel,
            subtitle: 'Temp.',
            color: _tempColor(),
          ),
          _IndicatorChip(
            icon: Icons.favorite_outline_rounded,
            label: dog.operationalStatus,
            subtitle: 'Status',
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }

  Color _tempColor() {
    if (weatherData == null) return AppTheme.textTertiary;
    final temp = weatherData!.temperatura;
    if (temp >= 35) return AppTheme.error;
    if (temp >= 30) return AppTheme.warning;
    return AppTheme.success;
  }

  int _countTodayRecords(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
    DateTime startOfDay,
  ) {
    int count = 0;
    count += trainingVM.trainings
        .where((t) => t.date.isAfter(startOfDay))
        .length;
    count += healthVM.healthLogs
        .where((h) => h.date.isAfter(startOfDay))
        .length;
    count += incidentVM.incidents
        .where((i) => i.date.isAfter(startOfDay))
        .length;
    count += routineVM.routines
        .where((r) => r.timestamp.isAfter(startOfDay))
        .length;
    return count;
  }
}

class _IndicatorChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _IndicatorChip({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}