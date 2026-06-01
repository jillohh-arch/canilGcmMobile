part of 'health_dashboard_screen.dart';

class _ReadinessHudBar extends StatelessWidget {
  final Dog dog;
  final List<HealthLogModel> logs;
  final DateTime? lastBath;

  const _ReadinessHudBar({
    required this.dog,
    required this.logs,
    required this.lastBath,
  });

  @override
  Widget build(BuildContext context) {
    final latestWeight = logs
        .where((log) => log.weight != null)
        .map((log) => log.weight!)
        .cast<double?>()
        .firstWhere((weight) => weight != null, orElse: () => null);
    final breakdown = dog.calculateReadinessBreakdown(
      lastBathOverride: lastBath,
      weightOverride: latestWeight,
    );
    final score = breakdown.total;
    final barColor = _readinessColor(score);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRONTIDÃO',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppTheme.textPrimary.withAlpha(138),
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.shareTechMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: AppTheme.surfacePanel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: barColor.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppTheme.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vacinação, peso, higiene e treino recente.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textPrimary.withAlpha(97),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vacinação ${breakdown.vacinacao}/30 • Peso ${breakdown.peso}/25 • Higiene ${breakdown.higiene}/15 • Treino ${breakdown.treino}/30',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textPrimary.withAlpha(153),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _readinessColor(int score) {
    if (score >= 80) return AppTheme.primary;
    if (score >= 50) return AppTheme.attention;
    return AppTheme.errorStrong;
  }
}
