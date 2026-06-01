// ignore_for_file: invalid_use_of_protected_member

part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetSave on _DynamicActivitySheetState {
  Future<bool> _save({bool closeAfterSave = true}) async {
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      return false;
    }
    if (_isSaving) return false;
    HapticFeedback.lightImpact();

    if (!_formKey.currentState!.validate()) {
      return false;
    }

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final trainingVM = Provider.of<TrainingViewModel>(context, listen: false);
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);

    _formKey.currentState!.save();
    setState(() {
      _isSaving = true;
      _saveStatus = 'Preparando dados...';
      _saveFailed = false;
    });

    try {
      await _saveByCategory(
        authVM: authVM,
        trainingVM: trainingVM,
        healthVM: healthVM,
      );

      if (mounted) {
        _setSaveStatus('Sincronizado com Firebase.');
        HapticFeedback.mediumImpact();
        _showOperationalSnack(
          _successSaveMessage(),
          backgroundColor: AppTheme.successOperational,
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
          backgroundColor: AppTheme.errorStrong,
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
