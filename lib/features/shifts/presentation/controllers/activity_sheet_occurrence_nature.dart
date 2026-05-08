part of 'activity_sheet_occurrence_ctrl.dart';

extension ActivitySheetOccurrenceNature on ActivitySheetOccurrenceCtrl {
  // Natureza da ocorrência
  // -------------------------------------------------------------------------

  void _setNatureTextFromSelected() {
    if (_selectedNature == null) return;
    final n = _selectedOccurrenceNature();
    naturezaController.text = n?.label ?? _selectedNature!;
  }

  void syncNatureFromText() {
    final text = naturezaController.text.trim();
    if (text.isEmpty) {
      _selectedNature = null;
      return;
    }
    final normalized = OccurrenceNature.normalizeForSearch(text);
    final found = natures.cast<OccurrenceNature?>().firstWhere(
      (n) =>
          n != null &&
          (OccurrenceNature.normalizeForSearch(n.label) == normalized ||
              OccurrenceNature.normalizeForSearch(n.name) == normalized ||
              OccurrenceNature.normalizeForSearch(n.code) == normalized),
      orElse: () => null,
    );
    _selectedNature = found?.name ?? text;
  }

  OccurrenceNature? _selectedOccurrenceNature() {
    if (_selectedNature == null || _selectedNature!.trim().isEmpty) return null;
    final normalized = OccurrenceNature.normalizeForSearch(_selectedNature!);
    return natures.cast<OccurrenceNature?>().firstWhere(
      (n) =>
          n != null &&
          (OccurrenceNature.normalizeForSearch(n.name) == normalized ||
              OccurrenceNature.normalizeForSearch(n.label) == normalized),
      orElse: () => null,
    );
  }

  OccurrenceNature? get currentNature => _selectedOccurrenceNature();

  void selectNature(OccurrenceNature option) {
    _selectedNature = option.name;
    naturezaController.text = option.label;
    _formCtrl.selectNature(option.name);
    _copyFormCtrlToFields();
    onStateChanged();
  }

  void selectNatureById(String id) {
    _selectedNature = id;
    _setNatureTextFromSelected();
    _formCtrl.selectNature(id);
    _copyFormCtrlToFields();
    timeline.clear();
    selectedUpdateTitle = null;
    updateController.clear();
    onStateChanged();
  }

  Future<void> loadNatures() async {
    try {
      final remote = await IncidentService().getOccurrenceNatures();
      if (remote.isEmpty) return;
      natures = remote;
      _setNatureTextFromSelected();
      onStateChanged();
    } catch (e) {
      debugPrint('[OccurrenceCtrl] Erro ao carregar naturezas: $e');
    }
  }

  // -------------------------------------------------------------------------
}
