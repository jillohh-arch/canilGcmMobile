/**
 * Readiness v1 — projection generation coordination (pure logic).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Why this module exists
 * ----------------------
 * The readiness projector runs from five independent entry points (four
 * Firestore triggers plus the explicit refresh callable). Every execution
 * rereads all canonical sources, so a late execution never derives state from a
 * stale event payload — but the WRITE itself had no ordering guard, so an
 * execution that read old sources could still commit AFTER an execution that
 * read new ones and silently overwrite it.
 *
 * A per-K9 monotonic generation fixes that. Each execution reserves a
 * generation BEFORE reading any source, so a higher generation always means
 * "started later, therefore saw state at least as new". The write is then
 * guarded: an execution whose generation was already superseded does not write.
 *
 * Three numbers, three distinct jobs — never conflate them:
 *
 *   last_reserved_generation  (server-only)
 *       ordering of projector EXECUTIONS. Advances at reservation.
 *
 *   last_applied_generation   (server-only)
 *       ordering of projector WRITES, ready AND unavailable alike. This is the
 *       guard. It must cover unavailable writes too: otherwise a stale
 *       unavailable run could still merge projection_status/technical_blockers
 *       over a newer ready projection — stale overwrite moved to another field,
 *       not eliminated.
 *
 *   projection_generation     (client-observable, on health_summary/current)
 *       generation of the last READY payload. This is the only one a client may
 *       use as causal proof, because only a ready run revalidated the clinical
 *       payload. An unavailable run never advances it.
 *
 * `readiness_updated_at` remains freshness only, and mutation `operationId`
 * remains idempotency only. Neither is an ordering authority.
 */

/**
 * Server-only coordination namespace.
 *
 * Already denied to clients by `firestore.rules` via
 * `match /_health_projection_state/{document=**} { allow read, write: if false }`,
 * so hosting the counter here needs no rules change. Admin SDK bypasses rules.
 */
export const READINESS_GENERATION_ROOT_COLLECTION = "_health_projection_state";
export const READINESS_GENERATION_ROOT_DOC = "health_readiness_v1";
export const READINESS_GENERATION_DOGS_COLLECTION = "dogs";

/** Field names on the coordination document. */
export const LAST_RESERVED_GENERATION_FIELD = "last_reserved_generation";
export const LAST_APPLIED_GENERATION_FIELD = "last_applied_generation";

/**
 * Client-observable field on `health_summary/current`, written on READY only.
 *
 * Added WITHOUT bumping `schema_version`: the mobile parser pins
 * `supportedSchemaVersion = 1` and treats a higher value as incompatible, so a
 * bump would silently degrade every already-shipped client to "unavailable".
 * An unknown extra field, by contrast, is simply ignored by that parser.
 */
export const PROJECTION_GENERATION_FIELD = "projection_generation";

/**
 * Upper bound for a reservation. One below MAX_SAFE_INTEGER so `current + 1`
 * can never leave the exactly-representable range.
 */
export const MAX_READINESS_GENERATION = Number.MAX_SAFE_INTEGER - 1;

/** Coordination state for one K9. Absent fields bootstrap to 0. */
export interface ReadinessGenerationState {
  readonly lastReservedGeneration: number;
  readonly lastAppliedGeneration: number;
}

/**
 * Causal convergence verdict, exposed additively under `result.convergence`.
 *
 * Answers exactly one question: "can the server prove a READY summary exists
 * whose generation is >= the generation this refresh required?"
 *
 * There is deliberately no generic `failed` member. Authorization, validation,
 * integrity and transport failures stay ordinary callable errors — folding them
 * in here would make `failed` ambiguous between "no causal proof" and "the call
 * itself broke".
 */
export type ConvergenceStatus = "confirmed" | "not_confirmed" | "unavailable";

/** The `result.convergence` object. Additive; never replaces a legacy field. */
export interface ConvergenceReport {
  readonly status: ConvergenceStatus;
  /** Generation reserved by THIS refresh execution. Always present, always > 0. */
  readonly requiredGeneration: number;
  /** Observed READY generation, or null when none is observable. Never 0. */
  readonly observedGeneration: number | null;
}

/**
 * Reads the client-observable READY generation off a summary snapshot.
 *
 * Fails closed to `null` — never to `0` — on absent, legacy-without-the-field,
 * or malformed values. `null` means "no causal proof available", which can only
 * ever produce `not_confirmed`; a fabricated `0` would be a number that invites
 * arithmetic and could read as a real generation.
 */
export function readObservedReadyGeneration(
  stored: Readonly<Record<string, unknown>> | null,
): number | null {
  const raw = stored?.[PROJECTION_GENERATION_FIELD];
  if (raw === undefined || raw === null) return null;
  if (
    typeof raw !== "number" ||
    !Number.isSafeInteger(raw) ||
    raw <= 0 ||
    raw > MAX_READINESS_GENERATION
  ) {
    // Corrupt client-observable marker: refuse to treat it as proof.
    return null;
  }
  return raw;
}

/**
 * Classifies causal convergence for one refresh execution.
 *
 * ── Precedence: OBSERVED PROOF FIRST ────────────────────────────────────────
 * The question is about the state currently committed, NOT about what this
 * particular execution managed to write. So a READY summary at generation
 * >= required confirms even when THIS execution ended unavailable or was
 * superseded: any generation above the required one was reserved after it, and
 * the required one was itself reserved after the mutation committed, so by
 * transitivity that newer READY read state at least as new as the caller needs.
 *
 * Checking this execution's own outcome first would produce a false negative
 * exactly when concurrency did the caller a favour — a refresh whose sources
 * were briefly unreadable would report unavailable while a newer, complete
 * READY projection sat committed in front of it. That would also contradict the
 * frozen `>=` rule (B4-R.B §14) by making convergence depend on WHICH execution
 * produced the proof.
 *
 * ── Why the generation alone is never enough ─────────────────────────────────
 * `projection_generation >= required` is only proof while the observed
 * `projection_status` is still `ready`. An unavailable write leaves the previous
 * READY marker untouched as last-known-good, so the pair
 * (`unavailable`, generation 42) means "42 was not revalidated", not "42 is
 * proven". Both conditions are therefore required together.
 */
