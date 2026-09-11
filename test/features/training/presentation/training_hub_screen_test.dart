// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/auth/data/auth_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_service.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_hub_screen.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
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

class _SpyDogService extends DogService {
  final List<String> watchDogCalls = [];
  final StreamController<Dog?> dogController =
      StreamController<Dog?>.broadcast();

  @override
  Stream<Dog?> watchDog(String id) {
    watchDogCalls.add(id);
    return dogController.stream;
  }
}

class _SpyTrainingService extends TrainingService {
  final List<String> watchSpecialtiesCalls = [];
  final List<String> watchSessionsCalls = [];
  final StreamController<List<TrainingSpecialtyModel>> specialtiesController =
      StreamController<List<TrainingSpecialtyModel>>.broadcast();
  final StreamController<List<TrainingHubSession>> sessionsController =
      StreamController<List<TrainingHubSession>>.broadcast();

  @override
  Stream<List<TrainingSpecialtyModel>> watchSpecialtiesForDog(String dogId) {
    watchSpecialtiesCalls.add(dogId);
    return specialtiesController.stream;
  }

  @override
  Stream<List<TrainingHubSession>> watchSessionsForDog(String dogId) {
    watchSessionsCalls.add(dogId);
    return sessionsController.stream;
  }

  @override
  TrainingHubData buildHubData({
    required List<TrainingSpecialtyModel> specialties,
    required List<TrainingHubSession> sessions,
  }) {
    return const TrainingHubData(
      trainingsThisWeek: 0,
      specialties: [],
      recentSessions: [],
      generalTrainings: [],
      lastTrainingLabel: 'Nenhum',
      suggestedFocus: 'Geral',
    );
  }
}

class _MockShiftService extends ShiftService {}

