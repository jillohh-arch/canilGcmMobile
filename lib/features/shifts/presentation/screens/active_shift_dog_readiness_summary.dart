part of 'active_shift_dashboard_screen.dart';

class _DogReadinessSummary extends StatelessWidget {
  final ({int total, int vacinacao, int peso, int higiene, int treino})
  breakdown;

  const _DogReadinessSummary({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final score = breakdown.total;
    final barColor = _readinessColor(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white60,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.oxanium(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: barColor,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white.withAlpha(18),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vacinação, peso, higiene e treino recente.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vacinação ${breakdown.vacinacao}/30 • Peso ${breakdown.peso}/25 • Higiene ${breakdown.higiene}/15 • Treino ${breakdown.treino}/30',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _readinessColor(int score) {
    if (score >= 80) return _hudGreen;
    if (score >= 50) return _hudAmber;
    return _hudDanger;
  }
}
