/// Classificador puro de evidência de ocupação.
///
/// Determina a classificação de uma entrada de evidência sem depender de
/// Firestore, Firebase, UI ou efeitos colaterais. Registros legados não são
/// promovidos automaticamente a autoridade operacional; migração/cutover
/// ficam fora desta Wave 1.
library;

/// Classificação de uma evidência de ocupação.
enum EvidenceClassification {
  /// Evidência autoritativa e atual, suficiente para decisões operacionais.
  authoritativeCurrent,

  /// Registro documental legado, sem autoridade operacional corrente.
  legacyDocumentaryOnly,

  /// Evidência incompleta, faltam campos ou contexto necessários.
  incomplete,

  /// Evidências contraditórias que não podem ser reconciliadas.
  contradictory,

  /// Proveniência insuficiente para determinar autoridade.
  insufficientProvenance,
}

/// Entrada de evidência para classificação.
///
/// Imutável. Representa os metadados mínimos necessários para classificar
/// a proveniência e a atualidade de uma evidência.
class EvidenceInput {
  /// Se a evidência possui proveniência verificada e rastreável.
  final bool hasVerifiedProvenance;

  /// Se a evidência é considerada atual (dentro da janela operacional).
  final bool isCurrent;

  /// Se todos os campos obrigatórios estão presentes.
  final bool isComplete;

  /// Se existem outras evidências que contradizem esta.
  final bool hasContradictions;

  /// Se a evidência é de origem documental legada (não operacional).
  final bool isLegacyDocumentary;

  const EvidenceInput({
    required this.hasVerifiedProvenance,
    required this.isCurrent,
    required this.isComplete,
    required this.hasContradictions,
    required this.isLegacyDocumentary,
  });

  @override
  String toString() =>
      'EvidenceInput(hasVerifiedProvenance: $hasVerifiedProvenance, '
      'isCurrent: $isCurrent, isComplete: $isComplete, '
      'hasContradictions: $hasContradictions, '
      'isLegacyDocumentary: $isLegacyDocumentary)';
}

/// Classifica uma evidência de ocupação de forma pura.
///
/// Prioridade de avaliação:
/// 1. Contradições → [EvidenceClassification.contradictory]
/// 2. Incompleta → [EvidenceClassification.incomplete]
/// 3. Proveniência insuficiente → [EvidenceClassification.insufficientProvenance]
/// 4. Legada/documental → [EvidenceClassification.legacyDocumentaryOnly]
/// 5. Autoritativa e atual → [EvidenceClassification.authoritativeCurrent]
EvidenceClassification classifyEvidence(EvidenceInput input) {
  if (input.hasContradictions) {
    return EvidenceClassification.contradictory;
  }
  if (!input.isComplete) {
    return EvidenceClassification.incomplete;
  }
  if (!input.hasVerifiedProvenance) {
    return EvidenceClassification.insufficientProvenance;
  }
  if (input.isLegacyDocumentary) {
    return EvidenceClassification.legacyDocumentaryOnly;
  }
  if (!input.isCurrent) {
    return EvidenceClassification.insufficientProvenance;
  }
  return EvidenceClassification.authoritativeCurrent;
}