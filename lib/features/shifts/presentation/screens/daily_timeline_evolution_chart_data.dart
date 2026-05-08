part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChartData on _DailyTimelineScreenState {
  double _resolveEvolutionChartMaxY(List<_DailyTrainingSummary> summaries) {
    final maxY = summaries.fold<double>(
      0,
      (max, summary) => summary.minutes > max ? summary.minutes : max,
    );

    return maxY <= 0 ? 30.0 : (maxY * 1.25).clamp(30, 240).toDouble();
  }

  BarChartData _buildEvolutionBarChartData({
    required List<_DailyTrainingSummary> dailySummaries,
    required double chartMaxY,
  }) {
    return BarChartData(
      maxY: chartMaxY,
      alignment: BarChartAlignment.spaceAround,
      gridData: _buildEvolutionGridData(chartMaxY),
      borderData: FlBorderData(show: false),
      titlesData: _buildEvolutionTitlesData(chartMaxY),
      barTouchData: _buildEvolutionBarTouchData(dailySummaries),
      barGroups: _buildEvolutionBarGroups(dailySummaries),
    );
  }

  FlGridData _buildEvolutionGridData(double chartMaxY) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: chartMaxY / 4,
      getDrawingHorizontalLine: (value) {
        return FlLine(color: Colors.white.withAlpha(18), strokeWidth: 1);
      },
    );
  }
}
