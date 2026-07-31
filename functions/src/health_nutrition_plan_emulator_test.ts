import * as assert from "assert";
import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  NutritionActor,
  runCancelNutritionPlan,
  runCreateAndActivateNutritionPlan,
  runUpdateActiveNutritionPlan,
} from "./health_nutrition_engine";
import {createNutritionFirestoreEngineDeps} from "./health_nutrition_firestore_adapter";
import {
  buildCanonicalNutritionPlanOperationFingerprint,
  nutritionOperationReceiptIdV1,
  parseCreateAndActivateNutritionPlan,
} from "./health_nutrition_logic";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.log("skip - FIRESTORE_EMULATOR_HOST not set");
  process.exit(0);
}
if (!getApps().length) initializeApp({projectId: process.env.GCLOUD_PROJECT ?? "canil-gcm"});
const db = getFirestore();
const actor: NutritionActor = {uid: "plan-manager", email: "manager@local", ra: "1", name: "Gestor"};
const base = Date.now();
const logicalNow = new Date(base - 60_000);
const deps = createNutritionFirestoreEngineDeps(db, {serverNow: () => logicalNow, isAdmin: () => true});
const dogId = `gate2-plan-${base}`;
const dog = db.collection("dogs").doc(dogId);

function payload(operationId: string, offsetMs = -120_000) {
  return {dogId, operationId, planData: {food_type: "Ração", amount_grams_per_day: 400,
    meals_per_day: 2, timezone: "Etc/UTC", valid_from: new Date(logicalNow.getTime() + offsetMs).toISOString(),
    meal_schedule: [{id: "am", period: "morning", scheduled_time: "07:00", target_grams: 200},
      {id: "pm", period: "evening", scheduled_time: "19:00", target_grams: 200}], supplements: []}};
}
function replacePayload(operationId: string, planId: string, revision: number, offsetMs = -60_000) {
  return {...payload(operationId, offsetMs), expectedActivePlanId: planId, expectedActiveRevision: revision};
}

async function test(name: string, fn: () => Promise<void>) {
  await fn();
  console.log(`ok - emulator ${name}`);
}
async function active() {
  return dog.collection("nutrition_plans").where("status", "==", "active").get();
}
async function audits() {
  return db.collection("auditLogs").where("metadata.dog_id", "==", dogId).get();
}
async function clearDog() {
  await db.recursiveDelete(dog);
  const a = await audits();
  await Promise.all(a.docs.map((d) => d.ref.delete()));
}
async function rejectsOne(promises: Promise<unknown>[]) {
  const settled = await Promise.allSettled(promises);
  assert.strictEqual(settled.filter((r) => r.status === "fulfilled").length, 1);
  assert.strictEqual(settled.filter((r) => r.status === "rejected").length, 1);
}

function twoPartyBarrier(operationIds: string[]) {
  const expected = new Set(operationIds);
  const arrived = new Set<string>();
  let released = false;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {release = resolve;});
  return async (event: {phase: "before-transaction"; operationId: string}) => {
    if (released || !expected.has(event.operationId)) return;
    arrived.add(event.operationId);
    if (arrived.size === expected.size) {
      released = true;
      release();
    }
    await gate;
  };
}

