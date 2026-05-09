part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetEvents on _DynamicActivitySheetState {
  Widget _buildOccurrenceQuickActionGrid(Color tColor) {
    final actions = OccurrenceQuickActionCatalog.primaryActions(
      amber: _kHudAmber,
      green: _kHudGreen,
      cyan: _kHudCyan,
    );

    return OccurrenceQuickActionGrid(
      accentColor: tColor,
      actions: actions,
      enabled: !_isSaving,
      onActionSelected: _handleOccurrenceQuickAction,
      onOpenEventCenter: () => _showOccurrenceEventCenter(tColor),
    );
  }

  Future<void> _handleOccurrenceQuickAction(
    OccurrenceQuickAction action,
  ) async {
    if (action.options.isEmpty) {
      await _registerOccurrenceEvent(action);
      return;
    }

    final selected = await _showOccurrenceActionOptions(action);
    if (selected == null) return;
    await _registerOccurrenceEvent(selected);
  }

  Future<OccurrenceQuickAction?> _showOccurrenceActionOptions(
    OccurrenceQuickAction action,
  ) {
    HapticFeedback.selectionClick();
    return _showTacticalBottomSheet<OccurrenceQuickAction>(
      builder: (context) => OccurrenceQuickActionOptionsSheet(
        action: action,
        backgroundColor: _kHudBackground,
        panelColor: _kHudPanel,
      ),
    );
  }

  Future<void> _showOccurrenceEventCenter(Color tColor) async {
    HapticFeedback.selectionClick();
    final categories = OccurrenceEventCatalog.categories(tColor);
    _occurrenceUpdateController.clear();

    await _showTacticalBottomSheet<void>(
      builder: (context) => OccurrenceEventCenterSheet(
        accentColor: tColor,
        backgroundColor: _kHudBackground,
        panelColor: _kHudPanel,
        categories: categories,
        controller: _occurrenceUpdateController,
        focusNode: _occurrenceUpdateFocusNode,
        onActionSelected: _registerOccurrenceEvent,
      ),
    );
  }

  IncidentProgressUpdate _buildOccurrenceEventUpdate(
    OccurrenceQuickAction action, {
    required DateTime timestamp,
    required OperatorContext operatorContext,
  }) {
    return IncidentProgressUpdate(
      title: action.title,
      description: action.description,
      timestamp: timestamp,
      location: _locationController.text.trim(),
      latitude: _selectedLocationLatLng?.latitude,
      longitude: _selectedLocationLatLng?.longitude,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
  }

  Future<void> _registerOccurrenceEvent(OccurrenceQuickAction action) async {
    if (_isSaving) return;
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    final update = _buildOccurrenceEventUpdate(
      action,
      timestamp: now,
      operatorContext: operatorContext,
    );

    setState(() {
      _isSaving = true;
      _saveStatus = 'Registrando evento...';
      _saveFailed = false;
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _selectedOccurrenceUpdateTitle = null;
      _ensureInitialOccurrenceTimelineEntry(
        timestamp: _activeOccurrenceStartedAt ?? _resolveFormTimestamp(),
        authorId: operatorContext.ra,
        authorName: operatorContext.name,
      );
      _occurrenceTimeline.add(update);
      _occurrenceUpdateController.clear();
    });

    try {
      await _saveActiveOccurrenceSnapshot(
        incidentVM: incidentVM,
        currentRa: operatorContext.ra,
        currentOperatorName: operatorContext.name,
        updatedAt: now,
      );
      if (!mounted) return;
      _setSaveStatus('Evento sincronizado.');
      _showOperationalSnack(
        '${action.title} registrado na linha do tempo.',
        backgroundColor: const Color(0xFF123044),
        icon: action.icon,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
        _saveStatus = 'Falha ao sincronizar evento.';
      });
      _showOperationalSnack(
        _cleanSaveError(e).isEmpty
            ? 'Não foi possível sincronizar o evento.'
            : _cleanSaveError(e),
        backgroundColor: const Color(0xFFE53935),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveActiveOccurrenceSnapshot({
    required IncidentViewModel incidentVM,
    required String currentRa,
    required String currentOperatorName,
    required DateTime updatedAt,
  }) async {
    await _attachOpenIncidentIfAllowed(
      incidentVM: incidentVM,
      allowAttach: _occurrenceTimeline.isNotEmpty,
    );

    _activeOccurrenceStartedAt ??= _resolveFormTimestamp();
    _ensureInitialOccurrenceTimelineEntry(
      timestamp: _activeOccurrenceStartedAt,
      authorId: currentRa,
      authorName: currentOperatorName,
    );
    final inc = _buildActiveOccurrenceSnapshot(
      currentRa: currentRa,
      currentOperatorName: currentOperatorName,
      updatedAt: updatedAt,
    );

    if (!_hasActiveIncidentDocument) {
      await incidentVM.saveIncident(inc);
      _activeIncidentId = inc.id;
      _activeOccurrenceStartedAt = inc.startedAt;
    } else {
      await incidentVM.updateIncident(inc);
    }
  }

  Incident _buildActiveOccurrenceSnapshot({
    required String currentRa,
    required String currentOperatorName,
    required DateTime updatedAt,
  }) {
    final effectiveNature = OccurrenceDisplayText.effectiveNature(
      _selectedSubtype,
    );
    final effectiveManualNature = OccurrenceDisplayText.manualNatureOr(
      manualNature: _naturezaOcorrenciaController.text,
      fallback: effectiveNature,
    );

    final extraFields = OccurrencePayloadBuilder.buildExtraFields(
      nature: effectiveNature,
      manualNature: effectiveManualNature,
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
      existingExtraFields: _existingOccurrenceExtraFields(),
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

    return OccurrencePayloadBuilder.buildIncident(
      documentId: _activeIncidentDocumentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      startedAt: _activeOccurrenceStartedAt ?? updatedAt,
      updatedAt: updatedAt,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : 'GCM',
      description: _descriptionController.text,
      result: OccurrenceFormController.statusInProgress,
      type: effectiveNature,
      extraFields: extraFields,
      mediaAttachments: _mergeExistingIncidentMedia(const []),
      status: OccurrenceFormController.statusInProgress,
      operationalSuccess: null,
      outcomes: _selectedOccurrenceOutcomes.toList(),
      progressUpdates: List<IncidentProgressUpdate>.from(_occurrenceTimeline),
    );
  }

  void _applyOccurrenceQuickUpdateShortcut(
    OccurrenceQuickUpdateShortcut shortcut,
  ) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedOccurrenceUpdateTitle == shortcut.title) {
        _selectedOccurrenceUpdateTitle = null;
        return;
      }
      _selectedOccurrenceUpdateTitle = shortcut.title;
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _occurrenceUpdateController.text = shortcut.template;
      _occurrenceUpdateController.selection = TextSelection.fromPosition(
        TextPosition(offset: _occurrenceUpdateController.text.length),
      );
    });
  }
}
