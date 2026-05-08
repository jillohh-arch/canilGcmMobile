part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryMedia on _DailyTimelineScreenState {
  List<Widget> _buildTimelineMediaSections(_TimelineEntry entry, Color color) {
    final attachments = entry.details['_mediaAttachments'] as List? ?? const [];

    return [
      ..._buildTimelinePhotoGallery(attachments, color),
      ..._buildTimelinePdfButton(entry, attachments),
    ];
  }
}
