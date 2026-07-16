import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_timeline_cursor_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/health_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Paginador multiorigem com cursor self-contained + residual.
///
/// Invariantes:
/// - zero perda silenciosa (residual no cursor);
/// - zero duplicação por id global;
/// - ordem `occurredAt DESC`, `id ASC`;
/// - cursor recriável sem memória de instância;
/// - cursor inválido **nunca** reinicia a timeline silenciosamente;
/// - emissão **watermark-safe**: nunca emite item que possa ser precedido por
///   documento ainda não lido de uma fonte aberta.
final class MultiSourceTimelinePaginator {
  MultiSourceTimelinePaginator({
    required List<HealthTimelineSourceReader> readers,
    this.batchSizeMultiplier = 1,
  }) : _readers = List.unmodifiable(
         List<HealthTimelineSourceReader>.of(readers),
       ) {
    if (_readers.isEmpty) {
      throw ArgumentError('paginator exige ao menos um reader');
    }
  }

  final List<HealthTimelineSourceReader> _readers;
  final int batchSizeMultiplier;

  Future<HealthTimelinePage> loadPage(
    HealthTimelineQuery query, {
    bool vaccinationFallbackEnabled = false,
    bool vaccinationFallbackDecided = false,
  }) async {
    // decode lança se cursor presente e inválido / de outra query.
    final decoded = CoexistenceTimelineCursorCodec.decode(
      query.cursor,
      query: query,
    );

    final sourceKeys = _readers.map((r) => r.sourceKey).toList(growable: false);

    final state =
        decoded ??
        CoexistenceTimelineCursorCodec.initial(
          query: query,
          sourceKeys: sourceKeys,
          vaccinationFallbackEnabled: vaccinationFallbackEnabled,
          vaccinationFallbackDecided: vaccinationFallbackDecided,
        );

    final vacEnabled =
        decoded?.vaccinationFallbackEnabled ?? vaccinationFallbackEnabled;
    final vacDecided =
        decoded?.vaccinationFallbackDecided ?? vaccinationFallbackDecided;

    final sources = <String, CoexistenceSourceCursorState>{
      for (final k in sourceKeys)
        k: state.sources[k] ?? const CoexistenceSourceCursorState(),
    };

    var residual = List<HealthTimelineEntryView>.of(state.residual);
    final seenIds = residual.map((e) => e.id).toSet();
    final pageSize = query.pageSize;
    final batchSize = (pageSize * batchSizeMultiplier).clamp(1, 100);

    var safetyRounds = 0;
    const maxRounds = 80;

    // Buffer de candidatos + watermark: só emite o que é globalmente seguro.
    while (_safePrefix(residual, sources).length < pageSize &&
        safetyRounds < maxRounds) {
      safetyRounds++;
      var anyOpen = false;
      var progressed = false;

      for (final reader in _readers) {
        final key = reader.sourceKey;
        final src = sources[key]!;
        if (src.exhausted) continue;
        anyOpen = true;

        late final HealthTimelineSourceBatch batch;
        try {
          batch = await reader.fetchBatch(
            dogId: query.dogId,
            batchSize: batchSize,
            after: src.after,
            filters: query,
          );
        } on HealthTimelineSourceException {
          rethrow;
        } catch (e) {
          throw HealthTimelineSourceException(
            TimelineErrorSanitizer.publicMessage(e),
          );
        }

        if (batch.truncated) {
          throw const HealthTimelineSourceException(
            'Varredura truncada em uma das fontes; '
            'não é possível garantir histórico completo.',
          );
        }

        for (final item in batch.items) {
          if (seenIds.add(item.id)) {
            residual.add(item);
            progressed = true;
          }
        }

        final newAfter = batch.lastFetched ?? src.after;
        final exhausted = batch.exhausted;
        if (newAfter != src.after || exhausted != src.exhausted) {
          progressed = true;
        }

        sources[key] = CoexistenceSourceCursorState(
          after: newAfter,
          exhausted: exhausted,
        );
      }

      residual = sortTimelineEntries(residual);

      if (!anyOpen) break;
      if (!progressed) break;

      // Se o prefixo seguro não cresceu e ainda precisamos de itens, continua
      // buscando até esgotar ou estagnar.
    }

    residual = sortTimelineEntries(residual);
    final allExhausted = _readers.every((r) => sources[r.sourceKey]!.exhausted);

    final safe = _safePrefix(residual, sources);

    if (safe.isEmpty) {
      if (allExhausted && residual.isEmpty) {
        return HealthTimelinePage.empty();
      }
      if (allExhausted && residual.isNotEmpty) {
        // Todas esgotadas: residual inteiro é seguro.
        return _buildPage(
          query: query,
          residual: residual,
          sources: sources,
          vacEnabled: vacEnabled,
          vacDecided: vacDecided,
          pageSize: pageSize,
          allExhausted: true,
        );
      }
      throw const HealthTimelineSourceException(
        'Não foi possível montar página com integridade garantida '
        '(fontes sem progresso conclusivo).',
      );
    }

    // Monta página a partir do prefixo seguro; o restante (safe tail + unsafe)
    // permanece no residual.
    return _buildPage(
      query: query,
      residual: residual,
      sources: sources,
      vacEnabled: vacEnabled,
      vacDecided: vacDecided,
      pageSize: pageSize,
      allExhausted: allExhausted,
      safeCount: safe.length,
    );
  }

