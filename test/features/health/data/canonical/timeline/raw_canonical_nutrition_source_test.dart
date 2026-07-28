// Copyright 2024 GCM Health. All rights reserved.
//
// READER-BACKED RAW CANONICAL NUTRITION FIRST-PAGE SOURCE TESTS — 24 tests.
//
// Pure Dart. NO Firestore, NO FakeFirebaseFirestore, NO sleep, NO real Timer,
// NO network, NO HealthTimelinePage / HealthTimelineSource / sampler /
// observer / bridge. Parallelism proven with Completer.

import 'dart:async';

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
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
// Sensitive fictitious values — used to prove the sanitized exception never
// leaks reader detail.
// ─────────────────────────────────────────────────────────────────────────────

const _secretMessage = 'secret-reader-message';
const _secretCode = 'permission-denied-private';
const _secretPath = 'dogs/dog-secret/meal_logs/doc-secret';

// ─────────────────────────────────────────────────────────────────────────────
// Fakes — record calls and return a configured batch, a Future error, or a
// pending Completer future. They NEVER apply from/to filtering (period is the
// merger's authority) and never touch Firestore.
// ─────────────────────────────────────────────────────────────────────────────

final class _FakeMealReader implements NutritionCanonicalMealReader {
  _FakeMealReader({this.result, this.error, this.completer});

  final NutritionSourceBatch<MealLog>? result;
  final Object? error;
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
    final c = completer;
    if (c != null) return c.future;
    final e = error;
    if (e != null) return Future<NutritionSourceBatch<MealLog>>.error(e);
    return Future<NutritionSourceBatch<MealLog>>.value(result);
  }
}

final class _FakeSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  _FakeSupplementReader({this.result, this.error, this.completer});

  final NutritionSourceBatch<SupplementLog>? result;
  final Object? error;
  final Completer<NutritionSourceBatch<SupplementLog>>? completer;

  int callCount = 0;
  final List<String> dogIds = <String>[];

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(String dogId) {
    callCount++;
    dogIds.add(dogId);
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
}) {
  return ReaderBackedRawCanonicalNutritionFirstPageSource(
    mealReader: mealReader,
    supplementReader: supplementReader,
  );
}

