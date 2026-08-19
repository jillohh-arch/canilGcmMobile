/**
 * Readiness v1 — Firestore boundary for the readiness projection.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Pipeline:
 *   readEvidence()  → Firestore reads (this module)
 *   evaluateReadiness()  → pure decision (health_readiness_policy.ts)
 *   buildReadinessSnapshotWrite() → pure payload (health_readiness_snapshot.ts)
 *   persistReadinessProjection() → Firestore write (this module)
 *
 * This module owns ONLY I/O orchestration. It never decides a clinical state,
 * never recomputes readiness, and never authorizes an operational action.
 *
 * Writes exactly one document per K9: `dogs/{dogId}/health_summary/current`.
 * Admin SDK only — clients never write this path.
 */

import {
  EvidenceState,
  evaluateReadiness,
  ReadinessConfig,
  ReadinessEvaluation,
  ReadinessRestriction,
  VaccinationEvidenceValue,
} from "./health_readiness_policy";
import {
  analyzeWeightCollection,
  RawDoc,
  RawQuery,
  resolveConsultationEvidence,
  resolveExamEvidence,
  resolveNutritionEvidence,
  resolveRestrictionsEvidence,
  resolveVaccinationEvidence,
  resolveWeightEvidence,
} from "./health_readiness_evidence_logic";
import {ProjectionApplyOutcome} from "./health_readiness_generation";
import {
  buildReadinessSnapshotWrite,
  FactualEvaluationInstants,
  ProjectionStatus,
  ReadinessSnapshotWrite,
  READINESS_OWNED_FIELDS,
} from "./health_readiness_snapshot";

/** Minimal logger, injected so submodules never import firebase-functions. */
export interface ProjectorLogger {
  info: (message: string, context?: Record<string, unknown>) => void;
  warn: (message: string, context?: Record<string, unknown>) => void;
  error: (message: string, context?: Record<string, unknown>) => void;
}

/**
 * Firestore surface the projector needs, kept narrow so the whole projector is
 * testable with an in-memory fake as well as against the emulator.
 */
export interface ProjectorFirestore {
  /** Reads a whole subcollection under a dog. */
  readSubcollection: (dogId: string, collection: string) => Promise<RawQuery>;
  /** Reads `dogs/{dogId}/health_summary/current`, or null when absent. */
  readCurrentSummary: (
    dogId: string,
  ) => Promise<Readonly<Record<string, unknown>> | null>;
  /**
   * Reserves this execution's projection generation. MUST be called before any
   * source read so a higher generation always means "started later".
   */
  reserveProjectionGeneration: (dogId: string) => Promise<number>;
  /**
   * Atomically ordering-guards and applies a projection.
   *
   * There is deliberately no unguarded write helper: every path into
   * `health_summary/current` goes through here, so a superseded execution can
   * never overwrite a newer one — whether it is ready or unavailable.
   */
  applyProjection: (args: {
    readonly dogId: string;
    readonly generation: number;
    readonly isReady: boolean;
    readonly payload: Record<string, unknown>;
  }) => Promise<ProjectionApplyOutcome>;
}

export interface ProjectorDeps {
  readonly firestore: ProjectorFirestore;
  readonly logger: ProjectorLogger;
  readonly config: ReadinessConfig;
  readonly now: () => Date;
}

export interface EvaluateReadinessResult {
  readonly dogId: string;
  readonly projectionStatus: ProjectionStatus;
  /** Present only when a clinical decision was reached. */
  readonly readinessStatus: string | null;
  readonly technicalBlockers: readonly string[];
  readonly operation: "ready" | "unavailable_preserving" | "unavailable_initial";
  /**
   * Generation reserved by THIS execution, before any source read.
   *
   * Internal metadata for the future causal-convergence contract. Not yet part
   * of any callable's public response — the refresh wire stays frozen in C1.
   */
  readonly requiredGeneration: number;
  /** Whether this execution's payload was applied or already superseded. */
  readonly applyOutcome: ProjectionApplyOutcome;
}

/** Canonical + coexistence source paths. */
const WEIGHT_RECORDS = "weight_records";
const VACCINATION_RECORDS = "vaccination_records";
const HEALTH_EVENTS = "health_events";
const NUTRITION_PLANS = "nutrition_plans";
const OPERATIONAL_RESTRICTIONS = "operational_restrictions";

