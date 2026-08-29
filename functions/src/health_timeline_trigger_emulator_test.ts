import * as assert from "assert";
import {deleteApp, initializeApp} from "firebase-admin/app";
import {
  Timestamp,
  getFirestore,
  type DocumentReference,
} from "firebase-admin/firestore";
import {deriveTimelineId} from "./health_timeline_projection";
import {
  FirestoreHealthTimelineRuntime,
  canonicalTimelineKeys,
  sourceCollectionPath,
  timelineDocumentPath,
  type HealthTimelineProjector,
  type RuntimeLogger,
} from "./health_timeline_runtime";
import {
  makeMealLogCreatedHandler,
  makeSupplementLogCreatedHandler,
  type HealthTimelineAnomaly,
  type HealthTimelineAnomalySink,
  type TriggerHandlerDependencies,
} from "./health_timeline_trigger_handlers";

const PROJECT_ID = process.env.GCLOUD_PROJECT || "canil-gcm";
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;

if (!EMULATOR_HOST) {
  throw new Error("FIRESTORE_EMULATOR_HOST is required.");
}

const runToken = `${Date.now()}_${Math.random().toString(16).slice(2, 8)}`;
const dogId = `dog_timeline_runtime_${runToken}`;
const otherDogId = `dog_timeline_other_${runToken}`;
const app = initializeApp({projectId: PROJECT_ID}, `timeline-runtime-${runToken}`);
const db = getFirestore(app);

const loggerEvents: Array<{
  level: string;
  message: string;
  context?: Record<string, unknown>;
}> = [];

const logger: RuntimeLogger = {
  info: (message, context) => loggerEvents.push({level: "info", message, context}),
  warn: (message, context) => loggerEvents.push({level: "warn", message, context}),
  error: (message, context) => loggerEvents.push({level: "error", message, context}),
};

class SteppingClock {
  private value = Date.parse("2026-07-23T12:00:00.000Z");
  calls = 0;

  now(): Date {
    const current = new Date(this.value);
    this.value += 1000;
    this.calls++;
    return current;
  }
}

const clock = new SteppingClock();
const runtime = new FirestoreHealthTimelineRuntime(db, clock, logger);
const anomalies: HealthTimelineAnomaly[] = [];
const anomalySink: HealthTimelineAnomalySink = {
  record: async (anomaly) => {
    anomalies.push(anomaly);
  },
};

function dependencies(
  projector: HealthTimelineProjector = runtime,
  sink: HealthTimelineAnomalySink = anomalySink,
): TriggerHandlerDependencies {
  return {projector, anomalySink: sink, clock, logger};
}

const mealHandler = makeMealLogCreatedHandler(dependencies());
const supplementHandler = makeSupplementLogCreatedHandler(dependencies());

function recordedBy() {
  return {
    uid: "uid-emulator",
    name: "Condutor Emulator",
    internal_role: "condutor",
  };
}

function mealFixture(overrides: Record<string, unknown> = {}) {
  return {
    period: "morning",
    offered_grams: 200,
    consumed_grams: 180,
    acceptance: "partial",
    fed_at: Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z")),
    recorded_at: Timestamp.fromDate(new Date("2026-07-23T08:01:00.000Z")),
    recorded_by: recordedBy(),
    food_name: "Ração Emulator",
    source_only_field: "never-project",
    ...overrides,
  };
}

function supplementFixture(overrides: Record<string, unknown> = {}) {
  return {
    supplement_name: "Vitamina Emulator",
    dose: 25,
    unit: "mg",
    administered_at: Timestamp.fromDate(
      new Date("2026-07-23T09:00:00.000Z"),
    ),
    recorded_at: Timestamp.fromDate(
      new Date("2026-07-23T09:01:00.000Z"),
    ),
    recorded_by: recordedBy(),
    source_only_field: "never-project",
    ...overrides,
  };
}

function mealRef(id: string, targetDogId = dogId): DocumentReference {
  return db.doc(`dogs/${targetDogId}/meal_logs/${id}`);
}

function supplementRef(id: string): DocumentReference {
  return db.doc(`dogs/${dogId}/supplement_logs/${id}`);
}

