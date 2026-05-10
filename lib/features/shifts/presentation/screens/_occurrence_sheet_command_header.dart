part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetCommandHeader on _DynamicActivitySheetState {
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
