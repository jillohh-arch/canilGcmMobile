part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetAccessors on _DynamicActivitySheetState {
  bool get _isOccurrenceCategory {
    final category = widget.category.toLowerCase();
    return category == 'ocorrencia' || category == 'ocorrência';
  }

  /// Verdadeiro para Ocorrência e Evento: ambos usam _occCtrl para salvar.
  bool get _isOccurrenceOrEventCategory =>
      _isOccurrenceCategory || widget.category == 'Evento';

  String? _nonEmptyId(String? value) {
    final id = value?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String? get _initialOccurrenceDocumentId {
    return _nonEmptyId(widget.documentId) ??
        _nonEmptyId(widget.initialData?['id']?.toString());
  }

  String? get _activeIncidentDocumentId {
    return _nonEmptyId(_activeIncidentId) ?? _initialOccurrenceDocumentId;
  }

  bool get _hasActiveIncidentDocument => _activeIncidentDocumentId != null;

  bool get _isExistingOccurrence =>
      _isOccurrenceCategory && _initialOccurrenceDocumentId != null;

  bool get _hasActiveOccurrenceRecord =>
      _isExistingOccurrence || _hasActiveIncidentDocument;

  TextEditingController get _locationController => _isOccurrenceOrEventCategory
      ? _occCtrl.locationController
      : widget.category == 'Treino'
      ? _trainingCtrl.locationController
      : _locationCtrlOther;

  TextEditingController get _descriptionController =>
      _isOccurrenceOrEventCategory
      ? _occCtrl.descriptionController
      : widget.category == 'Treino'
      ? _trainingCtrl.descriptionController
      : widget.category == 'Rotina'
      ? _routineCtrl.descriptionController
      : _healthCtrl.descriptionController;

  TextEditingController get _timeController => _isOccurrenceOrEventCategory
      ? _occCtrl.timeController
      : widget.category == 'Treino'
      ? _trainingCtrl.timeController
      : widget.category == 'Rotina'
      ? _routineCtrl.timeController
      : _healthCtrl.timeController;

  TextEditingController get _durationController => widget.category == 'Treino'
      ? _trainingCtrl.durationController
      : widget.category == 'Rotina'
      ? _routineCtrl.durationController
      : _durationCtrlOther;

  TextEditingController get _tempController => _trainingCtrl.tempController;

  TextEditingController get _humidityController =>
      _trainingCtrl.humidityController;

  TextEditingController get _objetivoTreinoController =>
      _trainingCtrl.objetivoController;

  TextEditingController get _dificuldadesController =>
      _trainingCtrl.dificuldadesController;

  TextEditingController get _racaoMarcaController =>
      _routineCtrl.racaoMarcaController;

  TextEditingController get _racaoQtdController =>
      _routineCtrl.racaoQtdController;

  TextEditingController get _distanciaController =>
      _routineCtrl.distanciaController;

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

  TextEditingController get _naturezaOcorrenciaController =>
      _occCtrl.naturezaController;

  FocusNode get _occurrenceNatureFocusNode => _occCtrl.naturezaFocusNode;

  FocusNode get _occurrenceUpdateFocusNode => _occCtrl.updateFocusNode;

  TextEditingController get _occurrenceUpdateController =>
      _occCtrl.updateController;

  TextEditingController get _equipeController => _occCtrl.equipeController;

  TextEditingController get _boController => _occCtrl.boController;

  TextEditingController get _guarnicaoController =>
      _occCtrl.guarnicaoController;

  TextEditingController get _situacaoController => _occCtrl.situacaoController;

  TextEditingController get _desfechoController => _occCtrl.desfechoController;

  TextEditingController get _odorObjetoController =>
      _occCtrl.odorObjetoController;

  TextEditingController get _tempoDesaparecimentoController =>
      _occCtrl.tempoDesaparecimentoController;

  TextEditingController get _condicaoTerrenoController =>
      _occCtrl.condicaoTerrenoController;

  TextEditingController get _numeroOsController => _occCtrl.numeroOsController;

  TextEditingController get _publicoController => _occCtrl.publicoController;

  TextEditingController get _temaController => _occCtrl.temaController;

  List<Map<String, dynamic>> get _detecaoDrogas => _occCtrl.detecaoDrogas;

  List<Map<String, dynamic>> get _detainedIndividuals =>
      _occCtrl.detainedIndividuals;

  List<Map<String, dynamic>> get _seizedObjects => _occCtrl.seizedObjects;

  List<Map<String, dynamic>> get _detainedVehicles => _occCtrl.detainedVehicles;

  List<IncidentProgressUpdate> get _occurrenceTimeline => _occCtrl.timeline;

  Set<String> get _selectedOccurrenceOutcomes => _occCtrl.selectedOutcomes;

  LatLng? get _selectedLocationLatLng => _occCtrl.selectedLocationLatLng;

  String get _occurrenceStatus => _occCtrl.status;

  set _occurrenceStatus(String v) => _occCtrl.status = v;

  bool? get _occurrenceSuccessful => _occCtrl.successful;

  set _occurrenceSuccessful(bool? v) => _occCtrl.successful = v;

  bool get _showOccurrenceFinalization => _occCtrl.showFinalization;

  set _showOccurrenceFinalization(bool v) => _occCtrl.showFinalization = v;

  bool get _occurrenceFinishSubmitted => _occCtrl.finishSubmitted;

  set _occurrenceFinishSubmitted(bool v) => _occCtrl.finishSubmitted = v;

  String? get _activeIncidentId => _occCtrl.activeIncidentId;

  set _activeIncidentId(String? v) => _occCtrl.activeIncidentId = v;

  DateTime? get _activeOccurrenceStartedAt => _occCtrl.activeStartedAt;

  set _activeOccurrenceStartedAt(DateTime? v) => _occCtrl.activeStartedAt = v;

  bool get _showStartNatureEditor => _occCtrl.showStartNatureEditor;

  set _showStartNatureEditor(bool v) => _occCtrl.showStartNatureEditor = v;

  String? get _selectedOccurrenceUpdateTitle => _occCtrl.selectedUpdateTitle;

  set _selectedOccurrenceUpdateTitle(String? v) =>
      _occCtrl.selectedUpdateTitle = v;

  List<OccurrenceNature> get _occurrenceNatures => _occCtrl.natures;

  List<Map<String, dynamic>> get _currentCategoryCards {
    return ActivityCardCatalog.forCategory(widget.category);
  }
}
