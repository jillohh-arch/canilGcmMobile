part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionRecentSessions on _DailyTimelineScreenState {
  Widget _buildRecentPerformanceSessions(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 14);

    if (trainings.isEmpty) {
      return _buildRecentPerformanceSessionsEmptyState();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: trainings.length.clamp(0, 8),
      itemBuilder: (context, index) {
        final training = trainings[index];
        return _buildRecentPerformanceSessionTile(training);
      },
    );
  }
}
