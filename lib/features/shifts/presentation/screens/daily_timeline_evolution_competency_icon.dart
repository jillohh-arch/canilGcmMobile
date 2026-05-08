part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencyIcon on _DailyTimelineScreenState {
  Widget _buildEvolutionCompetencyIcon({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
