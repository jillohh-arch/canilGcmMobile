// Copyright 2024 GCM Health. All rights reserved.
//
// HEALTH TIMELINE RAW CANONICAL FIRST-PAGE MERGER — Pure Dart foundation.
//
// NO production parity claims. NO Firestore. NO I/O.
//
// Receives already-parsed MealLog and SupplementLog lists and produces
// an internal first-page result for the canonical raw source.
//
// See 4C-C-B for full contract documentation.

library;

import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_id_deriver.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Raw canonical comparable entry — minimum structure for merger.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimum comparable entry produced by the raw canonical merger.
///
/// Contains ONLY the fields needed for correlation and ordering:
/// - locator (sourceCollection + sourceId)
/// - occurredAt (for ordering)
/// - derivedTimelineId (for tie-break and identity)
///
/// Does NOT contain:
/// - title, subtitle, status, recordedAt
/// - recordedBy, professional, observations, notes
/// - dose, grams, planId, mealOccurrenceId
/// - legacySource, legacyId
/// - MealLog.source
/// - attachments, payload
final class RawCanonicalNutritionComparableEntry {
  const RawCanonicalNutritionComparableEntry({
    required this.dogId,
    required this.sourceCollection,
    required this.sourceId,
    required this.occurredAt,
    required this.derivedTimelineId,
  });

  /// Dog scope — must match the query.
  final String dogId;

  /// Canonical source collection identifier.
  final CanonicalHealthTimelineSourceCollection sourceCollection;

  /// Document ID from the source collection.
  final String sourceId;

  /// When the event occurred (fedAt or administeredAt).
  final DateTime occurredAt;

  /// Derived timeline document ID (`tl1_` + 64 hex chars).
  final String derivedTimelineId;

  /// Leaf collection name for locator compatibility.
  String get locatorCollection => switch (sourceCollection) {
    CanonicalHealthTimelineSourceCollection.mealLogs => 'meal_logs',
    CanonicalHealthTimelineSourceCollection.supplementLogs => 'supplement_logs',
  };

  /// Unique key combining collection and source ID.
  String get locatorKey => '$locatorCollection:$sourceId';
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal first-page result — NOT HealthTimelinePage
// ─────────────────────────────────────────────────────────────────────────────

/// Internal result of merging raw canonical nutrition entries.
///
/// Does NOT contain:
/// - HealthTimelinePage
/// - HealthTimelineCursor
/// - nextCursor
/// - title/status/recordedAt
final class RawCanonicalNutritionFirstPage {
  RawCanonicalNutritionFirstPage({
    required List<RawCanonicalNutritionComparableEntry> entries,
    required this.hasMore,
  }) : entries = List.unmodifiable(entries);

  /// Entries in occurredAt DESC / derivedTimelineId DESC order.
  final List<RawCanonicalNutritionComparableEntry> entries;

