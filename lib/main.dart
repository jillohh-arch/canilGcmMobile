import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/onboarding_service.dart';
import 'package:canil_gcm/core/services/push_notification_service.dart';
import 'package:canil_gcm/features/app_shell/presentation/screens/main_root_screen.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_minimum_duration.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_screen.dart';
import 'package:canil_gcm/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'package:canil_gcm/features/auth/presentation/screens/login_screen.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

/// Messenger global para feedback que sobrevive à troca de tela (ex.: ao
/// encerrar turno, o widget de origem é desmontado antes do snackbar aparecer).
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(
    canilK9FirebaseMessagingBackgroundHandler,
  );

  await _activateAppCheckSafely();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => UserViewModel()),
        ChangeNotifierProvider(create: (_) => DogViewModel()),
        ChangeNotifierProvider(create: (_) => TrainingViewModel()),
        ChangeNotifierProvider(create: (_) => HealthViewModel()),
        ChangeNotifierProvider(
          create: (_) {
            final firestore = FirebaseFirestore.instance;
            return OccurrenceViewModel(
              repository: OccurrenceRepository(firestore),
              eventRepository: OccurrenceEventRepository(firestore),
            );
          },
        ),
        ChangeNotifierProvider(create: (_) => ShiftViewModel()),
        ChangeNotifierProvider(create: (_) => ShiftGroupViewModel()),
        ChangeNotifierProvider(create: (_) => NutritionViewModel()),
      ],
      child: const GcmK9App(),
    ),
  );

  unawaited(_initializePushNotificationsSafely());
}

Future<void> _activateAppCheckSafely() async {
  try {
    await FirebaseAppCheck.instance
        .activate(providerAndroid: const AndroidDebugProvider())
        .timeout(const Duration(seconds: 6));
  } catch (e, stack) {
    debugPrint('[Bootstrap] App Check nao bloqueou a inicializacao: $e');
    debugPrintStack(stackTrace: stack);
  }
}

Future<void> _initializePushNotificationsSafely() async {
  try {
    await PushNotificationService()
        .initialize(navigatorKey: globalNavigatorKey)
        .timeout(const Duration(seconds: 8));
  } catch (e, stack) {
    debugPrint('[Bootstrap] Push/FCM nao bloqueou a inicializacao: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class GcmK9App extends StatefulWidget {
  const GcmK9App({super.key});

  @override
  State<GcmK9App> createState() => _GcmK9AppState();
}

class _GcmK9AppState extends State<GcmK9App> {
  bool _showOnboarding = false;
  bool _onboardingChecked = false;

  // Política visual de duração mínima (800ms)
  Timer? _minDurationTimer;
  bool _minDurationElapsed = false;
  bool _hasStartedMinDuration = false;

  void _startMinDurationIfNeeded() {
    if (_hasStartedMinDuration) return;
    _hasStartedMinDuration = true;
    _minDurationElapsed = false;
    _minDurationTimer?.cancel();
    _minDurationTimer = Timer(k9OpsLoadingMinDuration, () {
      if (mounted) {
        setState(() {
          _minDurationElapsed = true;
        });
      }
    });
  }

  void _resetMinDuration() {
    _minDurationTimer?.cancel();
    _minDurationTimer = null;
    _hasStartedMinDuration = false;
    _minDurationElapsed = false;
  }

  @override
  void dispose() {
    _minDurationTimer?.cancel();
    super.dispose();
  }

  void _onOnboardingComplete() {
    setState(() {
      _showOnboarding = false;
      _onboardingChecked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canil K9',
      theme: AppTheme.darkTheme,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: globalNavigatorKey,
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      builder: (context, child) {
        return child ?? const SizedBox.shrink();
      },
      home: Consumer3<AuthViewModel, ShiftViewModel, UserViewModel>(
        builder: (context, authVM, shiftVM, userVM, _) {
          final currentRa = HandlerIdentityService.raFromUser(authVM.user);
          final isLoadingCurrentUser =
              authVM.user != null &&
              currentRa != null &&
              !userVM.hasUserForRa(currentRa) &&
              !userVM.hasLoadedInitialData;

          // Sem auth → Login (cancela e reseta qualquer janela de loading anterior)
          if (authVM.user == null) {
            _resetMinDuration();
            return const LoginScreen();
          }

          final isTechnicalLoadingActive =
              isLoadingCurrentUser || shiftVM.isLoading;
          final shouldHoldVisual =
              K9OpsLoadingDurationPolicy.shouldHoldVisualLoading(
                isTechnicalLoadingActive: isTechnicalLoadingActive,
                isMinDurationElapsed: _minDurationElapsed,
              );

          // Carregando dados do usuário/turno ou segurando a janela visual mínima de 800ms
          if (isTechnicalLoadingActive || shouldHoldVisual) {
            _startMinDurationIfNeeded();
            final loadingState = K9OpsLoadingDurationPolicy.resolveLoadingState(
              isLoadingCurrentUser: isLoadingCurrentUser,
              shiftIsLoading: shiftVM.isLoading,
            );
            return K9OpsLoadingScreen(
              stage: loadingState.stage,
              progress: loadingState.progress,
            );
          }

          // Check onboarding after data is loaded and minimum visual window completed
          if (!_onboardingChecked) {
            _checkOnboarding();
            _startMinDurationIfNeeded();
            final loadingState = K9OpsLoadingDurationPolicy.resolveLoadingState(
              isLoadingCurrentUser: isLoadingCurrentUser,
              shiftIsLoading: shiftVM.isLoading,
            );
            return K9OpsLoadingScreen(
              stage: loadingState.stage,
              progress: loadingState.progress,
            );
          }

          // Show onboarding if needed
          if (_showOnboarding) {
            return OnboardingScreen(onComplete: _onOnboardingComplete);
          }

          // Sem turno ativo → Seleção de cão
          if (!shiftVM.hasActiveShift) {
            return const ShiftAssumptionScreen();
          }

          // Turno ativo → Dashboard
          return const MainRootScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  Future<void> _checkOnboarding() async {
    if (_onboardingChecked) return;
    final service = OnboardingService();
    final hasSeen = await service.hasCompletedOnboarding();
    if (mounted) {
      setState(() {
        _onboardingChecked = true;
        _showOnboarding = !hasSeen;
      });
    }
  }
}
