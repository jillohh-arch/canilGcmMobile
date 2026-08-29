import * as assert from "assert";
import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldPath,
  Timestamp,
  getFirestore,
  type DocumentData,
  type DocumentReference,
} from "firebase-admin/firestore";
import {
  HealthTimelineReconciliationRuntime,
} from "./health_timeline_reconciliation";
import {
  FirestoreReconciliationState,
  StaleLeaseError,
  cursorsEqual,
  globalPassKey,
  sourcePassKey,
  type LeaseToken,
} from "./health_timeline_reconciliation_state";
import {
  FirestoreHealthTimelineRuntime,
  type RuntimeClock,
  type RuntimeLogger,
} from "./health_timeline_runtime";
import {makeMealLogCreatedHandler} from "./health_timeline_trigger_handlers";
import {deriveTimelineId} from "./health_timeline_projection";

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT || "canil-gcm";
if (!emulatorHost) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST is required; reconciliation tests never use production.",
  );
}
if (getApps().length === 0) initializeApp({projectId});
const db = getFirestore();

let nowMs = Date.parse("2026-07-23T12:00:00.000Z");
const clock: RuntimeClock = {now: () => new Date(nowMs)};
const logEvents: Array<{level: string; message: string}> = [];
const logger: RuntimeLogger = {
  info: (message) => logEvents.push({level: "info", message}),
  warn: (message) => logEvents.push({level: "warn", message}),
  error: (message) => logEvents.push({level: "error", message}),
};

let passed = 0;
let failed = 0;

function recordedBy(): {
  uid: string;
  name: string;
  internal_role: string;
} {
  return {
    uid: "reconciliation-test-user",
    name: "Reconciliation Test",
    internal_role: "tester",
  };
}

function mealData(
  recordedAt: Timestamp,
  overrides: DocumentData = {},
): DocumentData {
  return {
    kind: "adhoc",
    acceptance: "full",
    offered_grams: 200,
    consumed_grams: 200,
    fed_at: recordedAt,
    recorded_at: recordedAt,
    recorded_by: recordedBy(),
    food_name: "Ração Reconciliation",
    ...overrides,
  };
}

function supplementData(
  recordedAt: Timestamp,
  overrides: DocumentData = {},
): DocumentData {
  return {
    supplement_name: "Vitamina Reconciliation",
    dose: 10,
    unit: "mg",
    administered_at: recordedAt,
    recorded_at: recordedAt,
    recorded_by: recordedBy(),
    ...overrides,
  };
}

function at(offsetMs: number): Timestamp {
  return Timestamp.fromMillis(
    Date.parse("2026-07-23T08:00:00.000Z") + offsetMs,
  );
}

function sourceRef(
  dogId: string,
  sourceId: string,
  sourceType: "meal" | "supplement" = "meal",
): DocumentReference {
  const collection = sourceType === "meal" ?
    "meal_logs" :
    "supplement_logs";
  return db.doc(`dogs/${dogId}/${collection}/${sourceId}`);
}

function timelineRef(
  dogId: string,
  sourceId: string,
  sourceType: "meal" | "supplement" = "meal",
): DocumentReference {
  const collection = sourceType === "meal" ?
    "meal_logs" :
    "supplement_logs";
  const timelineId = deriveTimelineId({
    sourceCollection: `dogs/${dogId}/${collection}`,
    sourceId,
  });
  return db.doc(`dogs/${dogId}/health_timeline/${timelineId}`);
}

async function deleteQuery(
  query: FirebaseFirestore.Query,
): Promise<void> {
  while (true) {
    const snapshot = await query.limit(400).get();
    if (snapshot.empty) return;
    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
  }
}

async function clearState(): Promise<void> {
  const root = db.doc("_health_projection_state/health_timeline_v1");
  await Promise.all([
    deleteQuery(root.collection("passes").orderBy(FieldPath.documentId())),
    deleteQuery(root.collection("runs").orderBy(FieldPath.documentId())),
    deleteQuery(root.collection("discrepancies").orderBy(FieldPath.documentId())),
  ]);
  await root.delete();
}

