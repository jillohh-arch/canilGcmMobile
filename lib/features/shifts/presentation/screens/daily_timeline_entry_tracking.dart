part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryTracking on _DailyTimelineScreenState {
  List<Widget> _buildTimelineTrackingSections(
    _TimelineEntry entry,
    Color color,
  ) {
    return [
      ..._buildTimelineDistanceSection(entry, color),
      ..._buildTimelineRouteSection(entry),
    ];
  }
}