  /// Itens de [residual] (já ordenado) que podem ser emitidos sem risco de
  /// haver documento ainda não lido de fonte aberta que deva vir antes.
  ///
  /// Regra: X é seguro se, para toda fonte aberta S com cursor L_s,
  /// `compareTimelineEntries(X, synthetic(L_s)) <= 0` — ou seja, X aparece
  /// antes ou na posição de L_s. Qualquer documento ainda não lido de S vem
  /// **depois** de L_s, logo depois de X.
  static List<HealthTimelineEntryView> _safePrefix(
    List<HealthTimelineEntryView> residual,
    Map<String, CoexistenceSourceCursorState> sources,
  ) {
    if (residual.isEmpty) return const [];

    final openWatermarks = <HealthTimelineSourceReaderCursor>[];
    for (final src in sources.values) {
      if (src.exhausted) continue;
      final after = src.after;
      if (after == null) {
        // Fonte aberta sem nenhuma leitura: nada é seguro ainda.
        return const [];
      }
      openWatermarks.add(after);
    }

    // Todas esgotadas: residual inteiro é seguro.
    if (openWatermarks.isEmpty) {
      return residual;
    }

    final safe = <HealthTimelineEntryView>[];
    for (final item in residual) {
      var ok = true;
      for (final wm in openWatermarks) {
        if (!_isAtOrBeforeWatermark(item, wm)) {
          ok = false;
          break;
        }
      }
      if (!ok) break; // residual ordenado: a partir daqui tudo é unsafe
      safe.add(item);
    }
    return safe;
  }

  /// true se [item] deve aparecer **antes ou na** posição do watermark
  /// (compare(item, wm) <= 0 na ordem global DESC time / ASC id).
  static bool _isAtOrBeforeWatermark(
    HealthTimelineEntryView item,
    HealthTimelineSourceReaderCursor wm,
  ) {
    // compare(item, wmEntry) <= 0 na ordem global (DESC time, ASC id).
    final timeCmp = wm.lastOccurredAt.compareTo(item.occurredAt);
    // compare(item, wm) time part = wm.time.compareTo(item.time) = timeCmp
    if (timeCmp != 0) {
      // timeCmp > 0 ⇒ wm more recent than item ⇒ item after wm ⇒ unsafe
      // timeCmp < 0 ⇒ item more recent than wm ⇒ item before wm ⇒ safe
      return timeCmp < 0;
    }
    // Mesmo timestamp: id ASC — item antes ou igual se item.id <= wm.id
    return item.id.compareTo(wm.lastId) <= 0;
  }

  static HealthTimelinePage _buildPage({
    required HealthTimelineQuery query,
    required List<HealthTimelineEntryView> residual,
    required Map<String, CoexistenceSourceCursorState> sources,
    required bool vacEnabled,
    required bool vacDecided,
    required int pageSize,
    required bool allExhausted,
    int? safeCount,
  }) {
    final safeLen = safeCount ?? residual.length;
    final take = safeLen <= pageSize ? safeLen : pageSize;
    if (take == 0) {
      if (allExhausted) return HealthTimelinePage.empty();
      throw const HealthTimelineSourceException(
        'Não foi possível montar página com integridade garantida '
        '(fontes sem progresso conclusivo).',
      );
    }

    final pageItems = residual.sublist(0, take);
    final nextResidual = residual.length > take
        ? residual.sublist(take)
        : const <HealthTimelineEntryView>[];

    if (nextResidual.length >
        CoexistenceTimelineCursorCodec.maxResidualEntries) {
      throw const HealthTimelineSourceException(
        'Buffer residual de paginação excedeu o limite seguro.',
      );
    }

    final hasMore = nextResidual.isNotEmpty || !allExhausted;

    return HealthTimelinePage(
      items: pageItems,
      nextCursor: hasMore
          ? CoexistenceTimelineCursorCodec.encode(
              CoexistenceTimelineCursorState(
                version: CoexistenceTimelineCursorState.currentVersion,
                dogId: query.dogId,
                filterFingerprint:
                    CoexistenceTimelineCursorCodec.filterFingerprint(query),
                sources: sources,
                residual: nextResidual,
                vaccinationFallbackEnabled: vacEnabled,
                vaccinationFallbackDecided: vacDecided,
              ),
            )
          : null,
      hasMore: hasMore,
    );
  }
}

/// Sanitização de erros de subfonte / Firebase para mensagens públicas.
abstract final class TimelineErrorSanitizer {
  TimelineErrorSanitizer._();

  static String publicMessage(Object error, {String? code}) {
    final c = (code ?? '').toLowerCase();
    if (c == 'unavailable' || c == 'network-request-failed') {
      return 'Sem conexão para carregar o histórico clínico.';
    }
    if (c == 'permission-denied') {
      return 'Sem permissão para carregar o histórico clínico.';
    }
    if (c == 'failed-precondition') {
      return 'Consulta de histórico temporariamente indisponível.';
    }

    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('permission-denied') ||
        lower.contains('permission_denied')) {
      return 'Sem permissão para carregar o histórico clínico.';
    }
    if (lower.contains('unavailable') ||
        lower.contains('network-request-failed') ||
        lower.contains('socket') ||
        lower.contains('offline')) {
      return 'Sem conexão para carregar o histórico clínico.';
    }
    if (lower.contains('failed-precondition') ||
        lower.contains('requires an index') ||
        lower.contains('googleapis.com')) {
      return 'Consulta de histórico temporariamente indisponível.';
    }
    if (lower.contains('.dart') ||
        lower.contains('firebase') ||
        lower.contains('stack') ||
        raw.length > 180) {
      return 'Falha ao carregar o histórico clínico.';
    }
    return 'Falha ao carregar o histórico clínico.';
  }

  static bool looksLikeOffline(Object error, {String? code}) {
    final c = (code ?? '').toLowerCase();
    if (c == 'unavailable' || c == 'network-request-failed') return true;
    final lower = error.toString().toLowerCase();
    return lower.contains('unavailable') ||
        lower.contains('network-request-failed') ||
        lower.contains('socketexception') ||
        lower.contains('offline');
  }
}
