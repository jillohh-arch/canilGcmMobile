/// Nomes wire exatos dos callables do fluxo de restrição operacional.
///
/// Reúne as duas autoridades consumidas pela vertical: HealthDocument (B0) e
/// ISSUE de OperationalRestriction (B1). END/CANCEL existem no backend (B2) mas
/// não são expostos aqui — entram no B4.
abstract final class HealthRestrictionFlowCallables {
  static const documentPrepareUpload = 'healthDocumentPrepareUpload';
  static const documentFinalizeUpload = 'healthDocumentFinalizeUpload';
  static const restrictionIssue = 'healthRestrictionIssue';

  static const region = 'southamerica-east1';
}
