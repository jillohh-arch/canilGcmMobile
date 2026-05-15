part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionWeekComparison on _DailyTimelineScreenState {
  Widget _buildEvolutionWeekComparisonCard({
    required double currentMinutes,
    required double previousMinutes,
    required int currentSessions,
    required int previousSessions,
    String? scopeLabel,
  }) {
    final deltaMinutes = currentMinutes - previousMinutes;
    final deltaSessions = currentSessions - previousSessions;
    final style = _resolveEvolutionWeekComparisonStyle(deltaMinutes);
    final accent = style.accent;
    final scopeText = scopeLabel ?? 'performance';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(95)),
        boxShadow: [BoxShadow(color: accent.withAlpha(18), blurRadius: 14)],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withAlpha(24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(style.icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scopeLabel == null
                      ? 'COMPARATIVO SEMANAL'
                      : 'COMPARATIVO DE ${scopeLabel.toUpperCase()}',
                  style: GoogleFonts.inter(
                    color: accent.withAlpha(220),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildEvolutionWeekComparisonHeadline(
                    previousMinutes: previousMinutes,
                    isUp: style.isUp,
                    isDown: style.isDown,
                    scopeText: scopeText,
                  ),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildEvolutionWeekComparisonDetail(
                    currentMinutes: currentMinutes,
                    previousMinutes: previousMinutes,
                    currentSessions: currentSessions,
                    deltaMinutes: deltaMinutes,
                    deltaSessions: deltaSessions,
                  ),
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
