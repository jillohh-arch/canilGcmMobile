part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChartTitles on _DailyTimelineScreenState {
  FlTitlesData _buildEvolutionTitlesData(double chartMaxY) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: chartMaxY / 4,
          getTitlesWidget: _buildEvolutionLeftTitle,
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

  Widget _buildEvolutionLeftTitle(double value, TitleMeta meta) {
    return Text(
      value.toInt().toString(),
      style: GoogleFonts.inter(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
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
}
