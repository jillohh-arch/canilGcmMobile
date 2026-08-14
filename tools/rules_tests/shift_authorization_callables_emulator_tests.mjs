/**
 * HEALTH-V1-OP-AUTH — Gate E
 * Prova de TRANSPORTE REAL da autorização operacional de turno:
 *   Auth Emulator + Firestore Emulator + Functions Emulator
 *
 * Invoca `shiftExecuteAuthorizedCommand` via cliente Firebase autenticado
 * (`httpsCallable`) com ID token real. NÃO chama handlers internos: o que está
 * sob teste é a cadeia inteira —
 *
 *   client → callable transport → auth context → shiftExecuteAuthorizedCommand
 *   → operational_restrictions canônicas → guard → transação → audit/receipt
 *   → Firestore
 *
 * Os testes unitários já provam a lógica isoladamente. Aqui provamos que ela
 * sobrevive ao transporte: códigos de aplicação atravessam `details`, a
 * identidade vem do token (não do payload), e uma negativa não deixa resíduo
 * NENHUM no Firestore real.
 *
 * Execução (repo root, após npm --prefix functions run build):
 *   firebase emulators:exec --project canil-gcm --config firebase.json \
 *     --only auth,firestore,functions \
 *     "node tools/rules_tests/shift_authorization_callables_emulator_tests.mjs"
 *
 * Zero produção.
 */
