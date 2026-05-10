part of 'occurrence_timeline_preview.dart';

class _OccurrenceTimelineTile extends StatelessWidget {
  final IncidentProgressUpdate update;
  final Color accent;
  final bool isLatest;
  final VoidCallback? onTap;

  const _OccurrenceTimelineTile({
    required this.update,
    required this.accent,
    required this.isLatest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eventVisual = _visualForTimelineTitle(update.title, accent);
    final eventColor = eventVisual.color;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLatest
              ? eventColor.withAlpha(14)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isLatest ? eventColor.withAlpha(120) : Colors.white12,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimelineLeadingVisual(
              update: update,
              eventVisual: eventVisual,
              isLatest: isLatest,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimelineEventBody(
                update: update,
                accent: accent,
                isLatest: isLatest,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withAlpha(90),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
