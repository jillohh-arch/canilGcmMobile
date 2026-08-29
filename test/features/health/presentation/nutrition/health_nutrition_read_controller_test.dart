import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
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

final class _SequencePlanReader implements NutritionCanonicalPlanReader {
  _SequencePlanReader(this.batches);

  final List<NutritionSourceBatch<NutritionPlan>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _SequenceMealReader implements NutritionCanonicalMealReader {
  _SequenceMealReader(this.batches);

  final List<NutritionSourceBatch<MealLog>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _SequenceSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  _SequenceSupplementReader(this.batches);

  final List<NutritionSourceBatch<SupplementLog>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _ControlledPlanReader implements NutritionCanonicalPlanReader {
  final responses = <Completer<NutritionSourceBatch<NutritionPlan>>>[];
  final started = <Completer<void>>[];
  var calls = 0;

  void enqueue() {
    responses.add(Completer<NutritionSourceBatch<NutritionPlan>>());
    started.add(Completer<void>());
  }

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) {
    final index = calls++;
    started[index].complete();
    return responses[index].future;
  }
}

final class _FakeMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  void advance(Duration duration) => value += duration;
}

final class _TemporalGateway implements AuthoritativeTimeGateway {
  _TemporalGateway(this.callback);

  Future<AuthoritativeTimeRemoteResponse> Function() callback;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() {
    calls++;
    return callback();
  }
}

AuthoritativeTimeRemoteResponse _timeResponse({int sequence = 1}) {
  final base = DateTime.utc(2026, 7, 22, 15);
  return AuthoritativeTimeRemoteResponse(
    protocolVersion: 1,
    requestId:
        '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
    requestReceivedAtUtc: base,
    serverSentAtUtc: base,
    maxAge: const Duration(minutes: 15),
  );
}

