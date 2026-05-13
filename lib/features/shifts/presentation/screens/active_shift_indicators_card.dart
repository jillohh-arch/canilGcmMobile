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
      trainingVM,
      healthVM,
      incidentVM,
      routineVM,
      startOfDay,
    );

    final tempLabel = weatherData != null
        ? '${weatherData!.temperatura.round()}°C'
        : '--°C';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _hudCyan.withAlpha(40)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _IndicatorChip(
                icon: Icons.description_outlined,
                color: _hudCyan,
                label: '$todayRecords registro${todayRecords != 1 ? 's' : ''}',
              ),
              _IndicatorChip(
                icon: Icons.notifications_active_outlined,
                color: totalAlerts > 0 ? _hudDanger : Colors.white38,
                label: '$totalAlerts alerta${totalAlerts != 1 ? 's' : ''}',
              ),
              _IndicatorChip(
                icon: Icons.thermostat_rounded,
                color: _hudAmber,
                label: tempLabel,
              ),
              _IndicatorChip(
                icon: Icons.shield_outlined,
                color: _hudGreen,
                label: dog.operationalStatus,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LastRecordLabel(
            trainingVM: trainingVM,
            healthVM: healthVM,
            routineVM: routineVM,
          ),
        ],
      ),
    );
  }

  int _countTodayRecords(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
    DateTime startOfDay,
  ) {
    int count = 0;
    for (final s in trainingVM.trainings) {
      if (!s.date.isBefore(startOfDay)) count++;
    }
    for (final h in healthVM.healthLogs) {
      if (!h.date.isBefore(startOfDay)) count++;
    }
    for (final i in incidentVM.incidents) {
      if (!i.date.isBefore(startOfDay)) count++;
    }
    for (final r in routineVM.routines) {
      if (!r.timestamp.isBefore(startOfDay)) count++;
    }
    return count;
  }
}

class _IndicatorChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _IndicatorChip({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LastRecordLabel extends StatelessWidget {
  final TrainingViewModel trainingVM;
  final HealthViewModel healthVM;
  final RoutineViewModel routineVM;

  const _LastRecordLabel({
    required this.trainingVM,
    required this.healthVM,
    required this.routineVM,
  });

  @override
  Widget build(BuildContext context) {
    final lastText = _resolveLastRecord();
    return Text(
      lastText,
      style: GoogleFonts.inter(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _resolveLastRecord() {
    DateTime? lastDate;
    String lastType = '';

    if (trainingVM.trainings.isNotEmpty) {
      final s = trainingVM.trainings.first;
      lastDate = s.date;
      lastType = 'Treino';
    }
    if (healthVM.healthLogs.isNotEmpty) {
      final h = healthVM.healthLogs.first;
      if (lastDate == null || h.date.isAfter(lastDate)) {
        lastDate = h.date;
        lastType = h.logType;
      }
    }
    if (routineVM.routines.isNotEmpty) {
      final r = routineVM.routines.first;
      if (lastDate == null || r.timestamp.isAfter(lastDate)) {
        lastDate = r.timestamp;
        lastType = r.activityType;
      }
    }

    if (lastDate == null) return 'Nenhum registro hoje';

    final hour =
        '${lastDate.hour.toString().padLeft(2, '0')}:${lastDate.minute.toString().padLeft(2, '0')}';
    return 'Último registro: $lastType às $hour';
  }
}
