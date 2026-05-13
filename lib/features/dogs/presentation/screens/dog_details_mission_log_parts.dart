part of 'dog_details_screen.dart';

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
