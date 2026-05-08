part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryIncidentSections on _DailyTimelineScreenState {
  List<Widget> _buildTimelineIncidentSections(
    _TimelineEntry entry,
    Color color,
  ) {
    return [
      ..._buildTimelineOutcomeSection(entry, color),
      ..._buildTimelineProgressSection(entry, color),
    ];
  }

  List<Widget> _buildTimelineOutcomeSection(_TimelineEntry entry, Color color) {
    if (entry.type != 'Ocorrência' ||
        entry.details['_outcomes'] is! List ||
        (entry.details['_outcomes'] as List).isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      Text(
        'RESULTADOS FINAIS',
        style: GoogleFonts.oxanium(
          color: color.withAlpha(230),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: (entry.details['_outcomes'] as List)
            .map<Widget>(
              (outcome) =>
                  _buildTimelineOutcomeBadge(outcome: outcome.toString()),
            )
            .toList(),
      ),
    ];
  }

  Widget _buildTimelineOutcomeBadge({required String outcome}) {
    final badgeStyle = _resolveIncidentOutcomeBadgeStyle(outcome);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeStyle.backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeStyle.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeStyle.icon, size: 13, color: badgeStyle.iconColor),
          const SizedBox(width: 6),
          Text(
            outcome,
            style: GoogleFonts.inter(
              color: badgeStyle.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimelineProgressSection(
    _TimelineEntry entry,
    Color color,
  ) {
    if (entry.type != 'Ocorrência' ||
        entry.details['_progressUpdates'] is! List ||
        (entry.details['_progressUpdates'] as List).isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 14),
      Text(
        'LINHA DO TEMPO',
        style: GoogleFonts.oxanium(
          color: color.withAlpha(230),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      _buildIncidentProgressTimeline(
        updates: entry.details['_progressUpdates'] as List,
        accent: color,
      ),
    ];
  }
}
