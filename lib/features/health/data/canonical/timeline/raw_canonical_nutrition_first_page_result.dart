// Copyright 2024 GCM Health. All rights reserved.
//
// RAW CANONICAL NUTRITION FIRST-PAGE RESULT UNION (4C-C-C-F).
//
// Typed outcome of the reader-backed raw canonical nutrition first-page source.
// Exactly one of two shapes: success (carries the merged page) or failure
// (carries only a sanitized dependency kind).
//
// The failure kind names ONLY which dependency prevented the page — meal
// reader, supplement reader, both, or a merge invariant. It NEVER carries the
// per-reader capture kind (offline / error / notConfigured / threw /
// invalidBatch), a batch message/code, an exception, a stack trace, a dogId, a
// path, or any payload. Those details stay internal to the reader captures.
//
// This file does NOT import readers, captures, Firestore, query, bridge, or UI.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Failure taxonomy — one value per dependency that could prevent the page.
// ─────────────────────────────────────────────────────────────────────────────

/// Sanitized reason the raw canonical nutrition first page could not be
/// produced. Names the dependency only; never the underlying capture kind.
enum RawCanonicalNutritionSourceFailureKind {
  /// The meal reader was unavailable (supplement reader was usable).
  mealReaderUnavailable,

  /// The supplement reader was unavailable (meal reader was usable).
  supplementReaderUnavailable,

  /// Both readers were unavailable.
  multipleReadersUnavailable,

  /// Both readers were usable but the pure merger violated an invariant.
  mergeInvariantFailed,
}

// ─────────────────────────────────────────────────────────────────────────────
// Sealed result — exhaustive pattern matching, no invalid states reachable.
// ─────────────────────────────────────────────────────────────────────────────

/// Typed outcome of `loadFirstPage`: exactly [RawCanonicalNutritionFirstPageSuccess]
/// or [RawCanonicalNutritionFirstPageFailure].
sealed class RawCanonicalNutritionFirstPageResult {
  const RawCanonicalNutritionFirstPageResult();
}

/// Both readers were usable and the merger produced a page.
final class RawCanonicalNutritionFirstPageSuccess
    extends RawCanonicalNutritionFirstPageResult {
  const RawCanonicalNutritionFirstPageSuccess({required this.page});

  /// The exact page produced by the merger. Not copied or re-wrapped.
  final RawCanonicalNutritionFirstPage page;
}

/// The page could not be produced; carries only a sanitized dependency kind.
final class RawCanonicalNutritionFirstPageFailure
    extends RawCanonicalNutritionFirstPageResult {
  const RawCanonicalNutritionFirstPageFailure({required this.kind});

  /// Sanitized reason the page could not be produced.
  final RawCanonicalNutritionSourceFailureKind kind;
}