import assert from "node:assert/strict";
import {
  initializeApp as initializeAdminApp,
  getApps,
} from "firebase-admin/app";
import {getAuth as getAdminAuth} from "firebase-admin/auth";
import {
  getFirestore as getAdminFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {initializeApp, deleteApp as deleteClientApp} from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {connectFirestoreEmulator, getFirestore} from "firebase/firestore";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";

const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCLOUD_PROJECT_ID || "canil-gcm";
const REGION = "southamerica-east1";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const PASSWORD = "GateE-OpAuth-Emulator-Only-Not-Prod!";

const CALLABLE = "shiftExecuteAuthorizedCommand";

const DOG_A = "dog-opauth-e2e-a";
const DOG_B = "dog-opauth-e2e-b";
const DOG_FOREIGN = "dog-opauth-e2e-foreign";
const VEHICLE_ID = "VTR-OPAUTH-E2E";

const OP = {
  ra: "720001",
  uid: "uid-720001",
  email: "720001@gcm.com.br",
  name: "Operador OpAuth E2E",
};
const MATE = {
  ra: "720002",
  uid: "uid-720002",
  email: "720002@gcm.com.br",
  name: "Colega Guarnicao",
};
const OUTSIDER = {
  ra: "720003",
  uid: "uid-720003",
  email: "720003@gcm.com.br",
  name: "Sem Acesso Ao K9",
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

/** Extrai o código de aplicação do erro do callable, atravessando o SDK. */
function errorWire(err) {
  const details =
    err?.details ?? err?.customData?.details ?? err?.customData ?? {};
  const detailsCode =
    (details && typeof details === "object" && details.code) || undefined;
  return {
    code: String(err?.code || ""),
    detailsCode: detailsCode ? String(detailsCode) : undefined,
    details,
    message: String(err?.message || ""),
  };
}

function assertAppCode(err, appCode) {
  const wire = errorWire(err);
  assert.strictEqual(
    wire.detailsCode,
    appCode,
    `esperado app code "${appCode}", wire=${JSON.stringify(wire)}`,
  );
}

function assertTransportCode(err, expected) {
  const wire = errorWire(err);
  assert.ok(
    wire.code.includes(expected),
    `esperado transport code conter "${expected}", wire=${JSON.stringify(wire)}`,
  );
}

// --- Guard: precisa estar em emuladores ---
assert.ok(
  process.env.FIRESTORE_EMULATOR_HOST,
  "FIRESTORE_EMULATOR_HOST obrigatório (use firebase emulators:exec)",
);
assert.ok(
  process.env.FIREBASE_AUTH_EMULATOR_HOST,
  "FIREBASE_AUTH_EMULATOR_HOST obrigatório (use firebase emulators:exec)",
);

// --- Admin (seed / inspeção) ---
if (!getApps().length) {
  initializeAdminApp({projectId: PROJECT_ID});
}
const adminAuth = getAdminAuth();
const adminDb = getAdminFirestore();

// --- Cliente ---
const clientApp = initializeApp(
  {
    projectId: PROJECT_ID,
    apiKey: "fake-api-key-emulator",
    appId: "1:fake:web:gateE-opauth",
  },
  "gateE-opauth-client",
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

/** Login real no Auth Emulator → ID token real que atravessa o transporte. */
async function signIn(user) {
  await signOut(auth).catch(() => undefined);
  const cred = await signInWithEmailAndPassword(auth, user.email, PASSWORD);
  const token = await cred.user.getIdToken(true);
  assert.ok(token && token.length > 20, "ID token Auth Emulator vazio");
  return cred.user;
}

function ts(iso) {
  return Timestamp.fromDate(new Date(iso));
}

function restrictionDoc({
  level = "absolute",
  status = "active",
  activities = [],
  expectedEnd = null,
  issuedAt = "2026-08-10T12:00:00.000Z",
  description = "Restricao registrada por profissional externo.",
  extra = {},
} = {}) {
  return {
    level,
    status,
    category: "injury",
    description,
    activities_restricted: activities,
    issued_at: ts(issuedAt),
    ...(expectedEnd ? {expected_end: ts(expectedEnd)} : {}),
    schema_version: 1,
    ...extra,
  };
}

async function clearCollection(ref) {
  const snap = await ref.get();
  for (const d of snap.docs) await d.ref.delete();
}

/** Limpa TODO o estado operacional e clínico entre cenários. */
async function resetState() {
  for (const dogId of [DOG_A, DOG_B, DOG_FOREIGN]) {
    await clearCollection(
      adminDb.collection("dogs").doc(dogId).collection("operational_restrictions"),
    );
  }
  for (const ra of [OP.ra, MATE.ra, OUTSIDER.ra]) {
    await adminDb.collection("active_shifts").doc(ra).delete().catch(() => {});
  }
  await clearCollection(adminDb.collection("shift_logs"));
  await clearCollection(adminDb.collection("shift_operations"));
  await clearCollection(adminDb.collection("auditLogs"));
  await clearCollection(
    adminDb.collection("vehicle_crews").doc(VEHICLE_ID).collection("members"),
  );
  await adminDb.collection("vehicle_crews").doc(VEHICLE_ID).delete().catch(() => {});
}

async function seedBase() {
  // K9 vinculados ao operador → autoriza `requireDogRecordAccess` pela via
  // "condutor do K9", que é a via real de quem inicia turno.
  for (const dogId of [DOG_A, DOG_B]) {
    await adminDb.collection("dogs").doc(dogId).set({
      name: dogId,
      status: "active",
      conductorRa: OP.ra,
      handlerId: OP.ra,
    });
  }
  // K9 de outro condutor, sem vínculo com OUTSIDER.
  await adminDb.collection("dogs").doc(DOG_FOREIGN).set({
    name: DOG_FOREIGN,
    status: "active",
    conductorRa: MATE.ra,
    handlerId: MATE.ra,
  });

  await adminDb.collection("access_profiles").doc("operador_k9_opauth").set({
    status: "active",
    scope: "own_records",
    permissions: {health: {view: true, create: true}},
  });

  for (const u of [OP, MATE, OUTSIDER]) {
    await adminDb.collection("users").doc(u.ra).set({
      ra: u.ra,
      name: u.name,
      email: u.email,
      access_profile_id: "operador_k9_opauth",
      access_scope: "own_records",
      status: "active",
    });
  }
}

async function seedRestriction(dogId, id, payload) {
  await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection("operational_restrictions")
    .doc(id)
    .set(payload);
}

/** Snapshot de display dizendo "operacional" — NUNCA deve autorizar. */
async function seedSummaryOperational(dogId) {
  await adminDb
    .collection("dogs")
    .doc(dogId)
    .collection("health_summary")
    .doc("current")
    .set({
      projection_status: "ready",
      readiness_status: "operational",
      readiness_label: "Operacional",
      active_restrictions: [],
      restriction_count: {absolute: 0, partial: 0, attention: 0},
      updated_at: ts("2026-08-13T11:59:00.000Z"),
      schema_version: 1,
    });
}

async function seedActiveShift({
  ra = OP.ra,
  dogId = DOG_A,
  shiftId = "shift-e2e-1",
  withVehicle = false,
} = {}) {
  await adminDb
    .collection("active_shifts")
    .doc(ra)
    .set({
      shiftId,
      handlerId: ra,
      auth_uid: `uid-${ra}`,
      handler_email: `${ra}@gcm.com.br`,
      dogId,
      service_dog_id: dogId,
      status: "active",
      startedAt: ts("2026-08-13T08:00:00.000Z"),
      updatedAt: ts("2026-08-13T08:00:00.000Z"),
      ...(withVehicle
        ? {
            vehicle_id: VEHICLE_ID,
            vehicle_crew_id: VEHICLE_ID,
            crew_id: VEHICLE_ID,
            crew_role: "motorista",
            crew_status: "active",
          }
        : {}),
    });
  await adminDb.collection("shift_logs").doc(shiftId).set({
    id: shiftId,
    handlerId: ra,
    initialDogId: dogId,
    currentDogId: dogId,
    service_dog_id: dogId,
    status: "active",
    startedAt: ts("2026-08-13T08:00:00.000Z"),
    updatedAt: ts("2026-08-13T08:00:00.000Z"),
  });
}

async function seedCrew({dogId = DOG_A} = {}) {
  await adminDb.collection("vehicle_crews").doc(VEHICLE_ID).set({
    id: VEHICLE_ID,
    vehicle_id: VEHICLE_ID,
    crew_size: 3,
    service_dog_id: dogId,
    titular_handler_id: OP.ra,
    active: true,
    created_at: ts("2026-08-13T08:00:00.000Z"),
    updated_at: ts("2026-08-13T08:00:00.000Z"),
  });
}

// ── Inspeção de estado ────────────────────────────────────────────────────────

async function activeShift(ra = OP.ra) {
  const snap = await adminDb.collection("active_shifts").doc(ra).get();
  return snap.exists ? snap.data() : null;
}

async function crewDoc() {
  const snap = await adminDb.collection("vehicle_crews").doc(VEHICLE_ID).get();
  return snap.exists ? snap.data() : null;
}

async function countCollection(name) {
  const snap = await adminDb.collection(name).get();
  return snap.size;
}

async function shiftAuditLogs() {
  const snap = await adminDb.collection("auditLogs").get();
  return snap.docs
    .map((d) => d.data())
    .filter((d) => String(d.action || "").startsWith("shift_"));
}

function opId(suffix) {
  return `e2e-op-${suffix}`;
}

async function invoke(payload) {
  const res = await callable(CALLABLE)(payload);
  return res.data;
}

async function invokeExpectingFailure(payload) {
  try {
    await invoke(payload);
  } catch (e) {
    return e;
  }
  throw new Error("esperava falha do callable, obteve sucesso");
}

/** Prova que NENHUM documento operacional foi tocado. */
async function assertNoOperationalWrites(ra = OP.ra) {
  const shift = await activeShift(ra);
  assert.strictEqual(shift, null, "active_shifts não pode existir");
  assert.strictEqual(
    await countCollection("shift_logs"),
    0,
    "shift_logs não pode ter documentos",
  );
  assert.strictEqual(
    await countCollection("vehicle_crews"),
    0,
    "vehicle_crews não pode ter documentos",
  );
  assert.strictEqual(
    await countCollection("shift_operations"),
    0,
    "receipt não pode existir",
  );
}

// ─────────────────────────────────────────────────────────────────────────────

await ensureUser(OP, {ra: OP.ra, access_scope: "own_records"});
await ensureUser(MATE, {ra: MATE.ra, access_scope: "own_records"});
await ensureUser(OUTSIDER, {ra: OUTSIDER.ra, access_scope: "own_records"});
await seedBase();

// ── E-01 ─────────────────────────────────────────────────────────────────────
await test("E-01 sem restrições: startShift executa via transporte real", async () => {
  await resetState();
  await signIn(OP);

  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("01"),
    startedAt: "2026-08-13T12:00:00.000Z",
  });

  assert.strictEqual(data.ok, true);
  assert.strictEqual(data.decision, "allowed");
  assert.strictEqual(data.wasNoOp, false);
  assert.strictEqual(data.dogId, DOG_A);

  // Writes esperados, exatamente uma vez.
  const shift = await activeShift();
  assert.ok(shift, "active_shifts precisa existir");
  assert.strictEqual(shift.service_dog_id, DOG_A);
  assert.strictEqual(shift.status, "active");
  // Identidade derivada do TOKEN, não do payload.
  assert.strictEqual(shift.handlerId, OP.ra);
  assert.strictEqual(shift.auth_uid, OP.uid);
  assert.strictEqual(await countCollection("shift_logs"), 1);
  assert.strictEqual(await countCollection("shift_operations"), 1);

  const audits = await shiftAuditLogs();
  assert.strictEqual(audits.length, 1, "um audit");
  assert.strictEqual(audits[0].metadata.authority, "operational_restrictions");
});

// ── E-02 ─────────────────────────────────────────────────────────────────────
await test("E-02 attention active: executa e retorna notice, sem bloqueio", async () => {
  await resetState();
  await seedRestriction(DOG_A, "r-att", restrictionDoc({level: "attention"}));
  await signIn(OP);

  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("02"),
  });

  assert.strictEqual(data.decision, "allowed");
  assert.strictEqual(data.acknowledgementRecorded, false);
  assert.strictEqual(data.restrictions.length, 1, "notice retornado");
  assert.strictEqual(data.restrictions[0].level, "attention");
  assert.ok(await activeShift(), "turno criado");
});

