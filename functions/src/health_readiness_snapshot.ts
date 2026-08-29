/**
 * Readiness v1 — pure snapshot builder.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Converts an evaluator outcome into the exact payload persisted at
 * `dogs/{dogId}/health_summary/current`. PURE: no Firestore, no Admin SDK, no
 * clock — `now` is supplied by the caller.
 *
 * ── Two independent planes ───────────────────────────────────────────────────
 *   CLINICAL   `readiness_status` — exactly one of the five official states.
 *   TECHNICAL  `projection_status` — `ready` | `unavailable`.
 *
 * A technical failure NEVER becomes a clinical state. In particular it never
 * becomes `not_evaluated`: "could not evaluate" and "never evaluated" are
 * different claims, and conflating them would let a read error read as a
 * clinical fact.
 *
 * ── Authority ────────────────────────────────────────────────────────────────
 * This projection is for DISPLAY only. Critical operational actions must keep
 * validating canonical `operational_restrictions` server-side. Nothing in this
 * module authorizes anything.
 */

import {
  ReadinessAlert,
  ReadinessDecision,
  ReadinessEvaluation,
  ReadinessRestrictionSummary,
  ReadinessStatus,
  READINESS_EVALUATED_BY,
  READINESS_SCHEMA_VERSION,
} from "./health_readiness_policy";

/** Technical plane. Never persisted as `readiness_status`. */
export type ProjectionStatus = "ready" | "unavailable";

/**
 * Readiness-owned fields.
 *
 * `health_summary/current` is broader than readiness in the target schema, so
 * every field this slice owns is listed here and always written on success —
 * otherwise a merge could leave a stale restriction or alert behind.
 */
export const READINESS_OWNED_FIELDS: readonly string[] = Object.freeze([
  "projection_status",
  "readiness_status",
  "readiness_label",
  "readiness_reason",
  "readiness_reason_code",
  "readiness_updated_at",
  "projection_attempted_at",
  "evaluated_by",
  "data_completeness",
  "active_restrictions",
  "restriction_count",
  "open_alerts",
  "last_evaluated_at",
  "technical_blockers",
  "updated_at",
  "schema_version",
]);

export interface SnapshotRestriction {
  readonly id: string;
  readonly level: "absolute" | "partial" | "attention";
  readonly category: string;
  readonly description: string;
  readonly activities_restricted: readonly string[];
  readonly since: Date;
  readonly expected_end: Date | null;
  readonly is_overdue: boolean;
}

export interface SnapshotAlert {
  readonly code: string;
  readonly severity: string;
  readonly message: string;
}

/** Exactly the four ratified gates. `has_recent_exam` is deliberately absent. */
export interface SnapshotCompleteness {
  readonly has_recent_weight: boolean;
  readonly has_vaccination_current: boolean;
  readonly has_recent_consultation: boolean;
  readonly has_active_nutrition: boolean;
}

/** Payload written on a SUCCESSFUL evaluation. */
export interface ReadySnapshot {
  readonly projection_status: "ready";
  readonly readiness_status: ReadinessStatus;
  readonly readiness_label: string;
  readonly readiness_reason: string;
  readonly readiness_reason_code: string;
  readonly readiness_updated_at: Date;
  readonly projection_attempted_at: Date;
  readonly evaluated_by: string;
  readonly data_completeness: SnapshotCompleteness;
  readonly active_restrictions: readonly SnapshotRestriction[];
  readonly restriction_count: {
    readonly absolute: number;
    readonly partial: number;
    readonly attention: number;
  };
  readonly open_alerts: readonly SnapshotAlert[];
  readonly last_evaluated_at: Date | null;
  readonly technical_blockers: readonly string[];
  readonly updated_at: Date;
  readonly schema_version: number;
}

/**
 * Patch written on TECHNICAL FAILURE when a previous valid snapshot exists.
 *
 * Clinical fields are deliberately absent: they are LEFT UNTOUCHED as
 * last-known-good, not revalidated by the failed run. The client will later be
 * instructed not to present them as current while `projection_status != ready`.
 */
export interface UnavailablePatch {
  readonly projection_status: "unavailable";
  readonly projection_attempted_at: Date;
  readonly technical_blockers: readonly string[];
  readonly updated_at: Date;
  readonly schema_version: number;
}

/**
 * Payload written on TECHNICAL FAILURE when NO previous snapshot exists.
 *
 * Technical metadata only. No `readiness_status` is fabricated.
 */
export interface UnavailableSnapshot extends UnavailablePatch {}

export type ReadinessSnapshotWrite =
  | {
    readonly kind: "ready";
    readonly payload: ReadySnapshot;
  }
  | {
    readonly kind: "unavailable_preserving";
    readonly payload: UnavailablePatch;
  }
  | {
    readonly kind: "unavailable_initial";
    readonly payload: UnavailableSnapshot;
  };

/** Factual instants of recognized health evidence, for `last_evaluated_at`. */
export interface FactualEvaluationInstants {
  readonly weightAt?: Date | null;
  readonly vaccinationAt?: Date | null;
  readonly consultationAt?: Date | null;
  /**
   * Exam counts here ONLY. It proves a health evaluation occurred but is not a
   * completeness gate and produces no readiness alert.
   */
  readonly examAt?: Date | null;
}

