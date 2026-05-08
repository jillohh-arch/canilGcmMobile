part of 'ranking_screen.dart';

class _BadgeProgressTab extends StatelessWidget {
  final UserModel? currentUser;
  final Future<Map<String, BadgeProgress>>? badgeProgressFuture;
  final Future<List<WeeklyMissionProgress>>? weeklyMissionFuture;

  const _BadgeProgressTab({
    required this.currentUser,
    required this.badgeProgressFuture,
    required this.weeklyMissionFuture,
  });

  @override
  Widget build(BuildContext context) {
    if (currentUser == null ||
        badgeProgressFuture == null ||
        weeklyMissionFuture == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Não foi possível identificar o condutor atual para carregar o progresso dos troféus.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return FutureBuilder<Map<String, BadgeProgress>>(
      future: badgeProgressFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _hudCyan),
          );
        }

        final progressMap = snapshot.data ?? const <String, BadgeProgress>{};
        final levelProgress = GamificationService.getLevelProgress(
          currentUser!.xp,
        );
        final lockedBadges = _lockedBadges(progressMap);

        if (lockedBadges.isEmpty) {
          return const _AllBadgesUnlockedEmptyState();
        }

        final nextBadge = lockedBadges.first;
        final nextBadgeProgress = progressMap[nextBadge.id]!;
        final remainingBadges = lockedBadges.skip(1).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _WeeklyMissionsPanel(weeklyMissionFuture: weeklyMissionFuture!),
            const SizedBox(height: 14),
            LevelProgressCard(progress: levelProgress),
            const SizedBox(height: 14),
            NextBadgeHighlightCard(
              badge: nextBadge,
              progress: nextBadgeProgress,
            ),
            if (remainingBadges.isNotEmpty) ...[
              const SizedBox(height: 14),
              _RemainingBadgesPanel(
                badges: remainingBadges,
                progressMap: progressMap,
              ),
            ],
          ],
        );
      },
    );
  }

  List<BadgeData> _lockedBadges(Map<String, BadgeProgress> progressMap) {
    return BadgesConfig.badges
        .where((badge) => !currentUser!.userBadges.contains(badge.id))
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

class _WeeklyMissionsPanel extends StatelessWidget {
  final Future<List<WeeklyMissionProgress>> weeklyMissionFuture;

  const _WeeklyMissionsPanel({required this.weeklyMissionFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WeeklyMissionProgress>>(
      future: weeklyMissionFuture,
      builder: (context, missionSnapshot) {
        if (missionSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(color: _hudCyan),
            ),
          );
        }

        final missions =
            missionSnapshot.data ?? const <WeeklyMissionProgress>[];

        return _GamificationPanel(
          title: 'MISSÕES DA SEMANA',
          subtitle:
              'Conclua metas operacionais e receba bônus de XP uma vez por semana.',
          children: missions
              .map(
                (mission) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: WeeklyMissionCard(mission: mission),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _RemainingBadgesPanel extends StatelessWidget {
  final List<BadgeData> badges;
  final Map<String, BadgeProgress> progressMap;

  const _RemainingBadgesPanel({
    required this.badges,
    required this.progressMap,
  });

  @override
  Widget build(BuildContext context) {
    return _GamificationPanel(
      title: 'OUTROS TROFÉUS EM PROGRESSO',
      subtitle:
          'Acompanhe o que falta para desbloquear as próximas conquistas.',
      children: badges.map((badge) {
        final progress = progressMap[badge.id]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BadgeProgressCard(badge: badge, progress: progress),
        );
      }).toList(),
    );
  }
}

class _GamificationPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _GamificationPanel({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _AllBadgesUnlockedEmptyState extends StatelessWidget {
  const _AllBadgesUnlockedEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 64,
            color: _hudAmber,
          ),
          const SizedBox(height: 16),
          Text(
            'TODOS OS TROFÉUS DISPONÍVEIS\nJÁ FORAM CONQUISTADOS.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
