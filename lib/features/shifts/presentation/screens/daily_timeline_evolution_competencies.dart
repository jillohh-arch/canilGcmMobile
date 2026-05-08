part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCompetencies on _DailyTimelineScreenState {
  Widget _buildCompetencyEvolutionSection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final grouped = <String, List<TrainingSessionModel>>{};
    final totalMinutes = trainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );

    for (final training in trainings) {
      final category = _normalizePerformanceCategory(training.trainingType);
      grouped.putIfAbsent(category, () => []).add(training);
    }

    final cards = grouped.entries.toList()
      ..sort((a, b) {
        final aMinutes = a.value.fold<double>(
          0,
          (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
        );
        final bMinutes = b.value.fold<double>(
          0,
          (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
        );
        return bMinutes.compareTo(aMinutes);
      });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'COMPETÊNCIAS TRABALHADAS',
              style: GoogleFonts.robotoMono(
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

  Widget _buildEvolutionCompetencyCard({
    required MapEntry<String, List<TrainingSessionModel>> entry,
    required double totalMinutes,
  }) {
    final sessions = entry.value.length;
    final minutes = entry.value.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final latest = entry.value.first;
    final share = totalMinutes <= 0 ? 0 : (minutes / totalMinutes) * 100;
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: visual.color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(visual.icon, color: visual.color, size: 20),
          ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: visual.color.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${share.toStringAsFixed(0)}%',
                        style: GoogleFonts.robotoMono(
                          color: visual.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
