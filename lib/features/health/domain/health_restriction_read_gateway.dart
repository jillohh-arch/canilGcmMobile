/// Contrato de leitura canônica de OperationalRestriction.
///
/// Uma restrição é identificada por `dogId` + `restrictionId`, nunca por
/// descrição, nível, categoria ou posição em lista. A autoridade de detalhe é
/// `dogs/{dogId}/operational_restrictions/{restrictionId}` — NÃO
/// `health_summary/current`, que é projeção resumida de restrições ativas e não
/// carrega metadata terminal, profissional nem evidência.
///
/// Este contrato é somente leitura. END/CANCEL vivem no
/// [HealthRestrictionLifecycleGateway] e continuam sendo autoridade do backend.
library;

import 'operational_restriction.dart';

/// Natureza da falha de leitura.
///
/// `notFound` é um resultado explícito, não `null`: o chamador precisa poder
/// distinguir "esta restrição não existe" de "não foi possível carregar".
enum HealthRestrictionReadErrorCode {
  /// Documento canônico ausente. Não é fabricado a partir de projeção.
  notFound,

  /// Rules negaram a leitura. Nunca é traduzido para lista vazia.
  permissionDenied,

  /// Falha transitória de transporte (offline, indisponível, deadline).
  unavailable,

  /// Documento existe mas viola o contrato persistido, ou identidade divergente.
  integrity,

  /// Entrada local inválida antes de qualquer I/O.
  validation,

  /// Falha não classificada.
  unexpected,
}

final class HealthRestrictionReadFailure {
  const HealthRestrictionReadFailure({
    required this.code,
    required this.message,
    this.field,
  });

  final HealthRestrictionReadErrorCode code;

  /// Mensagem operacional, sem vocabulário técnico de capability ou de Rules.
  final String message;

  /// Campo canônico envolvido, quando a falha é de contrato.
  final String? field;

  @override
  String toString() =>
      'HealthRestrictionReadFailure(${code.name}'
      '${field == null ? '' : ', $field'}): $message';
}

sealed class HealthRestrictionReadResult {
  const HealthRestrictionReadResult();
}

final class HealthRestrictionReadSuccess extends HealthRestrictionReadResult {
  const HealthRestrictionReadSuccess(this.restriction);

  final OperationalRestriction restriction;
}

final class HealthRestrictionReadError extends HealthRestrictionReadResult {
  const HealthRestrictionReadError(this.failure);

  final HealthRestrictionReadFailure failure;
}

/// Leitura de UMA restrição canônica por identidade.
abstract interface class HealthRestrictionReadGateway {
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  });
}
