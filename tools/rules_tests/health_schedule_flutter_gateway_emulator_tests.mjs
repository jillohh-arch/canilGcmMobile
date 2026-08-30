/**
 * Health v1 — Fase 4E Gate 4
 * Happy path integrado: FirebaseFunctionsHealthScheduleMutationGateway (Dart)
 * → Functions/Auth/Firestore Emulator.
 *
 * Orquestra:
 * 1. seed (padrão Gate 3)
 * 2. flutter test do gateway permanente (codec + mapper + callables reais)
 * 3. inspeção Admin de receipts + audits
 *
 * Execução (repo root):
 *   & 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only auth,firestore,functions "node tools/rules_tests/health_schedule_flutter_gateway_emulator_tests.mjs"
 *
 * Zero produção: emulators:exec isola o project canil-gcm no Emulator.
 */
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {initializeApp as initializeAdminApp, getApps} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore} from "firebase-admin/firestore";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "canil-gcm";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const FN_HOST = process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";

const PASSWORD = "Gate3-Emulator-Only-Not-Prod!";
const DOG_A = "dog-gate4-flutter-a";
const OP = {
  ra: "691755",
  uid: "uid-691755",
  email: "691755@gcm.com.br",
  name: "Operador Gate4 Flutter",
};

function log(msg) {
  console.log(msg);
}

function assertEmulatorHosts() {
  for (const [label, host] of [
    ["AUTH", AUTH_HOST],
    ["FS", FS_HOST],
    ["FN", FN_HOST],
  ]) {
    const h = String(host);
    assert.ok(
      h.includes("127.0.0.1") || h.includes("localhost"),
      `${label} host não é Emulator local: ${h}`,
    );
  }
  log(`EMULATOR_ONLY_OK project=${PROJECT_ID} AUTH=${AUTH_HOST} FS=${FS_HOST} FN=${FN_HOST}`);
}

if (!getApps().length) {
  initializeAdminApp({projectId: PROJECT_ID});
}
const adminAuth = getAdminAuth();
const adminDb = getAdminFirestore();

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

async function seedBase() {
  await adminDb.collection("access_profiles").doc("operador_k9").set({
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
  await adminDb.collection("dogs").doc(DOG_A).set({
    name: "Rex Gate4 Flutter",
    conductor_ra: OP.ra,
    status: "active",
  });
  await ensureUser(OP);
  log("seed: operador + dog + access_profile ok");
}

function runFlutterGatewayTest() {
  const testFile = path.join(
    "test",
    "features",
    "health",
    "data",
    "schedule",
    "firebase_functions_health_schedule_mutation_gateway_emulator_test.dart",
  );
  log(`\n=== flutter test ${testFile} ===`);
  const env = {
    ...process.env,
    HEALTH_SCHEDULE_EMULATOR_INTEGRATION: "1",
    GCLOUD_PROJECT: PROJECT_ID,
    FIREBASE_AUTH_EMULATOR_HOST: AUTH_HOST,
    FIRESTORE_EMULATOR_HOST: FS_HOST,
    FIREBASE_FUNCTIONS_EMULATOR_HOST: FN_HOST,
    GATE4_DOG_ID: DOG_A,
    GATE4_OP_EMAIL: OP.email,
    GATE4_OP_PASSWORD: PASSWORD,
  };
  const result = spawnSync(
    "flutter",
    ["test", testFile, "--reporter", "expanded"],
    {
      cwd: REPO_ROOT,
      env,
      encoding: "utf8",
      shell: true,
      maxBuffer: 20 * 1024 * 1024,
    },
  );
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    throw new Error(`flutter test falhou com exit ${result.status}`);
  }
  return result.stdout || "";
}

function parseGate4Results(stdout) {
  const out = {};
  for (const line of stdout.split(/\r?\n/)) {
    const m1 = line.match(/GATE4_RESULT\s+(\{.*\})\s*$/);
    if (m1) Object.assign(out, JSON.parse(m1[1]));
    const m2 = line.match(/GATE4_RESULT_CANCEL\s+(\{.*\})\s*$/);
    if (m2) Object.assign(out, JSON.parse(m2[1]));
  }
  return out;
}

async function getSchedule(dogId, scheduleId) {
  const snap = await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId)
    .get();
  return snap.exists ? snap.data() : null;
}

async function listOps(dogId, scheduleId) {
  const snap = await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId)
    .collection("operations")
    .get();
  return snap.docs.map((d) => ({id: d.id, ...(d.data() || {})}));
}

async function countAuditsForSchedule(scheduleId) {
  const snap = await adminDb
    .collection("auditLogs")
    .where("entity_id", "==", scheduleId)
    .get();
  return snap.docs.map((d) => ({id: d.id, ...(d.data() || {})}));
}