  /// True when eligible entries exceed page size.
  final bool hasMore;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure merger function
// ─────────────────────────────────────────────────────────────────────────────

/// Merges MealLog and SupplementLog lists into a raw canonical first page.
///
/// Rules:
/// - Only accepts first-page queries (no cursor, no type/professional filters)
/// - Applies INCLUSIVE period bounds (>= start, <= end)
/// - Orders by occurredAt DESC, tie-break derivedTimelineId DESC
/// - Validates dog scope matches query
/// - Detects duplicate derived timeline IDs
///
/// Does NOT:
/// - Execute I/O
/// - Know about Firestore
/// - Return HealthTimelinePage or HealthTimelineCursor
RawCanonicalNutritionFirstPage mergeRawCanonicalNutritionFirstPage({
  required HealthTimelineQuery query,
  required List<MealLog> meals,
  required List<SupplementLog> supplements,
}) {
  validateRawCanonicalNutritionFirstPageQuery(query);

  final entries = <RawCanonicalNutritionComparableEntry>[];

  // ─── Map meals ───────────────────────────────────────────────────────────
  for (final meal in meals) {
    if (meal.dogId != query.dogId) {
      throw StateError(
        'dog_mismatch: MealLog.dogId="${meal.dogId}" != '
        'query.dogId="${query.dogId}"',
      );
    }

    entries.add(
      RawCanonicalNutritionComparableEntry(
        dogId: meal.dogId,
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: meal.id,
        occurredAt: meal.fedAt,
        derivedTimelineId: deriveCanonicalHealthTimelineId(
          dogId: meal.dogId,
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: meal.id,
        ),
      ),
    );
  }

  // ─── Map supplements ──────────────────────────────────────────────────────
  for (final supplement in supplements) {
    if (supplement.dogId != query.dogId) {
      throw StateError(
        'dog_mismatch: SupplementLog.dogId="${supplement.dogId}" != '
        'query.dogId="${query.dogId}"',
      );
    }

    entries.add(
      RawCanonicalNutritionComparableEntry(
        dogId: supplement.dogId,
        sourceCollection:
            CanonicalHealthTimelineSourceCollection.supplementLogs,
        sourceId: supplement.id,
        occurredAt: supplement.administeredAt,
        derivedTimelineId: deriveCanonicalHealthTimelineId(
          dogId: supplement.dogId,
          sourceCollection:
              CanonicalHealthTimelineSourceCollection.supplementLogs,
          sourceId: supplement.id,
        ),
      ),
    );
  }

  // ─── Filter by period (inclusive) ─────────────────────────────────────────
  final period = query.period;
  final start = period.start?.toUtc();
  final end = period.end?.toUtc();

  final filtered = entries.where((e) {
    final occurredUtc = e.occurredAt.toUtc();

    if (start != null && occurredUtc.isBefore(start)) return false;
    if (end != null && occurredUtc.isAfter(end)) return false;

    return true;
  }).toList();

  // ─── Sort: occurredAt DESC, derivedTimelineId DESC ─────────────────────────
  filtered.sort((a, b) {
    final byTime = b.occurredAt.compareTo(a.occurredAt);
    if (byTime != 0) return byTime;
    return b.derivedTimelineId.compareTo(a.derivedTimelineId);
  });

  // ─── Detect duplicate derived timeline IDs ─────────────────────────────────
  final seenIds = <String, RawCanonicalNutritionComparableEntry>{};
  for (final entry in filtered) {
    final existing = seenIds.putIfAbsent(entry.derivedTimelineId, () => entry);
    if (!identical(existing, entry)) {
      // Check if it's the same locator or a real collision
      if (existing.locatorKey == entry.locatorKey) {
        throw StateError(
          'duplicate_raw_canonical_entry: '
          '${entry.sourceCollection.name}:${entry.sourceId}',
        );
      } else {
        throw StateError(
          'derived_timeline_id_collision: ${entry.derivedTimelineId}',
        );
      }
    }
  }

  // ─── Page boundary ─────────────────────────────────────────────────────────
  final pageSize = query.pageSize;
  final hasMore = filtered.length > pageSize;
  final pageEntries = hasMore ? filtered.sublist(0, pageSize) : filtered;

  return RawCanonicalNutritionFirstPage(entries: pageEntries, hasMore: hasMore);
}

// ─────────────────────────────────────────────────────────────────────────────
// Query eligibility policy — single authoritative implementation
// ─────────────────────────────────────────────────────────────────────────────

/// Validates that [query] is eligible for a first-page raw canonical merge.
///
/// This is the single policy authority for first-page eligibility.
/// Throws [ArgumentError] if any of the following conditions are violated:
/// - cursor must be null (first-page only)
/// - types must be empty (no type filtering)
/// - caseId must be null (not supported)
/// - professional must be null (not supported)
///
/// Does NOT validate:
/// - dogId, period, pageSize (caller's responsibility)
/// - Firestore, readers, or any I/O
void validateRawCanonicalNutritionFirstPageQuery(HealthTimelineQuery query) {
  if (query.cursor != null) {
    throw ArgumentError.value(
      query,
      'query',
      'first-page merger does not accept queries with a cursor',
    );
  }
  if (query.types.isNotEmpty) {
    throw ArgumentError.value(
      query,
      'query.types',
      'first-page merger does not support type filters',
    );
  }
  if (query.caseId != null) {
    throw ArgumentError.value(
      query,
      'query.caseId',
      'first-page merger does not support caseId filters',
    );
  }
  if (query.professional != null) {
    throw ArgumentError.value(
      query,
      'query.professional',
      'first-page merger does not support professional filters',
    );
  }
}
