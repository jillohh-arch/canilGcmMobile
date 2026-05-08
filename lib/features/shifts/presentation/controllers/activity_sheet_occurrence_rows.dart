part of 'activity_sheet_occurrence_ctrl.dart';

extension ActivitySheetOccurrenceRows on ActivitySheetOccurrenceCtrl {
  // Listas dinâmicas
  // -------------------------------------------------------------------------

  void _replaceDynamicRows(
    List<Map<String, dynamic>> target,
    List<String> keys,
    List<Map<String, dynamic>> next,
  ) {
    OccurrenceDynamicRows.disposeRows(target, keys);
    target
      ..clear()
      ..addAll(next);
  }

  void _hydrateDetainedIndividuals(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(detainedIndividuals, [
      'quantidade',
    ], OccurrenceDynamicRows.hydrateDetainedIndividuals(rows));
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(seizedObjects, [
      'descricao',
      'quantidade',
    ], OccurrenceDynamicRows.hydrateSeizedObjects(rows));
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      detecaoDrogas,
      ['quantidade', 'especificar'],
      OccurrenceDynamicRows.hydrateDrugs(
        rows,
        knownOptions: ActivitySheetOccurrenceCtrl.drugOptions,
      ),
    );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(detainedVehicles, [
      'tipo',
      'placa',
    ], OccurrenceDynamicRows.hydrateDetainedVehicles(rows));
  }

  void addDrug() {
    detecaoDrogas.add(OccurrenceDynamicRows.drug());
    onStateChanged();
  }

  void removeDrug(int index) {
    detecaoDrogas[index]['quantidade'].dispose();
    detecaoDrogas[index]['especificar']?.dispose();
    detecaoDrogas.removeAt(index);
    onStateChanged();
  }

  void addDetainedIndividual() {
    detainedIndividuals.add(OccurrenceDynamicRows.detainedIndividual());
    onStateChanged();
  }

  void addSeizedObject() {
    seizedObjects.add(OccurrenceDynamicRows.seizedObject());
    onStateChanged();
  }

  void addDetainedVehicle() {
    detainedVehicles.add(OccurrenceDynamicRows.detainedVehicle());
    onStateChanged();
  }

  void ensureOutcomeDetailRow(String option) {
    final normalized = const TextMatchService().normalizePtBr(option);
    if (normalized.contains('veiculo') && detainedVehicles.isEmpty) {
      addDetainedVehicle();
    } else if (normalized.contains('detido') && detainedIndividuals.isEmpty) {
      addDetainedIndividual();
    } else if (normalized.contains('objeto') && seizedObjects.isEmpty) {
      addSeizedObject();
    } else if (normalized.contains('droga') && detecaoDrogas.isEmpty) {
      addDrug();
    }
  }

  // -------------------------------------------------------------------------
}
