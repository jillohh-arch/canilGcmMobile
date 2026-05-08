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

class _StartShiftButton extends StatelessWidget {
  final bool isStarting;

  const _StartShiftButton({required this.isStarting});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: _hudCyan,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(70), blurRadius: 16)],
      ),
      child: Center(
        child: isStarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _hudBackground,
                ),
              )
            : Text(
                'ASSUMIR TURNO',
                style: GoogleFonts.robotoMono(
                  color: _hudBackground,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hudBackground.withAlpha(180),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(150)),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _PageIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: List.generate(count, (index) {
        final selected = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? _hudCyan : Colors.white24,
            borderRadius: BorderRadius.circular(4),
            boxShadow: selected
                ? [BoxShadow(color: _hudCyan.withAlpha(80), blurRadius: 10)]
                : null,
          ),
        );
      }),
    );
  }
}

class _EmptyDogState extends StatelessWidget {
  const _EmptyDogState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(230),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(80)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.dog,
                size: 44,
                color: _hudCyan.withAlpha(160),
              ),
              const SizedBox(height: 16),
              Text(
                'NENHUM CÃO DISPONÍVEL',
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cadastre ou libere um K9 para iniciar o plantão.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _HudGlow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: size / 2, spreadRadius: 18),
          ],
        ),
      ),
    );
  }
}
