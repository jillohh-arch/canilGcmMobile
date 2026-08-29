// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE RAW CANONICAL FIRST-PAGE MERGER TESTS — 25 tests.

import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_id_deriver.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared fixtures
// ─────────────────────────────────────────────────────────────────────────────

final class _TestRecordedBy {
  static RecordedBy get value => RecordedBy(
    uid: 'uid-test',
    name: 'Test User',
    internalRole: 'veterinary',
  );
}

/// Builds a minimal MealLog for testing.
MealLog _makeMeal({
  required String id,
  required String dogId,
  required DateTime fedAt,
  String? legacySource,
  String? legacyId,
  String? source,
}) {
  return MealLog(
    id: id,
    dogId: dogId,
    period: MealPeriodWire.parseCanonical('morning'),
    offeredGrams: 200.0,
    acceptance: MealAcceptanceWire.parse('full'),
    fedAt: fedAt,
    recordedBy: _TestRecordedBy.value,
    schemaVersion: 1,
    revision: 1,
    legacySource: legacySource,
    legacyId: legacyId,
    source: source,
  );
}

/// Builds a minimal SupplementLog for testing.
SupplementLog _makeSupplement({
  required String id,
  required String dogId,
  required DateTime administeredAt,
  String? legacySource,
  String? legacyId,
}) {
  return SupplementLog(
    id: id,
    dogId: dogId,
    supplementName: 'Vitamin D',
    dose: 10.0,
    unit: SupplementDoseUnit.mg,
    administeredAt: administeredAt,
    recordedBy: _TestRecordedBy.value,
    schemaVersion: 1,
    revision: 1,
    legacySource: legacySource,
    legacyId: legacyId,
  );
}

