/**
 * Health v1 — Fase 5D Gate 2
 * Callable transport E2E REAL:
 *   Auth Emulator + Firestore Emulator + Functions Emulator
 *
 * Invoca callables via cliente Firebase autenticado (httpsCallable).
 * NÃO chama runHealthNutritionCreateMealLog / handlers internos.
 *
 * Execução (repo root, após npm --prefix functions run build):
 *   firebase emulators:exec --project canil-gcm --config firebase.json \
 *     --only auth,firestore,functions \
 *     "node tools/rules_tests/health_nutrition_callables_emulator_tests.mjs"
 *
 * Zero produção.
 */
import assert from "node:assert/strict";
import {
  initializeApp as initializeAdminApp,
  getApps,
} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore} from "firebase-admin/firestore";
import {initializeApp, deleteApp as deleteClientApp} from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {
  connectFirestoreEmulator,
  getFirestore,
} from "firebase/firestore";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";

const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT_ID ||
  "canil-gcm";
const REGION = "southamerica-east1";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

const PASSWORD = "Gate2-Nutrition-Emulator-Only-Not-Prod!";
const DOG_A = "dog-nutri-e2e-a";
const DOG_OTHER = "dog-nutri-e2e-other";
const PLAN_ID = "plan-nutri-1";

const OP = {
  ra: "710001",
  uid: "uid-710001",
  email: "710001@gcm.com.br",
  name: "Operador Nutri E2E",
};
const NO_PERM = {
  ra: "710002",
  uid: "uid-710002",
  email: "710002@gcm.com.br",
  name: "Sem Health Create",
};
const OWN_OTHER = {
  ra: "710003",
  uid: "uid-710003",
  email: "710003@gcm.com.br",
  name: "Own Records Other Dog",
};

const results = [];
let failures = 0;

function log(msg) {
  console.log(msg);
}

function record(name, ok, detail = "") {
  results.push({name, ok, detail});
  if (ok) {
    log(`ok - ${name}${detail ? ` (${detail})` : ""}`);
  } else {
    failures++;
    log(`FAIL - ${name}${detail ? `: ${detail}` : ""}`);
  }
}

async function test(name, fn) {
  try {
    await fn();
    record(name, true);
  } catch (e) {
    record(name, false, e?.message || String(e));
    console.error(e);
  }
}

