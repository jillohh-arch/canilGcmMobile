import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';

/// Resultado de aplicação pura de mutação (sem I/O).
final class HealthScheduleMutationApplyResult {
  const HealthScheduleMutationApplyResult({
    required this.snapshot,
    required this.wasNoOp,
    required this.operationId,
  });

  /// Estado pós-operação (item + revision + ids de op processados).
  final HealthScheduleMutationStateSnapshot snapshot;

  HealthScheduleItem get item => snapshot.item;

  /// true quando nenhuma mutação de dados ocorreu (retry/idempotente).
  final bool wasNoOp;
  final String operationId;
}

/// Engine puro de mutações da Agenda (Fase 4E Gate 1 — correção concorrência).
///
/// - Não fala com Firestore.
/// - Não confia em ator/timestamp vindos do comando do cliente.
/// - Exige [HealthScheduleTrustedExecutionContext] reconstruído pelo backend.
///
/// ### Concorrência de edição
/// `updateOpen` exige `expectedRevision` == revisão atual do snapshot.
/// Lifecycle `open` **sozinho** não autoriza update stale.
///
/// ### Idempotência
/// - **create**: `operationId` obrigatório; se já existe item com a mesma key → no-op.
/// - **complete**: semanticamente idempotente; no-op **não** altera completed_*.
/// - **cancel**: mesma `operationId` → no-op; outra op em cancelled → alreadyCancelled.
/// - **update**: mesma `operationId` já aplicada → no-op; revision stale → conflict.
abstract final class HealthScheduleMutationEngine {
  /// Cria item manual open. `source_type=manual`, `lifecycle=open`.
  ///
  /// [existingByCreateOperationId]: se o backend já materializou a mesma
  /// idempotency key, retorna no-op com o item existente (sem segundo doc).
  static HealthScheduleMutationApplyResult createManual({
    required CreateManualScheduleItemCommand command,
    required HealthScheduleTrustedExecutionContext trusted,
    required String resolvedId,
    HealthScheduleMutationStateSnapshot? existingByCreateOperationId,
  }) {
    if (existingByCreateOperationId != null) {
      final existing = existingByCreateOperationId;
      if (existing.createOperationId != command.operationId) {
        throw const HealthScheduleMutationConflict(
          'Índice de idempotência inconsistente com operationId',
        );
      }
      return HealthScheduleMutationApplyResult(
        snapshot: existing,
        wasNoOp: true,
        operationId: command.operationId,
      );
    }

    final id = resolvedId.trim();
    if (id.isEmpty) {
      throw const HealthScheduleMutationValidation(
        'id do item é obrigatório na criação',
      );
    }
    if (command.scheduledFor.isBefore(trusted.serverNow) &&
        !_isSameUtcMinute(command.scheduledFor, trusted.serverNow)) {
      throw const HealthScheduleMutationValidation(
        'scheduled_for deve ser presente ou futuro na criação',
      );
    }

    try {
      final item = HealthScheduleItem(
        id: id,
        dogId: command.dogId,
        scheduleType: command.scheduleType,
        title: command.title,
        scheduledFor: command.scheduledFor.toUtc(),
        timezone: command.timezone,
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.manual,
        createdAt: trusted.serverNow.toUtc(),
        recordedBy: trusted.actor,
        schemaVersion: 1,
        dueUntil: command.dueUntil?.toUtc(),
        caseId: command.caseId,
        notes: command.notes,
      );
      return HealthScheduleMutationApplyResult(
        snapshot: HealthScheduleMutationStateSnapshot(
          item: item,
          revision: HealthScheduleRevision.numeric(0),
          createOperationId: command.operationId,
        ),
        wasNoOp: false,
        operationId: command.operationId,
      );
    } on HealthDomainException catch (e) {
      throw HealthScheduleMutationValidation(e.message);
    }
  }

