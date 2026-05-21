part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetMediaActions on _DynamicActivitySheetState {
  Future<void> _pickImage() async {
    if (mounted) {
      _updateState(() => _isCompressing = true);
    }

    final compressedImages = await const MediaProcessingService()
        .pickAndCompressImages();
    if (compressedImages.isNotEmpty) {
      _updateState(() {
        for (final file in compressedImages) {
          _mediaAttachments.add(MediaAttachmentRows.pendingPhoto(file));
        }
        _isCompressing = false;
      });
      HapticFeedback.lightImpact();
    } else if (mounted) {
      _updateState(() => _isCompressing = false);
    }
  }

  Future<void> _listen() async {
    if (_isListening) {
      _stopListening();
      return;
    }

    final started = await _speechDictation.start(
      controller: _descriptionController,
      onListeningStarted: () {
        _updateState(() => _isListening = true);
      },
      onListeningStopped: () {
        _updateState(() => _isListening = false);
      },
    );
    if (started) {
      HapticFeedback.lightImpact();
    }
  }

  void _stopListening() {
    if (_isListening) {
      _updateState(() => _isListening = false);
      _speechDictation.stop();
      HapticFeedback.selectionClick();
    }
  }
}
