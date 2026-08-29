import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Política de mutabilidade de campos e origem (Fase 4E Gate 1).
///
/// Pura — sem I/O. Não autoriza quem pode executar; só o que pode mudar.
abstract final class HealthScheduleMutationPolicy {
  /// Campos controlados exclusivamente por transição de lifecycle.
  static const lifecycleControlledFields = <String>{
    'lifecycle_status',
    'completed_at',
    'completed_by',
    'cancelled_at',
    'cancelled_by',
    'cancel_reason',
  };

  /// Campos imutáveis após criação (salvo backend de migração auditado).
  static const immutableAfterCreate = <String>{
    'schedule_type',
    'source_type',
    'source_id',
    'case_id',
    'created_at',
    'recorded_by',
    'schema_version',
    'id',
    'dog_id',
  };

  /// Campos editáveis via [UpdateOpenScheduleItemCommand] em item **manual**.
  static const manualEditableWhenOpen = <String>{
    'title',
    'scheduled_for',
    'due_until',
    'timezone',
    'notes',
  };

  /// Itens automáticos: edição de agenda/vínculo proibida; lifecycle via
  /// complete/cancel; notes opcionalmente editável (política conservadora:
  /// notes **não** editável em automático no Gate 1 — só lifecycle).
  static const automaticEditableWhenOpen = <String>{};

  static bool isAutomaticSource(ScheduleSourceType sourceType) =>
      sourceType != ScheduleSourceType.manual;

  static bool allowsOpenFieldEdit({
    required HealthScheduleItem item,
    required String field,
  }) {
    if (item.lifecycleStatus != ScheduleLifecycleStatus.open) return false;
    if (immutableAfterCreate.contains(field)) return false;
    if (lifecycleControlledFields.contains(field)) return false;
    if (isAutomaticSource(item.sourceType)) {
      return automaticEditableWhenOpen.contains(field);
    }
    return manualEditableWhenOpen.contains(field);
  }

  /// Hard delete de item canônico — proibido para cliente e para esta fundação.
  static bool allowsHardDelete() => false;
}
