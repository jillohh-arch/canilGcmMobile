part of 'dynamic_activity_sheet.dart';

// ignore_for_file: unused_element, invalid_use_of_protected_member

extension _OccurrenceSheetBuilders on _DynamicActivitySheetState {
  Widget _buildOccurrenceFormScaffold() {
    final tColor = _getCategoryColor();
    final isNewRecord = widget.documentId == null;

    return OccurrenceFormScaffold(
      backgroundColor: _kHudBackground,
      panelColor: _kHudPanel,
      accentColor: _kHudCyan,
      showTopBar: !_hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      modeLabel: ActivityFormLabels.occurrenceModeLabel(
        isNewRecord: isNewRecord,
      ),
      statusLabel: ActivityFormLabels.occurrenceStatusLabel(
        occurrenceStatus: _occurrenceStatus,
        isNewRecord: isNewRecord,
      ),
      content: _buildOccurrenceStepperContent(tColor, includeControls: false),
      footer: _showOccurrenceFinalization
          ? null
          : _buildOccurrenceActiveFooter(tColor),
      onBack: () => _closeForm(false),
    );
  }

  Widget _buildGroupedFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedSubtype == _SheetSubtype.detection)
          ..._buildDetecaoGrouped(),
        if (_selectedSubtype == _SheetSubtype.missingPerson)
          ..._buildBuscaPessoaGrouped(),
        ..._buildOccurrenceMetaFields(),
        const SizedBox(height: 32),
        _buildSaveButton(tColor),
      ],
    );
  }

  Widget _buildOccurrenceStepperContent(
    Color tColor, {
    bool includeControls = true,
  }) {
    final canShowFinalResults = _descriptionController.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, includeControls ? 28 : 18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showOccurrenceFinalization)
              _buildOccurrenceFinalizationPanel(tColor, canShowFinalResults)
            else
              _buildOccurrenceActivePanel(tColor),
            if (includeControls) ...[
              const SizedBox(height: 16),
              _buildOccurrenceActiveFooter(tColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOccurrenceActivePanel(Color tColor) {
    if (!_hasActiveOccurrenceRecord) {
      return _buildOccurrenceStartScreenV2(tColor);
    }

    return OccurrenceActivePanel(
      commandHeader: _buildOccurrenceCommandHeader(tColor),
      contextSummary: _buildOccurrenceActiveContextSummary(tColor),
      quickActions: _buildOccurrenceQuickActionGrid(tColor),
      timelinePreview: _occurrenceTimeline.isEmpty
          ? const []
          : [
              OccurrenceTimelinePreview(
                updates: _occurrenceTimeline,
                accent: _getCategoryColor(),
                onEventTap: _openOccurrenceEventDetails,
              ),
            ],
    );
  }

  Widget _buildOccurrenceStartScreenV2(Color tColor) {
    final dogVM = Provider.of<DogViewModel>(context);
    dynamic activeDog;
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        activeDog = dog;
        break;
      }
    }

    final dogName = widget.dogName.isNotEmpty
        ? widget.dogName
        : (activeDog?.name?.toString() ?? 'K9');
    final imageUrl = activeDog?.profileImageUrl?.toString();
    final locationLabel = _locationController.text.trim().isEmpty
        ? 'Capturando localização...'
        : _locationController.text.trim();
    final timeLabel = _timeController.text.trim().isEmpty
        ? '--:--'
        : _timeController.text.trim();
    final dateLabel = _formatDatePtBr(DateTime.now());
    final natureText = _naturezaOcorrenciaController.text.trim();

    return OccurrenceStartScreen(
      accentColor: tColor,
      panelColor: _kHudPanel,
      dogName: dogName,
      dogImageUrl: imageUrl,
      locationLabel: locationLabel,
      timeLabel: timeLabel,
      dateLabel: dateLabel,
      natureText: natureText,
      showNatureEditor: _showStartNatureEditor,
      natureEditor: _buildOccurrenceNatureOnlyEditor(),
      onRefreshLocation: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onRefreshTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onToggleNatureEditor: () =>
          setState(() => _showStartNatureEditor = !_showStartNatureEditor),
    );
  }

  Widget _buildOccurrenceNatureOnlyEditor() {
    return OccurrenceNatureSearch(
      controller: _naturezaOcorrenciaController,
      focusNode: _occurrenceNatureFocusNode,
      natures: _occurrenceNatures,
      panelColor: _kHudPanel,
      accent: _kHudCyan,
      onChanged: (_) => setState(_syncSelectedOccurrenceNatureFromText),
      onSelected: _selectOccurrenceNature,
      fieldBuilder: (context, controller, focusNode, onChanged) {
        return TacticalTextField(
          controller: controller,
          focusNode: focusNode,
          labelText: 'Natureza da ocorrência',
          prefixIcon: Icons.category_rounded,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search_rounded, color: _kHudCyan, size: 18),
            onPressed: () => focusNode.requestFocus(),
          ),
          onChanged: onChanged,
        );
      },
    );
  }

  Widget _buildOccurrenceFinalizationPanel(
    Color tColor,
    bool canShowFinalResults,
  ) {
    return OccurrenceFinalizationPanel(
      commandHeader: _buildOccurrenceCommandHeader(
        tColor,
        showOperationalMetrics: true,
      ),
      closeStep: _buildOccurrenceCloseStep(canShowFinalResults),
    );
  }

  Widget _buildOccurrenceInitialDataPanel(Color tColor) {
    return OccurrenceInitialDataPanel(
      accentColor: tColor,
      panelColor: _kHudPanel,
      natureStep: _buildOccurrenceNatureStep(),
      locationBlock: _buildOccurrenceCompactLocationBlock(tColor),
    );
  }

  Widget _buildOccurrenceActiveContextSummary(Color tColor) {
    final startedAt = _occurrenceStartedAt() ?? _resolveFormTimestamp();
    final startedLabel = _formatTimeOfDay(startedAt);
    final location = _locationController.text.trim().isEmpty
        ? 'Local pendente'
        : _locationController.text.trim();
    final team = _equipeController.text.trim().isEmpty
        ? 'Equipe pendente'
        : _equipeController.text.trim();

    return OccurrenceActiveContextSummary(
      accentColor: tColor,
      panelColor: _kHudPanel,
      backgroundColor: _kHudBackground,
      location: location,
      team: team,
      startedLabel: startedLabel,
      onEdit: () => _showOccurrenceInitialDataSheet(tColor),
    );
  }

  Future<void> _showOccurrenceInitialDataSheet(Color tColor) async {
    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceInitialDataSheet(
          accentColor: tColor,
          backgroundColor: _kHudBackground,
          child: _buildOccurrenceInitialDataPanel(tColor),
          onDone: () {
            setState(() {});
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildOccurrenceCompactLocationBlock(Color tColor) {
    return OccurrenceCompactLocationBlock(
      hasLocation: _locationController.text.trim().isNotEmpty,
      showMapAdjust: _selectedLocationLatLng != null,
      gpsColor: _kHudAmber,
      timeColor: _kHudGreen,
      accentColor: tColor,
      locationField: TacticalTextField(
        controller: _locationController,
        labelText: 'Endereço / Local',
        prefixIcon: Icons.location_on_rounded,
      ),
      timeField: TacticalTextField(
        controller: _timeController,
        labelText: 'Hora de início',
        prefixIcon: Icons.schedule_rounded,
        readOnly: true,
      ),
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onAdjustMap: _showOccurrenceLocationMapSheet,
    );
  }

  Future<void> _showOccurrenceLocationMapSheet() async {
    final location = _selectedLocationLatLng;
    if (location == null) return;

    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceLocationMapSheet(
          location: location,
          accentColor: _kHudCyan,
          backgroundColor: _kHudBackground,
          onLocationChanged: _selectOccurrenceLocation,
        );
      },
    );
  }

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

  Widget _buildOccurrenceActiveFooter(Color tColor) {
    return OccurrenceActiveFooter(
      showFinalization: _showOccurrenceFinalization,
      hasActiveOccurrenceRecord: _hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      accentColor: tColor,
      backgroundColor: _kHudBackground,
      dangerColor: _kHudRed,
      saveStatusPanel: _buildSaveStatusPanel(tColor),
      finalSaveButton: _buildPrimarySaveButton(_kHudRed),
      onCancelFinalization: () => setState(() {
        _showOccurrenceFinalization = false;
        _occurrenceStatus = OccurrenceFormController.statusInProgress;
        _occurrenceSuccessful = null;
      }),
      onStartOccurrence: _saveOccurrenceInProgress,
      onRequestFinalization: () {
        setState(() {
          _occurrenceFinishSubmitted = false;
          _showOccurrenceFinalization = true;
          _occurrenceStatus = OccurrenceFormController.statusCompleted;
          _occCtrl.setStatus(OccurrenceFormController.statusCompleted);
          _copyOccurrenceControllerToFields(includeOutcomes: false);
        });
      },
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
    if (_activeIncidentId == null) {
      final openIncident = await incidentVM.findOpenIncident(
        dogId: widget.dogId,
      );
      if (openIncident != null) {
        throw Exception(
          'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
        );
      }
    }

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

    if (_activeIncidentId == null) {
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
      documentId: _activeIncidentId,
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

  dynamic _activeDogFrom(DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        return dog;
      }
    }
    return null;
  }

  dynamic _operatorUserFrom({
    required UserViewModel userVM,
    required String currentRa,
  }) {
    for (final user in userVM.users) {
      if (user.ra == currentRa) {
        return user;
      }
    }
    return null;
  }

  Widget _buildOccurrenceCommandHeader(
    Color tColor, {
    bool showOperationalMetrics = false,
  }) {
    final status = _occurrenceStatus;
    final startedAt = _occurrenceStartedAt();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);
    final activeDog = _activeDogFrom(dogVM);
    final currentUser = _operatorUserFrom(
      userVM: userVM,
      currentRa: operatorContext.ra,
    );

    return OccurrenceCommandHeader(
      nature: OccurrenceDisplayText.headerNatureLabel(
        selectedSubtype: _selectedSubtype,
        manualNature: _naturezaOcorrenciaController.text,
      ),
      status: status,
      dogName: widget.dogName,
      operatorName: operatorContext.name,
      elapsedLabel: OccurrenceDisplayText.elapsedLabel(startedAt),
      eventCount: showOperationalMetrics ? _occurrenceTimeline.length : null,
      showOperationalMetrics: showOperationalMetrics,
      dogImageUrl: activeDog?.profileImageUrl?.toString(),
      operatorImageUrl: currentUser?.photoUrl?.toString(),
      accent: tColor,
      statusColor: status == OccurrenceFormController.statusCanceled
          ? _kHudRed
          : _kHudGreen,
      onBack: _isSaving ? null : () => _closeForm(false),
    );
  }

  DateTime? _occurrenceStartedAt() {
    if (_activeOccurrenceStartedAt != null) return _activeOccurrenceStartedAt;
    final data = widget.initialData;
    if (data == null) return null;
    final startedAt = data['startedAt'];
    if (startedAt != null) {
      return parseFirestoreDate(startedAt);
    }
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) return rawDate;
    return null;
  }

  Widget _buildOccurrenceNatureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OccurrenceNatureSearch(
          controller: _naturezaOcorrenciaController,
          focusNode: _occurrenceNatureFocusNode,
          natures: _occurrenceNatures,
          panelColor: _kHudPanel,
          accent: _kHudCyan,
          onChanged: (_) => setState(_syncSelectedOccurrenceNatureFromText),
          onSelected: _selectOccurrenceNature,
          fieldBuilder: (context, controller, focusNode, onChanged) {
            return TacticalTextField(
              controller: controller,
              focusNode: focusNode,
              labelText: 'Natureza da ocorrência',
              prefixIcon: Icons.category_rounded,
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.search_rounded,
                  color: _kHudCyan,
                  size: 18,
                ),
                onPressed: () => focusNode.requestFocus(),
              ),
              onChanged: onChanged,
            );
          },
        ),
        const SizedBox(height: 14),
        TacticalTextField(
          controller: _equipeController,
          labelText: 'Equipe envolvida',
          prefixIcon: Icons.group_rounded,
        ),
      ],
    );
  }

  Widget _buildOccurrenceCloseStep(bool canShowFinalResults) {
    return OccurrenceCloseWizard(
      isSaving: _isSaving,
      onCancel: () {
        setState(() {
          _occurrenceFinishSubmitted = false;
          _showOccurrenceFinalization = false;
          _occurrenceStatus = OccurrenceFormController.statusInProgress;
          _occurrenceSuccessful = null;
        });
      },
      onFinish: (wizardData) async {
        if (_occurrenceFinishSubmitted || _isSaving) return;
        setState(() {
          _occurrenceFinishSubmitted = true;
          _applyOccurrenceWizardData(wizardData);
        });

        final saved = await _save();
        if (!saved && mounted) {
          setState(() => _occurrenceFinishSubmitted = false);
        }
      },
    );
  }

  void _selectOccurrenceNature(OccurrenceNature option) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSubtype = option.name;
      _naturezaOcorrenciaController.text = option.label;
      _occCtrl.selectNatureById(option.name);
      _copyOccurrenceControllerToFields();
    });
  }

  void _addWizardDrugRow({required String type, required String amount}) {
    if (type.isEmpty && amount.isEmpty) return;
    _detecaoDrogas.add(
      OccurrenceDynamicRows.drug(
        type: type.isEmpty ? 'Maconha' : type,
        amount: amount,
      ),
    );
  }

  void _applyWizardDrugResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Droga apreendida')) return;

    _replaceDynamicRows(_detecaoDrogas, ['quantidade', 'especificar'], []);
    final drugDetails = wizardResult.details['drogas'];
    if (drugDetails is List) {
      for (final item in drugDetails) {
        if (item is! Map) continue;
        final data = Map<String, dynamic>.from(item);
        _addWizardDrugRow(
          type: (data['tipo'] ?? '').toString().trim(),
          amount: (data['quantidade'] ?? '').toString().trim(),
        );
      }
    }

    if (_detecaoDrogas.isEmpty) {
      _addWizardDrugRow(
        type: wizardResult.detail('droga_tipo'),
        amount: wizardResult.detail('droga_quantidade'),
      );
    }

    if (_detecaoDrogas.isEmpty) {
      _detecaoDrogas.add(OccurrenceDynamicRows.drug());
    }
  }

  void _applyWizardSeizedObjectResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Objetos apreendidos')) return;

    _replaceDynamicRows(_seizedObjects, ['descricao', 'quantidade'], []);
    final descricao = wizardResult.detail('objetos_descricao');
    final quantidade = wizardResult.detail('objetos_quantidade');
    if (descricao.isNotEmpty || quantidade.isNotEmpty) {
      _seizedObjects.add(
        OccurrenceDynamicRows.seizedObject(
          description: descricao,
          amount: quantidade,
        ),
      );
    }
  }

  void _applyWizardDetainedVehicleResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Veículo detido')) return;

    _replaceDynamicRows(_detainedVehicles, ['tipo', 'placa'], []);
    final tipo = wizardResult.detail('veiculo_tipo');
    final placa = wizardResult.detail('veiculo_placa');
    if (tipo.isNotEmpty || placa.isNotEmpty) {
      _detainedVehicles.add(
        OccurrenceDynamicRows.detainedVehicle(type: tipo, plate: placa),
      );
    }
  }

  void _applyWizardDetainedIndividualResult(
    OccurrenceWizardResult wizardResult,
  ) {
    if (!wizardResult.containsResult('Indivíduo detido')) return;

    _replaceDynamicRows(_detainedIndividuals, ['quantidade'], []);
    final quantidade = wizardResult.detail('individuo_quantidade');
    if (quantidade.isNotEmpty) {
      _detainedIndividuals.add(
        OccurrenceDynamicRows.detainedIndividual(amount: quantidade),
      );
    }

    final destino = wizardResult.detail('individuo_destino');
    if (destino.isNotEmpty) {
      _formData['Destino do indivíduo'] = destino;
    }
  }

  void _applyWizardAdministrativeDetails(OccurrenceWizardResult wizardResult) {
    final bo = wizardResult.detail('bo_numero');
    if (bo.isNotEmpty) {
      _boController.text = bo;
    }

    final apoio = wizardResult.detail('apoio_observacao');
    if (apoio.isNotEmpty) {
      _formData['Apoio prestado'] = apoio;
    }

    final encaminhamento = wizardResult.detail('encaminhamento_observacao');
    if (encaminhamento.isNotEmpty) {
      _formData['Encaminhamento médico'] = encaminhamento;
    }
  }

  void _applyOccurrenceWizardData(Map<String, dynamic> wizardData) {
    final wizardResult = OccurrenceWizardResult.fromMap(wizardData);
    _occurrenceStatus = OccurrenceFormController.statusCompleted;
    _occCtrl.setStatus(OccurrenceFormController.statusCompleted);

    _descriptionController.text = wizardResult.report;

    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(wizardResult.results);
    _occCtrl.selectedOutcomes
      ..clear()
      ..addAll(wizardResult.results);

    _occurrenceSuccessful = wizardResult.successful;

    _formData['wizard_results'] = wizardResult.results;
    _formData['wizard_details'] = wizardResult.details;

    _applyWizardDrugResult(wizardResult);
    _applyWizardSeizedObjectResult(wizardResult);
    _applyWizardDetainedVehicleResult(wizardResult);
    _applyWizardDetainedIndividualResult(wizardResult);
    _applyWizardAdministrativeDetails(wizardResult);

    _syncOccurrenceController();
  }

  List<Widget> _buildStandardContextFields() {
    if (!_isOccurrenceCategory) {
      return const [];
    }
    return [
      const SizedBox(height: 16),
      TacticalTextField(
        controller: _naturezaOcorrenciaController,
        labelText: 'Natureza da ocorrência',
        prefixIcon: Icons.category_rounded,
      ),
      ..._buildOccurrenceMetaFields(),
    ];
  }

  List<Widget> _buildOccurrenceMetaFields() {
    if (!_isOccurrenceCategory) {
      return const [];
    }

    final shortcuts = OccurrenceQuickUpdateCatalog.forSubtype(_selectedSubtype);
    return [
      OccurrenceMetaFields(
        status: _occurrenceStatus,
        successful: _occurrenceSuccessful,
        outcomeOptions: _outcomeOptionsForOccurrenceSubtype(_selectedSubtype),
        selectedOutcomes: _selectedOccurrenceOutcomes,
        shortcuts: shortcuts,
        selectedShortcutTitle: _selectedOccurrenceUpdateTitle,
        showUpdateSpacing: _selectedSubtype != null,
        updateController: _occurrenceUpdateController,
        timelineUpdates: _occurrenceTimeline,
        accent: _getCategoryColor(),
        onStatusSelected: (value) {
          setState(() {
            _occCtrl.setStatus(value);
            _copyOccurrenceControllerToFields(includeOutcomes: false);
          });
        },
        onSuccessChanged: (value) {
          setState(() => _occurrenceSuccessful = value);
        },
        onOutcomeToggle: (option) {
          setState(() {
            if (_selectedOccurrenceOutcomes.contains(option)) {
              _selectedOccurrenceOutcomes.remove(option);
            } else {
              _selectedOccurrenceOutcomes.add(option);
              _ensureOutcomeDetailRow(option);
            }
          });
        },
        onShortcutSelected: (title) {
          final shortcut = shortcuts.firstWhere(
            (shortcut) => shortcut.title == title,
          );
          _applyOccurrenceQuickUpdateShortcut(shortcut);
        },
        onEventTap: _openOccurrenceEventDetails,
      ),
    ];
  }

  List<Widget> _buildDetecaoGrouped() {
    return [
      OccurrenceDetectionGroupedSections(
        natureController: _naturezaOcorrenciaController,
        specificFields: _buildCategorySpecificFields(),
        topActionRow: _buildTopActionRow(),
        locationTimeRow: _buildLocationTimeRow(),
        descriptionField: _buildDescriptionField(),
        imageGallery: _buildImageGallery(),
      ),
    ];
  }

  List<Widget> _buildBuscaPessoaGrouped() {
    return [
      OccurrencePersonSearchGroupedSections(
        natureController: _naturezaOcorrenciaController,
        searchCaptureSubtype: _SheetSubtype.searchCapture,
        selectedSearchType: _formData['Tipo de Busca'] as String?,
        accentColor: _getCategoryColor(),
        odorObjectController: _odorObjetoController,
        missingTimeController: _tempoDesaparecimentoController,
        durationController: _durationController,
        terrainConditionController: _condicaoTerrenoController,
        onPullWeather: _pullCurrentWeather,
        onSearchTypeChanged: (value) {
          setState(() {
            if (value == null) {
              _formData.remove('Tipo de Busca');
            } else {
              _formData['Tipo de Busca'] = value;
            }
          });
        },
        topActionRow: _buildTopActionRow(),
        locationTimeRow: _buildLocationTimeRow(),
        trackingAction: _buildTrackingAction(
          startLabel: 'INICIAR RASTREIO TÁTICO',
          startIcon: Icons.satellite_alt_rounded,
          backgroundColor: const Color(0xFFFBBF24),
          foregroundColor: Colors.black,
        ),
        descriptionField: _buildDescriptionField(),
        imageGallery: _buildImageGallery(),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Ocorrência — ações rápidas / eventos
  // ---------------------------------------------------------------------------

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

  Future<List<File>> _pickOccurrenceEventPhotos() async {
    final files = await OccurrenceEventMediaService(
      storageService: StorageService(),
    ).pickCompressedPhotos();
    if (files.isEmpty) return const [];
    HapticFeedback.lightImpact();
    return files;
  }

  Future<List<Map<String, dynamic>>> _uploadOccurrenceEventPhotos(
    List<File> files,
  ) async {
    return OccurrenceEventMediaService(
      storageService: StorageService(),
    ).uploadPhotos(
      files: files,
      incidentIdOrDogId: _activeIncidentId ?? widget.dogId,
    );
  }

  Future<ResolvedLocation> _captureOccurrenceEventLocation() async {
    final location = await const LocationResolutionService()
        .currentHighAccuracy();
    HapticFeedback.lightImpact();
    return location;
  }

  Future<void> _openOccurrenceEventDetails(int index) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;
    final update = _occurrenceTimeline[index];
    final draft = OccurrenceEventDraft(update);
    final result = await _showOccurrenceEventDetailsSheet(update, draft);
    draft.dispose();
    if (result == null || !mounted) return;
    await _applyOccurrenceEventChange(index, result);
  }

  Future<OccurrenceEventChange?> _showOccurrenceEventDetailsSheet(
    IncidentProgressUpdate update,
    OccurrenceEventDraft draft,
  ) {
    return _showTacticalBottomSheet<OccurrenceEventChange>(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => OccurrenceEventDetailsSheet(
            update: update,
            titleController: draft.titleController,
            descriptionController: draft.descriptionController,
            timestampLabel: _formatOccurrenceEventTimestamp(update.timestamp),
            eventLocation: draft.location,
            eventAttachments: draft.attachments,
            pendingPhotoCount: draft.pendingPhotoCount,
            backgroundColor: _kHudBackground,
            panelColor: _kHudPanel,
            accentColor: _kHudCyan,
            successColor: _kHudGreen,
            warningColor: _kHudAmber,
            dangerColor: _kHudRed,
            onAddPhotos: () async {
              final files = await _pickOccurrenceEventPhotos();
              if (files.isEmpty) return;
              setSheetState(() => draft.addPendingPhotos(files));
            },
            onCaptureLocation: () async {
              try {
                final eventPoint = await _captureOccurrenceEventLocation();
                setSheetState(() => draft.applyLocation(eventPoint));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Não foi possível capturar o local: $e'),
                  ),
                );
              }
            },
            onDelete: () =>
                Navigator.of(context).pop(const OccurrenceEventChange.delete()),
            onSave: () async {
              try {
                final uploaded = await _uploadOccurrenceEventPhotos(
                  draft.pendingPhotos,
                );
                draft.addAttachments(uploaded);
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pop(OccurrenceEventChange.update(draft.toProgressUpdate()));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _cleanSaveError(e).isEmpty
                          ? 'Não foi possível salvar as evidências.'
                          : _cleanSaveError(e),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Future<T?> _showTacticalBottomSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  String _formatOccurrenceEventTimestamp(DateTime timestamp) {
    return '${_formatDatePtBr(timestamp)} às ${_formatTimeOfDay(timestamp)}';
  }

  Future<void> _syncActiveOccurrenceSnapshot(DateTime updatedAt) async {
    if (_activeIncidentId == null) return;
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);
    await _saveActiveOccurrenceSnapshot(
      incidentVM: incidentVM,
      currentRa: operatorContext.ra,
      currentOperatorName: operatorContext.name,
      updatedAt: updatedAt,
    );
  }

  Future<void> _applyOccurrenceEventChange(
    int index,
    OccurrenceEventChange change,
  ) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;
    final previousTimeline = List<IncidentProgressUpdate>.from(
      _occurrenceTimeline,
    );

    setState(() {
      _isSaving = true;
      _saveStatus = change.delete
          ? 'Excluindo evento...'
          : 'Atualizando evento...';
      _saveFailed = false;
      if (change.delete) {
        _occurrenceTimeline.removeAt(index);
      } else if (change.update != null) {
        _occurrenceTimeline[index] = change.update!;
      }
    });

    try {
      await _syncActiveOccurrenceSnapshot(DateTime.now());
      if (!mounted) return;
      _setSaveStatus('Linha do tempo sincronizada.');
      _showOperationalSnack(
        change.delete ? 'Evento excluído.' : 'Evento atualizado.',
        backgroundColor: const Color(0xFF123044),
        icon: change.delete
            ? Icons.delete_outline_rounded
            : Icons.cloud_done_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _occurrenceTimeline
          ..clear()
          ..addAll(previousTimeline);
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Ocorrência — controller sync e helpers de desfecho
  // ---------------------------------------------------------------------------

  String _resolveIncidentResultSummary() {
    return _occCtrl.resultSummary(
      fallback: (_formData['Resultado da Busca'] ?? 'Averiguação').toString(),
    );
  }

  void _syncOccurrenceController() {
    _occCtrl.status = _occurrenceStatus;
    _occCtrl.successful = _occurrenceSuccessful;
    _occCtrl.selectedOutcomes
      ..clear()
      ..addAll(_selectedOccurrenceOutcomes);
  }

  void _copyOccurrenceControllerToFields({bool includeOutcomes = true}) {
    // Status e successful são lidos diretamente via getters proxied para _occCtrl
    if (!includeOutcomes) return;
    // selectedOutcomes já é um getter para _occCtrl.selectedOutcomes
  }

  List<String> _outcomeOptionsForOccurrenceSubtype(String? subtype) {
    return _occCtrl.outcomeOptionsForNature(subtype);
  }

  void _ensureOutcomeDetailRow(String option) {
    final normalized = const TextMatchService().normalizePtBr(option);
    if (normalized.contains('veiculo') && _detainedVehicles.isEmpty) {
      _addDetainedVehicle();
    } else if (normalized.contains('detido') && _detainedIndividuals.isEmpty) {
      _addDetainedIndividual();
    } else if (normalized.contains('objeto') && _seizedObjects.isEmpty) {
      _addSeizedObject();
    } else if (normalized.contains('droga') && _detecaoDrogas.isEmpty) {
      _addDrug();
    }
  }

  List<IncidentProgressUpdate> _buildIncidentProgressUpdates(
    DateTime finalDate, {
    required String authorId,
    required String authorName,
  }) {
    return OccurrenceProgressUpdateBuilder.build(
      timeline: _occurrenceTimeline,
      isNewRecord: widget.initialData == null,
      isEditingExistingRecord: widget.documentId != null,
      timestamp: finalDate,
      description: _descriptionController.text,
      location: _locationController.text,
      status: _occurrenceStatus,
      selectedUpdateTitle: _selectedOccurrenceUpdateTitle,
      updateNote: _occurrenceUpdateController.text,
      authorId: authorId,
      authorName: authorName,
    );
  }

  List<String> get _detectionDrugOptions => [
    'Maconha',
    'Cocaína',
    'Crack',
    'Sintéticos',
    'Nose MP',
    'Outros',
  ];
}
