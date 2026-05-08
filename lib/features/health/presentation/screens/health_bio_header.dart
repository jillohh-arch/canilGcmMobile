part of 'health_dashboard_screen.dart';

extension _HealthBioHeader on _HealthDashboardScreenState {
  Widget _buildBioHudHeader(
    Dog dog,
    List<HealthLogModel> logs,
    DateTime? lastBath,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(
                      alpha: 0.3 + (_pulseController.value * 0.7),
                    ),
                    width: 2 + (_pulseController.value * 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(
                        alpha: 0.4 * _pulseController.value,
                      ),
                      blurRadius: 15 + (15 * _pulseController.value),
                      spreadRadius: 2 + (5 * _pulseController.value),
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: CircleAvatar(
              radius: 55,
              backgroundColor: const Color(0xFF111111),
              backgroundImage: dog.profileImageUrl != null
                  ? CachedNetworkImageProvider(dog.profileImageUrl!)
                  : null,
              child: dog.profileImageUrl == null
                  ? const Icon(Icons.pets, size: 40, color: Colors.white24)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            dog.name.toUpperCase(),
            style: GoogleFonts.oxanium(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          _ReadinessHudBar(dog: dog, logs: logs, lastBath: lastBath),
        ],
      ),
    );
  }
}

class _ReadinessHudBar extends StatelessWidget {
  final Dog dog;
  final List<HealthLogModel> logs;
  final DateTime? lastBath;

  const _ReadinessHudBar({
    required this.dog,
    required this.logs,
    required this.lastBath,
  });

  @override
  Widget build(BuildContext context) {
    final latestWeight = logs
        .where((log) => log.weight != null)
        .map((log) => log.weight!)
        .cast<double?>()
        .firstWhere((weight) => weight != null, orElse: () => null);
    final breakdown = dog.calculateReadinessBreakdown(
      lastBathOverride: lastBath,
      weightOverride: latestWeight,
    );
    final score = breakdown.total;
    final barColor = _readinessColor(score);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.oxanium(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white54,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.shareTechMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: barColor.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vacinação, peso, higiene e treino recente.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vacinação ${breakdown.vacinacao}/30 • Peso ${breakdown.peso}/25 • Higiene ${breakdown.higiene}/15 • Treino ${breakdown.treino}/30',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _readinessColor(int score) {
    if (score >= 80) return Colors.cyanAccent;
    if (score >= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}
