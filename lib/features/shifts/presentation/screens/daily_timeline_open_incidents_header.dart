part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentsHeader on _DailyTimelineScreenState {
  Widget _buildOpenIncidentsHeader(int openIncidentCount) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24).withAlpha(28),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFFBBF24).withAlpha(90)),
          ),
          child: const Icon(
            Icons.pending_actions_rounded,
            color: Color(0xFFFBBF24),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OCORRÊNCIAS EM ANDAMENTO',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$openIncidentCount caso(s) aberto(s) para continuidade',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
