import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Cursor interno de um reader (posição na fonte).
///
/// Não é o [HealthTimelineCursor] público — fica encapsulado no token composto.
final class HealthTimelineSourceReaderCursor {
  const HealthTimelineSourceReaderCursor({
    required this.lastOccurredAt,
    required this.lastId,
  });

  final DateTime lastOccurredAt;
  final String lastId;
}

/// Lote de uma subfonte.
final class HealthTimelineSourceBatch {
  const HealthTimelineSourceBatch({
    required this.items,
    required this.exhausted,
    this.truncated = false,
    this.lastFetched,
  });

  /// Itens já mapeados e ordenados internamente (occurredAt DESC, id ASC).
  final List<HealthTimelineEntryView> items;

  /// Fonte esgotada (sem mais documentos).
  final bool exhausted;

  /// Varredura atingiu teto sem provar exaustão — **não** é vazio legítimo.
  final bool truncated;

  /// Último documento **lido** nesta fonte (para startAfter).
  final HealthTimelineSourceReaderCursor? lastFetched;
}

/// Contrato de reader por coleção/fonte legada.
///
/// Isola query, soft-delete e mapping. Não conhece UI/controller.
abstract interface class HealthTimelineSourceReader {
  /// Chave estável da fonte (`health_events`, `weight_records`, …).
  String get sourceKey;

  /// Busca o próximo lote **após** [after] (exclusivo na ordem global da fonte).
  Future<HealthTimelineSourceBatch> fetchBatch({
    required String dogId,
    required int batchSize,
    HealthTimelineSourceReaderCursor? after,
    required HealthTimelineQuery filters,
  });
}
