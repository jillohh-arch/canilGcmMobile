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

  FlTitlesData _buildEvolutionTitlesData(double chartMaxY) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: chartMaxY / 4,
          getTitlesWidget: (value, meta) => Text(
            value.toInt().toString(),
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: _buildEvolutionBottomTitle,
        ),
      ),
    );
  }

  Widget _buildEvolutionBottomTitle(double value, TitleMeta meta) {
    final index = value.toInt();
    final labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    if (index < 0 || index >= labels.length) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final date = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: 6 - index));

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        labels[date.weekday - 1],
        style: GoogleFonts.inter(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

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
