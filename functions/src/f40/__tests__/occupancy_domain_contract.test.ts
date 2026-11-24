/**
 * F40 Occupancy Domain Contract — Unit Tests
 *
 * Validates pure domain logic for occupancy sessions, coverage evaluation,
 * evidence classification, state machine transitions, and temporal eligibility.
 *
 * Test style: node:test with node:assert/strict (matches functions/src/__tests__/*.f20_r2.test.ts)
 */

import { describe, it } from "node:test";
import * as assert from "node:assert/strict";

import {
  OccupancySessionState,
  createOccupancySession,
  createSuccessor,
  copyWithState,
  CoverageVerdict,
  evaluateCoverage,
  EvidenceClassification,
  classifyEvidence,
  proposeSelfRegularizationRequest,
  proposeCoverageEvaluation,
  proposeSuccessionPermission,
  proposeSuccessionDenial,
  proposeStale,
  proposeConflict,
  SelfRegularizationEligibilityResult,
  evaluateSelfRegularizationEligibility,
  type Engagement,
  type CoverageEvidence,
} from "../occupancy_domain_contract";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeEngagement(overrides: Partial<Engagement> = {}): Engagement {
  return {
    engagementId: "eng-1",
    isBlocking: true,
    ...overrides,
  };
}

function makeEvidence(overrides: Partial<CoverageEvidence> = {}): CoverageEvidence {
  return {
    classification: EvidenceClassification.authoritativeCurrent,
    matchesSessionAndGeneration: true,
    isAuthoritativeAndSufficient: true,
    ...overrides,
  };
}

function makeSession(overrides: Partial<{ sessionId: string; vehicleId: string; crewId: string; generation: number; predecessorSessionId: string | null; state: OccupancySessionState }> = {}) {
  return createOccupancySession({
    sessionId: overrides.sessionId ?? "sess-1",
    vehicleId: overrides.vehicleId ?? "veh-1",
    crewId: overrides.crewId ?? "crew-1",
    generation: overrides.generation ?? 1,
    predecessorSessionId: overrides.predecessorSessionId ?? null,
    state: overrides.state ?? OccupancySessionState.active,
  });
}

// ---------------------------------------------------------------------------
// 1. Session and generation validation
// ---------------------------------------------------------------------------

