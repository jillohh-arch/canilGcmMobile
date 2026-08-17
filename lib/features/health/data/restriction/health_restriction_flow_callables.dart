/// Nomes wire exatos dos callables do fluxo de restrição operacional.
///
/// Reúne as autoridades consumidas pela vertical: HealthDocument (B0), ISSUE
/// (B1) e os dois comandos terminais (B2). Cada comando é nomeado
/// explicitamente — não existe um callable genérico de mudança de status.
abstract final class HealthRestrictionFlowCallables {
  static const documentPrepareUpload = 'healthDocumentPrepareUpload';
  static const documentFinalizeUpload = 'healthDocumentFinalizeUpload';
  static const restrictionIssue = 'healthRestrictionIssue';

  /// Liberação clínica documentada (`health.release_restriction`).
  static const restrictionEnd = 'healthRestrictionEnd';

  /// Invalidação administrativa (`health.cancel_restriction`).
  static const restrictionCancel = 'healthRestrictionCancel';

  static const region = 'southamerica-east1';
}
