import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';

/// Seção REGISTROS RECENTES com mapper visual tolerante de [type].
class HealthSummaryRecentRecords extends StatelessWidget {
  final HealthSummarySectionData<HealthSummaryRecentRecordsView> recentRecords;
  final VoidCallback? onOpenHistory;
  final ValueChanged<HealthSummaryRecentRecordView>? onRecentRecordTap;

  const HealthSummaryRecentRecords({
    super.key,
    required this.recentRecords,
    this.onOpenHistory,
    this.onRecentRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'REGISTROS RECENTES',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Semantics(
              button: onOpenHistory != null,
              enabled: onOpenHistory != null,
              label: 'Ver histórico',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Material(
                  color: AppTheme.transparent,
                  child: InkWell(
                    onTap: onOpenHistory,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver histórico',
                            style: GoogleFonts.inter(
                              color: onOpenHistory != null
                                  ? AppTheme.primary
                                  : AppTheme.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: onOpenHistory != null
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HealthSummaryCardSurface(
          padding: EdgeInsets.zero,
          borderRadius: 14,
          child: _body(),
        ),
      ],
    );
  }

  Widget _body() {
    switch (recentRecords.status) {
      case HealthSummarySectionStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            children: [
              HealthSummarySkeletonBar(height: 16),
              SizedBox(height: 12),
              HealthSummarySkeletonBar(height: 16),
              SizedBox(height: 12),
              HealthSummarySkeletonBar(height: 16),
            ],
          ),
        );
      case HealthSummarySectionStatus.unavailable:
        return _message(
          recentRecords.message ?? 'Dados indisponíveis',
          AppTheme.textSoft,
        );
      case HealthSummarySectionStatus.notRecorded:
        return _message(
          recentRecords.message ?? 'Nenhum registro recente',
          AppTheme.textSecondary,
        );
      case HealthSummarySectionStatus.available:
        final items = recentRecords.value!.items;
        if (items.isEmpty) {
          return _message('Nenhum registro recente', AppTheme.textSecondary);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _RecentTile(
                  record: items[i],
                  isFirst: i == 0,
                  isLast: i == items.length - 1,
                  onTap: onRecentRecordTap == null
                      ? null
                      : () => onRecentRecordTap!(items[i]),
                ),
            ],
          ),
        );
    }
  }

  Widget _message(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final HealthSummaryRecentRecordView record;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const _RecentTile({
    required this.record,
    required this.isFirst,
    required this.isLast,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = HealthSummaryRecentRecordIconMapper.iconFor(record.type);
    final color = HealthSummaryRecentRecordColorMapper.colorFor(record.type);
    final dateLabel = record.occurredAt == null
        ? null
        : HealthSummaryFormatters.shortDate(record.occurredAt!);
    final subtitleParts = <String>[
      ?dateLabel,
      if (record.subtitle != null && record.subtitle!.trim().isNotEmpty)
        record.subtitle!.trim(),
    ];
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(' · ');

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label:
          '${record.title}'
          '${subtitle != null ? '. $subtitle' : ''}',
      excludeSemantics: true,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Expanded(
                          child: isFirst
                              ? const SizedBox()
                              : Center(
                                  child: Container(
                                    width: 2,
                                    color: AppTheme.surfaceWhiteBorder,
                                  ),
                                ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, size: 17, color: color),
                        ),
                        Expanded(
                          child: isLast
                              ? const SizedBox()
                              : Center(
                                  child: Container(
                                    width: 2,
                                    color: AppTheme.surfaceWhiteBorder,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            record.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppTheme.textSoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mapper local de cor semântica para registros recentes do Resumo.
abstract final class HealthSummaryRecentRecordColorMapper {
  static Color colorFor(String type) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) return AppTheme.textSoft;

    if (t.contains('feed') ||
        t.contains('aliment') ||
        t.contains('nutrition') ||
        t.contains('refeic')) {
      return AppTheme.attention;
    }
    if (t.contains('weight') || t.contains('peso') || t.contains('pesagem')) {
      return AppTheme.info;
    }
    if (t.contains('vaccin') || t.contains('vacina')) {
      return AppTheme.success;
    }
    if (t.contains('consult') || t.contains('vet') || t.contains('clin')) {
      return AppTheme.healthAccent;
    }
    if (t.contains('exam') || t.contains('exame')) {
      return AppTheme.healthAccent;
    }
    if (t.contains('treat') ||
        t.contains('medica') ||
        t.contains('dose') ||
        t.contains('protocol')) {
      return AppTheme.primary;
    }
    if (t.contains('surger') || t.contains('cirurg')) {
      return AppTheme.healthAccent;
    }
    if (t.contains('antiparasit')) {
      return AppTheme.success;
    }
    if (t.contains('symptom') || t.contains('sintoma')) {
      return AppTheme.warningAccent;
    }
    if (t.contains('restrict') || t.contains('restric')) {
      return AppTheme.error;
    }
    return AppTheme.textSoft;
  }
}

/// Mapper local tolerante: tipos conhecidos → ícone; desconhecido → neutro.
abstract final class HealthSummaryRecentRecordIconMapper {
  static IconData iconFor(String type) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) return Icons.note_outlined;

    if (t.contains('feed') ||
        t.contains('aliment') ||
        t.contains('nutrition') ||
        t.contains('refeic')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('weight') || t.contains('peso') || t.contains('pesagem')) {
      return Icons.monitor_weight_outlined;
    }
    if (t.contains('vaccin') || t.contains('vacina')) {
      return Icons.verified_user_outlined;
    }
    if (t.contains('consult') || t.contains('vet') || t.contains('clin')) {
      return Icons.medical_services_outlined;
    }
    if (t.contains('exam') || t.contains('exame')) {
      return Icons.assignment_outlined;
    }
    if (t.contains('treat') ||
        t.contains('medica') ||
        t.contains('dose') ||
        t.contains('protocol')) {
      return Icons.medication_outlined;
    }
    if (t.contains('surger') || t.contains('cirurg')) {
      return Icons.medical_services_outlined;
    }
    if (t.contains('antiparasit')) {
      return Icons.shield_outlined;
    }
    if (t.contains('symptom') || t.contains('sintoma')) {
      return Icons.warning_amber_rounded;
    }
    if (t.contains('restrict') || t.contains('restric')) {
      return Icons.gpp_maybe_outlined;
    }
    return Icons.note_outlined;
  }
}
