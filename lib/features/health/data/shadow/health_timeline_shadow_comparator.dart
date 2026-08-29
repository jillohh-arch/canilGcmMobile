// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW COMPARATOR — Pure synthetic foundation.
//
// NO production parity claims. Correlation only possible when
// sourceCollection/sourceId or legacySource/legacyId are shared.
//
// Coverage: PROVEN_CORRELATABLE_ORIGINS=0

library;

import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';

import 'health_timeline_shadow_models.dart';

/// Allowlist of known collection names in both sources.
const _kAllowedCollections = {
  'health_events',
  'weight_records',
  'feeding_events',
  'feedings',
  'vacinas',
  'meal_logs',
  'supplement_logs',
};

/// Normalizes a collection path or simple name into a correlation locator.
///
/// Returns null for invalid inputs.
///
/// Accepts:
/// - Simple collection name in allowlist: "vacinas"
/// - Dog-scoped path: "dogs/{dogId}/meal_logs"
///
/// Rejects:
/// - Unknown prefix: "foo/bar/meal_logs"
/// - Wrong prefix: "users/123/health_events"
/// - Empty segments: "dogs//meal_logs"
/// - Whitespace-only segments: "dogs/   /meal_logs"
/// - Collection outside allowlist
/// - Empty documentId
HealthTimelineCorrelationLocator? normalizeHealthTimelineLocator({
  required String? collectionOrPath,
  required String? documentId,
}) {
  if (collectionOrPath == null || documentId == null) return null;

  final colTrimmed = collectionOrPath.trim();
  final docTrimmed = documentId.trim();

  if (colTrimmed.isEmpty || docTrimmed.isEmpty) return null;

  // Remove all leading/trailing slashes
  var cleaned = colTrimmed;
  while (cleaned.startsWith('/')) {
    cleaned = cleaned.substring(1);
  }
  while (cleaned.endsWith('/')) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }

  if (cleaned.isEmpty) return null;

  // Split and reject empty or whitespace-only segments
  final rawSegments = cleaned.split('/');
  final segments = <String>[];
  for (final seg in rawSegments) {
    final t = seg.trim();
    if (t.isEmpty) return null; // empty or whitespace segment = malformed
    segments.add(t);
  }

  if (segments.isEmpty) return null;

  String collectionName;

  if (segments.length == 1) {
    // Simple collection name
    collectionName = segments.single;
  } else if (segments.length == 3 && segments[0] == 'dogs') {
    // Dog-scoped path: dogs/<dog-segment>/<collection>
    final dogSegment = segments[1].trim();
    if (dogSegment.isEmpty) return null;
    collectionName = segments[2];
  } else {
    // Any other format: rejected
    return null;
  }

  // Collection must be in allowlist
  if (!_kAllowedCollections.contains(collectionName)) return null;

  return HealthTimelineCorrelationLocator(
    collection: collectionName,
    documentId: docTrimmed,
  );
}

/// Extracts all locators from a neutral comparable item.
///
/// Uses normalizeHealthTimelineLocator as the single normalization authority.
/// Deduplicates equivalent locators via Set.
Set<HealthTimelineCorrelationLocator> extractHealthTimelineComparableLocators(
  HealthTimelineComparableItem item,
) {
  final result = <HealthTimelineCorrelationLocator>{};

  // Locator 1: sourceCollection + sourceId
  final loc1 = normalizeHealthTimelineLocator(
    collectionOrPath: item.sourceCollection,
    documentId: item.sourceId,
  );
  if (loc1 != null) result.add(loc1);

  // Locator 2: legacySource + legacyId
  final loc2 = normalizeHealthTimelineLocator(
    collectionOrPath: item.legacySource,
    documentId: item.legacyId,
  );
  if (loc2 != null) result.add(loc2);

  return result;
}

/// Extracts all locators from an entry via traceability fields.
///
/// Converts entry.traceability to HealthTimelineComparableItem
/// and delegates to the neutral extractor.
Set<HealthTimelineCorrelationLocator> extractHealthTimelineLocators(
  HealthTimelineEntryView entry,
) {
  final t = entry.traceability;
  return extractHealthTimelineComparableLocators(
    HealthTimelineComparableItem(
      sourceCollection: t?.sourceCollection,
      sourceId: t?.sourceId,
      legacySource: t?.legacySource,
      legacyId: t?.legacyId,
    ),
  );
}