/**
 * Firestore document ids must be safe path segments. A bad dogId is a
 * programming error, not a clinical condition.
 */
function assertSafeDogId(dogId: string): void {
  if (
    typeof dogId !== "string" ||
    dogId.trim() === "" ||
    dogId.length > 128 ||
    dogId.includes("/") ||
    dogId === "." ||
    dogId === ".."
  ) {
    throw new Error("invalid_dog_id");
  }
}

export interface ReadinessEvidenceBundle {
  readonly evidence: Parameters<typeof evaluateReadiness>[0];
  readonly instants: FactualEvaluationInstants;
  /** Technical blockers observed while reading, beyond the evaluator's own. */
  readonly extraBlockers: readonly string[];
}

/**
 * Extracts the factual weight instant for `last_evaluated_at`.
 *
 * Reuses the canonical analysis so the instant always belongs to the SAME
 * record the parity-proven ordering selected as current.
 */
function factualWeightAt(query: RawQuery, dogId: string): Date | null {
  if (query.kind === "failed") return null;
  const analysis = analyzeWeightCollection(query.docs, dogId);
  if (analysis.kind !== "current") return null;
  return analysis.current?.measuredAt ?? null;
}

function vaccinationInstant(
  evidence: EvidenceState<VaccinationEvidenceValue>,
): Date | null {
  if (evidence.kind !== "present") return null;
  return evidence.value.appliedAt ?? null;
}

function presentInstant(evidence: EvidenceState<Date>): Date | null {
  return evidence.kind === "present" ? evidence.value : null;
}

/**
 * Reads every readiness evidence source for one K9.
 *
 * Queries run in parallel; a per-source failure is captured as a `failed`
 * RawQuery rather than throwing, so one unreadable source cannot masquerade as
 * "no records" and cannot abort the sources that did succeed.
 */
export async function readReadinessEvidence(
  dogId: string,
  deps: ProjectorDeps,
): Promise<ReadinessEvidenceBundle> {
  assertSafeDogId(dogId);

  const [
    weightQuery,
    canonicalVaccinationQuery,
    healthEventsQuery,
    nutritionQuery,
    restrictionsQuery,
  ] = await Promise.all([
    deps.firestore.readSubcollection(dogId, WEIGHT_RECORDS),
    deps.firestore.readSubcollection(dogId, VACCINATION_RECORDS),
    deps.firestore.readSubcollection(dogId, HEALTH_EVENTS),
    deps.firestore.readSubcollection(dogId, NUTRITION_PLANS),
    deps.firestore.readSubcollection(dogId, OPERATIONAL_RESTRICTIONS),
  ]);

  const latestWeightAt = resolveWeightEvidence(weightQuery, dogId);
  const vaccination = resolveVaccinationEvidence(
    canonicalVaccinationQuery,
    healthEventsQuery,
  );
  const latestConsultationAt = resolveConsultationEvidence(healthEventsQuery);
  const nutrition = resolveNutritionEvidence(nutritionQuery);
  const latestExamAt = resolveExamEvidence(healthEventsQuery);
  const restrictions = resolveRestrictionsEvidence(restrictionsQuery);

  // A restriction source we cannot trust must block any clinical claim: a
  // dropped restriction could present a restricted K9 as operational.
  const extraBlockers: string[] = [];
  let activeRestrictions: readonly ReadinessRestriction[] = [];
  if (restrictions.kind === "unreliable") {
    extraBlockers.push(`restrictions_source_${restrictions.reasonCode}`);
  } else {
    activeRestrictions = restrictions.active;
  }

  return {
    evidence: {
      now: deps.now(),
      activeRestrictions,
      latestWeightAt,
      vaccination,
      latestConsultationAt,
      nutrition,
      latestExamAt,
      config: deps.config,
    },
    instants: {
      weightAt: factualWeightAt(weightQuery, dogId),
      vaccinationAt: vaccinationInstant(vaccination),
      consultationAt: presentInstant(latestConsultationAt),
      examAt: presentInstant(latestExamAt),
    },
    extraBlockers,
  };
}

/**
 * Determines whether the stored summary holds a valid clinical readiness that
 * must be preserved as last-known-good on technical failure.
 */
