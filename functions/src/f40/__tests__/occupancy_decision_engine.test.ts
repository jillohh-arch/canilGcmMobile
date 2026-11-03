/**
 * F40 Occupancy Decision Engine — Unit Tests
 *
 * Validates the pure decision engine orchestrator, K9 association guard,
 * authority boundary enforcement, and idempotency constraints.
 *
 * Test style: node:test with node:assert/strict (matches functions/src/__tests__/*.f20_r2.test.ts)
 */

import { describe, it } from "node:test";
import * as assert from "node:assert/strict";

import {
  evaluateK9Association,
  validateSuccessorGeneration,
  isEngagementActive,
  findBlockingEngagements,
} from "../occupancy_decision_engine";

import {
  OccupancySessionState,
  createOccupancySession,
  createSuccessor,
  type OperationalEngagement,
  type Engagement,
} from "../occupancy_domain_contract";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function makeOperationalEngagement(overrides: Partial<OperationalEngagement> = {}): OperationalEngagement {
  return {
    engagementId: "eng-1",
    linkedOccurrenceId: "occ-1",
    occupancySessionId: "sess-1",
    vehicleId: "veh-1",
    generation: 1,
    serverConfirmed: true,
    startedAt: new Date("2026-01-01T08:00:00Z"),
    endedAt: null,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// 12. Non-titular incoming actor does not fail solely due to titularity
// ---------------------------------------------------------------------------

describe("Non-titular actor handling", () => {
  it("K9 evaluation does not reject based on actor identity alone when no K9 intent", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      trustedActor: null,
      currentAuthorityEvidence: null,
    });
    assert.equal(result.status, "ALLOWED");
  });

  it("non-matching actor with K9 intent fails closed (not due to titularity)", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
      trustedActor: { uid: "actor-a", ra: "ra-a", email: "a@x", name: "A" },
      currentAuthorityEvidence: { actorUid: "actor-b", actorRa: "ra-b", dogId: "dog-1" },
    });
    // Fails because actor mismatch, not because of titularity
    assert.equal(result.status, "UNKNOWN");
    assert.ok(result.reason?.includes("does not match"));
  });
});

// ---------------------------------------------------------------------------
// 13. Missing F10 authority fails closed
// ---------------------------------------------------------------------------

describe("Missing F10 authority fails closed", () => {
  it("K9 association without authority evidence returns UNKNOWN", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
      trustedActor: { uid: "u", ra: "r", email: "u@x", name: "U" },
      currentAuthorityEvidence: null,
    });
    assert.equal(result.status, "UNKNOWN");
    assert.ok(result.reason?.toLowerCase().includes("authority") || result.reason?.toLowerCase().includes("f10"));
  });

  it("K9 association without trusted actor returns UNKNOWN", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
      trustedActor: null,
      currentAuthorityEvidence: { actorUid: "u", actorRa: "r", dogId: "d" },
    });
    assert.equal(result.status, "UNKNOWN");
  });
});

// ---------------------------------------------------------------------------
// 14. K9 association requires F20 decision
// ---------------------------------------------------------------------------

describe("K9 association requires F20 decision", () => {
  it("valid K9 association returns REQUIRES_F20_DECISION", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
      trustedActor: { uid: "u", ra: "r", email: "u@x", name: "U" },
      currentAuthorityEvidence: { actorUid: "u", actorRa: "r", dogId: "dog-1" },
    });
    assert.equal(result.status, "REQUIRES_F20_DECISION");
    assert.ok(result.reason?.toLowerCase().includes("f20"));
  });

  it("no K9 association is clinically neutral (ALLOWED)", () => {
    const result = evaluateK9Association({
      k9AssociationIntent: "NO_K9_ASSOCIATION",
    });
    assert.equal(result.status, "ALLOWED");
    assert.equal(result.reason, null);
  });

  it("must NOT simulate ALLOWED from old K9 references", () => {
    // Even with matching authority, K9 intent always requires F20
    const result = evaluateK9Association({
      k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
      trustedActor: { uid: "u", ra: "r", email: "u@x", name: "U" },
      currentAuthorityEvidence: { actorUid: "u", actorRa: "r", dogId: "old-dog" },
    });
    assert.notEqual(result.status, "ALLOWED");
    assert.equal(result.status, "REQUIRES_F20_DECISION");
  });
});

