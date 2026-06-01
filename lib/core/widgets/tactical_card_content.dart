part of 'tactical_card.dart';

class _TacticalCardContent extends StatelessWidget {
  final Widget? avatar;
  final String title;
  final String? subtitle;
  final Widget? rightBadge;
  final List<Widget> alerts;
  final List<TacticalCardStat> stats;

  const _TacticalCardContent({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.rightBadge,
    required this.alerts,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TacticalCardHeader(
          avatar: avatar,
          title: title,
          subtitle: subtitle,
          rightBadge: rightBadge,
          alerts: alerts,
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TacticalCardStatsRow(stats: stats),
        ],
      ],
    );
  }
}

class _TacticalCardHeader extends StatelessWidget {
  final Widget? avatar;
  final String title;
  final String? subtitle;
  final Widget? rightBadge;
  final List<Widget> alerts;

  const _TacticalCardHeader({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.rightBadge,
    required this.alerts,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (avatar != null) ...[avatar!, const SizedBox(width: 14)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.8,
                  height: 1.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary.withAlpha(153),
                  ),
                ),
              ],
              if (alerts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: alerts),
              ],
            ],
          ),
        ),
        if (rightBadge != null) ...[const SizedBox(width: 8), rightBadge!],
      ],
    );
  }
}

class _TacticalCardStatsRow extends StatelessWidget {
  final List<TacticalCardStat> stats;

  const _TacticalCardStatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 28,
                color: AppTheme.textPrimary.withAlpha(61),
              ),
            Expanded(child: stats[i]),
          ],
        ],
      ),
    );
  }
}
