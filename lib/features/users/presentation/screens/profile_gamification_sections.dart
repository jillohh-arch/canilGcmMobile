part of 'profile_screen.dart';

extension _ProfileGamificationSections on _ProfileScreenState {
  Widget _buildTacticalEvolutionSliver(LevelProgress levelProgress) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EVOLUÇÃO TÁTICA',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            LevelProgressCard(progress: levelProgress),
            if (_weeklyMissionFuture != null) ...[
              const SizedBox(height: 14),
              FutureBuilder<List<WeeklyMissionProgress>>(
                future: _weeklyMissionFuture,
                builder: (context, missionSnapshot) {
                  if (missionSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(
                          color: Color(0xFFFBBF24),
                        ),
                      ),
                    );
                  }

                  final missions =
                      missionSnapshot.data ?? const <WeeklyMissionProgress>[];

                  return _buildBadgeStatusCard(
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
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeGallerySliver(UserModel userModel) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GALERIA DE TROFÉUS',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: BadgesConfig.badges.map((b) {
                final bool isUnlocked = userModel.userBadges.contains(b.id);

                return Tooltip(
                  message: isUnlocked
                      ? b.description
                      : 'Bloqueado: ${b.description}',
                  textStyle: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: isUnlocked
                      ? Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(8),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: b.color.withAlpha(140)),
                            boxShadow: [
                              BoxShadow(
                                color: b.color.withValues(alpha: 0.16),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(b.icon, size: 32, color: b.color),
                              const SizedBox(height: 6),
                              Text(
                                b.name,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0,
                            0,
                            0,
                            0.4,
                            0, // Opacidade reduzida + Grayscale
                          ]),
                          child: Container(
                            width: 80,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: b.color.withAlpha(120)),
                            ),
                            child: Column(
                              children: [
                                Icon(b.icon, size: 32, color: b.color),
                                const SizedBox(height: 6),
                                Text(
                                  b.name,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeProgressSliver(UserModel userModel) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: FutureBuilder<Map<String, BadgeProgress>>(
          future: _badgeProgressFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: Color(0xFFFBBF24)),
                ),
              );
            }

            final progressMap =
                snapshot.data ?? const <String, BadgeProgress>{};
            final lockedBadges =
                BadgesConfig.badges
                    .where((badge) => !userModel.userBadges.contains(badge.id))
                    .where((badge) => progressMap.containsKey(badge.id))
                    .toList()
                  ..sort((a, b) {
                    final progressA = progressMap[a.id]!;
                    final progressB = progressMap[b.id]!;
                    final byCompletion = progressB.progress.compareTo(
                      progressA.progress,
                    );
                    if (byCompletion != 0) return byCompletion;
                    return progressA.remaining.compareTo(progressB.remaining);
                  });

            if (lockedBadges.isEmpty) {
              return _buildBadgeStatusCard(
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

            return _buildBadgeStatusCard(
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
        ),
      ),
    );
  }
}