export function hasPreviousValidReadiness(
  stored: Readonly<Record<string, unknown>> | null,
): boolean {
  if (stored === null) return false;
  const status = stored["readiness_status"];
  return typeof status === "string" && status.trim() !== "";
}

/**
 * Persists a readiness snapshot write under the generation ordering guard.
 *
 * Uses merge so unrelated future summary slices survive, but on a ready write
 * emits EVERY readiness-owned field explicitly — otherwise an emptied
 * restriction or alert array would silently keep its previous contents. The
 * `projection_generation` field is added on ready writes only; the guarded
 * apply publishes it atomically with the payload.
 *
 * Returns the apply outcome. `superseded` means a generation >= this one was
 * already applied, so nothing was written — a healthy result under concurrency,
 * not an error.
 */
export async function persistReadinessProjection(
  dogId: string,
  write: ReadinessSnapshotWrite,
  generation: number,
  deps: ProjectorDeps,
): Promise<ProjectionApplyOutcome> {
  assertSafeDogId(dogId);

  const payload: Record<string, unknown> = {...write.payload};
  const isReady = write.kind === "ready";

  if (isReady) {
    // Defensive completeness check: every owned field must be present so a
    // merge can never leave a stale readiness value behind.
    const missing = READINESS_OWNED_FIELDS.filter(
      (field) => !(field in payload),
    );
    if (missing.length > 0) {
      throw new Error(`incomplete_readiness_payload:${missing.join(",")}`);
    }
  }

  return deps.firestore.applyProjection({
    dogId,
    generation,
    isReady,
    payload,
  });
}

/**
 * Evaluates readiness for one K9 and persists the projection.
 *
 * Returns a technical result for tests and future callers. Never throws for
 * clinical reasons; a technical failure yields `projection_status = unavailable`
 * with sanitized blocker codes.
 */
export async function evaluateHealthReadiness(
  dogId: string,
  deps: ProjectorDeps,
): Promise<EvaluateReadinessResult> {
  assertSafeDogId(dogId);

  // Reserve BEFORE any source read: a higher generation must always mean this
  // execution started later, so its reads saw state at least as new.
  const generation = await deps.firestore.reserveProjectionGeneration(dogId);

  const bundle = await readReadinessEvidence(dogId, deps);

  let evaluation: ReadinessEvaluation = evaluateReadiness(bundle.evidence);

  // An unreadable restriction source outranks a clinical verdict, because
  // restrictions are the most consequential evidence in the whole model.
  if (bundle.extraBlockers.length > 0 && evaluation.outcome === "decided") {
    evaluation = {
      outcome: "indeterminate",
      reasonCode: bundle.extraBlockers[0],
    };
  }

  const stored = await deps.firestore.readCurrentSummary(dogId);
  const write = buildReadinessSnapshotWrite({
    evaluation,
    now: bundle.evidence.now,
    instants: bundle.instants,
    hasPreviousValidSnapshot: hasPreviousValidReadiness(stored),
    extraBlockers: bundle.extraBlockers,
  });

  const applyOutcome = await persistReadinessProjection(
    dogId,
    write,
    generation,
    deps,
  );

  const result: EvaluateReadinessResult = {
    dogId,
    projectionStatus: write.payload.projection_status,
    readinessStatus:
      write.kind === "ready" ? write.payload.readiness_status : null,
    technicalBlockers: write.payload.technical_blockers ?? [],
    operation: write.kind,
    requiredGeneration: generation,
    applyOutcome,
  };

  if (applyOutcome === "superseded") {
    // A newer generation already committed. Expected under concurrency; log so
    // the ordering guard's behavior is observable, never silently.
    deps.logger.info("HealthReadiness projection superseded", {
      dogId,
      generation,
      operation: write.kind,
    });
  } else if (write.kind === "ready") {
    deps.logger.info("HealthReadiness projection updated", {
      dogId,
      generation,
      readinessStatus: result.readinessStatus,
      restrictionCount: write.payload.restriction_count,
    });
  } else {
    // Divergence signal: log at warn, never silently degrade.
    deps.logger.warn("HealthReadiness projection unavailable", {
      dogId,
      generation,
      operation: write.kind,
      technicalBlockers: result.technicalBlockers,
    });
  }

  return result;
}

/** Re-exported for the Firestore adapter layer. */
export type {RawDoc, RawQuery};
