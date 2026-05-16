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
            style: GoogleFonts.inter(
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

// ─── STREAK CARD ─────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _StreakCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final streak = _calculateStreak(sessions);
    final maxStreak = _calculateMaxStreak(sessions);
    final thisWeek = _countThisWeek(sessions);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF6B35).withAlpha(60)),
      ),
      child: Row(
        children: [
          // Streak fire icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                streak > 0 ? '🔥' : '❄️',
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$streak',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: streak > 0 ? const Color(0xFFFF6B35) : AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      streak == 1 ? 'dia seguido' : 'dias seguidos',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Recorde: $maxStreak dias · Esta semana: $thisWeek sessões',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _calculateStreak(List<TrainingSessionModel> sessions) {
    if (sessions.isEmpty) return 0;
    final sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    int streak = 0;
    DateTime checkDate = todayDate;

    for (int i = 0; i < 365; i++) {
      final hasSession = sorted.any((s) {
        final sDate = DateTime(s.date.year, s.date.month, s.date.day);
        return sDate == checkDate;
      });
      if (hasSession) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (i == 0) {
        // Hoje ainda não treinou, verifica ontem
        checkDate = checkDate.subtract(const Duration(days: 1));
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  int _calculateMaxStreak(List<TrainingSessionModel> sessions) {
    if (sessions.isEmpty) return 0;
    final sorted = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    final dates = sorted
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet()
        .toList()
      ..sort();

    int maxStreak = 1;
    int current = 1;
    for (int i = 1; i < dates.length; i++) {
      if (dates[i].difference(dates[i - 1]).inDays == 1) {
        current++;
        if (current > maxStreak) maxStreak = current;
      } else {
        current = 1;
      }
    }
    return maxStreak;
  }

  int _countThisWeek(List<TrainingSessionModel> sessions) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return sessions.where((s) => s.date.isAfter(start)).length;
  }
}

// ─── WEEKLY BAR CHART ────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _WeeklyBarChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final weekData = _getLast8Weeks(sessions);
    final maxVal = weekData.map((w) => w.count).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: (maxVal + 1).toDouble(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${rod.toY.round()} sessões',
                  GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
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
                reservedSize: 28,
                getTitlesWidget: (val, meta) => Text(
                  '${val.round()}',
                  style: GoogleFonts.inter(fontSize: 9, color: Colors.white38),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= weekData.length) return const SizedBox();
                  return Text(
                    weekData[idx].label,
                    style: GoogleFonts.inter(fontSize: 9, color: Colors.white38),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: weekData.asMap().entries.map((entry) {
            final isCurrentWeek = entry.key == weekData.length - 1;
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.count.toDouble(),
                  color: isCurrentWeek ? _hudCyan : _hudCyan.withAlpha(120),
                  width: 16,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  List<_WeekData> _getLast8Weeks(List<TrainingSessionModel> sessions) {
    final now = DateTime.now();
    final weeks = <_WeekData>[];

    for (int i = 7; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (i * 7)));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = start.add(const Duration(days: 7));
      final count = sessions.where((s) => s.date.isAfter(start) && s.date.isBefore(end)).length;
      final label = '${start.day}/${start.month}';
      weeks.add(_WeekData(label: label, count: count));
    }
    return weeks;
  }
}

class _WeekData {
  final String label;
  final int count;
  const _WeekData({required this.label, required this.count});
}

// ─── SPECIALTY DONUT CHART ───────────────────────────────────────────────────

class _SpecialtyDonutChart extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SpecialtyDonutChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final distribution = _getDistribution(sessions);
    final total = sessions.length;

    return Row(
      children: [
        // Donut chart
        SizedBox(
          width: 120,
          height: 120,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: distribution.map((d) {
                return PieChartSectionData(
                  value: d.count.toDouble(),
                  color: d.color,
                  radius: 24,
                  showTitle: false,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Legend
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: distribution.map((d) {
              final pct = total > 0 ? (d.count / total * 100).round() : 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: d.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.name,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: d.color,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<_DistributionData> _getDistribution(List<TrainingSessionModel> sessions) {
    final map = <String, int>{};
    for (final s in sessions) {
      final type = _normalizeType(s.trainingType);
      map[type] = (map[type] ?? 0) + 1;
    }

    final colors = {
      'Detecção': const Color(0xFF4dd0e1),
      'Obediência': const Color(0xFF66BB6A),
      'Condicionamento': const Color(0xFFFBBF24),
      'Guarda & Proteção': const Color(0xFFEF5350),
      'Faro': const Color(0xFF29B6F6),
      'Outro': const Color(0xFF7E57C2),
    };

    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => _DistributionData(
      name: e.key,
      count: e.value,
      color: colors[e.key] ?? const Color(0xFF7E57C2),
    )).toList();
  }

  String _normalizeType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('detec') || lower.contains('droga')) return 'Detecção';
    if (lower.contains('obed')) return 'Obediência';
    if (lower.contains('condic') || lower.contains('físic')) return 'Condicionamento';
    if (lower.contains('guarda') || lower.contains('proteção') || lower.contains('protecao')) return 'Guarda & Proteção';
    if (lower.contains('faro') || lower.contains('rastro') || lower.contains('busca')) return 'Faro';
    return 'Outro';
  }
}

class _DistributionData {
  final String name;
  final int count;
  final Color color;
  const _DistributionData({required this.name, required this.count, required this.color});
}

// ─── SPECIALTY PROGRESS BARS ─────────────────────────────────────────────────

class _SpecialtyProgressBars extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SpecialtyProgressBars({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last30 = sessions.where((s) => now.difference(s.date).inDays <= 30).toList();
    final specialties = _getSpecialtyActivity(last30);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hudCyan.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ATIVIDADE POR ESPECIALIDADE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _hudCyan,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                'últimos 30 dias',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...specialties.map((s) => _buildProgressRow(s, last30.length)),
        ],
      ),
    );
  }

  Widget _buildProgressRow(_SpecialtyActivity spec, int total) {
    final pct = total > 0 ? spec.count / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                spec.emoji,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  spec.name,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                '${spec.count}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: spec.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: Colors.white.withAlpha(10),
              valueColor: AlwaysStoppedAnimation<Color>(spec.color),
            ),
          ),
        ],
      ),
    );
  }

  List<_SpecialtyActivity> _getSpecialtyActivity(List<TrainingSessionModel> sessions) {
    final map = <String, int>{};
    for (final s in sessions) {
      final type = _normalizeType(s.trainingType);
      map[type] = (map[type] ?? 0) + 1;
    }

    final specs = [
      _SpecialtyActivity(name: 'Detecção', emoji: '👃', color: const Color(0xFF4dd0e1), count: map['Detecção'] ?? 0),
      _SpecialtyActivity(name: 'Obediência', emoji: '🎓', color: const Color(0xFF66BB6A), count: map['Obediência'] ?? 0),
      _SpecialtyActivity(name: 'Condicionamento', emoji: '💪', color: const Color(0xFFFBBF24), count: map['Condicionamento'] ?? 0),
      _SpecialtyActivity(name: 'Guarda & Proteção', emoji: '🛡', color: const Color(0xFFEF5350), count: map['Guarda & Proteção'] ?? 0),
      _SpecialtyActivity(name: 'Faro', emoji: '🔍', color: const Color(0xFF29B6F6), count: map['Faro'] ?? 0),
    ];

    return specs.where((s) => s.count > 0).toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  String _normalizeType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('detec') || lower.contains('droga')) return 'Detecção';
    if (lower.contains('obed')) return 'Obediência';
    if (lower.contains('condic') || lower.contains('físic')) return 'Condicionamento';
    if (lower.contains('guarda') || lower.contains('proteção') || lower.contains('protecao')) return 'Guarda & Proteção';
    if (lower.contains('faro') || lower.contains('rastro') || lower.contains('busca')) return 'Faro';
    return 'Outro';
  }
}

class _SpecialtyActivity {
  final String name;
  final String emoji;
  final Color color;
  final int count;
  const _SpecialtyActivity({required this.name, required this.emoji, required this.color, required this.count});
}

// Section header
