// ignore_for_file: invalid_use_of_protected_member

part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetCategorySave on _DynamicActivitySheetState {
  Future<void> _saveByCategory({
    required AuthViewModel authVM,
    required TrainingViewModel trainingVM,
    required HealthViewModel healthVM,
  }) async {
    if (widget.category == 'Treino') {
      _setSaveStatus('Salvando treino no Firebase...');
      await _saveTraining(trainingVM: trainingVM, authVM: authVM);
      return;
    }

    if (widget.category == 'Saude') {
      await _saveHealth(healthVM: healthVM);
      return;
    }

    throw StateError('Categoria não suportada por DynamicActivitySheet.');
  }

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
}
