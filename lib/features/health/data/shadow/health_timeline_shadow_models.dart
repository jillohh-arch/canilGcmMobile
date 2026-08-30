// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW MODELS — Foundation-only pure implementation.
// NO production parity claims. No wiring. No activation.
//
// Coverage: PROVEN_CORRELATABLE_ORIGINS=0
// See Etapa 4A for traceability audit.

import 'dart:async';

/// Locator normalizado: collection name puro + documentId.
///
/// dogId NÃO está no locator — o escopo já é a query ativa.
///
/// This class is used internally for correlation matching.
/// It is NOT part of any outcome sent to the observer.
final class HealthTimelineCorrelationLocator {
  const HealthTimelineCorrelationLocator({
    required this.collection,
    required this.documentId,
  });

  final String collection;
  final String documentId;

  @override
  bool operator ==(Object other) {
    return other is HealthTimelineCorrelationLocator &&
        other.collection == collection &&
        other.documentId == documentId;
  }

  @override
  int get hashCode => Object.hash(collection, documentId);
}

/// Pair of indices for a matched entry.
final class HealthTimelineMatchedPair {
  const HealthTimelineMatchedPair({
    required this.primaryIndex,
    required this.shadowIndex,
  });

  final int primaryIndex;
  final int shadowIndex;
}

/// Internal result of correlation — indices only.
/// No entry data, no clinical identifiers.
final class HealthTimelineCorrelationResult {
  const HealthTimelineCorrelationResult({
    required this.matchedPairs,
    required this.missingPrimaryIndices,
    required this.extraShadowIndices,
    required this.ambiguousPrimaryIndices,
    required this.ambiguousShadowIndices,
    required this.uncorrelatedPrimaryIndices,
    required this.uncorrelatedShadowIndices,
  });

  /// Ordered list of matched pairs by primary index.
  final List<HealthTimelineMatchedPair> matchedPairs;

  /// Primary indices with locator(s), no edge to shadow.
  final List<int> missingPrimaryIndices;

  /// Shadow indices with locator(s), no edge to primary.
  final List<int> extraShadowIndices;

  /// Primary indices in ambiguous component (>1 node).
  final List<int> ambiguousPrimaryIndices;

  /// Shadow indices in ambiguous component (>1 node).
  final List<int> ambiguousShadowIndices;

  /// Primary indices without any locator.
  final List<int> uncorrelatedPrimaryIndices;

  /// Shadow indices without any locator.
  final List<int> uncorrelatedShadowIndices;

  int get matchedCount => matchedPairs.length;
  int get missingCount => missingPrimaryIndices.length;
  int get extraCount => extraShadowIndices.length;
  int get ambiguousPrimaryCount => ambiguousPrimaryIndices.length;
  int get ambiguousShadowCount => ambiguousShadowIndices.length;
  int get uncorrelatedPrimaryCount => uncorrelatedPrimaryIndices.length;
  int get uncorrelatedShadowCount => uncorrelatedShadowIndices.length;
}

/// Shadow skip kinds for query eligibility.
enum HealthTimelineShadowSkipKind {
  notFirstPage,
  unsupportedTypes,
  unsupportedCaseId,
  unsupportedProfessional,
}

/// Shadow failure kinds.
enum HealthTimelineShadowFailureKind {
  primaryFailure,
  shadowFailure,
  shadowTimeout,
  comparatorFailure,
}

/// Sealed outcome hierarchy for shadow observation.
sealed class HealthTimelineShadowOutcome {
  const HealthTimelineShadowOutcome();
}

/// Shadow executed and compared successfully.
final class HealthTimelineShadowComparison extends HealthTimelineShadowOutcome {
  const HealthTimelineShadowComparison({
    required this.primaryCount,
    required this.shadowCount,
    required this.matchedCount,
    required this.missingCount,
    required this.extraCount,
    required this.uncorrelatedPrimaryCount,
    required this.uncorrelatedShadowCount,
    required this.ambiguousPrimaryCount,
    required this.ambiguousShadowCount,
    required this.orderingMismatch,
    required this.shadowLatencyMs,
  });

  /// Count of primary entries.
  final int primaryCount;

  /// Count of shadow entries.
  final int shadowCount;

  /// Count of one-to-one matched pairs.
  final int matchedCount;

  /// Primary entries with locator but no shadow partner.
  final int missingCount;

  /// Shadow entries with locator but no primary partner.
  final int extraCount;

  /// Primary entries without any locator.
  final int uncorrelatedPrimaryCount;

  /// Shadow entries without any locator.
  final int uncorrelatedShadowCount;

  /// Primary entries in ambiguous components.
  final int ambiguousPrimaryCount;

  /// Shadow entries in ambiguous components.
  final int ambiguousShadowCount;

  /// Whether matched entries have different relative order.
  final bool orderingMismatch;

  /// Milliseconds elapsed from shadow start to shadow completion.
  final int shadowLatencyMs;

  // NO dogId / eventId / sourceId / timestamp / payload / clinical data
}

/// Shadow did not execute due to query eligibility.
final class HealthTimelineShadowSkipped extends HealthTimelineShadowOutcome {
  const HealthTimelineShadowSkipped({required this.skipKind});
  final HealthTimelineShadowSkipKind skipKind;
}

/// Shadow execution failed.
final class HealthTimelineShadowFailure extends HealthTimelineShadowOutcome {
  const HealthTimelineShadowFailure({
    required this.failureKind,
    this.shadowLatencyMs,
  });

  final HealthTimelineShadowFailureKind failureKind;

  /// Milliseconds elapsed before failure, if available.
  final int? shadowLatencyMs;
}

/// Neutral comparable item for correlation.
///
/// Contains ONLY the four locator fields.
/// All four are nullable because a source entry may have:
/// - canonical locator only (sourceCollection + sourceId)
/// - legacy locator only (legacySource + legacyId)
/// - both
/// - neither (uncorrelated)
///
/// Does NOT contain: dogId, occurredAt, derivedTimelineId, hasMore,
/// entry, payload, type, status, title.
///
/// This class is not part of any outcome sent to the observer.
final class HealthTimelineComparableItem {
  const HealthTimelineComparableItem({
    this.sourceCollection,
    this.sourceId,
    this.legacySource,
    this.legacyId,
  });

  /// Canonical source collection name (e.g. "meal_logs").
  final String? sourceCollection;

  /// Document ID from the canonical source collection.
  final String? sourceId;

  /// Legacy source path or collection name.
  final String? legacySource;

  /// Legacy document ID.
  final String? legacyId;
}

/// Observer interface for shadow outcomes.
///
/// All methods accept FutureOr to support both sync and async observers.
/// Failures are captured internally — observer never crashes the app.
abstract interface class HealthTimelineShadowObserver {
  FutureOr<void> onComparison(HealthTimelineShadowComparison value);
  FutureOr<void> onSkipped(HealthTimelineShadowSkipped value);
  FutureOr<void> onFailure(HealthTimelineShadowFailure value);
}
