import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Skeleton de loading da Agenda (padrão Resumo/Timeline).
class HealthScheduleLoadingView extends StatelessWidget {
  const HealthScheduleLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: HealthScheduleUserCopy.loadingMessage,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: const [
            Row(
              children: [
                Expanded(child: _KpiSkeleton()),
                SizedBox(width: 8),
                Expanded(child: _KpiSkeleton()),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _KpiSkeleton()),
                SizedBox(width: 8),
                Expanded(child: _KpiSkeleton()),
              ],
            ),
            SizedBox(height: 20),
            HealthSummarySkeletonBar(height: 12, width: 100),
            SizedBox(height: 10),
            HealthSummaryCardSurface(
              padding: EdgeInsets.all(14),
              borderRadius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HealthSummarySkeletonBar(height: 10, width: 80),
                  SizedBox(height: 10),
                  HealthSummarySkeletonBar(height: 14, width: 180),
                  SizedBox(height: 8),
                  HealthSummarySkeletonBar(height: 12),
                ],
              ),
            ),
            SizedBox(height: 10),
            HealthSummaryCardSurface(
              padding: EdgeInsets.all(14),
              borderRadius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HealthSummarySkeletonBar(height: 10, width: 60),
                  SizedBox(height: 10),
                  HealthSummarySkeletonBar(height: 14, width: 160),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();

  @override
  Widget build(BuildContext context) {
    return const HealthSummaryCardSurface(
      padding: EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthSummarySkeletonBar(height: 10, width: 64),
          SizedBox(height: 10),
          HealthSummarySkeletonBar(height: 20, width: 28),
        ],
      ),
    );
  }
}

/// Empty / error / offline / initial.
class HealthScheduleSurfaceMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HealthScheduleSurfaceMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = AppTheme.primary,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: HealthSummaryCardSurface(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: iconColor.withValues(alpha: 0.9)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                Semantics(
                  button: true,
                  label: actionLabel,
                  child: TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
