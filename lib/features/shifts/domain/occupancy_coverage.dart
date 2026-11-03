/// Avaliação pura de cobertura de ocupação.
///
/// Determina se existe cobertura autoritativa suficiente para permitir
/// sucessão de uma sessão de ocupação. PROVEN_CLEAR só resulta de evidência
/// autoritativa completa sobre sessão e geração específicas.
///
/// É PROIBIDO considerar como clearance:
/// - Guarnição completa
/// - Horário dentro da escala
/// - Consulta vazia
/// - Contador zero sem proveniência
/// - occurrences.status=finalized
/// - Lista parcial de evidências
library;

import 'occupancy_evidence_classifier.dart';

/// Veredito de cobertura de uma sessão de ocupação.
enum CoverageVerdict {
  /// Engajamento impeditivo confirmado. Sucessão bloqueada.
  blocking,

  /// Cobertura autoritativa completa e válida, sem impedimentos.
  /// Somente este veredito permite prosseguir com sucessão.
  provenClear,

  /// Cobertura incompleta, ausente, contraditória ou não comprovada.
  /// Sucessão NÃO permitida.
  indeterminate,
}

/// Representa um engajamento que pode impedir a sucessão.
class Engagement {
  /// Identificador do engajamento.
  final String engagementId;

  /// Se o engajamento é confirmadamente impeditivo.
  final bool isBlocking;

  const Engagement({
    required this.engagementId,
    required this.isBlocking,
  });

  @override
  String toString() =>
      'Engagement(engagementId: $engagementId, isBlocking: $isBlocking)';
}

/// Contexto de evidência para avaliação de cobertura.
class CoverageEvidence {
  /// Classificação da evidência avaliada.
  final EvidenceClassification classification;

  /// Se a evidência refere-se à sessão e geração específicas.
  final bool matchesSessionAndGeneration;

  /// Se a evidência é autoritativa e suficiente para clearance.
  final bool isAuthoritativeAndSufficient;

  const CoverageEvidence({
    required this.classification,
    required this.matchesSessionAndGeneration,
    required this.isAuthoritativeAndSufficient,
  });

  @override
  String toString() =>
      'CoverageEvidence(classification: $classification, '
      'matchesSessionAndGeneration: $matchesSessionAndGeneration, '
      'isAuthoritativeAndSufficient: $isAuthoritativeAndSufficient)';
}

/// Avalia a cobertura de forma pura.
///
/// Regras:
/// - Se algum engajamento é bloqueante → [CoverageVerdict.blocking]
/// - Se evidência é autoritativa, completa, específica da sessão/geração
///   e sem impedimentos → [CoverageVerdict.provenClear]
/// - Qualquer outro caso → [CoverageVerdict.indeterminate]
///
/// Consulta vazia, lista parcial ou ausência de evidência autoritativa
/// resultam em [CoverageVerdict.indeterminate], nunca em provenClear.
CoverageVerdict evaluateCoverage({
  required List<CoverageEvidence> evidence,
  required List<Engagement> engagements,
}) {
  // Engajamento bloqueante tem prioridade absoluta.
  for (final engagement in engagements) {
    if (engagement.isBlocking) {
      return CoverageVerdict.blocking;
    }
  }

  // Sem evidência → indeterminate (consulta vazia não é clearance).
  if (evidence.isEmpty) {
    return CoverageVerdict.indeterminate;
  }

  // Verifica se TODA evidência é autoritativa, específica e suficiente.
  bool hasAuthoritativeComplete = false;
  for (final ev in evidence) {
    if (ev.classification == EvidenceClassification.contradictory ||
        ev.classification == EvidenceClassification.incomplete ||
        ev.classification == EvidenceClassification.insufficientProvenance ||
        ev.classification == EvidenceClassification.legacyDocumentaryOnly) {
      // Evidência não autoritativa torna o resultado indeterminate.
      return CoverageVerdict.indeterminate;
    }

    if (ev.classification == EvidenceClassification.authoritativeCurrent &&
        ev.matchesSessionAndGeneration &&
        ev.isAuthoritativeAndSufficient) {
      hasAuthoritativeComplete = true;
    }
  }

  if (hasAuthoritativeComplete) {
    return CoverageVerdict.provenClear;
  }

  return CoverageVerdict.indeterminate;
}