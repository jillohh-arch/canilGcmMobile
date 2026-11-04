/**
 * F40 Operational Occupancy Persistence and Succession — Isolated Firestore Emulator Test Suite.
 *
 * Exercises the complete backend runtime against the local Firestore Emulator
 * under isolated demo project `demo-k9-ops-occupancy-m1`:
 *
 * Test Matrix:
 * 1. Canonical Sessions: Valid succession advancing N to N+1 atomically.
 * 2. Stale Generations: Rejection of outdated generation inputs.
 * 3. Racing Incoming Crews: Concurrency OCC serialization.
 * 4. Racing Engagements & Reconciliations: Active engagement blocks succession; supervisor reconciliation unblocks.
 * 5. Unproven Legacy Registries: Zero positive clearance yields INDETERMINATE (fail-closed).
 * 6. Membership Forgery: Unauthorized actor rejected from incoming crew.
 * 7. Schedule Thresholds: Exact boundaries at +59m (denied), +60m (accepted), and +61m (accepted).
 * 8. K9 Restrictions: Absolute restriction blocks; partial requires ack; no-K9 exempt.
 * 9. Replay Attacks: Idempotent replay vs tampered-payload replay conflict.
 * 10. Closed Feature Flag: VEHICLE_OCCUPANCY_SUCCESSION_ENABLED = false blocks callable.
 */

import * as assert from "assert";
import * as admin from "firebase-admin";
import {
  runSelfRegularizePriorOccupancy,
  SelfRegularizePriorOccupancyRequest,
} from "../occupancy_succession_orchestrator";
import {
  runStartOperationalEngagement,
  runExceptionallyReconcileOperationalEngagement,
  OccupancyOperationError,
} from "../operational_engagement_engine";
import {
  runVehicleOccupancySelfRegularize,
} from "../vehicle_occupancy_callables";
import {
  VehicleOccupancyPointerDoc,
  VehicleOccupancySessionDoc,
} from "../occupancy_persistence_contracts";

const DEMO_PROJECT_ID = "demo-k9-ops-occupancy-m1";

// Ensure emulator host is set for local testing
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}
process.env.GCLOUD_PROJECT = DEMO_PROJECT_ID;

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: DEMO_PROJECT_ID,
  });
}

const db = admin.firestore();

// -----------------------------------------------------------------------------
// Seeding Helpers
// -----------------------------------------------------------------------------

async function seedActor(params: {
  readonly uid: string;
  readonly ra: string;
  readonly profileId?: string;
  readonly hasSelfReg?: boolean;
  readonly hasReconcile?: boolean;
  readonly designation?: "supervisor" | "operational_inspector";
}): Promise<void> {
  const profileId = params.profileId ?? `profile_${params.ra}`;
  await db.collection("identity_bindings").doc(params.uid).set({
    uid: params.uid,
    ra: params.ra,
    active: true,
    confirmed: true,
    revision: 1,
  });

  await db.collection("users").doc(params.ra).set({
    uid: params.uid,
    ra: params.ra,
    status: "active",
    active: true,
    access_profile_id: profileId,
    designation: params.designation ?? null,
  });

  await db.collection("access_profiles").doc(profileId).set({
    status: "active",
    grant_revision: 1,
    authority_revision: 1,
    permissions: {
      vehicles: {
        self_regularize_prior_occupancy: params.hasSelfReg ?? true,
        exceptionally_reconcile_operational_engagement: params.hasReconcile ?? false,
      },
    },
  });
}

async function seedSchedule(params: {
  readonly snapshotId: string;
  readonly endIso: string;
  readonly supersededBy?: string | null;
  readonly crewId?: string;
}): Promise<void> {
  await db.collection("crew_schedule_snapshots").doc(params.snapshotId).set({
    scheduleId: "sched-canon",
    crewId: params.crewId ?? "crew-canon",
    revision: 1,
    timezone: "America/Sao_Paulo",
    serviceDate: "2026-11-04",
    start: "2026-11-03T12:00:00.000Z",
    end: params.endIso,
    superseded_by: params.supersededBy ?? null,
    source: "crew_assignment",
    createdAt: new Date().toISOString(),
  });
}

