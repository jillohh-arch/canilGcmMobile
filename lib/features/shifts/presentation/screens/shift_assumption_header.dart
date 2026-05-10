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
          Text(
            'K9 DUTY SELECTION',
            style: GoogleFonts.robotoMono(
              color: _hudCyan,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(232),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(110)),
              boxShadow: [
                BoxShadow(color: _hudCyan.withAlpha(22), blurRadius: 18),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _hudCyan.withAlpha(18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _hudCyan.withAlpha(130)),
                  ),
                  child: const Icon(
                    Icons.pets_rounded,
                    color: _hudCyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECIONE SEU CÃO',
                        style: GoogleFonts.oxanium(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Bem-vindo, ${displayName.toUpperCase()}. Escolha o K9 que vai assumir o plantão.',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _DogCountBadge(count: dogCount),
              ],
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
