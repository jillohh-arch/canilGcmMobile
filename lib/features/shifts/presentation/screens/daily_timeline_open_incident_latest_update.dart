part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentLatestUpdate on _DailyTimelineScreenState {
  Widget _buildIncidentLatestUpdateCard({
    required Incident incident,
    required IncidentProgressUpdate latestUpdate,
  }) {
    final progressStyle = _resolveIncidentProgressStyle(
      latestUpdate.title,
      latestUpdate.description,
    );
    final location = (latestUpdate.location ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progressStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: progressStyle.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: progressStyle.iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              progressStyle.icon,
              size: 16,
              color: progressStyle.iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestUpdate.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: progressStyle.titleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestUpdate.description.isNotEmpty
                      ? latestUpdate.description
                      : incident.description,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildIncidentMetaPill(
                      icon: Icons.schedule_rounded,
                      label: _formatIncidentTimestamp(latestUpdate.timestamp),
                    ),
                    if (location.isNotEmpty)
                      _buildIncidentMetaPill(
                        icon: Icons.place_rounded,
                        label: location,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