async function seedVehicleAndPointer(params: {
  readonly vehicleId: string;
  readonly currentSessionId: string;
  readonly currentGeneration: number;
  readonly currentCrewId: string;
  readonly titularHandlerRa: string;
  readonly serviceDogId?: string | null;
  readonly status?: "active" | "conflicted" | "locked";
}): Promise<void> {
  await db.collection("vehicles").doc(params.vehicleId).set({
    id: params.vehicleId,
    active: true,
  });

  const pointer: VehicleOccupancyPointerDoc = {
    vehicleId: params.vehicleId,
    currentSessionId: params.currentSessionId,
    currentGeneration: params.currentGeneration,
    currentCrewId: params.currentCrewId,
    titularHandlerRa: params.titularHandlerRa,
    serviceDogId: params.serviceDogId ?? null,
    status: params.status ?? "active",
    lastTransitionAt: new Date(),
    lastTransitionByRa: params.titularHandlerRa,
    lastTransitionOperationId: "init-op",
    schemaVersion: 1,
    updatedAt: new Date(),
  };

  await db.collection("vehicle_occupancy").doc(params.vehicleId).set(pointer);
}

async function seedSession(params: {
  readonly sessionId: string;
  readonly vehicleId: string;
  readonly crewId: string;
  readonly generation: number;
  readonly predecessorSessionId?: string | null;
  readonly state?: "active" | "successionAllowed" | "stale";
  readonly clearanceAction?: string | null;
  readonly admissionProtocol?: "CANONICAL_V1" | "LEGACY_UNPROVEN" | null;
}): Promise<void> {
  const auditTrail = [
    {
      action: "SESSION_INITIALIZED",
      fromState: "none",
      toState: "active",
      performedAt: new Date(),
      performedByRa: "INITIALIZER",
      reason: "Initial seed",
    },
  ];

  if (params.clearanceAction) {
    auditTrail.push({
      action: params.clearanceAction,
      fromState: "active",
      toState: "active",
      performedAt: new Date(),
      performedByRa: "BASE_OPERATOR",
      reason: "Patrulha concluída e viatura retornada à base.",
    });
  }

  const sessionDoc: VehicleOccupancySessionDoc = {
    sessionId: params.sessionId,
    vehicleId: params.vehicleId,
    crewId: params.crewId,
    generation: params.generation,
    predecessorSessionId: params.predecessorSessionId ?? null,
    successorSessionId: null,
    state: params.state ?? "active",
    admissionProtocol: params.admissionProtocol !== undefined ? params.admissionProtocol : (params.clearanceAction ? "CANONICAL_V1" : "LEGACY_UNPROVEN"),
    serviceDogId: null,
    f20GuardReceiptId: null,
    f10ScheduleSnapshotId: "snap-canon",
    inspectionEvidence: {
      acknowledged: true,
      physicalKeysInHand: true,
      recordedAt: new Date(),
      recordedByRa: "INITIALIZER",
      checklistRef: "chk-0",
      notes: "Seed session",
      vehicleOdometerKm: 10000,
    },
    possessionAcknowledgment: {
      acknowledged: true,
      physicalKeysInHand: true,
      recordedAt: new Date(),
      actorRa: "INITIALIZER",
    },
    startedAt: new Date(),
    startedByRa: "INITIALIZER",
    endedAt: null,
    endedByRa: null,
    auditTrail,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  await db.collection("vehicle_occupancy_sessions").doc(params.sessionId).set(sessionDoc);
}

async function seedCrew(params: {
  readonly crewId: string;
  readonly titularHandlerRa: string;
  readonly members: readonly string[];
}): Promise<void> {
  await db.collection("vehicle_crews").doc(params.crewId).set({
    id: params.crewId,
    titular_handler_id: params.titularHandlerRa,
    active: true,
    updated_at: new Date(),
  });

  for (const memberRa of params.members) {
    await db.collection("vehicle_crews").doc(params.crewId).collection("members").doc(memberRa).set({
      ra: memberRa,
      status: "active",
      active: true,
      confirmed: true,
    });
  }
}

async function seedDog(dogId: string, restrictions: readonly { id: string; level: "absolute" | "partial" | "attention" }[] = []): Promise<void> {
  await db.collection("dogs").doc(dogId).set({
    id: dogId,
    name: dogId,
    status: "active",
  });

  for (const r of restrictions) {
    await db.collection("dogs").doc(dogId).collection("operational_restrictions").doc(r.id).set({
      id: r.id,
      level: r.level,
      category: "clinical",
      status: "active",
      active: true,
      description: `Restrição ${r.level}`,
      activities_restricted: r.level === "partial" ? ["patrol"] : [],
      since: new Date().toISOString(),
      issued_at: new Date().toISOString(),
      created_at: new Date().toISOString(),
    });
  }
}

// -----------------------------------------------------------------------------
// Test Runner
// -----------------------------------------------------------------------------

async function runTest(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`[PASS] ${name}`);
  } catch (err) {
    console.error(`[FAIL] ${name}`, err);
    throw err;
  }
}

