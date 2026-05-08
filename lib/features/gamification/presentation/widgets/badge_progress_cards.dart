part of 'gamification_progress_widgets.dart';

class NextBadgeHighlightCard extends StatelessWidget {
  final BadgeData badge;
  final BadgeProgress progress;

  const NextBadgeHighlightCard({
    super.key,
    required this.badge,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            badge.color.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.24),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badge.color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: badge.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'PRÓXIMO TROFÉU',
                style: GoogleFonts.inter(
                  color: badge.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(badge.icon, color: badge.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      badge.description,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(18),
              valueColor: AlwaysStoppedAnimation<Color>(badge.color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress.summary,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            progress.remaining == 0
                ? 'Pronto para desbloquear'
                : 'Faltam ${progress.remaining} ${progress.unitLabel}.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class BadgeProgressCard extends StatelessWidget {
  final BadgeData badge;
  final BadgeProgress progress;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const BadgeProgressCard({
    super.key,
    required this.badge,
    required this.progress,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final remainingLabel = progress.remaining == 0
        ? 'Pronto para desbloquear'
        : 'Faltam ${progress.remaining} ${progress.unitLabel}';

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: badge.color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(badge.icon, color: badge.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress.summary,
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).round()}%',
                style: GoogleFonts.inter(
                  color: badge.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(14),
              valueColor: AlwaysStoppedAnimation<Color>(badge.color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remainingLabel,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
