import * as assert from "assert";
import {
  JsonMap,
  NutritionActor,
  NutritionEngineDeps,
  NutritionTxn,
  assertCanonicalFirestoreTimestampIso,
  assertSafePlainFirestoreRecord,
  parseLegacyNutritionPlanReceipt,
  pathNutritionOperation,
  pathNutritionPlan,
  runCancelNutritionPlan,
  runCreateAndActivateNutritionPlan,
  runUpdateActiveNutritionPlan,
} from "./health_nutrition_engine";
import {
  nutritionOperationReceiptIdV1,
  parseCreateAndActivateNutritionPlan,
} from "./health_nutrition_logic";

const actor: NutritionActor = {uid: "manager-1", email: "m@k9.local", ra: "10", name: "Gestor"};
const now = new Date("2026-07-19T15:00:00.000Z");

function adapterPlain(value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(adapterPlain);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, adapterPlain(item)]));
  }
  return value;
}

function createPayload(operationId: string, validFrom = "2026-07-19T14:00:00.000Z"): JsonMap {
  return {dogId: "dog-1", operationId, planData: {food_type: "Ração A", amount_grams_per_day: 300,
    meals_per_day: 1, timezone: "America/Sao_Paulo", valid_from: validFrom,
    meal_schedule: [{id: "meal-1", period: "morning", scheduled_time: "07:00", target_grams: 300}],
    supplements: [], special_instructions: "original"}};
}

function replacePayload(
  operationId: string,
  expectedActivePlanId: string,
  expectedActiveRevision: number,
  validFrom = "2026-07-19T14:00:00.000Z",
): JsonMap {
  return {
    ...createPayload(operationId, validFrom),
    expectedActivePlanId,
    expectedActiveRevision,
  };
}

function harness(initial: Record<string, JsonMap> = {}, logs: {meal?: JsonMap[]; supplement?: JsonMap[]} = {}) {
  const store = new Map<string, JsonMap>(Object.entries(initial).map(([k, v]) => [k, {...v}]));
  const writes: string[] = [];
  const outOfTransactionReads: string[] = [];
  const activePlanReads: string[] = [];
  const snap = (path: string) => ({
    exists: store.has(path),
    data: adapterPlain(store.get(path) ?? {}) as JsonMap,
  });
  const deps: NutritionEngineDeps = {
    serverNow: () => now,
    isAdmin: () => true,
    getDoc: async (path) => {outOfTransactionReads.push(path); return snap(path);},
    runTransaction: async <T>(fn: (tx: NutritionTxn) => Promise<T>) => fn({
      get: async (path) => snap(path),
      getActivePlans: async (dogId) => {
        activePlanReads.push(dogId);
        return [...store.entries()]
          .filter(([p, d]) => p.startsWith(`dogs/${dogId}/nutrition_plans/`) && d.status === "active")
          .map(([p, data]) => ({id: p.split("/").pop()!, data}));
      },
      getMealLogsInWindow: async () => (logs.meal ?? []).map((data, i) => ({id: `m${i}`, data})),
      getSupplementLogsInWindow: async () => (logs.supplement ?? []).map((data, i) => ({id: `s${i}`, data})),
      set: (path, data) => {writes.push(path); store.set(path, {...data});},
    }),
  };
  return {deps, store, writes, outOfTransactionReads, activePlanReads};
}

async function test(name: string, fn: () => Promise<void>) {
  await fn();
  console.log(`ok - ${name}`);
}

async function rejectsCode(fn: () => Promise<unknown>, code: string) {
  await assert.rejects(fn, (error: Error & {detailCode?: string}) => error.detailCode === code);
}

