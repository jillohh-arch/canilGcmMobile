// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChart on _DailyTimelineScreenState {
  Widget _buildEvolutionBarChart(String dogId) {
    final dailySummaries = _buildDailyTrainingSummaries(dogId);
    final chartMaxY = _resolveEvolutionChartMaxY(dailySummaries);

    return Container(
      height: 320,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(60)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(14), blurRadius: 16)],
      ),
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              _buildEvolutionBarChartData(
                dailySummaries: dailySummaries,
                chartMaxY: chartMaxY,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildEvolutionLegend(),
        ],
      ),
    );
  }
}
