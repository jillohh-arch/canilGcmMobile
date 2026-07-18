/**
 * Gate 6 — smoke produção negativo (create no passado).
 * NÃO cria schedule feliz.
 *
 * Preferido (sem Admin SDK):
 *   $env:GATE3_ID_TOKEN="..."; $env:GATE3_DOG_ID="dogId-real"
 *   node tools/rules_tests/health_schedule_gate6_prod_past_smoke.mjs
 *
 * Alternativa (service account com signBlob):
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="path-to-sa.json"
 *   node tools/rules_tests/health_schedule_gate6_prod_past_smoke.mjs
 */
import {readFileSync, existsSync} from "node:fs";
import {resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";

const PROJECT_ID = "canil-gcm";
const REGION = "southamerica-east1";
const BASE = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;
const RA = process.env.GATE6_SMOKE_RA || "691755";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");

async function resolveIdToken() {
  if (process.env.GATE3_ID_TOKEN) {
    return process.env.GATE3_ID_TOKEN.trim();
  }
  // Optional Admin path
  const {initializeApp, applicationDefault, getApps} = await import(
    "firebase-admin/app"
  );
  const {getAuth} = await import("firebase-admin/auth");
  const {getFirestore} = await import("firebase-admin/firestore");
  if (!getApps().length) {
    initializeApp({credential: applicationDefault(), projectId: PROJECT_ID});
  }
  const auth = getAuth();
  const db = getFirestore();
  const userSnap = await db.collection("users").doc(RA).get();
  if (!userSnap.exists) {
    throw new Error(`user ${RA} not found`);
  }
  const email = String(userSnap.data()?.email || `${RA}@gcm.com.br`).trim();
  const userRecord = await auth.getUserByEmail(email);
  const custom = await auth.createCustomToken(userRecord.uid);
  const gs = resolve(repoRoot, "android/app/google-services.json");
  if (!existsSync(gs)) throw new Error("google-services.json missing");
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
    throw new Error(`token exchange failed: ${JSON.stringify(exchanged).slice(0, 300)}`);
  }
  return exchanged.idToken;
}

async function resolveDogId() {
  if (process.env.GATE3_DOG_ID || process.env.GATE6_SMOKE_DOG_ID) {
    return process.env.GATE3_DOG_ID || process.env.GATE6_SMOKE_DOG_ID;
  }
  // Prefer non-existent dog: still hits validation after authz/dog access order.
  // Create validates scheduled_for after dog access — use a dog the user can access
  // or accept permission-denied if dog missing. Prefer explicit GATE3_DOG_ID.
  return "nonexistent-dog-gate6-smoke";
}

let idToken;
try {
  idToken = await resolveIdToken();
} catch (e) {
  console.error(
    "FAIL - sem ID token. Defina GATE3_ID_TOKEN ou GOOGLE_APPLICATION_CREDENTIALS (service account).",
  );
  console.error(String(e?.message || e));
  process.exit(2);
}

const dogId = await resolveDogId();
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
    Authorization: `Bearer ${idToken}`,
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

// Zero write heuristic: no success result
const wasSuccess = Boolean(body?.result?.scheduleId);
if (ok && !wasSuccess) {
  console.log("GATE6_PROD_PAST_SMOKE: PASS (validation; no success result)");
  process.exit(0);
}
// If dog not found / permission, still prove deploy is live but not the temporal rule
if (detailsCode === "not-found" || detailsCode === "permission-denied") {
  console.error(
    "GATE6_PROD_PAST_SMOKE: INCONCLUSIVE — auth ok but dog/access blocked before temporal check. Set GATE3_DOG_ID de um K9 acessível.",
  );
  process.exit(3);
}
console.error("GATE6_PROD_PAST_SMOKE: FAIL");
process.exit(1);
