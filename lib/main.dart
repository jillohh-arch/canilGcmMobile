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
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
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
        ChangeNotifierProvider(create: (_) => RoutineViewModel()),
        ChangeNotifierProvider(create: (_) => HealthViewModel()),
        ChangeNotifierProvider(create: (_) => IncidentViewModel()),
        ChangeNotifierProvider(create: (_) => ShiftViewModel()),
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

          return Navigator(
            onDidRemovePage: (_) {},
            pages: [
              // Sem auth → Login
              if (authVM.user == null)
                const MaterialPage(
                  key: ValueKey('Login'),
                  child: LoginScreen(),
                )
              else ...[
                // Carregando dados do usuário/turno → Splash
                if (isLoadingCurrentUser || shiftVM.isLoading)
                  const MaterialPage(
                    key: ValueKey('Splash'),
                    child: SplashScreen(),
                  )
                // Sem turno ativo → Seleção de cão
                else if (!shiftVM.hasActiveShift)
                  const MaterialPage(
                    key: ValueKey('Assumption'),
                    child: ShiftAssumptionScreen(),
                  ),
                // Turno ativo → Dashboard
                if (!isLoadingCurrentUser &&
                    !shiftVM.isLoading &&
                    shiftVM.hasActiveShift)
                  const MaterialPage(
                    key: ValueKey('Dashboard'),
                    child: MainRootScreen(),
                  ),
              ],
            ],
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}