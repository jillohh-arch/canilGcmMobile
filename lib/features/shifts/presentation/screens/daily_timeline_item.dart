part of 'daily_timeline_screen.dart';

extension _DailyTimelineItem on _DailyTimelineScreenState {
  Widget _buildTimelineTile({
    required _TimelineEntry entry,
    required int index,
    required int total,
    required String dogId,
    required String dogName,
  }) {
    final current = entry;
    final presentation = _resolveTimelineTilePresentation(current);
    final color = presentation.color;

    return TimelineTile(
      alignment: TimelineAlign.manual,
      lineXY: 0.12,
      isFirst: index == 0,
      isLast: index == total - 1,
      beforeLineStyle: LineStyle(color: color.withAlpha(90), thickness: 2.5),
      afterLineStyle: LineStyle(color: color.withAlpha(70), thickness: 2.5),
      indicatorStyle: _buildTimelineTileIndicator(presentation),
      endChild: _buildTimelineTileCard(
        entry: current,
        presentation: presentation,
        dogId: dogId,
        dogName: dogName,
      ),
    );
  }
}
