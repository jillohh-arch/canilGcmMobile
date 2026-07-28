// Copyright 2024 GCM Health. All rights reserved.
//
// READER-BACKED RAW CANONICAL NUTRITION FIRST-PAGE SOURCE TESTS — 37 tests.
//
// Pure Dart. NO Firestore, NO FakeFirebaseFirestore, NO sleep, NO real Timer,
// NO Future.delayed, NO timeout, NO Stopwatch, NO network, NO HealthTimelinePage
// / HealthTimelineSource / sampler / observer / bridge. Parallelism proven with
// Completer. Expected reader unavailability is a typed Failure, never a throw.

import 'dart:async';

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fakes — record calls and return a configured batch, a Future error, a
// synchronous throw, or a pending Completer future. They NEVER apply from/to
// filtering (period is the merger's authority) and never touch Firestore.
// `syncThrow` throws directly in the method body BEFORE returning a Future —
// distinct from `error`, which completes a Future with an exception.
// ─────────────────────────────────────────────────────────────────────────────

final class _FakeMealReader implements NutritionCanonicalMealReader {
  _FakeMealReader({this.result, this.error, this.syncThrow, this.completer});

  final NutritionSourceBatch<MealLog>? result;
  final Object? error;
  final Object? syncThrow;
  final Completer<NutritionSourceBatch<MealLog>>? completer;

  int callCount = 0;
  final List<String> dogIds = <String>[];
  final List<DateTime?> froms = <DateTime?>[];
  final List<DateTime?> tos = <DateTime?>[];

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) {
    callCount++;
    dogIds.add(dogId);
    froms.add(from);
    tos.add(to);
    final s = syncThrow;
    if (s != null) throw s;
    final c = completer;
    if (c != null) return c.future;
    final e = error;
    if (e != null) return Future<NutritionSourceBatch<MealLog>>.error(e);
    return Future<NutritionSourceBatch<MealLog>>.value(result);
  }
}

