part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryTrackingDistance on _DailyTimelineScreenState {
  List<Widget> _buildTimelineDistanceSection(
    _TimelineEntry entry,
    Color color,
  ) {
    final rawDistance =
        entry.details['_trackingDistance'] ??
        entry.details['_trackingdistance'];
    if (rawDistance is! num) {
      return const [];
    }

    return [
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.background.withAlpha(220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(140), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.straighten_rounded, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              'DISTÂNCIA TOTAL PERCORRIDA: ',
              style: GoogleFonts.inter(
                color: color.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              _formatTrackingDistance(rawDistance.toDouble()),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  String _formatTrackingDistance(double distance) {
    if (distance > 999) {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
    return '${distance.toStringAsFixed(1)} m';
  }
}
