part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _DynamicActivitySheetLifecycle on _DynamicActivitySheetState {
  void _initActivityControllers() {
    _occCtrl = ActivitySheetOccurrenceCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: _notifySheetStateChanged,
    );
    _trainingCtrl = ActivitySheetTrainingCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: _notifySheetStateChanged,
    );
    _routineCtrl = ActivitySheetRoutineCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: _notifySheetStateChanged,
    );
    _healthCtrl = ActivitySheetHealthCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: _notifySheetStateChanged,
    );
  }

  void _notifySheetStateChanged() {
    if (mounted) setState(() {});
  }

  void _initSelectedActivityController() {
    if (_isOccurrenceCategory) {
      _occCtrl.init();
    } else if (widget.category == 'Treino') {
      _trainingCtrl.init();
    } else if (widget.category == 'Rotina') {
      _routineCtrl.init();
    } else if (widget.category == 'Saude') {
      _healthCtrl.init();
    }
  }

  void _initMenuPager() {
    _menuPageController = PageController(viewportFraction: 0.80);
    _menuPageController.addListener(() {
      final page = _menuPageController.page?.round();
      if (page != null && page != _currentMenuPage) {
        setState(() => _currentMenuPage = page);
      }
    });
  }

  void _primeNewRecordTime() {
    if (widget.initialData != null) return;

    final nowTime = _formatTimeOfDay(DateTime.now());
    _occCtrl.timeController.text = nowTime;
    _trainingCtrl.timeController.text = nowTime;
    _routineCtrl.timeController.text = nowTime;
    _healthCtrl.timeController.text = nowTime;
  }

  void _scheduleOccurrenceStartContext() {
    if (widget.initialData != null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoPrimeOccurrenceStart) return;
      _didAutoPrimeOccurrenceStart = true;
      _setTimeToNow();
      _fetchCurrentAddress();
    });
  }

  void _disposeActivityControllers() {
    _occCtrl.dispose();
    _trainingCtrl.dispose();
    _routineCtrl.dispose();
    _healthCtrl.dispose();
  }

  void _disposeSheetResources() {
    _locationCtrlOther.dispose();
    _durationCtrlOther.dispose();
    MediaAttachmentRows.disposeAll(_mediaAttachments);
    _menuPageController.dispose();
  }
}
