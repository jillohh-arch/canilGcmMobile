import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
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

final class _UnavailablePlanReader implements NutritionCanonicalPlanReader {
  _UnavailablePlanReader(this.batch);

  final NutritionSourceBatch<NutritionPlan> batch;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      batch;
}

final class _UnavailableMealReader implements NutritionCanonicalMealReader {
  _UnavailableMealReader(this.batch);

  final NutritionSourceBatch<MealLog> batch;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => batch;
}

final class _UnavailableSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  _UnavailableSupplementReader(this.batch);

  final NutritionSourceBatch<SupplementLog> batch;

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async => batch;
}

final class _SummaryMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;
}

final class _SummaryTimeGateway implements AuthoritativeTimeGateway {
  bool fail = false;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    calls++;
    if (fail) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unavailable,
        'callable indisponível',
      );
    }
    final now = DateTime.utc(2026, 7, 22, 12);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

void main() {
  final actor = RecordedBy(
    uid: 'user-1',
    name: 'Operador',
    internalRole: 'operator',
  );

  test('Summary applies fresh stale and expired temporal policy', () async {
    final now = DateTime.utc(2026, 7, 22, 12);
    final meal = MealLog(
      id: 'temporal-meal',
      dogId: 'dog-bono',
      offeredGrams: 180,
      consumedGrams: 120,
      acceptance: MealAcceptanceWire.parse('partial'),
      period: MealPeriodWire.parseCanonical('morning'),
      fedAt: now,
      recordedBy: actor,
      revision: 1,
      schemaVersion: 1,
    );
    final gateway = _SummaryTimeGateway();
    final monotonic = _SummaryMonotonicClock();
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: monotonic,
    );
    final reader = HealthSummaryNutritionReader(
      coexistenceReadSource: CoexistenceNutritionReadSource(
        canonicalPlanReader: _FakeCanonicalPlanReader(null),
        canonicalMealReader: _FakeCanonicalMealReader([meal]),
      ),
      authoritativeTimeProvider: provider,
    );

    final fresh = await reader.readToday('dog-bono');
    expect(fresh.isAvailable, isTrue);
    expect(fresh.isDegraded, isFalse);

    monotonic.value = const Duration(minutes: 6);
    gateway.fail = true;
    await provider.synchronize(force: true);
    final stale = await reader.readToday(
      'dog-bono',
      synchronizeTime: false,
    );
    expect(stale.isAvailable, isTrue);
    expect(stale.isDegraded, isTrue);
    expect(stale.message, contains('Horário aguardando atualização'));
    expect(stale.valueOrNull?.consumedAmount, 120);
    expect(gateway.calls, 2);

    monotonic.value = const Duration(minutes: 16);
    final expired = await reader.readToday(
      'dog-bono',
      synchronizeTime: false,
    );
    expect(expired.isUnavailable, isTrue);
    expect(expired.valueOrNull, isNull);
    expect(expired.message, contains('Horário confiável indisponível'));
    expect(gateway.calls, 2);
  });

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
      expect(result.isDegraded, isFalse);

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

  test(
    'Summary fails closed for cross-plan and duplicate occurrence',
    () async {
      final now = DateTime.utc(2026, 7, 18, 12);
      final plan = NutritionPlan(
        id: 'plan-active',
        dogId: 'dog-bono',
        foodType: 'Racao',
        amountGramsPerDay: 125,
        mealsPerDay: 1,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-1',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 125,
          ),
        ],
        validFrom: DateTime.utc(2026, 1, 1),
        timezone: 'America/Sao_Paulo',
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );
      String occurrence(String planId) => MealOccurrenceId.v1(
        MealOccurrenceKey(
          dogId: plan.dogId,
          planId: planId,
          plannedMealId: 'slot-1',
          localServiceDate: LocalServiceDate.fromInstant(
            now,
            timezone: plan.timezone,
          ),
        ),
      ).value;
      MealLog meal(String id, String planId) => MealLog(
        id: id,
        dogId: plan.dogId,
        planId: planId,
        plannedMealId: 'slot-1',
        mealOccurrenceId: occurrence(planId),
        offeredGrams: 125,
        consumedGrams: null,
        acceptance: MealAcceptanceWire.parse('unknown'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
      );
      Future<(int?, double?)> projection(List<MealLog> meals) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(plan),
          canonicalMealReader: _FakeCanonicalMealReader(meals),
        );
        final result = await HealthSummaryNutritionReader(
          coexistenceReadSource: source,
          clock: () => now,
        ).readToday(plan.dogId);
        return (result.value!.mealsRecorded, result.value!.offeredAmount);
      }

      expect(await projection([meal('cross-plan', 'plan-old')]), (0, 125.0));
      expect(
        await projection([
          meal('duplicate-a', plan.id),
          meal('duplicate-b', plan.id),
        ]),
        (0, null),
      );
    },
  );

  test(
    'Summary does not fall back to another snapshot after today error',
    () async {
      var fallbackCalls = 0;
      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _UnavailablePlanReader(
            const NutritionSourceBatch.error(message: 'plan failed'),
          ),
          canonicalMealReader: _UnavailableMealReader(
            const NutritionSourceBatch.error(message: 'meals failed'),
          ),
        ),
        loadDaySnapshot: (_) async {
          fallbackCalls++;
          return const HealthSummaryNutritionDaySnapshot(feedings: []);
        },
        clock: () => DateTime.utc(2026, 7, 22, 12),
      );

      final result = await reader.readToday('dog-bono');

      expect(result.status, HealthSummarySectionStatus.unavailable);
      expect(result.value, isNull);
      expect(fallbackCalls, 0);
    },
  );

  test(
    'Summary keeps offline unavailable and valid empty notRecorded',
    () async {
      Future<HealthSummarySectionStatus> statusFor({
        required NutritionSourceBatch<NutritionPlan> plans,
        required NutritionSourceBatch<MealLog> meals,
      }) async {
        final reader = HealthSummaryNutritionReader(
          coexistenceReadSource: CoexistenceNutritionReadSource(
            canonicalPlanReader: _UnavailablePlanReader(plans),
            canonicalMealReader: _UnavailableMealReader(meals),
          ),
          clock: () => DateTime.utc(2026, 7, 22, 12),
        );
        return (await reader.readToday('dog-bono')).status;
      }

      expect(
        await statusFor(
          plans: const NutritionSourceBatch.offline(),
          meals: const NutritionSourceBatch.offline(),
        ),
        HealthSummarySectionStatus.unavailable,
      );
      expect(
        await statusFor(
          plans: const NutritionSourceBatch.empty(),
          meals: const NutritionSourceBatch.empty(),
        ),
        HealthSummarySectionStatus.notRecorded,
      );
    },
  );

  test(
    'Summary preserva degraded e totais seguros quando supplement_logs falha',
    () async {
      final now = DateTime.utc(2026, 7, 22, 12);
      final meal = MealLog(
        id: 'meal-safe',
        dogId: 'dog-bono',
        offeredGrams: 180,
        consumedGrams: 120,
        acceptance: MealAcceptanceWire.parse('partial'),
        period: MealPeriodWire.parseCanonical('morning'),
        fedAt: now,
        recordedBy: actor,
        revision: 1,
        schemaVersion: 1,
      );
      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(null),
          canonicalMealReader: _FakeCanonicalMealReader([meal]),
          canonicalSupplementLogReader: _UnavailableSupplementReader(
            const NutritionSourceBatch.error(
              message: 'supplement_logs indisponível',
            ),
          ),
        ),
        clock: () => now,
      );

      final result = await reader.readToday('dog-bono');

      expect(result.status, HealthSummarySectionStatus.available);
      expect(result.isAvailable, isTrue);
      expect(result.isDegraded, isTrue);
      expect(result.message, contains('parcial'));
      expect(result.valueOrNull, isNotNull);
      expect(result.value!.offeredAmount, 180);
      expect(result.value!.consumedAmount, 120);
      expect(result.isUnavailable, isFalse);
    },
  );

  // ════════════════════════════════════════════════════════════════════════════════
  // UX-04B3C — CANONICAL CONTEXT MATRIX
  // ════════════════════════════════════════════════════════════════════════════════

  group('UX-04B3C — Canonical Context Matrix', () {
    final validDogId = 'dog-canonical-test';
    final now = DateTime.utc(2026, 7, 22, 12);

    test('no plan: dogId real, nutrition notRecorded, activePlan null', () async {
      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(null),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      final result = await reader.readToday(validDogId);

      expect(result.status, HealthSummarySectionStatus.notRecorded);
      expect(result.valueOrNull, isNull);
      expect(result.isUnavailable, isFalse);
      expect(result.isAvailable, isFalse);
    });

    test('legacy plan: dogId real, canonical reader returns null, notRecorded', () async {
      // Legacy plans are not returned by canonicalPlanReader
      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(null),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      final result = await reader.readToday(validDogId);

      // No canonical conversion of legacy data — treated as no plan
      expect(result.status, HealthSummarySectionStatus.notRecorded);
    });

    test('canonical plan active: dogId real, nutrition available', () async {
      final plan = NutritionPlan(
        id: 'plan-canonical-1',
        dogId: validDogId,
        foodType: 'Ração Canônica',
        amountGramsPerDay: 500,
        mealsPerDay: 2,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-m',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 250,
          ),
        ],
        validFrom: DateTime.utc(2026, 1, 1),
        timezone: NutritionPlan.defaultTimezone,
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(plan),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      final result = await reader.readToday(validDogId);

      // Plan exists and is active
      expect(result.isAvailable, isTrue);
      expect(result.valueOrNull, isNotNull);
      // Plan has expected characteristics
      expect(result.status, HealthSummarySectionStatus.available);
    });

    test('expired plan (superseded status): treated as not effective, notRecorded', () async {
      final expiredPlan = NutritionPlan(
        id: 'plan-expired',
        dogId: validDogId,
        foodType: 'Ração Vencida',
        amountGramsPerDay: 500,
        mealsPerDay: 2,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-m',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 250,
          ),
        ],
        validFrom: DateTime.utc(2025, 1, 1),
        validUntil: DateTime.utc(2025, 12, 31),
        timezone: NutritionPlan.defaultTimezone,
        recordedBy: actor,
        status: NutritionPlanStatus.superseded,
        schemaVersion: 1,
        revision: 1,
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(expiredPlan),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      final result = await reader.readToday(validDogId);

      // Superseded/expired plan is not effective for nutrition
      expect(result.status, HealthSummarySectionStatus.notRecorded);
    });

    test('cancelled plan: not effective, notRecorded', () async {
      final cancelledPlan = NutritionPlan(
        id: 'plan-cancelled',
        dogId: validDogId,
        foodType: 'Ração Cancelada',
        amountGramsPerDay: 500,
        mealsPerDay: 2,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-m',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 250,
          ),
        ],
        validFrom: DateTime.utc(2026, 1, 1),
        timezone: NutritionPlan.defaultTimezone,
        recordedBy: actor,
        status: NutritionPlanStatus.cancelled,
        schemaVersion: 1,
        revision: 1,
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(cancelledPlan),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      final result = await reader.readToday(validDogId);

      // Cancelled plan is not effective
      expect(result.status, HealthSummarySectionStatus.notRecorded);
    });

    test('plan for different dogId: no match, notRecorded', () async {
      final plan = NutritionPlan(
        id: 'plan-1',
        dogId: 'dog-other', // Different dogId
        foodType: 'Ração',
        amountGramsPerDay: 500,
        mealsPerDay: 2,
        mealSchedule: [
          MealScheduleSlot(
            id: 'slot-m',
            period: MealPeriodWire.parseCanonical('morning'),
            scheduledTime: ScheduledTimeOfDay('07:00'),
            targetGrams: 250,
          ),
        ],
        validFrom: DateTime.utc(2026, 1, 1),
        timezone: NutritionPlan.defaultTimezone,
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
        revision: 1,
      );

      final reader = HealthSummaryNutritionReader(
        coexistenceReadSource: CoexistenceNutritionReadSource(
          canonicalPlanReader: _FakeCanonicalPlanReader(plan),
          canonicalMealReader: _FakeCanonicalMealReader([]),
        ),
        clock: () => now,
      );

      // Request for a dogId that doesn't match the plan's dogId
      final result = await reader.readToday('dog-nonexistent');

      // The plan belongs to a different dog — not effective for this dog
      expect(result.status, HealthSummarySectionStatus.notRecorded);
    });
  });
}