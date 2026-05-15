part of 'daily_timeline_screen.dart';

extension _DailyTimelineItemIndicator on _DailyTimelineScreenState {
  IndicatorStyle _buildTimelineTileIndicator(
    _TimelineTilePresentation presentation,
  ) {
    final color = presentation.color;

    return IndicatorStyle(
      width: 40,
      height: 40,
      drawGap: true,
      indicator: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(140),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(child: Icon(presentation.icon, color: color, size: 19)),
      ),
    );
  }
}
