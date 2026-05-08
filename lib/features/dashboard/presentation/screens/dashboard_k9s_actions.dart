part of 'dashboard_screen.dart';

extension _DashboardK9sTabActions on _K9sTabState {
  Future<void> _continueIncident(
    String dogId,
    String dogName,
    Incident incident,
  ) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(
          dogId: dogId,
          dogName: dogName,
          incident: incident,
        ),
      ),
    );
  }

  Future<void> _showQuickCloseIncidentSheet(
    Incident incident,
    String dogId,
    String dogName,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickCloseIncidentSheet(incident: incident),
    );
  }
}
