// Copyright 2024 GCM Health. All rights reserved.
//
// PER-READER RAW CANONICAL NUTRITION CAPTURE TESTS — 24 tests.
//
// Pure Dart. NO Firestore, NO FakeFirebaseFirestore, NO network, NO sleep,
// NO Timer, NO Future.delayed, NO timeout, NO Stopwatch, NO HealthTimelineSource
// / HealthTimelinePage / sampler / observer / bridge. Parallelism is proven
// EXCLUSIVELY with Completer.

import 'dart:async';
import 'dart:collection';

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_reader_capture.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sensitive fictitious values — used to prove the sanitized capture never
// exposes reader message / code / exception detail.
// ─────────────────────────────────────────────────────────────────────────────

const String _secretMessage = 'SECRET_READER_MESSAGE_do-not-leak';
const String _secretCode = 'SECRET_READER_CODE_do-not-leak';
const String _secretExceptionText = 'SECRET_EXCEPTION_do-not-leak';

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures — generic captures require NO type-specific branch, so the same
// entry point is exercised with both MealLog and SupplementLog.
// ─────────────────────────────────────────────────────────────────────────────

final class _TestRecordedBy {
  static RecordedBy get value => RecordedBy(
    uid: 'uid-test',
    name: 'Test User',
    internalRole: 'veterinary',
  );
}

MealLog _makeMeal({String id = 'meal-1', String dogId = 'dog-1'}) {
  return MealLog(
    id: id,
    dogId: dogId,
    period: MealPeriodWire.parseCanonical('morning'),
    offeredGrams: 200.0,
    acceptance: MealAcceptanceWire.parse('full'),
    fedAt: DateTime.utc(2024, 1, 1, 8),
    recordedBy: _TestRecordedBy.value,
    schemaVersion: 1,
    revision: 1,
  );
}

SupplementLog _makeSupplement({String id = 'supp-1', String dogId = 'dog-1'}) {
  return SupplementLog(
    id: id,
    dogId: dogId,
    supplementName: 'Vitamin D',
    dose: 10.0,
    unit: SupplementDoseUnit.mg,
    administeredAt: DateTime.utc(2024, 1, 1, 9),
    recordedBy: _TestRecordedBy.value,
    schemaVersion: 1,
    revision: 1,
  );
}

/// A [List] whose inspection / iteration always throws. Returned intact by the
/// thunk so the failure occurs AFTER the Future resolves, during batch
/// post-processing (isEmpty / copy) — proving the try/catch is total.
final class _ExplodingList<T> extends ListBase<T> {
  @override
  int get length => throw StateError(_secretExceptionText);

  @override
  set length(int newLength) => throw StateError(_secretExceptionText);

  @override
  T operator [](int index) => throw StateError(_secretExceptionText);

  @override
  void operator []=(int index, T value) =>
      throw StateError(_secretExceptionText);

  @override
  Iterator<T> get iterator => throw StateError(_secretExceptionText);
}

