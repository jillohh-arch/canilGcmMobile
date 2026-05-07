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
        if (_selectedSubtype == ActivitySubtypeIds.detection)
          ..._buildDetecaoGrouped(),
        if (_selectedSubtype == ActivitySubtypeIds.missingPerson)
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
        searchCaptureSubtype: ActivitySubtypeIds.searchCapture,
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

  Future<T?> _showTacticalBottomSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
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
    final selectedOutcomes = Set<String>.from(_selectedOccurrenceOutcomes);

    _occCtrl.status = _occurrenceStatus;
    _occCtrl.successful = _occurrenceSuccessful;
    _occCtrl.selectedOutcomes
      ..clear()
      ..addAll(selectedOutcomes);
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
