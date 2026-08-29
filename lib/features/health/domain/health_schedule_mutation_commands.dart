import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

export 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';

/// Comandos de intenção do **cliente** (Fase 4E Gate 1).
///
/// Contêm apenas o que o usuário/UI pode fornecer. **Não** incluem:
/// - ator final (`completed_by` / `cancelled_by` / `recorded_by`);
/// - timestamps de servidor (`completed_at` / `cancelled_at` / `created_at`);
/// - `lifecycle_status` arbitrário.
///
/// Esses campos são injetados pela camada confiável de execução
/// ([HealthScheduleTrustedExecutionContext]).
///
/// ## operationId por operação
///
/// | Operação | operationId | Estratégia |
/// |----------|-------------|------------|
/// | create manual | **obrigatório** | chave de idempotência / dedupe de criação |
/// | update open | **obrigatório** | retry da mesma op + [expectedRevision] |
/// | complete | **opcional** | terminal semanticamente idempotente |
/// | cancel | **obrigatório** | distingue retry da mesma op vs outro cancel |
///
/// ## Trusted context
///
/// [HealthScheduleTrustedExecutionContext] é contrato do **adapter backend**
/// futuro. Nunca é preenchido a partir de campos arbitrários do form.
/// Nenhum gateway remoto deve aceitar UID/nome/timestamp de auditoria
/// vindos do cliente como autoridade.

/// Snapshot de estado para o engine puro (item + metadados de concorrência).
///
/// Persistência futura: revision + last*OperationId no doc ou índice auxiliar.
final class HealthScheduleMutationStateSnapshot {
  const HealthScheduleMutationStateSnapshot({
    required this.item,
    required this.revision,
    this.lastLifecycleOperationId,
    this.lastUpdateOperationId,
    this.createOperationId,
  });

  final HealthScheduleItem item;
  final HealthScheduleRevision revision;

  /// operationId da última transição complete/cancel bem-sucedida.
  final String? lastLifecycleOperationId;

  /// operationId do último updateOpen bem-sucedido.
  final String? lastUpdateOperationId;

  /// operationId (idempotency key) usado na criação deste item.
  final String? createOperationId;

  HealthScheduleMutationStateSnapshot copyWith({
    HealthScheduleItem? item,
    HealthScheduleRevision? revision,
    String? lastLifecycleOperationId,
    String? lastUpdateOperationId,
    String? createOperationId,
  }) {
    return HealthScheduleMutationStateSnapshot(
      item: item ?? this.item,
      revision: revision ?? this.revision,
      lastLifecycleOperationId:
          lastLifecycleOperationId ?? this.lastLifecycleOperationId,
      lastUpdateOperationId:
          lastUpdateOperationId ?? this.lastUpdateOperationId,
      createOperationId: createOperationId ?? this.createOperationId,
    );
  }
}

/// Contexto confiável — produzido por Auth + backend/callable, **nunca** pelo form.
///
/// Campos proibidos de origem cliente:
/// - actor.uid / actor.name finais inventados no form;
/// - serverNow como DateTime.now() do aparelho em produção.
final class HealthScheduleTrustedExecutionContext {
  HealthScheduleTrustedExecutionContext({
    required this.actor,
    required this.serverNow,
  }) {
    if (actor.uid.trim().isEmpty) {
      throw const HealthDomainException(
        'missing_trusted_actor_uid',
        'ator confiável exige uid',
      );
    }
  }

  final RecordedBy actor;

  /// Instante de autoridade (server timestamp materializado ou relógio de teste).
  final DateTime serverNow;
}

/// Cria item manual. `source_type` e `lifecycle_status` são forçados pelo engine.
///
/// [operationId] é **obrigatório** e atua como idempotency key de criação.
final class CreateManualScheduleItemCommand {
  CreateManualScheduleItemCommand({
    required String dogId,
    required this.scheduleType,
    required String title,
    required this.scheduledFor,
    required String timezone,
    required String operationId,
    this.dueUntil,
    String? notes,
    String? caseId,

    /// ID opcional do documento; se null, a camada de persistência gera.
    String? clientGeneratedId,
  }) : dogId = dogId.trim(),
       title = title.trim(),
       timezone = timezone.trim(),
       notes = notes?.trim(),
       caseId = caseId?.trim(),
       operationId = operationId.trim(),
       clientGeneratedId = clientGeneratedId?.trim() {
    if (this.dogId.isEmpty) {
      throw const HealthDomainException(
        'missing_dog_id',
        'dogId é obrigatório',
      );
    }
    if (title.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_title',
        'title é obrigatório',
      );
    }
    if (timezone.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_timezone',
        'timezone é obrigatório',
      );
    }
    if (this.operationId.isEmpty) {
      throw const HealthDomainException(
        'missing_operation_id',
        'operationId (idempotency key) é obrigatório na criação manual',
      );
    }
  }

  final String dogId;
  final ScheduleType scheduleType;
  final String title;
  final DateTime scheduledFor;
  final String timezone;
  final DateTime? dueUntil;
  final String? notes;
  final String? caseId;

  /// Idempotency key de criação (obrigatória). Alias semântico: idempotencyKey.
  final String operationId;
  String get idempotencyKey => operationId;

  final String? clientGeneratedId;
}

