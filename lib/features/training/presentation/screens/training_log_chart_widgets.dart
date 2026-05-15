part of 'training_log_screen.dart';

class _ChartSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(60), width: 0.8),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(14), blurRadius: 14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _hudCyan,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white30,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// Search Duration Line Chart (fl_chart)
class _SearchDurationChart extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SearchDurationChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final spots = sessions.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.searchDuration!.toDouble());
    }).toList();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) * 0.25;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: (minY - yPad).clamp(0, double.infinity),
          maxY: maxY + yPad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.white10,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (val, meta) => Text(
                  '${val.round()}s',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= sessions.length) {
                    return const SizedBox();
                  }
                  final d = sessions[idx].date;
                  return Text(
                    '${d.day}/${d.month}',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: Colors.white38,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                return LineTooltipItem(
                  '${s.y.round()}s',
                  GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppTheme.amber,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 4,
                      color: AppTheme.amber,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.amber.withAlpha(60),
                    AppTheme.amber.withAlpha(0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Section header
