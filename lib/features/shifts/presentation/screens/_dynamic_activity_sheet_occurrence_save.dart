part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceSave on _DynamicActivitySheetState {
  DateTime _occurrenceSaveDate() {
    return !_hasActiveIncidentDocument
        ? _resolveFormTimestamp()
        : DateTime.now();
  }

  DateTime _occurrenceStartedAtOr(DateTime fallbackDate) {
    return _activeOccurrenceStartedAt ??
        (widget.initialData?['startedAt'] != null
            ? parseFirestoreDate(widget.initialData!['startedAt'])
            : widget.initialData?['_rawDate'] ?? fallbackDate);
  }

  bool _isFinalizingOccurrence() {
    return _occurrenceStatus != OccurrenceFormController.statusInProgress;
  }

  OperatorContext _operatorContext({
    required AuthViewModel authVM,
    required UserViewModel userVM,
  }) {
    return const OperatorContextService().fromViewModels(
      authVM: authVM,
      userVM: userVM,
    );
  }

  Future<void> _saveOccurrenceOrEvent({
    required AuthViewModel authVM,
    required IncidentViewModel incidentVM,
    required UserViewModel userVM,
  }) async {
    _setSaveStatus('Validando ocorrência...');
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    await _attachOpenIncidentIfAllowed(
      incidentVM: incidentVM,
      allowAttach: _isFinalizingOccurrence() || _occurrenceTimeline.isNotEmpty,
    );

    _validateOccurrenceBeforeSave();

    final finalMedia = await _prepareOccurrenceMediaAttachments();
    final extraFields = _buildOccurrenceExtraFields(
      existingExtraFields: _existingOccurrenceExtraFields(),
    );

    final finalDate = _occurrenceSaveDate();
    final startedAt = _occurrenceStartedAtOr(finalDate);
    _activeOccurrenceStartedAt ??= startedAt;
    _ensureInitialOccurrenceTimelineEntry(
      timestamp: startedAt,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
    final incidentUpdates = _buildIncidentProgressUpdates(
      finalDate,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );

    final inc = _buildOccurrenceIncident(
      currentRa: operatorContext.ra,
      finalDate: finalDate,
      startedAt: startedAt,
      extraFields: extraFields,
      mediaAttachments: finalMedia,
      progressUpdates: incidentUpdates,
    );

    if (_hasActiveIncidentDocument) {
      _setSaveStatus('Atualizando ocorrência no Firebase...');
      await incidentVM.updateIncident(inc);
      _occurrenceTimeline
        ..clear()
        ..addAll(incidentUpdates);
      return;
    }

    _setSaveStatus('Criando ocorrência no Firebase...');
    await incidentVM.saveIncident(inc);
    _activeIncidentId = inc.id;
    _activeOccurrenceStartedAt = inc.startedAt;
    _occurrenceTimeline
      ..clear()
      ..addAll(incidentUpdates);
  }
}
