import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'theme/app_theme.dart';
import 'viewmodels/dashboard_viewmodel.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/user_viewmodel.dart';
import 'viewmodels/dog_viewmodel.dart';
import 'viewmodels/training_viewmodel.dart';
import 'viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'services/handler_identity_service.dart';
import 'views/main_root_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'views/auth/login_screen.dart';
import 'widgets/gamification_listener.dart';

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
        ChangeNotifierProvider(create: (_) => DashboardViewModel()),
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
      title: 'GCM K9',
      theme: AppTheme.darkTheme,
      navigatorKey: globalNavigatorKey,
      builder: (context, child) {
        return GamificationListener(child: child ?? const SizedBox.shrink());
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
              if (authVM.user == null)
                const MaterialPage(key: ValueKey('Login'), child: LoginScreen())
              else ...[
                if (isLoadingCurrentUser || shiftVM.isLoading)
                  const MaterialPage(
                    key: ValueKey('LoadingSession'),
                    child: Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (!shiftVM.hasActiveShift)
                  const MaterialPage(
                    key: ValueKey('Assumption'),
                    child: ShiftAssumptionScreen(),
                  ),
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
