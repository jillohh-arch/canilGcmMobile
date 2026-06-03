part of 'history_screen.dart';

extension _HistoryDataLoader on _HistoryScreenState {
  void _loadAllData({bool forceReload = false}) {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) return;

    final dogId = shiftVM.activeDogId!;

    debugPrint(
      '[History] _loadAllData chamado para dogId=$dogId (force=$forceReload)',
    );

    // Buscar treinos
    final trainingVM = Provider.of<TrainingViewModel>(context, listen: false);
    trainingVM
        .fetchTrainingsForDog(dogId)
        .then((_) {
          final count = trainingVM.trainings.length;
          debugPrint('[History] Treinos carregados: $count');
        })
        .catchError((e) {
          debugPrint('[History] ERRO ao carregar treinos: $e');
        });

    // Buscar registros de saúde
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    healthVM
        .fetchHealthLogsForDog(dogId)
        .then((_) {
          final count = healthVM.healthLogs.length;
          debugPrint('[History] Saúde carregados: $count');
        })
        .catchError((e) {
          debugPrint('[History] ERRO ao carregar saúde: $e');
        });

    // Buscar nutrição
    final nutritionVM = Provider.of<NutritionViewModel>(context, listen: false);
    nutritionVM.loadForDog(dogId, forceReload: forceReload).catchError((e) {
      debugPrint('[History] ERRO ao carregar nutrição: $e');
    });
    nutritionVM
        .loadFullHistory(dogId)
        .then((_) {
          debugPrint(
            '[History] Nutrição carregados: ${nutritionVM.historyFeedings.length}',
          );
        })
        .catchError((e) {
          debugPrint('[History] ERRO ao carregar histórico nutrição: $e');
        });

    WeightHistoryService()
        .getHistory(dogId, limit: 200)
        .then((records) {
          if (!mounted) return;
          setState(() => _weightRecords = records);
          debugPrint(
            '[History] Pesagens canônicas carregadas: ${records.length}',
          );
        })
        .catchError((e) {
          if (!mounted) return;
          setState(() => _weightRecords = const []);
          debugPrint('[History] ERRO ao carregar pesagens canônicas: $e');
        });
    // Observar ocorrências (stream real-time)
    Provider.of<OccurrenceViewModel>(context, listen: false).watchByDog(dogId);
    debugPrint('[History] watchByDog iniciado para dogId=$dogId');
  }

  List<HistoryEntry> _buildAllEntries(String dogId) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);

    final dogName = _resolveDogName(dogId, dogVM);
    final entries = <HistoryEntry>[];

    for (final log in healthVM.healthLogs) {
      if (log.dogId == dogId) entries.add(_buildHealthEntry(log, dogName));
    }

    for (final record in _weightRecords) {
      entries.add(_buildWeightRecordEntry(record, dogName));
    }

    for (final occ in occurrenceVM.occurrences) {
      if (occ.dogId == dogId) entries.add(_buildOccurrenceEntry(occ));
    }

    for (final training in trainingVM.trainings) {
      if (training.dogId == dogId || training.dogId.isEmpty) {
        entries.add(_buildTrainingEntry(training));
      }
    }

    final feedings = nutritionVM.historyFeedings.isNotEmpty
        ? nutritionVM.historyFeedings
        : nutritionVM.todayFeedings;
    for (final feeding in feedings) {
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
          color: _hYellow,
          originalModel: feeding,
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
      color: _hGreen,
      originalModel: log,
      details: {
        'Cão': dogName,
        'Tipo': log.logType,
        '_healthKind': isWeight ? 'weight' : log.type,
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

  HistoryEntry _buildWeightRecordEntry(WeightRecord record, String dogName) {
    return HistoryEntry(
      id: record.id ?? 'weight_${record.measuredAt.millisecondsSinceEpoch}',
      type: HistoryEntryType.health,
      title: 'Pesagem operacional registrada',
      subtitle: 'Peso atual: ${record.weightKg.toStringAsFixed(1)} kg',
      time: record.measuredAt,
      author: _resolveAuthorName(record.measuredBy),
      authorId: record.measuredBy,
      tag: 'PESO',
      icon: Icons.monitor_weight_rounded,
      color: _hPurple,
      originalModel: record,
      details: {
        'Cão': dogName,
        'Tipo': 'Pesagem',
        '_healthKind': 'weight',
        'Peso': '${record.weightKg.toStringAsFixed(1)} kg',
        if (record.context.trim().isNotEmpty) 'Contexto': record.context,
        if (record.notes?.trim().isNotEmpty == true)
          'Observações': record.notes,
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
      color: _hGreen,
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

  HistoryEntry _buildOccurrenceEntry(Occurrence occ) {
    final isYou = _isCurrentUser(occ.primaryHandlerId);
    final isOpen =
        occ.status == OccurrenceStatus.inProgress ||
        occ.status == OccurrenceStatus.finalizing;

    return HistoryEntry(
      id: occ.id,
      type: HistoryEntryType.occurrence,
      title: 'Ocorrência · ${occ.typeName}',
      subtitle: occ.locationAddress?.trim().isNotEmpty == true
          ? occ.locationAddress!.trim()
          : 'Local não informado',
      time: occ.startedAt,
      author: isYou ? 'Você' : _resolveAuthorName(occ.primaryHandlerId),
      authorId: occ.primaryHandlerId,
      tag: isYou ? 'VOCÊ' : 'OCORRÊNCIA',
      icon: Icons.assignment_outlined,
      color: isYou ? _hYellow : _hCyan,
      location: occ.locationAddress ?? '',
      isInProgress: isOpen,
      editedAt: occ.auditTrail.length > 1 ? occ.updatedAt : null,
      originalModel: occ,
      details: {
        'Tipo': occ.typeName,
        'Status': occ.status.toMap(),
        if (occ.locationAddress?.isNotEmpty == true)
          'Local': occ.locationAddress,
        'Condutor': _resolveAuthorName(occ.primaryHandlerId),
        'Início': DateFormat('HH:mm').format(occ.startedAt),
        if (occ.finalizedAt != null)
          'Fim': DateFormat('HH:mm').format(occ.finalizedAt!),
        if (occ.finalReport?.isNotEmpty == true) 'Descrição': occ.finalReport,
        if (occ.results.isNotEmpty)
          '_outcomes': occ.results.map((r) => r.toMap()).toList(),
        if (occ.auditTrail.isNotEmpty) '_auditTrail': occ.auditTrail,
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

  // ignore: unused_element
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
        color: _hGreen,
        details: const {'Peso': '27.0 kg', 'Responsável': 'Ragonha'},
      ),
      HistoryEntry(
        id: 'mock_occurrence_1',
        type: HistoryEntryType.occurrence,
        title: 'Ocorrência • Averiguação',
        subtitle: 'Rua Guido Orsi, Jardim Ouro Verde',
        time: today.add(const Duration(hours: 13, minutes: 17)),
        author: 'Você',
        tag: 'VOCÊ',
        icon: Icons.assignment_outlined,
        color: _hYellow,
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
        color: _hGreen,
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
        color: _hYellow,
        details: const {'Quantidade': '450g', 'Responsável': 'Ragonha'},
      ),
      HistoryEntry(
        id: 'mock_occurrence_2',
        type: HistoryEntryType.occurrence,
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
        color: _hGreen,
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
        color: _hGreen,
        details: const {'Tipo': 'Detecção', 'Substância': 'Cocaína'},
      ),
    ]..sort((a, b) => b.time.compareTo(a.time));
  }
}
