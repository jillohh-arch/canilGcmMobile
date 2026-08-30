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
                color: AppTheme.attention,
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nutrition.isDegraded) ...[
              Semantics(
                container: true,
                liveRegion: true,
                label: nutrition.message,
                excludeSemantics: true,
                child: _statusMessage(
                  nutrition.message ??
                      'Dados de nutrição parcialmente disponíveis.',
                  AppTheme.warningAccent,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _available(nutrition.value!),
          ],
        );
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
    final mealsLine = _mealsLine(view.mealsRecorded, view.mealsPlanned);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          planned == null || !planned.isFinite || planned <= 0
              ? 'Meta diária não informada'
              : 'Meta diária: ${HealthSummaryFormatters.amount(planned, unit)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        _ProgressMetric(
          label: 'Oferecido',
          amount: offered,
          planned: planned,
          unit: unit,
          color: AppTheme.attention,
        ),
        const SizedBox(height: 12),
        _ProgressMetric(
          label: 'Consumido',
          amount: consumed,
          planned: planned,
          unit: unit,
          color: AppTheme.success,
          unknownLabel: 'Consumo não informado',
        ),
        if (mealsLine != null) ...[
          const SizedBox(height: 12),
          Text(
            mealsLine,
            style: GoogleFonts.inter(
              color: AppTheme.textSoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
    );
  }

  static String? _mealsLine(int? recorded, int? planned) {
    if (recorded == null && planned == null) return null;
    if (recorded != null && planned != null) {
      return '$recorded de $planned refeições executadas';
    }
    if (recorded != null) {
      return recorded == 1
          ? '1 refeição registrada'
          : '$recorded refeições registradas';
    }
    return '$planned refeições planejadas';
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.label,
    required this.amount,
    required this.planned,
    required this.unit,
    required this.color,
    this.unknownLabel,
  });

  final String label;
  final double? amount;
  final double? planned;
  final String? unit;
  final Color color;
  final String? unknownLabel;

  @override
  Widget build(BuildContext context) {
    final validAmount = amount != null && amount!.isFinite;
    final validPlan = planned != null && planned!.isFinite && planned! > 0;
    final ratio = validAmount && validPlan ? amount! / planned! : null;
    final visualProgress = ratio?.clamp(0.0, 1.0).toDouble();
    final text = !validAmount
        ? (unknownLabel ?? '$label não informado')
        : validPlan
        ? '$label: ${HealthSummaryFormatters.amount(amount!, unit)} de '
              '${HealthSummaryFormatters.amount(planned!, unit)}'
        : '$label: ${HealthSummaryFormatters.amount(amount!, unit)}';
    final semanticsLabel = !validAmount
        ? '$label, quantidade não informada.'
        : validPlan
        ? '$label, ${_semanticAmount(amount!)} de uma meta de '
              '${_semanticAmount(planned!)}, '
              '${(visualProgress! * 100).round()} por cento.'
        : '$label, ${_semanticAmount(amount!)}. '
              'Meta diária não informada.';

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: validAmount ? AppTheme.textPrimary : AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (visualProgress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: visualProgress,
                minHeight: 8,
                backgroundColor: AppTheme.surfaceWhiteOverlay,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _semanticAmount(double value) {
    final formatted = HealthSummaryFormatters.amount(value, unit);
    return unit?.trim().toLowerCase() == 'g'
        ? formatted.replaceFirst(RegExp(r'\s*g$'), ' gramas')
        : formatted;
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