describe("Session and generation validation", () => {
  it("creates a valid session with generation > 0", () => {
    const session = makeSession({ generation: 1 });
    assert.equal(session.generation, 1);
    assert.equal(session.state, OccupancySessionState.active);
    assert.equal(session.predecessorSessionId, null);
  });

  it("rejects generation <= 0", () => {
    assert.throws(
      () => makeSession({ generation: 0 }),
      /generation/i,
    );
  });

  it("rejects negative generation", () => {
    assert.throws(
      () => makeSession({ generation: -1 }),
      /generation/i,
    );
  });

  it("rejects empty sessionId", () => {
    assert.throws(
      () => createOccupancySession({ sessionId: "", vehicleId: "v", crewId: "c", generation: 1, state: OccupancySessionState.active }),
      /sessionId/i,
    );
  });

  it("rejects empty vehicleId", () => {
    assert.throws(
      () => createOccupancySession({ sessionId: "s", vehicleId: "", crewId: "c", generation: 1, state: OccupancySessionState.active }),
      /vehicleId/i,
    );
  });

  it("rejects empty crewId", () => {
    assert.throws(
      () => createOccupancySession({ sessionId: "s", vehicleId: "v", crewId: "", generation: 1, state: OccupancySessionState.active }),
      /crewId/i,
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Invalid or stale generation
// ---------------------------------------------------------------------------

describe("Invalid or stale generation", () => {
  it("stale session cannot create successor", () => {
    const session = makeSession({ state: OccupancySessionState.stale });
    assert.throws(
      () => createSuccessor(session, "sess-2", "crew-2"),
      /stale/i,
    );
  });

  it("terminal successionAllowed cannot create successor", () => {
    const session = makeSession({ state: OccupancySessionState.successionAllowed });
    assert.throws(
      () => createSuccessor(session, "sess-2", "crew-2"),
      /terminal/i,
    );
  });

  it("terminal successionDenied cannot create successor", () => {
    const session = makeSession({ state: OccupancySessionState.successionDenied });
    assert.throws(
      () => createSuccessor(session, "sess-2", "crew-2"),
      /terminal/i,
    );
  });

  it("terminal conflicted cannot create successor", () => {
    const session = makeSession({ state: OccupancySessionState.conflicted });
    assert.throws(
      () => createSuccessor(session, "sess-2", "crew-2"),
      /terminal/i,
    );
  });
});

// ---------------------------------------------------------------------------
// 3. Generation gaps
// ---------------------------------------------------------------------------

describe("Generation gaps", () => {
  it("successor generation is exactly predecessor + 1", () => {
    const parent = makeSession({ generation: 3, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "sess-2", "crew-2");
    assert.equal(successor.generation, 4);
  });

  it("first generation successor is 2", () => {
    const parent = makeSession({ generation: 1, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "sess-2", "crew-2");
    assert.equal(successor.generation, 2);
  });
});

// ---------------------------------------------------------------------------
// 4. Correct predecessor/successor mapping
// ---------------------------------------------------------------------------

describe("Predecessor/successor mapping", () => {
  it("successor references parent sessionId as predecessor", () => {
    const parent = makeSession({ sessionId: "parent-sess", generation: 1, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "child-sess", "crew-2");
    assert.equal(successor.predecessorSessionId, "parent-sess");
  });

  it("successor preserves vehicleId from parent", () => {
    const parent = makeSession({ vehicleId: "veh-42", generation: 1, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "sess-2", "crew-2");
    assert.equal(successor.vehicleId, "veh-42");
  });

  it("successor uses new crewId", () => {
    const parent = makeSession({ crewId: "crew-old", generation: 1, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "sess-2", "crew-new");
    assert.equal(successor.crewId, "crew-new");
  });

  it("copyWithState preserves all fields except state", () => {
    const session = makeSession({ generation: 5, predecessorSessionId: "prev" });
    const updated = copyWithState(session, OccupancySessionState.selfRegularizationRequested);
    assert.equal(updated.generation, 5);
    assert.equal(updated.sessionId, "sess-1");
    assert.equal(updated.predecessorSessionId, "prev");
    assert.equal(updated.state, OccupancySessionState.selfRegularizationRequested);
  });
});

// ---------------------------------------------------------------------------
// 5. Missing or ambiguous coverage
// ---------------------------------------------------------------------------

describe("Missing or ambiguous coverage", () => {
  it("empty evidence returns INDETERMINATE", () => {
    const verdict = evaluateCoverage({ evidence: [], engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });

  it("contradictory evidence returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ classification: EvidenceClassification.contradictory })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });

  it("incomplete evidence returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ classification: EvidenceClassification.incomplete })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });

  it("insufficientProvenance evidence returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ classification: EvidenceClassification.insufficientProvenance })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });

  it("authoritativeCurrent but not matching session returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ matchesSessionAndGeneration: false })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });

  it("authoritativeCurrent but not sufficient returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ isAuthoritativeAndSufficient: false })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });
});

// ---------------------------------------------------------------------------
// 6. Active qualifying engagement blocks
// ---------------------------------------------------------------------------

describe("Active qualifying engagement blocks", () => {
  it("single blocking engagement returns BLOCKING", () => {
    const engagements = [makeEngagement({ isBlocking: true })];
    const verdict = evaluateCoverage({ evidence: [], engagements });
    assert.equal(verdict, CoverageVerdict.BLOCKING);
  });

  it("blocking engagement overrides authoritative evidence", () => {
    const engagements = [makeEngagement({ isBlocking: true })];
    const evidence = [makeEvidence()];
    const verdict = evaluateCoverage({ evidence, engagements });
    assert.equal(verdict, CoverageVerdict.BLOCKING);
  });
});

// ---------------------------------------------------------------------------
// 7. Multiple engagements, one still active blocks
// ---------------------------------------------------------------------------

describe("Multiple engagements with one blocking", () => {
  it("one blocking among many returns BLOCKING", () => {
    const engagements = [
      makeEngagement({ engagementId: "eng-1", isBlocking: false }),
      makeEngagement({ engagementId: "eng-2", isBlocking: true }),
      makeEngagement({ engagementId: "eng-3", isBlocking: false }),
    ];
    const verdict = evaluateCoverage({ evidence: [], engagements });
    assert.equal(verdict, CoverageVerdict.BLOCKING);
  });

  it("no blocking engagements allows evidence evaluation", () => {
    const engagements = [
      makeEngagement({ engagementId: "eng-1", isBlocking: false }),
      makeEngagement({ engagementId: "eng-2", isBlocking: false }),
    ];
    const evidence = [makeEvidence()];
    const verdict = evaluateCoverage({ evidence, engagements });
    assert.equal(verdict, CoverageVerdict.PROVEN_CLEAR);
  });
});

// ---------------------------------------------------------------------------
// 8. Complete authoritative clearance
// ---------------------------------------------------------------------------

describe("Complete authoritative clearance", () => {
  it("returns PROVEN_CLEAR with full authoritative evidence", () => {
    const evidence = [makeEvidence({
      classification: EvidenceClassification.authoritativeCurrent,
      matchesSessionAndGeneration: true,
      isAuthoritativeAndSufficient: true,
    })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.PROVEN_CLEAR);
  });
});

// ---------------------------------------------------------------------------
// 9. Legacy-only evidence remains indeterminate
// ---------------------------------------------------------------------------

describe("Legacy-only evidence remains indeterminate", () => {
  it("legacyDocumentaryOnly evidence returns INDETERMINATE", () => {
    const evidence = [makeEvidence({ classification: EvidenceClassification.legacyDocumentaryOnly })];
    const verdict = evaluateCoverage({ evidence, engagements: [] });
    assert.equal(verdict, CoverageVerdict.INDETERMINATE);
  });
});

// ---------------------------------------------------------------------------
// 10. Offline/delayed event cannot retroactively affect successor
// ---------------------------------------------------------------------------

describe("Offline/delayed event isolation", () => {
  it("successor generation is deterministic regardless of timing", () => {
    const parent = makeSession({ generation: 5, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "sess-next", "crew-next");
    // The generation is purely derived from parent, not from any external timing
    assert.equal(successor.generation, 6);
    assert.equal(successor.predecessorSessionId, "sess-1");
  });
});

// ---------------------------------------------------------------------------
// 11. Eligibility at 59/60/61 minutes
// ---------------------------------------------------------------------------

describe("Temporal eligibility at boundary", () => {
  const shiftEnd = new Date("2026-01-01T16:00:00Z");

  it("notEligible before shift end", () => {
    const now = new Date(shiftEnd.getTime() - 1000);
    const result = evaluateSelfRegularizationEligibility({ now, officialShiftEnd: shiftEnd });
    assert.equal(result, SelfRegularizationEligibilityResult.notEligible);
  });

  it("notEligible at exact shift end", () => {
    const result = evaluateSelfRegularizationEligibility({ now: shiftEnd, officialShiftEnd: shiftEnd });
    assert.equal(result, SelfRegularizationEligibilityResult.notEligible);
  });

  it("notEligible at 59 minutes after shift end", () => {
    const now = new Date(shiftEnd.getTime() + 59 * 60 * 1000);
    const result = evaluateSelfRegularizationEligibility({ now, officialShiftEnd: shiftEnd });
    assert.equal(result, SelfRegularizationEligibilityResult.notEligible);
  });

  it("temporallyEligible at exactly 60 minutes after shift end", () => {
    const now = new Date(shiftEnd.getTime() + 60 * 60 * 1000);
    const result = evaluateSelfRegularizationEligibility({ now, officialShiftEnd: shiftEnd });
    assert.equal(result, SelfRegularizationEligibilityResult.temporallyEligible);
  });

  it("temporallyEligible at 61 minutes after shift end", () => {
    const now = new Date(shiftEnd.getTime() + 61 * 60 * 1000);
    const result = evaluateSelfRegularizationEligibility({ now, officialShiftEnd: shiftEnd });
    assert.equal(result, SelfRegularizationEligibilityResult.temporallyEligible);
  });

  it("indeterminate when officialShiftEnd is null", () => {
    const result = evaluateSelfRegularizationEligibility({ now: new Date(), officialShiftEnd: null });
    assert.equal(result, SelfRegularizationEligibilityResult.indeterminate);
  });
});

// ---------------------------------------------------------------------------
// Evidence classifier priority
// ---------------------------------------------------------------------------

describe("Evidence classifier priority", () => {
  it("contradictory takes highest priority", () => {
    const result = classifyEvidence({
      hasContradictions: true,
      isComplete: false,
      hasVerifiedProvenance: false,
      isLegacyDocumentary: true,
      isCurrent: false,
    });
    assert.equal(result, EvidenceClassification.contradictory);
  });

  it("incomplete takes priority over provenance", () => {
    const result = classifyEvidence({
      hasContradictions: false,
      isComplete: false,
      hasVerifiedProvenance: false,
      isLegacyDocumentary: false,
      isCurrent: true,
    });
    assert.equal(result, EvidenceClassification.incomplete);
  });

  it("insufficientProvenance when not verified", () => {
    const result = classifyEvidence({
      hasContradictions: false,
      isComplete: true,
      hasVerifiedProvenance: false,
      isLegacyDocumentary: false,
      isCurrent: true,
    });
    assert.equal(result, EvidenceClassification.insufficientProvenance);
  });

  it("legacyDocumentaryOnly when legacy", () => {
    const result = classifyEvidence({
      hasContradictions: false,
      isComplete: true,
      hasVerifiedProvenance: true,
      isLegacyDocumentary: true,
      isCurrent: true,
    });
    assert.equal(result, EvidenceClassification.legacyDocumentaryOnly);
  });

  it("insufficientProvenance when not current", () => {
    const result = classifyEvidence({
      hasContradictions: false,
      isComplete: true,
      hasVerifiedProvenance: true,
      isLegacyDocumentary: false,
      isCurrent: false,
    });
    assert.equal(result, EvidenceClassification.insufficientProvenance);
  });

  it("authoritativeCurrent when all conditions met", () => {
    const result = classifyEvidence({
      hasContradictions: false,
      isComplete: true,
      hasVerifiedProvenance: true,
      isLegacyDocumentary: false,
      isCurrent: true,
    });
    assert.equal(result, EvidenceClassification.authoritativeCurrent);
  });
});

// ---------------------------------------------------------------------------
// State machine transitions
// ---------------------------------------------------------------------------

describe("State machine transitions", () => {
  it("self-regularization request accepted from active", () => {
    const t = proposeSelfRegularizationRequest(makeSession({ state: OccupancySessionState.active }));
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.selfRegularizationRequested);
  });

  it("self-regularization request rejected from non-active", () => {
    const t = proposeSelfRegularizationRequest(makeSession({ state: OccupancySessionState.coverageValidated }));
    assert.equal(t.accepted, false);
  });

  it("self-regularization request rejected from stale", () => {
    const t = proposeSelfRegularizationRequest(makeSession({ state: OccupancySessionState.stale }));
    assert.equal(t.accepted, false);
    assert.equal(t.newState, OccupancySessionState.stale);
  });

  it("coverage evaluation with PROVEN_CLEAR advances to coverageValidated", () => {
    const t = proposeCoverageEvaluation(
      makeSession({ state: OccupancySessionState.selfRegularizationRequested }),
      CoverageVerdict.PROVEN_CLEAR,
    );
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.coverageValidated);
  });

  it("coverage evaluation with BLOCKING denies succession", () => {
    const t = proposeCoverageEvaluation(
      makeSession({ state: OccupancySessionState.selfRegularizationRequested }),
      CoverageVerdict.BLOCKING,
    );
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.successionDenied);
  });

  it("coverage evaluation with INDETERMINATE does not advance", () => {
    const t = proposeCoverageEvaluation(
      makeSession({ state: OccupancySessionState.selfRegularizationRequested }),
      CoverageVerdict.INDETERMINATE,
    );
    assert.equal(t.accepted, false);
    assert.equal(t.newState, OccupancySessionState.selfRegularizationRequested);
  });

  it("succession permission accepted from coverageValidated", () => {
    const t = proposeSuccessionPermission(makeSession({ state: OccupancySessionState.coverageValidated }));
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.successionAllowed);
  });

  it("succession permission rejected from active", () => {
    const t = proposeSuccessionPermission(makeSession({ state: OccupancySessionState.active }));
    assert.equal(t.accepted, false);
  });

  it("succession denial accepted from selfRegularizationRequested", () => {
    const t = proposeSuccessionDenial(
      makeSession({ state: OccupancySessionState.selfRegularizationRequested }),
      "test reason",
    );
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.successionDenied);
  });

  it("succession denial accepted from coverageValidated", () => {
    const t = proposeSuccessionDenial(
      makeSession({ state: OccupancySessionState.coverageValidated }),
      "test reason",
    );
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.successionDenied);
  });

  it("proposeStale accepted from active", () => {
    const t = proposeStale(makeSession({ state: OccupancySessionState.active }));
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.stale);
  });

  it("proposeStale rejected from already stale", () => {
    const t = proposeStale(makeSession({ state: OccupancySessionState.stale }));
    assert.equal(t.accepted, false);
  });

  it("proposeStale rejected from terminal states", () => {
    const t = proposeStale(makeSession({ state: OccupancySessionState.successionAllowed }));
    assert.equal(t.accepted, false);
  });

  it("proposeConflict accepted from active", () => {
    const t = proposeConflict(makeSession({ state: OccupancySessionState.active }));
    assert.equal(t.accepted, true);
    assert.equal(t.newState, OccupancySessionState.conflicted);
  });

  it("proposeConflict rejected from stale", () => {
    const t = proposeConflict(makeSession({ state: OccupancySessionState.stale }));
    assert.equal(t.accepted, false);
  });

  it("proposeConflict rejected from already conflicted", () => {
    const t = proposeConflict(makeSession({ state: OccupancySessionState.conflicted }));
    assert.equal(t.accepted, false);
  });

  it("proposeConflict rejected from terminal succession states", () => {
    const t = proposeConflict(makeSession({ state: OccupancySessionState.successionAllowed }));
    assert.equal(t.accepted, false);
  });
});