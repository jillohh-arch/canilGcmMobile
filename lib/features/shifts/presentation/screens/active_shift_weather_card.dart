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
