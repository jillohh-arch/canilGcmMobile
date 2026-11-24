/**
 * F40 Occupancy Domain Contract — pure TypeScript representation of the
 * ratified vehicle-occupancy domain model.
 *
 * CRITICAL BOUNDARY:
 * - ZERO Firestore / Admin SDK imports.
 * - ZERO I/O or side effects.
 * - All functions are pure; they accept explicit evidence contracts and
 *   return deterministic results.
 * - This module models EXPECTED generation transitions in memory. It does
 *   NOT prove atomic persistence or Firestore concurrency safety. Those
 *   guarantees belong to the transaction-aware integration layer (future).
 *
 * Parity source: lib/features/shifts/domain/*.dart (Wave 2 R1 reference).
 */

// ---------------------------------------------------------------------------
// A. OccupancySession
// ---------------------------------------------------------------------------

export enum OccupancySessionState {
  active = "active",
  selfRegularizationRequested = "selfRegularizationRequested",
  coverageValidated = "coverageValidated",
  successionAllowed = "successionAllowed",
  successionDenied = "successionDenied",
  conflicted = "conflicted",
  stale = "stale",
}

export interface OccupancySessionInput {
  readonly sessionId: string;
  readonly vehicleId: string;
  readonly crewId: string;
  readonly generation: number;
  readonly predecessorSessionId?: string | null;
  readonly state: OccupancySessionState;
}

export interface OccupancySession {
  readonly sessionId: string;
  readonly vehicleId: string;
  readonly crewId: string;
  readonly generation: number;
  readonly predecessorSessionId: string | null;
  readonly state: OccupancySessionState;
}

export function createOccupancySession(input: OccupancySessionInput): OccupancySession {
  if (!input.sessionId || input.sessionId.length === 0) {
    throw new Error("sessionId must not be empty");
  }
  if (!input.vehicleId || input.vehicleId.length === 0) {
    throw new Error("vehicleId must not be empty");
  }
  if (!input.crewId || input.crewId.length === 0) {
    throw new Error("crewId must not be empty");
  }
  if (!Number.isInteger(input.generation) || input.generation <= 0) {
    throw new Error("generation must be an integer > 0");
  }
  return Object.freeze({
    sessionId: input.sessionId,
    vehicleId: input.vehicleId,
    crewId: input.crewId,
    generation: input.generation,
    predecessorSessionId: input.predecessorSessionId ?? null,
    state: input.state,
  });
}

const TERMINAL_STATES: ReadonlySet<OccupancySessionState> = new Set([
  OccupancySessionState.successionAllowed,
  OccupancySessionState.successionDenied,
  OccupancySessionState.conflicted,
]);

export function createSuccessor(
  session: OccupancySession,
  newSessionId: string,
  newCrewId: string,
  initialState: OccupancySessionState = OccupancySessionState.active,
): OccupancySession {
  if (session.state === OccupancySessionState.stale) {
    throw new Error(`Cannot create successor from stale session ${session.sessionId}`);
  }
  if (TERMINAL_STATES.has(session.state)) {
    throw new Error(
      `Session ${session.sessionId} is in terminal state ${session.state} and cannot produce a successor`,
    );
  }
  return createOccupancySession({
    sessionId: newSessionId,
    vehicleId: session.vehicleId,
    crewId: newCrewId,
    generation: session.generation + 1,
    predecessorSessionId: session.sessionId,
    state: initialState,
  });
}

export function copyWithState(
  session: OccupancySession,
  newState: OccupancySessionState,
): OccupancySession {
  return Object.freeze({
    sessionId: session.sessionId,
    vehicleId: session.vehicleId,
    crewId: session.crewId,
    generation: session.generation,
    predecessorSessionId: session.predecessorSessionId,
    state: newState,
  });
}

// ---------------------------------------------------------------------------
// B. OperationalEngagement
// ---------------------------------------------------------------------------

export interface OperationalEngagement {
  readonly engagementId: string;
  readonly linkedOccurrenceId: string | null;
  readonly occupancySessionId: string;
  readonly vehicleId: string;
  readonly generation: number;
  readonly serverConfirmed: boolean;
  readonly startedAt: Date;
  readonly endedAt: Date | null;
}