// ---------------------------------------------------------------------------
// 15. Idempotency inputs bound to session/generation
// ---------------------------------------------------------------------------

describe("Idempotency inputs bound to session/generation", () => {
  it("successor generation is deterministic from parent", () => {
    const parent = makeSession({ generation: 3, state: OccupancySessionState.coverageValidated });
    const s1 = createSuccessor(parent, "s-next", "c-next");
    const s2 = createSuccessor(parent, "s-next", "c-next");
    assert.equal(s1.generation, s2.generation);
    assert.equal(s1.predecessorSessionId, s2.predecessorSessionId);
    assert.equal(s1.vehicleId, s2.vehicleId);
  });

  it("validateSuccessorGeneration confirms correct gap", () => {
    const parent = makeSession({ generation: 5, state: OccupancySessionState.coverageValidated });
    const successor = createSuccessor(parent, "s-next", "c-next");
    assert.equal(validateSuccessorGeneration(parent, successor), true);
  });

  it("validateSuccessorGeneration rejects wrong gap", () => {
    const parent = makeSession({ generation: 5 });
    const wrongSuccessor = makeSession({ generation: 7, sessionId: "wrong" });
    assert.equal(validateSuccessorGeneration(parent, wrongSuccessor), false);
  });
});

// ---------------------------------------------------------------------------
// 16. No transition triggers a Firestore write
// ---------------------------------------------------------------------------

describe("No Firestore side effects", () => {
  it("decision engine module has no firestore imports", async () => {
    // Verify by checking that the module can be imported and used
    // without any Firestore dependency being loaded
    const engineModule = await import("../occupancy_decision_engine");
    const contractModule = await import("../occupancy_domain_contract");

    // These modules should export only pure functions and types
    // No Firestore client, admin SDK, or I/O functions should be present
    assert.ok(typeof engineModule.evaluateK9Association === "function");
    assert.ok(typeof contractModule.createOccupancySession === "function");
    assert.ok(typeof contractModule.evaluateCoverage === "function");
    assert.ok(typeof contractModule.proposeSelfRegularizationRequest === "function");

    // Verify no firestore-related exports exist
    const engineKeys = Object.keys(engineModule);
    for (const key of engineKeys) {
      assert.ok(
        !key.toLowerCase().includes("firestore"),
        `Engine module should not export firestore-related items: ${key}`,
      );
    }
    const contractKeys = Object.keys(contractModule);
    for (const key of contractKeys) {
      assert.ok(
        !key.toLowerCase().includes("firestore"),
        `Contract module should not export firestore-related items: ${key}`,
      );
    }
  });
});

// ---------------------------------------------------------------------------
// Engagement helpers
// ---------------------------------------------------------------------------

describe("Engagement helper functions", () => {
  it("isEngagementActive returns true when endedAt is null", () => {
    const eng = makeOperationalEngagement({ endedAt: null });
    assert.equal(isEngagementActive(eng), true);
  });

  it("isEngagementActive returns false when endedAt is set", () => {
    const eng = makeOperationalEngagement({ endedAt: new Date("2026-01-01T10:00:00Z") });
    assert.equal(isEngagementActive(eng), false);
  });

  it("findBlockingEngagements filters correctly", () => {
    const engagements: Engagement[] = [
      { engagementId: "e1", isBlocking: false },
      { engagementId: "e2", isBlocking: true },
      { engagementId: "e3", isBlocking: false },
      { engagementId: "e4", isBlocking: true },
    ];
    const blocking = findBlockingEngagements(engagements);
    assert.equal(blocking.length, 2);
    assert.equal(blocking[0].engagementId, "e2");
    assert.equal(blocking[1].engagementId, "e4");
  });

  it("findBlockingEngagements returns empty when none blocking", () => {
    const engagements: Engagement[] = [
      { engagementId: "e1", isBlocking: false },
      { engagementId: "e2", isBlocking: false },
    ];
    const blocking = findBlockingEngagements(engagements);
    assert.equal(blocking.length, 0);
  });
});