import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';

/// Snapshot utilizável da Agenda (itens + agrupamentos + flags).
final class HealthScheduleSnapshot {
  HealthScheduleSnapshot({
    required List<HealthScheduleItemView> items,
    required this.groups,
    required this.hasMore,
    required this.query,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.lastRefreshError,
    this.lastRefreshWasOffline = false,
  }) : items = List.unmodifiable(List<HealthScheduleItemView>.of(items));

  final List<HealthScheduleItemView> items;
  final HealthScheduleGroups groups;
  final bool hasMore;
  final HealthScheduleQuery query;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? loadMoreError;
  final String? lastRefreshError;
  final bool lastRefreshWasOffline;

  HealthScheduleFilterIdentity get filterIdentity => query.filterIdentity;
  String get dogId => query.dogId;
  bool get hasRefreshFailure => lastRefreshError != null;

  HealthScheduleSnapshot copyWith({
    List<HealthScheduleItemView>? items,
    HealthScheduleGroups? groups,
    bool? hasMore,
    HealthScheduleQuery? query,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    String? lastRefreshError,
    bool clearLastRefreshError = false,
    bool? lastRefreshWasOffline,
  }) {
    final clearRefresh = clearLastRefreshError;
    return HealthScheduleSnapshot(
      items: items ?? this.items,
      groups: groups ?? this.groups,
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
    if (other is! HealthScheduleSnapshot) return false;
    if (other.hasMore != hasMore) return false;
    if (other.query != query) return false;
    if (other.groups != groups) return false;
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
    groups,
    isRefreshing,
    isLoadingMore,
    loadMoreError,
    lastRefreshError,
    lastRefreshWasOffline,
    Object.hashAll(items),
  );
}

/// Estados do ciclo de vida da Agenda (padrão Health v1).
///
/// Mínimos: initial / loading / data / empty / error.
/// Offline é distinguido de erro genérico (como Resumo e Timeline).
sealed class HealthScheduleState {
  const HealthScheduleState();

  String? get dogId;
  HealthScheduleFilterIdentity? get filterIdentity;
}

final class HealthScheduleInitial extends HealthScheduleState {
  const HealthScheduleInitial();

  @override
  String? get dogId => null;

  @override
  HealthScheduleFilterIdentity? get filterIdentity => null;

  @override
  bool operator ==(Object other) => other is HealthScheduleInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class HealthScheduleLoading extends HealthScheduleState {
  const HealthScheduleLoading({required this.query});

  final HealthScheduleQuery query;

  @override
  String get dogId => query.dogId;

  @override
  HealthScheduleFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleLoading && other.query == query;

  @override
  int get hashCode => Object.hash(runtimeType, query);
}

final class HealthScheduleData extends HealthScheduleState {
  const HealthScheduleData({required this.snapshot});

  final HealthScheduleSnapshot snapshot;

  List<HealthScheduleItemView> get items => snapshot.items;
  HealthScheduleGroups get groups => snapshot.groups;
  bool get hasMore => snapshot.hasMore;
  bool get isRefreshing => snapshot.isRefreshing;
  bool get isLoadingMore => snapshot.isLoadingMore;
  String? get loadMoreError => snapshot.loadMoreError;
  String? get lastRefreshError => snapshot.lastRefreshError;
  bool get lastRefreshWasOffline => snapshot.lastRefreshWasOffline;
  bool get hasRefreshFailure => snapshot.hasRefreshFailure;
  HealthScheduleQuery get query => snapshot.query;

  @override
  String get dogId => snapshot.dogId;

  @override
  HealthScheduleFilterIdentity get filterIdentity => snapshot.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleData && other.snapshot == snapshot;

  @override
  int get hashCode => Object.hash(runtimeType, snapshot);
}

final class HealthScheduleEmpty extends HealthScheduleState {
  const HealthScheduleEmpty({required this.query, this.isRefreshing = false});

  final HealthScheduleQuery query;
  final bool isRefreshing;

  @override
  String get dogId => query.dogId;

  @override
  HealthScheduleFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleEmpty &&
      other.query == query &&
      other.isRefreshing == isRefreshing;

  @override
  int get hashCode => Object.hash(runtimeType, query, isRefreshing);
}

final class HealthScheduleError extends HealthScheduleState {
  const HealthScheduleError({
    required this.query,
    required this.message,
    this.lastKnown,
  });

  final HealthScheduleQuery query;
  final String message;
  final HealthScheduleSnapshot? lastKnown;

  @override
  String get dogId => query.dogId;

  @override
  HealthScheduleFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleError &&
      other.query == query &&
      other.message == message &&
      other.lastKnown == lastKnown;

  @override
  int get hashCode => Object.hash(runtimeType, query, message, lastKnown);
}

final class HealthScheduleOffline extends HealthScheduleState {
  const HealthScheduleOffline({required this.query, this.lastKnown});

  final HealthScheduleQuery query;
  final HealthScheduleSnapshot? lastKnown;

  @override
  String get dogId => query.dogId;

  @override
  HealthScheduleFilterIdentity get filterIdentity => query.filterIdentity;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleOffline &&
      other.query == query &&
      other.lastKnown == lastKnown;

  @override
  int get hashCode => Object.hash(runtimeType, query, lastKnown);
}