// ---------------------------------------------------------------------------
// C. Coverage — Evidence Classification & Verdict
// ---------------------------------------------------------------------------

export enum EvidenceClassification {
  authoritativeCurrent = "authoritativeCurrent",
  legacyDocumentaryOnly = "legacyDocumentaryOnly",
  incomplete = "incomplete",
  contradictory = "contradictory",
  insufficientProvenance = "insufficientProvenance",
}

export interface EvidenceInput {
  readonly hasVerifiedProvenance: boolean;
  readonly isCurrent: boolean;
  readonly isComplete: boolean;
  readonly hasContradictions: boolean;
  readonly isLegacyDocumentary: boolean;
}

/**
 * Classifies evidence with strict priority matching Dart:
 * contradictory > incomplete > insufficientProvenance > legacy > authoritative.
 */
export function classifyEvidence(input: EvidenceInput): EvidenceClassification {
  if (input.hasContradictions) return EvidenceClassification.contradictory;
  if (!input.isComplete) return EvidenceClassification.incomplete;
  if (!input.hasVerifiedProvenance) return EvidenceClassification.insufficientProvenance;
  if (input.isLegacyDocumentary) return EvidenceClassification.legacyDocumentaryOnly;
  if (!input.isCurrent) return EvidenceClassification.insufficientProvenance;
  return EvidenceClassification.authoritativeCurrent;
}

export enum CoverageVerdict {
  BLOCKING = "BLOCKING",
  PROVEN_CLEAR = "PROVEN_CLEAR",
  INDETERMINATE = "INDETERMINATE",
}

export interface Engagement {
  readonly engagementId: string;
  readonly isBlocking: boolean;
}

export interface CoverageEvidence {
  readonly classification: EvidenceClassification;
  readonly matchesSessionAndGeneration: boolean;
  readonly isAuthoritativeAndSufficient: boolean;
}

/**
 * Pure coverage evaluation mirroring Dart evaluateCoverage exactly.
 *
 * Priority:
 * 1. Any blocking engagement => BLOCKING (absolute priority)
 * 2. Empty evidence => INDETERMINATE
 * 3. Any evidence classified contradictory/incomplete/insufficientProvenance/
 *    legacyDocumentaryOnly => INDETERMINATE
 * 4. PROVEN_CLEAR only when evidence is authoritativeCurrent AND
 *    matchesSessionAndGeneration AND isAuthoritativeAndSufficient
 */
export function evaluateCoverage(params: {
  evidence: readonly CoverageEvidence[];
  engagements: readonly Engagement[];
}): CoverageVerdict {
  for (const eng of params.engagements) {
    if (eng.isBlocking) return CoverageVerdict.BLOCKING;
  }
  if (params.evidence.length === 0) return CoverageVerdict.INDETERMINATE;

  let hasAuthoritativeComplete = false;
  for (const ev of params.evidence) {
    if (
      ev.classification === EvidenceClassification.contradictory ||
      ev.classification === EvidenceClassification.incomplete ||
      ev.classification === EvidenceClassification.insufficientProvenance ||
      ev.classification === EvidenceClassification.legacyDocumentaryOnly
    ) {
      return CoverageVerdict.INDETERMINATE;
    }
    if (
      ev.classification === EvidenceClassification.authoritativeCurrent &&
      ev.matchesSessionAndGeneration &&
      ev.isAuthoritativeAndSufficient
    ) {
      hasAuthoritativeComplete = true;
    }
  }
  return hasAuthoritativeComplete ? CoverageVerdict.PROVEN_CLEAR : CoverageVerdict.INDETERMINATE;
}

// ---------------------------------------------------------------------------
// D. Succession State Machine
// ---------------------------------------------------------------------------

export interface SuccessionTransition {
  readonly newState: OccupancySessionState;
  readonly accepted: boolean;
  readonly rejectionReason: string | null;
}

function makeTransition(
  newState: OccupancySessionState,
  accepted: boolean,
  rejectionReason?: string,
): SuccessionTransition {
  return Object.freeze({
    newState,
    accepted,
    rejectionReason: rejectionReason ?? null,
  });
}

export function proposeSelfRegularizationRequest(
  session: OccupancySession,
): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Stale session cannot request self-regularization");
  }
  if (session.state !== OccupancySessionState.active) {
    return makeTransition(
      session.state,
      false,
      `Self-regularization request only valid from active state, current: ${session.state}`,
    );
  }
  return makeTransition(OccupancySessionState.selfRegularizationRequested, true);
}

