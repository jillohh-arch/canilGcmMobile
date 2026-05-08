part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetActions on _DynamicActivitySheetState {
  void _disposeDynamicResultRows(
    List<Map<String, dynamic>> rows,
    List<String> controllerKeys,
  ) {
    OccurrenceDynamicRows.disposeRows(rows, controllerKeys);
  }

  void _replaceDynamicRows(
    List<Map<String, dynamic>> target,
    List<String> controllerKeys,
    List<Map<String, dynamic>> nextRows,
  ) {
    _disposeDynamicResultRows(target, controllerKeys);
    target
      ..clear()
      ..addAll(nextRows);
  }

  void _selectSubtype(String type, {String? imagePath}) {
    HapticFeedback.lightImpact();
    _updateState(() {
      _selectedSubtype = type;
      if (_isOccurrenceCategory) {
        _setOccurrenceNatureTextFromSelected();
      }
      _selectedSubtypeImagePath =
          imagePath ?? 'assets/images/k9_tactical_background.png';
      _formData.clear();
      if (_isOccurrenceCategory) {
        _occCtrl.status = OccurrenceFormController.statusCompleted;
        _occCtrl.successful = true;
        _occCtrl.selectNatureById(type);
        _copyOccurrenceControllerToFields();
        _occurrenceTimeline.clear();
        _selectedOccurrenceUpdateTitle = null;
        _occurrenceUpdateController.clear();
      }
      _showMenu = false;
    });
  }

  Future<void> _fetchCurrentAddress() async {
    try {
      HapticFeedback.lightImpact();
      final location = await const LocationResolutionService()
          .currentHighAccuracy();
      _updateState(() {
        _locationController.text = location.address;
        _occCtrl.selectedLocationLatLng = location.point;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao obter endereço: $e')));
      }
    }
  }

  Future<void> _selectOccurrenceLocation(LatLng point) async {
    _updateState(() => _occCtrl.selectedLocationLatLng = point);
    final address = await const LocationResolutionService().addressForPoint(
      point,
    );
    if (address.isNotEmpty) {
      _updateState(() => _locationController.text = address);
    }
  }

  void _setTimeToNow() {
    _updateState(() {
      _timeController.text = _formatTimeOfDay(DateTime.now());
    });
    HapticFeedback.selectionClick();
  }

  void _addDrug() {
    _updateState(() {
      _detecaoDrogas.add(OccurrenceDynamicRows.drug());
    });
    HapticFeedback.selectionClick();
  }

  void _removeDrug(int index) {
    _updateState(() {
      _detecaoDrogas[index]['quantidade'].dispose();
      _detecaoDrogas[index]['especificar']?.dispose();
      _detecaoDrogas.removeAt(index);
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedIndividual() {
    _updateState(() {
      _detainedIndividuals.add(OccurrenceDynamicRows.detainedIndividual());
    });
    HapticFeedback.selectionClick();
  }

  void _addSeizedObject() {
    _updateState(() {
      _seizedObjects.add(OccurrenceDynamicRows.seizedObject());
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedVehicle() {
    _updateState(() {
      _detainedVehicles.add(OccurrenceDynamicRows.detainedVehicle());
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pullCurrentWeather() async {
    try {
      HapticFeedback.lightImpact();
      final weather = await const WeatherCaptureService().currentWeather();
      if (weather != null) {
        _updateState(() {
          _tempController.text = weather.temperature.toString();
          _humidityController.text = weather.humidity.toString();
          if (_condicaoTerrenoController.text.isEmpty) {
            _condicaoTerrenoController.text = weather.terrainSummary;
          }
        });
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clima atualizado com sucesso!'),
              backgroundColor: Color(0xFF1B8A4C),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao coletar clima: $e')));
      }
    }
  }

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

  Future<List<Map<String, dynamic>>> _uploadAllMedia(String folder) async {
    if (_mediaAttachments.isEmpty) return const [];

    if (mounted) {
      _updateState(() {
        _saveStatus = 'Fazendo upload de mídias...';
      });
    }

    return _occCtrl.uploadAllMedia(
      attachments: _mediaAttachments,
      folder: folder,
      onUploading: _markMediaUploading,
      onUploaded: _markMediaUploaded,
      onPending: _markMediaPending,
    );
  }

  List<Map<String, dynamic>> _mergeExistingIncidentMedia(
    List<Map<String, dynamic>> uploadedMedia,
  ) {
    return MediaAttachmentRows.mergeExistingWithUploaded(
      existing: widget.initialData?['mediaAttachments'],
      uploaded: uploadedMedia,
    );
  }

  DateTime _resolveFormTimestamp() {
    final baseTimestamp = widget.initialData?['_rawDate'] ?? DateTime.now();
    return const PtBrDateTimeService().withTimeText(
      base: baseTimestamp,
      timeText: _timeController.text,
    );
  }
}
