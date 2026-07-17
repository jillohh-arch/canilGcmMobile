import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';

/// Controller da Agenda Preventiva Health v1 (ChangeNotifier).
///
/// Responsabilidades:
/// - configurar query estruturada;
/// - carregar primeira página / refresh / loadMore;
/// - trocar cão com isolamento de identidade;
/// - race protection por generation token;
/// - derivar estados temporais com [HealthScheduleTemporalPolicy] (única fonte);
/// - agrupar para apresentação (Atrasados / Hoje / Próximos / Programados);
/// - não conhecer Firebase/Firestore;
/// - não escrever no schema.
///
/// ## Clock
/// [clock] é injetável para testes determinísticos. Em produção usa UTC
/// absoluto (`DateTime.now().toUtc()`); o timezone de cada item participa
/// da comparação civil na política temporal.
class HealthScheduleController extends ChangeNotifier {
  HealthScheduleController({
    required HealthScheduleSource source,
    required HealthScheduleTemporalPolicy temporalPolicy,
    DateTime Function()? clock,
  }) : _source = source,
       _temporalPolicy = temporalPolicy,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final HealthScheduleSource _source;
  final HealthScheduleTemporalPolicy _temporalPolicy;
  final DateTime Function() _clock;

  HealthScheduleState _state = const HealthScheduleInitial();
  HealthScheduleQuery? _activeQuery;
  HealthScheduleCursor? _nextCursor;
  bool _disposed = false;
  int _generation = 0;
  HealthScheduleSnapshot? _currentSnapshot;

  HealthScheduleState get state => _state;
  HealthScheduleQuery? get activeQuery => _activeQuery;
  String? get activeDogId => _activeQuery?.dogId;

  /// Define a query ativa e carrega a primeira página.
  Future<void> setQuery(HealthScheduleQuery query) async {
    if (_disposed) return;
    final firstPageQuery = query.withoutCursor();
    final generation = ++_generation;
    _activeQuery = firstPageQuery;
    _nextCursor = null;
    _currentSnapshot = null;
    _setState(HealthScheduleLoading(query: firstPageQuery));
    await _loadFirstPage(generation: generation, query: firstPageQuery);
  }

  /// Troca o cão. Invalida geração anterior (respostas stale ignoradas).
  Future<void> selectDog(String dogId) async {
    if (_disposed) return;
    final current = _activeQuery;
    final next = current == null
        ? HealthScheduleQuery(dogId: dogId)
        : current.copyWith(dogId: dogId, clearCursor: true);
    await setQuery(next);
  }

  /// Aplica filtros de tipo/lifecycle ao cão ativo (ou [dogId] informado).
  Future<void> applyFilters({
    String? dogId,
    Set<ScheduleType>? types,
    Set<ScheduleLifecycleStatus>? lifecycleStatuses,
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
    final next = HealthScheduleQuery(
      dogId: baseDogId,
      types: types ?? current?.types ?? const {},
      lifecycleStatuses:
          lifecycleStatuses ?? current?.lifecycleStatuses ?? const {},
      pageSize:
          pageSize ?? current?.pageSize ?? HealthScheduleQuery.defaultPageSize,
    );
    await setQuery(next);
  }

  /// Recarrega a primeira página da identidade atual.
  Future<void> refresh() async {
    if (_disposed) return;
    final query = _activeQuery;
    if (query == null) {
      throw StateError('refresh exige query ativa (chame setQuery/selectDog)');
    }
    final firstPageQuery = query.withoutCursor();
    final generation = ++_generation;
    _activeQuery = firstPageQuery;
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
        clearLastRefreshError: true,
        query: firstPageQuery,
      );
      _currentSnapshot = refreshing;
      _setState(HealthScheduleData(snapshot: refreshing));
    } else if (existing != null &&
        existing.filterIdentity == firstPageQuery.filterIdentity &&
        existing.items.isEmpty) {
      _setState(HealthScheduleEmpty(query: firstPageQuery, isRefreshing: true));
    } else {
      _currentSnapshot = null;
      _setState(HealthScheduleLoading(query: firstPageQuery));
    }

