part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryTrainingBuilder on _DailyTimelineScreenState {
  bool _matchesSelectedTrainingFilter(TrainingSessionModel training) {
    final selectedFilter = _selectedTrainingFilter;
    if (selectedFilter == null) return true;

    return training.trainingType.toLowerCase().contains(
          selectedFilter.toLowerCase(),
        ) ||
        (selectedFilter == 'Busca & Captura' &&
            (training.trainingType.contains('Busca') ||
                training.trainingType.contains('Captura')));
  }

  _TimelineEntry _buildTrainingTimelineEntry(TrainingSessionModel training) {
    final isRoutine = _routineTrainingTypes.contains(training.trainingType);

    return _TimelineEntry(
      id: training.id,
      category: isRoutine ? 'Rotina' : 'Treino',
      originalModel: training,
      time: training.date,
      title: isRoutine
          ? 'ROTINA: ${training.trainingType}'
          : 'TREINO: ${training.trainingType}',
      location: training.location,
      type: isRoutine ? 'Rotina' : 'Treino',
      details: {
        'Clima': training.weather,
        'Duração': training.searchDuration != null
            ? '${(training.searchDuration! / 60).round()} min'
            : null,
        'Notas': training.handlerNotes,
        if (training.mediaAttachments != null &&
            training.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': training.mediaAttachments,
        ...?training.metadata,
      },
    );
  }
}

const _routineTrainingTypes = {
  'Passeio',
  'Lazer/Brincadeira',
  'Condicionamento Físico',
  'Outros',
  'Brincadeira',
  'Alimentação',
  'Limpeza',
  'Descanso',
  'Escovação',
};
