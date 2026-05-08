part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryIncidentSections on _DailyTimelineScreenState {
  List<Widget> _buildTimelineIncidentSections(
    _TimelineEntry entry,
    Color color,
  ) {
    return [
      ..._buildTimelineOutcomeSection(entry, color),
      ..._buildTimelineProgressSection(entry, color),
    ];
  }
}
