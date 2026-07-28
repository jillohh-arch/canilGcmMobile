// Copyright 2024 GCM Health. All rights reserved.
//
// READER-BACKED RAW CANONICAL NUTRITION FIRST-PAGE SOURCE (4C-C-C-D).
//
// Injectable, local, reader-backed source that:
// - receives a HealthTimelineQuery
// - validates eligibility BEFORE any I/O (single authority: the merger's
//   validateRawCanonicalNutritionFirstPageQuery)
// - runs the canonical MealLog and SupplementLog readers in parallel,
//   keeping BOTH futures observed
// - feeds the COMPLETE parsed lists to the pure merger
// - returns RawCanonicalNutritionFirstPage
//
// This source does NOT:
// - import cloud_firestore / receive FirebaseFirestore
// - instantiate concrete readers
// - implement HealthTimelineSource
// - return HealthTimelinePage / HealthTimelineCursor
// - import HealthTimelineEntryView / sampler / observer / comparator
// - create reader captures, result union, or a raw-to-shadow bridge
//
// Period authority (inclusive start/end) belongs EXCLUSIVELY to the merger, so
// the meal reader is called WITHOUT from/to. See 4C-C-C-D contract.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sanitized source exception.
// ─────────────────────────────────────────────────────────────────────────────

/// Signals that the raw canonical nutrition first page could not be produced
/// because at least one reader was unavailable (error / offline /
/// notConfigured) or threw.
///
/// Intentionally opaque: no fields, no kind enum, no meal/supplement
/// distinction, no batch message/code, no dogId, no path, no sourceId, no
/// payload, and no wrapped original exception. Result union and reader capture
/// hierarchy are deferred to later gates.
final class RawCanonicalNutritionSourceException implements Exception {
  const RawCanonicalNutritionSourceException();

  @override
  String toString() => 'raw canonical nutrition source unavailable';
}

// ─────────────────────────────────────────────────────────────────────────────
// Source contract.
// ─────────────────────────────────────────────────────────────────────────────

/// Injectable contract for the reader-backed raw canonical nutrition
/// first-page source.
abstract interface class RawCanonicalNutritionFirstPageSource {
  Future<RawCanonicalNutritionFirstPage> loadFirstPage(
    HealthTimelineQuery query,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reader-backed implementation.
// ─────────────────────────────────────────────────────────────────────────────

/// Reader-backed implementation over injected canonical readers.
///
/// Pure coordination: eligibility → parallel reads → exhaustive batch
/// classification → pure merge. No Firestore, no wiring, no UI.
final class ReaderBackedRawCanonicalNutritionFirstPageSource
    implements RawCanonicalNutritionFirstPageSource {
  ReaderBackedRawCanonicalNutritionFirstPageSource({
    required NutritionCanonicalMealReader mealReader,
    required NutritionCanonicalSupplementLogReader supplementReader,
  }) : _mealReader = mealReader,
       _supplementReader = supplementReader;

  final NutritionCanonicalMealReader _mealReader;
  final NutritionCanonicalSupplementLogReader _supplementReader;

  @override
  Future<RawCanonicalNutritionFirstPage> loadFirstPage(
    HealthTimelineQuery query,
  ) async {
    // ── Eligibility BEFORE any I/O ─────────────────────────────────────────
    // Single authority. Throws ArgumentError for cursor / types / caseId /
    // professional. No reader future is created when the query is ineligible.
    validateRawCanonicalNutritionFirstPageQuery(query);

    // ── Start both reads in parallel, before any await ─────────────────────
    // Meal reader is called WITHOUT from/to: inclusive period is the merger's
    // exclusive authority.
    final mealFuture = _mealReader.loadMeals(query.dogId);
    final supplementFuture = _supplementReader.loadSupplementLogs(query.dogId);

    // ── Await BOTH jointly so neither future is left unobserved ─────────────
    // Record `.wait` awaits both futures even when one fails, avoiding an
    // orphaned/unobserved async error. Any failure becomes the sanitized
    // exception. The catch wraps ONLY the reads — never the merger.
    late final NutritionSourceBatch<MealLog> mealBatch;
    late final NutritionSourceBatch<SupplementLog> supplementBatch;
    try {
      (mealBatch, supplementBatch) = await (mealFuture, supplementFuture).wait;
    } catch (_) {
      throw const RawCanonicalNutritionSourceException();
    }

    // ── Pure merge OUTSIDE the catch ───────────────────────────────────────
    // The merger stays the exclusive authority for defensive eligibility, dog
    // scope, inclusive period, ordering, tie-break, derived IDs, duplicates,
    // collisions, pageSize and hasMore. Its ArgumentError/StateError propagate
    // unwrapped.
    return mergeRawCanonicalNutritionFirstPage(
      query: query,
      meals: _usableItems(mealBatch),
      supplements: _usableItems(supplementBatch),
    );
  }

  /// Exhaustively classifies a batch's availability into usable items.
  ///
  /// - [NutritionSourceAvailability.available] → items
  /// - [NutritionSourceAvailability.empty] → legitimate empty list
  /// - error / offline / notConfigured → sanitized exception (never empty)
  ///
  /// `notConfigured` must be handled because [NutritionSourceBatch] exposes a
  /// public generic constructor and can be built directly with any enum value.
  /// No unavailable state is ever converted into an empty list, and neither
  /// `message` nor `code` is read.
  List<T> _usableItems<T>(NutritionSourceBatch<T> batch) {
    return switch (batch.availability) {
      NutritionSourceAvailability.available => batch.items,
      NutritionSourceAvailability.empty => const [],
      NutritionSourceAvailability.error ||
      NutritionSourceAvailability.offline ||
      NutritionSourceAvailability.notConfigured =>
        throw const RawCanonicalNutritionSourceException(),
    };
  }
}
