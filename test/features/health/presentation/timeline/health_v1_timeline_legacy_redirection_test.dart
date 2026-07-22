import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/nutrition_full_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';

class _MockNutritionViewModel extends Mock implements NutritionViewModel {}

void main() {
  testWidgets(
    'F-03 Legacy Redirection: NutritionFullScreen with onRegisterAdhoc redirects CTA to HealthAdhocMealFormSheet and blocks FeedingRegistrationScreen',
    (tester) async {
      final dog = Dog(
        id: 'dog-bono',
        name: 'Bono',
        breed: 'Pastor Alemão',
        dateOfBirth: DateTime(2020, 1, 1),
      );

      final mockVm = _MockNutritionViewModel();
      when(() => mockVm.totalFeedings90d).thenReturn(0);
      when(() => mockVm.conformity90d).thenReturn(100.0);
      when(() => mockVm.conformFeedings90d).thenReturn(0);
      when(() => mockVm.divergentFeedings90d).thenReturn(0);
      when(() => mockVm.dailyConsumption14d).thenReturn(const []);
      when(() => mockVm.prescribedPerDay).thenReturn(500);
      when(() => mockVm.setFilterType(any())).thenReturn(null);
      when(() => mockVm.setFilterPeriod(any())).thenReturn(null);

      when(() => mockVm.loading).thenReturn(false);
      when(() => mockVm.historyLoading).thenReturn(false);
      when(() => mockVm.prescription).thenReturn(null);
      when(() => mockVm.todayFeedings).thenReturn(const []);
      when(() => mockVm.historyFeedings).thenReturn(const []);
      when(() => mockVm.filteredFeedings).thenReturn(const []);
      when(() => mockVm.prescriptionHistory).thenReturn(const []);
      when(() => mockVm.filterType).thenReturn('todas');
      when(() => mockVm.filterPeriod).thenReturn('mes');
      when(() => mockVm.conformityPercent).thenReturn(100.0);

      when(() => mockVm.addListener(any())).thenReturn(null);
      when(() => mockVm.removeListener(any())).thenReturn(null);
      when(() => mockVm.dispose()).thenReturn(null);
      when(() => mockVm.hasListeners).thenReturn(false);
      when(
        () => mockVm.loadForDog(any(), forceReload: any(named: 'forceReload')),
      ).thenAnswer((_) async {});
      when(() => mockVm.loadFullHistory(any())).thenAnswer((_) async {});

      var adhocSheetOpened = false;

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<NutritionViewModel>.value(
          value: mockVm,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => NutritionFullScreen(
                  dog: dog,
                  onRegisterAdhoc: () {
                    adhocSheetOpened = true;
                    showModalBottomSheet<void>(
                      context: ctx,
                      builder: (_) => const SizedBox(
                        key: Key('mock_adhoc_sheet'),
                        child: Text('Mock Adhoc Sheet'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final ctaFinder = find.text('REGISTRAR ALIMENTAÇÃO');
      expect(ctaFinder, findsOneWidget);

      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      expect(adhocSheetOpened, isTrue);
      expect(find.byType(FeedingRegistrationScreen), findsNothing);
      expect(find.byKey(const Key('mock_adhoc_sheet')), findsOneWidget);
    },
  );
}
