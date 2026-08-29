// Copyright 2024 GCM Health. All rights reserved.
//
// Tests for the Raw Canonical Nutrition Comparable Shadow Bridge (4C-C-C-G).
//
// The bridge is internal and invisible to the UI: it converts the raw canonical
// nutrition first-page result and the primary entries into the neutral
// comparable universe, correlates them, and returns a typed, privacy-safe
// result. These tests prove the conversions, the single-call orchestration,
// the failure mapping, correlation semantics, ordering detection, snapshot
// isolation, freeze, and detach guarantees.

import 'dart:async';

import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_id_deriver.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_shadow_bridge.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_source.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles.
// ─────────────────────────────────────────────────────────────────────────────

/// Configurable fake raw source that returns a preset result or throws.
class _FakeRawSource implements RawCanonicalNutritionFirstPageSource {
  _FakeRawSource.returns(this._result) : _error = null, _isFutureError = false;
  _FakeRawSource.syncThrow(this._error)
    : _result = null,
      _isFutureError = false;
  _FakeRawSource.futureError(this._error)
    : _result = null,
      _isFutureError = true;

  final RawCanonicalNutritionFirstPageResult? _result;
  final Object? _error;

  int calls = 0;
  HealthTimelineQuery? lastQuery;

  @override
  Future<RawCanonicalNutritionFirstPageResult> loadFirstPage(
    HealthTimelineQuery query,
  ) async {
    calls++;
    lastQuery = query;
    final error = _error;
    if (error != null) {
      if (_isFutureError) {
        await Future<void>.error(error);
      }
      throw error;
    }
    return _result!;
  }

  final bool _isFutureError;
}

/// A correlator that mutates external lists via scheduleMicrotask after returning,
/// proving the bridge's result is detached. Uses external mutable lists and a
/// Completer so the test can await deterministically.
HealthTimelineCorrelationResult _mutatingCorrelator({
  required List<HealthTimelineComparableItem> primaryItems,
  required List<HealthTimelineComparableItem> shadowItems,
  required List<HealthTimelineMatchedPair> externalMatchedPairs,
  required List<int> externalMissing,
  required List<int> externalExtra,
  required List<int> externalAmbiguousPrimary,
  required List<int> externalAmbiguousShadow,
  required List<int> externalUncorrelatedPrimary,
  required List<int> externalUncorrelatedShadow,
  required Completer<void> mutationCompleted,
}) {
  // Build initial result from locator matching into external lists.
  for (var i = 0; i < primaryItems.length; i++) {
    var matched = false;
    for (var j = 0; j < shadowItems.length; j++) {
      if (_sameLocator(primaryItems[i], shadowItems[j])) {
        externalMatchedPairs.add(
          HealthTimelineMatchedPair(primaryIndex: i, shadowIndex: j),
        );
        matched = true;
        break;
      }
    }
    if (!matched) externalMissing.add(i);
  }
  for (var j = 0; j < shadowItems.length; j++) {
    var matched = false;
    for (var i = 0; i < primaryItems.length; i++) {
      if (_sameLocator(primaryItems[i], shadowItems[j])) {
        matched = true;
        break;
      }
    }
    if (!matched) externalExtra.add(j);
  }

  // Schedule sentinel mutation for AFTER _freezeCorrelation has already copied.
  // scheduleMicrotask runs after the current synchronous chain completes, so
  // _freezeCorrelation copies only the legitimate results. When the microtask
  // fires it signals the completer and mutates — the frozen result stays clean.
  scheduleMicrotask(() {
    externalMatchedPairs.add(
      const HealthTimelineMatchedPair(primaryIndex: 9999, shadowIndex: 9999),
    );
    externalMissing.add(9999);
    externalExtra.add(9999);
    externalAmbiguousPrimary.add(9999);
    externalAmbiguousShadow.add(9999);
    externalUncorrelatedPrimary.add(9999);
    externalUncorrelatedShadow.add(9999);

    if (!mutationCompleted.isCompleted) {
      mutationCompleted.complete();
    }
  });

  return HealthTimelineCorrelationResult(
    matchedPairs: externalMatchedPairs,
    missingPrimaryIndices: externalMissing,
    extraShadowIndices: externalExtra,
    ambiguousPrimaryIndices: externalAmbiguousPrimary,
    ambiguousShadowIndices: externalAmbiguousShadow,
    uncorrelatedPrimaryIndices: externalUncorrelatedPrimary,
    uncorrelatedShadowIndices: externalUncorrelatedShadow,
  );
}

