part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryRoutineHealthBuilders
    on _DailyTimelineScreenState {
  _TimelineEntry _buildRoutineTimelineEntry(
    RoutineModel routine,
    String dogName,
  ) {
    return _TimelineEntry(
      id: routine.id,
      category: 'Rotina',
      originalModel: routine,
      time: routine.timestamp,
      title: 'ROTINA: ${routine.activityType}',
      location: routine.dogName.isNotEmpty ? routine.dogName : dogName,
      type: 'Rotina',
      details: {
        'Status': routine.status,
        'Notas': routine.notes,
        if (routine.mediaAttachments != null &&
            routine.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': routine.mediaAttachments,
        ...?routine.metadata,
      },
    );
  }

  _TimelineEntry _buildHealthTimelineEntry(
    HealthLogModel healthLog,
    String dogName,
  ) {
    final healthTitle = _resolveHealthTimelineTitle(healthLog);

    return _TimelineEntry(
      id: healthLog.id,
      category: 'Saude',
      originalModel: healthLog,
      time: healthLog.date,
      title: 'SAÚDE: $healthTitle',
      location: healthLog.dogName.isNotEmpty ? healthLog.dogName : dogName,
      type: 'Saude',
      details: {
        if (healthLog.weight != null) 'Peso': '${healthLog.weight} kg',
        if (healthLog.vaccines.isNotEmpty)
          'Vacinas': healthLog.vaccines.join(', '),
        'Observações': healthLog.healthObservations,
        if (healthLog.vetName != null && healthLog.vetName!.isNotEmpty)
          'Veterinário': healthLog.vetName,
        if (healthLog.mediaAttachments != null &&
            healthLog.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': healthLog.mediaAttachments,
      },
    );
  }
}
