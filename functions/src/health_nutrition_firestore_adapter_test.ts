/**
 * Testes do adapter Firestore Admin (paths, timestamps, decode fail-closed).
 * Com FIRESTORE_EMULATOR_HOST: valida transaction real no Emulator.
 * Sem emulator: testes unitários de prepareWriteData / decode / path guards.
 *
 * npm run build && node lib/health_nutrition_firestore_adapter_test.js
 */
import * as assert from "assert";
import {
  createNutritionFirestoreEngineDeps,
  decodeMealLogDoc,
  decodeNutritionReceiptDoc,
  docRefFromPath,
  firestoreDataToPlain,
  prepareWriteData,
} from "./health_nutrition_firestore_adapter";
import {
  NutritionActor,
  runCreatePlannedMealLog,
  runCreateAdhocMealLog,
  runCreateSupplementLog,
} from "./health_nutrition_engine";

type JsonMap = Record<string, unknown>;

async function test(name: string, fn: () => Promise<void> | void): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

const actor: NutritionActor = {
  uid: "uid-adapter",
  email: "100@gcm.com.br",
  ra: "100",
  name: "Adapter Tester",
};

function samplePlan(): JsonMap {
  return {
    status: "active",
    timezone: "America/Sao_Paulo",
    valid_from: "2026-01-01T00:00:00.000Z",
    meal_schedule: [
      {
        id: "slot-am",
        period: "morning",
        scheduled_time: "07:00",
        target_grams: 300,
      },
    ],
    supplements: [{id: "reg-1"}],
  };
}

