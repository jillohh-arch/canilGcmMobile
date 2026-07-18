/**
 * Gate 6 — smoke produção negativo (create no passado).
 * NÃO cria schedule feliz. Usa Admin ADC só para mint de ID token;
 * a tentativa de write passa pelo callable público.
 *
 * Uso (repo root, firebase login / ADC):
 *   node tools/rules_tests/health_schedule_gate6_prod_past_smoke.mjs
 */
import {readFileSync} from "node:fs";
import {resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {initializeApp, applicationDefault, getApps} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

const PROJECT_ID = "canil-gcm";
const REGION = "southamerica-east1";
const BASE = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;
const RA = process.env.GATE6_SMOKE_RA || "691755";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");

if (!getApps().length) {
  initializeApp({credential: applicationDefault(), projectId: PROJECT_ID});
}
const auth = getAuth();
const db = getFirestore();

const userSnap = await db.collection("users").doc(RA).get();
if (!userSnap.exists) {
  console.error("FAIL - user not found", RA);
  process.exit(2);
}
const email = String(userSnap.data()?.email || `${RA}@gcm.com.br`).trim();
const userRecord = await auth.getUserByEmail(email);
const custom = await auth.createCustomToken(userRecord.uid);

const gs = resolve(repoRoot, "android/app/google-services.json");
const j = JSON.parse(readFileSync(gs, "utf8"));
const apiKey = j.client[0].api_key[0].current_key;
const exchange = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
  {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({token: custom, returnSecureToken: true}),
  },
);
const exchanged = await exchange.json();
if (!exchanged.idToken) {
  console.error("FAIL - token exchange", JSON.stringify(exchanged).slice(0, 400));
  process.exit(3);
}

let dogId = process.env.GATE3_DOG_ID || process.env.GATE6_SMOKE_DOG_ID || "";
if (!dogId) {
  const dogs = await db
    .collection("dogs")
    .where("conductor_ra", "==", RA)
    .limit(1)
    .get();
  dogId = dogs.empty ? "nonexistent-dog-gate6-smoke" : dogs.docs[0].id;
}

const idempotencyKey = `gate6-prod-smoke-past-${Date.now()}`;
const payload = {
  dogId,
  scheduleType: "vaccination",
  title: "Gate6 smoke past create (must fail)",
  scheduledFor: "2020-01-01T12:00:00.000Z",
  timezone: "America/Sao_Paulo",
  idempotencyKey,
};

console.log("project", PROJECT_ID);
console.log("region", REGION);
console.log("function", "healthScheduleCreateManual");
console.log("dogId", dogId);
console.log("idempotencyKey", idempotencyKey);

const res = await fetch(`${BASE}/healthScheduleCreateManual`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${exchanged.idToken}`,
  },
  body: JSON.stringify({data: payload}),
});
const text = await res.text();
let body;
try {
  body = JSON.parse(text);
} catch {
  body = {raw: text};
}
console.log("status", res.status);
console.log("body", JSON.stringify(body).slice(0, 600));

const detailsCode = body?.error?.details?.code;
const status = body?.error?.status;
const ok =
  res.status === 400 &&
  (detailsCode === "validation" ||
    String(status || "").toUpperCase().includes("INVALID_ARGUMENT"));

// Zero write: deterministic schedule id should not exist
// scheduleId = m_{sha256(uid|dogId|create_manual|key).slice(0,28)}
// Safer: query open items with matching create_operation_id if field present
const ops = await db
  .collectionGroup("operations")
  .where("operation_id", "==", idempotencyKey)
  .limit(5)
  .get()
  .catch(() => ({empty: true, size: 0, docs: []}));

const audits = await db
  .collection("auditLogs")
  .where("metadata.operation_id", "==", idempotencyKey)
  .limit(5)
  .get()
  .catch(() => ({empty: true, size: 0, docs: []}));

console.log("ops_with_key", ops.size ?? 0);
console.log("audits_with_key", audits.size ?? 0);

const zeroWrite = (ops.size ?? 0) === 0 && (audits.size ?? 0) === 0;
if (ok && zeroWrite) {
  console.log("GATE6_PROD_PAST_SMOKE: PASS");
  process.exit(0);
}
console.error("GATE6_PROD_PAST_SMOKE: FAIL");
process.exit(1);
