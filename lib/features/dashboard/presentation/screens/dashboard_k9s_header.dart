part of 'dashboard_screen.dart';

class _K9SelectionHeader extends StatelessWidget {
  final int count;

  const _K9SelectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(210),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(65)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hudCyan.withAlpha(18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _hudCyan.withAlpha(120)),
                ),
                child: const Icon(
                  Icons.pets_rounded,
                  color: _hudCyan,
                  size: 18,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cães operacionais disponíveis',
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _hudCyan.withAlpha(16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _hudCyan.withAlpha(120)),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _hudCyan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
