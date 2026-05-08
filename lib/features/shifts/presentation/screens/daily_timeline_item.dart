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
      indicatorStyle: IndicatorStyle(
        width: 40,
        height: 40,
        drawGap: true,
        indicator: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF070B14),
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
      ),
      endChild: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4, bottom: 16, top: 4),
        child: Card(
          elevation: 0,
          color: const Color(0xFF0B1020),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: color.withAlpha(150), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 4)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withAlpha(32),
                    const Color(0xFF0F1726),
                    const Color(0xFF070B14),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  onExpansionChanged: (expanded) {
                    if (expanded) HapticFeedback.lightImpact();
                  },
                  iconColor: color,
                  collapsedIconColor: color.withAlpha(180),
                  tilePadding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  title: _buildTimelineTileHeader(presentation),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._buildTimelineExpandedContent(
                            entry: current,
                            color: color,
                            dogId: dogId,
                            dogName: dogName,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
