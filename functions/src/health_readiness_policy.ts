/**
 * Readiness v1 — pure operational readiness policy.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Contract sources (in precedence order):
 *   1. READINESS-V1 ratified human decision: the four completeness gates are
 *      weight (90d), vaccination currency, consultation (180d) and an active
 *      nutrition plan. Exam is NOT a gate.
 *   2. HEALTH_V1_READINESS_POLICY.md §3/§4 — precedence matrix.
 *
 * The older ADR-005 §12 snapshot example lists `has_recent_exam` inside
 * `data_completeness`. That field is superseded here: the ratified decision
 * gates on consultation, and exam must never substitute for consultation.
 *
 * The Dart `lib/features/health/domain/readiness_policy.dart` still encodes the
 * older exam-gated shape. It has no runtime caller and is documented there as
 * non-authoritative legacy. THIS module is the only readiness authority.
 *
 * This module is PURE:
 *   - no Firestore access, no Admin SDK, no clock of its own;
 *   - `now` is supplied by the caller;
 *   - the same evidence + config + instant always yields the same decision.
 *
 * The client never evaluates readiness.
 */

/** Schema/version stamps persisted on the projection document. */
export const READINESS_SCHEMA_VERSION = 1;
export const READINESS_PROJECTION_VERSION = "readiness_v1";
export const READINESS_EVALUATED_BY = "function_v1";

/** The five official clinical states. There is no sixth. */
export type ReadinessStatus =
  | "operational"
  | "operational_attention"
  | "fit_with_restrictions"
  | "temporarily_unfit"
  | "not_evaluated";

/**
 * Human-approved operational defaults (READINESS-V1 ratified decision).
 *
 * These are DEFAULTS, not magic numbers: every threshold is read from this
 * object, never inlined at a comparison site. Changing a threshold must not
 * require touching domain logic.
 *
 * There is deliberately NO exam threshold: exam is not a readiness gate in v1.
 */
export interface ReadinessConfig {
  weightMaxAgeDays: number;
  consultationMaxAgeDays: number;
}

export const DEFAULT_READINESS_CONFIG: Readonly<ReadinessConfig> = Object.freeze({
  weightMaxAgeDays: 90,
  consultationMaxAgeDays: 180,
});

/**
 * Per-source evidence state.
 *
 * `absent` is a legitimate fact (nothing recorded). `unreliable` is a technical
 * fault (malformed/unsupported/inconclusive source) and must never be
 * collapsed into `absent`, because "no records" and "could not read records"
 * are different clinical claims.
 */
export type EvidenceState<T> =
  | {readonly kind: "present"; readonly value: T}
  | {readonly kind: "absent"}
  | {readonly kind: "unreliable"; readonly reasonCode: string};

/** Vaccination currency is a due-date comparison, not an age threshold. */
export interface VaccinationEvidenceValue {
  /** Next due instant of the governing canonical dose. */
  readonly nextDueAt: Date;
  /**
   * Factual application instant of the governing dose, when known.
   *
   * Never used to judge currency — that is `nextDueAt` alone. Supplied only so
   * the projector can derive `last_evaluated_at` from a real clinical event.
   */
  readonly appliedAt?: Date;
}

export interface NutritionEvidenceValue {
  /** Count of factual plans in `active` lifecycle. Exactly one is expected. */
  readonly activePlanCount: number;
}

/**
 * An active operational restriction, already parsed and filtered.
 *
 * Only `status == active` restrictions reach the evaluator. A restriction is a
 * deliberate professional decision — it is never inferred from a symptom,
 * medication, exam, surgery or consultation.
 */
export interface ReadinessRestriction {
  readonly id: string;
  readonly level: "absolute" | "partial" | "attention";
  readonly category: string;
  readonly description: string;
  readonly activitiesRestricted: readonly string[];
  readonly since: Date;
  readonly expectedEnd: Date | null;
}

export interface ReadinessEvidence {
  readonly now: Date;
  readonly activeRestrictions: readonly ReadinessRestriction[];
  readonly latestWeightAt: EvidenceState<Date>;
  readonly vaccination: EvidenceState<VaccinationEvidenceValue>;
  readonly latestConsultationAt: EvidenceState<Date>;
  readonly nutrition: EvidenceState<NutritionEvidenceValue>;
  /**
   * INFORMATIONAL ONLY — never gates `readinessStatus`.
   *
   * An exam proves a health evaluation happened (precedence step 4), but a
   * missing or stale exam does not demote `operational`, and a recent exam
   * cannot rescue a stale consultation.
   */
  readonly latestExamAt: EvidenceState<Date>;
  readonly config: ReadinessConfig;
}

