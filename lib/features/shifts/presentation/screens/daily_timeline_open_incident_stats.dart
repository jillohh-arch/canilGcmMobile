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

  Widget _buildOpenIncidentStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
