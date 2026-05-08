part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateSave on _DailyTimelineScreenState {
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

    final updated = incident.copyWith(
      status: 'Em andamento',
      outcomes: selectedOutcomes.toList(),
      updatedAt: now,
      result: selectedOutcomes.isNotEmpty
          ? selectedOutcomes.first
          : incident.result,
      progressUpdates: _appendIncidentProgressUpdate(
        incident: incident,
        title: title,
        description: description,
        timestamp: now,
      ),
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

  List<IncidentProgressUpdate> _appendIncidentProgressUpdate({
    required Incident incident,
    required String title,
    required String description,
    required DateTime timestamp,
  }) {
    return List<IncidentProgressUpdate>.from(incident.progressUpdates)..add(
      _authoredIncidentUpdate(
        title: title,
        description: description,
        timestamp: timestamp,
        location: incident.location,
      ),
    );
  }
}