/**
 * `data_completeness` — the four ratified readiness gates.
 *
 * Exam is deliberately absent. Missing exam is not incompleteness in v1.
 */
export interface ReadinessCompleteness {
  readonly hasRecentWeight: boolean;
  readonly hasVaccinationCurrent: boolean;
  readonly hasRecentConsultation: boolean;
  readonly hasActiveNutrition: boolean;
}

export type ReadinessAlertSeverity = "info" | "attention" | "critical";
export type ReadinessAlertSource = "data_completeness" | "operational_restriction";

export interface ReadinessAlert {
  readonly code: string;
  readonly label: string;
  readonly severity: ReadinessAlertSeverity;
  readonly source: ReadinessAlertSource;
}

export interface ReadinessRestrictionSummary {
  readonly id: string;
  readonly level: "absolute" | "partial" | "attention";
  readonly category: string;
  readonly description: string;
  readonly activitiesRestricted: readonly string[];
  readonly since: Date;
  readonly expectedEnd: Date | null;
  readonly isOverdue: boolean;
}

export interface ReadinessRestrictionCount {
  readonly absolute: number;
  readonly partial: number;
  readonly attention: number;
}

/**
 * Stable machine-readable reason, owned by the evaluator.
 *
 * The projector may format `readinessReason` for display but must never derive
 * a different state or reason: there is exactly one owner of this decision.
 */
export type ReadinessReasonCode =
  | "restriction_absolute_active"
  | "restriction_partial_active"
  | "restriction_attention_active"
  | "no_factual_health_evaluation"
  | "significant_incomplete_data"
  | "no_restrictions_evidence_complete";

export interface ReadinessDecision {
  readonly readinessStatus: ReadinessStatus;
  readonly readinessLabel: string;
  readonly readinessReason: string;
  readonly readinessReasonCode: ReadinessReasonCode;
  readonly activeRestrictions: readonly ReadinessRestrictionSummary[];
  readonly restrictionCount: ReadinessRestrictionCount;
  readonly completeness: ReadinessCompleteness;
  readonly openAlerts: readonly ReadinessAlert[];
}

/**
 * Evaluation outcome.
 *
 * `indeterminate` means a critical evidence source could not be read. The
 * projection must NOT assert a clinical state in that case — it is neither
 * `operational` nor `not_evaluated`. Callers surface it as a technical
 * unavailability, never as a clinical verdict.
 */
export type ReadinessEvaluation =
  | {readonly outcome: "decided"; readonly decision: ReadinessDecision}
  | {readonly outcome: "indeterminate"; readonly reasonCode: string};

/**
 * Deterministic PT-BR labels, frozen by READINESS-V1 Gate 3 §6.
 *
 * Title case is the persisted form. Presentation-layer casing (e.g. an
 * uppercase badge) is a UI concern and must not change what is stored, so no
 * client ever needs to invent a sixth label.
 */
const READINESS_LABELS: Readonly<Record<ReadinessStatus, string>> = Object.freeze({
  operational: "Operacional",
  operational_attention: "Operacional com Atenção",
  fit_with_restrictions: "Apto com Restrições",
  temporarily_unfit: "Temporariamente Inapto",
  not_evaluated: "Não Avaliado",
});

/**
 * Deterministic emission order for alerts, independent of discovery order.
 *
 * There is no `exam_overdue` code: exam does not produce a readiness alert.
 */
const ALERT_CODE_ORDER: readonly string[] = Object.freeze([
  "restriction_absolute",
  "restriction_partial",
  "restriction_attention",
  "restriction_overdue",
  "weight_overdue",
  "vaccination_overdue",
  "consultation_overdue",
  "nutrition_plan_missing",
]);

const MILLIS_PER_DAY = 86_400_000;

/**
 * Freezes the boundary semantics required by test matrix R4/R6.
 *
 * Age exactly equal to the threshold is still RECENT. Only a strictly greater
 * age is stale. `maxAgeDays` is inclusive.
 */
