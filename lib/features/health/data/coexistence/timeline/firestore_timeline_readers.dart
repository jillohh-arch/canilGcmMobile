import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_mappers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/multi_source_timeline_paginator.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Reader Firestore genérico: orderBy(dateField DESC) + filtro cliente.
///
/// Soft-delete e mapping via [tryMap] → [TimelineMappingResult].
/// Documento ativo estruturalmente unmappable → [HealthTimelineSourceException]
/// inconclusiva (nunca empty / sucesso parcial).
class FirestoreOrderedTimelineReader implements HealthTimelineSourceReader {
  FirestoreOrderedTimelineReader({
    required this.sourceKey,
    required this.dateField,
    required TimelineMappingResult Function({
      required String dogId,
      required String docId,
      required Map<String, dynamic> data,
      required HealthTimelineQuery filters,
    })
    tryMap,
    FirebaseFirestore? firestore,
    this.isRootCollection = false,
    this.rootDogIdField,
    this.maxDocsPerBatchHardCap = 200,
    this.clientSideOrderOnly = false,
  }) : _tryMap = tryMap,
       _firestore = firestore;

  @override
  final String sourceKey;
  final String dateField;
  final bool isRootCollection;
  final String? rootDogIdField;
  final int maxDocsPerBatchHardCap;
  final bool clientSideOrderOnly;

  final FirebaseFirestore? _firestore;
  final TimelineMappingResult Function({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  })
  _tryMap;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<HealthTimelineSourceBatch> fetchBatch({
    required String dogId,
    required int batchSize,
    HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  }) async {
    try {
      final want = batchSize.clamp(1, maxDocsPerBatchHardCap);
      final fetchLimit = (want * 3).clamp(want, maxDocsPerBatchHardCap);

      if (clientSideOrderOnly) {
        return _fetchClientOrdered(
          dogId: dogId,
          want: want,
          fetchLimit: fetchLimit,
          after: after,
          filters: filters,
        );
      }

      Query<Map<String, dynamic>> q;
      if (isRootCollection) {
        final field = rootDogIdField ?? 'caoId';
        q = _db
            .collection(sourceKey)
            .where(field, isEqualTo: dogId)
            .orderBy(dateField, descending: true);
      } else {
        q = _db
            .collection('dogs')
            .doc(dogId)
            .collection(sourceKey)
            .orderBy(dateField, descending: true);
      }

      if (after != null) {
        q = q.startAt([Timestamp.fromDate(after.lastOccurredAt.toUtc())]);
      }
      q = q.limit(fetchLimit);

      final snap = await q.get();
      return _mapSnapshot(
        dogId: dogId,
        snap: snap,
        want: want,
        fetchLimit: fetchLimit,
        after: after,
        filters: filters,
      );
    } on HealthTimelineSourceException {
      rethrow;
    } on FirebaseException catch (e) {
      final offline = TimelineErrorSanitizer.looksLikeOffline(e, code: e.code);
      throw HealthTimelineSourceException(
        TimelineErrorSanitizer.publicMessage(e, code: e.code),
        isOffline: offline,
      );
    }
  }