/// Correlates primary and shadow comparable items using bipartite graph matching.
///
/// Uses indices as nodes to avoid equality issues with item objects.
/// Each index appears in exactly one category.
///
/// This is the single authoritative algorithm for health timeline correlation.
HealthTimelineCorrelationResult correlateHealthTimelineComparableItems({
  required List<HealthTimelineComparableItem> primaryItems,
  required List<HealthTimelineComparableItem> shadowItems,
}) {
  final n = primaryItems.length;
  final m = shadowItems.length;

  // Extract locators per index
  final primaryLocators = <int, Set<HealthTimelineCorrelationLocator>>{};
  final primaryHasLocator = <int>{};

  for (var i = 0; i < n; i++) {
    final locs = extractHealthTimelineComparableLocators(primaryItems[i]);
    primaryLocators[i] = locs;
    if (locs.isNotEmpty) primaryHasLocator.add(i);
  }

  final shadowLocators = <int, Set<HealthTimelineCorrelationLocator>>{};
  final shadowHasLocator = <int>{};

  for (var j = 0; j < m; j++) {
    final locs = extractHealthTimelineComparableLocators(shadowItems[j]);
    shadowLocators[j] = locs;
    if (locs.isNotEmpty) shadowHasLocator.add(j);
  }

  // Pre-classify: items without locators → uncorrelated
  final uncorrelatedPrimaryIndices = <int>[];
  final uncorrelatedShadowIndices = <int>[];
  final primaryWithLocator = <int>{};
  final shadowWithLocator = <int>{};

  for (var i = 0; i < n; i++) {
    if (!primaryHasLocator.contains(i)) {
      uncorrelatedPrimaryIndices.add(i);
    } else {
      primaryWithLocator.add(i);
    }
  }

  for (var j = 0; j < m; j++) {
    if (!shadowHasLocator.contains(j)) {
      uncorrelatedShadowIndices.add(j);
    } else {
      shadowWithLocator.add(j);
    }
  }

  // Build edge maps: locator → [primary indices] and locator → [shadow indices]
  final locatorToPrimary = <HealthTimelineCorrelationLocator, List<int>>{};
  final locatorToShadow = <HealthTimelineCorrelationLocator, List<int>>{};

  for (final i in primaryWithLocator) {
    for (final loc in primaryLocators[i]!) {
      locatorToPrimary.putIfAbsent(loc, () => []).add(i);
    }
  }

  for (final j in shadowWithLocator) {
    for (final loc in shadowLocators[j]!) {
      locatorToShadow.putIfAbsent(loc, () => []).add(j);
    }
  }

  // BFS to find connected components in bipartite graph
  final visitedPrimary = <int>{};
  final visitedShadow = <int>{};

  final matchedPairs = <HealthTimelineMatchedPair>[];
  final ambiguousPrimaryIndices = <int>[];
  final ambiguousShadowIndices = <int>[];
  final missingPrimaryIndices = <int>[];
  final extraShadowIndices = <int>[];

  for (final startPrimary in primaryWithLocator) {
    if (visitedPrimary.contains(startPrimary)) continue;

    // BFS flood-fill from this primary node
    final componentPrimary = <int>{};
    final componentShadow = <int>{};

    final primaryQueue = <int>[startPrimary];
    final shadowQueue = <int>[];

    while (primaryQueue.isNotEmpty || shadowQueue.isNotEmpty) {
      // Process primary nodes
      while (primaryQueue.isNotEmpty) {
        final pi = primaryQueue.removeLast();
        if (visitedPrimary.contains(pi)) continue;
        visitedPrimary.add(pi);
        componentPrimary.add(pi);

        // Discover shadow nodes via shared locators
        for (final loc in primaryLocators[pi]!) {
          for (final sj in locatorToShadow[loc] ?? const []) {
            if (!visitedShadow.contains(sj)) {
              shadowQueue.add(sj);
            }
          }
        }
      }

      // Process shadow nodes discovered in this component
      while (shadowQueue.isNotEmpty) {
        final sj = shadowQueue.removeLast();
        if (visitedShadow.contains(sj)) continue;
        visitedShadow.add(sj);
        componentShadow.add(sj);

        // Discover more primary nodes via shared locators
        for (final loc in shadowLocators[sj]!) {
          for (final pi in locatorToPrimary[loc] ?? const []) {
            if (!visitedPrimary.contains(pi)) {
              primaryQueue.add(pi);
            }
          }
        }
      }
    }

    // Classify component
    if (componentPrimary.isEmpty || componentShadow.isEmpty) {
      // Isolated nodes without edges — classify separately
      for (final pi in componentPrimary) {
        missingPrimaryIndices.add(pi);
      }
      for (final sj in componentShadow) {
        extraShadowIndices.add(sj);
      }
    } else if (componentPrimary.length == 1 && componentShadow.length == 1) {
      // Exactly 1×1 → unique match
      matchedPairs.add(
        HealthTimelineMatchedPair(
          primaryIndex: componentPrimary.single,
          shadowIndex: componentShadow.single,
        ),
      );
    } else {
      // Any other size → entire component is ambiguous
      ambiguousPrimaryIndices.addAll(componentPrimary);
      ambiguousShadowIndices.addAll(componentShadow);
    }
  }

  // Shadow nodes with locators but not visited (disconnected components)
  for (final j in shadowWithLocator) {
    if (!visitedShadow.contains(j)) {
      extraShadowIndices.add(j);
    }
  }

  // Sort all index lists for deterministic output
  matchedPairs.sort((a, b) => a.primaryIndex.compareTo(b.primaryIndex));
  missingPrimaryIndices.sort();
  extraShadowIndices.sort();
  ambiguousPrimaryIndices.sort();
  ambiguousShadowIndices.sort();
  uncorrelatedPrimaryIndices.sort();
  uncorrelatedShadowIndices.sort();

  return HealthTimelineCorrelationResult(
    matchedPairs: matchedPairs,
    missingPrimaryIndices: missingPrimaryIndices,
    extraShadowIndices: extraShadowIndices,
    ambiguousPrimaryIndices: ambiguousPrimaryIndices,
    ambiguousShadowIndices: ambiguousShadowIndices,
    uncorrelatedPrimaryIndices: uncorrelatedPrimaryIndices,
    uncorrelatedShadowIndices: uncorrelatedShadowIndices,
  );
}

