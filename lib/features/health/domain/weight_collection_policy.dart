/// Regra canônica única de seleção de peso atual a partir de uma coleção
/// completa de `weight_records` (WEIGHT-01E-C1).
///
/// Paridade semântica com a policy Web já auditada
/// (`weight-collection-policy.ts`): a coleção inteira é analisada antes de
/// qualquer seleção, e a posição física de um documento nunca decide se ele
/// participa da decisão de peso atual.
///
/// Contrato:
/// 1. `malformed`, `unsupported` e `entityId` duplicado são bloqueadores
///    GLOBAIS → [WeightCurrentKind.inconclusive];
/// 2. `invalidated` é excluído dos candidatos e NÃO bloqueia;
/// 3. sem bloqueadores e havendo candidatos → peso atual é o primeiro da
///    ordenação canônica ([compareWeightRecency]);
/// 4. sem bloqueadores e sem candidatos (vazio ou somente `invalidated`) →
///    [WeightCurrentKind.none].
///
/// Não consulta Firestore, não escreve, não classifica documentos por conta
/// própria (a autoridade permanece no parser/adapter central) e não muta a
/// lista de entrada.
library;

import 'package:canil_gcm/features/health/domain/weight_assessment.dart';

/// Bloqueador global de seleção de peso atual.
enum WeightCurrentBlocker { malformed, unsupported, duplicateEntityId }

/// Estado da seleção de peso atual.
enum WeightCurrentKind {
  /// Há peso atual factual.
  current,

  /// Não há registro algum elegível (coleção vazia ou somente `invalidated`).
  none,

  /// A coleção contém bloqueador global; o peso atual é desconhecido e NÃO
  /// pode ser substituído por um registro anterior.
  inconclusive,
}

/// Classificação de um documento já resolvida pelo adapter central.
///
/// Espelha `WeightReadKind` sem criar dependência da camada `data`, mantendo
/// esta policy no domínio e testável sem Firestore.
enum WeightCandidateKind { valid, invalidated, malformed, unsupported }

/// Entrada da policy: um documento já classificado.
///
/// [assessment] é obrigatório para `valid`/`invalidated` (o parser produziu
/// aggregate) e deve ser `null` para `malformed`/`unsupported`, que não
/// possuem aggregate factual.
final class WeightCandidate {
  const WeightCandidate({
    required this.entityId,
    required this.kind,
    this.assessment,
  });

  final String entityId;
  final WeightCandidateKind kind;
  final WeightAssessment? assessment;

  bool get isBlocking =>
      kind == WeightCandidateKind.malformed ||
      kind == WeightCandidateKind.unsupported;
}

/// Resultado da análise coletiva.
final class WeightCollectionAnalysis {
  const WeightCollectionAnalysis._({
    required this.kind,
    required this.current,
    required this.validRecords,
    required this.invalidatedRecords,
    required this.blockers,
  });

  final WeightCurrentKind kind;

  /// Peso atual factual; `null` em [WeightCurrentKind.none] e
  /// [WeightCurrentKind.inconclusive].
  final WeightAssessment? current;

  /// Candidatos válidos em ordem canônica decrescente de recência.
  ///
  /// Preenchido mesmo quando há bloqueador, para diagnóstico — mas nesse caso
  /// [current] permanece `null` e o primeiro elemento NÃO deve ser promovido.
  final List<WeightAssessment> validRecords;

  final List<WeightAssessment> invalidatedRecords;

  /// Bloqueadores globais detectados, em ordem estável.
  final List<WeightCurrentBlocker> blockers;

  bool get isCurrent => kind == WeightCurrentKind.current;
  bool get isNone => kind == WeightCurrentKind.none;
  bool get isInconclusive => kind == WeightCurrentKind.inconclusive;
}

/// Compara strings por unidade de código UTF-16, de forma determinística.
///
/// `String.compareTo` do Dart já é ordenação por code unit UTF-16, mas a
/// comparação é implementada explicitamente para que o contrato não dependa
/// de detalhe de implementação da plataforma nem de collation/locale.
int compareWeightEntityIdCodeUnits(String a, String b) {
  if (a == b) return 0;
  final minLength = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < minLength; i++) {
    final codeA = a.codeUnitAt(i);
    final codeB = b.codeUnitAt(i);
    if (codeA != codeB) return codeA - codeB;
  }
  return a.length - b.length;
}

/// Ordenação canônica de recência entre registros válidos.
///
/// 1. `measuredAt` DESC;
/// 2. `recordedAt` DESC — factual vence `null`; ambos `null` empata;
/// 3. `entityId` DESC por unidade de código UTF-16.
///
/// Negativo quando [a] é mais recente que [b]. Não usa locale, collation,
/// ordem de origem nem ordenação implícita do Firestore.
int compareWeightRecency(WeightAssessment a, WeightAssessment b) {
  final measuredComparison = b.measuredAt.compareTo(a.measuredAt);
  if (measuredComparison != 0) return measuredComparison;

  final aRecorded = a.recordedAt;
  final bRecorded = b.recordedAt;
  if (aRecorded != null && bRecorded == null) return -1;
  if (aRecorded == null && bRecorded != null) return 1;
  if (aRecorded != null && bRecorded != null) {
    final recordedComparison = bRecorded.compareTo(aRecorded);
    if (recordedComparison != 0) return recordedComparison;
  }

  final idComparison = compareWeightEntityIdCodeUnits(a.entityId, b.entityId);
  if (idComparison != 0) return idComparison > 0 ? -1 : 1;
  return 0;
}

/// Aplica a regra canônica de peso atual sobre a coleção completa.
///
/// O resultado é independente da ordem de [documents].
WeightCollectionAnalysis analyzeWeightCollection(
  List<WeightCandidate> documents,
) {
  final valid = <WeightAssessment>[];
  final invalidated = <WeightAssessment>[];
  final blockerSet = <WeightCurrentBlocker>{};
  final entityIdCounts = <String, int>{};

  for (final document in documents) {
    entityIdCounts.update(
      document.entityId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    switch (document.kind) {
      case WeightCandidateKind.malformed:
        blockerSet.add(WeightCurrentBlocker.malformed);
      case WeightCandidateKind.unsupported:
        blockerSet.add(WeightCurrentBlocker.unsupported);
      case WeightCandidateKind.invalidated:
        final assessment = document.assessment;
        if (assessment != null) invalidated.add(assessment);
      case WeightCandidateKind.valid:
        final assessment = document.assessment;
        if (assessment != null) valid.add(assessment);
    }
  }

  if (entityIdCounts.values.any((count) => count > 1)) {
    blockerSet.add(WeightCurrentBlocker.duplicateEntityId);
  }

  // Ordem estável dos bloqueadores, independente da ordem de entrada.
  final blockers = <WeightCurrentBlocker>[
    for (final blocker in WeightCurrentBlocker.values)
      if (blockerSet.contains(blocker)) blocker,
  ];

  final sortedValid = [...valid]..sort(compareWeightRecency);

  final WeightCurrentKind kind;
  final WeightAssessment? current;
  if (blockers.isNotEmpty) {
    kind = WeightCurrentKind.inconclusive;
    current = null;
  } else if (sortedValid.isNotEmpty) {
    kind = WeightCurrentKind.current;
    current = sortedValid.first;
  } else {
    kind = WeightCurrentKind.none;
    current = null;
  }

  return WeightCollectionAnalysis._(
    kind: kind,
    current: current,
    validRecords: List.unmodifiable(sortedValid),
    invalidatedRecords: List.unmodifiable(invalidated),
    blockers: List.unmodifiable(blockers),
  );
}
