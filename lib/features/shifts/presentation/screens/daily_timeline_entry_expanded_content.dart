part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryExpandedContent on _DailyTimelineScreenState {
  List<Widget> _buildTimelineExpandedContent({
    required _TimelineEntry entry,
    required Color color,
    required String dogId,
    required String dogName,
  }) {
    return [
      _buildTimelineDetailPanel(entry, color),
      ..._buildTimelineIncidentSections(entry, color),
      ..._buildTimelineTrackingSections(entry, color),
      ..._buildTimelineMediaSections(entry, color),
      const SizedBox(height: 16),
      _buildTimelineEditAction(
        entry: entry,
        color: color,
        dogId: dogId,
        dogName: dogName,
      ),
    ];
  }
}
