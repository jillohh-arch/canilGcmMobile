/**
 * E2E Nutrition callables contra Firestore Emulator + auth de permissão real
 * (sem mock de allowCreate genérico).
 *
 * Requer:
 *   FIRESTORE_EMULATOR_HOST
 *   (opcional) FIREBASE_AUTH_EMULATOR_HOST
 *
 * Orquestração:
 *   firebase emulators:exec --project canil-gcm --only firestore \\
 *     "npm run test:health-nutrition-emulator"
 *
 * NÃO usa produção. NÃO faz deploy.
 */
import * as assert from "assert";
import {
  runHealthNutritionCreateMealLog,
  runHealthNutritionCreateSupplementLog,
  HealthNutritionCallableDeps,
} from "./health_nutrition_callables";
import {createNutritionFirestoreEngineDeps} from "./health_nutrition_firestore_adapter";
import type {NutritionActor} from "./health_nutrition_engine";

type JsonMap = Record<string, unknown>;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mockRequest(data: JsonMap, auth: any): any {
  return {data, auth};
}

function samplePlan(overrides: JsonMap = {}): JsonMap {
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
    supplements: [{id: "reg-1", name: "Omega"}],
    ...overrides,
  };
}

/**
 * Deps com checagem real de access_profiles no Emulator (não mock boolean).
 */
function buildRealPermissionDeps(
  db: FirebaseFirestore.Firestore,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  HttpsError: any,
): HealthNutritionCallableDeps {
  async function loadUserByRa(ra: string): Promise<JsonMap> {
    const snap = await db.collection("users").doc(ra).get();
    return (snap.data() ?? {}) as JsonMap;
  }

  async function profileGrants(
    profileId: string,
    moduleId: string,
    action: string,
  ): Promise<boolean> {
    const snap = await db.collection("access_profiles").doc(profileId).get();
    if (!snap.exists) return false;
    const data = snap.data() ?? {};
    if (String(data.status ?? "active") !== "active") return false;
    const perms = (data.permissions ?? {}) as JsonMap;
    const mod = (perms[moduleId] ?? {}) as JsonMap;
    return mod[action] === true;
  }

  return {
    db,
    requireHealthCreate: async (auth) => {
      if (!auth) {
        throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
      }
      const email = String(auth.token?.email ?? "").trim().toLowerCase();
      const ra = email
        .replace("@canilgcm.com", "")
        .replace("@gcm.com.br", "")
        .trim();
      const caller: NutritionActor = {
        uid: auth.uid,
        email,
        ra,
        name: String(auth.token?.name ?? ra),
      };
      if (auth.token?.admin === true) return caller;
      const user = await loadUserByRa(ra);
      const accessLevel = String(user.accessLevel ?? user.access_level ?? "");
      if (accessLevel === "admin" || user.admin === true) return caller;
      const profileId = String(
        auth.token?.accessProfileId ??
          auth.token?.access_profile_id ??
          user.accessProfileId ??
          user.access_profile_id ??
          "default",
      );
      if (await profileGrants(profileId, "health", "create")) return caller;
      throw new HttpsError(
        "permission-denied",
        "Perfil sem permissao para health.create.",
        {code: "permission-denied"},
      );
    },
    requireDogAccess: async (auth, caller, dogId, dog) => {
      if (auth?.token?.admin === true) return;
      const user = await loadUserByRa(caller.ra);
      const accessLevel = String(user.accessLevel ?? user.access_level ?? "");
      if (accessLevel === "admin" || user.admin === true) return;

      const profileId = String(
        auth?.token?.accessProfileId ??
          user.accessProfileId ??
          user.access_profile_id ??
          "default",
      );
      const profileSnap = await db
        .collection("access_profiles")
        .doc(profileId)
        .get();
      const scope = String(profileSnap.data()?.scope ?? "global");
      if (scope === "global") return;

      const handlerRa =
        (dog.conductorRa as string) ||
        (dog.conductor_ra as string) ||
        (dog.handlerId as string) ||
        (dog.handler_id as string) ||
        null;
      if (handlerRa === caller.ra) return;

      throw new HttpsError(
        "permission-denied",
        "Seu perfil permite registrar dados apenas para o K9 vinculado.",
        {code: "permission-denied"},
      );
    },
    isAdministrativeAuthority: async (auth, caller) => {
      if (auth?.token?.admin === true) return true;
      const user = await loadUserByRa(caller.ra);
      const accessLevel = String(user.accessLevel ?? user.access_level ?? "");
      return accessLevel === "admin" || user.admin === true;
    },
    createEngineDeps: ({isAdmin}) =>
      createNutritionFirestoreEngineDeps(db, {
        serverNow: () => new Date("2026-07-18T15:00:00.000Z"),
        isAdmin,
      }),
  };
}

