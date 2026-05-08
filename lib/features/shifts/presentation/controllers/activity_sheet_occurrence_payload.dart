part of 'activity_sheet_occurrence_ctrl.dart';

extension ActivitySheetOccurrencePayload on ActivitySheetOccurrenceCtrl {
  // Sincronização com OccurrenceFormController
  // -------------------------------------------------------------------------

  void _syncFormCtrl() {
    _formCtrl.status = status;
    _formCtrl.successful = successful;
    _formCtrl.outcomes
      ..clear()
      ..addAll(selectedOutcomes);
  }

  void _copyFormCtrlToFields({bool includeOutcomes = true}) {
    status = _formCtrl.status;
    successful = _formCtrl.successful;
    if (!includeOutcomes) return;
    selectedOutcomes
      ..clear()
      ..addAll(_formCtrl.outcomes);
  }

  void setStatus(String s) {
    _formCtrl.setStatus(s);
    _copyFormCtrlToFields(includeOutcomes: false);
    onStateChanged();
  }

  List<String> outcomeOptionsForNature(String? subtype) =>
      _formCtrl.outcomeOptionsForNature(subtype);

  String resultSummary({String? fallback}) => _formCtrl.resultSummary(
    nature: _selectedNature,
    fallback: fallback ?? 'Averiguação',
  );

  // -------------------------------------------------------------------------
  // Build de payload (extraFields + Incident)
  // -------------------------------------------------------------------------

  Map<String, dynamic> buildExtraFields({
    required Map<String, dynamic> formData,
    required Map<String, dynamic>? existingExtraFields,
  }) {
    final extra = OccurrencePayloadBuilder.buildExtraFields(
      nature: _selectedNature,
      manualNature: naturezaController.text,
      formData: formData,
      team: equipeController.text,
      bo: boController.text,
      supportedTeam: guarnicaoController.text,
      situation: situacaoController.text,
      interventionOutcome: desfechoController.text,
      odorSource: odorObjetoController.text,
      missingTime: tempoDesaparecimentoController.text,
      searchDuration: '', // Preenchido pelo State via _durationController
      terrainCondition: condicaoTerrenoController.text,
      serviceOrderNumber: numeroOsController.text,
      drugRows: detecaoDrogas,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: publicoController.text,
      eventTheme: temaController.text,
      locationLat: selectedLocationLatLng?.latitude,
      locationLng: selectedLocationLatLng?.longitude,
    );
    final n = _selectedOccurrenceNature();
    if (n != null) {
      extra['natureza_codigo'] = n.code;
      extra['natureza_nome'] = n.name;
      extra['natureza_grupo'] = n.group;
    }
    return extra;
  }

  Incident buildIncident({
    required String? currentRa,
    required DateTime finalDate,
    required DateTime startedAt,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required List<IncidentProgressUpdate> progressUpdates,
    required String handlerIdOverride,
  }) {
    _syncFormCtrl();
    return OccurrencePayloadBuilder.buildIncident(
      documentId: activeIncidentId,
      dogId: dogId,
      dogName: dogName,
      handlerId: handlerIdOverride.isNotEmpty
          ? handlerIdOverride
          : (currentRa ?? 'GCM'),
      location: locationController.text.isNotEmpty
          ? locationController.text
          : 'GCM',
      description: descriptionController.text,
      result: resultSummary(
        fallback: (extraFields['Resultado da Busca'] ?? 'Averiguação')
            .toString(),
      ),
      type: _selectedNature,
      extraFields: extraFields,
      mediaAttachments: mediaAttachments,
      status: status,
      operationalSuccess: successful,
      outcomes: selectedOutcomes.toList(),
      startedAt: startedAt,
      updatedAt: finalDate,
      progressUpdates: progressUpdates,
    );
  }

  List<IncidentProgressUpdate> buildProgressUpdates({
    required DateTime finalDate,
    required String authorId,
    required String authorName,
    required bool isNewRecord,
    required bool isEditingExistingRecord,
  }) {
    return OccurrenceProgressUpdateBuilder.build(
      timeline: timeline,
      isNewRecord: isNewRecord,
      isEditingExistingRecord: isEditingExistingRecord,
      timestamp: finalDate,
      description: descriptionController.text,
      location: locationController.text,
      status: status,
      selectedUpdateTitle: selectedUpdateTitle,
      updateNote: updateController.text,
      authorId: authorId,
      authorName: authorName,
    );
  }

  // -------------------------------------------------------------------------
  // Validação
  // -------------------------------------------------------------------------

  void validate() {
    OccurrenceSaveValidator.validate(
      status: status,
      description: descriptionController.text,
      outcomes: selectedOutcomes,
      subtype: _selectedNature,
      natureText: naturezaController.text,
    );
  }

  // -------------------------------------------------------------------------
}
