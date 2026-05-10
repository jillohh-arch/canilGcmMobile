part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetHydration on _DynamicActivitySheetState {
  void _populateEditData() {
    final d = widget.initialData!;
    _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';
    _populateEditTimestamp(d);

    if (widget.category == 'Treino') {
      _populateTrainingEditData(d);
    } else if (widget.category == 'Rotina') {
      _populateRoutineEditData(d);
    } else if (_isOccurrenceCategory || widget.category == 'Evento') {
      _populateOccurrenceEditData(d);
    } else if (widget.category == 'Saude') {
      _populateHealthEditData(d);
    }

    _applySelectedSubtypeImage();
  }

  void _populateEditTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      _timeController.text = _formatTimeOfDay(rawDate);
    }
  }

  void _populateTrainingEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _trainingCtrl.init()
    _selectedSubtype = data['trainingType'];
  }

  void _populateRoutineEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _routineCtrl.init()
    _selectedSubtype = data['activityType'];
  }

  void _populateHealthEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _healthCtrl.init()
    _selectedSubtype = data['logType'];
  }

  void _applySelectedSubtypeImage() {
    final cardImage = ActivityCardCatalog.imageFor(
      category: widget.category,
      id: _selectedSubtype,
    );
    if (cardImage != null) {
      _selectedSubtypeImagePath = cardImage;
    }
  }
}
