part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentCardHeader on _DailyTimelineScreenState {
  Widget _buildOpenIncidentHeader({
    required Incident incident,
    required Color accent,
  }) {
    final statusStyle = _resolveIncidentStatusBadgeStyle(incident.status);
    final resultLabel = incident.displayResult.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (incident.type ?? 'Ocorrência').toUpperCase(),
                style: GoogleFonts.inter(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                incident.location,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildIncidentBadge(
                    label: incident.status.toUpperCase(),
                    style: statusStyle,
                  ),
                  if (resultLabel.isNotEmpty &&
                      resultLabel.toLowerCase() !=
                          incident.status.toLowerCase())
                    _buildIncidentBadge(
                      label: resultLabel,
                      style: _resolveIncidentOutcomeBadgeStyle(resultLabel),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withAlpha(70)),
          ),
          child: Icon(Icons.radar_rounded, color: accent, size: 18),
        ),
      ],
    );
  }
}
