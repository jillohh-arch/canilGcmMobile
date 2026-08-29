// Copyright 2024 GCM Health. All rights reserved.
//
// PER-READER RAW CANONICAL NUTRITION CAPTURE FOUNDATION (4C-C-C-E).
//
// Pure, sealed, generic foundation that captures the SANITIZED result of a
// SINGLE reader call. It does NOT combine Meal and Supplement captures, does
// NOT decide which reader failed, and does NOT know about meal / supplement /
// dogId / collection / sourceKey. The Meal-vs-Supplement identity belongs to
// the FUTURE coordinator (by position / dependency), never to this capture.
//
// This file does NOT:
// - integrate with ReaderBackedRawCanonicalNutritionFirstPageSource
// - create a result union (success / failure / multipleReadersUnavailable)
// - create a raw-to-shadow bridge or a HealthTimelineSource adapter
// - touch Firestore, Remote Config, or any wiring
// - use a clock (Stopwatch / Timer / Future.delayed / timeout) or carry latency
//
// The ONLY construction authority is captureRawCanonicalNutritionReader: the
// concrete captures have private constructors, so no external caller can
// fabricate a contradictory capture.

library;

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Usable state — preserves the original available-vs-empty distinction WITHOUT
// re-exposing the full NutritionSourceAvailability enum.
// ─────────────────────────────────────────────────────────────────────────────

/// State of a usable capture: the reader returned a coherent batch.
enum RawCanonicalNutritionReaderUsableState {
  /// Batch was `available` with a non-empty item list.
  available,

  /// Batch was `empty` with an empty item list.
  empty,
}

// ─────────────────────────────────────────────────────────────────────────────
// Unavailable classification — sanitized, carries ONLY a kind.
// ─────────────────────────────────────────────────────────────────────────────

/// Sanitized reason a reader capture is unavailable.
///
/// Carries no message, code, payload, path, dogId, sourceKey, exception,
/// stack trace, or reader identity — only the coarse classification.
enum RawCanonicalNutritionReaderUnavailableKind {
  /// Batch availability was `offline` (with an empty list).
  offline,

  /// Batch availability was `error` (with an empty list).
  error,

  /// Batch availability was `notConfigured` (with an empty list).
  notConfigured,

  /// The reader threw synchronously or its Future completed with an exception,
  /// or a failure occurred while inspecting / copying the batch items.
  threw,

  /// The batch violated an availability↔items invariant (fail-closed):
  /// `available` with an empty list, or any other state carrying items that
  /// contradict its availability. Contradictory items are never exposed.
  invalidBatch,
}

// ─────────────────────────────────────────────────────────────────────────────
// Sealed capture — exhaustive pattern matching, no invalid states reachable.
// ─────────────────────────────────────────────────────────────────────────────

/// Sanitized capture of a single reader call.
///
/// Exactly one of two shapes: [RawCanonicalNutritionReaderUsable] (the reader
/// returned coherent data) or [RawCanonicalNutritionReaderUnavailable] (the
/// reader was unavailable / threw / returned a contradictory batch).
sealed class RawCanonicalNutritionReaderCapture<T> {
  const RawCanonicalNutritionReaderCapture();
}

/// A reader capture that carries usable items.
///
/// [items] is an immutable snapshot taken at capture time: mutations to the
/// original list after capture do not affect it, and the captured list itself
/// rejects mutation.
final class RawCanonicalNutritionReaderUsable<T>
    extends RawCanonicalNutritionReaderCapture<T> {
  RawCanonicalNutritionReaderUsable._({
    required this.state,
    required List<T> items,
  }) : items = List<T>.unmodifiable(items);

  /// Whether the batch was `available` (non-empty) or `empty`.
  final RawCanonicalNutritionReaderUsableState state;

  /// Immutable snapshot of the batch items. Empty when [state] is
  /// [RawCanonicalNutritionReaderUsableState.empty]. Never projected, filtered,
  /// ordered, or deduplicated by this layer.
  final List<T> items;
}

/// A reader capture that is unavailable, carrying only a sanitized [kind].
final class RawCanonicalNutritionReaderUnavailable<T>
    extends RawCanonicalNutritionReaderCapture<T> {
  const RawCanonicalNutritionReaderUnavailable._({required this.kind});

  /// Sanitized reason this capture is unavailable.
  final RawCanonicalNutritionReaderUnavailableKind kind;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sole construction authority.
// ─────────────────────────────────────────────────────────────────────────────

/// Captures the sanitized result of a single reader call.
///
/// [read] is a thunk (not an already-created Future) so that a synchronous
/// throw before the Future is returned is captured just like a Future that
/// completes with an exception.
///
/// The function ALWAYS completes with a capture and NEVER rethrows. A single
/// `try` covers the entire operation — invoking the thunk, the synchronous
/// throw, the Future exception, reading `availability` and `items`, the
/// emptiness check, the immutable copy, and construction — so even a defective
/// list or a failure during the copy is sanitized as
/// [RawCanonicalNutritionReaderUnavailableKind.threw].
Future<RawCanonicalNutritionReaderCapture<T>>
captureRawCanonicalNutritionReader<T>(
  Future<NutritionSourceBatch<T>> Function() read,
) async {
  try {
    final batch = await Future.sync(read);
    final availability = batch.availability;
    final items = batch.items;
    final isEmpty = items.isEmpty;

    return switch (availability) {
      NutritionSourceAvailability.available =>
        isEmpty
            ? RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
              )
            : RawCanonicalNutritionReaderUsable<T>._(
                state: RawCanonicalNutritionReaderUsableState.available,
                items: items,
              ),
      NutritionSourceAvailability.empty =>
        isEmpty
            ? RawCanonicalNutritionReaderUsable<T>._(
                state: RawCanonicalNutritionReaderUsableState.empty,
                items: const <Never>[],
              )
            : RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
              ),
      NutritionSourceAvailability.offline =>
        isEmpty
            ? RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.offline,
              )
            : RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
              ),
      NutritionSourceAvailability.error =>
        isEmpty
            ? RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.error,
              )
            : RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
              ),
      NutritionSourceAvailability.notConfigured =>
        isEmpty
            ? RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.notConfigured,
              )
            : RawCanonicalNutritionReaderUnavailable<T>._(
                kind: RawCanonicalNutritionReaderUnavailableKind.invalidBatch,
              ),
    };
  } catch (_) {
    return RawCanonicalNutritionReaderUnavailable<T>._(
      kind: RawCanonicalNutritionReaderUnavailableKind.threw,
    );
  }
}
