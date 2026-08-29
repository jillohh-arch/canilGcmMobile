/**
 * Gate 3 — smoke de produção não destrutivo (canil-gcm).
 *
 * NÃO cria seeds, NÃO altera claims, NÃO grava health_schedule feliz.
 * NÃO usa Admin SDK para fingir cliente.
 *
 * Variáveis de ambiente (opcionais / sensíveis — nunca hardcoded):
 *   GATE3_WEB_API_KEY   — API key web/android do projeto (ou lê google-services se omitida)
 *   GATE3_ID_TOKEN      — Firebase ID token de usuário real já autenticado
 *   GATE3_DOG_ID        — K9 que o usuário pode acessar (default: dog inexistente seguro)
 *
 * Uso:
 *   node tools/rules_tests/health_schedule_prod_smoke.mjs
 *   $env:GATE3_ID_TOKEN="..."; $env:GATE3_DOG_ID="..."; node tools/rules_tests/health_schedule_prod_smoke.mjs
 */
import {readFileSync, existsSync} from "node:fs";
import {resolve, dirname} from "node:path";
import {fileURLToPath} from "node:url";

const PROJECT_ID = "canil-gcm";
const REGION = "southamerica-east1";
const BASE =
  `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");

function loadApiKey() {
  if (process.env.GATE3_WEB_API_KEY) return process.env.GATE3_WEB_API_KEY;
  const gs = resolve(repoRoot, "android/app/google-services.json");
  if (existsSync(gs)) {
    const j = JSON.parse(readFileSync(gs, "utf8"));
    const key = j?.client?.[0]?.api_key?.[0]?.current_key;
    if (key) return key;
  }
  return null;
}

const results = [];
function record(name, ok, detail = "") {
  results.push({name, ok, detail});
  console.log(`${ok ? "ok" : "FAIL"} - ${name}${detail ? " — " + detail : ""}`);
}

/**
 * Invoca callable Gen2 via protocolo HTTP oficial.
 * @param {string} name
 * @param {object} data
 * @param {string|null} idToken
 */
async function callCallable(name, data, idToken = null) {
  const headers = {
    "Content-Type": "application/json",
  };
  if (idToken) {
    headers.Authorization = `Bearer ${idToken}`;
  }
  const res = await fetch(`${BASE}/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify({data}),
  });
  let body;
  try {
    body = await res.json();
  } catch {
    body = {raw: await res.text()};
  }
  return {status: res.status, body};
}

function haystack(status, body) {
  return `${status} ${JSON.stringify(body)}`.toLowerCase();
}

// --- A) sem autenticação ---
for (const name of [
  "healthScheduleCreateManual",
  "healthScheduleUpdateOpen",
  "healthScheduleComplete",
  "healthScheduleCancel",
]) {
  const {status, body} = await callCallable(name, {dogId: "x"}, null);
  const h = haystack(status, body);
  const ok =
    status === 401 ||
    h.includes("unauthenticated") ||
    h.includes("autenticacao");
  record(
    `${name} sem auth → unauthenticated`,
    ok,
    `HTTP ${status} ${JSON.stringify(body?.error || body).slice(0, 160)}`,
  );
}

// --- B) autenticado (token real via ambiente) ---
const idToken = process.env.GATE3_ID_TOKEN;
const dogId = process.env.GATE3_DOG_ID || "nonexistent-dog-gate3-smoke";

if (!idToken) {
  record(
    "smoke autenticado real",
    false,
    "PENDENTE: defina GATE3_ID_TOKEN (ID token Firebase de usuário real autorizado)",
  );
} else {
  // Create: operationId path-unsafe → validation (antes de write)
  {
    const {status, body} = await callCallable(
      "healthScheduleCreateManual",
      {
        dogId,
        scheduleType: "vaccination",
        title: "smoke-no-write",
        scheduledFor: "2026-09-01T12:00:00.000Z",
        timezone: "America/Sao_Paulo",
        idempotencyKey: "../escape",
      },
      idToken,
    );
    const h = haystack(status, body);
    // O Gate exige rejeicao de validacao antes de qualquer write.
    const ok =
      h.includes("invalid-argument") ||
      h.includes("validation");
    const stage = h.includes("validation") || h.includes("invalid-argument") ?
      "validation(path-safety)" :
      `unexpected HTTP ${status}`;
    record(
      "create autenticado rejeitado antes de write feliz",
      ok,
      `stage=${stage} body=${JSON.stringify(body?.error || body).slice(0, 200)}`,
    );
  }

  // Update / complete / cancel com scheduleId inexistente
  const missing = {
    dogId,
    scheduleId: "nonexistent-schedule-gate3-smoke",
  };

  for (const [name, payload] of [
    [
      "healthScheduleUpdateOpen",
      {
        ...missing,
        expectedRevision: 1,
        operationId: "smoke-upd-1",
        title: "x",
      },
    ],
    [
      "healthScheduleComplete",
      {...missing, operationId: "smoke-comp-1"},
    ],
    [
      "healthScheduleCancel",
      {
        ...missing,
        operationId: "smoke-cancel-1",
        cancelReason: "smoke only no write",
      },
    ],
  ]) {
    const {status, body} = await callCallable(name, payload, idToken);
    const h = haystack(status, body);
    // ordem real: auth → perm → dog access → handler → not-found
    const ok = h.includes("not-found");
    record(
      `${name} autenticado sem write (not-found)`,
      ok,
      `HTTP ${status} ${JSON.stringify(body?.error || body).slice(0, 200)}`,
    );
  }
}

// API key presence only for diagnostics (not printed)
const apiKey = loadApiKey();
record(
  "api key disponível para clientes (não logada)",
  Boolean(apiKey),
  apiKey ? "ok" : "ausente",
);

console.log("\n=== PROD SMOKE SUMMARY ===");
let failed = 0;
let authPending = false;
for (const r of results) {
  console.log(
    `${r.ok ? "PASS" : "FAIL"}  ${r.name}${r.detail ? " — " + r.detail : ""}`,
  );
  if (!r.ok) {
    failed++;
    if (r.name.includes("autenticado") && String(r.detail).includes("PENDENTE")) {
      authPending = true;
    }
  }
}

if (authPending) {
  console.log("\nSMOKE AUTENTICADO DE PRODUÇÃO: PENDENTE");
  process.exitCode = 2;
} else if (failed) {
  console.log(`\nprod smoke: ${failed} falha(s)`);
  process.exitCode = 1;
} else {
  console.log("\nSMOKE AUTENTICADO DE PRODUÇÃO: PASS");
  console.log("health_schedule_prod_smoke: all checks passed");
}
