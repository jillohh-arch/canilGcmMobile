// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/data/shift_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/auth/data/auth_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/core/services/dog_fitness_service.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform() : _app = _FakeFirebaseAppPlatform();
  final FirebaseAppPlatform _app;
  @override
  List<FirebaseAppPlatform> get apps => <FirebaseAppPlatform>[_app];
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;
  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
      : super(
          defaultFirebaseAppName,
          const FirebaseOptions(
            apiKey: 'fake-api-key',
            appId: 'fake-app-id',
            messagingSenderId: 'fake-sender-id',
            projectId: 'k9-ops-staging',
          ),
        );
}

class _MockShiftService extends ShiftService {
  String? lastStartDogId;
  String? lastAssumeDogId;
  String? lastAssumeRole;
  Vehicle? lastAssumeVehicle;
  int startShiftCallCount = 0;
  int assumeVehicleCallCount = 0;

  @override
  Future<void> startShift({
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    String? shiftGroupId,
    String? shiftGroupCode,
    String? shiftGroupLabel,
    String dogId = '',
    required DateTime startedAt,
    Vehicle? vehicle,
  }) async {
    startShiftCallCount++;
    lastStartDogId = dogId;
  }

  @override
  Future<void> assumeVehicle({
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    required String dogId,
    required Vehicle vehicle,
    required String role,
  }) async {
    assumeVehicleCallCount++;
    lastAssumeDogId = dogId;
    lastAssumeRole = role;
    lastAssumeVehicle = vehicle;
  }
}

class _MockShiftAuthorizationGateway implements ShiftAuthorizationGateway {
  final List<ShiftAuthorizationCommand> commandsReceived = [];
  ShiftAuthorizationResult? resultToReturn;

  @override
  Future<ShiftAuthorizationResult> execute(ShiftAuthorizationCommand command) async {
    commandsReceived.add(command);
    return resultToReturn ??
        const ShiftAuthorizationResult(
          action: ShiftAuthorizedAction.assumeVehicle,
          outcome: ShiftAuthorizationOutcome.allowed,
          dogId: 'stg-dog-tc1-001',
          restrictions: [],
          acknowledgementRecorded: false,
          shiftId: 'shift-1',
          wasNoOp: false,
        );
  }
}

class _MockAuthService extends AuthService {
  @override
  Stream<fb_auth.User?> get authStateChanges => const Stream.empty();

  @override
  fb_auth.User? get currentUser => null;
}

class _MockShiftGroupViewModel extends ChangeNotifier implements ShiftGroupViewModel {
  @override
  UserShiftInfo? get currentShift => null;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  bool get isWithinShiftHours => false;

  @override
  bool get shouldStartShift => false;

