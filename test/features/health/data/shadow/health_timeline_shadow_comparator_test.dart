// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW COMPARATOR TESTS — 26 tests.

import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_comparator.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake entry with controllable traceability for testing.
HealthTimelineEntryView _makeEntry({
  String? sourceCollection,
  String? sourceId,
  String? legacySource,
  String? legacyId,
}) {
  return HealthTimelineEntryView(
    id: 'entry-${sourceId ?? legacyId ?? 'none'}',
    dogId: 'dog-test',
    type: HealthTimelineTypeView.known(HealthTimelineType.meal),
    occurredAt: DateTime(2024, 1, 1),
    recordedAt: DateTime(2024, 1, 1),
    title: 'Test Entry',
    status: HealthTimelineEntryStatus.finalised,
    traceability: HealthTimelineTraceability(
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      legacySource: legacySource,
      legacyId: legacyId,
    ),
  );
}

void main() {
  group('normalizeHealthTimelineLocator', () {
    test('normalizes valid dog-scoped path', () {
      final locator = normalizeHealthTimelineLocator(
        collectionOrPath: 'dogs/dog-123/meal_logs',
        documentId: 'ml_abc',
      );
      expect(locator, isNotNull);
      expect(locator!.collection, equals('meal_logs'));
      expect(locator.documentId, equals('ml_abc'));
    });

    test('normalizes valid simple collection', () {
      final locator = normalizeHealthTimelineLocator(
        collectionOrPath: 'feeding_events',
        documentId: 'fe_456',
      );
      expect(locator, isNotNull);
      expect(locator!.collection, equals('feeding_events'));
      expect(locator.documentId, equals('fe_456'));
    });

    test('rejects malformed or unknown collection paths', () {
      // Unknown prefix
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'foo/bar/vacinas',
          documentId: 'x',
        ),
        isNull,
      );

      // Wrong prefix
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'users/123/health_events',
          documentId: 'x',
        ),
        isNull,
      );

      // Collection outside allowlist
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/dog-1/other_collection',
          documentId: 'x',
        ),
        isNull,
      );

      // Too many segments
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/dog-1/sub/path/meal_logs',
          documentId: 'x',
        ),
        isNull,
      );

      // Empty segment
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs//meal_logs',
          documentId: 'x',
        ),
        isNull,
      );

      // Whitespace segment
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/   /meal_logs',
          documentId: 'x',
        ),
        isNull,
      );
    });

    test('rejects null blank or whitespace document ids', () {
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/dog-1/meal_logs',
          documentId: null,
        ),
        isNull,
      );
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/dog-1/meal_logs',
          documentId: '',
        ),
        isNull,
      );
      expect(
        normalizeHealthTimelineLocator(
          collectionOrPath: 'dogs/dog-1/meal_logs',
          documentId: '   ',
        ),
        isNull,
      );
      expect(
        normalizeHealthTimelineLocator(collectionOrPath: null, documentId: 'x'),
        isNull,
      );
      expect(
        normalizeHealthTimelineLocator(collectionOrPath: '', documentId: 'x'),
        isNull,
      );
    });

    test('deduplicates equivalent source and legacy locators', () {
      // Equivalent pair: deduplicates to 1 locator
      final entryEquivalent = _makeEntry(
        sourceCollection: 'dogs/dog-1/feeding_events',
        sourceId: 'doc-1',
        legacySource: 'feeding_events',
        legacyId: 'doc-1',
      );

      final locatorsEquivalent = extractHealthTimelineLocators(entryEquivalent);
      expect(locatorsEquivalent.length, equals(1));
      expect(locatorsEquivalent.first.collection, equals('feeding_events'));
      expect(locatorsEquivalent.first.documentId, equals('doc-1'));

      // Different pair: remains 2 locators
      final entryDifferent = _makeEntry(
        sourceCollection: 'dogs/dog-1/feeding_events',
        sourceId: 'doc-1',
        legacySource: 'vacinas',
        legacyId: 'doc-2',
      );

      final locatorsDifferent = extractHealthTimelineLocators(entryDifferent);
      expect(locatorsDifferent.length, equals(2));
    });

    test('classifies entry without locator as uncorrelated', () {
      final entry = _makeEntry(
        sourceCollection: null,
        sourceId: null,
        legacySource: null,
        legacyId: null,
      );

      final locators = extractHealthTimelineLocators(entry);
      expect(locators.isEmpty, isTrue);
    });
  });

  group('correlateHealthTimelineEntries', () {
    test('matches a unique one-to-one component', () {
      final primaryModified = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'a'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'b'),
      ];
      final shadowModified = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'a'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'b'),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primaryModified,
        shadowItems: shadowModified,
      );

      expect(result.matchedCount, equals(2));
      expect(result.missingCount, equals(0));
      expect(result.extraCount, equals(0));
      expect(result.ambiguousPrimaryCount, equals(0));
      expect(result.ambiguousShadowCount, equals(0));
    });

    test('classifies canonical empty as primary missing', () {
      // Primary has entries with locators; shadow is empty
      final primary = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'p1'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'p2'),
      ];
      final shadow = <HealthTimelineEntryView>[];

      final result = correlateHealthTimelineEntries(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.missingCount, equals(2));
      expect(result.extraCount, equals(0));
    });

    test('classifies isolated shadow node as extra', () {
      final primary = <HealthTimelineEntryView>[];
      final shadow = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 's1'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 's2'),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.missingCount, equals(0));
      expect(result.extraCount, equals(2));
    });

    test('classifies duplicate primary component as ambiguous', () {
      // Primary has two entries with the same locator
      final primary = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
      ];
      final shadow = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.ambiguousPrimaryCount, equals(2));
      expect(result.ambiguousShadowCount, equals(1));
    });

    test('classifies duplicate shadow component as ambiguous', () {
      final primary = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
      ];
      final shadow = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'shared'),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.ambiguousPrimaryCount, equals(1));
      expect(result.ambiguousShadowCount, equals(2));
    });

    test('classifies one-to-many component as ambiguous', () {
      // Primary shares locators A,B with shadow1, shadow2 shares only B → same component
      final primaryModified = [
        _makeEntry(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
          legacySource: 'meal_logs',
          legacyId: 'b',
        ),
      ];
      final shadowModified = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'a'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'b'),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primaryModified,
        shadowItems: shadowModified,
      );

      // Primary connected to both shadows via shared locators
      // Component: 1 primary + 2 shadow → ambiguous
      expect(result.matchedCount, equals(0));
      expect(result.ambiguousPrimaryCount, equals(1));
      expect(result.ambiguousShadowCount, equals(2));
    });

    test('matches one pair sharing multiple locators only once', () {
      // Two entries that share two locators should match ONCE
      final primary = [
        _makeEntry(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
          legacySource: 'meal_logs',
          legacyId: 'b',
        ),
      ];
      final shadow = [
        _makeEntry(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
          legacySource: 'meal_logs',
          legacyId: 'b',
        ),
      ];

      final result = correlateHealthTimelineEntries(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(1)); // only one match, not two
    });

    test('detects equal and inverted matched ordering', () {
      // Equal order: primary[0]↔shadow[0], primary[1]↔shadow[1]
      final pairsEqual = [
        HealthTimelineMatchedPair(primaryIndex: 0, shadowIndex: 0),
        HealthTimelineMatchedPair(primaryIndex: 1, shadowIndex: 1),
      ];

      expect(
        detectHealthTimelineOrderingMismatch(matchedPairs: pairsEqual),
        isFalse,
      );

      // Inverted order: primary[0]↔shadow[1], primary[1]↔shadow[0]
      final pairsInverted = [
        HealthTimelineMatchedPair(primaryIndex: 0, shadowIndex: 1),
        HealthTimelineMatchedPair(primaryIndex: 1, shadowIndex: 0),
      ];

      expect(
        detectHealthTimelineOrderingMismatch(matchedPairs: pairsInverted),
        isTrue,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Neutral comparator tests — 12 new tests (tests 15–26)
  // ─────────────────────────────────────────────────────────────────────────────

  group('extractHealthTimelineComparableLocators', () {
    test('extracts a neutral canonical locator', () {
      final item = HealthTimelineComparableItem(
        sourceCollection: 'dogs/d1/meal_logs',
        sourceId: 'ml_abc',
      );

      final locators = extractHealthTimelineComparableLocators(item);

      expect(locators.length, equals(1));
      expect(locators.first.collection, equals('meal_logs'));
      expect(locators.first.documentId, equals('ml_abc'));
    });

    test('extracts a neutral legacy locator', () {
      final item = HealthTimelineComparableItem(
        legacySource: 'feeding_events',
        legacyId: 'fe_xyz',
      );

      final locators = extractHealthTimelineComparableLocators(item);

      expect(locators.length, equals(1));
      expect(locators.first.collection, equals('feeding_events'));
      expect(locators.first.documentId, equals('fe_xyz'));
    });

    test('deduplicates equivalent neutral canonical and legacy locators', () {
      // Same collection + docId via both paths → deduplicated to 1
      final item = HealthTimelineComparableItem(
        sourceCollection: 'dogs/d1/vacinas',
        sourceId: 'vac_1',
        legacySource: 'vacinas',
        legacyId: 'vac_1',
      );

      final locators = extractHealthTimelineComparableLocators(item);

      expect(locators.length, equals(1));
      expect(locators.first.collection, equals('vacinas'));
      expect(locators.first.documentId, equals('vac_1'));
    });

    test('extracts distinct neutral canonical and legacy locators', () {
      final item = HealthTimelineComparableItem(
        sourceCollection: 'dogs/d1/meal_logs',
        sourceId: 'ml_1',
        legacySource: 'feeding_events',
        legacyId: 'fe_1',
      );

      final locators = extractHealthTimelineComparableLocators(item);

      expect(locators.length, equals(2));
      final collections = locators.map((l) => l.collection).toSet();
      expect(collections, containsAll(['meal_logs', 'feeding_events']));
    });

    test('returns no locator for an all-null neutral item', () {
      final item = HealthTimelineComparableItem(
        sourceCollection: null,
        sourceId: null,
        legacySource: null,
        legacyId: null,
      );

      final locators = extractHealthTimelineComparableLocators(item);

      expect(locators.isEmpty, isTrue);
    });
  });

  group('correlateHealthTimelineComparableItems', () {
    test('correlates neutral items as a unique one-to-one match', () {
      final primary = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
      ];
      final shadow = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
      ];

      final result = correlateHealthTimelineComparableItems(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(2));
      expect(result.matchedPairs.length, equals(2));
      expect(result.matchedPairs[0].primaryIndex, equals(0));
      expect(result.matchedPairs[0].shadowIndex, equals(0));
      expect(result.matchedPairs[1].primaryIndex, equals(1));
      expect(result.matchedPairs[1].shadowIndex, equals(1));
      expect(result.missingCount, equals(0));
      expect(result.extraCount, equals(0));
      expect(result.ambiguousPrimaryCount, equals(0));
      expect(result.ambiguousShadowCount, equals(0));
      expect(result.uncorrelatedPrimaryCount, equals(0));
      expect(result.uncorrelatedShadowCount, equals(0));
    });

    test('classifies neutral missing extra and uncorrelated indices', () {
      final primary = [
        // Missing: has locator but no shadow partner
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'p_missing',
        ),
        // Uncorrelated: no locator
        HealthTimelineComparableItem(),
      ];
      final shadow = [
        // Extra: has locator but no primary partner
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 's_extra',
        ),
        // Uncorrelated: no locator
        HealthTimelineComparableItem(),
      ];

      final result = correlateHealthTimelineComparableItems(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.missingPrimaryIndices, equals([0]));
      expect(result.extraShadowIndices, equals([0]));
      expect(result.uncorrelatedPrimaryIndices, equals([1]));
      expect(result.uncorrelatedShadowIndices, equals([1]));
    });

    test('classifies a neutral duplicate component as ambiguous', () {
      // Two primary share same locator; one shadow shares same locator
      final primary = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'shared',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'shared',
        ),
      ];
      final shadow = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'shared',
        ),
      ];

      final result = correlateHealthTimelineComparableItems(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(result.matchedCount, equals(0));
      expect(result.ambiguousPrimaryIndices, equals([0, 1]));
      expect(result.ambiguousShadowIndices, equals([0]));
    });

    test('preserves equal positional ordering for neutral matched pairs', () {
      // primary[a, b] × shadow[a, b] → equal order, no mismatch
      final primary = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
      ];
      final shadow = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
      ];

      final result = correlateHealthTimelineComparableItems(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(
        detectHealthTimelineOrderingMismatch(matchedPairs: result.matchedPairs),
        isFalse,
      );
    });

    test('detects inverted positional ordering from neutral correlation', () {
      // primary[a, b] × shadow[b, a] → inverted order, mismatch detected
      final primary = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
      ];
      final shadow = [
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'b',
        ),
        HealthTimelineComparableItem(
          sourceCollection: 'dogs/d1/meal_logs',
          sourceId: 'a',
        ),
      ];

      final result = correlateHealthTimelineComparableItems(
        primaryItems: primary,
        shadowItems: shadow,
      );

      expect(
        detectHealthTimelineOrderingMismatch(matchedPairs: result.matchedPairs),
        isTrue,
      );
    });
  });

  group('entry-view extractor wrapper', () {
    test('entry-view extractor wrapper matches the neutral extractor', () {
      // Create entry with both canonical and legacy locators
      final entry = _makeEntry(
        sourceCollection: 'dogs/d1/meal_logs',
        sourceId: 'ml_1',
        legacySource: 'feeding_events',
        legacyId: 'fe_1',
      );

      final t = entry.traceability!;
      final comparable = HealthTimelineComparableItem(
        sourceCollection: t.sourceCollection,
        sourceId: t.sourceId,
        legacySource: t.legacySource,
        legacyId: t.legacyId,
      );

      final fromEntry = extractHealthTimelineLocators(entry);
      final fromComparable = extractHealthTimelineComparableLocators(
        comparable,
      );

      // Same set of locators
      expect(fromEntry.length, equals(fromComparable.length));
      final entryCollections = fromEntry.map((l) => l.collection).toList();
      final comparableCollections = fromComparable
          .map((l) => l.collection)
          .toList();
      expect(entryCollections.toSet(), equals(comparableCollections.toSet()));
    });
  });

  group('entry-view correlation wrapper', () {
    test('entry-view correlation wrapper matches the neutral correlation', () {
      // Mixed scenario: match, missing, extra, ambiguous, uncorrelated
      final primaryEntries = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'matched'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'missing'),
        _makeEntry(legacySource: 'vacinas', legacyId: 'legacy_matched'),
        _makeEntry(), // uncorrelated
      ];

      final shadowEntries = [
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'matched'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'extra'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'dup'),
        _makeEntry(sourceCollection: 'dogs/d1/meal_logs', sourceId: 'dup'),
        _makeEntry(legacySource: 'vacinas', legacyId: 'legacy_matched'),
        _makeEntry(), // uncorrelated
      ];

      // Convert entries to comparable
      List<HealthTimelineComparableItem> toComparable(
        List<HealthTimelineEntryView> entries,
      ) {
        return entries.map((e) {
          final t = e.traceability;
          return HealthTimelineComparableItem(
            sourceCollection: t?.sourceCollection,
            sourceId: t?.sourceId,
            legacySource: t?.legacySource,
            legacyId: t?.legacyId,
          );
        }).toList();
      }

      final fromEntry = correlateHealthTimelineEntries(
        primaryItems: primaryEntries,
        shadowItems: shadowEntries,
      );

      final fromComparable = correlateHealthTimelineComparableItems(
        primaryItems: toComparable(primaryEntries),
        shadowItems: toComparable(shadowEntries),
      );

      // Structural comparison of all fields
      expect(
        fromEntry.matchedPairs.length,
        equals(fromComparable.matchedPairs.length),
      );
      for (var i = 0; i < fromEntry.matchedPairs.length; i++) {
        expect(
          fromEntry.matchedPairs[i].primaryIndex,
          equals(fromComparable.matchedPairs[i].primaryIndex),
        );
        expect(
          fromEntry.matchedPairs[i].shadowIndex,
          equals(fromComparable.matchedPairs[i].shadowIndex),
        );
      }

      expect(
        fromEntry.missingPrimaryIndices,
        equals(fromComparable.missingPrimaryIndices),
      );
      expect(
        fromEntry.extraShadowIndices,
        equals(fromComparable.extraShadowIndices),
      );
      expect(
        fromEntry.ambiguousPrimaryIndices,
        equals(fromComparable.ambiguousPrimaryIndices),
      );
      expect(
        fromEntry.ambiguousShadowIndices,
        equals(fromComparable.ambiguousShadowIndices),
      );
      expect(
        fromEntry.uncorrelatedPrimaryIndices,
        equals(fromComparable.uncorrelatedPrimaryIndices),
      );
      expect(
        fromEntry.uncorrelatedShadowIndices,
        equals(fromComparable.uncorrelatedShadowIndices),
      );
    });
  });
}