// ── E-03 ─────────────────────────────────────────────────────────────────────
await test("E-03 partial sem ciência: acknowledgement_required, zero writes, zero receipt", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-partial",
    restrictionDoc({level: "partial", activities: ["busca", "guarda"]}),
  );
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("03"),
  });

  assertAppCode(err, "partial_acknowledgement_required");
  const wire = errorWire(err);
  assert.deepStrictEqual(wire.details.pendingAcknowledgementIds, ["r-partial"]);
  // As restrições viajam para a UI poder montar o alerta.
  assert.strictEqual(wire.details.restrictions.length, 1);
  await assertNoOperationalWrites();
});

// ── E-04 ─────────────────────────────────────────────────────────────────────
await test("E-04 retry mesmo operationId com ciência: executa exatamente uma vez", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-partial",
    restrictionDoc({level: "partial", activities: ["busca"]}),
  );
  await signIn(OP);

  // 1ª: sem ciência → negado, sem resíduo.
  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("04"),
  });
  assertAppCode(err, "partial_acknowledgement_required");
  await assertNoOperationalWrites();

  // 2ª: MESMO operationId, agora com ciência.
  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("04"),
    acknowledgedRestrictionIds: ["r-partial"],
  });

  assert.strictEqual(data.decision, "allowed_with_restrictions");
  assert.strictEqual(data.acknowledgementRecorded, true);
  assert.strictEqual(data.wasNoOp, false);

  // Exatamente uma vez, cada coisa.
  assert.strictEqual(await countCollection("shift_logs"), 1, "um shift_log");
  assert.strictEqual(
    await countCollection("shift_operations"),
    1,
    "um receipt",
  );
  const audits = await shiftAuditLogs();
  assert.strictEqual(audits.length, 1, "um audit de ciência");
  assert.deepStrictEqual(audits[0].metadata.partial_acknowledged, [
    "r-partial",
  ]);

  // A ciência NÃO altera a restrição clínica.
  const restr = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("operational_restrictions")
    .doc("r-partial")
    .get();
  assert.strictEqual(restr.data().status, "active", "restrição segue ativa");
});