async function clearCanonicalTestData(): Promise<void> {
  await Promise.all([
    deleteQuery(db.collectionGroup("meal_logs").orderBy(FieldPath.documentId())),
    deleteQuery(db.collectionGroup("supplement_logs").orderBy(FieldPath.documentId())),
    deleteQuery(db.collectionGroup("health_timeline").orderBy(FieldPath.documentId())),
  ]);
  await clearState();
}

async function assertZeroLegacyWrites(): Promise<void> {
  for (const collection of [
    "feeding_events",
    "feedings",
    "nutrition_supplements",
    "nutritional_prescriptions",
    "nutrition_prescriptions",
  ]) {
    const snapshot = await db.collectionGroup(collection).limit(1).get();
    assert.strictEqual(snapshot.empty, true, `${collection} must stay empty`);
  }
}

function harness(options: {
  beforeSourceProjection?: (
    sourceType: "meal" | "supplement",
    path: string,
  ) => void | Promise<void>;
  beforeDiscrepancyWrite?: (
    identity: {
      sourceId: string | null;
    },
  ) => void | Promise<void>;
} = {}) {
  const state = new FirestoreReconciliationState(
    db,
    clock,
    options.beforeDiscrepancyWrite,
  );
  const projector = new FirestoreHealthTimelineRuntime(db, clock, logger);
  const reconciliation = new HealthTimelineReconciliationRuntime(
    db,
    state,
    projector,
    logger,
    {beforeSourceProjection: options.beforeSourceProjection},
  );
  return {state, projector, reconciliation};
}

async function lease(
  state: FirestoreReconciliationState,
  owner = "worker-a",
  durationMs = 24 * 60 * 60 * 1000,
): Promise<LeaseToken> {
  const token = await state.acquireLease(owner, durationMs);
  assert.ok(token, `lease ${owner} should be acquired`);
  return token;
}

