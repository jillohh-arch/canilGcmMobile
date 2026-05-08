part of 'gamification_progress_widgets.dart';

class WeeklyMissionCard extends StatelessWidget {
  final WeeklyMissionProgress mission;

  const WeeklyMissionCard({super.key, required this.mission});

  IconData _iconForMission() {
    switch (mission.missionId) {
      case 'treino_da_semana':
        return Icons.fitness_center_rounded;
      case 'turno_da_semana':
        return Icons.badge_rounded;
      case 'ocorrencia_da_semana':
        return Icons.local_police_rounded;
      case 'cuidado_da_semana':
        return Icons.pets_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  Color _colorForMission() {
    switch (mission.missionId) {
      case 'treino_da_semana':
        return const Color(0xFF22C55E);
      case 'turno_da_semana':
        return const Color(0xFF38BDF8);
      case 'ocorrencia_da_semana':
        return const Color(0xFFF97316);
      case 'cuidado_da_semana':
        return const Color(0xFFA78BFA);
      default:
        return const Color(0xFFFBBF24);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _colorForMission();
    final statusLabel = mission.claimed
        ? 'Bônus aplicado'
        : mission.completed
        ? 'Pronto para bônus'
        : 'Faltam ${mission.remaining} ${mission.unitLabel}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(_iconForMission(), color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mission.description,
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+${mission.rewardXp} XP',
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: mission.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(14),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${mission.current} de ${mission.target} ${mission.unitLabel}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                statusLabel,
                style: GoogleFonts.inter(
                  color: mission.claimed ? accent : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
