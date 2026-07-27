// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW COMPARATOR TESTS — 14 tests.

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
}
