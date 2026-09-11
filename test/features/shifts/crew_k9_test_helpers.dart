// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/data/shift_service.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/auth/data/auth_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/users/domain/user.dart';

class FakeFirebasePlatform extends FirebasePlatform {
  FakeFirebasePlatform() : _app = _FakeFirebaseAppPlatform();
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

class MockShiftService extends ShiftService {}

class MockShiftAuthorizationGateway implements ShiftAuthorizationGateway {
  @override
  Future<ShiftAuthorizationResult> execute(ShiftAuthorizationCommand command) async {
    return const ShiftAuthorizationResult(
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

class MockAuthService extends AuthService {
  @override
  Stream<fb_auth.User?> get authStateChanges => const Stream.empty();
  @override
  fb_auth.User? get currentUser => null;
}

class MockVehicleCrewService extends VehicleCrewService {
  final StreamController<VehicleCrew?> crewController = StreamController<VehicleCrew?>.broadcast();
  final StreamController<List<VehicleCrewMember>> membersController = StreamController<List<VehicleCrewMember>>.broadcast();

  @override
  Stream<VehicleCrew?> watchCrew(String crewId) => crewController.stream;

  @override
  Stream<List<VehicleCrewMember>> watchMembers(String crewId) => membersController.stream;

  @override
  Future<String> getCrewOperationalStatus(String crewId) async => 'active';
}

class MockDogViewModel extends ChangeNotifier implements DogViewModel {
  final List<Dog> _dogs;
  MockDogViewModel(this._dogs);

  @override
  List<Dog> get dogs => _dogs;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockUserViewModel extends ChangeNotifier implements UserViewModel {
  final Map<String, String> names;
  MockUserViewModel(this.names);

  @override
  String displayNameFor({
    required String? ra,
    dynamic firebaseUser,
    String fallback = 'Condutor',
  }) {
    if (ra != null && names.containsKey(ra)) return names[ra]!;
    return 'GCM $ra';
  }

  @override
  UserModel? findByRa(String? ra) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget buildTestCockpit({
  required ShiftViewModel shiftVM,
  required Dog? personalDog,
  required String callsign,
  required MockVehicleCrewService crewService,
  required MockDogViewModel dogVM,
  required MockUserViewModel userVM,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
      ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
      ChangeNotifierProvider<UserViewModel>.value(value: userVM),
      ChangeNotifierProvider<DogViewModel>.value(value: dogVM),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EmServicoCard(
            dog: personalDog,
            callsign: callsign,
            conductorPhotoUrl: null,
            crewService: crewService,
          ),
        ),
      ),
    ),
  );
}

final defaultTestDog1 = Dog(
  id: 'stg-dog-tc1-001',
  name: 'STG TC1 OPERATIONAL DOG',
  breed: 'Pastor Alemão',
  dateOfBirth: DateTime(2021, 1, 1),
  conductorRa: '990001',
  status: 'Ativo',
);

final defaultTestDog2 = Dog(
  id: 'dog-diff-002',
  name: 'OTHER PERSONAL DOG',
  breed: 'Labrador',
  dateOfBirth: DateTime(2022, 1, 1),
  conductorRa: '990002',
  status: 'Ativo',
);

void emitStgCrew(MockVehicleCrewService crewService, {String serviceDogId = 'stg-dog-tc1-001'}) {
  crewService.crewController.add(
    VehicleCrew(
      id: 'STG-TC1-VTR-01',
      vehicleId: 'STG-TC1-VTR-01',
      vehicleLabel: 'V-TC1',
      crewSize: 2,
      serviceDogId: serviceDogId,
      titularHandlerId: '990001',
      active: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  crewService.membersController.add([
    VehicleCrewMember(
      handlerId: '990001',
      role: 'encarregado',
      status: 'active',
      joinedAt: DateTime.now(),
      name: 'Nutrition',
      dogId: serviceDogId,
    ),
    VehicleCrewMember(
      handlerId: '990002',
      role: 'motorista',
      status: 'active',
      joinedAt: DateTime.now(),
      name: 'RA 990002',
      dogId: '',
    ),
  ]);
}

