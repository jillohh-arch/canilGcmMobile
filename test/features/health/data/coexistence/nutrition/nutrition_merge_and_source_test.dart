import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');
  final t0 = DateTime.utc(2026, 7, 14, 8);
  final t1 = DateTime.utc(2026, 7, 14, 19);

  MealLog meal({
    required String id,
    required String dogId,
    required DateTime fedAt,
    String? legacyId,
    String? legacySource,
    num offered = 100,
  }) {
    return MealLog(
      id: id,
      dogId: dogId,
      period: MealPeriodWire.parseCanonical('morning'),
      offeredGrams: offered,
      acceptance: MealAcceptanceWire.parse('unknown'),
      fedAt: fedAt,
      recordedBy: actor,
      schemaVersion: 1,
      revision: 1,
      legacyId: legacyId,
      legacySource: legacySource,
    );
  }

  NutritionPlan canonicalPlan({
    required String id,
    required String dogId,
    NutritionPlanStatus status = NutritionPlanStatus.active,
    DateTime? validFrom,
  }) {
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
      validFrom: validFrom ?? DateTime.utc(2026, 1, 1),
      timezone: NutritionPlan.defaultTimezone,
      recordedBy: actor,
      status: status,
      schemaVersion: 1,
      revision: 1,
    );
  }

  LegacyNutritionPlanView legacyPlan({
    required String id,
    required String dogId,
  }) {
    return LegacyNutritionPlanView(
      id: id,
      dogId: dogId,
      foodType: 'Ração L',
      amountGramsPerDay: 300,
      mealsPerDay: 2,
      vigentFrom: DateTime.utc(2026, 6, 1),
      legacySource: 'nutritional_prescriptions',
    );
  }

  group('NutritionLegacySourceIdentity', () {
    test('normaliza path e aliases sem fundir collections distintas', () {
      expect(
        NutritionLegacySourceIdentity.normalize('dogs/dog-1/feeding_events'),
        'feeding_events',
      );
      expect(NutritionLegacySourceIdentity.normalize('/feedings'), 'feedings');
      expect(
        NutritionLegacySourceIdentity.normalize('feeding_events'),
        isNot(NutritionLegacySourceIdentity.normalize('feedings')),
      );
      expect(NutritionLegacySourceIdentity.normalize(null), isNull);
      expect(NutritionLegacySourceIdentity.normalize('  '), isNull);
    });
  });

  group('mergeLegacyMealCollections §22', () {
    test(
      'mesmo ID: feeding_events vence feedings (ordem invertida de entrada)',
      () {
        final result = NutritionMergePolicy.mergeLegacyMealCollections(
          envelopes: [
            LegacyMealEnvelope(
              meal: meal(id: 'x1', dogId: 'dog-1', fedAt: t0, offered: 100),
              collectionKey: NutritionMergePolicy.feedings,
            ),
            LegacyMealEnvelope(
              meal: meal(id: 'x1', dogId: 'dog-1', fedAt: t0, offered: 150),
              collectionKey: 'dogs/x/feeding_events',
            ),
          ],
        );
        expect(result.items, hasLength(1));
        expect(result.items.single.collectionKey, 'feeding_events');
        expect(result.items.single.meal.offeredGrams, 150);
      },
    );

    test('mesmo ID com payload divergente → primary vence + warning', () {
      final result = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'x1', dogId: 'dog-1', fedAt: t0, offered: 100),
            collectionKey: NutritionMergePolicy.feedings,
          ),
          LegacyMealEnvelope(
            meal: meal(id: 'x1', dogId: 'dog-1', fedAt: t1, offered: 200),
            collectionKey: NutritionMergePolicy.feedingEvents,
          ),
        ],
      );
      expect(result.items.single.meal.offeredGrams, 200);
      expect(
        result.diagnostics.any((d) => d.code == 'legacy_meal_payload_conflict'),
        isTrue,
      );
    });
  });

  group('mergeCanonicalAndLegacyMeals — provenance gate', () {
    test('Caso A: legacySource+legacyId → canônico vence', () {
      final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 100),
            collectionKey: 'feeding_events',
          ),
        ],
      ).items;
      final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
        canonical: [
          meal(
            id: 'c1',
            dogId: 'dog-1',
            fedAt: t0,
            offered: 120,
            legacyId: 'X',
            legacySource: 'feeding_events',
          ),
        ],
        legacyItems: legacyItems,
      );
      expect(merged.items, hasLength(1));
      expect(merged.items.single.origin, NutritionDataOrigin.canonical);
      expect(merged.items.single.meal.offeredGrams, 120);
    });

    test('Caso B: legacyId sozinho NÃO deduplica', () {
      final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 100),
            collectionKey: 'feeding_events',
          ),
        ],
      ).items;
      final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
        canonical: [
          meal(
            id: 'c1',
            dogId: 'dog-1',
            fedAt: t0,
            offered: 120,
            legacyId: 'X',
            // legacySource null
          ),
        ],
        legacyItems: legacyItems,
      );
      expect(merged.items, hasLength(2));
      expect(
        merged.diagnostics.any(
          (d) => d.code == 'insufficient_provenience_same_legacy_id',
        ),
        isTrue,
      );
    });

    test('Caso C: feeding_events canônico × feedings legado → 2 itens', () {
      final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 100),
            collectionKey: 'feedings',
          ),
        ],
      ).items;
      final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
        canonical: [
          meal(
            id: 'c1',
            dogId: 'dog-1',
            fedAt: t0,
            offered: 120,
            legacyId: 'X',
            legacySource: 'feeding_events',
          ),
        ],
        legacyItems: legacyItems,
      );
      // Collections distintas: proveniência não casa.
      expect(merged.items, hasLength(2));
    });

    test(
      'Caso C-pipeline: events+feedings colapsam, depois canônico events vence',
      () {
        final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
          envelopes: [
            LegacyMealEnvelope(
              meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 90),
              collectionKey: 'feedings',
            ),
            LegacyMealEnvelope(
              meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 100),
              collectionKey: 'feeding_events',
            ),
          ],
        ).items;
        expect(legacyItems, hasLength(1));
        expect(legacyItems.single.collectionKey, 'feeding_events');

        final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
          canonical: [
            meal(
              id: 'c1',
              dogId: 'dog-1',
              fedAt: t0,
              offered: 120,
              legacyId: 'X',
              legacySource: 'feeding_events',
            ),
          ],
          legacyItems: legacyItems,
        );
        expect(merged.items, hasLength(1));
        expect(merged.items.single.meal.offeredGrams, 120);
      },
    );

    test('Caso D: outra_collection + mesmo id → 2 itens', () {
      final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'X', dogId: 'dog-1', fedAt: t0, offered: 100),
            collectionKey: 'feeding_events',
          ),
        ],
      ).items;
      final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
        canonical: [
          meal(
            id: 'c1',
            dogId: 'dog-1',
            fedAt: t0,
            offered: 120,
            legacyId: 'X',
            legacySource: 'nutritional_prescriptions',
          ),
        ],
        legacyItems: legacyItems,
      );
      expect(merged.items, hasLength(2));
    });

    test('path-normalized source casa com leaf id', () {
      final legacyItems = NutritionMergePolicy.mergeLegacyMealCollections(
        envelopes: [
          LegacyMealEnvelope(
            meal: meal(id: 'abc', dogId: 'dog-1', fedAt: t0),
            collectionKey: 'feeding_events',
          ),
        ],
      ).items;
      final merged = NutritionMergePolicy.mergeCanonicalAndLegacyMeals(
        canonical: [
          meal(
            id: 'c1',
            dogId: 'dog-1',
            fedAt: t0,
            legacyId: 'abc',
            legacySource: 'dogs/dog-1/feeding_events',
          ),
        ],
        legacyItems: legacyItems,
      );
      expect(merged.items, hasLength(1));
    });
  });

  group('resolveActivePlan — D3 multiple active', () {
    test('0 active → fallback legado', () {
      final ref = NutritionMergePolicy.resolveActivePlan(
        canonical: [
          canonicalPlan(
            id: 'c',
            dogId: 'dog-1',
            status: NutritionPlanStatus.superseded,
          ),
        ],
        legacy: [legacyPlan(id: 'l', dogId: 'dog-1')],
      );
      expect(ref, isA<NutritionActiveLegacyPlan>());
    });

    test('1 active → canonical', () {
      final ref = NutritionMergePolicy.resolveActivePlan(
        canonical: [canonicalPlan(id: 'c', dogId: 'dog-1')],
        legacy: [legacyPlan(id: 'l', dogId: 'dog-1')],
      );
      expect(ref, isA<NutritionActiveCanonicalPlan>());
      expect((ref as NutritionActiveCanonicalPlan).plan.id, 'c');
    });

    test('>1 active → integrity conflict (não escolhe mais recente)', () {
      final ref = NutritionMergePolicy.resolveActivePlan(
        canonical: [
          canonicalPlan(
            id: 'old',
            dogId: 'dog-1',
            validFrom: DateTime.utc(2025, 1, 1),
          ),
          canonicalPlan(
            id: 'new',
            dogId: 'dog-1',
            validFrom: DateTime.utc(2026, 6, 1),
          ),
        ],
        legacy: [legacyPlan(id: 'l', dogId: 'dog-1')],
      );
      expect(ref, isA<NutritionActivePlanIntegrityConflict>());
      final conflict = ref as NutritionActivePlanIntegrityConflict;
      expect(conflict.activeCount, 2);
      expect(conflict.activePlanIds, containsAll(['old', 'new']));
      // Não é NutritionActiveCanonicalPlan com o "mais novo".
      expect(ref, isNot(isA<NutritionActiveCanonicalPlan>()));
    });
  });

  group('CoexistenceNutritionReadSource §29', () {
    test('today aggregation usa data civil America/Sao_Paulo', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemCanonicalPlans([
          canonicalPlan(id: 'tz-plan', dogId: 'dog-1'),
        ]),
        canonicalMealReader: _MemCanonicalMeals([
          meal(
            id: 'local-yesterday',
            dogId: 'dog-1',
            fedAt: DateTime.utc(2026, 7, 19, 0, 30),
          ),
          meal(
            id: 'local-today',
            dogId: 'dog-1',
            fedAt: DateTime.utc(2026, 7, 19, 23, 30),
          ),
        ]),
      );

      final result = await source.loadToday(
        'dog-1',
        serverNow: DateTime.utc(2026, 7, 19, 16),
      );

      expect(result.isData, isTrue);
      expect(result.value!.localServiceDate, '2026-07-19');
      expect(result.value!.meals.map((m) => m.meal.id), ['local-today']);
    });

    test('1. canonical only', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemCanonicalPlans([
          canonicalPlan(id: 'c', dogId: 'dog-1'),
        ]),
        canonicalMealReader: _MemCanonicalMeals([
          meal(id: 'm1', dogId: 'dog-1', fedAt: t0),
        ]),
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isData, isTrue);
      expect(r.value!.mergedMeals, hasLength(1));
      expect(r.value!.activePlan, isA<NutritionActiveCanonicalPlan>());
    });

    test('2. legacy only', () async {
      final source = CoexistenceNutritionReadSource(
        legacyPlanReader: _MemLegacyPlans([
          legacyPlan(id: 'l', dogId: 'dog-1'),
        ]),
        legacyMealReaders: [
          _MemLegacyMeals('feeding_events', [
            meal(id: 'm1', dogId: 'dog-1', fedAt: t0),
          ]),
        ],
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isData, isTrue);
      expect(r.value!.activePlan, isA<NutritionActiveLegacyPlan>());
    });

    test('3. ambos vazios → empty', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemCanonicalPlans(const []),
        canonicalMealReader: _MemCanonicalMeals(const []),
        legacyPlanReader: _MemLegacyPlans(const []),
        legacyMealReaders: [_MemLegacyMeals('feeding_events', const [])],
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isEmpty, isTrue);
    });

    test('multiple active detectável no snapshot', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemCanonicalPlans([
          canonicalPlan(id: 'a', dogId: 'dog-1'),
          canonicalPlan(
            id: 'b',
            dogId: 'dog-1',
            validFrom: DateTime.utc(2026, 2, 1),
          ),
        ]),
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.hasUsableValue, isTrue);
      expect(r.value!.activePlan, isA<NutritionActivePlanIntegrityConflict>());
      expect(
        r.value!.mergeDiagnostics.any(
          (d) => d.code == 'multiple_active_nutrition_plans',
        ),
        isTrue,
      );
    });

    test('9. canonical error + legacy data → degraded', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _ErrCanonicalPlans(),
        legacyPlanReader: _MemLegacyPlans([
          legacyPlan(id: 'l', dogId: 'dog-1'),
        ]),
        legacyMealReaders: [
          _MemLegacyMeals('feeding_events', [
            meal(id: 'm1', dogId: 'dog-1', fedAt: t0),
          ]),
        ],
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isDegraded, isTrue);
      expect(r.hasUsableValue, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('10. canonical data + legacy error → degraded', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemCanonicalPlans([
          canonicalPlan(id: 'c', dogId: 'dog-1'),
        ]),
        canonicalMealReader: _MemCanonicalMeals([
          meal(id: 'm1', dogId: 'dog-1', fedAt: t0),
        ]),
        legacyMealReaders: [_ErrLegacyMeals('feeding_events')],
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isDegraded, isTrue);
      expect(r.value!.mergedMeals, isNotEmpty);
    });

    test('11. ambos error → error (nunca empty)', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _ErrCanonicalPlans(),
        canonicalMealReader: _ErrCanonicalMeals(),
        legacyPlanReader: _ErrLegacyPlans(),
        legacyMealReaders: [_ErrLegacyMeals('feeding_events')],
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.isError, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('14. dog A não vaza para dog B (stateless)', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalMealReader: _MemCanonicalMeals([
          meal(id: 'mA', dogId: 'dog-A', fedAt: t0),
          meal(id: 'mB', dogId: 'dog-B', fedAt: t0),
        ]),
      );
      final rA = await source.loadSnapshot('dog-A');
      final rB = await source.loadSnapshot('dog-B');
      expect(
        rA.value!.mergedMeals.every((m) => m.meal.dogId == 'dog-A'),
        isTrue,
      );
      expect(
        rB.value!.mergedMeals.every((m) => m.meal.dogId == 'dog-B'),
        isTrue,
      );
      expect(rA.value!.mergedMeals, hasLength(1));
      expect(rB.value!.mergedMeals, hasLength(1));
    });

    test('13. ordering fedAt DESC estável', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalMealReader: _MemCanonicalMeals([
          meal(id: 'a', dogId: 'dog-1', fedAt: t0),
          meal(id: 'b', dogId: 'dog-1', fedAt: t1),
        ]),
      );
      final r = await source.loadSnapshot('dog-1');
      expect(r.value!.mergedMeals.map((m) => m.id).toList(), ['b', 'a']);
    });
  });
}

