part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceSave on _DynamicActivitySheetState {
  Future<List<Map<String, dynamic>>>
  _prepareOccurrenceMediaAttachments() async {
    _setSaveStatus('Preparando anexos da ocorrência...');
    final List<Map<String, dynamic>> uploadedMedia = await _uploadAllMedia(
      'incidents',
    );
    return _mergeExistingIncidentMedia(uploadedMedia);
  }

  Map<String, dynamic>? _existingOccurrenceExtraFields() {
    if (widget.initialData?['extraFields'] is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(widget.initialData!['extraFields'] as Map);
  }

  DateTime _occurrenceSaveDate() {
    return !_hasActiveIncidentDocument
        ? _resolveFormTimestamp()
        : DateTime.now();
  }

  DateTime _occurrenceStartedAtOr(DateTime fallbackDate) {
    return _activeOccurrenceStartedAt ??
        (widget.initialData?['startedAt'] != null
            ? parseFirestoreDate(widget.initialData!['startedAt'])
            : widget.initialData?['_rawDate'] ?? fallbackDate);
  }

  bool _isFinalizingOccurrence() {
    return _occurrenceStatus != OccurrenceFormController.statusInProgress;
  }

  bool _sameOccurrenceProgressUpdate(
    IncidentProgressUpdate left,
    IncidentProgressUpdate right,
  ) {
    return left.title == right.title &&
        left.description == right.description &&
        left.timestamp.isAtSameMomentAs(right.timestamp);
  }

  void _mergeOpenIncidentTimeline(Incident openIncident) {
    if (openIncident.progressUpdates.isEmpty) return;

    final current = List<IncidentProgressUpdate>.from(_occurrenceTimeline);
    _occurrenceTimeline.clear();

    for (final update in openIncident.progressUpdates) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }

    for (final update in current) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }
  }

  void _adoptOpenIncidentForCurrentOccurrence(Incident openIncident) {
    final id = _nonEmptyId(openIncident.id);
    if (id == null) return;

    _activeIncidentId = id;
    _activeOccurrenceStartedAt = openIncident.startedAt;
    _mergeOpenIncidentTimeline(openIncident);

    if (_locationController.text.trim().isEmpty) {
      _locationController.text = openIncident.location;
    }
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      _selectedSubtype = openIncident.type;
      _setOccurrenceNatureTextFromSelected();
    }
  }

  Future<void> _attachOpenIncidentIfAllowed({
    required IncidentViewModel incidentVM,
    required bool allowAttach,
  }) async {
    if (_hasActiveIncidentDocument) return;

    _setSaveStatus('Verificando ocorrência aberta...');
    final openIncident = await incidentVM.findOpenIncident(dogId: widget.dogId);
    if (openIncident == null) return;

    if (!allowAttach) {
      throw Exception(
        'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
      );
    }

    _adoptOpenIncidentForCurrentOccurrence(openIncident);
  }

  Future<void> _grantOccurrenceBadgesIfNeeded({
    required UserViewModel userVM,
    required String currentRa,
    required Map<String, dynamic> extraFields,
  }) async {
    final hasDetectedDrugs =
        extraFields.containsKey('drogas') &&
        (extraFields['drogas'] as List).isNotEmpty;
    final isDetection =
        _selectedSubtype == ActivitySubtypeIds.detection ||
        _selectedSubtype == ActivitySubtypeIds.narcoticsSearch;

    if (isDetection && hasDetectedDrugs) {
      await userVM.grantBadge(currentRa, 'faro_afiado');
    }
  }

  OperatorContext _operatorContext({
    required AuthViewModel authVM,
    required UserViewModel userVM,
  }) {
    return const OperatorContextService().fromViewModels(
      authVM: authVM,
      userVM: userVM,
    );
  }

  Future<void> _saveOccurrenceOrEvent({
    required AuthViewModel authVM,
    required IncidentViewModel incidentVM,
    required UserViewModel userVM,
  }) async {
    _setSaveStatus('Validando ocorrência...');
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    await _attachOpenIncidentIfAllowed(
      incidentVM: incidentVM,
      allowAttach: _isFinalizingOccurrence() || _occurrenceTimeline.isNotEmpty,
    );

    _validateOccurrenceBeforeSave();

    final finalMedia = await _prepareOccurrenceMediaAttachments();
    final extraFields = _buildOccurrenceExtraFields(
      existingExtraFields: _existingOccurrenceExtraFields(),
    );

    final finalDate = _occurrenceSaveDate();
    final startedAt = _occurrenceStartedAtOr(finalDate);
    _activeOccurrenceStartedAt ??= startedAt;
    _ensureInitialOccurrenceTimelineEntry(
      timestamp: startedAt,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
    final incidentUpdates = _buildIncidentProgressUpdates(
      finalDate,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );

    final inc = _buildOccurrenceIncident(
      currentRa: operatorContext.ra,
      finalDate: finalDate,
      startedAt: startedAt,
      extraFields: extraFields,
      mediaAttachments: finalMedia,
      progressUpdates: incidentUpdates,
    );

    if (_hasActiveIncidentDocument) {
      _setSaveStatus('Atualizando ocorrência no Firebase...');
      await incidentVM.updateIncident(inc);
      _occurrenceTimeline
        ..clear()
        ..addAll(incidentUpdates);
      return;
    }

    _setSaveStatus('Criando ocorrência no Firebase...');
    await incidentVM.saveIncident(inc);
    _activeIncidentId = inc.id;
    _activeOccurrenceStartedAt = inc.startedAt;
    _occurrenceTimeline
      ..clear()
      ..addAll(incidentUpdates);

    await _grantOccurrenceBadgesIfNeeded(
      userVM: userVM,
      currentRa: operatorContext.ra,
      extraFields: extraFields,
    );
  }

  void _validateOccurrenceBeforeSave() {
    OccurrenceSaveValidator.validate(
      status: _occurrenceStatus,
      description: _descriptionController.text,
      outcomes: _selectedOccurrenceOutcomes,
      subtype: _selectedSubtype,
      natureText: _naturezaOcorrenciaController.text,
    );
  }

  Map<String, dynamic> _buildOccurrenceExtraFields({
    required Map<String, dynamic>? existingExtraFields,
  }) {
    final extraFields = OccurrencePayloadBuilder.buildExtraFields(
      nature: _selectedSubtype,
      manualNature: _naturezaOcorrenciaController.text,
      formData: _formData,
      team: _equipeController.text,
      bo: _boController.text,
      supportedTeam: _guarnicaoController.text,
      situation: _situacaoController.text,
      interventionOutcome: _desfechoController.text,
      odorSource: _odorObjetoController.text,
      missingTime: _tempoDesaparecimentoController.text,
      searchDuration: _durationController.text,
      terrainCondition: _condicaoTerrenoController.text,
      serviceOrderNumber: _numeroOsController.text,
      drugRows: _detecaoDrogas,
      detainedIndividuals: _detainedIndividuals,
      seizedObjects: _seizedObjects,
      detainedVehicles: _detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: _publicoController.text,
      eventTheme: _temaController.text,
      locationLat: _selectedLocationLatLng?.latitude,
      locationLng: _selectedLocationLatLng?.longitude,
    );
    final selectedNature = _selectedOccurrenceNature();
    if (selectedNature != null) {
      extraFields['natureza_codigo'] = selectedNature.code;
      extraFields['natureza_nome'] = selectedNature.name;
      extraFields['natureza_grupo'] = selectedNature.group;
    }
    return extraFields;
  }

  Incident _buildOccurrenceIncident({
    required String currentRa,
    required DateTime finalDate,
    required DateTime startedAt,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required List<IncidentProgressUpdate> progressUpdates,
  }) {
    return OccurrencePayloadBuilder.buildIncident(
      documentId: _activeIncidentDocumentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      location: _locationController.text.isNotEmpty
          ? _locationController.text
          : 'GCM',
      description: _descriptionController.text,
      result: _resolveIncidentResultSummary(),
      type: _selectedSubtype,
      extraFields: extraFields,
      mediaAttachments: mediaAttachments,
      status: _occurrenceStatus,
      operationalSuccess: _occurrenceSuccessful,
      outcomes: _selectedOccurrenceOutcomes.toList(),
      startedAt: startedAt,
      updatedAt: finalDate,
      progressUpdates: progressUpdates,
    );
  }
}