  Future<HealthTimelineSourceBatch> _fetchClientOrdered({
    required String dogId,
    required int want,
    required int fetchLimit,
    required HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  }) async {
    final field = rootDogIdField ?? 'caoId';
    final snap = await _db
        .collection(sourceKey)
        .where(field, isEqualTo: dogId)
        .limit(fetchLimit)
        .get();

    final mapped = <HealthTimelineEntryView>[];
    for (final doc in snap.docs) {
      final result = _tryMap(
        dogId: dogId,
        docId: doc.id,
        data: doc.data(),
        filters: filters,
      );
      switch (result) {
        case TimelineInvalid(:final reason):
          HealthTimelineMappers.throwInconclusive(
            sourceKey: sourceKey,
            reason: reason,
          );
        case TimelineIgnored():
          continue;
        case TimelineMapped(:final entry):
          if (after != null && !_comesAfterCursor(after, entry)) continue;
          mapped.add(entry);
      }
    }
    mapped.sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });

    final page = mapped.take(want).toList(growable: false);
    final hitServerCap = snap.docs.length >= fetchLimit;
    final exhausted = !hitServerCap && page.length >= mapped.length;
    final truncated = hitServerCap && page.length < want && mapped.length < want
        ? true
        : hitServerCap && after == null && mapped.isEmpty
        ? true
        : false;

    if (hitServerCap && page.isEmpty) {
      return const HealthTimelineSourceBatch(
        items: [],
        exhausted: false,
        truncated: true,
      );
    }

    HealthTimelineSourceReaderCursor? lastFetched;
    if (page.isNotEmpty) {
      final last = page.last;
      lastFetched = HealthTimelineSourceReaderCursor(
        lastOccurredAt: last.occurredAt,
        lastId: last.id,
      );
    }

    if (after != null && hitServerCap && page.isEmpty) {
      return const HealthTimelineSourceBatch(
        items: [],
        exhausted: false,
        truncated: true,
      );
    }

    return HealthTimelineSourceBatch(
      items: page,
      exhausted: exhausted || (!hitServerCap && mapped.length <= want),
      truncated: truncated && page.length < want,
      lastFetched: lastFetched ?? after,
    );
  }

  HealthTimelineSourceBatch _mapSnapshot({
    required String dogId,
    required QuerySnapshot<Map<String, dynamic>> snap,
    required int want,
    required int fetchLimit,
    required HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  }) {
    final mapped = <HealthTimelineEntryView>[];
    for (final doc in snap.docs) {
      final result = _tryMap(
        dogId: dogId,
        docId: doc.id,
        data: doc.data(),
        filters: filters,
      );
      switch (result) {
        case TimelineInvalid(:final reason):
          // Não avança cursor como sucesso; não emite parcial.
          HealthTimelineMappers.throwInconclusive(
            sourceKey: sourceKey,
            reason: reason,
          );
        case TimelineIgnored():
          continue;
        case TimelineMapped(:final entry):
          if (after != null && !_comesAfterCursor(after, entry)) continue;
          mapped.add(entry);
          if (mapped.length >= want) break;
      }
    }

    final exhausted = snap.docs.length < fetchLimit;
    HealthTimelineSourceReaderCursor? lastFetched;
    if (mapped.isNotEmpty) {
      final last = mapped.last;
      lastFetched = HealthTimelineSourceReaderCursor(
        lastOccurredAt: last.occurredAt,
        lastId: last.id,
      );
    } else if (snap.docs.isNotEmpty && !exhausted) {
      // Página cheia só de ignored (soft-delete/filtro): avança se data parseável.
      final lastDoc = snap.docs.last;
      final at = HealthSummaryDateParse.tryParse(lastDoc.data()[dateField]);
      if (at != null) {
        lastFetched = HealthTimelineSourceReaderCursor(
          lastOccurredAt: at,
          lastId: _cursorIdForDoc(lastDoc.id),
        );
      }
    }

    return HealthTimelineSourceBatch(
      items: mapped,
      exhausted: exhausted && mapped.length < want,
      truncated:
          !exhausted &&
          mapped.isEmpty &&
          lastFetched == null &&
          snap.docs.isNotEmpty,
      lastFetched: lastFetched ?? after,
    );
  }

  String _cursorIdForDoc(String docId) {
    if (sourceKey == HealthTimelineMappers.sourceFeedingEvents ||
        sourceKey == HealthTimelineMappers.sourceFeedings) {
      return 'feeding:$docId';
    }
    return HealthTimelineMappers.globalId(sourceKey, docId);
  }

  static bool _comesAfterCursor(
    HealthTimelineSourceReaderCursor after,
    HealthTimelineEntryView entry,
  ) {
    final byTime = entry.occurredAt.compareTo(after.lastOccurredAt);
    if (byTime != 0) {
      return entry.occurredAt.isBefore(after.lastOccurredAt);
    }
    return entry.id.compareTo(after.lastId) > 0;
  }
}

/// Factories das fontes SAFE/PARTIAL comprovadas.
abstract final class FirestoreTimelineReaders {
  FirestoreTimelineReaders._();

  static HealthTimelineSourceReader healthEvents({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceHealthEvents,
      dateField: 'date',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapHealthEvent(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
              ),
    );
  }

  static HealthTimelineSourceReader weightRecords({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceWeightRecords,
      dateField: 'measured_at',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapWeightRecord(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
              ),
    );
  }

  static HealthTimelineSourceReader feedingEvents({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceFeedingEvents,
      dateField: 'fed_at',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapFeeding(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
                sourceKey: HealthTimelineMappers.sourceFeedingEvents,
              ),
    );
  }

  static HealthTimelineSourceReader feedings({FirebaseFirestore? firestore}) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceFeedings,
      dateField: 'fed_at',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapFeeding(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
                sourceKey: HealthTimelineMappers.sourceFeedings,
              ),
    );
  }

  static HealthTimelineSourceReader mealLogs({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceMealLogs,
      dateField: 'fed_at',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapCanonicalMealLog(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
              ),
    );
  }

  static HealthTimelineSourceReader supplementLogs({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceSupplementLogs,
      dateField: 'administered_at',
      firestore: firestore,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapCanonicalSupplementLog(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
              ),
    );
  }

  /// Vacinas raiz — **sem** orderBy servidor (índice composto ausente).
  static HealthTimelineSourceReader legacyVacinas({
    FirebaseFirestore? firestore,
  }) {
    return FirestoreOrderedTimelineReader(
      sourceKey: HealthTimelineMappers.sourceVacinas,
      dateField: 'dataAplicacao',
      firestore: firestore,
      isRootCollection: true,
      rootDogIdField: 'caoId',
      clientSideOrderOnly: true,
      maxDocsPerBatchHardCap: 100,
      tryMap:
          ({required dogId, required docId, required data, required filters}) =>
              HealthTimelineMappers.mapLegacyVacina(
                dogId: dogId,
                docId: docId,
                data: data,
                filters: filters,
              ),
    );
  }
}
