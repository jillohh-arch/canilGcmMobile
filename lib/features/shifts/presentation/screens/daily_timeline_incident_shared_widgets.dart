part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentSharedWidgets on _DailyTimelineScreenState {
  Widget _buildIncidentQuickSheetHeader({
    required String title,
    required Incident incident,
    required _IncidentBadgeStyle badgeStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeStyle.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeStyle.borderColor),
              ),
              child: Icon(
                badgeStyle.icon,
                color: badgeStyle.iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${incident.type ?? 'Ocorrência'} - ${incident.location}',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildIncidentBadge(
              label: incident.status.toUpperCase(),
              style: _resolveIncidentStatusBadgeStyle(incident.status),
            ),
            _buildIncidentMetaPill(
              icon: Icons.schedule_rounded,
              label: _formatIncidentTimestamp(incident.updatedAt),
            ),
          ],
        ),
      ],
    );
  }
}
