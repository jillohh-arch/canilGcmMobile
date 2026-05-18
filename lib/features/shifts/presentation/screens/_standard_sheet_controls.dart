part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _StandardSheetControls on _DynamicActivitySheetState {
  Widget _buildTopActionRow() {
    return QuickLocationActions(
      backgroundColor: _kHudBackground,
      gpsColor: _kHudAmber,
      timeColor: _kHudGreen,
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
    );
  }

  Widget _buildLocationTimeRow() {
    return ActivityLocationTimeFields(
      locationController: _locationController,
      timeController: _timeController,
      isHealth: widget.category == 'Saude',
    );
  }

  Widget _buildDescriptionField() {
    return ActivityDescriptionField(
      controller: _descriptionController,
      labelText: _descriptionLabel(),
      isListening: _isListening,
      onStartListening: _listen,
      onStopListening: _stopListening,
      onToggleListening: () {
        if (_isListening) {
          _stopListening();
        } else {
          _listen();
        }
      },
    );
  }

  String _descriptionLabel() {
    return ActivityFormLabels.descriptionLabel(
      category: widget.category,
      subtype: _selectedSubtype,
    );
  }

  Widget _buildSaveButton(Color tColor) {
    return ActivitySaveButton(
      accentColor: tColor,
      foregroundColor: _kHudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildPrimarySaveButton(Color tColor) {
    return ActivityPrimarySaveButton(
      accentColor: tColor,
      foregroundColor: _kHudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildSaveStatusPanel(Color accent) {
    return ActivitySaveStatusPanel(
      accentColor: accent,
      isSaving: _isSaving,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
    );
  }

  void _handlePrimarySave() {
    HapticFeedback.heavyImpact();
    _save();
  }

  Widget _buildTrackingAction({
    required String startLabel,
    required IconData startIcon,
    required Color backgroundColor,
    required Color foregroundColor,
    bool isLightMode = false,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    EdgeInsetsGeometry capturedMargin = EdgeInsets.zero,
  }) {
    final distance = _formData['_trackingDistance'];
    return ActivityTrackingAction(
      hasRoute: _formData.containsKey('_trackingRoute'),
      distanceMeters: distance is num ? distance : null,
      startLabel: startLabel,
      startIcon: startIcon,
      startBackgroundColor: backgroundColor,
      startForegroundColor: foregroundColor,
      padding: padding,
      capturedMargin: capturedMargin,
      onStart: () => _openLiveTracking(isLightMode: isLightMode),
    );
  }

  Widget _buildImageGallery() {
    return MediaAttachmentGallery(
      isCompressing: _isCompressing,
      showPdfAttachment: _selectedSubtype == ActivitySubtypeIds.exam,
      pdfName: _examePdfFile != null ? (_examePdfName ?? 'arquivo.pdf') : null,
      mediaAttachments: _mediaAttachments,
      activePhotoIndex: _activePhotoIndex,
      onPickImage: _pickImage,
      onPickPdf: _pickPdf,
      onRemovePdf: () => setState(() {
        _healthCtrl.examePdfFile = null;
        _healthCtrl.examePdfName = null;
      }),
      onSelectPhoto: (index) {
        setState(() => _activePhotoIndex = index);
        HapticFeedback.lightImpact();
      },
      onRemovePhoto: (index) {
        setState(() {
          MediaAttachmentRows.disposeCaption(_mediaAttachments[index]);
          _mediaAttachments.removeAt(index);
          if (_activePhotoIndex >= _mediaAttachments.length) {
            _activePhotoIndex = _mediaAttachments.length - 1;
          }
        });
        HapticFeedback.selectionClick();
      },
    );
  }

  Future<void> _pickPdf() async {
    final result = await const PdfAttachmentService().pickPdf();
    if (result != null) {
      setState(() {
        _healthCtrl.examePdfFile = result.file;
        _healthCtrl.examePdfName = result.name;
      });
      HapticFeedback.lightImpact();
    }
  }

  String _saveButtonLabel() {
    return ActivityFormLabels.saveButtonLabel(
      category: widget.category,
      occurrenceStatus: _occurrenceStatus,
    );
  }

  Future<void> _openLiveTracking({bool isLightMode = false}) async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTrackingScreen(isLightMode: isLightMode),
      ),
    );

    if (result == null || result is! Map || !mounted) return;

    final distanceMeters = result['distanceMeters'];
    final durationSeconds = result['durationSeconds'];

    setState(() {
      _formData['_trackingRoute'] = result['route'];
      _formData['_trackingDistance'] = distanceMeters;
      if (durationSeconds is num) {
        _durationController.text = (durationSeconds / 60).floor().toString();
      }
      if (distanceMeters is num) {
        _formData['_trackingDistanceKm'] =
            (distanceMeters / 1000).toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rastreamento finalizado. Distância e tempo calculados.'),
        backgroundColor: Color(0xFF1B8A4C),
      ),
    );
  }

  void _setFormDataValue(String label, String? value) {
    setState(() {
      if (value == null) {
        _formData.remove(label);
      } else {
        _formData[label] = value;
      }
    });
  }
}
