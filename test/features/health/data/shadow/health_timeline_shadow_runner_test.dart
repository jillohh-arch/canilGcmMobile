// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for Health Timeline Shadow Runner (4C-C-C-H1).
//
// Tests prove: result contracts, orchestration, success mapping,
// typed failure mapping, exception sanitization, and snapshot isolation.

import 'dart:async';

import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_id_deriver.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_shadow_bridge.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_source.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_runner.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake bridge for testing.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeComparator implements RawCanonicalNutritionShadowComparator {
  _FakeComparator({required this.result}) : error = null, isFutureError = false;

  _FakeComparator.syncThrow(this.error) : result = null, isFutureError = false;

  _FakeComparator.futureError(Object this.error)
    : result = null,
      isFutureError = true;

  final RawCanonicalNutritionShadowBridgeResult? result;
  final Object? error;
  final bool isFutureError;

  int calls = 0;
  HealthTimelineQuery? lastQuery;
  List<HealthTimelineEntryView>? lastPrimaryItems;

  @override
  Future<RawCanonicalNutritionShadowBridgeResult> compare({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    calls++;
    lastQuery = query;
    lastPrimaryItems = primaryItems;

    final err = error;
    if (err != null) {
      if (isFutureError) {
        final c = Completer<void>();
        c.completeError(err);
        await c.future;
      }
      throw err;
    }
    return result!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Builders.
// ─────────────────────────────────────────────────────────────────────────────

HealthTimelineEntryView _primaryEntry({
  required String id,
  String? sourceCollection,
  String? sourceId,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog1',
    type: HealthTimelineTypeView.parse('meal'),
    occurredAt: DateTime.utc(2024, 1, 1, 8),
    recordedAt: DateTime.utc(2024, 1, 1, 9),
    title: 'entry $id',
    status: HealthTimelineEntryStatus.finalised,
    traceability: sourceCollection != null || sourceId != null
        ? HealthTimelineTraceability(
            sourceCollection: sourceCollection,
            sourceId: sourceId,
          )
        : null,
  );
}

RawCanonicalNutritionShadowBridgeSuccess _bridgeSuccess({
  required int primaryCount,
  required int shadowCount,
  int matched = 0,
  int missing = 0,
  int extra = 0,
  int uncorrelatedPrimary = 0,
  int uncorrelatedShadow = 0,
  int ambiguousPrimary = 0,
  int ambiguousShadow = 0,
  bool orderingMismatch = false,
}) {
  return RawCanonicalNutritionShadowBridgeSuccess(
    correlation: HealthTimelineCorrelationResult(
      matchedPairs: List.generate(
        matched,
        (i) => HealthTimelineMatchedPair(primaryIndex: i, shadowIndex: i),
      ),
      missingPrimaryIndices: List.generate(missing, (i) => i),
      extraShadowIndices: List.generate(extra, (i) => i),
      ambiguousPrimaryIndices: List.generate(ambiguousPrimary, (i) => i),
      ambiguousShadowIndices: List.generate(ambiguousShadow, (i) => i),
      uncorrelatedPrimaryIndices: List.generate(uncorrelatedPrimary, (i) => i),
      uncorrelatedShadowIndices: List.generate(uncorrelatedShadow, (i) => i),
    ),
    orderingMismatch: orderingMismatch,
    primaryCount: primaryCount,
    shadowCount: shadowCount,
  );
}

HealthTimelineQuery _query() => HealthTimelineQuery(dogId: 'dog1');

// ─────────────────────────────────────────────────────────────────────────────
// Tests.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('HealthTimelineShadowRunResult contracts', () {
    test('1. success preserves every count and ordering flag', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 10,
          shadowCount: 9,
          matched: 8,
          missing: 2,
          extra: 1,
          uncorrelatedPrimary: 0,
          uncorrelatedShadow: 0,
          ambiguousPrimary: 0,
          ambiguousShadow: 0,
          orderingMismatch: true,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunSuccess>());
      final success = result as HealthTimelineShadowRunSuccess;

      expect(success.primaryCount, 10);
      expect(success.shadowCount, 9);
      expect(success.matchedCount, 8);
      expect(success.missingCount, 2);
      expect(success.extraCount, 1);
      expect(success.uncorrelatedPrimaryCount, 0);
      expect(success.uncorrelatedShadowCount, 0);
      expect(success.ambiguousPrimaryCount, 0);
      expect(success.ambiguousShadowCount, 0);
      expect(success.orderingMismatch, true);
    });

    test('2. failure preserves only the public failure kind', () async {
      final comparator = _FakeComparator(
        result: const RawCanonicalNutritionShadowBridgeFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunFailure>());
      final failure = result as HealthTimelineShadowRunFailure;

      expect(failure.kind, HealthTimelineShadowFailureKind.shadowFailure);
    });

    test(
      '3. result hierarchy supports exhaustive Success/Failure matching',
      () async {
        // Test that switch on the sealed class is exhaustive.
        // Success path.
        final successComparator = _FakeComparator(
          result: _bridgeSuccess(primaryCount: 1, shadowCount: 1),
        );
        final successRunner = HealthTimelineNutritionShadowRunner(
          comparator: successComparator,
        );
        final successResult = await successRunner.run(
          query: _query(),
          primaryItems: const [],
        );

        final successSwitchResult = switch (successResult) {
          HealthTimelineShadowRunSuccess() => 'success',
          HealthTimelineShadowRunFailure() => 'failure',
        };
        expect(successSwitchResult, 'success');

        // Failure path.
        final failureComparator = _FakeComparator(
          result: const RawCanonicalNutritionShadowBridgeFailure(
            kind: RawCanonicalNutritionSourceFailureKind
                .multipleReadersUnavailable,
          ),
        );
        final failureRunner = HealthTimelineNutritionShadowRunner(
          comparator: failureComparator,
        );
        final failureResult = await failureRunner.run(
          query: _query(),
          primaryItems: const [],
        );

        final failureSwitchResult = switch (failureResult) {
          HealthTimelineShadowRunSuccess() => 'success',
          HealthTimelineShadowRunFailure() => 'failure',
        };
        expect(failureSwitchResult, 'failure');
      },
    );
  });

  group('HealthTimelineNutritionShadowRunner orchestration', () {
    test('4. runner calls bridge exactly once', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 0, shadowCount: 0),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      await runner.run(query: _query(), primaryItems: const []);

      expect(comparator.calls, 1);
    });

    test('5. runner forwards the identical query instance', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 0, shadowCount: 0),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final query = _query();

      await runner.run(query: query, primaryItems: const []);

      expect(identical(comparator.lastQuery, query), isTrue);
    });

    test('6. runner forwards primary entries in original order', () async {
      final received = <List<HealthTimelineEntryView>>[];
      final capturingComparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 0, shadowCount: 0),
      );

      // Inject a capturing wrapper.
      final runner = _CapturingRunner(capturingComparator, received);
      final entries = [
        _primaryEntry(id: 'e1', sourceCollection: 'meal_logs', sourceId: 'p1'),
        _primaryEntry(id: 'e2', sourceCollection: 'meal_logs', sourceId: 'p2'),
        _primaryEntry(
          id: 'e3',
          sourceCollection: 'supplement_logs',
          sourceId: 'p3',
        ),
      ];

      await runner.run(query: _query(), primaryItems: entries);

      expect(received.single.length, 3);
      expect(received.single[0].id, 'e1');
      expect(received.single[1].id, 'e2');
      expect(received.single[2].id, 'e3');
    });

    test(
      '7. caller mutation after run starts does not affect primary snapshot',
      () async {
        final completer = Completer<RawCanonicalNutritionShadowBridgeResult>();
        final overridingComparator = _OverridingComparator(completer.future);

        final runner = HealthTimelineNutritionShadowRunner(
          comparator: overridingComparator,
        );

        final original = _primaryEntry(
          id: 'e1',
          sourceCollection: 'meal_logs',
          sourceId: 'p1',
        );
        final primaryItems = [original];

        final runFuture = runner.run(
          query: _query(),
          primaryItems: primaryItems,
        );

        // Mutate AFTER run was called, BEFORE it completes.
        primaryItems.clear();
        primaryItems.add(
          _primaryEntry(
            id: 'e2',
            sourceCollection: 'meal_logs',
            sourceId: 'p2',
          ),
        );

        // Complete the comparator with a dummy result.
        completer.complete(_bridgeSuccess(primaryCount: 1, shadowCount: 0));

        await runFuture;

        // The comparator must have received the snapshot of [original].
        expect(overridingComparator.receivedPrimaryItems!.length, 1);
        expect(
          overridingComparator
              .receivedPrimaryItems!
              .first
              .traceability
              ?.sourceId,
          'p1',
        );
      },
    );

    test('8. runner does not mutate caller primary list', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 0, shadowCount: 0),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final entries = [
        _primaryEntry(id: 'e1', sourceCollection: 'meal_logs', sourceId: 'm1'),
      ];

      await runner.run(query: _query(), primaryItems: entries);

      // The original list is unchanged.
      expect(entries.length, 1);
      expect(entries.first.id, 'e1');
    });
  });

  group('HealthTimelineNutritionShadowRunner success mapping', () {
    test('9. maps primaryCount', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 42, shadowCount: 0),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).primaryCount, 42);
    });

    test('10. maps shadowCount', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 0, shadowCount: 7),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).shadowCount, 7);
    });

    test('11. maps matchedCount', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(primaryCount: 5, shadowCount: 5, matched: 3),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).matchedCount, 3);
    });

    test('12. maps missingCount', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 10,
          shadowCount: 5,
          matched: 4,
          missing: 1,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).missingCount, 1);
    });

    test('13. maps extraCount', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 5,
          shadowCount: 10,
          matched: 4,
          extra: 2,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).extraCount, 2);
    });

    test('14. maps uncorrelated primary and shadow counts', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 6,
          shadowCount: 6,
          matched: 2,
          missing: 2,
          extra: 2,
          uncorrelatedPrimary: 1,
          uncorrelatedShadow: 1,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      final success = result as HealthTimelineShadowRunSuccess;
      expect(success.uncorrelatedPrimaryCount, 1);
      expect(success.uncorrelatedShadowCount, 1);
    });

    test('15. maps ambiguous primary and shadow counts', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 5,
          shadowCount: 5,
          matched: 0,
          ambiguousPrimary: 2,
          ambiguousShadow: 3,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      final success = result as HealthTimelineShadowRunSuccess;
      expect(success.ambiguousPrimaryCount, 2);
      expect(success.ambiguousShadowCount, 3);
    });

    test('16. maps orderingMismatch false', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 2,
          shadowCount: 2,
          matched: 2,
          orderingMismatch: false,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(
        (result as HealthTimelineShadowRunSuccess).orderingMismatch,
        false,
      );
    });

    test('17. maps orderingMismatch true', () async {
      final comparator = _FakeComparator(
        result: _bridgeSuccess(
          primaryCount: 2,
          shadowCount: 2,
          matched: 2,
          orderingMismatch: true,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect((result as HealthTimelineShadowRunSuccess).orderingMismatch, true);
    });
  });

  group('HealthTimelineNutritionShadowRunner typed failure mapping', () {
    test('18. mealReaderUnavailable maps to shadowFailure', () async {
      final comparator = _FakeComparator(
        result: const RawCanonicalNutritionShadowBridgeFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunFailure>());
      expect(
        (result as HealthTimelineShadowRunFailure).kind,
        HealthTimelineShadowFailureKind.shadowFailure,
      );
    });

    test('19. supplementReaderUnavailable maps to shadowFailure', () async {
      final comparator = _FakeComparator(
        result: const RawCanonicalNutritionShadowBridgeFailure(
          kind: RawCanonicalNutritionSourceFailureKind
              .supplementReaderUnavailable,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunFailure>());
      expect(
        (result as HealthTimelineShadowRunFailure).kind,
        HealthTimelineShadowFailureKind.shadowFailure,
      );
    });

    test('20. multipleReadersUnavailable maps to shadowFailure', () async {
      final comparator = _FakeComparator(
        result: const RawCanonicalNutritionShadowBridgeFailure(
          kind:
              RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunFailure>());
      expect(
        (result as HealthTimelineShadowRunFailure).kind,
        HealthTimelineShadowFailureKind.shadowFailure,
      );
    });

    test('21. mergeInvariantFailed maps to shadowFailure', () async {
      final comparator = _FakeComparator(
        result: const RawCanonicalNutritionShadowBridgeFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
        ),
      );

      final runner = HealthTimelineNutritionShadowRunner(
        comparator: comparator,
      );
      final result = await runner.run(query: _query(), primaryItems: const []);

      expect(result, isA<HealthTimelineShadowRunFailure>());
      expect(
        (result as HealthTimelineShadowRunFailure).kind,
        HealthTimelineShadowFailureKind.shadowFailure,
      );
    });
  });

  group('HealthTimelineNutritionShadowRunner exception sanitization', () {
    test(
      '22. synchronous bridge exception maps to comparatorFailure',
      () async {
        final comparator = _FakeComparator.syncThrow(
          StateError('comparator sync boom'),
        );

        final runner = HealthTimelineNutritionShadowRunner(
          comparator: comparator,
        );
        final result = await runner.run(
          query: _query(),
          primaryItems: const [],
        );

        expect(result, isA<HealthTimelineShadowRunFailure>());
        expect(
          (result as HealthTimelineShadowRunFailure).kind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
      },
    );

    test(
      '23. asynchronous bridge exception maps to comparatorFailure',
      () async {
        final comparator = _FakeComparator.futureError(
          Exception('comparator async boom'),
        );

        final runner = HealthTimelineNutritionShadowRunner(
          comparator: comparator,
        );
        final result = await runner.run(
          query: _query(),
          primaryItems: const [],
        );

        expect(result, isA<HealthTimelineShadowRunFailure>());
        expect(
          (result as HealthTimelineShadowRunFailure).kind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
      },
    );

    test(
      '24. ineligible query ArgumentError maps to comparatorFailure',
      () async {
        final comparator = _FakeComparator.syncThrow(
          ArgumentError.value(null, 'query', 'ineligible'),
        );

        final runner = HealthTimelineNutritionShadowRunner(
          comparator: comparator,
        );
        final result = await runner.run(
          query: _query(),
          primaryItems: const [],
        );

        expect(result, isA<HealthTimelineShadowRunFailure>());
        expect(
          (result as HealthTimelineShadowRunFailure).kind,
          HealthTimelineShadowFailureKind.comparatorFailure,
        );
      },
    );
  });

  group('RawCanonicalNutritionShadowBridgeAdapter integration', () {
    test(
      '25. adapter forwards the identical query to the real bridge pipeline',
      () async {
        final queryLog = <HealthTimelineQuery>[];
        final capturingSource = _CountingRawSource((query) {
          queryLog.add(query);
          return Future.value(_rawSuccessEmpty());
        });

        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: capturingSource,
        );
        final adapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: bridge,
        );

        final query = _query();
        const entries = <HealthTimelineEntryView>[];

        await adapter.compare(query: query, primaryItems: entries);

        expect(queryLog.length, 1);
        expect(identical(queryLog.first, query), isTrue);
      },
    );

    test(
      '26. adapter preserves primary comparable order through the real bridge',
      () async {
        final capturedPrimaryItems = <List<HealthTimelineComparableItem>>[];

        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: _CountingRawSource(
            (_) => Future.value(_rawSuccessEmpty()),
          ),
          correlate:
              ({
                required List<HealthTimelineComparableItem> primaryItems,
                required List<HealthTimelineComparableItem> shadowItems,
              }) {
                capturedPrimaryItems.add(primaryItems);
                return _zeroCorrelation(
                  primaryItems.length,
                  shadowItems.length,
                );
              },
        );
        final adapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: bridge,
        );

        final entries = [
          _primaryEntry(id: 'e1', sourceCollection: 'meal_logs', sourceId: 'A'),
          _primaryEntry(id: 'e2', sourceCollection: 'meal_logs', sourceId: 'B'),
          _primaryEntry(
            id: 'e3',
            sourceCollection: 'supplement_logs',
            sourceId: 'C',
          ),
        ];

        await adapter.compare(query: _query(), primaryItems: entries);

        expect(capturedPrimaryItems.length, 1);
        final captured = capturedPrimaryItems.single;
        expect(captured.length, 3);
        expect(captured[0].sourceId, 'A');
        expect(captured[1].sourceId, 'B');
        expect(captured[2].sourceId, 'C');
      },
    );

    test(
      '27. adapter invokes the underlying bridge pipeline exactly once',
      () async {
        var rawSourceCalls = 0;
        var correlatorCalls = 0;
        var detectorCalls = 0;

        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: _CountingRawSource((_) {
            rawSourceCalls++;
            return Future.value(_rawSuccessEmpty());
          }),
          correlate:
              ({
                required List<HealthTimelineComparableItem> primaryItems,
                required List<HealthTimelineComparableItem> shadowItems,
              }) {
                correlatorCalls++;
                return _zeroCorrelation(
                  primaryItems.length,
                  shadowItems.length,
                );
              },
          detectOrderingMismatch:
              ({required List<HealthTimelineMatchedPair> matchedPairs}) {
                detectorCalls++;
                return false;
              },
        );
        final adapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: bridge,
        );

        await adapter.compare(query: _query(), primaryItems: const []);

        expect(rawSourceCalls, 1);
        expect(correlatorCalls, 1);
        expect(detectorCalls, 1);
      },
    );

    test(
      '28. adapter returns bridge success semantics without alteration',
      () async {
        // Inject a correlator that produces all distinct, non-trivial values
        // to detect any field omission, inversion, fixed value, swap, or loss.
        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: _CountingRawSource(
            (_) => Future.value(_rawSuccessTwelveEntries()),
          ),
          correlate:
              ({
                required List<HealthTimelineComparableItem> primaryItems,
                required List<HealthTimelineComparableItem> shadowItems,
              }) {
                // Correlator configured for 10 primary / 12 shadow.
                return HealthTimelineCorrelationResult(
                  matchedPairs: [
                    HealthTimelineMatchedPair(primaryIndex: 0, shadowIndex: 0),
                  ],
                  missingPrimaryIndices: [1, 2],
                  extraShadowIndices: [3, 4, 5, 6, 7],
                  ambiguousPrimaryIndices: [3, 4, 5],
                  ambiguousShadowIndices: [8, 9],
                  uncorrelatedPrimaryIndices: [1, 2, 3, 4],
                  uncorrelatedShadowIndices: [1, 2, 3, 4],
                );
              },
          detectOrderingMismatch:
              ({required List<HealthTimelineMatchedPair> matchedPairs}) => true,
        );
        final adapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: bridge,
        );

        // 10 primary entries to produce primaryCount = 10.
        final entries = List.generate(
          10,
          (i) => _primaryEntry(
            id: 'e$i',
            sourceCollection: 'meal_logs',
            sourceId: 'p$i',
          ),
        );

        final result = await adapter.compare(
          query: _query(),
          primaryItems: entries,
        );

        expect(result, isA<RawCanonicalNutritionShadowBridgeSuccess>());
        final success = result as RawCanonicalNutritionShadowBridgeSuccess;

        // All fields verified against the injected correlator values.
        expect(success.primaryCount, 10);
        expect(success.shadowCount, 12);
        expect(success.correlation.matchedCount, 1);
        expect(success.correlation.missingCount, 2);
        expect(success.correlation.extraCount, 5);
        expect(success.correlation.uncorrelatedPrimaryCount, 4);
        expect(success.correlation.uncorrelatedShadowCount, 4);
        expect(success.correlation.ambiguousPrimaryCount, 3);
        expect(success.correlation.ambiguousShadowCount, 2);
        expect(success.orderingMismatch, true);

        // No field omitted, inverted, fixed, swapped, or lost.
      },
    );

    test(
      '29. adapter propagates synchronous and asynchronous bridge exceptions',
      () async {
        // Sync exception from raw source.
        final syncBridge = RawCanonicalNutritionShadowBridge(
          rawSource: _CountingRawSource((_) {
            throw StateError('raw source sync boom');
          }),
        );
        final syncAdapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: syncBridge,
        );

        expect(
          () => syncAdapter.compare(query: _query(), primaryItems: const []),
          throwsA(isA<StateError>()),
        );

        // Async exception from raw source.
        final asyncBridge = RawCanonicalNutritionShadowBridge(
          rawSource: _CountingRawSource((_) {
            final completer = Completer<RawCanonicalNutritionFirstPageResult>();
            completer.completeError(Exception('raw source async boom'));
            return completer.future;
          }),
        );
        final asyncAdapter = RawCanonicalNutritionShadowBridgeAdapter(
          bridge: asyncBridge,
        );

        await expectLater(
          () => asyncAdapter.compare(query: _query(), primaryItems: const []),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper classes for orchestration tests.
// ─────────────────────────────────────────────────────────────────────────────

class _OverridingComparator implements RawCanonicalNutritionShadowComparator {
  _OverridingComparator(this.future);

  final Future<RawCanonicalNutritionShadowBridgeResult> future;

  List<HealthTimelineEntryView>? receivedPrimaryItems;

  @override
  Future<RawCanonicalNutritionShadowBridgeResult> compare({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    receivedPrimaryItems = primaryItems;
    return future;
  }
}

class _CapturingRunner implements HealthTimelineShadowRunner {
  _CapturingRunner(this._comparator, this._received);

  final RawCanonicalNutritionShadowComparator _comparator;
  final List<List<HealthTimelineEntryView>> _received;

  @override
  Future<HealthTimelineShadowRunResult> run({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    final snapshot = List<HealthTimelineEntryView>.unmodifiable(primaryItems);
    _received.add(snapshot);

    final result = await _comparator.compare(
      query: query,
      primaryItems: snapshot,
    );

    return switch (result) {
      RawCanonicalNutritionShadowBridgeSuccess() =>
        HealthTimelineShadowRunSuccess(
          primaryCount: result.primaryCount,
          shadowCount: result.shadowCount,
          matchedCount: result.correlation.matchedCount,
          missingCount: result.correlation.missingCount,
          extraCount: result.correlation.extraCount,
          uncorrelatedPrimaryCount: result.correlation.uncorrelatedPrimaryCount,
          uncorrelatedShadowCount: result.correlation.uncorrelatedShadowCount,
          ambiguousPrimaryCount: result.correlation.ambiguousPrimaryCount,
          ambiguousShadowCount: result.correlation.ambiguousShadowCount,
          orderingMismatch: result.orderingMismatch,
        ),
      RawCanonicalNutritionShadowBridgeFailure() =>
        const HealthTimelineShadowRunFailure(
          kind: HealthTimelineShadowFailureKind.shadowFailure,
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fakes for RawCanonicalNutritionShadowBridgeAdapter integration tests.
// ─────────────────────────────────────────────────────────────────────────────

/// Counts calls to the raw source.
class _CountingRawSource implements RawCanonicalNutritionFirstPageSource {
  _CountingRawSource(this._load);

  final Future<RawCanonicalNutritionFirstPageResult> Function(
    HealthTimelineQuery query,
  )
  _load;

  @override
  Future<RawCanonicalNutritionFirstPageResult> loadFirstPage(
    HealthTimelineQuery query,
  ) => _load(query);
}

HealthTimelineCorrelationResult _zeroCorrelation(int primary, int shadow) {
  return HealthTimelineCorrelationResult(
    matchedPairs: const [],
    missingPrimaryIndices: const [],
    extraShadowIndices: const [],
    ambiguousPrimaryIndices: const [],
    ambiguousShadowIndices: const [],
    uncorrelatedPrimaryIndices: List.generate(primary, (i) => i),
    uncorrelatedShadowIndices: List.generate(shadow, (i) => i),
  );
}

RawCanonicalNutritionFirstPageResult _rawSuccessEmpty() {
  return RawCanonicalNutritionFirstPageSuccess(
    page: RawCanonicalNutritionFirstPage(entries: const [], hasMore: false),
  );
}

RawCanonicalNutritionFirstPageResult _rawSuccessTwelveEntries() {
  return RawCanonicalNutritionFirstPageSuccess(
    page: RawCanonicalNutritionFirstPage(
      entries: List<RawCanonicalNutritionComparableEntry>.unmodifiable(
        List.generate(
          12,
          (i) => RawCanonicalNutritionComparableEntry(
            dogId: 'dog1',
            sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 's$i',
            occurredAt: DateTime.utc(2024, 1, 1),
            derivedTimelineId: deriveCanonicalHealthTimelineId(
              dogId: 'dog1',
              sourceCollection:
                  CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 's$i',
            ),
          ),
        ),
      ),
      hasMore: false,
    ),
  );
}
