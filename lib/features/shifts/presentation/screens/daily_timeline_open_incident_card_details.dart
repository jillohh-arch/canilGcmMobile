part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentCardDetails on _DailyTimelineScreenState {
  List<Widget> _buildOpenIncidentDetails(Incident incident) {
    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last
        : null;

    return [
      _buildOpenIncidentStats(incident),
      ..._buildOpenIncidentOutcomeBadges(incident),
      if (latestUpdate != null) ...[
        const SizedBox(height: 12),
        _buildIncidentLatestUpdateCard(
          incident: incident,
          latestUpdate: latestUpdate,
        ),
      ],
    ];
  }
}
