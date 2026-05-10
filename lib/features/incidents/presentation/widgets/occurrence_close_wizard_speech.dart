part of 'occurrence_close_wizard.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceCloseWizardSpeech on _OccurrenceCloseWizardState {
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
}
