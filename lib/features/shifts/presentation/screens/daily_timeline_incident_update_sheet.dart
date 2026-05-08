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

  Future<void> _saveIncidentUpdate({
    required IncidentViewModel incidentVM,
    required Incident incident,
    required String? selectedShortcut,
    required Set<String> selectedOutcomes,
    required TextEditingController noteController,
  }) async {
    final note = noteController.text.trim();
    if (selectedShortcut == null && note.isEmpty && selectedOutcomes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione uma etapa, desfecho ou descreva o andamento.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final title =
        selectedShortcut ??
        (selectedOutcomes.isNotEmpty
            ? selectedOutcomes.first
            : 'Atualização operacional');
    final description = note.isNotEmpty
        ? note
        : selectedOutcomes.isNotEmpty
        ? 'Desfechos: ${selectedOutcomes.join(', ')}.'
        : 'Andamento registrado.';

    final updates = List<IncidentProgressUpdate>.from(incident.progressUpdates)
      ..add(
        _authoredIncidentUpdate(
          title: title,
          description: description,
          timestamp: now,
          location: incident.location,
        ),
      );

    final updated = incident.copyWith(
      status: 'Em andamento',
      outcomes: selectedOutcomes.toList(),
      updatedAt: now,
      result: selectedOutcomes.isNotEmpty
          ? selectedOutcomes.first
          : incident.result,
      progressUpdates: updates,
    );

    await incidentVM.updateIncident(updated);
    if (!mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ocorrência atualizada.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
