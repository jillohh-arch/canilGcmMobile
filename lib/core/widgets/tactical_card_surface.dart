part of 'tactical_card.dart';

class _TacticalCardSurface extends StatelessWidget {
  final LinearGradient gradient;
  final double? height;
  final Widget child;

  const _TacticalCardSurface({
    required this.gradient,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: height,
      constraints: height == null ? const BoxConstraints(minHeight: 148) : null,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withAlpha(90),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const _TacticalCardCircleDecoration(
            right: -50,
            bottom: -30,
            size: 200,
            alpha: 18,
          ),
          const _TacticalCardCircleDecoration(
            right: 20,
            top: -60,
            size: 120,
            alpha: 10,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _TacticalCardCircleDecoration extends StatelessWidget {
  final double right;
  final double? top;
  final double? bottom;
  final double size;
  final int alpha;

  const _TacticalCardCircleDecoration({
    required this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.textPrimary.withAlpha(alpha),
        ),
      ),
    );
  }
}
