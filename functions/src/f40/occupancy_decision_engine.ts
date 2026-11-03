/**
 * F40 Occupancy Decision Engine — pure, server-oriented TypeScript layer
 * that orchestrates the occupancy domain contract for decision-making.
 *
 * CRITICAL BOUNDARY:
 * - ZERO Firestore / Admin SDK imports.
 * - ZERO I/O or side effects.
 * - All functions are pure; they accept explicit evidence contracts and
 * return deterministic results without writing anywhere.
 * - This module models EXPECTED generation transitions in memory. It does
 * NOT prove atomic persistence or Firestore concurrency safety. Those
 * guarantees belong to the transaction-aware integration layer (future).
 *
 * Parity source: lib/features/shifts/domain/*.dart (Wave 2 R1 reference).
 */

import {
 OccupancySession,
 OccupancySessionState,
 createOccupancySession,
 createSuccessor,
 copyWithState,
 OperationalEngagement,
 Engagement,
 CoverageEvidence,
 CoverageVerdict,
 evaluateCoverage,
 EvidenceClassification,
 classifyEvidence,
 EvidenceInput,
 SuccessionTransition,
 proposeSelfRegularizationRequest,
 proposeCoverageEvaluation,
 proposeSuccessionPermission,
 proposeSuccessionDenial,
 proposeStale,
 proposeConflict,
 SelfRegularizationEligibilityResult,
 evaluateSelfRegularizationEligibility,
} from "./occupancy_domain_contract";

// ---------------------------------------------------------------------------
// K9 Association Guard
// ---------------------------------------------------------------------------

export interface K9AssociationDecision {
 readonly status: "ALLOWED" | "REQUIRES_F20_DECISION" | "UNKNOWN";
 readonly reason: string | null;
}

/**
 * Evaluates K9 association intent against a proposed operation.
 *
 * Rules:
 * - No-K9 occupancy => clinically neutral (ALLOWED)
 * - If a proposed operation introduces a NEW K9 association => requires
 * FRESH F20 guard decision (REQUIRES_F20_DECISION)
 * - Must NOT simulate ALLOWED from old K9 references
 * - Do NOT import or call the F20 guard
 */
export function evaluateK9Association(params: {
 k9AssociationIntent: "NO_K9_ASSOCIATION" | "K9_ASSOCIATION_REQUESTED";
 currentAuthorityEvidence?: {
 actorUid: string;
 actorRa: string;
 dogId: string;
 } | null;
 trustedActor?: {
 uid: string;
 ra: string;
 email: string;
 name: string;
 } | null;
}): K9AssociationDecision {
 if (params.k9AssociationIntent === "NO_K9_ASSOCIATION") {
 return { status: "ALLOWED", reason: null };
 }

 // K9 association requested — must have current authority evidence
 if (params.currentAuthorityEvidence == null) {
 return {
 status: "UNKNOWN",
 reason: "Missing F10 authority evidence for K9 association; fails closed",
 };
 }

 // Verify the trusted actor matches the authority evidence
 if (params.trustedActor == null) {
 return {
 status: "UNKNOWN",
 reason: "No trusted actor provided for K9 association verification",
 };
 }

 const evidence = params.currentAuthorityEvidence;
 if (
 evidence.actorUid !== params.trustedActor.uid ||
 evidence.actorRa !== params.trustedActor.ra
 ) {
 return {
 status: "UNKNOWN",
 reason: "Trusted actor does not match authority evidence for K9 association",
 };
 }

 // Authority verified — but K9 association still requires F20 decision
 return {
 status: "REQUIRES_F20_DECISION",
 reason: "K9 association requires fresh F20 guard decision",
 };
}

// ---------------------------------------------------------------------------
// Occupancy Decision Engine — Orchestrator
// ---------------------------------------------------------------------------

export interface OccupancyDecisionContext {
 readonly session: OccupancySession;
 readonly engagements: readonly Engagement[];
 readonly evidence: readonly CoverageEvidence[];
 readonly now: Date;
 readonly officialShiftEnd: Date | null;
}

export interface OccupancyDecisionResult {
 readonly transition: SuccessionTransition | null;
 readonly coverageVerdict: CoverageVerdict | null;
 readonly eligibility: SelfRegularizationEligibilityResult | null;
 readonly k9Decision: K9AssociationDecision | null;
 readonly successorSession: OccupancySession | null;
 readonly notes: readonly string[];
}

/**
 * Pure decision engine that evaluates an occupancy session state machine
 * progression based on explicit evidence contracts.
 *
 * Does NOT write to Firestore or any external system. Returns only the
 * proposed transitions and decisions.
 */
export function evaluateOccupancyDecision(
 context: OccupancyDecisionContext,
): OccupancyDecisionResult {
 const notes: string[] = [];
 let transition: SuccessionTransition | null = null;
 let coverageVerdict: CoverageVerdict | null = null;
 let eligibility: SelfRegularizationEligibilityResult | null = null;
 let k9Decision: K9AssociationDecision | null = null;
 let successorSession: OccupancySession | null = null;

 // Evaluate temporal eligibility
 eligibility = evaluateSelfRegularizationEligibility({
 now: context.now,
 officialShiftEnd: context.officialShiftEnd,
 });

 // Evaluate coverage
 coverageVerdict = evaluateCoverage({
 evidence: context.evidence,
 engagements: context.engagements,
 });

 // State machine transitions based on current state
 switch (context.session.state) {
 case OccupancySessionState.active: {
 // Can request self-regularization
 transition = proposeSelfRegularizationRequest(context.session);
 break;
 }
 case OccupancySessionState.selfRegularizationRequested: {
 // Evaluate coverage verdict
 transition = proposeCoverageEvaluation(context.session, coverageVerdict);
 break;
 }
 case OccupancySessionState.coverageValidated: {
 // Can be granted succession permission
 transition = proposeSuccessionPermission(context.session);
 break;
 }
 case OccupancySessionState.successionAllowed:
 case OccupancySessionState.successionDenied:
 case OccupancySessionState.conflicted:
 case OccupancySessionState.stale: {
 // Terminal or stale states — no further transitions
 notes.push(`Session is in terminal/stale state: ${context.session.state}`);
 break;
 }
 }

 // Build successor if succession is allowed and coverage is proven clear
 if (
 transition?.accepted &&
 transition.newState === OccupancySessionState.successionAllowed &&
 coverageVerdict === CoverageVerdict.PROVEN_CLEAR
 ) {
 try {
 successorSession = createSuccessor(
 context.session,
 `${context.session.sessionId}-successor`,
 context.session.crewId, // same crew for now
 );
 notes.push("Successor session created");
 } catch (e) {
 notes.push(`Failed to create successor: ${e instanceof Error ? e.message : String(e)}`);
 }
 }

 return Object.freeze({
 transition,
 coverageVerdict,
 eligibility,
 k9Decision,
 successorSession,
 notes: Object.freeze(notes),
 });
}

/**
 * Validates that a proposed successor session has the correct generation
 * gap (exactly +1) relative to its predecessor.
 */
export function validateSuccessorGeneration(
 predecessor: OccupancySession,
 successor: OccupancySession,
): boolean {
 return successor.generation === predecessor.generation + 1;
}

/**
 * Checks if an engagement is currently active (not ended).
 */
export function isEngagementActive(engagement: OperationalEngagement): boolean {
 return engagement.endedAt == null;
}

/**
 * Filters engagements to find blocking ones.
 */
export function findBlockingEngagements(
 engagements: readonly Engagement[],
): readonly Engagement[] {
 return engagements.filter((e) => e.isBlocking);
}