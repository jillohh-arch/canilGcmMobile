// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_post_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';

import 'crew_k9_test_helpers.dart';

void main() {
  setUpAll(() {
    FirebasePlatform.instance = FakeFirebasePlatform();
  });

  const testVehicle = Vehicle(
    id: 'STG-TC1-VTR-01',
    name: 'Viatura 01',
    prefix: 'V-TC1',
    modelName: 'Hilux',
    crewSize: 4,
    unit: 'Canil GCM',
    active: true,
  );

  Widget buildPostBoardHarness({
    required Widget child,
    required ShiftViewModel shiftVM,
    required MockUserViewModel userVM,
    DogViewModel? dogVM,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
        ChangeNotifierProvider<AuthViewModel>.value(value: AuthViewModel()),
        ChangeNotifierProvider<UserViewModel>.value(value: userVM),
        ChangeNotifierProvider<DogViewModel>.value(
          value: dogVM ?? MockDogViewModel([defaultTestDog1]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  ShiftViewModel createTestShiftVM({
    String handlerId = '990001',
    String vehicleCrewId = 'STG-TC1-VTR-01',
    String? dogId = 'stg-dog-tc1-001',
  }) {
    final vm = ShiftViewModel(
      authorizationGateway: MockShiftAuthorizationGateway(),
      shiftService: MockShiftService(),
      authService: MockAuthService(),
    );
    vm.setBoundRaForTesting(handlerId);
    vm.setSessionForTesting(
      ActiveShiftSession.fromJson({
        'handlerId': handlerId,
        'dogId': dogId,
        'vehicle_crew_id': vehicleCrewId,
        'vehicle_id': vehicleCrewId,
        'vehicle_label': 'V-TC1',
        'crew_role': 'encarregado',
        'status': 'active',
      }),
    );
    return vm;
  }

  group('CT.MOBILE-SHIFT.CREW-ROLE-SWAP-NULL-REPAIR-R1 — PostBoard & Crew Role Swap Null-Safety', () {
    testWidgets('1. Occupied Motorista with dogId == null renders normally without exception', (tester) async {
      final shiftVM = createTestShiftVM(handlerId: '990002', dogId: null);
      final userVM = MockUserViewModel({
        '990002': 'Condutor Silva',
      });

      final memberMotoristaNoDog = VehicleCrewMember(
        handlerId: '990002',
        role: 'motorista',
        status: 'active',
        joinedAt: DateTime.now(),
        name: 'Condutor Silva',
        dogId: null, // Critical condition: empty Firestore dog_id normalized to null
      );

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostBoard(
            vehicle: testVehicle,
            activeMembers: {'motorista': memberMotoristaNoDog},
            hasBinomioActive: false,
            onPostSelected: (_) {},
            onLeaveVehicle: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'Must not throw null-check exception on member.dogId');
      expect(find.text('MOTORISTA'), findsOneWidget);
      expect(find.text('Condutor Silva'), findsOneWidget);
      expect(find.text('K9'), findsNothing, reason: 'Motorista without K9 must not display K9 badge');
    });

    testWidgets('2. Occupied Auxiliar with dogId == null renders normally without exception', (tester) async {
      final shiftVM = createTestShiftVM(handlerId: '990003', dogId: null);
      final userVM = MockUserViewModel({
        '990003': 'Auxiliar Santos',
      });

      final memberAuxiliarNoDog = VehicleCrewMember(
        handlerId: '990003',
        role: 'auxiliar_1',
        status: 'active',
        joinedAt: DateTime.now(),
        name: 'Auxiliar Santos',
        dogId: null, // Critical condition: empty Firestore dog_id normalized to null
      );

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostBoard(
            vehicle: testVehicle,
            activeMembers: {'auxiliar_1': memberAuxiliarNoDog},
            hasBinomioActive: false,
            onPostSelected: (_) {},
            onLeaveVehicle: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'Must not throw null-check exception on Auxiliar member.dogId');
      expect(find.text('AUXILIAR 1'), findsOneWidget);
      expect(find.text('Auxiliar Santos'), findsOneWidget);
      expect(find.text('K9'), findsNothing, reason: 'Auxiliar without K9 must not display K9 badge');
    });

    testWidgets('3. Occupied member with dogId populated shows K9 indication', (tester) async {
      final shiftVM = createTestShiftVM(handlerId: '990001', dogId: 'stg-dog-tc1-001');
      final userVM = MockUserViewModel({
        '990001': 'Nutrition',
      });

      final memberWithDog = VehicleCrewMember(
        handlerId: '990001',
        role: 'encarregado',
        status: 'active',
        joinedAt: DateTime.now(),
        name: 'Nutrition',
        dogId: 'stg-dog-tc1-001',
      );

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostBoard(
            vehicle: testVehicle,
            activeMembers: {'encarregado': memberWithDog},
            hasBinomioActive: true,
            onPostSelected: (_) {},
            onLeaveVehicle: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('ENCARREGADO'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('K9'), findsOneWidget, reason: 'Occupied member with dogId must display K9 badge');
    });

    testWidgets('4. Vacant slots remain unchanged and interactive', (tester) async {
      final shiftVM = createTestShiftVM();
      final userVM = MockUserViewModel({});
      String? selectedRole;

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostBoard(
            vehicle: testVehicle,
            activeMembers: const {}, // All 4 slots vacant
            hasBinomioActive: false,
            onPostSelected: (role) => selectedRole = role,
            onLeaveVehicle: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // All 4 slots should show 'Vago' and 'ASSUMIR'
      expect(find.text('Vago'), findsNWidgets(4));
      expect(find.text('ASSUMIR'), findsNWidgets(4));

      // Tap on the Motorista slot to assume
      await tester.tap(find.text('MOTORISTA'));
      expect(selectedRole, equals('motorista'));
    });

    testWidgets('5. Role swap to a no-K9 member recomposes dynamically without exception', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = createTestShiftVM(handlerId: '990002', dogId: null);
      final userVM = MockUserViewModel({
        '990001': 'Nutrition',
        '990002': 'Condutor Silva',
      });

      // Initial state:
      // 990001 is encarregado (with dogId)
      // 990002 is auxiliar_1 (no dogId)
      // motorista is vacant
      final initialMembers = [
        VehicleCrewMember(
          handlerId: '990001',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Nutrition',
          dogId: 'stg-dog-tc1-001',
        ),
        VehicleCrewMember(
          handlerId: '990002',
          role: 'auxiliar_1',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Condutor Silva',
          dogId: null,
        ),
      ];

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostSheet(
            initialVehicle: testVehicle,
            crewService: mockCrewService,
          ),
        ),
      );

      mockCrewService.membersController.add(initialMembers);
      // Use pump() because HudStatusDot uses continuous pulse animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('ENCARREGADO'), findsOneWidget);
      expect(find.text('AUXILIAR 1'), findsOneWidget);
      expect(find.text('Condutor Silva'), findsOneWidget);

      // Now simulate a ROLE SWAP:
      // Condutor Silva (990002, dogId == null) moves to 'motorista'
      // 990001 stays 'encarregado'
      // 'auxiliar_1' becomes vacant
      final swappedMembers = [
        VehicleCrewMember(
          handlerId: '990001',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Nutrition',
          dogId: 'stg-dog-tc1-001',
        ),
        VehicleCrewMember(
          handlerId: '990002',
          role: 'motorista', // Swapped role to Motorista with NO K9
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Condutor Silva',
          dogId: null, // Still no K9
        ),
      ];

      mockCrewService.membersController.add(swappedMembers);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify recomposition succeeded with NO exception
      expect(tester.takeException(), isNull, reason: 'Recomposition after role swap with dogId == null must not throw');
      expect(find.text('MOTORISTA'), findsOneWidget);
      expect(find.text('Condutor Silva'), findsOneWidget);
      // Only 1 K9 badge should exist (on encarregado)
      expect(find.text('K9'), findsOneWidget);
    });

    testWidgets('6. Member with empty whitespace dogId handles safely without crash', (tester) async {
      final shiftVM = createTestShiftVM(handlerId: '990004', dogId: '');
      final userVM = MockUserViewModel({
        '990004': 'Condutor Branco',
      });

      final memberEmptyDog = VehicleCrewMember(
        handlerId: '990004',
        role: 'auxiliar_2',
        status: 'active',
        joinedAt: DateTime.now(),
        name: 'Condutor Branco',
        dogId: '   ', // Edge case: whitespace-only dogId
      );

      await tester.pumpWidget(
        buildPostBoardHarness(
          shiftVM: shiftVM,
          userVM: userVM,
          child: VehicleCrewPostBoard(
            vehicle: testVehicle,
            activeMembers: {'auxiliar_2': memberEmptyDog},
            hasBinomioActive: false,
            onPostSelected: (_) {},
            onLeaveVehicle: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('AUXILIAR 2'), findsOneWidget);
      expect(find.text('Condutor Branco'), findsOneWidget);
      expect(find.text('K9'), findsNothing, reason: 'Whitespace-only dogId must not display K9 badge');
    });
  });
}
