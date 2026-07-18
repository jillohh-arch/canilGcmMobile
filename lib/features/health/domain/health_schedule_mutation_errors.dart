// Erros tipados das mutações da Agenda Preventiva (Fase 4E Gate 1).
// Não acoplados a FirebaseException. A camada de execução futura mapeia
// falhas remotas para estes códigos.

enum HealthScheduleMutationErrorCode {
  unauthenticated,
  permissionDenied,
  notFound,
  conflict,

  /// Mesma operationId/idempotencyKey com intenção diferente.
  idempotencyConflict,
  alreadyCompleted,
  alreadyCancelled,
  invalidTransition,
  validation,

  /// Documento/payload estruturalmente inconsistente (backend ou wire).
  integrity,
  offline,
  unexpected,

  /// Escritas ainda não autorizadas/implantadas (fail-closed do Gate 1).
  writesNotEnabled,
}

/// Falha tipada de uma mutação de domínio (sem I/O).
///
/// Implementa [Exception] para uso com throw/catch no engine puro.
sealed class HealthScheduleMutationFailure implements Exception {
  const HealthScheduleMutationFailure({
    required this.code,
    required this.message,
  });

  final HealthScheduleMutationErrorCode code;
  final String message;

  @override
  String toString() => 'HealthScheduleMutationFailure($code): $message';
}

final class HealthScheduleMutationUnauthenticated
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationUnauthenticated([
    String message = 'Usuário não autenticado.',
  ]) : super(
         code: HealthScheduleMutationErrorCode.unauthenticated,
         message: message,
       );
}

final class HealthScheduleMutationPermissionDenied
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationPermissionDenied([
    String message = 'Sem permissão para esta operação da agenda.',
  ]) : super(
         code: HealthScheduleMutationErrorCode.permissionDenied,
         message: message,
       );
}

final class HealthScheduleMutationNotFound
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationNotFound([
    String message = 'Item de agenda não encontrado.',
  ]) : super(code: HealthScheduleMutationErrorCode.notFound, message: message);
}

final class HealthScheduleMutationConflict
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationConflict([
    String message =
        'O item mudou desde a última leitura (conflito de concorrência).',
  ]) : super(code: HealthScheduleMutationErrorCode.conflict, message: message);
}

final class HealthScheduleMutationIdempotencyConflict
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationIdempotencyConflict([
    String message =
        'Mesma operação com intenção diferente da original (idempotency conflict).',
  ]) : super(
         code: HealthScheduleMutationErrorCode.idempotencyConflict,
         message: message,
       );
}

final class HealthScheduleMutationAlreadyCompleted
    extends HealthScheduleMutationFailure {
  /// [asSuccess] true = tratado como no-op idempotente no engine.
  const HealthScheduleMutationAlreadyCompleted({
    this.asSuccess = true,
    String message = 'Item já está concluído.',
  }) : super(
         code: HealthScheduleMutationErrorCode.alreadyCompleted,
         message: message,
       );

  final bool asSuccess;
}

final class HealthScheduleMutationAlreadyCancelled
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationAlreadyCancelled({
    this.asSuccess = true,
    String message = 'Item já está cancelado.',
  }) : super(
         code: HealthScheduleMutationErrorCode.alreadyCancelled,
         message: message,
       );

  final bool asSuccess;
}

final class HealthScheduleMutationInvalidTransition
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationInvalidTransition([
    String message = 'Transição de lifecycle inválida.',
  ]) : super(
         code: HealthScheduleMutationErrorCode.invalidTransition,
         message: message,
       );
}

final class HealthScheduleMutationValidation
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationValidation(String message)
    : super(code: HealthScheduleMutationErrorCode.validation, message: message);
}

final class HealthScheduleMutationIntegrity
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationIntegrity([
    String message = 'Resposta ou estado da agenda inconsistente.',
  ]) : super(code: HealthScheduleMutationErrorCode.integrity, message: message);
}

final class HealthScheduleMutationOffline
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationOffline([
    String message = 'Sem conexão para mutar a agenda.',
  ]) : super(code: HealthScheduleMutationErrorCode.offline, message: message);
}

final class HealthScheduleMutationUnexpected
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationUnexpected([
    String message = 'Falha inesperada na mutação da agenda.',
  ]) : super(
         code: HealthScheduleMutationErrorCode.unexpected,
         message: message,
       );
}

final class HealthScheduleMutationWritesNotEnabled
    extends HealthScheduleMutationFailure {
  const HealthScheduleMutationWritesNotEnabled([
    String message =
        'Escritas da agenda ainda não estão autorizadas (fail-closed).',
  ]) : super(
         code: HealthScheduleMutationErrorCode.writesNotEnabled,
         message: message,
       );
}
