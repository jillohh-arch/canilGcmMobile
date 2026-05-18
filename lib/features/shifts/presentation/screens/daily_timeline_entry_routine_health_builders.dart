part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryHealthBuilders
    on _DailyTimelineScreenState {
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