// ── E-05 ─────────────────────────────────────────────────────────────────────
await test("E-05 absolute active: bloqueia, zero writes operacionais", async () => {
  await resetState();
  await seedRestriction(DOG_A, "r-abs", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("05"),
  });

  assertAppCode(err, "absolute_restriction_active");
  assertTransportCode(err, "failed-precondition");
  await assertNoOperationalWrites();
  assert.strictEqual((await shiftAuditLogs()).length, 0, "nenhum audit");
});

// ── E-06 / E-07 ──────────────────────────────────────────────────────────────
await test("E-06 absolute ended: permite", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-ended",
    restrictionDoc({level: "absolute", status: "ended"}),
  );
  await signIn(OP);

  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("06"),
  });
  assert.strictEqual(data.decision, "allowed");
  assert.ok(await activeShift());
});

await test("E-07 absolute cancelled: permite", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-cancel",
    restrictionDoc({level: "absolute", status: "cancelled"}),
  );
  await signIn(OP);

  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("07"),
  });
  assert.strictEqual(data.decision, "allowed");
  assert.ok(await activeShift());
});

// ── E-08 ─────────────────────────────────────────────────────────────────────
await test("E-08 absolute active com expected_end no passado: CONTINUA bloqueando", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-overdue",
    restrictionDoc({
      level: "absolute",
      expectedEnd: "2026-07-01T00:00:00.000Z", // vencido
    }),
  );
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("08"),
  });

  assertAppCode(err, "absolute_restriction_active");
  const wire = errorWire(err);
  assert.strictEqual(
    wire.details.restrictions[0].isOverdue,
    true,
    "sinaliza reavaliação pendente",
  );
  await assertNoOperationalWrites();
});

