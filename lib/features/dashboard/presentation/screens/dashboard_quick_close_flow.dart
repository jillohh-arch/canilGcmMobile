part of 'dashboard_screen.dart';

extension _QuickCloseIncidentFlow on _QuickCloseIncidentSheetState {
  Future<void> _closeIncident() async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final now = DateTime.now();
    final updates = _buildProgressUpdates(now);

    final closedIncident = _incident.copyWith(
      status: 'Concluída',
      operationalSuccess: _operationalSuccess,
      outcomes: _selectedOutcomes.toList(),
      endedAt: now,
      updatedAt: now,
      result: _buildQuickCloseResultSummary(
        selectedOutcomes: _selectedOutcomes,
        operationalSuccess: _operationalSuccess,
      ),
      progressUpdates: updates,
    );

    await incidentVM.updateIncident(closedIncident);
    if (!mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ocorrência encerrada com sucesso.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  List<IncidentProgressUpdate> _buildProgressUpdates(DateTime timestamp) {
    final updates = List<IncidentProgressUpdate>.from(
      _incident.progressUpdates,
    );
    final note = _noteController.text.trim();

    if (note.isEmpty) return updates;

    updates.add(
      IncidentProgressUpdate(
        title: 'Encerramento da ocorrência',
        description: note,
        timestamp: timestamp,
        location: _incident.location,
      ),
    );
    return updates;
  }
}
