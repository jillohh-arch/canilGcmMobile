part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentOutcomeBadges on _DailyTimelineScreenState {
  List<Widget> _buildOpenIncidentOutcomeBadges(Incident incident) {
    if (incident.outcomes.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: incident.outcomes
            .map(
              (outcome) => _buildIncidentBadge(
                label: outcome,
                style: _resolveIncidentOutcomeBadgeStyle(outcome),
              ),
            )
            .toList(),
      ),
    ];
  }
}