// ── E-09 ─────────────────────────────────────────────────────────────────────
await test("E-09 partial + absolute: absolute prevalece", async () => {
  await resetState();
  await seedRestriction(
    DOG_A,
    "r-p",
    restrictionDoc({level: "partial", activities: ["faro"]}),
  );
  await seedRestriction(DOG_A, "r-a", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("09"),
    // Mesmo reconhecendo a parcial, a absoluta bloqueia.
    acknowledgedRestrictionIds: ["r-p"],
  });

  assertAppCode(err, "absolute_restriction_active");
  await assertNoOperationalWrites();
});

// ── E-10 ─────────────────────────────────────────────────────────────────────
await test("E-10 LOAD-BEARING: summary diz operational + absolute canônica ativa → BLOQUEIA", async () => {
  await resetState();
  // Projeção de display desatualizada dizendo que está tudo bem...
  await seedSummaryOperational(DOG_A);
  // ...mas a autoridade canônica diz o contrário.
  await seedRestriction(DOG_A, "r-abs", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("10"),
  });

  assertAppCode(err, "absolute_restriction_active");
  await assertNoOperationalWrites();

  // E o summary permanece intocado — o guard não escreve display.
  const summary = await adminDb
    .collection("dogs")
    .doc(DOG_A)
    .collection("health_summary")
    .doc("current")
    .get();
  assert.strictEqual(summary.data().readiness_status, "operational");
});

// ── Evidência inconclusiva → fail-closed ─────────────────────────────────────
const malformed = [
  ["level inválido", restrictionDoc({level: "quarentena_total"})],
  ["status inválido", restrictionDoc({level: "absolute", status: "suspensa"})],
  [
    "timestamp inválido",
    {...restrictionDoc({level: "absolute"}), issued_at: 12345},
  ],
  [
    "description vazia",
    restrictionDoc({level: "absolute", description: "   "}),
  ],
  [
    "partial sem activities_restricted",
    restrictionDoc({level: "partial", activities: []}),
  ],
  [
    "formato inesperado em activities_restricted",
    {...restrictionDoc({level: "partial"}), activities_restricted: "busca"},
  ],
];

for (const [label, payload] of malformed) {
  await test(
    `E-FC ${label} → restrictions_unavailable (nunca "sem restrição")`,
    async () => {
      await resetState();
      await seedRestriction(DOG_A, "r-bad", payload);
      await signIn(OP);

      const err = await invokeExpectingFailure({
        action: "start_shift",
        dogId: DOG_A,
        operationId: opId(`fc-${label.replace(/\W+/g, "-")}`),
      });

      assertAppCode(err, "restrictions_unavailable");
      // Distinto de bloqueio clínico: a UI precisa diferenciar.
      const wire = errorWire(err);
      assert.notStrictEqual(wire.detailsCode, "absolute_restriction_active");
      await assertNoOperationalWrites();
    },
  );
}

