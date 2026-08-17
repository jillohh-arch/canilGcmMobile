/// Falhas do fluxo de emissão de restrição operacional (B3).
///
/// Hierarquia compartilhada pelos dois comandos do fluxo — HealthDocument (B0)
/// e ISSUE (B1) — porque ambos são callables do MESMO backend e mapeiam
/// exatamente o mesmo conjunto de códigos (`appError` → `details.code`).
/// Duplicar treze classes por etapa não acrescentaria informação; o que muda é
/// a ETAPA, e isso é modelado em [HealthRestrictionFlowStep].
library;

/// Etapa do fluxo onde a falha ocorreu.
///
/// Existe para a UI dizer "não foi possível anexar o documento" versus "não foi
/// possível registrar a restrição", sem expor detalhe técnico do protocolo.
enum HealthRestrictionFlowStep {
  /// PREPARE do HealthDocument.
  documentPrepare,

  /// Upload no staging path devolvido pelo PREPARE.
  documentUpload,

  /// FINALIZE do HealthDocument (selagem + agregado canônico).
  documentFinalize,

  /// ISSUE da OperationalRestriction.
  restrictionIssue,

  /// END da OperationalRestriction — liberação clínica documentada.
  restrictionEnd,

  /// CANCEL da OperationalRestriction — invalidação administrativa.
  restrictionCancel;

  /// Rótulo operacional da etapa, sem vocabulário técnico.
  String get label => switch (this) {
    HealthRestrictionFlowStep.documentPrepare ||
    HealthRestrictionFlowStep.documentUpload ||
    HealthRestrictionFlowStep.documentFinalize => 'anexar o documento',
    HealthRestrictionFlowStep.restrictionIssue => 'registrar a restrição',
    HealthRestrictionFlowStep.restrictionEnd => 'encerrar a restrição',
    HealthRestrictionFlowStep.restrictionCancel => 'cancelar o registro',
  };
}

enum HealthRestrictionFlowErrorCode {
  unauthenticated,
  permissionDenied,
  notFound,
  conflict,
  idempotencyConflict,
  validation,
  integrity,
  offline,
  unexpected,
}

/// Falha do fluxo, sempre com etapa e mensagem apresentável.
sealed class HealthRestrictionFlowFailure implements Exception {
  const HealthRestrictionFlowFailure({
    required this.code,
    required this.step,
    required this.message,
  });

  final HealthRestrictionFlowErrorCode code;
  final HealthRestrictionFlowStep step;
  final String message;

  /// `true` quando repetir a MESMA intenção tende a resolver.
  ///
  /// Conflito de idempotência NÃO é retryable como está: o payload divergiu da
  /// intenção original, então repetir com a mesma chave só repetiria o erro.
  bool get isRetryable =>
      code == HealthRestrictionFlowErrorCode.offline ||
      code == HealthRestrictionFlowErrorCode.unexpected;

  @override
  String toString() => 'HealthRestrictionFlowFailure($code, $step): $message';
}

final class HealthRestrictionFlowUnauthenticated
    extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowUnauthenticated(
    HealthRestrictionFlowStep step, [
    String message = 'Sessão expirada. Entre novamente para continuar.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.unauthenticated,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowPermissionDenied
    extends HealthRestrictionFlowFailure {
  /// O default é neutro quanto à etapa de propósito: o construtor é `const` e
  /// não pode derivar a mensagem de [step], então uma frase específica aqui
  /// mentiria para os outros comandos ("registrar" numa negação de
  /// encerramento). A frase por etapa é responsabilidade do error mapper, que
  /// conhece o comando que falhou.
  const HealthRestrictionFlowPermissionDenied(
    HealthRestrictionFlowStep step, [
    String message =
        'Você não possui autorização para esta ação em restrições '
            'operacionais.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.permissionDenied,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowNotFound extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowNotFound(
    HealthRestrictionFlowStep step, [
    String message = 'Registro não encontrado.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.notFound,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowConflict extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowConflict(
    HealthRestrictionFlowStep step, [
    String message = 'O registro mudou de estado. Recarregue e tente de novo.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.conflict,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowIdempotencyConflict
    extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowIdempotencyConflict(
    HealthRestrictionFlowStep step, [
    String message =
        'Os dados mudaram desde a tentativa anterior. Revise e envie novamente.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.idempotencyConflict,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowValidation
    extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowValidation(
    HealthRestrictionFlowStep step,
    String message,
  ) : super(
        code: HealthRestrictionFlowErrorCode.validation,
        step: step,
        message: message,
      );
}

final class HealthRestrictionFlowIntegrity extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowIntegrity(
    HealthRestrictionFlowStep step, [
    String message = 'Não foi possível concluir com segurança. Tente de novo.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.integrity,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowOffline extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowOffline(
    HealthRestrictionFlowStep step, [
    String message = 'Sem conexão. Verifique o sinal e tente novamente.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.offline,
         step: step,
         message: message,
       );
}

final class HealthRestrictionFlowUnexpected
    extends HealthRestrictionFlowFailure {
  const HealthRestrictionFlowUnexpected(
    HealthRestrictionFlowStep step, [
    String message = 'Falha inesperada. Tente novamente.',
  ]) : super(
         code: HealthRestrictionFlowErrorCode.unexpected,
         step: step,
         message: message,
       );
}
