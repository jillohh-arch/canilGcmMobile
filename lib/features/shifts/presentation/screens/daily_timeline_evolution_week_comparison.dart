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
    final isUp = deltaMinutes > 0;
    final isDown = deltaMinutes < 0;
    final accent = isUp
        ? const Color(0xFF4ADE80)
        : isDown
        ? const Color(0xFFF87171)
        : const Color(0xFF94A3B8);
    final icon = isUp
        ? Icons.trending_up_rounded
        : isDown
        ? Icons.trending_down_rounded
        : Icons.remove_rounded;
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
            child: Icon(icon, color: accent, size: 22),
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
                  style: GoogleFonts.robotoMono(
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
                    isUp: isUp,
                    isDown: isDown,
                    scopeText: scopeText,
                  ),
                  style: GoogleFonts.oxanium(
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

  String _buildEvolutionWeekComparisonHeadline({
    required double previousMinutes,
    required bool isUp,
    required bool isDown,
    required String scopeText,
  }) {
    if (previousMinutes <= 0) {
      return 'Primeira base comparável de $scopeText';
    }
    if (isUp) {
      return '$scopeText acima da semana anterior';
    }
    if (isDown) {
      return '$scopeText abaixo da semana anterior';
    }
    return 'Mesmo volume de $scopeText na semana anterior';
  }

  String _buildEvolutionWeekComparisonDetail({
    required double currentMinutes,
    required double previousMinutes,
    required int currentSessions,
    required double deltaMinutes,
    required int deltaSessions,
  }) {
    if (previousMinutes <= 0) {
      return 'Esta semana soma ${_formatEvolutionMinutes(currentMinutes)} em $currentSessions sessão(ões).';
    }

    return '${deltaMinutes.abs().toStringAsFixed(0)} min e ${deltaSessions.abs()} sessão(ões) de diferença • ${((deltaMinutes.abs() / previousMinutes) * 100).toStringAsFixed(0)}% em relação à semana passada.';
  }
}
