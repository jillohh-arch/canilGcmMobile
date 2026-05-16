part of 'training_log_screen.dart';

class _TrainingHudHeader extends StatelessWidget {
  final List<TrainingSessionModel> sessions;

  const _TrainingHudHeader({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final lastSession = sessions.isNotEmpty ? sessions.last : null;
    final lastLabel = lastSession == null
        ? 'Sem sessões registradas'
        : '${lastSession.trainingType} • ${_formatDate(lastSession.date)}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18)],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Icon(Icons.timeline_rounded, color: _hudCyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAINEL DE EVOLUÇÃO',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lastLabel,
                  style: GoogleFonts.inter(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Text(
              '${sessions.length}',
              style: GoogleFonts.inter(
                color: _hudCyan,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

// Training Evolution Tab (Garmin/Apple Fitness style)
class _TrainingEvolutionTab extends StatelessWidget {
  final String dogId;
  const _TrainingEvolutionTab({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);

    if (tVM.isLoading) {
      return Center(child: CircularProgressIndicator(color: _hudCyan));
    }

    final sessions = tVM.trainings..sort((a, b) => a.date.compareTo(b.date));
    final scentSessions = sessions
        .where((s) => s.trainingType == 'Faro' && s.searchDuration != null)
        .toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Performance summary cards
          _TrainingHudHeader(sessions: sessions),
          const SizedBox(height: 14),
          if (sessions.isNotEmpty) _SummaryCards(sessions: sessions),
          const SizedBox(height: 20),

          // Streak card
          if (sessions.isNotEmpty) ...[
            _StreakCard(sessions: sessions),
            const SizedBox(height: 20),
          ],

          // Weekly bar chart (últimas 8 semanas)
          if (sessions.length >= 2) ...[
            _ChartSection(
              title: 'SESSÕES POR SEMANA',
              subtitle: 'Frequência de treino nas últimas 8 semanas',
              child: _WeeklyBarChart(sessions: sessions),
            ),
            const SizedBox(height: 20),
          ],

          // Distribuição por especialidade (donut)
          if (sessions.length >= 3) ...[
            _ChartSection(
              title: 'DISTRIBUIÇÃO POR TIPO',
              subtitle: 'Proporção de cada especialidade treinada',
              child: _SpecialtyDonutChart(sessions: sessions),
            ),
            const SizedBox(height: 20),
          ],

          // Progresso por especialidade (barras horizontais)
          if (sessions.isNotEmpty) ...[
            _SpecialtyProgressBars(sessions: sessions),
            const SizedBox(height: 20),
          ],

          // Scent search duration chart
          if (scentSessions.length >= 2) ...[
            _ChartSection(
              title: 'TEMPO DE BUSCA — FARO',
              subtitle: 'Duração em segundos por sessão (↓ é melhor)',
              child: _SearchDurationChart(sessions: scentSessions),
            ),
            const SizedBox(height: 24),
          ],

          // Sessions history
          _SectionHeader(label: 'SESSÕES REGISTRADAS', count: sessions.length),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            _EmptyTraining()
          else
            ...sessions.reversed.take(10).map((s) => _SessionCard(session: s)),
        ],
      ),
    );
  }
}

// Chart section container
