part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionLastTraining on _DailyTimelineScreenState {
  Widget _buildEvolutionLastTrainingCard({
    required TrainingSessionModel lastTraining,
    required ({IconData icon, Color color}) focusVisual,
  }) {
    final location = lastTraining.location.isNotEmpty
        ? lastTraining.location
        : 'Local não informado';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: focusVisual.color.withAlpha(24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(focusVisual.icon, color: focusVisual.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTrainingFilter == null
                      ? 'ÚLTIMO TREINO'
                      : 'ÚLTIMO REGISTRO DE ${_selectedTrainingFilter!.toUpperCase()}',
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatEvolutionDate(lastTraining.date)} • $location',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
