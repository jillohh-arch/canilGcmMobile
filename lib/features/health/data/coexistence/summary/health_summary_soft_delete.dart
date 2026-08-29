import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Resultado de varredura paginada com filtro de soft-delete no cliente.
///
/// Distingue:
/// - [exhausted]: coleção **provada** esgotada (página curta/vazia) ou target atingido
///   com fim natural irrelevante;
/// - [truncated]: parou em [maxPages] com última página **cheia** e
///   `items.length < targetActive` — **não** prova ausência.
final class HealthSummaryPaginatedActiveResult<T> {
  const HealthSummaryPaginatedActiveResult({
    required this.items,
    required this.exhausted,
    required this.truncated,
    this.pagesScanned = 0,
  });

  final List<T> items;

  /// Há evidência de que não há mais documentos a ler (ou target já coberto).
  final bool exhausted;

  /// Teto de páginas atingido sem target e sem prova de fim da coleção.
  final bool truncated;

  final int pagesScanned;

  /// Vazio **conclusivo** — seguro para notRecorded / fallback.
  bool get isConclusiveEmpty => items.isEmpty && exhausted && !truncated;

  /// Target de ativos atingido (sucesso útil).
  bool get reachedTarget => items.isNotEmpty && !truncated;
}

/// Varredura truncada por [maxPages] sem esgotar a coleção.
///
/// Readers devem mapear para `unavailable`, **não** `notRecorded` nem fallback.
final class HealthSummaryScanTruncatedException implements Exception {
  HealthSummaryScanTruncatedException({
    required this.scope,
    required this.pageSize,
    required this.maxPages,
    required this.targetActive,
    required this.pagesScanned,
    required this.itemsFound,
  });

  final String scope;
  final int pageSize;
  final int maxPages;
  final int targetActive;
  final int pagesScanned;
  final int itemsFound;

  @override
  String toString() =>
      'HealthSummaryScanTruncatedException($scope: pages=$pagesScanned/'
      '$maxPages pageSize=$pageSize target=$targetActive found=$itemsFound)';
}

/// Utilitários de soft-delete e janela paginada para o Resumo (2D/2E-R).
///
/// Contrato alinhado a [SoftDeletable.activeOnly]:
/// - `deleted_at == null` ou ausente → **ativo**
/// - qualquer valor não-nulo em `deleted_at` → **soft-deleted**
///
/// ## Por que paginar
/// `orderBy` + `limit` no servidor **antes** do filtro de soft-delete no
/// cliente pode retornar só documentos deletados e esconder ativos mais
/// antigos (perda silenciosa). A coleta pagina até atingir [targetActive]
/// itens mapeados, esgotar a coleção, ou atingir [maxPages].
///
/// ## Truncamento ≠ vazio
/// Se [maxPages] for atingido com última página cheia e sem target,
/// o resultado é [HealthSummaryPaginatedActiveResult.truncated] — a camada
/// **não** pode afirmar “não existe registro”.
abstract final class HealthSummarySoftDelete {
  HealthSummarySoftDelete._();

  /// Página padrão e teto de varredura (custo controlado, sem full scan).
  static const int defaultPageSize = 50;
  static const int defaultMaxPages = 6; // ≤ 300 docs

  /// Soft-deleted se e somente se `deleted_at` está presente e não-nulo.
  static bool isSoftDeleted(Map<String, dynamic> data) {
    return data['deleted_at'] != null;
  }

  /// Acumula itens ativos a partir de páginas já ordenadas (mais recente primeiro).
  ///
  /// Preferir [collectActiveFromPagesResult] quando o caller precisar de
  /// exhausted/truncated. Este método devolve só a lista (compat).
  static List<T> collectActiveFromPages<T>({
    required List<List<Map<String, dynamic>>> pages,
    required T? Function(Map<String, dynamic> data, int pageIndex, int docIndex)
    tryMap,
    required int targetActive,
    int pageSize = defaultPageSize,
    int maxPages = defaultMaxPages,
  }) {
    return collectActiveFromPagesResult(
      pages: pages,
      tryMap: tryMap,
      targetActive: targetActive,
      pageSize: pageSize,
      maxPages: maxPages,
    ).items;
  }

