// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for ShadowComparingHealthTimelineSource withRunner Integration (4C-C-C-H2B).
//
// Exactly 32 test declarations. Zero functional timing / wall-clock delays.

import 'dart:async';

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';
import 'package:canil_gcm/features/health/data/shadow/shadow_comparing_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test Fakes — Zero wall clock delays.
// ─────────────────────────────────────────────────────────────────────────────

class _FakePrimarySource implements HealthTimelineSource {
  _FakePrimarySource({
    this.pageToReturn,
    this.syncException,
    this.asyncException,
    this.completer,
  });

  final HealthTimelinePage? pageToReturn;
  final Object? syncException;
  final Object? asyncException;
  final Completer<HealthTimelinePage>? completer;

  int calls = 0;
  HealthTimelineQuery? receivedQuery;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) {
    calls++;
    receivedQuery = query;

    final syncErr = syncException;
    if (syncErr != null) throw syncErr;

    final asyncErr = asyncException;
    if (asyncErr != null) return Future.error(asyncErr);

    final comp = completer;
    if (comp != null) return comp.future;

    return Future.value(
      pageToReturn ??
          HealthTimelinePage(items: const [], nextCursor: null, hasMore: false),
    );
  }
}

class _FakeShadowSource implements HealthTimelineSource {
  _FakeShadowSource();

  int calls = 0;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) {
    calls++;
    return Future.value(
      HealthTimelinePage(items: const [], nextCursor: null, hasMore: false),
    );
  }
}

class _FakeShadowRunner implements HealthTimelineShadowRunner {
  _FakeShadowRunner({this.resultToReturn});

  final HealthTimelineShadowRunResult? resultToReturn;

  int calls = 0;
  HealthTimelineQuery? receivedQuery;
  List<HealthTimelineEntryView>? receivedPrimaryItems;

  @override
  Future<HealthTimelineShadowRunResult> run({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    calls++;
    receivedQuery = query;
    receivedPrimaryItems = primaryItems;

    return resultToReturn ??
        const HealthTimelineShadowRunSuccess(
          primaryCount: 0,
          shadowCount: 0,
          matchedCount: 0,
          missingCount: 0,
          extraCount: 0,
          uncorrelatedPrimaryCount: 0,
          uncorrelatedShadowCount: 0,
          ambiguousPrimaryCount: 0,
          ambiguousShadowCount: 0,
          orderingMismatch: false,
        );
  }
}

class _FakeRunnerExecutor implements HealthTimelineShadowRunnerExecutor {
  _FakeRunnerExecutor({
    this.resultToReturn,
    this.syncException,
    this.asyncException,
    this.completer,
    this.passthrough = true,
  });

  final HealthTimelineShadowRunnerExecutionResult? resultToReturn;
  final Object? syncException;
  final Object? asyncException;
  final Completer<HealthTimelineShadowRunnerExecutionResult>? completer;
  final bool passthrough;

  int calls = 0;
  Future<HealthTimelineShadowRunResult> Function()? receivedOperation;
  Duration? receivedTimeout;

  @override
  Future<HealthTimelineShadowRunnerExecutionResult> execute({
    required Future<HealthTimelineShadowRunResult> Function() operation,
    required Duration timeout,
  }) async {
    calls++;
    receivedOperation = operation;
    receivedTimeout = timeout;

    final syncErr = syncException;
    if (syncErr != null) throw syncErr;

    final asyncErr = asyncException;
    if (asyncErr != null) return Future.error(asyncErr);

    final comp = completer;
    if (comp != null) return comp.future;

    HealthTimelineShadowRunResult? runResult;
    if (passthrough) {
      runResult = await operation();
    }

    return resultToReturn ??
        HealthTimelineShadowRunnerCompleted(
          result:
              runResult ??
              const HealthTimelineShadowRunSuccess(
                primaryCount: 0,
                shadowCount: 0,
                matchedCount: 0,
                missingCount: 0,
                extraCount: 0,
                uncorrelatedPrimaryCount: 0,
                uncorrelatedShadowCount: 0,
                ambiguousPrimaryCount: 0,
                ambiguousShadowCount: 0,
                orderingMismatch: false,
              ),
          elapsedMilliseconds: 42,
        );
  }
}

class _RecordingObserver implements HealthTimelineShadowObserver {
  final List<HealthTimelineShadowOutcome> outcomes = [];
  final List<Completer<void>> _completers = [];