void main() {
  group('captureRawCanonicalNutritionReader', () {
    test('1. available non-empty returns usable available', () async {
      final meal = _makeMeal();
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => NutritionSourceBatch<MealLog>.available([meal]),
      );

      expect(capture, isA<RawCanonicalNutritionReaderUsable<MealLog>>());
      final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
      expect(usable.state, RawCanonicalNutritionReaderUsableState.available);
      expect(usable.items, hasLength(1));
    });

    test('2. available preserves item order and item identity', () async {
      final a = _makeMeal(id: 'meal-a');
      final b = _makeMeal(id: 'meal-b');
      final c = _makeMeal(id: 'meal-c');
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => NutritionSourceBatch<MealLog>.available([a, b, c]),
      );

      final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
      expect(usable.items, hasLength(3));
      expect(identical(usable.items[0], a), isTrue);
      expect(identical(usable.items[1], b), isTrue);
      expect(identical(usable.items[2], c), isTrue);
    });

    test(
      '3. available capture is detached from later mutations of the original '
      'list',
      () async {
        final source = <MealLog>[_makeMeal(id: 'meal-a')];
        // Build the batch directly via the generic constructor so the source
        // list is NOT copied by the named constructor before capture.
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.available,
            items: source,
          ),
        );

        final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
        expect(usable.items, hasLength(1));

        source.add(_makeMeal(id: 'meal-b'));
        expect(usable.items, hasLength(1));
      },
    );

    test('4. available capture items reject mutation', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => NutritionSourceBatch<MealLog>.available([_makeMeal()]),
      );

      final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
      expect(
        () => usable.items.add(_makeMeal(id: 'meal-x')),
        throwsUnsupportedError,
      );
      expect(() => usable.items.clear(), throwsUnsupportedError);
    });

    test('5. empty returns usable empty distinct from available', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => const NutritionSourceBatch<MealLog>.empty(),
      );

      expect(capture, isA<RawCanonicalNutritionReaderUsable<MealLog>>());
      final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
      expect(usable.state, RawCanonicalNutritionReaderUsableState.empty);
      expect(
        usable.state,
        isNot(RawCanonicalNutritionReaderUsableState.available),
      );
    });

    test('6. empty capture has immutable empty items', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => const NutritionSourceBatch<MealLog>.empty(),
      );

      final usable = capture as RawCanonicalNutritionReaderUsable<MealLog>;
      expect(usable.items, isEmpty);
      expect(() => usable.items.add(_makeMeal()), throwsUnsupportedError);
    });

    test('7. offline returns unavailable offline', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => const NutritionSourceBatch<MealLog>.offline(),
      );

      expect(capture, isA<RawCanonicalNutritionReaderUnavailable<MealLog>>());
      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.offline,
      );
    });

    test('8. error returns unavailable error', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => const NutritionSourceBatch<MealLog>.error(),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.error,
      );
    });

    test('9. notConfigured returns unavailable notConfigured', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => const NutritionSourceBatch<MealLog>(
          availability: NutritionSourceAvailability.notConfigured,
        ),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.notConfigured,
      );
    });

    test('10. synchronous throw returns unavailable threw', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () => throw StateError(_secretExceptionText),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.threw,
      );
    });

    test('11. Future exception returns unavailable threw', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () => Future<NutritionSourceBatch<MealLog>>.error(
          StateError(_secretExceptionText),
        ),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.threw,
      );
    });

    test('12. original exception is not stored or exposed', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () => throw StateError(_secretExceptionText),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      // Only the kind is carried; no exception / message / stack is reachable.
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.threw,
      );
      expect(unavailable.toString(), isNot(contains(_secretExceptionText)));
    });

    test('13. batch message is not stored or exposed', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async =>
            const NutritionSourceBatch<MealLog>.error(message: _secretMessage),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.error,
      );
      expect(unavailable.toString(), isNot(contains(_secretMessage)));
    });

    test('14. batch code is not stored or exposed', () async {
      final capture = await captureRawCanonicalNutritionReader<MealLog>(
        () async =>
            const NutritionSourceBatch<MealLog>.error(code: _secretCode),
      );

      final unavailable =
          capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
      expect(
        unavailable.kind,
        RawCanonicalNutritionReaderUnavailableKind.error,
      );
      expect(unavailable.toString(), isNot(contains(_secretCode)));
    });

    test(
      '15. generic available with empty items returns invalidBatch',
      () async {
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => const NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.available,
            items: <MealLog>[],
          ),
        );

        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
        );
      },
    );

    test(
      '16. generic empty with non-empty items returns invalidBatch',
      () async {
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.empty,
            items: [_makeMeal()],
          ),
        );

        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
        );
      },
    );

    test(
      '17. generic offline with non-empty items returns invalidBatch',
      () async {
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.offline,
            items: [_makeMeal()],
          ),
        );

        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
        );
      },
    );

    test(
      '18. generic error with non-empty items returns invalidBatch',
      () async {
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.error,
            items: [_makeMeal()],
          ),
        );

        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
        );
      },
    );

    test(
      '19. generic notConfigured with non-empty items returns invalidBatch',
      () async {
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.notConfigured,
            items: [_makeMeal()],
          ),
        );

        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
        );
      },
    );

    test('20. read callback is invoked exactly once', () async {
      var calls = 0;
      await captureRawCanonicalNutritionReader<MealLog>(() async {
        calls++;
        return const NutritionSourceBatch<MealLog>.empty();
      });

      expect(calls, 1);
    });

    test(
      '21. exception while inspecting or copying batch items is sanitized as '
      'threw',
      () async {
        // The thunk returns a well-formed Future whose batch carries a list
        // that explodes on inspection / copy. The failure therefore happens
        // AFTER Future.sync resolves, during post-processing.
        final capture = await captureRawCanonicalNutritionReader<MealLog>(
          () async => NutritionSourceBatch<MealLog>(
            availability: NutritionSourceAvailability.available,
            items: _ExplodingList<MealLog>(),
          ),
        );

        expect(capture, isA<RawCanonicalNutritionReaderUnavailable<MealLog>>());
        final unavailable =
            capture as RawCanonicalNutritionReaderUnavailable<MealLog>;
        expect(
          unavailable.kind,
          RawCanonicalNutritionReaderUnavailableKind.threw,
        );
        expect(unavailable.toString(), isNot(contains(_secretExceptionText)));
      },
    );

    test(
      '22. two captures can remain pending simultaneously using Completers',
      () async {
        final firstCompleter = Completer<NutritionSourceBatch<MealLog>>();
        final secondCompleter = Completer<NutritionSourceBatch<MealLog>>();
        var firstCalls = 0;
        var secondCalls = 0;

        final firstFuture = captureRawCanonicalNutritionReader<MealLog>(() {
          firstCalls++;
          return firstCompleter.future;
        });
        final secondFuture = captureRawCanonicalNutritionReader<MealLog>(() {
          secondCalls++;
          return secondCompleter.future;
        });

        // Let the microtasks up to the first await run so both thunks are called.
        await Future<void>.value();

        expect(firstCalls, 1);
        expect(secondCalls, 1);
        expect(firstCompleter.isCompleted, isFalse);
        expect(secondCompleter.isCompleted, isFalse);

        firstCompleter.complete(
          NutritionSourceBatch<MealLog>.available([_makeMeal()]),
        );
        secondCompleter.complete(const NutritionSourceBatch<MealLog>.empty());

        final first = await firstFuture;
        final second = await secondFuture;

        expect(
          (first as RawCanonicalNutritionReaderUsable<MealLog>).state,
          RawCanonicalNutritionReaderUsableState.available,
        );
        expect(
          (second as RawCanonicalNutritionReaderUsable<MealLog>).state,
          RawCanonicalNutritionReaderUsableState.empty,
        );
      },
    );

    test(
      '23. failure of one capture does not prevent the other completing',
      () async {
        final firstCompleter = Completer<NutritionSourceBatch<MealLog>>();
        final secondCompleter = Completer<NutritionSourceBatch<MealLog>>();

        final firstFuture = captureRawCanonicalNutritionReader<MealLog>(
          () => firstCompleter.future,
        );
        final secondFuture = captureRawCanonicalNutritionReader<MealLog>(
          () => secondCompleter.future,
        );

        // First fails while the second stays pending.
        firstCompleter.completeError(StateError(_secretExceptionText));
        final first = await firstFuture;
        expect(
          (first as RawCanonicalNutritionReaderUnavailable<MealLog>).kind,
          RawCanonicalNutritionReaderUnavailableKind.threw,
        );

        // Second can still complete normally and is unaffected by the first.
        expect(secondCompleter.isCompleted, isFalse);
        secondCompleter.complete(
          NutritionSourceBatch<MealLog>.available([_makeMeal()]),
        );
        final second = await secondFuture;
        expect(second, isA<RawCanonicalNutritionReaderUsable<MealLog>>());
        expect(
          (second as RawCanonicalNutritionReaderUsable<MealLog>).state,
          RawCanonicalNutritionReaderUsableState.available,
        );
      },
    );

    test('24. generic MealLog and SupplementLog captures require no '
        'type-specific branch', () async {
      final mealCapture = await captureRawCanonicalNutritionReader<MealLog>(
        () async => NutritionSourceBatch<MealLog>.available([_makeMeal()]),
      );
      final supplementCapture =
          await captureRawCanonicalNutritionReader<SupplementLog>(
            () async => NutritionSourceBatch<SupplementLog>.available([
              _makeSupplement(),
            ]),
          );

      final mealUsable =
          mealCapture as RawCanonicalNutritionReaderUsable<MealLog>;
      final supplementUsable =
          supplementCapture as RawCanonicalNutritionReaderUsable<SupplementLog>;

      expect(
        mealUsable.state,
        RawCanonicalNutritionReaderUsableState.available,
      );
      expect(
        supplementUsable.state,
        RawCanonicalNutritionReaderUsableState.available,
      );
      expect(mealUsable.items.single, isA<MealLog>());
      expect(supplementUsable.items.single, isA<SupplementLog>());
    });
  });
}