void main() {
  group('ReaderBackedRawCanonicalNutritionFirstPageSource', () {
    // ── Test 1 ───────────────────────────────────────────────────────────────
    test('eligible query invokes both readers exactly once', () async {
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

      await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));
      expect(mealReader.dogIds, equals(['dog123']));
      expect(supplementReader.dogIds, equals(['dog123']));
    });

    // ── Test 2 ───────────────────────────────────────────────────────────────
    test('eligibility is evaluated before any reader I/O', () async {
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

    // ── Test 3 ───────────────────────────────────────────────────────────────
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

    // ── Test 4 ───────────────────────────────────────────────────────────────
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

    // ── Test 5 ───────────────────────────────────────────────────────────────
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

    // ── Test 6 ───────────────────────────────────────────────────────────────
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

    // ── Test 7 ───────────────────────────────────────────────────────────────
    test('both readers start in parallel using Completers', () async {
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

      final pageFuture = source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      // Both readers were started before either future completed.
      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));
      expect(mealCompleter.isCompleted, isFalse);
      expect(supplementCompleter.isCompleted, isFalse);

      mealCompleter.complete(NutritionSourceBatch<MealLog>.available([]));
      supplementCompleter.complete(
        NutritionSourceBatch<SupplementLog>.available([]),
      );

      final page = await pageFuture;
      expect(page, isA<RawCanonicalNutritionFirstPage>());
    });

    // ── Test 8 ───────────────────────────────────────────────────────────────
    test('meal reader is called with from null and to null', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([]),
      );
      final supplementReader = _FakeSupplementReader(
        result: NutritionSourceBatch<SupplementLog>.available([]),
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

      expect(mealReader.froms, equals([null]));
      expect(mealReader.tos, equals([null]));
    });

    // ── Test 9 ───────────────────────────────────────────────────────────────
    test('available + available feeds the merger', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(
            id: 'ml_1',
            dogId: 'dog123',
            fedAt: DateTime(2024, 3, 15, 8),
          ),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: NutritionSourceBatch<SupplementLog>.available([
          _makeSupplement(
            id: 'sl_1',
            dogId: 'dog123',
            administeredAt: DateTime(2024, 3, 14, 8),
          ),
        ]),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final page = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(page.entries.length, equals(2));
      expect(page.hasMore, isFalse);
    });

    // ── Test 10 ──────────────────────────────────────────────────────────────
    test('empty + available returns supplements only', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: NutritionSourceBatch<SupplementLog>.available([
          _makeSupplement(
            id: 'sl_1',
            dogId: 'dog123',
            administeredAt: DateTime(2024, 3, 14, 8),
          ),
        ]),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final page = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(page.entries.length, equals(1));
      expect(page.entries.single.sourceId, equals('sl_1'));
      expect(page.hasMore, isFalse);
    });

    // ── Test 11 ──────────────────────────────────────────────────────────────
    test('available + empty returns meals only', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(
            id: 'ml_1',
            dogId: 'dog123',
            fedAt: DateTime(2024, 3, 15, 8),
          ),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final page = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(page.entries.length, equals(1));
      expect(page.entries.single.sourceId, equals('ml_1'));
      expect(page.hasMore, isFalse);
    });

    // ── Test 12 ──────────────────────────────────────────────────────────────
    test('empty + empty returns an empty page with hasMore false', () async {
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

      final page = await source.loadFirstPage(_makeQuery(dogId: 'dog123'));

      expect(page.entries, isEmpty);
      expect(page.hasMore, isFalse);
    });

    // ── Test 13 ──────────────────────────────────────────────────────────────
    test('meal error throws sanitized source exception', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.error(
          message: _secretMessage,
          code: _secretCode,
        ),
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

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 14 ──────────────────────────────────────────────────────────────
    test('meal offline throws sanitized source exception', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.offline(
          message: _secretMessage,
          code: _secretCode,
        ),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 15 ──────────────────────────────────────────────────────────────
    test('meal notConfigured throws sanitized source exception', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>(
          availability: NutritionSourceAvailability.notConfigured,
          message: _secretMessage,
          code: _secretCode,
        ),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 16 ──────────────────────────────────────────────────────────────
    test('supplement error throws sanitized source exception', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(id: 'ml_1', dogId: 'dog123', fedAt: DateTime(2024, 3, 15)),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.error(
          message: _secretMessage,
          code: _secretCode,
        ),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 17 ──────────────────────────────────────────────────────────────
    test('supplement offline throws sanitized source exception', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.offline(
          message: _secretMessage,
          code: _secretCode,
        ),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 18 ──────────────────────────────────────────────────────────────
    test(
      'supplement notConfigured throws sanitized source exception',
      () async {
        final mealReader = _FakeMealReader(
          result: const NutritionSourceBatch<MealLog>.empty(),
        );
        final supplementReader = _FakeSupplementReader(
          result: NutritionSourceBatch<SupplementLog>(
            availability: NutritionSourceAvailability.notConfigured,
            message: _secretMessage,
            code: _secretCode,
          ),
        );
        final source = _makeSource(
          mealReader: mealReader,
          supplementReader: supplementReader,
        );

        final error = await _captureError(
          () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
        );
        expect(error, isA<RawCanonicalNutritionSourceException>());
        _expectNoLeak(error);
      },
    );

    // ── Test 19 ──────────────────────────────────────────────────────────────
    test('meal Future exception is sanitized', () async {
      final mealReader = _FakeMealReader(error: Exception(_secretPath));
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 20 ──────────────────────────────────────────────────────────────
    test('supplement Future exception is sanitized', () async {
      final mealReader = _FakeMealReader(
        result: const NutritionSourceBatch<MealLog>.empty(),
      );
      final supplementReader = _FakeSupplementReader(
        error: Exception(_secretPath),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      final error = await _captureError(
        () => source.loadFirstPage(_makeQuery(dogId: 'dog123')),
      );
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
    });

    // ── Test 21 ──────────────────────────────────────────────────────────────
    test('both Future exceptions are jointly observed and sanitized', () async {
      // Both readers fail via Completers. Record `.wait` registers listeners on
      // BOTH futures up front and only settles after observing both, so the
      // source's returned Future is itself the synchronization point — no timer
      // or microtask flush is needed and no unobserved async error can escape.
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

      // Both readers were started before either future settled.
      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));

      mealCompleter.completeError(Exception(_secretPath));
      supplementCompleter.completeError(Exception(_secretMessage));

      final error = await _captureError(() => resultFuture);
      expect(error, isA<RawCanonicalNutritionSourceException>());
      _expectNoLeak(error);
      expect(mealReader.callCount, equals(1));
      expect(supplementReader.callCount, equals(1));
    });

    // ── Test 22 ──────────────────────────────────────────────────────────────
    test('dog mismatch propagates merger StateError', () async {
      final mealReader = _FakeMealReader(
        result: NutritionSourceBatch<MealLog>.available([
          _makeMeal(
            id: 'ml_1',
            dogId: 'other-dog',
            fedAt: DateTime(2024, 3, 15),
          ),
        ]),
      );
      final supplementReader = _FakeSupplementReader(
        result: const NutritionSourceBatch<SupplementLog>.empty(),
      );
      final source = _makeSource(
        mealReader: mealReader,
        supplementReader: supplementReader,
      );

      await expectLater(
        source.loadFirstPage(_makeQuery(dogId: 'dog123')),
        throwsA(isA<StateError>()),
      );
    });

    // ── Test 23 ──────────────────────────────────────────────────────────────
    test('period start remains inclusive', () async {
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

      final page = await source.loadFirstPage(
        _makeQuery(dogId: 'dog123', start: start, end: DateTime(2024, 3, 31)),
      );

      expect(page.entries.length, equals(1));
      expect(page.entries.single.sourceId, equals('ml_start'));
    });

    // ── Test 24 ──────────────────────────────────────────────────────────────
    test('period end remains inclusive', () async {
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

      final page = await source.loadFirstPage(
        _makeQuery(dogId: 'dog123', start: DateTime(2024, 3, 1), end: end),
      );

      expect(page.entries.length, equals(1));
      expect(page.entries.single.sourceId, equals('ml_end'));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Runs [action] and returns the thrown error, failing if none is thrown.
Future<Object> _captureError(Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    return e;
  }
  fail('expected an exception but none was thrown');
}

/// Asserts the sanitized exception's string form leaks no reader detail.
void _expectNoLeak(Object error) {
  final text = error.toString();
  expect(text, isNot(contains(_secretMessage)));
  expect(text, isNot(contains(_secretCode)));
  expect(text, isNot(contains(_secretPath)));
  expect(text, equals('raw canonical nutrition source unavailable'));
}
