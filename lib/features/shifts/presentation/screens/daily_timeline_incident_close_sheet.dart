part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseSheet on _DailyTimelineScreenState {
  Future<void> _showQuickCloseIncidentSheet({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = incident.outcomes.isNotEmpty
        ? <String>{...incident.outcomes}
        : _quickCloseDefaultOutcomesForSubtype(incident.type);
    var operationalSuccess = incident.operationalSuccess ?? true;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setModalState) {
              return _buildIncidentCloseSheetContent(
                sheetContext: sheetContext,
                incident: incident,
                noteController: noteController,
                selectedOutcomes: selectedOutcomes,
                operationalSuccess: operationalSuccess,
                onOperationalSuccessChanged: (value) {
                  HapticFeedback.selectionClick();
                  setModalState(() => operationalSuccess = value);
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
                onSave: () => _saveQuickCloseIncident(
                  incidentVM: incidentVM,
                  incident: incident,
                  noteController: noteController,
                  selectedOutcomes: selectedOutcomes,
                  operationalSuccess: operationalSuccess,
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

  Future<void> _saveQuickCloseIncident({
    required IncidentViewModel incidentVM,
    required Incident incident,
    required TextEditingController noteController,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) async {
    final now = DateTime.now();
    final updates = List<IncidentProgressUpdate>.from(incident.progressUpdates);
    final note = noteController.text.trim();

    updates.add(
      _authoredIncidentUpdate(
        title: 'Encerramento da ocorrência',
        description: note.isNotEmpty
            ? note
            : 'Ocorrência encerrada pela equipe.',
        timestamp: now,
        location: incident.location,
      ),
    );

    final closedIncident = incident.copyWith(
      status: 'Concluída',
      operationalSuccess: operationalSuccess,
      outcomes: selectedOutcomes.toList(),
      endedAt: now,
      updatedAt: now,
      result: _buildQuickCloseResultSummary(
        incident: incident,
        selectedOutcomes: selectedOutcomes,
        operationalSuccess: operationalSuccess,
      ),
      progressUpdates: updates,
    );

    await incidentVM.updateIncident(closedIncident);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ocorrência encerrada com sucesso.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
