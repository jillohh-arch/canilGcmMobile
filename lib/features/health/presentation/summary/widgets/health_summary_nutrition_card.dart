import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';

/// Card ALIMENTAÇÃO HOJE — apenas apresentação do read model 2B.
class HealthSummaryNutritionCard extends StatelessWidget {
  final HealthSummarySectionData<HealthSummaryNutritionTodayView> nutrition;
  final VoidCallback? onOpenNutrition;
  final VoidCallback? onRegisterFeeding;

  const HealthSummaryNutritionCard({
    super.key,
    required this.nutrition,
    this.onOpenNutrition,
    this.onRegisterFeeding,
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
                Icons.restaurant_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ALIMENTAÇÃO HOJE',
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
          const SizedBox(height: 12),
          _body(),
          const SizedBox(height: 16),
          _PrimaryCta(
            label: 'Abrir Nutrição',
            onTap: onOpenNutrition,
            filled: true,
          ),
          const SizedBox(height: 8),
          _PrimaryCta(
            label: 'Registrar alimentação',
            onTap: onRegisterFeeding,
            filled: false,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (nutrition.status) {
      case HealthSummarySectionStatus.loading:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HealthSummarySkeletonBar(height: 22, width: 140),
            SizedBox(height: 10),
            HealthSummarySkeletonBar(height: 12, width: 120),
            SizedBox(height: 14),
            HealthSummarySkeletonBar(height: 8),
          ],
        );
      case HealthSummarySectionStatus.notRecorded:
        return _statusMessage(
          nutrition.message ?? 'Nenhum plano registrado',
          AppTheme.textSecondary,
        );
      case HealthSummarySectionStatus.unavailable:
        return _statusMessage(
          nutrition.message ?? 'Dados indisponíveis',
          AppTheme.textSoft,
        );
      case HealthSummarySectionStatus.available:
        return _available(nutrition.value!);
    }
  }

  Widget _statusMessage(String text, Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _available(HealthSummaryNutritionTodayView view) {
    final unit = view.unitLabel;
    final consumed = view.consumedAmount;
    final offered = view.offeredAmount;
    final planned = view.plannedAmount;

    final effectiveAmount = consumed ?? offered;
    final headline = _headline(
      consumed: consumed,
      offered: offered,
      planned: planned,
      unit: unit,
    );
    final mealsLine = _mealsLine(view.mealsRecorded, view.mealsPlanned);
    final progress = _progress(effectiveAmount, planned);
    final percentLabel = progress == null
        ? null
        : '${(progress * 100).clamp(0, 999).round()}%';
    final barValue = progress?.clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        if (mealsLine != null) ...[
          const SizedBox(height: 6),
          Text(
            mealsLine,
            style: GoogleFonts.inter(
              color: AppTheme.textSoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (barValue != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: barValue,
                    minHeight: 8,
                    backgroundColor: AppTheme.surfaceWhiteOverlay,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              if (percentLabel != null) ...[
                const SizedBox(width: 10),
                Text(
                  percentLabel,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (consumed != null &&
              planned != null &&
              planned.isFinite &&
              consumed.isFinite &&
              planned > 0 &&
              consumed > planned) ...[
            const SizedBox(height: 6),
            Text(
              'Consumo acima da meta',
              style: GoogleFonts.inter(
                color: AppTheme.warningAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ],
    );
  }

  static String _headline({
    double? consumed,
    double? offered,
    double? planned,
    String? unit,
  }) {
    if (consumed == null && offered == null && planned == null) {
      return 'Sem quantidades';
    }

    final amount = consumed ?? offered;
    final isOfferedOnly = consumed == null && offered != null;
    final suffix = isOfferedOnly ? ' oferecidos' : '';

    if (amount != null && planned != null) {
      return '${HealthSummaryFormatters.amount(amount, unit)}$suffix de '
          '${HealthSummaryFormatters.amount(planned, unit)}';
    }
    if (amount != null) {
      return '${HealthSummaryFormatters.amount(amount, unit)}$suffix';
    }
    return 'Meta ${HealthSummaryFormatters.amount(planned!, unit)}';
  }

  static String? _mealsLine(int? recorded, int? planned) {
    if (recorded == null && planned == null) return null;
    if (recorded != null && planned != null) {
      return '$recorded de $planned refeições registradas';
    }
    if (recorded != null) {
      return recorded == 1
          ? '1 refeição registrada'
          : '$recorded refeições registradas';
    }
    return '$planned refeições planejadas';
  }

  /// Progresso visual trivial. Meta zero / null / não-finito → sem barra.
  /// Nunca retorna NaN ou Infinity.
  static double? _progress(double? consumed, double? planned) {
    if (consumed == null || planned == null) return null;
    if (!consumed.isFinite || !planned.isFinite) return null;
    if (planned <= 0) return null;
    final ratio = consumed / planned;
    if (!ratio.isFinite) return null;
    return ratio;
  }
}

class _PrimaryCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  const _PrimaryCta({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: filled
                  ? AppTheme.primary.withValues(alpha: 0.18)
                  : AppTheme.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: filled ? 0.55 : 0.75),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (filled) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
