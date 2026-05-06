part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _StandardSheetBuilders on _DynamicActivitySheetState {
  Widget _buildStandardFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      children: [
        _buildTopActionRow(),
        const SizedBox(height: 16),
        _buildLocationTimeRow(),
        const SizedBox(height: 32),
        ..._buildDynamicFields(),
        ..._buildCategorySpecificFields(),
        ..._buildStandardContextFields(),
        ..._buildTrainingMetaFields(),
        ..._buildHealthMetaFields(),
        ..._buildRoutineMetaFields(),
        const SizedBox(height: 24),
        _buildDescriptionField(),
        const SizedBox(height: 24),
        _buildImageGallery(),
        const SizedBox(height: 48),
        _buildSaveButton(tColor),
      ],
    );
  }

  List<Widget> _buildTrainingMetaFields() {
    if (widget.category != 'Treino') {
      return const [];
    }

    return [
      TrainingActivityFields(
        visible: true,
        durationController: _durationController,
      ),
    ];
  }

  List<Widget> _buildRoutineMetaFields() {
    if (widget.category != 'Rotina') {
      return const [];
    }

    return [
      RoutineActivityFields(
        visible: true,
        isFeeding: _selectedSubtype == _SheetSubtype.feeding,
        isPlayOrWalk:
            _selectedSubtype == _SheetSubtype.play ||
            _selectedSubtype == _SheetSubtype.walk,
        isWalk: _selectedSubtype == _SheetSubtype.walk,
        rationBrandController: _racaoMarcaController,
        rationAmountController: _racaoQtdController,
        durationController: _durationController,
        distanceController: _distanciaController,
      ),
    ];
  }

  List<Widget> _buildHealthMetaFields() {
    if (widget.category != 'Saude') {
      return const [];
    }

    return [
      HealthActivityFields(
        subtype: _selectedSubtype,
        consultationSubtype: _SheetSubtype.consultation,
        vaccineSubtype: _SheetSubtype.vaccine,
        examSubtype: _SheetSubtype.exam,
        bathSubtype: _SheetSubtype.bath,
        accentColor: _kHudCyan,
        responsibleController: _vetNameController,
        reasonController: _motivoController,
        vaccineTypeController: _tipoVacinaController,
        examTypeController: _tipoExameController,
        bathProductsController: _produtosBanhoController,
        returnDateController: _returnDateController,
        selectedVaccine: _selectedVacina,
        onVaccineChanged: (val) => setState(() {
          _healthCtrl.selectedVacina = val;
          _healthCtrl.tipoVacinaController.text = val ?? '';
        }),
        onPickReturnDate: _pickReturnDate,
      ),
    ];
  }

  Future<void> _pickReturnDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1B8A4C),
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null) {
      return;
    }

    _returnDateController.text = _formatDatePtBr(date);
  }

  Widget _buildTopActionRow() {
    return QuickLocationActions(
      backgroundColor: _kHudBackground,
      gpsColor: _kHudAmber,
      timeColor: _kHudGreen,
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
    );
  }

  Widget _buildLocationTimeRow() {
    return ActivityLocationTimeFields(
      locationController: _locationController,
      timeController: _timeController,
      isHealth: widget.category == 'Saude',
    );
  }

  Widget _buildDescriptionField() {
    return ActivityDescriptionField(
      controller: _descriptionController,
      labelText: _descriptionLabel(),
      isListening: _isListening,
      onStartListening: _listen,
      onStopListening: _stopListening,
      onToggleListening: () {
        if (_isListening) {
          _stopListening();
        } else {
          _listen();
        }
      },
    );
  }

  String _descriptionLabel() {
    return ActivityFormLabels.descriptionLabel(
      category: widget.category,
      subtype: _selectedSubtype,
      feedingSubtype: _SheetSubtype.feeding,
    );
  }

  Widget _buildSaveButton(Color tColor) {
    return ActivitySaveButton(
      accentColor: tColor,
      foregroundColor: _kHudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildPrimarySaveButton(Color tColor) {
    return ActivityPrimarySaveButton(
      accentColor: tColor,
      foregroundColor: _kHudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildSaveStatusPanel(Color accent) {
    return ActivitySaveStatusPanel(
      accentColor: accent,
      isSaving: _isSaving,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
    );
  }

  void _handlePrimarySave() {
    HapticFeedback.heavyImpact();
    _save();
  }

  Widget _buildTrackingAction({
    required String startLabel,
    required IconData startIcon,
    required Color backgroundColor,
    required Color foregroundColor,
    bool isLightMode = false,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    EdgeInsetsGeometry capturedMargin = EdgeInsets.zero,
  }) {
    final distance = _formData['_trackingDistance'];
    return ActivityTrackingAction(
      hasRoute: _formData.containsKey('_trackingRoute'),
      distanceMeters: distance is num ? distance : null,
      startLabel: startLabel,
      startIcon: startIcon,
      startBackgroundColor: backgroundColor,
      startForegroundColor: foregroundColor,
      padding: padding,
      capturedMargin: capturedMargin,
      onStart: () => _openLiveTracking(isLightMode: isLightMode),
    );
  }

  List<Widget> _buildDynamicFields() {
    if (!DynamicSubtypeFields.handles(_selectedSubtype)) {
      return const [];
    }

    return [
      DynamicSubtypeFields(
        subtype: _selectedSubtype,
        formData: _formData,
        accentColor: _getCategoryColor(),
        odorAccentColor: _kHudAmber,
        objectiveController: _objetivoTreinoController,
        difficultiesController: _dificuldadesController,
        temperatureController: _tempController,
        humidityController: _humidityController,
        onChanged: _setFormDataValue,
        onOdorChanged: (value) {
          setState(() => _formData['Tipo de Odor'] = value);
        },
        onPullWeather: _pullCurrentWeather,
        trackingActionBuilder: _buildTrackingAction,
      ),
    ];
  }

  List<Widget> _buildCategorySpecificFields() {
    if (!_isOccurrenceCategory ||
        !OccurrenceSpecificFields.handles(_selectedSubtype)) {
      return const [];
    }

    return [
      OccurrenceSpecificFields(
        subtype: _selectedSubtype,
        formData: _formData,
        drugs: _detecaoDrogas,
        drugOptions: _detectionDrugOptions,
        accentColor: _getCategoryColor(),
        detectionAccentColor: _kHudCyan,
        supportTeamController: _equipeController,
        reportNumberController: _boController,
        garrisonController: _guarnicaoController,
        situationController: _situacaoController,
        outcomeController: _desfechoController,
        odorObjectController: _odorObjetoController,
        missingTimeController: _tempoDesaparecimentoController,
        durationController: _durationController,
        terrainConditionController: _condicaoTerrenoController,
        orderNumberController: _numeroOsController,
        audienceController: _publicoController,
        themeController: _temaController,
        onAddDrug: _addDrug,
        onRemoveDrug: _removeDrug,
        onDrugTypeChanged: (drug, type) {
          setState(() => drug['tipo'] = type);
        },
        onSearchTypeChanged: (value) {
          setState(() {
            if (value == null) {
              _formData.remove('Tipo de Busca');
            } else {
              _formData['Tipo de Busca'] = value;
            }
          });
        },
        onPullWeather: _pullCurrentWeather,
      ),
    ];
  }

  Widget _buildImageGallery() {
    return MediaAttachmentGallery(
      isCompressing: _isCompressing,
      showPdfAttachment: _selectedSubtype == _SheetSubtype.exam,
      pdfName: _examePdfFile != null ? (_examePdfName ?? 'arquivo.pdf') : null,
      mediaAttachments: _mediaAttachments,
      activePhotoIndex: _activePhotoIndex,
      onPickImage: _pickImage,
      onPickPdf: _pickPdf,
      onRemovePdf: () => setState(() {
        _healthCtrl.examePdfFile = null;
        _healthCtrl.examePdfName = null;
      }),
      onSelectPhoto: (index) {
        setState(() => _activePhotoIndex = index);
        HapticFeedback.lightImpact();
      },
      onRemovePhoto: (index) {
        setState(() {
          MediaAttachmentRows.disposeCaption(_mediaAttachments[index]);
          _mediaAttachments.removeAt(index);
          if (_activePhotoIndex >= _mediaAttachments.length) {
            _activePhotoIndex = _mediaAttachments.length - 1;
          }
        });
        HapticFeedback.selectionClick();
      },
    );
  }

  Future<void> _pickPdf() async {
    final result = await const PdfAttachmentService().pickPdf();
    if (result != null) {
      setState(() {
        _healthCtrl.examePdfFile = result.file;
        _healthCtrl.examePdfName = result.name;
      });
      HapticFeedback.lightImpact();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers de formulário padrão
  // ---------------------------------------------------------------------------

  String _saveButtonLabel() {
    return ActivityFormLabels.saveButtonLabel(
      category: widget.category,
      occurrenceStatus: _occurrenceStatus,
    );
  }

  Future<void> _openLiveTracking({bool isLightMode = false}) async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTrackingScreen(isLightMode: isLightMode),
      ),
    );

    if (result == null || result is! Map || !mounted) return;

    final distanceMeters = result['distanceMeters'];
    final durationSeconds = result['durationSeconds'];

    setState(() {
      _formData['_trackingRoute'] = result['route'];
      _formData['_trackingDistance'] = distanceMeters;
      if (durationSeconds is num) {
        _durationController.text = (durationSeconds / 60).floor().toString();
      }
      if (distanceMeters is num) {
        _distanciaController.text = (distanceMeters / 1000).toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rastreamento finalizado. Distância e tempo calculados.'),
        backgroundColor: Color(0xFF1B8A4C),
      ),
    );
  }

  void _setFormDataValue(String label, String? value) {
    setState(() {
      if (value == null) {
        _formData.remove(label);
      } else {
        _formData[label] = value;
      }
    });
  }
}
