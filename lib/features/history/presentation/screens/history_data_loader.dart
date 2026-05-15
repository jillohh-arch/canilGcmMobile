part of 'history_screen.dart';

/// Carrega dados do Firebase e constrói as entries filtradas
extension _HistoryDataLoader on _HistoryScreenState {
  void _loadAllData() {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) return;

    final dogId = shiftVM.activeDogId!;
    final iVM = Provider.of<IncidentViewModel>(context, listen: false);
    final tVM = Provider.of<TrainingViewModel>(context, listen: false);
    final rVM = Provider.of<RoutineViewModel>(context, listen: false);
    final hVM = Provider.of<HealthViewModel>(context, listen: false);

    // Carrega todos os dados em paralelo
    iVM.fetchIncidentsForDog(dogId);
    tVM.fetchTrainingsForDog(dogId);
    rVM.fetchRoutinesForDog(dogId);
    hVM.fetchHealthLogsForDog(dogId);
  }

  /// Constrói todas as entries filtradas por período e tipo
  List<HistoryEntry> _buildFilteredEntries(String dogId) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final rVM = Provider.of<RoutineViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);

    final dogName = _resolveDogName(dogId, dogVM);
    final range = _periodDateRange();

    List<HistoryEntry> entries = [];

    // Rotinas
    if (_typeFilter == 'Tudo' || _typeFilter == 'Rotina') {
      for (final r in rVM.routines) {
        if (r.dogId == dogId && _isInRange(r.timestamp, range)) {
          entries.add(_buildRoutineEntry(r, dogName));
        }
      }
    }

    // Saúde
    if (_typeFilter == 'Tudo' || _typeFilter == 'Saude') {
      for (final h in hVM.healthLogs) {
        if (h.dogId == dogId && _isInRange(h.date, range)) {
          entries.add(_buildHealthEntry(h, dogName));
        }
      }
    }

    // Treinos
    if (_typeFilter == 'Tudo' || _typeFilter == 'Treino') {
      for (final t in tVM.trainings) {
        if (t.dogId == dogId && _isInRange(t.date, range)) {
          entries.add(_buildTrainingEntry(t));
        }
      }
    }

    // Ocorrências
    if (_typeFilter == 'Tudo' || _typeFilter == 'Ocorrência') {
      for (final i in iVM.incidents) {
        if (i.dogId == dogId) {
          // Ocorrências em andamento sempre aparecem, independente do filtro de data
          if (i.isInProgress || _isInRange(i.date, range)) {
            entries.add(_buildIncidentEntry(i));
          }
        }
      }
    }

    // Nutrição
    if (_typeFilter == 'Tudo' || _typeFilter == 'Nutricao') {
      final nVM = Provider.of<NutritionViewModel>(context);
      for (final f in nVM.todayFeedings) {
        if (_isInRange(f.fedAt, range)) {
          entries.add(HistoryEntry(
            id: f.id ?? f.fedAt.millisecondsSinceEpoch.toString(),
            category: 'Nutricao',
            originalModel: f,
            time: f.fedAt,
            title: 'Alimentação · ${f.amountGrams}g',
            subtitle: '${f.period} · ${f.fedBy}',
            location: '',
            authorId: f.fedBy,
            authorName: _resolveAuthorName(f.fedBy),
            details: {
              'Período': f.period,
              'Quantidade': '${f.amountGrams}g',
              'Prescrição': '${f.prescriptionAtTime}g',
              'Divergência': '${f.divergencePercent.toStringAsFixed(1)}%',
              if (f.observations != null) 'Observações': f.observations,
            },
          ));
        }
      }
    }

    // Ordena por hora (mais recente primeiro)
    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }

  bool _isInRange(DateTime date, ({DateTime start, DateTime end}) range) {
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }

  String _resolveDogName(String dogId, DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return 'K9';
  }

  HistoryEntry _buildRoutineEntry(RoutineModel routine, String dogName) {
    final subtitle = routine.notes?.isNotEmpty == true
        ? routine.notes!
        : routine.status;

    return HistoryEntry(
      id: routine.id,
      category: 'Rotina',
      originalModel: routine,
      time: routine.timestamp,
      title: '${routine.activityType}${routine.metadata?['quantidade'] != null ? ' · ${routine.metadata!['quantidade']}' : ''}',
      subtitle: subtitle,
      location: '',
      authorId: routine.handlerId,
      authorName: _resolveAuthorName(routine.handlerId),
      details: {
        'Status': routine.status,
        'Notas': routine.notes ?? '',
        if (routine.metadata != null) ...routine.metadata!,
        if (routine.mediaAttachments != null)
          '_mediaAttachments': routine.mediaAttachments,
      },
    );
  }

  HistoryEntry _buildHealthEntry(HealthLogModel healthLog, String dogName) {
    final title = _resolveHealthTitle(healthLog);
    final subtitle = healthLog.healthObservations.isNotEmpty
        ? healthLog.healthObservations
        : (healthLog.vaccines.isNotEmpty
            ? healthLog.vaccines.join(', ')
            : '');

    return HistoryEntry(
      id: healthLog.id,
      category: 'Saude',
      originalModel: healthLog,
      time: healthLog.date,
      title: title,
      subtitle: subtitle,
      location: '',
      authorId: '', // HealthLogModel não tem handlerId
      authorName: '',
      details: {
        if (healthLog.weight != null) 'Peso': '${healthLog.weight} kg',
        if (healthLog.vaccines.isNotEmpty)
          'Vacinas': healthLog.vaccines.join(', '),
        'Observações': healthLog.healthObservations,
        if (healthLog.vetName != null && healthLog.vetName!.isNotEmpty)
          'Veterinário': healthLog.vetName,
        if (healthLog.mediaAttachments != null)
          '_mediaAttachments': healthLog.mediaAttachments,
      },
    );
  }

  HistoryEntry _buildTrainingEntry(TrainingSessionModel training) {
    final duration = training.searchDuration != null
        ? '${(training.searchDuration! / 60).round()} min'
        : '';
    final subtitle = [
      if (duration.isNotEmpty) duration,
      if (training.location.isNotEmpty) training.location,
    ].join(' · ');

    return HistoryEntry(
      id: training.id,
      category: 'Treino',
      originalModel: training,
      time: training.date,
      title: 'Treino · ${training.trainingType}',
      subtitle: subtitle,
      location: training.location,
      authorId: training.handlerId,
      authorName: _resolveAuthorName(training.handlerId),
      details: {
        'Tipo': training.trainingType,
        if (duration.isNotEmpty) 'Duração': duration,
        'Local': training.location,
        'Clima': training.weather,
        'Notas': training.handlerNotes,
        if (training.substanceUsed != null)
          'Substância': training.substanceUsed,
        if (training.metadata != null) ...training.metadata!,
        if (training.mediaAttachments != null)
          '_mediaAttachments': training.mediaAttachments,
      },
    );
  }

  HistoryEntry _buildIncidentEntry(Incident incident) {
    final type = (incident.type ?? 'Ocorrência').trim();
    final isActive = incident.isInProgress;

    return HistoryEntry(
      id: incident.id,
      category: 'Ocorrência',
      originalModel: incident,
      time: incident.date,
      title: 'Ocorrência · $type',
      subtitle: incident.location,
      location: incident.location,
      authorId: incident.handlerId,
      authorName: _resolveAuthorName(incident.handlerId),
      isInProgress: isActive,
      editedAt: !incident.updatedAt.isAtSameMomentAs(incident.date) ? incident.updatedAt : null,
      details: {
        'Resultado': incident.displayResult,
        'Status': incident.status,
        'Descrição': incident.description,
        'Local': incident.location,
        if (incident.startedAt != incident.date)
          'Início': DateFormat('HH:mm').format(incident.startedAt),
        if (incident.endedAt != null)
          'Fim': DateFormat('HH:mm').format(incident.endedAt!),
        if (incident.outcomes.isNotEmpty)
          '_outcomes': incident.outcomes,
        if (incident.progressUpdates.isNotEmpty)
          '_progressUpdates': incident.progressUpdates,
        if (incident.extraFields != null) ...incident.extraFields!,
        if (incident.mediaAttachments != null)
          '_mediaAttachments': incident.mediaAttachments,
      },
    );
  }

  String _resolveHealthTitle(HealthLogModel healthLog) {
    final logType = healthLog.logType.trim();
    if (logType.isNotEmpty && logType.toLowerCase() != 'rotina') {
      return logType;
    }
    if (healthLog.vaccines.isNotEmpty) {
      return healthLog.vaccines.first;
    }
    final obs = healthLog.healthObservations.trim();
    if (obs.isNotEmpty) {
      final first = obs.split(RegExp(r'[.!?\n]')).first.trim();
      if (first.isNotEmpty) return first;
    }
    return 'Registro de saúde';
  }

  String _resolveAuthorName(String handlerId) {
    if (handlerId.isEmpty) return '';
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    // Tenta encontrar o nome do usuário pelo handlerId (que é o RA)
    for (final user in userVM.users) {
      if (user.ra == handlerId) {
        return user.callsign.isNotEmpty ? user.callsign : user.name;
      }
    }
    // Fallback: usa o próprio handlerId como nome
    return 'GCM $handlerId';
  }
}
