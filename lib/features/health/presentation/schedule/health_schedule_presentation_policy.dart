import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

/// Política temporal de **apresentação** da Agenda (bootstrap 4B).
///
/// Valores alinhados ao default **proposto** do ADR-004 (não é default
/// universal de domínio):
/// - tolerância sem `due_until`: 24h
/// - janela upcoming: 7 dias
///
/// Injetável / substituível quando existir configuração remota por tipo.
HealthScheduleTemporalPolicy healthSchedulePresentationPolicy() {
  return HealthScheduleTemporalPolicy(
    config: MapHealthScheduleTemporalConfig.uniform(
      HealthScheduleTypeTemporalConfig(
        toleranceAfterScheduled: const Duration(hours: 24),
        upcomingWindow: const Duration(days: 7),
      ),
    ),
  );
}
