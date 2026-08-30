import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Snapshot utilizável da timeline (itens + flags de paginação).
///
/// Usado em [HealthTimelineData] e como [lastKnown] em error/offline
/// quando a identidade lógica coincide.
///
/// ## Falha de refresh com dados preservados
/// Quando um refresh (ou revalidação de 1ª página) falha mas a lista
/// da mesma identidade permanece, [lastRefreshError] carrega a mensagem
/// e [lastRefreshWasOffline] distingue offline de erro genérico.
/// A UI (3B+) pode reagir sem perder os itens.
final class HealthTimelineSnapshot {
  HealthTimelineSnapshot({
    required List<HealthTimelineEntryView> items,
    required this.hasMore,
    required this.query,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.lastRefreshError,
    this.lastRefreshWasOffline = false,
  }) : items = List.unmodifiable(List<HealthTimelineEntryView>.of(items));

  final List<HealthTimelineEntryView> items;
  final bool hasMore;

  /// Query ativa (cursor de paginação não faz parte da identidade lógica).
  final HealthTimelineQuery query;
  final bool isRefreshing;
  final bool isLoadingMore;

  /// Erro local de paginação; não invalida [items].
  final String? loadMoreError;

  /// Última falha de 1ª página/refresh com dados ainda utilizáveis.
  ///
  /// `null` após 1ª página bem-sucedida da identidade atual.
  final String? lastRefreshError;

  /// `true` se [lastRefreshError] foi classificado como offline.
  final bool lastRefreshWasOffline;

  HealthTimelineFilterIdentity get filterIdentity => query.filterIdentity;

  String get dogId => query.dogId;

  bool get hasRefreshFailure => lastRefreshError != null;

  HealthTimelineSnapshot copyWith({
    List<HealthTimelineEntryView>? items,
    bool? hasMore,
    HealthTimelineQuery? query,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    String? lastRefreshError,
    bool clearLastRefreshError = false,
    bool? lastRefreshWasOffline,
  }) {
    final clearRefresh = clearLastRefreshError;
    return HealthTimelineSnapshot(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      query: query ?? this.query,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
      lastRefreshError: clearRefresh
          ? null
          : (lastRefreshError ?? this.lastRefreshError),
      lastRefreshWasOffline: clearRefresh
          ? false
          : (lastRefreshWasOffline ?? this.lastRefreshWasOffline),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! HealthTimelineSnapshot) return false;
    if (other.hasMore != hasMore) return false;
    if (other.query != query) return false;
    if (other.isRefreshing != isRefreshing) return false;
    if (other.isLoadingMore != isLoadingMore) return false;
    if (other.loadMoreError != loadMoreError) return false;
    if (other.lastRefreshError != lastRefreshError) return false;
    if (other.lastRefreshWasOffline != lastRefreshWasOffline) return false;
    if (other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    hasMore,
    query,
    isRefreshing,
    isLoadingMore,
    loadMoreError,
    lastRefreshError,
    lastRefreshWasOffline,
    Object.hashAll(items),
  );
}

/// Estados do ciclo de vida da timeline paginada.
///
/// Distinções:
/// - [HealthTimelineEmpty]: primeira página conclusivamente vazia.
/// - [HealthTimelineOffline] ≠ [HealthTimelineError].
/// - Dados anteriores só reaparecem se a identidade lógica (dog + filtros)
///   for a mesma.
sealed class HealthTimelineState {
  const HealthTimelineState();

  String? get dogId;
  HealthTimelineFilterIdentity? get filterIdentity;
}

/// Nenhuma timeline ativa ainda.
final class HealthTimelineInitial extends HealthTimelineState {
  const HealthTimelineInitial();

  @override
  String? get dogId => null;

  @override
  HealthTimelineFilterIdentity? get filterIdentity => null;

  @override
  bool operator ==(Object other) => other is HealthTimelineInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Primeira página em carregamento (sem dados utilizáveis da query atual).
final class HealthTimelineLoading extends HealthTimelineState {
  const HealthTimelineLoading({required this.query});

  final HealthTimelineQuery query;

  @override
  String get dogId => query.dogId;

  @override
  HealthTimelineFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineLoading && other.query == query;

  @override
  int get hashCode => Object.hash(runtimeType, query);
}

/// Itens utilizáveis da query ativa.
final class HealthTimelineData extends HealthTimelineState {
  const HealthTimelineData({required this.snapshot});

  final HealthTimelineSnapshot snapshot;

  List<HealthTimelineEntryView> get items => snapshot.items;
  bool get hasMore => snapshot.hasMore;
  bool get isRefreshing => snapshot.isRefreshing;
  bool get isLoadingMore => snapshot.isLoadingMore;
  String? get loadMoreError => snapshot.loadMoreError;
  String? get lastRefreshError => snapshot.lastRefreshError;
  bool get lastRefreshWasOffline => snapshot.lastRefreshWasOffline;
  bool get hasRefreshFailure => snapshot.hasRefreshFailure;
  HealthTimelineQuery get query => snapshot.query;

  @override
  String get dogId => snapshot.dogId;

  @override
  HealthTimelineFilterIdentity get filterIdentity => snapshot.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineData && other.snapshot == snapshot;

  @override
  int get hashCode => Object.hash(runtimeType, snapshot);
}

/// Primeira página conclusivamente vazia para a query.
final class HealthTimelineEmpty extends HealthTimelineState {
  const HealthTimelineEmpty({required this.query, this.isRefreshing = false});

  final HealthTimelineQuery query;
  final bool isRefreshing;

  @override
  String get dogId => query.dogId;

  @override
  HealthTimelineFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineEmpty &&
      other.query == query &&
      other.isRefreshing == isRefreshing;

  @override
  int get hashCode => Object.hash(runtimeType, query, isRefreshing);
}

/// Falha inicial/global sem dados utilizáveis da identidade atual.
///
/// [lastKnown] só é preenchido quando pertence à mesma identidade lógica.
final class HealthTimelineError extends HealthTimelineState {
  const HealthTimelineError({
    required this.query,
    required this.message,
    this.lastKnown,
  });

  final HealthTimelineQuery query;
  final String message;
  final HealthTimelineSnapshot? lastKnown;

  @override
  String get dogId => query.dogId;

  @override
  HealthTimelineFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineError &&
      other.query == query &&
      other.message == message &&
      other.lastKnown == lastKnown;

  @override
  int get hashCode => Object.hash(runtimeType, query, message, lastKnown);
}

/// Offline separado de erro genérico.
///
/// [lastKnown] só é preenchido quando pertence à mesma identidade lógica.
final class HealthTimelineOffline extends HealthTimelineState {
  const HealthTimelineOffline({required this.query, this.lastKnown});

  final HealthTimelineQuery query;
  final HealthTimelineSnapshot? lastKnown;

  @override
  String get dogId => query.dogId;

  @override
  HealthTimelineFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineOffline &&
      other.query == query &&
      other.lastKnown == lastKnown;

  @override
  int get hashCode => Object.hash(runtimeType, query, lastKnown);
}
