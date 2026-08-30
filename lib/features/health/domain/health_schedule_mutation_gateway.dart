import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_engine.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Resultado assíncrono tipado do gateway (sucesso ou falha).
sealed class HealthScheduleMutationResult {
  const HealthScheduleMutationResult();
}

/// Sucesso de mutação com receipt canônico (engine local ou callable remoto).
///
/// Callables retornam receipt enxuto (`dogId`/`scheduleId`/`revision`/
/// `lifecycleStatus`/`wasNoOp`) — [apply] fica null nesse caminho.
/// O engine puro preenche [apply] com o snapshot completo.
final class HealthScheduleMutationSuccess extends HealthScheduleMutationResult {
  const HealthScheduleMutationSuccess({
    required this.dogId,
    required this.scheduleId,
    required this.revision,
    required this.wasNoOp,
    required this.lifecycleStatus,
    required this.operationId,
    this.apply,
  });

  factory HealthScheduleMutationSuccess.fromApply(
    HealthScheduleMutationApplyResult apply,
  ) {
    return HealthScheduleMutationSuccess(
      dogId: apply.item.dogId,
      scheduleId: apply.item.id,
      revision: apply.snapshot.revision,
      wasNoOp: apply.wasNoOp,
      lifecycleStatus: apply.item.lifecycleStatus,
      operationId: apply.operationId,
      apply: apply,
    );
  }

  final String dogId;
  final String scheduleId;
  final HealthScheduleRevision revision;
  final bool wasNoOp;
  final ScheduleLifecycleStatus lifecycleStatus;
  final String operationId;

  /// Snapshot completo quando produzido pelo engine local; null no receipt remoto.
  final HealthScheduleMutationApplyResult? apply;

  HealthScheduleItem? get item => apply?.item;
}

final class HealthScheduleMutationErrorResult
    extends HealthScheduleMutationResult {
  const HealthScheduleMutationErrorResult(this.failure);

  final HealthScheduleMutationFailure failure;
}

/// Porta de mutação da Agenda Preventiva.
///
/// Produção (Gate 4): [FirebaseFunctionsHealthScheduleMutationGateway].
/// Testes/harnesses: [FailClosedHealthScheduleMutationGateway] ou fakes.
abstract interface class HealthScheduleMutationGateway {
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  );

  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  );

  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  );

  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  );
}

/// Fail-closed: nenhuma escrita real até autorização e backend/Rules aprovados.
final class FailClosedHealthScheduleMutationGateway
    implements HealthScheduleMutationGateway {
  const FailClosedHealthScheduleMutationGateway();

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) async => const HealthScheduleMutationErrorResult(
    HealthScheduleMutationWritesNotEnabled(),
  );

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) async => const HealthScheduleMutationErrorResult(
    HealthScheduleMutationWritesNotEnabled(),
  );

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) async => const HealthScheduleMutationErrorResult(
    HealthScheduleMutationWritesNotEnabled(),
  );

  @override
  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  ) async => const HealthScheduleMutationErrorResult(
    HealthScheduleMutationWritesNotEnabled(),
  );
}

/// Sessão de submissão para impedir double-submit (ações rápidas).
///
/// Não é o controller de leitura da Agenda.
final class HealthScheduleCommandSession {
  var _submitting = false;

  bool get isSubmitting => _submitting;

  /// Executa [action] se não houver submissão em voo.
  /// Retorna null se bloqueado por double-submit.
  Future<T?> runExclusive<T>(Future<T> Function() action) async {
    if (_submitting) return null;
    _submitting = true;
    try {
      return await action();
    } finally {
      _submitting = false;
    }
  }
}