async function main(): Promise<void> {
  console.log("Starting F40 Runtime Integration Emulator Test Suite...");
  console.log(`Project: ${DEMO_PROJECT_ID}, Emulator: ${process.env.FIRESTORE_EMULATOR_HOST}`);

  // Test 1: Canonical Session Succession
  await runTest("1. Canonical Session: advances N to N+1 atomically", async () => {
    const vh = "vh-canon-01";
    const sess1 = "sess-canon-g1";
    const snapId = "snap-canon-1";
    const crew1 = "crew-canon-out";
    const crew2 = "crew-canon-in";
    const actorUid = "uid-actor-01";
    const actorRa = "001001";
    const baseDate = new Date("2026-11-04T10:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 65 * 60 * 1000).toISOString(); // 65m ago

    await seedActor({ uid: actorUid, ra: actorRa, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crew1, titularHandlerRa: "009001", members: ["009001"] });
    await seedCrew({ crewId: crew2, titularHandlerRa: actorRa, members: [actorRa] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: crew1,
      titularHandlerRa: "009001",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: crew1,
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const opId = "op-canon-001";
    const req: SelfRegularizePriorOccupancyRequest = {
      operationId: opId,
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crew2,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: {
        checklistConfirmed: true,
        physicalKeysInHand: true,
        vehicleOdometerKm: 25400,
        notes: "Viatura limpa",
      },
    };

    const res = await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req, { now: baseDate });

    assert.strictEqual(res.status, "SUCCESS");
    assert.strictEqual(res.successorGeneration, 2);
    assert.strictEqual(res.predecessorGeneration, 1);
    assert.strictEqual(res.predecessorSessionId, sess1);

    // Verify Pointer updated
    const pointerSnap = await db.collection("vehicle_occupancy").doc(vh).get();
    const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;
    assert.strictEqual(pointer.currentGeneration, 2);
    assert.strictEqual(pointer.currentCrewId, crew2);
    assert.strictEqual(pointer.currentSessionId, res.successorSessionId);

    // Verify Predecessor Session terminated
    const predSnap = await db.collection("vehicle_occupancy_sessions").doc(sess1).get();
    const pred = predSnap.data() as VehicleOccupancySessionDoc;
    assert.strictEqual(pred.state, "successionAllowed");
    assert.strictEqual(pred.successorSessionId, res.successorSessionId);
    assert.ok(pred.endedAt !== null);

    // Verify Successor Session created
    const succSnap = await db.collection("vehicle_occupancy_sessions").doc(res.successorSessionId).get();
    const succ = succSnap.data() as VehicleOccupancySessionDoc;
    assert.strictEqual(succ.generation, 2);
    assert.strictEqual(succ.predecessorSessionId, sess1);
    assert.strictEqual(succ.state, "active");
  });

  // Test 2: Stale Generation Fencing
  await runTest("2. Stale Generations: Rejection of outdated generation inputs", async () => {
    const vh = "vh-canon-01"; // pointer is now at generation 2
    const actorUid = "uid-actor-01";
    const opId = "op-stale-001";
    const baseDate = new Date("2026-11-04T10:00:00.000Z");

    const req: SelfRegularizePriorOccupancyRequest = {
      operationId: opId,
      vehicleId: vh,
      expectedSessionId: "sess-canon-g1", // outdated
      expectedGeneration: 1,              // outdated (pointer is at 2)
      incomingCrewId: "crew-canon-in",
      f10ScheduleSnapshotId: "snap-canon-1",
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: {
        checklistConfirmed: true,
        physicalKeysInHand: true,
      },
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "idempotency_conflict");
        return true;
      },
    );
  });

  // Test 3: Racing Incoming Crews (OCC Concurrency)
  await runTest("3. Racing Incoming Crews: Concurrency OCC serialization", async () => {
    const vh = "vh-race-01";
    const sess1 = "sess-race-g1";
    const snapId = "snap-race-1";
    const crewOut = "crew-race-out";
    const crewA = "crew-race-a";
    const crewB = "crew-race-b";
    const uidA = "uid-actor-a";
    const raA = "002001";
    const uidB = "uid-actor-b";
    const raB = "002002";
    const baseDate = new Date("2026-11-04T12:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 70 * 60 * 1000).toISOString();

    await seedActor({ uid: uidA, ra: raA, hasSelfReg: true });
    await seedActor({ uid: uidB, ra: raB, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crewOut, titularHandlerRa: "009002", members: ["009002"] });
    await seedCrew({ crewId: crewA, titularHandlerRa: raA, members: [raA] });
    await seedCrew({ crewId: crewB, titularHandlerRa: raB, members: [raB] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: crewOut,
      titularHandlerRa: "009002",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: crewOut,
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const reqA: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-race-a",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewA,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    const reqB: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-race-b",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewB,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    // Race both concurrently
    const results = await Promise.allSettled([
      runSelfRegularizePriorOccupancy(db, { uid: uidA }, reqA, { now: baseDate }),
      runSelfRegularizePriorOccupancy(db, { uid: uidB }, reqB, { now: baseDate }),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");

    assert.strictEqual(fulfilled.length, 1, "Exactly 1 crew must win the race");
    assert.strictEqual(rejected.length, 1, "Exactly 1 crew must lose with conflict");

    // Verify pointer incremented exactly once (to gen 2)
    const pointerSnap = await db.collection("vehicle_occupancy").doc(vh).get();
    const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;
    assert.strictEqual(pointer.currentGeneration, 2);
  });

  // Test 4: Racing Engagements & Reconciliations
  await runTest("4. Racing Engagements & Reconciliations: Active engagement blocks; reconciliation unblocks", async () => {
    const vh = "vh-eng-01";
    const sess1 = "sess-eng-g1";
    const snapId = "snap-eng-1";
    const crewOut = "crew-eng-out";
    const crewIn = "crew-eng-in";
    const uidOut = "uid-actor-out";
    const raOut = "003001";
    const uidIn = "uid-actor-in";
    const raIn = "003002";
    const uidSup = "uid-supervisor";
    const raSup = "003099";
    const baseDate = new Date("2026-11-04T14:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 80 * 60 * 1000).toISOString();

    await seedActor({ uid: uidOut, ra: raOut });
    await seedActor({ uid: uidIn, ra: raIn, hasSelfReg: true });
    await seedActor({
      uid: uidSup,
      ra: raSup,
      hasReconcile: true,
      designation: "supervisor",
    });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crewOut, titularHandlerRa: raOut, members: [raOut] });
    await seedCrew({ crewId: crewIn, titularHandlerRa: raIn, members: [raIn] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: crewOut,
      titularHandlerRa: raOut,
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: crewOut,
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    // Start an operational engagement
    const startRes = await db.runTransaction(async (tx) => {
      return runStartOperationalEngagement(tx, db, {
        uid: uidOut,
        vehicleId: vh,
        expectedSessionId: sess1,
        expectedGeneration: 1,
        operationId: "op-start-eng-1",
        linkedOccurrenceId: "occ-991",
        now: baseDate,
      });
    });
    assert.strictEqual(startRes.status, "STARTED");

    // Succession attempt while engagement is active MUST fail with invalid_state
    const reqIn: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-succ-blocked",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewIn,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: uidIn }, reqIn, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "invalid_state");
        return true;
      },
    );

    // Supervisor exceptionally reconciles the engagement
    const reconcileRes = await db.runTransaction(async (tx) => {
      return runExceptionallyReconcileOperationalEngagement(tx, db, {
        uid: uidSup,
        engagementId: startRes.engagementId,
        vehicleId: vh,
        expectedSessionId: sess1,
        expectedGeneration: 1,
        operationId: "op-rec-eng-1",
        reason: "Ocorrência finalizada via rádio",
        evidenceRef: "CAD-2026-991",
        now: baseDate,
      });
    });
    assert.strictEqual(reconcileRes.status, "RECONCILED");

    // Now succession succeeds!
    const succRes = await runSelfRegularizePriorOccupancy(
      db,
      { uid: uidIn },
      { ...reqIn, operationId: "op-succ-unblocked" },
      { now: baseDate },
    );
    assert.strictEqual(succRes.status, "SUCCESS");
    assert.strictEqual(succRes.successorGeneration, 2);
  });

  // Test 5: Unproven Legacy Registries (Zero clearance yields INDETERMINATE)
  await runTest("5. Unproven Legacy Registries: Zero positive clearance yields INDETERMINATE", async () => {
    const vh = "vh-unproven-01";
    const sess1 = "sess-unproven-g1";
    const snapId = "snap-unproven-1";
    const crewOut = "crew-unproven-out";
    const crewIn = "crew-unproven-in";
    const uidIn = "uid-actor-unproven";
    const raIn = "004001";
    const baseDate = new Date("2026-11-04T16:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 90 * 60 * 1000).toISOString();

    await seedActor({ uid: uidIn, ra: raIn, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crewOut, titularHandlerRa: "009004", members: ["009004"] });
    await seedCrew({ crewId: crewIn, titularHandlerRa: raIn, members: [raIn] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: crewOut,
      titularHandlerRa: "009004",
    });
    // Session with NO positive clearance action in audit trail
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: crewOut,
      generation: 1,
      clearanceAction: null,
    });

    const req: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-unproven-1",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewIn,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: uidIn }, req, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "restrictions_unavailable");
        return true;
      },
    );

    // Conversely: Event-free session admitted under CANONICAL_V1 reaches PROVEN_CLEAR
    // without requiring an artificial clearance action from the outgoing crew (Condition A)
    const vhCanon = "vh-canon-eventfree";
    const sessCanon = "sess-canon-ef-g1";
    await seedVehicleAndPointer({
      vehicleId: vhCanon,
      currentSessionId: sessCanon,
      currentGeneration: 1,
      currentCrewId: crewOut,
      titularHandlerRa: "009004",
    });
    await seedSession({
      sessionId: sessCanon,
      vehicleId: vhCanon,
      crewId: crewOut,
      generation: 1,
      clearanceAction: null,
      admissionProtocol: "CANONICAL_V1",
    });

    const resCanonEf = await runSelfRegularizePriorOccupancy(
      db,
      { uid: uidIn },
      {
        ...req,
        operationId: "op-canon-ef-1",
        vehicleId: vhCanon,
        expectedSessionId: sessCanon,
      },
      { now: baseDate },
    );
    assert.strictEqual(resCanonEf.status, "SUCCESS");
    assert.strictEqual(resCanonEf.successorGeneration, 2);
  });

  // Test 6: Membership Forgery
  await runTest("6. Membership Forgery: Unauthorized actor rejected from incoming crew", async () => {
    const vh = "vh-forgery-01";
    const sess1 = "sess-forgery-g1";
    const snapId = "snap-forgery-1";
    const crewIn = "crew-forgery-in";
    const rogueUid = "uid-rogue-01";
    const rogueRa = "005099";
    const baseDate = new Date("2026-11-04T18:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 80 * 60 * 1000).toISOString();

    await seedActor({ uid: rogueUid, ra: rogueRa, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    // Rogue is NOT a member of crewIn
    await seedCrew({ crewId: crewIn, titularHandlerRa: "005001", members: ["005001"] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: "crew-out",
      titularHandlerRa: "009005",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: "crew-out",
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const req: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-forgery-1",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewIn,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: rogueUid }, req, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "permission_denied");
        return true;
      },
    );
  });

  // Test 7: Schedule Threshold Boundaries (+59m, +60m, +61m)
  await runTest("7. Schedule Thresholds: +59m rejected, +60m accepted, +61m accepted", async () => {
    const vh = "vh-thresh-01";
    const sess1 = "sess-thresh-g1";
    const crewIn = "crew-thresh-in";
    const actorUid = "uid-actor-thresh";
    const actorRa = "006001";
    const scheduleEndInstant = new Date("2026-11-04T12:00:00.000Z");

    await seedActor({ uid: actorUid, ra: actorRa, hasSelfReg: true });
    await seedCrew({ crewId: crewIn, titularHandlerRa: actorRa, members: [actorRa] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: "crew-thresh-out",
      titularHandlerRa: "009006",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: "crew-thresh-out",
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const snapId = "snap-thresh-1";
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEndInstant.toISOString() });

    // Case 7.1: +59m (11h59 from scheduleEnd -> rejected)
    const at59m = new Date(scheduleEndInstant.getTime() + 59 * 60 * 1000);
    const req59: SelfRegularizePriorOccupancyRequest = {
      operationId: "op-thresh-59",
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewIn,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req59, { now: at59m });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "invalid_state");
        return true;
      },
    );

    // Case 7.2: +60m (exactly 60 minutes -> accepted)
    const at60m = new Date(scheduleEndInstant.getTime() + 60 * 60 * 1000);
    const res60 = await runSelfRegularizePriorOccupancy(
      db,
      { uid: actorUid },
      { ...req59, operationId: "op-thresh-60" },
      { now: at60m },
    );
    assert.strictEqual(res60.status, "SUCCESS");
    assert.strictEqual(res60.successorGeneration, 2);

    // Reset pointer for +61m check
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: "sess-thresh-g2",
      currentGeneration: 2,
      currentCrewId: "crew-thresh-out",
      titularHandlerRa: "009006",
    });
    await seedSession({
      sessionId: "sess-thresh-g2",
      vehicleId: vh,
      crewId: "crew-thresh-out",
      generation: 2,
      clearanceAction: "RETURNED_TO_BASE",
    });

    // Case 7.3: +61m (accepted)
    const at61m = new Date(scheduleEndInstant.getTime() + 61 * 60 * 1000);
    const res61 = await runSelfRegularizePriorOccupancy(
      db,
      { uid: actorUid },
      {
        ...req59,
        operationId: "op-thresh-61",
        expectedSessionId: "sess-thresh-g2",
        expectedGeneration: 2,
      },
      { now: at61m },
    );
    assert.strictEqual(res61.status, "SUCCESS");
    assert.strictEqual(res61.successorGeneration, 3);
  });

  // Test 8: K9 Clinical Restrictions
  await runTest("8. K9 Restrictions: absolute restriction blocks; partial requires ack; no-K9 allowed", async () => {
    const vh = "vh-k9-01";
    const sess1 = "sess-k9-g1";
    const snapId = "snap-k9-1";
    const crewIn = "crew-k9-in";
    const actorUid = "uid-actor-k9";
    const actorRa = "007001";
    const baseDate = new Date("2026-11-04T20:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 75 * 60 * 1000).toISOString();

    await seedActor({ uid: actorUid, ra: actorRa, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crewIn, titularHandlerRa: actorRa, members: [actorRa] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: "crew-k9-out",
      titularHandlerRa: "009007",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: "crew-k9-out",
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const dogAbsolute = "dog-abs-01";
    await seedDog(dogAbsolute, [{ id: "res-abs", level: "absolute" }]);

    // Case 8.1: Absolute restriction -> denied
    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(
          db,
          { uid: actorUid },
          {
            operationId: "op-k9-abs",
            vehicleId: vh,
            expectedSessionId: sess1,
            expectedGeneration: 1,
            incomingCrewId: crewIn,
            f10ScheduleSnapshotId: snapId,
            k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
            dogId: dogAbsolute,
            inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
          },
          { now: baseDate },
        );
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.details?.code, "absolute_restriction_active");
        return true;
      },
    );

    // Case 8.2: Partial restriction without acknowledgment -> denied
    const dogPartial = "dog-part-01";
    await seedDog(dogPartial, [{ id: "res-part-1", level: "partial" }]);

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(
          db,
          { uid: actorUid },
          {
            operationId: "op-k9-part-unack",
            vehicleId: vh,
            expectedSessionId: sess1,
            expectedGeneration: 1,
            incomingCrewId: crewIn,
            f10ScheduleSnapshotId: snapId,
            k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
            dogId: dogPartial,
            inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
          },
          { now: baseDate },
        );
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.details?.code, "partial_acknowledgement_required");
        return true;
      },
    );

    // Case 8.3: Partial restriction with acknowledgment -> succeeds
    const resAck = await runSelfRegularizePriorOccupancy(
      db,
      { uid: actorUid },
      {
        operationId: "op-k9-part-ack",
        vehicleId: vh,
        expectedSessionId: sess1,
        expectedGeneration: 1,
        incomingCrewId: crewIn,
        f10ScheduleSnapshotId: snapId,
        k9AssociationIntent: "K9_ASSOCIATION_REQUESTED",
        dogId: dogPartial,
        acknowledgedRestrictionIds: ["res-part-1"],
        inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
      },
      { now: baseDate },
    );
    assert.strictEqual(resAck.status, "SUCCESS");
    assert.strictEqual(resAck.effectiveDogId, dogPartial);
    assert.strictEqual(resAck.f20Outcome, "ALLOWED");
  });

  // Test 9: Replay Attacks & Idempotency
  await runTest("9. Replay Attacks: Idempotent repeat succeeds; tampered-payload replay rejected", async () => {
    const vh = "vh-replay-01";
    const sess1 = "sess-replay-g1";
    const snapId = "snap-replay-1";
    const crewIn = "crew-replay-in";
    const actorUid = "uid-actor-replay";
    const actorRa = "008001";
    const baseDate = new Date("2026-11-04T22:00:00.000Z");
    const scheduleEnd = new Date(baseDate.getTime() - 85 * 60 * 1000).toISOString();

    await seedActor({ uid: actorUid, ra: actorRa, hasSelfReg: true });
    await seedSchedule({ snapshotId: snapId, endIso: scheduleEnd });
    await seedCrew({ crewId: crewIn, titularHandlerRa: actorRa, members: [actorRa] });
    await seedVehicleAndPointer({
      vehicleId: vh,
      currentSessionId: sess1,
      currentGeneration: 1,
      currentCrewId: "crew-replay-out",
      titularHandlerRa: "009008",
    });
    await seedSession({
      sessionId: sess1,
      vehicleId: vh,
      crewId: "crew-replay-out",
      generation: 1,
      clearanceAction: "RETURNED_TO_BASE",
    });

    const opId = "op-replay-unique-01";
    const req: SelfRegularizePriorOccupancyRequest = {
      operationId: opId,
      vehicleId: vh,
      expectedSessionId: sess1,
      expectedGeneration: 1,
      incomingCrewId: crewIn,
      f10ScheduleSnapshotId: snapId,
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    // First commit
    const res1 = await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req, { now: baseDate });
    assert.strictEqual(res1.status, "SUCCESS");

    // Replay 1: Exactly same payload and opId -> returns cached response
    const resReplay = await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req, { now: baseDate });
    assert.strictEqual(resReplay.status, "SUCCESS");
    assert.strictEqual(resReplay.successorGeneration, res1.successorGeneration);
    assert.strictEqual(resReplay.successorSessionId, res1.successorSessionId);

    // Replay 2: Tampered payload with same opId (different vehicleId) -> rejected
    const tamperedReq: SelfRegularizePriorOccupancyRequest = {
      ...req,
      vehicleId: "vh-tampered-02",
    };

    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, tamperedReq, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "idempotency_conflict");
        return true;
      },
    );

    // Replay 3: Cross-actor replay with same opId -> rejected with idempotency_conflict
    const otherUid = "uid-other-replay";
    const otherRa = "008002";
    await seedActor({ uid: otherUid, ra: otherRa, hasSelfReg: true });
    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: otherUid }, req, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "idempotency_conflict");
        return true;
      },
    );

    // Replay 4: Revoked actor attempts replay -> rejected with permission_denied before cached result
    await db.collection("identity_bindings").doc(actorUid).update({ active: false });
    await assert.rejects(
      async () => {
        await runSelfRegularizePriorOccupancy(db, { uid: actorUid }, req, { now: baseDate });
      },
      (err: unknown) => {
        assert.ok(err instanceof OccupancyOperationError);
        assert.strictEqual(err.appCode, "permission_denied");
        return true;
      },
    );
  });

  // Test 10: Closed-by-Default Feature Flag
  await runTest("10. Closed Feature Flag: VEHICLE_OCCUPANCY_SUCCESSION_ENABLED = false blocks callable", async () => {
    const actorUid = "uid-actor-01";
    const mockAuth = {
      uid: actorUid,
      token: { email: "001001@canilgcm.com" },
    };

    const payload = {
      operationId: "op-flag-01",
      vehicleId: "vh-01",
      expectedSessionId: "sess-1",
      expectedGeneration: 1,
      incomingCrewId: "crew-1",
      f10ScheduleSnapshotId: "snap-1",
      k9AssociationIntent: "NO_K9_ASSOCIATION",
      inspectionEvidence: { checklistConfirmed: true, physicalKeysInHand: true },
    };

    // Without bypass -> must fail with feature_disabled
    await assert.rejects(
      async () => {
        await runVehicleOccupancySelfRegularize(payload, mockAuth as any, db);
      },
      (err: any) => {
        assert.strictEqual(err.code, "failed-precondition");
        assert.strictEqual(err.details?.code, "feature_disabled");
        return true;
      },
    );

    // With bypass -> executes feature logic
    // (Will fail on vehicle not found, proving feature flag gate was passed)
    await assert.rejects(
      async () => {
        await runVehicleOccupancySelfRegularize(payload, mockAuth as any, db, {
          bypassFeatureFlag: true,
        });
      },
      (err: any) => {
        // Not feature_disabled, reached vehicle lookup
        assert.notStrictEqual(err.details?.code, "feature_disabled");
        return true;
      },
    );
  });

  console.log("\n========================================================");
  console.log("All 10 F40 Runtime Integration Emulator Tests Passed!");
  console.log("========================================================\n");
}

main().catch((err) => {
  console.error("Integration test suite failed:", err);
  process.exit(1);
});
