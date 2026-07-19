import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_document_parser.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';

/// Consome fixtures JSON exportadas do Firestore Emulator real
/// (`temp/g4_nutrition_emulator_fixtures.json` via orchestrator).
///
/// Exercita parsers 5C + a mesma semântica do reader pós-scan
/// (fail-closed em malformados) **sem** plugins Firebase no harness unitário.
///
/// Ativado apenas com:
/// ```text
/// HEALTH_NUTRITION_READER_EMULATOR=1
/// G4_NUTRITION_EMU_FIXTURE=<path>
/// ```
void main() {
  final enabled =
      Platform.environment['HEALTH_NUTRITION_READER_EMULATOR'] == '1';
  final fixturePath = Platform.environment['G4_NUTRITION_EMU_FIXTURE'];

  group('Gate4 Emulator fixtures → Dart parsers / integrity', () {
    if (!enabled || fixturePath == null || fixturePath.isEmpty) {
      test(
        'skipped fora do orquestrador Emulator',
        () {},
        skip:
            'Rode via npm run test:health-nutrition-readers '
            '(exporta fixtures do Emulator)',
      );
      return;
    }

    late Map<String, dynamic> root;

    setUpAll(() {
      final file = File(fixturePath);
      expect(file.existsSync(), isTrue, reason: 'fixture missing: $fixturePath');
      root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    List<MapEntry<String, Map<String, Object?>>> docs(
      String dogId,
      String collection,
    ) {
      final dogs = root['dogs'] as Map<String, dynamic>;
      final dog = dogs[dogId] as Map<String, dynamic>?;
      expect(dog, isNotNull, reason: 'dog $dogId missing in fixture');
      final list = dog![collection] as List<dynamic>? ?? const [];
      return [
        for (final item in list)
          MapEntry(
            (item as Map<String, dynamic>)['id'] as String,
            Map<String, Object?>.from(
              (item['data'] as Map).map(
                (k, v) => MapEntry(k as String, v as Object?),
              ),
            ),
          ),
      ];
    }

    /// Espelha o loop fail-closed do reader canônico (pós collection.get).
    NutritionSourceBatch<T> parseAllFailClosed<T>({
      required List<MapEntry<String, Map<String, Object?>>> documents,
      required String dogId,
      required T Function(String id, String dogId, Map<String, Object?> data)
      parse,
    }) {
      if (documents.isEmpty) {
        return const NutritionSourceBatch.empty();
      }
      final items = <T>[];
      for (final e in documents) {
        try {
          items.add(parse(e.key, dogId, e.value));
        } on HealthDomainException catch (ex) {
          return NutritionSourceBatch.error(
            code: ex.code,
            message: ex.message,
          );
        }
      }
      return NutritionSourceBatch.available(items);
    }

    test('MealLog sem fed_at (Emulator) → missing_fed_at', () {
      const dogId = 'dog-nutrition-reader-meal-broken';
      final batch = parseAllFailClosed<MealLog>(
        documents: docs(dogId, 'meal_logs'),
        dogId: dogId,
        parse: (id, d, data) =>
            MealLogDocumentParser.parse(id: id, dogId: d, data: data),
      );
      expect(batch.availability, NutritionSourceAvailability.error);
      expect(batch.code, 'missing_fed_at');
    });

    test(
      'SupplementLog sem administered_at (Emulator) → missing_administered_at',
      () {
        const dogId = 'dog-nutrition-reader-supp-broken';
        final batch = parseAllFailClosed<SupplementLog>(
          documents: docs(dogId, 'supplement_logs'),
          dogId: dogId,
          parse: (id, d, data) =>
              SupplementLogDocumentParser.parse(id: id, dogId: d, data: data),
        );
        expect(batch.availability, NutritionSourceAvailability.error);
        expect(batch.code, 'missing_administered_at');
      },
    );

    test('plan malformed (Emulator) → integrity error', () {
      const dogId = 'dog-nutrition-reader-plan-broken';
      final batch = parseAllFailClosed<NutritionPlan>(
        documents: docs(dogId, 'nutrition_plans'),
        dogId: dogId,
        parse: (id, d, data) =>
            NutritionPlanDocumentParser.parse(id: id, dogId: d, data: data),
      );
      expect(batch.availability, NutritionSourceAvailability.error);
    });

    test('multiple active plans (Emulator export) → integrity conflict', () {
      const dogId = 'dog-nutrition-reader-multi';
      final batch = parseAllFailClosed<NutritionPlan>(
        documents: docs(dogId, 'nutrition_plans'),
        dogId: dogId,
        parse: (id, d, data) =>
            NutritionPlanDocumentParser.parse(id: id, dogId: d, data: data),
      );
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
    });

    test('valid plan/meal/supplement (Emulator export) parse OK', () {
      const dogId = 'dog-nutrition-reader-valid';
      final plans = parseAllFailClosed<NutritionPlan>(
        documents: docs(dogId, 'nutrition_plans'),
        dogId: dogId,
        parse: (id, d, data) =>
            NutritionPlanDocumentParser.parse(id: id, dogId: d, data: data),
      );
      final meals = parseAllFailClosed<MealLog>(
        documents: docs(dogId, 'meal_logs'),
        dogId: dogId,
        parse: (id, d, data) =>
            MealLogDocumentParser.parse(id: id, dogId: d, data: data),
      );
      final supps = parseAllFailClosed<SupplementLog>(
        documents: docs(dogId, 'supplement_logs'),
        dogId: dogId,
        parse: (id, d, data) =>
            SupplementLogDocumentParser.parse(id: id, dogId: d, data: data),
      );
      expect(plans.availability, NutritionSourceAvailability.available);
      expect(plans.items.map((p) => p.id), contains('plan-valid'));
      expect(meals.availability, NutritionSourceAvailability.available);
      expect(meals.items.map((m) => m.id), contains('meal-valid'));
      expect(supps.availability, NutritionSourceAvailability.available);
      expect(supps.items.map((s) => s.id), contains('supp-valid'));
    });

    test(
      'meal broken + legacy feeding_events (Emulator) → canonical fail, legacy ok',
      () {
        const dogId = 'dog-nutrition-reader-meal-legacy';
        final canonical = parseAllFailClosed<MealLog>(
          documents: docs(dogId, 'meal_logs'),
          dogId: dogId,
          parse: (id, d, data) =>
              MealLogDocumentParser.parse(id: id, dogId: d, data: data),
        );
        expect(canonical.availability, NutritionSourceAvailability.error);
        expect(canonical.code, 'missing_fed_at');

        final legacyDocs = docs(dogId, 'feeding_events');
        expect(legacyDocs, isNotEmpty);
        final adapter = const LegacyNutritionAdapter();
        final legacyMeals = <MealLog>[];
        for (final e in legacyDocs) {
          final result = adapter.parse(
            sourceId: e.key,
            dogId: dogId,
            data: e.value,
          );
          final v = result.value;
          if (v is MealLog) legacyMeals.add(v);
        }
        expect(legacyMeals, isNotEmpty);
      },
    );

    test('paths canônicos documentados', () {
      expect(NutritionCanonicalPaths.mealLogs, 'meal_logs');
      expect(NutritionCanonicalPaths.supplementLogs, 'supplement_logs');
      expect(NutritionCanonicalPaths.plans, 'nutrition_plans');
    });
  });
}
