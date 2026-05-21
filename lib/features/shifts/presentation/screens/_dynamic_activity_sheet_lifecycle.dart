part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _DynamicActivitySheetLifecycle on _DynamicActivitySheetState {
  void _initActivityControllers() {
    _trainingCtrl = ActivitySheetTrainingCtrl(
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
    if (widget.category == 'Treino') {
      _trainingCtrl.init();
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
    _trainingCtrl.timeController.text = nowTime;
    _healthCtrl.timeController.text = nowTime;
    _timeCtrlOther.text = nowTime;
  }

  void _disposeActivityControllers() {
    _trainingCtrl.dispose();
    _healthCtrl.dispose();
  }

  void _disposeSheetResources() {
    _locationCtrlOther.dispose();
    _descriptionCtrlOther.dispose();
    _timeCtrlOther.dispose();
    _durationCtrlOther.dispose();
    MediaAttachmentRows.disposeAll(_mediaAttachments);
    _menuPageController.dispose();
  }
}
