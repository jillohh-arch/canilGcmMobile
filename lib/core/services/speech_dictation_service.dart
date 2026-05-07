import 'package:flutter/widgets.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechDictationService {
  final stt.SpeechToText _speech;

  SpeechDictationService([stt.SpeechToText? speech])
    : _speech = speech ?? stt.SpeechToText();

  Future<bool> start({
    required TextEditingController controller,
    required VoidCallback onListeningStarted,
    required VoidCallback onListeningStopped,
  }) async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          onListeningStopped();
        }
      },
      onError: (_) => onListeningStopped(),
    );
    if (!available) return false;

    onListeningStarted();
    var previousText = controller.text;
    if (previousText.isNotEmpty && !previousText.endsWith(' ')) {
      previousText += ' ';
    }

    _speech.listen(
      localeId: 'pt_BR',
      onResult: (result) {
        controller.text = previousText + result.recognizedWords;
      },
    );
    return true;
  }

  void stop() {
    _speech.stop();
  }
}
