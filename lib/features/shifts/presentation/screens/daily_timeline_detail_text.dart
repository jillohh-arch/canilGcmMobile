part of 'daily_timeline_screen.dart';

extension _DailyTimelineDetailText on _DailyTimelineScreenState {
  Widget _buildTimelineDetailText(String label, String value, bool expanded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: expanded ? 12 : 13,
            fontWeight: expanded ? FontWeight.w500 : FontWeight.w800,
            height: 1.35,
          ),
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          maxLines: expanded ? null : 2,
        ),
      ],
    );
  }
}