    await _loadFirstPage(
      generation: generation,
      query: firstPageQuery,
      preserveOnFailure: true,
      restoreCursorOnFailure: cursorBeforeRefresh,
    );
  }

  /// Próxima página (não invalida a lista em falha).
  Future<void> loadMore() async {
    if (_disposed) return;
    final query = _activeQuery;
    final snapshot = _currentSnapshot;
    final cursor = _nextCursor;
    if (query == null || snapshot == null) return;
    if (snapshot.items.isEmpty) return;
    if (!snapshot.hasMore || cursor == null) return;
    if (snapshot.isLoadingMore || snapshot.isRefreshing) return;
    if (_state is! HealthScheduleData) return;

    final generation = _generation;
    final loading = snapshot.copyWith(
      isLoadingMore: true,
      clearLoadMoreError: true,
    );
    _currentSnapshot = loading;
    _setState(HealthScheduleData(snapshot: loading));

    final pageQuery = query.copyWith(cursor: cursor);

    try {
      final page = await _source.loadPage(pageQuery);
      if (!_isCurrent(generation, query.filterIdentity)) return;

      final incoming = _mapPage(page);
      final merged = _mergeById(existing: snapshot.items, incoming: incoming);
      final groups = groupScheduleItems(merged);
      final next = HealthScheduleSnapshot(
        items: merged,
        groups: groups,
        hasMore: page.hasMore,
        query: query.withoutCursor(),
        isRefreshing: false,
        isLoadingMore: false,
        lastRefreshError: snapshot.lastRefreshError,
        lastRefreshWasOffline: snapshot.lastRefreshWasOffline,
      );
      _nextCursor = page.nextCursor;
      _currentSnapshot = next;
      _setState(HealthScheduleData(snapshot: next));
    } catch (error) {
      if (!_isCurrent(generation, query.filterIdentity)) return;
      final message = _messageOf(error);
      final failed = snapshot.copyWith(
        isLoadingMore: false,
        loadMoreError: message,
      );
      _currentSnapshot = failed;
      _setState(HealthScheduleData(snapshot: failed));
    }
  }

  Future<void> _loadFirstPage({
    required int generation,
    required HealthScheduleQuery query,
    bool preserveOnFailure = false,
    HealthScheduleCursor? restoreCursorOnFailure,
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
    required HealthScheduleQuery query,
    required HealthSchedulePage page,
  }) {
    _nextCursor = page.nextCursor;
    final views = _mapPage(page);
    final deduped = _mergeById(existing: const [], incoming: views);
    final groups = groupScheduleItems(deduped);

    if (deduped.isEmpty) {
      _nextCursor = null;
      _currentSnapshot = HealthScheduleSnapshot(
        items: const [],
        groups: groupScheduleItems(const []),
        hasMore: false,
        query: query.withoutCursor(),
      );
      _setState(HealthScheduleEmpty(query: query.withoutCursor()));
      return;
    }

    final snapshot = HealthScheduleSnapshot(
      items: deduped,
      groups: groups,
      hasMore: page.hasMore,
      query: query.withoutCursor(),
      isRefreshing: false,
      isLoadingMore: false,
      lastRefreshError: null,
      lastRefreshWasOffline: false,
    );
    _currentSnapshot = snapshot;
    _setState(HealthScheduleData(snapshot: snapshot));
  }

  void _applyFirstPageFailure({
    required HealthScheduleQuery query,
    required Object error,
    required bool preserveOnFailure,
    HealthScheduleCursor? restoreCursorOnFailure,
  }) {
    final isOffline = error is HealthScheduleSourceException && error.isOffline;
    final message = _messageOf(error);

    HealthScheduleSnapshot? lastKnown;
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
        _nextCursor = restoreCursorOnFailure;
        _currentSnapshot = lastKnown;
        _setState(HealthScheduleData(snapshot: lastKnown));
        return;
      }
      _currentSnapshot = null;
      _setState(
        HealthScheduleOffline(query: query.withoutCursor(), lastKnown: null),
      );
      return;
    }

    if (lastKnown != null) {
      _nextCursor = restoreCursorOnFailure;
      _currentSnapshot = lastKnown;
      _setState(HealthScheduleData(snapshot: lastKnown));
      return;
    }

    _currentSnapshot = null;
    _setState(
      HealthScheduleError(
        query: query.withoutCursor(),
        message: message,
        lastKnown: null,
      ),
    );
  }

  List<HealthScheduleItemView> _mapPage(HealthSchedulePage page) {
    final now = _clock();
    return [
      for (final item in page.items)
        HealthScheduleItemView.fromDomain(
          item,
          policy: _temporalPolicy,
          now: now,
        ),
    ];
  }

  static List<HealthScheduleItemView> _mergeById({
    required List<HealthScheduleItemView> existing,
    required List<HealthScheduleItemView> incoming,
  }) {
    final byId = <String, HealthScheduleItemView>{};
    for (final item in existing) {
      byId[item.id] = item;
    }
    for (final item in incoming) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()..sort(compareScheduleItemsByDue);
    return merged;
  }

  bool _isCurrent(int generation, HealthScheduleFilterIdentity identity) {
    if (_disposed) return false;
    if (generation != _generation) return false;
    final active = _activeQuery;
    if (active == null) return false;
    return active.filterIdentity == identity;
  }

  void _setState(HealthScheduleState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  static String _messageOf(Object error) {
    if (error is HealthScheduleSourceException) return error.message;
    return error.toString();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  int get generationForTest => _generation;

  @visibleForTesting
  HealthScheduleCursor? get nextCursorForTest => _nextCursor;
}