function assertOneSuccessOneConflict(settled: PromiseSettledResult<unknown>[], detailCode: string) {
  assert.strictEqual(settled.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = settled.filter((result): result is PromiseRejectedResult => result.status === "rejected");
  assert.strictEqual(rejected.length, 1);
  assert.strictEqual((rejected[0].reason as {detailCode?: string}).detailCode, detailCode);
}

async function main() {
  await test("create zero active is atomic", async () => {
    await clearDog();
    const r = await runCreateAndActivateNutritionPlan(actor, payload("create-zero"), deps);
    assert.strictEqual((await active()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, 1);
    assert.strictEqual((await audits()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_plans").doc(r.planId).get()).data()?.revision, 1);
  });
  await test("replace exact active ID/revision", async () => {
    const current = (await active()).docs[0];
    const r = await runCreateAndActivateNutritionPlan(
      actor,
      replacePayload("supersede", current.id, current.data().revision),
      deps,
    );
    assert.strictEqual(r.supersededPlanId, current.id);
    const old = (await current.ref.get()).data()!;
    assert.strictEqual(old.status, "superseded");
    assert.ok(old.valid_until instanceof Timestamp);
    assert.ok(old.superseded_at instanceof Timestamp);
    assert.strictEqual(old.superseded_by_plan_id, r.planId);
    assert.strictEqual(
      (await dog.collection("nutrition_plans").doc(r.planId).get()).data()?.supersedes_plan_id,
      current.id,
    );
    assert.strictEqual((await active()).size, 1);
  });
  await test("multiple active fails closed", async () => {
    await dog.collection("nutrition_plans").doc("corrupt-active").set({status: "active", revision: 1,
      valid_from: Timestamp.fromDate(new Date(logicalNow.getTime() - 300_000))});
    await assert.rejects(() => runCreateAndActivateNutritionPlan(actor, payload("multi-active", -30_000), deps));
    assert.strictEqual((await active()).size, 2);
    await dog.collection("nutrition_plans").doc("corrupt-active").delete();
  });
  await test("replay and idempotency conflict", async () => {
    await clearDog();
    const command = payload("replay");
    const a = await runCreateAndActivateNutritionPlan(actor, command, deps);
    const auditCount = (await audits()).size;
    const b = await runCreateAndActivateNutritionPlan(actor, command, deps);
    assert.strictEqual(b.planId, a.planId);
    assert.strictEqual(b.wasNoOp, true);
    assert.strictEqual((await audits()).size, auditCount);
    const changed = payload("replay");
    changed.planData.food_type = "Outra";
    await assert.rejects(() => runCreateAndActivateNutritionPlan(actor, changed, deps));
  });
  await test("seeded legacy/v2 receipt corruption fails closed with zero writes", async () => {
    const command = payload("receipt-corruption", -120_000);
    const parsed = parseCreateAndActivateNutritionPlan(command, logicalNow);
    const receiptId = nutritionOperationReceiptIdV1({
      actorUid: actor.uid,
      operationType: "create_nutrition_plan",
      operationId: parsed.operationId,
    });
    const receiptRef = dog.collection("nutrition_operations").doc(receiptId);
    const result = {
      success: true,
      planId: "seeded-plan",
      status: "active",
      revision: 1,
      mode: "create",
      supersededPlanId: null,
      expectedActivePlanId: null,
      expectedActiveRevision: null,
    };
    const v2Receipt: Record<string, unknown> = {
      receipt_schema_version: 2,
      fingerprint_version: 2,
      receipt_id: receiptId,
      operation_id: parsed.operationId,
      operation_type: "create_nutrition_plan",
      actor_uid: actor.uid,
      dog_id: dogId,
      fingerprint: buildCanonicalNutritionPlanOperationFingerprint(parsed),
      entity_type: "nutrition_plan",
      entity_id: "seeded-plan",
      new_plan_id: "seeded-plan",
      intent: "create",
      expected_active_plan_id: null,
      expected_active_revision: null,
      replaced_plan_id: null,
      result,
      processed_at: Timestamp.fromDate(logicalNow),
      created_at: Timestamp.fromDate(logicalNow),
    };
    const legacyReceipt: Record<string, unknown> = {
      receipt_id: receiptId,
      operation_id: parsed.operationId,
      operation_type: "create_nutrition_plan",
      actor_uid: actor.uid,
      fingerprint: "a".repeat(64),
      entity_type: "nutrition_plan",
      entity_id: "seeded-plan",
      result: {success: true, planId: "seeded-plan", status: "active", revision: 1, supersededPlanId: null},
      processed_at: Timestamp.fromDate(logicalNow),
    };

    await clearDog();
    await receiptRef.set(v2Receipt);
    const replay = await runCreateAndActivateNutritionPlan(actor, command, deps);
    assert.strictEqual(replay.planId, "seeded-plan");
    assert.strictEqual(replay.wasNoOp, true);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 0);
    assert.strictEqual((await audits()).size, 0);

    for (const validLegacy of [
      legacyReceipt,
      {
        ...legacyReceipt,
        fingerprint: "f".repeat(64),
        entity_id: "plano-á-🐕",
        result: {...legacyReceipt.result as Record<string, unknown>, planId: "plano-á-🐕"},
      },
    ]) {
      await clearDog();
      await receiptRef.set(validLegacy);
      const before = (await receiptRef.get()).data();
      await assert.rejects(
        () => runCreateAndActivateNutritionPlan(actor, command, deps),
        (error: Error & {detailCode?: string}) =>
          error.detailCode === "legacy-receipt-replay-unsupported",
      );
      assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 0);
      assert.strictEqual((await audits()).size, 0);
      assert.deepStrictEqual((await receiptRef.get()).data(), before);
    }

    const corruptions: Array<[string, Record<string, unknown>]> = [
      ["legacy-extra", {...legacyReceipt, suspicious: true}],
      ["legacy-missing", Object.fromEntries(Object.entries(legacyReceipt).filter(([key]) => key !== "actor_uid"))],
      ["legacy-result-diverge", {...legacyReceipt, result: {...legacyReceipt.result as Record<string, unknown>, planId: "other"}}],
      ["legacy-hybrid", {...legacyReceipt, receipt_schema_version: 2}],
      ["legacy-timestamp", {...legacyReceipt, processed_at: "+010000-01-01T00:00:00.000Z"}],
      ["schema-999", {...v2Receipt, receipt_schema_version: 999}],
      ["schema-string", {...v2Receipt, receipt_schema_version: "2"}],
      ["schema-zero", {...v2Receipt, receipt_schema_version: 0}],
      ["fingerprint-version", {...v2Receipt, fingerprint_version: 999}],
      ["ids-diverge", {...v2Receipt, new_plan_id: "other-plan"}],
      ["dog-diverge", {...v2Receipt, dog_id: "other-dog"}],
      ["operation-diverge", {...v2Receipt, operation_id: "other-operation"}],
      ["intent-diverge", {...v2Receipt, intent: "replace"}],
      ["timestamp-extended", {...v2Receipt, processed_at: "+010000-01-01T00:00:00.000Z"}],
      ["timestamp-offset", {...v2Receipt, created_at: "2026-07-19T12:00:00.000-03:00"}],
      ["timestamp-no-ms", {...v2Receipt, processed_at: "2026-07-19T15:00:00Z"}],
      ["v2-extra", {...v2Receipt, suspicious: true}],
    ];
    for (const [name, corrupted] of corruptions) {
      await clearDog();
      await receiptRef.set(corrupted);
      const before = (await receiptRef.get()).data();
      await assert.rejects(
        () => runCreateAndActivateNutritionPlan(actor, command, deps),
        (error: Error & {detailCode?: string}) => error.detailCode === "receipt-integrity",
        name,
      );
      assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 0, name);
      assert.strictEqual((await dog.collection("nutrition_operations").get()).size, 1, name);
      assert.strictEqual((await audits()).size, 0, name);
      assert.deepStrictEqual((await receiptRef.get()).data(), before, name);
    }
  });
  await test("legacy CREATE fingerprint is not evaluated for operational replay", async () => {
    await clearDog();
    const command = payload("legacy-policy-independent-fingerprint", -120_000);
    const parsed = parseCreateAndActivateNutritionPlan(command, logicalNow);
    const receiptId = nutritionOperationReceiptIdV1({
      actorUid: actor.uid,
      operationType: "create_nutrition_plan",
      operationId: parsed.operationId,
    });
    const receiptRef = dog.collection("nutrition_operations").doc(receiptId);
    await receiptRef.set({
      receipt_id: receiptId,
      operation_id: parsed.operationId,
      operation_type: "create_nutrition_plan",
      actor_uid: actor.uid,
      fingerprint: "0".repeat(64),
      entity_type: "nutrition_plan",
      entity_id: "legacy-policy-plan",
      result: {
        success: true,
        planId: "legacy-policy-plan",
        status: "active",
        revision: 1,
        supersededPlanId: null,
      },
      processed_at: Timestamp.fromDate(logicalNow),
    });
    const before = (await receiptRef.get()).data();
    await assert.rejects(
      () => runCreateAndActivateNutritionPlan(actor, command, deps),
      (error: Error & {detailCode?: string}) =>
        error.detailCode === "legacy-receipt-replay-unsupported",
    );
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 0);
    assert.strictEqual((await audits()).size, 0);
    assert.deepStrictEqual((await receiptRef.get()).data(), before);
  });
  await test("two concurrent creates serialize", async () => {
    await clearDog();
    const settled = await Promise.allSettled([
      runCreateAndActivateNutritionPlan(actor, payload("cc-a", -180_000), deps),
      runCreateAndActivateNutritionPlan(actor, payload("cc-b", -120_000), deps),
    ]);
    assert.ok(settled.some((r) => r.status === "fulfilled"));
    assert.strictEqual((await active()).size, 1);
    assert.ok((await dog.collection("nutrition_plans").get()).size >= 1);
  });
  await test("stale replace after UPDATE produces zero writes", async () => {
    await clearDog();
    const seeded = await runCreateAndActivateNutritionPlan(actor, payload("seed-update", -240_000), deps);
    await runUpdateActiveNutritionPlan(actor, {dogId, planId: seeded.planId, operationId: "advance-update",
      expectedRevision: 1, planData: {special_instructions: "revision 2"}}, deps);
    const plansBefore = (await dog.collection("nutrition_plans").get()).size;
    const receiptsBefore = (await dog.collection("nutrition_operations").get()).size;
    const auditsBefore = (await audits()).size;
    await assert.rejects(
      () => runCreateAndActivateNutritionPlan(
        actor,
        replacePayload("stale-update", seeded.planId, 1),
        deps,
      ),
      (error: Error & {detailCode?: string}) => error.detailCode === "revision-conflict",
    );
    assert.strictEqual((await active()).docs[0].data().revision, 2);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, plansBefore);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, receiptsBefore);
    assert.strictEqual((await audits()).size, auditsBefore);
  });
  await test("stale replace after REPLACE produces zero writes", async () => {
    await clearDog();
    const a = await runCreateAndActivateNutritionPlan(actor, payload("seed-replace", -240_000), deps);
    const b = await runCreateAndActivateNutritionPlan(
      actor,
      replacePayload("winner-replace", a.planId, 1, -120_000),
      deps,
    );
    const plansBefore = (await dog.collection("nutrition_plans").get()).size;
    const receiptsBefore = (await dog.collection("nutrition_operations").get()).size;
    const auditsBefore = (await audits()).size;
    await assert.rejects(
      () => runCreateAndActivateNutritionPlan(
        actor,
        replacePayload("stale-replace", a.planId, 1),
        deps,
      ),
      (error: Error & {detailCode?: string}) => error.detailCode === "active-plan-conflict",
    );
    assert.strictEqual((await active()).docs[0].id, b.planId);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, plansBefore);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, receiptsBefore);
    assert.strictEqual((await audits()).size, auditsBefore);
  });
  await test("stale replace after CANCEL produces zero writes", async () => {
    await clearDog();
    const a = await runCreateAndActivateNutritionPlan(actor, payload("seed-cancel", -240_000), deps);
    await runCancelNutritionPlan(actor, {dogId, planId: a.planId, operationId: "winner-cancel",
      expectedRevision: 1, reason: "concorrência"}, deps);
    const plansBefore = (await dog.collection("nutrition_plans").get()).size;
    const receiptsBefore = (await dog.collection("nutrition_operations").get()).size;
    const auditsBefore = (await audits()).size;
    await assert.rejects(
      () => runCreateAndActivateNutritionPlan(
        actor,
        replacePayload("stale-cancel", a.planId, 1),
        deps,
      ),
      (error: Error & {detailCode?: string}) => error.detailCode === "active-plan-conflict",
    );
    assert.strictEqual((await active()).size, 0);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, plansBefore);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, receiptsBefore);
    assert.strictEqual((await audits()).size, auditsBefore);
  });
  await test("two deterministic replacements of A/3: exactly one wins in 10 iterations", async () => {
    for (let iteration = 1; iteration <= 10; iteration++) {
      await clearDog();
      const seed = await runCreateAndActivateNutritionPlan(actor, payload(`seed-r3-${iteration}`, -240_000), deps);
      await runUpdateActiveNutritionPlan(actor, {dogId, planId: seed.planId, operationId: `to-r2-${iteration}`,
        expectedRevision: 1, planData: {special_instructions: "revision 2"}}, deps);
      await runUpdateActiveNutritionPlan(actor, {dogId, planId: seed.planId, operationId: `to-r3-${iteration}`,
        expectedRevision: 2, planData: {special_instructions: "revision 3"}}, deps);
      const operationIds = [`replace-a-${iteration}`, `replace-b-${iteration}`];
      const observedA3 = new Set<string>();
      const controlledDeps = createNutritionFirestoreEngineDeps(db, {
        serverNow: () => logicalNow,
        isAdmin: () => true,
        onPlanTransactionPhase: twoPartyBarrier(operationIds),
        onPlanActiveSnapshot: (event) => {
          if (event.active.length === 1 && event.active[0].id === seed.planId && event.active[0].revision === 3) {
            observedA3.add(event.operationId);
          }
        },
      });
      const receiptsBefore = (await dog.collection("nutrition_operations").get()).size;
      const auditsBefore = (await audits()).size;
      const settled = await Promise.allSettled([
        runCreateAndActivateNutritionPlan(actor, replacePayload(operationIds[0], seed.planId, 3, -120_000), controlledDeps),
        runCreateAndActivateNutritionPlan(actor, replacePayload(operationIds[1], seed.planId, 3, -60_000), controlledDeps),
      ]);
      assertOneSuccessOneConflict(settled, "active-plan-conflict");
      assert.deepStrictEqual([...observedA3].sort(), [...operationIds].sort());
      assert.strictEqual((await active()).size, 1);
      assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 2);
      assert.strictEqual((await dog.collection("nutrition_operations").get()).size, receiptsBefore + 1);
      assert.strictEqual((await audits()).size, auditsBefore + 1);
    }
  });
  await test("same operationId + same payload concurrent: one mutation and identical replay", async () => {
    await clearDog();
    const operationId = "same-op-same-payload";
    let arrivals = 0;
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {release = resolve;});
    const controlledDeps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => logicalNow,
      isAdmin: () => true,
      onPlanTransactionPhase: async (event) => {
        if (event.operationId !== operationId || arrivals >= 2) return;
        arrivals++;
        if (arrivals === 2) release();
        await gate;
      },
    });
    const command = payload(operationId, -120_000);
    const settled = await Promise.all([
      runCreateAndActivateNutritionPlan(actor, command, controlledDeps),
      runCreateAndActivateNutritionPlan(actor, structuredClone(command), controlledDeps),
    ]);
    assert.strictEqual(settled[0].planId, settled[1].planId);
    assert.strictEqual(settled.filter((result) => result.wasNoOp).length, 1);
    assert.strictEqual((await active()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, 1);
    assert.strictEqual((await audits()).size, 1);
  });
  await test("same operationId + different payload concurrent: incompatible call writes nothing", async () => {
    await clearDog();
    const operationId = "same-op-different-payload";
    let arrivals = 0;
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {release = resolve;});
    const controlledDeps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => logicalNow,
      isAdmin: () => true,
      onPlanTransactionPhase: async (event) => {
        if (event.operationId !== operationId || arrivals >= 2) return;
        arrivals++;
        if (arrivals === 2) release();
        await gate;
      },
    });
    const commandA = payload(operationId, -120_000);
    const commandB = structuredClone(commandA);
    commandB.planData.food_type = "Outra ração";
    const settled = await Promise.allSettled([
      runCreateAndActivateNutritionPlan(actor, commandA, controlledDeps),
      runCreateAndActivateNutritionPlan(actor, commandB, controlledDeps),
    ]);
    assertOneSuccessOneConflict(settled, "idempotency-conflict");
    assert.strictEqual((await active()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_plans").get()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, 1);
    assert.strictEqual((await audits()).size, 1);
  });
  await test("two same-revision updates: one wins", async () => {
    const plan = (await active()).docs[0];
    const revision = plan.data().revision as number;
    await rejectsOne([
      runUpdateActiveNutritionPlan(actor, {dogId, planId: plan.id, operationId: "uu-a", expectedRevision: revision,
        planData: {special_instructions: "a"}}, deps),
      runUpdateActiveNutritionPlan(actor, {dogId, planId: plan.id, operationId: "uu-b", expectedRevision: revision,
        planData: {special_instructions: "b"}}, deps),
    ]);
    assert.strictEqual((await plan.ref.get()).data()?.revision, revision + 1);
  });
  await test("update versus cancel: one wins", async () => {
    const plan = (await active()).docs[0];
    const revision = plan.data().revision as number;
    await rejectsOne([
      runUpdateActiveNutritionPlan(actor, {dogId, planId: plan.id, operationId: "uc-u", expectedRevision: revision,
        planData: {special_instructions: "race"}}, deps),
      runCancelNutritionPlan(actor, {dogId, planId: plan.id, operationId: "uc-c", expectedRevision: revision,
        reason: "race"}, deps),
    ]);
  });
  await test("replace versus update preserves unique active", async () => {
    if ((await active()).empty) await runCreateAndActivateNutritionPlan(actor, payload("seed-cu", -180_000), deps);
    const plan = (await active()).docs[0];
    const revision = plan.data().revision as number;
    await Promise.allSettled([
      runCreateAndActivateNutritionPlan(actor, replacePayload("cu-create", plan.id, revision, -30_000), deps),
      runUpdateActiveNutritionPlan(actor, {dogId, planId: plan.id, operationId: "cu-update", expectedRevision: revision,
        planData: {special_instructions: "race"}}, deps),
    ]);
    assert.strictEqual((await active()).size, 1);
  });
  await test("retroactive MealLog and SupplementLog block", async () => {
    await clearDog();
    await dog.collection("meal_logs").doc("meal").set({fed_at: Timestamp.fromDate(new Date(logicalNow.getTime() - 60_000))});
    await assert.rejects(() => runCreateAndActivateNutritionPlan(actor, payload("retro-meal", -120_000), deps));
    await dog.collection("meal_logs").doc("meal").delete();
    await dog.collection("supplement_logs").doc("supp").set({administered_at: Timestamp.fromDate(new Date(logicalNow.getTime() - 60_000))});
    await assert.rejects(() => runCreateAndActivateNutritionPlan(actor, payload("retro-supp", -120_000), deps));
  });
  await test("zero legacy writes", async () => {
    assert.strictEqual((await dog.collection("nutritional_prescriptions").get()).size, 0);
    assert.strictEqual((await dog.collection("nutrition_prescriptions").get()).size, 0);
  });
  await clearDog();
  console.log("health_nutrition_plan_emulator_test: all passed");
}

void main().catch(async (error) => {console.error(error); await clearDog(); process.exitCode = 1;});