  static HealthScheduleMutationApplyResult complete({
    required HealthScheduleMutationStateSnapshot current,
    required CompleteScheduleItemCommand command,
    required HealthScheduleTrustedExecutionContext trusted,
  }) {
    _assertIdentity(current.item, command.dogId, command.scheduleId);

    if (current.item.lifecycleStatus == ScheduleLifecycleStatus.completed) {
      // Semântico: já concluído. Nunca sobrescreve completed_at / completed_by.
      return HealthScheduleMutationApplyResult(
        snapshot: current,
        wasNoOp: true,
        operationId:
            command.operationId ??
            current.lastLifecycleOperationId ??
            'complete-noop',
      );
    }
    if (current.item.lifecycleStatus == ScheduleLifecycleStatus.cancelled) {
      throw const HealthScheduleMutationInvalidTransition(
        'Não é possível concluir item cancelado',
      );
    }
    if (current.item.lifecycleStatus != command.expectedLifecycleStatus) {
      throw const HealthScheduleMutationConflict(
        'Lifecycle esperado não confere (concorrência).',
      );
    }
    if (!HealthScheduleItemTransitions.canTransition(
      current.item.lifecycleStatus,
      ScheduleLifecycleStatus.completed,
    )) {
      throw const HealthScheduleMutationInvalidTransition();
    }

    try {
      final next = HealthScheduleItemTransitions.transition(
        current.item,
        ScheduleLifecycleStatus.completed,
        completedAt: trusted.serverNow.toUtc(),
        completedBy: trusted.actor,
      );
      final lifecycleOp = command.operationId ?? 'complete:${next.id}';
      return HealthScheduleMutationApplyResult(
        snapshot: current.copyWith(
          item: next,
          revision: current.revision.nextNumeric(),
          lastLifecycleOperationId: lifecycleOp,
        ),
        wasNoOp: false,
        operationId: lifecycleOp,
      );
    } on HealthDomainException catch (e) {
      throw HealthScheduleMutationValidation(e.message);
    }
  }

  static HealthScheduleMutationApplyResult cancel({
    required HealthScheduleMutationStateSnapshot current,
    required CancelScheduleItemCommand command,
    required HealthScheduleTrustedExecutionContext trusted,
  }) {
    _assertIdentity(current.item, command.dogId, command.scheduleId);

    if (current.item.lifecycleStatus == ScheduleLifecycleStatus.cancelled) {
      // Mesma operação já processada → no-op (preserva reason/at/by).
      if (current.lastLifecycleOperationId == command.operationId) {
        return HealthScheduleMutationApplyResult(
          snapshot: current,
          wasNoOp: true,
          operationId: command.operationId,
        );
      }
      // Outra operação (ou desconhecida) → não silencia reason diferente.
      throw const HealthScheduleMutationAlreadyCancelled(
        asSuccess: false,
        message:
            'Item já cancelado por outra operação; cancel_reason não pode ser substituído.',
      );
    }
    if (current.item.lifecycleStatus == ScheduleLifecycleStatus.completed) {
      throw const HealthScheduleMutationInvalidTransition(
        'Não é possível cancelar item concluído',
      );
    }
    if (current.item.lifecycleStatus != command.expectedLifecycleStatus) {
      throw const HealthScheduleMutationConflict(
        'Lifecycle esperado não confere (concorrência).',
      );
    }
    if (!HealthScheduleItemTransitions.canTransition(
      current.item.lifecycleStatus,
      ScheduleLifecycleStatus.cancelled,
    )) {
      throw const HealthScheduleMutationInvalidTransition();
    }

    try {
      final next = HealthScheduleItemTransitions.transition(
        current.item,
        ScheduleLifecycleStatus.cancelled,
        cancelledAt: trusted.serverNow.toUtc(),
        cancelledBy: trusted.actor,
        cancelReason: command.cancelReason,
      );
      return HealthScheduleMutationApplyResult(
        snapshot: current.copyWith(
          item: next,
          revision: current.revision.nextNumeric(),
          lastLifecycleOperationId: command.operationId,
        ),
        wasNoOp: false,
        operationId: command.operationId,
      );
    } on HealthDomainException catch (e) {
      throw HealthScheduleMutationValidation(e.message);
    }
  }