function parseHost(hostPort) {
  const cleaned = String(hostPort).replace(/^https?:\/\//, "");
  const [host, portStr] = cleaned.split(":");
  return {host, port: Number(portStr)};
}

function errorWire(err) {
  // Firebase JS SDK surfaces callable errors as FirebaseError:
  // code: "functions/unauthenticated" | "functions/failed-precondition" | ...
  // details: may be the details payload { code: "..." } depending on SDK version
  const code = err?.code || "";
  const message = err?.message || "";
  const details =
    err?.details ??
    err?.customData?.details ??
    err?.customData ??
    {};
  const detailsCode =
    (details && typeof details === "object" && details.code) ||
    err?.customData?.details?.code ||
    undefined;
  return {
    code: String(code),
    detailsCode: detailsCode ? String(detailsCode) : undefined,
    details,
    message: String(message),
    rawKeys: err && typeof err === "object" ? Object.keys(err) : [],
  };
}

function assertHttpsCode(err, expectedSubstring) {
  const {code, detailsCode, message} = errorWire(err);
  const hay = `${code} ${detailsCode || ""} ${message}`.toLowerCase();
  assert.ok(
    hay.includes(String(expectedSubstring).toLowerCase()),
    `esperado conter "${expectedSubstring}", obtido code=${code} details=${detailsCode} msg=${message}`,
  );
}

function assertDetailsCode(err, appCode) {
  const wire = errorWire(err);
  const hay = `${wire.code} ${wire.detailsCode || ""} ${wire.message} ${JSON.stringify(wire.details)}`.toLowerCase();
  assert.ok(
    hay.includes(String(appCode).toLowerCase()),
    `esperado details/app code "${appCode}", wire=${JSON.stringify(wire)}`,
  );
}

// --- Guard: must be on emulators ---
assert.ok(
  process.env.FIRESTORE_EMULATOR_HOST,
  "FIRESTORE_EMULATOR_HOST obrigatório (use firebase emulators:exec)",
);
assert.ok(
  process.env.FIREBASE_AUTH_EMULATOR_HOST,
  "FIREBASE_AUTH_EMULATOR_HOST obrigatório (use firebase emulators:exec)",
);

// --- Admin (seed / inspect) ---
if (!getApps().length) {
  initializeAdminApp({projectId: PROJECT_ID});
}
const adminAuth = getAdminAuth();
const adminDb = getAdminFirestore();

// --- Client ---
const clientApp = initializeApp(
  {
    projectId: PROJECT_ID,
    apiKey: "fake-api-key-emulator",
    appId: "1:fake:web:gate2-nutrition",
  },
  "gate2-nutrition-client",
);

const auth = getAuth(clientApp);
const authParsed = parseHost(AUTH_HOST);
connectAuthEmulator(auth, `http://${authParsed.host}:${authParsed.port}`, {
  disableWarnings: true,
});

const firestore = getFirestore(clientApp);
const fsParsed = parseHost(FS_HOST);
connectFirestoreEmulator(firestore, fsParsed.host, fsParsed.port);

const functions = getFunctions(clientApp, REGION);
let fnHost = "127.0.0.1";
let fnPort = 5001;
if (
  process.env.FUNCTIONS_EMULATOR === "true" ||
  process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST
) {
  const raw =
    process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
  const p = parseHost(raw.includes(":") ? raw : `127.0.0.1:${raw}`);
  fnHost = p.host;
  fnPort = p.port || 5001;
}
connectFunctionsEmulator(functions, fnHost, fnPort);

const FUNCTIONS_BASE_URL =
  `http://${fnHost}:${fnPort}/${PROJECT_ID}/${REGION}`;

function callable(name) {
  return httpsCallable(functions, name);
}

async function ensureUser(user, claims = {}) {
  try {
    await adminAuth.createUser({
      uid: user.uid,
      email: user.email,
      password: PASSWORD,
      displayName: user.name,
      emailVerified: true,
    });
  } catch (e) {
    if (
      e?.code !== "auth/uid-already-exists" &&
      e?.code !== "auth/email-already-exists"
    ) {
      throw e;
    }
  }
  if (Object.keys(claims).length) {
    await adminAuth.setCustomUserClaims(user.uid, claims);
  }
}

/**
 * Login real no Auth Emulator → ID token real.
 * Prova: token atravessa Functions Emulator → request.auth.
 */
async function signIn(user) {
  await signOut(auth).catch(() => undefined);
  const cred = await signInWithEmailAndPassword(auth, user.email, PASSWORD);
  const token = await cred.user.getIdToken(true);
  assert.ok(token && token.length > 20, "ID token Auth Emulator vazio");
  return {user: cred.user, idToken: token};
}

function samplePlan(overrides = {}) {
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

async function seedBase() {
  for (const col of ["meal_logs", "nutrition_operations", "supplement_logs", "feeding_events", "feedings"]) {
    const snap = await adminDb.collection("dogs").doc(DOG_A).collection(col).get();
    for (const d of snap.docs) {
      await d.ref.delete();
    }
  }

  await adminDb.collection("access_profiles").doc("operador_k9").set({
    status: "active",
    scope: "own_records",
    permissions: {
      health: {view: true, create: true, edit: true},
    },
  });
  await adminDb.collection("access_profiles").doc("sem_saude").set({
    status: "active",
    scope: "global",
    permissions: {
      health: {view: true, create: false, edit: false},
    },
  });
  await adminDb.collection("access_profiles").doc("own_other").set({
    status: "active",
    scope: "own_records",
    permissions: {
      health: {view: true, create: true, edit: true},
    },
  });

  await adminDb.collection("users").doc(OP.ra).set({
    email: OP.email,
    name: OP.name,
    access_profile_id: "operador_k9",
    accessLevel: "operador",
  });
  await adminDb.collection("users").doc(NO_PERM.ra).set({
    email: NO_PERM.email,
    name: NO_PERM.name,
    access_profile_id: "sem_saude",
    accessLevel: "operador",
  });
  await adminDb.collection("users").doc(OWN_OTHER.ra).set({
    email: OWN_OTHER.email,
    name: OWN_OTHER.name,
    access_profile_id: "own_other",
    accessLevel: "operador",
  });

  await adminDb.collection("dogs").doc(DOG_A).set({
    name: "Rex Nutri E2E",
    conductor_ra: OP.ra,
    status: "active",
  });
  await adminDb.collection("dogs").doc(DOG_OTHER).set({
    name: "Other K9",
    conductor_ra: "999999",
    status: "active",
  });

  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("nutrition_plans")
    .doc(PLAN_ID)
    .set(samplePlan());

  await ensureUser(OP);
  await ensureUser(NO_PERM);
  await ensureUser(OWN_OTHER);
}

function plannedPayload(overrides = {}) {
  return {
    mode: "planned",
    dog_id: DOG_A,
    plan_id: PLAN_ID,
    planned_meal_id: "slot-am",
    offered_grams: 300,
    acceptance: "full",
    fed_at: "2026-07-10T10:00:00.000Z",
    operation_id: "nutri-e2e-planned-1",
    ...overrides,
  };
}

async function countSub(dogId, col) {
  const snap = await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection(col)
    .get();
  return snap.size;
}

async function countAuditsForEntity(entityId) {
  const snap = await adminDb
    .collection("auditLogs")
    .where("entity_id", "==", entityId)
    .get();
  return snap.size;
}

async function countLegacy(dogId) {
  let n = 0;
  for (const col of [
    "feeding_events",
    "feedings",
    "nutritional_prescriptions",
    "nutrition_prescriptions",
    "nutrition_supplements",
  ]) {
    const snap = await adminDb
      .collection("dogs")
      .doc(dogId)
      .collection(col)
      .get();
    n += snap.size;
  }
  return n;
}

// =============================================================================
log(`\n=== Health Nutrition Callables — REAL TRANSPORT E2E (Gate 2) ===`);
log(`project=${PROJECT_ID}`);
log(`AUTH_EMULATOR=${AUTH_HOST}`);
log(`FIRESTORE_EMULATOR=${FS_HOST}`);
log(`FUNCTIONS_EMULATOR=${fnHost}:${fnPort}`);
log(`FUNCTIONS_BASE_URL=${FUNCTIONS_BASE_URL}`);
log(`region=${REGION}`);
log(`GCLOUD_PROJECT=${process.env.GCLOUD_PROJECT || "(unset)"}`);
log(`FUNCTIONS_EMULATOR_FLAG=${process.env.FUNCTIONS_EMULATOR || "(unset)"}`);
log(`Node=${process.version}`);
log(`ZERO_PRODUCTION: emulators:exec only`);

await seedBase();

// Prove Auth Emulator issues real tokens before callables
await test("Auth Emulator emite ID token real", async () => {
  const {idToken, user} = await signIn(OP);
  assert.equal(user.email, OP.email);
  assert.ok(idToken.split(".").length === 3, "JWT malformado");
  log(`  token_len=${idToken.length} uid=${user.uid}`);
});

// -----------------------------------------------------------------------------
// Unauthenticated
// -----------------------------------------------------------------------------
await test("callable real sem token → unauthenticated", async () => {
  await signOut(auth).catch(() => undefined);
  try {
    await callable("healthNutritionCreateMealLog")(
      plannedPayload({operation_id: "no-auth"}),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "unauthenticated");
    const wire = errorWire(e);
    assert.ok(
      wire.code.includes("unauthenticated") ||
        wire.message.toLowerCase().includes("unauthenticated"),
      `código wire unauthenticated: ${JSON.stringify(wire)}`,
    );
  }
});

// -----------------------------------------------------------------------------
// Permission denied
// -----------------------------------------------------------------------------
await test("callable real auth sem health.create → permission-denied", async () => {
  await signIn(NO_PERM);
  const beforeMeals = await countSub(DOG_A, "meal_logs");
  const beforeOps = await countSub(DOG_A, "nutrition_operations");
  try {
    await callable("healthNutritionCreateMealLog")(
      plannedPayload({operation_id: "no-perm"}),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }
  assert.equal(await countSub(DOG_A, "meal_logs"), beforeMeals);
  assert.equal(await countSub(DOG_A, "nutrition_operations"), beforeOps);
  assert.equal(await countLegacy(DOG_A), 0);
});

// -----------------------------------------------------------------------------
// Dog access denied
// -----------------------------------------------------------------------------
await test(
  "callable real health.create sem dog access → permission-denied",
  async () => {
    await signIn(OWN_OTHER);
    const beforeMeals = await countSub(DOG_A, "meal_logs");
    const beforeOps = await countSub(DOG_A, "nutrition_operations");
    try {
      await callable("healthNutritionCreateMealLog")(
        plannedPayload({operation_id: "no-dog"}),
      );
      assert.fail("deveria falhar");
    } catch (e) {
      assertHttpsCode(e, "permission-denied");
    }
    assert.equal(await countSub(DOG_A, "meal_logs"), beforeMeals);
    assert.equal(await countSub(DOG_A, "nutrition_operations"), beforeOps);
  },
);

// -----------------------------------------------------------------------------
// Planned happy path
// -----------------------------------------------------------------------------
let plannedMealId = "";

await test("callable real planned meal happy path", async () => {
  await signIn(OP);
  const res = await callable("healthNutritionCreateMealLog")(
    plannedPayload({operation_id: "nutri-e2e-planned-1"}),
  );
  const data = res.data;
  assert.equal(data.was_no_op ?? data.wasNoOp, false);
  assert.equal(data.revision, 1);
  assert.ok(data.meal_id || data.mealId);
  plannedMealId = String(data.meal_id || data.mealId);
  assert.ok(plannedMealId.startsWith("mo1_"));
  assert.equal(
    data.meal_occurrence_id ?? data.mealOccurrenceId,
    plannedMealId,
  );

  const meal = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("meal_logs")
    .doc(plannedMealId)
    .get();
  assert.ok(meal.exists, "MealLog deve existir no Firestore Emulator");
  assert.equal(meal.data()?.revision, 1);
  assert.ok(meal.data()?.recorded_at, "recorded_at server timestamp");
  assert.ok(meal.data()?.fed_at, "fed_at persistido");

  const ops = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("nutrition_operations")
    .get();
  assert.ok(ops.size >= 1);
  const audits = await countAuditsForEntity(plannedMealId);
  assert.equal(audits, 1);
  assert.equal(await countLegacy(DOG_A), 0);
});

// -----------------------------------------------------------------------------
// Replay
// -----------------------------------------------------------------------------
await test("callable real planned replay", async () => {
  await signIn(OP);
  const res = await callable("healthNutritionCreateMealLog")(
    plannedPayload({operation_id: "nutri-e2e-planned-1"}),
  );
  const data = res.data;
  assert.equal(data.was_no_op ?? data.wasNoOp, true);
  assert.equal(String(data.meal_id || data.mealId), plannedMealId);
  assert.equal(await countAuditsForEntity(plannedMealId), 1);
  // still one meal for this id
  const meal = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("meal_logs")
    .doc(plannedMealId)
    .get();
  assert.ok(meal.exists);
});

// -----------------------------------------------------------------------------
// Durable replay via HTTP (optional high-value)
// -----------------------------------------------------------------------------
await test("callable real durable replay após plano cancelled", async () => {
  await signIn(OP);
  const payload = plannedPayload({
    operation_id: "nutri-e2e-durable-1",
    fed_at: "2026-07-11T10:00:00.000Z",
  });
  const r1 = await callable("healthNutritionCreateMealLog")(payload);
  assert.equal(r1.data.was_no_op ?? r1.data.wasNoOp, false);
  const mealId = String(r1.data.meal_id || r1.data.mealId);

  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("nutrition_plans")
    .doc(PLAN_ID)
    .update({status: "cancelled"});

  const r2 = await callable("healthNutritionCreateMealLog")(payload);
  assert.equal(r2.data.was_no_op ?? r2.data.wasNoOp, true);
  assert.equal(String(r2.data.meal_id || r2.data.mealId), mealId);
  assert.equal(await countAuditsForEntity(mealId), 1);

  // restore plan
  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("nutrition_plans")
    .doc(PLAN_ID)
    .update({status: "active"});
});

// -----------------------------------------------------------------------------
// HttpsError wire: idempotency_conflict
// -----------------------------------------------------------------------------
await test(
  "callable real HttpsError wire: idempotency_conflict",
  async () => {
    await signIn(OP);
    await callable("healthNutritionCreateMealLog")(
      plannedPayload({
        operation_id: "nutri-e2e-idem",
        fed_at: "2026-07-14T10:00:00.000Z",
      }),
    );
    try {
      await callable("healthNutritionCreateMealLog")(
        plannedPayload({
          operation_id: "nutri-e2e-idem",
          offered_grams: 250,
          fed_at: "2026-07-14T10:00:00.000Z",
        }),
      );
      assert.fail("deveria falhar");
    } catch (e) {
      assertHttpsCode(e, "failed-precondition");
      assertDetailsCode(e, "idempotency_conflict");
      const wire = errorWire(e);
      log(`  wire_idempotency=${JSON.stringify(wire)}`);
    }
  },
);

// -----------------------------------------------------------------------------
// HttpsError wire: meal_occurrence_conflict
// -----------------------------------------------------------------------------
await test(
  "callable real HttpsError wire: meal_occurrence_conflict",
  async () => {
    await signIn(OP);
    const fedAt = "2026-07-16T10:00:00.000Z";
    await callable("healthNutritionCreateMealLog")(
      plannedPayload({
        operation_id: "nutri-e2e-conf-a",
        fed_at: fedAt,
      }),
    );
    try {
      await callable("healthNutritionCreateMealLog")(
        plannedPayload({
          operation_id: "nutri-e2e-conf-b",
          offered_grams: 200,
          acceptance: "partial",
          consumed_grams: 100,
          fed_at: fedAt,
        }),
      );
      assert.fail("deveria falhar");
    } catch (e) {
      assertHttpsCode(e, "failed-precondition");
      assertDetailsCode(e, "meal_occurrence_conflict");
      const wire = errorWire(e);
      log(`  wire_occurrence=${JSON.stringify(wire)}`);
    }
  },
);

// -----------------------------------------------------------------------------
// Invalid date via real transport
// -----------------------------------------------------------------------------
await test("callable real fed_at inválido → invalid-argument", async () => {
  await signIn(OP);
  try {
    await callable("healthNutritionCreateMealLog")(
      plannedPayload({
        operation_id: "nutri-e2e-baddate",
        fed_at: "not-a-date",
      }),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "invalid-argument");
  }
});

// -----------------------------------------------------------------------------
// Supplement via real callable — E2E completo com 7 fases
// GATE 5C.4B: documenta todos os asserts concretos da tabela deverdade
// -----------------------------------------------------------------------------
await test(
  "GATE 5C.4B E2E SupplementLog: creation, receipt, audit, replay, nulls",
  async () => {
    await signIn(OP);

    const opId = "nutri-e2e-supp-1";

    // 1. BASELINE
    const beforeLogs = await countSub(DOG_A, "supplement_logs");
    const beforeOps = await countSub(DOG_A, "nutrition_operations");
    const beforeLegacy = await countLegacy(DOG_A);
    const planDocBefore = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_plans")
      .doc(PLAN_ID)
      .get();
    const planRevisionBefore = planDocBefore.data()?.revision ?? 1;

    // 2. CREATE via real callable
    const res = await callable("healthNutritionCreateSupplementLog")({
      dog_id: DOG_A,
      supplement_name: "Omega E2E",
      dose: 5,
      unit: "ml",
      administered_at: "2026-07-17T14:00:00.000Z",
      operation_id: opId,
      nutrition_plan_id: null,
      supplement_regimen_id: null,
    });
    const data = res.data;
    const wasNoOp = data.was_no_op ?? data.wasNoOp;
    const logId = String(data.supplement_log_id || data.supplementLogId || data.entityId || "MISSING");

    // 3. AFTER delta validation
    const afterLogs = await countSub(DOG_A, "supplement_logs");
    const afterOps = await countSub(DOG_A, "nutrition_operations");
    const afterLegacy = await countLegacy(DOG_A);
    const planDocAfter = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_plans")
      .doc(PLAN_ID)
      .get();
    const planRevisionAfter = planDocAfter.data()?.revision ?? 1;

    assert.equal(wasNoOp, false, "Primeira execução não deve ser no-op");
    assert.equal(data.revision, 1);
    assert.ok(logId.startsWith("sl1_"), `Log ID deve ter prefixo sl1_: ${logId}`);
    assert.equal(afterLogs, beforeLogs + 1, "supplement_logs delta deve ser +1");
    assert.equal(afterOps, beforeOps + 1, "nutrition_operations delta deve ser +1");
    assert.equal(afterLegacy, beforeLegacy, "Legacy write delta deve ser ZERO");
    assert.equal(
      planRevisionAfter,
      planRevisionBefore,
      "NutritionPlan revision delta deve ser ZERO (plano inalterado)",
    );

    // 4. PERSISTED DOCUMENT CANONICAL FIELDS
    const snap = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("supplement_logs")
      .doc(logId)
      .get();
    assert.ok(snap.exists, `Documento SupplementLog ${logId} deve existir`);
    const doc = snap.data();
    assert.equal(snap.ref.path, `dogs/${DOG_A}/supplement_logs/${logId}`);
    assert.equal(doc?.dose, 5);
    assert.equal(doc?.supplement_name, "Omega E2E");
    assert.equal(doc?.unit, "ml");
    assert.equal(doc?.nutrition_plan_id, null, "nutrition_plan_id deve ser null no modo avulso");
    assert.equal(
      doc?.supplement_regimen_id,
      null,
      "supplement_regimen_id deve ser null no modo avulso",
    );
    assert.ok(doc?.recorded_by, "recorded_by presente");
    assert.ok(doc?.recorded_at, "recorded_at presente");
    assert.equal(doc?.revision, 1);
    assert.equal(doc?.schema_version, 1);
    assert.equal(doc?.source, "mobile_callable");

    // 5. RECEIPT VALIDATION
    const receiptSnap = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_operations")
      .where("operation_id", "==", opId)
      .get();
    assert.equal(receiptSnap.size, 1, "Receipt de operação deve existir para operation_id");
    const receiptData = receiptSnap.docs[0].data();
    assert.equal(
      receiptData?.operation_type,
      "create_supplement_log",
      "operation_type deve ser create_supplement_log",
    );
    assert.equal(receiptData?.operation_id, opId, "operation_id no receipt deve ser preservado");
    const receiptResult = receiptData?.result || {};
    assert.equal(
      receiptResult.was_no_op ?? receiptResult.wasNoOp,
      false,
      "Receipt result.was_no_op deve ser false",
    );
    assert.equal(
      String(receiptResult.entityId || receiptResult.logId || receiptResult.supplement_log_id || receiptResult.supplementLogId),
      logId,
    );

    // 6. AUDITLOG VALIDATION
    const auditSnap = await adminDb
      .collection("auditLogs")
      .where("entity_id", "==", logId)
      .get();
    assert.equal(auditSnap.size, 1, "AuditLog para o sl1_* deve existir");
    const auditDoc = auditSnap.docs[0];
    assert.equal(
      auditDoc.data()?.action,
      "health.nutrition.supplement_log.create",
      "AuditLog action deve ser health.nutrition.supplement_log.create",
    );
    assert.equal(auditDoc.data()?.entity_type, "supplement_log");
    assert.equal(auditDoc.data()?.entity_path, `dogs/${DOG_A}/supplement_logs/${logId}`);

    // 7. CONTROLLED REPLAY (mesmo operation_id → no-op)
    const replayRes = await callable("healthNutritionCreateSupplementLog")({
      dog_id: DOG_A,
      supplement_name: "Omega E2E",
      dose: 5,
      unit: "ml",
      administered_at: "2026-07-17T14:00:00.000Z",
      operation_id: opId,
      nutrition_plan_id: null,
      supplement_regimen_id: null,
    });
    const replayData = replayRes.data;
    assert.equal(
      replayData.was_no_op ?? replayData.wasNoOp,
      true,
      "Replay com mesmo operation_id deve retornar was_no_op = true",
    );
    assert.equal(
      String(replayData.supplement_log_id || replayData.supplementLogId),
      logId,
      "Replay deve retornar o mesmo logId",
    );
    assert.equal(
      await countSub(DOG_A, "supplement_logs"),
      afterLogs,
      "Replay supplement_logs delta deve ser ZERO",
    );
    assert.equal(
      await countSub(DOG_A, "nutrition_operations"),
      afterOps,
      "Replay nutrition_operations delta deve ser ZERO",
    );
    assert.equal(
      await countLegacy(DOG_A),
      beforeLegacy,
      "Replay legacy delta deve ser ZERO",
    );
  },
);

// -----------------------------------------------------------------------------
// Modo prescrito: nutrition_plan_id e supplement_regimen_id preenchidos
// -----------------------------------------------------------------------------
await test(
  "GATE 5C.4B E2E SupplementLog modo prescrito: vínculos preenchidos no documento",
  async () => {
    await signIn(OP);

    const opId = "nutri-e2e-supp-prescribed-1";
    const res = await callable("healthNutritionCreateSupplementLog")({
      dog_id: DOG_A,
      supplement_name: "Vitamina B12",
      dose: 1,
      unit: "tablet",
      administered_at: "2026-07-17T15:00:00.000Z",
      operation_id: opId,
      nutrition_plan_id: PLAN_ID,
      supplement_regimen_id: "reg-1",
      notes: "Aplicar via oral",
    });
    const data = res.data;
    const logId = String(data.supplement_log_id || data.supplementLogId);
    assert.ok(logId.startsWith("sl1_"));
    assert.equal(data.was_no_op ?? data.wasNoOp, false);

    const snap = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("supplement_logs")
      .doc(logId)
      .get();
    assert.ok(snap.exists);
    const doc = snap.data();
    assert.equal(doc?.nutrition_plan_id, PLAN_ID, "nutrition_plan_id deve ser preenchido");
    assert.equal(doc?.supplement_regimen_id, "reg-1", "supplement_regimen_id deve ser preenchido");
    assert.equal(doc?.notes, "Aplicar via oral");

    // AuditLog existe
    const auditSnap = await adminDb
      .collection("auditLogs")
      .where("entity_id", "==", logId)
      .get();
    assert.equal(auditSnap.size, 1);

    // Receipt existe
    const receiptSnap = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_operations")
      .where("operation_id", "==", opId)
      .get();
    assert.equal(receiptSnap.size, 1);
    assert.equal(receiptSnap.docs[0].data()?.operation_type, "create_supplement_log");
  },
);

// -----------------------------------------------------------------------------
// App Check off — already proven by all authorized calls without App Check token
// -----------------------------------------------------------------------------
await test(
  "App Check enforcement off (callable operável sem App Check token)",
  async () => {
    await signIn(OP);
    const res = await callable("healthNutritionCreateMealLog")({
      mode: "adhoc",
      dog_id: DOG_A,
      period: "extra",
      offered_grams: 80,
      acceptance: "full",
      fed_at: "2026-07-17T18:00:00.000Z",
      operation_id: "nutri-e2e-no-appcheck",
    });
    assert.equal(res.data.was_no_op ?? res.data.wasNoOp, false);
    assert.ok(String(res.data.meal_id || res.data.mealId).startsWith("ml1_"));
  },
);

// -----------------------------------------------------------------------------
// GATE 5C.3B — Ad Hoc Meal Execution Real E2E Emulator (Baseline, After, Slot Non-Interference, Replay)
// -----------------------------------------------------------------------------
await test(
  "GATE 5C.3B Real E2E: Ad hoc meal creation, baseline/after, slot non-interference, receipt, audit & replay",
  async () => {
    await signIn(OP);

    // 1. BASELINE
    const beforeMeals = await countSub(DOG_A, "meal_logs");
    const beforeOps = await countSub(DOG_A, "nutrition_operations");
    const beforeAudits = await adminDb
      .collection("auditLogs")
      .where("action", "==", "health.nutrition.meal_log.create_adhoc")
      .get();
    const beforeAuditsCount = beforeAudits.size;
    const beforeLegacy = await countLegacy(DOG_A);

    const planDocBefore = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_plans")
      .doc(PLAN_ID)
      .get();
    const planRevisionBefore = planDocBefore.data()?.revision ?? 1;

    const opId = "gate-5c3b-adhoc-e2e-op-1";
    const adhocPayload = {
      mode: "adhoc",
      dog_id: DOG_A,
      period: "afternoon",
      offered_grams: 150,
      consumed_grams: 150,
      acceptance: "full",
      fed_at: "2026-07-21T15:00:00.000Z",
      operation_id: opId,
      observations: "Ad hoc meal via canonical execution UI",
      attachment_refs: [],
    };

    // 2. EXECUTION VIA REAL CALLABLE
    const res = await callable("healthNutritionCreateMealLog")(adhocPayload);
    const data = res.data;
    const wasNoOp = data.was_no_op ?? data.wasNoOp;
    const mealId = String(data.meal_id || data.mealId);
    const occurrenceId = data.meal_occurrence_id ?? data.mealOccurrenceId;

    assert.equal(wasNoOp, false, "Primeira execução não deve ser no-op");
    assert.ok(mealId.startsWith("ml1_"), `MealLog ID deve ter prefixo ml1_: ${mealId}`);
    assert.equal(occurrenceId, null, "meal_occurrence_id deve ser null para adhoc");

    // 3. AFTER IN FIRESTORE EMULATOR
    const afterMeals = await countSub(DOG_A, "meal_logs");
    const afterOps = await countSub(DOG_A, "nutrition_operations");
    const afterAuditsCount = await countAuditsForEntity(mealId);
    const afterLegacy = await countLegacy(DOG_A);

    const planDocAfter = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_plans")
      .doc(PLAN_ID)
      .get();
    const planRevisionAfter = planDocAfter.data()?.revision ?? 1;

    assert.equal(afterMeals, beforeMeals + 1, "meal_logs delta deve ser +1");
    assert.equal(afterOps, beforeOps + 1, "nutrition_operations delta deve ser +1");
    assert.equal(afterAuditsCount, 1, "auditLogs count para o mealId deve ser 1");
    assert.equal(afterLegacy, beforeLegacy, "Legacy write delta deve ser ZERO");
    assert.equal(planRevisionAfter, planRevisionBefore, "NutritionPlan revision delta deve ser ZERO");

    // 4. PERSISTED MEALLOG CANONICAL FIELDS & NULL MATERIALIZATION
    const mealDoc = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("meal_logs")
      .doc(mealId)
      .get();
    assert.ok(mealDoc.exists, "Documento MealLog ml1_* deve existir no Firestore");
    const m = mealDoc.data();

    // Persisted null materialization for planned fields & path-based dog identity
    assert.equal(m?.dog_id, undefined, "dog_id NÃO é armazenado no corpo do documento (determinado pelo path)");
    assert.equal(mealDoc.ref.path, `dogs/${DOG_A}/meal_logs/${mealId}`);
    assert.equal(m?.plan_id, null, "plan_id deve ser persistido como null");
    assert.equal(m?.planned_meal_id, null, "planned_meal_id deve ser persistido como null");
    assert.equal(m?.meal_occurrence_id, null, "meal_occurrence_id deve ser persistido como null");
    assert.equal(m?.scheduled_for, null, "scheduled_for deve ser persistido como null");
    assert.equal(m?.prescription_amount_at_time, null, "prescription_amount_at_time deve ser persistido como null");

    // Ad hoc persisted canonical payload
    assert.equal(m?.period, "afternoon");
    assert.equal(m?.offered_grams, 150);
    assert.equal(m?.consumed_grams, 150);
    assert.equal(m?.acceptance, "full");
    assert.equal(m?.observations, "Ad hoc meal via canonical execution UI");
    assert.deepEqual(m?.attachment_refs, []);
    assert.ok(m?.recorded_by, "recorded_by presente");
    assert.ok(m?.recorded_at, "recorded_at presente");
    assert.equal(m?.revision, 1);
    assert.equal(m?.schema_version, 1);
    assert.equal(m?.source, "mobile_callable");

    // 5. RECEIPT VALIDATION
    const receiptSnap = await adminDb
      .collection("dogs")
      .doc(DOG_A)
      .collection("nutrition_operations")
      .where("operation_id", "==", opId)
      .get();
    assert.equal(receiptSnap.size, 1, "Receipt de operação deve existir");
    const receiptData = receiptSnap.docs[0].data();
    assert.equal(receiptData?.operation_type, "create_adhoc_meal");
    const receiptResult = receiptData?.result || {};
    assert.equal(receiptResult.was_no_op ?? receiptResult.wasNoOp, false);

    // 6. AUDITLOG VALIDATION
    const auditSnap = await adminDb
      .collection("auditLogs")
      .where("entity_id", "==", mealId)
      .get();
    assert.equal(auditSnap.size, 1, "AuditLog correspondente ao ml1_* deve existir");
    const auditDoc = auditSnap.docs[0];
    assert.equal(auditDoc.data()?.action, "health.nutrition.meal_log.create_adhoc");
    assert.equal(auditDoc.data()?.entity_type, "meal_log");
    assert.equal(auditDoc.data()?.entity_path, `dogs/${DOG_A}/meal_logs/${mealId}`);

    // 7. CONTROLLED REPLAY
    const replayRes = await callable("healthNutritionCreateMealLog")(adhocPayload);
    const replayData = replayRes.data;
    assert.equal(replayData.was_no_op ?? replayData.wasNoOp, true, "Replay deve retornar was_no_op = true");
    assert.equal(String(replayData.meal_id || replayData.mealId), mealId);

    assert.equal(await countSub(DOG_A, "meal_logs"), afterMeals, "Replay delta meal_logs deve ser ZERO");
    assert.equal(await countSub(DOG_A, "nutrition_operations"), afterOps, "Replay delta operations deve ser ZERO");
    assert.equal(await countLegacy(DOG_A), beforeLegacy, "Replay delta legacy deve ser ZERO");
  },
);

// -----------------------------------------------------------------------------
// Exports presence: if names wrong, earlier tests fail; document base URL
// -----------------------------------------------------------------------------
await test("exports callable na região southamerica-east1", async () => {
  // Successful httpsCallable to both names already proves export+region.
  assert.equal(REGION, "southamerica-east1");
  assert.ok(FUNCTIONS_BASE_URL.includes(REGION));
  log(`  base=${FUNCTIONS_BASE_URL}`);
  log(
    `  endpoints=` +
      `${FUNCTIONS_BASE_URL}/healthNutritionCreateMealLog , ` +
      `${FUNCTIONS_BASE_URL}/healthNutritionCreateSupplementLog`,
  );
});

// Cleanup client
await deleteClientApp(clientApp).catch(() => undefined);

// Summary
log("\n--- Summary ---");
for (const r of results) {
  log(`${r.ok ? "PASS" : "FAIL"} ${r.name}${r.detail ? " — " + r.detail : ""}`);
}
log(`failures=${failures}`);
log(`Node=${process.version}`);
log(
  `AUTH=${AUTH_HOST} FS=${FS_HOST} FN=${fnHost}:${fnPort} project=${PROJECT_ID}`,
);

if (failures > 0) {
  throw new Error(`Gate 2 callable transport E2E: ${failures} falha(s)`);
}
log("\nhealth_nutrition_callables_emulator_tests: all passed");
log("REAL_CALLABLE_TRANSPORT_E2E: OK");
log("ZERO_PRODUCTION: confirmed");
