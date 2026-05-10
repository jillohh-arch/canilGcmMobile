part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceOpenIncident
    on _DynamicActivitySheetState {
  bool _sameOccurrenceProgressUpdate(
    IncidentProgressUpdate left,
    IncidentProgressUpdate right,
  ) {
    return left.title == right.title &&
        left.description == right.description &&
        left.timestamp.isAtSameMomentAs(right.timestamp);
  }

  void _mergeOpenIncidentTimeline(Incident openIncident) {
    if (openIncident.progressUpdates.isEmpty) return;

    final current = List<IncidentProgressUpdate>.from(_occurrenceTimeline);
    _occurrenceTimeline.clear();

    for (final update in openIncident.progressUpdates) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }

    for (final update in current) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }
  }

  void _adoptOpenIncidentForCurrentOccurrence(Incident openIncident) {
    final id = _nonEmptyId(openIncident.id);
    if (id == null) return;

    _activeIncidentId = id;
    _activeOccurrenceStartedAt = openIncident.startedAt;
    _mergeOpenIncidentTimeline(openIncident);

    if (_locationController.text.trim().isEmpty) {
      _locationController.text = openIncident.location;
    }
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      _selectedSubtype = openIncident.type;
      _setOccurrenceNatureTextFromSelected();
    }
  }

  Future<void> _attachOpenIncidentIfAllowed({
    required IncidentViewModel incidentVM,
    required bool allowAttach,
  }) async {
    if (_hasActiveIncidentDocument) return;

    _setSaveStatus('Verificando ocorrência aberta...');
    final openIncident = await incidentVM.findOpenIncident(dogId: widget.dogId);
    if (openIncident == null) return;

    if (!allowAttach) {
      throw Exception(
        'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
      );
    }

    _adoptOpenIncidentForCurrentOccurrence(openIncident);
  }
}
