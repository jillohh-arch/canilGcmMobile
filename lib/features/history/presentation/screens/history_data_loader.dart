part of 'history_screen.dart';

extension _HistoryDataLoader on _HistoryScreenState {
  void _loadAllData() {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) return;

    final dogId = shiftVM.activeDogId!;
    Provider.of<IncidentViewModel>(
      context,
      listen: false,
    ).fetchIncidentsForDog(dogId);
    Provider.of<TrainingViewModel>(
      context,
      listen: false,
    ).fetchTrainingsForDog(dogId);
    Provider.of<HealthViewModel>(
      context,
      listen: false,
    ).fetchHealthLogsForDog(dogId);
    Provider.of<NutritionViewModel>(context, listen: false).loadForDog(dogId);
  }

  List<HistoryEntry> _buildAllEntries(String dogId) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);

    final dogName = _resolveDogName(dogId, dogVM);
    final entries = <HistoryEntry>[];

    for (final log in healthVM.healthLogs) {
      if (log.dogId == dogId) entries.add(_buildHealthEntry(log, dogName));
    }

    for (final incident in incidentVM.incidents) {
      if (incident.dogId == dogId) entries.add(_buildIncidentEntry(incident));
    }

    for (final training in trainingVM.trainings) {
      if (training.dogId == dogId) entries.add(_buildTrainingEntry(training));
    }

    for (final feeding in nutritionVM.todayFeedings) {
      entries.add(
        HistoryEntry(
          id: feeding.id ?? 'nutrition_${feeding.fedAt.millisecondsSinceEpoch}',
          type: HistoryEntryType.nutrition,
          title: 'Alimentação registrada',
          subtitle: 'Ração: ${feeding.amountGrams}g',
          time: feeding.fedAt,
          author: _resolveAuthorName(feeding.fedBy),
          authorId: feeding.fedBy,
          tag: 'NUTRIÇÃO',
          icon: Icons.rice_bowl_rounded,
          color: _historyYellow,
          details: {
            'Período': _periodLabel(feeding.period),
            'Quantidade': '${feeding.amountGrams}g',
            'Prescrição': '${feeding.prescriptionAtTime}g',
            'Divergência': '${feeding.divergencePercent.toStringAsFixed(1)}%',
            if (feeding.observations?.trim().isNotEmpty == true)
              'Observações': feeding.observations,
          },
        ),
      );
    }

    if (entries.isEmpty) return _mockEntries();

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }

  HistoryEntry _buildHealthEntry(HealthLogModel log, String dogName) {
    final isWeight = log.weight != null;
    final title = isWeight
        ? 'Pesagem operacional registrada'
        : _healthTitle(log);
    final subtitle = isWeight
        ? 'Peso atual: ${log.weight!.toStringAsFixed(1)} kg'
        : _healthSubtitle(log);
    final author = log.vetName?.trim().isNotEmpty == true
        ? log.vetName!.trim()
        : 'Ragonha';

    return HistoryEntry(
      id: log.id ?? 'health_${log.date.millisecondsSinceEpoch}',
      type: HistoryEntryType.health,
      title: title,
      subtitle: subtitle,
      time: log.date,
      author: author,
      tag: 'SAÚDE',
      icon: isWeight ? Icons.monitor_weight_outlined : Icons.vaccines_outlined,
      color: _historyGreen,
      originalModel: log,
      details: {
        'Cão': dogName,
        'Tipo': log.logType,
        if (log.weight != null) 'Peso': '${log.weight!.toStringAsFixed(1)} kg',
        if (log.vaccines.isNotEmpty) 'Vacinas': log.vaccines.join(', '),
        if (log.healthObservations.trim().isNotEmpty)
          'Observações': log.healthObservations,
        if (log.vetName?.trim().isNotEmpty == true) 'Responsável': log.vetName,
        if (log.mediaAttachments?.isNotEmpty == true)
          '_mediaAttachments': log.mediaAttachments,
      },
    );
  }

  HistoryEntry _buildIncidentEntry(Incident incident) {
    final type = (incident.type ?? 'Registro').trim();
    final isYou = _isCurrentUser(incident.handlerId);

    return HistoryEntry(
      id: incident.id,
      type: HistoryEntryType.incident,
      title: 'Ocorrência • $type',
      subtitle: incident.location.trim().isEmpty
          ? 'Local não informado'
          : incident.location.trim(),
      time: incident.date,
      author: isYou ? 'Você' : _resolveAuthorName(incident.handlerId),
      authorId: incident.handlerId,
      tag: isYou ? 'VOCÊ' : 'OCORRÊNCIA',
      icon: Icons.assignment_outlined,
      color: isYou ? _historyYellow : AppTheme.error,
      location: incident.location,
      isInProgress: incident.isInProgress,
      editedAt: !incident.updatedAt.isAtSameMomentAs(incident.date)
          ? incident.updatedAt
          : null,
      originalModel: incident,
      details: {
        'Resultado': incident.displayResult,
        'Status': incident.status,
        'Descrição': incident.description,
        'Local': incident.location,
        'Condutor': _resolveAuthorName(incident.handlerId),
        if (incident.startedAt != incident.date)
          'Início': DateFormat('HH:mm').format(incident.startedAt),
        if (incident.endedAt != null)
          'Fim': DateFormat('HH:mm').format(incident.endedAt!),
        if (incident.outcomes.isNotEmpty) '_outcomes': incident.outcomes,
        if (incident.progressUpdates.isNotEmpty)
          '_progressUpdates': incident.progressUpdates,
        if (incident.extraFields != null) ...incident.extraFields!,
        if (incident.mediaAttachments?.isNotEmpty == true)
          '_mediaAttachments': incident.mediaAttachments,
      },
    );
  }

  HistoryEntry _buildTrainingEntry(TrainingSessionModel training) {
    final subtitle = training.location.trim().isEmpty
        ? 'Sessão registrada'
        : training.location.trim();
    final duration = training.searchDuration != null
        ? '${(training.searchDuration! / 60).round()} min'
        : '';

    return HistoryEntry(
      id: training.id ?? 'training_${training.date.millisecondsSinceEpoch}',
      type: HistoryEntryType.training,
      title: 'Treino • ${training.trainingType}',
      subtitle: subtitle,
      time: training.date,
      author: _resolveAuthorName(training.handlerId),
      authorId: training.handlerId,
      tag: 'TREINO',
      icon: Icons.fitness_center_rounded,
      color: _historyGreen,
      location: training.location,
      originalModel: training,
      details: {
        'Tipo': training.trainingType,
        if (duration.isNotEmpty) 'Duração': duration,
        if (training.location.trim().isNotEmpty) 'Local': training.location,
        if (training.weather.trim().isNotEmpty) 'Clima': training.weather,
        if (training.handlerNotes.trim().isNotEmpty)
          'Notas': training.handlerNotes,
        if (training.substanceUsed?.trim().isNotEmpty == true)
          'Substância': training.substanceUsed,
        if (training.metadata != null) ...training.metadata!,
        if (training.mediaAttachments?.isNotEmpty == true)
          '_mediaAttachments': training.mediaAttachments,
      },
    );
  }

  String _resolveDogName(String dogId, DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return 'K9';
  }

  String _resolveAuthorName(String handlerId) {
    if (handlerId.trim().isEmpty) return 'Ragonha';
    if (_isCurrentUser(handlerId)) return 'Você';

    final userVM = Provider.of<UserViewModel>(context, listen: false);
    for (final user in userVM.users) {
      if (user.ra == handlerId) {
        return user.callsign.isNotEmpty ? user.callsign : user.name;
      }
    }
    return 'GCM $handlerId';
  }

  bool _isCurrentUser(String handlerId) {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final emailRa = authVM.user?.email?.split('@').first;
    return handlerId == authVM.user?.uid || handlerId == emailRa;
  }

  String _healthTitle(HealthLogModel log) {
    final logType = log.logType.trim();
    if (logType.toLowerCase().contains('vacin')) return 'Vacinação aplicada';
    if (logType.isNotEmpty && logType.toLowerCase() != 'rotina') {
      return '$logType registrado';
    }
    if (log.vaccines.isNotEmpty) return 'Vacinação aplicada';
    return 'Registro de saúde';
  }

  String _healthSubtitle(HealthLogModel log) {
    if (log.vaccines.isNotEmpty) return log.vaccines.join(' • ');
    if (log.healthObservations.trim().isNotEmpty) return log.healthObservations;
    return 'Registro clínico operacional';
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'manha':
        return 'Manhã';
      case 'almoco':
        return 'Almoço';
      case 'noite':
        return 'Noite';
      default:
        return period;
    }
  }

  List<HistoryEntry> _mockEntries() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final previous = today.subtract(const Duration(days: 3));

    return [
      HistoryEntry(
        id: 'mock_weight',
        type: HistoryEntryType.health,
        title: 'Pesagem operacional registrada',
        subtitle: 'Peso atual: 27.0 kg',
        time: today.add(const Duration(hours: 14, minutes: 23)),
        author: 'Ragonha',
        tag: 'SAÚDE',
        icon: Icons.monitor_weight_outlined,
        color: _historyGreen,
        details: const {'Peso': '27.0 kg', 'Responsável': 'Ragonha'},
      ),
      HistoryEntry(
        id: 'mock_incident_1',
        type: HistoryEntryType.incident,
        title: 'Ocorrência • Averiguação',
        subtitle: 'Rua Guido Orsi, Jardim Ouro Verde',
        time: today.add(const Duration(hours: 13, minutes: 17)),
        author: 'Você',
        tag: 'VOCÊ',
        icon: Icons.assignment_outlined,
        color: _historyYellow,
        location: 'Rua Guido Orsi, Jardim Ouro Verde',
        details: const {
          'Status': 'Concluída',
          'Local': 'Rua Guido Orsi, Jardim Ouro Verde',
          'Resultado': 'Sem alteração',
        },
      ),
      HistoryEntry(
        id: 'mock_training_1',
        type: HistoryEntryType.training,
        title: 'Treino • Obediência',
        subtitle: 'Sessão registrada',
        time: today.add(const Duration(hours: 12, minutes: 37)),
        author: 'Ragonha',
        tag: 'TREINO',
        icon: Icons.fitness_center_rounded,
        color: _historyGreen,
        details: const {'Tipo': 'Obediência', 'Condutor': 'Ragonha'},
      ),
      HistoryEntry(
        id: 'mock_nutrition',
        type: HistoryEntryType.nutrition,
        title: 'Alimentação registrada',
        subtitle: 'Ração: 450g',
        time: yesterday.add(const Duration(hours: 17, minutes: 48)),
        author: 'Ragonha',
        tag: 'NUTRIÇÃO',
        icon: Icons.rice_bowl_rounded,
        color: _historyYellow,
        details: const {'Quantidade': '450g', 'Responsável': 'Ragonha'},
      ),
      HistoryEntry(
        id: 'mock_incident_2',
        type: HistoryEntryType.incident,
        title: 'Ocorrência • Apoio em abordagem',
        subtitle: 'Av. das Américas, 1200',
        time: yesterday.add(const Duration(hours: 9, minutes: 12)),
        author: 'Ragonha',
        tag: 'OCORRÊNCIA',
        icon: Icons.emergency_share_rounded,
        color: AppTheme.error,
        location: 'Av. das Américas, 1200',
        details: const {
          'Status': 'Concluída',
          'Local': 'Av. das Américas, 1200',
        },
      ),
      HistoryEntry(
        id: 'mock_vaccine',
        type: HistoryEntryType.health,
        title: 'Vacinação aplicada',
        subtitle: 'V8 • Lote 24521',
        time: previous.add(const Duration(hours: 16, minutes: 2)),
        author: 'Veterinário João',
        tag: 'SAÚDE',
        icon: Icons.vaccines_outlined,
        color: _historyGreen,
        details: const {'Vacina': 'V8', 'Lote': '24521', 'Veterinário': 'João'},
      ),
      HistoryEntry(
        id: 'mock_training_2',
        type: HistoryEntryType.training,
        title: 'Treino • Detecção',
        subtitle: 'Odor: Cocaína',
        time: previous.add(const Duration(hours: 10, minutes: 31)),
        author: 'Ragonha',
        tag: 'TREINO',
        icon: Icons.fitness_center_rounded,
        color: _historyGreen,
        details: const {'Tipo': 'Detecção', 'Substância': 'Cocaína'},
      ),
    ]..sort((a, b) => b.time.compareTo(a.time));
  }
}
