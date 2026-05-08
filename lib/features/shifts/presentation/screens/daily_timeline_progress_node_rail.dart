part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressNodeRail on _DailyTimelineScreenState {
  Widget _buildProgressNodeRail({
    required bool isLast,
    required _IncidentProgressStyle progressStyle,
  }) {
    return SizedBox(
      width: 34,
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: progressStyle.iconBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: progressStyle.iconColor.withAlpha(170)),
              boxShadow: [
                BoxShadow(
                  color: progressStyle.iconColor.withAlpha(70),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(
              progressStyle.icon,
              size: 15,
              color: progressStyle.iconColor,
            ),
          ),
          if (!isLast)
            Container(
              width: 2,
              height: 58,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: progressStyle.borderColor.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