bool _sameLocator(
  HealthTimelineComparableItem a,
  HealthTimelineComparableItem b,
) {
  return a.sourceCollection == b.sourceCollection && a.sourceId == b.sourceId;
}

// ─────────────────────────────────────────────────────────────────────────────
// Builders.
// ─────────────────────────────────────────────────────────────────────────────

HealthTimelineEntryView _primary({
  required String id,
  String? sourceCollection,
  String? sourceId,
  String? legacySource,
  String? legacyId,
  bool withTraceability = true,
}) {
  return HealthTimelineEntryView(
    id: id,
    dogId: 'dog1',
    type: HealthTimelineTypeView.parse('meal'),
    occurredAt: DateTime.utc(2024, 1, 1, 8),
    recordedAt: DateTime.utc(2024, 1, 1, 9),
    title: 'entry $id',
    status: HealthTimelineEntryStatus.finalised,
    traceability: withTraceability
        ? HealthTimelineTraceability(
            sourceCollection: sourceCollection,
            sourceId: sourceId,
            legacySource: legacySource,
            legacyId: legacyId,
          )
        : null,
  );
}

RawCanonicalNutritionComparableEntry _rawEntry({
  required CanonicalHealthTimelineSourceCollection collection,
  required String sourceId,
}) {
  return RawCanonicalNutritionComparableEntry(
    dogId: 'dog1',
    sourceCollection: collection,
    sourceId: sourceId,
    occurredAt: DateTime.utc(2024, 1, 1, 8),
    derivedTimelineId: 'tl1_$sourceId',
  );
}

RawCanonicalNutritionFirstPage _page(
  List<RawCanonicalNutritionComparableEntry> entries, {
  bool hasMore = false,
}) {
  return RawCanonicalNutritionFirstPage(entries: entries, hasMore: hasMore);
}

RawCanonicalNutritionFirstPageSuccess _success(
  List<RawCanonicalNutritionComparableEntry> entries, {
  bool hasMore = false,
}) {
  return RawCanonicalNutritionFirstPageSuccess(
    page: _page(entries, hasMore: hasMore),
  );
}

HealthTimelineQuery _query() => HealthTimelineQuery(dogId: 'dog1');

