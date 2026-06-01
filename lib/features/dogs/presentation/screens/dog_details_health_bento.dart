part of 'dog_details_screen.dart';

class _HealthSummaryBento extends StatelessWidget {
  final HealthLogModel? lastHealth;
  final DateTime? lastVaccineDate;

  const _HealthSummaryBento({
    required this.lastHealth,
    required this.lastVaccineDate,
  });

  @override
  Widget build(BuildContext context) {
    return _BentoBlock(
      height: 120,
      accent: _healthAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.medical_services_rounded,
                color: _healthAccent,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'SAÚDE',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _healthAccent,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (lastHealth != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lastHealth!.logType,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _formatDogDetailsDate(lastHealth!.date),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppTheme.textPrimary.withAlpha(97),
                  ),
                ),
              ],
            )
          else
            Text(
              'Sem registros',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textPrimary.withAlpha(97),
              ),
            ),
          if (lastVaccineDate != null)
            Row(
              children: [
                Icon(
                  Icons.vaccines_rounded,
                  size: 12,
                  color: AppTheme.textPrimary.withAlpha(97),
                ),
                const SizedBox(width: 4),
                Text(
                  'Vacina: ${_formatDogDetailsDate(lastVaccineDate!)}',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: AppTheme.textPrimary.withAlpha(97),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WeightSummaryBento extends StatelessWidget {
  final Dog dog;
  final double? weight;

  const _WeightSummaryBento({required this.dog, required this.weight});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDogWeightDialog(context, dog, weight),
      child: _BentoBlock(
        height: 120,
        accent: _weightAccent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  color: _weightAccent,
                  size: 18,
                ),
                Icon(
                  Icons.edit_rounded,
                  color: _weightAccent.withAlpha(150),
                  size: 14,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weight != null ? weight!.toStringAsFixed(1) : '--',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'KG',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary.withAlpha(97),
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            Text(
              'PESO',
              style: GoogleFonts.inter(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: _weightAccent,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
