part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrencePayload on _DynamicActivitySheetState {
  Future<List<Map<String, dynamic>>>
  _prepareOccurrenceMediaAttachments() async {
    _setSaveStatus('Preparando anexos da ocorrência...');
    final List<Map<String, dynamic>> uploadedMedia = await _uploadAllMedia(
      'incidents',
    );
    return _mergeExistingIncidentMedia(uploadedMedia);
  }

  Map<String, dynamic>? _existingOccurrenceExtraFields() {
    if (widget.initialData?['extraFields'] is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(widget.initialData!['extraFields'] as Map);
  }

  void _validateOccurrenceBeforeSave() {
    OccurrenceSaveValidator.validate(
      status: _occurrenceStatus,
      description: _descriptionController.text,
      outcomes: _selectedOccurrenceOutcomes,
      subtype: _selectedSubtype,
      natureText: _naturezaOcorrenciaController.text,
    );
  }

  Map<String, dynamic> _buildOccurrenceExtraFields({
    required Map<String, dynamic>? existingExtraFields,
  }) {
    final extraFields = OccurrencePayloadBuilder.buildExtraFields(
      nature: _selectedSubtype,
      manualNature: _naturezaOcorrenciaController.text,
      formData: _formData,
      team: _equipeController.text,
      bo: _boController.text,
      supportedTeam: _guarnicaoController.text,
      situation: _situacaoController.text,
      interventionOutcome: _desfechoController.text,
      odorSource: _odorObjetoController.text,
      missingTime: _tempoDesaparecimentoController.text,
      searchDuration: _durationController.text,
      terrainCondition: _condicaoTerrenoController.text,
      serviceOrderNumber: _numeroOsController.text,
      drugRows: _detecaoDrogas,
      detainedIndividuals: _detainedIndividuals,
      seizedObjects: _seizedObjects,
      detainedVehicles: _detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: _publicoController.text,
      eventTheme: _temaController.text,
      locationLat: _selectedLocationLatLng?.latitude,
      locationLng: _selectedLocationLatLng?.longitude,
    );
    final selectedNature = _selectedOccurrenceNature();
    if (selectedNature != null) {
      extraFields['natureza_codigo'] = selectedNature.code;
      extraFields['natureza_nome'] = selectedNature.name;
      extraFields['natureza_grupo'] = selectedNature.group;
    }
    return extraFields;
  }

  Incident _buildOccurrenceIncident({
    required String currentRa,
    required DateTime finalDate,
    required DateTime startedAt,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required List<IncidentProgressUpdate> progressUpdates,
  }) {
    return OccurrencePayloadBuilder.buildIncident(
      documentId: _activeIncidentDocumentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      location: _locationController.text.isNotEmpty
          ? _locationController.text
          : 'GCM',
      description: _descriptionController.text,
      result: _resolveIncidentResultSummary(),
      type: _selectedSubtype,
      extraFields: extraFields,
      mediaAttachments: mediaAttachments,
      status: _occurrenceStatus,
      operationalSuccess: _occurrenceSuccessful,
      outcomes: _selectedOccurrenceOutcomes.toList(),
      startedAt: startedAt,
      updatedAt: finalDate,
      progressUpdates: progressUpdates,
    );
  }
}
