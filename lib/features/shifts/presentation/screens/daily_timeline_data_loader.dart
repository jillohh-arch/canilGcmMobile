part of 'daily_timeline_screen.dart';

extension _DailyTimelineDataLoader on _DailyTimelineScreenState {
  void _loadTimelineDataForActiveShift() {
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) {
      return;
    }

    final dogId = shiftVM.activeDogId!;
    Provider.of<IncidentViewModel>(
      context,
      listen: false,
    ).fetchIncidentsForDog(dogId);
    Provider.of<TrainingViewModel>(
      context,
      listen: false,
    ).fetchTrainingsForDog(dogId);
    Provider.of<HealthViewModel>(
      context,
      listen: false,
    ).fetchHealthLogsForDog(dogId);
  }
}
