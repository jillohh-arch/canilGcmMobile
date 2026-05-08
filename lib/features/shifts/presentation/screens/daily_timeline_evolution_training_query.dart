part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionTrainingQuery on _DailyTimelineScreenState {
  bool _isPerformanceType(String trainingType) {
    for (final allowed in _performanceTrainingAllowlist) {
      if (trainingType.toLowerCase().contains(allowed.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool _matchesTrainingFilter(String trainingType) {
    final filter = _selectedTrainingFilter;
    if (filter == null) return true;

    return trainingType.toLowerCase().contains(filter.toLowerCase()) ||
        (filter == 'Busca & Captura' &&
            (trainingType.contains('Busca') ||
                trainingType.contains('Captura')));
  }

  String _normalizePerformanceCategory(String trainingType) {
    final normalized = trainingType.toLowerCase();
    if (normalized.contains('faro')) return 'Faro';
    if (normalized.contains('busca') || normalized.contains('captura')) {
      return 'Busca & Captura';
    }
    if (normalized.contains('guarda') || normalized.contains('prote')) {
      return 'Guarda';
    }
    if (normalized.contains('obedi')) return 'Obediência';
    return trainingType;
  }

  List<TrainingSessionModel> _getPerformanceTrainings(
    String dogId, {
    int? lastDays,
    bool applyFilter = true,
  }) {
    final tVM = Provider.of<TrainingViewModel>(context, listen: false);
    final startDate = _resolvePerformanceStartDate(lastDays);

    final trainings = tVM.trainings.where((training) {
      if (training.dogId != dogId) return false;
      if (!_isPerformanceType(training.trainingType)) return false;
      if (applyFilter && !_matchesTrainingFilter(training.trainingType)) {
        return false;
      }
      if (startDate != null && training.date.isBefore(startDate)) return false;
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    return trainings;
  }

  DateTime? _resolvePerformanceStartDate(int? lastDays) {
    if (lastDays == null) return null;

    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: lastDays - 1));
  }
}

const _performanceTrainingAllowlist = [
  'Faro',
  'Busca & Captura',
  'Busca de Pessoa',
  'Guarda e Proteção',
  'Guarda',
  'Obediência',
];
