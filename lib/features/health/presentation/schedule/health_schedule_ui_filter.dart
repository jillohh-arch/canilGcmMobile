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

  bool matches(HealthScheduleItemView item) {
    switch (this) {
      case HealthScheduleUiFilter.all:
        return true;
      case HealthScheduleUiFilter.today:
        return item.temporalStatus == HealthScheduleTemporalStatus.today;
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

/// Aplica filtro de UI e reagrupa (derivado — não muta fonte).
List<HealthScheduleItemView> filterScheduleItems(
  Iterable<HealthScheduleItemView> items,
  HealthScheduleUiFilter filter,
) {
  if (filter == HealthScheduleUiFilter.all) {
    return List<HealthScheduleItemView>.of(items);
  }
  return [
    for (final item in items)
      if (filter.matches(item)) item,
  ];
}
