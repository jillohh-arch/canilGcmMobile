part of 'occurrence_form_scaffold.dart';

class _OccurrenceScaffoldGlowLayer extends StatelessWidget {
  final Color accentColor;

  const _OccurrenceScaffoldGlowLayer({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 80,
          left: -120,
          child: _HudGlow(color: accentColor.withAlpha(36), size: 240),
        ),
        Positioned(
          right: -140,
          bottom: 120,
          child: _HudGlow(color: accentColor.withAlpha(24), size: 280),
        ),
      ],
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

class _OccurrenceFormFooter extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final Widget child;

  const _OccurrenceFormFooter({
    required this.backgroundColor,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(244),
        border: const Border(top: BorderSide(color: Color(0x3300E5FF))),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(30),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: child,
    );
  }
}
