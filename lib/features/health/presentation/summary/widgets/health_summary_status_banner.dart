import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Banner discreto de erro/offline/stale no topo do dashboard.
enum HealthSummaryBannerKind { error, offline, stale, cache }

class HealthSummaryStatusBanner extends StatelessWidget {
  final HealthSummaryBannerKind kind;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const HealthSummaryStatusBanner({
    super.key,
    required this.kind,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Tentar novamente',
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette(kind);
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(palette.icon, size: 18, color: palette.fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: palette.fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: retryLabel,
                excludeSemantics: true,
                child: Material(
                  color: AppTheme.transparent,
                  child: InkWell(
                    onTap: onRetry,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        retryLabel,
                        style: GoogleFonts.inter(
                          color: palette.fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static _BannerPalette _palette(HealthSummaryBannerKind kind) {
    switch (kind) {
      case HealthSummaryBannerKind.error:
        return _BannerPalette(
          bg: AppTheme.error.withValues(alpha: 0.12),
          border: AppTheme.error.withValues(alpha: 0.45),
          fg: AppTheme.error,
          icon: Icons.error_outline_rounded,
        );
      case HealthSummaryBannerKind.offline:
        return _BannerPalette(
          bg: AppTheme.warning.withValues(alpha: 0.10),
          border: AppTheme.warning.withValues(alpha: 0.40),
          fg: AppTheme.warningAccent,
          icon: Icons.cloud_off_outlined,
        );
      case HealthSummaryBannerKind.stale:
        return _BannerPalette(
          bg: AppTheme.attention.withValues(alpha: 0.10),
          border: AppTheme.attention.withValues(alpha: 0.35),
          fg: AppTheme.attention,
          icon: Icons.schedule_rounded,
        );
      case HealthSummaryBannerKind.cache:
        return _BannerPalette(
          bg: AppTheme.primary.withValues(alpha: 0.08),
          border: AppTheme.primary.withValues(alpha: 0.28),
          fg: AppTheme.primary,
          icon: Icons.offline_bolt_outlined,
        );
    }
  }
}

class _BannerPalette {
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;

  const _BannerPalette({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
  });
}
