// ignore_for_file: invalid_use_of_protected_member

part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetSave on _DynamicActivitySheetState {
  Future<void> _saveTraining({
    required TrainingViewModel trainingVM,
    required AuthViewModel authVM,
  }) async {
    await _trainingCtrl.save(
      trainingVM: trainingVM,
      authVM: authVM,
      selectedSubtype: _selectedSubtype,
      formData: _formData,
      mediaAttachments: _mediaAttachments,
      onStatus: (msg) {
        if (mounted) setState(() => _saveStatus = msg);
      },
      onUploading: _markMediaUploading,
      onUploaded: _markMediaUploaded,
      onPending: _markMediaPending,
    );
  }

  Future<bool> _save({bool closeAfterSave = true}) async {
    if (_isOccurrenceCategory) {
      _syncSelectedOccurrenceNatureFromText();
    }
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      if (_isOccurrenceCategory) {
        _selectedSubtype = _naturezaOcorrenciaController.text.trim().isEmpty
            ? 'Averiguação'
            : _naturezaOcorrenciaController.text.trim();
        if (_naturezaOcorrenciaController.text.trim().isEmpty) {
          _naturezaOcorrenciaController.text = _selectedSubtype!;
        }
      } else {
        return false;
      }
    }
    if (_isSaving) return false;
    HapticFeedback.lightImpact();

    if (!_formKey.currentState!.validate()) {
      return false;
    }

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final routineVM = Provider.of<RoutineViewModel>(context, listen: false);
    final trainingVM = Provider.of<TrainingViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);

    _formKey.currentState!.save();
    setState(() {
      _isSaving = true;
      _saveStatus = 'Preparando dados...';
      _saveFailed = false;
    });

    try {
      await _saveByCategory(
        authVM: authVM,
        routineVM: routineVM,
        trainingVM: trainingVM,
        incidentVM: incidentVM,
        healthVM: healthVM,
        userVM: userVM,
      );

      if (mounted) {
        _setSaveStatus('Sincronizado com Firebase.');
        HapticFeedback.mediumImpact();
        _showOperationalSnack(
          _successSaveMessage(),
          backgroundColor: const Color(0xFF1B8A4C),
          icon: Icons.cloud_done_rounded,
        );
        if (closeAfterSave) {
          Navigator.pop(context, true);
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        final message = _cleanSaveError(e);
        _setSaveStatus(
          'Falha ao salvar. Verifique conexão/permissão.',
          failed: true,
        );
        _showOperationalSnack(
          message.isEmpty ? 'Não foi possível salvar o registro.' : message,
          backgroundColor: const Color(0xFFE53935),
          icon: Icons.error_outline_rounded,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _saveByCategory({
    required AuthViewModel authVM,
    required RoutineViewModel routineVM,
    required TrainingViewModel trainingVM,
    required IncidentViewModel incidentVM,
    required HealthViewModel healthVM,
    required UserViewModel userVM,
  }) async {
    if (widget.category == 'Rotina') {
      await _saveRoutine(routineVM: routineVM, authVM: authVM);
      return;
    }

    if (widget.category == 'Treino') {
      _setSaveStatus('Salvando treino no Firebase...');
      await _saveTraining(trainingVM: trainingVM, authVM: authVM);
      return;
    }

    if (_isOccurrenceCategory || widget.category == 'Evento') {
      await _saveOccurrenceOrEvent(
        authVM: authVM,
        incidentVM: incidentVM,
        userVM: userVM,
      );
      return;
    }

    if (widget.category == 'Saude') {
      await _saveHealth(healthVM: healthVM);
    }
  }

  Future<void> _saveRoutine({
    required RoutineViewModel routineVM,
    required AuthViewModel authVM,
  }) async {
    _setSaveStatus('Salvando rotina no Firebase...');
    await _routineCtrl.save(
      routineVM: routineVM,
      authVM: authVM,
      selectedSubtype: _selectedSubtype,
      formData: _formData,
      mediaAttachments: _mediaAttachments,
      resolvedTimestamp: _resolveFormTimestamp(),
      onStatus: (msg) {
        if (mounted) setState(() => _saveStatus = msg);
      },
      onUploading: _markMediaUploading,
      onUploaded: _markMediaUploaded,
      onPending: _markMediaPending,
    );
  }

  Future<void> _saveHealth({required HealthViewModel healthVM}) async {
    _setSaveStatus('Salvando prontuário no Firebase...');
    await _healthCtrl.save(
      healthVM: healthVM,
      selectedSubtype: _selectedSubtype,
      formData: _formData,
      mediaAttachments: _mediaAttachments,
      resolvedTimestamp: _resolveFormTimestamp(),
      onStatus: (msg) {
        if (mounted) setState(() => _saveStatus = msg);
      },
      onUploading: _markMediaUploading,
      onUploaded: _markMediaUploaded,
      onPending: _markMediaPending,
    );
  }

  void _markMediaUploading(Map<String, dynamic> attachment) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markUploading(attachment));
    }
  }

  void _markMediaUploaded(Map<String, dynamic> attachment, String url) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markDone(attachment, url));
    }
  }

  void _markMediaPending(Map<String, dynamic> attachment) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markPending(attachment));
    }
  }

  void _saveOccurrenceInProgress() {
    setState(() {
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _showOccurrenceFinalization = false;
    });
    _save(closeAfterSave: false);
  }
}
