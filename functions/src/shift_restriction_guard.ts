/**
 * HEALTH-V1-OP-AUTH — Guard canônico de restrições operacionais.
 *
 * AUTORIDADE: `dogs/{dogId}/operational_restrictions` onde `status == "active"`.
 *
 * Este módulo NUNCA lê `health_summary/current`. O summary é projeção de display
 * e pode estar atrasado; usá-lo para autorizar uma ação crítica é exatamente a
 * inconsistência que esta vertical elimina (ADR-005 §13: "O summary sozinho NÃO
 * é barreira suficiente"). A ausência de qualquer import/menção de summary aqui
 * é load-bearing e há teste arquitetural que falha se isso mudar.
 *
 * Lógica pura: sem Admin SDK, sem HttpsError, sem I/O. O chamador busca a
 * coleção e traduz a decisão para o transporte. Isso mantém o guard exercitável
 * por teste unitário e por E2E de emulador com a MESMA implementação.
 */

import {
  RawQuery,
  resolveRestrictionsEvidence,
} from "./health_readiness_evidence_logic";
import {ReadinessRestriction} from "./health_readiness_policy";

/**
 * Decisão do guard.
 *
 * `blocked_absolute` e `unavailable` são ambos negativas, mas NUNCA são a mesma
 * coisa: a primeira é uma certeza clínica, a segunda é uma incerteza técnica.
 * Colapsá-las produziria ou um bloqueio falso ou uma liberação falsa.
 */
export type ShiftRestrictionDecision =
  | {
      readonly outcome: "allowed";
      readonly restrictions: readonly ShiftRestrictionView[];
    }
  | {
      readonly outcome: "allowed_with_restrictions";
      readonly restrictions: readonly ShiftRestrictionView[];
    }
  | {
      readonly outcome: "blocked_absolute";
      readonly restrictions: readonly ShiftRestrictionView[];
    }
  | {
      readonly outcome: "blocked_activity";
      readonly activity: string;
      readonly restrictions: readonly ShiftRestrictionView[];
    }
  | {
      readonly outcome: "unavailable";
      readonly reasonCode: string;
    };

/**
 * Projeção segura de uma restrição ativa para exibição no Mobile.
 *
 * Deliberadamente NÃO carrega `professional` nem `source_document`: são PII de
 * profissional externo (ADR-005 §13 "Dados sensíveis") e o operador só precisa
 * saber o que está restrito, não quem assinou.
 */
export interface ShiftRestrictionView {
  readonly id: string;
  readonly level: "absolute" | "partial" | "attention";
  readonly category: string;
  readonly description: string;
  readonly activitiesRestricted: readonly string[];
  readonly expectedEndIso: string | null;
  /**
   * `expected_end` no passado com `status` ainda `active`.
   *
   * Sinaliza "vencida, aguardando reavaliação" — e NÃO encerra a restrição
   * (ADR-005 §15 decisão 2). Uma restrição absoluta vencida continua bloqueando.
   */
  readonly isOverdue: boolean;
}

export interface ShiftRestrictionGuardInput {
  /** Resultado bruto da leitura de `operational_restrictions`. */
  readonly restrictions: RawQuery;
  /**
   * Atividade operacional explicitamente solicitada, quando existir contrato
   * runtime que a identifique de forma inequívoca.
   *
   * Início genérico de turno NÃO é uma atividade: passa `null` e uma restrição
   * parcial permite com alerta. Só um pedido de atividade nomeada pode casar com
   * `activities_restricted`.
   */
  readonly requestedActivity?: string | null;
  /** Referência temporal para derivar `isOverdue`. Server-side, nunca do cliente. */
  readonly now: Date;
}

function toView(
  restriction: ReadinessRestriction,
  now: Date,
): ShiftRestrictionView {
  const expectedEnd = restriction.expectedEnd;
  return {
    id: restriction.id,
    level: restriction.level,
    category: restriction.category,
    description: restriction.description,
    activitiesRestricted: restriction.activitiesRestricted,
    expectedEndIso: expectedEnd === null ? null : expectedEnd.toISOString(),
    isOverdue: expectedEnd !== null && now.getTime() > expectedEnd.getTime(),
  };
}

/** Normaliza um token de atividade para comparação tolerante a caixa/espaço. */
function normalizeActivity(value: string): string {
  return value.trim().toLowerCase();
}

/**
 * Avalia se um K9 pode ser associado a uma ação operacional crítica.
 *
 * Precedência: indisponibilidade técnica → absoluta → atividade restrita →
 * parcial → attention/limpo. Absoluta vence qualquer outra restrição presente.
 */
export function evaluateShiftRestrictionGuard(
  input: ShiftRestrictionGuardInput,
): ShiftRestrictionDecision {
  const evidence = resolveRestrictionsEvidence(input.restrictions);

  // Fail-closed: uma leitura que falhou ou um documento malformado NUNCA é
  // tratado como "sem restrições". Sem isso, negar permissão na query viraria
  // liberação silenciosa — o pior modo de falha possível nesta vertical.
  if (evidence.kind === "unreliable") {
    return {outcome: "unavailable", reasonCode: evidence.reasonCode};
  }

  const active = evidence.active;
  const views = active.map((restriction) => toView(restriction, input.now));

  // `expected_end` vencido é irrelevante aqui: o filtro é `status == active`,
  // aplicado pelo parser canônico. Vencimento sinaliza reavaliação, não fim.
  const absolute = views.filter((view) => view.level === "absolute");
  if (absolute.length > 0) {
    return {outcome: "blocked_absolute", restrictions: views};
  }

  const partial = views.filter((view) => view.level === "partial");

  const requestedActivity =
    typeof input.requestedActivity === "string" ?
      normalizeActivity(input.requestedActivity) :
      "";

  if (requestedActivity.length > 0) {
    const blocking = partial.find((view) =>
      view.activitiesRestricted.some(
        (activity) => normalizeActivity(activity) === requestedActivity,
      ),
    );
    if (blocking !== undefined) {
      return {
        outcome: "blocked_activity",
        activity: requestedActivity,
        restrictions: views,
      };
    }
  }

  // Parcial permite iniciar turno, com alerta visível e aceite auditado do
  // responsável (ADR-005 §15 decisão 1). Parcial NÃO é absoluta.
  if (partial.length > 0) {
    return {outcome: "allowed_with_restrictions", restrictions: views};
  }

  // `attention` informa, não bloqueia, e não exige override clínico.
  return {outcome: "allowed", restrictions: views};
}

/** True quando a decisão autoriza a mutação de turno prosseguir. */
export function decisionAllowsMutation(
  decision: ShiftRestrictionDecision,
): boolean {
  return (
    decision.outcome === "allowed" ||
    decision.outcome === "allowed_with_restrictions"
  );
}

/** True quando a decisão exige aceite de ciência registrado antes de operar. */
export function decisionRequiresAcknowledgement(
  decision: ShiftRestrictionDecision,
): boolean {
  return decision.outcome === "allowed_with_restrictions";
}
