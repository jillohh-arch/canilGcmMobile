part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChartBars on _DailyTimelineScreenState {
  BarTouchData _buildEvolutionBarTouchData(
    List<_DailyTrainingSummary> dailySummaries,
  ) {
    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => const Color(0xFF1E1E1E),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final summary = dailySummaries[group.x.toInt()];
          final categoryLabel = summary.categories.isEmpty
              ? 'Sem treino'
              : summary.categories.join(' • ');
          return BarTooltipItem(
            '${rod.toY.toStringAsFixed(0)} min\n$categoryLabel',
            GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  List<BarChartGroupData> _buildEvolutionBarGroups(
    List<_DailyTrainingSummary> dailySummaries,
  ) {
    return dailySummaries.asMap().entries.map((entry) {
      final summary = entry.value;
      final visual = summary.primaryCategory == null
          ? null
          : _resolveEvolutionCategoryVisual(summary.primaryCategory!);
      final isEmpty = summary.minutes == 0;

      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: summary.minutes,
            width: 18,
            borderRadius: BorderRadius.circular(6),
            color: isEmpty ? Colors.white.withAlpha(18) : visual!.color,
          ),
        ],
      );
    }).toList();
  }
}