NutritionPlan _plan(
  String id,
  String dogId, {
  double amountGramsPerDay = 200,
  String slotId = 's1',
}) {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');
  return NutritionPlan(
    id: id,
    dogId: dogId,
    foodType: 'Ração',
    amountGramsPerDay: amountGramsPerDay,
    mealsPerDay: 1,
    mealSchedule: [
      MealScheduleSlot(
        id: slotId,
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: amountGramsPerDay,
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

MealLog _meal({
  required String id,
  required String planId,
  required String slotId,
  required double offeredGrams,
}) {
  final fedAt = DateTime.utc(2026, 7, 22, 12);
  final occurrenceId = MealOccurrenceId.v1(
    MealOccurrenceKey(
      dogId: 'dog-a',
      planId: planId,
      plannedMealId: slotId,
      localServiceDate: LocalServiceDate.fromInstant(
        fedAt,
        timezone: NutritionPlan.defaultTimezone,
      ),
    ),
  ).value;
  return MealLog(
    id: id,
    dogId: 'dog-a',
    period: MealPeriodWire.parseCanonical('morning'),
    offeredGrams: offeredGrams,
    consumedGrams: offeredGrams,
    acceptance: MealAcceptanceWire.parse('full'),
    fedAt: fedAt,
    recordedBy: RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin'),
    schemaVersion: 1,
    revision: 1,
    plannedMealId: slotId,
    planId: planId,
    mealOccurrenceId: occurrenceId,
  );
}

SupplementLog _supplement(String id) => SupplementLog(
  id: id,
  dogId: 'dog-a',
  supplementName: id,
  dose: 1,
  unit: SupplementDoseUnit.tablet,
  administeredAt: DateTime.utc(2026, 7, 22, 12),
  recordedBy: RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin'),
  schemaVersion: 1,
  revision: 1,
);

void main() {
  test('authoritative fresh is atomic and refresh forces a new sync', () async {
    final monotonic = _FakeMonotonicClock();
    var sequence = 0;
    final gateway = _TemporalGateway(
      () async => _timeResponse(sequence: ++sequence),
    );
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _SequencePlanReader([
        NutritionSourceBatch.available([_plan('pa', 'dog-a')]),
      ]),
    );
    final controller = HealthNutritionReadController(
      source: source,
      authoritativeTimeProvider: AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: monotonic,
      ),
    );
    addTearDown(controller.dispose);

    await controller.selectDog('dog-a');
    expect(gateway.calls, 1);
    expect(controller.temporalState, HealthNutritionTemporalState.fresh);
    expect(controller.todayOrNull?.referenceNow, DateTime.utc(2026, 7, 22, 15));

    await controller.refresh();
    expect(gateway.calls, 2);
    expect(controller.snapshotResult.valueOrNull, isNotNull);
    expect(controller.todayResult?.isData, isTrue);
  });

  test(
    'stale anchor preserves safe today with diagnostic and blocks actions',
    () async {
      final monotonic = _FakeMonotonicClock();
      var fail = false;
      final gateway = _TemporalGateway(() async {
        if (fail) {
          throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'callable indisponível',
          );
        }
        return _timeResponse();
      });
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: _SequencePlanReader([
            NutritionSourceBatch.available([_plan('pa', 'dog-a')]),
          ]),
        ),
        authoritativeTimeProvider: AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: monotonic,
        ),
      );
      addTearDown(controller.dispose);

      await controller.selectDog('dog-a');
      monotonic.advance(const Duration(minutes: 6));
      fail = true;
      await controller.refresh();

      expect(controller.temporalState, HealthNutritionTemporalState.stale);
      expect(controller.temporalActionsAllowed, isFalse);
      expect(controller.todayResult?.isDegraded, isTrue);
      expect(controller.todayOrNull, isNotNull);
      expect(
        controller.temporalFailure?.code,
        AuthoritativeTimeFailureCode.unavailable,
      );
    },
  );

  test(
    'expired anchor keeps snapshot facts but never recalculates today',
    () async {
      final monotonic = _FakeMonotonicClock();
      var fail = false;
      final gateway = _TemporalGateway(() async {
        if (fail) {
          throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'callable indisponível',
          );
        }
        return _timeResponse();
      });
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: _SequencePlanReader([
            NutritionSourceBatch.available([_plan('pa', 'dog-a')]),
          ]),
        ),
        authoritativeTimeProvider: AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: monotonic,
        ),
      );
      addTearDown(controller.dispose);

      await controller.selectDog('dog-a');
      monotonic.advance(const Duration(minutes: 16));
      fail = true;
      await controller.refresh();

      expect(controller.snapshotResult.valueOrNull, isNotNull);
      expect(
        controller.temporalState,
        HealthNutritionTemporalState.unavailable,
      );
      expect(controller.todayResult?.isError, isTrue);
      expect(controller.todayResult?.code, 'authoritative_time_unavailable');
      expect(controller.temporalActionsAllowed, isFalse);
    },
  );

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
    expect(planReader.calls['dog-b'], 2);

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

  test('snapshot e today preservam o mesmo erro e refresh recupera', () async {
    final plan = _plan('pa', 'dog-a');
    final reader = _SequencePlanReader([
      const NutritionSourceBatch.error(message: 'today failed'),
      NutritionSourceBatch.available([plan]),
    ]);
    final controller = HealthNutritionReadController(
      source: CoexistenceNutritionReadSource(canonicalPlanReader: reader),
      clock: () => DateTime.utc(2026, 7, 22, 12),
    );

    await controller.selectDog('dog-a');
    expect(controller.snapshotResult.isError, isTrue);
    expect(controller.todayResult?.isError, isTrue);
    expect(controller.todayOrNull, isNull);

    await controller.refresh();
    expect(controller.snapshotResult.hasUsableValue, isTrue);
    expect(controller.todayResult?.isData, isTrue);
    expect(controller.todayOrNull?.dogId, 'dog-a');
    expect(reader.calls, 2);
    controller.dispose();
  });

  test(
    'uma leitura por geração mantém plano meta slots refeições e suplementos atômicos',
    () async {
      final planA = _plan(
        'plan-a',
        'dog-a',
        amountGramsPerDay: 200,
        slotId: 'slot-a',
      );
      final planB = _plan(
        'plan-b',
        'dog-a',
        amountGramsPerDay: 500,
        slotId: 'slot-b',
      );
      final plans = _SequencePlanReader([
        NutritionSourceBatch.available([planA]),
        NutritionSourceBatch.available([planB]),
      ]);
      final meals = _SequenceMealReader([
        NutritionSourceBatch.available([
          _meal(
            id: 'meal-a',
            planId: 'plan-a',
            slotId: 'slot-a',
            offeredGrams: 200,
          ),
        ]),
        NutritionSourceBatch.available([
          _meal(
            id: 'meal-b',
            planId: 'plan-b',
            slotId: 'slot-b',
            offeredGrams: 500,
          ),
        ]),
      ]);
      final supplements = _SequenceSupplementReader([
        NutritionSourceBatch.available([_supplement('supp-a')]),
        NutritionSourceBatch.available([_supplement('supp-b')]),
      ]);
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: plans,
          canonicalMealReader: meals,
          canonicalSupplementLogReader: supplements,
        ),
        clock: () => DateTime.utc(2026, 7, 22, 12),
      );

      await controller.selectDog('dog-a');
      expect(plans.calls, 1);
      expect(meals.calls, 1);
      expect(supplements.calls, 1);
      expect(
        (controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan)
            .plan
            .id,
        'plan-a',
      );
      expect(
        (controller.todayOrNull!.activePlan as NutritionActiveCanonicalPlan)
            .plan
            .id,
        'plan-a',
      );
      expect(controller.todayOrNull!.meals.single.meal.id, 'meal-a');
      expect(
        controller.todayOrNull!.canonicalSupplementLogs.single.id,
        'supp-a',
      );
      expect(controller.todayOrNull!.plannedMealsCompleted, 1);

      await controller.refresh();
      expect(plans.calls, 2);
      expect(meals.calls, 2);
      expect(supplements.calls, 2);
      final snapshotPlan =
          controller.snapshotOrNull!.activePlan as NutritionActiveCanonicalPlan;
      final todayPlan =
          controller.todayOrNull!.activePlan as NutritionActiveCanonicalPlan;
      expect(snapshotPlan.plan.id, 'plan-b');
      expect(todayPlan.plan.id, 'plan-b');
      expect(snapshotPlan.plan.amountGramsPerDay, 500);
      expect(todayPlan.plan.mealSchedule.single.id, 'slot-b');
      expect(controller.todayOrNull!.meals.single.meal.id, 'meal-b');
      expect(
        controller.todayOrNull!.canonicalSupplementLogs.single.id,
        'supp-b',
      );
      expect(controller.todayOrNull!.plannedMealsCompleted, 1);
      expect(controller.todayOrNull!.meals, hasLength(1));
      controller.dispose();
    },
  );

  test('refresh concorrente do mesmo K9 mantém geração mais nova', () async {
    final plans = _ControlledPlanReader()
      ..enqueue()
      ..enqueue();
    final meals = _SequenceMealReader([
      NutritionSourceBatch.available([
        _meal(
          id: 'meal-new',
          planId: 'plan-new',
          slotId: 'slot-new',
          offeredGrams: 500,
        ),
      ]),
      NutritionSourceBatch.available([
        _meal(
          id: 'meal-old',
          planId: 'plan-old',
          slotId: 'slot-old',
          offeredGrams: 200,
        ),
      ]),
    ]);
    final supplements = _SequenceSupplementReader([
      NutritionSourceBatch.available([_supplement('supp-new')]),
      NutritionSourceBatch.available([_supplement('supp-old')]),
    ]);
    final controller = HealthNutritionReadController(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: plans,
        canonicalMealReader: meals,
        canonicalSupplementLogReader: supplements,
      ),
      clock: () => DateTime.utc(2026, 7, 22, 12),
    );

    final oldGeneration = controller.selectDog('dog-a');
    await plans.started[0].future;
    final newGeneration = controller.refresh();
    await plans.started[1].future;
    plans.responses[1].complete(
      NutritionSourceBatch.available([
        _plan('plan-new', 'dog-a', amountGramsPerDay: 500, slotId: 'slot-new'),
      ]),
    );
    await newGeneration;
    expect(controller.generationForTest, 2);
    expect(
      (controller.todayOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'plan-new',
    );
    expect(controller.todayOrNull!.meals.single.meal.id, 'meal-new');
    expect(
      controller.todayOrNull!.canonicalSupplementLogs.single.id,
      'supp-new',
    );

    plans.responses[0].complete(
      NutritionSourceBatch.available([
        _plan('plan-old', 'dog-a', slotId: 'slot-old'),
      ]),
    );
    await oldGeneration;
    expect(
      (controller.todayOrNull!.activePlan as NutritionActiveCanonicalPlan)
          .plan
          .id,
      'plan-new',
    );
    expect(controller.todayOrNull!.meals.single.meal.id, 'meal-new');
    expect(
      controller.todayOrNull!.canonicalSupplementLogs.single.id,
      'supp-new',
    );
    expect(controller.todayOrNull!.meals, hasLength(1));
    controller.dispose();
  });
}
