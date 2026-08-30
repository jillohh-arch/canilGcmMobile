// Copyright 2024 GCM Health. All rights reserved.
//
// RAW CANONICAL NUTRITION COMPARABLE SHADOW BRIDGE (4C-C-C-G).
//
// Internal, invisible-to-UI bridge between the reader-backed raw canonical
// nutrition first-page source and the neutral comparable universe used by the
// shadow comparator.
//
// Conceptual flow:
//   primary List<HealthTimelineEntryView>
//     -> comparable primary items (locator fields only, via traceability)
//
//   raw source
//     -> RawCanonicalNutritionFirstPageResult
//     -> comparable shadow items (locator fields only, via locatorCollection)
//
//   primary comparable + shadow comparable
//     -> correlateHealthTimelineComparableItems
//     -> detectHealthTimelineOrderingMismatch
//     -> typed RawCanonicalNutritionShadowBridgeResult
//
// This bridge does NOT:
// - fabricate a synthetic HealthTimelineEntryView
// - create a HealthTimelinePage / HealthTimelineCursor
// - implement HealthTimelineSource
// - touch the sampler, observer, ShadowComparingHealthTimelineSource
// - run Firestore, wiring, Remote Config, deploy, or UI
//
// Privacy: the public result carries ONLY indices/counts (via the neutral
// HealthTimelineCorrelationResult), a bool orderingMismatch, primary/shadow
// counts, and — on failure — the already-sanitized dependency kind. It NEVER
// carries dogId, sourceId, sourceCollection, occurredAt, derivedTimelineId,
// hasMore, a cursor, MealLog / SupplementLog, or any clinical payload.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_source.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_comparator.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pure conversions — raw comparable universe -> neutral comparable universe.
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a single [RawCanonicalNutritionComparableEntry] into the neutral
/// [HealthTimelineComparableItem] consumed by the shadow comparator.
///
/// Only the locator fields cross the boundary. The canonical collection is
/// projected through [RawCanonicalNutritionComparableEntry.locatorCollection]
/// (`meal_logs` / `supplement_logs`) so it lines up with the primary side's
/// `traceability.sourceCollection`. The raw entry has no legacy origin, so both
/// legacy fields are null.
///
/// Does NOT transport dogId, occurredAt, or derivedTimelineId.
HealthTimelineComparableItem rawCanonicalNutritionEntryToComparable(
  RawCanonicalNutritionComparableEntry entry,
) {
  return HealthTimelineComparableItem(
    sourceCollection: entry.locatorCollection,
    sourceId: entry.sourceId,
    legacySource: null,
    legacyId: null,
  );
}

