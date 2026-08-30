import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

/// Snapshot de dados da Agenda Global.
final class HealthScheduleGlobalSnapshot {
  HealthScheduleGlobalSnapshot({
    required List<HealthScheduleItemView> items,
    required this.groups,
    required this.truncated,
    required this.catalogSize,
    this.isRefreshing = false,
    this.lastRefreshError,
    this.lastRefreshWasOffline = false,
  }) : items = List.unmodifiable(List<HealthScheduleItemView>.of(items));

  final List<HealthScheduleItemView> items;

  /// Seções temporais (primeiro nível) — derivadas na leitura pela policy.
  final HealthScheduleGroups groups;

  /// `true` quando o limite explícito do reader cortou o conjunto.
  ///
  /// Nunca é ocultado: a Agenda Global do HW-4B não tem paginação
  /// multi-chunk, então lista cortada precisa ser dita como cortada.
  final bool truncated;

  /// Quantos K9s o catálogo autorizado continha nesta leitura.
  final int catalogSize;

  final bool isRefreshing;
  final String? lastRefreshError;
  final bool lastRefreshWasOffline;

  bool get hasRefreshFailure => lastRefreshError != null;

  HealthScheduleGlobalSnapshot copyWith({
    List<HealthScheduleItemView>? items,
    HealthScheduleGroups? groups,
    bool? truncated,
    int? catalogSize,
    bool? isRefreshing,
    String? lastRefreshError,
    bool clearLastRefreshError = false,
    bool? lastRefreshWasOffline,
  }) {
    return HealthScheduleGlobalSnapshot(
      items: items ?? this.items,
      groups: groups ?? this.groups,
      truncated: truncated ?? this.truncated,
      catalogSize: catalogSize ?? this.catalogSize,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRefreshError: clearLastRefreshError
          ? null
          : (lastRefreshError ?? this.lastRefreshError),
      lastRefreshWasOffline:
          lastRefreshWasOffline ?? this.lastRefreshWasOffline,
    );
  }
}

/// Estados da Agenda Global.
///
/// Estados de falha NÃO colapsam em vazio: `permission-denied` e erro técnico
/// (índice/query) são variantes distintas de [HealthScheduleGlobalEmpty], e
/// catálogo vazio é distinto de "agenda em dia".
sealed class HealthScheduleGlobalState {
  const HealthScheduleGlobalState();
}

final class HealthScheduleGlobalInitial extends HealthScheduleGlobalState {
  const HealthScheduleGlobalInitial();
}

final class HealthScheduleGlobalLoading extends HealthScheduleGlobalState {
  const HealthScheduleGlobalLoading();
}

final class HealthScheduleGlobalData extends HealthScheduleGlobalState {
  const HealthScheduleGlobalData({required this.snapshot});

  final HealthScheduleGlobalSnapshot snapshot;
}

/// Catálogo existe, porém nenhum compromisso corresponde — agenda em dia.
final class HealthScheduleGlobalEmpty extends HealthScheduleGlobalState {
  const HealthScheduleGlobalEmpty({
    this.isRefreshing = false,
    required this.catalogSize,
  });

  final bool isRefreshing;
  final int catalogSize;
}

/// Nenhum K9 acessível — semanticamente diferente de "agenda sem itens".
final class HealthScheduleGlobalNoCatalog extends HealthScheduleGlobalState {
  const HealthScheduleGlobalNoCatalog();
}

/// Falha de autorização. Nunca apresentada como agenda vazia.
final class HealthScheduleGlobalPermissionDenied
    extends HealthScheduleGlobalState {
  const HealthScheduleGlobalPermissionDenied({required this.message});

  final String message;
}

/// Falha técnica (índice ausente / query) ou genérica.
final class HealthScheduleGlobalError extends HealthScheduleGlobalState {
  const HealthScheduleGlobalError({
    required this.message,
    this.isOffline = false,
  });

  final String message;
  final bool isOffline;
}