async function main() {
  await test("plan create: zero active + plan/receipt/audit", async () => {
    const h = harness();
    const r = await runCreateAndActivateNutritionPlan(actor, createPayload("create-1"), h.deps);
    assert.strictEqual(r.revision, 1);
    assert.strictEqual(r.supersededPlanId, null);
    assert.strictEqual([...h.store.values()].filter((d) => d.status === "active").length, 1);
    assert.strictEqual(h.writes.filter((p) => p.startsWith("auditLogs/")).length, 1);
    assert.strictEqual(h.writes.filter((p) => p.includes("/nutrition_operations/")).length, 1);
  });
  await test("plan create: active existing fails closed with zero writes", async () => {
    const oldPath = pathNutritionPlan("dog-1", "old");
    const recorded = {uid: "author", name: "Autor", internal_role: "condutor"};
    const h = harness({[oldPath]: {status: "active", revision: 4, valid_from: "2026-07-19T10:00:00.000Z",
      recorded_by: recorded, created_at: "kept", clinical_extension: {preserve: true}}});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, createPayload("create-2"), h.deps),
      "active-plan-conflict",
    );
    assert.strictEqual(h.writes.length, 0);
    assert.strictEqual(h.store.get(oldPath)?.status, "active");
  });
  await test("plan replace: exact ID/revision supersedes atomically with receipt and audit evidence", async () => {
    const oldPath = pathNutritionPlan("dog-1", "old");
    const recorded = {uid: "author", name: "Autor", internal_role: "condutor"};
    const h = harness({[oldPath]: {status: "active", revision: 4, valid_from: "2026-07-19T10:00:00.000Z",
      recorded_by: recorded, created_at: "kept", clinical_extension: {preserve: true}}});
    const r = await runCreateAndActivateNutritionPlan(
      actor,
      replacePayload("replace-2", "old", 4),
      h.deps,
    );
    assert.strictEqual(r.supersededPlanId, "old");
    assert.deepStrictEqual(h.store.get(oldPath)?.recorded_by, recorded);
    assert.deepStrictEqual(h.store.get(oldPath)?.clinical_extension, {preserve: true});
    assert.strictEqual(h.store.get(oldPath)?.revision, 5);
    assert.strictEqual(h.store.get(oldPath)?.superseded_by_plan_id, r.planId);
    assert.strictEqual(h.store.get(oldPath)?.superseded_at, now);
    assert.strictEqual((h.store.get(oldPath)?.valid_until as Date).toISOString(), "2026-07-19T14:00:00.000Z");
    assert.strictEqual(h.store.get(pathNutritionPlan("dog-1", r.planId))?.supersedes_plan_id, "old");
    const receipt = [...h.store.entries()].find(([p]) => p.includes("/nutrition_operations/"))?.[1];
    const receiptResult = receipt?.result as JsonMap;
    assert.strictEqual(receipt?.intent, "replace");
    assert.strictEqual(receipt?.receipt_schema_version, 2);
    assert.strictEqual(receipt?.fingerprint_version, 2);
    assert.strictEqual(receipt?.dog_id, "dog-1");
    assert.strictEqual(receipt?.new_plan_id, r.planId);
    assert.strictEqual(receipt?.entity_id, r.planId);
    assert.strictEqual(receipt?.created_at, now);
    assert.strictEqual(receipt?.expected_active_plan_id, "old");
    assert.strictEqual(receipt?.expected_active_revision, 4);
    assert.strictEqual(receipt?.replaced_plan_id, "old");
    assert.strictEqual(receiptResult.mode, "replace");
    assert.strictEqual(receiptResult.expectedActivePlanId, "old");
    assert.strictEqual(receiptResult.expectedActiveRevision, 4);
    const audit = [...h.store.entries()].find(([p]) => p.startsWith("auditLogs/"))?.[1];
    const metadata = audit?.metadata as JsonMap;
    assert.strictEqual(metadata.intent, "replace");
    assert.strictEqual(metadata.actor_uid, actor.uid);
    assert.strictEqual(metadata.dog_id, receipt?.dog_id);
    assert.strictEqual(metadata.fingerprint, receipt?.fingerprint);
    assert.strictEqual(metadata.fingerprint_version, receipt?.fingerprint_version);
    assert.strictEqual(metadata.expected_active_plan_id, "old");
    assert.strictEqual(metadata.expected_active_revision, 4);
    assert.strictEqual(metadata.replaced_plan_id, "old");
    assert.strictEqual(metadata.replaced_plan_revision, 4);
    assert.strictEqual(metadata.new_plan_id, r.planId);
    assert.strictEqual(metadata.new_plan_id, receipt?.new_plan_id);
    assert.strictEqual(metadata.previous_status, "active");
    assert.strictEqual(metadata.new_status, "active");
    assert.strictEqual(h.outOfTransactionReads.length, 0);
  });
  await test("plan replace: zero active fails closed", async () => {
    const h = harness();
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, replacePayload("replace-zero", "old", 4), h.deps),
      "active-plan-conflict",
    );
    assert.strictEqual(h.writes.length, 0);
  });
  await test("plan replace: expected ID mismatch fails closed", async () => {
    const oldPath = pathNutritionPlan("dog-1", "current");
    const h = harness({[oldPath]: {status: "active", revision: 4, valid_from: "2026-07-19T10:00:00.000Z"}});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, replacePayload("replace-id", "stale", 4), h.deps),
      "active-plan-conflict",
    );
    assert.strictEqual(h.writes.length, 0);
    assert.strictEqual(h.store.get(oldPath)?.status, "active");
  });
  await test("plan replace: expected revision mismatch fails closed", async () => {
    const oldPath = pathNutritionPlan("dog-1", "current");
    const h = harness({[oldPath]: {status: "active", revision: 5, valid_from: "2026-07-19T10:00:00.000Z"}});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, replacePayload("replace-revision", "current", 4), h.deps),
      "revision-conflict",
    );
    assert.strictEqual(h.writes.length, 0);
    assert.strictEqual(h.store.get(oldPath)?.revision, 5);
  });
  await test("plan replace: cancelled or superseded target fails closed", async () => {
    for (const status of ["cancelled", "superseded"]) {
      const h = harness({[pathNutritionPlan("dog-1", "old")]: {status, revision: 4}});
      await rejectsCode(
        () => runCreateAndActivateNutritionPlan(actor, replacePayload(`replace-${status}`, "old", 4), h.deps),
        "active-plan-conflict",
      );
      assert.strictEqual(h.writes.length, 0);
    }
  });
  await test("plan create: multiple active fails closed", async () => {
    const h = harness({[pathNutritionPlan("dog-1", "a")]: {status: "active"},
      [pathNutritionPlan("dog-1", "b")]: {status: "active"}});
    await rejectsCode(() => runCreateAndActivateNutritionPlan(actor, createPayload("create-3"), h.deps), "integrity-conflict");
    assert.strictEqual(h.writes.length, 0);
  });
  await test("retroactive create: MealLog blocks", async () => {
    const h = harness({}, {meal: [{fed_at: new Date(now.getTime() - 30_000).toISOString()}]});
    await rejectsCode(() => runCreateAndActivateNutritionPlan(actor, createPayload("retro-meal"), h.deps), "retroactive-plan-conflict");
  });
  await test("retroactive create: SupplementLog blocks", async () => {
    const h = harness({}, {supplement: [{administered_at: new Date(now.getTime() - 30_000).toISOString()}]});
    await rejectsCode(() => runCreateAndActivateNutritionPlan(actor, createPayload("retro-supp"), h.deps), "retroactive-plan-conflict");
  });
  await test("create replay: same result and zero writes", async () => {
    const h = harness();
    const first = await runCreateAndActivateNutritionPlan(actor, createPayload("replay"), h.deps);
    const count = h.writes.length;
    const second = await runCreateAndActivateNutritionPlan(actor, createPayload("replay"), h.deps);
    assert.strictEqual(second.planId, first.planId);
    assert.strictEqual(second.wasNoOp, true);
    assert.strictEqual(h.writes.length, count);
  });
  await test("create replay: changed payload conflicts", async () => {
    const h = harness();
    await runCreateAndActivateNutritionPlan(actor, createPayload("conflict"), h.deps);
    const changed = createPayload("conflict");
    (changed.planData as JsonMap).special_instructions = "changed";
    await rejectsCode(() => runCreateAndActivateNutritionPlan(actor, changed, h.deps), "idempotency-conflict");
  });
  await test("replace replay precedes current-state validation", async () => {
    const oldPath = pathNutritionPlan("dog-1", "old");
    const h = harness({[oldPath]: {status: "active", revision: 3, valid_from: "2026-07-19T10:00:00.000Z"}});
    const command = replacePayload("replace-replay", "old", 3);
    const first = await runCreateAndActivateNutritionPlan(actor, command, h.deps);
    const count = h.writes.length;
    const second = await runCreateAndActivateNutritionPlan(actor, command, h.deps);
    assert.strictEqual(second.planId, first.planId);
    assert.strictEqual(second.wasNoOp, true);
    assert.strictEqual(h.writes.length, count);
  });
  await test("replace replay: changed expected revision or ID conflicts", async () => {
    const oldPath = pathNutritionPlan("dog-1", "old");
    const h = harness({[oldPath]: {status: "active", revision: 3, valid_from: "2026-07-19T10:00:00.000Z"}});
    await runCreateAndActivateNutritionPlan(actor, replacePayload("replace-fingerprint", "old", 3), h.deps);
    const count = h.writes.length;
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(
        actor,
        replacePayload("replace-fingerprint", "old", 4),
        h.deps,
      ),
      "idempotency-conflict",
    );
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(
        actor,
        replacePayload("replace-fingerprint", "other", 3),
        h.deps,
      ),
      "idempotency-conflict",
    );
    assert.strictEqual(h.writes.length, count);
  });
  await test("create replay: semantic array reordering is compatible", async () => {
    const h = harness();
    const command = createPayload("reordered-replay");
    const planData = command.planData as JsonMap;
    planData.amount_grams_per_day = 300;
    planData.meals_per_day = 2;
    planData.meal_schedule = [
      {id: "am", period: "morning", scheduled_time: "07:00", target_grams: 150},
      {id: "pm", period: "evening", scheduled_time: "19:00", target_grams: 150},
    ];
    planData.supplements = [
      {id: "a", name: "A", dose: 1, unit: "tablet", frequency: "daily"},
      {id: "b", name: "B", dose: 2, unit: "tablet", frequency: "daily"},
    ];
    const first = await runCreateAndActivateNutritionPlan(actor, command, h.deps);
    const reordered = structuredClone(command);
    const reorderedData = reordered.planData as JsonMap;
    reorderedData.meal_schedule = [...(reorderedData.meal_schedule as JsonMap[])].reverse();
    reorderedData.supplements = [...(reorderedData.supplements as JsonMap[])].reverse();
    const second = await runCreateAndActivateNutritionPlan(actor, reordered, h.deps);
    assert.strictEqual(second.planId, first.planId);
    assert.strictEqual(second.wasNoOp, true);
    assert.strictEqual(h.writes.filter((path) => path.includes("/nutrition_operations/")).length, 1);
    assert.strictEqual(h.writes.filter((path) => path.startsWith("auditLogs/")).length, 1);
    assert.strictEqual(h.outOfTransactionReads.length, 0);
  });
  await test("legacy CREATE receipt is recognized but never authorizes replay", async () => {
    const command = createPayload("legacy-create");
    const parsed = parseCreateAndActivateNutritionPlan(command, now);
    const receiptId = nutritionOperationReceiptIdV1({
      actorUid: actor.uid,
      operationType: "create_nutrition_plan",
      operationId: parsed.operationId,
    });
    const receiptPath = pathNutritionOperation(parsed.dogId, receiptId);
    const legacyReceipt: JsonMap = {
      receipt_id: receiptId,
      operation_id: parsed.operationId,
      operation_type: "create_nutrition_plan",
      actor_uid: actor.uid,
      fingerprint: "a".repeat(64),
      entity_type: "nutrition_plan",
      entity_id: "legacy-plan",
      result: {success: true, planId: "legacy-plan", status: "active", revision: 1, supersededPlanId: null},
      processed_at: now.toISOString(),
    };
    const h = harness({[receiptPath]: legacyReceipt});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, command, h.deps),
      "legacy-receipt-replay-unsupported",
    );
    assert.strictEqual(h.writes.length, 0);
    assert.strictEqual(h.activePlanReads.length, 0);
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(
        actor,
        {...command, expectedActivePlanId: "legacy-plan", expectedActiveRevision: 1},
        h.deps,
      ),
      "receipt-integrity",
    );
    assert.strictEqual(h.writes.length, 0);

    const corruptions: Array<[string, (receipt: JsonMap) => void]> = [
      ["required missing", (receipt) => { delete receipt.receipt_id; }],
      ["actor missing", (receipt) => { delete receipt.actor_uid; }],
      ["unknown field", (receipt) => { receipt.suspicious_admin_override = true; }],
      ["known field wrong type", (receipt) => { receipt.actor_uid = 123; }],
      ["result inconsistent", (receipt) => { (receipt.result as JsonMap).status = "cancelled"; }],
      ["entity result mismatch", (receipt) => { (receipt.result as JsonMap).planId = "other-plan"; }],
      ["hybrid schema", (receipt) => { receipt.receipt_schema_version = 2; }],
      ["hybrid fingerprint", (receipt) => { receipt.fingerprint_version = 2; }],
      ["constructor field", (receipt) => { receipt["constructor"] = "unexpected"; }],
      ["prototype field", (receipt) => { receipt.prototype = "unexpected"; }],
      ["__proto__ field", (receipt) => {
        Object.defineProperty(receipt, "__proto__", {value: "unexpected", enumerable: true, configurable: true, writable: true});
      }],
    ];
    for (const [name, corrupt] of corruptions) {
      const corrupted = structuredClone(legacyReceipt);
      corrupt(corrupted);
      const probe = harness({[receiptPath]: corrupted});
      const before = structuredClone(probe.store.get(receiptPath));
      await rejectsCode(
        () => runCreateAndActivateNutritionPlan(actor, command, probe.deps),
        "receipt-integrity",
      );
      assert.strictEqual(probe.writes.length, 0, name);
      assert.deepStrictEqual(probe.store.get(receiptPath), before, name);
    }

    const changedFingerprint = structuredClone(legacyReceipt);
    changedFingerprint.fingerprint = "0".repeat(64);
    const conflict = harness({[receiptPath]: changedFingerprint});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, command, conflict.deps),
      "legacy-receipt-replay-unsupported",
    );
    assert.strictEqual(conflict.writes.length, 0);

    const unicodeReceipt = structuredClone(legacyReceipt);
    unicodeReceipt.entity_id = "plano-á-🐕";
    (unicodeReceipt.result as JsonMap).planId = "plano-á-🐕";
    const unicode = harness({[receiptPath]: unicodeReceipt});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, command, unicode.deps),
      "legacy-receipt-replay-unsupported",
    );
    assert.strictEqual(unicode.writes.length, 0);

    const invalidTimestamp = structuredClone(legacyReceipt);
    invalidTimestamp.processed_at = "+010000-01-01T00:00:00.000Z";
    const invalidTime = harness({[receiptPath]: invalidTimestamp});
    await rejectsCode(
      () => runCreateAndActivateNutritionPlan(actor, command, invalidTime.deps),
      "receipt-integrity",
    );
    assert.strictEqual(invalidTime.writes.length, 0);
  });

  await test("receipt timestamps and hostile object shapes fail closed", async () => {
    const validTimes = ["0001-01-01T00:00:00.000Z", "9999-12-31T23:59:59.999Z"];
    for (const value of validTimes) assert.doesNotThrow(() => assertCanonicalFirestoreTimestampIso(value));
    const invalidTimes: unknown[] = [
      "", "2026-01-01T00:00:00", "2026-01-01T00:00:00Z",
      "2026-01-01T00:00:00.000-03:00", "2026-01-01T00:00:00.000+00:00",
      "2026-13-01T00:00:00.000Z", "2026-02-30T00:00:00.000Z",
      "0000-01-01T00:00:00.000Z", "+010000-01-01T00:00:00.000Z",
      "-000001-01-01T00:00:00.000Z", " 2026-01-01T00:00:00.000Z ",
      "0", "1700000000000", null, 0, new Date(), {}, [],
    ];
    for (const value of invalidTimes) {
      assert.throws(
        () => assertCanonicalFirestoreTimestampIso(value),
        (error: Error & {detailCode?: string}) => error.detailCode === "receipt-integrity",
      );
    }

    const hostile: unknown[] = [Object.create(null), Object.create({custom: true})];
    const nonEnumerable = {};
    Object.defineProperty(nonEnumerable, "hidden", {value: true, enumerable: false});
    hostile.push(nonEnumerable, {[Symbol("receipt")]: true});
    const throwingGetter = {};
    Object.defineProperty(throwingGetter, "boom", {enumerable: true, get: () => { throw new Error("getter-boom"); }});
    hostile.push(throwingGetter, new Proxy({}, {ownKeys: () => { throw new Error("ownKeys-boom"); }}));
    hostile.push(new Proxy({field: true}, {getOwnPropertyDescriptor: () => { throw new Error("descriptor-boom"); }}));
    const setterOnly = {};
    Object.defineProperty(setterOnly, "field", {enumerable: true, set: () => undefined});
    const readOnlyDescriptor = {};
    Object.defineProperty(readOnlyDescriptor, "field", {value: true, enumerable: true, configurable: true, writable: false});
    hostile.push(setterOnly, readOnlyDescriptor);
    for (const value of hostile) {
      assert.throws(
        () => assertSafePlainFirestoreRecord(value),
        (error: Error & {detailCode?: string}) =>
          error.detailCode === "receipt-integrity" && !error.message.includes("boom"),
      );
    }

    const command = createPayload("hostile-parser");
    const parsed = parseCreateAndActivateNutritionPlan(command, now);
    const context = {
      receiptId: "receipt", operationId: parsed.operationId,
      operationType: "create_nutrition_plan" as const, actorUid: actor.uid,
      dogId: parsed.dogId, intent: "create" as const,
      expectedActivePlanId: null, expectedActiveRevision: null,
    };
    assert.throws(
      () => parseLegacyNutritionPlanReceipt(new Proxy({}, {ownKeys: () => { throw new Error("raw-proxy"); }}) as JsonMap, context),
      (error: Error & {detailCode?: string}) => error.detailCode === "receipt-integrity",
    );
  });

  await test("receipt timestamp canonical Firestore boundaries are accepted", async () => {
    assert.doesNotThrow(() => assertCanonicalFirestoreTimestampIso("0001-01-01T00:00:00.000Z"));
    assert.doesNotThrow(() => assertCanonicalFirestoreTimestampIso("9999-12-31T23:59:59.999Z"));
  });

  await test("receipt timestamp expanded and zero years are rejected", async () => {
    for (const value of [
      "0000-01-01T00:00:00.000Z",
      "+010000-01-01T00:00:00.000Z",
      "-000001-01-01T00:00:00.000Z",
    ]) {
      assert.throws(() => assertCanonicalFirestoreTimestampIso(value));
    }
  });

  await test("receipt timestamp offsets and missing milliseconds are rejected", async () => {
    for (const value of [
      "2026-01-01T00:00:00.000-03:00",
      "2026-01-01T00:00:00.000+00:00",
      "2026-01-01T00:00:00Z",
    ]) {
      assert.throws(() => assertCanonicalFirestoreTimestampIso(value));
    }
  });

  await test("safe receipt record accepts only ordinary mutable data properties", async () => {
    assert.doesNotThrow(() => assertSafePlainFirestoreRecord({field: true}));
    assert.throws(() => assertSafePlainFirestoreRecord(Object.freeze({field: true})));
  });

  await test("safe receipt record rejects symbol and non-enumerable properties", async () => {
    const hidden = {};
    Object.defineProperty(hidden, "field", {value: true, enumerable: false});
    assert.throws(() => assertSafePlainFirestoreRecord(hidden));
    assert.throws(() => assertSafePlainFirestoreRecord({[Symbol("field")]: true}));
  });

  await test("safe receipt record sanitizes Proxy inspection failures", async () => {
    for (const value of [
      new Proxy({}, {ownKeys: () => { throw new Error("private-ownKeys"); }}),
      new Proxy({field: true}, {getOwnPropertyDescriptor: () => { throw new Error("private-descriptor"); }}),
    ]) {
      assert.throws(
        () => assertSafePlainFirestoreRecord(value),
        (error: Error & {detailCode?: string}) =>
          error.detailCode === "receipt-integrity" && !error.message.includes("private"),
      );
    }
  });
  await test("v2 receipt versions, shape and internal parity fail closed", async () => {
    const command = createPayload("v2-corruption");
    const source = harness();
    const created = await runCreateAndActivateNutritionPlan(actor, command, source.deps);
    const entry = [...source.store.entries()].find(([path]) => path.includes("/nutrition_operations/"));
    assert.ok(entry);
    const [receiptPath, validReceipt] = entry!;
    const validReplay = harness({[receiptPath]: structuredClone(validReceipt)});
    const replay = await runCreateAndActivateNutritionPlan(actor, command, validReplay.deps);
    assert.strictEqual(replay.planId, created.planId);
    assert.strictEqual(replay.wasNoOp, true);
    assert.strictEqual(validReplay.writes.length, 0);

    const invalidVersions: unknown[] = [undefined, null, "2", 0, -1, 1, 3, 999, 2.5, NaN, Infinity, {}, []];
    const corruptions: Array<[string, (receipt: JsonMap) => void]> = invalidVersions.map((version, index) => [
      `schema version ${index}`,
      (receipt: JsonMap) => {
        if (version === undefined) delete receipt.receipt_schema_version;
        else receipt.receipt_schema_version = version;
      },
    ]);
    corruptions.push(
      ["fingerprint version missing", (receipt) => { delete receipt.fingerprint_version; }],
      ["fingerprint version string", (receipt) => { receipt.fingerprint_version = "2"; }],
      ["fingerprint version unknown", (receipt) => { receipt.fingerprint_version = 999; }],
      ["dog mismatch", (receipt) => { receipt.dog_id = "other-dog"; }],
      ["operation mismatch", (receipt) => { receipt.operation_id = "other-operation"; }],
      ["intent mismatch", (receipt) => { receipt.intent = "replace"; }],
      ["expected ID mismatch", (receipt) => { receipt.expected_active_plan_id = "old"; }],
      ["expected revision mismatch", (receipt) => { receipt.expected_active_revision = 1; }],
      ["replaced mismatch", (receipt) => { receipt.replaced_plan_id = "old"; }],
      ["new entity mismatch", (receipt) => { receipt.new_plan_id = "other-plan"; }],
      ["new result mismatch", (receipt) => { (receipt.result as JsonMap).planId = "other-plan"; }],
      ["result plan missing", (receipt) => { delete (receipt.result as JsonMap).planId; }],
      ["result revision invalid", (receipt) => { (receipt.result as JsonMap).revision = 0; }],
      ["required missing", (receipt) => { delete receipt.created_at; }],
      ["timestamp extended year", (receipt) => { receipt.processed_at = "+010000-01-01T00:00:00.000Z"; }],
      ["timestamp offset", (receipt) => { receipt.created_at = "2026-07-19T12:00:00.000-03:00"; }],
      ["timestamp no milliseconds", (receipt) => { receipt.processed_at = "2026-07-19T15:00:00Z"; }],
      ["unknown field", (receipt) => { receipt.suspicious = true; }],
      ["result unknown field", (receipt) => { (receipt.result as JsonMap).suspicious = true; }],
    );
    for (const [name, corrupt] of corruptions) {
      const corrupted = structuredClone(validReceipt);
      corrupt(corrupted);
      const probe = harness({[receiptPath]: corrupted});
      const before = structuredClone(probe.store.get(receiptPath));
      await rejectsCode(
        () => runCreateAndActivateNutritionPlan(actor, command, probe.deps),
        "receipt-integrity",
      );
      assert.strictEqual(probe.writes.length, 0, name);
      assert.deepStrictEqual(probe.store.get(receiptPath), before, name);
    }
  });
  await test("update: admin-only patch, revision and authorship", async () => {
    const path = pathNutritionPlan("dog-1", "p1");
    const recorded = {uid: "original", name: "Original", internal_role: "admin"};
    const h = harness({[path]: {status: "active", revision: 2, valid_from: "2026-07-19T10:00:00.000Z",
      food_type: "keep", professional: {name: "keep"}, recorded_by: recorded, created_at: "keep"}});
    const r = await runUpdateActiveNutritionPlan(actor, {dogId: "dog-1", planId: "p1", operationId: "u1",
      expectedRevision: 2, planData: {special_instructions: "new"}}, h.deps);
    assert.strictEqual(r.revision, 3);
    assert.strictEqual(h.store.get(path)?.food_type, "keep");
    assert.deepStrictEqual(h.store.get(path)?.professional, {name: "keep"});
    assert.deepStrictEqual(h.store.get(path)?.recorded_by, recorded);
  });
  await test("update: stale revision rejected", async () => {
    const path = pathNutritionPlan("dog-1", "p1");
    const h = harness({[path]: {status: "active", revision: 2}});
    await rejectsCode(() => runUpdateActiveNutritionPlan(actor, {dogId: "dog-1", planId: "p1", operationId: "u2",
      expectedRevision: 1, planData: {special_instructions: "x"}}, h.deps), "revision-conflict");
  });
  await test("cancel: terminal zero-active, reason audited, author preserved", async () => {
    const path = pathNutritionPlan("dog-1", "p1");
    const recorded = {uid: "original", name: "Original", internal_role: "admin"};
    const h = harness({[path]: {status: "active", revision: 7, recorded_by: recorded, created_at: "keep"}});
    const r = await runCancelNutritionPlan(actor, {dogId: "dog-1", planId: "p1", operationId: "c1",
      expectedRevision: 7, reason: "Mudança clínica"}, h.deps);
    assert.strictEqual(r.revision, 8);
    assert.strictEqual(h.store.get(path)?.status, "cancelled");
    assert.deepStrictEqual(h.store.get(path)?.recorded_by, recorded);
    const audit = [...h.store.entries()].find(([p]) => p.startsWith("auditLogs/"))?.[1];
    assert.strictEqual((audit?.metadata as JsonMap).reason, "Mudança clínica");
  });
  console.log("health_nutrition_plan_engine_test: all passed");
}

void main().catch((error) => {console.error(error); process.exitCode = 1;});
