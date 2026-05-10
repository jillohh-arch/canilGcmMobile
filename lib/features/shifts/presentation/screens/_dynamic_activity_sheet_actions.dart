part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetActions on _DynamicActivitySheetState {
  void _disposeDynamicResultRows(
    List<Map<String, dynamic>> rows,
    List<String> controllerKeys,
  ) {
    OccurrenceDynamicRows.disposeRows(rows, controllerKeys);
  }

  void _replaceDynamicRows(
    List<Map<String, dynamic>> target,
    List<String> controllerKeys,
    List<Map<String, dynamic>> nextRows,
  ) {
    _disposeDynamicResultRows(target, controllerKeys);
    target
      ..clear()
      ..addAll(nextRows);
  }

  void _selectSubtype(String type, {String? imagePath}) {
    HapticFeedback.lightImpact();
    _updateState(() {
      _selectedSubtype = type;
      if (_isOccurrenceCategory) {
        _setOccurrenceNatureTextFromSelected();
      }
      _selectedSubtypeImagePath =
          imagePath ?? 'assets/images/k9_tactical_background.png';
      _formData.clear();
      if (_isOccurrenceCategory) {
        _occCtrl.status = OccurrenceFormController.statusCompleted;
        _occCtrl.successful = true;
        _occCtrl.selectNatureById(type);
        _copyOccurrenceControllerToFields();
        _occurrenceTimeline.clear();
        _selectedOccurrenceUpdateTitle = null;
        _occurrenceUpdateController.clear();
      }
      _showMenu = false;
    });
  }

  void _addDrug() {
    _updateState(() {
      _detecaoDrogas.add(OccurrenceDynamicRows.drug());
    });
    HapticFeedback.selectionClick();
  }

  void _removeDrug(int index) {
    _updateState(() {
      _detecaoDrogas[index]['quantidade'].dispose();
      _detecaoDrogas[index]['especificar']?.dispose();
      _detecaoDrogas.removeAt(index);
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedIndividual() {
    _updateState(() {
      _detainedIndividuals.add(OccurrenceDynamicRows.detainedIndividual());
    });
    HapticFeedback.selectionClick();
  }

  void _addSeizedObject() {
    _updateState(() {
      _seizedObjects.add(OccurrenceDynamicRows.seizedObject());
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedVehicle() {
    _updateState(() {
      _detainedVehicles.add(OccurrenceDynamicRows.detainedVehicle());
    });
    HapticFeedback.selectionClick();
  }
}
