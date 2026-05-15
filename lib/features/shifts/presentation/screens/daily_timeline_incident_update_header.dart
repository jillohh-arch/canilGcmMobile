part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateHeader on _DailyTimelineScreenState {
  Widget _buildIncidentUpdateHeader(Incident incident) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primary.withAlpha(80)),
          ),
          child: const Icon(
            Icons.edit_rounded,
            color: AppTheme.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ATUALIZAR OCORRÊNCIA',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                incident.location,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
