part of 'occurrence_command_header.dart';

class _CommandHeaderFrame extends StatelessWidget {
  final Color accent;
  final Widget child;

  const _CommandHeaderFrame({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF07101C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(150), width: 1.2),
        boxShadow: [
          BoxShadow(color: accent.withAlpha(34), blurRadius: 26),
          const BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _CommandHeaderGlow(accent: accent)),
          Positioned(
            right: 22,
            top: 34,
            child: Icon(
              Icons.shield_rounded,
              size: 126,
              color: accent.withAlpha(18),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _CommandHeaderGlow extends StatelessWidget {
  final Color accent;

  const _CommandHeaderGlow({required this.accent});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: RadialGradient(
          center: const Alignment(0.55, -0.55),
          radius: 1.2,
          colors: [accent.withAlpha(32), const Color(0xFF07101C).withAlpha(0)],
        ),
      ),
    );
  }
}
