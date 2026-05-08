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
}
