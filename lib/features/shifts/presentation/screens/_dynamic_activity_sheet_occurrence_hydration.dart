part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceHydration
    on _DynamicActivitySheetState {
  void _populateOccurrenceEditData(Map<String, dynamic> data) {
    _selectedSubtype = OccurrenceFormController.normalizeNature(
      data['type'] ??
          (_isOccurrenceCategory
              ? ActivitySubtypeIds.detection
              : ActivitySubtypeIds.event),
    );
    _setOccurrenceNatureTextFromSelected();
    _locationController.text = data['location'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _formData['Resultado da Busca'] = data['result'];
    _occurrenceStatus = OccurrenceFormController.normalizeStatus(
      data['status'],
    );
    _occurrenceSuccessful = data['operationalSuccess'] as bool?;
    _showOccurrenceFinalization =
        _occurrenceStatus != OccurrenceFormController.statusInProgress;

    if (data['extraFields'] is Map) {
      _populateOccurrenceExtraFields(
        Map<String, dynamic>.from(data['extraFields'] as Map),
      );
    }
    _populateOccurrenceOutcomes(data['outcomes']);
    _populateOccurrenceTimeline(data);
    _syncOccurrenceController();
  }

  void _populateOccurrenceOutcomes(dynamic rawOutcomes) {
    if (rawOutcomes is! List) return;

    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(
        List<String>.from(
          rawOutcomes,
        ).map(OccurrenceFormController.normalizeOutcome),
      );
  }
}
