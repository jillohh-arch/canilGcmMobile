part of 'occurrence_close_wizard.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceCloseWizardFlow on _OccurrenceCloseWizardState {
  void _finish() {
    if (widget.isSaving) return;

    widget.onFinish({
      'report': _reportController.text.trim(),
      'results': _selectedResults.toList(),
      'details': _buildFinishDetails(),
    });
  }

  void _toggleResult(String label) {
    setState(() {
      if (label == 'Sem constatação') {
        if (_selectedResults.contains(label)) {
          _selectedResults.remove(label);
        } else {
          _selectedResults
            ..clear()
            ..add(label);
        }
        return;
      }

      _selectedResults.remove('Sem constatação');
      if (_selectedResults.contains(label)) {
        _selectedResults.remove(label);
      } else {
        _selectedResults.add(label);
      }
    });
  }

  TextEditingController _detailController(String key) {
    return _detailControllers.putIfAbsent(key, TextEditingController.new);
  }

  void _addDrugEntry() {
    setState(() => _drugEntries.add(_DrugEntry()));
  }

  void _updateDrugEntryType(_DrugEntry entry, String type) {
    setState(() => entry.type = type);
  }

  void _removeDrugEntry(int index) {
    setState(() {
      final removed = _drugEntries.removeAt(index);
      removed.dispose();
    });
  }
}
