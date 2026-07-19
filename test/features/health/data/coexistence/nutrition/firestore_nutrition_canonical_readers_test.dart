import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_legacy_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_firestore_error.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';

Map<String, dynamic> _recordedBy() => {
  'uid': 'u1',
  'name': 'Condutor',
  'internal_role': 'condutor',
};

Map<String, dynamic> _validPlan({
  String status = 'active',
  String foodType = 'Ração Premium',
  DateTime? validFrom,
}) {
  return {
    'food_type': foodType,
    'amount_grams_per_day': 400,
    'meals_per_day': 2,
    'meal_schedule': [
      {
        'id': 'slot-morning',
        'period': 'morning',
        'scheduled_time': '07:00',
        'target_grams': 200,
      },
      {
        'id': 'slot-evening',
        'period': 'evening',
        'scheduled_time': '18:00',
        'target_grams': 200,
      },
    ],
    'valid_from': Timestamp.fromDate(
      (validFrom ?? DateTime.utc(2026, 1, 1)).toUtc(),
    ),
    'timezone': 'America/Sao_Paulo',
    'status': status,
    'recorded_by': _recordedBy(),
    'schema_version': 1,
    'revision': 1,
  };
}

Map<String, dynamic> _validMeal({
  required DateTime fedAt,
  String period = 'morning',
  num offered = 150,
  String? planId,
  String? plannedMealId,
  String? mealOccurrenceId,
  String? legacySource,
  String? legacyId,
}) {
  return {
    'period': period,
    'offered_grams': offered,
    'acceptance': 'full',
    'fed_at': Timestamp.fromDate(fedAt.toUtc()),
    'recorded_by': _recordedBy(),
    'schema_version': 1,
    'revision': 1,
    'plan_id': ?planId,
    'planned_meal_id': ?plannedMealId,
    'meal_occurrence_id': ?mealOccurrenceId,
    'legacy_source': ?legacySource,
    'legacy_id': ?legacyId,
  };
}

Map<String, dynamic> _validSupplement({required DateTime at}) {
  return {
    'supplement_name': 'Ômega 3',
    'dose': 5,
    'unit': 'ml',
    'administered_at': Timestamp.fromDate(at.toUtc()),
    'recorded_by': _recordedBy(),
    'schema_version': 1,
    'revision': 1,
  };
}

