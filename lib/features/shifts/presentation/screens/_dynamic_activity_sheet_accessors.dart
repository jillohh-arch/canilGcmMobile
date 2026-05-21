part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetAccessors on _DynamicActivitySheetState {
  TextEditingController get _locationController {
    if (widget.category == 'Treino') return _trainingCtrl.locationController;
    if (widget.category == 'Saude') return _healthCtrl.clinicaController;
    return _locationCtrlOther;
  }

  TextEditingController get _descriptionController {
    if (widget.category == 'Treino') return _trainingCtrl.descriptionController;
    if (widget.category == 'Saude') return _healthCtrl.descriptionController;
    return _descriptionCtrlOther;
  }

  TextEditingController get _timeController {
    if (widget.category == 'Treino') return _trainingCtrl.timeController;
    if (widget.category == 'Saude') return _healthCtrl.timeController;
    return _timeCtrlOther;
  }

  TextEditingController get _durationController {
    if (widget.category == 'Treino') return _trainingCtrl.durationController;
    return _durationCtrlOther;
  }

  TextEditingController get _tempController => _trainingCtrl.tempController;

  TextEditingController get _humidityController =>
      _trainingCtrl.humidityController;

  TextEditingController get _objetivoTreinoController =>
      _trainingCtrl.objetivoController;

  TextEditingController get _dificuldadesController =>
      _trainingCtrl.dificuldadesController;

  TextEditingController get _vetNameController => _healthCtrl.vetNameController;

  TextEditingController get _motivoController => _healthCtrl.motivoController;

  TextEditingController get _tipoVacinaController =>
      _healthCtrl.tipoVacinaController;

  TextEditingController get _tipoExameController =>
      _healthCtrl.tipoExameController;

  TextEditingController get _produtosBanhoController =>
      _healthCtrl.produtosBanhoController;

  TextEditingController get _returnDateController =>
      _healthCtrl.returnDateController;

  String? get _selectedVacina => _healthCtrl.selectedVacina;

  File? get _examePdfFile => _healthCtrl.examePdfFile;

  String? get _examePdfName => _healthCtrl.examePdfName;

  List<Map<String, dynamic>> get _currentCategoryCards {
    return ActivityCardCatalog.forCategory(widget.category);
  }
}
