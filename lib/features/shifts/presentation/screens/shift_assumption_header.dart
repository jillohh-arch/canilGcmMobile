part of 'shift_assumption_screen.dart';

class _AssumptionHeader extends StatelessWidget {
  final String displayName;
  final int dogCount;

  const _AssumptionHeader({required this.displayName, required this.dogCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELEÇÃO DE CÃO',
                style: GoogleFonts.robotoMono(
                  color: _hudCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.4,
                ),
              ),
              _DogCountBadge(count: dogCount),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bem-vindo, ${displayName.toUpperCase()}. Escolha o K9 para o plantão.',
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DogCountBadge extends StatelessWidget {
  final int count;

  const _DogCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _hudCyan.withAlpha(14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(120)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.oxanium(
              color: _hudCyan,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'K9',
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
