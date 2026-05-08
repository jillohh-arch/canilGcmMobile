part of 'daily_timeline_screen.dart';

typedef _EvolutionWeekComparisonStyle = ({
  Color accent,
  IconData icon,
  bool isUp,
  bool isDown,
});

extension _DailyTimelineEvolutionWeekComparisonStyle
    on _DailyTimelineScreenState {
  _EvolutionWeekComparisonStyle _resolveEvolutionWeekComparisonStyle(
    double deltaMinutes,
  ) {
    final isUp = deltaMinutes > 0;
    final isDown = deltaMinutes < 0;

    return (
      accent: isUp
          ? const Color(0xFF4ADE80)
          : isDown
          ? const Color(0xFFF87171)
          : const Color(0xFF94A3B8),
      icon: isUp
          ? Icons.trending_up_rounded
          : isDown
          ? Icons.trending_down_rounded
          : Icons.remove_rounded,
      isUp: isUp,
      isDown: isDown,
    );
  }
}
