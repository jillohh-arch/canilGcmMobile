part of 'active_shift_dashboard_screen.dart';

class _WeatherCockpitCard extends StatefulWidget {
  @override
  State<_WeatherCockpitCard> createState() => _WeatherCockpitCardState();
}

class _WeatherCockpitCardState extends State<_WeatherCockpitCard> {
  String _temp = '--°C';
  String _humidity = 'Umidade --%';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final weatherService = WeatherService();
      final weather = await weatherService.getCurrentWeather(
        position.latitude,
        position.longitude,
      );

      if (weather != null && mounted) {
        setState(() {
          _temp = '${weather['temperature']}°C';
          _humidity = 'Umidade ${weather['humidity']}%';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'CONDIÇÕES / CLIMA',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 0.9,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.thermostat_rounded, color: _hudAmber, size: 36),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  _temp,
                  style: GoogleFonts.oxanium(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _hudCyan,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
          Text(
            _humidity,
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftMetricsCockpitCard extends StatefulWidget {
  final Dog dog;
  const _ShiftMetricsCockpitCard({required this.dog});

  @override
  State<_ShiftMetricsCockpitCard> createState() =>
      _ShiftMetricsCockpitCardState();
}

class _ShiftMetricsCockpitCardState extends State<_ShiftMetricsCockpitCard> {
  Timer? _timer;
  String _activeTimeText = '--h --m';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final startTime = shiftVM.shiftStartTime;
    if (startTime != null) {
      final diff = DateTime.now().difference(startTime);
      final hours = diff.inHours.toString().padLeft(2, '0');
      final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _activeTimeText = '${hours}h ${minutes}m ${seconds}s';
      });
    } else {
      setState(() {
        _activeTimeText = '--h --m';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int todayLogs = _countTodayRecords(context);

    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TEMPO ATIVO',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 0.9,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: _hudCyan, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _activeTimeText,
                    style: GoogleFonts.oxanium(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _hudCyan,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '$todayLogs registro${todayLogs == 1 ? '' : 's'} hoje',
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  int _countTodayRecords(BuildContext context) {
    final healthLogs = Provider.of<HealthViewModel>(context).healthLogs;
    final trainings = Provider.of<TrainingViewModel>(context).trainings;
    final incidents = Provider.of<IncidentViewModel>(context).incidents;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    bool isToday(DateTime value) {
      return !value.isBefore(startOfDay) && value.isBefore(endOfDay);
    }

    final healthCount = healthLogs.where((log) {
      return log.dogId == widget.dog.id && isToday(log.date);
    }).length;
    final trainingCount = trainings.where((training) {
      return training.dogId == widget.dog.id && isToday(training.date);
    }).length;
    final incidentCount = incidents.where((incident) {
      return incident.dogId == widget.dog.id && isToday(incident.date);
    }).length;

    return healthCount + trainingCount + incidentCount;
  }
}

// Health Alert Banner ---------------------------------------------------------
class _HealthAlertBanner extends StatelessWidget {
  final String dogId;
  const _HealthAlertBanner({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final hVM = Provider.of<HealthViewModel>(context);
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));

    // Find health logs that have a return date within the next 7 days
    final alerts = hVM.healthLogs.where((h) {
      if (h.dogId != dogId) return false;
      // Return date is stored as "Retorno agendado: DD/MM/YYYY"
      if (!h.healthObservations.contains('Retorno agendado:')) return false;
      try {
        final raw = h.healthObservations.split('Retorno agendado:').last.trim();
        final parts = raw.split('/');
        if (parts.length != 3) return false;
        final date = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        return date.isAfter(now.subtract(const Duration(days: 1))) &&
            date.isBefore(horizon);
      } catch (_) {
        return false;
      }
    }).toList();

    if (alerts.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final nextLog = alerts.first;
    final rawDate = nextLog.healthObservations
        .split('Retorno agendado:')
        .last
        .trim()
        .split('\n')
        .first
        .trim();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(235),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudAmber, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _hudAmber.withAlpha(40),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: _hudAmber,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALERTA DE SAÚDE',
                      style: GoogleFonts.robotoMono(
                        color: _hudAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${nextLog.logType} — Retorno agendado: $rawDate',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Today Activities Card -------------------------------------------------------
