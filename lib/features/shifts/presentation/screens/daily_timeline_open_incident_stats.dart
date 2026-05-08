part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentStats on _DailyTimelineScreenState {
  Widget _buildOpenIncidentStats(Incident incident) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildOpenIncidentStat(
          icon: Icons.schedule_rounded,
          label: 'Aberta',
          value: _formatIncidentRelative(incident.startedAt),
        ),
        _buildOpenIncidentStat(
          icon: Icons.update_rounded,
          label: 'Atualizada',
          value: _formatIncidentTimestamp(incident.updatedAt),
        ),
        if (incident.outcomes.isNotEmpty)
          _buildOpenIncidentStat(
            icon: Icons.fact_check_rounded,
            label: 'Resultados',
            value: '${incident.outcomes.length} marcados',
          ),
      ],
    );
  }
}
