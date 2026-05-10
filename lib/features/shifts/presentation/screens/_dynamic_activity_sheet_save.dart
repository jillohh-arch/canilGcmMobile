// ignore_for_file: invalid_use_of_protected_member

part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetSave on _DynamicActivitySheetState {
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
}