  /// Variante com semântica exhausted / truncated.
  static HealthSummaryPaginatedActiveResult<T> collectActiveFromPagesResult<T>({
    required List<List<Map<String, dynamic>>> pages,
    required T? Function(Map<String, dynamic> data, int pageIndex, int docIndex)
    tryMap,
    required int targetActive,
    int pageSize = defaultPageSize,
    int maxPages = defaultMaxPages,
  }) {
    if (targetActive <= 0) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: const [],
        exhausted: true,
        truncated: false,
        pagesScanned: 0,
      );
    }

    final out = <T>[];
    var pagesScanned = 0;
    var lastPageLen = 0;
    var stoppedForShortPage = false;
    var stoppedForTarget = false;

    final pageLimit = pages.length < maxPages ? pages.length : maxPages;
    for (var p = 0; p < pageLimit; p++) {
      final page = pages[p];
      lastPageLen = page.length;
      pagesScanned++;

      for (var i = 0; i < page.length; i++) {
        final mapped = tryMap(page[i], p, i);
        if (mapped == null) continue;
        out.add(mapped);
        if (out.length >= targetActive) {
          stoppedForTarget = true;
          break;
        }
      }
      if (stoppedForTarget) break;

      // Página curta ou vazia = fim real da coleção.
      if (page.length < pageSize) {
        stoppedForShortPage = true;
        break;
      }
    }

    return _finalizeResult(
      items: out,
      pagesScanned: pagesScanned,
      lastPageLen: lastPageLen,
      pageSize: pageSize,
      maxPages: maxPages,
      targetActive: targetActive,
      stoppedForTarget: stoppedForTarget,
      stoppedForShortPage: stoppedForShortPage,
      noPages: pages.isEmpty,
    );
  }

  /// Janela única (equivale a limit server-side + filtro cliente sem paginar).
  static List<T> collectActiveFromSingleWindow<T>({
    required List<Map<String, dynamic>> window,
    required T? Function(Map<String, dynamic> data) tryMap,
  }) {
    final out = <T>[];
    for (final data in window) {
      final mapped = tryMap(data);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  /// Lê query ordenada com paginação até [targetActive] mapeados.
  ///
  /// Ver [HealthSummaryPaginatedActiveResult.truncated] quando o teto impede
  /// afirmar ausência.
  static Future<HealthSummaryPaginatedActiveResult<T>> paginateActiveMapped<T>({
    required Query<Map<String, dynamic>> orderedQuery,
    required T? Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
    tryMap,
    required int targetActive,
    int pageSize = defaultPageSize,
    int maxPages = defaultMaxPages,
    String debugScope = 'health_events',
  }) async {
    if (targetActive <= 0) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: const [],
        exhausted: true,
        truncated: false,
        pagesScanned: 0,
      );
    }

    final out = <T>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    var pagesScanned = 0;
    var lastPageLen = 0;
    var stoppedForShortPage = false;
    var stoppedForTarget = false;

    while (pagesScanned < maxPages && out.length < targetActive) {
      Query<Map<String, dynamic>> pageQuery = orderedQuery.limit(pageSize);
      if (cursor != null) {
        pageQuery = pageQuery.startAfterDocument(cursor);
      }

      final snap = await pageQuery.get();
      lastPageLen = snap.docs.length;
      pagesScanned++;

      if (snap.docs.isEmpty) {
        stoppedForShortPage = true;
        break;
      }

      for (final doc in snap.docs) {
        final mapped = tryMap(doc);
        if (mapped == null) continue;
        out.add(mapped);
        if (out.length >= targetActive) {
          stoppedForTarget = true;
          break;
        }
      }

      cursor = snap.docs.last;
      if (stoppedForTarget) break;

      if (snap.docs.length < pageSize) {
        stoppedForShortPage = true;
        break;
      }
    }

    final result = _finalizeResult(
      items: out,
      pagesScanned: pagesScanned,
      lastPageLen: lastPageLen,
      pageSize: pageSize,
      maxPages: maxPages,
      targetActive: targetActive,
      stoppedForTarget: stoppedForTarget,
      stoppedForShortPage: stoppedForShortPage,
      noPages: pagesScanned == 0,
    );

    if (result.truncated) {
      debugPrint(
        '[HealthSummarySoftDelete] truncated scope=$debugScope '
        'pages=$pagesScanned/$maxPages pageSize=$pageSize '
        'target=$targetActive found=${out.length}',
      );
    }

    return result;
  }

  static HealthSummaryPaginatedActiveResult<T> _finalizeResult<T>({
    required List<T> items,
    required int pagesScanned,
    required int lastPageLen,
    required int pageSize,
    required int maxPages,
    required int targetActive,
    required bool stoppedForTarget,
    required bool stoppedForShortPage,
    required bool noPages,
  }) {
    if (stoppedForTarget) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: List<T>.unmodifiable(items),
        exhausted: false,
        truncated: false,
        pagesScanned: pagesScanned,
      );
    }

    // Sem páginas / página curta / vazia → fim real.
    if (noPages || stoppedForShortPage || lastPageLen < pageSize) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: List<T>.unmodifiable(items),
        exhausted: true,
        truncated: false,
        pagesScanned: pagesScanned,
      );
    }

    // Última página cheia e target não atingido.
    if (pagesScanned >= maxPages && lastPageLen >= pageSize) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: List<T>.unmodifiable(items),
        exhausted: false,
        truncated: true,
        pagesScanned: pagesScanned,
      );
    }

    // Páginas fornecidas acabaram com última cheia, mas abaixo de maxPages
    // (lista de teste incompleta): tratar como truncated se target não atingido.
    if (lastPageLen >= pageSize && items.length < targetActive) {
      return HealthSummaryPaginatedActiveResult<T>(
        items: List<T>.unmodifiable(items),
        exhausted: false,
        truncated: true,
        pagesScanned: pagesScanned,
      );
    }

    return HealthSummaryPaginatedActiveResult<T>(
      items: List<T>.unmodifiable(items),
      exhausted: true,
      truncated: false,
      pagesScanned: pagesScanned,
    );
  }
}
