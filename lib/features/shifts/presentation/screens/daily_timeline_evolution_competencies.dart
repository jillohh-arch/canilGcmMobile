part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencies on _DailyTimelineScreenState {
  Widget _buildCompetencyEvolutionSection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final totalMinutes = _sumEvolutionMinutes(trainings);
    final cards = _buildCompetencyTrainingGroups(trainings);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'COMPETÊNCIAS TRABALHADAS',
              style: GoogleFonts.inter(
                color: _hudCyan.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (cards.isEmpty)
            _buildEvolutionMessageCard(
              icon: Icons.track_changes_rounded,
              title: 'Nenhuma competência registrada',
              description:
                  'Ainda não há treinos de performance suficientes nesta janela para comparar a evolução.',
            )
          else
            ...cards.map(
              (entry) => _buildEvolutionCompetencyCard(
                entry: entry,
                totalMinutes: totalMinutes,
              ),
            ),
        ],
      ),
    );
  }
}
