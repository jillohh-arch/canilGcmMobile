import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';
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
  final actor = RecordedBy(
    uid: 'user-1',
    name: 'Operador',
    internalRole: 'operator',
  );

  test(
    'F-04 Adhoc Non-Contamination: 1 planned meal completed + 1 adhoc meal log => planned completed = 1 / 3, total offered = 175g, known consumed = 50g',
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

      // 1 Planned MealLog (Morning, 125g offered, consumed=null)
      final plannedMeal = MealLog(
        id: 'ml1_planned_1',
        dogId: 'dog-bono',
        planId: 'plan_bono_1',
        plannedMealId: 'slot-1',
        mealOccurrenceId: MealOccurrenceId.v1(
          MealOccurrenceKey(
            dogId: 'dog-bono',
            planId: 'plan_bono_1',
            plannedMealId: 'slot-1',
            localServiceDate: LocalServiceDate.fromInstant(
              now,
              timezone: plan.timezone,
            ),
          ),
        ).value,
        offeredGrams: 125,
        consumedGrams: null,
        acceptance: MealAcceptanceWire.parse('unknown'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      // 1 Adhoc MealLog (Extra, 50g offered, 50g consumed, plan linkage = null)
      final adhocMeal = MealLog(
        id: 'ml1_adhoc_extra',
        dogId: 'dog-bono',
        planId: null,
        plannedMealId: null,
        mealOccurrenceId: null,
        scheduledFor: null,
        offeredGrams: 50,
        consumedGrams: 50,
        acceptance: MealAcceptanceWire.parse('full'),
        period: MealPeriodWire.parseCanonical('extra'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      expect(plannedMeal.isPlanned, isTrue);
      expect(plannedMeal.isAdHoc, isFalse);
      expect(adhocMeal.isPlanned, isFalse);
      expect(adhocMeal.isAdHoc, isTrue);

      final mealsList = [plannedMeal, adhocMeal];

      final readItems = mealsList
          .map(
            (m) => NutritionMealReadItem(
              meal: m,
              origin: NutritionDataOrigin.canonical,
              mergeKey: m.id,
            ),
          )
          .toList();

      final todayModel = NutritionTodayReadModel(
        dogId: 'dog-bono',
        localServiceDate: LocalServiceDate.fromInstant(
          now,
          timezone: plan.timezone,
        ).isoDate,
        timezone: 'America/Sao_Paulo',
        activePlan: NutritionActiveCanonicalPlan(plan),
        meals: readItems,
      );

      // CRITICAL ASSERTION 1: Read Model planned completion count = 1 / 3
      expect(todayModel.plannedMealsCompleted, 1);
      expect(todayModel.mealsPlanned, 3);
      expect(todayModel.mealsRecorded, 2); // 2 total logs in history list

      // CRITICAL ASSERTION 2: Formatter aggregates
      final offeredSum = HealthNutritionTodayFormatters.offeredSum(readItems);
      expect(offeredSum, 175.0); // 125g + 50g

      final consumedAgg = HealthNutritionTodayFormatters.consumedAggregation(
        readItems,
      );
      expect(consumedAgg.knownSum, 50.0); // Only adhoc 50g is known
      expect(consumedAgg.hasUnknownConsumed, isTrue); // Planned 125g is null

      // CRITICAL ASSERTION 3: Summary Reader planned completion counter
      final coexistenceSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: _FakeCanonicalPlanReader(plan),
        canonicalMealReader: _FakeCanonicalMealReader(mealsList),
      );

      final summaryReader = HealthSummaryNutritionReader(
        coexistenceReadSource: coexistenceSource,
        clock: () => now,
      );

      final summaryResult = await summaryReader.readToday('dog-bono');
      expect(summaryResult.status, HealthSummarySectionStatus.available);

      final summaryData = summaryResult.value!;
      expect(summaryData.mealsRecorded, 1); // Only 1 planned slot completed!
      expect(summaryData.mealsPlanned, 3);
      expect(summaryData.offeredAmount, 175.0);
      expect(summaryData.consumedAmount, 50.0);
    },
  );

  test(
    'F-04 Summary Surface: 1 planned + 1 ad hoc => Resumo shows 1/3 meals, 175g offered, 50g consumed — no ad hoc contamination',
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

      final plannedMeal = MealLog(
        id: 'ml1_planned_1',
        dogId: 'dog-bono',
        planId: 'plan_bono_1',
        plannedMealId: 'slot-1',
        mealOccurrenceId: MealOccurrenceId.v1(
          MealOccurrenceKey(
            dogId: 'dog-bono',
            planId: 'plan_bono_1',
            plannedMealId: 'slot-1',
            localServiceDate: LocalServiceDate.fromInstant(
              now,
              timezone: plan.timezone,
            ),
          ),
        ).value,
        offeredGrams: 125,
        consumedGrams: null, // unknown — no false inference
        acceptance: MealAcceptanceWire.parse('unknown'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      final adhocMeal = MealLog(
        id: 'ml1_adhoc_extra',
        dogId: 'dog-bono',
        planId: null,
        plannedMealId: null,
        mealOccurrenceId: null,
        scheduledFor: null,
        offeredGrams: 50,
        consumedGrams: 50, // known consumption
        acceptance: MealAcceptanceWire.parse('full'),
        period: MealPeriodWire.parseCanonical('extra'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
        source: 'test',
      );

      final mealsList = [plannedMeal, adhocMeal];

      final coexistenceSource = CoexistenceNutritionReadSource(
        canonicalPlanReader: _FakeCanonicalPlanReader(plan),
        canonicalMealReader: _FakeCanonicalMealReader(mealsList),
      );

      final summaryReader = HealthSummaryNutritionReader(
        coexistenceReadSource: coexistenceSource,
        clock: () => now,
      );

      final summaryResult = await summaryReader.readToday('dog-bono');
      expect(summaryResult.status, HealthSummarySectionStatus.available);

      final data = summaryResult.value!;

      // CRITICAL: mealsRecorded = 1, not 2
      // Ad hoc does NOT increment planned completion count
      expect(data.mealsRecorded, 1);

      // Planned total from plan
      expect(data.mealsPlanned, 3);

      // Offered sum: planned (125) + adhoc (50) = 175
      expect(data.offeredAmount, 175.0);

      // Consumed: only adhoc 50g is known; planned 125g has null
      expect(data.consumedAmount, 50.0);

      // Semantic coherence: mealsRecorded = 1 means ONE planned slot completed
      // This matches "1 / 3" display in both Nutrição Hoje and Resumo
    },
  );
}