// ── switch_dog ───────────────────────────────────────────────────────────────
await test("E-SW-01 switch_dog sem restrição: fan-out atinge TODOS os membros", async () => {
  await resetState();
  await seedActiveShift({ra: OP.ra, dogId: DOG_A, withVehicle: true});
  await seedActiveShift({
    ra: MATE.ra,
    dogId: DOG_A,
    shiftId: "shift-e2e-mate",
    withVehicle: true,
  });
  await seedCrew({dogId: DOG_A});
  await signIn(OP);

  const data = await invoke({
    action: "switch_dog",
    dogId: DOG_B,
    operationId: opId("sw01"),
  });
  assert.strictEqual(data.decision, "allowed");

  // Todos recebem o mesmo novo dogId — nenhum estado parcial.
  const own = await activeShift(OP.ra);
  const mate = await activeShift(MATE.ra);
  assert.strictEqual(own.service_dog_id, DOG_B, "próprio atualizado");
  assert.strictEqual(mate.service_dog_id, DOG_B, "colega atualizado (fan-out)");
  const crew = await crewDoc();
  assert.strictEqual(crew.service_dog_id, DOG_B, "guarnição atualizada");
});

await test("E-SW-02 switch_dog com absolute: NENHUM membro alterado (atomicidade)", async () => {
  await resetState();
  await seedActiveShift({ra: OP.ra, dogId: DOG_A, withVehicle: true});
  await seedActiveShift({
    ra: MATE.ra,
    dogId: DOG_A,
    shiftId: "shift-e2e-mate",
    withVehicle: true,
  });
  await seedCrew({dogId: DOG_A});
  await seedRestriction(DOG_B, "r-abs", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "switch_dog",
    dogId: DOG_B,
    operationId: opId("sw02"),
  });
  assertAppCode(err, "absolute_restriction_active");

  // Estado íntegro: ou todos mudam, ou nenhum. Aqui, nenhum.
  assert.strictEqual((await activeShift(OP.ra)).service_dog_id, DOG_A);
  assert.strictEqual((await activeShift(MATE.ra)).service_dog_id, DOG_A);
  assert.strictEqual((await crewDoc()).service_dog_id, DOG_A);
  assert.strictEqual(
    await countCollection("shift_operations"),
    0,
    "nenhum receipt",
  );
});

// ── assume_vehicle ───────────────────────────────────────────────────────────
await test("E-AV-01 assume_vehicle sem restrição: embarca o K9 autorizado", async () => {
  await resetState();
  await seedActiveShift({ra: OP.ra, dogId: DOG_A});
  await signIn(OP);

  const data = await invoke({
    action: "assume_vehicle",
    dogId: DOG_A,
    operationId: opId("av01"),
    role: "k9",
    vehicle: {id: VEHICLE_ID, label: "VTR E2E", crewSize: 3},
  });
  assert.strictEqual(data.decision, "allowed");

  const crew = await crewDoc();
  assert.strictEqual(crew.service_dog_id, DOG_A);
  assert.strictEqual(crew.active, true);
  const member = await adminDb
    .collection("vehicle_crews")
    .doc(VEHICLE_ID)
    .collection("members")
    .doc(OP.ra)
    .get();
  assert.strictEqual(member.data().dog_id, DOG_A);
  assert.strictEqual(member.data().role, "k9");
});

await test("E-AV-02 assume_vehicle com absolute: guarnição intocada", async () => {
  await resetState();
  await seedActiveShift({ra: OP.ra, dogId: DOG_A});
  await seedRestriction(DOG_A, "r-abs", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "assume_vehicle",
    dogId: DOG_A,
    operationId: opId("av02"),
    role: "k9",
    vehicle: {id: VEHICLE_ID, label: "VTR E2E", crewSize: 3},
  });
  assertAppCode(err, "absolute_restriction_active");

  assert.strictEqual(
    await countCollection("vehicle_crews"),
    0,
    "guarnição não criada",
  );
});

// ── Autenticação / autoria ───────────────────────────────────────────────────
await test("E-AUTH-01 caller não autenticado é rejeitado", async () => {
  await resetState();
  await signOut(auth).catch(() => undefined);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("auth01"),
  });
  assertTransportCode(err, "unauthenticated");
  await assertNoOperationalWrites();
});

await test("E-AUTH-02 payload não falsifica identidade: RA vem do token", async () => {
  await resetState();
  await signIn(OP);

  // Tenta abrir turno no RA de outro operador via payload.
  const data = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("auth02"),
    handlerId: MATE.ra,
    ra: MATE.ra,
    handler_email: MATE.email,
    auth_uid: MATE.uid,
  });
  assert.strictEqual(data.decision, "allowed");

  // O turno é do TOKEN, não do payload.
  assert.strictEqual(await activeShift(MATE.ra), null, "RA alheio intocado");
  const own = await activeShift(OP.ra);
  assert.ok(own, "turno criado no RA do token");
  assert.strictEqual(own.handlerId, OP.ra);
  assert.strictEqual(own.auth_uid, OP.uid);
});

