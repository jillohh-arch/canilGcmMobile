part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionRecentSessionTile
    on _DailyTimelineScreenState {
  Widget _buildRecentPerformanceSessionTile(TrainingSessionModel training) {
    final minutes = ((training.searchDuration ?? 0) / 60).round();
    final location = training.location.trim();
    final subtitle = location.isEmpty
        ? _formatEvolutionDate(training.date)
        : '${_formatEvolutionDate(training.date)} • $location';
    final visual = _resolveEvolutionCategoryVisual(
      _normalizePerformanceCategory(training.trainingType),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: visual.color.withAlpha(70)),
        boxShadow: [
          BoxShadow(color: visual.color.withAlpha(12), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: visual.color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: visual.color.withAlpha(70)),
            ),
            child: Icon(Icons.timeline_rounded, color: visual.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  training.trainingType,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            minutes > 0 ? '$minutes min' : '--',
            style: GoogleFonts.inter(
              color: visual.color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
