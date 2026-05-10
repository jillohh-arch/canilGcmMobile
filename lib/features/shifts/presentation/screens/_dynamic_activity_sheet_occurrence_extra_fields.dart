part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetOccurrenceExtraFields
    on _DynamicActivitySheetState {
  void _populateOccurrenceExtraFields(Map<String, dynamic> extraFields) {
    final snapshot = OccurrenceExtraFieldsSnapshot(extraFields);

    _equipeController.text = snapshot.team;
    _boController.text = snapshot.reportNumber;
    _guarnicaoController.text = snapshot.supportedGarrison;
    _situacaoController.text = snapshot.situation;
    _desfechoController.text = snapshot.interventionOutcome;
    _odorObjetoController.text = snapshot.odorSource;
    _tempoDesaparecimentoController.text = snapshot.missingTime;
    _durationController.text = snapshot.searchDuration;
    _condicaoTerrenoController.text = snapshot.terrainCondition;
    _numeroOsController.text = snapshot.serviceOrderNumber;
    _publicoController.text = snapshot.publicEstimate;
    _temaController.text = snapshot.eventTheme;

    if (_selectedSubtype == ActivitySubtypeIds.other) {
      _naturezaOcorrenciaController.text = snapshot.manualNatureOrNature();
    }

    if (snapshot.searchType != null) {
      _formData['Tipo de Busca'] = snapshot.searchType;
    }

    final lat = snapshot.locationLat;
    final lng = snapshot.locationLng;
    if (lat != null && lng != null) {
      _occCtrl.selectedLocationLatLng = LatLng(lat, lng);
    }

    final details = snapshot.detailedResults;
    if (details != null) {
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }

    if (_detecaoDrogas.isEmpty) {
      _hydrateDrugRows(snapshot.legacyDrugRows);
    }
  }

  void _hydrateDetainedIndividuals(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detainedIndividuals,
      ['quantidade'],
      OccurrenceDynamicRows.hydrateDetainedIndividuals(rows),
    );
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_seizedObjects, [
      'descricao',
      'quantidade',
    ], OccurrenceDynamicRows.hydrateSeizedObjects(rows));
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detecaoDrogas,
      ['quantidade', 'especificar'],
      OccurrenceDynamicRows.hydrateDrugs(
        rows,
        knownOptions: _detectionDrugOptions,
      ),
    );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_detainedVehicles, [
      'tipo',
      'placa',
    ], OccurrenceDynamicRows.hydrateDetainedVehicles(rows));
  }
}