await test("E-AUTH-03 caller sem acesso ao K9 é negado", async () => {
  await resetState();
  await signIn(OUTSIDER);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_FOREIGN,
    operationId: opId("auth03"),
  });
  assertTransportCode(err, "permission-denied");
  await assertNoOperationalWrites(OUTSIDER.ra);
});

await test("E-AUTH-04 cliente não influencia decisão clínica pelo payload", async () => {
  await resetState();
  await seedRestriction(DOG_A, "r-abs", restrictionDoc({level: "absolute"}));
  await signIn(OP);

  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("auth04"),
    // Tentativa de auto-autorização.
    restrictionStatus: "none",
    readinessStatus: "operational",
    override: true,
    acknowledgedRestrictionIds: ["r-abs"],
  });

  assertAppCode(err, "absolute_restriction_active");
  await assertNoOperationalWrites();
});

// ── Integridade do comando ───────────────────────────────────────────────────
await test("E-CMD-01 action desconhecida é rejeitada", async () => {
  await resetState();
  await signIn(OP);
  const err = await invokeExpectingFailure({
    action: "delete_everything",
    dogId: DOG_A,
    operationId: opId("cmd01"),
  });
  assertTransportCode(err, "invalid-argument");
  await assertNoOperationalWrites();
});

await test("E-CMD-02 dogId ausente/vazio é rejeitado", async () => {
  await resetState();
  await signIn(OP);
  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: "   ",
    operationId: opId("cmd02"),
  });
  assertTransportCode(err, "invalid-argument");
  await assertNoOperationalWrites();
});

await test("E-CMD-03 reuso de operationId com payload diferente → conflito", async () => {
  await resetState();
  await signIn(OP);

  await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("cmd03"),
  });

  // Mesmo operationId, outro K9 → fingerprint incompatível.
  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: DOG_B,
    operationId: opId("cmd03"),
  });
  assertAppCode(err, "idempotency_conflict");

  // O turno original permanece com o K9 original.
  assert.strictEqual((await activeShift()).service_dog_id, DOG_A);
});

await test("E-CMD-04 replay idêntico é no-op, não duplica", async () => {
  await resetState();
  await signIn(OP);

  const first = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("cmd04"),
  });
  assert.strictEqual(first.wasNoOp, false);

  const second = await invoke({
    action: "start_shift",
    dogId: DOG_A,
    operationId: opId("cmd04"),
  });
  assert.strictEqual(second.wasNoOp, true, "replay reconhecido");
  assert.strictEqual(second.shiftId, first.shiftId);

  assert.strictEqual(await countCollection("shift_logs"), 1, "um shift_log");
  assert.strictEqual((await shiftAuditLogs()).length, 1, "um audit");
});

// ── K9 inexistente ───────────────────────────────────────────────────────────
await test("E-CMD-05 K9 inexistente é negado antes de qualquer write", async () => {
  await resetState();
  await signIn(OP);
  const err = await invokeExpectingFailure({
    action: "start_shift",
    dogId: "dog-que-nao-existe",
    operationId: opId("cmd05"),
  });
  assertTransportCode(err, "not-found");
  await assertNoOperationalWrites();
});

// Cleanup
await resetState();
await deleteClientApp(clientApp).catch(() => undefined);

log("\n--- Summary ---");
for (const r of results) {
  log(`${r.ok ? "PASS" : "FAIL"} ${r.name}${r.detail ? " — " + r.detail : ""}`);
}
log(`failures=${failures}`);
log(`Node=${process.version}`);
log(`AUTH=${AUTH_HOST} FS=${FS_HOST} FN=${fnHost}:${fnPort} project=${PROJECT_ID}`);

if (failures > 0) {
  throw new Error(`Gate E callable transport E2E: ${failures} falha(s)`);
}
log("\nshift_authorization_callables_emulator_tests: all passed");
log("REAL_CALLABLE_TRANSPORT_E2E: OK");
log("ZERO_PRODUCTION: confirmed");
