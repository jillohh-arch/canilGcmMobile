part of 'activity_sheet_occurrence_ctrl.dart';

extension ActivitySheetOccurrencePopulate on ActivitySheetOccurrenceCtrl {
  // Populate (edição de registro existente)
  // -------------------------------------------------------------------------

  void _populate(Map<String, dynamic> data) {
    _populateTimestamp(data);
    _populateEditData(data);
  }

  void _populateTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      final h = rawDate.hour.toString().padLeft(2, '0');
      final m = rawDate.minute.toString().padLeft(2, '0');
      timeController.text = '$h:$m';
    }
  }

  void _populateEditData(Map<String, dynamic> data) {
    _selectedNature = OccurrenceFormController.normalizeNature(
      data['type'] ?? _Sub.detection,
    );
    _setNatureTextFromSelected();
    locationController.text = data['location'] ?? '';
    descriptionController.text = data['description'] ?? '';
    status = OccurrenceFormController.normalizeStatus(data['status']);
    successful = data['operationalSuccess'] as bool?;
    showFinalization = status != OccurrenceFormController.statusInProgress;

    if (data['extraFields'] is Map) {
      _populateExtraFields(
        Map<String, dynamic>.from(data['extraFields'] as Map),
      );
    }
    _populateOutcomes(data['outcomes']);
    _populateTimeline(data);
    _syncFormCtrl();
  }

  void _populateOutcomes(dynamic rawOutcomes) {
    if (rawOutcomes is! List) return;
    selectedOutcomes
      ..clear()
      ..addAll(
        List<String>.from(
          rawOutcomes,
        ).map(OccurrenceFormController.normalizeOutcome),
      );
  }

  void _populateTimeline(Map<String, dynamic> data) {
    if (data['progressUpdates'] is List) {
      timeline
        ..clear()
        ..addAll(
          (data['progressUpdates'] as List).map(
            (e) => IncidentProgressUpdate.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
      return;
    }
    if (descriptionController.text.isEmpty) return;
    timeline
      ..clear()
      ..add(
        IncidentProgressUpdate(
          title: 'Registro inicial',
          description: descriptionController.text,
          timestamp: data['_rawDate'] is DateTime
              ? data['_rawDate'] as DateTime
              : DateTime.now(),
          location: locationController.text,
        ),
      );
  }

  void _populateExtraFields(Map<String, dynamic> extra) {
    final snapshot = OccurrenceExtraFieldsSnapshot(extra);
    equipeController.text = snapshot.team;
    boController.text = snapshot.reportNumber;
    guarnicaoController.text = snapshot.supportedGarrison;
    situacaoController.text = snapshot.situation;
    desfechoController.text = snapshot.interventionOutcome;
    odorObjetoController.text = snapshot.odorSource;
    tempoDesaparecimentoController.text = snapshot.missingTime;
    condicaoTerrenoController.text = snapshot.terrainCondition;
    numeroOsController.text = snapshot.serviceOrderNumber;
    publicoController.text = snapshot.publicEstimate;
    temaController.text = snapshot.eventTheme;

    if (_selectedNature == _Sub.other) {
      naturezaController.text = snapshot.manualNatureOrNature();
    }

    if (snapshot.searchType != null) {
      // Armazenado via formData no State — será repassado via formData
    }

    final lat = snapshot.locationLat;
    final lng = snapshot.locationLng;
    if (lat != null && lng != null) {
      selectedLocationLatLng = LatLng(lat, lng);
    }

    final details = snapshot.detailedResults;
    if (details != null) {
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }
    if (detecaoDrogas.isEmpty) {
      _hydrateDrugRows(snapshot.legacyDrugRows);
    }
  }

  // -------------------------------------------------------------------------
}
