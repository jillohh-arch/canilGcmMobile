part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentsData on _DailyTimelineScreenState {
  List<Incident> _openIncidentsForDog(String dogId) {
    final incidentVM = Provider.of<IncidentViewModel>(context);

    return incidentVM.incidents
        .where((incident) => incident.dogId == dogId && incident.isInProgress)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}
