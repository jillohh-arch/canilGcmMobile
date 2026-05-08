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

part 'ranking_screen_sections.dart';
part 'ranking_rank_card.dart';
part 'ranking_badge_progress_tab.dart';

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
}
