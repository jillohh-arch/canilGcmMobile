part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryData on _DailyTimelineScreenState {
  _TimelineListData _buildTimelineEntries(String dogId, {String? filterType}) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final rVM = Provider.of<RoutineViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final dogName = _resolveTimelineDogName(dogId, dogVM);
    final dayRange = _selectedTimelineDayRange();

    final trainings = tVM.trainings
        .where(
          (t) =>
              t.dogId == dogId &&
              _isWithinSelectedTimelineDay(t.date, dayRange),
        )
        .toList();

    final incidents = iVM.incidents
        .where(
          (i) =>
              i.dogId == dogId &&
              !i.isInProgress &&
              _isWithinSelectedTimelineDay(i.date, dayRange),
        )
        .toList();

    final healthLogs = hVM.healthLogs
        .where(
          (h) =>
              h.dogId == dogId &&
              _isWithinSelectedTimelineDay(h.date, dayRange),
        )
        .toList();

    final routines = rVM.routines
        .where(
          (r) =>
              r.dogId == dogId &&
              _isWithinSelectedTimelineDay(r.timestamp, dayRange),
        )
        .toList();

    List<_TimelineEntry> entries = [];

    // Include trainings/health only if not in Ocorrência-only tab
    if (filterType != 'Ocorrência') {
      for (var r in routines) {
        entries.add(_buildRoutineTimelineEntry(r, dogName));
      }

      for (var h in healthLogs) {
        entries.add(_buildHealthTimelineEntry(h, dogName));
      }

      for (var t in trainings) {
        if (_matchesSelectedTrainingFilter(t)) {
          entries.add(_buildTrainingTimelineEntry(t));
        }
      }
    }

    // Include incidents only if not in Training-only tab
    if (filterType != 'Training') {
      for (var i in incidents) {
        entries.add(_buildIncidentTimelineEntry(i));
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));

    final hasOpenIncidents =
        filterType == 'Ocorrência' &&
        iVM.incidents.any(
          (incident) => incident.dogId == dogId && incident.isInProgress,
        );

    return _TimelineListData(
      entries: entries,
      dogName: dogName,
      hasOpenIncidents: hasOpenIncidents,
    );
  }
}
