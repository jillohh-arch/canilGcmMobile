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
      padding: const EdgeInsets.all(14),
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
            child: const Icon(Icons.timeline_rounded, color: _hudCyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAINEL DE EVOLUÇÃO',
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lastLabel,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Text(
              '${sessions.length}',
              style: GoogleFonts.robotoMono(
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
      return const Center(child: CircularProgressIndicator(color: _hudCyan));
    }

    final sessions = tVM.trainings..sort((a, b) => a.date.compareTo(b.date));
    final scentSessions = sessions
        .where((s) => s.trainingType == 'Faro' && s.searchDuration != null)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Performance summary cards
          _TrainingHudHeader(sessions: sessions),
          const SizedBox(height: 14),
          if (sessions.isNotEmpty) _SummaryCards(sessions: sessions),
          const SizedBox(height: 24),

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
            ...sessions.reversed.map((s) => _SessionCard(session: s)),
        ],
      ),
    );
  }
}

// Summary stat cards row
class _SummaryCards extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SummaryCards({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final total = sessions.length;
    final scentCount = sessions.where((s) => s.trainingType == 'Faro').length;
    final durations = sessions
        .where((s) => s.searchDuration != null)
        .map((s) => s.searchDuration!)
        .toList();
    final avgDuration = durations.isEmpty
        ? '--'
        : '${(durations.reduce((a, b) => a + b) / durations.length).round()}s';
    final bestDuration = durations.isEmpty
        ? '--'
        : '${durations.reduce((a, b) => a < b ? a : b)}s';

    return Row(
      children: [
        _MiniStat(
          label: 'Sessões',
          value: '$total',
          icon: Icons.fitness_center_rounded,
          color: AppTheme.amber,
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Faro',
          value: '$scentCount',
          icon: Icons.track_changes_rounded,
          color: const Color(0xFF29B6F6),
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Melhor',
          value: bestDuration,
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF66BB6A),
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Média',
          value: avgDuration,
          icon: Icons.timer_rounded,
          color: const Color(0xFF7E57C2),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(80), width: 0.8),
          boxShadow: [BoxShadow(color: color.withAlpha(12), blurRadius: 12)],
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.oxanium(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.robotoMono(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Chart section container
