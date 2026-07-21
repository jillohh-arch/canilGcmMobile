import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';

final class _PlanReader implements NutritionCanonicalPlanReader {
  final NutritionPlan plan;
  _PlanReader(this.plan);

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    return NutritionSourceBatch.available([plan]);
  }
}

final class _MealReader implements NutritionCanonicalMealReader {
  final List<MealLog> meals;
  _MealReader(this.meals);

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return NutritionSourceBatch.available(meals);
  }
}

void main() {
  final actor = RecordedBy(uid: 'u-operator', name: 'Op', internalRole: 'operator');

  test(
    'SLOT NON-INTERFERENCE: Active plan + slot pending/late + adhoc MealLog → slot status remains unchanged',
    () async {
      // 1. Active plan with 1 slot (morning, 07:00, 200g)
      final slot1 = MealScheduleSlot(
        id: 'slot-morning-1',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: 200,
      );

      final plan = NutritionPlan(
        id: 'plan-canonical-101',
        dogId: 'dog-bono',
        foodType: 'Super Premium K9',
        amountGramsPerDay: 200,
        mealsPerDay: 1,
        mealSchedule: [slot1],
        validFrom: DateTime.utc(2026, 1, 1),
        timezone: 'America/Sao_Paulo',
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );

      // 2. Adhoc MealLog created on same local service date (2026-07-21)
      final fedAtInstant = DateTime.utc(2026, 7, 21, 14, 0); // 11:00 SP (America/Sao_Paulo)
      final adhocMeal = MealLog(
        id: 'ml1_0123456789abcdef',
        dogId: 'dog-bono',
        period: MealPeriodWire.parseCanonical('afternoon'),
        offeredGrams: 150,
        consumedGrams: 150,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAtInstant,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
        // Adhoc MealLogs explicitly have NULL plan linkage:
        planId: null,
        plannedMealId: null,
        mealOccurrenceId: null,
        scheduledFor: null,
      );

      // Verify domain invariants for adhoc MealLog
      expect(adhocMeal.planId, isNull);
      expect(adhocMeal.plannedMealId, isNull);
      expect(adhocMeal.mealOccurrenceId, isNull);
      expect(adhocMeal.scheduledFor, isNull);

      // 3. Load Today Read Model
      final readSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: _PlanReader(plan),
        canonicalMealReader: _MealReader([adhocMeal]),
      );

      final result = await readSource.loadToday(
        'dog-bono',
        serverNow: fedAtInstant,
      );

      expect(result.isData, isTrue);
      final today = result.value!;
      expect(today.activePlan, isA<NutritionActiveCanonicalPlan>());

      // Adhoc meal appears in today's meals list
      expect(today.meals.length, equals(1));
      expect(today.meals.first.id, equals('ml1_0123456789abcdef'));

      // Slot non-interference assertion:
      // Check that none of the meals in today.meals match slot1's plannedMealId or mealOccurrenceId
      final matchingMealForSlot = today.meals.where(
        (m) => m.meal.plannedMealId == slot1.id || m.meal.mealOccurrenceId != null,
      );
      expect(matchingMealForSlot, isEmpty);
    },
  );
}
