import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';

/// Query estruturada de leitura da Agenda Preventiva.
///
/// Evolui para filtros por tipo, lifecycle, paginação e seções sem quebrar
/// a fronteira de apresentação (sem Firestore).
final class HealthScheduleQuery {
  HealthScheduleQuery({
    required String dogId,
    Set<ScheduleType> types = const {},
    Set<ScheduleLifecycleStatus> lifecycleStatuses = const {},
    this.pageSize = defaultPageSize,
    this.cursor,
  }) : dogId = _normalizeDogId(dogId),
       types = Set<ScheduleType>.unmodifiable(types),
       lifecycleStatuses = Set<ScheduleLifecycleStatus>.unmodifiable(
         lifecycleStatuses,
       ) {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'deve ser positivo');
    }
  }

  static const int defaultPageSize = 50;

  final String dogId;

  /// Vazio = todos os tipos.
  final Set<ScheduleType> types;

  /// Vazio = política operacional da source: somente `open`
  /// ([FirestoreHealthScheduleSource] força open-only).
  /// Terminais (completed/cancelled) não entram na lista padrão da Agenda.
  final Set<ScheduleLifecycleStatus> lifecycleStatuses;

  final int pageSize;
  final HealthScheduleCursor? cursor;

  /// Identidade lógica (sem cursor) para race protection e isolamento.
  HealthScheduleFilterIdentity get filterIdentity =>
      HealthScheduleFilterIdentity(
        dogId: dogId,
        types: types,
        lifecycleStatuses: lifecycleStatuses,
        pageSize: pageSize,
      );

  HealthScheduleQuery withoutCursor() => copyWith(clearCursor: true);

  HealthScheduleQuery copyWith({
    String? dogId,
    Set<ScheduleType>? types,
    Set<ScheduleLifecycleStatus>? lifecycleStatuses,
    int? pageSize,
    HealthScheduleCursor? cursor,
    bool clearCursor = false,
  }) {
    return HealthScheduleQuery(
      dogId: dogId ?? this.dogId,
      types: types ?? this.types,
      lifecycleStatuses: lifecycleStatuses ?? this.lifecycleStatuses,
      pageSize: pageSize ?? this.pageSize,
      cursor: clearCursor ? null : (cursor ?? this.cursor),
    );
  }

  static String _normalizeDogId(String dogId) {
    final normalized = dogId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio');
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) {
    if (other is! HealthScheduleQuery) return false;
    if (other.dogId != dogId) return false;
    if (other.pageSize != pageSize) return false;
    if (other.cursor != cursor) return false;
    if (!_setEq(other.types, types)) return false;
    if (!_setEq(other.lifecycleStatuses, lifecycleStatuses)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    dogId,
    pageSize,
    cursor,
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(lifecycleStatuses),
  );

  static bool _setEq<T>(Set<T> a, Set<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}

/// Identidade lógica da Agenda (dog + filtros + pageSize; sem cursor).
final class HealthScheduleFilterIdentity {
  const HealthScheduleFilterIdentity({
    required this.dogId,
    required this.types,
    required this.lifecycleStatuses,
    required this.pageSize,
  });

  final String dogId;
  final Set<ScheduleType> types;
  final Set<ScheduleLifecycleStatus> lifecycleStatuses;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    if (other is! HealthScheduleFilterIdentity) return false;
    if (other.dogId != dogId) return false;
    if (other.pageSize != pageSize) return false;
    if (!_setEq(other.types, types)) return false;
    if (!_setEq(other.lifecycleStatuses, lifecycleStatuses)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    dogId,
    pageSize,
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(lifecycleStatuses),
  );

  static bool _setEq<T>(Set<T> a, Set<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}
