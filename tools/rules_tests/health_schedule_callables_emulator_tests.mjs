/**
 * Health v1 — Fase 4E Gate 3
 * Integração real: Auth + Firestore + Functions Emulator.
 *
 * Invoca callables via cliente Firebase autenticado (httpsCallable),
 * não via handlers TypeScript internos.
 *
 * Execução (repo root):
 *   & 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only auth,firestore,functions "node tools/rules_tests/health_schedule_callables_emulator_tests.mjs"
 *
 * Nenhum dado aponta para produção: tudo no Emulator.
 */
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {initializeApp as initializeAdminApp, getApps, deleteApp} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore, FieldValue} from "firebase-admin/firestore";
import {initializeApp, deleteApp as deleteClientApp} from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  query,
  where,
} from "firebase/firestore";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID || "canil-gcm";
const REGION = "southamerica-east1";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const FN_HOST = process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";

const PASSWORD = "Gate3-Emulator-Only-Not-Prod!";
const DOG_A = "dog-gate3-a";
const DOG_OTHER = "dog-gate3-other";

const OP = {ra: "691755", uid: "uid-691755", email: "691755@gcm.com.br", name: "Operador Gate3"};
const OP_B = {ra: "691756", uid: "uid-691756", email: "691756@gcm.com.br", name: "Operador B Gate3"};
const NO_PERM = {ra: "800001", uid: "uid-800001", email: "800001@gcm.com.br", name: "Sem perm"};
const ADMIN = {ra: "1", uid: "uid-admin-1", email: "1@gcm.com.br", name: "Admin Gate3"};

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
  const cleaned = hostPort.replace(/^https?:\/\//, "");
  const [host, portStr] = cleaned.split(":");
  return {host, port: Number(portStr)};
}

function errorCode(err) {
  // Firebase client HttpsError codes: functions/unauthenticated, etc.
  const code = err?.code || err?.details?.code || "";
  const message = err?.message || "";
  const detailsCode = err?.customData?.details?.code || err?.details?.code;
  return {
    code: String(code),
    detailsCode: detailsCode ? String(detailsCode) : undefined,
    message: String(message),
  };
}

function assertHttpsCode(err, expectedSubstring) {
  const {code, detailsCode, message} = errorCode(err);
  const hay = `${code} ${detailsCode || ""} ${message}`.toLowerCase();
  assert.ok(
    hay.includes(String(expectedSubstring).toLowerCase()),
    `esperado conter "${expectedSubstring}", obtido code=${code} details=${detailsCode} msg=${message}`,
  );
}

/**
 * SEC-02A.1 — exige que a callable seja NEGADA, e pelo motivo certo.
 *
 * Asserir apenas "lançou" deixaria o teste passar por validação de payload ou
 * erro interno, mascarando exatamente a falha de autorização que ele existe
 * para provar.
 */
async function assertCallableDenied(name, payload) {
  let threw = false;
  try {
    await callable(name)(payload);
  } catch (e) {
    threw = true;
    assertHttpsCode(e, "permission-denied");
  }
  assert.ok(threw, `${name} deveria ter sido negada, mas foi permitida`);
}

function assertAppCode(err, appCode) {
  const {code, detailsCode, message} = errorCode(err);
  // callable details: { code: 'idempotency-conflict' } surfaces variously
  const details = err?.details || err?.customData?.details || {};
  const nested = details?.code || detailsCode;
  const hay = `${code} ${nested || ""} ${message} ${JSON.stringify(details)}`.toLowerCase();
  assert.ok(
    hay.includes(String(appCode).toLowerCase()),
    `esperado app code "${appCode}", obtido: ${hay}`,
  );
}

// --- Admin (seed / inspect) ---
if (!getApps().length) {
  initializeAdminApp({projectId: PROJECT_ID});
}
const adminAuth = getAdminAuth();
const adminDb = getAdminFirestore();

// --- Client ---
const clientApp = initializeApp({
  projectId: PROJECT_ID,
  apiKey: "fake-api-key-emulator",
  appId: "1:fake:web:gate3",
}, "gate3-client");

