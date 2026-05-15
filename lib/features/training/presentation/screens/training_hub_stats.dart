part of 'training_hub_screen.dart';

class _TrainingHubStats extends StatelessWidget {
  final TrainingViewModel trainingVM;
  const _TrainingHubStats({required this.trainingVM});

  @override
  Widget build(BuildContext context) {
    final sessions = trainingVM.trainings;
    final totalSessions = sessions.length;
    final totalSeconds = sessions.fold<int>(
      0,
      (sum, s) => sum + (s.searchDuration ?? 0),
    );
    final totalHours = (totalSeconds / 3600).toStringAsFixed(1);

    // Dias desde último treino
    String lastLabel = '--';
    if (sessions.isNotEmpty) {
      final diff = DateTime.now().difference(sessions.first.date).inDays;
      lastLabel = diff == 0 ? 'Hoje' : '${diff}d atrás';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: Icons.fitness_center_rounded,
            value: '$totalSessions',
            label: 'Sessões',
            color: AppTheme.primary,
          ),
          _StatItem(
            icon: Icons.timer_outlined,
            value: '${totalHours}h',
            label: 'Total',
            color: AppTheme.success,
          ),
          _StatItem(
            icon: Icons.calendar_today_rounded,
            value: lastLabel,
            label: 'Último',
            color: AppTheme.warning,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}