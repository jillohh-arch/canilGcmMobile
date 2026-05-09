part of 'profile_screen.dart';

class _WeeklyMissionsStatusCard extends StatelessWidget {
  final Future<List<WeeklyMissionProgress>> missionFuture;

  const _WeeklyMissionsStatusCard({required this.missionFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WeeklyMissionProgress>>(
      future: missionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProfileSectionLoader();
        }

        final missions = snapshot.data ?? const <WeeklyMissionProgress>[];

        return _ProfileStatusCard(
          title: 'MISSÕES DA SEMANA',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Metas rápidas da semana com bônus automático de XP ao concluir.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...missions.map((mission) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: WeeklyMissionCard(mission: mission),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _BadgeProgressStatusCard extends StatelessWidget {
  final UserModel userModel;
  final Future<Map<String, BadgeProgress>> badgeProgressFuture;

  const _BadgeProgressStatusCard({
    required this.userModel,
    required this.badgeProgressFuture,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, BadgeProgress>>(
      future: badgeProgressFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProfileSectionLoader();
        }

        final progressMap = snapshot.data ?? const <String, BadgeProgress>{};
        final lockedBadges = _sortedLockedBadges(progressMap);

        if (lockedBadges.isEmpty) {
          return _ProfileStatusCard(
            title: 'PROGRESSO DOS TROFÉUS',
            child: Text(
              'Todos os troféus disponíveis já foram conquistados.',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final nextBadge = lockedBadges.first;
        final nextBadgeProgress = progressMap[nextBadge.id]!;
        final remainingBadges = lockedBadges.skip(1).toList();

        return _ProfileStatusCard(
          title: 'PROGRESSO DOS TROFÉUS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NextBadgeHighlightCard(
                badge: nextBadge,
                progress: nextBadgeProgress,
              ),
              if (remainingBadges.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'OUTROS TROFÉUS EM PROGRESSO',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                ...remainingBadges.map((badge) {
                  final progress = progressMap[badge.id]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BadgeProgressCard(
                      badge: badge,
                      progress: progress,
                      padding: const EdgeInsets.all(14),
                      borderRadius: 14,
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  List<BadgeData> _sortedLockedBadges(Map<String, BadgeProgress> progressMap) {
    return BadgesConfig.badges
        .where((badge) => !userModel.userBadges.contains(badge.id))
        .where((badge) => progressMap.containsKey(badge.id))
        .toList()
      ..sort((a, b) {
        final progressA = progressMap[a.id]!;
        final progressB = progressMap[b.id]!;
        final byCompletion = progressB.progress.compareTo(progressA.progress);
        if (byCompletion != 0) return byCompletion;
        return progressA.remaining.compareTo(progressB.remaining);
      });
  }
}

class _ProfileStatusCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ProfileStatusCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.robotoMono(
            color: _hudCyan.withAlpha(210),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(235),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(65)),
            boxShadow: [
              BoxShadow(color: _hudCyan.withAlpha(20), blurRadius: 18),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ProfileSectionLoader extends StatelessWidget {
  const _ProfileSectionLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: CircularProgressIndicator(color: Color(0xFFFBBF24)),
      ),
    );
  }
}
