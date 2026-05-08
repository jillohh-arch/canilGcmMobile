part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionStaleCategoryAlerts
    on _DailyTimelineScreenState {
  List<Widget> _buildStaleCategoryAlerts(String dogId) {
    final alerts = <Widget>[];

    for (final category in _trainingCategories) {
      if (_selectedTrainingFilter != null &&
          category != _selectedTrainingFilter) {
        continue;
      }

      final categoryTrainings =
          _getPerformanceTrainings(dogId, applyFilter: false)
              .where(
                (training) =>
                    _normalizePerformanceCategory(training.trainingType) ==
                    category,
              )
              .toList();

      if (categoryTrainings.isEmpty) continue;

      final latest = categoryTrainings.first.date;
      final daysWithout = DateTime.now()
          .difference(DateTime(latest.year, latest.month, latest.day))
          .inDays;

      if (daysWithout >= 7) {
        alerts.add(
          _buildEvolutionMessageCard(
            icon: Icons.schedule_rounded,
            title: '$category sem registro recente',
            description:
                'A última sessão dessa competência foi há $daysWithout dias.',
          ),
        );
      }
    }

    return alerts;
  }
}
