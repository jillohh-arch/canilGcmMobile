part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryBuilders on _DailyTimelineScreenState {
  String _resolveTimelineDogName(String dogId, DogViewModel dogVM) {
    return dogVM.dogs
        .firstWhere(
          (dog) => dog.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;
  }

  ({DateTime start, DateTime end}) _selectedTimelineDayRange() {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    return (start: start, end: start.add(const Duration(days: 1)));
  }

  bool _isWithinSelectedTimelineDay(
    DateTime date,
    ({DateTime start, DateTime end}) range,
  ) {
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }

  _TimelineEntry _buildRoutineTimelineEntry(
    RoutineModel routine,
    String dogName,
  ) {
    return _TimelineEntry(
      id: routine.id,
      category: 'Rotina',
      originalModel: routine,
      time: routine.timestamp,
      title: 'ROTINA: ${routine.activityType}',
      location: routine.dogName.isNotEmpty ? routine.dogName : dogName,
      type: 'Rotina',
      details: {
        'Status': routine.status,
        'Notas': routine.notes,
        if (routine.mediaAttachments != null &&
            routine.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': routine.mediaAttachments,
        ...?routine.metadata,
      },
    );
  }

  _TimelineEntry _buildHealthTimelineEntry(
    HealthLogModel healthLog,
    String dogName,
  ) {
    final healthTitle = _resolveHealthTimelineTitle(healthLog);

    return _TimelineEntry(
      id: healthLog.id,
      category: 'Saude',
      originalModel: healthLog,
      time: healthLog.date,
      title: 'SAÚDE: $healthTitle',
      location: healthLog.dogName.isNotEmpty ? healthLog.dogName : dogName,
      type: 'Saude',
      details: {
        if (healthLog.weight != null) 'Peso': '${healthLog.weight} kg',
        if (healthLog.vaccines.isNotEmpty)
          'Vacinas': healthLog.vaccines.join(', '),
        'Observações': healthLog.healthObservations,
        if (healthLog.vetName != null && healthLog.vetName!.isNotEmpty)
          'Veterinário': healthLog.vetName,
        if (healthLog.mediaAttachments != null &&
            healthLog.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': healthLog.mediaAttachments,
      },
    );
  }

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

  _TimelineEntry _buildIncidentTimelineEntry(Incident incident) {
    final incidentTitle = _resolveIncidentTimelineTitle(incident);

    return _TimelineEntry(
      id: incident.id,
      category: 'Ocorrência',
      originalModel: incident,
      time: incident.date,
      title: 'OCORRÊNCIA: $incidentTitle',
      location: incident.location,
      type: 'Ocorrência',
      details: {
        'Resultado': incident.displayResult,
        'Status': incident.status,
        'Descrição': incident.description,
        if (incident.outcomes.isNotEmpty) '_outcomes': incident.outcomes,
        if (incident.progressUpdates.isNotEmpty)
          '_progressUpdates': incident.progressUpdates
              .map(
                (update) => {
                  'title': update.title,
                  'description': update.description,
                  'location': update.location,
                  'timestamp': update.timestamp,
                  'authorId': update.authorId,
                  'authorName': update.authorName,
                },
              )
              .toList(),
        if (incident.mediaAttachments != null &&
            incident.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': incident.mediaAttachments,
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