/// Converts a [RawCanonicalNutritionFirstPage] into an immutable list of
/// neutral comparable items.
///
/// Contract:
/// - exactly one output per input entry;
/// - the order of [RawCanonicalNutritionFirstPage.entries] is preserved 1:1;
/// - no filter, no sort, no deduplication, no extra projection;
/// - the returned list is unmodifiable.
///
/// [RawCanonicalNutritionFirstPage.hasMore] does NOT enter the list.
List<HealthTimelineComparableItem> rawCanonicalNutritionPageToComparableItems(
  RawCanonicalNutritionFirstPage page,
) {
  return List<HealthTimelineComparableItem>.unmodifiable(
    page.entries.map(rawCanonicalNutritionEntryToComparable),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Injectable seams — precise typedefs mirroring the neutral comparator API.
// ─────────────────────────────────────────────────────────────────────────────

/// Neutral correlator seam. Defaults to [correlateHealthTimelineComparableItems].
typedef RawCanonicalNutritionComparableCorrelator =
    HealthTimelineCorrelationResult Function({
      required List<HealthTimelineComparableItem> primaryItems,
      required List<HealthTimelineComparableItem> shadowItems,
    });

/// Ordering-mismatch detector seam. Defaults to
/// [detectHealthTimelineOrderingMismatch].
typedef RawCanonicalNutritionOrderingDetector =
    bool Function({required List<HealthTimelineMatchedPair> matchedPairs});

// ─────────────────────────────────────────────────────────────────────────────
// Bridge result union.
// ─────────────────────────────────────────────────────────────────────────────

/// Typed outcome of [RawCanonicalNutritionShadowBridge.compare]: exactly one of
/// [RawCanonicalNutritionShadowBridgeSuccess] or
/// [RawCanonicalNutritionShadowBridgeFailure].
sealed class RawCanonicalNutritionShadowBridgeResult {
  const RawCanonicalNutritionShadowBridgeResult();
}

/// The raw source produced a page and the neutral correlation completed.
///
/// Carries ONLY the frozen neutral correlation (indices/counts), the ordering
/// mismatch flag, and the primary/shadow item counts. No locator or clinical
/// payload is exposed.
final class RawCanonicalNutritionShadowBridgeSuccess
    extends RawCanonicalNutritionShadowBridgeResult {
  const RawCanonicalNutritionShadowBridgeSuccess({
    required this.correlation,
    required this.orderingMismatch,
    required this.primaryCount,
    required this.shadowCount,
  });

  /// Frozen neutral correlation result (index lists only).
  final HealthTimelineCorrelationResult correlation;

  /// Whether the matched pairs reveal an ordering inversion.
  final bool orderingMismatch;

  /// Number of primary comparable items correlated.
  final int primaryCount;

  /// Number of shadow comparable items correlated.
  final int shadowCount;
}

/// The raw source could not produce a page. Carries only the sanitized
/// dependency kind already emitted by the raw source; the comparator is not
/// invoked and no partial comparison is produced.
final class RawCanonicalNutritionShadowBridgeFailure
    extends RawCanonicalNutritionShadowBridgeResult {
  const RawCanonicalNutritionShadowBridgeFailure({required this.kind});

  /// Sanitized dependency reason forwarded from the raw source.
  final RawCanonicalNutritionSourceFailureKind kind;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge.
// ─────────────────────────────────────────────────────────────────────────────

/// Injectable bridge that runs a single raw canonical nutrition first-page load
/// and correlates it against the supplied primary entries in the neutral
/// comparable universe.
///
/// The bridge:
/// - snapshots the primary comparable items BEFORE any await;
/// - calls [RawCanonicalNutritionFirstPageSource.loadFirstPage] exactly once;
/// - maps a raw failure to a typed bridge failure without invoking the
///   comparator;
/// - converts the primary entries by their `traceability` locator fields and
///   the raw page by `locatorCollection`;
/// - runs the neutral correlation, freezes the result, and derives the ordering
///   mismatch from the frozen matched pairs.
///
/// Eligibility is NOT re-validated here: the raw source is the single authority
/// and throws [ArgumentError] before any I/O for ineligible queries (cursor /
/// types / caseId / professional). That error propagates out of [compare]; it
/// does not become a bridge failure. Unexpected comparator / detector failures
/// also propagate — the bridge never swallows them with `catch (_)`.
final class RawCanonicalNutritionShadowBridge {
  RawCanonicalNutritionShadowBridge({
    required RawCanonicalNutritionFirstPageSource rawSource,
    RawCanonicalNutritionComparableCorrelator? correlate,
    RawCanonicalNutritionOrderingDetector? detectOrderingMismatch,
  }) : _rawSource = rawSource,
       _correlate = correlate ?? correlateHealthTimelineComparableItems,
       _detectOrderingMismatch =
           detectOrderingMismatch ?? detectHealthTimelineOrderingMismatch;

  final RawCanonicalNutritionFirstPageSource _rawSource;
  final RawCanonicalNutritionComparableCorrelator _correlate;
  final RawCanonicalNutritionOrderingDetector _detectOrderingMismatch;

  /// Loads the raw canonical nutrition first page for [query] and correlates it
  /// against [primaryItems] in the neutral comparable universe.
  Future<RawCanonicalNutritionShadowBridgeResult> compare({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    // Immutable snapshot of the primary comparable items BEFORE the await, so
    // later mutation of the caller's list cannot affect the correlation and the
    // caller's list is never reordered or mutated.
    final primaryComparables = List<HealthTimelineComparableItem>.unmodifiable(
      primaryItems.map(_primaryEntryToComparable),
    );

    // Single raw source call. An ineligible query throws ArgumentError here and
    // propagates unchanged (not a bridge failure).
    final result = await _rawSource.loadFirstPage(query);

    switch (result) {
      case RawCanonicalNutritionFirstPageFailure(:final kind):
        // No partial comparison: the comparator is never invoked on failure.
        return RawCanonicalNutritionShadowBridgeFailure(kind: kind);
      case RawCanonicalNutritionFirstPageSuccess(:final page):
        final shadowComparables = rawCanonicalNutritionPageToComparableItems(
          page,
        );
        final correlation = _freezeCorrelation(
          _correlate(
            primaryItems: primaryComparables,
            shadowItems: shadowComparables,
          ),
        );
        final orderingMismatch = _detectOrderingMismatch(
          matchedPairs: correlation.matchedPairs,
        );
        return RawCanonicalNutritionShadowBridgeSuccess(
          correlation: correlation,
          orderingMismatch: orderingMismatch,
          primaryCount: primaryComparables.length,
          shadowCount: shadowComparables.length,
        );
    }
  }

  /// Extracts the four comparable locator fields from an entry's traceability.
  /// This is the ONLY primary-side normalization done here; the correlation
  /// algorithm itself is not duplicated.
  static HealthTimelineComparableItem _primaryEntryToComparable(
    HealthTimelineEntryView entry,
  ) {
    final t = entry.traceability;
    return HealthTimelineComparableItem(
      sourceCollection: t?.sourceCollection,
      sourceId: t?.sourceId,
      legacySource: t?.legacySource,
      legacyId: t?.legacyId,
    );
  }

  /// Copies and freezes every list of the neutral correlation result, preserving
  /// order, so the result exposed by the bridge cannot be mutated and the
  /// ordering detector reads frozen matched pairs. Uses List.from() to copy
  /// (not a view) so mutations of the correlator's backing lists are isolated.
  static HealthTimelineCorrelationResult _freezeCorrelation(
    HealthTimelineCorrelationResult r,
  ) {
    return HealthTimelineCorrelationResult(
      matchedPairs: List<HealthTimelineMatchedPair>.unmodifiable(
        List<HealthTimelineMatchedPair>.from(r.matchedPairs),
      ),
      missingPrimaryIndices: List<int>.unmodifiable(
        List<int>.from(r.missingPrimaryIndices),
      ),
      extraShadowIndices: List<int>.unmodifiable(
        List<int>.from(r.extraShadowIndices),
      ),
      ambiguousPrimaryIndices: List<int>.unmodifiable(
        List<int>.from(r.ambiguousPrimaryIndices),
      ),
      ambiguousShadowIndices: List<int>.unmodifiable(
        List<int>.from(r.ambiguousShadowIndices),
      ),
      uncorrelatedPrimaryIndices: List<int>.unmodifiable(
        List<int>.from(r.uncorrelatedPrimaryIndices),
      ),
      uncorrelatedShadowIndices: List<int>.unmodifiable(
        List<int>.from(r.uncorrelatedShadowIndices),
      ),
    );
  }
}
