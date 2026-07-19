import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';

final class _MealGateway implements HealthNutritionMutationGateway {
  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    return CreateMealLogSuccess(
      dogId: command.dogId,
      mealId: 'meal-new',
      revision: 1,
      wasNoOp: false,
      mealOccurrenceId: null,
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    return CreateMealLogSuccess(
      dogId: command.dogId,
      mealId: 'meal-adhoc',
      revision: 1,
      wasNoOp: false,
      mealOccurrenceId: null,
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    throw UnimplementedError();
  }
}

final class _CountingPlanReader implements NutritionCanonicalPlanReader {
  int calls = 0;
  final List<NutritionPlan> plans;

  _CountingPlanReader(this.plans);

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    calls++;
    return NutritionSourceBatch.available(plans);
  }
}

NutritionPlan _plan(String dogId) {
  return NutritionPlan(
    id: 'plan-1',
    dogId: dogId,
    foodType: 'Ração',
    amountGramsPerDay: 200,
    mealsPerDay: 1,
    mealSchedule: [
      MealScheduleSlot(
        id: 's1',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: 200,
      ),
    ],
    validFrom: DateTime.utc(2026, 1, 1),
    timezone: NutritionPlan.defaultTimezone,
    recordedBy: RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin'),
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
  );
}

void main() {
  test(
    'mutation success → refresh → read controller carrega snapshot',
    () async {
      final planReader = _CountingPlanReader([_plan('dog-a')]);
      final readSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: planReader,
      );
      final readController = HealthNutritionReadController(source: readSource);

      final mutationController = HealthNutritionMutationController(
        gateway: _MealGateway(),
        operationIdFactory: () => 'op-1',
        onRefreshAfterSuccess: () =>
            readController.ensureDogAndRefresh('dog-a'),
      );

      final outcome = await mutationController.createAdhocMeal(
        dogId: 'dog-a',
        period: MealPeriodWire.parseCanonical('morning'),
        offeredGrams: 100,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 14, 12),
      );

      expect(outcome, isA<HealthNutritionMutationUiSuccess>());
      final success = outcome as HealthNutritionMutationUiSuccess;
      expect(success.savedAndRefreshed, isTrue);
      expect(success.savedButRefreshFailed, isFalse);
      expect(readController.activeDogId, 'dog-a');
      expect(readController.snapshotResult.hasUsableValue, isTrue);
      expect(planReader.calls, greaterThanOrEqualTo(1));

      mutationController.dispose();
      readController.dispose();
    },
  );

  test('mutation success + refresh failure → savedButRefreshFailed', () async {
    final mutationController = HealthNutritionMutationController(
      gateway: _MealGateway(),
      operationIdFactory: () => 'op-2',
      onRefreshAfterSuccess: () async {
        throw StateError('refresh boom');
      },
    );

    final outcome = await mutationController.createAdhocMeal(
      dogId: 'dog-a',
      period: MealPeriodWire.parseCanonical('morning'),
      offeredGrams: 100,
      acceptance: MealAcceptanceWire.parse('full'),
      fedAt: DateTime.utc(2026, 7, 14, 12),
    );

    expect(outcome, isA<HealthNutritionMutationUiSuccess>());
    final success = outcome as HealthNutritionMutationUiSuccess;
    expect(success.savedButRefreshFailed, isTrue);
    expect(success.savedAndRefreshed, isFalse);
    expect(success.refreshWarning, isNotNull);
    // Não é failure de mutação.
    expect(outcome, isNot(isA<HealthNutritionMutationUiFailure>()));

    mutationController.dispose();
  });
}