  @override
  FutureOr<void> onComparison(HealthTimelineShadowComparison value) {
    _record(value);
  }

  @override
  FutureOr<void> onSkipped(HealthTimelineShadowSkipped value) {
    _record(value);
  }

  @override
  FutureOr<void> onFailure(HealthTimelineShadowFailure value) {
    _record(value);
  }

  void _record(HealthTimelineShadowOutcome outcome) {
    outcomes.add(outcome);
    if (_completers.isNotEmpty) {
      _completers.removeAt(0).complete();
    }
  }

  Future<void> waitForOutcome() async {
    if (outcomes.isNotEmpty) return;
    final c = Completer<void>();
    _completers.add(c);
    await c.future;
  }
}

class _ThrowingObserver implements HealthTimelineShadowObserver {
  _ThrowingObserver({this.isAsync = false});
  final bool isAsync;

  @override
  FutureOr<void> onComparison(HealthTimelineShadowComparison value) => _throw();

  @override
  FutureOr<void> onSkipped(HealthTimelineShadowSkipped value) => _throw();

  @override
  FutureOr<void> onFailure(HealthTimelineShadowFailure value) => _throw();

  Never _throw() {
    if (isAsync) {
      throw StateError('async_observer_error');
    } else {
      throw StateError('sync_observer_error');
    }
  }
}

// Helpers
HealthTimelineQuery _sampleQuery() => HealthTimelineQuery(dogId: 'dog-123');

HealthTimelineEntryView _sampleItem(String id) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog-123',
    type: HealthTimelineTypeView.known(HealthTimelineType.meal),
    occurredAt: DateTime.utc(2024, 1, 1),
    recordedAt: DateTime.utc(2024, 1, 1),
    title: 'Item $id',
    status: HealthTimelineEntryStatus.finalised,
  );
}

