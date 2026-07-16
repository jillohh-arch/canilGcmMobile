import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_grouping.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';

/// Controller da timeline Health v1 (ChangeNotifier).
///
/// Responsabilidades:
/// - configurar query estruturada;
/// - carregar primeira página / refresh / loadMore;
/// - trocar cão e filtros com isolamento de identidade;
/// - race protection por generation token;
/// - dedupe por id + ordenação determinística;
/// - preservar lista em falha de loadMore;
/// - não conhecer Firebase/Firestore.
///
/// ## Identidade lógica
/// dogId + tipos + período + caseId + profissional + pageSize
/// ([HealthTimelineFilterIdentity]). Cursor **não** entra na identidade.
///
/// ## Race protection
/// Toda mutação de query (setQuery, selectDog, applyFilters, refresh)
/// incrementa [_generation]. Respostas com generation antiga são ignoradas.
/// loadMore captura a generation atual sem incrementar; refresh invalida
/// loadMore em andamento.
class HealthTimelineController extends ChangeNotifier {
  HealthTimelineController({required HealthTimelineSource source})
    : _source = source;

  final HealthTimelineSource _source;

  HealthTimelineState _state = const HealthTimelineInitial();
  HealthTimelineQuery? _activeQuery;
  HealthTimelineCursor? _nextCursor;
  bool _disposed = false;
  int _generation = 0;

  /// Snapshot utilizável da identidade atual (para refresh/error/offline).
  HealthTimelineSnapshot? _currentSnapshot;

  HealthTimelineState get state => _state;

  HealthTimelineQuery? get activeQuery => _activeQuery;

  String? get activeDogId => _activeQuery?.dogId;

  /// Define a query ativa e carrega a primeira página.
  ///
  /// Cursor da [query] é descartado (sempre inicia do começo).
  Future<void> setQuery(HealthTimelineQuery query) async {
    if (_disposed) return;
    final firstPageQuery = query.withoutCursor();
    final generation = ++_generation;
    _activeQuery = firstPageQuery;
    _nextCursor = null;
    _currentSnapshot = null;
    _setState(HealthTimelineLoading(query: firstPageQuery));
    await _loadFirstPage(generation: generation, query: firstPageQuery);
  }

  /// Troca o cão mantendo filtros estruturados (tipos/período/caso/profissional).
  ///
  /// Se ainda não houver query ativa, cria query mínima só com [dogId].
  Future<void> selectDog(String dogId) async {
    if (_disposed) return;
    final current = _activeQuery;
    final next = current == null
        ? HealthTimelineQuery(dogId: dogId)
        : current.copyWith(dogId: dogId, clearCursor: true);
    await setQuery(next);
  }

  /// Aplica filtros estruturados ao cão ativo (ou ao [dogId] informado).
  ///
  /// Não inclui busca textual (fora do Health v1).
  Future<void> applyFilters({
    String? dogId,
    Set<HealthTimelineType>? types,
    HealthTimelinePeriod? period,
    String? caseId,
    bool clearCaseId = false,
    HealthTimelineProfessionalFilter? professional,
    bool clearProfessional = false,
    int? pageSize,
  }) async {
    if (_disposed) return;
    final baseDogId = dogId ?? _activeQuery?.dogId;
    if (baseDogId == null) {
      throw StateError(
        'applyFilters exige dogId (informe dogId ou chame selectDog/setQuery)',
      );
    }
    final current = _activeQuery;
    final next = HealthTimelineQuery(
      dogId: baseDogId,
      types: types ?? current?.types ?? const {},
      period: period ?? current?.period,
      caseId: clearCaseId ? null : (caseId ?? current?.caseId),
      professional: clearProfessional
          ? null
          : (professional ?? current?.professional),
      pageSize:
          pageSize ?? current?.pageSize ?? HealthTimelineQuery.defaultPageSize,
    );
    await setQuery(next);
  }

