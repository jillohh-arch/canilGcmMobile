import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

final class _FakeCanonicalPlanReader implements NutritionCanonicalPlanReader {
  _FakeCanonicalPlanReader(this.plan);
  final NutritionPlan? plan;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    return plan != null
        ? NutritionSourceBatch.available([plan!])
        : const NutritionSourceBatch.empty();
  }
}

final class _FakeCanonicalMealReader implements NutritionCanonicalMealReader {
  _FakeCanonicalMealReader(this.meals);
  final List<MealLog> meals;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return meals.isNotEmpty
        ? NutritionSourceBatch.available(meals)
        : const NutritionSourceBatch.empty();
  }
}

void main() {
  final actor = RecordedBy(uid: 'user-1', name: 'Operador', internalRole: 'operator');

  test(
    'F-02 Canonical Summary Consistency & 125g Semantics: Active canonical plan + 1 planned meal (offered=125, consumed=null) returns available, offeredAmount=125, consumedAmount=null',
    () async {
      final now = DateTime.now();

      final plan = NutritionPlan(
        id: 'plan_bono_1',
        dogId: 'dog-bono',
        foodType: 'Premiatta Whey HD',
        amountGramsPerDay: 500,
        mealsPerDay: 3,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-1',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 125,
          ),
          MealScheduleSlot(
            id: 'slot-2',
            period: MealPeriodWire.parseCanonical('afternoon'),
            scheduledTime: ScheduledTimeOfDay('13:00'),
            targetGrams: 250,
          ),
          MealScheduleSlot(
            id: 'slot-3',
            period: MealPeriodWire.parseCanonical('evening'),
            scheduledTime: ScheduledTimeOfDay('19:00'),
            targetGrams: 125,
          ),
        ],
        validFrom: now.subtract(const Duration(days: 1)),
        timezone: 'America/Sao_Paulo',
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );

      // Gate 5C.2B planned meal log real: offeredGrams = 125, consumedGrams = null, acceptance = unknown
      final meal = MealLog(
        id: 'ml1_test_1',
        dogId: 'dog-bono',
        planId: 'plan_bono_1',
        plannedMealId: 'slot-1',
        mealOccurrenceId: 'occ-1',
        offeredGrams: 125,
        consumedGrams: null, // Explicitly NULL per 5C.2B planned execution
        acceptance: MealAcceptanceWire.parse('unknown'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      final coexistenceSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: _FakeCanonicalPlanReader(plan),
        canonicalMealReader: _FakeCanonicalMealReader([meal]),
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: coexistenceSource,
        clock: () => now,
      );

      final result = await reader.readToday('dog-bono');

      // CRITICAL ASSERTION 1: Result status is available, NOT notRecorded
      expect(result.status, HealthSummarySectionStatus.available);

      final data = result.value!;

      // CRITICAL ASSERTION 2: 125g semantics — NO false inference of consumedAmount!
      expect(data.consumedAmount, isNull);
      expect(data.offeredAmount, 125.0);
      expect(data.plannedAmount, 500.0);
      expect(data.mealsRecorded, 1);
      expect(data.mealsPlanned, 3);
    },
  );

  test(
    'F-02 Canonical Summary Consistency: MealLog with consumedGrams=125 returns consumedAmount=125',
    () async {
      final now = DateTime.now();

      final plan = NutritionPlan(
        id: 'plan_bono_1',
        dogId: 'dog-bono',
        foodType: 'Premiatta Whey HD',
        amountGramsPerDay: 500,
        mealsPerDay: 3,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-1',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 125,
          ),
        ],
        validFrom: now.subtract(const Duration(days: 1)),
        timezone: 'America/Sao_Paulo',
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );

      final meal = MealLog(
        id: 'ml1_test_2',
        dogId: 'dog-bono',
        planId: 'plan_bono_1',
        plannedMealId: 'slot-1',
        mealOccurrenceId: 'occ-1',
        offeredGrams: 125,
        consumedGrams: 125,
        acceptance: MealAcceptanceWire.parse('full'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      final coexistenceSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: _FakeCanonicalPlanReader(plan),
        canonicalMealReader: _FakeCanonicalMealReader([meal]),
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: coexistenceSource,
        clock: () => now,
      );

      final result = await reader.readToday('dog-bono');
      final data = result.value!;

      expect(data.consumedAmount, 125.0);
      expect(data.offeredAmount, 125.0);
    },
  );
}
