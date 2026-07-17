import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_formatters.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Card read-only de item da Agenda (sem ações de write).
class HealthScheduleItemCard extends StatelessWidget {
  final HealthScheduleItemView item;
  final DateTime Function()? now;

  const HealthScheduleItemCard({super.key, required this.item, this.now});

  @override
  Widget build(BuildContext context) {
    final status = item.temporalStatus;
    final accent = HealthScheduleFormatters.statusColor(status);
    final muted =
        status == HealthScheduleTemporalStatus.cancelled ||
        status == HealthScheduleTemporalStatus.completed;
    final clock = now?.call() ?? DateTime.now().toUtc();
    final when = HealthScheduleFormatters.whenLabel(item, now: clock);
    final statusLabel = HealthScheduleFormatters.statusLabel(status);
    final typeLabel = HealthScheduleFormatters.typeLabel(item.scheduleType);
    final assignee = item.assignedToName?.trim();

    final semantic =
        '$typeLabel, ${item.title}, $statusLabel, $when'
        '${assignee != null && assignee.isNotEmpty ? ', responsável $assignee' : ''}';

    return Semantics(
      label: semantic,
      child: HealthSummaryCardSurface(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        borderRadius: 14,
        borderColor: muted
            ? AppTheme.outline.withValues(alpha: 0.5)
            : accent.withValues(alpha: 0.28),
        backgroundColor: muted
            ? AppTheme.surfacePanelSoft.withValues(alpha: 0.9)
            : AppTheme.surfacePanel.withValues(alpha: 0.94),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: muted ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: accent.withValues(alpha: muted ? 0.15 : 0.28),
                ),
              ),
              child: Icon(
                HealthScheduleFormatters.typeIcon(item.scheduleType),
                color: accent.withValues(alpha: muted ? 0.55 : 0.95),
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        label: statusLabel,
                        color: accent,
                        muted: muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: muted
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.notes!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (assignee != null && assignee.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            assignee,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool muted;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: muted ? 0.08 : 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: muted ? 0.2 : 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color.withValues(alpha: muted ? 0.7 : 1),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
