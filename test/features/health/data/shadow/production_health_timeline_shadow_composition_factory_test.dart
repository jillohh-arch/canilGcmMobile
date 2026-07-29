// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for ProductionHealthTimelineShadowCompositionFactory (4C-C-C-H3B1).
//
// Exactly 12 test declarations. Zero functional timing / wall-clock delays.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner_executor.dart';
import 'package:canil_gcm/features/health/data/shadow/production_health_timeline_shadow_composition_factory.dart';
import 'package:canil_gcm/features/health/data/shadow/shadow_comparing_health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test Fakes — Zero wall-clock delays.
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _recordedBy() => {
  'uid': 'u1',
  'name': 'Condutor',
  'internal_role': 'condutor',
};

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

void main() {
  final sampleQuery = HealthTimelineQuery(dogId: 'dog-123');

  group('Construção', () {
    test(
      'forFirestore returns a health timeline shadow composition factory',
      () {
        final fakeFirestore = FakeFirebaseFirestore();
        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
            );

        expect(factory, isA<HealthTimelineShadowCompositionFactory>());
      },
    );

    test('forFirestore performs no Firestore reads during construction', () {
      final fakeFirestore = FakeFirebaseFirestore();
      final observer = _RecordingObserver();
      final executor = _FakeRunnerExecutor();

      ProductionHealthTimelineShadowCompositionFactory.forFirestore(
        firestore: fakeFirestore,
        observer: observer,
        runnerExecutor: executor,
      );

      expect(observer.outcomes, isEmpty);
      expect(executor.calls, 0);
    });
  });

  group('Modos fail-closed', () {
    test(
      'legacyOnly creates a coexistence source using the injected Firestore',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
            );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.legacyOnly,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        expect(source, isA<CoexistenceHealthTimelineSource>());
        expect(source, isNot(isA<ShadowComparingHealthTimelineSource>()));

        final page = await source.loadPage(sampleQuery);
        expect(page.items, isEmpty);
      },
    );

    test('legacyOnly performs no canonical shadow read', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final observer = _RecordingObserver();
      final executor = _FakeRunnerExecutor();

      final factory =
          ProductionHealthTimelineShadowCompositionFactory.forFirestore(
            firestore: fakeFirestore,
            observer: observer,
            runnerExecutor: executor,
          );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      await source.loadPage(sampleQuery);

      expect(observer.outcomes, isEmpty);
      expect(executor.calls, 0);
    });

    test('canonicalPrimary creates a coexistence source fail-closed', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final factory =
          ProductionHealthTimelineShadowCompositionFactory.forFirestore(
            firestore: fakeFirestore,
          );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(source, isA<CoexistenceHealthTimelineSource>());
      expect(source, isNot(isA<ShadowComparingHealthTimelineSource>()));

      final page = await source.loadPage(sampleQuery);
      expect(page.items, isEmpty);
    });

    test('canonicalPrimary performs no canonical shadow read', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final observer = _RecordingObserver();
      final executor = _FakeRunnerExecutor();

      final factory =
          ProductionHealthTimelineShadowCompositionFactory.forFirestore(
            firestore: fakeFirestore,
            observer: observer,
            runnerExecutor: executor,
          );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      await source.loadPage(sampleQuery);

      expect(observer.outcomes, isEmpty);
      expect(executor.calls, 0);
    });
  });

  group('Shadow composition', () {
    test('shadowCompare creates a shadow comparing source', () {
      final fakeFirestore = FakeFirebaseFirestore();
      final factory =
          ProductionHealthTimelineShadowCompositionFactory.forFirestore(
            firestore: fakeFirestore,
          );

      final source = factory.createForResolution(
        const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        ),
      );

      expect(source, isA<ShadowComparingHealthTimelineSource>());
    });

    test(
      'shadowCompare uses the injected Firestore without requiring a default Firebase app',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(passthrough: true);

        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
              observer: observer,
              runnerExecutor: executor,
            );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        final page = await source.loadPage(sampleQuery);
        expect(page, isNotNull);
        await observer.waitForOutcome();

        expect(executor.calls, 1);
        expect(observer.outcomes.length, 1);
      },
    );
  });

  group('Cadeia canônica', () {
    test(
      'shadowCompare empty canonical collections emit a zero-count comparison',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(passthrough: true);

        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
              observer: observer,
              runnerExecutor: executor,
            );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        await source.loadPage(sampleQuery);
        await observer.waitForOutcome();

        final outcome = observer.outcomes.single;
        expect(outcome, isA<HealthTimelineShadowComparison>());

        final comparison = outcome as HealthTimelineShadowComparison;
        expect(comparison.shadowCount, 0);
        expect(comparison.primaryCount, 0);
      },
    );

    test(
      'shadowCompare canonical meal fixture contributes to the shadow comparison',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(passthrough: true);

        await fakeFirestore
            .collection('dogs')
            .doc('dog-123')
            .collection('meal_logs')
            .doc('meal-1')
            .set({
              'dog_id': 'dog-123',
              'fed_at': Timestamp.fromDate(DateTime.utc(2026, 7, 15, 12)),
              'offered_grams': 150,
              'period': 'morning',
              'acceptance': 'full',
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });

        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
              observer: observer,
              runnerExecutor: executor,
            );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        await source.loadPage(sampleQuery);
        await observer.waitForOutcome();

        final outcome = observer.outcomes.single;
        expect(outcome, isA<HealthTimelineShadowComparison>());

        final comparison = outcome as HealthTimelineShadowComparison;
        expect(comparison.shadowCount, 1);
        expect(comparison.extraCount, 1);
      },
    );

    test(
      'shadowCompare canonical supplement fixture contributes to the shadow comparison',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(passthrough: true);

        await fakeFirestore
            .collection('dogs')
            .doc('dog-123')
            .collection('supplement_logs')
            .doc('supp-1')
            .set({
              'dog_id': 'dog-123',
              'supplement_name': 'Ômega 3',
              'dose': 5,
              'unit': 'ml',
              'administered_at': Timestamp.fromDate(
                DateTime.utc(2026, 7, 15, 14),
              ),
              'recorded_by': _recordedBy(),
              'schema_version': 1,
              'revision': 1,
            });

        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
              observer: observer,
              runnerExecutor: executor,
            );

        final source = factory.createForResolution(
          const HealthTimelineModeResolution(
            mode: HealthTimelineMode.shadowCompare,
            kind: HealthTimelineModeResolutionKind.configured,
          ),
        );

        await source.loadPage(sampleQuery);
        await observer.waitForOutcome();

        final outcome = observer.outcomes.single;
        expect(outcome, isA<HealthTimelineShadowComparison>());

        final comparison = outcome as HealthTimelineShadowComparison;
        expect(comparison.shadowCount, 1);
        expect(comparison.extraCount, 1);
      },
    );

    test(
      'shadowCompare forwards configured timeout executor and observer',
      () async {
        const configuredTimeout = Duration(seconds: 42);
        const configuredLatency = 987;
        final fakeFirestore = FakeFirebaseFirestore();
        final observer = _RecordingObserver();
        final executor = _FakeRunnerExecutor(
          passthrough: true,
          elapsedMilliseconds: configuredLatency,
        );

        final factory =
            ProductionHealthTimelineShadowCompositionFactory.forFirestore(
              firestore: fakeFirestore,
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

        final page = await source.loadPage(sampleQuery);
        expect(page, isNotNull);
        await observer.waitForOutcome();

        expect(executor.calls, 1);
        expect(executor.receivedTimeout, equals(configuredTimeout));
        expect(observer.outcomes.length, 1);

        final outcome = observer.outcomes.single;
        expect(outcome, isA<HealthTimelineShadowComparison>());

        final comparison = outcome as HealthTimelineShadowComparison;
        expect(comparison.shadowLatencyMs, equals(configuredLatency));
      },
    );
  });
}
