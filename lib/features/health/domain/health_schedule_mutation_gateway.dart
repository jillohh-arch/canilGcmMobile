import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_engine.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';

/// Resultado assíncrono tipado do gateway (sucesso ou falha).
sealed class HealthScheduleMutationResult {
  const HealthScheduleMutationResult();
}

final class HealthScheduleMutationSuccess extends HealthScheduleMutationResult {
  const HealthScheduleMutationSuccess(this.apply);

  final HealthScheduleMutationApplyResult apply;

  HealthScheduleItem get item => apply.item;
  bool get wasNoOp => apply.wasNoOp;
}

final class HealthScheduleMutationErrorResult
    extends HealthScheduleMutationResult {
  const HealthScheduleMutationErrorResult(this.failure);

  final HealthScheduleMutationFailure failure;
}

/// Porta de mutação da Agenda — sem implementação remota no Gate 1.
///
/// Estratégia planejada (ver relatório 4E):
/// - complete / cancel → callable/backend (preferencial)
/// - create manual / update open → pendente de autorização formal;
///   preferência alinhada a callable se capabilities granulares não existirem
///
/// Gate 1: [FailClosedHealthScheduleMutationGateway] recusa writes.
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
