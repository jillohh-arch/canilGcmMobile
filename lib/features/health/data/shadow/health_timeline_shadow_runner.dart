// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE SHADOW RUNNER (4C-C-C-H1).
//
// Neutral runner that bridges the RawCanonicalNutritionShadowBridge to the
// shadow comparator lifecycle.
//
// This runner does NOT:
// - measure latency (H2 responsibility)
// - apply timeout (H2 responsibility)
// - evaluate eligibility (H2 responsibility)
// - call observer (decorator responsibility)
// - know about primary source (bridge owns the primary side)
// - return HealthTimelinePage or HealthTimelineCursor
//
// Privacy: the public result carries ONLY counts and a bool. It NEVER carries
// dogId, sourceId, sourceCollection, documentId, occurredAt, entry, payload,
// exception, message, or stack trace.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_shadow_bridge.dart';
import 'package:canil_gcm/features/health/data/shadow/health_timeline_shadow_models.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Neutral runner result — internal to the runner.
// ─────────────────────────────────────────────────────────────────────────────

/// Sealed result union for [HealthTimelineShadowRunner].
///
/// This is the runner's internal result, later mapped to
/// [HealthTimelineShadowOutcome] by the decorator/sampler in H2.
sealed class HealthTimelineShadowRunResult {
  const HealthTimelineShadowRunResult();
}

/// Runner completed successfully — carries only counts and ordering flag.
final class HealthTimelineShadowRunSuccess
    extends HealthTimelineShadowRunResult {
  const HealthTimelineShadowRunSuccess({
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
  });

  final int primaryCount;
  final int shadowCount;
  final int matchedCount;
  final int missingCount;
  final int extraCount;
  final int uncorrelatedPrimaryCount;
  final int uncorrelatedShadowCount;
  final int ambiguousPrimaryCount;
  final int ambiguousShadowCount;
  final bool orderingMismatch;
}

/// Runner encountered a failure — carries only the public failure kind.
final class HealthTimelineShadowRunFailure
    extends HealthTimelineShadowRunResult {
  const HealthTimelineShadowRunFailure({required this.kind});

  final HealthTimelineShadowFailureKind kind;
}

// ─────────────────────────────────────────────────────────────────────────────
// Abstract runner interface.
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract runner that executes a shadow comparison and returns a neutral result.
///
/// The runner is stateless; it receives query and primary items per call but
/// owns the bridge as a constructor dependency.
///
/// H2 will wire this runner into the sampler/decorator lifecycle.
abstract interface class HealthTimelineShadowRunner {
  /// Executes a single shadow run for [query] against [primaryItems].
  ///
  /// Returns [HealthTimelineShadowRunSuccess] or [HealthTimelineShadowRunFailure].
  /// Exceptions are sanitized to [HealthTimelineShadowRunFailure].
  ///
  /// Does NOT evaluate eligibility; caller (H2 sampler) is responsible.
  /// Does NOT measure latency; caller (H2 sampler) is responsible.
  /// Does NOT call observer; caller (H2 decorator) is responsible.
  Future<HealthTimelineShadowRunResult> run({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Bridge adapter — bridges the concrete bridge to the runner interface.
// ─────────────────────────────────────────────────────────────────────────────

/// Adapter that wraps [RawCanonicalNutritionShadowBridge] as a typed
/// [RawCanonicalNutritionShadowComparator] for dependency injection.
///
/// This allows the runner to be tested without coupling to the concrete
/// bridge implementation.
abstract interface class RawCanonicalNutritionShadowComparator {
  Future<RawCanonicalNutritionShadowBridgeResult> compare({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  });
}

/// Adapter that delegates to the concrete
/// [RawCanonicalNutritionShadowBridge] implementation.
final class RawCanonicalNutritionShadowBridgeAdapter
    implements RawCanonicalNutritionShadowComparator {
  const RawCanonicalNutritionShadowBridgeAdapter({
    required RawCanonicalNutritionShadowBridge bridge,
  }) : _bridge = bridge;

  final RawCanonicalNutritionShadowBridge _bridge;

  @override
  Future<RawCanonicalNutritionShadowBridgeResult> compare({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) {
    return _bridge.compare(query: query, primaryItems: primaryItems);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nutrition-specific runner implementation.
// ─────────────────────────────────────────────────────────────────────────────

/// Nutrition-specific shadow runner that executes a comparison against the
/// raw canonical nutrition bridge.
///
/// Owns the bridge as a constructor dependency.
/// Does NOT measure latency, apply timeout, evaluate eligibility, or call
/// the observer.
final class HealthTimelineNutritionShadowRunner
    implements HealthTimelineShadowRunner {
  const HealthTimelineNutritionShadowRunner({
    required RawCanonicalNutritionShadowComparator comparator,
  }) : _comparator = comparator;

  final RawCanonicalNutritionShadowComparator _comparator;

  @override
  Future<HealthTimelineShadowRunResult> run({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> primaryItems,
  }) async {
    // Snapshot the primary items BEFORE any await to prevent caller mutation.
    final primarySnapshot = List<HealthTimelineEntryView>.unmodifiable(
      primaryItems,
    );

    try {
      final bridgeResult = await _comparator.compare(
        query: query,
        primaryItems: primarySnapshot,
      );

      return switch (bridgeResult) {
        RawCanonicalNutritionShadowBridgeSuccess() => _mapSuccess(bridgeResult),
        RawCanonicalNutritionShadowBridgeFailure() => _mapFailure(bridgeResult),
      };
    } on ArgumentError {
      // Ineligible query — sanitized to comparatorFailure.
      // This is a contract violation; sampler should have filtered.
      return const HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.comparatorFailure,
      );
    } on Object {
      // Any unexpected exception from raw source, correlator, or detector.
      // Sanitized to comparatorFailure without transport.
      return const HealthTimelineShadowRunFailure(
        kind: HealthTimelineShadowFailureKind.comparatorFailure,
      );
    }
  }

  /// Maps a successful bridge result to a neutral runner success.
  ///
  /// Extracts only counts and the ordering flag.
  /// Does NOT transport the correlation object itself.
  HealthTimelineShadowRunSuccess _mapSuccess(
    RawCanonicalNutritionShadowBridgeSuccess bridgeResult,
  ) {
    return HealthTimelineShadowRunSuccess(
      primaryCount: bridgeResult.primaryCount,
      shadowCount: bridgeResult.shadowCount,
      matchedCount: bridgeResult.correlation.matchedCount,
      missingCount: bridgeResult.correlation.missingCount,
      extraCount: bridgeResult.correlation.extraCount,
      uncorrelatedPrimaryCount:
          bridgeResult.correlation.uncorrelatedPrimaryCount,
      uncorrelatedShadowCount: bridgeResult.correlation.uncorrelatedShadowCount,
      ambiguousPrimaryCount: bridgeResult.correlation.ambiguousPrimaryCount,
      ambiguousShadowCount: bridgeResult.correlation.ambiguousShadowCount,
      orderingMismatch: bridgeResult.orderingMismatch,
    );
  }

  /// Maps a typed bridge failure to the neutral runner failure.
  ///
  /// All four internal kinds (mealReaderUnavailable,
  /// supplementReaderUnavailable, multipleReadersUnavailable,
  /// mergeInvariantFailed) collapse to shadowFailure.
  HealthTimelineShadowRunFailure _mapFailure(
    RawCanonicalNutritionShadowBridgeFailure bridgeResult,
  ) {
    return const HealthTimelineShadowRunFailure(
      kind: HealthTimelineShadowFailureKind.shadowFailure,
    );
  }
}
