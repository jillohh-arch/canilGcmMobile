import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Marker discreto da linha cronológica.
///
/// Prioriza cyan / acento controlado; evita círculos gigantes ou neon.
class HealthTimelineMarker extends StatelessWidget {
  final Color accent;
  final bool cancelled;
  final double size;

  const HealthTimelineMarker({
    super.key,
    required this.accent,
    this.cancelled = false,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    final color = cancelled
        ? AppTheme.textMuted
        : accent.withValues(alpha: 0.95);
    final border = cancelled
        ? AppTheme.textMuted.withValues(alpha: 0.55)
        : color;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cancelled
            ? AppTheme.surfacePanelAlt
            : color.withValues(alpha: 0.18),
        border: Border.all(color: border, width: 2),
        boxShadow: cancelled
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.32,
        height: size * 0.32,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// Desenha rail vertical + marker sem [IntrinsicHeight].
///
/// O [CustomPaint] ocupa a altura do card (via [Stack]/[Positioned]),
/// evitando layout multi-pass por item em listas longas.
class HealthTimelineRailPainter extends CustomPainter {
  HealthTimelineRailPainter({
    required this.isFirst,
    required this.isLast,
    required this.accent,
    required this.cancelled,
    this.markerCenterY = 22,
    this.markerRadius = 6,
  });

  final bool isFirst;
  final bool isLast;
  final Color accent;
  final bool cancelled;
  final double markerCenterY;
  final double markerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = AppTheme.primary.withValues(alpha: 0.22);
    final markerColor = cancelled
        ? AppTheme.textMuted
        : accent.withValues(alpha: 0.95);
    final cx = size.width / 2;
    final cy = markerCenterY.clamp(
      markerRadius + 1,
      size.height - markerRadius,
    );

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, cy - markerRadius), linePaint);
    }
    if (!isLast && size.height > cy + markerRadius) {
      canvas.drawLine(
        Offset(cx, cy + markerRadius),
        Offset(cx, size.height),
        linePaint,
      );
    }

    final fill = Paint()
      ..color = cancelled
          ? AppTheme.surfacePanelAlt
          : markerColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = cancelled
          ? AppTheme.textMuted.withValues(alpha: 0.55)
          : markerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final core = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), markerRadius, fill);
    canvas.drawCircle(Offset(cx, cy), markerRadius, border);
    canvas.drawCircle(Offset(cx, cy), markerRadius * 0.32, core);
  }

  @override
  bool shouldRepaint(covariant HealthTimelineRailPainter oldDelegate) {
    return oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.accent != accent ||
        oldDelegate.cancelled != cancelled;
  }
}
