part of 'daily_timeline_screen.dart';

extension _DailyTimelineItemHeader on _DailyTimelineScreenState {
  Widget _buildTimelineTileHeader(_TimelineTilePresentation presentation) {
    final color = presentation.color;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(170)),
            boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 12)],
          ),
          child: Icon(presentation.icon, color: color, size: 17),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                presentation.title.toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.1,
                ),
                softWrap: true,
              ),
              const SizedBox(height: 5),
              Text(
                presentation.subtitle,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                softWrap: true,
              ),
              if (presentation.mainMetric.isNotEmpty) ...[
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withAlpha(120)),
                    ),
                    child: Text(
                      presentation.mainMetric,
                      style: GoogleFonts.inter(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
