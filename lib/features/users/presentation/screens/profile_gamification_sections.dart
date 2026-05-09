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
              _WeeklyMissionsStatusCard(missionFuture: _weeklyMissionFuture!),
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
              children: BadgesConfig.badges.map((badge) {
                final isUnlocked = userModel.userBadges.contains(badge.id);
                return _BadgeGalleryTile(badge: badge, isUnlocked: isUnlocked);
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
        child: _BadgeProgressStatusCard(
          userModel: userModel,
          badgeProgressFuture: _badgeProgressFuture!,
        ),
      ),
    );
  }
}
