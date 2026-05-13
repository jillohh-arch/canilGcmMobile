part of 'active_shift_dashboard_screen.dart';

/// Seção "CONDIÇÕES" com temperatura, umidade e risco térmico.
class _ConditionsCard extends StatefulWidget {
  final WeatherData? weatherData;

  const _ConditionsCard({this.weatherData});

  @override
  State<_ConditionsCard> createState() => _ConditionsCardState();
}

class _ConditionsCardState extends State<_ConditionsCard> {
  double? _temperature;
  int? _humidity;
  String? _riskFromFirestore;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _initWeather();
  }

  @override
  void didUpdateWidget(covariant _ConditionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.weatherData != oldWidget.weatherData) {
      _initWeather();
    }
  }

  void _initWeather() {
    if (widget.weatherData != null) {
      setState(() {
        _temperature = widget.weatherData!.temperatura;
        _humidity = widget.weatherData!.umidade;
        _riskFromFirestore = widget.weatherData!.riscoTermico;
        _loaded = true;
      });
    } else {
      _loadFromApi();
    }
  }

  Future<void> _loadFromApi() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      final weather = await WeatherService().getCurrentWeather(
        position.latitude,
        position.longitude,
      );
      if (mounted && weather != null) {
        setState(() {
          _temperature = (weather['temperature'] as num?)?.toDouble();
          _humidity = (weather['humidity'] as num?)?.toInt();
          _loaded = true;
        });
      } else if (mounted) {
        setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _riskLevel() {
    if (_riskFromFirestore != null && _riskFromFirestore != '--') {
      return _riskFromFirestore!;
    }
    if (_temperature == null) return '--';
    if (_temperature! >= 35) return 'ALTO';
    if (_temperature! >= 30) return 'MODERADO';
    return 'BAIXO';
  }

  Color _riskColor() {
    final risk = _riskLevel();
    switch (risk) {
      case 'ALTO':
        return _hudDanger;
      case 'MODERADO':
        return _hudAmber;
      case 'BAIXO':
        return _hudGreen;
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_outlined, color: _hudCyan, size: 15),
            const SizedBox(width: 6),
            Text(
              'CONDIÇÕES',
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(200),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hudCyan.withAlpha(30)),
          ),
          child: _loaded ? _buildContent() : _buildLoading(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Row(
      children: [
        // Temperatura
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.thermostat_rounded, color: _hudAmber, size: 18),
              const SizedBox(width: 6),
              Text(
                _temperature != null ? '${_temperature!.round()}°C' : '--°C',
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, height: 28, color: Colors.white.withAlpha(15)),
        // Umidade
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.water_drop_outlined, color: _hudCyan, size: 16),
              const SizedBox(width: 6),
              Text(
                _humidity != null ? '$_humidity%' : '--%',
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, height: 28, color: Colors.white.withAlpha(15)),
        // Risco térmico
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: _riskColor(), size: 16),
              const SizedBox(width: 6),
              Text(
                _riskLevel(),
                style: GoogleFonts.oxanium(
                  color: _riskColor(),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _hudCyan),
      ),
    );
  }
}
