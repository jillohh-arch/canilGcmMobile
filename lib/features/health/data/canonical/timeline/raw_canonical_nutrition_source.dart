// Copyright 2024 GCM Health. All rights reserved.
//
// READER-BACKED RAW CANONICAL NUTRITION FIRST-PAGE SOURCE (4C-C-C-F).
//
// Injectable, local, reader-backed source that:
// - receives a HealthTimelineQuery
// - validates eligibility BEFORE any I/O (single authority: the merger's
//   validateRawCanonicalNutritionFirstPageQuery)
// - captures the canonical MealLog and SupplementLog readers in parallel via
//   captureRawCanonicalNutritionReader, keeping BOTH captures observed
// - classifies the (meal, supplement) capture pair deterministically
// - runs the pure merger ONLY when BOTH captures are usable
// - returns a typed RawCanonicalNutritionFirstPageResult (success / failure)
//
// This source does NOT:
// - import cloud_firestore / receive FirebaseFirestore
// - instantiate concrete readers
// - implement HealthTimelineSource
// - return HealthTimelinePage / HealthTimelineCursor
// - import HealthTimelineEntryView / sampler / observer / comparator
// - create a raw-to-shadow bridge
//
// Failure taxonomy names ONLY the dependency (meal / supplement / both /
// merge). The per-reader capture kind never leaks into the result.
//
// Period authority (inclusive start/end) belongs EXCLUSIVELY to the merger, so
// the meal reader is called WITHOUT from/to. See 4C-C-C-D contract.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_reader_capture.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Injectable merger seam.
// ─────────────────────────────────────────────────────────────────────────────

/// Signature of the pure first-page merger. Exists only so the source can
/// inject a fake for testing; production uses the real top-level merger.
typedef RawCanonicalNutritionFirstPageMerger =
    RawCanonicalNutritionFirstPage Function({
      required HealthTimelineQuery query,
      required List<MealLog> meals,
      required List<SupplementLog> supplements,
    });

// ─────────────────────────────────────────────────────────────────────────────
// Source contract.
// ─────────────────────────────────────────────────────────────────────────────

/// Injectable contract for the reader-backed raw canonical nutrition
/// first-page source.
abstract interface class RawCanonicalNutritionFirstPageSource {
  Future<RawCanonicalNutritionFirstPageResult> loadFirstPage(
    HealthTimelineQuery query,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reader-backed implementation.
// ─────────────────────────────────────────────────────────────────────────────

/// Reader-backed implementation over injected canonical readers.
///
/// Pure coordination: eligibility → parallel captures → exhaustive
/// classification → pure merge (only when both usable). No Firestore, no
/// wiring, no UI.
final class ReaderBackedRawCanonicalNutritionFirstPageSource
    implements RawCanonicalNutritionFirstPageSource {
  ReaderBackedRawCanonicalNutritionFirstPageSource({
    required NutritionCanonicalMealReader mealReader,
    required NutritionCanonicalSupplementLogReader supplementReader,
    RawCanonicalNutritionFirstPageMerger? merge,
  }) : _mealReader = mealReader,
       _supplementReader = supplementReader,
       _merge = merge ?? mergeRawCanonicalNutritionFirstPage;

  final NutritionCanonicalMealReader _mealReader;
  final NutritionCanonicalSupplementLogReader _supplementReader;
  final RawCanonicalNutritionFirstPageMerger _merge;

  @override
  Future<RawCanonicalNutritionFirstPageResult> loadFirstPage(
    HealthTimelineQuery query,
  ) async {
    // ── Eligibility BEFORE any I/O ─────────────────────────────────────────
    // Single authority. Throws ArgumentError for cursor / types / caseId /
    // professional. No capture is created when the query is ineligible.
    validateRawCanonicalNutritionFirstPageQuery(query);

    // ── Start both captures in parallel, before any await ──────────────────
    // Meal reader is called WITHOUT from/to: inclusive period is the merger's
    // exclusive authority. Each capture absorbs its reader's synchronous throw
    // and Future exception, so neither reader can fail the other.
    final mealCaptureFuture = captureRawCanonicalNutritionReader<MealLog>(
      () => _mealReader.loadMeals(query.dogId),
    );
    final supplementCaptureFuture =
        captureRawCanonicalNutritionReader<SupplementLog>(
          () => _supplementReader.loadSupplementLogs(query.dogId),
        );

    // ── Await BOTH jointly so neither capture is left unobserved ────────────
    // Not wrapped in catch: captures never throw for expected reader failures;
    // any violation of that contract must stay visible as a programming error.
    final (mealCapture, supplementCapture) = await (
      mealCaptureFuture,
      supplementCaptureFuture,
    ).wait;

    // ── Exhaustive classification of the capture pair ──────────────────────
    // The per-reader capture kind (offline / error / notConfigured / threw /
    // invalidBatch) is intentionally collapsed by POSITION into a dependency
    // failure. Only both-usable reaches the merger.
    return switch ((mealCapture, supplementCapture)) {
      (
        final RawCanonicalNutritionReaderUsable<MealLog> meal,
        final RawCanonicalNutritionReaderUsable<SupplementLog> supplement,
      ) =>
        _merged(query: query, meal: meal, supplement: supplement),
      (
        RawCanonicalNutritionReaderUnavailable<MealLog>(),
        RawCanonicalNutritionReaderUsable<SupplementLog>(),
      ) =>
        const RawCanonicalNutritionFirstPageFailure(
          kind: RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
        ),
      (
        RawCanonicalNutritionReaderUsable<MealLog>(),
        RawCanonicalNutritionReaderUnavailable<SupplementLog>(),
      ) =>
        const RawCanonicalNutritionFirstPageFailure(
          kind: RawCanonicalNutritionSourceFailureKind
              .supplementReaderUnavailable,
        ),
      (
        RawCanonicalNutritionReaderUnavailable<MealLog>(),
        RawCanonicalNutritionReaderUnavailable<SupplementLog>(),
      ) =>
        const RawCanonicalNutritionFirstPageFailure(
          kind:
              RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
        ),
    };
  }

  /// Runs the pure merger over both usable captures. The `try` wraps ONLY the
  /// merge call and the immediate Success construction: a merger invariant
  /// (StateError) becomes a sanitized failure, while any other error type
  /// (ArgumentError / TypeError / RangeError / …) propagates as a programming
  /// error.
  RawCanonicalNutritionFirstPageResult _merged({
    required HealthTimelineQuery query,
    required RawCanonicalNutritionReaderUsable<MealLog> meal,
    required RawCanonicalNutritionReaderUsable<SupplementLog> supplement,
  }) {
    try {
      final page = _merge(
        query: query,
        meals: meal.items,
        supplements: supplement.items,
      );
      return RawCanonicalNutritionFirstPageSuccess(page: page);
    } on StateError {
      return const RawCanonicalNutritionFirstPageFailure(
        kind: RawCanonicalNutritionSourceFailureKind.mergeInvariantFailed,
      );
    }
  }
}
