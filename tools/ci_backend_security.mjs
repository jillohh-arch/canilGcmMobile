import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.resolve(__dirname, "..");
const IS_WIN = process.platform === "win32";
const NPM_BIN = IS_WIN ? "npm.cmd" : "npm";
const FIREBASE_BIN = IS_WIN ? "firebase.cmd" : "firebase";

const CREDENTIAL_ENV_VARS = [
  "GOOGLE_APPLICATION_CREDENTIALS",
  "FIREBASE_TOKEN",
  "GCP_SERVICE_ACCOUNT",
  "GCP_WORKLOAD_IDENTITY_PROVIDER",
  "FIREBASE_SERVICE_ACCOUNT",
  "GOOGLE_CLOUD_PROJECT",
];

const UNIT_STRIP_ENV_VARS = [
  ...CREDENTIAL_ENV_VARS,
  "GCLOUD_PROJECT",
  "FIREBASE_CONFIG",
  "FIREBASE_PROJECT_ID",
  "FIRESTORE_EMULATOR_HOST",
  "FIREBASE_AUTH_EMULATOR_HOST",
  "FIREBASE_STORAGE_EMULATOR_HOST",
  "STORAGE_EMULATOR_HOST",
  "FIREBASE_EMULATOR_HUB",
];

const EMULATOR_SUITES = [
  // 14 M2-verified Firestore & Storage Rules suites
  { services: "firestore,storage", file: "tools/rules_tests/rules_tests.mjs" },
  { services: "firestore,storage", file: "tools/rules_tests/health_document_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/f20_sec02a2_adversarial_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_schedule_collection_group_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_schedule_cg_chunk_limit_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_schedule_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/clinical_read_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_readiness_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_timeline_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/health_nutrition_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/test-warehouse-rules-authoritative.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_read_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/f40_tc1_shift_crew_rules_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/f40_tc1_notification_and_occurrence_rules_tests.mjs" },
  // 6 Warehouse Admin-SDK emulator suites
  { services: "firestore", file: "tools/rules_tests/warehouse_material_flow_emulator_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_concurrency_emulator_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_equipment_custody_emulator_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_hardening_emulator_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_inventory_scale_emulator_tests.mjs" },
  { services: "firestore", file: "tools/rules_tests/warehouse_physical_inventory_emulator_tests.mjs" },
  // 1 F40 Runtime Integration emulator suite (isolated demo project)
  {
    services: "firestore",
    project: "demo-k9-ops-occupancy-m1",
    file: "functions/lib/f40/__tests__/occupancy_runtime_integration.emulator.test.js",
  },
];

const DEBUG_LOG_FILES = [
  "firestore-debug.log",
  "firebase-debug.log",
  "ui-debug.log",
  "pubsub-debug.log",
];

function buildUnitEnv() {
  const env = { ...process.env };
  for (const key of UNIT_STRIP_ENV_VARS) {
    delete env[key];
  }
  return env;
}

function buildEmulatorEnv(projectId = "canil-gcm") {
  const env = { ...process.env };
  for (const key of CREDENTIAL_ENV_VARS) {
    delete env[key];
  }
  for (const key of [
    "FIRESTORE_EMULATOR_HOST",
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIREBASE_STORAGE_EMULATOR_HOST",
  ]) {
    const val = env[key];
    if (val && !val.startsWith("127.0.0.1:") && !val.startsWith("localhost:")) {
      console.error(`[CI] ERROR: Forbidden non-local emulator host in ${key}=${val}`);
      process.exit(1);
    }
  }
  if (
    env.STORAGE_EMULATOR_HOST &&
    !env.STORAGE_EMULATOR_HOST.startsWith("http://127.0.0.1:") &&
    !env.STORAGE_EMULATOR_HOST.startsWith("http://localhost:")
  ) {
    console.error(`[CI] ERROR: Forbidden non-local STORAGE_EMULATOR_HOST=${env.STORAGE_EMULATOR_HOST}`);
    process.exit(1);
  }
  env.GCLOUD_PROJECT = projectId;
  env.FIREBASE_PROJECT_ID = projectId;
  return env;
}

function runCommand(bin, args, env, label) {
  console.log(`\n[CI] >>> ${label}`);
  const result = spawnSync(bin, args, {
    cwd: BACKEND_ROOT,
    env,
    stdio: "inherit",
    shell: IS_WIN,
  });
  if (result.error) {
    console.error(`[CI] ERROR executing ${label}: ${result.error.message}`);
    process.exit(1);
  }
  if (result.status !== 0) {
    console.error(`[CI] FAILED (${result.status ?? 1}): ${label}`);
    process.exit(result.status ?? 1);
  }
}

function runUnit() {
  const env = buildUnitEnv();
  runCommand(
    NPM_BIN,
    ["--prefix", "functions", "run", "test:ci-unit"],
    env,
    "functions test:ci-unit (build, 13 unit suites, F10/F03, F60 legacy, F20 unit, F40 unit, Warehouse unit, 131 endpoints)"
  );
}

function runEmulator() {
  const unitEnv = buildUnitEnv();
  runCommand(
    NPM_BIN,
    ["--prefix", "functions", "run", "build"],
    unitEnv,
    "functions build (prerequisite for Warehouse Admin-SDK and F40 Runtime Integration emulator suites)"
  );

  for (let i = 0; i < EMULATOR_SUITES.length; i += 1) {
    const suite = EMULATOR_SUITES[i];
    const projectId = suite.project ?? "canil-gcm";
    const emuEnv = buildEmulatorEnv(projectId);
    const nodeCmd = `node ${suite.file}`;
    const cmdArg = IS_WIN ? `"${nodeCmd}"` : nodeCmd;
    const label = `[${i + 1}/${EMULATOR_SUITES.length}] firebase emulators:exec (--project ${projectId} --only ${suite.services}) ${suite.file}`;
    runCommand(
      FIREBASE_BIN,
      [
        "emulators:exec",
        "--project",
        projectId,
        "--config",
        "firebase.json",
        "--non-interactive",
        "--only",
        suite.services,
        cmdArg,
      ],
      emuEnv,
      label
    );
  }
}

function cleanDebugLogs() {
  for (const name of DEBUG_LOG_FILES) {
    const target = path.join(BACKEND_ROOT, name);
    if (fs.existsSync(target)) {
      fs.unlinkSync(target);
      console.log(`[CI] Cleaned ${name}`);
    }
  }
}

function main() {
  const args = new Set(process.argv.slice(2));
  const wantUnit = args.has("--unit") || args.has("--all");
  const wantEmulator = args.has("--emulator") || args.has("--all");
  const wantCleanLogs = args.has("--clean-logs");

  for (const arg of args) {
    if (!["--unit", "--emulator", "--all", "--clean-logs"].includes(arg)) {
      console.error(`Unknown argument: ${arg}`);
      console.error("Usage: node tools/ci_backend_security.mjs [--unit] [--emulator] [--all] [--clean-logs]");
      process.exit(2);
    }
  }

  if (!wantUnit && !wantEmulator) {
    console.error("Usage: node tools/ci_backend_security.mjs [--unit] [--emulator] [--all] [--clean-logs]");
    process.exit(2);
  }

  if (wantUnit) {
    runUnit();
  }
  if (wantEmulator) {
    runEmulator();
  }
  if (wantCleanLogs) {
    cleanDebugLogs();
  }

  console.log("\n[CI] ALL REQUESTED BACKEND SECURITY CHECKS PASSED.");
}

main();
