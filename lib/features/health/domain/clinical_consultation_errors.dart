/// Falhas tipadas do registro canônico de Consulta Veterinária.
///
/// Espelha os códigos estruturados que os writers clínicos emitem em
/// `HttpsError.details.code` (`clinical_case_callables.ts`). O gateway NUNCA
/// cai de volta para o `HealthLog` legado: uma falha aqui é uma falha visível.
sealed class ClinicalConsultationFailure implements Exception {
  const ClinicalConsultationFailure({this.message});

  /// Mensagem do backend quando existir. Nunca inventada no cliente.
  final String? message;
}

/// Caller autenticado sem a capability clínica exigida.
///
/// Backend: `capability-not-granted` (`health.record_clinical`).
final class ClinicalConsultationNotAuthorized
    extends ClinicalConsultationFailure {
  const ClinicalConsultationNotAuthorized({super.message, this.action});

  /// Capability exigida, quando o backend a expõe em `details.action`.
  final String? action;
}

/// Sessão ausente/expirada.
final class ClinicalConsultationUnauthenticated
    extends ClinicalConsultationFailure {
  const ClinicalConsultationUnauthenticated({super.message});
}

/// Escopo do perfil não alcança o K9 (own_records sem vínculo/turno).
final class ClinicalConsultationDogAccessDenied
    extends ClinicalConsultationFailure {
  const ClinicalConsultationDogAccessDenied({super.message});
}

/// Payload rejeitado pela validação de contrato do writer.
final class ClinicalConsultationValidationFailure
    extends ClinicalConsultationFailure {
  const ClinicalConsultationValidationFailure({super.message, this.reason});

  /// Código estruturado do backend quando disponível.
  final String? reason;
}

/// Mesmo `operationId` reenviado com intenção semântica diferente.
final class ClinicalConsultationIdempotencyConflict
    extends ClinicalConsultationFailure {
  const ClinicalConsultationIdempotencyConflict({super.message});
}

/// Caso não encontrado no path canônico.
final class ClinicalConsultationCaseNotFound
    extends ClinicalConsultationFailure {
  const ClinicalConsultationCaseNotFound({super.message});
}

/// Caso em estado que não aceita novos eventos (ex.: terminal).
final class ClinicalConsultationCaseNotWritable
    extends ClinicalConsultationFailure {
  const ClinicalConsultationCaseNotWritable({super.message, this.reason});

  final String? reason;
}

/// Callable indisponível no ambiente (não publicado / região errada).
///
/// Load-bearing: distingue "feature ainda não publicada" de "erro do usuário".
final class ClinicalConsultationUnavailable
    extends ClinicalConsultationFailure {
  const ClinicalConsultationUnavailable({super.message});
}

/// Qualquer outra falha. Nunca degradar para sucesso aparente.
final class ClinicalConsultationUnexpected
    extends ClinicalConsultationFailure {
  const ClinicalConsultationUnexpected({super.message});
}
