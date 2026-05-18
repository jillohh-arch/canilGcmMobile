part of 'shift_assumption_screen.dart';

class _AssumptionHeader extends StatelessWidget {
  final String displayName;
  final String ra;
  final int dogCount;

  const _AssumptionHeader({
    required this.displayName,
    required this.ra,
    this.dogCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Saudação contextual
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 18
            ? 'Boa tarde'
            : 'Boa noite';

    final now = DateTime.now();
    final weekdays = [
      'segunda',
      'terça',
      'quarta',
      'quinta',
      'sexta',
      'sábado',
      'domingo',
    ];
    final weekday = weekdays[now.weekday - 1];
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'RA $ra · $dateStr · $weekday',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          // ── Title da lista ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Selecione o cão',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (dogCount > 0)
                Text(
                  '$dogCount ${dogCount == 1 ? 'cão' : 'cães'} no canil',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}