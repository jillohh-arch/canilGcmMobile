part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionMetrics on _DailyTimelineScreenState {
  String _resolveMostFrequentCategory(List<TrainingSessionModel> trainings) {
    if (trainings.isEmpty) return '--';

    final counts = <String, int>{};
    for (final training in trainings) {
      final category = _normalizePerformanceCategory(training.trainingType);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String _formatEvolutionDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;

    if (difference == 0) return 'Hoje';
    if (difference == 1) return 'Ontem';
    return DateFormat('dd/MM').format(date);
  }

  ({IconData icon, Color color}) _resolveEvolutionCategoryVisual(
    String category,
  ) {
    switch (category) {
      case 'Faro':
        return (icon: Icons.sensors_rounded, color: const Color(0xFF38BDF8));
      case 'Busca & Captura':
        return (
          icon: Icons.crisis_alert_rounded,
          color: const Color(0xFFF97316),
        );
      case 'Guarda':
        return (icon: Icons.shield_rounded, color: const Color(0xFF4ADE80));
      case 'Obediência':
        return (icon: Icons.rule_rounded, color: const Color(0xFFA78BFA));
      default:
        return (icon: Icons.pets_rounded, color: const Color(0xFFFBBF24));
    }
  }

  String _formatEvolutionMinutes(double minutes) {
    if (minutes <= 0) return '0 min';
    return '${minutes.toStringAsFixed(0)} min';
  }

  List<({double minutes, String? primaryCategory, Set<String> categories})>
  _buildDailyTrainingSummaries(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final totals = List.generate(7, (_) => <String, double>{}, growable: false);

    for (final training in trainings) {
      final trainingDay = DateTime(
        training.date.year,
        training.date.month,
        training.date.day,
      );
      final index = trainingDay.difference(start).inDays;
      if (index >= 0 && index < 7) {
        final category = _normalizePerformanceCategory(training.trainingType);
        totals[index][category] =
            (totals[index][category] ?? 0) +
            ((training.searchDuration ?? 0) / 60);
      }
    }

    return totals
        .map((dailyTotals) {
          if (dailyTotals.isEmpty) {
            return (
              minutes: 0.0,
              primaryCategory: null,
              categories: <String>{},
            );
          }

          final entries = dailyTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final totalMinutes = dailyTotals.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );

          return (
            minutes: totalMinutes,
            primaryCategory: entries.first.key,
            categories: dailyTotals.keys.toSet(),
          );
        })
        .toList(growable: false);
  }
}
