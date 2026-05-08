part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencyCard on _DailyTimelineScreenState {
  Widget _buildEvolutionCompetencyCard({
    required MapEntry<String, List<TrainingSessionModel>> entry,
    required double totalMinutes,
  }) {
    final sessions = entry.value.length;
    final minutes = _sumEvolutionMinutes(entry.value);
    final latest = entry.value.first;
    final share = totalMinutes <= 0 ? 0.0 : (minutes / totalMinutes) * 100;
    final visual = _resolveEvolutionCategoryVisual(entry.key);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: visual.color.withAlpha(70)),
        boxShadow: [
          BoxShadow(color: visual.color.withAlpha(14), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          _buildEvolutionCompetencyIcon(icon: visual.icon, color: visual.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: GoogleFonts.oxanium(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _buildEvolutionCompetencyShareBadge(
                      share: share,
                      color: visual.color,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$sessions sessão(ões) • ${minutes.toStringAsFixed(0)} min • Último registro ${_formatEvolutionDate(latest.date)}',
                  style: GoogleFonts.inter(
                    color: Colors.white60,
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
