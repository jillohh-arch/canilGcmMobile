part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentDefaultOutcomes on _DailyTimelineScreenState {
  Set<String> _quickCloseDefaultOutcomesForSubtype(String? subtype) {
    switch (subtype) {
      case 'supportVehicle':
      case 'serviceOrder':
      case 'event':
      case 'other':
        return {'Apoio prestado'};
      default:
        return <String>{};
    }
  }
}
