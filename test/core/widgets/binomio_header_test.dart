import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_group_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class _MockAuthViewModel extends Mock implements AuthViewModel {}

class _MockShiftViewModel extends Mock implements ShiftViewModel {}

class _MockShiftGroupViewModel extends Mock implements ShiftGroupViewModel {}

class _MockUserViewModel extends Mock implements UserViewModel {}

void main() {
  testWidgets('sem K9 mantém operador, menu e ação de associação', (
    tester,
  ) async {
    final authVM = _MockAuthViewModel();
    final shiftVM = _MockShiftViewModel();
    final shiftGroupVM = _MockShiftGroupViewModel();
    final userVM = _MockUserViewModel();

    when(() => authVM.user).thenReturn(null);
    when(() => shiftVM.hasActiveShift).thenReturn(true);
    when(() => shiftVM.vehicleCrewId).thenReturn(null);
    when(() => shiftGroupVM.isLoading).thenReturn(false);
    when(() => shiftGroupVM.currentShift).thenReturn(null);
    when(() => userVM.findByRa(null)).thenReturn(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authVM),
          ChangeNotifierProvider<ShiftViewModel>.value(value: shiftVM),
          ChangeNotifierProvider<ShiftGroupViewModel>.value(
            value: shiftGroupVM,
          ),
          ChangeNotifierProvider<UserViewModel>.value(value: userVM),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BinomioHeader(
              dog: null,
              handlerNameOverride: 'GCM Teste',
              subtitle: 'Turno ativo · Sem K9',
              onSwitchDog: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('GCM Teste'), findsOneWidget);
    expect(find.text('Turno ativo · Sem K9'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Associar K9'), findsOneWidget);
    expect(find.text('Encerrar turno'), findsOneWidget);
  });
}
