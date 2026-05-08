part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionScopeCard on _DailyTimelineScreenState {
  Widget _buildEvolutionScopeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECORTE ATUAL',
            style: GoogleFonts.robotoMono(
              color: _hudCyan.withAlpha(210),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _buildEvolutionScopeHeadline(),
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _buildEvolutionScopeDescription(),
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
