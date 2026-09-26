// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';

import 'crew_k9_test_helpers.dart';

void main() {
  setUpAll(() {
    FirebasePlatform.instance = FakeFirebasePlatform();
  });

  group('CT.MOBILE-SHIFT.CREW-K9-PROJECTION-REPAIR-R1 — Deterministic Crew K9 Projection Tests', () {
    testWidgets('A. Actor A with personal K9 + crew K9 shows crew service dog in shared slot', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'vehicle_crew_id': 'STG-TC1-VTR-01',
          'vehicle_id': 'STG-TC1-VTR-01',
          'vehicle_label': 'V-TC1',
          'crew_role': 'encarregado',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1]);
      final userVM = MockUserViewModel({'990001': 'Nutrition', '990002': 'RA 990002'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: defaultTestDog1,
          callsign: 'Nutrition',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      emitStgCrew(mockCrewService);
      await tester.pumpAndSettle();

      expect(find.text('STG TC1 OPERATIONAL DOG'), findsWidgets);
      expect(find.text('com Nutrition'), findsOneWidget);
    });
    // ─────────────────────────────────────────────────────────
    // Test B: Actor B without personal K9, same crew
    // ─────────────────────────────────────────────────────────
    testWidgets('B. Actor B without personal K9 shows "Sem K9" in personal section, but crew dog in shared slot', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990002');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': '',
          'vehicle_crew_id': 'STG-TC1-VTR-01',
          'vehicle_id': 'STG-TC1-VTR-01',
          'vehicle_label': 'V-TC1',
          'crew_role': 'motorista',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1]);
      final userVM = MockUserViewModel({'990001': 'Nutrition', '990002': 'RA 990002'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: null,
          callsign: 'RA 990002',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      emitStgCrew(mockCrewService);
      await tester.pumpAndSettle();

      expect(find.text('Em serviço · Sem K9'), findsOneWidget);
      expect(find.text('STG TC1 OPERATIONAL DOG'), findsOneWidget);
      expect(find.text('com Nutrition'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────
    // Test C: Actor B does NOT become the displayed K9 handler
    // ─────────────────────────────────────────────────────────
    testWidgets('C. Actor B does NOT become the displayed K9 handler in the shared K9 slot', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990002');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': '',
          'vehicle_crew_id': 'STG-TC1-VTR-01',
          'vehicle_id': 'STG-TC1-VTR-01',
          'vehicle_label': 'V-TC1',
          'crew_role': 'motorista',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1]);
      final userVM = MockUserViewModel({'990001': 'Nutrition', '990002': 'RA 990002'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: null,
          callsign: 'RA 990002',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      emitStgCrew(mockCrewService);
      await tester.pumpAndSettle();

      expect(find.text('com RA 990002'), findsNothing);
      expect(find.text('com Nutrition'), findsOneWidget);
    });
    // ─────────────────────────────────────────────────────────
    // Test D: K9 handler resolves strictly from active member whose dogId matches crew.serviceDogId
    // ─────────────────────────────────────────────────────────
    testWidgets('D. K9 handler resolves strictly from active member whose dogId matches crew.serviceDogId', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990003');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990003',
          'dogId': '',
          'vehicle_crew_id': 'VTR-99',
          'vehicle_id': 'VTR-99',
          'vehicle_label': 'V-99',
          'crew_role': 'auxiliar_1',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1]);
      final userVM = MockUserViewModel({
        '990001': 'Guarda Um',
        '990002': 'Guarda Dois',
        '990003': 'Guarda Tres',
      });

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: null,
          callsign: 'Guarda Tres',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      mockCrewService.crewController.add(
        VehicleCrew(
          id: 'VTR-99',
          vehicleId: 'VTR-99',
          vehicleLabel: 'V-99',
          crewSize: 3,
          serviceDogId: 'stg-dog-tc1-001',
          titularHandlerId: '990001',
          active: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      mockCrewService.membersController.add([
        VehicleCrewMember(
          handlerId: '990001',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Guarda Um',
          dogId: '',
        ),
        VehicleCrewMember(
          handlerId: '990002',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Guarda Dois',
          dogId: 'stg-dog-tc1-001',
        ),
        VehicleCrewMember(
          handlerId: '990003',
          role: 'auxiliar_1',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Guarda Tres',
          dogId: '',
        ),
      ]);

      await tester.pumpAndSettle();

      expect(find.text('com Guarda Dois'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────
    // Test E: crew.serviceDogId empty renders SEM K9
    // ─────────────────────────────────────────────────────────
    testWidgets('E. crew.serviceDogId empty renders SEM K9 in shared slot', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': 'stg-dog-tc1-001',
          'vehicle_crew_id': 'VTR-EMPTY',
          'vehicle_id': 'VTR-EMPTY',
          'vehicle_label': 'V-EMPTY',
          'crew_role': 'motorista',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1]);
      final userVM = MockUserViewModel({'990001': 'Operador'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: defaultTestDog1,
          callsign: 'Operador',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      mockCrewService.crewController.add(
        VehicleCrew(
          id: 'VTR-EMPTY',
          vehicleId: 'VTR-EMPTY',
          vehicleLabel: 'V-EMPTY',
          crewSize: 1,
          serviceDogId: '',
          titularHandlerId: '990001',
          active: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      mockCrewService.membersController.add([
        VehicleCrewMember(
          handlerId: '990001',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Operador',
          dogId: '',
        ),
      ]);

      await tester.pumpAndSettle();

      expect(find.text('SEM K9'), findsOneWidget);
    });
    // ─────────────────────────────────────────────────────────
    // Test F: User personal dog differs from crew.serviceDogId
    // ─────────────────────────────────────────────────────────
    testWidgets('F. current user personal dog differs from crew.serviceDogId: shared slot follows crew dog', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990002');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990002',
          'dogId': 'dog-diff-002',
          'vehicle_crew_id': 'VTR-01',
          'vehicle_id': 'VTR-01',
          'vehicle_label': 'V-01',
          'crew_role': 'motorista',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1, defaultTestDog2]);
      final userVM = MockUserViewModel({'990001': 'Handler Um', '990002': 'Handler Dois'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: defaultTestDog2,
          callsign: 'Handler Dois',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      mockCrewService.crewController.add(
        VehicleCrew(
          id: 'VTR-01',
          vehicleId: 'VTR-01',
          vehicleLabel: 'V-01',
          crewSize: 2,
          serviceDogId: 'stg-dog-tc1-001',
          titularHandlerId: '990001',
          active: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      mockCrewService.membersController.add([
        VehicleCrewMember(
          handlerId: '990001',
          role: 'encarregado',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Handler Um',
          dogId: 'stg-dog-tc1-001',
        ),
        VehicleCrewMember(
          handlerId: '990002',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Handler Dois',
          dogId: 'dog-diff-002',
        ),
      ]);

      await tester.pumpAndSettle();

      expect(find.text('OTHER PERSONAL DOG'), findsOneWidget);
      expect(find.text('STG TC1 OPERATIONAL DOG'), findsOneWidget);
      expect(find.text('com Handler Um'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────
    // Test G: Inconsistent member dog references do not pick arbitrary first dog
    // ─────────────────────────────────────────────────────────
    testWidgets('G. inconsistent member dog references do not cause arbitrary dog selection when crew.serviceDogId is empty', (tester) async {
      final mockCrewService = MockVehicleCrewService();
      final shiftVM = ShiftViewModel(
        authorizationGateway: MockShiftAuthorizationGateway(),
        shiftService: MockShiftService(),
        authService: MockAuthService(),
      );
      shiftVM.setBoundRaForTesting('990001');
      shiftVM.setSessionForTesting(
        ActiveShiftSession.fromJson({
          'handlerId': '990001',
          'dogId': '',
          'vehicle_crew_id': 'VTR-INCONSISTENT',
          'vehicle_id': 'VTR-INCONSISTENT',
          'vehicle_label': 'V-INC',
          'crew_role': 'motorista',
          'status': 'active',
        }),
      );

      final dogVM = MockDogViewModel([defaultTestDog1, defaultTestDog2]);
      final userVM = MockUserViewModel({'990001': 'Operador'});

      await tester.pumpWidget(
        buildTestCockpit(
          shiftVM: shiftVM,
          personalDog: null,
          callsign: 'Operador',
          crewService: mockCrewService,
          dogVM: dogVM,
          userVM: userVM,
        ),
      );

      mockCrewService.crewController.add(
        VehicleCrew(
          id: 'VTR-INCONSISTENT',
          vehicleId: 'VTR-INCONSISTENT',
          vehicleLabel: 'V-INC',
          crewSize: 1,
          serviceDogId: '',
          titularHandlerId: '990001',
          active: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      mockCrewService.membersController.add([
        VehicleCrewMember(
          handlerId: '990001',
          role: 'motorista',
          status: 'active',
          joinedAt: DateTime.now(),
          name: 'Operador',
          dogId: 'stg-dog-tc1-001',
        ),
      ]);

      await tester.pumpAndSettle();

      expect(find.text('SEM K9'), findsOneWidget);
      expect(find.text('STG TC1 OPERATIONAL DOG'), findsNothing);
    });



  });
}
