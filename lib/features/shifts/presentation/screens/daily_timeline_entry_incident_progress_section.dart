part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryIncidentProgressSection
    on _DailyTimelineScreenState {
  List<Widget> _buildTimelineProgressSection(
    _TimelineEntry entry,
    Color color,
  ) {
    if (entry.type != 'Ocorrência' ||
        entry.details['_progressUpdates'] is! List ||
        (entry.details['_progressUpdates'] as List).isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 14),
      Text(
        'LINHA DO TEMPO',
        style: GoogleFonts.inter(
          color: color.withAlpha(230),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      _buildIncidentProgressTimeline(
        updates: entry.details['_progressUpdates'] as List,
        accent: color,
      ),
    ];
  }
}
