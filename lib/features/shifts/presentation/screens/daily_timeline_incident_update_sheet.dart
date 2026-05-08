part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateSheet on _DailyTimelineScreenState {
  Future<void> _showUnifiedUpdateSheet({
    required Incident incident,
    required String dogId,
    required String dogName,
  }) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = <String>{...incident.outcomes};
    final shortcuts = _quickProgressShortcutsForSubtype(incident.type);
    String? selectedShortcut;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setModalState) {
              return _buildIncidentUpdateSheetContent(
                sheetContext: sheetContext,
                incident: incident,
                shortcuts: shortcuts,
                selectedShortcut: selectedShortcut,
                selectedOutcomes: selectedOutcomes,
                noteController: noteController,
                onShortcutSelected: (shortcut, isSelected) {
                  HapticFeedback.selectionClick();
                  setModalState(() {
                    if (isSelected) {
                      selectedShortcut = null;
                      noteController.clear();
                    } else {
                      selectedShortcut = shortcut.title;
                      noteController.text = shortcut.template;
                    }
                  });
                },
                onOutcomeSelected: (outcome, isSelected) {
                  HapticFeedback.selectionClick();
                  setModalState(() {
                    if (isSelected) {
                      selectedOutcomes.remove(outcome);
                    } else {
                      selectedOutcomes.add(outcome);
                    }
                  });
                },
                onSave: () => _saveIncidentUpdate(
                  incidentVM: incidentVM,
                  incident: incident,
                  selectedShortcut: selectedShortcut,
                  selectedOutcomes: selectedOutcomes,
                  noteController: noteController,
                ),
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }
}
