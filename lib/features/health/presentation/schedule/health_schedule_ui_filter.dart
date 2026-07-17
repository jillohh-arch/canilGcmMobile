import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

/// Filtros de leitura da UI da Agenda (sobre itens já carregados).
///
/// Não alteram o contrato de domínio nem disparam writes.
enum HealthScheduleUiFilter {
  all,
  today,
  vaccination,
  consultation,
  weighing,
  dose,
  exam,
  reevaluation,
  others,
}

extension HealthScheduleUiFilterX on HealthScheduleUiFilter {
  String get label => switch (this) {
    HealthScheduleUiFilter.all => 'Todos',
    HealthScheduleUiFilter.today => 'Hoje',
    HealthScheduleUiFilter.vaccination => 'Vacinas',
    HealthScheduleUiFilter.consultation => 'Consultas',
    HealthScheduleUiFilter.weighing => 'Pesagem',
    HealthScheduleUiFilter.dose => 'Medicação',
    HealthScheduleUiFilter.exam => 'Exames',
    HealthScheduleUiFilter.reevaluation => 'Reavaliações',
    HealthScheduleUiFilter.others => 'Outros',
  };

  /// [now] é o instante de referência (clock injetável).
  ///
  /// **Hoje (Fase 4C):** calendário UI — `scheduled_for` no dia civil atual
  /// no **timezone do item**, com lifecycle `open` (via item carregado).
  /// Inclui `today`, `pending` e `overdue` do mesmo dia civil.
  /// Não altera [HealthScheduleTemporalStatus].
  bool matches(HealthScheduleItemView item, {required DateTime now}) {
    switch (this) {
      case HealthScheduleUiFilter.all:
        return true;
      case HealthScheduleUiFilter.today:
        return isScheduledOnLocalCivilDay(item: item, now: now);
      case HealthScheduleUiFilter.vaccination:
        return item.scheduleType == ScheduleType.vaccination;
      case HealthScheduleUiFilter.consultation:
        return item.scheduleType == ScheduleType.consultation;
      case HealthScheduleUiFilter.weighing:
        return item.scheduleType == ScheduleType.weighing;
      case HealthScheduleUiFilter.dose:
        return item.scheduleType == ScheduleType.dose;
      case HealthScheduleUiFilter.exam:
        return item.scheduleType == ScheduleType.exam;
      case HealthScheduleUiFilter.reevaluation:
        return item.scheduleType == ScheduleType.reevaluation;
      case HealthScheduleUiFilter.others:
        return item.scheduleType == ScheduleType.deworming ||
            item.scheduleType == ScheduleType.bath ||
            item.scheduleType == ScheduleType.general;
    }
  }
}

bool _tzReady = false;

void _ensureTz() {
  if (_tzReady) return;
  tz_data.initializeTimeZones();
  _tzReady = true;
}

/// `scheduled_for` e `now` caem no mesmo dia civil no timezone do item.
bool isScheduledOnLocalCivilDay({
  required HealthScheduleItemView item,
  required DateTime now,
}) {
  _ensureTz();
  final location = tz.getLocation(item.timezone);
  final scheduledLocal = tz.TZDateTime.from(item.scheduledFor, location);
  final nowLocal = tz.TZDateTime.from(now, location);
  return scheduledLocal.year == nowLocal.year &&
      scheduledLocal.month == nowLocal.month &&
      scheduledLocal.day == nowLocal.day;
}

/// Aplica filtro de UI e reagrupa (derivado — não muta fonte).
List<HealthScheduleItemView> filterScheduleItems(
  Iterable<HealthScheduleItemView> items,
  HealthScheduleUiFilter filter, {
  required DateTime now,
}) {
  if (filter == HealthScheduleUiFilter.all) {
    return List<HealthScheduleItemView>.of(items);
  }
  return [
    for (final item in items)
      if (filter.matches(item, now: now)) item,
  ];
}
