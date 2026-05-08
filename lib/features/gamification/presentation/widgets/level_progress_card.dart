part of 'gamification_progress_widgets.dart';

class LevelProgressCard extends StatelessWidget {
  final LevelProgress progress;

  const LevelProgressCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFFFBBF24),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROGRESSO DE NÍVEL',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nível ${progress.level} • ${progress.currentXp} XP',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).round()}%',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFBBF24),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFBBF24),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Faltam ${progress.xpRemaining} XP para alcançar o nível ${progress.level + 1}.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