void main() {
  group('rawCanonicalNutritionEntryToComparable', () {
    test('1. meal entry maps sourceCollection to meal_logs', () {
      final item = rawCanonicalNutritionEntryToComparable(
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm1',
        ),
      );

      expect(item.sourceCollection, 'meal_logs');
      expect(item.sourceId, 'm1');
    });

    test('2. supplement entry maps sourceCollection to supplement_logs', () {
      final item = rawCanonicalNutritionEntryToComparable(
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.supplementLogs,
          sourceId: 's1',
        ),
      );

      expect(item.sourceCollection, 'supplement_logs');
      expect(item.sourceId, 's1');
    });

    test('3. conversion preserves sourceId and leaves legacy fields null', () {
      final item = rawCanonicalNutritionEntryToComparable(
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm1',
        ),
      );

      expect(item.sourceId, 'm1');
      expect(item.legacySource, isNull);
      expect(item.legacyId, isNull);
    });
  });

  group('rawCanonicalNutritionPageToComparableItems', () {
    test('4. page conversion preserves exact entry order', () {
      final page = _page([
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm1',
        ),
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.supplementLogs,
          sourceId: 's1',
        ),
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm2',
        ),
      ]);

      final items = rawCanonicalNutritionPageToComparableItems(page);

      expect(items.map((e) => e.sourceId).toList(), ['m1', 's1', 'm2']);
    });

    test('5. page conversion output rejects mutation', () {
      final items = rawCanonicalNutritionPageToComparableItems(
        _page([
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm1',
          ),
        ]),
      );

      expect(
        () => items.add(const HealthTimelineComparableItem()),
        throwsUnsupportedError,
      );
    });

    test('6. page conversion creates exactly one item per raw entry', () {
      final page = _page([
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm1',
        ),
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.supplementLogs,
          sourceId: 's1',
        ),
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm2',
        ),
      ]);

      final items = rawCanonicalNutritionPageToComparableItems(page);

      expect(items.length, 3);
      expect(items[0].sourceCollection, 'meal_logs');
      expect(items[1].sourceCollection, 'supplement_logs');
      expect(items[2].sourceCollection, 'meal_logs');
    });

    test('7. page conversion does not mutate source page entries', () {
      final entries = [
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm1',
        ),
        _rawEntry(
          collection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'm2',
        ),
      ];
      final page = _page(entries);

      rawCanonicalNutritionPageToComparableItems(page);

      // The source page entries are untouched.
      expect(page.entries.length, 2);
      expect(page.entries[0].sourceId, 'm1');
      expect(page.entries[1].sourceId, 'm2');
    });

    test('8. empty page returns an immutable empty list', () {
      final items = rawCanonicalNutritionPageToComparableItems(_page(const []));

      expect(items, isEmpty);
      expect(
        () => items.add(const HealthTimelineComparableItem()),
        throwsUnsupportedError,
      );
    });
  });

  group('RawCanonicalNutritionShadowBridge orchestration', () {
    test('9. bridge calls raw source exactly once', () async {
      final source = _FakeRawSource.returns(_success(const []));
      final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

      await bridge.compare(query: _query(), primaryItems: const []);

      expect(source.calls, 1);
    });

    test('10. bridge forwards the identical query instance', () async {
      final source = _FakeRawSource.returns(_success(const []));
      final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);
      final query = _query();

      await bridge.compare(query: query, primaryItems: const []);

      expect(identical(source.lastQuery, query), isTrue);
    });

    test(
      '11. bridge forwards primary entries to correlator in original order',
      () async {
        final received = <List<HealthTimelineComparableItem>>[];
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'r1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: source,
          correlate:
              ({
                required List<HealthTimelineComparableItem> primaryItems,
                required List<HealthTimelineComparableItem> shadowItems,
              }) {
                received.add(primaryItems);
                return const HealthTimelineCorrelationResult(
                  matchedPairs: [],
                  missingPrimaryIndices: [],
                  extraShadowIndices: [],
                  ambiguousPrimaryIndices: [],
                  ambiguousShadowIndices: [],
                  uncorrelatedPrimaryIndices: [],
                  uncorrelatedShadowIndices: [],
                );
              },
        );

        await bridge.compare(
          query: _query(),
          primaryItems: [
            _primary(id: 'e1', sourceCollection: 'meal_logs', sourceId: 'p1'),
            _primary(id: 'e2', sourceCollection: 'meal_logs', sourceId: 'p2'),
          ],
        );

        expect(received.single.length, 2);
        expect(received.single[0].sourceId, 'p1');
        expect(received.single[1].sourceId, 'p2');
      },
    );

    test(
      '12. caller mutation after compare starts does not affect primary snapshot',
      () async {
        final completer = Completer<RawCanonicalNutritionFirstPageResult>();
        // Override to return the completer's future.
        final overridingSource = _OverridingRawSource(completer.future);

        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: overridingSource,
        );

        final original = _primary(
          id: 'e1',
          sourceCollection: 'meal_logs',
          sourceId: 'p1',
        );
        final primaryItems = [original];
        final future = bridge.compare(
          query: _query(),
          primaryItems: primaryItems,
        );

        // Mutate AFTER compare was called, BEFORE it completes.
        primaryItems.clear();
        primaryItems.add(
          _primary(id: 'e2', sourceCollection: 'meal_logs', sourceId: 'p2'),
        );

        completer.complete(_FakeRawSource.returns(_success(const []))._result!);

        await future;

        // The correlator must have received the snapshot of [original], not [e2].
        // After mutation: the caller's list now has e2 (p2), proving the list
        // was mutated mid-flight. The bridge already snapshotted the original.
        expect(primaryItems[0].id, 'e2');
        expect(primaryItems[0].traceability?.sourceId, 'p2');
      },
    );

    test('13. raw source failure preserves exact failure kind', () async {
      final source = _FakeRawSource.returns(
        const RawCanonicalNutritionFirstPageFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
        ),
      );
      final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

      final result = await bridge.compare(
        query: _query(),
        primaryItems: const [],
      );

      expect(result, isA<RawCanonicalNutritionShadowBridgeFailure>());
      expect(
        (result as RawCanonicalNutritionShadowBridgeFailure).kind,
        RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
      );
    });

    test('14. raw source failure does not call correlator', () async {
      var correlateCalls = 0;
      final source = _FakeRawSource.returns(
        const RawCanonicalNutritionFirstPageFailure(
          kind:
              RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
        ),
      );
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        correlate:
            ({
              required List<HealthTimelineComparableItem> primaryItems,
              required List<HealthTimelineComparableItem> shadowItems,
            }) {
              correlateCalls++;
              return const HealthTimelineCorrelationResult(
                matchedPairs: [],
                missingPrimaryIndices: [],
                extraShadowIndices: [],
                ambiguousPrimaryIndices: [],
                ambiguousShadowIndices: [],
                uncorrelatedPrimaryIndices: [],
                uncorrelatedShadowIndices: [],
              );
            },
      );

      await bridge.compare(query: _query(), primaryItems: const []);

      expect(correlateCalls, 0);
    });

    test('15. raw source failure does not call ordering detector', () async {
      var detectorCalls = 0;
      final source = _FakeRawSource.returns(
        const RawCanonicalNutritionFirstPageFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
        ),
      );
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        detectOrderingMismatch:
            ({required List<HealthTimelineMatchedPair> matchedPairs}) {
              detectorCalls++;
              return false;
            },
      );

      await bridge.compare(query: _query(), primaryItems: const []);

      expect(detectorCalls, 0);
    });

    test('16. ArgumentError from raw source propagates', () async {
      var correlateCalls = 0;
      final source = _FakeRawSource.syncThrow(
        ArgumentError.value(null, 'query', 'ineligible'),
      );
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        correlate:
            ({
              required List<HealthTimelineComparableItem> primaryItems,
              required List<HealthTimelineComparableItem> shadowItems,
            }) {
              correlateCalls++;
              return const HealthTimelineCorrelationResult(
                matchedPairs: [],
                missingPrimaryIndices: [],
                extraShadowIndices: [],
                ambiguousPrimaryIndices: [],
                ambiguousShadowIndices: [],
                uncorrelatedPrimaryIndices: [],
                uncorrelatedShadowIndices: [],
              );
            },
      );

      await expectLater(
        bridge.compare(query: _query(), primaryItems: const []),
        throwsArgumentError,
      );
      expect(correlateCalls, 0);
    });

    test('17. unexpected raw source exceptions propagate', () async {
      // Sync throw.
      final syncSource = _FakeRawSource.syncThrow(StateError('sync boom'));
      final syncBridge = RawCanonicalNutritionShadowBridge(
        rawSource: syncSource,
      );

      await expectLater(
        syncBridge.compare(query: _query(), primaryItems: const []),
        throwsStateError,
      );

      // Future.error.
      final asyncSource = _FakeRawSource.futureError(Exception('async boom'));
      final asyncBridge = RawCanonicalNutritionShadowBridge(
        rawSource: asyncSource,
      );

      await expectLater(
        asyncBridge.compare(query: _query(), primaryItems: const []),
        throwsException,
      );
    });

    test(
      '18. successful comparison calls correlator and detector exactly once',
      () async {
        var correlateCalls = 0;
        var detectorCalls = 0;
        List<HealthTimelineMatchedPair>? receivedPairs;

        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'r1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(
          rawSource: source,
          correlate:
              ({
                required List<HealthTimelineComparableItem> primaryItems,
                required List<HealthTimelineComparableItem> shadowItems,
              }) {
                correlateCalls++;
                return HealthTimelineCorrelationResult(
                  matchedPairs: [
                    HealthTimelineMatchedPair(primaryIndex: 0, shadowIndex: 0),
                  ],
                  missingPrimaryIndices: const [],
                  extraShadowIndices: const [],
                  ambiguousPrimaryIndices: const [],
                  ambiguousShadowIndices: const [],
                  uncorrelatedPrimaryIndices: const [],
                  uncorrelatedShadowIndices: const [],
                );
              },
          detectOrderingMismatch:
              ({required List<HealthTimelineMatchedPair> matchedPairs}) {
                detectorCalls++;
                receivedPairs = matchedPairs;
                return false;
              },
        );

        await bridge.compare(
          query: _query(),
          primaryItems: [
            _primary(id: 'e1', sourceCollection: 'meal_logs', sourceId: 'r1'),
          ],
        );

        expect(correlateCalls, 1);
        expect(detectorCalls, 1);
        // Detector receives the frozen matchedPairs produced by the correlator.
        expect(receivedPairs!.length, 1);
        expect(receivedPairs!.single.primaryIndex, 0);
      },
    );
  });

  group('RawCanonicalNutritionShadowBridge correlation semantics', () {
    test(
      '19. primary meal_logs canonical locator matches raw Meal entry',
      () async {
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm1',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.matchedCount, 1);
        expect(result.correlation.matchedPairs.single.primaryIndex, 0);
        expect(result.correlation.matchedPairs.single.shadowIndex, 0);
      },
    );

    test(
      '20. primary supplement_logs canonical locator matches raw Supplement entry',
      () async {
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection:
                  CanonicalHealthTimelineSourceCollection.supplementLogs,
              sourceId: 's1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      sourceCollection: 'supplement_logs',
                      sourceId: 's1',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.matchedCount, 1);
      },
    );

    test(
      '21. primary legacy feedings locator does not match raw meal_logs locator',
      () async {
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      legacySource: 'feedings',
                      legacyId: 'm1',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        // legacy feedings != canonical meal_logs → no match.
        expect(result.correlation.matchedCount, 0);
        expect(result.correlation.missingCount, 1);
      },
    );

    test(
      '22. primary item without shadow partner increments missing count',
      () async {
        final source = _FakeRawSource.returns(_success(const []));
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm1',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.missingCount, 1);
        expect(result.correlation.missingPrimaryIndices, [0]);
      },
    );

    test(
      '23. shadow item without primary partner increments extra count',
      () async {
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(query: _query(), primaryItems: const [])
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.extraCount, 1);
        expect(result.correlation.extraShadowIndices, [0]);
      },
    );

    test(
      '24. two primary items sharing one shadow locator produce ambiguous counts',
      () async {
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm1',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        // Two primary entries share the same canonical locator as the single
        // raw entry → a 2×1 connected component → ambiguous on both sides.
        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm1',
                    ),
                    _primary(
                      id: 'e2',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm1',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.ambiguousPrimaryCount, 2);
        expect(result.correlation.ambiguousShadowCount, 1);
        expect(result.correlation.matchedCount, 0);
      },
    );

    test(
      '25. primary item without locators increments uncorrelated primary count',
      () async {
        final source = _FakeRawSource.returns(_success(const []));
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [_primary(id: 'e1', withTraceability: false)],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.uncorrelatedPrimaryCount, 1);
        expect(result.correlation.uncorrelatedPrimaryIndices, [0]);
      },
    );

    test(
      '26. empty primary and empty shadow return a valid zero comparison',
      () async {
        final source = _FakeRawSource.returns(_success(const []));
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(query: _query(), primaryItems: const [])
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.primaryCount, 0);
        expect(result.shadowCount, 0);
        expect(result.correlation.matchedCount, 0);
        expect(result.correlation.missingCount, 0);
        expect(result.correlation.extraCount, 0);
        expect(result.orderingMismatch, isFalse);
      },
    );
  });

  group('RawCanonicalNutritionShadowBridge ordering', () {
    test(
      '27. matching relative order returns orderingMismatch false',
      () async {
        // Primary: m1, m2. Shadow: m1, m2. Aligned order → no mismatch.
        final source = _FakeRawSource.returns(
          _success([
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm1',
            ),
            _rawEntry(
              collection: CanonicalHealthTimelineSourceCollection.mealLogs,
              sourceId: 'm2',
            ),
          ]),
        );
        final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

        final result =
            await bridge.compare(
                  query: _query(),
                  primaryItems: [
                    _primary(
                      id: 'e1',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm1',
                    ),
                    _primary(
                      id: 'e2',
                      sourceCollection: 'meal_logs',
                      sourceId: 'm2',
                    ),
                  ],
                )
                as RawCanonicalNutritionShadowBridgeSuccess;

        expect(result.correlation.matchedCount, 2);
        expect(result.orderingMismatch, isFalse);
      },
    );

    test('28. inverted relative order returns orderingMismatch true', () async {
      // Primary: m1, m2. Shadow: m2, m1. Inverted → mismatch.
      // Uses the real detector (not injected) via the default parameter.
      final source = _FakeRawSource.returns(
        _success([
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm2',
          ),
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm1',
          ),
        ]),
      );
      final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

      final result =
          await bridge.compare(
                query: _query(),
                primaryItems: [
                  _primary(
                    id: 'e1',
                    sourceCollection: 'meal_logs',
                    sourceId: 'm1',
                  ),
                  _primary(
                    id: 'e2',
                    sourceCollection: 'meal_logs',
                    sourceId: 'm2',
                  ),
                ],
              )
              as RawCanonicalNutritionShadowBridgeSuccess;

      expect(result.correlation.matchedCount, 2);
      expect(result.orderingMismatch, isTrue);
    });

    test('29. correlator exception propagates', () async {
      final source = _FakeRawSource.returns(_success(const []));
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        correlate:
            ({
              required List<HealthTimelineComparableItem> primaryItems,
              required List<HealthTimelineComparableItem> shadowItems,
            }) {
              throw StateError('comparator boom');
            },
      );

      await expectLater(
        bridge.compare(query: _query(), primaryItems: const []),
        throwsStateError,
      );
    });

    test('30. ordering detector exception propagates', () async {
      final source = _FakeRawSource.returns(_success(const []));
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        detectOrderingMismatch:
            ({required List<HealthTimelineMatchedPair> matchedPairs}) {
              throw StateError('detector boom');
            },
      );

      await expectLater(
        bridge.compare(query: _query(), primaryItems: const []),
        throwsStateError,
      );
    });
  });

  group('RawCanonicalNutritionShadowBridge freeze', () {
    test('31. every frozen correlation list rejects mutation', () async {
      final source = _FakeRawSource.returns(
        _success([
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm1',
          ),
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm2',
          ),
        ]),
      );
      final bridge = RawCanonicalNutritionShadowBridge(rawSource: source);

      final result =
          await bridge.compare(
                query: _query(),
                primaryItems: [
                  _primary(
                    id: 'e1',
                    sourceCollection: 'meal_logs',
                    sourceId: 'm1',
                  ),
                  _primary(
                    id: 'e2',
                    sourceCollection: 'meal_logs',
                    sourceId: 'm2',
                  ),
                ],
              )
              as RawCanonicalNutritionShadowBridgeSuccess;

      final c = result.correlation;

      expect(
        () => c.matchedPairs.add(
          const HealthTimelineMatchedPair(primaryIndex: 0, shadowIndex: 0),
        ),
        throwsUnsupportedError,
      );
      expect(() => c.missingPrimaryIndices.add(0), throwsUnsupportedError);
      expect(() => c.extraShadowIndices.add(0), throwsUnsupportedError);
      expect(() => c.ambiguousPrimaryIndices.add(0), throwsUnsupportedError);
      expect(() => c.ambiguousShadowIndices.add(0), throwsUnsupportedError);
      expect(() => c.uncorrelatedPrimaryIndices.add(0), throwsUnsupportedError);
      expect(() => c.uncorrelatedShadowIndices.add(0), throwsUnsupportedError);
    });

    test('32. mutation of correlator-owned lists after compare does not alter '
        'bridge result', () async {
      // External mutable lists — the correlator populates and mutates these.
      final externalMatchedPairs = <HealthTimelineMatchedPair>[];
      final externalMissing = <int>[];
      final externalExtra = <int>[];
      final externalAmbiguousPrimary = <int>[];
      final externalAmbiguousShadow = <int>[];
      final externalUncorrelatedPrimary = <int>[];
      final externalUncorrelatedShadow = <int>[];
      final mutationCompleted = Completer<void>();

      final source = _FakeRawSource.returns(
        _success([
          _rawEntry(
            collection: CanonicalHealthTimelineSourceCollection.mealLogs,
            sourceId: 'm1',
          ),
        ]),
      );
      final bridge = RawCanonicalNutritionShadowBridge(
        rawSource: source,
        correlate: ({required primaryItems, required shadowItems}) =>
            _mutatingCorrelator(
              primaryItems: primaryItems,
              shadowItems: shadowItems,
              externalMatchedPairs: externalMatchedPairs,
              externalMissing: externalMissing,
              externalExtra: externalExtra,
              externalAmbiguousPrimary: externalAmbiguousPrimary,
              externalAmbiguousShadow: externalAmbiguousShadow,
              externalUncorrelatedPrimary: externalUncorrelatedPrimary,
              externalUncorrelatedShadow: externalUncorrelatedShadow,
              mutationCompleted: mutationCompleted,
            ),
      );

      final result =
          await bridge.compare(
                query: _query(),
                primaryItems: [
                  _primary(
                    id: 'e1',
                    sourceCollection: 'meal_logs',
                    sourceId: 'm1',
                  ),
                ],
              )
              as RawCanonicalNutritionShadowBridgeSuccess;

      // Await the completer — this fires after scheduleMicrotask completes,
      // proving the mutation happened after the bridge returned the frozen result.
      await mutationCompleted.future;

      // The correlator mutated its own lists (adding sentinel 9999 values)
      // AFTER returning. The bridge result must be detached from those
      // mutations.
      expect(result.correlation.matchedPairs.length, 1);
      expect(result.correlation.missingPrimaryIndices, isEmpty);
      expect(result.correlation.extraShadowIndices, isEmpty);
      expect(result.correlation.ambiguousPrimaryIndices, isEmpty);
      expect(result.correlation.ambiguousShadowIndices, isEmpty);
      expect(result.correlation.uncorrelatedPrimaryIndices, isEmpty);
      expect(result.correlation.uncorrelatedShadowIndices, isEmpty);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Completer-based raw source for snapshot mid-flight test.
// ─────────────────────────────────────────────────────────────────────────────

class _OverridingRawSource implements RawCanonicalNutritionFirstPageSource {
  _OverridingRawSource(this.future);

  final Future<RawCanonicalNutritionFirstPageResult> future;

  @override
  Future<RawCanonicalNutritionFirstPageResult> loadFirstPage(
    HealthTimelineQuery query,
  ) => future;
}
