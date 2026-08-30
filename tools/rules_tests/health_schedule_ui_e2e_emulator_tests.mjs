/**
 * Health v1 — Fase 4E Gate 5
 * Orquestra seed Emulator + UI E2E (integration_test no Android físico)
 * e inspeção Admin pós-mutações.
 *
 * Execução (repo root, emulators já sobem via emulators:exec OU em background):
 *
 *   # Preferido (isolado):
 *   & 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only auth,firestore,functions "node tools/rules_tests/health_schedule_ui_e2e_emulator_tests.mjs"
 *
 *   # Ou com emulators já rodando + device:
 *   $env:HEALTH_SCHEDULE_UI_E2E_STANDALONE='1'
 *   node tools/rules_tests/health_schedule_ui_e2e_emulator_tests.mjs
 *
 * Zero produção: hosts Emulator locais + adb reverse; sem claims/dogs reais.
 */
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {initializeApp as initializeAdminApp, getApps} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {getFirestore as getAdminFirestore, Timestamp} from "firebase-admin/firestore";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "canil-gcm";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const FN_HOST = process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";

const PASSWORD = "Gate5-Emulator-Only-Not-Prod!";
const DOG_A = "dog-gate5-ui-a";
const OP = {
  ra: "691755",
  uid: "uid-691755",
  email: "691755@gcm.com.br",
  name: "Operador Gate5 UI",
};

const SCREENSHOT_DIR = path.join(
  REPO_ROOT,
  "temp",
  "gate5_ui_e2e_screenshots",
);

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
  log(
    `EMULATOR_ONLY_OK project=${PROJECT_ID} AUTH=${AUTH_HOST} FS=${FS_HOST} FN=${FN_HOST}`,
  );
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
    // Garante senha do seed mesmo se o uid já existia de Gates anteriores.
    await adminAuth.updateUser(user.uid, {
      password: PASSWORD,
      displayName: user.name,
      emailVerified: true,
    });
  }
  const nextClaims = {ra: user.ra, ...claims};
  await adminAuth.setCustomUserClaims(user.uid, nextClaims);
}

function recordedBy() {
  return {
    uid: OP.uid,
    name: OP.name,
    internal_role: "condutor",
  };
}

function scheduleDoc({
  title,
  lifecycle = "open",
  sourceType = "manual",
  revision = 0,
  scheduleType = "vaccination",
  cancelReason,
  extra = {},
}) {
  const now = Timestamp.now();
  const scheduled = Timestamp.fromDate(
    new Date(Date.now() + 2 * 60 * 60 * 1000),
  );
  const base = {
    schedule_type: scheduleType,
    title,
    scheduled_for: scheduled,
    timezone: "America/Sao_Paulo",
    lifecycle_status: lifecycle,
    source_type: sourceType,
    created_at: now,
    recorded_by: recordedBy(),
    schema_version: 1,
    revision,
    ...extra,
  };
  if (lifecycle === "completed") {
    base.completed_at = now;
    base.completed_by = recordedBy();
  }
  if (lifecycle === "cancelled") {
    base.cancelled_at = now;
    base.cancelled_by = recordedBy();
    base.cancel_reason = cancelReason || "seed cancelado";
  }
  if (sourceType !== "manual") {
    base.source_id = "seed-protocol-1";
  }
  return base;
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
    name: "Rex Gate5 UI",
    conductor_ra: OP.ra,
    status: "active",
    active: true,
  });

  // Item automático open (matriz UI: só Concluir)
  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_schedule")
    .doc("seed-auto-open")
    .set(
      scheduleDoc({
        title: "Dose protocolo automática",
        sourceType: "treatment_protocol",
        scheduleType: "dose",
        revision: 1,
      }),
    );

  // Terminais (sem menu)
  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_schedule")
    .doc("seed-completed")
    .set(
      scheduleDoc({
        title: "Item já concluído (seed)",
        lifecycle: "completed",
        revision: 2,
      }),
    );
  await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_schedule")
    .doc("seed-cancelled")
    .set(
      scheduleDoc({
        title: "Item já cancelado (seed)",
        lifecycle: "cancelled",
        revision: 2,
        cancelReason: "seed terminal",
      }),
    );

  await ensureUser(OP);
  log("seed: operador + dog + auto open + terminais ok");
}

function adbReverse() {
  const device =
    process.env.ANDROID_SERIAL ||
    process.env.GATE5_ANDROID_DEVICE ||
    "";
  const adbBase = device ? ["-s", device] : [];
  for (const port of [9099, 8080, 5001]) {
    const r = spawnSync(
      "adb",
      [...adbBase, "reverse", `tcp:${port}`, `tcp:${port}`],
      {encoding: "utf8", shell: true},
    );
    if (r.stdout) process.stdout.write(r.stdout);
    if (r.stderr) process.stderr.write(r.stderr);
    if (r.status !== 0) {
      log(`WARN adb reverse ${port}: exit ${r.status}`);
    } else {
      log(`adb reverse tcp:${port} ok`);
    }
  }
}