/// Conclui item open → completed.
///
/// [operationId] **opcional**: terminal é semanticamente idempotente sem chave.
final class CompleteScheduleItemCommand {
  CompleteScheduleItemCommand({
    required String dogId,
    required String scheduleId,
    this.expectedLifecycleStatus = ScheduleLifecycleStatus.open,
    String? operationId,
  }) : dogId = dogId.trim(),
       scheduleId = scheduleId.trim(),
       operationId = operationId?.trim() {
    if (this.dogId.isEmpty || this.scheduleId.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_identity',
        'dogId e scheduleId são obrigatórios',
      );
    }
    if (operationId != null && this.operationId!.isEmpty) {
      throw const HealthDomainException(
        'missing_operation_id',
        'operationId, se informado, não pode ser vazio',
      );
    }
  }

  final String dogId;
  final String scheduleId;
  final ScheduleLifecycleStatus expectedLifecycleStatus;
  final String? operationId;
}

/// Cancela item open → cancelled. Motivo obrigatório.
///
/// [operationId] **obrigatório** para distinguir retry vs outro cancel.
final class CancelScheduleItemCommand {
  CancelScheduleItemCommand({
    required String dogId,
    required String scheduleId,
    required String cancelReason,
    required String operationId,
    this.expectedLifecycleStatus = ScheduleLifecycleStatus.open,
  }) : dogId = dogId.trim(),
       scheduleId = scheduleId.trim(),
       cancelReason = cancelReason.trim(),
       operationId = operationId.trim() {
    if (this.dogId.isEmpty || this.scheduleId.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_identity',
        'dogId e scheduleId são obrigatórios',
      );
    }
    if (this.cancelReason.isEmpty) {
      throw const HealthDomainException(
        'missing_cancel_reason',
        'cancel_reason é obrigatório e não pode ser vazio',
      );
    }
    if (this.operationId.isEmpty) {
      throw const HealthDomainException(
        'missing_operation_id',
        'operationId é obrigatório no cancelamento',
      );
    }
  }

  final String dogId;
  final String scheduleId;
  final String cancelReason;
  final ScheduleLifecycleStatus expectedLifecycleStatus;
  final String operationId;
}

/// Patch de campos editáveis de item **open**.
///
/// Exige [expectedRevision] (optimistic concurrency) e [operationId] (retry).
final class UpdateOpenScheduleItemCommand {
  UpdateOpenScheduleItemCommand({
    required String dogId,
    required String scheduleId,
    required this.expectedRevision,
    required String operationId,
    this.expectedLifecycleStatus = ScheduleLifecycleStatus.open,
    String? title,
    this.scheduledFor,
    this.dueUntil,
    this.clearDueUntil = false,
    String? timezone,
    String? notes,
    this.clearNotes = false,
  }) : dogId = dogId.trim(),
       scheduleId = scheduleId.trim(),
       title = title?.trim(),
       timezone = timezone?.trim(),
       notes = notes?.trim(),
       operationId = operationId.trim() {
    if (dogId.isEmpty || scheduleId.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_identity',
        'dogId e scheduleId são obrigatórios',
      );
    }
    if (expectedRevision.token.isEmpty) {
      throw const HealthDomainException(
        'missing_expected_revision',
        'expectedRevision é obrigatório no updateOpen',
      );
    }
    if (this.operationId.isEmpty) {
      throw const HealthDomainException(
        'missing_operation_id',
        'operationId é obrigatório no updateOpen',
      );
    }
    if (title != null && this.title!.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_title',
        'title não pode ser vazio',
      );
    }
    if (timezone != null && this.timezone!.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_timezone',
        'timezone não pode ser vazio',
      );
    }
    final hasAny =
        this.title != null ||
        scheduledFor != null ||
        dueUntil != null ||
        clearDueUntil ||
        this.timezone != null ||
        this.notes != null ||
        clearNotes;
    if (!hasAny) {
      throw const HealthDomainException(
        'empty_schedule_patch',
        'updateOpen exige ao menos um campo mutável',
      );
    }
  }

  final String dogId;
  final String scheduleId;

  /// Revisão lida pelo cliente — optimistic concurrency.
  final HealthScheduleRevision expectedRevision;
  final ScheduleLifecycleStatus expectedLifecycleStatus;
  final String? title;
  final DateTime? scheduledFor;
  final DateTime? dueUntil;
  final bool clearDueUntil;
  final String? timezone;
  final String? notes;
  final bool clearNotes;
  final String operationId;
}
