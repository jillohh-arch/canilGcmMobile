import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_post_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class _MockShiftViewModel extends Mock implements ShiftViewModel {}

class _MockUserViewModel extends Mock implements UserViewModel {}

void main() {
  testWidgets('renderiza posto ocupado por membro sem K9', (tester) async {
    final shiftVM = _MockShiftViewModel();
    final userVM = _MockUserViewModel();
    const vehicle = Vehicle(
      id: 'canil-1075',
      name: 'Canil',
      prefix: '1075',
      modelName: 'Teste',
      crewSize: 4,
      unit: 'Limeira/SP',
      active: true,
    );
    final member = VehicleCrewMember(
      handlerId: '12345',
      name: 'GCM Teste',
      role: 'motorista',
      status: 'active',
      joinedAt: DateTime(2026, 7, 13),
    );

    when(() => shiftVM.vehicleCrewId).thenReturn(vehicle.id);
    when(() => shiftVM.handlerId).thenReturn(member.handlerId);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
          ChangeNotifierProvider<UserViewModel>.value(value: userVM),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 700,
              child: buildVehicleCrewPostBoardForTesting(
                vehicle: vehicle,
                activeMembers: {member.role: member},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('GCM Teste'), findsOneWidget);
    expect(find.text('MOTORISTA'), findsOneWidget);
    expect(find.text('Sem K9 embarcado'), findsOneWidget);
  });
}
