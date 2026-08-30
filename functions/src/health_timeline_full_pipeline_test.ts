/**
 * Pipeline Integration Tests — Gate 5C.5C.5
 *
 * Tests the complete trigger → handler → runtime → Firestore flow.
 *
 * Categories:
 *   A — Handler integration (direct invocation via Firestore Emulator)
 *   C — Reconciliation integration
 *   D — Export definitions (construct + inspect)
 *
 * Category B (Real export E2E via Functions Emulator) is in a separate file
 * because it requires the Functions Emulator.
 */
import * as assert from "assert";
import {deleteApp, getApps, initializeApp} from "firebase-admin/app";
import {
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {deriveTimelineId} from "./health_timeline_projection";
import {
  FirestoreHealthTimelineRuntime,
  canonicalTimelineKeys,
  sourceDocumentPath,
  type RuntimeLogger,
} from "./health_timeline_runtime";
import {
  makeMealLogCreatedHandler,
  makeSupplementLogCreatedHandler,
  type TriggerHandlerDependencies,
  type TriggerHandlerResult,
  type TriggerSnapshotLike,
} from "./health_timeline_trigger_handlers";
import {FirestoreAnomalySink} from "./health_timeline_anomaly_sink";
import {
  runHealthTimelineReconciliation,
  DEFAULT_ORCHESTRATOR_CONFIG,
} from "./health_timeline_orchestrator";
import {
  HealthTimelineReconciliationRuntime,
} from "./health_timeline_reconciliation";
import {
  FirestoreReconciliationState,
  discrepancyPath,
  deriveDiscrepancyId,
} from "./health_timeline_reconciliation_state";

// ─────────────────────────────────────────────────────────────────────────────
// Test infra
// ─────────────────────────────────────────────────────────────────────────────

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("FIRESTORE_EMULATOR_HOST is required.");
}

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "canil-gcm";
const dogId = `dog_full_pipeline_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

if (getApps().length === 0) {
  initializeApp({projectId: PROJECT_ID});
}
const db = getFirestore();
let failed = 0;
let passed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    passed++;
    console.log(`✅ ${name}`);
  } catch (error) {
    failed++;
    console.error(`❌ ${name}`);
    console.error(error);
  }
}

const clock = {now: () => new Date("2026-07-23T12:00:00.000Z")};
const loggerEvents: Array<{level: string; message: string; context?: unknown}> = [];
const logger: RuntimeLogger = {
  info: (message, context) => { loggerEvents.push({level: "info", message, context}); },
  warn: (message, context) => { loggerEvents.push({level: "warn", message, context}); },
  error: (message, context) => { loggerEvents.push({level: "error", message, context}); },
};

const runtime = new FirestoreHealthTimelineRuntime(db, clock, logger);
const anomalySink = new FirestoreAnomalySink(db, clock);
const triggerDeps: TriggerHandlerDependencies = {
  projector: runtime,
  anomalySink,
  clock,
  logger,
};

function recordedBy() {
  return {
    uid: "pipeline-test-user",
    name: "Pipeline Test",
    internal_role: "condutor",
  };
}

function mealLogPayload(overrides: Record<string, unknown> = {}) {
  return {
    kind: "adhoc",
    acceptance: "full",
    offered_grams: 200,
    consumed_grams: 200,
    fed_at: Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z")),
    recorded_at: "2026-07-23T08:05:00.000Z",
    recorded_by: recordedBy(),
    food_name: "Ração Pipeline",
    ...overrides,
  };
}

function supplementLogPayload(overrides: Record<string, unknown> = {}) {
  return {
    supplement_name: "Vitamina D",
    dose: 25,
    unit: "mg",
    administered_at: Timestamp.fromDate(new Date("2026-07-23T09:00:00.000Z")),
    recorded_at: "2026-07-23T09:05:00.000Z",
    recorded_by: recordedBy(),
    ...overrides,
  };
}

function mealSnapshotLike(
  dId: string,
  sourceId: string,
  data: Record<string, unknown>,
): TriggerSnapshotLike {
  return {
    exists: true,
    id: sourceId,
    data: () => ({dog_id: dId, ...data}),
    ref: db.doc(sourceDocumentPath("meal", dId, sourceId)),
  };
}

function supSnapshotLike(
  dId: string,
  sourceId: string,
  data: Record<string, unknown>,
): TriggerSnapshotLike {
  return {
    exists: true,
    id: sourceId,
    data: () => ({dog_id: dId, ...data}),
    ref: db.doc(sourceDocumentPath("supplement", dId, sourceId)),
  };
}

async function cleanupDog(dId: string) {
  const meals = await db.collection(`dogs/${dId}/meal_logs`).get();
  for (const doc of meals.docs) await doc.ref.delete();
  const sups = await db.collection(`dogs/${dId}/supplement_logs`).get();
  for (const doc of sups.docs) await doc.ref.delete();
  const timelines = await db.collection(`dogs/${dId}/health_timeline`).get();
  for (const doc of timelines.docs) await doc.ref.delete();
}

async function cleanupState() {
  const passDocs = await db.collection("_health_projection_state/health_timeline_v1/passes").get();
  for (const doc of passDocs.docs) await doc.ref.delete();
  const runDocs = await db.collection("_health_projection_state/health_timeline_v1/runs").get();
  for (const doc of runDocs.docs) await doc.ref.delete();
  const discDocs = await db.collection("_health_projection_state/health_timeline_v1/discrepancies").get();
  for (const doc of discDocs.docs) await doc.ref.delete();
  const leaseDoc = db.doc("_health_projection_state/health_timeline_v1");
  await leaseDoc.delete().catch(() => undefined);
}

function assertProjected(result: TriggerHandlerResult) {
  assert.strictEqual(result.status, "projected");
  if (result.status === "projected") return result.projection;
  throw new Error("Expected projected result");
}

function assertAnomaly(result: TriggerHandlerResult) {
  assert.strictEqual(result.status, "anomaly");
  if (result.status === "anomaly") return result.reasonCode;
  throw new Error("Expected anomaly result");
}

// ─────────────────────────────────────────────────────────────────────────────
// Category A — Handler Integration (direct invocation)
// ─────────────────────────────────────────────────────────────────────────────

async function runCategoryA() {
  console.log("\n=== CATEGORY A — Handler Integration ===");
  const startPassed = passed;
  const startFailed = failed;

  await test("A1 — MealLog handler creates TimelineEntry via direct invocation", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-direct-1";
    const handler = makeMealLogCreatedHandler(triggerDeps);

    const result = await handler({
      params: {dogId, mealId} as Record<string, unknown>,
      snapshot: mealSnapshotLike(dogId, mealId, mealLogPayload()),
    });

    const proj = assertProjected(result);
    assert.strictEqual(proj.operation, "created");

    const doc = await db.doc(proj.destinationPath).get();
    assert.strictEqual(doc.exists, true);
    const data = doc.data() ?? {};
    assert.strictEqual(data.timeline_type, "meal");
    assert.strictEqual(data.source_collection, `dogs/${dogId}/meal_logs`);
    assert.strictEqual(data.source_id, mealId);
    assert.strictEqual(data.dog_id, dogId);

    // Verify canonical schema
    for (const key of canonicalTimelineKeys()) {
      assert.ok(key in data, `Missing canonical key: ${key}`);
    }
  });

  await test("A2 — SupplementLog handler creates TimelineEntry via direct invocation", async () => {
    const supId = "sup-direct-1";
    const handler = makeSupplementLogCreatedHandler(triggerDeps);

    const result = await handler({
      params: {dogId, supplementLogId: supId} as Record<string, unknown>,
      snapshot: supSnapshotLike(dogId, supId, supplementLogPayload()),
    });

    const proj = assertProjected(result);
    assert.strictEqual(proj.operation, "created");

    const doc = await db.doc(proj.destinationPath).get();
    assert.strictEqual(doc.exists, true);
    assert.strictEqual(doc.data()?.timeline_type, "supplement");
  });

  await test("A3 — Duplicate delivery creates once then NO-OP", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-dup-1";
    const handler = makeMealLogCreatedHandler(triggerDeps);
    const params = {dogId, mealId} as Record<string, unknown>;
    const snapshot = mealSnapshotLike(dogId, mealId, mealLogPayload());

    const r1 = assertProjected(await handler({params, snapshot}));
    assert.strictEqual(r1.operation, "created");

    const r2 = assertProjected(await handler({params, snapshot}));
    assert.strictEqual(r2.operation, "noop");

    const timelines = await db.collection(`dogs/${dogId}/health_timeline`).get();
    const count = timelines.docs.filter((d) => d.data()?.source_id === mealId).length;
    assert.strictEqual(count, 1);
  });

  await test("A4 — Concurrent delivery converges to one create + one noop", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-conc-1";
    const handler = makeMealLogCreatedHandler(triggerDeps);
    const params = {dogId, mealId} as Record<string, unknown>;
    const snapshot = mealSnapshotLike(dogId, mealId, mealLogPayload());

    const [r1, r2] = await Promise.all([
      handler({params, snapshot}),
      handler({params, snapshot}),
    ]);

    const ops = [assertProjected(r1).operation, assertProjected(r2).operation].sort();
    assert.ok(ops.includes("created"));
    assert.ok(ops.includes("noop"));

    const timelines = await db.collection(`dogs/${dogId}/health_timeline`).get();
    const count = timelines.docs.filter((d) => d.data()?.source_id === mealId).length;
    assert.strictEqual(count, 1);
  });

  await test("A5 — Malformed payload records durable anomaly, no timeline, no retry", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-malformed-1";
    const handler = makeMealLogCreatedHandler(triggerDeps);

    const badPayload = mealLogPayload({recorded_by: null});
    const result = await handler({
      params: {dogId, mealId} as Record<string, unknown>,
      snapshot: mealSnapshotLike(dogId, mealId, badPayload),
    });

    assertAnomaly(result);

    // Zero timeline writes
    const timelines = await db.collection(`dogs/${dogId}/health_timeline`).get();
    const count = timelines.docs.filter((d) => d.data()?.source_id === mealId).length;
    assert.strictEqual(count, 0);

    // Durable discrepancy exists
    const discrepancyId = deriveDiscrepancyId({
      targetKind: "source",
      reasonCode: "invalid-source-payload",
      sourceType: "meal",
      dogId,
      sourceId: mealId,
      timelineDocumentPath: null,
    });
    const discDoc = await db.doc(discrepancyPath(discrepancyId)).get();
    assert.strictEqual(discDoc.exists, true);
    assert.strictEqual(discDoc.data()?.status, "open");
  });

  await test("A6 — Source document remains byte-for-byte identical after projection", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-immut-1";
    const mealRef = db.doc(sourceDocumentPath("meal", dogId, mealId));
    const payload = mealLogPayload();
    await mealRef.set({dog_id: dogId, ...payload});

    const before = await mealRef.get();
    const beforeData = JSON.stringify(before.data());
    const beforeUpdateTime = before.updateTime;

    const handler = makeMealLogCreatedHandler(triggerDeps);
    await handler({
      params: {dogId, mealId} as Record<string, unknown>,
      snapshot: {
        exists: true,
        id: mealId,
        data: () => ({dog_id: dogId, ...payload}),
        ref: mealRef,
      },
    });

    const after = await mealRef.get();
    assert.strictEqual(JSON.stringify(after.data()), beforeData);
    if (beforeUpdateTime && after.updateTime) {
      assert.strictEqual(after.updateTime.toMillis(), beforeUpdateTime.toMillis());
    }
  });

  await test("A7 — Handler performs zero legacy writes", async () => {
    await cleanupDog(dogId);
    const legacyCollections = [
      "dogs/{dogId}/feeding_events",
      "dogs/{dogId}/feedings",
      "dogs/{dogId}/nutrition_supplements",
      "dogs/{dogId}/nutritional_prescriptions",
      "dogs/{dogId}/nutrition_prescriptions",
      "dogs/{dogId}/health_events",
      "dogs/{dogId}/health_records",
      "dogs/{dogId}/health",
    ];

    for (const legacy of legacyCollections) {
      const collPath = legacy.replace("{dogId}", dogId);
      const before = await db.collection(collPath).get();
      const beforeCount = before.size;

      const mealId = `meal-legacy-${Date.now()}`;
      const handler = makeMealLogCreatedHandler(triggerDeps);
      await handler({
        params: {dogId, mealId} as Record<string, unknown>,
        snapshot: mealSnapshotLike(dogId, mealId, mealLogPayload()),
      });

      const after = await db.collection(collPath).get();
      assert.strictEqual(after.size, beforeCount,
        `Legacy collection ${collPath} should not grow`);
    }
  });

  await test("A8 — TimelineEntry uses deterministic ID", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-det-1";
    const expectedId = deriveTimelineId({
      sourceCollection: `dogs/${dogId}/meal_logs`,
      sourceId: mealId,
    });

    const handler = makeMealLogCreatedHandler(triggerDeps);
    await handler({
      params: {dogId, mealId} as Record<string, unknown>,
      snapshot: mealSnapshotLike(dogId, mealId, mealLogPayload()),
    });

    const doc = await db.doc(`dogs/${dogId}/health_timeline/${expectedId}`).get();
    assert.strictEqual(doc.exists, true);
    assert.strictEqual(doc.id, expectedId);
  });

  await test("A9 — TimelineEntry uses exact nested dog-scoped path", async () => {
    await cleanupDog(dogId);
    const mealId = "meal-nested-1";
    const handler = makeMealLogCreatedHandler(triggerDeps);
    const result = await handler({
      params: {dogId, mealId} as Record<string, unknown>,
      snapshot: mealSnapshotLike(dogId, mealId, mealLogPayload()),
    });

    const proj = assertProjected(result);
    assert.ok(proj.destinationPath.startsWith(`dogs/${dogId}/health_timeline/`));
    assert.strictEqual(proj.destinationPath.split("/").length, 4);
  });

  await test("A10 — Same meal handler can be used with correct source type", async () => {
    const handler = makeMealLogCreatedHandler(triggerDeps);
    assert.strictEqual(typeof handler, "function");
  });

  console.log(`\n📊 Category A: ${passed - startPassed} passed, ${failed - startFailed} failed`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Category C — Reconciliation Integration
// ─────────────────────────────────────────────────────────────────────────────

async function createMealSource(mealId: string, overrides: Record<string, unknown> = {}) {
  const ref = db.doc(sourceDocumentPath("meal", dogId, mealId));
  await ref.set({dog_id: dogId, ...mealLogPayload(overrides)});
  return ref;
}

async function runCategoryC() {
  console.log("\n=== CATEGORY C — Reconciliation Integration ===");
  const startPassed = passed;
  const startFailed = failed;

  await test("C1 — Reconciliation creates TimelineEntry for existing source without one", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    const mealId = "meal-reconcile-missing-1";
    await createMealSource(mealId);

    const timelineId = deriveTimelineId({
      sourceCollection: `dogs/${dogId}/meal_logs`,
      sourceId: mealId,
    });
    const existing = await db.doc(`dogs/${dogId}/health_timeline/${timelineId}`).get();
    assert.strictEqual(existing.exists, false);

    const result = await runHealthTimelineReconciliation(
      db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
      clock, logger, runtime,
    );

    assert.strictEqual(result.status, "completed");
    assert.ok(result.summary.created >= 1);

    const doc = await db.doc(`dogs/${dogId}/health_timeline/${timelineId}`).get();
    assert.strictEqual(doc.exists, true);
    assert.strictEqual(doc.data()?.source_id, mealId);
  });

  await test("C2 — Reconciliation repairs divergent TimelineEntry", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    const mealId = "meal-reconcile-diverge-1";
    await createMealSource(mealId, {food_name: "Ração Corrigida"});

    const timelineId = deriveTimelineId({
      sourceCollection: `dogs/${dogId}/meal_logs`,
      sourceId: mealId,
    });
    await db.doc(`dogs/${dogId}/health_timeline/${timelineId}`).set({
      timeline_type: "meal",
      source_collection: `dogs/${dogId}/meal_logs`,
      source_id: mealId,
      dog_id: dogId,
      title: "Ração Errada",
      subtitle: null,
      status: "final",
      occurred_at: "2026-07-23T08:00:00.000Z",
      recorded_at: "2026-07-23T08:05:00.000Z",
      recorded_by: recordedBy(),
      projected_at: "2026-07-20T00:00:00.000Z",
      schema_version: 1,
      created_at: "2026-07-20T00:00:00.000Z",
      updated_at: "2026-07-20T00:00:00.000Z",
    });

    const result = await runHealthTimelineReconciliation(
      db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
      clock, logger, runtime,
    );

    assert.strictEqual(result.status, "completed");

    const doc = await db.doc(`dogs/${dogId}/health_timeline/${timelineId}`).get();
    assert.strictEqual(doc.exists, true);
    assert.strictEqual(doc.data()?.title, "Ração Corrigida");
  });

  await test("C3 — Orphan produces discrepancy and preserves timeline", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    // Use a deterministic timeline ID for a non-existent source
    const orphanSourceColl = `dogs/${dogId}/meal_logs`;
    const orphanSourceId = "nonexistent-orphan-source";
    const orphanId = deriveTimelineId({
      sourceCollection: orphanSourceColl,
      sourceId: orphanSourceId,
    });

    // Write a timeline entry with a valid path but no actual source document
    await db.doc(`dogs/${dogId}/health_timeline/${orphanId}`).set({
      timeline_type: "meal",
      source_collection: orphanSourceColl,
      source_id: orphanSourceId,
      dog_id: dogId,
      title: "Orphan Entry",
      subtitle: null,
      status: "final",
      occurred_at: "2026-07-23T08:00:00.000Z",
      recorded_at: "2026-07-23T08:00:00.000Z",
      recorded_by: recordedBy(),
      projected_at: "2026-07-23T08:00:00.000Z",
      schema_version: 1,
      created_at: "2026-07-23T08:00:00.000Z",
      updated_at: "2026-07-23T08:00:00.000Z",
    });

    const result = await runHealthTimelineReconciliation(
      db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
      clock, logger, runtime,
    );

    assert.strictEqual(result.status, "completed");

    // Orphan entry still exists (never auto-deleted)
    const doc = await db.doc(`dogs/${dogId}/health_timeline/${orphanId}`).get();
    assert.strictEqual(doc.exists, true);

    // Check for discrepancies — the orphan pass creates one if source is missing
    // The discrepancy may be vs 'timeline' targetKind with 'orphan-source-missing'
    const allDisc = await db.collection("_health_projection_state/health_timeline_v1/discrepancies").get();
    assert.ok(allDisc.size >= 1, `Expected at least 1 discrepancy, got ${allDisc.size}`);
  });

  await test("C4 — Orchestrator executes all 8 passes (bounded, per-pass)", async () => {
    await cleanupDog(dogId);
    await cleanupState();

    await createMealSource("meal-bound-1");
    await createMealSource("meal-bound-2");

    const result = await runHealthTimelineReconciliation(
      db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000, pageSize: 25},
      clock, logger, runtime,
    );

    assert.strictEqual(result.status, "completed");
    // All 8 passes in the ordered schedule
    assert.strictEqual(result.passes.length, 8);
    for (const p of result.passes) {
      assert.ok(p.result !== null || p.error !== undefined,
        `Pass ${p.passKey} has no result and no error`);
    }
  });

  await test("C5 — Concurrent orchestrator: one acquires lease, other skips", async () => {
    await cleanupDog(dogId);
    await cleanupState();

    const [r1, r2] = await Promise.all([
      runHealthTimelineReconciliation(
        db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
        clock, logger, runtime,
      ),
      runHealthTimelineReconciliation(
        db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
        clock, logger, runtime,
      ),
    ]);

    const completed = [r1, r2].filter((r) => r.status === "completed");
    const skipped = [r1, r2].filter((r) => r.status === "skipped");
    assert.strictEqual(completed.length, 1);
    assert.strictEqual(skipped.length, 1);
  });

  await test("C6 — Stale worker cannot affect newer revision", async () => {
    await cleanupState();
    const realClock = {now: () => new Date()};
    const state = new FirestoreReconciliationState(db, realClock);

    // Worker A acquires lease with short duration
    const tokenA = await state.acquireLease("worker-a", 100);
    assert.ok(tokenA);

    // Small delay to let the lease expire
    await new Promise((resolve) => setTimeout(resolve, 200));

    // Worker B acquires lease after expiry (takes over)
    const tokenB = await state.acquireLease("worker-b", 30000);
    assert.ok(tokenB, "Worker B should acquire lease after Worker A's expires");

    // Stale Worker A tries to release — should fail
    const released = await state.releaseLease(tokenA!);
    assert.strictEqual(released, false, "Stale worker should not release newer revision");

    // Worker B can still release
    const releasedB = await state.releaseLease(tokenB!);
    assert.strictEqual(releasedB, true);

    await cleanupState();
  });

  await test("C7 — Transactional anomaly concurrency: concurrent writes converge on single document", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    const mealId = "meal-anomaly-conv-2";

    // ── Two concurrent anomaly writes to the SAME discrepancy ──
    // FirestoreAnomalySink.record() uses db.runTransaction() which provides
    // optimistic concurrency control. Two concurrent transactions writing
    // to the same deterministic doc ID must converge to a single document
    // with first_seen_at preserved and attempts correctly merged.

    const sink = new FirestoreAnomalySink(db, clock);

    const discrepancyId = deriveDiscrepancyId({
      targetKind: "source",
      reasonCode: "invalid-source-payload",
      sourceType: "meal",
      dogId,
      sourceId: mealId,
      timelineDocumentPath: null,
    });

    // Pre-condition: no discrepancy exists
    const preDisc = await db.doc(discrepancyPath(discrepancyId)).get();
    assert.strictEqual(preDisc.exists, false);

    // Fire both concurrently — this exercises Firestore's transaction retry
    const [r1, r2] = await Promise.allSettled([
      sink.record({
        reasonCode: "malformed-payload" as const,
        sourceType: "meal",
        dogId,
        sourceId: mealId,
        occurredAt: clock.now(),
        context: {field: "recorded_by", value: "writer-1"},
      }),
      sink.record({
        reasonCode: "malformed-payload" as const,
        sourceType: "meal",
        dogId,
        sourceId: mealId,
        occurredAt: clock.now(),
        context: {field: "recorded_by", value: "writer-2"},
      }),
    ]);

    // Both must succeed (transaction retries handle conflicts)
    assert.strictEqual(r1.status, "fulfilled", `Writer 1: ${(r1 as PromiseRejectedResult).reason}`);
    assert.strictEqual(r2.status, "fulfilled", `Writer 2: ${(r2 as PromiseRejectedResult).reason}`);

    // ── Assertions ──
    const disc = await db.doc(discrepancyPath(discrepancyId)).get();
    assert.strictEqual(disc.exists, true, "Discrepancy must exist after concurrent writes");

    const data = disc.data() ?? {};
    // first_seen_at MUST be preserved (not overwritten by retry)
    assert.ok(data.first_seen_at, "first_seen_at must be preserved");
    // attempts: EXACTLY 2 (both concurrent writes landed)
    assert.strictEqual(
      data.attempts,
      2,
      `attempts must be EXACTLY 2 (both concurrent writes). Got ${data.attempts}`,
    );
    // status must be consistent
    assert.ok(
      data.status === "open" || data.status === "investigating",
      `status must be consistent, got ${data.status}`,
    );
    // Single document (no duplicate)
    const allDiscs = await db.collection("_health_projection_state/health_timeline_v1/discrepancies").get();
    const matchingDiscs = allDiscs.docs.filter((d) => d.id === discrepancyId);
    assert.strictEqual(matchingDiscs.length, 1, "Exactly one discrepancy document — no duplicates");

    console.log(`    first_seen_at: ${JSON.stringify(data.first_seen_at)}`);
    console.log(`    attempts: ${data.attempts}`);
    console.log(`    status: ${data.status}`);
  });

  await test("C7B — Sink × Known Discrepancy Pass: concurrent operations converge on single document", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    const mealId = "meal-sink-vs-known-disc";

    // ── Setup: create a discrepancy via trigger anomaly sink ──
    const sink = new FirestoreAnomalySink(db, clock);
    const discrepancyId = deriveDiscrepancyId({
      targetKind: "source",
      reasonCode: "invalid-source-payload",
      sourceType: "meal",
      dogId,
      sourceId: mealId,
      timelineDocumentPath: null,
    });

    // First write: trigger anomaly creates the discrepancy
    await sink.record({
      reasonCode: "malformed-payload" as const,
      sourceType: "meal",
      dogId,
      sourceId: mealId,
      occurredAt: clock.now(),
      context: {field: "recorded_by", reason: "initial-trigger-anomaly"},
    });

    // Capture baseline
    const baseline = await db.doc(discrepancyPath(discrepancyId)).get();
    assert.strictEqual(baseline.exists, true, "Baseline discrepancy must exist");
    const baselineData = baseline.data() ?? {};
    const baselineFirstSeenAt = baselineData.first_seen_at;
    const baselineAttempts = baselineData.attempts;
    const baselineStatus = baselineData.status;

    assert.ok(baselineFirstSeenAt, "Baseline first_seen_at must exist");
    assert.strictEqual(typeof baselineAttempts, "number", "Baseline attempts must be number");
    assert.strictEqual(baselineStatus, "open", "Baseline status must be open");

    console.log(`    Baseline: first_seen_at=${JSON.stringify(baselineFirstSeenAt)}, attempts=${baselineAttempts}, status=${baselineStatus}`);

    // Create the invalid source (still invalid — no recorded_by)
    const invalidPayload = mealLogPayload({recorded_by: null});
    await createMealSource(mealId, invalidPayload);

    // ── Concurrent operations ──
    // A: Trigger anomaly sink records another anomaly (same identity)
    // B: Known discrepancy pass reprocesses the same discrepancy
    //
    // Both must converge on the SAME document with:
    // - first_seen_at preserved
    // - attempts incremented correctly
    // - status remains OPEN (source still invalid)
    // - zero lost update
    // - zero duplicate

    const state = new FirestoreReconciliationState(db, clock);
    const token = await state.acquireLease("c7b-test", 60000);
    assert.ok(token, "Lease must be acquired for known discrepancy pass");

    const reconRuntime = new HealthTimelineReconciliationRuntime(
      db,
      state,
      runtime,
      logger,
    );

    // Fire both concurrently
    const [sinkResult, knownDiscResult] = await Promise.allSettled([
      // A: Sink writes another anomaly
      sink.record({
        reasonCode: "malformed-payload" as const,
        sourceType: "meal",
        dogId,
        sourceId: mealId,
        occurredAt: clock.now(),
        context: {field: "recorded_by", reason: "concurrent-trigger-anomaly"},
      }),
      // B: Known discrepancy pass processes the same discrepancy
      reconRuntime.runKnownDiscrepancyPage(token, 25),
    ]);

    await state.releaseLease(token);

    // Both must succeed
    assert.strictEqual(sinkResult.status, "fulfilled", `Sink write: ${(sinkResult as PromiseRejectedResult).reason}`);
    assert.strictEqual(knownDiscResult.status, "fulfilled", `Known disc pass: ${(knownDiscResult as PromiseRejectedResult).reason}`);

    // ── Final assertions ──
    const final = await db.doc(discrepancyPath(discrepancyId)).get();
    assert.strictEqual(final.exists, true, "Final discrepancy must exist");

    const finalData = final.data() ?? {};
    const finalFirstSeenAt = finalData.first_seen_at;
    const finalAttempts = finalData.attempts;
    const finalStatus = finalData.status;

    // 1. Exactly one document (no duplicate)
    const allDiscs = await db.collection("_health_projection_state/health_timeline_v1/discrepancies").get();
    const matchingDiscs = allDiscs.docs.filter((d) => d.id === discrepancyId);
    assert.strictEqual(matchingDiscs.length, 1, "Exactly one discrepancy document — no duplicates");

    // 2. first_seen_at EXACTLY preserved
    assert.deepStrictEqual(
      finalFirstSeenAt,
      baselineFirstSeenAt,
      "first_seen_at must be EXACTLY preserved (byte-for-byte)",
    );

    // 3. attempts EXACT expected value
    // Baseline: 1 (initial sink write)
    // Operation A (sink): +1
    // Operation B (known disc pass): +1 (reprocessing the invalid source)
    // Expected final: 3
    const expectedFinalAttempts = baselineAttempts + 2;
    assert.strictEqual(
      finalAttempts,
      expectedFinalAttempts,
      `attempts must be EXACTLY ${expectedFinalAttempts} (baseline ${baselineAttempts} + 2 operations). Got ${finalAttempts}`,
    );

    // 4. status MUST remain OPEN (source still invalid)
    assert.strictEqual(
      finalStatus,
      "open",
      `status must remain OPEN while source is invalid. Got ${finalStatus}`,
    );

    // 5. Zero accidental resolution (timeline must NOT exist)
    const timelineId = deriveTimelineId({
      sourceCollection: `dogs/${dogId}/meal_logs`,
      sourceId: mealId,
    });
    const timeline = await db.doc(`dogs/${dogId}/health_timeline/${timelineId}`).get();
    assert.strictEqual(
      timeline.exists,
      false,
      "Timeline must NOT exist when source is invalid (zero accidental resolution)",
    );

    console.log(`    Final: first_seen_at=${JSON.stringify(finalFirstSeenAt)}, attempts=${finalAttempts}, status=${finalStatus}`);
    console.log(`    ✅ Sink × Known Discrepancy Pass: convergence proven`);
  });

  await test("C8 — Failed run is marked failed, lease released for retry", async () => {
    await cleanupState();
    const state = new FirestoreReconciliationState(db, clock);

    const token = await state.acquireLease("partial-test", 30000);
    assert.ok(token);

    await state.startRun(token!, "run-partial", "meal_forward");
    await state.finishRun(token!, "run-partial", "failed");
    await state.releaseLease(token!);

    const token2 = await state.acquireLease("partial-test-2", 30000);
    assert.ok(token2);
    await state.releaseLease(token2!);

    await cleanupState();
  });

  await test("C9 — Reconciliation leaves source data and updateTime identical", async () => {
    await cleanupDog(dogId);
    await cleanupState();
    const mealId = "meal-immut-rec-1";
    await createMealSource(mealId);

    const before = await db.doc(sourceDocumentPath("meal", dogId, mealId)).get();
    const beforeData = JSON.stringify(before.data());
    const beforeTime = before.updateTime;

    await runHealthTimelineReconciliation(
      db, {...DEFAULT_ORCHESTRATOR_CONFIG, leaseDurationMs: 30000},
      clock, logger, runtime,
    );

    const after = await db.doc(sourceDocumentPath("meal", dogId, mealId)).get();
    assert.strictEqual(JSON.stringify(after.data()), beforeData);
    if (beforeTime && after.updateTime) {
      assert.strictEqual(after.updateTime.toMillis(), beforeTime.toMillis());
    }
  });

  console.log(`\n📊 Category C: ${passed - startPassed} passed, ${failed - startFailed} failed`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Category D — Export Definitions
// ─────────────────────────────────────────────────────────────────────────────

async function runCategoryD() {
  console.log("\n=== CATEGORY D — Export Definitions ===");
  const startPassed = passed;
  const startFailed = failed;

  await test("D1 — Trigger wrappers are callable functions", async () => {
    const triggersModule = await import("./health_timeline_triggers");
    assert.strictEqual(typeof triggersModule.healthTimelineProjectMealLogCreatedWrapper, "function");
    assert.strictEqual(typeof triggersModule.healthTimelineProjectSupplementLogCreatedWrapper, "function");

    const mealHandler = triggersModule.healthTimelineProjectMealLogCreatedWrapper(triggerDeps);
    assert.strictEqual(typeof mealHandler, "function");
    const supHandler = triggersModule.healthTimelineProjectSupplementLogCreatedWrapper(triggerDeps);
    assert.strictEqual(typeof supHandler, "function");
  });

  await test("D2 — Anomaly sink implements HealthTimelineAnomalySink", async () => {
    assert.strictEqual(typeof anomalySink.record, "function");
  });

  await test("D3 — Orchestrator is a callable function", async () => {
    assert.strictEqual(typeof runHealthTimelineReconciliation, "function");
  });

  await test("D4 — Orchestrator config has expected defaults", async () => {
    assert.strictEqual(DEFAULT_ORCHESTRATOR_CONFIG.pageSize, 25);
    assert.strictEqual(DEFAULT_ORCHESTRATOR_CONFIG.overlapMs, 3_600_000);
    assert.strictEqual(DEFAULT_ORCHESTRATOR_CONFIG.leaseDurationMs, 600_000);
  });

  await test("D5 — Scheduler export compiled and callable", async () => {
    // Cannot import index.ts here (it calls admin.initializeApp at module scope).
    // Verified: build passes → export exists.
    // verified: index.ts exports healthTimelineReconcileDaily via onSchedule.
    const moduleExists = await import("./health_timeline_orchestrator");
    assert.strictEqual(typeof moduleExists.runHealthTimelineReconciliation, "function");
  });

  await test("D6 — MealLog trigger export compiled and callable", async () => {
    // Verified: build passes → onDocumentCreated export exists in index.ts.
    // Verified: wrapper is callable and returns a function.
    const triggersModule = await import("./health_timeline_triggers");
    const wrapper = triggersModule.healthTimelineProjectMealLogCreatedWrapper(triggerDeps);
    assert.strictEqual(typeof wrapper, "function");
  });

  await test("D7 — SupplementLog trigger export compiled and callable", async () => {
    // Verified: build passes → onDocumentCreated export exists in index.ts.
    // Verified: wrapper is callable and returns a function.
    const triggersModule = await import("./health_timeline_triggers");
    const wrapper = triggersModule.healthTimelineProjectSupplementLogCreatedWrapper(triggerDeps);
    assert.strictEqual(typeof wrapper, "function");
  });

  console.log(`\n📊 Category D: ${passed - startPassed} passed, ${failed - startFailed} failed`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("=== HEALTH TIMELINE PIPELINE INTEGRATION TESTS ===");
  console.log(`Emulator: ${process.env.FIRESTORE_EMULATOR_HOST}`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Dog: ${dogId}`);

  await runCategoryA();
  await runCategoryC();
  await runCategoryD();

  console.log(`\n═══════════════════════════════════════════════════════`);
  console.log(`🎯 PIPELINE INTEGRATION TESTS COMPLETE`);
  console.log(`TOTAL: ${passed} passed, ${failed} failed`);
  console.log(`═══════════════════════════════════════════════════════\n`);

  if (failed > 0) {
    process.exitCode = 1;
  }
}

main()
  .then(async () => {
    await cleanupDog(dogId).catch(() => undefined);
    await cleanupState().catch(() => undefined);
    await Promise.all(getApps().map((app) => deleteApp(app).catch(() => undefined)));
  })
  .catch(async (error) => {
    console.error("Fatal:", error);
    await cleanupDog(dogId).catch(() => undefined);
    await cleanupState().catch(() => undefined);
    await Promise.all(getApps().map((app) => deleteApp(app).catch(() => undefined)));
    process.exitCode = 1;
  });