async function timelineFor(
  sourceType: "meal" | "supplement",
  sourceId: string,
  targetDogId = dogId,
) {
  const sourceCollection = sourceCollectionPath(sourceType, targetDogId);
  const timelineId = deriveTimelineId({sourceCollection, sourceId});
  const ref = db.doc(timelineDocumentPath(targetDogId, timelineId));
  return {timelineId, ref, snapshot: await ref.get()};
}

async function nestedTimelineCount(
  sourceId: string,
  targetDogId = dogId,
): Promise<number> {
  const snap = await db.collection(`dogs/${targetDogId}/health_timeline`)
    .where("source_id", "==", sourceId)
    .get();
  return snap.size;
}

async function collectionCount(path: string): Promise<number> {
  return (await db.collection(path).get()).size;
}

async function deleteCollection(path: string): Promise<void> {
  const snap = await db.collection(path).get();
  if (snap.empty) return;
  const batch = db.batch();
  for (const doc of snap.docs) batch.delete(doc.ref);
  await batch.commit();
}

async function cleanupDog(targetDogId: string): Promise<void> {
  const names = [
    "meal_logs",
    "supplement_logs",
    "health_timeline",
    "feeding_events",
    "feedings",
    "nutrition_supplements",
    "nutritional_prescriptions",
    "nutrition_prescriptions",
  ];
  for (const name of names) {
    await deleteCollection(`dogs/${targetDogId}/${name}`);
  }
  await db.doc(`dogs/${targetDogId}`).delete().catch(() => undefined);
}

function assertTimestampFields(data: Record<string, unknown>): void {
  assert.ok(data.occurred_at instanceof Timestamp);
  assert.ok(data.recorded_at instanceof Timestamp);
  assert.ok(data.projected_at instanceof Timestamp);
}

function assertNoUndefined(value: unknown): void {
  if (!value || typeof value !== "object") return;
  for (const nested of Object.values(value as Record<string, unknown>)) {
    assert.notStrictEqual(nested, undefined);
    assertNoUndefined(nested);
  }
}

let passed = 0;

async function test(name: string, body: () => Promise<void>): Promise<void> {
  await body();
  passed++;
  console.log(`✅ ${name}`);
}

