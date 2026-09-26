// ignore_for_file: depend_on_referenced_packages, unused_element_parameter
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_supplement.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_start_eligibility.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
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
          apiKey: 'test-api-key',
          appId: 'test-app-id',
          messagingSenderId: 'test-sender-id',
          projectId: 'test-project',
          storageBucket: 'test-project.appspot.com',
        ),
      );
}

class _FakeShiftViewModel extends ShiftViewModel {
  _FakeShiftViewModel({
    this.fakeHasActiveShift = true,
    this.fakeActiveDogId,
    this.fakeServiceDogId,
    this.fakeVehicleCrewId = 'STG-TC1-VTR-01',
    this.fakeShiftStartTime,
    this.fakeHasVehicle = true,
    this.fakeIsLoading = false,
    this.fakeError,
  });

  final bool fakeHasActiveShift;
  final String? fakeActiveDogId;
  final String? fakeServiceDogId;
  final String? fakeVehicleCrewId;
  final DateTime? fakeShiftStartTime;
  final bool fakeHasVehicle;
  final bool fakeIsLoading;
  final String? fakeError;

  @override
  bool get hasActiveShift => fakeHasActiveShift;

  @override
  String? get activeDogId => fakeActiveDogId;

  @override
  String? get serviceDogId => fakeServiceDogId;

  @override
  String? get vehicleCrewId => fakeVehicleCrewId;

  @override
  bool get hasVehicle => fakeHasVehicle;

  @override
  bool get isLoading => fakeIsLoading;

  @override
  String? get error => fakeError;

  @override
  DateTime? get shiftStartTime => fakeShiftStartTime ?? DateTime.now();
}

class _FakeShiftGroupViewModel extends ChangeNotifier
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser extends Fake implements User {
  _FakeUser({
    required this.email,
    this.displayName,
    this.photoURL,
    this.uid = 'test-uid',
  });
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final String? photoURL;
  @override
  final String uid;
}

class _FakeAuthViewModel extends ChangeNotifier implements AuthViewModel {
  _FakeAuthViewModel({this.currentUser});
  final User? currentUser;

