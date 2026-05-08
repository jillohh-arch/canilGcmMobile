part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentLatestUpdateIcon
    on _DailyTimelineScreenState {
  Widget _buildIncidentLatestUpdateIcon(_IncidentProgressStyle progressStyle) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: progressStyle.iconBackground,
        shape: BoxShape.circle,
      ),
      child: Icon(progressStyle.icon, size: 16, color: progressStyle.iconColor),
    );
  }
}
