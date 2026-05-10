part of 'shift_assumption_screen.dart';

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
