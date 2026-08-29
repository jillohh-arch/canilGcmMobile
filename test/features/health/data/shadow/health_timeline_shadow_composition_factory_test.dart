// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for HealthTimelineShadowCompositionFactory (4C-C-C-H3A).
//
// Exactly 16 test declarations. Zero functional timing / wall-clock delays.

import 'dart:async';

import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_composition_factory.dart';
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
// Test Fakes — Zero wall-clock delays.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeHealthTimelineSource implements HealthTimelineSource {
  _FakeHealthTimelineSource({this.pageToReturn, this.completer});

  final HealthTimelinePage? pageToReturn;
  final Completer<HealthTimelinePage>? completer;

  int calls = 0;
  HealthTimelineQuery? receivedQuery;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) {
    calls++;
    receivedQuery = query;

    final comp = completer;
    if (comp != null) return comp.future;

    return Future.value(
      pageToReturn ??
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
  _FakeRunnerExecutor({this.passthrough = true, this.elapsedMilliseconds = 10});

  final bool passthrough;
  final int elapsedMilliseconds;

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

    HealthTimelineShadowRunResult? runResult;
    if (passthrough) {
      runResult = await operation();
    }

    return HealthTimelineShadowRunnerCompleted(
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
      elapsedMilliseconds: elapsedMilliseconds,
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
  group('Legacy e defaults', () {
    test('legacyOnly returns the identical coexistence source', () {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final result = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(identical(result, coexistenceSource), isTrue);
    });

    test('legacyOnly invokes coexistence source factory exactly once', () {
      int coexistenceCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () {
          coexistenceCalls++;
          return coexistenceSource;
        },
        runnerFactory: () => runner,
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(coexistenceCalls, 1);
    });

    test('legacyOnly does not invoke runner factory', () {
      int runnerFactoryCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () {
          runnerFactoryCalls++;
          return runner;
        },
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(runnerFactoryCalls, 0);
    });

    test(
      'missingDefault resolution returns coexistence fail-closed without runner',
      () {
        int runnerFactoryCalls = 0;
        final coexistenceSource = _FakeHealthTimelineSource();
        final runner = _FakeShadowRunner();

        final resolution = HealthTimelineModeResolution.parse(null);
        expect(
          resolution.kind,
          HealthTimelineModeResolutionKind.missingDefault,
        );
        expect(resolution.mode, HealthTimelineMode.legacyOnly);

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () {
            runnerFactoryCalls++;
            return runner;
          },
        );

        final result = factory.createForResolution(resolution);

        expect(identical(result, coexistenceSource), isTrue);
        expect(runnerFactoryCalls, 0);
      },
    );

    test(
      'invalidDefault resolution returns coexistence fail-closed without runner',
      () {
        int runnerFactoryCalls = 0;
        final coexistenceSource = _FakeHealthTimelineSource();
        final runner = _FakeShadowRunner();

        final resolution = HealthTimelineModeResolution.parse(
          'invalid_wire_mode',
        );
        expect(
          resolution.kind,
          HealthTimelineModeResolutionKind.invalidDefault,
        );
        expect(resolution.mode, HealthTimelineMode.legacyOnly);

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () {
            runnerFactoryCalls++;
            return runner;
          },
        );

        final result = factory.createForResolution(resolution);

        expect(identical(result, coexistenceSource), isTrue);
        expect(runnerFactoryCalls, 0);
      },
    );
  });

  group('Canonical fail-closed', () {
    test('canonicalPrimary returns the identical coexistence source', () {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final result = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(identical(result, coexistenceSource), isTrue);
    });

    test(
      'canonicalPrimary invokes coexistence source factory exactly once',
      () {
        int coexistenceCalls = 0;
        final coexistenceSource = _FakeHealthTimelineSource();
        final runner = _FakeShadowRunner();

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () {
            coexistenceCalls++;
            return coexistenceSource;
          },
          runnerFactory: () => runner,
        );

        factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.canonicalPrimary,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        expect(coexistenceCalls, 1);
      },
    );

    test('canonicalPrimary does not invoke runner factory', () {
      int runnerFactoryCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () {
          runnerFactoryCalls++;
          return runner;
        },
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(runnerFactoryCalls, 0);
    });
  });

  group('Shadow composition', () {
    test('shadowCompare returns a shadow comparing source', () {
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final result = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(result, isA<ShadowComparingHealthTimelineSource>());
    });

    test('shadowCompare invokes coexistence source factory exactly once', () {
      int coexistenceCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () {
          coexistenceCalls++;
          return coexistenceSource;
        },
        runnerFactory: () => runner,
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(coexistenceCalls, 1);
    });

    test('shadowCompare invokes runner factory exactly once', () {
      int runnerFactoryCalls = 0;
      final coexistenceSource = _FakeHealthTimelineSource();
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () {
          runnerFactoryCalls++;
          return runner;
        },
      );

      factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(runnerFactoryCalls, 1);
    });
  });

  group('Shadow integration', () {
    test('shadowCompare preserves the identical primary page', () async {
      final expectedPage = HealthTimelinePage(
        items: [_sampleItem('1'), _sampleItem('2')],
        nextCursor: HealthTimelineCursor('token-xyz'),
        hasMore: true,
      );
      final coexistenceSource = _FakeHealthTimelineSource(
        pageToReturn: expectedPage,
      );
      final runner = _FakeShadowRunner();

      final factory = HealthTimelineShadowCompositionFactory(
        coexistenceSourceFactory: () => coexistenceSource,
        runnerFactory: () => runner,
      );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      final resultPage = await source.loadPage(_sampleQuery());

      expect(identical(resultPage, expectedPage), isTrue);
      expect(resultPage.items, equals(expectedPage.items));
      expect(resultPage.nextCursor?.token, equals('token-xyz'));
      expect(resultPage.hasMore, isTrue);
    });

    test(
      'shadowCompare does not invoke runner before primary success',
      () async {
        final primaryCompleter = Completer<HealthTimelinePage>();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(passthrough: true);
        final coexistenceSource = _FakeHealthTimelineSource(
          completer: primaryCompleter,
        );
        final runner = _FakeShadowRunner();
        final expectedPage = HealthTimelinePage(
          items: const [],
          nextCursor: null,
          hasMore: false,
        );

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: observer,
          runnerExecutor: executor,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        final pageFuture = source.loadPage(_sampleQuery());

        expect(coexistenceSource.calls, 1);
        expect(executor.calls, 0);
        expect(runner.calls, 0);

        primaryCompleter.complete(expectedPage);

        final returnedPage = await pageFuture;
        await observer.waitForOutcome();

        expect(identical(returnedPage, expectedPage), isTrue);
        expect(executor.calls, 1);
        expect(runner.calls, 1);
        expect(observer.outcomes.length, 1);
      },
    );

    test(
      'shadowCompare invokes runner exactly once after primary success',
      () async {
        final primaryCompleter = Completer<HealthTimelinePage>();
        final observer = _RecordingObserver();
        final coexistenceSource = _FakeHealthTimelineSource(
          completer: primaryCompleter,
        );
        final runner = _FakeShadowRunner();

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: observer,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        unawaited(source.loadPage(_sampleQuery()));
        expect(runner.calls, 0);

        primaryCompleter.complete(
          HealthTimelinePage(items: const [], nextCursor: null, hasMore: false),
        );
        await observer.waitForOutcome();

        expect(runner.calls, 1);
      },
    );

    test(
      'shadowCompare forwards the identical query and primary items to runner',
      () async {
        final items = [_sampleItem('x'), _sampleItem('y')];
        final expectedPage = HealthTimelinePage(
          items: items,
          nextCursor: null,
          hasMore: false,
        );
        final observer = _RecordingObserver();
        final coexistenceSource = _FakeHealthTimelineSource(
          pageToReturn: expectedPage,
        );
        final runner = _FakeShadowRunner();
        final query = _sampleQuery();

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: observer,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        await source.loadPage(query);
        await observer.waitForOutcome();

        expect(identical(runner.receivedQuery, query), isTrue);
        expect(runner.receivedPrimaryItems, equals(items));
      },
    );

    test(
      'shadowCompare forwards configured timeout executor and observer outcome',
      () async {
        const configuredTimeout = Duration(seconds: 37);
        const configuredLatency = 321;
        const expectedRunSuccess = HealthTimelineShadowRunSuccess(
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

        final expectedPage = HealthTimelinePage(
          items: [_sampleItem('1')],
          nextCursor: null,
          hasMore: false,
        );
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(
          passthrough: true,
          elapsedMilliseconds: configuredLatency,
        );
        final coexistenceSource = _FakeHealthTimelineSource(
          pageToReturn: expectedPage,
        );
        final runner = _FakeShadowRunner(resultToReturn: expectedRunSuccess);

        final factory = HealthTimelineShadowCompositionFactory(
          coexistenceSourceFactory: () => coexistenceSource,
          runnerFactory: () => runner,
          observer: observer,
          runnerExecutor: executor,
          shadowTimeout: configuredTimeout,
        );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        final returnedPage = await source.loadPage(_sampleQuery());

        expect(identical(returnedPage, expectedPage), isTrue);
        await observer.waitForOutcome();

        expect(executor.calls, 1);
        expect(runner.calls, 1);
        expect(executor.receivedTimeout, equals(configuredTimeout));
        expect(observer.outcomes.length, 1);

        final outcome = observer.outcomes.single;
        expect(outcome, isA<HealthTimelineShadowComparison>());

        final comparison = outcome as HealthTimelineShadowComparison;
        expect(comparison.shadowLatencyMs, configuredLatency);
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
      },
    );
  });
}
