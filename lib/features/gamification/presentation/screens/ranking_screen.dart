import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/gamification/domain/badge_progress.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/gamification/domain/weekly_mission_progress.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/gamification/data/gamification_service.dart';
import 'package:canil_gcm/features/gamification/domain/badges_data.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/gamification/presentation/widgets/gamification_progress_widgets.dart';
import 'package:canil_gcm/core/widgets/hud_tab_bar.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudPanelAlt = Color(0xFF111827);
const _hudCyan = Color(0xFF00E5FF);
const _hudAmber = Color(0xFFFBBF24);

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  bool _initialized = false;
  Future<Map<String, BadgeProgress>>? _badgeProgressFuture;
  Future<List<WeeklyMissionProgress>>? _weeklyMissionFuture;
  String? _badgeProgressRa;
  String? _weeklyMissionRa;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final trainingVM = Provider.of<TrainingViewModel>(context, listen: false);
    await trainingVM.fetchAllTrainings();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  void _ensureBadgeProgressLoaded(String? ra) {
    if (ra == null || ra.isEmpty) return;
    if (_badgeProgressRa == ra && _badgeProgressFuture != null) return;
    _badgeProgressRa = ra;
    _badgeProgressFuture = GamificationService().getBadgeProgress(ra);
  }

  void _ensureWeeklyMissionsLoaded(String? ra) {
    if (ra == null || ra.isEmpty) return;
    if (_weeklyMissionRa == ra && _weeklyMissionFuture != null) return;
    _weeklyMissionRa = ra;
    _weeklyMissionFuture = (() async {
      await GamificationService().syncWeeklyMissions(ra);
      return GamificationService().getWeeklyMissionProgress(ra);
    })();
  }

  DateTime _getStartOfWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _hudBackground,
        appBar: AppBar(
          title: Text(
            'RANKING DA UNIDADE',
            style: GoogleFonts.oxanium(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.4,
            ),
          ),
          backgroundColor: _hudBackground,
          centerTitle: true,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(74),
            child: const HudTabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.track_changes_rounded, size: 22),
                  text: 'Treinos',
                ),
                Tab(icon: Icon(Icons.bolt_rounded, size: 22), text: 'XP Geral'),
                Tab(
                  icon: Icon(Icons.emoji_events_rounded, size: 22),
                  text: 'Troféus',
                ),
              ],
            ),
          ),
        ),
        body: !_initialized
            ? const Center(child: CircularProgressIndicator(color: _hudCyan))
            : Consumer4<
                AuthViewModel,
                TrainingViewModel,
                UserViewModel,
                DogViewModel
              >(
                builder: (context, authVM, trainingVM, userVM, dogVM, child) {
                  if (trainingVM.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: _hudCyan),
                    );
                  }

                  final currentRa = HandlerIdentityService.raFromUser(
                    authVM.user,
                  );
                  _ensureBadgeProgressLoaded(currentRa);
                  _ensureWeeklyMissionsLoaded(currentRa);

                  final currentUser = userVM.users
                      .cast<UserModel?>()
                      .firstWhere(
                        (user) => user?.ra == currentRa,
                        orElse: () => null,
                      );

                  return TabBarView(
                    children: [
                      _buildTrainingRanking(trainingVM, userVM, dogVM),
                      _buildXpRanking(userVM),
                      _buildBadgeProgressTab(currentUser),
                    ],
                  );
                },
              ),
      ),
    );
  }

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
    late final Color rankColor;
    late final IconData rankIcon;

    if (index == 0) {
      rankColor = const Color(0xFFFFD700);
      rankIcon = Icons.emoji_events_rounded;
    } else if (index == 1) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.military_tech_rounded;
    } else if (index == 2) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.military_tech_rounded;
    } else {
      rankColor = Colors.white24;
      rankIcon = Icons.star_border_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: index == 0
            ? _hudPanelAlt.withAlpha(245)
            : _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: index == 0 ? rankColor.withAlpha(190) : _hudCyan.withAlpha(55),
          width: index == 0 ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (index == 0 ? rankColor : _hudCyan).withAlpha(
              index == 0 ? 45 : 18,
            ),
            blurRadius: index == 0 ? 24 : 14,
            spreadRadius: index == 0 ? 1 : 0,
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _hudBackground,
              backgroundImage: photoUrl != null
                  ? CachedNetworkImageProvider(photoUrl)
                  : null,
              child: photoUrl == null
                  ? Text(
                      callsign.isNotEmpty ? callsign[0].toUpperCase() : 'O',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            if (index < 3)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hudBackground,
                  border: Border.all(color: rankColor.withAlpha(160)),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(rankIcon, size: 16, color: rankColor),
              ),
          ],
        ),
        title: Text(
          '${index + 1}º  $title',
          style: GoogleFonts.oxanium(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: index == 0 ? 18 : 16,
            letterSpacing: 0.8,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: GoogleFonts.robotoMono(
              color: index == 0 ? rankColor.withAlpha(215) : Colors.white60,
              fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        trailing: index == 0
            ? Icon(
                isXp ? Icons.star_rounded : Icons.local_fire_department_rounded,
                color: isXp ? rankColor : _hudAmber,
                size: 32,
              )
            : null,
      ),
    );
  }

  Widget _buildBadgeProgressTab(UserModel? currentUser) {
    if (currentUser == null ||
        _badgeProgressFuture == null ||
        _weeklyMissionFuture == null) {
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
      future: _badgeProgressFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _hudCyan),
          );
        }

        final progressMap = snapshot.data ?? const <String, BadgeProgress>{};
        final levelProgress = GamificationService.getLevelProgress(
          currentUser.xp,
        );

        final lockedBadges =
            BadgesConfig.badges
                .where((badge) => !currentUser.userBadges.contains(badge.id))
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

        final nextBadge = lockedBadges.first;
        final nextBadgeProgress = progressMap[nextBadge.id]!;
        final remainingBadges = lockedBadges.skip(1).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            FutureBuilder<List<WeeklyMissionProgress>>(
              future: _weeklyMissionFuture,
              builder: (context, missionSnapshot) {
                if (missionSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: _hudCyan),
                    ),
                  );
                }

                final missions =
                    missionSnapshot.data ?? const <WeeklyMissionProgress>[];

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _hudPanel.withAlpha(230),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _hudCyan.withAlpha(65)),
                    boxShadow: [
                      BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MISSÕES DA SEMANA',
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Conclua metas operacionais e receba bônus de XP uma vez por semana.',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...missions.map(
                        (mission) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: WeeklyMissionCard(mission: mission),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            LevelProgressCard(progress: levelProgress),
            const SizedBox(height: 14),
            NextBadgeHighlightCard(
              badge: nextBadge,
              progress: nextBadgeProgress,
            ),
            if (remainingBadges.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _hudPanel.withAlpha(230),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _hudCyan.withAlpha(65)),
                  boxShadow: [
                    BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 16),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OUTROS TROFÉUS EM PROGRESSO',
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Acompanhe o que falta para desbloquear as próximas conquistas.',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...remainingBadges.map((badge) {
                      final progress = progressMap[badge.id]!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BadgeProgressCard(
                          badge: badge,
                          progress: progress,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
