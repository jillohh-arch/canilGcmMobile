part of 'occurrence_timeline_preview.dart';

class _TimelineMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _TimelineMetaChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _TimelineLeadingVisual extends StatelessWidget {
  final IncidentProgressUpdate update;
  final _OccurrenceEventVisual eventVisual;
  final bool isLatest;

  const _TimelineLeadingVisual({
    required this.update,
    required this.eventVisual,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    final eventColor = eventVisual.color;
    final assetPath = eventVisual.assetPath;

    return SizedBox(
      width: 48,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: eventColor.withAlpha(isLatest ? 35 : 18),
              shape: BoxShape.circle,
              border: Border.all(color: eventColor.withAlpha(150)),
            ),
            child: assetPath == null
                ? Icon(eventVisual.icon, color: eventColor, size: 20)
                : Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(eventVisual.icon, color: eventColor, size: 20),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatHour(update.timestamp),
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEventBody extends StatelessWidget {
  final IncidentProgressUpdate update;
  final Color accent;
  final bool isLatest;

  const _TimelineEventBody({
    required this.update,
    required this.accent,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                update.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              _TimelineMetaChip(
                icon: Icons.bolt_rounded,
                label: 'RECENTE',
                accent: accent,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        _TimelineMetaWrap(update: update, accent: accent),
        if ((update.location ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            update.location!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
        if (update.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            update.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: Colors.white70, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _TimelineMetaWrap extends StatelessWidget {
  final IncidentProgressUpdate update;
  final Color accent;

  const _TimelineMetaWrap({required this.update, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if ((update.authorName ?? '').isNotEmpty)
          _TimelineMetaChip(
            icon: Icons.person_rounded,
            label: update.authorName!,
            accent: accent,
          ),
        if ((update.location ?? '').isNotEmpty)
          _TimelineMetaChip(
            icon: Icons.place_rounded,
            label: 'Local',
            accent: accent,
          ),
        if (update.attachments.isNotEmpty)
          _TimelineMetaChip(
            icon: Icons.photo_camera_rounded,
            label:
                '${update.attachments.length} foto${update.attachments.length == 1 ? '' : 's'}',
            accent: accent,
          ),
        if (update.latitude != null && update.longitude != null)
          _TimelineMetaChip(
            icon: Icons.my_location_rounded,
            label: 'GPS',
            accent: accent,
          ),
      ],
    );
  }
}

String _formatHour(DateTime timestamp) {
  return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
}