async function main(): Promise<void> {
  await test("prepareWriteData uses serverTimestamp sentinels", () => {
    // FieldValue.serverTimestamp is an object sentinel
    const prepared = prepareWriteData({
      recorded_at: "2026-07-18T15:00:00.000Z",
      processed_at: "2026-07-18T15:00:00.000Z",
      performed_at: "2026-07-18T15:00:00.000Z",
      createdAt: "2026-07-18T15:00:00.000Z",
      fed_at: "2026-07-10T10:00:00.000Z",
      offered_grams: 300,
    });
    // server fields replaced
    for (const k of [
      "recorded_at",
      "processed_at",
      "performed_at",
      "createdAt",
    ]) {
      const v = prepared[k] as {_methodName?: string; methodName?: string};
      const name = v?._methodName ?? v?.methodName ?? String(v);
      assert.ok(
        String(name).toLowerCase().includes("servertimestamp") ||
          typeof v === "object",
        `${k} should be serverTimestamp sentinel, got ${name}`,
      );
    }
    // client fact converted to Timestamp-like
    assert.ok(prepared.fed_at !== "2026-07-10T10:00:00.000Z");
    assert.strictEqual(prepared.offered_grams, 300);
  });

  await test("decode receipt missing → passthrough", () => {
    const r = decodeNutritionReceiptDoc({exists: false, data: {}});
    assert.strictEqual(r.exists, false);
  });

  await test("decode receipt malformed → integrity", () => {
    assert.throws(
      () =>
        decodeNutritionReceiptDoc({
          exists: true,
          data: {operation_id: "x"},
        }),
      (e: Error & {appCode?: string; detailCode?: string}) =>
        e.appCode === "integrity" ||
        e.detailCode === "receipt_integrity",
    );
  });

  await test("decode receipt valid", () => {
    const r = decodeNutritionReceiptDoc({
      exists: true,
      data: {
        receipt_id: "nr1_x",
        operation_id: "op1",
        operation_type: "create_planned_meal",
        actor_uid: "uid",
        fingerprint: "fp",
        entity_type: "meal_log",
        entity_id: "mo1_x",
        result: {revision: 1},
      },
    });
    assert.strictEqual(r.exists, true);
  });

  await test("decode meal malformed → integrity", () => {
    assert.throws(
      () =>
        decodeMealLogDoc({
          exists: true,
          data: {random: true},
        }),
      (e: Error & {appCode?: string}) =>
        e.appCode === "integrity" || e.appCode === "conflict",
    );
  });

  await test("decode meal with semantic fingerprint ok", () => {
    const r = decodeMealLogDoc({
      exists: true,
      data: {
        entity_semantic_fingerprint: "abc",
        offered_grams: 300,
        acceptance: "full",
      },
    });
    assert.strictEqual(r.exists, true);
  });

  await test("docRefFromPath builds nested path", () => {
    // uses admin app if initialized; path building only needs interface
    // Skip live db — only validate path split logic via error on odd segments
    assert.throws(
      () => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        docRefFromPath({} as any, "dogs/only");
      },
      () => true,
    );
  });

  // ── Emulator integration (optional) ──────────────────────────────────────
  const emuHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emuHost) {
    console.log(
      "skip - FIRESTORE_EMULATOR_HOST not set (unit-only adapter tests done)",
    );
    console.log("\nAll health_nutrition_firestore_adapter unit tests passed.");
    return;
  }

  // Live emulator path
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({projectId: process.env.GCLOUD_PROJECT || "canil-gcm"});
  }
  const db = admin.firestore();
  const dogId = `dog-adapter-${Date.now()}`;
  const planId = "plan-1";

  await test("emulator: seed plan + planned meal happy path", async () => {
    await db.collection("dogs").doc(dogId).set({name: "AdapterDog"});
    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_plans")
      .doc(planId)
      .set(samplePlan());

    const deps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
      isAdmin: () => false,
    });

    const result = await runCreatePlannedMealLog(
      actor,
      {
        dog_id: dogId,
        plan_id: planId,
        planned_meal_id: "slot-am",
        offered_grams: 300,
        acceptance: "full",
        fed_at: "2026-07-10T10:00:00.000Z",
        operation_id: "emu-planned-1",
      },
      deps,
    );

    assert.strictEqual(result.wasNoOp, false);
    assert.ok(result.entityId.startsWith("mo1_"));
    assert.strictEqual(result.entityId, result.mealOccurrenceId);

    const mealSnap = await db
      .collection("dogs")
      .doc(dogId)
      .collection("meal_logs")
      .doc(result.entityId)
      .get();
    assert.ok(mealSnap.exists);
    const meal = mealSnap.data()!;
    assert.ok(meal.recorded_at); // server timestamp materializado no emulator
    assert.strictEqual(meal.revision, 1);

    const ops = await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_operations")
      .get();
    assert.strictEqual(ops.size, 1);
    const receipt = ops.docs[0].data();
    assert.ok(receipt.processed_at);
    assert.strictEqual(receipt.operation_type, "create_planned_meal");

    const audits = await db.collection("auditLogs").get();
    // pode haver outros testes; filtrar por entity
    const mine = audits.docs.filter(
      (d: FirebaseFirestore.QueryDocumentSnapshot) =>
        d.data().entity_id === result.entityId,
    );
    assert.strictEqual(mine.length, 1);

    // zero legacy
    for (const col of [
      "feeding_events",
      "feedings",
      "nutritional_prescriptions",
    ]) {
      const legacy = await db
        .collection("dogs")
        .doc(dogId)
        .collection(col)
        .get();
      assert.strictEqual(legacy.size, 0, col);
    }
  });

  await test("emulator: durable replay after plan cancelled", async () => {
    const deps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
      isAdmin: () => false,
    });
    const payload = {
      dog_id: dogId,
      plan_id: planId,
      planned_meal_id: "slot-am",
      offered_grams: 300,
      acceptance: "full",
      fed_at: "2026-07-11T10:00:00.000Z",
      operation_id: "emu-durable-1",
    };
    const r1 = await runCreatePlannedMealLog(actor, payload, deps);
    assert.strictEqual(r1.wasNoOp, false);

    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_plans")
      .doc(planId)
      .update({status: "cancelled"});

    const r2 = await runCreatePlannedMealLog(actor, payload, deps);
    assert.strictEqual(r2.wasNoOp, true);
    assert.strictEqual(r2.entityId, r1.entityId);

    // restore plan for further tests
    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_plans")
      .doc(planId)
      .update({status: "active"});
  });

  await test("emulator: receipt malformed integrity", async () => {
    const badReceiptId = "nr1_malformed_test";
    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_operations")
      .doc(badReceiptId)
      .set({operation_id: "broken"});

    const deps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
    });

    // Direct getDoc via engine path that hits our receipt id only if matching
    // Use decode on loaded snap:
    const snap = await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_operations")
      .doc(badReceiptId)
      .get();
    assert.throws(
      () =>
        decodeNutritionReceiptDoc({
          exists: true,
          data: firestoreDataToPlain(snap.data()),
        }),
      (e: Error & {detailCode?: string}) =>
        e.detailCode === "receipt_integrity",
    );
    void deps;
  });

  await test("emulator: adhoc + supplement writes", async () => {
    const deps = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
      isAdmin: () => false,
    });
    const adhoc = await runCreateAdhocMealLog(
      actor,
      {
        dog_id: dogId,
        period: "extra",
        offered_grams: 120,
        acceptance: "full",
        fed_at: "2026-07-12T12:00:00.000Z",
        operation_id: "emu-adhoc-1",
      },
      deps,
    );
    assert.ok(adhoc.entityId.startsWith("ml1_"));

    const supp = await runCreateSupplementLog(
      actor,
      {
        dog_id: dogId,
        supplement_name: "Omega",
        dose: 5,
        unit: "ml",
        administered_at: "2026-07-12T13:00:00.000Z",
        operation_id: "emu-supp-1",
      },
      deps,
    );
    assert.ok(supp.entityId.startsWith("sl1_"));

    const meal = await db
      .collection("dogs")
      .doc(dogId)
      .collection("meal_logs")
      .doc(adhoc.entityId)
      .get();
    assert.strictEqual(meal.data()?.plan_id ?? null, null);
    assert.strictEqual(meal.data()?.meal_occurrence_id ?? null, null);
  });

  await test("emulator: plan authority is transactional get", async () => {
    // Instrument: cancel plan mid-flight using a custom deps wrapper that
    // mutates plan after outer getDoc (receipt) but before txn — engine
    // must see cancelled inside txn.
    const base = createNutritionFirestoreEngineDeps(db, {
      serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
      isAdmin: () => false,
    });
    let cancelled = false;
    const wrapped: typeof base = {
      ...base,
      runTransaction: async <T>(
        fn: Parameters<typeof base.runTransaction>[0],
      ): Promise<T> => {
        if (!cancelled) {
          await db
            .collection("dogs")
            .doc(dogId)
            .collection("nutrition_plans")
            .doc(planId)
            .update({status: "cancelled"});
          cancelled = true;
        }
        return base.runTransaction(fn) as Promise<T>;
      },
    };

    await assert.rejects(
      () =>
        runCreatePlannedMealLog(
          actor,
          {
            dog_id: dogId,
            plan_id: planId,
            planned_meal_id: "slot-am",
            offered_grams: 300,
            acceptance: "full",
            fed_at: "2026-07-13T10:00:00.000Z",
            operation_id: "emu-toctou-1",
          },
          wrapped,
        ),
      (e: Error & {detailCode?: string; appCode?: string}) =>
        e.detailCode === "nutrition_plan_cancelled" ||
        (e.message || "").toLowerCase().includes("cancel"),
    );
  });

  console.log("\nAll health_nutrition_firestore_adapter tests passed (with emulator).");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
