import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Banner discreto de falha de refresh com dados ainda visíveis.
///
/// Pequeno, não modal, não bloqueia interação. Some naturalmente
/// quando o próximo refresh/1ª página tiver sucesso (estado limpo).
class HealthTimelineRefreshBanner extends StatelessWidget {
  final bool offline;
  final String? message;
  final VoidCallback? onRetry;

  const HealthTimelineRefreshBanner({
    super.key,
    this.offline = false,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final text =
        message ??
        (offline
            ? HealthTimelineUserCopy.refreshOffline
            : HealthTimelineUserCopy.refreshError);
    final fg = offline ? AppTheme.warningAccent : AppTheme.error;
    final bg = offline
        ? AppTheme.warning.withValues(alpha: 0.10)
        : AppTheme.error.withValues(alpha: 0.10);
    final border = offline
        ? AppTheme.warning.withValues(alpha: 0.35)
        : AppTheme.error.withValues(alpha: 0.35);
    final icon = offline
        ? Icons.cloud_off_outlined
        : Icons.error_outline_rounded;

    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  color: fg,
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
                label: HealthTimelineUserCopy.retry,
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
                        HealthTimelineUserCopy.retry,
                        style: GoogleFonts.inter(
                          color: fg,
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
}
