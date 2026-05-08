part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionSummary on _DailyTimelineScreenState {
  Widget _buildEvolutionSummarySection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousTrainings = _getPerformanceTrainings(dogId, lastDays: 14)
        .where((training) {
          final cutoff = DateTime.now().subtract(const Duration(days: 7));
          return training.date.isBefore(cutoff);
        })
        .toList();

    final totalSessions = trainings.length;
    final totalMinutes = _sumEvolutionMinutes(trainings);
    final previousTotalSessions = previousTrainings.length;
    final previousTotalMinutes = _sumEvolutionMinutes(previousTrainings);
    final averageMinutes = totalSessions == 0
        ? 0.0
        : totalMinutes / totalSessions;
    final mostFrequentCategory = _resolveMostFrequentCategory(trainings);
    final lastTraining = trainings.isNotEmpty ? trainings.first : null;
    final focusVisual = _resolveEvolutionCategoryVisual(mostFrequentCategory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          _buildEvolutionScopeCard(),
          const SizedBox(height: 10),
          _buildEvolutionPrimaryStats(
            totalSessions: totalSessions,
            totalMinutes: totalMinutes,
          ),
          const SizedBox(height: 10),
          _buildEvolutionSecondaryStats(
            averageMinutes: averageMinutes,
            mostFrequentCategory: mostFrequentCategory,
            focusVisual: focusVisual,
          ),
          const SizedBox(height: 10),
          _buildEvolutionWeekComparisonCard(
            currentMinutes: totalMinutes,
            previousMinutes: previousTotalMinutes,
            currentSessions: totalSessions,
            previousSessions: previousTotalSessions,
            scopeLabel: _selectedTrainingFilter,
          ),
          if (lastTraining != null) ...[
            const SizedBox(height: 10),
            _buildEvolutionLastTrainingCard(
              lastTraining: lastTraining,
              focusVisual: focusVisual,
            ),
          ],
        ],
      ),
    );
  }

  double _sumEvolutionMinutes(List<TrainingSessionModel> trainings) {
    return trainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
  }

  Widget _buildEvolutionScopeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECORTE ATUAL',
            style: GoogleFonts.robotoMono(
              color: _hudCyan.withAlpha(210),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _buildEvolutionScopeHeadline(),
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _buildEvolutionScopeDescription(),
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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
