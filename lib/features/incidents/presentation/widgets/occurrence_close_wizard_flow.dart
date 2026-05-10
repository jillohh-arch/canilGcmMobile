part of 'occurrence_close_wizard.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceCloseWizardFlow on _OccurrenceCloseWizardState {
  void _finish() {
    if (widget.isSaving) return;

    final details = <String, dynamic>{};
    _detailControllers.forEach((key, controller) {
      details[key] = controller.text.trim();
    });
    if (_selectedResults.contains('Droga apreendida')) {
      final drugs = _drugEntries
          .map(
            (entry) => {
              'tipo': entry.type,
              'quantidade': entry.quantityController.text.trim(),
            },
          )
          .where(
            (entry) =>
                entry['tipo']!.trim().isNotEmpty ||
                entry['quantidade']!.trim().isNotEmpty,
          )
          .toList();
      details['drogas'] = drugs;
      if (drugs.isNotEmpty) {
        details['droga_tipo'] = drugs.first['tipo'];
        details['droga_quantidade'] = drugs.first['quantidade'];
      }
    }

    widget.onFinish({
      'report': _reportController.text.trim(),
      'results': _selectedResults.toList(),
      'details': details,
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

  InputDecoration _fieldDecoration({
    required String hint,
    IconData? icon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.white38),
      counterStyle: GoogleFonts.robotoMono(color: Colors.white38, fontSize: 9),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: _OccurrenceCloseWizardState._cyan, size: 18),
      suffixText: suffixText,
      suffixStyle: GoogleFonts.robotoMono(
        color: _OccurrenceCloseWizardState._cyan,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
      filled: true,
      fillColor: const Color(0xFF0A1322),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: _OccurrenceCloseWizardState._cyan.withAlpha(55),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: _OccurrenceCloseWizardState._cyan,
          width: 1.4,
        ),
      ),
    );
  }
}