export function isWithinMaxAge(at: Date, now: Date, maxAgeDays: number): boolean {
  const ageMillis = now.getTime() - at.getTime();
  if (ageMillis < 0) return true;
  return ageMillis <= maxAgeDays * MILLIS_PER_DAY;
}

/**
 * Vaccination is current while the governing dose's `next_due` has not passed.
 * A due instant exactly equal to `now` is still current (inclusive), matching
 * the inclusive boundary chosen for age thresholds.
 */
export function isVaccinationCurrent(nextDueAt: Date, now: Date): boolean {
  return nextDueAt.getTime() >= now.getTime();
}

function label(status: ReadinessStatus): string {
  return READINESS_LABELS[status];
}

function levelRank(level: "absolute" | "partial" | "attention"): number {
  if (level === "absolute") return 0;
  if (level === "partial") return 1;
  return 2;
}

/** Stable restriction ordering: most restrictive, then most recent, then id. */
function compareRestrictions(
  a: ReadinessRestrictionSummary,
  b: ReadinessRestrictionSummary,
): number {
  const byLevel = levelRank(a.level) - levelRank(b.level);
  if (byLevel !== 0) return byLevel;
  const bySince = b.since.getTime() - a.since.getTime();
  if (bySince !== 0) return bySince;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

function summarizeRestrictions(
  restrictions: readonly ReadinessRestriction[],
  now: Date,
): readonly ReadinessRestrictionSummary[] {
  const summaries = restrictions.map((restriction): ReadinessRestrictionSummary => ({
    id: restriction.id,
    level: restriction.level,
    category: restriction.category,
    description: restriction.description,
    activitiesRestricted: [...restriction.activitiesRestricted],
    since: restriction.since,
    expectedEnd: restriction.expectedEnd,
    // expected_end in the past does NOT end a restriction; it only marks it as
    // due for professional re-evaluation. Ending is always explicit.
    isOverdue:
      restriction.expectedEnd !== null &&
      restriction.expectedEnd.getTime() < now.getTime(),
  }));
  return summaries.sort(compareRestrictions);
}

function countRestrictions(
  restrictions: readonly ReadinessRestrictionSummary[],
): ReadinessRestrictionCount {
  let absolute = 0;
  let partial = 0;
  let attention = 0;
  for (const restriction of restrictions) {
    if (restriction.level === "absolute") absolute++;
    else if (restriction.level === "partial") partial++;
    else attention++;
  }
  return {absolute, partial, attention};
}

function resolveCompleteness(evidence: ReadinessEvidence): ReadinessCompleteness {
  const {now, config} = evidence;

  const hasRecentWeight =
    evidence.latestWeightAt.kind === "present" &&
    isWithinMaxAge(evidence.latestWeightAt.value, now, config.weightMaxAgeDays);

  const hasVaccinationCurrent =
    evidence.vaccination.kind === "present" &&
    isVaccinationCurrent(evidence.vaccination.value.nextDueAt, now);

  const hasRecentConsultation =
    evidence.latestConsultationAt.kind === "present" &&
    isWithinMaxAge(
      evidence.latestConsultationAt.value,
      now,
      config.consultationMaxAgeDays,
    );

  // Exactly one active plan is expected. Zero is missing; more than one is a
  // conflict and must not be resolved by arbitrarily picking a plan.
  const hasActiveNutrition =
    evidence.nutrition.kind === "present" &&
    evidence.nutrition.value.activePlanCount === 1;

  return {
    hasRecentWeight,
    hasVaccinationCurrent,
    hasRecentConsultation,
    hasActiveNutrition,
  };
}

/**
 * Priority 4 of the precedence matrix: has this K9 ever been evaluated?
 *
 * Derived exclusively from recognized factual health evidence, conservatively:
 * only a `present` source counts. Malformed/unsupported sources do not prove an
 * evaluation happened, and a query failure never becomes `not_evaluated`.
 *
 * Exam counts here — it proves an evaluation occurred — even though it is not a
 * completeness gate.
 *
 * Deliberately does NOT consider `health_summary/current`: that document is the
 * output of this evaluation, not an input to it.
 */
export function derivesAnyHealthEvaluation(evidence: ReadinessEvidence): boolean {
  return (
    evidence.latestWeightAt.kind === "present" ||
    evidence.vaccination.kind === "present" ||
    evidence.latestConsultationAt.kind === "present" ||
    evidence.latestExamAt.kind === "present"
  );
}

/**
 * Critical sources whose technical failure blocks any clinical claim.
 *
 * Exactly the four gating sources. Exam is excluded: it is informational, so an
 * unreadable exam source cannot suppress the verdict.
 */
function firstUnreliableCriticalSource(evidence: ReadinessEvidence): string | null {
  // 1. Any source the reader marked as unreliable blocks the clinical claim.
  const critical: ReadonlyArray<readonly [string, EvidenceState<unknown>]> = [
    ["weight", evidence.latestWeightAt],
    ["vaccination", evidence.vaccination],
    ["consultation", evidence.latestConsultationAt],
    ["nutrition", evidence.nutrition],
  ];
  for (const [source, state] of critical) {
    if (state.kind === "unreliable") {
      return `${source}_source_${state.reasonCode}`;
    }
  }

  // 2. >1 active nutrition plan is a data-integrity conflict, not clinical incompleteness.
  // The reader reports it faithfully (count > 1); the evaluator must block it.
  if (
    evidence.nutrition.kind === "present" &&
    evidence.nutrition.value.activePlanCount > 1
  ) {
    return "nutrition_active_plan_conflict";
  }

  return null;
}

function buildCompletenessAlerts(
  evidence: ReadinessEvidence,
  completeness: ReadinessCompleteness,
): ReadinessAlert[] {
  const alerts: ReadinessAlert[] = [];

  if (!completeness.hasRecentWeight) {
    alerts.push({
      code: "weight_overdue",
      label: `Pesagem ausente ou com mais de ${evidence.config.weightMaxAgeDays} dias.`,
      severity: "attention",
      source: "data_completeness",
    });
  }
  if (!completeness.hasVaccinationCurrent) {
    alerts.push({
      code: "vaccination_overdue",
      label: "Vacinação ausente ou com dose vencida.",
      severity: "attention",
      source: "data_completeness",
    });
  }
  if (!completeness.hasRecentConsultation) {
    alerts.push({
      code: "consultation_overdue",
      label: `Consulta ausente ou com mais de ${evidence.config.consultationMaxAgeDays} dias.`,
      severity: "attention",
      source: "data_completeness",
    });
  }
  if (!completeness.hasActiveNutrition) {
    // >1 active plans are a technical conflict (handled in firstUnreliableCriticalSource).
    // A genuinely missing plan is a clinical completeness alert.
    alerts.push({
      code: "nutrition_plan_missing",
      label: "Nenhum plano alimentar ativo.",
      severity: "attention",
      source: "data_completeness",
    });
  }

  return alerts;
}

function buildRestrictionAlerts(
  restrictions: readonly ReadinessRestrictionSummary[],
): ReadinessAlert[] {
  const alerts: ReadinessAlert[] = [];
  const counts = countRestrictions(restrictions);

  if (counts.absolute > 0) {
    alerts.push({
      code: "restriction_absolute",
      label: "Restrição operacional absoluta ativa.",
      severity: "critical",
      source: "operational_restriction",
    });
  }
  if (counts.partial > 0) {
    alerts.push({
      code: "restriction_partial",
      label: "Restrição operacional parcial ativa.",
      severity: "attention",
      source: "operational_restriction",
    });
  }
  if (counts.attention > 0) {
    alerts.push({
      code: "restriction_attention",
      label: "Restrição operacional de atenção ativa.",
      severity: "attention",
      source: "operational_restriction",
    });
  }
  if (restrictions.some((restriction) => restriction.isOverdue)) {
    alerts.push({
      code: "restriction_overdue",
      label: "Restrição ativa com término previsto vencido. Requer reavaliação.",
      severity: "attention",
      source: "operational_restriction",
    });
  }

  return alerts;
}

function sortAlerts(alerts: readonly ReadinessAlert[]): readonly ReadinessAlert[] {
  return [...alerts].sort((a, b) => {
    const rankA = ALERT_CODE_ORDER.indexOf(a.code);
    const rankB = ALERT_CODE_ORDER.indexOf(b.code);
    if (rankA !== rankB) return rankA - rankB;
    return a.code < b.code ? -1 : a.code > b.code ? 1 : 0;
  });
}

function restrictionReason(
  level: "absolute" | "partial" | "attention",
  contributing: readonly ReadinessRestrictionSummary[],
): string {
  const prefix =
    level === "absolute"
      ? "Restrição absoluta ativa"
      : level === "partial"
        ? "Restrição parcial ativa"
        : "Restrição de atenção ativa";
  if (contributing.length === 1) {
    return `${prefix}: ${contributing[0].description}`;
  }
  return `${prefix} (${contributing.length} registros).`;
}

function incompleteReason(alerts: readonly ReadinessAlert[]): string {
  const gating = alerts.filter((alert) => alert.source === "data_completeness");
  if (gating.length === 1) return gating[0].label;
  return `Pendências de dados de saúde: ${gating.length} itens.`;
}

/**
 * Evaluates readiness against the canonical precedence matrix.
 *
 * Order (HEALTH_V1_READINESS_POLICY §3/§4):
 *   1. active absolute restriction  → temporarily_unfit
 *   2. active partial restriction    → fit_with_restrictions
 *   3. active attention restriction  → operational_attention
 *   -- technical guard: unreadable gating source → indeterminate
 *   4. no factual health evaluation  → not_evaluated
 *   5. significant incomplete data   → operational_attention
 *   6. otherwise                     → operational
 *
 * Restrictions are evaluated BEFORE the technical guard: a restriction is an
 * explicit professional decision and must never be suppressed by an unrelated
 * unreadable evidence source. Multiple restrictions: absolute > partial >
 * attention decides the state; all active restrictions stay listed.
 */
export function evaluateReadiness(evidence: ReadinessEvidence): ReadinessEvaluation {
  const allActive = summarizeRestrictions(evidence.activeRestrictions, evidence.now);
  const restrictionCount = countRestrictions(allActive);
  const completeness = resolveCompleteness(evidence);
  const restrictionAlerts = buildRestrictionAlerts(allActive);

  const decide = (
    status: ReadinessStatus,
    reason: string,
    reasonCode: ReadinessReasonCode,
    alerts: readonly ReadinessAlert[],
  ): ReadinessEvaluation => ({
    outcome: "decided",
    decision: {
      readinessStatus: status,
      readinessLabel: label(status),
      readinessReason: reason,
      readinessReasonCode: reasonCode,
      activeRestrictions: allActive,
      restrictionCount,
      completeness,
      openAlerts: sortAlerts(alerts),
    },
  });

  const completenessAlerts = buildCompletenessAlerts(evidence, completeness);
  const allAlerts = [...restrictionAlerts, ...completenessAlerts];

  // 1/2/3 — active restrictions, most restrictive first.
  for (const level of ["absolute", "partial", "attention"] as const) {
    const contributing = allActive.filter((restriction) => restriction.level === level);
    if (contributing.length === 0) continue;
    const status: ReadinessStatus =
      level === "absolute"
        ? "temporarily_unfit"
        : level === "partial"
          ? "fit_with_restrictions"
          : "operational_attention";
    const reasonCode: ReadinessReasonCode =
      level === "absolute"
        ? "restriction_absolute_active"
        : level === "partial"
          ? "restriction_partial_active"
          : "restriction_attention_active";
    return decide(
      status,
      restrictionReason(level, contributing),
      reasonCode,
      allAlerts,
    );
  }

  // Technical guard — never assert a clinical state over unreadable evidence.
  const unreliable = firstUnreliableCriticalSource(evidence);
  if (unreliable !== null) {
    return {outcome: "indeterminate", reasonCode: unreliable};
  }

  // 4 — never evaluated.
  if (!derivesAnyHealthEvaluation(evidence)) {
    return decide(
      "not_evaluated",
      "Nenhuma avaliação de saúde registrada para este K9.",
      "no_factual_health_evaluation",
      allAlerts,
    );
  }

  // 5 — significant incomplete data. Never produces unfit.
  const hasSignificantIncompleteData =
    !completeness.hasRecentWeight ||
    !completeness.hasVaccinationCurrent ||
    !completeness.hasRecentConsultation ||
    !completeness.hasActiveNutrition;
  if (hasSignificantIncompleteData) {
    return decide(
      "operational_attention",
      incompleteReason(allAlerts),
      "significant_incomplete_data",
      allAlerts,
    );
  }

  // 6 — operational.
  return decide(
    "operational",
    "Sem restrições ativas e dados de saúde em dia.",
    "no_restrictions_evidence_complete",
    allAlerts,
  );
}
