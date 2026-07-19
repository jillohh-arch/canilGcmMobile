// Erros tipados das mutações de Nutrição (Fase 5D Gate 3).
// Não acoplados a FirebaseException. Mapper data → estes códigos.

/// Categorias de falha de mutação canônica de Nutrição.
enum HealthNutritionMutationErrorCode {
  unauthenticated,
  permissionDenied,
  notFound,
  validation,
  failedPrecondition,
  conflict,

  /// Mesma operationId com intenção diferente.
  idempotencyConflict,

  /// Occurrence planejada com materialização divergente.
  mealOccurrenceConflict,

  /// Resposta/documento estruturalmente inconsistente.
  integrity,
  unavailable,
  network,
  unexpected,

  /// Gateway fail-closed (testes / composition incompleta).
  writesNotEnabled,
}

/// Falha tipada de mutação de Nutrição (sem I/O).
sealed class HealthNutritionMutationFailure implements Exception {
  const HealthNutritionMutationFailure({
    required this.code,
    required this.message,
    this.detailCode,
  });

  final HealthNutritionMutationErrorCode code;
  final String message;

  /// Código semântico estável do backend (`details.code`), quando presente.
  final String? detailCode;

  @override
  String toString() =>
      'HealthNutritionMutationFailure($code'
      '${detailCode != null ? ', detail=$detailCode' : ''}): $message';
}

final class HealthNutritionMutationUnauthenticated
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationUnauthenticated([
    String message = 'Usuário não autenticado.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.unauthenticated,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationPermissionDenied
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationPermissionDenied([
    String message = 'Sem permissão para registrar nutrição.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.permissionDenied,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationNotFound
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationNotFound([
    String message = 'Recurso de nutrição não encontrado.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.notFound,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationValidation
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationValidation(
    String message, {
    String? detailCode,
  }) : super(
         code: HealthNutritionMutationErrorCode.validation,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationFailedPrecondition
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationFailedPrecondition(
    String message, {
    String? detailCode,
  }) : super(
         code: HealthNutritionMutationErrorCode.failedPrecondition,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationConflict
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationConflict([
    String message = 'Conflito na mutação de nutrição.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.conflict,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationIdempotencyConflict
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationIdempotencyConflict([
    String message =
        'Mesma operação com intenção diferente da original (idempotency conflict).',
    String? detailCode = 'idempotency_conflict',
  ]) : super(
         code: HealthNutritionMutationErrorCode.idempotencyConflict,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationMealOccurrenceConflict
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationMealOccurrenceConflict([
    String message =
        'Conflito na mesma refeição planejada (materialização divergente).',
    String? detailCode = 'meal_occurrence_conflict',
  ]) : super(
         code: HealthNutritionMutationErrorCode.mealOccurrenceConflict,
         message: message,
         detailCode: detailCode,
       );
}

// Note: detailCode is positional optional (2nd), not named — call sites must
// pass positionally if overriding.

final class HealthNutritionMutationIntegrity
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationIntegrity([
    String message = 'Resposta ou estado de nutrição inconsistente.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.integrity,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationUnavailable
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationUnavailable([
    String message = 'Serviço de nutrição temporariamente indisponível.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.unavailable,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationNetwork
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationNetwork([
    String message = 'Sem conexão para mutar nutrição.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.network,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationUnexpected
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationUnexpected([
    String message = 'Falha inesperada na mutação de nutrição.',
    String? detailCode,
  ]) : super(
         code: HealthNutritionMutationErrorCode.unexpected,
         message: message,
         detailCode: detailCode,
       );
}

final class HealthNutritionMutationWritesNotEnabled
    extends HealthNutritionMutationFailure {
  const HealthNutritionMutationWritesNotEnabled([
    String message =
        'Escritas canônicas de nutrição não estão habilitadas neste contexto.',
  ]) : super(
         code: HealthNutritionMutationErrorCode.writesNotEnabled,
         message: message,
       );
}

/// Erros de transporte em que o request pode ter chegado sem resposta.
bool isUncertainNutritionTransportFailure(
  HealthNutritionMutationFailure failure,
) {
  return failure.code == HealthNutritionMutationErrorCode.unavailable ||
      failure.code == HealthNutritionMutationErrorCode.network;
}
