import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

/// Agrupamentos de apresentação da Agenda Preventiva.
///
/// Seções operacionais equivalentes ao mockup:
/// - [overdue] → Atrasados
/// - [pending] → No horário (ação imediata; não se confunde com overdue)
/// - [today] → Hoje
/// - [upcoming] → Próximos
/// - [scheduled] → Programados
///
/// [completed] e [cancelled] existem no contrato para histórico/filtro
/// separado; a UI futura decide se os exibe na lista principal.
final class HealthScheduleGroups {
  HealthScheduleGroups({
    required List<HealthScheduleItemView> overdue,
    required List<HealthScheduleItemView> pending,
    required List<HealthScheduleItemView> today,
    required List<HealthScheduleItemView> upcoming,
    required List<HealthScheduleItemView> scheduled,
    required List<HealthScheduleItemView> completed,
    required List<HealthScheduleItemView> cancelled,
  }) : overdue = List.unmodifiable(List<HealthScheduleItemView>.of(overdue)),
       pending = List.unmodifiable(List<HealthScheduleItemView>.of(pending)),
       today = List.unmodifiable(List<HealthScheduleItemView>.of(today)),
       upcoming = List.unmodifiable(List<HealthScheduleItemView>.of(upcoming)),
       scheduled = List.unmodifiable(
         List<HealthScheduleItemView>.of(scheduled),
       ),
       completed = List.unmodifiable(
         List<HealthScheduleItemView>.of(completed),
       ),
       cancelled = List.unmodifiable(
         List<HealthScheduleItemView>.of(cancelled),
       );

  final List<HealthScheduleItemView> overdue;
  final List<HealthScheduleItemView> pending;
  final List<HealthScheduleItemView> today;
  final List<HealthScheduleItemView> upcoming;
  final List<HealthScheduleItemView> scheduled;
  final List<HealthScheduleItemView> completed;
  final List<HealthScheduleItemView> cancelled;

  /// Itens das seções operacionais (sem completed/cancelled).
  List<HealthScheduleItemView> get operationalItems => [
    ...overdue,
    ...pending,
    ...today,
    ...upcoming,
    ...scheduled,
  ];

  bool get isOperationalEmpty => operationalItems.isEmpty;

  bool get isFullyEmpty =>
      overdue.isEmpty &&
      pending.isEmpty &&
      today.isEmpty &&
      upcoming.isEmpty &&
      scheduled.isEmpty &&
      completed.isEmpty &&
      cancelled.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! HealthScheduleGroups) return false;
    return _listEq(other.overdue, overdue) &&
        _listEq(other.pending, pending) &&
        _listEq(other.today, today) &&
        _listEq(other.upcoming, upcoming) &&
        _listEq(other.scheduled, scheduled) &&
        _listEq(other.completed, completed) &&
        _listEq(other.cancelled, cancelled);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(overdue),
    Object.hashAll(pending),
    Object.hashAll(today),
    Object.hashAll(upcoming),
    Object.hashAll(scheduled),
    Object.hashAll(completed),
    Object.hashAll(cancelled),
  );

  static bool _listEq(
    List<HealthScheduleItemView> a,
    List<HealthScheduleItemView> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Agrupa views já classificadas (não recalcula precedência temporal).
///
/// Ordenação dentro de cada grupo: `scheduledFor ASC`, empate por `id ASC`
/// (agenda operacional olha o mais próximo primeiro).
HealthScheduleGroups groupScheduleItems(
  Iterable<HealthScheduleItemView> items,
) {
  final overdue = <HealthScheduleItemView>[];
  final pending = <HealthScheduleItemView>[];
  final today = <HealthScheduleItemView>[];
  final upcoming = <HealthScheduleItemView>[];
  final scheduled = <HealthScheduleItemView>[];
  final completed = <HealthScheduleItemView>[];
  final cancelled = <HealthScheduleItemView>[];

  for (final item in items) {
    switch (item.temporalStatus) {
      case HealthScheduleTemporalStatus.overdue:
        overdue.add(item);
      case HealthScheduleTemporalStatus.pending:
        pending.add(item);
      case HealthScheduleTemporalStatus.today:
        today.add(item);
      case HealthScheduleTemporalStatus.upcoming:
        upcoming.add(item);
      case HealthScheduleTemporalStatus.scheduled:
        scheduled.add(item);
      case HealthScheduleTemporalStatus.completed:
        completed.add(item);
      case HealthScheduleTemporalStatus.cancelled:
        cancelled.add(item);
    }
  }

  overdue.sort(compareScheduleItemsByDue);
  pending.sort(compareScheduleItemsByDue);
  today.sort(compareScheduleItemsByDue);
  upcoming.sort(compareScheduleItemsByDue);
  scheduled.sort(compareScheduleItemsByDue);
  completed.sort(compareScheduleItemsByDue);
  cancelled.sort(compareScheduleItemsByDue);

  return HealthScheduleGroups(
    overdue: overdue,
    pending: pending,
    today: today,
    upcoming: upcoming,
    scheduled: scheduled,
    completed: completed,
    cancelled: cancelled,
  );
}

/// `scheduledFor ASC`, empate por `id ASC`.
int compareScheduleItemsByDue(
  HealthScheduleItemView a,
  HealthScheduleItemView b,
) {
  final byTime = a.scheduledFor.compareTo(b.scheduledFor);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}

/// Ordena lista completa de forma determinística (nova lista).
List<HealthScheduleItemView> sortScheduleItems(
  Iterable<HealthScheduleItemView> items,
) {
  final list = List<HealthScheduleItemView>.of(items);
  list.sort(compareScheduleItemsByDue);
  return list;
}