  /// Recarrega a primeira página da identidade atual.
  ///
  /// - descarta cursor (restaura se o refresh falhar e a lista for preservada);
  /// - invalida loadMore em andamento;
  /// - se já houver dados da mesma identidade, mantém lista visível
  ///   com [HealthTimelineSnapshot.isRefreshing] == true.
  Future<void> refresh() async {
    if (_disposed) return;
    final query = _activeQuery;
    if (query == null) {
      throw StateError('refresh exige query ativa (chame setQuery/selectDog)');
    }
    final firstPageQuery = query.withoutCursor();
    final generation = ++_generation;
    _activeQuery = firstPageQuery;
    // Guarda cursor atual para restaurar se o refresh falhar com lista preservada.
    // Sem isso, hasMore=true + cursor null impede loadMore após refresh offline.
    final cursorBeforeRefresh = _nextCursor;
    _nextCursor = null;

    final existing = _currentSnapshot;
    if (existing != null &&
        existing.filterIdentity == firstPageQuery.filterIdentity &&
        existing.items.isNotEmpty) {
      final refreshing = existing.copyWith(
        isRefreshing: true,
        isLoadingMore: false,
        clearLoadMoreError: true,
        // Limpa falha anterior enquanto tenta de novo; se falhar de novo,
        // _applyFirstPageFailure regrava lastRefreshError.
        clearLastRefreshError: true,
        query: firstPageQuery,
      );
      _currentSnapshot = refreshing;
      _setState(HealthTimelineData(snapshot: refreshing));
    } else if (existing != null &&
        existing.filterIdentity == firstPageQuery.filterIdentity &&
        existing.items.isEmpty) {
      _setState(HealthTimelineEmpty(query: firstPageQuery, isRefreshing: true));
    } else {
      _currentSnapshot = null;
      _setState(HealthTimelineLoading(query: firstPageQuery));
    }

    await _loadFirstPage(
      generation: generation,
      query: firstPageQuery,
      preserveOnFailure: true,
      restoreCursorOnFailure: cursorBeforeRefresh,
    );
  }

  /// Carrega a próxima página quando [hasMore] e há dados.
  ///
  /// Falha de loadMore **não** transforma a timeline em error global.
  Future<void> loadMore() async {
    if (_disposed) return;
    final query = _activeQuery;
    final snapshot = _currentSnapshot;
    final cursor = _nextCursor;
    if (query == null || snapshot == null) return;
    // Spec: só com dados utilizáveis (não empty/loading/error).
    if (snapshot.items.isEmpty) return;
    if (!snapshot.hasMore || cursor == null) return;
    if (snapshot.isLoadingMore || snapshot.isRefreshing) return;
    // Estado público deve ser data; evita loadMore a partir de empty com
    // snapshot interno residual (edge case de source vazia + hasMore).
    if (_state is! HealthTimelineData) return;

    // Captura generation atual — refresh/setQuery incrementam e invalidam.
    final generation = _generation;
    final loading = snapshot.copyWith(
      isLoadingMore: true,
      clearLoadMoreError: true,
    );
    _currentSnapshot = loading;
    _setState(HealthTimelineData(snapshot: loading));

    final pageQuery = query.copyWith(cursor: cursor);

    try {
      final page = await _source.loadPage(pageQuery);
      if (!_isCurrent(generation, query.filterIdentity)) return;

      final merged = mergeTimelineEntries(
        existing: snapshot.items,
        incoming: page.items,
      );
      final next = HealthTimelineSnapshot(
        items: merged,
        hasMore: page.hasMore,
        query: query.withoutCursor(),
        isRefreshing: false,
        isLoadingMore: false,
        // Preserva sinal de refresh falho até um refresh/1ª página ok.
        lastRefreshError: snapshot.lastRefreshError,
        lastRefreshWasOffline: snapshot.lastRefreshWasOffline,
      );
      _nextCursor = page.nextCursor;
      _currentSnapshot = next;
      _setState(HealthTimelineData(snapshot: next));
    } catch (error) {
      if (!_isCurrent(generation, query.filterIdentity)) return;
      final message = _messageOf(error);
      final failed = snapshot.copyWith(
        isLoadingMore: false,
        loadMoreError: message,
      );
      _currentSnapshot = failed;
      _setState(HealthTimelineData(snapshot: failed));
    }
  }