void main() {
  test('legacy Firestore payload removes Timestamp SDK types recursively', () {
    final instant = DateTime.utc(2026, 7, 19, 12);
    final mapped = NutritionFirestoreError.asLegacyDomainMap({
      'fed_at': Timestamp.fromDate(instant),
      'nested': {
        'created_at': Timestamp.fromDate(instant),
        'items': [Timestamp.fromDate(instant)],
      },
    });

    expect(mapped['fed_at'], instant);
    final nested = mapped['nested']! as Map;
    expect(nested['created_at'], instant);
    expect((nested['items']! as List).single, instant);
  });

  test(
    'legacy meal with textual author remains visible as legacy read',
    () async {
      final legacyDb = FakeFirebaseFirestore();
      await legacyDb
          .collection('dogs')
          .doc('dog-a')
          .collection('feeding_events')
          .doc('legacy-1')
          .set({
            'amount_grams': 180,
            'period': 'morning',
            'fed_at': Timestamp.fromDate(DateTime.utc(2026, 7, 19, 10)),
            'fed_by': 'Condutor legado',
            'created_at': Timestamp.fromDate(DateTime.utc(2026, 7, 19, 10)),
          });

      final batch = await FirestoreNutritionLegacyMealReader(
        collectionKey: 'feeding_events',
        firestore: legacyDb,
      ).loadMeals('dog-a');

      expect(batch.availability, NutritionSourceAvailability.available);
      final meal = batch.items.single;
      expect(meal.offeredGrams, 180);
      expect(meal.consumedGrams, isNull);
      expect(meal.acceptance.value, MealAcceptance.unknown);
      expect(meal.legacySource, 'feeding_events');
      expect(meal.plannedMealId, isNull);
      expect(meal.mealOccurrenceId, isNull);
    },
  );

  late FakeFirebaseFirestore db;
  late FirestoreNutritionCanonicalPlanReader planReader;
  late FirestoreNutritionCanonicalMealReader mealReader;
  late FirestoreNutritionCanonicalSupplementLogReader supplementReader;

  setUp(() {
    db = FakeFirebaseFirestore();
    planReader = FirestoreNutritionCanonicalPlanReader(firestore: db);
    mealReader = FirestoreNutritionCanonicalMealReader(firestore: db);
    supplementReader = FirestoreNutritionCanonicalSupplementLogReader(
      firestore: db,
    );
  });

  group('FirestoreNutritionCanonicalPlanReader', () {
    test('lê planos canônicos e reutiliza parser 5C', () async {
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('nutrition_plans')
          .doc('plan-1')
          .set(_validPlan());

      final batch = await planReader.loadPlans('dog-a');
      expect(batch.availability, NutritionSourceAvailability.available);
      expect(batch.items, hasLength(1));
      expect(batch.items.single.id, 'plan-1');
      expect(batch.items.single.dogId, 'dog-a');
      expect(batch.items.single.status, NutritionPlanStatus.active);
      expect(batch.items.single.mealSchedule, hasLength(2));
    });

    test('empty quando zero documentos', () async {
      final batch = await planReader.loadPlans('dog-empty');
      expect(batch.availability, NutritionSourceAvailability.empty);
      expect(batch.items, isEmpty);
    });

    test(
      'malformado → integrity error (não empty / não “sem plano”)',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('nutrition_plans')
            .doc('bad')
            .set({
              'food_type': 'X',
              'amount_grams_per_day': 100,
              'meals_per_day': 1,
              'status': 'not_a_real_status',
              'valid_from': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
              'timezone': 'America/Sao_Paulo',
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });

        final batch = await planReader.loadPlans('dog-a');
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'invalid_status');
        expect(batch.items, isEmpty);
      },
    );

    test(
      'múltiplos active retornados sem limit(1) — integridade no merge',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('nutrition_plans')
            .doc('p1')
            .set(_validPlan(validFrom: DateTime.utc(2026, 1, 1)));
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('nutrition_plans')
            .doc('p2')
            .set(_validPlan(validFrom: DateTime.utc(2026, 2, 1)));

        final batch = await planReader.loadPlans('dog-a');
        expect(batch.availability, NutritionSourceAvailability.available);
        expect(
          batch.items.where((p) => p.status == NutritionPlanStatus.active),
          hasLength(2),
        );

        final active = NutritionMergePolicy.resolveActivePlan(
          canonical: batch.items,
          legacy: const [],
        );
        expect(active, isA<NutritionActivePlanIntegrityConflict>());
        final conflict = active! as NutritionActivePlanIntegrityConflict;
        expect(conflict.activeCount, 2);
        expect(conflict.activePlanIds, containsAll(['p1', 'p2']));
      },
    );
  });

  group('FirestoreNutritionCanonicalMealReader', () {
    test(
      'documento canônico em meal_logs é lido com campos preservados',
      () async {
        final fedAt = DateTime.utc(2026, 7, 14, 12);
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('meal-1')
            .set(
              _validMeal(
                fedAt: fedAt,
                planId: 'plan-1',
                plannedMealId: 'slot-morning',
                mealOccurrenceId: 'occ-1',
                legacySource: 'feeding_events',
                legacyId: 'legacy-fe-1',
              ),
            );

        final batch = await mealReader.loadMeals('dog-a');
        expect(batch.availability, NutritionSourceAvailability.available);
        final meal = batch.items.single;
        expect(meal.id, 'meal-1');
        expect(meal.offeredGrams, 150);
        expect(meal.planId, 'plan-1');
        expect(meal.plannedMealId, 'slot-morning');
        expect(meal.legacySource, 'feeding_events');
        expect(meal.legacyId, 'legacy-fe-1');
        expect(meal.fedAt.toUtc(), fedAt);
      },
    );

    test('malformado → error de integridade', () async {
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('meal_logs')
          .doc('bad')
          .set({
            'period': 'morning',
            // offered_grams ausente
            'acceptance': 'full',
            'fed_at': Timestamp.fromDate(DateTime.utc(2026, 7, 14)),
            'recorded_by': _recordedBy(),
            'schema_version': 1,
            'revision': 1,
          });

      final batch = await mealReader.loadMeals('dog-a');
      expect(batch.availability, NutritionSourceAvailability.error);
      expect(batch.code, 'missing_offered_grams');
    });

    test(
      'G4-QUERY-INTEGRITY: MealLog sem fed_at → integrity (não invisível)',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('broken-no-fed-at')
            .set({
              'period': 'morning',
              'offered_grams': 100,
              'acceptance': 'full',
              // fed_at ausente — orderBy fed_at ocultaria no Firestore real
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('valid')
            .set(_validMeal(fedAt: DateTime.utc(2026, 7, 14, 12)));

        final batch = await mealReader.loadMeals('dog-a');
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'missing_fed_at');
        expect(batch.items, isEmpty);
      },
    );

    test(
      'range em memória após parse; malformed no range ainda falha',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('in-range')
            .set(_validMeal(fedAt: DateTime.utc(2026, 7, 15, 12)));
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('out-range')
            .set(_validMeal(fedAt: DateTime.utc(2026, 1, 1, 12)));

        final ok = await mealReader.loadMeals(
          'dog-a',
          from: DateTime.utc(2026, 7, 1),
          to: DateTime.utc(2026, 8, 1),
        );
        expect(ok.availability, NutritionSourceAvailability.available);
        expect(ok.items.map((m) => m.id), ['in-range']);

        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('broken')
            .set({
              'period': 'morning',
              'offered_grams': 50,
              'acceptance': 'full',
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });

        final bad = await mealReader.loadMeals(
          'dog-a',
          from: DateTime.utc(2026, 7, 1),
          to: DateTime.utc(2026, 8, 1),
        );
        // Collection scan: broken sem fed_at é visto antes do filtro de range.
        expect(bad.availability, NutritionSourceAvailability.error);
        expect(bad.code, 'missing_fed_at');
      },
    );
  });

  group('FirestoreNutritionCanonicalSupplementLogReader', () {
    test('supplement_logs separado de legacy regimen', () async {
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('supplement_logs')
          .doc('slog-1')
          .set(_validSupplement(at: DateTime.utc(2026, 7, 14, 9)));

      // Seed legado no mesmo dog — reader canônico não mistura.
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('nutrition_supplements')
          .doc('reg-1')
          .set({'name': 'Vitamina', 'dose': '1 cp'});

      final batch = await supplementReader.loadSupplementLogs('dog-a');
      expect(batch.availability, NutritionSourceAvailability.available);
      expect(batch.items, hasLength(1));
      expect(batch.items.single.id, 'slog-1');
      expect(batch.items.single.supplementName, 'Ômega 3');
    });

    test(
      'G4-QUERY-INTEGRITY: SupplementLog sem administered_at → integrity',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('supplement_logs')
            .doc('broken-no-admin-at')
            .set({
              'supplement_name': 'Ômega 3',
              'dose': 5,
              'unit': 'ml',
              // administered_at ausente
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });

        final batch = await supplementReader.loadSupplementLogs('dog-a');
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'missing_administered_at');
      },
    );
  });

  group('Coexistence + controller visibility', () {
    test(
      'meal canônico → coexistence inclui → read controller recebe',
      () async {
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('nutrition_plans')
            .doc('plan-1')
            .set(_validPlan());
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('meal-1')
            .set(_validMeal(fedAt: DateTime.utc(2026, 7, 14, 12)));
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('supplement_logs')
            .doc('slog-1')
            .set(_validSupplement(at: DateTime.utc(2026, 7, 14, 9)));

        final source = CoexistenceNutritionReadSourceFactory.forFirestore(
          firestore: db,
        );
        final result = await source.loadSnapshot('dog-a');
        expect(result.isData || result.isDegraded, isTrue);
        final snap = result.value!;
        expect(snap.canonicalMeals.map((m) => m.id), contains('meal-1'));
        expect(
          snap.canonicalSupplementLogs.map((s) => s.id),
          contains('slog-1'),
        );
        expect(snap.legacySupplementRegimens, isEmpty);
        expect(snap.activePlan, isA<NutritionActiveCanonicalPlan>());

        final controller = HealthNutritionReadController(source: source);
        await controller.selectDog('dog-a');
        expect(controller.activeDogId, 'dog-a');
        expect(controller.snapshotResult.hasUsableValue, isTrue);
        expect(
          controller.snapshotOrNull!.canonicalMeals.map((m) => m.id),
          contains('meal-1'),
        );
        controller.dispose();
      },
    );

    test('múltiplos active → integrity conflict no snapshot', () async {
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('nutrition_plans')
          .doc('p1')
          .set(_validPlan(validFrom: DateTime.utc(2026, 1, 1)));
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('nutrition_plans')
          .doc('p2')
          .set(_validPlan(validFrom: DateTime.utc(2026, 3, 1)));

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: planReader,
      );
      final result = await source.loadSnapshot('dog-a');
      expect(result.hasUsableValue, isTrue);
      expect(
        result.value!.activePlan,
        isA<NutritionActivePlanIntegrityConflict>(),
      );
      expect(
        result.value!.mergeDiagnostics.any(
          (d) => d.code == 'multiple_active_nutrition_plans',
        ),
        isTrue,
      );
    });

    test('canonical malformado + legacy ok → degraded', () async {
      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('nutrition_plans')
          .doc('bad')
          .set({
            'food_type': 'X',
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'status': 'broken',
            'valid_from': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
            'timezone': 'America/Sao_Paulo',
            'recorded_by': _recordedBy(),
            'schema_version': 1,
            'revision': 1,
          });

      await db
          .collection('dogs')
          .doc('dog-a')
          .collection('feeding_events')
          .doc('fe-1')
          .set({
            'period': 'manha',
            'amount_grams': 120,
            'fed_at': Timestamp.fromDate(DateTime.utc(2026, 7, 14, 8)),
            'recorded_by': _recordedBy(),
          });

      final source = CoexistenceNutritionReadSourceFactory.forFirestore(
        firestore: db,
      );
      final result = await source.loadSnapshot('dog-a');
      expect(result.isDegraded, isTrue);
      expect(result.value, isNotNull);
      expect(result.value!.canonicalPlans, isEmpty);
      expect(result.value!.mergedMeals, isNotEmpty);
      expect(
        result.value!.planSources.any(
          (s) => s.origin == NutritionDataOrigin.canonical && s.isFailure,
        ),
        isTrue,
      );
    });

    test(
      'canonical ok + legacy meal failure isolado → degraded com canônico',
      () async {
        // Force legacy meal reader failure via unmapped docs only for feedings
        // while canonical works. Use a failing custom reader.
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: planReader,
          canonicalMealReader: mealReader,
          legacyMealReaders: [_AlwaysFailLegacyMealReader()],
        );

        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('nutrition_plans')
            .doc('plan-1')
            .set(_validPlan());
        await db
            .collection('dogs')
            .doc('dog-a')
            .collection('meal_logs')
            .doc('meal-1')
            .set(_validMeal(fedAt: DateTime.utc(2026, 7, 14, 12)));

        final result = await source.loadSnapshot('dog-a');
        expect(result.isDegraded, isTrue);
        expect(result.value!.canonicalMeals, hasLength(1));
        expect(result.value!.activePlan, isA<NutritionActiveCanonicalPlan>());
      },
    );

    test('ambas fontes falham → error (nunca empty)', () async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _AlwaysFailPlanReader(),
        legacyPlanReader: _AlwaysFailLegacyPlanReader(),
        canonicalMealReader: _AlwaysFailMealReader(),
        legacyMealReaders: [_AlwaysFailLegacyMealReader()],
      );

      final result = await source.loadSnapshot('dog-x');
      expect(result.isError || result.isOffline, isTrue);
      expect(result.isEmpty, isFalse);
    });
  });
}

final class _AlwaysFailPlanReader implements NutritionCanonicalPlanReader {
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    return const NutritionSourceBatch.error(
      code: 'forced_canonical_fail',
      message: 'fail',
    );
  }
}

final class _AlwaysFailLegacyPlanReader implements NutritionLegacyPlanReader {
  @override
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(
    String dogId,
  ) async {
    return const NutritionSourceBatch.error(
      code: 'forced_legacy_plan_fail',
      message: 'fail',
    );
  }
}

final class _AlwaysFailMealReader implements NutritionCanonicalMealReader {
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return const NutritionSourceBatch.error(
      code: 'forced_canonical_meal_fail',
      message: 'fail',
    );
  }
}

final class _AlwaysFailLegacyMealReader implements NutritionLegacyMealReader {
  @override
  String get collectionKey => 'feeding_events';

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return const NutritionSourceBatch.error(
      code: 'forced_legacy_meal_fail',
      message: 'fail',
    );
  }
}
