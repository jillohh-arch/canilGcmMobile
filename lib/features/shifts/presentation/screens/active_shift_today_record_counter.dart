part of 'active_shift_dashboard_screen.dart';

int _countTodayRecords(BuildContext context, String dogId) {
  final healthLogs = Provider.of<HealthViewModel>(context).healthLogs;
  final trainings = Provider.of<TrainingViewModel>(context).trainings;
  final incidents = Provider.of<IncidentViewModel>(context).incidents;
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final healthCount = healthLogs.where((log) {
    return log.dogId == dogId && _isTodayRecord(log.date, startOfDay, endOfDay);
  }).length;
  final trainingCount = trainings.where((training) {
    return training.dogId == dogId &&
        _isTodayRecord(training.date, startOfDay, endOfDay);
  }).length;
  final incidentCount = incidents.where((incident) {
    return incident.dogId == dogId &&
        _isTodayRecord(incident.date, startOfDay, endOfDay);
  }).length;

  return healthCount + trainingCount + incidentCount;
}
