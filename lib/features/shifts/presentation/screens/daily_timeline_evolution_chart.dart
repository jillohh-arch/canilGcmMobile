// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChart on _DailyTimelineScreenState {
  Widget _buildTrainingFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'Todos',
            selected: _selectedTrainingFilter == null,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedTrainingFilter = null);
            },
          ),
          ..._DailyTimelineScreenState._trainingCategories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _FilterChip(
                label: cat,
                selected: _selectedTrainingFilter == cat,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                    () => _selectedTrainingFilter =
                        _selectedTrainingFilter == cat ? null : cat,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionBarChart(String dogId) {
    final dailySummaries = _buildDailyTrainingSummaries(dogId);
    final maxY = dailySummaries.fold<double>(
      0,
      (max, summary) => summary.minutes > max ? summary.minutes : max,
    );
    final chartMaxY = maxY <= 0
        ? 30.0
        : (maxY * 1.25).clamp(30, 240).toDouble();

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
              BarChartData(
                maxY: chartMaxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMaxY / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withAlpha(18),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: chartMaxY / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final now = DateTime.now();
                        final date = DateTime(
                          now.year,
                          now.month,
                          now.day,
                        ).subtract(Duration(days: 6 - value.toInt()));
                        final labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
                        if (value.toInt() < 0 ||
                            value.toInt() >= labels.length) {
                          return const SizedBox.shrink();
                        }
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
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
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
                ),
                barGroups: dailySummaries.asMap().entries.map((entry) {
                  final summary = entry.value;
                  final visual = summary.primaryCategory == null
                      ? null
                      : _resolveEvolutionCategoryVisual(
                          summary.primaryCategory!,
                        );
                  final isEmpty = summary.minutes == 0;
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: summary.minutes,
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                        color: isEmpty
                            ? Colors.white.withAlpha(18)
                            : visual!.color,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _DailyTimelineScreenState._trainingCategories.map((
              category,
            ) {
              final visual = _resolveEvolutionCategoryVisual(category);
              return _buildEvolutionLegendChip(
                label: category,
                color: visual.color,
                icon: visual.icon,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionLegendChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
