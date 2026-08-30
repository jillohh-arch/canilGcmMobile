import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

/// Política temporal da Agenda — defaults **operacionais aprovados**
/// (HW-4A.2B, decisões humanas 1 e 2).
///
/// | schedule_type | toleranceAfterScheduled | upcomingWindow |
/// |---------------|-------------------------|----------------|
/// | dose          | AUSENTE (null)          | 7 dias         |
/// | os outros 8   | 24h                     | 7 dias         |
///
/// Estes são limiares de **agendamento/apresentação**: definem quando a Agenda
/// rotula uma ação agendada como atrasada. **Não** são limiares de validade
/// clínica — `overdue` numa vacinação significa que a ação está atrasada, nunca
/// que a imunização perdeu validade.
///
/// `dose` não possui fallback genérico por decisão humana: sem
/// `due_until` explícito no item, a derivação temporal falha fechada com
/// `incomplete_schedule_temporal_config`. Inventar 24h de tolerância
/// farmacológica seria afirmação clínica sem autoridade — `TreatmentProtocol` /
/// `ScheduleBlock.toleranceMinutes` ainda não possuem persistência nem producer
/// real. Quando existirem, o **producer** materializa `due_until` na criação do
/// item; o leitor e o avaliador permanecem puros e nunca consultam protocolo.
///
/// - Centralizado neste ponto único;
/// - não persistido;
/// - não bloqueia operação clínica.
const Duration kScheduleUpcomingWindow = Duration(days: 7);

/// Tolerância pós-vencimento aprovada para todos os tipos **exceto** `dose`.
const Duration kScheduleDefaultToleranceAfterScheduled = Duration(hours: 24);

/// Tipos sem tolerância genérica: exigem `due_until` explícito.
const Set<ScheduleType> kScheduleTypesWithoutGenericTolerance = {
  ScheduleType.dose,
};

Map<ScheduleType, HealthScheduleTypeTemporalConfig> _approvedConfig() {
  return {
    for (final type in ScheduleType.values)
      type: HealthScheduleTypeTemporalConfig(
        toleranceAfterScheduled:
            kScheduleTypesWithoutGenericTolerance.contains(type)
            ? null
            : kScheduleDefaultToleranceAfterScheduled,
        upcomingWindow: kScheduleUpcomingWindow,
      ),
  };
}

HealthScheduleTemporalPolicy healthSchedulePresentationPolicy() {
  return HealthScheduleTemporalPolicy(
    config: MapHealthScheduleTemporalConfig(_approvedConfig()),
  );
}

/// Snapshot legível dos parâmetros aprovados (relatório / testes).
///
/// Deriva da mesma fonte que [healthSchedulePresentationPolicy] — não duplica
/// literais, para que política e snapshot não possam divergir.
Map<ScheduleType, HealthScheduleTypeTemporalConfig>
healthSchedulePresentationPolicySnapshot() => _approvedConfig();
