import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';

/// Card EVOLUÇÃO DO PESO com gráfico leve (CustomPainter).
class HealthSummaryWeightTrendCard extends StatelessWidget {
  final HealthSummarySectionData<HealthSummaryWeightTrendView> weightTrend;
  final HealthSummarySectionData<HealthSummaryWeightView>? currentWeight;

  const HealthSummaryWeightTrendCard({
    super.key,
    required this.weightTrend,
    this.currentWeight,
  });

  @override
  Widget build(BuildContext context) {
    return HealthSummaryCardSurface(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.show_chart_rounded,
                size: 16,
                color: AppTheme.info,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'EVOLUÇÃO DO PESO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _header(),
          const SizedBox(height: 8),
          SizedBox(height: 96, child: _chartArea()),
          const SizedBox(height: 10),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    final weightLabel = _currentWeightLabel();
    final subtitle = _subtitle();

    if (weightLabel == null && subtitle == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weightLabel != null)
          Text(
            weightLabel,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: AppTheme.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  String? _currentWeightLabel() {
    if (currentWeight != null && currentWeight!.isAvailable) {
      final kg = currentWeight!.value!.weightKg;
      if (!kg.isFinite) return null;
      return HealthSummaryFormatters.weightKg(kg);
    }
    if (weightTrend.isAvailable) {
      final ordered = _orderedFinitePoints(weightTrend.value!.points);
      if (ordered.isEmpty) return null;
      return HealthSummaryFormatters.weightKg(ordered.last.weightKg);
    }
    return null;
  }

  String? _subtitle() {
    DateTime? at;
    if (currentWeight != null && currentWeight!.isAvailable) {
      at = currentWeight!.value!.measuredAt;
    } else if (weightTrend.isAvailable) {
      final ordered = _orderedFinitePoints(weightTrend.value!.points);
      if (ordered.isNotEmpty) at = ordered.last.at;
    }
    if (at == null) return null;
    return HealthSummaryFormatters.lastWeighingLabel(at);
  }

  Widget _chartArea() {
    switch (weightTrend.status) {
      case HealthSummarySectionStatus.loading:
        return const Center(child: HealthSummarySkeletonBar(height: 70));
      case HealthSummarySectionStatus.notRecorded:
        return _emptyChart(weightTrend.message ?? 'Sem histórico suficiente');
      case HealthSummarySectionStatus.unavailable:
        return _emptyChart(weightTrend.message ?? 'Dados indisponíveis');
      case HealthSummarySectionStatus.available:
        final points = _orderedFinitePoints(weightTrend.value!.points);
        if (points.isEmpty) {
          return _emptyChart('Sem histórico suficiente');
        }
        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: HealthSummaryWeightChartPainter(points: points),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            _dateLabels(points),
          ],
        );
    }
  }

  /// Ordena por data e descarta pesos não finitos (apresentação segura).
  static List<HealthSummaryWeightPoint> _orderedFinitePoints(
    List<HealthSummaryWeightPoint> raw,
  ) {
    final filtered = raw
        .where((p) => p.weightKg.isFinite)
        .toList(growable: true);
    filtered.sort((a, b) => a.at.compareTo(b.at));
    return filtered;
  }

  Widget _emptyChart(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: AppTheme.textSoft,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _dateLabels(List<HealthSummaryWeightPoint> points) {
    final labels = _pickLabels(points);
    if (labels.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Text(
              labels[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: i == 0
                  ? TextAlign.left
                  : (i == labels.length - 1
                        ? TextAlign.right
                        : TextAlign.center),
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  List<String> _pickLabels(List<HealthSummaryWeightPoint> points) {
    if (points.isEmpty) return const [];
    if (points.length == 1) {
      return [HealthSummaryFormatters.shortDate(points.first.at)];
    }
    if (points.length == 2) {
      return [
        HealthSummaryFormatters.shortDate(points.first.at),
        HealthSummaryFormatters.shortDate(points.last.at),
      ];
    }
    final mid = points[points.length ~/ 2];
    return [
      HealthSummaryFormatters.shortDate(points.first.at),
      HealthSummaryFormatters.shortDate(mid.at),
      HealthSummaryFormatters.shortDate(points.last.at),
    ];
  }

  Widget _footer() {
    if (!weightTrend.isAvailable) {
      return const SizedBox.shrink();
    }
    final view = weightTrend.value!;
    final hasTarget = view.targetWeightKg != null;
    final hasBcs = view.bodyConditionScore?.trim().isNotEmpty == true;
    if (!hasTarget && !hasBcs) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasTarget)
          Expanded(
            child: _footerMetric(
              label: 'Meta operacional',
              value: HealthSummaryFormatters.weightKg(view.targetWeightKg!),
              icon: null,
            ),
          ),
        if (hasTarget && hasBcs)
          Container(
            width: 1,
            height: 34,
            color: AppTheme.surfaceWhiteBorder,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
        if (hasBcs)
          Expanded(
            child: _footerMetric(
              label: 'Score corporal',
              value: view.bodyConditionScore!.trim(),
              icon: Icons.monitor_heart_outlined,
            ),
          ),
      ],
    );
  }

  Widget _footerMetric({
    required String label,
    required String value,
    required IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppTheme.success),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Gráfico simples de evolução (0 / 1 / N pontos) sem biblioteca pesada.
///
/// Expecta pontos já filtrados/ordenados pelo card. Não classifica tendência.
class HealthSummaryWeightChartPainter extends CustomPainter {
  final List<HealthSummaryWeightPoint> points;

  const HealthSummaryWeightChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    if (!size.width.isFinite || !size.height.isFinite) return;

    final gridPaint = Paint()
      ..color = AppTheme.surfaceWhiteBorder
      ..strokeWidth = 1;
    for (final y in [size.height * .25, size.height * .5, size.height * .75]) {
      if (!y.isFinite) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final values = <double>[];
    for (final p in points) {
      if (p.weightKg.isFinite) values.add(p.weightKg);
    }
    if (values.isEmpty) return;

    var minVal = values.reduce((a, b) => a < b ? a : b);
    var maxVal = values.reduce((a, b) => a > b ? a : b);
    if (!minVal.isFinite || !maxVal.isFinite) return;

    if ((maxVal - minVal).abs() < 0.1) {
      minVal -= 0.5;
      maxVal += 0.5;
    } else {
      final pad = (maxVal - minVal) * 0.15;
      minVal -= pad;
      maxVal += pad;
    }
    final span = maxVal - minVal;
    if (!span.isFinite || span <= 0) return;

    final plotHeight = (size.height - 12).clamp(1.0, size.height);
    final offsets = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final normalized = ((values[i] - minVal) / span).clamp(0.0, 1.0);
      final y = size.height - (normalized * plotHeight) - 6;
      if (!x.isFinite || !y.isFinite) continue;
      offsets.add(Offset(x, y));
    }
    if (offsets.isEmpty) return;

    final linePaint = Paint()
      ..color = AppTheme.info
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (offsets.length == 1) {
      canvas.drawCircle(offsets.first, 4.5, Paint()..color = AppTheme.info);
      canvas.drawCircle(
        offsets.first,
        4.5,
        Paint()
          ..color = AppTheme.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }

    final fill = Path.from(path)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.info.withValues(alpha: 0.22),
            AppTheme.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < offsets.length; i++) {
      final radius = i == offsets.length - 1 ? 4.0 : 3.0;
      canvas.drawCircle(offsets[i], radius, Paint()..color = AppTheme.info);
    }
  }

  @override
  bool shouldRepaint(covariant HealthSummaryWeightChartPainter oldDelegate) {
    if (identical(oldDelegate.points, points)) return false;
    if (oldDelegate.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (oldDelegate.points[i] != points[i]) return true;
    }
    return false;
  }
}