class _MockShiftAuthorizationGateway implements ShiftAuthorizationGateway {
  @override
  Future<ShiftAuthorizationResult> execute(
    ShiftAuthorizationCommand command,
  ) async {
    return const ShiftAuthorizationResult(
      action: ShiftAuthorizedAction.assumeVehicle,
      outcome: ShiftAuthorizationOutcome.allowed,
      dogId: '',
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

class _MockDogViewModel extends ChangeNotifier implements DogViewModel {
  final List<Dog> _dogs;
  _MockDogViewModel([this._dogs = const []]);

  @override
  List<Dog> get dogs => _dogs;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockUserViewModel extends ChangeNotifier implements UserViewModel {
  @override
  String displayNameFor({
    required String? ra,
    dynamic firebaseUser,
    String fallback = 'Condutor',
  }) => 'Condutor Teste';

  @override
  UserModel? findByRa(String? ra) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockShiftGroupViewModel extends ChangeNotifier
    implements ShiftGroupViewModel {
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

Widget _buildTestTree({
  required ShiftViewModel shiftVM,
  required DogViewModel dogVM,
  required UserViewModel userVM,
  DogService? dogService,
  TrainingService? trainingService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
      ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
      ChangeNotifierProvider<UserViewModel>.value(value: userVM),
      ChangeNotifierProvider<DogViewModel>.value(value: dogVM),
      ChangeNotifierProvider<ShiftGroupViewModel>.value(
        value: _MockShiftGroupViewModel(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TrainingHubScreen(
        dogService: dogService,
        trainingService: trainingService,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final testDog = Dog(
    id: 'dog-test-01',
    name: 'STG APOLLO',
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2021, 6, 1),
    conductorRa: '990001',
    status: 'Ativo',
  );

  group('F50.MOBILE-NO-K9-TRAINING-GUARD-R1 — Contract & Regression Tests', () {
    test('0. normalizeDogId treats null, empty, and whitespace as absent', () {
      expect(TrainingHubScreenState.normalizeDogId(null), isNull);
      expect(TrainingHubScreenState.normalizeDogId(''), isNull);
      expect(TrainingHubScreenState.normalizeDogId('   '), isNull);
      expect(TrainingHubScreenState.normalizeDogId('\t\n  '), isNull);
      expect(
        TrainingHubScreenState.normalizeDogId('dog-test-01'),
        'dog-test-01',
      );
      expect(
        TrainingHubScreenState.normalizeDogId('  dog-test-01  '),
        'dog-test-01',
      );
    });

    testWidgets('1. activeDogId == null -> no dog stream binding', (
      tester,
    ) async {
      final spyDog = _SpyDogService();
      final spyTraining = _SpyTrainingService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: _MockShiftAuthorizationGateway(),
        shiftService: _MockShiftService(),
        authService: _MockAuthService(),
      );
      // Active shift session with null dogId (simulating absent activeDogId)
      shiftVM.setSessionForTesting(
        ActiveShiftSession(
          shiftId: 'shift-null-k9',
          handlerId: '990001',
          dogId: '',
          serviceDogId: null,
          startedAt: DateTime.now(),
          status: 'active',
        ),
      );

      await tester.pumpWidget(
        _buildTestTree(
          shiftVM: shiftVM,
          dogVM: _MockDogViewModel([testDog]),
          userVM: _MockUserViewModel(),
          dogService: spyDog,
          trainingService: spyTraining,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final state = tester.state<TrainingHubScreenState>(
        find.byType(TrainingHubScreen),
      );
      expect(state.boundDogId, isNull);
      expect(state.hasBoundDogStreams, isFalse);
      expect(spyDog.watchDogCalls, isEmpty);
      expect(spyTraining.watchSpecialtiesCalls, isEmpty);
      expect(spyTraining.watchSessionsCalls, isEmpty);
      expect(find.text('Turno ativo sem K9 associado'), findsOneWidget);
    });

    testWidgets('2. activeDogId == "" -> no dog stream binding', (
      tester,
    ) async {
      final spyDog = _SpyDogService();
      final spyTraining = _SpyTrainingService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: _MockShiftAuthorizationGateway(),
        shiftService: _MockShiftService(),
        authService: _MockAuthService(),
      );
      // Canonical no-K9 session: dogId == '', serviceDogId == null -> effectiveServiceDogId == ''
      shiftVM.setSessionForTesting(
        ActiveShiftSession(
          shiftId: 'shift-empty-k9',
          handlerId: '990001',
          dogId: '',
          serviceDogId: null,
          startedAt: DateTime.now(),
          status: 'active',
        ),
      );

      expect(shiftVM.activeDogId, '');

      await tester.pumpWidget(
        _buildTestTree(
          shiftVM: shiftVM,
          dogVM: _MockDogViewModel([testDog]),
          userVM: _MockUserViewModel(),
          dogService: spyDog,
          trainingService: spyTraining,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final state = tester.state<TrainingHubScreenState>(
        find.byType(TrainingHubScreen),
      );
      expect(state.boundDogId, isNull);
      expect(state.hasBoundDogStreams, isFalse);
      expect(spyDog.watchDogCalls, isEmpty);
      expect(spyTraining.watchSpecialtiesCalls, isEmpty);
      expect(spyTraining.watchSessionsCalls, isEmpty);
      expect(find.text('Turno ativo sem K9 associado'), findsOneWidget);
    });

    testWidgets('3. activeDogId == whitespace -> no dog stream binding', (
      tester,
    ) async {
      final spyDog = _SpyDogService();
      final spyTraining = _SpyTrainingService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: _MockShiftAuthorizationGateway(),
        shiftService: _MockShiftService(),
        authService: _MockAuthService(),
      );
      shiftVM.setSessionForTesting(
        ActiveShiftSession(
          shiftId: 'shift-whitespace-k9',
          handlerId: '990001',
          dogId: '   \t  \n ',
          serviceDogId: '  \t ',
          startedAt: DateTime.now(),
          status: 'active',
        ),
      );

      await tester.pumpWidget(
        _buildTestTree(
          shiftVM: shiftVM,
          dogVM: _MockDogViewModel([testDog]),
          userVM: _MockUserViewModel(),
          dogService: spyDog,
          trainingService: spyTraining,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final state = tester.state<TrainingHubScreenState>(
        find.byType(TrainingHubScreen),
      );
      expect(state.boundDogId, isNull);
      expect(state.hasBoundDogStreams, isFalse);
      expect(spyDog.watchDogCalls, isEmpty);
      expect(spyTraining.watchSpecialtiesCalls, isEmpty);
      expect(spyTraining.watchSessionsCalls, isEmpty);
      expect(find.text('Turno ativo sem K9 associado'), findsOneWidget);
    });

    testWidgets(
      '4. transition from valid dog ID to absent dog -> unbinds/cleans up streams',
      (tester) async {
        final spyDog = _SpyDogService();
        final spyTraining = _SpyTrainingService();
        final shiftVM = ShiftViewModel(
          authorizationGateway: _MockShiftAuthorizationGateway(),
          shiftService: _MockShiftService(),
          authService: _MockAuthService(),
        );

        // Start with valid dog
        shiftVM.setSessionForTesting(
          ActiveShiftSession(
            shiftId: 'shift-transition',
            handlerId: '990001',
            dogId: 'dog-test-01',
            serviceDogId: 'dog-test-01',
            startedAt: DateTime.now(),
            status: 'active',
          ),
        );

        await tester.pumpWidget(
          _buildTestTree(
            shiftVM: shiftVM,
            dogVM: _MockDogViewModel([testDog]),
            userVM: _MockUserViewModel(),
            dogService: spyDog,
            trainingService: spyTraining,
          ),
        );
        await tester.pump();

        final state = tester.state<TrainingHubScreenState>(
          find.byType(TrainingHubScreen),
        );
        expect(state.boundDogId, 'dog-test-01');
        expect(state.hasBoundDogStreams, isTrue);
        expect(spyDog.watchDogCalls, ['dog-test-01']);
        expect(spyTraining.watchSpecialtiesCalls, ['dog-test-01']);
        expect(spyTraining.watchSessionsCalls, ['dog-test-01']);

        // Now transition to absent dog
        shiftVM.setSessionForTesting(
          ActiveShiftSession(
            shiftId: 'shift-transition',
            handlerId: '990001',
            dogId: '',
            serviceDogId: null,
            startedAt: DateTime.now(),
            status: 'active',
          ),
        );
        await tester.pump();

        expect(state.boundDogId, isNull);
        expect(state.hasBoundDogStreams, isFalse);
        expect(find.text('Turno ativo sem K9 associado'), findsOneWidget);
        // Ensure no subsequent call to watchDog('') occurred
        expect(spyDog.watchDogCalls, ['dog-test-01']);
      },
    );

    testWidgets('5. valid dog ID -> Training dog stream remains functional', (
      tester,
    ) async {
      final spyDog = _SpyDogService();
      final spyTraining = _SpyTrainingService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: _MockShiftAuthorizationGateway(),
        shiftService: _MockShiftService(),
        authService: _MockAuthService(),
      );

      shiftVM.setSessionForTesting(
        ActiveShiftSession(
          shiftId: 'shift-valid-k9',
          handlerId: '990001',
          dogId: 'dog-test-01',
          serviceDogId: 'dog-test-01',
          startedAt: DateTime.now(),
          status: 'active',
        ),
      );

      await tester.pumpWidget(
        _buildTestTree(
          shiftVM: shiftVM,
          dogVM: _MockDogViewModel([testDog]),
          userVM: _MockUserViewModel(),
          dogService: spyDog,
          trainingService: spyTraining,
        ),
      );
      await tester.pump();

      final state = tester.state<TrainingHubScreenState>(
        find.byType(TrainingHubScreen),
      );
      expect(state.boundDogId, 'dog-test-01');
      expect(state.hasBoundDogStreams, isTrue);
      expect(spyDog.watchDogCalls, ['dog-test-01']);
      expect(find.text('Treinos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '6. no Firestore .doc("") path is reached through Training Hub path',
      (tester) async {
        final fakeFirestore = FakeFirebaseFirestore();
        // Use real services backed by FakeFirebaseFirestore
        final realDogService = DogService(firestore: fakeFirestore);
        final realTrainingService = TrainingService(firestore: fakeFirestore);

        final shiftVM = ShiftViewModel(
          authorizationGateway: _MockShiftAuthorizationGateway(),
          shiftService: _MockShiftService(),
          authService: _MockAuthService(),
        );

        // Active shift with empty string dog ID
        shiftVM.setSessionForTesting(
          ActiveShiftSession(
            shiftId: 'shift-real-services',
            handlerId: '990001',
            dogId: '',
            serviceDogId: null,
            startedAt: DateTime.now(),
            status: 'active',
          ),
        );

        await tester.pumpWidget(
          _buildTestTree(
            shiftVM: shiftVM,
            dogVM: _MockDogViewModel([testDog]),
            userVM: _MockUserViewModel(),
            dogService: realDogService,
            trainingService: realTrainingService,
          ),
        );
        await tester.pump();

        // No ArgumentError or runtime exception from .doc("")
        expect(tester.takeException(), isNull);
        expect(find.text('Turno ativo sem K9 associado'), findsOneWidget);
      },
    );
  });
}
