/// Elegibilidade temporal pura para auto-regularização.
///
/// Determina se o momento atual permite solicitar auto-regularização com
/// base exclusivamente no fim oficial do turno. Esta avaliação temporal
/// NÃO substitui validações de identidade, membership, capability, posse,
/// vistoria ou cobertura.
///
/// Não exige titularidade quando o ator for integrante confirmado e autorizado.
library;

/// Resultado da avaliação de elegibilidade temporal.
enum SelfRegularizationEligibilityResult {
  /// Ainda não atingiu o limiar temporal (antes de officialShiftEnd + 60min).
  notEligible,

  /// Atingiu o limiar temporal (officialShiftEnd + 60min ou depois).
  temporallyEligible,

  /// Fim do turno ausente ou inválido; não é possível determinar.
  indeterminate,
}

/// Duração mínima após o fim do turno para elegibilidade.
const Duration _eligibilityGracePeriod = Duration(minutes: 60);

/// Avalia a elegibilidade temporal para auto-regularização.
///
/// Regras exatas:
/// - [officialShiftEnd] null → [SelfRegularizationEligibilityResult.indeterminate]
/// - [now] < officialShiftEnd + 60min → notEligible
/// - [now] == officialShiftEnd + 60min → temporallyEligible
/// - [now] > officialShiftEnd + 60min → temporallyEligible
///
/// No instante exato do fim do turno → notEligible.
/// Fim + 59 minutos → notEligible.
/// Fim + 60 minutos → temporallyEligible.
SelfRegularizationEligibilityResult evaluateSelfRegularizationEligibility({
  required DateTime now,
  required DateTime? officialShiftEnd,
}) {
  if (officialShiftEnd == null) {
    return SelfRegularizationEligibilityResult.indeterminate;
  }

  final eligibilityThreshold = officialShiftEnd.add(_eligibilityGracePeriod);

  if (now.isBefore(eligibilityThreshold)) {
    return SelfRegularizationEligibilityResult.notEligible;
  }

  return SelfRegularizationEligibilityResult.temporallyEligible;
}