async function main(): Promise<void> {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error(
      "FIRESTORE_EMULATOR_HOST não definido. " +
        "Execute via firebase emulators:exec.",
    );
    process.exit(2);
  }

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const admin = require("firebase-admin");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");

  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT || "canil-gcm",
    });
  }
  const db = admin.firestore() as FirebaseFirestore.Firestore;
  const deps = buildRealPermissionDeps(db, HttpsError);
  const suffix = `${Date.now()}`;
  const dogId = `dog-e2e-${suffix}`;

  // Seed profiles
  await db.collection("access_profiles").doc("profile_health_create").set({
    status: "active",
    scope: "global",
    permissions: {health: {create: true, edit: true, view: true}},
  });
  await db.collection("access_profiles").doc("profile_no_health").set({
    status: "active",
    scope: "global",
    permissions: {health: {create: false, view: true}},
  });
  await db.collection("access_profiles").doc("profile_own_records").set({
    status: "active",
    scope: "own_records",
    permissions: {health: {create: true, edit: true, view: true}},
  });

  await db.collection("users").doc("700001").set({
    accessProfileId: "profile_health_create",
    accessLevel: "operator",
  });
  await db.collection("users").doc("700002").set({
    accessProfileId: "profile_no_health",
    accessLevel: "operator",
  });
  await db.collection("users").doc("700003").set({
    accessProfileId: "profile_own_records",
    accessLevel: "operator",
  });

  await db.collection("dogs").doc(dogId).set({
    name: "E2E Dog",
    conductorRa: "700001",
  });
  await db
    .collection("dogs")
    .doc(dogId)
    .collection("nutrition_plans")
    .doc("plan-1")
    .set(samplePlan());

  const authOk = {
    uid: "uid-700001",
    token: {
      email: "700001@gcm.com.br",
      name: "Operador E2E",
      accessProfileId: "profile_health_create",
    },
  };
  const authNoHealth = {
    uid: "uid-700002",
    token: {
      email: "700002@gcm.com.br",
      name: "Sem Health",
      accessProfileId: "profile_no_health",
    },
  };
  const authOwnOtherDog = {
    uid: "uid-700003",
    token: {
      email: "700003@gcm.com.br",
      name: "Own Records",
      accessProfileId: "profile_own_records",
    },
  };

  await test("E2E unauthenticated", async () => {
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: dogId,
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "e2e-unauth",
            },
            null,
          ),
          deps,
        ),
      (e: {code?: string}) => e.code === "unauthenticated",
    );
  });

  await test("E2E authenticated sem health.create", async () => {
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: dogId,
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "e2e-noperm",
            },
            authNoHealth,
          ),
          deps,
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );
  });

  await test("E2E health.create sem dog access (own_records)", async () => {
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: dogId,
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "e2e-nodog",
            },
            authOwnOtherDog,
          ),
          deps,
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );
  });

  let plannedMealId = "";

  await test("E2E planned meal happy path", async () => {
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: dogId,
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: "2026-07-10T10:00:00.000Z",
          operation_id: "e2e-planned-1",
        },
        authOk,
      ),
      deps,
    );
    assert.strictEqual(r.was_no_op, false);
    assert.ok(String(r.meal_id).startsWith("mo1_"));
    assert.strictEqual(r.meal_id, r.meal_occurrence_id);
    plannedMealId = String(r.meal_id);

    const meal = await db
      .collection("dogs")
      .doc(dogId)
      .collection("meal_logs")
      .doc(plannedMealId)
      .get();
    assert.ok(meal.exists);
    const ops = await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_operations")
      .get();
    assert.ok(ops.size >= 1);
    const audits = await db
      .collection("auditLogs")
      .where("entity_id", "==", plannedMealId)
      .get();
    assert.strictEqual(audits.size, 1);

    for (const col of ["feeding_events", "feedings"]) {
      const leg = await db
        .collection("dogs")
        .doc(dogId)
        .collection(col)
        .get();
      assert.strictEqual(leg.size, 0);
    }
  });

  await test("E2E planned replay", async () => {
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: dogId,
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: "2026-07-10T10:00:00.000Z",
          operation_id: "e2e-planned-1",
        },
        authOk,
      ),
      deps,
    );
    assert.strictEqual(r.was_no_op, true);
    assert.strictEqual(r.meal_id, plannedMealId);
    const meals = await db
      .collection("dogs")
      .doc(dogId)
      .collection("meal_logs")
      .get();
    // only one for this occurrence (may have more from other tests on same dog later)
    const thisMeal = meals.docs.filter((d) => d.id === plannedMealId);
    assert.strictEqual(thisMeal.length, 1);
    const audits = await db
      .collection("auditLogs")
      .where("entity_id", "==", plannedMealId)
      .get();
    assert.strictEqual(audits.size, 1);
  });

  await test("E2E durable replay after plan cancelled", async () => {
    const payload = {
      mode: "planned" as const,
      dog_id: dogId,
      plan_id: "plan-1",
      planned_meal_id: "slot-am",
      offered_grams: 300,
      acceptance: "full",
      fed_at: "2026-07-11T10:00:00.000Z",
      operation_id: "e2e-durable-1",
    };
    const r1 = await runHealthNutritionCreateMealLog(
      mockRequest(payload, authOk),
      deps,
    );
    assert.strictEqual(r1.was_no_op, false);

    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_plans")
      .doc("plan-1")
      .update({status: "cancelled"});

    const r2 = await runHealthNutritionCreateMealLog(
      mockRequest(payload, authOk),
      deps,
    );
    assert.strictEqual(r2.was_no_op, true);
    assert.strictEqual(r2.meal_id, r1.meal_id);

    const audits = await db
      .collection("auditLogs")
      .where("entity_id", "==", r1.meal_id)
      .get();
    assert.strictEqual(audits.size, 1);

    await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_plans")
      .doc("plan-1")
      .update({status: "active"});
  });

  await test("E2E idempotency conflict", async () => {
    await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: dogId,
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: "2026-07-14T10:00:00.000Z",
          operation_id: "e2e-idem",
        },
        authOk,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: dogId,
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 250,
              acceptance: "full",
              fed_at: "2026-07-14T10:00:00.000Z",
              operation_id: "e2e-idem",
            },
            authOk,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "failed-precondition",
    );
  });

  await test("E2E semantic no-op (same occurrence, different operation_id)", async () => {
    const fedAt = "2026-07-15T10:00:00.000Z";
    const base = {
      mode: "planned" as const,
      dog_id: dogId,
      plan_id: "plan-1",
      planned_meal_id: "slot-am",
      offered_grams: 300,
      acceptance: "full" as const,
      fed_at: fedAt,
    };
    const r1 = await runHealthNutritionCreateMealLog(
      mockRequest({...base, operation_id: "e2e-sem-a"}, authOk),
      deps,
    );
    const r2 = await runHealthNutritionCreateMealLog(
      mockRequest({...base, operation_id: "e2e-sem-b"}, authOk),
      deps,
    );
    assert.strictEqual(r1.was_no_op, false);
    assert.strictEqual(r2.was_no_op, true);
    assert.strictEqual(r1.meal_id, r2.meal_id);

    const ops = await db
      .collection("dogs")
      .doc(dogId)
      .collection("nutrition_operations")
      .get();
    // at least 2 receipts for the two operation ids (plus prior tests)
    assert.ok(ops.size >= 2);

    const audits = await db
      .collection("auditLogs")
      .where("entity_id", "==", r1.meal_id)
      .get();
    assert.strictEqual(audits.size, 1);
  });

  await test("E2E occurrence conflict", async () => {
    const fedAt = "2026-07-16T10:00:00.000Z";
    await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: dogId,
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: fedAt,
          operation_id: "e2e-conf-a",
        },
        authOk,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: dogId,
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 200,
              acceptance: "partial",
              consumed_grams: 100,
              fed_at: fedAt,
              operation_id: "e2e-conf-b",
            },
            authOk,
          ),
          deps,
        ),
      (e: {details?: {code?: string}}) =>
        e.details?.code === "meal_occurrence_conflict",
    );
  });

  await test("E2E ad hoc", async () => {
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "adhoc",
          dog_id: dogId,
          period: "extra",
          offered_grams: 90,
          acceptance: "full",
          fed_at: "2026-07-17T12:00:00.000Z",
          operation_id: "e2e-adhoc",
        },
        authOk,
      ),
      deps,
    );
    assert.ok(String(r.meal_id).startsWith("ml1_"));
    const meal = await db
      .collection("dogs")
      .doc(dogId)
      .collection("meal_logs")
      .doc(String(r.meal_id))
      .get();
    assert.strictEqual(meal.data()?.plan_id ?? null, null);
    assert.strictEqual(meal.data()?.planned_meal_id ?? null, null);
    assert.strictEqual(meal.data()?.meal_occurrence_id ?? null, null);
    assert.strictEqual(meal.data()?.scheduled_for ?? null, null);
  });

  await test("E2E supplement free + regimen requires plan + regimen not found", async () => {
    const free = await runHealthNutritionCreateSupplementLog(
      mockRequest(
        {
          dog_id: dogId,
          supplement_name: "Omega",
          dose: 2,
          unit: "ml",
          administered_at: "2026-07-17T14:00:00.000Z",
          operation_id: "e2e-supp-free",
        },
        authOk,
      ),
      deps,
    );
    assert.ok(String(free.supplement_log_id).startsWith("sl1_"));

    await assert.rejects(
      () =>
        runHealthNutritionCreateSupplementLog(
          mockRequest(
            {
              dog_id: dogId,
              supplement_name: "Omega",
              dose: 2,
              unit: "ml",
              administered_at: "2026-07-17T14:30:00.000Z",
              supplement_regimen_id: "reg-1",
              operation_id: "e2e-supp-nplan",
            },
            authOk,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "invalid-argument" ||
        e.details?.code === "supplement_regimen_requires_plan",
    );

    await assert.rejects(
      () =>
        runHealthNutritionCreateSupplementLog(
          mockRequest(
            {
              dog_id: dogId,
              supplement_name: "Omega",
              dose: 2,
              unit: "ml",
              administered_at: "2026-07-17T15:00:00.000Z",
              nutrition_plan_id: "plan-1",
              supplement_regimen_id: "reg-missing",
              operation_id: "e2e-supp-nreg",
            },
            authOk,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "not-found" ||
        e.details?.code === "supplement_regimen_not_found",
    );

    const linked = await runHealthNutritionCreateSupplementLog(
      mockRequest(
        {
          dog_id: dogId,
          supplement_name: "Omega",
          dose: 2,
          unit: "ml",
          administered_at: "2026-07-17T15:30:00.000Z",
          nutrition_plan_id: "plan-1",
          supplement_regimen_id: "reg-1",
          operation_id: "e2e-supp-ok",
        },
        authOk,
      ),
      deps,
    );
    assert.strictEqual(linked.was_no_op, false);
  });

  await test("E2E App Check not enforced (callable operable without token)", async () => {
    // handlers do not check app check; smoke that authorized call still works
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "adhoc",
          dog_id: dogId,
          period: "night",
          offered_grams: 50,
          acceptance: "full",
          fed_at: "2026-07-17T22:00:00.000Z",
          operation_id: "e2e-no-appcheck",
        },
        authOk,
      ),
      deps,
    );
    assert.strictEqual(r.was_no_op, false);
  });

  console.log("\nAll health_nutrition_emulator_e2e tests passed.");
  console.log("Node:", process.version);
  console.log("FIRESTORE_EMULATOR_HOST:", process.env.FIRESTORE_EMULATOR_HOST);
  console.log("GCLOUD_PROJECT:", process.env.GCLOUD_PROJECT || "canil-gcm");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
