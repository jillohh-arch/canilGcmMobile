import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/data/dashboard_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/features/profiles/presentation/screens/handler_profile_page.dart';
import 'package:canil_gcm/core/services/dog_fitness_service.dart';

import 'dynamic_activity_sheet.dart';

part 'active_shift_header.dart';
part 'active_shift_indicators_card.dart';
part 'active_shift_quick_actions.dart';
part 'active_shift_alerts_section.dart';
part 'active_shift_today_section.dart';
part 'active_shift_dog_profile_card.dart';
part 'active_shift_profile_cards.dart';
part 'active_shift_cockpit.dart';
part 'active_shift_readiness.dart';
part 'active_shift_dog_switcher.dart';

class ActiveShiftDashboardScreen extends StatefulWidget {
  const ActiveShiftDashboardScreen({super.key});

  @override
  State<ActiveShiftDashboardScreen> createState() =>
      _ActiveShiftDashboardScreenState();
}

class _ActiveShiftDashboardScreenState
    extends State<ActiveShiftDashboardScreen> {
  final DogService _dogService = DogService();
  final DashboardService _dashboardService = DashboardService();
  final VehicleService _vehicleService = VehicleService();
  String? _lastFetchedDogId;

  // Dados dinâmicos carregados do Firestore
  List<QuickAction> _quickActions = [];
  List<DashboardAlert> _alerts = [];
  int _totalAlerts = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogId = shiftVM.activeDogId;

    if (dogId != null && dogId != _lastFetchedDogId) {
      _lastFetchedDogId = dogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDashboardData(dogId);
        Provider.of<TrainingViewModel>(
          context,
          listen: false,
        ).fetchTrainingsForDog(dogId);
        Provider.of<HealthViewModel>(
          context,
          listen: false,
        ).fetchHealthLogsForDog(dogId);
        Provider.of<OccurrenceViewModel>(
          context,
          listen: false,
        ).watchByDog(dogId);
        Provider.of<NutritionViewModel>(
          context,
          listen: false,
        ).loadForDog(dogId);
        Provider.of<NutritionViewModel>(
          context,
          listen: false,
        ).loadFullHistory(dogId);

        final dogVM = Provider.of<DogViewModel>(context, listen: false);
        final userVM = Provider.of<UserViewModel>(context, listen: false);
        final authVM = Provider.of<AuthViewModel>(context, listen: false);
        final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';

        try {
          final dog = dogVM.dogs.firstWhere((d) => d.id == dogId);
          _checkReadinessStreakTracker(dog, currentRa, userVM, dogVM);
        } catch (_) {}
      });
    }
  }

  Future<void> _loadDashboardData(String dogId) async {
    List<QuickAction> quickActions = [];
    List<DashboardAlert> alerts = [];
    int totalAlerts = 0;

    try {
      quickActions = await _dashboardService.getQuickActions();
    } catch (_) {}
    try {
      alerts = await _dashboardService.getActiveAlerts(dogId);
    } catch (_) {}
    try {
      totalAlerts = await _dashboardService.countActiveAlerts(dogId);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _quickActions = quickActions;
      _alerts = alerts;
      _totalAlerts = totalAlerts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      ShiftViewModel,
      DogViewModel,
      AuthViewModel,
      UserViewModel
    >(
      builder: (context, shiftVM, dogVM, authVM, userVM, _) {
        if (!shiftVM.hasActiveShift) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Text(
                'Nenhum turno ativo.\nInicie um turno para acessar o dashboard.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final callsign = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );
        final dogId = shiftVM.activeDogId!;

        return StreamBuilder<Dog?>(
          stream: _dogService.watchDog(dogId),
          builder: (context, snapshot) {
            final dog = snapshot.data ?? _localDogFallback(dogVM, dogId);
            if (dog == null) {
              return Scaffold(
                backgroundColor: AppTheme.background,
                body: Center(
                  child: Text(
                    'K9 do turno não encontrado.',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                ),
              );
            }
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: AppTheme.transparent,
                  systemNavigationBarColor: AppTheme.surfaceNavigation,
                  systemNavigationBarIconBrightness: Brightness.light,
                ),
                child: _buildCockpit(context, dog, callsign),
              ),
            );
          },
        );
      },
    );
  }
}