function assertReceipt(op, {
  operationType,
  actorUid,
  wasNoOp,
  revision,
}) {
  assert.equal(op.operation_type, operationType, "operation_type");
  assert.equal(op.actor_uid, actorUid, "actor_uid");
  assert.ok(op.fingerprint, "fingerprint");
  assert.ok(op.processed_at, "processed_at");
  const result = op.result || {};
  if (wasNoOp !== undefined) {
    assert.equal(result.wasNoOp, wasNoOp, "result.wasNoOp");
  }
  if (revision !== undefined) {
    assert.equal(result.revision, revision, "result.revision");
  }
}

async function verifyPhysical(results) {
  const dogId = results.dogId || DOG_A;
  const scheduleId = results.scheduleIdComplete;
  const scheduleCancel = results.scheduleIdCancel;
  assert.ok(scheduleId, "scheduleIdComplete ausente no stdout do flutter test");
  assert.ok(scheduleCancel, "scheduleIdCancel ausente no stdout do flutter test");

  // Complete path document
  const completed = await getSchedule(dogId, scheduleId);
  assert.ok(completed, "schedule complete path missing");
  assert.equal(completed.lifecycle_status, "completed");
  assert.equal(completed.revision, 3);
  assert.equal(completed.source_type, "manual");
  assert.ok(completed.completed_at, "completed_at");
  assert.ok(completed.completed_by?.uid, "completed_by.uid");

  const ops = await listOps(dogId, scheduleId);
  const byId = Object.fromEntries(ops.map((o) => [o.id, o]));
  assert.ok(results.createKey, "createKey complete-path");
  assert.ok(byId[results.createKey], `create receipt missing id=${results.createKey} have=${Object.keys(byId)}`);
  assert.ok(byId[results.updateOp], "update receipt");
  assert.ok(byId[results.completeOp], "complete receipt");

  assertReceipt(byId[results.createKey], {
    operationType: "create_manual",
    actorUid: OP.uid,
    wasNoOp: false,
    revision: 1,
  });
  // update receipt stores final result of first successful apply
  assertReceipt(byId[results.updateOp], {
    operationType: "update_open",
    actorUid: OP.uid,
    revision: 2,
  });
  assertReceipt(byId[results.completeOp], {
    operationType: "complete",
    actorUid: OP.uid,
    revision: 3,
  });

  // One logical audit per operation type (create/update/complete) — no replay extras
  const audits = await countAuditsForSchedule(scheduleId);
  const actions = audits.map((a) => a.action).sort();
  log(`audits complete-path: ${JSON.stringify(actions)}`);
  assert.equal(
    audits.filter((a) => a.action === "health_schedule_created").length,
    1,
    "create audit único",
  );
  assert.equal(
    audits.filter((a) => a.action === "health_schedule_updated").length,
    1,
    "update audit único",
  );
  assert.equal(
    audits.filter((a) => a.action === "health_schedule_completed").length,
    1,
    "complete audit único",
  );

  // Cancel path
  const cancelled = await getSchedule(dogId, scheduleCancel);
  assert.ok(cancelled, "schedule cancel path missing");
  assert.equal(cancelled.lifecycle_status, "cancelled");
  assert.equal(cancelled.revision, 2);
  assert.equal(cancelled.cancel_reason, "motivo gate4 emulator");
  assert.ok(cancelled.cancelled_at, "cancelled_at");
  assert.ok(cancelled.cancelled_by?.uid, "cancelled_by.uid");

  const cancelOps = await listOps(dogId, scheduleCancel);
  const cancelById = Object.fromEntries(cancelOps.map((o) => [o.id, o]));
  assert.ok(cancelById[results.cancelOp], "cancel receipt");
  assertReceipt(cancelById[results.cancelOp], {
    operationType: "cancel",
    actorUid: OP.uid,
  });

  const cancelAudits = await countAuditsForSchedule(scheduleCancel);
  assert.equal(
    cancelAudits.filter((a) => a.action === "health_schedule_created").length,
    1,
    "cancel-path create audit único",
  );
  assert.equal(
    cancelAudits.filter((a) => a.action === "health_schedule_cancelled").length,
    1,
    "cancel audit único (replay não duplica)",
  );

  // Total schedules for dog: exactly 2 (complete path + cancel path)
  const all = await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .get();
  assert.equal(all.size, 2, "exatamente 2 schedules no Emulator");

  log("physical receipts + audits OK");
  log(
    JSON.stringify({
      scheduleIdComplete: scheduleId,
      scheduleIdCancel: scheduleCancel,
      completePathRevision: completed.revision,
      cancelPathRevision: cancelled.revision,
      completeAudits: audits.length,
      cancelAudits: cancelAudits.length,
      operationsComplete: ops.length,
      operationsCancel: cancelOps.length,
    }),
  );
}

// ---------------------------------------------------------------------------
log("\n=== Health Schedule Flutter Gateway Emulator Gate 4 ===");
assertEmulatorHosts();
await seedBase();
const stdout = runFlutterGatewayTest();
const results = parseGate4Results(stdout);
log(`parsed results: ${JSON.stringify(results)}`);
await verifyPhysical(results);
log("\nGATE4_EMULATOR_HAPPY_PATH: all checks passed");
log("ZERO_PRODUCTION: emulators:exec only");