// ── fakes ────────────────────────────────────────────────────────────────────

final class _MemCanonicalPlans implements NutritionCanonicalPlanReader {
  _MemCanonicalPlans(this.items);
  final List<NutritionPlan> items;
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      NutritionSourceBatch.available(items);
}

final class _MemLegacyPlans implements NutritionLegacyPlanReader {
  _MemLegacyPlans(this.items);
  final List<LegacyNutritionPlanView> items;
  @override
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(
    String dogId,
  ) async => NutritionSourceBatch.available(items);
}

final class _MemCanonicalMeals implements NutritionCanonicalMealReader {
  _MemCanonicalMeals(this.items);
  final List<MealLog> items;
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => NutritionSourceBatch.available(items);
}

final class _MemLegacyMeals implements NutritionLegacyMealReader {
  _MemLegacyMeals(this.collectionKey, this.items);
  @override
  final String collectionKey;
  final List<MealLog> items;
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => NutritionSourceBatch.available(items);
}

final class _ErrCanonicalPlans implements NutritionCanonicalPlanReader {
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      const NutritionSourceBatch.error(code: 'permission_denied');
}

final class _ErrCanonicalMeals implements NutritionCanonicalMealReader {
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => const NutritionSourceBatch.error(code: 'permission_denied');
}

final class _ErrLegacyPlans implements NutritionLegacyPlanReader {
  @override
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(
    String dogId,
  ) async => const NutritionSourceBatch.error(code: 'permission_denied');
}

final class _ErrLegacyMeals implements NutritionLegacyMealReader {
  _ErrLegacyMeals(this.collectionKey);
  @override
  final String collectionKey;
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => const NutritionSourceBatch.error(code: 'unavailable');
}
