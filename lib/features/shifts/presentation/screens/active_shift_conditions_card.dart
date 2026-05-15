part of 'active_shift_dashboard_screen.dart';

/// Card de condições ambientais: temperatura, umidade, risco térmico.
class _ConditionsCard extends StatelessWidget {
  final WeatherData weatherData;

  const _ConditionsCard({required this.weatherData});

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColor(weatherData.riscoTermico);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONDIÇÕES AMBIENTAIS',
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ConditionItem(
                icon: Icons.thermostat_outlined,
                value: '${weatherData.temperatura.round()}°C',
                label: 'Temperatura',
              ),
              const SizedBox(width: 24),
              _ConditionItem(
                icon: Icons.water_drop_outlined,
                value: '${weatherData.umidade}%',
                label: 'Umidade',
              ),
              const SizedBox(width: 24),
              _ConditionItem(
                icon: Icons.warning_amber_rounded,
                value: weatherData.riscoTermico,
                label: 'Risco térmico',
                valueColor: riskColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _riskColor(String risco) {
    switch (risco.toUpperCase()) {
      case 'ALTO':
        return AppTheme.error;
      case 'MODERADO':
        return AppTheme.warning;
      default:
        return AppTheme.success;
    }
  }
}

class _ConditionItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  const _ConditionItem({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}