/**
 * Latest factual health-evaluation instant.
 *
 * This is clinical time, NOT projection time: a K9 evaluated last month has a
 * month-old `last_evaluated_at` even though `readiness_updated_at` is now.
 *
 * Nutrition-plan activation is deliberately excluded — an active plan is a
 * configuration state, not a clinical evaluation event.
 */
export function deriveLastEvaluatedAt(
  instants: FactualEvaluationInstants,
): Date | null {
  const candidates = [
    instants.weightAt,
    instants.vaccinationAt,
    instants.consultationAt,
    instants.examAt,
  ].filter((value): value is Date => value instanceof Date);

  if (candidates.length === 0) return null;
  return candidates.reduce((latest, candidate) =>
    candidate.getTime() > latest.getTime() ? candidate : latest,
  );
}

function toSnapshotRestrictions(
  restrictions: readonly ReadinessRestrictionSummary[],
): readonly SnapshotRestriction[] {
  return restrictions.map((restriction) => ({
    id: restriction.id,
    level: restriction.level,
    category: restriction.category,
    description: restriction.description,
    activities_restricted: [...restriction.activitiesRestricted],
    since: restriction.since,
    expected_end: restriction.expectedEnd,
    is_overdue: restriction.isOverdue,
  }));
}

function toSnapshotAlerts(
  alerts: readonly ReadinessAlert[],
): readonly SnapshotAlert[] {
  return alerts.map((alert) => ({
    code: alert.code,
    severity: alert.severity,
    message: alert.label,
  }));
}

/**
 * Builds the success payload.
 *
 * The projector FORMATS the evaluator's decision; it never derives a different
 * status or reason. `readiness_status`, `readiness_label`, `readiness_reason`,
 * `readiness_reason_code`, the alerts and the completeness booleans all come
 * straight from the single owner.
 */
export function buildReadySnapshot(
  decision: ReadinessDecision,
  now: Date,
  instants: FactualEvaluationInstants,
): ReadySnapshot {
  return {
    projection_status: "ready",
    readiness_status: decision.readinessStatus,
    readiness_label: decision.readinessLabel,
    readiness_reason: decision.readinessReason,
    readiness_reason_code: decision.readinessReasonCode,
    // Projection time — when the Function evaluated.
    readiness_updated_at: now,
    projection_attempted_at: now,
    evaluated_by: READINESS_EVALUATED_BY,
    data_completeness: {
      has_recent_weight: decision.completeness.hasRecentWeight,
      has_vaccination_current: decision.completeness.hasVaccinationCurrent,
      has_recent_consultation: decision.completeness.hasRecentConsultation,
      has_active_nutrition: decision.completeness.hasActiveNutrition,
    },
    // ALL valid active restrictions, not only the one that set the status.
    active_restrictions: toSnapshotRestrictions(decision.activeRestrictions),
    restriction_count: {
      absolute: decision.restrictionCount.absolute,
      partial: decision.restrictionCount.partial,
      attention: decision.restrictionCount.attention,
    },
    open_alerts: toSnapshotAlerts(decision.openAlerts),
    // Clinical time — distinct from the projection timestamps above.
    last_evaluated_at: deriveLastEvaluatedAt(instants),
    // Cleared on success so a prior failure leaves no residue.
    technical_blockers: [],
    updated_at: now,
    schema_version: READINESS_SCHEMA_VERSION,
  };
}

/** Sanitized, machine-readable technical blocker codes. */
export function buildTechnicalBlockers(
  reasonCodes: readonly string[],
): readonly string[] {
  const unique = new Set<string>();
  for (const raw of reasonCodes) {
    const trimmed = raw.trim();
    if (trimmed === "") continue;
    // Keep codes machine-readable and free of payload detail.
    const sanitized = trimmed.toLowerCase().replace(/[^a-z0-9_]/g, "_").slice(0, 64);
    if (sanitized !== "") unique.add(sanitized);
  }
  return [...unique].sort();
}

export function buildUnavailablePatch(
  reasonCodes: readonly string[],
  now: Date,
): UnavailablePatch {
  return {
    projection_status: "unavailable",
    projection_attempted_at: now,
    technical_blockers: buildTechnicalBlockers(reasonCodes),
    updated_at: now,
    schema_version: READINESS_SCHEMA_VERSION,
  };
}

/**
 * Decides what to write for a given evaluation outcome.
 *
 * `hasPreviousValidSnapshot` selects between preserving last-known-good
 * clinical fields and writing technical metadata only.
 */
export function buildReadinessSnapshotWrite(options: {
  readonly evaluation: ReadinessEvaluation;
  readonly now: Date;
  readonly instants: FactualEvaluationInstants;
  readonly hasPreviousValidSnapshot: boolean;
  /** Additional technical blockers detected while reading evidence. */
  readonly extraBlockers?: readonly string[];
}): ReadinessSnapshotWrite {
  const {evaluation, now, instants, hasPreviousValidSnapshot} = options;
  const extraBlockers = options.extraBlockers ?? [];

  if (evaluation.outcome === "decided") {
    return {
      kind: "ready",
      payload: buildReadySnapshot(evaluation.decision, now, instants),
    };
  }

  const blockers = [evaluation.reasonCode, ...extraBlockers];
  const payload = buildUnavailablePatch(blockers, now);

  return hasPreviousValidSnapshot
    ? {kind: "unavailable_preserving", payload}
    : {kind: "unavailable_initial", payload};
}