void main() {
  group('Construção e primary', () {
    test('withRunner constructs without requiring a shadow source', () {
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: null,
        runnerExecutor: executor,
      );

      expect(source, isA<ShadowComparingHealthTimelineSource>());
    });

    test('legacy constructor remains source compatible', () {
      final primary = _FakePrimarySource();
      final shadow = _FakeShadowSource();

      final source = ShadowComparingHealthTimelineSource(
        primarySource: primary,
        shadowSource: shadow,
        observer: null,
      );

      expect(source, isA<ShadowComparingHealthTimelineSource>());
    });

    test('runner mode calls primary source exactly once', () async {
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: null,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());

      expect(primary.calls, 1);
    });

    test('runner mode forwards the identical query to primary', () async {
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();
      final query = _sampleQuery();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: null,
        runnerExecutor: executor,
      );

      await source.loadPage(query);

      expect(identical(primary.receivedQuery, query), isTrue);
    });

    test(
      'runner mode returns the identical primary page with items cursor and hasMore',
      () async {
        final expectedPage = HealthTimelinePage(
          items: [_sampleItem('1'), _sampleItem('2')],
          nextCursor: HealthTimelineCursor('cursor-abc'),
          hasMore: true,
        );
        final primary = _FakePrimarySource(pageToReturn: expectedPage);
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor();

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: null,
          runnerExecutor: executor,
        );

        final resultPage = await source.loadPage(_sampleQuery());

        expect(identical(resultPage, expectedPage), isTrue);
        expect(resultPage.items, equals(expectedPage.items));
        expect(resultPage.nextCursor?.token, equals('cursor-abc'));
        expect(resultPage.hasMore, isTrue);
      },
    );

    test('primary result does not wait for runner completion', () async {
      final executorCompleter =
          Completer<HealthTimelineShadowRunnerExecutionResult>();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(completer: executorCompleter);

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: null,
        runnerExecutor: executor,
      );

      final pageFuture = source.loadPage(_sampleQuery());

      // Should resolve without waiting for executorCompleter
      final page = await pageFuture;
      expect(page, isNotNull);
      expect(executorCompleter.isCompleted, isFalse);
    });
  });

  group('Lifecycle do runner', () {
    test('runner is not called before primary completes', () async {
      final primaryCompleter = Completer<HealthTimelinePage>();
      final primary = _FakePrimarySource(completer: primaryCompleter);
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: null,
        runnerExecutor: executor,
      );

      unawaited(source.loadPage(_sampleQuery()));

      expect(primary.calls, 1);
      expect(executor.calls, 0);
      expect(runner.calls, 0);
    });

    test('runner is called exactly once after primary success', () async {
      final primaryCompleter = Completer<HealthTimelinePage>();
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource(completer: primaryCompleter);
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      unawaited(source.loadPage(_sampleQuery()));
      expect(runner.calls, 0);

      primaryCompleter.complete(
        HealthTimelinePage(items: const [], nextCursor: null, hasMore: false),
      );
      await observer.waitForOutcome();

      expect(executor.calls, 1);
      expect(runner.calls, 1);
    });

    test('runner receives the identical query', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();
      final query = _sampleQuery();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(query);
      await observer.waitForOutcome();

      expect(identical(runner.receivedQuery, query), isTrue);
    });

    test('runner receives primary items in original order', () async {
      final items = [_sampleItem('a'), _sampleItem('b'), _sampleItem('c')];
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource(
        pageToReturn: HealthTimelinePage(
          items: items,
          nextCursor: null,
          hasMore: false,
        ),
      );
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      expect(runner.receivedPrimaryItems, equals(items));
    });
  });

  group('Eligibility', () {
    test('notFirstPage skips runner and executor', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(
        HealthTimelineQuery(
          dogId: 'dog-1',
          cursor: HealthTimelineCursor('cursor-123'),
        ),
      );
      await observer.waitForOutcome();

      expect(runner.calls, 0);
      expect(executor.calls, 0);
      expect(observer.outcomes.length, 1);
      final outcome = observer.outcomes.first as HealthTimelineShadowSkipped;
      expect(outcome.skipKind, HealthTimelineShadowSkipKind.notFirstPage);
    });

    test('unsupportedTypes skips runner and executor', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-1', types: {HealthTimelineType.meal}),
      );
      await observer.waitForOutcome();

      expect(runner.calls, 0);
      expect(executor.calls, 0);
      expect(observer.outcomes.length, 1);
      final outcome = observer.outcomes.first as HealthTimelineShadowSkipped;
      expect(outcome.skipKind, HealthTimelineShadowSkipKind.unsupportedTypes);
    });

    test('unsupportedCaseId skips runner and executor', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(
        HealthTimelineQuery(dogId: 'dog-1', caseId: 'case-99'),
      );
      await observer.waitForOutcome();

      expect(runner.calls, 0);
      expect(executor.calls, 0);
      expect(observer.outcomes.length, 1);
      final outcome = observer.outcomes.first as HealthTimelineShadowSkipped;
      expect(outcome.skipKind, HealthTimelineShadowSkipKind.unsupportedCaseId);
    });

    test('unsupportedProfessional skips runner and executor', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(
        HealthTimelineQuery(
          dogId: 'dog-1',
          professional: HealthTimelineProfessionalFilter(name: 'vet-pro'),
        ),
      );
      await observer.waitForOutcome();

      expect(runner.calls, 0);
      expect(executor.calls, 0);
      expect(observer.outcomes.length, 1);
      final outcome = observer.outcomes.first as HealthTimelineShadowSkipped;
      expect(
        outcome.skipKind,
        HealthTimelineShadowSkipKind.unsupportedProfessional,
      );
    });
  });

  group('Primary failure', () {
    test(
      'synchronous primary failure propagates and does not call runner',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource(
          syncException: StateError('sync_prim_err'),
        );
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor();

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        expect(
          () => source.loadPage(_sampleQuery()),
          throwsA(isA<StateError>()),
        );
        await observer.waitForOutcome();

        expect(runner.calls, 0);
        expect(executor.calls, 0);
      },
    );

    test(
      'asynchronous primary failure propagates and does not call runner',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource(
          asyncException: StateError('async_prim_err'),
        );
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor();

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        await expectLater(
          source.loadPage(_sampleQuery()),
          throwsA(isA<StateError>()),
        );
        await observer.waitForOutcome();

        expect(runner.calls, 0);
        expect(executor.calls, 0);
      },
    );

    test('primary failure is observed with null latency', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource(
        asyncException: StateError('prim_err'),
      );
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await expectLater(
        source.loadPage(_sampleQuery()),
        throwsA(isA<StateError>()),
      );
      await observer.waitForOutcome();

      expect(observer.outcomes.length, 1);
      final failure = observer.outcomes.first as HealthTimelineShadowFailure;
      expect(
        failure.failureKind,
        HealthTimelineShadowFailureKind.primaryFailure,
      );
      expect(failure.shadowLatencyMs, isNull);
    });
  });

  group('Success mapping', () {
    test('runner success maps all ten fields without recalculation', () async {
      const runSuccess = HealthTimelineShadowRunSuccess(
        primaryCount: 10,
        shadowCount: 8,
        matchedCount: 6,
        missingCount: 4,
        extraCount: 2,
        uncorrelatedPrimaryCount: 1,
        uncorrelatedShadowCount: 1,
        ambiguousPrimaryCount: 3,
        ambiguousShadowCount: 3,
        orderingMismatch: true,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner(resultToReturn: runSuccess);
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runSuccess,
          elapsedMilliseconds: 99,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      expect(observer.outcomes.length, 1);
      final comparison =
          observer.outcomes.first as HealthTimelineShadowComparison;
      expect(comparison.primaryCount, 10);
      expect(comparison.shadowCount, 8);
      expect(comparison.matchedCount, 6);
      expect(comparison.missingCount, 4);
      expect(comparison.extraCount, 2);
      expect(comparison.uncorrelatedPrimaryCount, 1);
      expect(comparison.uncorrelatedShadowCount, 1);
      expect(comparison.ambiguousPrimaryCount, 3);
      expect(comparison.ambiguousShadowCount, 3);
      expect(comparison.orderingMismatch, isTrue);
    });

    test('runner success uses the exact executor latency', () async {
      const runSuccess = HealthTimelineShadowRunSuccess(
        primaryCount: 1,
        shadowCount: 1,
        matchedCount: 1,
        missingCount: 0,
        extraCount: 0,
        uncorrelatedPrimaryCount: 0,
        uncorrelatedShadowCount: 0,
        ambiguousPrimaryCount: 0,
        ambiguousShadowCount: 0,
        orderingMismatch: false,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runSuccess,
          elapsedMilliseconds: 321,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      final comparison =
          observer.outcomes.first as HealthTimelineShadowComparison;
      expect(comparison.shadowLatencyMs, 321);
    });
  });

  group('Typed failure mapping', () {
    test('runner shadowFailure maps with exact latency', () async {
      const runFailure = HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.shadowFailure,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runFailure,
          elapsedMilliseconds: 77,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      final failure = observer.outcomes.first as HealthTimelineShadowFailure;
      expect(
        failure.failureKind,
        HealthTimelineShadowFailureKind.shadowFailure,
      );
      expect(failure.shadowLatencyMs, 77);
    });

    test('runner comparatorFailure maps with exact latency', () async {
      const runFailure = HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.comparatorFailure,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runFailure,
          elapsedMilliseconds: 88,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      final failure = observer.outcomes.first as HealthTimelineShadowFailure;
      expect(
        failure.failureKind,
        HealthTimelineShadowFailureKind.comparatorFailure,
      );
      expect(failure.shadowLatencyMs, 88);
    });

    test('runner primaryFailure is normalized to comparatorFailure', () async {
      const runFailure = HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.primaryFailure,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runFailure,
          elapsedMilliseconds: 44,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      final failure = observer.outcomes.first as HealthTimelineShadowFailure;
      expect(
        failure.failureKind,
        HealthTimelineShadowFailureKind.comparatorFailure,
      );
      expect(failure.shadowLatencyMs, 44);
    });

    test('runner shadowTimeout is normalized to comparatorFailure', () async {
      const runFailure = HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.shadowTimeout,
      );
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerCompleted(
          result: runFailure,
          elapsedMilliseconds: 55,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      final failure = observer.outcomes.first as HealthTimelineShadowFailure;
      expect(
        failure.failureKind,
        HealthTimelineShadowFailureKind.comparatorFailure,
      );
      expect(failure.shadowLatencyMs, 55);
    });
  });

  group('Executor outcomes', () {
    test(
      'executor Threw maps to comparatorFailure with exact latency',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(
          resultToReturn: const HealthTimelineShadowRunnerThrew(
            elapsedMilliseconds: 123,
          ),
          passthrough: false,
        );

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        await source.loadPage(_sampleQuery());
        await observer.waitForOutcome();

        final failure = observer.outcomes.first as HealthTimelineShadowFailure;
        expect(
          failure.failureKind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
        expect(failure.shadowLatencyMs, 123);
      },
    );

    test(
      'executor TimedOut maps to shadowTimeout with exact latency',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(
          resultToReturn: const HealthTimelineShadowRunnerTimedOut(
            elapsedMilliseconds: 5000,
          ),
          passthrough: false,
        );

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        await source.loadPage(_sampleQuery());
        await observer.waitForOutcome();

        final failure = observer.outcomes.first as HealthTimelineShadowFailure;
        expect(
          failure.failureKind,
          HealthTimelineShadowFailureKind.shadowTimeout,
        );
        expect(failure.shadowLatencyMs, 5000);
      },
    );

    test(
      'synchronous executor throw is contained as comparatorFailure with null latency',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(
          syncException: StateError('exec_sync_err'),
        );

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        final page = await source.loadPage(_sampleQuery());
        expect(page, isNotNull);
        await observer.waitForOutcome();

        final failure = observer.outcomes.first as HealthTimelineShadowFailure;
        expect(
          failure.failureKind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
        expect(failure.shadowLatencyMs, isNull);
      },
    );

    test(
      'asynchronous executor error is contained as comparatorFailure with null latency',
      () async {
        final observer = _RecordingObserver();
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor(
          asyncException: StateError('exec_async_err'),
        );

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: observer,
          runnerExecutor: executor,
        );

        final page = await source.loadPage(_sampleQuery());
        expect(page, isNotNull);
        await observer.waitForOutcome();

        final failure = observer.outcomes.first as HealthTimelineShadowFailure;
        expect(
          failure.failureKind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
        expect(failure.shadowLatencyMs, isNull);
      },
    );
  });

  group('Observer', () {
    test('observer receives the exact comparison outcome', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor();

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      expect(observer.outcomes.length, 1);
      expect(observer.outcomes.first, isA<HealthTimelineShadowComparison>());
    });

    test('observer receives the exact failure outcome', () async {
      final observer = _RecordingObserver();
      final primary = _FakePrimarySource();
      final runner = _FakeShadowRunner();
      final executor = _FakeRunnerExecutor(
        resultToReturn: const HealthTimelineShadowRunnerTimedOut(
          elapsedMilliseconds: 5000,
        ),
        passthrough: false,
      );

      final source = ShadowComparingHealthTimelineSource.withRunner(
        primarySource: primary,
        runner: runner,
        observer: observer,
        runnerExecutor: executor,
      );

      await source.loadPage(_sampleQuery());
      await observer.waitForOutcome();

      expect(observer.outcomes.length, 1);
      expect(observer.outcomes.first, isA<HealthTimelineShadowFailure>());
    });

    test(
      'synchronous observer throw is absorbed without affecting primary',
      () async {
        final throwingObserver = _ThrowingObserver(isAsync: false);
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor();

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: throwingObserver,
          runnerExecutor: executor,
        );

        final page = await source.loadPage(_sampleQuery());
        expect(page, isNotNull);
      },
    );

    test(
      'asynchronous observer error is absorbed without affecting primary',
      () async {
        final throwingObserver = _ThrowingObserver(isAsync: true);
        final primary = _FakePrimarySource();
        final runner = _FakeShadowRunner();
        final executor = _FakeRunnerExecutor();

        final source = ShadowComparingHealthTimelineSource.withRunner(
          primarySource: primary,
          runner: runner,
          observer: throwingObserver,
          runnerExecutor: executor,
        );

        final page = await source.loadPage(_sampleQuery());
        expect(page, isNotNull);
      },
    );
  });

  group('Retrocompatibilidade', () {
    test(
      'legacy shadow source path remains unchanged and functional',
      () async {
        final primary = _FakePrimarySource();
        final shadow = _FakeShadowSource();
        final observer = _RecordingObserver();

        final source = ShadowComparingHealthTimelineSource(
          primarySource: primary,
          shadowSource: shadow,
          observer: observer,
        );

        final page = await source.loadPage(_sampleQuery());
        expect(page, isNotNull);
        await observer.waitForOutcome();

        expect(primary.calls, 1);
        expect(shadow.calls, 1);
        expect(observer.outcomes.length, 1);
        expect(observer.outcomes.first, isA<HealthTimelineShadowComparison>());
      },
    );
  });
}
