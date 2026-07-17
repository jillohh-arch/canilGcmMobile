import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Quatro KPIs derivados de [HealthScheduleGroups] (sem contador paralelo).
///
/// Em largura < 420: grid 2×2. Acima: uma linha (fidelidade ao mockup mobile).
class HealthScheduleKpiRow extends StatelessWidget {
  final HealthScheduleGroups groups;

  const HealthScheduleKpiRow({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile(
        label: HealthScheduleUserCopy.kpiPending,
        hint: HealthScheduleUserCopy.kpiPendingHint,
        count: groups.pending.length,
        color: AppTheme.warning,
        icon: Icons.warning_amber_rounded,
        semanticsLabel:
            '${HealthScheduleUserCopy.kpiPending}: ${groups.pending.length}',
      ),
      _KpiTile(
        label: HealthScheduleUserCopy.kpiToday,
        hint: HealthScheduleUserCopy.kpiTodayHint,
        count: groups.today.length,
        color: AppTheme.primary,
        icon: Icons.today_rounded,
        semanticsLabel:
            '${HealthScheduleUserCopy.kpiToday}: ${groups.today.length}',
      ),
      _KpiTile(
        label: HealthScheduleUserCopy.kpiUpcoming,
        hint: HealthScheduleUserCopy.kpiUpcomingHint,
        count: groups.upcoming.length,
        color: AppTheme.success,
        icon: Icons.event_available_rounded,
        semanticsLabel:
            '${HealthScheduleUserCopy.kpiUpcoming}: ${groups.upcoming.length}',
      ),
      _KpiTile(
        label: HealthScheduleUserCopy.kpiOverdue,
        hint: HealthScheduleUserCopy.kpiOverdueHint,
        count: groups.overdue.length,
        color: AppTheme.error,
        icon: Icons.schedule_rounded,
        semanticsLabel:
            '${HealthScheduleUserCopy.kpiOverdue}: ${groups.overdue.length}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 8),
                  Expanded(child: tiles[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String hint;
  final int count;
  final Color color;
  final IconData icon;
  final String semanticsLabel;

  const _KpiTile({
    required this.label,
    required this.hint,
    required this.count,
    required this.color,
    required this.icon,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticsLabel. $hint',
      child: HealthSummaryCardSurface(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        borderRadius: 12,
        borderColor: color.withValues(alpha: 0.28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color.withValues(alpha: 0.9)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: GoogleFonts.inter(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
