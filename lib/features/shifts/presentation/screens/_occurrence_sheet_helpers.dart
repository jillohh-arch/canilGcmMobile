part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetHelpers on _DynamicActivitySheetState {
  Future<T?> _showTacticalBottomSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

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
    // Status e successful são lidos diretamente via getters proxied para _occCtrl.
    if (!includeOutcomes) return;
    // selectedOutcomes já é um getter para _occCtrl.selectedOutcomes.
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