function resolveAndroidDevice() {
  if (process.env.GATE5_ANDROID_DEVICE) {
    return process.env.GATE5_ANDROID_DEVICE;
  }
  const r = spawnSync("adb", ["devices"], {encoding: "utf8", shell: true});
  const lines = (r.stdout || "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("List of"));
  const devices = lines
    .map((l) => l.split(/\s+/)[0])
    .filter((id) => id && !id.includes("emulator"));
  // prefer wireless / physical
  const physical = devices.find((d) => d.includes("adb-") || d.length > 8);
  return physical || devices[0] || "";
}

function runHostUiE2eTest() {
  const testFile = path.join(
    "test",
    "features",
    "health",
    "presentation",
    "schedule",
    "health_schedule_ui_e2e_emulator_test.dart",
  );
  log(`\n=== flutter test ${testFile} (host UI E2E Emulator) ===`);
  const env = {
    ...process.env,
    HEALTH_SCHEDULE_UI_E2E: "1",
    GCLOUD_PROJECT: PROJECT_ID,
    FIREBASE_AUTH_EMULATOR_HOST: AUTH_HOST,
    FIRESTORE_EMULATOR_HOST: FS_HOST,
    FIREBASE_FUNCTIONS_EMULATOR_HOST: FN_HOST,
    GATE5_DOG_ID: DOG_A,
    GATE5_OP_EMAIL: OP.email,
    GATE5_OP_PASSWORD: PASSWORD,
    GATE5_OP_RA: OP.ra,
    GATE5_SCREENSHOT_DIR: SCREENSHOT_DIR,
  };
  const result = spawnSync(
    "flutter",
    ["test", testFile, "--reporter", "expanded"],
    {
      cwd: REPO_ROOT,
      env,
      encoding: "utf8",
      shell: true,
      maxBuffer: 40 * 1024 * 1024,
    },
  );
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    throw new Error(`UI E2E flutter test falhou com exit ${result.status}`);
  }
  return result.stdout || "";
}

async function listOpenSchedules() {
  const snap = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_schedule")
    .where("lifecycle_status", "==", "open")
    .get();
  return snap.docs.map((d) => ({id: d.id, ...(d.data() || {})}));
}

async function listAllSchedules() {
  const snap = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_schedule")
    .get();
  return snap.docs.map((d) => ({id: d.id, ...(d.data() || {})}));
}

function parseMarkers(stdout) {
  const out = {};
  for (const line of stdout.split(/\r?\n/)) {
    const m = line.match(/GATE5_UI_E2E\s+(\{.*\})\s*$/);
    if (m) Object.assign(out, JSON.parse(m[1]));
  }
  return out;
}

async function main() {
  assertEmulatorHosts();
  await seedBase();

  // adb reverse opcional (Android visual harness); UI E2E host usa 127.0.0.1 direto.
  try {
    adbReverse();
  } catch (e) {
    log(`WARN adb reverse: ${e?.message || e}`);
  }
  const deviceId = resolveAndroidDevice();
  log(`ANDROID_DEVICE=${deviceId || "(none — host UI E2E only)"}`);

  const stdout = runHostUiE2eTest();
  const markers = parseMarkers(stdout);
  log(`markers: ${JSON.stringify(markers, null, 2)}`);

  assert.ok(markers.createId, "createId ausente no marker");
  assert.ok(markers.cancelId, "cancelId ausente no marker");
  assert.equal(markers.createRevision, 1, "create revision deve ser 1");
  assert.equal(markers.editRevision, 2, "edit revision deve ser 2");

  const all = await listAllSchedules();
  const byId = Object.fromEntries(all.map((d) => [d.id, d]));

  const created = byId[markers.createId];
  assert.ok(created, "doc create não encontrado no Emulator");
  // após complete, lifecycle completed
  assert.equal(
    created.lifecycle_status,
    "completed",
    "create item deve estar completed após UI complete",
  );
  assert.ok(
    Number(created.revision) >= 3,
    `revision pós-complete esperada >=3, obtida ${created.revision}`,
  );

  const cancelled = byId[markers.cancelId];
  assert.ok(cancelled, "doc cancel não encontrado");
  assert.equal(cancelled.lifecycle_status, "cancelled");
  assert.ok(
    String(cancelled.cancel_reason || "").length > 0,
    "cancel_reason no Emulator",
  );

  const open = await listOpenSchedules();
  const openIds = new Set(open.map((d) => d.id));
  assert.ok(!openIds.has(markers.createId), "completed não deve estar open");
  assert.ok(!openIds.has(markers.cancelId), "cancelled não deve estar open");
  assert.ok(
    openIds.has("seed-auto-open"),
    "item automático open deve permanecer (se não concluído)",
  );

  log("\nUI E2E FULL EMULATOR: PASS");
  log("ZERO_PRODUCTION: emulators only + adb reverse");
  log(`screenshots dir (se geradas): ${SCREENSHOT_DIR}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