const auth = getAuth(clientApp);
const authParsed = parseHost(AUTH_HOST);
connectAuthEmulator(auth, `http://${authParsed.host}:${authParsed.port}`, {
  disableWarnings: true,
});

const firestore = getFirestore(clientApp);
const fsParsed = parseHost(FS_HOST);
connectFirestoreEmulator(firestore, fsParsed.host, fsParsed.port);

const functions = getFunctions(clientApp, REGION);
const fnParsed = parseHost(FN_HOST.includes(":") ? FN_HOST : `127.0.0.1:${FN_HOST}`);
// FIREBASE_FUNCTIONS_EMULATOR_HOST may be host:port or just used by CLI
let fnHost = "127.0.0.1";
let fnPort = 5001;
if (process.env.FUNCTIONS_EMULATOR === "true" || process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST) {
  const raw = process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
  const p = parseHost(raw.includes(":") ? raw : `127.0.0.1:${raw}`);
  fnHost = p.host;
  fnPort = p.port || 5001;
}
connectFunctionsEmulator(functions, fnHost, fnPort);

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
    if (e?.code !== "auth/uid-already-exists" && e?.code !== "auth/email-already-exists") {
      throw e;
    }
  }
  if (Object.keys(claims).length) {
    await adminAuth.setCustomUserClaims(user.uid, claims);
  }
}

async function signIn(user) {
  await signOut(auth).catch(() => undefined);
  const cred = await signInWithEmailAndPassword(auth, user.email, PASSWORD);
  // force refresh for custom claims
  await cred.user.getIdToken(true);
  return cred.user;
}

async function seedBase() {
  // access profiles
  await adminDb.collection("access_profiles").doc("operador_k9").set({
    status: "active",
    scope: "own_records",
    permissions: {
      health: {view: true, create: true, edit: true},
    },
  });
  await adminDb.collection("access_profiles").doc("sem_saude").set({
    status: "active",
    scope: "own_records",
    permissions: {
      health: {view: true, create: false, edit: false},
    },
  });
  await adminDb.collection("access_profiles").doc("administrador").set({
    status: "active",
    scope: "global",
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
    },
  });

  await adminDb.collection("users").doc(OP.ra).set({
    email: OP.email,
    name: OP.name,
    access_profile_id: "operador_k9",
    accessLevel: "operador",
  });
  await adminDb.collection("users").doc(OP_B.ra).set({
    email: OP_B.email,
    name: OP_B.name,
    access_profile_id: "operador_k9",
    accessLevel: "operador",
  });
  await adminDb.collection("users").doc(NO_PERM.ra).set({
    email: NO_PERM.email,
    name: NO_PERM.name,
    access_profile_id: "sem_saude",
    accessLevel: "operador",
  });
  await adminDb.collection("users").doc(ADMIN.ra).set({
    email: ADMIN.email,
    name: ADMIN.name,
    access_profile_id: "administrador",
    accessLevel: "admin",
    admin: true,
  });

  await adminDb.collection("dogs").doc(DOG_A).set({
    name: "Rex Gate3",
    conductor_ra: OP.ra,
    status: "active",
  });
  await adminDb.collection("dogs").doc(DOG_OTHER).set({
    name: "Other K9",
    conductor_ra: "999999",
    status: "active",
  });

  // OP_B access to same dog via active shift
  await adminDb.collection("active_shifts").doc(OP_B.ra).set({
    status: "active",
    service_dog_id: DOG_A,
    dogId: DOG_A,
    handlerId: OP_B.ra,
    auth_uid: OP_B.uid,
  });

  // SEC-02A: claims realistas. Em produção `humanClaims` SEMPRE emite `ra` e
  // `access_scope`; a fixture antes criava usuários sem claim alguma e as Rules
  // supriam com default 'global'. Sem isso, a leitura cliente passava a valer
  // por fail-open, não por autoridade real.
  await ensureUser(OP, {ra: OP.ra, access_scope: "own_records"});
  await ensureUser(OP_B, {ra: OP_B.ra, access_scope: "own_records"});
  await ensureUser(NO_PERM, {ra: NO_PERM.ra, access_scope: "own_records"});
  await ensureUser(ADMIN, {
    admin: true,
    role: "admin",
    ra: ADMIN.ra,
    access_scope: "global",
  });
}

