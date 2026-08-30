import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/config/crew_composition.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/core/theme/animation_constants.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/screens/dog_health_prontuario_screen.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/data/dashboard_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_post_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_hub_screen.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/features/profiles/presentation/screens/handler_profile_page.dart';
import 'package:canil_gcm/features/profiles/presentation/screens/k9_profile_page.dart';
import 'package:canil_gcm/core/services/dog_fitness_service.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/shift_authorization_prompts.dart';

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
  final VoidCallback? onOpenTrainingHub;
  final VoidCallback? onOpenHealthTab;

  const ActiveShiftDashboardScreen({
    super.key,
    this.onOpenTrainingHub,
    this.onOpenHealthTab,
  });

  @override
  State<ActiveShiftDashboardScreen> createState() =>
      _ActiveShiftDashboardScreenState();
}

class _ActiveShiftDashboardScreenState
    extends State<ActiveShiftDashboardScreen>
    with TickerProviderStateMixin {
  final DogService _dogService = DogService();
  final DashboardService _dashboardService = DashboardService();
  String? _lastFetchedDogId;
  bool _recoveringMissingDog = false;

  // Controller de animação de entrada das seções.
  // Criado uma vez no initState — não re-criado em rebuilds.
  late final AnimationController _sectionsAnimController;
  late final Animation<double> _sectionsAnimation;

  // Duração total da animação de entrada (compaível com HudDurations.entry + stagger).
  static const _animTotalMs = 900; // ~3 * 300ms em sequência

  // Dados dinâmicos carregados do Firestore
  List<QuickAction> _quickActions = [];
  List<DashboardAlert> _alerts = [];
  int _totalAlerts = 0;

  @override
  void initState() {
    super.initState();
    _sectionsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _animTotalMs),
    );
    _sectionsAnimation = CurvedAnimation(
      parent: _sectionsAnimController,
      curve: HudCurves.enter,
    );

    // Inicia a animação de entrada.
    // Não usa post-frame callback — initState garante que o controller
    // está disponível antes do primeiro build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldAnimate(context)) {
        _sectionsAnimController.forward();
      } else {
        // Se animações estão desativadas, vai direto ao estado final.
        _sectionsAnimController.value = 1.0;
      }
    });
  }

  @override
  void dispose() {
    _sectionsAnimController.dispose();
    super.dispose();
  }

  /// Wrapper que aplica fade + slide vertical a qualquer widget de seção.
  /// Interval controla em qual parte da timeline da animação a seção aparece.
  /// Ex: intervalo 0.0–0.33 = primeira seção, 0.11–0.44 = segunda, etc.
  Widget _animateSection(
    Widget child, {
    required double intervalStart,
    required double intervalEnd,
  }) {
    final animate = shouldAnimate(context);
    if (!animate) return child;

    return AnimatedBuilder(
      animation: _sectionsAnimation,
      builder: (context, _) {
        final progress = _sectionsAnimation.value;
        final interval = Interval(intervalStart, intervalEnd, curve: HudCurves.enter);
        final sectionProgress = interval.transform(progress.clamp(intervalStart, intervalEnd));

        return Opacity(
          opacity: sectionProgress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - sectionProgress)),
            child: child,
          ),
        );
      },
    );
  }

  /// Dashboard simplificado para turno sem K9 (motorista/apoio).
  Widget _buildNoK9Body(String callsign) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final hasVehicle = shiftVM.hasVehicle;
    final userVM = Provider.of<UserViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user);
    final userModel = userVM.findByRa(currentRa);
    final userPhoto = userModel?.photoUrl?.trim();
    final firebasePhoto = authVM.user?.photoURL?.trim();
    final conductorPhoto = userPhoto != null && userPhoto.isNotEmpty
        ? userPhoto
        : firebasePhoto != null && firebasePhoto.isNotEmpty
        ? firebasePhoto
        : null;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header simplificado — sem BinomioHeader pois não há cão
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withAlpha(12),
                    border: Border.all(color: AppTheme.primary.withAlpha(180)),
                  ),
                  child: conductorPhoto != null
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: conductorPhoto,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(
                              Icons.person_rounded,
                              color: AppTheme.primary,
                              size: 24,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        callsign,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Em serviço · Sem K9',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Scroll area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card condutor solo (sem binômio)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.textPrimary.withAlpha(7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.textPrimary.withAlpha(18)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primary.withAlpha(12),
                            border: Border.all(color: AppTheme.primary.withAlpha(180)),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: AppTheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                callsign,
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Em serviço · Sem K9',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Guarnição (se embarcado)
                  if (hasVehicle) ...[
                    const SizedBox(height: 14),
                    _GuarnicaoFaixa(hasVehicle: true, dog: null),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Monta o conteúdo do dashboard com animações de entrada escalonadas.
  Widget _buildCockpitBody(Dog dog, String callsign) {
    final userVM = Provider.of<UserViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user);
    final userModel = userVM.findByRa(currentRa);
    final userPhoto = userModel?.photoUrl?.trim();
    final firebasePhoto = authVM.user?.photoURL?.trim();
    final conductorPhoto = userPhoto != null && userPhoto.isNotEmpty
        ? userPhoto
        : firebasePhoto != null && firebasePhoto.isNotEmpty
        ? firebasePhoto
        : null;

    // Layout de intervalos para as seções.
    // Total: 0.0 → 1.0 ao longo de ~900ms.
    // Cada seção entra sequencialmente com stagger.
    const base = 0.0;
    const step = 0.14; // fração por seção

    return SafeArea(
      child: Column(
        children: [
          // Header (índice 0, entra imediatamente)
          _ShiftHeader(
            dog: dog,
            currentRa: currentRa,
            conductorPhotoUrl: conductorPhoto,
            onSwitchDog: () => _showDogSwitcher(context),
            onDogHealth: widget.onOpenHealthTab,
            onProfile: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const HandlerProfilePage(showBottomNav: false),
              ),
            ),
          ),
          // Scroll area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card unificado "EM SERVIÇO" (Binômio + Guarnição fundidos)
                  _animateSection(
                    _EmServicoCard(
                      dog: dog,
                      callsign: callsign,
                      conductorPhotoUrl: conductorPhoto,
                    ),
                    intervalStart: base + step * 1,
                    intervalEnd: base + step * 1 + 0.12,
                  ),
                  const SizedBox(height: 18),
                  _animateSection(
                    const _OperationalPulseSection(),
                    intervalStart: base + step * 2,
                    intervalEnd: base + step * 2 + 0.1,
                  ),
                  const SizedBox(height: 18),
                  _animateSection(
                    _QuickActionsSection(
                      dog: dog,
                      actions: _quickActions,
                      onOpenTrainingHub: widget.onOpenTrainingHub,
                      onOpenHealthTab: widget.onOpenHealthTab,
                    ),
                    intervalStart: base + step * 3,
                    intervalEnd: base + step * 3 + 0.12,
                  ),
                  const SizedBox(height: 18),
                  _animateSection(
                    const _LatestRecordsSection(),
                    intervalStart: base + step * 4,
                    intervalEnd: base + step * 4 + 0.1,
                  ),
                  const SizedBox(height: 18),
                  // Alertas (condicional)
                  if (_alerts.isNotEmpty) ...[
                    _animateSection(
                      _AlertsSection(
                        alerts: _alerts,
                        totalAlerts: _totalAlerts,
                      ),
                      intervalStart: base + step * 5,
                      intervalEnd: base + step * 5 + 0.1,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
    } catch (e) {
      debugPrint('[STREAM] getQuickActions falhou: $e');
    }
    try {
      alerts = await _dashboardService.getActiveAlerts(dogId);
    } catch (e) {
      debugPrint('[STREAM] getActiveAlerts falhou: $e');
    }
    try {
      totalAlerts = await _dashboardService.countActiveAlerts(dogId);
    } catch (e) {
      debugPrint('[STREAM] countActiveAlerts falhou: $e');
    }

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
        final dogId = shiftVM.activeDogId;

        // Turno sem K9 (intencional): mostrar dashboard simplificado
        if (dogId == null || dogId.trim().isEmpty) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light.copyWith(
                statusBarColor: AppTheme.transparent,
                systemNavigationBarColor: AppTheme.surfaceNavigation,
                systemNavigationBarIconBrightness: Brightness.light,
              ),
              child: _buildNoK9Body(callsign),
            ),
          );
        }

        return StreamBuilder<Dog?>(
          stream: _dogService.watchDog(dogId),
          builder: (context, snapshot) {
            final dog = snapshot.data ?? _localDogFallback(dogVM, dogId);
            final stillLoading =
                snapshot.connectionState == ConnectionState.waiting ||
                dogVM.isLoading;

            if (dog == null && stillLoading) {
              return const Scaffold(
                backgroundColor: AppTheme.background,
                body: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              );
            }

            if (dog == null) {
              return _MissingShiftDogState(
                dogId: dogId,
                recovering: _recoveringMissingDog,
                onRecover: () => _recoverMissingShiftDog(context),
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
                child: _buildCockpitBody(dog, callsign),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _recoverMissingShiftDog(BuildContext context) async {
    if (_recoveringMissingDog) return;
    HapticFeedback.mediumImpact();
    setState(() => _recoveringMissingDog = true);

    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    await shiftVM.endShift();

    if (!mounted) return;
    setState(() => _recoveringMissingDog = false);

    final error = shiftVM.error;
    if (error != null && error.trim().isNotEmpty) {
      AppFeedback.error(context, error);
    }
  }
}

class _MissingShiftDogState extends StatelessWidget {
  final String? dogId;
  final bool recovering;
  final VoidCallback onRecover;

  const _MissingShiftDogState({
    this.dogId,
    required this.recovering,
    required this.onRecover,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppTheme.surfacePanel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.warning.withAlpha(120)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.warning.withAlpha(22),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(24),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.warning.withAlpha(130),
                      ),
                    ),
                    child: const Icon(
                      Icons.pets_rounded,
                      color: AppTheme.warning,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Turno anterior precisa ser revisado',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dogId?.trim().isNotEmpty == true
                        ? 'O turno ativo aponta para um K9 que não está mais disponível no cadastro. Isso pode acontecer após limpeza do banco ou alteração administrativa.'
                        : 'O turno ativo não possui um K9 de serviço válido. Encerre este registro antigo para escolher o cão e a viatura novamente.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: recovering ? null : onRecover,
                      icon: recovering
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.background,
                              ),
                            )
                          : const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        recovering
                            ? 'Limpando turno...'
                            : 'Escolher K9 e viatura novamente',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.background,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'O histórico preservado no servidor não será apagado.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