  Future<void> _loadFirstPage({
    required int generation,
    required HealthTimelineQuery query,
    bool preserveOnFailure = false,
    HealthTimelineCursor? restoreCursorOnFailure,
  }) async {
    try {
      final page = await _source.loadPage(query.withoutCursor());
      if (!_isCurrent(generation, query.filterIdentity)) return;
      _applyFirstPage(query: query, page: page);
    } catch (error) {
      if (!_isCurrent(generation, query.filterIdentity)) return;
      _applyFirstPageFailure(
        query: query,
        error: error,
        preserveOnFailure: preserveOnFailure,
        restoreCursorOnFailure: restoreCursorOnFailure,
      );
    }
  }

  void _applyFirstPage({
    required HealthTimelineQuery query,
    required HealthTimelinePage page,
  }) {
    _nextCursor = page.nextCursor;
    final sorted = sortTimelineEntries(page.items);
    // Dedupe na primeira página (source pode sobrepor).
    final deduped = mergeTimelineEntries(existing: const [], incoming: sorted);
    final snapshot = HealthTimelineSnapshot(
      items: deduped,
      hasMore: page.hasMore,
      query: query.withoutCursor(),
      isRefreshing: false,
      isLoadingMore: false,
      // Sucesso de 1ª página limpa falha de refresh anterior.
      lastRefreshError: null,
      lastRefreshWasOffline: false,
    );
    _currentSnapshot = snapshot;

    // Empty: sem itens utilizáveis. loadMore exige items não vazios.
    // Cursor residual de source inconsistente (empty+hasMore) é descartado.
    if (deduped.isEmpty) {
      _nextCursor = null;
      _currentSnapshot = HealthTimelineSnapshot(
        items: const [],
        hasMore: false,
        query: query.withoutCursor(),
      );
      _setState(HealthTimelineEmpty(query: query.withoutCursor()));
      return;
    }

    _setState(HealthTimelineData(snapshot: snapshot));
  }

  void _applyFirstPageFailure({
    required HealthTimelineQuery query,
    required Object error,
    required bool preserveOnFailure,
    HealthTimelineCursor? restoreCursorOnFailure,
  }) {
    final isOffline = error is HealthTimelineSourceException && error.isOffline;
    final message = _messageOf(error);

    HealthTimelineSnapshot? lastKnown;
    if (preserveOnFailure) {
      final existing = _currentSnapshot;
      if (existing != null &&
          existing.filterIdentity == query.filterIdentity &&
          existing.items.isNotEmpty) {
        lastKnown = existing.copyWith(
          isRefreshing: false,
          isLoadingMore: false,
          clearLoadMoreError: true,
          query: query.withoutCursor(),
          lastRefreshError: message,
          lastRefreshWasOffline: isOffline,
        );
      }
    }

    if (isOffline) {
      if (lastKnown != null) {
        // Offline com dados da mesma identidade: mantém lista + sinaliza falha.
        // Restaura cursor pré-refresh para loadMore continuar coerente com hasMore.
        _nextCursor = restoreCursorOnFailure;
        _currentSnapshot = lastKnown;
        _setState(HealthTimelineData(snapshot: lastKnown));
        return;
      }
      _currentSnapshot = null;
      _setState(
        HealthTimelineOffline(query: query.withoutCursor(), lastKnown: null),
      );
      return;
    }

    if (lastKnown != null) {
      // Erro no refresh: preserva dados + mensagem em lastRefreshError.
      _nextCursor = restoreCursorOnFailure;
      _currentSnapshot = lastKnown;
      _setState(HealthTimelineData(snapshot: lastKnown));
      return;
    }

    _currentSnapshot = null;
    _setState(
      HealthTimelineError(
        query: query.withoutCursor(),
        message: message,
        lastKnown: null,
      ),
    );
  }

  bool _isCurrent(int generation, HealthTimelineFilterIdentity identity) {
    if (_disposed) return false;
    if (generation != _generation) return false;
    final active = _activeQuery;
    if (active == null) return false;
    return active.filterIdentity == identity;
  }

  void _setState(HealthTimelineState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  static String _messageOf(Object error) {
    if (error is HealthTimelineSourceException) return error.message;
    return error.toString();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Invalida respostas pendentes.
    _generation++;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  int get generationForTest => _generation;

  @visibleForTesting
  HealthTimelineCursor? get nextCursorForTest => _nextCursor;

  @visibleForTesting
  HealthTimelineSnapshot? get currentSnapshotForTest => _currentSnapshot;
}