  @override
  Future<void> refresh() async {}
}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = _FakeFirebasePlatform();
  });

  const testVehicle = Vehicle(
    id: 'STG-TC1-VTR-01',
    name: 'VTR-01',
    prefix: '01',
    modelName: 'Hilux',
    crewSize: 2,
    unit: 'Canil',
    active: true,
  );

  final testDog = Dog(
    id: 'stg-dog-tc1-001',
    name: 'STG TC1 OPERATIONAL DOG',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime.now().subtract(const Duration(days: 365 * 3)),
    conductorRa: '990001',
    status: 'Ativo',
  );

  group('CT.MOBILE-SHIFT.NO-K9-FLOW-REPAIR-R1 — Shift Flow Repair Tests', () {
    // ─────────────────────────────────────────────────────────
    // Test A: Start shift without K9
    // ─────────────────────────────────────────────────────────
    test('A. start shift without K9 bypasses OP-AUTH and sets empty dog session', () async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990002');

      // Start shift without K9 (dogId: '')
      await shiftVM.startShift('', vehicle: testVehicle, role: 'motorista');

      // Verify ShiftService was invoked with dogId: ''
      expect(mockService.startShiftCallCount, 1);
      expect(mockService.lastStartDogId, '');

      // Verify OP-AUTH execute was NOT called
      expect(mockGateway.commandsReceived, isEmpty);

      // Verify local session state
      expect(shiftVM.session, isNotNull);
      expect(shiftVM.session?.hasK9, isFalse);
      expect(shiftVM.activeDogId?.isEmpty ?? true, isTrue);
      expect(shiftVM.session?.dogId, '');
      expect(shiftVM.hasActiveShift, isTrue);
    });

    // ─────────────────────────────────────────────────────────
    // Test B: No-K9 active cockpit renders properly
    // ─────────────────────────────────────────────────────────
    testWidgets('B. no-K9 active cockpit renders single identity, Sem viatura, ASSUMIR POSTO, and end-shift menu', (tester) async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990002');

      // Active shift without dog and without vehicle
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': '',
          'status': 'active',
        }),
      );

      final authVM = AuthViewModel();
      final userVM = UserViewModel();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
            ChangeNotifierProvider<AuthViewModel>.value(value: authVM),
            ChangeNotifierProvider<UserViewModel>.value(value: userVM),
            ChangeNotifierProvider<ShiftGroupViewModel>.value(value: _MockShiftGroupViewModel()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    BinomioHeader(
                      dog: null,
                      subtitle: 'Em serviço · Sem K9',
                      showStatusDot: false,
                      showNotificationButton: false,
                    ),
                    EmServicoCard(
                      dog: null,
                      callsign: 'GCM 990002',
                      conductorPhotoUrl: null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Single identity renders with "Em serviço · Sem K9"
      expect(find.text('Em serviço · Sem K9'), findsNWidgets(2));
      expect(find.text('GCM 990002'), findsWidgets);

      // 2. Guarnição Sem Viatura renders cleanly
      expect(find.text('Sem viatura'), findsOneWidget);
      expect(find.text('ASSUMIR POSTO'), findsOneWidget);

      // 3. Open menu button and verify actions
      final menuButton = find.byIcon(Icons.menu_rounded);
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // "Encerrar turno", "Meu perfil", "Associar K9" are reachable!
      expect(find.text('Encerrar turno'), findsOneWidget);
      expect(find.text('Meu perfil'), findsOneWidget);
      expect(find.text('Associar K9'), findsOneWidget);
      // "Meu K9" is omitted for no-K9 operator
      expect(find.text('Meu K9'), findsNothing);
    });

    // ─────────────────────────────────────────────────────────
    // Test C: assumeVehicle succeeds with active shift + no K9
    // ─────────────────────────────────────────────────────────
    test('C. assumeVehicle succeeds with active shift + no K9 without OP-AUTH call', () async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990002');

      // Seed active shift without K9
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': '',
          'status': 'active',
        }),
      );

      await shiftVM.assumeVehicle(testVehicle, role: 'auxiliar_1', name: 'GCM 990002');

      // Verify ShiftService.assumeVehicle was called with dogId: ''
      expect(mockService.assumeVehicleCallCount, 1);
      expect(mockService.lastAssumeDogId, '');
      expect(mockService.lastAssumeRole, 'auxiliar_1');
      expect(mockService.lastAssumeVehicle?.id, 'STG-TC1-VTR-01');

      // Verify OP-AUTH was bypassed (no dog introduced)
      expect(mockGateway.commandsReceived, isEmpty);

      // Verify local session updated
      expect(shiftVM.vehicleId, 'STG-TC1-VTR-01');
      expect(shiftVM.vehicleLabel, 'VTR-01 01');
      expect(shiftVM.crewRole, 'auxiliar_1');
      expect(shiftVM.error, isNull);
    });

    // ─────────────────────────────────────────────────────────
    // Test D: assumeVehicle with K9 still routes through OP-AUTH
    // ─────────────────────────────────────────────────────────
    test('D. assumeVehicle with K9 still routes through OP-AUTH', () async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990001');

      // Seed active shift WITH K9
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'service_dog_id': 'stg-dog-tc1-001',
          'status': 'active',
        }),
      );

      await shiftVM.assumeVehicle(testVehicle, role: 'motorista', name: 'GCM 990001');

      // Verify OP-AUTH WAS called with exact command
      expect(mockGateway.commandsReceived.length, 1);
      final command = mockGateway.commandsReceived.first;
      expect(command.action, ShiftAuthorizedAction.assumeVehicle);
      expect(command.dogId, 'stg-dog-tc1-001');
      expect(command.role, 'motorista');
      expect(command.vehicle?.id, 'STG-TC1-VTR-01');

      // Verify local session updated
      expect(shiftVM.vehicleId, 'STG-TC1-VTR-01');
      expect(shiftVM.crewRole, 'motorista');
    });

    // ─────────────────────────────────────────────────────────
    // Test E: No client path can inject/change dog through vehicle assumption
    // ─────────────────────────────────────────────────────────
    test('E. no client path can inject operational dog through vehicle assumption', () async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990002');

      // Shift without K9
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': '',
          'status': 'active',
        }),
      );

      await shiftVM.assumeVehicle(testVehicle, role: 'auxiliar_1');

      // Even after assuming vehicle, dogId remains ''
      expect(mockService.lastAssumeDogId, '');
      expect(shiftVM.session?.dogId, '');
      expect(shiftVM.session?.hasK9, isFalse);
      expect(shiftVM.activeDogId?.isEmpty ?? true, isTrue);
    });

    // ─────────────────────────────────────────────────────────
    // Test F: Long dog name does not overflow in DogSelectionCard
    // ─────────────────────────────────────────────────────────
    testWidgets('F. long dog name does not overflow in DogSelectionCard', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: DogSelectionCard(
                  dog: testDog,
                  fitness: const DogFitnessResult(
                    status: DogFitnessStatus.apt,
                    pendencies: [],
                  ),
                  isSelected: false,
                  isTitular: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('STG TC1 OPERATIONAL DOG'), findsOneWidget);
      expect(find.text('SEU CÃO'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────
    // Test G: Existing K9 cockpit header renders dog info and Trocar K9 menu
    // ─────────────────────────────────────────────────────────
    testWidgets('G. existing K9 cockpit header renders dog info and Trocar K9 menu', (tester) async {
      final mockService = _MockShiftService();
      final mockGateway = _MockShiftAuthorizationGateway();
      final mockAuth = _MockAuthService();

      final shiftVM = ShiftViewModel(
        authorizationGateway: mockGateway,
        shiftService: mockService,
        authService: mockAuth,
      );
      shiftVM.setBoundRaForTesting('990001');

      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'service_dog_id': 'stg-dog-tc1-001',
          'status': 'active',
        }),
      );

      final authVM = AuthViewModel();
      final userVM = UserViewModel();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
            ChangeNotifierProvider<AuthViewModel>.value(value: authVM),
            ChangeNotifierProvider<UserViewModel>.value(value: userVM),
            ChangeNotifierProvider<ShiftGroupViewModel>.value(value: _MockShiftGroupViewModel()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BinomioHeader(
                  dog: testDog,
                  subtitle: 'Turno ativo · há 5min',
                  showStatusDot: false,
                  showNotificationButton: false,
                  onSwitchDog: () {},
                  onProfileTap: () {},
                  onDogHealthTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('STG TC1 OPERATIONAL DOG'), findsOneWidget);
      expect(find.text('Turno ativo · há 5min'), findsOneWidget);

      final menuButton = find.byIcon(Icons.menu_rounded);
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      expect(find.text('Meu K9'), findsOneWidget);
      expect(find.text('Trocar K9'), findsOneWidget);
      expect(find.text('Encerrar turno'), findsOneWidget);
    });
  });
}
