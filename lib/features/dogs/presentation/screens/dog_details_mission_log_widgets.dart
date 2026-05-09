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
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: Colors.white10)),
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
            const Icon(Icons.timeline_rounded, size: 40, color: Colors.white12),
            const SizedBox(height: 8),
            Text(
              'Nenhuma atividade registrada',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white24),
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

class _MissionTimelineRail extends StatelessWidget {
  final _MissionTimelineItem item;
  final bool isLast;

  const _MissionTimelineRail({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.color.withAlpha(30),
              border: Border.all(color: item.color.withAlpha(120), width: 1.5),
            ),
            child: Icon(item.icon, color: item.color, size: 16),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
        ],
      ),
    );
  }
}

class _MissionTimelineContent extends StatelessWidget {
  final _MissionTimelineItem item;
  final String dateStr;

  const _MissionTimelineContent({required this.item, required this.dateStr});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MissionTagChip(item: item),
            Text(
              dateStr,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white30,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          item.title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        if (item.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.subtitle,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.white38,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _MissionTagChip extends StatelessWidget {
  final _MissionTimelineItem item;

  const _MissionTagChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: item.color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.tag,
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: item.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
