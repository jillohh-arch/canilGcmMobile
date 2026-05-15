part of 'training_log_screen.dart';

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
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
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
