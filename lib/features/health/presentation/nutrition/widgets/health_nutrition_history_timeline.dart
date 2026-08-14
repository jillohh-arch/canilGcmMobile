import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_marker.dart';

/// Uma entrada da timeline local de Nutrição.
///
/// Presentation-only. Todos os campos já vêm resolvidos pela tela — este widget
/// não lê período, origem nem status de nenhuma fonte.
@immutable
class HealthNutritionHistoryEntry {
  const HealthNutritionHistoryEntry({
    required this.group,
    required this.title,
    required this.whenLabel,
    required this.detailLine,
    required this.isLegacy,
    this.statusLabel,
    this.statusColor,
  });

  final HealthNutritionPeriodGroup group;
  final String title;
  final String whenLabel;
  final String detailLine;

  /// Proveniência legada. Renderizada como BADGE, nunca como cor do marcador:
  /// a cor carrega período, e trocá-la por origem perderia a informação de
  /// coexistência que a tela exibia antes.
  final bool isLegacy;

  final String? statusLabel;
  final Color? statusColor;
}

/// Timeline vertical compacta dos registros recentes de Nutrição.
///
/// Reusa [HealthTimelineRailPainter] (trilha + marcador) e
/// [HealthSummaryCardSurface], mantendo a anatomia já aprovada no Health:
/// card deslocado 36px à direita com a trilha desenhada atrás.
class HealthNutritionHistoryTimeline extends StatelessWidget {
  const HealthNutritionHistoryTimeline({
    super.key,
    required this.entries,
  });

  final List<HealthNutritionHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final HealthNutritionHistoryEntry entry;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final visual = HealthNutritionPeriodVisuals.resolve(entry.group);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 36, bottom: 8),
          child: HealthSummaryCardSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: 14,
            borderColor: visual.accent.withValues(alpha: 0.22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: visual.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(visual.icon, size: 17, color: visual.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (entry.statusLabel != null &&
                              entry.statusColor != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: entry.statusColor!.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                entry.statusLabel!,
                                style: GoogleFonts.inter(
                                  color: entry.statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.whenLabel,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.detailLine,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      if (entry.isLegacy) ...[
                        const SizedBox(height: 6),
                        _LegacyBadge(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 8,
          width: 28,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: HealthTimelineRailPainter(
                isFirst: isFirst,
                isLast: isLast,
                accent: visual.accent,
                cancelled: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Badge de proveniência legada — canal separado da cor do período.
class _LegacyBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhiteOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.surfaceWhiteBorderMedium),
      ),
      child: Text(
        'legado',
        style: GoogleFonts.inter(
          color: AppTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