async function countCollection(pathPrefix, field, value) {
  // Admin list: for auditLogs filter by action
  if (pathPrefix === "auditLogs") {
    const snap = await adminDb.collection("auditLogs")
      .where(field, "==", value)
      .get();
    return snap.size;
  }
  return 0;
}

async function listOps(dogId, scheduleId) {
  const snap = await adminDb
    .collection("dogs").doc(dogId)
    .collection("health_schedule").doc(scheduleId)
    .collection("operations")
    .get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

async function getSchedule(dogId, scheduleId) {
  const snap = await adminDb
    .collection("dogs").doc(dogId)
    .collection("health_schedule").doc(scheduleId)
    .get();
  return snap.exists ? snap.data() : null;
}

function createPayload(overrides = {}) {
  return {
    dogId: DOG_A,
    scheduleType: "vaccination",
    title: "Vacina Gate3",
    scheduledFor: "2026-09-01T12:00:00.000Z",
    timezone: "America/Sao_Paulo",
    idempotencyKey: "gate3-create-1",
    ...overrides,
  };
}

// =============================================================================
log(`\n=== Health Schedule Callables Emulator Gate 3 ===`);
log(`project=${PROJECT_ID}`);
log(`AUTH=${AUTH_HOST} FS=${FS_HOST} FN=${fnHost}:${fnPort} region=${REGION}`);
log(`GCLOUD_PROJECT=${process.env.GCLOUD_PROJECT || "(unset)"}`);
log(`FUNCTIONS_EMULATOR=${process.env.FUNCTIONS_EMULATOR || "(unset)"}`);

await seedBase();

// -----------------------------------------------------------------------------
// A. Create
// -----------------------------------------------------------------------------
await test("create sem auth → unauthenticated", async () => {
  await signOut(auth).catch(() => undefined);
  try {
    await callable("healthScheduleCreateManual")(createPayload({idempotencyKey: "no-auth"}));
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "unauthenticated");
  }
});

await test("create sem health.create → permission-denied", async () => {
  await signIn(NO_PERM);
  try {
    await callable("healthScheduleCreateManual")(
      createPayload({idempotencyKey: "no-perm"}),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }
});

await test("create com perm sem acesso ao K9 → permission-denied", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleCreateManual")(
      createPayload({dogId: DOG_OTHER, idempotencyKey: "no-dog"}),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }
});

let createdScheduleId;
let createdRevision;

await test("create autorizado → item + receipt + audit", async () => {
  await signIn(OP);
  const res = await callable("healthScheduleCreateManual")(createPayload());
  const data = res.data;
  assert.equal(data.wasNoOp, false);
  assert.equal(data.lifecycleStatus, "open");
  assert.equal(data.revision, 1);
  assert.ok(data.scheduleId);
  createdScheduleId = data.scheduleId;
  createdRevision = data.revision;

  const item = await getSchedule(DOG_A, createdScheduleId);
  assert.ok(item);
  assert.equal(item.source_type, "manual");
  assert.equal(item.lifecycle_status, "open");
  assert.equal(item.revision, 1);
  assert.equal(item.schema_version, 1);
  assert.ok(item.create_fingerprint);
  assert.ok(item.create_operation_id);
  assert.ok(item.recorded_by?.uid === OP.uid);
  assert.ok(item.created_at);

  const ops = await listOps(DOG_A, createdScheduleId);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].operation_type, "create_manual");
  assert.equal(ops[0].actor_uid, OP.uid);
  assert.ok(ops[0].fingerprint);
  assert.ok(ops[0].processed_at);

  const audits = await countCollection("auditLogs", "action", "health_schedule_created");
  assert.ok(audits >= 1);
});

