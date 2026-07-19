import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';

final class _ScriptedPlanReader implements NutritionCanonicalPlanReader {
  _ScriptedPlanReader(this._plansByDog);

  final Map<String, List<NutritionPlan>> _plansByDog;
  final Map<String, Completer<void>> hold = {};
  final Map<String, int> calls = {};

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    calls[dogId] = (calls[dogId] ?? 0) + 1;
    final gate = hold[dogId];
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    final plans = _plansByDog[dogId] ?? const <NutritionPlan>[];
    return NutritionSourceBatch.available(List.of(plans));
  }
}

NutritionPlan _plan(String id, String dogId) {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');
  return NutritionPlan(
    id: id,
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
    recordedBy: actor,
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
  );
}

void main() {
  test('estado keyed por dogId + refresh preserva dog atual', () async {
    final planReader = _ScriptedPlanReader({
      'dog-a': [_plan('pa', 'dog-a')],
      'dog-b': [_plan('pb', 'dog-b')],
    });
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
    );
    final controller = HealthNutritionReadController(source: source);

    await controller.selectDog('dog-a');
    expect(controller.activeDogId, 'dog-a');
    expect(
      (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'pa',
    );

    await controller.selectDog('dog-b');
    expect(controller.activeDogId, 'dog-b');
    expect(
      (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'pb',
    );

    await controller.refresh();
    expect(controller.activeDogId, 'dog-b');
    expect(planReader.calls['dog-b'], greaterThanOrEqualTo(2));

    controller.dispose();
  });

  test('stale result de dog A não sobrescreve dog B', () async {
    final planReader = _ScriptedPlanReader({
      'dog-a': [_plan('pa', 'dog-a')],
      'dog-b': [_plan('pb', 'dog-b')],
    });
    planReader.hold['dog-a'] = Completer<void>();

    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
    );
    final controller = HealthNutritionReadController(source: source);

    final slowA = controller.selectDog('dog-a');
    // B termina primeiro.
    await controller.selectDog('dog-b');
    expect(controller.activeDogId, 'dog-b');
    expect(
      (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'pb',
    );

    planReader.hold['dog-a']!.complete();
    await slowA;

    expect(controller.activeDogId, 'dog-b');
    expect(
      (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'pb',
    );

    controller.dispose();
  });

  test('dispose safety: future antiga não notifica', () async {
    final planReader = _ScriptedPlanReader({
      'dog-a': [_plan('pa', 'dog-a')],
    });
    planReader.hold['dog-a'] = Completer<void>();
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
    );
    final controller = HealthNutritionReadController(source: source);

    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.selectDog('dog-a');
    controller.dispose();
    final before = notifications;
    planReader.hold['dog-a']!.complete();
    await pending;
    // Apenas notifies anteriores ao dispose (loading); sem notify pós-dispose.
    expect(notifications, before);
    expect(controller.isDisposedForTest, isTrue);
  });

  test('ensureDogAndRefresh troca dog se necessário', () async {
    final planReader = _ScriptedPlanReader({
      'dog-a': [_plan('pa', 'dog-a')],
      'dog-b': [_plan('pb', 'dog-b')],
    });
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
    );
    final controller = HealthNutritionReadController(source: source);

    await controller.ensureDogAndRefresh('dog-a');
    expect(controller.activeDogId, 'dog-a');
    await controller.ensureDogAndRefresh('dog-b');
    expect(controller.activeDogId, 'dog-b');
    expect(
      (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'pb',
    );
    controller.dispose();
  });
}
