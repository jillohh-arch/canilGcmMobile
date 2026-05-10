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