async function test(
  name: string,
  fn: () => Promise<void>,
): Promise<void> {
  await clearCanonicalTestData();
  nowMs = Date.parse("2026-07-23T12:00:00.000Z");
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

async function allDiscrepancies(): Promise<FirebaseFirestore.QuerySnapshot> {
  return db.collection(
    "_health_projection_state/health_timeline_v1/discrepancies",
  ).get();
}

async function main(): Promise<void> {
  console.log("\n=== HEALTH TIMELINE RECONCILIATION — EMULATOR ===");
  console.log(`Emulator: ${emulatorHost}`);
  console.log(`Project: ${projectId}\n`);

  await test("1 — forward is bounded and eventually covers backlog", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    for (let index = 0; index < 3; index++) {
      await sourceRef("dog-forward", `meal-${index}`)
        .set(mealData(at(index * 1000)));
    }
    const first = await reconciliation.runForwardPage(token, "meal", 2);
    assert.strictEqual(first.processed, 2);
    assert.strictEqual(first.hasMore, true);
    const second = await reconciliation.runForwardPage(token, "meal", 2);
    assert.strictEqual(second.processed, 1);
    assert.strictEqual(
      (await db.collectionGroup("health_timeline").get()).size,
      3,
    );
  });

  await test("2 — global tie-break covers same time/local ID across dogs", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    const sameTime = at(0);
    await Promise.all([
      sourceRef("dog-a", "same-id").set(mealData(sameTime)),
      sourceRef("dog-b", "same-id").set(mealData(sameTime)),
    ]);
    const first = await reconciliation.runForwardPage(token, "meal", 1);
    const second = await reconciliation.runForwardPage(token, "meal", 1);
    assert.strictEqual(first.processed, 1);
    assert.strictEqual(second.processed, 1);
    assert.strictEqual(
      (await timelineRef("dog-a", "same-id").get()).exists,
      true,
    );
    assert.strictEqual(
      (await timelineRef("dog-b", "same-id").get()).exists,
      true,
    );
  });

  await test("3 — persisted cursor resumes after runtime restart", async () => {
    const firstHarness = harness();
    const token = await lease(firstHarness.state);
    for (let index = 0; index < 3; index++) {
      await sourceRef("dog-restart", `meal-${index}`)
        .set(mealData(at(index * 1000)));
    }
    await firstHarness.reconciliation.runForwardPage(token, "meal", 1);
    const before = await firstHarness.state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    const restarted = harness();
    const page = await restarted.reconciliation.runForwardPage(
      token,
      "meal",
      1,
    );
    const after = await restarted.state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    assert.strictEqual(page.processed, 1);
    assert.strictEqual(cursorsEqual(before.cursor, after.cursor), false);
    assert.strictEqual(
      after.cursor?.documentPath.endsWith("/meal-1"),
      true,
    );
  });

  await test("4 — transient A/B/C stops at A and retry covers B/C", async () => {
    let failB = true;
    const firstHarness = harness({
      beforeSourceProjection: (_type, path) => {
        if (failB && path.endsWith("/meal-b")) {
          throw new Error("injected transient failure");
        }
      },
    });
    const token = await lease(firstHarness.state);
    await sourceRef("dog-partial", "meal-a").set(mealData(at(0)));
    await sourceRef("dog-partial", "meal-b").set(mealData(at(1000)));
    await sourceRef("dog-partial", "meal-c").set(mealData(at(2000)));
    await assert.rejects(
      () => firstHarness.reconciliation.runForwardPage(token, "meal", 3),
      /injected transient failure/,
    );
    const cursor = await firstHarness.state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    assert.strictEqual(cursor.cursor?.documentPath.endsWith("/meal-a"), true);
    assert.strictEqual((await timelineRef("dog-partial", "meal-a").get()).exists, true);
    assert.strictEqual((await timelineRef("dog-partial", "meal-b").get()).exists, false);
    assert.strictEqual((await timelineRef("dog-partial", "meal-c").get()).exists, false);

    failB = false;
    const retry = await firstHarness.reconciliation.runForwardPage(
      token,
      "meal",
      3,
    );
    assert.strictEqual(retry.processed, 2);
    assert.strictEqual((await timelineRef("dog-partial", "meal-b").get()).exists, true);
    assert.strictEqual((await timelineRef("dog-partial", "meal-c").get()).exists, true);
  });

  await test("5 — deterministic invalid B writes discrepancy and advances", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-invalid", "meal-a").set(mealData(at(0)));
    await sourceRef("dog-invalid", "meal-b")
      .set(mealData(at(1000), {acceptance: "invalid"}));
    await sourceRef("dog-invalid", "meal-c").set(mealData(at(2000)));
    const page = await reconciliation.runForwardPage(token, "meal", 3);
    assert.strictEqual(page.processed, 3);
    assert.strictEqual(page.skippedAnomaly, 1);
    assert.strictEqual((await allDiscrepancies()).size, 1);
    assert.strictEqual((await timelineRef("dog-invalid", "meal-c").get()).exists, true);
    const pass = await state.getPassState(sourcePassKey("meal", "forward"));
    assert.strictEqual(pass.cursor?.documentPath.endsWith("/meal-c"), true);
  });

  await test("6 — discrepancy failure cannot advance cursor over B", async () => {
    const {state, reconciliation} = harness({
      beforeDiscrepancyWrite: (identity) => {
        if (identity.sourceId === "meal-b") {
          throw new Error("injected discrepancy persistence failure");
        }
      },
    });
    const token = await lease(state);
    await sourceRef("dog-disc-fail", "meal-a").set(mealData(at(0)));
    await sourceRef("dog-disc-fail", "meal-b")
      .set(mealData(at(1000), {acceptance: "invalid"}));
    await sourceRef("dog-disc-fail", "meal-c").set(mealData(at(2000)));
    await assert.rejects(
      () => reconciliation.runForwardPage(token, "meal", 3),
      /injected discrepancy persistence failure/,
    );
    const pass = await state.getPassState(sourcePassKey("meal", "forward"));
    assert.strictEqual(pass.cursor?.documentPath.endsWith("/meal-a"), true);
    assert.strictEqual((await allDiscrepancies()).empty, true);
    assert.strictEqual((await timelineRef("dog-disc-fail", "meal-c").get()).exists, false);
  });

  await test("7 — overlap backlog spans pages without moving forward cursor", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    for (let index = 0; index < 5; index++) {
      await sourceRef("dog-overlap", `meal-${index}`)
        .set(mealData(at(index * 1000)));
    }
    await reconciliation.runForwardPage(token, "meal", 10);
    const forwardBefore = await state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    const pages = [
      await reconciliation.runOverlapPage(token, "meal", 2),
      await reconciliation.runOverlapPage(token, "meal", 2),
      await reconciliation.runOverlapPage(token, "meal", 2),
    ];
    assert.deepStrictEqual(pages.map((page) => page.processed), [2, 2, 1]);
    const forwardAfter = await state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    assert.strictEqual(
      cursorsEqual(forwardBefore.cursor, forwardAfter.cursor),
      true,
    );
    assert.strictEqual((await db.collectionGroup("health_timeline").get()).size, 5);
  });

  await test("8 — overlap captures out-of-order write behind forward", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-late", "meal-a").set(mealData(at(10_000)));
    await reconciliation.runForwardPage(token, "meal", 10);
    await sourceRef("dog-late", "meal-behind").set(mealData(at(5_000)));
    const forward = await reconciliation.runForwardPage(token, "meal", 10);
    assert.strictEqual(forward.processed, 0);
    assert.strictEqual((await timelineRef("dog-late", "meal-behind").get()).exists, false);
    await reconciliation.runOverlapPage(token, "meal", 10, 60_000);
    assert.strictEqual((await timelineRef("dog-late", "meal-behind").get()).exists, true);
  });

  await test("9 — historical sweep performs real wrap", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    for (let index = 0; index < 3; index++) {
      await sourceRef("dog-history", `meal-${index}`)
        .set(mealData(at(index * 1000)));
    }
    const page1 = await reconciliation.runHistoricalPage(token, "meal", 2);
    const page2 = await reconciliation.runHistoricalPage(token, "meal", 2);
    const cycleState = await state.getPassState(
      sourcePassKey("meal", "historical"),
    );
    const nextCycle = await reconciliation.runHistoricalPage(token, "meal", 2);
    assert.strictEqual(page1.processed, 2);
    assert.strictEqual(page2.processed, 1);
    assert.strictEqual(cycleState.cycle, 1);
    assert.strictEqual(cycleState.cursor, null);
    assert.strictEqual(nextCycle.processed, 2);
  });

  await test("10 — exact page multiple requires empty confirmation", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    for (let index = 0; index < 4; index++) {
      await sourceRef("dog-multiple", `meal-${index}`)
        .set(mealData(at(index * 1000)));
    }
    const page1 = await reconciliation.runHistoricalPage(token, "meal", 2);
    const page2 = await reconciliation.runHistoricalPage(token, "meal", 2);
    const beforeEmpty = await state.getPassState(
      sourcePassKey("meal", "historical"),
    );
    const empty = await reconciliation.runHistoricalPage(token, "meal", 2);
    const afterEmpty = await state.getPassState(
      sourcePassKey("meal", "historical"),
    );
    assert.strictEqual(page1.hasMore, true);
    assert.strictEqual(page2.hasMore, true);
    assert.notStrictEqual(beforeEmpty.cursor, null);
    assert.strictEqual(empty.processed, 0);
    assert.strictEqual(afterEmpty.cursor, null);
    assert.strictEqual(afterEmpty.cycle, 1);
  });

  await test("11 — valid orphan creates discrepancy and preserves timeline", async () => {
    const {state, projector, reconciliation} = harness();
    const token = await lease(state);
    const ref = sourceRef("dog-orphan", "meal-a");
    await ref.set(mealData(at(0)));
    await projector.project({
      sourceType: "meal",
      dogId: "dog-orphan",
      sourceId: "meal-a",
      data: {
        id: "meal-a",
        dogId: "dog-orphan",
        kind: "adhoc",
        acceptance: "full",
        offered_grams: 200,
        consumed_grams: 200,
        fed_at: at(0).toDate().toISOString(),
        recorded_at: at(0).toDate().toISOString(),
        recorded_by: recordedBy(),
        food_name: "Ração",
      },
    });
    await ref.delete();
    const timeline = timelineRef("dog-orphan", "meal-a");
    const before = await timeline.get();
    const page = await reconciliation.runOrphanPage(token, 10);
    const after = await timeline.get();
    assert.strictEqual(page.skippedAnomaly, 1);
    assert.strictEqual((await allDiscrepancies()).size, 1);
    assert.strictEqual(after.exists, true);
    assert.strictEqual(after.updateTime?.isEqual(before.updateTime!), true);
  });

  await test("12 — malformed/cross-dog timelines never dereference or delete", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    const fixtures = [
      {
        path: "dogs/dog-a/health_timeline/bad-cross",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-b/meal_logs",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-slash",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/meal_logs",
          source_id: "bad/id",
          timeline_type: "meal",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-unknown-collection",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/vet_logs",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-malformed-collection",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/meal_logs/extra",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-dog",
        data: {
          dog_id: "dog-b",
          source_collection: "dogs/dog-a/meal_logs",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-type",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/meal_logs",
          source_id: "meal-a",
          timeline_type: "supplement",
        },
      },
      {
        path: "dogs/dog-a/health_timeline/bad-deterministic-id",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/meal_logs",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
      {
        path: "owners/owner-a/health_timeline/bad-location",
        data: {
          dog_id: "dog-a",
          source_collection: "dogs/dog-a/meal_logs",
          source_id: "meal-a",
          timeline_type: "meal",
        },
      },
    ];
    for (const fixture of fixtures) await db.doc(fixture.path).set(fixture.data);
    const page = await reconciliation.runOrphanPage(token, 20);
    assert.strictEqual(page.skippedAnomaly, fixtures.length);
    assert.strictEqual((await allDiscrepancies()).size, fixtures.length);
    for (const fixture of fixtures) {
      assert.strictEqual((await db.doc(fixture.path).get()).exists, true);
    }
    assert.strictEqual((await db.doc("dogs/dog-b/meal_logs/meal-a").get()).exists, false);
  });

  await test("13 — corrected source resolves known discrepancy", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    const ref = sourceRef("dog-resolve", "meal-a");
    await ref.set(mealData(at(0), {acceptance: "invalid"}));
    await reconciliation.runForwardPage(token, "meal", 10);
    const discrepancy = (await allDiscrepancies()).docs[0];
    assert.strictEqual(discrepancy.get("status"), "open");
    await ref.set(mealData(at(0)));
    const page = await reconciliation.runKnownDiscrepancyPage(token, 10);
    assert.strictEqual(page.processed, 1);
    const resolved = await discrepancy.ref.get();
    assert.strictEqual(resolved.get("status"), "resolved");
    assert.ok(resolved.get("resolved_at") instanceof Timestamp);
    assert.strictEqual((await timelineRef("dog-resolve", "meal-a").get()).exists, true);
  });

  await test("14 — concurrent lease acquisition activates only one worker", async () => {
    const {state} = harness();
    const [left, right] = await Promise.all([
      state.acquireLease("worker-a", 10_000),
      state.acquireLease("worker-b", 10_000),
    ]);
    assert.strictEqual([left, right].filter(Boolean).length, 1);
    const blocked = await state.acquireLease("worker-c", 10_000);
    assert.strictEqual(blocked, null);
  });

  await test("15 — stale worker is fenced after expired takeover", async () => {
    const {state, reconciliation} = harness();
    const tokenA = await lease(state, "worker-a", 1000);
    await sourceRef("dog-fence", "meal-a").set(mealData(at(0)));
    nowMs += 2000;
    const tokenB = await lease(state, "worker-b", 10_000);
    await assert.rejects(
      () => reconciliation.runForwardPage(tokenA, "meal", 10),
      StaleLeaseError,
    );
    const passBefore = await state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    assert.strictEqual(passBefore.cursor, null);
    assert.strictEqual(await state.releaseLease(tokenA), false);
    await reconciliation.runForwardPage(tokenB, "meal", 10);
    const passAfter = await state.getPassState(
      sourcePassKey("meal", "forward"),
    );
    assert.notStrictEqual(passAfter.cursor, null);
  });

  await test("16 — trigger and reconciliation converge without second write", async () => {
    const {state, projector, reconciliation} = harness();
    const token = await lease(state);
    const ref = sourceRef("dog-trigger", "meal-a");
    await ref.set(mealData(at(0)));
    const snapshot = await ref.get();
    const handler = makeMealLogCreatedHandler({
      projector,
      clock,
      logger,
      anomalySink: {record: async () => undefined},
    });
    const [triggerResult, reconciliationResult] = await Promise.all([
      handler({
        params: {dogId: "dog-trigger", mealId: "meal-a"},
        snapshot: {
          exists: snapshot.exists,
          id: snapshot.id,
          ref: {path: snapshot.ref.path},
          data: () => snapshot.data(),
        },
      }),
      reconciliation.runForwardPage(token, "meal", 10),
    ]);
    assert.strictEqual(triggerResult.status, "projected");
    assert.strictEqual(reconciliationResult.processed, 1);
    const final = await timelineRef("dog-trigger", "meal-a").get();
    assert.strictEqual(final.exists, true);
    assert.strictEqual(final.createTime?.isEqual(final.updateTime!), true);
    assert.strictEqual(
      (await db.collectionGroup("health_timeline").get()).size,
      1,
    );
  });

  await test("17 — reconciliation leaves source data and updateTime identical", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    const ref = sourceRef("dog-immutable", "meal-a");
    await ref.set(mealData(at(0)));
    const before = await ref.get();
    await reconciliation.runForwardPage(token, "meal", 10);
    const after = await ref.get();
    assert.deepStrictEqual(after.data(), before.data());
    assert.strictEqual(after.updateTime?.isEqual(before.updateTime!), true);
  });

  await test("18 — reconciliation performs zero legacy writes", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-legacy", "meal-a").set(mealData(at(0)));
    await reconciliation.runForwardPage(token, "meal", 10);
    await reconciliation.runHistoricalPage(token, "meal", 10);
    await reconciliation.runOrphanPage(token, 10);
    await assertZeroLegacyWrites();
  });

  await test("19 — next overlap cycle captures late insert behind page cursor", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-starve", "meal-a").set(mealData(at(1000)));
    await sourceRef("dog-starve", "meal-b").set(mealData(at(2000)));
    await sourceRef("dog-starve", "meal-c").set(mealData(at(3000)));
    await reconciliation.runForwardPage(token, "meal", 10);
    await reconciliation.runOverlapPage(token, "meal", 1, 60_000);
    await sourceRef("dog-starve", "meal-late").set(mealData(at(500)));
    await reconciliation.runOverlapPage(token, "meal", 1, 60_000);
    await reconciliation.runOverlapPage(token, "meal", 1, 60_000);
    await reconciliation.runOverlapPage(token, "meal", 1, 60_000);
    assert.strictEqual((await timelineRef("dog-starve", "meal-late").get()).exists, false);
    await reconciliation.runOverlapPage(token, "meal", 1, 60_000);
    assert.strictEqual((await timelineRef("dog-starve", "meal-late").get()).exists, true);
  });

  await test("20 — unresolved discrepancy stays open and historical", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-open", "meal-a")
      .set(mealData(at(0), {acceptance: "invalid"}));
    await reconciliation.runForwardPage(token, "meal", 10);
    const discrepancy = (await allDiscrepancies()).docs[0];
    const attemptsBefore = discrepancy.get("attempts");
    await reconciliation.runKnownDiscrepancyPage(token, 10);
    const after = await discrepancy.ref.get();
    assert.strictEqual(after.get("status"), "open");
    assert.ok(after.get("attempts") > attemptsBefore);
  });

  await test("21 — reappearing orphan is reprojected and resolved", async () => {
    const {state, projector, reconciliation} = harness();
    const token = await lease(state);
    const ref = sourceRef("dog-return", "meal-a");
    const data = mealData(at(0));
    await ref.set(data);
    const parsed = {
      sourceType: "meal" as const,
      dogId: "dog-return",
      sourceId: "meal-a",
      data: {
        id: "meal-a",
        dogId: "dog-return",
        kind: "adhoc" as const,
        acceptance: "full",
        offered_grams: 200,
        consumed_grams: 200,
        fed_at: at(0).toDate().toISOString(),
        recorded_at: at(0).toDate().toISOString(),
        recorded_by: recordedBy(),
      },
    };
    await projector.project(parsed);
    await ref.delete();
    await reconciliation.runOrphanPage(token, 10);
    const discrepancy = (await allDiscrepancies()).docs[0];
    await ref.set(data);
    await reconciliation.runKnownDiscrepancyPage(token, 10);
    assert.strictEqual((await discrepancy.ref.get()).get("status"), "resolved");
    assert.strictEqual((await timelineRef("dog-return", "meal-a").get()).exists, true);
  });

  await test("22 — meal and supplement forward cursors are independent", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-types", "same-id", "meal").set(mealData(at(0)));
    await sourceRef("dog-types", "same-id", "supplement")
      .set(supplementData(at(0)));
    await reconciliation.runForwardPage(token, "meal", 10);
    const mealPass = await state.getPassState(sourcePassKey("meal", "forward"));
    const supplementBefore = await state.getPassState(
      sourcePassKey("supplement", "forward"),
    );
    assert.notStrictEqual(mealPass.cursor, null);
    assert.strictEqual(supplementBefore.cursor, null);
    await reconciliation.runForwardPage(token, "supplement", 10);
    const supplementAfter = await state.getPassState(
      sourcePassKey("supplement", "forward"),
    );
    assert.notStrictEqual(supplementAfter.cursor, null);
    assert.strictEqual(
      (await timelineRef("dog-types", "same-id", "supplement").get()).exists,
      true,
    );
  });

  await test("23 — durable run lifecycle is fenced and persistent", async () => {
    const {state} = harness();
    const token = await lease(state);
    await state.startRun(token, "run-1", sourcePassKey("meal", "forward"));
    const runRef = db.doc(
      "_health_projection_state/health_timeline_v1/runs/run-1",
    );
    assert.strictEqual((await runRef.get()).get("status"), "running");
    await state.finishRun(token, "run-1", "completed");
    const completed = await runRef.get();
    assert.strictEqual(completed.get("status"), "completed");
    assert.ok(completed.get("completed_at") instanceof Timestamp);
  });

  await test("24 — unexpected ISO physical cursor is preserved and anomalized", async () => {
    const {state, reconciliation} = harness();
    const token = await lease(state);
    await sourceRef("dog-physical", "meal-a").set(mealData(at(0), {
      recorded_at: "2026-07-23T08:00:00.000Z",
    }));
    const page = await reconciliation.runForwardPage(token, "meal", 10);
    const pass = await state.getPassState(sourcePassKey("meal", "forward"));
    assert.strictEqual(page.skippedAnomaly, 1);
    assert.strictEqual(pass.cursor?.kind, "recorded_at_name");
    if (pass.cursor?.kind === "recorded_at_name") {
      assert.strictEqual(
        pass.cursor.recordedAt,
        "2026-07-23T08:00:00.000Z",
      );
    }
    assert.strictEqual(
      (await allDiscrepancies()).docs[0].get("reason_code"),
      "unsupported-recorded-at-type",
    );
    assert.strictEqual((await timelineRef("dog-physical", "meal-a").get()).exists, false);
    const discrepancy = (await allDiscrepancies()).docs[0];
    await reconciliation.runKnownDiscrepancyPage(token, 10);
    assert.strictEqual((await discrepancy.ref.get()).get("status"), "open");
    await sourceRef("dog-physical", "meal-a").set(mealData(at(0)));
    await reconciliation.runKnownDiscrepancyPage(token, 10);
    assert.strictEqual((await discrepancy.ref.get()).get("status"), "resolved");
    assert.strictEqual((await timelineRef("dog-physical", "meal-a").get()).exists, true);
  });

  await test("25 — open discrepancies wrap and are eventually revisited", async () => {
    const initialHarness = harness();
    const token = await lease(initialHarness.state);
    await sourceRef("dog-revisit", "meal-d1")
      .set(mealData(at(0), {acceptance: "invalid"}));
    await sourceRef("dog-revisit", "meal-d2")
      .set(mealData(at(1000), {acceptance: "invalid"}));
    await initialHarness.reconciliation.runForwardPage(token, "meal", 10);

    const discrepancyRefs = (await db.collection(
      "_health_projection_state/health_timeline_v1/discrepancies",
    ).orderBy(FieldPath.documentId()).get()).docs.map((document) => document.ref);
    assert.strictEqual(discrepancyRefs.length, 2);
    const firstBefore = await discrepancyRefs[0].get();
    const firstId = firstBefore.id;
    const firstSeenAt = firstBefore.get("first_seen_at") as Timestamp;
    const firstAttemptsBefore = firstBefore.get("attempts") as number;

    const run1 = await initialHarness.reconciliation
      .runKnownDiscrepancyPage(token, 1);
    const afterRun1 = await discrepancyRefs[0].get();
    const stateAfterRun1 = await initialHarness.state.getPassState(
      globalPassKey("known_discrepancies"),
    );
    assert.strictEqual(run1.processed, 1);
    assert.strictEqual(run1.hasMore, true);
    assert.strictEqual(afterRun1.get("attempts"), firstAttemptsBefore + 1);
    assert.strictEqual(
      stateAfterRun1.cursor?.documentPath,
      discrepancyRefs[0].path,
    );

    const run2 = await initialHarness.reconciliation
      .runKnownDiscrepancyPage(token, 1);
    const stateAfterRun2 = await initialHarness.state.getPassState(
      globalPassKey("known_discrepancies"),
    );
    assert.strictEqual(run2.processed, 1);
    assert.strictEqual(run2.hasMore, true);
    assert.strictEqual(
      stateAfterRun2.cursor?.documentPath,
      discrepancyRefs[1].path,
    );

    const run3 = await initialHarness.reconciliation
      .runKnownDiscrepancyPage(token, 1);
    const stateAfterRun3 = await initialHarness.state.getPassState(
      globalPassKey("known_discrepancies"),
    );
    assert.strictEqual(run3.processed, 0);
    assert.strictEqual(run3.hasMore, false);
    assert.strictEqual(stateAfterRun3.cursor, null);
    assert.strictEqual(stateAfterRun3.cycle, 1);

    const restartedHarness = harness();
    const run4 = await restartedHarness.reconciliation
      .runKnownDiscrepancyPage(token, 1);
    const firstAfterRevisit = await discrepancyRefs[0].get();
    assert.strictEqual(run4.processed, 1);
    assert.strictEqual(firstAfterRevisit.id, firstId);
    assert.strictEqual(firstAfterRevisit.get("status"), "open");
    assert.strictEqual(
      firstAfterRevisit.get("attempts"),
      firstAttemptsBefore + 2,
    );
    assert.strictEqual(
      (firstAfterRevisit.get("first_seen_at") as Timestamp).isEqual(firstSeenAt),
      true,
    );
    assert.strictEqual((await allDiscrepancies()).size, 2);
  });

  await clearCanonicalTestData();
  await assertZeroLegacyWrites();

  console.log("\n=== RECONCILIATION EMULATOR SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log(`Structured log events: ${logEvents.length}`);
  if (failed > 0) process.exitCode = 1;
  else {
    console.log(
      `🎯 HEALTH TIMELINE RECONCILIATION EMULATOR TESTS PASSED (${passed}/${passed})`,
    );
  }
}

main().catch(async (error) => {
  console.error(error);
  process.exitCode = 1;
  try {
    await clearCanonicalTestData();
  } catch (cleanupError) {
    console.error("Cleanup failed", cleanupError);
  }
});
