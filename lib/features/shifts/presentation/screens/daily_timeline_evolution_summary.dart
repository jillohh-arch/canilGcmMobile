part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionSummary on _DailyTimelineScreenState {
  Widget _buildEvolutionSummarySection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousTrainings = _getPerformanceTrainings(dogId, lastDays: 14)
        .where((training) {
          final cutoff = DateTime.now().subtract(const Duration(days: 7));
          return training.date.isBefore(cutoff);
        })
        .toList();
    final totalSessions = trainings.length;
    final totalMinutes = trainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final previousTotalSessions = previousTrainings.length;
    final previousTotalMinutes = previousTrainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final averageMinutes = totalSessions == 0
        ? 0
        : totalMinutes / totalSessions;
    final mostFrequentCategory = _resolveMostFrequentCategory(trainings);
    final lastTraining = trainings.isNotEmpty ? trainings.first : null;
    final focusVisual = _resolveEvolutionCategoryVisual(mostFrequentCategory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(235),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(70)),
              boxShadow: [
                BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18),
              ],
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
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBox(
                label: 'SESSÕES',
                value: '$totalSessions',
                icon: Icons.format_list_numbered_rounded,
                color: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'TEMPO',
                value: totalMinutes > 0
                    ? '${totalMinutes.toStringAsFixed(0)} min'
                    : '--',
                icon: Icons.timer_rounded,
                color: const Color(0xFF00E5FF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBox(
                label: 'MÉDIA',
                value: averageMinutes > 0
                    ? '${averageMinutes.toStringAsFixed(1)} min'
                    : '--',
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'FOCO',
                value: mostFrequentCategory,
                icon: focusVisual.icon,
                color: focusVisual.color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildEvolutionWeekComparisonCard(
            currentMinutes: totalMinutes,
            previousMinutes: previousTotalMinutes,
            currentSessions: totalSessions,
            previousSessions: previousTotalSessions,
            scopeLabel: _selectedTrainingFilter,
          ),
          if (lastTraining != null) ...[
            const SizedBox(height: 10),
            Container(
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
                    child: Icon(
                      focusVisual.icon,
                      color: focusVisual.color,
                      size: 20,
                    ),
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
                          '${_formatEvolutionDate(lastTraining.date)} • ${lastTraining.location.isNotEmpty ? lastTraining.location : 'Local não informado'}',
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
            ),
          ],
        ],
      ),
    );
  }

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

    final headline = previousMinutes <= 0
        ? 'Primeira base comparável de $scopeText'
        : isUp
        ? '$scopeText acima da semana anterior'
        : isDown
        ? '$scopeText abaixo da semana anterior'
        : 'Mesmo volume de $scopeText na semana anterior';

    final detail = previousMinutes <= 0
        ? 'Esta semana soma ${_formatEvolutionMinutes(currentMinutes)} em $currentSessions sessão(ões).'
        : '${deltaMinutes.abs().toStringAsFixed(0)} min e ${deltaSessions.abs()} sessão(ões) de diferença • ${((deltaMinutes.abs() / previousMinutes) * 100).toStringAsFixed(0)}% em relação à semana passada.';

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
                  headline,
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
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
