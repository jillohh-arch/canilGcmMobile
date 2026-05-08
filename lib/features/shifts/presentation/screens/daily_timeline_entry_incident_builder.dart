part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryIncidentBuilder on _DailyTimelineScreenState {
  _TimelineEntry _buildIncidentTimelineEntry(Incident incident) {
    final incidentTitle = _resolveIncidentTimelineTitle(incident);

    return _TimelineEntry(
      id: incident.id,
      category: 'Ocorrência',
      originalModel: incident,
      time: incident.date,
      title: 'OCORRÊNCIA: $incidentTitle',
      location: incident.location,
      type: 'Ocorrência',
      details: {
        'Resultado': incident.displayResult,
        'Status': incident.status,
        'Descrição': incident.description,
        if (incident.outcomes.isNotEmpty) '_outcomes': incident.outcomes,
        if (incident.progressUpdates.isNotEmpty)
          '_progressUpdates': incident.progressUpdates
              .map(
                (update) => {
                  'title': update.title,
                  'description': update.description,
                  'location': update.location,
                  'timestamp': update.timestamp,
                  'authorId': update.authorId,
                  'authorName': update.authorName,
                },
              )
              .toList(),
        if (incident.mediaAttachments != null &&
            incident.mediaAttachments!.isNotEmpty)
          '_mediaAttachments': incident.mediaAttachments,
      },
    );
  }
}