await test("create same key same payload → replay + 1 audit", async () => {
  await signIn(OP);
  const before = await countCollection("auditLogs", "action", "health_schedule_created");
  const res = await callable("healthScheduleCreateManual")(createPayload());
  assert.equal(res.data.wasNoOp, true);
  assert.equal(res.data.scheduleId, createdScheduleId);
  const after = await countCollection("auditLogs", "action", "health_schedule_created");
  assert.equal(after, before);
  const ops = await listOps(DOG_A, createdScheduleId);
  assert.equal(ops.length, 1);
});

await test("create same key different payload → idempotency-conflict", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleCreateManual")(
      createPayload({title: "Titulo Diferente"}),
    );
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "idempotency-conflict");
  }
});

await test("create concorrente mesma key → 1 único item", async () => {
  await signIn(OP);
  const key = "gate3-concurrent-create";
  const payload = createPayload({idempotencyKey: key, title: "Concurrent"});
  const [a, b] = await Promise.allSettled([
    callable("healthScheduleCreateManual")(payload),
    callable("healthScheduleCreateManual")(payload),
  ]);
  const ok = [a, b].filter((r) => r.status === "fulfilled");
  assert.ok(ok.length >= 1, "ao menos uma deve ter sucesso");
  // both may succeed as no-op/create race; scheduleId must converge
  const ids = new Set();
  for (const r of [a, b]) {
    if (r.status === "fulfilled") ids.add(r.value.data.scheduleId);
  }
  // if one rejected with conflict-like, still only one doc for deterministic id
  const material = `${OP.uid}|${DOG_A}|create_manual|${key}`;
  const hash = createHash("sha256").update(material).digest("hex");
  const expectedId = `m_${hash.slice(0, 28)}`;
  const item = await getSchedule(DOG_A, expectedId);
  assert.ok(item, "item determinístico deve existir");
  assert.equal(item.title, "Concurrent");
  if (ids.size) {
    for (const id of ids) assert.equal(id, expectedId);
  }
});

// -----------------------------------------------------------------------------
// B. Update
// -----------------------------------------------------------------------------
await test("update open revision correta → sucesso + revision++", async () => {
  await signIn(OP);
  const res = await callable("healthScheduleUpdateOpen")({
    dogId: DOG_A,
    scheduleId: createdScheduleId,
    expectedRevision: createdRevision,
    operationId: "upd-A",
    title: "Titulo A",
  });
  assert.equal(res.data.wasNoOp, false);
  assert.equal(res.data.revision, createdRevision + 1);
  createdRevision = res.data.revision;
  const item = await getSchedule(DOG_A, createdScheduleId);
  assert.equal(item.title, "Titulo A");
  assert.equal(item.revision, createdRevision);
  const ops = await listOps(DOG_A, createdScheduleId);
  assert.ok(ops.some((o) => o.id === "upd-A" && o.operation_type === "update_open"));
});

await test("update B then retry A → A replay, B preserved", async () => {
  await signIn(OP);
  const revBeforeB = createdRevision;
  const b = await callable("healthScheduleUpdateOpen")({
    dogId: DOG_A,
    scheduleId: createdScheduleId,
    expectedRevision: revBeforeB,
    operationId: "upd-B",
    title: "Titulo B",
  });
  assert.equal(b.data.wasNoOp, false);
  createdRevision = b.data.revision;

  const retryA = await callable("healthScheduleUpdateOpen")({
    dogId: DOG_A,
    scheduleId: createdScheduleId,
    expectedRevision: revBeforeB, // stale — receipt deve vencer
    operationId: "upd-A",
    title: "Titulo A",
  });
  assert.equal(retryA.data.wasNoOp, true);
  const item = await getSchedule(DOG_A, createdScheduleId);
  assert.equal(item.title, "Titulo B");
  assert.equal(item.revision, createdRevision);
});