async function main(): Promise<void> {
  console.log("\n=== HEALTH TIMELINE TRIGGER FOUNDATION — EMULATOR ===");
  console.log(`Emulator: ${EMULATOR_HOST}`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Dog: ${dogId}\n`);

  await cleanupDog(dogId);
  await cleanupDog(otherDogId);

  const mealId = `meal_${runToken}`;
  const mealSource = mealRef(mealId);
  await mealSource.create(mealFixture());

  await test("A — MealLog CREATE uses nested deterministic path and Timestamps", async () => {
    const source = await mealSource.get();
    const result = await mealHandler({
      params: {dogId, mealId},
      snapshot: source,
    });
    assert.strictEqual(result.status, "projected");
    if (result.status !== "projected") return;
    assert.strictEqual(result.projection.operation, "created");
    const timeline = await timelineFor("meal", mealId);
    assert.strictEqual(timeline.snapshot.exists, true);
    assert.strictEqual(result.projection.timelineId, timeline.timelineId);
    assert.strictEqual(
      result.projection.destinationPath,
      `dogs/${dogId}/health_timeline/${timeline.timelineId}`,
    );
    assertTimestampFields(timeline.snapshot.data() ?? {});
  });

  const supplementId = `supp_${runToken}`;
  const supplementSource = supplementRef(supplementId);
  await supplementSource.create(supplementFixture());

  await test("B — SupplementLog CREATE uses the same runtime contract", async () => {
    const result = await supplementHandler({
      params: {dogId, supplementLogId: supplementId},
      snapshot: await supplementSource.get(),
    });
    assert.strictEqual(result.status, "projected");
    if (result.status !== "projected") return;
    assert.strictEqual(result.projection.operation, "created");
    const timeline = await timelineFor("supplement", supplementId);
    assert.strictEqual(timeline.snapshot.exists, true);
    assertTimestampFields(timeline.snapshot.data() ?? {});
  });

  await test("C — duplicate delivery creates once then remains no-op", async () => {
    const source = await mealSource.get();
    const first = await mealHandler({params: {dogId, mealId}, snapshot: source});
    const second = await mealHandler({params: {dogId, mealId}, snapshot: source});
    assert.strictEqual(first.status, "projected");
    assert.strictEqual(second.status, "projected");
    if (first.status !== "projected" || second.status !== "projected") return;
    assert.strictEqual(first.projection.operation, "noop");
    assert.strictEqual(second.projection.operation, "noop");
    assert.strictEqual(await nestedTimelineCount(mealId), 1);
  });

  const concurrentMealId = `meal_concurrent_${runToken}`;
  const concurrentSourceRef = mealRef(concurrentMealId);
  await concurrentSourceRef.create(mealFixture({
    recorded_at: Timestamp.fromDate(new Date("2026-07-23T08:02:00.000Z")),
  }));

  await test("D — concurrent delivery converges to one create and one no-op", async () => {
    const source = await concurrentSourceRef.get();
    const [left, right] = await Promise.all([
      mealHandler({
        params: {dogId, mealId: concurrentMealId},
        snapshot: source,
      }),
      mealHandler({
        params: {dogId, mealId: concurrentMealId},
        snapshot: source,
      }),
    ]);
    assert.strictEqual(left.status, "projected");
    assert.strictEqual(right.status, "projected");
    if (left.status !== "projected" || right.status !== "projected") return;
    assert.deepStrictEqual(
      [left.projection.operation, right.projection.operation].sort(),
      ["created", "noop"],
    );
    assert.strictEqual(await nestedTimelineCount(concurrentMealId), 1);
    const timeline = await timelineFor("meal", concurrentMealId);
    assert.ok(timeline.snapshot.createTime);
    assert.ok(timeline.snapshot.updateTime);
    assert.strictEqual(
      timeline.snapshot.createTime?.isEqual(timeline.snapshot.updateTime!),
      true,
      "Concurrent loser must not perform a second write.",
    );
  });

  await test("E — existing equivalent preserves projected_at and updateTime", async () => {
    const before = (await timelineFor("meal", mealId)).snapshot;
    const projectedBefore = before.get("projected_at") as Timestamp;
    const updateBefore = before.updateTime;
    const result = await mealHandler({
      params: {dogId, mealId},
      snapshot: await mealSource.get(),
    });
    assert.strictEqual(result.status, "projected");
    if (result.status !== "projected") return;
    assert.strictEqual(result.projection.operation, "noop");
    const after = (await timelineFor("meal", mealId)).snapshot;
    assert.strictEqual(
      (after.get("projected_at") as Timestamp).isEqual(projectedBefore),
      true,
    );
    assert.strictEqual(after.updateTime?.isEqual(updateBefore!), true);
  });

  await test("F — divergent entry is repaired transactionally with same ID", async () => {
    const before = await timelineFor("meal", mealId);
    const projectedBefore = before.snapshot.get("projected_at") as Timestamp;
    await before.ref.update({title: "CORRUPTED"});
    const result = await mealHandler({
      params: {dogId, mealId},
      snapshot: await mealSource.get(),
    });
    assert.strictEqual(result.status, "projected");
    if (result.status !== "projected") return;
    assert.strictEqual(result.projection.operation, "repaired");
    assert.strictEqual(result.projection.timelineId, before.timelineId);
    const after = await before.ref.get();
    assert.strictEqual(after.get("title"), "Ração Emulator");
    assert.strictEqual(
      (after.get("projected_at") as Timestamp).isEqual(projectedBefore),
      false,
    );
  });

  const malformedId = `meal_malformed_${runToken}`;
  const malformedRef = mealRef(malformedId);
  await malformedRef.create(mealFixture({fed_at: "not-an-instant"}));

  await test("G — malformed payload records anomaly and writes no timeline", async () => {
    const beforeAnomalies = anomalies.length;
    const result = await mealHandler({
      params: {dogId, mealId: malformedId},
      snapshot: await malformedRef.get(),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "invalid-timestamp",
    });
    assert.strictEqual(anomalies.length, beforeAnomalies + 1);
    assert.strictEqual((await timelineFor("meal", malformedId)).snapshot.exists, false);
  });

  await test("H — anomaly sink failure is propagated", async () => {
    const failingSink: HealthTimelineAnomalySink = {
      record: async () => {
        throw new Error("anomaly-sink-unavailable");
      },
    };
    const handler = makeMealLogCreatedHandler(dependencies(runtime, failingSink));
    await assert.rejects(
      async () => handler({
        params: {dogId, mealId: malformedId},
        snapshot: await malformedRef.get(),
      }),
      /anomaly-sink-unavailable/,
    );
  });

  await test("I — transient projector failure is thrown and not anomalized", async () => {
    const transientProjector: HealthTimelineProjector = {
      project: async () => {
        throw new Error("firestore-transient");
      },
    };
    const handler = makeMealLogCreatedHandler(
      dependencies(transientProjector),
    );
    const anomalyCount = anomalies.length;
    await assert.rejects(
      async () => handler({
        params: {dogId, mealId},
        snapshot: await mealSource.get(),
      }),
      /firestore-transient/,
    );
    assert.strictEqual(anomalies.length, anomalyCount);
  });

  await test("J — source documents remain byte-for-byte and updateTime identical", async () => {
    const beforeMeal = await mealSource.get();
    const beforeSupplement = await supplementSource.get();
    await mealHandler({
      params: {dogId, mealId},
      snapshot: beforeMeal,
    });
    await supplementHandler({
      params: {dogId, supplementLogId: supplementId},
      snapshot: beforeSupplement,
    });
    const afterMeal = await mealSource.get();
    const afterSupplement = await supplementSource.get();
    assert.deepStrictEqual(afterMeal.data(), beforeMeal.data());
    assert.deepStrictEqual(afterSupplement.data(), beforeSupplement.data());
    assert.strictEqual(
      afterMeal.updateTime?.isEqual(beforeMeal.updateTime!),
      true,
    );
    assert.strictEqual(
      afterSupplement.updateTime?.isEqual(beforeSupplement.updateTime!),
      true,
    );
  });

  await test("K — cross-dog/wrong path creates anomaly and no timeline in either dog", async () => {
    const anomalyCount = anomalies.length;
    const result = await mealHandler({
      params: {dogId: otherDogId, mealId},
      snapshot: await mealSource.get(),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "cross-dog-source",
    });
    assert.strictEqual(anomalies.length, anomalyCount + 1);
    assert.strictEqual(await nestedTimelineCount(mealId, otherDogId), 0);
    assert.strictEqual(await nestedTimelineCount(mealId, dogId), 1);
  });

  await test("L — persisted schema is exact allowlist with no undefined", async () => {
    const timeline = (await timelineFor("meal", mealId)).snapshot;
    const data = timeline.data() ?? {};
    assert.deepStrictEqual(
      Object.keys(data).sort(),
      [...canonicalTimelineKeys()].sort(),
    );
    assert.strictEqual("source_only_field" in data, false);
    assertNoUndefined(data);
    assertTimestampFields(data);
  });

  await test("M — zero writes to every legacy collection", async () => {
    const legacyCollections = [
      "feeding_events",
      "feedings",
      "nutrition_supplements",
      "nutritional_prescriptions",
      "nutrition_prescriptions",
    ];
    for (const name of legacyCollections) {
      assert.strictEqual(
        await collectionCount(`dogs/${dogId}/${name}`),
        0,
        `${name} must remain empty`,
      );
    }
  });

  console.log(`\n🎯 NEW EMULATOR TESTS PASSED (${passed}/${passed})`);
  console.log(`Anomalies recorded: ${anomalies.length}`);
  console.log(`Structured log events: ${loggerEvents.length}\n`);
}

main()
  .then(async () => {
    await cleanupDog(dogId);
    await cleanupDog(otherDogId);
    await deleteApp(app);
  })
  .catch(async (error) => {
    console.error(error);
    await cleanupDog(dogId).catch(() => undefined);
    await cleanupDog(otherDogId).catch(() => undefined);
    await deleteApp(app).catch(() => undefined);
    process.exitCode = 1;
  });
