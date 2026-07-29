import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/permission_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/app_shell/presentation/main_root_nav_metrics.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/production_health_timeline_flag_provider_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/production_health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent_session.dart';
import 'package:canil_gcm/features/health/presentation/screens/dog_health_prontuario_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_flags.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_hub_screen.dart';
import 'package:canil_gcm/main.dart';

part 'main_root_actions.dart';
part 'main_root_action_sheet.dart';
part 'main_root_exit_dialog.dart';
part 'main_root_widgets.dart';

class MainRootScreen extends StatefulWidget {
  const MainRootScreen({super.key});

  @override
  State<MainRootScreen> createState() => _MainRootScreenState();
}

class _MainRootScreenState extends State<MainRootScreen> {
  int _currentIndex = 0;
  String? _lastOccurrenceWatchDogId;
  DateTime? _lastBackPress;
  late final List<Widget> _screens;

  /// Sessão de pending intent Nutrição (Gate 3): lifecycle = MainRoot.
  /// Sobrevive a remount de HealthV1EntryScreen (ValueKey/dog) e à aba sem cão.
  final HealthNutritionPendingIntentSession _nutritionPendingSession =
      HealthNutritionPendingIntentSession();

  /// Provider de feature flag da timeline (H3B3A).
  /// Criado uma única vez — lifecycle = MainRootScreen State.
  late final HealthTimelineFlagProvider _healthTimelineFlagProvider;

  /// Factory de composição produtiva da timeline (H3B3A).
  /// Criado uma única vez — lifecycle = MainRootScreen State.
  late final HealthTimelineShadowCompositionFactory
  _healthTimelineCompositionFactory;

  @override
  void initState() {
    super.initState();

    // H3B3A: inicialização única das dependências de timeline.
    _healthTimelineFlagProvider =
        ProductionHealthTimelineFlagProviderFactory.forRemoteConfig();
    _healthTimelineCompositionFactory =
        ProductionHealthTimelineShadowCompositionFactory.forFirestore();

    _screens = [
      ActiveShiftDashboardScreen(
        onOpenTrainingHub: () => _onTabTapped(1),
        onOpenHealthTab: () => _onTabTapped(2),
      ),
      const TrainingHubScreen(),
      _MainRootHealthTab(
        nutritionPendingSession: _nutritionPendingSession,
        timelineFlagProvider: _healthTimelineFlagProvider,
        timelineSourceForResolution:
            _healthTimelineCompositionFactory.createForResolution,
      ),
      const HistoryScreen(),
    ];
    PermissionService.requestInitialPermissions();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final activeDogId = shiftVM.activeDogId;
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final openOccurrence = occurrenceVM.openOccurrence;
    final activeOccurrence =
        openOccurrence != null && openOccurrence.dogId == activeDogId
        ? openOccurrence
        : null;
    if (activeDogId != null &&
        (activeDogId != _lastOccurrenceWatchDogId ||
            !occurrenceVM.isWatchingOpen)) {
      _lastOccurrenceWatchDogId = activeDogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<OccurrenceViewModel>(
          context,
          listen: false,
        ).watchOpen(activeDogId);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: _screens),
            if (activeDogId != null && activeOccurrence != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 100,
                child: _ActiveOccurrenceBanner(
                  occurrence: activeOccurrence,
                  dogName: _dogNameFor(context, activeDogId),
                  onTap: () => _continueActiveOccurrence(
                    context,
                    occurrence: activeOccurrence,
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(context, activeDogId),
      ),
    );
  }
}
