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

async function main() {
  await test("create zero active is atomic", async () => {
    await clearDog();
    const r = await runCreateAndActivateNutritionPlan(actor, payload("create-zero"), deps);
    assert.strictEqual((await active()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_operations").get()).size, 1);
    assert.strictEqual((await audits()).size, 1);
    assert.strictEqual((await dog.collection("nutrition_plans").doc(r.planId).get()).data()?.revision, 1);
  });
  await test("create supersedes active", async () => {
    const current = (await active()).docs[0];
    const r = await runCreateAndActivateNutritionPlan(actor, payload("supersede", -60_000), deps);
    assert.strictEqual(r.supersededPlanId, current.id);
    const old = (await current.ref.get()).data()!;
    assert.strictEqual(old.status, "superseded");
    assert.ok(old.valid_until instanceof Timestamp);
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
  await test("create versus update preserves unique active", async () => {
    if ((await active()).empty) await runCreateAndActivateNutritionPlan(actor, payload("seed-cu", -180_000), deps);
    const plan = (await active()).docs[0];
    const revision = plan.data().revision as number;
    await Promise.allSettled([
      runCreateAndActivateNutritionPlan(actor, payload("cu-create", -30_000), deps),
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
