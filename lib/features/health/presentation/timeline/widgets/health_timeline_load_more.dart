import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Rodapé de paginação controlada (sem infinite scroll automático).
class HealthTimelineLoadMore extends StatelessWidget {
  final bool isLoadingMore;
  final String? loadMoreError;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  const HealthTimelineLoadMore({
    super.key,
    required this.isLoadingMore,
    required this.hasMore,
    this.loadMoreError,
    this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    // Progress tem prioridade sobre botão e erro.
    if (isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Semantics(
          liveRegion: true,
          label: HealthTimelineUserCopy.loadingMore,
          child: Column(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                HealthTimelineUserCopy.loadingMore,
                style: GoogleFonts.inter(
                  color: AppTheme.textSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Erro local só faz sentido se ainda há paginação ou retry explícito.
    if (loadMoreError != null && (hasMore || onLoadMore != null)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
          container: true,
          label: HealthTimelineUserCopy.loadMoreError,
          child: Column(
            children: [
              Text(
                HealthTimelineUserCopy.loadMoreError,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onLoadMore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  HealthTimelineUserCopy.retry,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hasMore || onLoadMore == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Semantics(
          button: true,
          label: HealthTimelineUserCopy.loadMore,
          child: OutlinedButton(
            onPressed: onLoadMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.55)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              HealthTimelineUserCopy.loadMore.toUpperCase(),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