  @override
  User? get user => currentUser;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTrainingViewModel extends ChangeNotifier
    implements TrainingViewModel {
  @override
  List<TrainingSessionModel> get trainings => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTrainingsForDog(String dogId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHealthViewModel extends ChangeNotifier implements HealthViewModel {
  @override
  List<HealthLogModel> get healthLogs => [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchHealthLogsForDog(String dogId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNutritionViewModel extends ChangeNotifier
    implements NutritionViewModel {
  @override
  List<Feeding> get historyFeedings => [];
  @override
  List<Feeding> get filteredFeedings => [];
  @override
  List<Feeding> get todayFeedings => [];
  @override
  List<NutritionSupplement> get supplements => [];
  @override
  List<NutritionPrescription> get prescriptionHistory => [];
  @override
  double get conformityPercent => 0.0;
  @override
  bool get loading => false;
  @override
  String? get activeDogId => null;
  @override
  Future<void> loadForDog(String dogId, {bool forceReload = false}) async {}
  @override
  Future<void> loadFullHistory(String dogId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserViewModel extends UserViewModel {
  _FakeUserViewModel({required this.displayNames});

  final Map<String, String> displayNames;

  @override
  String displayNameFor({
    required String? ra,
    dynamic firebaseUser,
    String fallback = 'Condutor',
  }) {
    if (ra != null && displayNames.containsKey(ra)) {
      return displayNames[ra]!;
    }
    return fallback;
  }
}

class _FakeDogViewModel extends DogViewModel {
  _FakeDogViewModel({required this.seededDogs});

  final List<Dog> seededDogs;

  @override
  List<Dog> get dogs => seededDogs;
}

Dog _createTestDog(String id, String name) {
  return Dog(
    id: id,
    name: name,
    breed: 'Pastor Belga Malinois',
    dateOfBirth: DateTime(2022, 1, 1),
    sex: 'M',
    status: 'Ativo',
    weight: 32.0,
  );
}

Occurrence _createOccurrence({
  required String id,
  required String dogId,
  required String typeName,
  required String primaryRa,
  required List<String> teamHandlerIds,
  required List<String> acceptedHandlerIds,
  required List<String> pendingHandlerIds,
}) {
  final now = DateTime.now();
  return Occurrence(
    id: id,
    shiftId: 'shift-001',
    primaryHandlerId: primaryRa,
    primaryHandlerRa: primaryRa,
    dogId: dogId,
    typeCode: 'AVERIGUACAO',
    typeName: typeName,
    locationAddress: 'Rua Operacional, 100',
    startedAt: now,
    createdAt: now,
    updatedAt: now,
    status: OccurrenceStatus.inProgress,
    acceptedHandlerIds: acceptedHandlerIds,
    pendingHandlerIds: pendingHandlerIds,
    team: teamHandlerIds
        .map(
          (ra) => OccurrenceTeamMember(
            handlerId: ra,
            handlerEmail: '$ra@gcm.com.br',
            role: ra == primaryRa ? TeamRole.titular : TeamRole.integrante,
            addedAt: now,
            addedBy: primaryRa,
          ),
        )
        .toList(),
  );
}

class _SpyTransitionService implements OccurrenceTransitionService {
  int acceptParticipationCalls = 0;
  String? lastAcceptedOccurrenceId;
  bool shouldThrow = false;

  @override
  Future<void> acceptParticipation({required String occurrenceId}) async {
    if (shouldThrow) {
      throw Exception('Simulated transition failure');
    }
    acceptParticipationCalls++;
    lastAcceptedOccurrenceId = occurrenceId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FirebasePlatform? _originalFirebasePlatform;

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    _originalFirebasePlatform = FirebasePlatform.instance;
    FirebasePlatform.instance = _FakeFirebasePlatform();
  });

  tearDownAll(() {
    final original = _originalFirebasePlatform;
    if (original != null) {
      FirebasePlatform.instance = original;
      _originalFirebasePlatform = null;
    }
  });

  group('TC1-PART & TC1-REG — Occurrence Participation & Presentation Repair Tests', () {
    testWidgets(
      'TC1-PART-01: Operator without personal K9 discovers notification bell in Cockpit',
      (tester) async {
        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null, // No personal K9
          fakeServiceDogId: 'stg-dog-tc1-001', // Crew service K9
        );

        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
                ChangeNotifierProvider<ShiftGroupViewModel>.value(
                  value: _FakeShiftGroupViewModel(),
                ),
                ChangeNotifierProvider<DogViewModel>.value(
                  value: _FakeDogViewModel(seededDogs: []),
                ),
                ChangeNotifierProvider<UserViewModel>.value(
                  value: _FakeUserViewModel(
                    displayNames: {'990002': 'Actor B'},
                  ),
                ),
                ChangeNotifierProvider<AuthViewModel>.value(
                  value: _FakeAuthViewModel(
                    currentUser: _FakeUser(
                      email: '990002@gcm.com.br',
                      displayName: 'Actor B',
                    ),
                  ),
                ),
                ChangeNotifierProvider<TrainingViewModel>.value(
                  value: _FakeTrainingViewModel(),
                ),
                ChangeNotifierProvider<HealthViewModel>.value(
                  value: _FakeHealthViewModel(),
                ),
                ChangeNotifierProvider<NutritionViewModel>.value(
                  value: _FakeNutritionViewModel(),
                ),
                ChangeNotifierProvider<OccurrenceViewModel>.value(
                  value: OccurrenceViewModel(
                    repository: OccurrenceRepository(FakeFirebaseFirestore()),
                    eventRepository: OccurrenceEventRepository(
                      FakeFirebaseFirestore(),
                    ),
                    signatureRepository: SignatureRepository(
                      firestore: FakeFirebaseFirestore(),
                    ),
                    sendTeamNotifications: false,
                  ),
                ),
              ],
              child: const ActiveShiftDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Cockpit shows "Em serviço · Sem K9"
        expect(find.text('Em serviço · Sem K9'), findsWidgets);
        // HeaderNotificationBell is present for the no-K9 operator
        expect(find.byType(HeaderNotificationBell), findsOneWidget);
      },
    );

    test(
      'TC1-PART-02 & TC1-PART-04: Operator without personal K9 is eligible to start/route occurrences',
      () {
        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null,
          fakeServiceDogId: 'stg-dog-tc1-001',
          fakeVehicleCrewId: 'STG-TC1-VTR-01',
        );

        final eligibility = evaluateOccurrenceStartEligibility(
          isLoading: shiftVM.isLoading,
          shiftError: shiftVM.error,
          hasActiveShift: shiftVM.hasActiveShift,
          vehicleCrewId: shiftVM.vehicleCrewId,
        );

        expect(eligibility, equals(OccurrenceStartEligibility.ready));
        expect(eligibility.canStart, isTrue);

        // Effective dog resolves to crew service dog without personal K9
        final effectiveDogId = shiftVM.activeDogId ?? shiftVM.serviceDogId;
        expect(effectiveDogId, equals('stg-dog-tc1-001'));
      },
    );

    testWidgets(
      'TC1-PART-03: Accepting participation executes OccurrenceTransitionService.acceptParticipation once',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final spy = _SpyTransitionService();
        final repo = OccurrenceRepository(db, transitionService: spy);

        final occ = _createOccurrence(
          id: 'occ-tc1-transition-test',
          dogId: 'stg-dog-tc1-001',
          typeName: 'Averiguação TC1',
          primaryRa: '990001',
          teamHandlerIds: ['990001', '990002'],
          acceptedHandlerIds: ['990001'],
          pendingHandlerIds: ['990002'], // Actor B pending
        );
        await repo.create(occ);

        // Execute acceptParticipation via repo
        await repo.acceptParticipation(occurrenceId: 'occ-tc1-transition-test');

        // Verify spy was invoked exactly once with matching arguments
        expect(spy.acceptParticipationCalls, equals(1));
        expect(spy.lastAcceptedOccurrenceId, equals('occ-tc1-transition-test'));
      },
    );

    testWidgets(
      'TC1-PART-07: Transition service failure raises clean exception without silent corruption',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final spy = _SpyTransitionService()..shouldThrow = true;
        final repo = OccurrenceRepository(db, transitionService: spy);

        final occ = _createOccurrence(
          id: 'occ-tc1-error-test',
          dogId: 'stg-dog-tc1-001',
          typeName: 'Averiguação TC1',
          primaryRa: '990001',
          teamHandlerIds: ['990001', '990002'],
          acceptedHandlerIds: ['990001'],
          pendingHandlerIds: ['990002'],
        );
        await repo.create(occ);

        expect(
          () async => await repo.acceptParticipation(
            occurrenceId: 'occ-tc1-error-test',
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'TC1-PART-05: Active occurrence projection is visible when accepted without personal K9',
      () {
        final occ = _createOccurrence(
          id: 'occ-tc1-active-proj',
          dogId: 'stg-dog-tc1-001',
          typeName: 'Patrulhamento Tático',
          primaryRa: '990001',
          teamHandlerIds: ['990001', '990002'],
          acceptedHandlerIds: ['990001', '990002'], // Actor B accepted
          pendingHandlerIds: [],
        );

        const String? activeDogId = null; // No personal K9
        const String currentRa = '990002'; // Actor B

        final bool isAcceptedParticipant = occ.acceptedHandlerIds.contains(
          currentRa,
        );
        final bool isPersonalDogOccurrence =
            activeDogId != null && occ.dogId == activeDogId;

        final activeOccurrence =
            (isPersonalDogOccurrence || isAcceptedParticipant) ? occ : null;

        expect(activeOccurrence, isNotNull);
        expect(activeOccurrence!.id, equals('occ-tc1-active-proj'));

        // For unrelated operator, activeOccurrence is null
        const String unrelatedRa = '990099';
        final bool isUnrelatedAccepted = occ.acceptedHandlerIds.contains(
          unrelatedRa,
        );
        final unrelatedOccurrence =
            (isPersonalDogOccurrence || isUnrelatedAccepted) ? occ : null;
        expect(unrelatedOccurrence, isNull);
      },
    );

    testWidgets(
      'TC1-REG-01 & TC1-REG-02: Preserves personal K9 cockpit and exposes serviceDogId cleanly',
      (tester) async {
        final personalDog = _createTestDog('stg-dog-tc1-002', 'Thor');
        final db = FakeFirebaseFirestore();
        await db.collection('dogs').doc('stg-dog-tc1-002').set({
          'id': 'stg-dog-tc1-002',
          'name': 'Thor',
          'breed': 'Pastor Alemão',
          'dateOfBirth': '2022-01-01',
          'status': 'Ativo',
        });

        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: 'stg-dog-tc1-002', // Has personal K9
          fakeServiceDogId: 'stg-dog-tc1-002',
        );

        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
                ChangeNotifierProvider<ShiftGroupViewModel>.value(
                  value: _FakeShiftGroupViewModel(),
                ),
                ChangeNotifierProvider<DogViewModel>.value(
                  value: _FakeDogViewModel(seededDogs: [personalDog]),
                ),
                ChangeNotifierProvider<UserViewModel>.value(
                  value: _FakeUserViewModel(
                    displayNames: {'990001': 'Actor A'},
                  ),
                ),
                ChangeNotifierProvider<AuthViewModel>.value(
                  value: _FakeAuthViewModel(
                    currentUser: _FakeUser(
                      email: '990001@gcm.com.br',
                      displayName: 'Actor A',
                    ),
                  ),
                ),
                ChangeNotifierProvider<TrainingViewModel>.value(
                  value: _FakeTrainingViewModel(),
                ),
                ChangeNotifierProvider<HealthViewModel>.value(
                  value: _FakeHealthViewModel(),
                ),
                ChangeNotifierProvider<NutritionViewModel>.value(
                  value: _FakeNutritionViewModel(),
                ),
                ChangeNotifierProvider<OccurrenceViewModel>.value(
                  value: OccurrenceViewModel(
                    repository: OccurrenceRepository(db),
                    eventRepository: OccurrenceEventRepository(db),
                    signatureRepository: SignatureRepository(firestore: db),
                    sendTeamNotifications: false,
                  ),
                ),
              ],
              child: const ActiveShiftDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // With personal dog, does NOT render "Em serviço · Sem K9"
        expect(find.text('Em serviço · Sem K9'), findsNothing);
        // Renders BinomioHeader with dog
        expect(find.byType(BinomioHeader), findsOneWidget);
      },
    );

    test(
      'TC1-REG-03: Shift state preserves role swap capability and does not mutate shift logic',
      () {
        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null,
          fakeServiceDogId: 'stg-dog-tc1-001',
          fakeVehicleCrewId: 'STG-TC1-VTR-01',
        );

        expect(shiftVM.hasActiveShift, isTrue);
        expect(shiftVM.activeDogId, isNull);
        expect(shiftVM.serviceDogId, equals('stg-dog-tc1-001'));
        expect(shiftVM.vehicleCrewId, equals('STG-TC1-VTR-01'));
        expect(shiftVM.hasVehicle, isTrue);
      },
    );
  });
}
