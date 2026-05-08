part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionStatRows on _DailyTimelineScreenState {
  Widget _buildEvolutionPrimaryStats({
    required int totalSessions,
    required double totalMinutes,
  }) {
    return Row(
      children: [
        _StatBox(
          label: 'SESSÕES',
          value: '$totalSessions',
          icon: Icons.format_list_numbered_rounded,
          color: const Color(0xFF00E5FF),
        ),
        const SizedBox(width: 10),
        _StatBox(
          label: 'TEMPO',
          value: totalMinutes > 0
              ? '${totalMinutes.toStringAsFixed(0)} min'
              : '--',
          icon: Icons.timer_rounded,
          color: const Color(0xFF00E5FF),
        ),
      ],
    );
  }

  Widget _buildEvolutionSecondaryStats({
    required double averageMinutes,
    required String mostFrequentCategory,
    required ({IconData icon, Color color}) focusVisual,
  }) {
    return Row(
      children: [
        _StatBox(
          label: 'MÉDIA',
          value: averageMinutes > 0
              ? '${averageMinutes.toStringAsFixed(1)} min'
              : '--',
          icon: Icons.bar_chart_rounded,
          color: const Color(0xFF00E5FF),
        ),
        const SizedBox(width: 10),
        _StatBox(
          label: 'FOCO',
          value: mostFrequentCategory,
          icon: focusVisual.icon,
          color: focusVisual.color,
        ),
      ],
    );
  }
}