export function proposeCoverageEvaluation(
  session: OccupancySession,
  verdict: CoverageVerdict,
): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Stale session cannot evaluate coverage");
  }
  if (session.state !== OccupancySessionState.selfRegularizationRequested) {
    return makeTransition(
      session.state,
      false,
      `Coverage evaluation only valid from selfRegularizationRequested state, current: ${session.state}`,
    );
  }
  switch (verdict) {
    case CoverageVerdict.BLOCKING:
      return makeTransition(OccupancySessionState.successionDenied, true);
    case CoverageVerdict.INDETERMINATE:
      return makeTransition(
        OccupancySessionState.selfRegularizationRequested,
        false,
        "Indeterminate coverage does not allow succession to proceed",
      );
    case CoverageVerdict.PROVEN_CLEAR:
      return makeTransition(OccupancySessionState.coverageValidated, true);
  }
}

export function proposeSuccessionPermission(
  session: OccupancySession,
): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Stale session cannot be granted succession");
  }
  if (session.state !== OccupancySessionState.coverageValidated) {
    return makeTransition(
      session.state,
      false,
      `Succession permission only valid from coverageValidated state, current: ${session.state}`,
    );
  }
  return makeTransition(OccupancySessionState.successionAllowed, true);
}

export function proposeSuccessionDenial(
  session: OccupancySession,
  reason: string,
): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Stale session cannot be denied succession");
  }
  if (
    session.state !== OccupancySessionState.selfRegularizationRequested &&
    session.state !== OccupancySessionState.coverageValidated
  ) {
    return makeTransition(
      session.state,
      false,
      `Succession denial only valid from selfRegularizationRequested or coverageValidated state, current: ${session.state}`,
    );
  }
  return makeTransition(OccupancySessionState.successionDenied, true, reason);
}

export function proposeStale(session: OccupancySession): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Session is already stale");
  }
  if (TERMINAL_STATES.has(session.state)) {
    return makeTransition(
      session.state,
      false,
      `Terminal state ${session.state} cannot transition to stale`,
    );
  }
  return makeTransition(OccupancySessionState.stale, true);
}

export function proposeConflict(session: OccupancySession): SuccessionTransition {
  if (session.state === OccupancySessionState.stale) {
    return makeTransition(OccupancySessionState.stale, false, "Stale session cannot transition to conflicted");
  }
  if (session.state === OccupancySessionState.conflicted) {
    return makeTransition(OccupancySessionState.conflicted, false, "Session is already conflicted");
  }
  if (
    session.state === OccupancySessionState.successionAllowed ||
    session.state === OccupancySessionState.successionDenied
  ) {
    return makeTransition(
      session.state,
      false,
      `Terminal state ${session.state} cannot transition to conflicted`,
    );
  }
  return makeTransition(OccupancySessionState.conflicted, true);
}

// ---------------------------------------------------------------------------
// E. Temporal Eligibility
// ---------------------------------------------------------------------------

export enum SelfRegularizationEligibilityResult {
  notEligible = "notEligible",
  temporallyEligible = "temporallyEligible",
  indeterminate = "indeterminate",
}

const ELIGIBILITY_GRACE_MS = 60 * 60 * 1000; // 60 minutes

/**
 * Evaluates temporal eligibility for self-regularization.
 *
 * Threshold: officialShiftEnd + 60 minutes (inclusive).
 * - now < threshold => notEligible
 * - now >= threshold => temporallyEligible
 * - officialShiftEnd null => indeterminate
 */
export function evaluateSelfRegularizationEligibility(params: {
  now: Date;
  officialShiftEnd: Date | null;
}): SelfRegularizationEligibilityResult {
  if (params.officialShiftEnd == null) {
    return SelfRegularizationEligibilityResult.indeterminate;
  }
  const thresholdMs = params.officialShiftEnd.getTime() + ELIGIBILITY_GRACE_MS;
  if (params.now.getTime() < thresholdMs) {
    return SelfRegularizationEligibilityResult.notEligible;
  }
  return SelfRegularizationEligibilityResult.temporallyEligible;
}