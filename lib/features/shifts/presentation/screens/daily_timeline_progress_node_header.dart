part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgressNodeHeader on _DailyTimelineScreenState {
  Widget _buildProgressNodeHeader({
    required int index,
    required String title,
    required Color accent,
    required _IncidentProgressStyle progressStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ETAPA ${(index + 1).toString().padLeft(2, '0')}',
          style: GoogleFonts.inter(
            color: accent.withAlpha(210),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              color: progressStyle.titleColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}
