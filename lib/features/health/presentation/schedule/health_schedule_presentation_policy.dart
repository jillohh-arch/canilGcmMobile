import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

/// Política temporal de **apresentação** da Agenda (bootstrap 4B/4C).
///
/// ## Classificação (Fase 4C)
/// Todos os valores abaixo são **PROVISÓRIO PARA APRESENTAÇÃO** — defaults
/// propostos do ADR-004, **não** regras institucionais aprovadas.
///
/// | schedule_type | toleranceAfterScheduled | upcomingWindow | status |
/// |---------------|-------------------------|----------------|--------|
/// | todos os 9    | 24h                     | 7 dias         | PROVISÓRIO |
///
/// - Centralizado neste ponto único;
/// - não persistido;
/// - não bloqueia operação clínica;
/// - UI não afirma “próximos 7 dias” como regra institucional.
///
/// Revisar com decisão humana antes de tratar como contrato operacional.
HealthScheduleTemporalPolicy healthSchedulePresentationPolicy() {
  return HealthScheduleTemporalPolicy(
    config: MapHealthScheduleTemporalConfig({
      for (final type in ScheduleType.values)
        type: HealthScheduleTypeTemporalConfig(
          toleranceAfterScheduled: const Duration(hours: 24),
          upcomingWindow: const Duration(days: 7),
        ),
    }),
  );
}

/// Snapshot legível dos parâmetros provisórios (relatório / testes).
Map<ScheduleType, HealthScheduleTypeTemporalConfig>
healthSchedulePresentationPolicySnapshot() {
  return {
    for (final type in ScheduleType.values)
      type: HealthScheduleTypeTemporalConfig(
        toleranceAfterScheduled: const Duration(hours: 24),
        upcomingWindow: const Duration(days: 7),
      ),
  };
}
