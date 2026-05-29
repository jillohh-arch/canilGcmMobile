import 'package:flutter/material.dart';

const _hudPanel = Color(0xFF0E1A1F);

class HudPanel extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final double? width;

  const HudPanel({
    super.key,
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(14),
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(236),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(150), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(34),
            blurRadius: 22,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                gradient: LinearGradient(
                  colors: [accent.withAlpha(60), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(top: 8, left: 8, child: HudCorner(accent)),
          Positioned(top: 8, right: 8, child: HudCorner(accent, flip: true)),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class HudCorner extends StatelessWidget {
  final Color color;
  final bool flip;
  final double size;

  const HudCorner(this.color, {super.key, this.flip = false, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1.0 : 1.0,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HudCornerPainter(color)),
      ),
    );
  }
}

class _HudCornerPainter extends CustomPainter {
  final Color color;

  const _HudCornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HudCornerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
