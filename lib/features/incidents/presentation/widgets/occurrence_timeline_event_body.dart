part of 'occurrence_timeline_preview.dart';

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