await test("update stale revision sem receipt → conflict", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleUpdateOpen")({
      dogId: DOG_A,
      scheduleId: createdScheduleId,
      expectedRevision: 1,
      operationId: "upd-stale-new",
      title: "Stale",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "conflict");
  }
});

await test("update same operationId patch diferente → idempotency-conflict", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleUpdateOpen")({
      dogId: DOG_A,
      scheduleId: createdScheduleId,
      expectedRevision: createdRevision,
      operationId: "upd-B",
      title: "Titulo B DIFERENTE",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "idempotency-conflict");
  }
});

await test("update cross-actor same operationId → idempotency-conflict", async () => {
  await signIn(OP_B);
  try {
    await callable("healthScheduleUpdateOpen")({
      dogId: DOG_A,
      scheduleId: createdScheduleId,
      expectedRevision: createdRevision,
      operationId: "upd-B",
      title: "Titulo B",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "idempotency-conflict");
  }
  const item = await getSchedule(DOG_A, createdScheduleId);
  assert.equal(item.title, "Titulo B");
});

await test("update item automático → permission-denied", async () => {
  const autoId = "auto-item-1";
  await adminDb.collection("dogs").doc(DOG_A)
    .collection("health_schedule").doc(autoId).set({
      schedule_type: "vaccination",
      title: "Auto",
      scheduled_for: new Date("2026-10-01T12:00:00.000Z"),
      timezone: "America/Sao_Paulo",
      lifecycle_status: "open",
      source_type: "preventive",
      revision: 1,
      schema_version: 1,
      created_at: new Date(),
      recorded_by: {uid: "system", name: "system", internal_role: "admin"},
    });
  await signIn(OP);
  try {
    await callable("healthScheduleUpdateOpen")({
      dogId: DOG_A,
      scheduleId: autoId,
      expectedRevision: 1,
      operationId: "upd-auto",
      title: "Hack",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "permission-denied");
  }
});

// -----------------------------------------------------------------------------
// C. Complete
// -----------------------------------------------------------------------------
let completeScheduleId;
await test("complete open → completed + server fields", async () => {
  await signIn(OP);
  const c = await callable("healthScheduleCreateManual")(
    createPayload({idempotencyKey: "gate3-for-complete", title: "To Complete"}),
  );
  completeScheduleId = c.data.scheduleId;
  const res = await callable("healthScheduleComplete")({
    dogId: DOG_A,
    scheduleId: completeScheduleId,
    operationId: "comp-1",
  });
  assert.equal(res.data.wasNoOp, false);
  assert.equal(res.data.lifecycleStatus, "completed");
  const item = await getSchedule(DOG_A, completeScheduleId);
  assert.equal(item.lifecycle_status, "completed");
  assert.ok(item.completed_at);
  assert.equal(item.completed_by?.uid, OP.uid);
  assert.ok(item.revision >= 2);
});

await test("complete retry → no-op sem re-audit/re-revision", async () => {
  await signIn(OP);
  const itemBefore = await getSchedule(DOG_A, completeScheduleId);
  const auditsBefore = await countCollection(
    "auditLogs",
    "action",
    "health_schedule_completed",
  );
  const res = await callable("healthScheduleComplete")({
    dogId: DOG_A,
    scheduleId: completeScheduleId,
    operationId: "comp-1",
  });
  assert.equal(res.data.wasNoOp, true);
  assert.equal(res.data.revision, itemBefore.revision);
  const itemAfter = await getSchedule(DOG_A, completeScheduleId);
  assert.equal(itemAfter.revision, itemBefore.revision);
  // completed_by preserved
  assert.equal(itemAfter.completed_by?.uid, OP.uid);
  const auditsAfter = await countCollection(
    "auditLogs",
    "action",
    "health_schedule_completed",
  );
  assert.equal(auditsAfter, auditsBefore);
});

await test("cancelled → complete = invalid-transition", async () => {
  await signIn(OP);
  const c = await callable("healthScheduleCreateManual")(
    createPayload({idempotencyKey: "gate3-cancel-then-complete", title: "X"}),
  );
  await callable("healthScheduleCancel")({
    dogId: DOG_A,
    scheduleId: c.data.scheduleId,
    operationId: "c-pre",
    cancelReason: "pre cancel",
  });
  try {
    await callable("healthScheduleComplete")({
      dogId: DOG_A,
      scheduleId: c.data.scheduleId,
      operationId: "comp-after-cancel",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "invalid-transition");
  }
});

// -----------------------------------------------------------------------------
// D. Cancel manual
// -----------------------------------------------------------------------------
let cancelScheduleId;
await test("cancel manual com reason → cancelled", async () => {
  await signIn(OP);
  const c = await callable("healthScheduleCreateManual")(
    createPayload({idempotencyKey: "gate3-for-cancel", title: "To Cancel"}),
  );
  cancelScheduleId = c.data.scheduleId;
  const res = await callable("healthScheduleCancel")({
    dogId: DOG_A,
    scheduleId: cancelScheduleId,
    operationId: "cancel-1",
    cancelReason: "  motivo normalizado  ",
  });
  assert.equal(res.data.wasNoOp, false);
  assert.equal(res.data.lifecycleStatus, "cancelled");
  const item = await getSchedule(DOG_A, cancelScheduleId);
  assert.equal(item.lifecycle_status, "cancelled");
  assert.ok(item.cancelled_at);
  assert.equal(item.cancelled_by?.uid, OP.uid);
  assert.ok(String(item.cancel_reason).includes("motivo"));
});

await test("cancel retry same reason → no-op", async () => {
  await signIn(OP);
  const auditsBefore = await countCollection(
    "auditLogs",
    "action",
    "health_schedule_cancelled",
  );
  const res = await callable("healthScheduleCancel")({
    dogId: DOG_A,
    scheduleId: cancelScheduleId,
    operationId: "cancel-1",
    cancelReason: "  motivo normalizado  ",
  });
  assert.equal(res.data.wasNoOp, true);
  const auditsAfter = await countCollection(
    "auditLogs",
    "action",
    "health_schedule_cancelled",
  );
  assert.equal(auditsAfter, auditsBefore);
});

await test("cancel same op different reason → idempotency-conflict", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleCancel")({
      dogId: DOG_A,
      scheduleId: cancelScheduleId,
      operationId: "cancel-1",
      cancelReason: "outro motivo",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "idempotency-conflict");
  }
});

