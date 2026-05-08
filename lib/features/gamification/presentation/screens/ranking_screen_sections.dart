part of 'ranking_screen.dart';

extension _RankingScreenSections on _RankingScreenState {
  Widget _buildTrainingRanking(
    TrainingViewModel trainingVM,
    UserViewModel userVM,
    DogViewModel dogVM,
  ) {
    final startOfWeek = _getStartOfWeek();
    final weekTrainings = trainingVM.trainings
        .where((training) => !training.date.isBefore(startOfWeek))
        .toList();
    final periodTrainings = weekTrainings.isNotEmpty
        ? weekTrainings
        : trainingVM.trainings
              .where(
                (training) => !training.date.isBefore(
                  DateTime.now().subtract(const Duration(days: 30)),
                ),
              )
              .toList();
    final periodLabel = weekTrainings.isNotEmpty
        ? 'Nesta semana'
        : 'Últimos 30 dias';

    final Map<String, int> trainingSecondsByRa = {};
    for (final training in periodTrainings) {
      final fallbackRa = dogVM.dogs
          .where((dog) => dog.id == training.dogId)
          .map((dog) => dog.conductorRa ?? '')
          .firstWhere((ra) => ra.isNotEmpty, orElse: () => '');
      final ra = training.handlerId.isNotEmpty
          ? training.handlerId
          : fallbackRa;
      if (ra.isEmpty) continue;

      final duration = training.searchDuration ?? 0;
      if (duration <= 0) continue;

      trainingSecondsByRa.update(
        ra,
        (current) => current + duration,
        ifAbsent: () => duration,
      );
    }

    if (trainingSecondsByRa.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.leaderboard_rounded, size: 64, color: _hudCyan),
            const SizedBox(height: 16),
            Text(
              'NENHUM TREINO REGISTRADO\nNOS ÚLTIMOS 30 DIAS.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final sortedEntries = trainingSecondsByRa.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: sortedEntries.length.clamp(0, 10) + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(230),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(70)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 18, color: _hudCyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$periodLabel • ranking por tempo acumulado de treino',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final entry = sortedEntries[index - 1];
        final user = userVM.users.cast<UserModel?>().firstWhere(
          (candidate) => candidate?.ra == entry.key,
          orElse: () => null,
        );

        final callsign = user?.callsign ?? 'Operador (${entry.key})';
        final photoUrl = user?.photoUrl;
        final hours = entry.value ~/ 3600;
        final minutes = (entry.value % 3600) ~/ 60;

        return _buildRankCard(
          index: index - 1,
          title: callsign.toUpperCase(),
          subtitle: 'Tempo acumulado: ${hours}h ${minutes}m',
          photoUrl: photoUrl,
          callsign: callsign,
        );
      },
    );
  }

  Widget _buildXpRanking(UserViewModel userVM) {
    if (userVM.users.isEmpty) {
      return const Center(
        child: Text('NENHUM USUÁRIO', style: TextStyle(color: Colors.white)),
      );
    }

    final sortedUsers = List<UserModel>.from(userVM.users)
      ..sort((a, b) => b.xp.compareTo(a.xp));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: sortedUsers.length,
      itemBuilder: (context, index) {
        final user = sortedUsers[index];
        final level = GamificationService.calculateLevel(user.xp);

        return _buildRankCard(
          index: index,
          title: user.callsign.toUpperCase(),
          subtitle: 'Nível $level • ${user.xp} XP',
          photoUrl: user.photoUrl,
          callsign: user.callsign,
          isXp: true,
        );
      },
    );
  }

  Widget _buildRankCard({
    required int index,
    required String title,
    required String subtitle,
    String? photoUrl,
    required String callsign,
    bool isXp = false,
  }) {
    return _RankingEntryCard(
      index: index,
      title: title,
      subtitle: subtitle,
      photoUrl: photoUrl,
      callsign: callsign,
      isXp: isXp,
    );
  }

  Widget _buildBadgeProgressTab(UserModel? currentUser) {
    return _BadgeProgressTab(
      currentUser: currentUser,
      badgeProgressFuture: _badgeProgressFuture,
      weeklyMissionFuture: _weeklyMissionFuture,
    );
  }
}