final class _FakeSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  _FakeSupplementReader({
    this.result,
    this.error,
    this.syncThrow,
    this.completer,
  });

  final NutritionSourceBatch<SupplementLog>? result;
  final Object? error;
  final Object? syncThrow;
  final Completer<NutritionSourceBatch<SupplementLog>>? completer;

  int callCount = 0;
  final List<String> dogIds = <String>[];

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(String dogId) {
    callCount++;
    dogIds.add(dogId);
    final s = syncThrow;
    if (s != null) throw s;
    final c = completer;
    if (c != null) return c.future;
    final e = error;
    if (e != null) return Future<NutritionSourceBatch<SupplementLog>>.error(e);
    return Future<NutritionSourceBatch<SupplementLog>>.value(result);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

final class _TestRecordedBy {
  static RecordedBy get value => RecordedBy(
    uid: 'uid-test',
    name: 'Test User',
    internalRole: 'veterinary',
  );
}

MealLog _makeMeal({
  required String id,
  required String dogId,
  required DateTime fedAt,
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
  );
}

SupplementLog _makeSupplement({
  required String id,
  required String dogId,
  required DateTime administeredAt,
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
  );
}

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

ReaderBackedRawCanonicalNutritionFirstPageSource _makeSource({
  required NutritionCanonicalMealReader mealReader,
  required NutritionCanonicalSupplementLogReader supplementReader,
  RawCanonicalNutritionFirstPageMerger? merge,
}) {
  return ReaderBackedRawCanonicalNutritionFirstPageSource(
    mealReader: mealReader,
    supplementReader: supplementReader,
    merge: merge,
  );
}

RawCanonicalNutritionFirstPageSuccess _expectSuccess(
  RawCanonicalNutritionFirstPageResult result,
) {
  expect(result, isA<RawCanonicalNutritionFirstPageSuccess>());
  return result as RawCanonicalNutritionFirstPageSuccess;
}

RawCanonicalNutritionFirstPageFailure _expectFailure(
  RawCanonicalNutritionFirstPageResult result,
) {
  expect(result, isA<RawCanonicalNutritionFirstPageFailure>());
  return result as RawCanonicalNutritionFirstPageFailure;
}

void main() {
  group('ReaderBackedRawCanonicalNutritionFirstPageSource', () {
    // ── Test 1 ───────────────────────────────────────────────────────────────
    test(
      'loadFirstPage returns a RawCanonicalNutritionFirstPageResult',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          result: const NutritionSourceBatch<SupplementLog>.empty(),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        expect(result, isA<RawCanonicalNutritionFirstPageResult>());
      },
    );

    // ── Test 2 ───────────────────────────────────────────────────────────────
    test('eligible query invokes both readers exactly once', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));
      expect(mealReader.dogIds, equals(['dog123']));
      expect(supplementReader.dogIds, equals(['dog123']));
    });

    // ── Test 3 ───────────────────────────────────────────────────────────────
    test('eligibility is evaluated before reader I/O', () async {
      final mealReader = _FakeMealReader();
      final supplementReader = _FakeSupplementReader();
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final ineligible = HealthTimelineQuery(
        dogId: 'dog123',
        cursor: HealthTimelineCursor('some-cursor'),
      );

      await expectLater(
        source.loadFirstPage(ineligible),
        throwsA(isA<ArgumentError>()),
      );
      expect(mealReader.callCount, equals(0));
      expect(supplementReader.callCount, equals(0));
    });

    // ── Test 4 ───────────────────────────────────────────────────────────────
    test('cursor query throws ArgumentError with zero reader calls', () async {
      final mealReader = _FakeMealReader();
      final supplementReader = _FakeSupplementReader();
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await expectLater(
        source.loadFirstPage(
          HealthTimelineQuery(
            dogId: 'dog123',
            cursor: HealthTimelineCursor('some-cursor'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(mealReader.callCount, equals(0));
      expect(supplementReader.callCount, equals(0));
    });

    // ── Test 5 ───────────────────────────────────────────────────────────────
    test('types query throws ArgumentError with zero reader calls', () async {
      final mealReader = _FakeMealReader();
      final supplementReader = _FakeSupplementReader();
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await expectLater(
        source.loadFirstPage(
          HealthTimelineQuery(
            dogId: 'dog123',
            types: {HealthTimelineType.meal},
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(mealReader.callCount, equals(0));
      expect(supplementReader.callCount, equals(0));
    });

    // ── Test 6 ───────────────────────────────────────────────────────────────
    test('caseId query throws ArgumentError with zero reader calls', () async {
      final mealReader = _FakeMealReader();
      final supplementReader = _FakeSupplementReader();
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await expectLater(
        source.loadFirstPage(
          HealthTimelineQuery(dogId: 'dog123', caseId: 'case_abc'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(mealReader.callCount, equals(0));
      expect(supplementReader.callCount, equals(0));
    });

    // ── Test 7 ───────────────────────────────────────────────────────────────
    test(
      'professional query throws ArgumentError with zero reader calls',
      () async {
        final mealReader = _FakeMealReader();
        final supplementReader = _FakeSupplementReader();
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        await expectLater(
          source.loadFirstPage(
            HealthTimelineQuery(
              dogId: 'dog123',
              professional: HealthTimelineProfessionalFilter(name: 'Dr. Smith'),
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(mealReader.callCount, equals(0));
        expect(supplementReader.callCount, equals(0));
      },
    );

    // ── Test 8 ───────────────────────────────────────────────────────────────
    test('both captures start in parallel using Completers', () async {
      final mealCompleter = Completer<NutritionSourceBatch<MealLog>>();
      final supplementCompleter =
          Completer<NutritionSourceBatch<SupplementLog>>();
      final mealReader = _FakeMealReader(completer: mealCompleter);
      final supplementReader = _FakeSupplementReader(
        completer: supplementCompleter,
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final resultFuture = source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      // Let microtasks up to the joint await run: both readers already invoked.
      await Future<void>.value();
      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));
      expect(mealCompleter.isCompleted, isFalse);
      expect(supplementCompleter.isCompleted, isFalse);

      mealCompleter.complete(const NutritionSourceBatch<MealLog>.empty());
      supplementCompleter.complete(
        const NutritionSourceBatch<SupplementLog>.empty(),
      );

      final result = await resultFuture;
      _expectSuccess(result);
    });

    // ── Test 9 ───────────────────────────────────────────────────────────────
    test('Meal Reader receives no from/to', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await source.loadFirstPage(
        _makeQuery(
          dogId: 'dog123',
          start: DateTime(2024, 3, 1),
          end: DateTime(2024, 3, 31),
        ),
      );

      expect(mealReader.froms, equals(<DateTime?>[null]));
      expect(mealReader.tos, equals(<DateTime?>[null]));
    });

    // ── Test 10 ──────────────────────────────────────────────────────────────
    test('available + available returns Success', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(id: 'ml_1', dogId: 'dog123', fedAt: DateTime(2024, 3, 15)),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: NutritionSourceBatch<SupplementLog>.available([
          _makeSupplement(
            id: 'sl_1',
            dogId: 'dog123',
            administeredAt: DateTime(2024, 3, 14),
          ),
        ]),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      final success = _expectSuccess(result);
      expect(success.page.entries.length, equals(2));
    });

    // ── Test 11 ──────────────────────────────────────────────────────────────
    test('empty + available returns Success', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: NutritionSourceBatch<SupplementLog>.available([
          _makeSupplement(
            id: 'sl_1',
            dogId: 'dog123',
            administeredAt: DateTime(2024, 3, 14),
          ),
        ]),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      final success = _expectSuccess(result);
      expect(success.page.entries.length, equals(1));
    });

    // ── Test 12 ──────────────────────────────────────────────────────────────
    test('available + empty returns Success', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(id: 'ml_1', dogId: 'dog123', fedAt: DateTime(2024, 3, 15)),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      final success = _expectSuccess(result);
      expect(success.page.entries.length, equals(1));
    });

    // ── Test 13 ──────────────────────────────────────────────────────────────
    test('empty + empty returns empty Success with hasMore false', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      final success = _expectSuccess(result);
      expect(success.page.entries, isEmpty);
      expect(success.page.hasMore, isFalse);
    });

    // ── Test 14 ──────────────────────────────────────────────────────────────
    test('Meal offline maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.offline(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 15 ──────────────────────────────────────────────────────────────
    test('Meal error maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.error(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 16 ──────────────────────────────────────────────────────────────
    test('Meal notConfigured maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>(
          availability: NutritionSourceAvailability.notConfigured,
        ),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 17 ──────────────────────────────────────────────────────────────
    test('Meal synchronous throw maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(syncThrow: StateError('meal sync'));
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 18 ──────────────────────────────────────────────────────────────
    test('Meal Future exception maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(error: Exception('meal future'));
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 19 ──────────────────────────────────────────────────────────────
    test('Meal invalidBatch maps to mealReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>(
          availability: NutritionSourceAvailability.available,
          items: <MealLog>[],
        ),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    // ── Test 20 ──────────────────────────────────────────────────────────────
    test('Supplement offline maps to supplementReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.offline(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
      );
    });

    // ── Test 21 ──────────────────────────────────────────────────────────────
    test('Supplement error maps to supplementReaderUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.error(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
      );
    });

    // ── Test 22 ──────────────────────────────────────────────────────────────
    test(
      'Supplement notConfigured maps to supplementReaderUnavailable',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          result: const NutritionSourceBatch<SupplementLog>(
            availability: NutritionSourceAvailability.notConfigured,
          ),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        expect(
          _expectFailure(result).kind,
          RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
        );
      },
    );

    // ── Test 23 ──────────────────────────────────────────────────────────────
    test(
      'Supplement synchronous throw maps to supplementReaderUnavailable',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          syncThrow: StateError('supplement sync'),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        expect(
          _expectFailure(result).kind,
          RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
        );
      },
    );

    // ── Test 24 ──────────────────────────────────────────────────────────────
    test(
      'Supplement Future exception maps to supplementReaderUnavailable',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          error: Exception('supplement future'),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        expect(
          _expectFailure(result).kind,
          RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
        );
      },
    );

    // ── Test 25 ──────────────────────────────────────────────────────────────
    test(
      'Supplement invalidBatch maps to supplementReaderUnavailable',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          result: const NutritionSourceBatch<SupplementLog>(
            availability: NutritionSourceAvailability.available,
            items: <SupplementLog>[],
          ),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        expect(
          _expectFailure(result).kind,
          RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
        );
      },
    );

    // ── Test 26 ──────────────────────────────────────────────────────────────
    test('two unavailable captures of different kinds map to '
        'multipleReadersUnavailable', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.offline(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.error(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
      );
    });

    // ── Test 27 ──────────────────────────────────────────────────────────────
    test('both readers throwing map to multipleReadersUnavailable', () async {
      final mealReader = _FakeMealReader(syncThrow: StateError('meal'));
      final supplementReader = _FakeSupplementReader(
        error: Exception('supplement'),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
      );
    });

    // ── Test 28 ──────────────────────────────────────────────────────────────
    test('merger is not called when Meal is unavailable', () async {
      var mergeCalls = 0;
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.error(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) {
          mergeCalls++;
          return RawCanonicalNutritionFirstPage(
            entries: const [],
            hasMore: false,
          );
        },
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
      expect(mergeCalls, equals(0));
    });

    // ── Test 29 ──────────────────────────────────────────────────────────────
    test('merger is not called when Supplement is unavailable', () async {
      var mergeCalls = 0;
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.error(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) {
          mergeCalls++;
          return RawCanonicalNutritionFirstPage(
            entries: const [],
            hasMore: false,
          );
        },
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.supplementReaderUnavailable,
      );
      expect(mergeCalls, equals(0));
    });

    // ── Test 30 ──────────────────────────────────────────────────────────────
    test(
      'merger StateError dog mismatch maps to mergeInvariantFailed',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          result: const NutritionSourceBatch<SupplementLog>.empty(),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
          merge: ({required query, required meals, required supplements}) {
            throw StateError('dog_mismatch');
          },
        );

        final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

        final failure = _expectFailure(result);
        expect(
          failure.kind,
          RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
        );
        expect(failure.toString(), isNot(contains('dog_mismatch')));
      },
    );

    // ── Test 31 ──────────────────────────────────────────────────────────────
    test('merger StateError duplicate maps to mergeInvariantFailed', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) {
          throw StateError('duplicate_raw_canonical_entry');
        },
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
      );
    });

    // ── Test 32 ──────────────────────────────────────────────────────────────
    test('merger StateError collision maps to mergeInvariantFailed', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) {
          throw StateError('derived_timeline_id_collision');
        },
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
      );
    });

    // ── Test 33 ──────────────────────────────────────────────────────────────
    test('unexpected non-StateError from injected merger propagates', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) {
          throw ArgumentError('unexpected merger contract error');
        },
      );

      await expectLater(
        source.loadFirstPage(_makeQuery(dogId: 'dog123')),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── Test 34 ──────────────────────────────────────────────────────────────
    test('start boundary remains inclusive', () async {
      final start = DateTime(2024, 3, 1, 0, 0);
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(id: 'ml_start', dogId: 'dog123', fedAt: start),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(
        _makeQuery(dogId: 'dog123', start: start, end: DateTime(2024, 3, 31)),
      );

      final success = _expectSuccess(result);
      expect(success.page.entries.length, equals(1));
      expect(success.page.entries.single.sourceId, equals('ml_start'));
    });

    // ── Test 35 ──────────────────────────────────────────────────────────────
    test('end boundary remains inclusive', () async {
      final end = DateTime(2024, 3, 31, 0, 0);
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(id: 'ml_end', dogId: 'dog123', fedAt: end),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final result = await source.loadFirstPage(
        _makeQuery(dogId: 'dog123', start: DateTime(2024, 3, 1), end: end),
      );

      final success = _expectSuccess(result);
      expect(success.page.entries.length, equals(1));
      expect(success.page.entries.single.sourceId, equals('ml_end'));
    });

    // ── Test 36 ──────────────────────────────────────────────────────────────
    test('Success preserves the exact injected merger page instance', () async {
      final injectedPage = RawCanonicalNutritionFirstPage(
        entries: const [],
        hasMore: false,
      );
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
        merge: ({required query, required meals, required supplements}) =>
            injectedPage,
      );

      final result = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      final success = _expectSuccess(result);
      expect(identical(success.page, injectedPage), isTrue);
    });

    // ── Test 37 ──────────────────────────────────────────────────────────────
    test('source waits for both captures before classifying an unavailable '
        'result', () async {
      final supplementCompleter =
          Completer<NutritionSourceBatch<SupplementLog>>();
      // Meal resolves unavailable immediately; supplement stays pending.
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.error(),
      );
      final supplementReader = _FakeSupplementReader(
        completer: supplementCompleter,
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      var done = false;
      final resultFuture = source.loadFirstPage(_makeQuery(dogId: 'dog123'))
        ..then((_) => done = true);

      // Even after microtask flushes, the source must NOT classify while the
      // supplement capture is still pending.
      await Future<void>.value();
      await Future<void>.value();
      expect(done, isFalse);
      expect(supplementCompleter.isCompleted, isFalse);

      supplementCompleter.complete(
        const NutritionSourceBatch<SupplementLog>.empty(),
      );

      final result = await resultFuture;
      expect(
        _expectFailure(result).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });
  });
}
