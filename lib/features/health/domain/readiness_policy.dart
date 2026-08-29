import 'health_v1_enums_ext.dart';

import 'operational_restriction.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReadinessPolicy — política pura de prontidão operacional.
//
// ⚠️ LEGADO NÃO AUTORITATIVO — NÃO USAR EM RUNTIME.
//
// Esta policy NÃO possui caller de runtime e NÃO deve ganhar um. Prontidão é
// uma projeção server-side: o Mobile apenas LÊ
// `dogs/{dogId}/health_summary/current` e nunca calcula prontidão localmente.
//
// A autoridade única de avaliação é `functions/src/health_readiness_policy.ts`.
//
// Divergência conhecida e deliberada: o gating de completude aqui usa
// `hasRecentExam` (exemplo de `data_completeness` do ADR-005, contrato mais
// antigo). A decisão humana ratificada em READINESS-V1 define as quatro
// lacunas significativas como peso (90d), vacinação vigente, CONSULTA (180d) e
// plano alimentar ativo — sem threshold de exame, e sem exame substituindo
// consulta. Onde este arquivo contradizer o evaluator server-side, o
// evaluator server-side prevalece.
//
// Mantido apenas como especificação histórica da matriz de precedência
// (Readiness Policy §3/§4), que permanece correta e é espelhada no servidor.
//
// Fontes: HEALTH_V1_READINESS_POLICY.md §3 e §4; ADR-005 matriz de precedência.
// Recebe fatos booleanos/canônicos já resolvidos pelo caller.
// Sem relógio, sem acesso remoto, sem dependência de health_projections.dart,
// sem catálogo público de strings de pendência.
// ─────────────────────────────────────────────────────────────────────────────

/// Entrada da política — fatos observados do domínio.
///
/// Os quatro indicadores de completude correspondem aos booleans documentados
/// em ADR-005 §12 (`data_completeness`). Thresholds temporais são resolvidos
/// **antes** de chamar a policy (Readiness Policy §4).
final class ReadinessEvaluationInput {
  ReadinessEvaluationInput({
    required List<OperationalRestriction> activeRestrictions,
    required this.hasAnyHealthEvaluation,
    required this.hasRecentWeight,
    required this.hasVaccinationCurrent,
    required this.hasRecentExam,
    required this.hasActiveNutritionPlan,
  }) : activeRestrictions = List.unmodifiable(
         List<OperationalRestriction>.of(activeRestrictions),
       );

  /// Cópia imutável — alteração da lista original do caller não afeta a input.
  final List<OperationalRestriction> activeRestrictions;

  /// Prioridade 4: houve ao menos uma avaliação de saúde registrada.
  final bool hasAnyHealthEvaluation;

  /// Fato de `data_completeness.has_recent_weight` (ADR-005 §12).
  final bool hasRecentWeight;

  /// Fato de `data_completeness.has_vaccination_current` (ADR-005 §12).
  final bool hasVaccinationCurrent;

  /// Fato de `data_completeness.has_recent_exam` (ADR-005 §12).
  final bool hasRecentExam;

  /// Fato de `data_completeness.has_active_nutrition` (ADR-005 §12).
  final bool hasActiveNutritionPlan;

  /// Dados incompletos significativos (prioridade 5 da matriz).
  bool get hasSignificantIncompleteData =>
      !hasRecentWeight ||
      !hasVaccinationCurrent ||
      !hasRecentExam ||
      !hasActiveNutritionPlan;
}

/// Resultado determinístico da avaliação de prontidão.
///
/// Contrato mínimo: status + restrições contribuidores.
/// Os fatos de completude permanecem na [ReadinessEvaluationInput]; a
/// documentação não exige reexportá-los no decision.
final class ReadinessDecision {
  ReadinessDecision({
    required this.status,
    required List<OperationalRestriction> contributingRestrictions,
  }) : contributingRestrictions = List.unmodifiable(
         List<OperationalRestriction>.of(contributingRestrictions),
       );

  final ReadinessStatus status;

  /// Restrições ativas que determinaram o estado (lista imutável, cópia própria).
  final List<OperationalRestriction> contributingRestrictions;
}

/// Política determinística de prontidão (Readiness Policy §3 e §4).
///
/// ⚠️ Não autoritativa. Ver nota no topo do arquivo.
@Deprecated(
  'Prontidão é projeção server-side. O Mobile deve LER '
  'dogs/{dogId}/health_summary/current, nunca calcular localmente. '
  'Autoridade: functions/src/health_readiness_policy.ts. '
  'Além disso, o gating de completude aqui (hasRecentExam) contraria a '
  'decisão ratificada em READINESS-V1 (peso/vacinação/consulta/plano).',
)
final class ReadinessPolicy {
  const ReadinessPolicy();

  ReadinessDecision evaluate(ReadinessEvaluationInput input) {
    // 1. Restrição absoluta ativa → temporarily_unfit.
    final absoluteActive = input.activeRestrictions
        .where((r) => r.level == RestrictionLevel.absolute)
        .toList(growable: false);
    if (absoluteActive.isNotEmpty) {
      return ReadinessDecision(
        status: ReadinessStatus.temporarilyUnfit,
        contributingRestrictions: absoluteActive,
      );
    }

    // 2. Restrição parcial ativa → fit_with_restrictions.
    final partialActive = input.activeRestrictions
        .where((r) => r.level == RestrictionLevel.partial)
        .toList(growable: false);
    if (partialActive.isNotEmpty) {
      return ReadinessDecision(
        status: ReadinessStatus.fitWithRestrictions,
        contributingRestrictions: partialActive,
      );
    }

    // 3. Restrição de atenção ativa → operational_attention.
    final attentionActive = input.activeRestrictions
        .where((r) => r.level == RestrictionLevel.attention)
        .toList(growable: false);
    if (attentionActive.isNotEmpty) {
      return ReadinessDecision(
        status: ReadinessStatus.operationalAttention,
        contributingRestrictions: attentionActive,
      );
    }

    // 4. Sem nenhuma avaliação registrada → not_evaluated.
    if (!input.hasAnyHealthEvaluation) {
      return ReadinessDecision(
        status: ReadinessStatus.notEvaluated,
        contributingRestrictions: const [],
      );
    }

    // 5. Dados incompletos significativos → operational_attention.
    if (input.hasSignificantIncompleteData) {
      return ReadinessDecision(
        status: ReadinessStatus.operationalAttention,
        contributingRestrictions: const [],
      );
    }

    // 6. Nenhuma das anteriores → operational.
    return ReadinessDecision(
      status: ReadinessStatus.operational,
      contributingRestrictions: const [],
    );
  }
}
