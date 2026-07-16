import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Skeleton de carregamento coerente com headers + linha + cards.
class HealthTimelineLoadingView extends StatelessWidget {
  const HealthTimelineLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: HealthTimelineUserCopy.loadingMessage,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [
            _SkeletonDayBlock(),
            SizedBox(height: 20),
            _SkeletonDayBlock(entryCount: 1),
          ],
        ),
      ),
    );
  }
}

class _SkeletonDayBlock extends StatelessWidget {
  final int entryCount;

  const _SkeletonDayBlock({this.entryCount = 2});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 36, bottom: 10),
          child: HealthSummarySkeletonBar(height: 12, width: 72),
        ),
        for (var i = 0; i < entryCount; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 2,
                      height: 10,
                      color: i == 0
                          ? AppTheme.transparent
                          : AppTheme.primary.withValues(alpha: 0.15),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceWhiteOverlay,
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.25),
                          width: 2,
                        ),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 56,
                      color: AppTheme.primary.withValues(alpha: 0.15),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: HealthSummaryCardSurface(
                  padding: EdgeInsets.all(14),
                  borderRadius: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HealthSummarySkeletonBar(height: 10, width: 140),
                      SizedBox(height: 10),
                      HealthSummarySkeletonBar(height: 14, width: 200),
                      SizedBox(height: 8),
                      HealthSummarySkeletonBar(height: 12),
                      SizedBox(height: 8),
                      HealthSummarySkeletonBar(height: 10, width: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Empty / error / offline / initial — superfície central consistente.
class HealthTimelineSurfaceMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HealthTimelineSurfaceMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = AppTheme.textMuted,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: iconColor),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HealthTimelineEmptyView extends StatelessWidget {
  final bool hasActiveFilters;
  final VoidCallback? onFilterRequested;

  const HealthTimelineEmptyView({
    super.key,
    this.hasActiveFilters = false,
    this.onFilterRequested,
  });

  @override
  Widget build(BuildContext context) {
    if (hasActiveFilters) {
      return HealthTimelineSurfaceMessage(
        icon: Icons.filter_alt_off_outlined,
        title: HealthTimelineUserCopy.emptyWithFiltersTitle,
        message: HealthTimelineUserCopy.emptyWithFiltersMessage,
        actionLabel: onFilterRequested == null
            ? null
            : HealthTimelineUserCopy.filterAction,
        onAction: onFilterRequested,
      );
    }
    return const HealthTimelineSurfaceMessage(
      icon: Icons.inbox_outlined,
      title: HealthTimelineUserCopy.emptyTitle,
      message: HealthTimelineUserCopy.emptyMessage,
    );
  }
}

class HealthTimelineErrorStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const HealthTimelineErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return HealthTimelineSurfaceMessage(
      icon: Icons.error_outline_rounded,
      iconColor: AppTheme.error,
      title: HealthTimelineUserCopy.errorTitle,
      message: message,
      actionLabel: onRetry == null ? null : HealthTimelineUserCopy.retry,
      onAction: onRetry,
    );
  }
}

class HealthTimelineOfflineStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const HealthTimelineOfflineStateView({
    super.key,
    this.message = HealthTimelineUserCopy.offlineMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return HealthTimelineSurfaceMessage(
      icon: Icons.wifi_off_rounded,
      iconColor: AppTheme.warning,
      title: HealthTimelineUserCopy.offlineTitle,
      message: message,
      actionLabel: onRetry == null ? null : HealthTimelineUserCopy.retry,
      onAction: onRetry,
    );
  }
}
