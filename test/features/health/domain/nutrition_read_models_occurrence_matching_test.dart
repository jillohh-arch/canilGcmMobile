import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';

final _actor = RecordedBy(
  uid: 'u1',
  name: 'Operador',
  internalRole: 'operator',
);

NutritionPlan _plan({String id = 'plan-1', List<String> slots = const ['am']}) {
  return NutritionPlan(
    id: id,
    dogId: 'dog-1',
    foodType: 'Racao',
    amountGramsPerDay: slots.length * 100,
    mealsPerDay: slots.length,
    mealSchedule: [
      for (var index = 0; index < slots.length; index++)
        MealScheduleSlot(
          id: slots[index],
          period: MealPeriodWire.parseCanonical(
            index == 0 ? 'morning' : 'night',
          ),
          scheduledTime: ScheduledTimeOfDay(index == 0 ? '07:00' : '19:00'),
          targetGrams: 100,
        ),
    ],
    validFrom: DateTime.utc(2026, 1, 1),
    timezone: 'America/Sao_Paulo',
    recordedBy: _actor,
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
  );
}

MealLog _meal({
  required String id,
  required NutritionPlan plan,
  String slot = 'am',
  String? occurrence,
  DateTime? fedAt,
}) {
  final serviceDate = LocalServiceDate.fromIso('2026-07-18');
  return MealLog(
    id: id,
    dogId: plan.dogId,
    planId: plan.id,
    plannedMealId: slot,
    mealOccurrenceId:
        occurrence ??
        MealOccurrenceId.v1(
          MealOccurrenceKey(
            dogId: plan.dogId,
            planId: plan.id,
            plannedMealId: slot,
            localServiceDate: serviceDate,
          ),
        ).value,
    offeredGrams: 100,
    consumedGrams: null,
    acceptance: MealAcceptanceWire.parse('unknown'),
    period: MealPeriodWire.parseCanonical('morning'),
    fedAt: fedAt ?? DateTime.utc(2026, 7, 18, 12),
    recordedBy: _actor,
    revision: 1,
    schemaVersion: 1,
  );
}

NutritionMealReadItem _item(
  MealLog meal, {
  NutritionDataOrigin origin = NutritionDataOrigin.canonical,
}) => NutritionMealReadItem(meal: meal, origin: origin, mergeKey: meal.id);

NutritionTodayReadModel _today(
  NutritionPlan plan,
  List<NutritionMealReadItem> meals,
) {
  return NutritionTodayReadModel(
    dogId: plan.dogId,
    localServiceDate: '2026-07-18',
    timezone: plan.timezone,
    activePlan: NutritionActiveCanonicalPlan(plan),
    meals: meals,
  );
}

void main() {
  test('exact dog plan slot date and occurrence completes only that slot', () {
    final plan = _plan(slots: const ['am', 'pm']);
    final meal = _meal(id: 'meal-1', plan: plan);
    final today = _today(plan, [_item(meal)]);

    expect(today.plannedMealsCompleted, 1);
    expect(
      today.plannedSlotViews.first.status,
      NutritionSlotDayStatus.completed,
    );
    expect(today.plannedSlotViews.first.meal?.meal, same(meal));
    expect(today.plannedSlotViews.last.status, NutritionSlotDayStatus.pending);
  });

  test('same slot from another plan stays planned but not completed', () {
    final active = _plan(slots: const ['am', 'pm']);
    final other = _plan(id: 'plan-2', slots: const ['am', 'pm']);
    final meal = _meal(id: 'other-plan', plan: other);
    final today = _today(active, [_item(meal)]);

    expect(meal.isPlanned, isTrue);
    expect(meal.isAdHoc, isFalse);
    expect(today.meals, hasLength(1));
    expect(today.plannedMealsCompleted, 0);
    expect(today.plannedSlotViews, hasLength(2));
    expect(today.plannedSlotViews.every((slot) => slot.meal == null), isTrue);
  });

  test('incompatible physical occurrence does not complete matching slot', () {
    final plan = _plan();
    final today = _today(plan, [
      _item(_meal(id: 'bad-occurrence', plan: plan, occurrence: 'mo1_wrong')),
    ]);

    expect(today.plannedMealsCompleted, 0);
    expect(
      today.plannedSlotViews.single.status,
      NutritionSlotDayStatus.pending,
    );
  });

  test('duplicate exact occurrence fails closed without arbitrary winner', () {
    final plan = _plan();
    final today = _today(plan, [
      _item(_meal(id: 'duplicate-1', plan: plan)),
      _item(_meal(id: 'duplicate-2', plan: plan)),
    ]);
    final slot = today.plannedSlotViews.single;

    expect(today.plannedMealsCompleted, 0);
    expect(slot.status, NutritionSlotDayStatus.pending);
    expect(slot.meal, isNull);
    expect(slot.hasOccurrenceConflict, isTrue);
    expect(today.meals, hasLength(2));
    expect(today.mealsForDailyTotals, isEmpty);
  });

  test('legacy origin and wrong civil day cannot complete canonical slot', () {
    final plan = _plan();
    final today = _today(plan, [
      _item(
        _meal(id: 'legacy', plan: plan),
        origin: NutritionDataOrigin.legacy,
      ),
      _item(
        _meal(
          id: 'wrong-date',
          plan: plan,
          fedAt: DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    ]);

    expect(today.plannedMealsCompleted, 0);
    expect(
      today.plannedSlotViews.single.status,
      NutritionSlotDayStatus.pending,
    );
  });

  test('UTC instant near midnight resolves through plan timezone', () {
    final plan = _plan();
    final meal = _meal(
      id: 'near-midnight',
      plan: plan,
      fedAt: DateTime.utc(2026, 7, 19, 2, 59),
    );

    expect(_today(plan, [_item(meal)]).plannedMealsCompleted, 1);
  });
}
