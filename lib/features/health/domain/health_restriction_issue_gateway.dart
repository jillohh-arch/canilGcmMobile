/// Contrato do gateway de emissão de OperationalRestriction (consumidor do B1).
///
/// Só ISSUE. END/CANCEL existem no backend (B2) mas ficam fora desta vertical:
/// entram no B4, junto da correção do lifecycle Dart.
library;

import 'health_restriction_flow_errors.dart';
import 'health_v1_enums_ext.dart';
import 'health_v1_value_objects.dart';

/// Comando de emissão.
///
/// Campos server-owned (`status`, `issued_at`, `recorded_by`, `schema_version`,
/// `revision`, metadata de end/cancel) NÃO existem aqui por construção — o
/// codec nunca tem como enviá-los.
final class IssueOperationalRestrictionCommand {
  const IssueOperationalRestrictionCommand({
    required this.dogId,
    required this.operationId,
    required this.level,
    required this.category,
    required this.description,
    required this.professional,
    required this.sourceDocument,
    this.activitiesRestricted = const <String>[],
    this.expectedEnd,
  });

  final String dogId;
  final String operationId;
  final RestrictionLevel level;
  final RestrictionCategory category;
  final String description;

  /// Obrigatório e não vazio quando [level] é `partial`; ignorado nos demais.
  final List<String> activitiesRestricted;

  /// Previsão de reavaliação. Não encerra a restrição.
  final DateTime? expectedEnd;

  /// Profissional EXTERNO que decidiu — distinto do operador que registra.
  final ProfessionalIdentity professional;

  /// Evidência canônica, citada por identidade.
  final HealthDocumentRef sourceDocument;
}

/// Restrição emitida.
final class IssuedOperationalRestriction {
  const IssuedOperationalRestriction({
    required this.dogId,
    required this.restrictionId,
    required this.wasNoOp,
  });

  final String dogId;
  final String restrictionId;

  /// `true` em replay idempotente — mesma restrição, nenhuma escrita nova.
  final bool wasNoOp;
}

sealed class IssueOperationalRestrictionResult {
  const IssueOperationalRestrictionResult();
}

final class IssueOperationalRestrictionSuccess
    extends IssueOperationalRestrictionResult {
  const IssueOperationalRestrictionSuccess(this.restriction);

  final IssuedOperationalRestriction restriction;
}

final class IssueOperationalRestrictionError
    extends IssueOperationalRestrictionResult {
  const IssueOperationalRestrictionError(this.failure);

  final HealthRestrictionFlowFailure failure;
}

abstract interface class HealthRestrictionIssueGateway {
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  );
}