  static HealthScheduleMutationApplyResult updateOpen({
    required HealthScheduleMutationStateSnapshot current,
    required UpdateOpenScheduleItemCommand command,
    required HealthScheduleTrustedExecutionContext trusted,
  }) {
    _assertIdentity(current.item, command.dogId, command.scheduleId);

    // Retry da mesma operação já aplicada: sucesso no-op (independe de revision).
    if (current.lastUpdateOperationId == command.operationId) {
      return HealthScheduleMutationApplyResult(
        snapshot: current,
        wasNoOp: true,
        operationId: command.operationId,
      );
    }

    // Optimistic concurrency: revision deve coincidir.
    // Lifecycle open sozinho NÃO basta.
    if (current.revision != command.expectedRevision) {
      throw const HealthScheduleMutationConflict(
        'Revisão stale: o item foi alterado desde a leitura.',
      );
    }

    if (current.item.lifecycleStatus != ScheduleLifecycleStatus.open) {
      if (current.item.lifecycleStatus == ScheduleLifecycleStatus.completed) {
        throw const HealthScheduleMutationAlreadyCompleted(asSuccess: false);
      }
      if (current.item.lifecycleStatus == ScheduleLifecycleStatus.cancelled) {
        throw const HealthScheduleMutationAlreadyCancelled(asSuccess: false);
      }
      throw const HealthScheduleMutationInvalidTransition(
        'Somente itens open podem ser editados',
      );
    }
    if (current.item.lifecycleStatus != command.expectedLifecycleStatus) {
      throw const HealthScheduleMutationConflict(
        'Lifecycle esperado não confere (concorrência).',
      );
    }

    if (HealthScheduleMutationPolicy.isAutomaticSource(
      current.item.sourceType,
    )) {
      throw const HealthScheduleMutationPermissionDenied(
        'Itens automáticos da agenda não podem ser editados pelo cliente; '
        'use complete/cancel ou fluxo de origem.',
      );
    }

    if (command.title != null &&
        !HealthScheduleMutationPolicy.allowsOpenFieldEdit(
          item: current.item,
          field: 'title',
        )) {
      throw const HealthScheduleMutationPermissionDenied(
        'Campo title não editável neste item',
      );
    }

    final nextScheduled =
        command.scheduledFor?.toUtc() ?? current.item.scheduledFor;
    final nextDue = command.clearDueUntil
        ? null
        : (command.dueUntil?.toUtc() ?? current.item.dueUntil);
    final nextTz = command.timezone ?? current.item.timezone;
    final nextTitle = command.title ?? current.item.title;
    final nextNotes = command.clearNotes
        ? null
        : (command.notes ?? current.item.notes);

    try {
      final next = HealthScheduleItem(
        id: current.item.id,
        dogId: current.item.dogId,
        scheduleType: current.item.scheduleType,
        title: nextTitle,
        scheduledFor: nextScheduled,
        timezone: nextTz,
        lifecycleStatus: current.item.lifecycleStatus,
        sourceType: current.item.sourceType,
        createdAt: current.item.createdAt,
        recordedBy: current.item.recordedBy,
        schemaVersion: current.item.schemaVersion,
        dueUntil: nextDue,
        completedAt: current.item.completedAt,
        completedBy: current.item.completedBy,
        cancelledAt: current.item.cancelledAt,
        cancelledBy: current.item.cancelledBy,
        cancelReason: current.item.cancelReason,
        sourceId: current.item.sourceId,
        caseId: current.item.caseId,
        notes: nextNotes,
        recurrenceRule: current.item.recurrenceRule,
        assignedToUid: current.item.assignedToUid,
        assignedToName: current.item.assignedToName,
      );
      return HealthScheduleMutationApplyResult(
        snapshot: current.copyWith(
          item: next,
          revision: current.revision.nextNumeric(),
          lastUpdateOperationId: command.operationId,
        ),
        wasNoOp: false,
        operationId: command.operationId,
      );
    } on HealthDomainException catch (e) {
      throw HealthScheduleMutationValidation(e.message);
    }
  }

  static void _assertIdentity(
    HealthScheduleItem current,
    String dogId,
    String scheduleId,
  ) {
    if (current.dogId != dogId || current.id != scheduleId) {
      throw const HealthScheduleMutationNotFound(
        'Identidade do item não confere com o comando',
      );
    }
  }

  static bool _isSameUtcMinute(DateTime a, DateTime b) {
    final au = a.toUtc();
    final bu = b.toUtc();
    return au.year == bu.year &&
        au.month == bu.month &&
        au.day == bu.day &&
        au.hour == bu.hour &&
        au.minute == bu.minute;
  }
}