export function classifyConvergence(options: {
  readonly requiredGeneration: number;
  readonly observedGeneration: number | null;
  readonly observedProjectionStatus: unknown;
  /** True when this execution took the unavailable_preserving/initial path. */
  readonly isUnavailableResult: boolean;
}): ConvergenceReport {
  const {
    requiredGeneration,
    observedGeneration,
    observedProjectionStatus,
    isUnavailableResult,
  } = options;

  // A required generation always comes from a completed reservation. A bad one
  // is an integrity bug, not a "no proof" condition, so it must not silently
  // degrade into not_confirmed.
  if (
    !Number.isSafeInteger(requiredGeneration) ||
    requiredGeneration <= 0 ||
    requiredGeneration > MAX_READINESS_GENERATION
  ) {
    throw new Error("invalid_generation_candidate");
  }

  // 1. Observed proof wins, whatever this execution's own outcome was.
  if (
    observedProjectionStatus === "ready" &&
    observedGeneration !== null &&
    observedGeneration >= requiredGeneration
  ) {
    return {status: "confirmed", requiredGeneration, observedGeneration};
  }

  // 2. No proof: report the factual unavailable condition when there is one.
  //    Either the state we observed is itself unavailable, or the reread told us
  //    nothing and this execution is known to have ended unavailable.
  if (observedProjectionStatus === "unavailable" || isUnavailableResult) {
    return {status: "unavailable", requiredGeneration, observedGeneration};
  }

  // 3. Everything else: the barrier simply could not be established.
  return {status: "not_confirmed", requiredGeneration, observedGeneration};
}

/** What a guarded apply actually did. `superseded` is healthy, not an error. */
export type ProjectionApplyOutcome =
  | "applied_ready"
  | "applied_unavailable"
  | "superseded";

/**
 * Reads one generation counter field, failing closed.
 *
 * Absent/null bootstraps to 0 — a K9 that never projected, or a summary written
 * before this contract existed, is legitimately at generation zero. Anything
 * else present but unusable (string, float, negative, NaN, beyond safe range)
 * is a corrupt coordination document: we refuse rather than silently reset,
 * because resetting would hand out a generation that was already applied and
 * reopen the overwrite window this module exists to close.
 */
export function parseGenerationField(raw: unknown, field: string): number {
  if (raw === undefined || raw === null) return 0;
  if (
    typeof raw !== "number" ||
    !Number.isSafeInteger(raw) ||
    raw < 0 ||
    raw > MAX_READINESS_GENERATION
  ) {
    throw new Error(`invalid_generation_state:${field}`);
  }
  return raw;
}

/** Parses a whole coordination document, failing closed on either field. */
export function parseGenerationState(
  stored: Readonly<Record<string, unknown>> | null,
): ReadinessGenerationState {
  const lastReservedGeneration = parseGenerationField(
    stored?.[LAST_RESERVED_GENERATION_FIELD],
    LAST_RESERVED_GENERATION_FIELD,
  );
  const lastAppliedGeneration = parseGenerationField(
    stored?.[LAST_APPLIED_GENERATION_FIELD],
    LAST_APPLIED_GENERATION_FIELD,
  );

  // Applied can never lead reserved: every apply is preceded by its own
  // reservation. If it does, the document is not trustworthy for ordering.
  if (lastAppliedGeneration > lastReservedGeneration) {
    throw new Error("invalid_generation_state:applied_ahead_of_reserved");
  }

  return {lastReservedGeneration, lastAppliedGeneration};
}

/**
 * Next generation to hand out. Never reuses, never wraps.
 *
 * Gaps are expected and harmless: a reserved generation whose execution dies
 * before applying simply never appears in `last_applied_generation`.
 */
export function nextGeneration(current: number): number {
  if (current >= MAX_READINESS_GENERATION) {
    throw new Error("generation_exhausted");
  }
  return current + 1;
}

/**
 * Ordering decision for a candidate write.
 *
 * The guard compares against `lastAppliedGeneration` — not against the
 * summary's `projection_generation` — precisely so unavailable writes are
 * ordered too. `>=` (not `>`) makes a replayed apply of the same generation a
 * no-op rather than a rewrite.
 */
export function decideProjectionApply(options: {
  readonly state: ReadinessGenerationState;
  readonly generation: number;
  readonly isReady: boolean;
}):
  | {readonly kind: "superseded"}
  | {
    readonly kind: "apply";
    readonly outcome: "applied_ready" | "applied_unavailable";
    /** Ready generation to publish, or null to leave the current one untouched. */
    readonly publishReadyGeneration: number | null;
  } {
  const {state, generation, isReady} = options;

  if (!Number.isSafeInteger(generation) || generation <= 0) {
    throw new Error("invalid_generation_candidate");
  }

  if (state.lastAppliedGeneration >= generation) {
    return {kind: "superseded"};
  }

  return isReady ?
    {
      kind: "apply",
      outcome: "applied_ready",
      publishReadyGeneration: generation,
    } :
    {
      kind: "apply",
      outcome: "applied_unavailable",
      publishReadyGeneration: null,
    };
}
