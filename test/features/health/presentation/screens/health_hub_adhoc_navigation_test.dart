import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';

final class _DummyAdhocGateway implements HealthNutritionMutationGateway {
  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => CreateMealLogSuccess(
    dogId: command.dogId,
    mealId: 'ml1_dummy',
    revision: 1,
    wasNoOp: false,
    mealOccurrenceId: null,
    operationId: command.operationId,
  );

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}

void main() {
  testWidgets(
    'Hub de Registros -> Nutrição opens HealthAdhocMealFormSheet and NOT legacy FeedingRegistrationScreen',
    (tester) async {
      final dog = Dog(
        id: 'dog-bono',
        name: 'Bono',
        breed: 'Pastor Alemão',
        dateOfBirth: DateTime(2020, 1, 1),
      );

      final controller = HealthNutritionMutationController(
        gateway: _DummyAdhocGateway(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return HealthTypeSelectorScreen(
                  dogId: dog.id,
                  dogName: dog.name,
                  onRegisterNutrition: (hubContext) async {
                    await showModalBottomSheet<void>(
                      context: hubContext,
                      isScrollControlled: true,
                      builder: (_) => HealthAdhocMealFormSheet(
                        dogId: dog.id,
                        dogDisplayName: dog.name,
                        controller: controller,
                        onRefreshRequested: () async {},
                      ),
                    );
                    return true;
                  },
                );
              },
            ),
          ),
        ),
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Select 'Nutrição' category
      final categoryFinder = find.text('Nutrição');
      expect(categoryFinder, findsOneWidget);
      await tester.ensureVisible(categoryFinder);
      await tester.tap(categoryFinder);
      await tester.pumpAndSettle();

      // Tap 'Continuar' button
      final continueFinder = find.text('Continuar');
      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      // Verify HealthAdhocMealFormSheet is displayed
      expect(find.byType(HealthAdhocMealFormSheet), findsOneWidget);

      // CRITICAL ASSERTION: Legacy FeedingRegistrationScreen is NOT present
      expect(find.byType(FeedingRegistrationScreen), findsNothing);

      controller.dispose();
    },
  );
}
