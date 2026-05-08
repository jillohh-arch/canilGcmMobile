part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentTimeFormatters on _DailyTimelineScreenState {
  String _formatIncidentRelative(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays > 0) {
      return '${diff.inDays}d';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes.clamp(0, 59)}m';
  }

  String _formatIncidentTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
