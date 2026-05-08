part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencyData on _DailyTimelineScreenState {
  List<MapEntry<String, List<TrainingSessionModel>>>
  _buildCompetencyTrainingGroups(List<TrainingSessionModel> trainings) {
    final grouped = <String, List<TrainingSessionModel>>{};

    for (final training in trainings) {
      final category = _normalizePerformanceCategory(training.trainingType);
      grouped.putIfAbsent(category, () => []).add(training);
    }

    return grouped.entries.toList()..sort((a, b) {
      final aMinutes = _sumEvolutionMinutes(a.value);
      final bMinutes = _sumEvolutionMinutes(b.value);
      return bMinutes.compareTo(aMinutes);
    });
  }
}
