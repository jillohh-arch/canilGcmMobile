import * as assert from "assert";
import {
  JsonMap,
  NutritionActor,
  NutritionEngineDeps,
  NutritionTxn,
  pathNutritionPlan,
  runCancelNutritionPlan,
  runCreateAndActivateNutritionPlan,
  runUpdateActiveNutritionPlan,
} from "./health_nutrition_engine";

const actor: NutritionActor = {uid: "manager-1", email: "m@k9.local", ra: "10", name: "Gestor"};
const now = new Date("2026-07-19T15:00:00.000Z");

function createPayload(operationId: string, validFrom = "2026-07-19T14:00:00.000Z"): JsonMap {
  return {dogId: "dog-1", operationId, planData: {food_type: "Ração A", amount_grams_per_day: 300,
    meals_per_day: 1, timezone: "America/Sao_Paulo", valid_from: validFrom,
    meal_schedule: [{id: "meal-1", period: "morning", scheduled_time: "07:00", target_grams: 300}],
    supplements: [], special_instructions: "original"}};
}

function harness(initial: Record<string, JsonMap> = {}, logs: {meal?: JsonMap[]; supplement?: JsonMap[]} = {}) {
  const store = new Map<string, JsonMap>(Object.entries(initial).map(([k, v]) => [k, {...v}]));
  const writes: string[] = [];
  const snap = (path: string) => ({exists: store.has(path), data: store.get(path) ?? {}});
  const deps: NutritionEngineDeps = {
    serverNow: () => now,
    isAdmin: () => true,
    getDoc: async (path) => snap(path),
    runTransaction: async <T>(fn: (tx: NutritionTxn) => Promise<T>) => fn({
      get: async (path) => snap(path),
      getActivePlans: async (dogId) => [...store.entries()]
        .filter(([p, d]) => p.startsWith(`dogs/${dogId}/nutrition_plans/`) && d.status === "active")
        .map(([p, data]) => ({id: p.split("/").pop()!, data})),
      getMealLogsInWindow: async () => (logs.meal ?? []).map((data, i) => ({id: `m${i}`, data})),
      getSupplementLogsInWindow: async () => (logs.supplement ?? []).map((data, i) => ({id: `s${i}`, data})),
      set: (path, data) => {writes.push(path); store.set(path, {...data});},
    }),
  };
  return {deps, store, writes};
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
  await test("plan create: supersedes active preserving author and boundary", async () => {
    const oldPath = pathNutritionPlan("dog-1", "old");
    const recorded = {uid: "author", name: "Autor", internal_role: "condutor"};
    const h = harness({[oldPath]: {status: "active", revision: 4, valid_from: "2026-07-19T10:00:00.000Z",
      recorded_by: recorded, created_at: "kept"}});
    const r = await runCreateAndActivateNutritionPlan(actor, createPayload("create-2"), h.deps);
    assert.strictEqual(r.supersededPlanId, "old");
    assert.deepStrictEqual(h.store.get(oldPath)?.recorded_by, recorded);
    assert.strictEqual(h.store.get(oldPath)?.revision, 5);
    assert.strictEqual((h.store.get(oldPath)?.valid_until as Date).toISOString(), "2026-07-19T14:00:00.000Z");
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
