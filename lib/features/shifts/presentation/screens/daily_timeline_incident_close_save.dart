part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseSave on _DailyTimelineScreenState {
  Future<void> _saveQuickCloseIncident({
    required IncidentViewModel incidentVM,
    required Incident incident,
    required TextEditingController noteController,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) async {
    final now = DateTime.now();
    final note = noteController.text.trim();

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
      progressUpdates: _appendIncidentProgressUpdate(
        incident: incident,
        title: 'Encerramento da ocorrência',
        description: note.isNotEmpty
            ? note
            : 'Ocorrência encerrada pela equipe.',
        timestamp: now,
      ),
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
