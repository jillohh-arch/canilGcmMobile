part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetContext on _DynamicActivitySheetState {
  Widget _buildOccurrenceStartScreenV2(Color tColor) {
    final dogVM = Provider.of<DogViewModel>(context);
    dynamic activeDog;
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        activeDog = dog;
        break;
      }
    }

    final dogName = widget.dogName.isNotEmpty
        ? widget.dogName
        : (activeDog?.name?.toString() ?? 'K9');
    final imageUrl = activeDog?.profileImageUrl?.toString();
    final locationLabel = _locationController.text.trim().isEmpty
        ? 'Capturando localização...'
        : _locationController.text.trim();
    final timeLabel = _timeController.text.trim().isEmpty
        ? '--:--'
        : _timeController.text.trim();
    final dateLabel = _formatDatePtBr(DateTime.now());
    final natureText = _naturezaOcorrenciaController.text.trim();

    return OccurrenceStartScreen(
      accentColor: tColor,
      panelColor: _kHudPanel,
      dogName: dogName,
      dogImageUrl: imageUrl,
      locationLabel: locationLabel,
      timeLabel: timeLabel,
      dateLabel: dateLabel,
      natureText: natureText,
      showNatureEditor: _showStartNatureEditor,
      natureEditor: _buildOccurrenceNatureOnlyEditor(),
      onRefreshLocation: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onRefreshTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onToggleNatureEditor: () =>
          setState(() => _showStartNatureEditor = !_showStartNatureEditor),
    );
  }

  Widget _buildOccurrenceNatureOnlyEditor() {
    return OccurrenceNatureSearch(
      controller: _naturezaOcorrenciaController,
      focusNode: _occurrenceNatureFocusNode,
      natures: _occurrenceNatures,
      panelColor: _kHudPanel,
      accent: _kHudCyan,
      onChanged: (_) => setState(_syncSelectedOccurrenceNatureFromText),
      onSelected: _selectOccurrenceNature,
      fieldBuilder: (context, controller, focusNode, onChanged) {
        return TacticalTextField(
          controller: controller,
          focusNode: focusNode,
          labelText: 'Natureza da ocorrência',
          prefixIcon: Icons.category_rounded,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search_rounded, color: _kHudCyan, size: 18),
            onPressed: () => focusNode.requestFocus(),
          ),
          onChanged: onChanged,
        );
      },
    );
  }

  Widget _buildOccurrenceInitialDataPanel(Color tColor) {
    return OccurrenceInitialDataPanel(
      accentColor: tColor,
      panelColor: _kHudPanel,
      natureStep: _buildOccurrenceNatureStep(),
      locationBlock: _buildOccurrenceCompactLocationBlock(tColor),
    );
  }

  Widget _buildOccurrenceActiveContextSummary(Color tColor) {
    final startedAt = _occurrenceStartedAt() ?? _resolveFormTimestamp();
    final startedLabel = _formatTimeOfDay(startedAt);
    final location = _locationController.text.trim().isEmpty
        ? 'Local pendente'
        : _locationController.text.trim();
    final team = _equipeController.text.trim().isEmpty
        ? 'Equipe pendente'
        : _equipeController.text.trim();

    return OccurrenceActiveContextSummary(
      accentColor: tColor,
      panelColor: _kHudPanel,
      backgroundColor: _kHudBackground,
      location: location,
      team: team,
      startedLabel: startedLabel,
      onEdit: () => _showOccurrenceInitialDataSheet(tColor),
    );
  }

  Future<void> _showOccurrenceInitialDataSheet(Color tColor) async {
    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceInitialDataSheet(
          accentColor: tColor,
          backgroundColor: _kHudBackground,
          child: _buildOccurrenceInitialDataPanel(tColor),
          onDone: () {
            setState(() {});
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildOccurrenceCompactLocationBlock(Color tColor) {
    return OccurrenceCompactLocationBlock(
      hasLocation: _locationController.text.trim().isNotEmpty,
      showMapAdjust: _selectedLocationLatLng != null,
      gpsColor: _kHudAmber,
      timeColor: _kHudGreen,
      accentColor: tColor,
      locationField: TacticalTextField(
        controller: _locationController,
        labelText: 'Endereço / Local',
        prefixIcon: Icons.location_on_rounded,
      ),
      timeField: TacticalTextField(
        controller: _timeController,
        labelText: 'Hora de início',
        prefixIcon: Icons.schedule_rounded,
        readOnly: true,
      ),
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onAdjustMap: _showOccurrenceLocationMapSheet,
    );
  }

  Future<void> _showOccurrenceLocationMapSheet() async {
    final location = _selectedLocationLatLng;
    if (location == null) return;

    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceLocationMapSheet(
          location: location,
          accentColor: _kHudCyan,
          backgroundColor: _kHudBackground,
          onLocationChanged: _selectOccurrenceLocation,
        );
      },
    );
  }

  dynamic _activeDogFrom(DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        return dog;
      }
    }
    return null;
  }

  dynamic _operatorUserFrom({
    required UserViewModel userVM,
    required String currentRa,
  }) {
    for (final user in userVM.users) {
      if (user.ra == currentRa) {
        return user;
      }
    }
    return null;
  }

  Widget _buildOccurrenceCommandHeader(
    Color tColor, {
    bool showOperationalMetrics = false,
  }) {
    final status = _occurrenceStatus;
    final startedAt = _occurrenceStartedAt();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);
    final activeDog = _activeDogFrom(dogVM);
    final currentUser = _operatorUserFrom(
      userVM: userVM,
      currentRa: operatorContext.ra,
    );

    return OccurrenceCommandHeader(
      nature: OccurrenceDisplayText.headerNatureLabel(
        selectedSubtype: _selectedSubtype,
        manualNature: _naturezaOcorrenciaController.text,
      ),
      status: status,
      dogName: widget.dogName,
      operatorName: operatorContext.name,
      elapsedLabel: OccurrenceDisplayText.elapsedLabel(startedAt),
      eventCount: showOperationalMetrics ? _occurrenceTimeline.length : null,
      showOperationalMetrics: showOperationalMetrics,
      dogImageUrl: activeDog?.profileImageUrl?.toString(),
      operatorImageUrl: currentUser?.photoUrl?.toString(),
      accent: tColor,
      statusColor: status == OccurrenceFormController.statusCanceled
          ? _kHudRed
          : _kHudGreen,
      onBack: _isSaving ? null : () => _closeForm(false),
    );
  }

  DateTime? _occurrenceStartedAt() {
    if (_activeOccurrenceStartedAt != null) return _activeOccurrenceStartedAt;
    final data = widget.initialData;
    if (data == null) return null;
    final startedAt = data['startedAt'];
    if (startedAt != null) {
      return parseFirestoreDate(startedAt);
    }
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) return rawDate;
    return null;
  }
}
