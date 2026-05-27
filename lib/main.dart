import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/app_shell/presentation/screens/main_root_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'package:canil_gcm/features/auth/presentation/screens/login_screen.dart';
import 'package:canil_gcm/features/auth/presentation/screens/splash_screen.dart';

final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => UserViewModel()),
        ChangeNotifierProvider(create: (_) => DogViewModel()),
        ChangeNotifierProvider(create: (_) => TrainingViewModel()),
        ChangeNotifierProvider(create: (_) => HealthViewModel()),
        ChangeNotifierProvider(create: (_) {
          final firestore = FirebaseFirestore.instance;
          return OccurrenceViewModel(
            repository: OccurrenceRepository(firestore),
            eventRepository: OccurrenceEventRepository(firestore),
          );
        }),
        ChangeNotifierProvider(create: (_) => ShiftViewModel()),
        ChangeNotifierProvider(create: (_) => NutritionViewModel()),
      ],
      child: const GcmK9App(),
    ),
  );
}

class GcmK9App extends StatelessWidget {
  const GcmK9App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canil K9',
      theme: AppTheme.darkTheme,
      navigatorKey: globalNavigatorKey,
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

          // Sem auth → Login
          if (authVM.user == null) {
            return const LoginScreen();
          }

          // Carregando dados do usuário/turno → Splash
          if (isLoadingCurrentUser || shiftVM.isLoading) {
            return const SplashScreen();
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
}
