part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetHydration on _DynamicActivitySheetState {
  void _populateEditData() {
    final d = widget.initialData!;
    _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';
    _populateEditTimestamp(d);

    if (widget.category == 'Treino') {
      _populateTrainingEditData(d);
    } else if (widget.category == 'Rotina') {
      _populateRoutineEditData(d);
    } else if (_isOccurrenceCategory || widget.category == 'Evento') {
      _populateOccurrenceEditData(d);
    } else if (widget.category == 'Saude') {
      _populateHealthEditData(d);
    }

    _applySelectedSubtypeImage();
  }

  void _populateEditTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      _timeController.text = _formatTimeOfDay(rawDate);
    }
  }

  void _populateTrainingEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _trainingCtrl.init()
    _selectedSubtype = data['trainingType'];
  }

  void _populateRoutineEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _routineCtrl.init()
    _selectedSubtype = data['activityType'];
  }

  void _populateOccurrenceEditData(Map<String, dynamic> data) {
    _selectedSubtype = OccurrenceFormController.normalizeNature(
      data['type'] ??
          (_isOccurrenceCategory
              ? ActivitySubtypeIds.detection
              : ActivitySubtypeIds.event),
    );
    _setOccurrenceNatureTextFromSelected();
    _locationController.text = data['location'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _formData['Resultado da Busca'] = data['result'];
    _occurrenceStatus = OccurrenceFormController.normalizeStatus(
      data['status'],
    );
    _occurrenceSuccessful = data['operationalSuccess'] as bool?;
    _showOccurrenceFinalization =
        _occurrenceStatus != OccurrenceFormController.statusInProgress;

    if (data['extraFields'] is Map) {
      _populateOccurrenceExtraFields(
        Map<String, dynamic>.from(data['extraFields'] as Map),
      );
    }
    _populateOccurrenceOutcomes(data['outcomes']);
    _populateOccurrenceTimeline(data);
    _syncOccurrenceController();
  }

  void _populateOccurrenceOutcomes(dynamic rawOutcomes) {
    if (rawOutcomes is! List) return;

    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(
        List<String>.from(
          rawOutcomes,
        ).map(OccurrenceFormController.normalizeOutcome),
      );
  }

  void _populateOccurrenceTimeline(Map<String, dynamic> data) {
    _occurrenceTimeline.clear();

    if (data['progressUpdates'] is List) {
      _occurrenceTimeline.addAll(
        (data['progressUpdates'] as List).map(
          (e) => IncidentProgressUpdate.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        ),
      );
    }

    _ensureInitialOccurrenceTimelineEntry(
      timestamp: _timelineStartFromOccurrenceData(data),
      authorId: data['_rawHandlerId']?.toString(),
    );
  }

  DateTime _timelineStartFromOccurrenceData(Map<String, dynamic> data) {
    if (data['startedAt'] != null) {
      return parseFirestoreDate(data['startedAt']);
    }
    if (data['_rawDate'] is DateTime) {
      return data['_rawDate'] as DateTime;
    }
    if (data['date'] != null) {
      return parseFirestoreDate(data['date']);
    }
    return _activeOccurrenceStartedAt ?? _resolveFormTimestamp();
  }

  IncidentProgressUpdate _initialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    final description = _descriptionController.text.trim();

    return IncidentProgressUpdate(
      title: 'Início da ocorrência',
      description: description.isNotEmpty
          ? description
          : 'Ocorrência iniciada pela equipe.',
      timestamp:
          timestamp ?? _activeOccurrenceStartedAt ?? _resolveFormTimestamp(),
      location: _locationController.text.trim(),
      authorId: authorId,
      authorName: authorName,
    );
  }

  bool _isInitialOccurrenceTimelineEntry(IncidentProgressUpdate update) {
    final normalized = const TextMatchService().normalizePtBr(update.title);
    return normalized.contains('inicio') ||
        normalized.contains('registro inicial');
  }

  void _ensureInitialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    if (_occurrenceTimeline.any(_isInitialOccurrenceTimelineEntry)) {
      return;
    }

    _occurrenceTimeline.insert(
      0,
      _initialOccurrenceTimelineEntry(
        timestamp: timestamp,
        authorId: authorId,
        authorName: authorName,
      ),
    );
  }

  void _populateHealthEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _healthCtrl.init()
    _selectedSubtype = data['logType'];
  }

  void _applySelectedSubtypeImage() {
    final cardImage = ActivityCardCatalog.imageFor(
      category: widget.category,
      id: _selectedSubtype,
    );
    if (cardImage != null) {
      _selectedSubtypeImagePath = cardImage;
    }
  }

  void _populateOccurrenceExtraFields(Map<String, dynamic> extraFields) {
    final snapshot = OccurrenceExtraFieldsSnapshot(extraFields);

    _equipeController.text = snapshot.team;
    _boController.text = snapshot.reportNumber;
    _guarnicaoController.text = snapshot.supportedGarrison;
    _situacaoController.text = snapshot.situation;
    _desfechoController.text = snapshot.interventionOutcome;
    _odorObjetoController.text = snapshot.odorSource;
    _tempoDesaparecimentoController.text = snapshot.missingTime;
    _durationController.text = snapshot.searchDuration;
    _condicaoTerrenoController.text = snapshot.terrainCondition;
    _numeroOsController.text = snapshot.serviceOrderNumber;
    _publicoController.text = snapshot.publicEstimate;
    _temaController.text = snapshot.eventTheme;

    if (_selectedSubtype == ActivitySubtypeIds.other) {
      _naturezaOcorrenciaController.text = snapshot.manualNatureOrNature();
    }

    if (snapshot.searchType != null) {
      _formData['Tipo de Busca'] = snapshot.searchType;
    }

    final lat = snapshot.locationLat;
    final lng = snapshot.locationLng;
    if (lat != null && lng != null) {
      _occCtrl.selectedLocationLatLng = LatLng(lat, lng);
    }

    final details = snapshot.detailedResults;
    if (details != null) {
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }

    if (_detecaoDrogas.isEmpty) {
      _hydrateDrugRows(snapshot.legacyDrugRows);
    }
  }

  void _setOccurrenceNatureTextFromSelected() {
    if (!_isOccurrenceCategory || _selectedSubtype == null) return;
    final selected = _selectedOccurrenceNature();
    _naturezaOcorrenciaController.text = selected?.label ?? _selectedSubtype!;
  }

  void _syncSelectedOccurrenceNatureFromText() {
    if (!_isOccurrenceCategory) return;
    final text = _naturezaOcorrenciaController.text.trim();
    if (text.isEmpty) {
      _selectedSubtype = null;
      return;
    }

    final normalized = OccurrenceNature.normalizeForSearch(text);
    final selected = _occurrenceNatures.cast<OccurrenceNature?>().firstWhere((
      nature,
    ) {
      if (nature == null) return false;
      return OccurrenceNature.normalizeForSearch(nature.label) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.name) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.code) == normalized;
    }, orElse: () => null);

    _selectedSubtype = selected?.name ?? text;
  }

  OccurrenceNature? _selectedOccurrenceNature() {
    final selectedSubtype = _selectedSubtype;
    if (selectedSubtype == null || selectedSubtype.trim().isEmpty) {
      return null;
    }
    final normalized = OccurrenceNature.normalizeForSearch(selectedSubtype);
    return _occurrenceNatures.cast<OccurrenceNature?>().firstWhere((nature) {
      if (nature == null) return false;
      return OccurrenceNature.normalizeForSearch(nature.name) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.label) == normalized;
    }, orElse: () => null);
  }

  void _hydrateDetainedIndividuals(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detainedIndividuals,
      ['quantidade'],
      OccurrenceDynamicRows.hydrateDetainedIndividuals(rows),
    );
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_seizedObjects, [
      'descricao',
      'quantidade',
    ], OccurrenceDynamicRows.hydrateSeizedObjects(rows));
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detecaoDrogas,
      ['quantidade', 'especificar'],
      OccurrenceDynamicRows.hydrateDrugs(
        rows,
        knownOptions: _detectionDrugOptions,
      ),
    );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_detainedVehicles, [
      'tipo',
      'placa',
    ], OccurrenceDynamicRows.hydrateDetainedVehicles(rows));
  }
}