/// Correlates primary and shadow entries using bipartite graph matching.
///
/// Converts HealthTimelineEntryView items to HealthTimelineComparableItem
/// and delegates to the neutral correlator. Preserves backward compatibility.
HealthTimelineCorrelationResult correlateHealthTimelineEntries({
  required List<HealthTimelineEntryView> primaryItems,
  required List<HealthTimelineEntryView> shadowItems,
}) {
  final primary = primaryItems.map((e) {
    final t = e.traceability;
    return HealthTimelineComparableItem(
      sourceCollection: t?.sourceCollection,
      sourceId: t?.sourceId,
      legacySource: t?.legacySource,
      legacyId: t?.legacyId,
    );
  }).toList();

  final shadow = shadowItems.map((e) {
    final t = e.traceability;
    return HealthTimelineComparableItem(
      sourceCollection: t?.sourceCollection,
      sourceId: t?.sourceId,
      legacySource: t?.legacySource,
      legacyId: t?.legacyId,
    );
  }).toList();

  return correlateHealthTimelineComparableItems(
    primaryItems: primary,
    shadowItems: shadow,
  );
}

/// Detects ordering mismatch between matched pairs.
///
/// Only matched pairs participate. For each pair, uses (primaryIndex, shadowIndex).
/// Sorts by primaryIndex, extracts shadowIndex sequence.
/// Returns true if shadowIndex sequence is not strictly increasing.
bool detectHealthTimelineOrderingMismatch({
  required List<HealthTimelineMatchedPair> matchedPairs,
}) {
  if (matchedPairs.length < 2) return false;

  // Sort by primary index
  final sorted = List<HealthTimelineMatchedPair>.from(matchedPairs)
    ..sort((a, b) => a.primaryIndex.compareTo(b.primaryIndex));

  // Extract shadow index sequence
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].shadowIndex <= sorted[i - 1].shadowIndex) {
      return true; // inversion detected
    }
  }
  return false;
}

/// Safely invokes observer, capturing all sync and async failures.
Future<void> safelyObserveHealthTimelineShadowOutcome(
  HealthTimelineShadowOutcome outcome,
  HealthTimelineShadowObserver? observer,
) async {
  if (observer == null) return;

  try {
    await Future.sync(() {
      return switch (outcome) {
        HealthTimelineShadowComparison value => observer.onComparison(value),
        HealthTimelineShadowSkipped value => observer.onSkipped(value),
        HealthTimelineShadowFailure value => observer.onFailure(value),
      };
    });
  } catch (_) {
    // Fail-silent absolute.
  }
}
