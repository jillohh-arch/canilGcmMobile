import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent_session.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';

/// Simula ownership MainRoot + remount de Entry (ValueKey / sem cão ativo).
void main() {
  test('holderFor is stable across entry remounts for same dog', () {
    final session = HealthNutritionPendingIntentSession();
    final h1 = session.holderFor('dog-a');
    final h2 = session.holderFor('dog-a');
    expect(identical(h1, h2), isTrue);
  });

  test('different dogs get isolated holders', () {
    final session = HealthNutritionPendingIntentSession();
    expect(
      identical(session.holderFor('dog-a'), session.holderFor('dog-b')),
      isFalse,
    );
  });

  test(
    'navigation-like remount: unavailable then remount then same operationId',
    () async {
      final session = HealthNutritionPendingIntentSession();
      final gateway = _Spy();
      var seq = 0;

      HealthNutritionMutationController ctrl() =>
          HealthNutritionMutationController(
            gateway: gateway,
            pendingIntentHolder: session.holderFor('dog-a'),
            operationIdFactory: () => 'nav-${++seq}',
          );

      var c = ctrl();
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationNetwork(),
      );
      await c.createAdhocMeal(
        dogId: 'dog-a',
        period: MealPeriodWire.parseCanonical('extra'),
        offeredGrams: 70,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 19),
      );
      final key =
          (gateway.commands.single as CreateAdhocMealLogCommand).operationId;

      // Tab switch / full-screen: Entry may dispose; session holds intent.
      c.dispose();
      // "Sem cão ativo" temporarily: Entry unmounted — session still has key.
      expect(session.hasPendingForDog('dog-a'), isTrue);

      // Return to Saúde with same dog: new Entry State, same session holder.
      c = ctrl();
      gateway.next = CreateMealLogSuccess(
        dogId: 'dog-a',
        mealId: 'ml1_nav',
        revision: 1,
        wasNoOp: false,
        operationId: key,
      );
      await c.createAdhocMeal(
        dogId: 'dog-a',
        period: MealPeriodWire.parseCanonical('extra'),
        offeredGrams: 70,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 19),
      );
      expect(
        (gateway.commands[1] as CreateAdhocMealLogCommand).operationId,
        key,
      );
      c.dispose();
    },
  );
}

class _Spy implements HealthNutritionMutationGateway {
  HealthNutritionMutationResult? next;
  final commands = <Object>[];

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(c) async {
    commands.add(c);
    return next!;
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(c) async {
    commands.add(c);
    return next!;
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(c) async {
    commands.add(c);
    return next!;
  }
}