await test("cancel other operationId after cancelled → already-cancelled", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleCancel")({
      dogId: DOG_A,
      scheduleId: cancelScheduleId,
      operationId: "cancel-2",
      cancelReason: "segunda tentativa",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertAppCode(e, "already-cancelled");
  }
});

// -----------------------------------------------------------------------------
// E. Cancel automático
// -----------------------------------------------------------------------------
const autoCancelId = "auto-cancel-item";
await adminDb.collection("dogs").doc(DOG_A)
  .collection("health_schedule").doc(autoCancelId).set({
    schedule_type: "vaccination",
    title: "Auto cancel target",
    scheduled_for: new Date("2026-11-01T12:00:00.000Z"),
    timezone: "America/Sao_Paulo",
    lifecycle_status: "open",
    source_type: "preventive",
    revision: 1,
    schema_version: 1,
    created_at: new Date(),
    recorded_by: {uid: "system", name: "system", internal_role: "admin"},
  });

await test("cancel automático operador comum → denied", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleCancel")({
      dogId: DOG_A,
      scheduleId: autoCancelId,
      operationId: "c-auto-op",
      cancelReason: "operador tenta",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }
});

await test("cancel automático autoridade admin real → allowed", async () => {
  await signIn(ADMIN);
  const res = await callable("healthScheduleCancel")({
    dogId: DOG_A,
    scheduleId: autoCancelId,
    operationId: "c-auto-admin",
    cancelReason: "admin cancela auto",
  });
  assert.equal(res.data.wasNoOp, false);
  const item = await getSchedule(DOG_A, autoCancelId);
  assert.equal(item.lifecycle_status, "cancelled");
});

