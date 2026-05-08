part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionSections on _DailyTimelineScreenState {
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
            ...cards.map((entry) {
              final sessions = entry.value.length;
              final minutes = entry.value.fold<double>(
                0,
                (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
              );
              final latest = entry.value.first;
              final share = totalMinutes <= 0
                  ? 0
                  : (minutes / totalMinutes) * 100;
              final visual = _resolveEvolutionCategoryVisual(entry.key);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _hudPanel.withAlpha(230),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: visual.color.withAlpha(70)),
                  boxShadow: [
                    BoxShadow(
                      color: visual.color.withAlpha(14),
                      blurRadius: 12,
                    ),
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
            }),
        ],
      ),
    );
  }

  Widget _buildEvolutionAttentionSection(String dogId) {
    final currentWindow = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousWindow = _getPerformanceTrainings(dogId, lastDays: 14).where((
      training,
    ) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return training.date.isBefore(cutoff);
    }).toList();

    final currentMinutes = currentWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final previousMinutes = previousWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );

    final alerts = <Widget>[];
    final scopeLabel = _selectedTrainingFilter ?? 'performance';

    if (currentWindow.isEmpty) {
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.warning_amber_rounded,
          title: 'Sem registros recentes de $scopeLabel',
          description:
              'Nenhum treino desse recorte foi registrado nos últimos 7 dias.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes < previousMinutes) {
      final variation =
          ((previousMinutes - currentMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_down_rounded,
          title: '$scopeLabel abaixo da semana anterior',
          description:
              'O volume caiu ${variation.toStringAsFixed(0)}% em comparação com a semana passada.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes > previousMinutes) {
      final variation =
          ((currentMinutes - previousMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_up_rounded,
          title: '$scopeLabel acima da semana anterior',
          description:
              'O volume subiu ${variation.toStringAsFixed(0)}% em relação à semana passada.',
        ),
      );
    }

    for (final category in const [
      'Faro',
      'Busca & Captura',
      'Guarda',
      'Obediência',
    ]) {
      if (_selectedTrainingFilter != null &&
          category != _selectedTrainingFilter) {
        continue;
      }

      final categoryTrainings =
          _getPerformanceTrainings(dogId, applyFilter: false)
              .where(
                (training) =>
                    _normalizePerformanceCategory(training.trainingType) ==
                    category,
              )
              .toList();

      if (categoryTrainings.isEmpty) continue;

      final latest = categoryTrainings.first.date;
      final daysWithout = DateTime.now()
          .difference(DateTime(latest.year, latest.month, latest.day))
          .inDays;

      if (daysWithout >= 7) {
        alerts.add(
          _buildEvolutionMessageCard(
            icon: Icons.schedule_rounded,
            title: '$category sem registro recente',
            description:
                'A última sessão dessa competência foi há $daysWithout dias.',
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              _selectedTrainingFilter == null
                  ? 'ATENÇÃO DO PERÍODO'
                  : 'ATENÇÃO EM ${_selectedTrainingFilter!.toUpperCase()}',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (alerts.isEmpty)
            _buildEvolutionMessageCard(
              icon: Icons.verified_rounded,
              title: _selectedTrainingFilter == null
                  ? 'Rotina consistente'
                  : 'Recorte consistente',
              description: _selectedTrainingFilter == null
                  ? 'Os registros recentes mostram continuidade de treino sem alertas importantes.'
                  : 'Os registros recentes de ${_selectedTrainingFilter!} estão consistentes neste período.',
            )
          else
            ...alerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: alert,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEvolutionMessageCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudAmber.withAlpha(65)),
        boxShadow: [BoxShadow(color: _hudAmber.withAlpha(12), blurRadius: 12)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudAmber.withAlpha(80)),
            ),
            child: Icon(icon, color: _hudAmber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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
                child: Icon(
                  Icons.timeline_rounded,
                  color: visual.color,
                  size: 20,
                ),
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
      },
    );
  }
}
