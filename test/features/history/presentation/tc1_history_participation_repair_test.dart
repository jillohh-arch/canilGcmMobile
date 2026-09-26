// ignore_for_file: depend_on_referenced_packages, unused_element_parameter
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_supplement.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';
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
  });

  final bool fakeHasActiveShift;
  final String? fakeActiveDogId;
  final String? fakeServiceDogId;
  final String? fakeVehicleCrewId;
  final DateTime? fakeShiftStartTime;

  @override
  bool get hasActiveShift => fakeHasActiveShift;

  @override
  String? get activeDogId => fakeActiveDogId;

  @override
  String? get serviceDogId => fakeServiceDogId;

  @override
  String? get vehicleCrewId => fakeVehicleCrewId;

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

  group('TC1-HIST — History Participation Repair Tests', () {
    testWidgets(
      'TC1-HIST-01: hasActiveShift=true + activeDogId=null does NOT return _HistoryNoShift',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final dog = _createTestDog('stg-dog-tc1-001', 'Bono');

        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null, // Actor B has no personal K9
          fakeServiceDogId: 'stg-dog-tc1-001', // Crew service K9
        );

        final occurrenceRepo = OccurrenceRepository(db);
        final occurrenceVM = OccurrenceViewModel(
          repository: occurrenceRepo,
          eventRepository: OccurrenceEventRepository(db),
          signatureRepository: SignatureRepository(firestore: db),
          sendTeamNotifications: false,
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
                  value: _FakeDogViewModel(seededDogs: [dog]),
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
                  value: occurrenceVM,
                ),
              ],
              child: const HistoryScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Must NOT show the "no active shift" placeholder
        expect(
          find.text(
            'Nenhum turno ativo.\nInicie um turno para ver o histórico.',
          ),
          findsNothing,
        );
        // Must show the History title
        expect(find.text('Histórico'), findsOneWidget);
      },
    );

    testWidgets(
      'TC1-HIST-02: Actor B can load legitimately related occurrence via crew service dog and participation',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final dog = _createTestDog('stg-dog-tc1-001', 'Bono');

        final occurrenceRepo = OccurrenceRepository(db);
        final occ = _createOccurrence(
          id: 'occ-tc1-b',
          dogId: 'stg-dog-tc1-001',
          typeName: 'Averiguação com Guarnição TC1',
          primaryRa: '990001',
          teamHandlerIds: ['990001', '990002'],
          acceptedHandlerIds: [
            '990001',
            '990002',
          ], // Actor B is accepted participant
        );
        await occurrenceRepo.create(occ);

        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null,
          fakeServiceDogId: 'stg-dog-tc1-001',
        );

        final occurrenceVM = OccurrenceViewModel(
          repository: occurrenceRepo,
          eventRepository: OccurrenceEventRepository(db),
          signatureRepository: SignatureRepository(firestore: db),
          sendTeamNotifications: false,
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
                  value: _FakeDogViewModel(seededDogs: [dog]),
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
                  value: occurrenceVM,
                ),
              ],
              child: const HistoryScreen(),
            ),
          ),
        );

        // Trigger data load
        occurrenceVM.watchByDog('stg-dog-tc1-001');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Averiguação com Guarnição TC1'), findsOneWidget);
      },
    );

    testWidgets(
      'TC1-HIST-03: Unrelated operator does not gain occurrence visibility',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final dog = _createTestDog('stg-dog-tc1-001', 'Bono');

        final occurrenceRepo = OccurrenceRepository(db);
        final occ = _createOccurrence(
          id: 'occ-tc1-unrelated',
          dogId: 'stg-dog-tc1-001',
          typeName: 'Ocorrência Confidencial Equipe Alfa',
          primaryRa: '990001',
          teamHandlerIds: ['990001'],
          acceptedHandlerIds: ['990001'], // Operator 990099 is NOT in team
        );
        await occurrenceRepo.create(occ);

        // Operator 990099 without personal K9, somehow sharing the dog slot:
        final shiftVM = _FakeShiftViewModel(
          fakeHasActiveShift: true,
          fakeActiveDogId: null,
          fakeServiceDogId: 'stg-dog-tc1-001',
        );

        final occurrenceVM = OccurrenceViewModel(
          repository: occurrenceRepo,
          eventRepository: OccurrenceEventRepository(db),
          signatureRepository: SignatureRepository(firestore: db),
          sendTeamNotifications: false,
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
                  value: _FakeDogViewModel(seededDogs: [dog]),
                ),
                ChangeNotifierProvider<UserViewModel>.value(
                  value: _FakeUserViewModel(
                    displayNames: {'990099': 'Operador C'},
                  ),
                ),
                ChangeNotifierProvider<AuthViewModel>.value(
                  value: _FakeAuthViewModel(
                    currentUser: _FakeUser(
                      email: '990099@gcm.com.br',
                      displayName: 'Operador C',
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
                  value: occurrenceVM,
                ),
              ],
              child: const HistoryScreen(),
            ),
          ),
        );

        occurrenceVM.watchByDog('stg-dog-tc1-001');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Unrelated occurrence must NOT be displayed
        expect(find.text('Ocorrência Confidencial Equipe Alfa'), findsNothing);
      },
    );
  });
}
