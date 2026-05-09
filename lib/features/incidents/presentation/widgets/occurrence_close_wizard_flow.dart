part of 'occurrence_close_wizard.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceCloseWizardFlow on _OccurrenceCloseWizardState {
  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() => _speechReady = ready);
  }

  Future<void> _toggleNarration() async {
    if (widget.isSaving) return;

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechReady) await _initSpeech();
    if (!_speechReady) {
      if (!mounted) return;
      _showMessage('Não foi possível iniciar a narração por voz.');
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'pt_BR',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        setState(() {
          _reportController.text = words;
          _reportController.selection = TextSelection.collapsed(
            offset: _reportController.text.length,
          );
        });
      },
    );
  }

  void _nextStep() {
    if (widget.isSaving) return;

    if (_currentStep == 0 && _reportController.text.trim().isEmpty) {
      _showMessage('Informe o relato final ou use a narração por voz.');
      return;
    }
    if (_currentStep == 1 && _selectedResults.isEmpty) {
      _showMessage('Selecione pelo menos um resultado da ocorrência.');
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      return;
    }
    _finish();
  }

  void _previousStep() {
    if (widget.isSaving) return;

    if (_currentStep == 0) {
      widget.onCancel();
      return;
    }
    setState(() => _currentStep--);
  }

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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Widget _buildNavigation() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: widget.isSaving ? null : _previousStep,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Colors.white70,
              side: BorderSide(
                color: _OccurrenceCloseWizardState._cyan.withAlpha(70),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _currentStep == 0 ? 'CANCELAR' : 'VOLTAR',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: widget.isSaving ? null : _nextStep,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
              backgroundColor: _currentStep == 2
                  ? _OccurrenceCloseWizardState._red
                  : _OccurrenceCloseWizardState._cyan,
              foregroundColor: _currentStep == 2
                  ? Colors.white
                  : _OccurrenceCloseWizardState._bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              _currentStep == 2 ? 'CONCLUIR OCORRÊNCIA' : 'PRÓXIMO',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
