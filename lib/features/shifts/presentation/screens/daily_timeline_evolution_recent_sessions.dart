part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionRecentSessions on _DailyTimelineScreenState {
  Widget _buildRecentPerformanceSessions(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 14);

    if (trainings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.track_changes_rounded,
                size: 60,
                color: Colors.white.withAlpha(30),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhuma sessão de performance registrada',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: trainings.length.clamp(0, 8),
      itemBuilder: (context, index) {
        final training = trainings[index];
        return _buildRecentPerformanceSessionTile(training);
      },
    );
  }

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
                  style: GoogleFonts.oxanium(
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
            style: GoogleFonts.robotoMono(
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
