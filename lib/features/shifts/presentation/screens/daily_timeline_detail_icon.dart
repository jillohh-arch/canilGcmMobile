part of 'daily_timeline_screen.dart';

extension _DailyTimelineDetailIcon on _DailyTimelineScreenState {
  Widget _buildTimelineDetailIcon(IconData icon, Color accent) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Icon(icon, size: 14, color: accent.withAlpha(230)),
    );
  }
}
