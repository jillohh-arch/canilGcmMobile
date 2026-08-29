import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_mappers.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Reader em memória determinístico (testes de paginação multiorigem).
///
/// Filtra primeiro e pagina no subconjunto — adequado para gates de merge.
/// Para simular scan limitado (soft-delete / filtro esparso / unmappable),
/// use [ScanningMemoryTimelineSourceReader].
class MemoryTimelineSourceReader implements HealthTimelineSourceReader {
  MemoryTimelineSourceReader({
    required this.sourceKey,
    required List<HealthTimelineEntryView> items,
    this.failOnFetch = false,
    this.truncateAfterBatches,
    this.failMessage,
    this.failIsOffline = false,
  }) : _items = sortTimelineEntries(items);

  @override
  final String sourceKey;

  final List<HealthTimelineEntryView> _items;
  final bool failOnFetch;
  final String? failMessage;
  final bool failIsOffline;

  /// Se não-null, após N batches bem-sucedidos o próximo retorna truncated.
  final int? truncateAfterBatches;

  int _batchesServed = 0;

  @override
  Future<HealthTimelineSourceBatch> fetchBatch({
    required String dogId,
    required int batchSize,
    HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  }) async {
    if (failOnFetch) {
      throw HealthTimelineSourceException(
        failMessage ?? 'Falha ao carregar o histórico clínico.',
        isOffline: failIsOffline,
      );
    }

    if (truncateAfterBatches != null &&
        _batchesServed >= truncateAfterBatches!) {
      return const HealthTimelineSourceBatch(
        items: [],
        exhausted: false,
        truncated: true,
      );
    }
    _batchesServed++;

    final filtered = _items
        .where(
          (e) =>
              e.dogId == dogId &&
              HealthTimelineMappers.matchesFilters(e, filters),
        )
        .toList(growable: false);

    var start = 0;
    if (after != null) {
      start = filtered.length;
      for (var i = 0; i < filtered.length; i++) {
        if (_comesAfterCursor(after, filtered[i])) {
          start = i;
          break;
        }
      }
    }

    final slice = filtered.skip(start).take(batchSize).toList(growable: false);
    final exhausted = start + slice.length >= filtered.length;
    HealthTimelineSourceReaderCursor? lastFetched;
    if (slice.isNotEmpty) {
      final last = slice.last;
      lastFetched = HealthTimelineSourceReaderCursor(
        lastOccurredAt: last.occurredAt,
        lastId: last.id,
      );
    }

    return HealthTimelineSourceBatch(
      items: slice,
      exhausted: exhausted,
      lastFetched: lastFetched,
    );
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

/// Documento bruto ordenado para simular scan servidor + filtro cliente.
///
/// Distingue:
/// - mapped ([entry] não-null);
/// - ignored (soft-delete / filtro — [ignored] true);
/// - invalid estrutural ([invalidReason] não-null) → inconclusivo.
final class MemoryTimelineScanDoc {
  /// Documento mapeável (entry completa).
  MemoryTimelineScanDoc.mapped({
    required this.id,
    required HealthTimelineEntryView this.entry,
  }) : occurredAt = entry.occurredAt,
       ignored = false,
       invalidReason = null;

  /// Soft-deleted ou irrelevante (não bloqueia).
  const MemoryTimelineScanDoc.ignored({
    required this.id,
    required this.occurredAt,
  }) : entry = null,
       ignored = true,
       invalidReason = null;

  /// Ativo relevante estruturalmente unmappable.
  const MemoryTimelineScanDoc.invalid({
    required this.id,
    required this.occurredAt,
    required TimelineMappingInvalidReason this.invalidReason,
  }) : entry = null,
       ignored = false;

  /// Id global estável (ex.: `src:doc-1`).
  final String id;

  /// Posição de scan (só para ordenar o harness; não inventa data de negócio).
  final DateTime occurredAt;

  final HealthTimelineEntryView? entry;
  final bool ignored;
  final TimelineMappingInvalidReason? invalidReason;
}

/// Reader que simula `orderBy + limit` no servidor e filtro no cliente.
///
/// - [MemoryTimelineScanDoc.ignored] → avança cursor, não emite;
/// - [MemoryTimelineScanDoc.invalid] → [HealthTimelineSourceException]
///   inconclusiva (não empty, não parcial);
/// - mapped → emite se passar filtros.
class ScanningMemoryTimelineSourceReader implements HealthTimelineSourceReader {
  ScanningMemoryTimelineSourceReader({
    required this.sourceKey,
    required List<MemoryTimelineScanDoc> docs,
    this.scanCap = 60,
    this.failOnFetch = false,
  }) : _docs = List<MemoryTimelineScanDoc>.of(docs)
         ..sort((a, b) {
           final byTime = b.occurredAt.compareTo(a.occurredAt);
           if (byTime != 0) return byTime;
           return a.id.compareTo(b.id);
         });

  @override
  final String sourceKey;

  final List<MemoryTimelineScanDoc> _docs;
  final int scanCap;
  final bool failOnFetch;

  @override
  Future<HealthTimelineSourceBatch> fetchBatch({
    required String dogId,
    required int batchSize,
    HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  }) async {
    if (failOnFetch) {
      throw const HealthTimelineSourceException(
        'Falha ao carregar o histórico clínico.',
      );
    }

    var start = 0;
    if (after != null) {
      start = _docs.length;
      for (var i = 0; i < _docs.length; i++) {
        if (_docComesAfter(after, _docs[i])) {
          start = i;
          break;
        }
      }
    }

    final want = batchSize.clamp(1, 100);
    final mapped = <HealthTimelineEntryView>[];
    var scanned = 0;
    var lastIndex = start - 1;

    for (var i = start; i < _docs.length && scanned < scanCap; i++) {
      scanned++;
      lastIndex = i;
      final doc = _docs[i];

      if (doc.invalidReason != null) {
        HealthTimelineMappers.throwInconclusive(
          sourceKey: sourceKey,
          reason: doc.invalidReason!,
        );
      }
      if (doc.ignored) continue;

      final entry = doc.entry;
      if (entry == null) continue;
      if (entry.dogId != dogId) continue;
      if (!HealthTimelineMappers.matchesFilters(entry, filters)) continue;
      if (after != null && !_entryComesAfter(after, entry)) continue;
      mapped.add(entry);
      if (mapped.length >= want) break;
    }

    final reachedEndOfCollection = lastIndex >= _docs.length - 1;
    final hitScanCap = scanned >= scanCap && !reachedEndOfCollection;

    HealthTimelineSourceReaderCursor? lastFetched;
    if (mapped.isNotEmpty) {
      final last = mapped.last;
      lastFetched = HealthTimelineSourceReaderCursor(
        lastOccurredAt: last.occurredAt,
        lastId: last.id,
      );
    } else if (lastIndex >= start && lastIndex < _docs.length) {
      final lastDoc = _docs[lastIndex];
      lastFetched = HealthTimelineSourceReaderCursor(
        lastOccurredAt: lastDoc.occurredAt,
        lastId: lastDoc.id,
      );
    }

    final truncated = hitScanCap && mapped.isEmpty && lastFetched == null;
    final exhausted =
        reachedEndOfCollection && mapped.length < want && !hitScanCap
        ? true
        : reachedEndOfCollection && mapped.isEmpty;

    return HealthTimelineSourceBatch(
      items: mapped,
      exhausted: exhausted || (reachedEndOfCollection && mapped.length < want),
      truncated: truncated,
      lastFetched: lastFetched ?? after,
    );
  }

  static bool _docComesAfter(
    HealthTimelineSourceReaderCursor after,
    MemoryTimelineScanDoc doc,
  ) {
    final byTime = doc.occurredAt.compareTo(after.lastOccurredAt);
    if (byTime != 0) {
      return doc.occurredAt.isBefore(after.lastOccurredAt);
    }
    return doc.id.compareTo(after.lastId) > 0;
  }

  static bool _entryComesAfter(
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
