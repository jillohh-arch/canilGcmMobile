part of 'dog_details_screen.dart';

class _MissionTimelineItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String tag;

  const _MissionTimelineItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tag,
  });
}

class _MissionLogHeader extends StatelessWidget {
  const _MissionLogHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'LOG DE MISSÕES',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: AppTheme.textPrimary.withAlpha(97),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.textPrimary.withAlpha(26),
          ),
        ),
      ],
    );
  }
}

class _MissionLogEmptyState extends StatelessWidget {
  const _MissionLogEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.timeline_rounded,
              size: 40,
              color: AppTheme.textPrimary.withAlpha(31),
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhuma atividade registrada',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textPrimary.withAlpha(61),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionTimelineRow extends StatelessWidget {
  final _MissionTimelineItem item;
  final bool isLast;

  const _MissionTimelineRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr =
        '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year.toString().substring(2)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MissionTimelineRail(item: item, isLast: isLast),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
                child: _MissionTimelineContent(item: item, dateStr: dateStr),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
