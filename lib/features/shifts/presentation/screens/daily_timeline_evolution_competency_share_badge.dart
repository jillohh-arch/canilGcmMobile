part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencyShareBadge
    on _DailyTimelineScreenState {
  Widget _buildEvolutionCompetencyShareBadge({
    required double share,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${share.toStringAsFixed(0)}%',
        style: GoogleFonts.robotoMono(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