// -----------------------------------------------------------------------------
// Path-safety
// -----------------------------------------------------------------------------
await test("operationId path-unsafe → validation", async () => {
  await signIn(OP);
  try {
    await callable("healthScheduleComplete")({
      dogId: DOG_A,
      scheduleId: createdScheduleId,
      operationId: "../escape",
    });
    assert.fail("deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "invalid-argument");
  }
});

// -----------------------------------------------------------------------------
// F. Client direct writes denied; callable (Admin path) works
// -----------------------------------------------------------------------------
await test("client direct create/update/delete health_schedule → permission-denied", async () => {
  await signIn(OP);
  const ref = doc(firestore, "dogs", DOG_A, "health_schedule", "client-direct-hack");
  try {
    await setDoc(ref, {
      schedule_type: "vaccination",
      title: "hack",
      lifecycle_status: "open",
      source_type: "manual",
      timezone: "America/Sao_Paulo",
      schema_version: 1,
    });
    assert.fail("create deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }

  // try update existing via client
  const existingRef = doc(firestore, "dogs", DOG_A, "health_schedule", createdScheduleId);
  try {
    await updateDoc(existingRef, {title: "client-hack"});
    assert.fail("update deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }

  try {
    await deleteDoc(existingRef);
    assert.fail("delete deveria falhar");
  } catch (e) {
    assertHttpsCode(e, "permission-denied");
  }

  // read still allowed
  const snap = await getDoc(existingRef);
  assert.equal(snap.exists(), true);
});

await test("callable ainda muta via Admin SDK após client deny", async () => {
  await signIn(OP);
  const c = await callable("healthScheduleCreateManual")(
    createPayload({idempotencyKey: "gate3-after-client-deny", title: "After deny"}),
  );
  assert.equal(c.data.wasNoOp, false);
  const item = await getSchedule(DOG_A, c.data.scheduleId);
  assert.ok(item);
});

// -----------------------------------------------------------------------------
// SEC-02A.1 — contrato estrito de estado de autorização
//
// Decisão humana: vínculo válido com o K9 NÃO compensa configuração de
// autorização ausente/inválida/malformada. Em todos os casos abaixo o chamador
// É o condutor registrado de DOG_A (conductor_ra: OP.ra na fixture) e ainda
// assim deve ser NEGADO, porque a camada declarativa está quebrada.
//
// A versão anterior deste hotfix permitia que esses casos passassem por prova
// de vínculo. Estes testes existem para impedir que essa política volte.
// -----------------------------------------------------------------------------

/** Restaura o estado canônico de autorização de OP entre os casos. */
async function restoreOpAuthState() {
  await adminDb.collection("users").doc(OP.ra).set({
    ra: OP.ra,
    access_profile_id: "operador_k9",
    access_scope: "own_records",
    auth_uid: OP.uid,
  }, {merge: true});
  // Recria o perfil INTEGRALMENTE (um dos casos o apaga), incluindo o mapa de
  // permissions — sem ele o gate de capability nega antes do de escopo, e o
  // caso ALLOW falharia pelo motivo errado.
  await adminDb.collection("access_profiles").doc("operador_k9").set({
    status: "active",
    scope: "own_records",
    permissions: {
      health: {view: true, create: true, edit: true},
    },
  });
}

await test("SEC-02A.1 espelho users/{ra} ausente → DENY mesmo sendo condutor", async () => {
  await adminDb.collection("users").doc(OP.ra).delete();
  await signIn(OP);
  try {
    await assertCallableDenied(
      "healthScheduleCreateManual",
      createPayload({idempotencyKey: "sec02a1-no-mirror", title: "No mirror"}),
    );
  } finally {
    await restoreOpAuthState();
  }
});

await test("SEC-02A.1 usuário soft-deleted → DENY mesmo sendo condutor", async () => {
  await adminDb.collection("users").doc(OP.ra).set(
    {deleted_at: new Date()}, {merge: true},
  );
  await signIn(OP);
  try {
    await assertCallableDenied(
      "healthScheduleCreateManual",
      createPayload({idempotencyKey: "sec02a1-soft-deleted", title: "Deleted"}),
    );
  } finally {
    await adminDb.collection("users").doc(OP.ra).update({
      deleted_at: FieldValue.delete(),
    });
    await restoreOpAuthState();
  }
});

await test("SEC-02A.1 access_profile ausente → DENY mesmo sendo condutor", async () => {
  await adminDb.collection("access_profiles").doc("operador_k9").delete();
  await signIn(OP);
  try {
    await assertCallableDenied(
      "healthScheduleCreateManual",
      createPayload({idempotencyKey: "sec02a1-no-profile", title: "No profile"}),
    );
  } finally {
    await restoreOpAuthState();
  }
});

await test("SEC-02A.1 perfil inativo → DENY mesmo sendo condutor", async () => {
  await adminDb.collection("access_profiles").doc("operador_k9").set(
    {status: "inactive"}, {merge: true},
  );
  await signIn(OP);
  try {
    await assertCallableDenied(
      "healthScheduleCreateManual",
      createPayload({idempotencyKey: "sec02a1-inactive", title: "Inactive"}),
    );
  } finally {
    await restoreOpAuthState();
  }
});

await test("SEC-02A.1 scope ausente/malformado → DENY mesmo sendo condutor", async () => {
  for (const [i, scope] of [undefined, "ownRecords", "", "unit"].entries()) {
    await adminDb.collection("access_profiles").doc("operador_k9").set(
      scope === undefined
        ? {status: "active", scope: FieldValue.delete()}
        : {status: "active", scope},
      {merge: true},
    );
    // espelho e claim também sem valor válido, senão restringiriam legitimamente
    await adminDb.collection("users").doc(OP.ra).set({
      access_scope: FieldValue.delete(),
      accessScope: FieldValue.delete(),
    }, {merge: true});
    await signIn(OP);
    try {
      await assertCallableDenied(
        "healthScheduleCreateManual",
        createPayload({
          idempotencyKey: `sec02a1-bad-scope-${i}`,
          title: "Bad scope",
        }),
      );
    } finally {
      await restoreOpAuthState();
    }
  }
});

await test("SEC-02A.1 estado válido own_records + próprio K9 → ALLOW (não regrediu)", async () => {
  await restoreOpAuthState();
  await signIn(OP);
  const c = await callable("healthScheduleCreateManual")(
    createPayload({idempotencyKey: "sec02a1-valid-allow", title: "Valid"}),
  );
  assert.equal(c.data.wasNoOp, false);
  assert.ok(await getSchedule(DOG_A, c.data.scheduleId));
});

// -----------------------------------------------------------------------------
// Physical receipt identity sample
// -----------------------------------------------------------------------------
await test("receipts contêm actor_uid + operation_type + fingerprint", async () => {
  const ops = await listOps(DOG_A, createdScheduleId);
  assert.ok(ops.length >= 2);
  for (const op of ops) {
    assert.ok(op.actor_uid, "actor_uid");
    assert.ok(op.operation_type, "operation_type");
    assert.ok(op.fingerprint, "fingerprint");
    assert.ok(op.processed_at, "processed_at");
  }
});

// Cleanup client app (emulator data discarded on exit)
await signOut(auth).catch(() => undefined);
await deleteClientApp(clientApp).catch(() => undefined);

// Summary
log("\n=== SUMMARY ===");
for (const r of results) {
  log(`${r.ok ? "PASS" : "FAIL"}  ${r.name}${r.detail ? " — " + r.detail : ""}`);
}
log(`\nTotal: ${results.length}  Passed: ${results.length - failures}  Failed: ${failures}`);

if (failures > 0) {
  process.exitCode = 1;
  throw new Error(`Gate 3 emulator: ${failures} falha(s)`);
}
log("\nhealth_schedule_callables_emulator_tests: all passed");