/// Builds a first-page query for a dog.
HealthTimelineQuery _makeQuery({
  required String dogId,
  DateTime? start,
  DateTime? end,
  int pageSize = 20,
}) {
  return HealthTimelineQuery(
    dogId: dogId,
    period: HealthTimelinePeriod(start: start, end: end),
    pageSize: pageSize,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('mergeRawCanonicalNutritionFirstPage', () {
    // ─── Test 1: maps a meal to the canonical comparable locator and derived id
    test('maps a meal to the canonical comparable locator and derived id', () {
      final meal = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 8, 0),
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [meal],
        supplements: [],
      );

      expect(result.entries.length, equals(1));

      final entry = result.entries.first;
      expect(entry.dogId, equals('dog123'));
      expect(
        entry.sourceCollection,
        equals(CanonicalHealthTimelineSourceCollection.mealLogs),
      );
      expect(entry.sourceId, equals('ml_001'));
      expect(entry.occurredAt, equals(DateTime(2024, 3, 15, 8, 0)));
      expect(entry.derivedTimelineId, startsWith('tl1_'));
      expect(entry.locatorCollection, equals('meal_logs'));
      expect(entry.locatorKey, equals('meal_logs:ml_001'));

      // Legacy fields must NOT appear in the result
      expect(entry.sourceId, isNot(equals('legacy_meal_001')));
    });

    // ─── Test 2: maps a supplement to the canonical comparable locator and derived id
    test(
      'maps a supplement to the canonical comparable locator and derived id',
      () {
        final supplement = _makeSupplement(
          id: 'sl_001',
          dogId: 'dog123',
          administeredAt: DateTime(2024, 3, 15, 9, 0),
        );

        final result = mergeRawCanonicalNutritionFirstPage(
          query: _makeQuery(dogId: 'dog123'),
          meals: [],
          supplements: [supplement],
        );

        expect(result.entries.length, equals(1));

        final entry = result.entries.first;
        expect(entry.dogId, equals('dog123'));
        expect(
          entry.sourceCollection,
          equals(CanonicalHealthTimelineSourceCollection.supplementLogs),
        );
        expect(entry.sourceId, equals('sl_001'));
        expect(entry.occurredAt, equals(DateTime(2024, 3, 15, 9, 0)));
        expect(entry.derivedTimelineId, startsWith('tl1_'));
        expect(entry.locatorCollection, equals('supplement_logs'));
        expect(entry.locatorKey, equals('supplement_logs:sl_001'));

        // Legacy fields must NOT appear in the result
        expect(entry.sourceId, isNot(equals('legacy_supplement_001')));
      },
    );

    // ─── Test 3: orders meal entries by occurred at descending
    test('orders meal entries by occurred at descending', () {
      final meal1 = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 8, 0), // earlier
      );
      final meal2 = _makeMeal(
        id: 'ml_002',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 12, 0), // later
      );
      final meal3 = _makeMeal(
        id: 'ml_003',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 10, 0), // middle
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [meal1, meal2, meal3],
        supplements: [],
      );

      expect(result.entries.length, equals(3));
      expect(result.entries[0].sourceId, equals('ml_002')); // 12:00
      expect(result.entries[1].sourceId, equals('ml_003')); // 10:00
      expect(result.entries[2].sourceId, equals('ml_001')); // 08:00
    });

    // ─── Test 4: orders supplement entries by occurred at descending
    test('orders supplement entries by occurred at descending', () {
      final sup1 = _makeSupplement(
        id: 'sl_001',
        dogId: 'dog123',
        administeredAt: DateTime(2024, 3, 15, 8, 0), // earlier
      );
      final sup2 = _makeSupplement(
        id: 'sl_002',
        dogId: 'dog123',
        administeredAt: DateTime(2024, 3, 15, 12, 0), // later
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [],
        supplements: [sup1, sup2],
      );

      expect(result.entries.length, equals(2));
      expect(result.entries[0].sourceId, equals('sl_002')); // 12:00
      expect(result.entries[1].sourceId, equals('sl_001')); // 08:00
    });

    // ─── Test 5: merges meal and supplement entries into one descending sequence
    test('merges meal and supplement entries into one descending sequence', () {
      final meal = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 8, 0),
      );
      final supplement = _makeSupplement(
        id: 'sl_001',
        dogId: 'dog123',
        administeredAt: DateTime(2024, 3, 15, 12, 0), // later
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [meal],
        supplements: [supplement],
      );

      expect(result.entries.length, equals(2));
      expect(result.entries[0].sourceId, equals('sl_001')); // later
      expect(
        result.entries[0].sourceCollection,
        equals(CanonicalHealthTimelineSourceCollection.supplementLogs),
      );
      expect(result.entries[1].sourceId, equals('ml_001')); // earlier
      expect(
        result.entries[1].sourceCollection,
        equals(CanonicalHealthTimelineSourceCollection.mealLogs),
      );
    });

    // ─── Test 6: uses derived timeline id descending when timestamps are equal
    test('uses derived timeline id descending when timestamps are equal', () {
      final sameTime = DateTime(2024, 3, 15, 12, 0);
      final meal = _makeMeal(
        id: 'ml_zzz', // lexicographically larger
        dogId: 'dog123',
        fedAt: sameTime,
      );
      final supplement = _makeSupplement(
        id: 'sl_aaa', // lexicographically smaller
        dogId: 'dog123',
        administeredAt: sameTime,
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [meal],
        supplements: [supplement],
      );

      expect(result.entries.length, equals(2));
      // tie-break: derived timeline ID DESC
      // meal derived ID ends with ...zzz
      // supplement derived ID ends with ...aaa
      // meal should come first (zzz > aaa lexicographically)
      expect(
        result.entries[0].derivedTimelineId.compareTo(
          result.entries[1].derivedTimelineId,
        ),
        greaterThan(0),
      );
    });

    // ─── Test 7: keeps the same raw source id distinct across collections
    test('keeps the same raw source id distinct across collections', () {
      // Same document ID in different collections produces different derived IDs
      final meal = _makeMeal(
        id: 'same_id',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 8, 0),
      );
      final supplement = _makeSupplement(
        id: 'same_id',
        dogId: 'dog123',
        administeredAt: DateTime(2024, 3, 15, 8, 0),
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'),
        meals: [meal],
        supplements: [supplement],
      );

      expect(result.entries.length, equals(2));

      // Derived IDs must be different
      expect(
        result.entries[0].derivedTimelineId,
        isNot(equals(result.entries[1].derivedTimelineId)),
      );

      // Locator keys must be different
      expect(
        result.entries[0].locatorKey,
        isNot(equals(result.entries[1].locatorKey)),
      );
    });

    // ─── Test 8: includes an entry exactly at the period start
    test('includes an entry exactly at the period start', () {
      final start = DateTime(2024, 3, 15, 8, 0);
      final meal = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: start, // exactly at start
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123', start: start),
        meals: [meal],
        supplements: [],
      );

      expect(result.entries.length, equals(1));
      expect(result.entries.first.sourceId, equals('ml_001'));
    });

    // ─── Test 9: includes an entry exactly at the period end
    test('includes an entry exactly at the period end', () {
      final end = DateTime(2024, 3, 15, 23, 59, 59);
      final supplement = _makeSupplement(
        id: 'sl_001',
        dogId: 'dog123',
        administeredAt: end, // exactly at end (inclusive)
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123', end: end),
        meals: [],
        supplements: [supplement],
      );

      expect(result.entries.length, equals(1));
      expect(result.entries.first.sourceId, equals('sl_001'));
    });

    // ─── Test 10: excludes entries before the period start
    test('excludes entries before the period start', () {
      final start = DateTime(2024, 3, 16, 0, 0);
      final meal = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 23, 0), // before start
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123', start: start),
        meals: [meal],
        supplements: [],
      );

      expect(result.entries.length, equals(0));
    });

    // ─── Test 11: excludes entries after the period end
    test('excludes entries after the period end', () {
      final end = DateTime(2024, 3, 15, 12, 0);
      final supplement = _makeSupplement(
        id: 'sl_001',
        dogId: 'dog123',
        administeredAt: DateTime(2024, 3, 15, 14, 0), // after end
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123', end: end),
        meals: [],
        supplements: [supplement],
      );

      expect(result.entries.length, equals(0));
    });

    // ─── Test 12: accepts an unbounded period
    test('accepts an unbounded period', () {
      final meal = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2020, 1, 1), // very old
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123'), // no period
        meals: [meal],
        supplements: [],
      );

      expect(result.entries.length, equals(1));
    });

    // ─── Test 13: returns has more false when eligible count equals page size
    test('returns has more false when eligible count equals page size', () {
      final meals = List.generate(
        5,
        (i) => _makeMeal(
          id: 'ml_$i',
          dogId: 'dog123',
          fedAt: DateTime(2024, 3, 15, i),
        ),
      );

      final result = mergeRawCanonicalNutritionFirstPage(
        query: _makeQuery(dogId: 'dog123', pageSize: 5),
        meals: meals,
        supplements: [],
      );

      expect(result.entries.length, equals(5));
      expect(result.hasMore, isFalse);
    });

    // ─── Test 14: returns only page size entries and has more true when one extra exists
    test(
      'returns only page size entries and has more true when one extra exists',
      () {
        final meals = List.generate(
          6,
          (i) => _makeMeal(
            id: 'ml_$i',
            dogId: 'dog123',
            fedAt: DateTime(2024, 3, 15, i),
          ),
        );

        final result = mergeRawCanonicalNutritionFirstPage(
          query: _makeQuery(dogId: 'dog123', pageSize: 5),
          meals: meals,
          supplements: [],
        );

        expect(result.entries.length, equals(5));
        expect(result.hasMore, isTrue);
        // First entry should be the most recent (15, 5)
        expect(result.entries.first.sourceId, equals('ml_5'));
      },
    );

    // ─── Test 15: rejects a query with a cursor
    test('rejects a query with a cursor', () {
      final queryWithCursor = HealthTimelineQuery(
        dogId: 'dog123',
        cursor: HealthTimelineCursor('some-cursor'),
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: queryWithCursor,
          meals: [],
          supplements: [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ─── Test 16: rejects unsupported type case or professional filters
    test('rejects unsupported type case or professional filters', () {
      // Type filter
      final queryWithTypes = HealthTimelineQuery(
        dogId: 'dog123',
        types: {HealthTimelineType.meal},
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: queryWithTypes,
          meals: [],
          supplements: [],
        ),
        throwsA(isA<ArgumentError>()),
      );

      // CaseId filter
      final queryWithCaseId = HealthTimelineQuery(
        dogId: 'dog123',
        caseId: 'case_abc',
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: queryWithCaseId,
          meals: [],
          supplements: [],
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Professional filter
      final queryWithProfessional = HealthTimelineQuery(
        dogId: 'dog123',
        professional: HealthTimelineProfessionalFilter(name: 'Dr. Smith'),
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: queryWithProfessional,
          meals: [],
          supplements: [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ─── Test 17: rejects a meal whose dog id differs from the query
    test('rejects a meal whose dog id differs from the query', () {
      final mealWrongDog = _makeMeal(
        id: 'ml_001',
        dogId: 'dog456', // different dog
        fedAt: DateTime(2024, 3, 15, 8, 0),
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: _makeQuery(dogId: 'dog123'),
          meals: [mealWrongDog],
          supplements: [],
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ─── Test 18: rejects a supplement whose dog id differs from the query
    test('rejects a supplement whose dog id differs from the query', () {
      final supplementWrongDog = _makeSupplement(
        id: 'sl_001',
        dogId: 'dog789', // different dog
        administeredAt: DateTime(2024, 3, 15, 9, 0),
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: _makeQuery(dogId: 'dog123'),
          meals: [],
          supplements: [supplementWrongDog],
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ─── Test 19: rejects a duplicate canonical locator
    test('rejects a duplicate canonical locator', () {
      // Same meal logged twice (same collection + same document ID)
      final meal1 = _makeMeal(
        id: 'ml_001',
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 8, 0),
      );
      final meal2 = _makeMeal(
        id: 'ml_001', // same ID
        dogId: 'dog123',
        fedAt: DateTime(2024, 3, 15, 10, 0), // different time
      );

      expect(
        () => mergeRawCanonicalNutritionFirstPage(
          query: _makeQuery(dogId: 'dog123'),
          meals: [meal1, meal2],
          supplements: [],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('duplicate_raw_canonical_entry'),
          ),
        ),
      );
    });

    // ─── Test 20: is deterministic across repeated merges
    test('is deterministic across repeated merges', () {
      final meals = [
        _makeMeal(
          id: 'ml_001',
          dogId: 'dog123',
          fedAt: DateTime(2024, 3, 15, 8, 0),
        ),
        _makeMeal(
          id: 'ml_002',
          dogId: 'dog123',
          fedAt: DateTime(2024, 3, 15, 10, 0),
        ),
      ];

      final supplements = [
        _makeSupplement(
          id: 'sl_001',
          dogId: 'dog123',
          administeredAt: DateTime(2024, 3, 15, 9, 0),
        ),
      ];

      final query = _makeQuery(dogId: 'dog123');

      // Merge multiple times
      final result1 = mergeRawCanonicalNutritionFirstPage(
        query: query,
        meals: meals,
        supplements: supplements,
      );

      final result2 = mergeRawCanonicalNutritionFirstPage(
        query: query,
        meals: meals,
        supplements: supplements,
      );

      // Results must be identical
      expect(result1.hasMore, equals(result2.hasMore));
      expect(result1.entries.length, equals(result2.entries.length));

      for (var i = 0; i < result1.entries.length; i++) {
        expect(
          result1.entries[i].derivedTimelineId,
          equals(result2.entries[i].derivedTimelineId),
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Shared query eligibility validator tests — 5 new tests (21–25)
  // ─────────────────────────────────────────────────────────────────────────────

  group('validateRawCanonicalNutritionFirstPageQuery', () {
    test('accepts an eligible first-page query', () {
      // An eligible first-page query has no cursor, types, caseId, or professional
      final eligibleQuery = _makeQuery(dogId: 'dog123');

      // Must not throw
      expect(
        () => validateRawCanonicalNutritionFirstPageQuery(eligibleQuery),
        returnsNormally,
      );
    });

    test('rejects a cursor', () {
      final queryWithCursor = HealthTimelineQuery(
        dogId: 'dog123',
        cursor: HealthTimelineCursor('some-cursor'),
      );

      expect(
        () => validateRawCanonicalNutritionFirstPageQuery(queryWithCursor),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects type filters', () {
      final queryWithTypes = HealthTimelineQuery(
        dogId: 'dog123',
        types: {HealthTimelineType.meal},
      );

      expect(
        () => validateRawCanonicalNutritionFirstPageQuery(queryWithTypes),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a case filter', () {
      final queryWithCaseId = HealthTimelineQuery(
        dogId: 'dog123',
        caseId: 'case_abc',
      );

      expect(
        () => validateRawCanonicalNutritionFirstPageQuery(queryWithCaseId),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a professional filter', () {
      final queryWithProfessional = HealthTimelineQuery(
        dogId: 'dog123',
        professional: HealthTimelineProfessionalFilter(name: 'Dr. Smith'),
      );

      expect(
        () =>
            validateRawCanonicalNutritionFirstPageQuery(queryWithProfessional),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
