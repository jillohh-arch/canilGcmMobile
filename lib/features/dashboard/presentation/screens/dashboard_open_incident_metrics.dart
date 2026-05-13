part of 'dashboard_screen.dart';

class _OpenIncidentMetrics extends StatelessWidget {
  final Incident incident;

  const _OpenIncidentMetrics({required this.incident});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _IncidentDashboardPill(
          icon: Icons.schedule_rounded,
          label: 'Aberta',
          value: _formatDashboardIncidentRelative(incident.startedAt),
        ),
        _IncidentDashboardPill(
          icon: Icons.update_rounded,
          label: 'Atualizada',
          value: _formatDashboardIncidentTimestamp(incident.updatedAt),
        ),
        if (incident.outcomes.isNotEmpty)
          _IncidentDashboardPill(
            icon: Icons.fact_check_rounded,
            label: 'Resultados',
            value: '${incident.outcomes.length} marcados',
          ),
      ],
    );
  }
}

class _OpenIncidentOutcomeChips extends StatelessWidget {
  final List<String> outcomes;

  const _OpenIncidentOutcomeChips({required this.outcomes});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: outcomes
          .map(
            (outcome) => _QuickIncidentChip(
              label: outcome,
              selected: true,
              icon: Icons.fact_check_rounded,
              selectedTextColor: const Color(0xFFFCD34D),
              selectedIconColor: const Color(0xFFFBBF24),
              selectedBorderColor: const Color(0x33FBBF24),
              selectedBackgroundColor: const Color(0x14FBBF24),
              onTap: () {},
            ),
          )
          .toList(),
    );
  }
}

String _formatDashboardIncidentRelative(DateTime startedAt) {
  final diff = DateTime.now().difference(startedAt);
  if (diff.inDays > 0) return '${diff.inDays}d';
  if (diff.inHours > 0) {
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }
  return '${diff.inMinutes.clamp(0, 59)}m';
}

String _formatDashboardIncidentTimestamp(DateTime timestamp) {
  return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
}
