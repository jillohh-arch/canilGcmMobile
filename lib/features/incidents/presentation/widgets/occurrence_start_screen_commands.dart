part of 'occurrence_start_screen.dart';

class _OccurrenceStartCommandGrid extends StatelessWidget {
  final Color panelColor;
  final String locationLabel;
  final String timeLabel;
  final String dateLabel;
  final VoidCallback onRefreshLocation;
  final VoidCallback onRefreshTime;

  const _OccurrenceStartCommandGrid({
    required this.panelColor,
    required this.locationLabel,
    required this.timeLabel,
    required this.dateLabel,
    required this.onRefreshLocation,
    required this.onRefreshTime,
  });

  @override
  Widget build(BuildContext context) {
    final commandColor = AppTheme.primary;

    return Row(
      children: [
        Expanded(
          child: _OccurrenceStartCommandCard(
            icon: Icons.location_on_outlined,
            label: 'LOCAL ATUAL',
            value: locationLabel,
            color: commandColor,
            panelColor: panelColor,
            onTap: onRefreshLocation,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OccurrenceStartCommandCard(
            icon: Icons.access_time_rounded,
            label: 'HORA ATUAL',
            value: '$timeLabel\n$dateLabel',
            color: commandColor,
            panelColor: panelColor,
            onTap: onRefreshTime,
          ),
        ),
      ],
    );
  }
}

class _OccurrenceStartCommandCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color panelColor;
  final VoidCallback onTap;

  const _OccurrenceStartCommandCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.panelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelColor.withAlpha(205),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(115)),
          boxShadow: [BoxShadow(color: color.withAlpha(18), blurRadius: 16)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
