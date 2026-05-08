part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryData on _DailyTimelineScreenState {
  _TimelineListData _buildTimelineEntries(String dogId, {String? filterType}) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final rVM = Provider.of<RoutineViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    // Filter by selected date (Inclusive start, exclusive end)
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final trainings = tVM.trainings
        .where(
          (t) =>
              t.dogId == dogId &&
              !t.date.isBefore(startOfDay) &&
              t.date.isBefore(endOfDay),
        )
        .toList();

    final incidents = iVM.incidents
        .where(
          (i) =>
              i.dogId == dogId &&
              !i.isInProgress &&
              !i.date.isBefore(startOfDay) &&
              i.date.isBefore(endOfDay),
        )
        .toList();

    final healthLogs = hVM.healthLogs
        .where(
          (h) =>
              h.dogId == dogId &&
              !h.date.isBefore(startOfDay) &&
              h.date.isBefore(endOfDay),
        )
        .toList();

    final routines = rVM.routines
        .where(
          (r) =>
              r.dogId == dogId &&
              !r.timestamp.isBefore(startOfDay) &&
              r.timestamp.isBefore(endOfDay),
        )
        .toList();

    List<_TimelineEntry> entries = [];

    // Include trainings/health only if not in Ocorrência-only tab
    if (filterType != 'Ocorrência') {
      for (var r in routines) {
        entries.add(
          _TimelineEntry(
            id: r.id,
            category: 'Rotina',
            originalModel: r,
            time: r.timestamp,
            title: 'ROTINA: ${r.activityType}',
            location: r.dogName.isNotEmpty ? r.dogName : dogName,
            type: 'Rotina',
            details: {
              'Status': r.status,
              'Notas': r.notes,
              if (r.mediaAttachments != null && r.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': r.mediaAttachments,
              ...?r.metadata,
            },
          ),
        );
      }

      for (var h in healthLogs) {
        final healthTitle = _resolveHealthTimelineTitle(h);
        entries.add(
          _TimelineEntry(
            id: h.id,
            category: 'Saude',
            originalModel: h,
            time: h.date,
            title: 'SAÚDE: $healthTitle',
            location: h.dogName.isNotEmpty ? h.dogName : dogName,
            type: 'Saude',
            details: {
              if (h.weight != null) 'Peso': '${h.weight} kg',
              if (h.vaccines.isNotEmpty) 'Vacinas': h.vaccines.join(', '),
              'Observações': h.healthObservations,
              if (h.vetName != null && h.vetName!.isNotEmpty)
                'Veterinário': h.vetName,
              if (h.mediaAttachments != null && h.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': h.mediaAttachments,
            },
          ),
        );
      }

      for (var t in trainings) {
        // Apply category filter if set
        if (_selectedTrainingFilter != null) {
          final matchesFilter =
              t.trainingType.toLowerCase().contains(
                _selectedTrainingFilter!.toLowerCase(),
              ) ||
              (_selectedTrainingFilter == 'Busca & Captura' &&
                  (t.trainingType.contains('Busca') ||
                      t.trainingType.contains('Captura')));
          if (!matchesFilter) continue;
        }
        final isRoutine = [
          'Passeio',
          'Lazer/Brincadeira',
          'Condicionamento Físico',
          'Outros',
          'Brincadeira',
          'Alimentação',
          'Limpeza',
          'Descanso',
          'Escovação',
        ].contains(t.trainingType);
        entries.add(
          _TimelineEntry(
            id: t.id,
            category: isRoutine ? 'Rotina' : 'Treino',
            originalModel: t,
            time: t.date,
            title: isRoutine
                ? 'ROTINA: ${t.trainingType}'
                : 'TREINO: ${t.trainingType}',
            location: t.location,
            type: isRoutine ? 'Rotina' : 'Treino',
            details: {
              'Clima': t.weather,
              'Duração': t.searchDuration != null
                  ? '${(t.searchDuration! / 60).round()} min'
                  : null,
              'Notas': t.handlerNotes,
              if (t.mediaAttachments != null && t.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': t.mediaAttachments,
              ...?t.metadata,
            },
          ),
        );
      }
    }

    // Include incidents only if not in Training-only tab
    if (filterType != 'Training') {
      for (var i in incidents) {
        final incidentTitle = _resolveIncidentTimelineTitle(i);
        entries.add(
          _TimelineEntry(
            id: i.id,
            category: 'Ocorrência',
            originalModel: i,
            time: i.date,
            title: 'OCORRÊNCIA: $incidentTitle',
            location: i.location,
            type: 'Ocorrência',
            details: {
              'Resultado': i.displayResult,
              'Status': i.status,
              'Descrição': i.description,
              if (i.outcomes.isNotEmpty) '_outcomes': i.outcomes,
              if (i.progressUpdates.isNotEmpty)
                '_progressUpdates': i.progressUpdates
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
              if (i.mediaAttachments != null && i.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': i.mediaAttachments,
            },
          ),
        );
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));

    final hasOpenIncidents =
        filterType == 'Ocorrência' &&
        iVM.incidents.any(
          (incident) => incident.dogId == dogId && incident.isInProgress,
        );

    return _TimelineListData(
      entries: entries,
      dogName: dogName,
      hasOpenIncidents: hasOpenIncidents,
    );
  }
}
