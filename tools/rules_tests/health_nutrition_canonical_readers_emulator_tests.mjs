/**
 * Health v1 — Fase 5D Gate 4 (query integrity audit)
 *
 * Orquestra:
 * 1. seed Admin (bypass Rules) com fixtures canônicas válidas + malformadas
 * 2. Auth user autenticável
 * 3. flutter test dos adapters reais (FirebaseFirestore → Emulator)
 *
 * Execução (tools/rules_tests, com firebase no PATH):
 *   npm run test:health-nutrition-readers
 *
 * Ou (repo root):
 *   firebase emulators:exec --project canil-gcm --config firebase.json \
 *     --only auth,firestore \
 *     "node tools/rules_tests/health_nutrition_canonical_readers_emulator_tests.mjs"
 *
 * Zero produção: emulators:exec isola o project no Emulator.
 */
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp as initializeAdminApp, getApps} from 'firebase-admin/app';
import {getAuth as getAdminAuth} from 'firebase-admin/auth';
import {getFirestore as getAdminFirestore, Timestamp} from 'firebase-admin/firestore';
import {initializeTestEnvironment, assertSucceeds} from '@firebase/rules-unit-testing';
import {
  collection,
  getDocs,
  orderBy,
  query,
} from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../..');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';

const PASSWORD = 'Gate4-Reader-Emulator-Only-Not-Prod!';
const OP = {
  ra: '691755',
  uid: 'uid-691755-nutrition-reader',
  email: '691755@gcm.com.br',
  name: 'Operador Gate4 Nutrition Reader',
};

const DOG_VALID = 'dog-nutrition-reader-valid';
const DOG_MULTI = 'dog-nutrition-reader-multi';
const DOG_MEAL_BROKEN = 'dog-nutrition-reader-meal-broken';
const DOG_SUPP_BROKEN = 'dog-nutrition-reader-supp-broken';
const DOG_PLAN_BROKEN = 'dog-nutrition-reader-plan-broken';
const DOG_MEAL_LEGACY = 'dog-nutrition-reader-meal-legacy';

function log(msg) {
  console.log(msg);
}

function assertEmulatorHosts() {
  for (const [label, host] of [
    ['AUTH', AUTH_HOST],
    ['FS', FS_HOST],
  ]) {
    const h = String(host);
    assert.ok(
      h.includes('127.0.0.1') || h.includes('localhost'),
      `${label} host não é Emulator local: ${h}`,
    );
  }
  log(
    `EMULATOR_ONLY_OK project=${PROJECT_ID} AUTH=${AUTH_HOST} FS=${FS_HOST}`,
  );
}

if (!getApps().length) {
  initializeAdminApp({projectId: PROJECT_ID});
}
const adminAuth = getAdminAuth();
const adminDb = getAdminFirestore();

function now() {
  return Timestamp.fromDate(new Date('2026-07-14T12:00:00.000Z'));
}

function recordedBy() {
  return {
    uid: OP.uid,
    name: OP.name,
    internal_role: 'condutor',
  };
}

function validPlan(overrides = {}) {
  return {
    food_type: 'Ração Premium',
    amount_grams_per_day: 400,
    meals_per_day: 2,
    meal_schedule: [
      {
        id: 'slot-morning',
        period: 'morning',
        scheduled_time: '07:00',
        target_grams: 200,
      },
      {
        id: 'slot-evening',
        period: 'evening',
        scheduled_time: '18:00',
        target_grams: 200,
      },
    ],
    valid_from: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
    timezone: 'America/Sao_Paulo',
    status: 'active',
    recorded_by: recordedBy(),
    schema_version: 1,
    revision: 1,
    ...overrides,
  };
}

function validMeal() {
  return {
    period: 'morning',
    offered_grams: 150,
    acceptance: 'full',
    fed_at: now(),
    recorded_by: recordedBy(),
    schema_version: 1,
    revision: 1,
  };
}

function validSupplement() {
  return {
    supplement_name: 'Ômega 3',
    dose: 5,
    unit: 'ml',
    administered_at: now(),
    recorded_by: recordedBy(),
    schema_version: 1,
    revision: 1,
  };
}

async function ensureUser(user) {
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
      e?.code !== 'auth/uid-already-exists' &&
      e?.code !== 'auth/email-already-exists'
    ) {
      throw e;
    }
  }
  await adminAuth.setCustomUserClaims(user.uid, {
    ra: user.ra,
    // global scope (default) — canAccessDogRecord true para qualquer dog
  });
}

async function seedDog(dogId, name) {
  await adminDb.collection('dogs').doc(dogId).set({
    name,
    conductorRa: OP.ra,
    conductor_ra: OP.ra,
    handlerId: OP.ra,
    handler_id: OP.ra,
  });
}

async function seedFixtures() {
  log('Seeding canonical reader fixtures (Admin SDK)…');

  await ensureUser(OP);

  // --- valid visibility ---
  await seedDog(DOG_VALID, 'Reader Valid');
  await adminDb
    .collection('dogs')
    .doc(DOG_VALID)
    .collection('nutrition_plans')
    .doc('plan-valid')
    .set(validPlan());
  await adminDb
    .collection('dogs')
    .doc(DOG_VALID)
    .collection('meal_logs')
    .doc('meal-valid')
    .set(validMeal());
  await adminDb
    .collection('dogs')
    .doc(DOG_VALID)
    .collection('supplement_logs')
    .doc('supp-valid')
    .set(validSupplement());
  await adminDb
    .collection('dogs')
    .doc(DOG_VALID)
    .collection('nutrition_supplements')
    .doc('reg-legacy')
    .set({name: 'Vitamina Legada', dose: '1 cp', started_at: now()});

  // --- multiple active ---
  await seedDog(DOG_MULTI, 'Reader Multi');
  await adminDb
    .collection('dogs')
    .doc(DOG_MULTI)
    .collection('nutrition_plans')
    .doc('p1')
    .set(
      validPlan({
        valid_from: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
      }),
    );
  await adminDb
    .collection('dogs')
    .doc(DOG_MULTI)
    .collection('nutrition_plans')
    .doc('p2')
    .set(
      validPlan({
        valid_from: Timestamp.fromDate(new Date('2026-03-01T00:00:00.000Z')),
      }),
    );

  // --- meal without fed_at ---
  await seedDog(DOG_MEAL_BROKEN, 'Reader Meal Broken');
  await adminDb
    .collection('dogs')
    .doc(DOG_MEAL_BROKEN)
    .collection('meal_logs')
    .doc('broken-no-fed-at')
    .set({
      period: 'morning',
      offered_grams: 100,
      acceptance: 'full',
      // fed_at AUSENTE — orderBy fed_at ocultaria no Emulator
      recorded_by: recordedBy(),
      schema_version: 1,
      revision: 1,
    });

  // --- supplement without administered_at ---
  await seedDog(DOG_SUPP_BROKEN, 'Reader Supp Broken');
  await adminDb
    .collection('dogs')
    .doc(DOG_SUPP_BROKEN)
    .collection('supplement_logs')
    .doc('broken-no-admin-at')
    .set({
      supplement_name: 'Ômega 3',
      dose: 5,
      unit: 'ml',
      // administered_at AUSENTE
      recorded_by: recordedBy(),
      schema_version: 1,
      revision: 1,
    });

  // --- plan malformed ---
  await seedDog(DOG_PLAN_BROKEN, 'Reader Plan Broken');
  await adminDb
    .collection('dogs')
    .doc(DOG_PLAN_BROKEN)
    .collection('nutrition_plans')
    .doc('plan-bad')
    .set({
      food_type: 'X',
      amount_grams_per_day: 100,
      meals_per_day: 1,
      status: 'not_a_real_status',
      valid_from: now(),
      timezone: 'America/Sao_Paulo',
      recorded_by: recordedBy(),
      schema_version: 1,
      revision: 1,
    });

  // --- meal broken + legacy meal (degraded path) ---
  await seedDog(DOG_MEAL_LEGACY, 'Reader Meal+Legacy');
  await adminDb
    .collection('dogs')
    .doc(DOG_MEAL_LEGACY)
    .collection('meal_logs')
    .doc('broken-no-fed-at')
    .set({
      period: 'morning',
      offered_grams: 100,
      acceptance: 'full',
      recorded_by: recordedBy(),
      schema_version: 1,
      revision: 1,
    });
  await adminDb
    .collection('dogs')
    .doc(DOG_MEAL_LEGACY)
    .collection('feeding_events')
    .doc('fe-legacy-1')
    .set({
      period: 'manha',
      amount_grams: 120,
      fed_at: now(),
      recorded_by: recordedBy(),
    });

  log('Seed OK');
}

/**
 * Prova adversarial no Emulator real (client SDK, Rules ativas):
 * orderBy(fed_at) omite doc sem campo; get() o inclui.
 * Espelha a estratégia do reader Dart (scan → parse fail-closed).
 */
async function proveQueryVisibilityWithClientSdk() {
  log('Proving query visibility (client SDK + Rules)…');
  const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});
  try {
    const db = testEnv
      .authenticatedContext(OP.uid, {
        email: OP.email,
        ra: OP.ra,
      })
      .firestore();

    const mealCol = collection(db, 'dogs', DOG_MEAL_BROKEN, 'meal_logs');

    const ordered = await assertSucceeds(
      getDocs(query(mealCol, orderBy('fed_at', 'desc'))),
    );
    const orderedIds = ordered.docs.map((d) => d.id);
    assert.ok(
      !orderedIds.includes('broken-no-fed-at'),
      `orderBy deve ocultar broken-no-fed-at; got ${orderedIds.join(',')}`,
    );
    log('  ✓ orderBy(fed_at) omite documento sem fed_at');

    const scanned = await assertSucceeds(getDocs(mealCol));
    const scannedIds = scanned.docs.map((d) => d.id);
    assert.ok(
      scannedIds.includes('broken-no-fed-at'),
      `collection get deve incluir broken-no-fed-at; got ${scannedIds.join(',')}`,
    );
    log('  ✓ collection.get() inclui documento sem fed_at');

    // Integrity check espelhando MealLogDocumentParser: fed_at obrigatório.
    for (const docSnap of scanned.docs) {
      const data = docSnap.data();
      if (data.fed_at == null) {
        assert.equal(docSnap.id, 'broken-no-fed-at');
        log(
          '  ✓ doc sem fed_at alcançável para fail-closed (missing_fed_at)',
        );
      }
    }

    const suppCol = collection(
      db,
      'dogs',
      DOG_SUPP_BROKEN,
      'supplement_logs',
    );
    const suppOrdered = await assertSucceeds(
      getDocs(query(suppCol, orderBy('administered_at', 'desc'))),
    );
    assert.ok(
      !suppOrdered.docs.map((d) => d.id).includes('broken-no-admin-at'),
      'orderBy(administered_at) deve ocultar broken',
    );
    const suppScan = await assertSucceeds(getDocs(suppCol));
    assert.ok(
      suppScan.docs.map((d) => d.id).includes('broken-no-admin-at'),
      'get() deve incluir broken-no-admin-at',
    );
    log('  ✓ supplement orderBy vs get() — mesma armadilha / correção');

    // Visibility canônica válida
    const validMeals = await assertSucceeds(
      getDocs(collection(db, 'dogs', DOG_VALID, 'meal_logs')),
    );
    assert.ok(validMeals.docs.some((d) => d.id === 'meal-valid'));
    const validPlans = await assertSucceeds(
      getDocs(collection(db, 'dogs', DOG_VALID, 'nutrition_plans')),
    );
    assert.ok(validPlans.docs.some((d) => d.id === 'plan-valid'));
    const multiPlans = await assertSucceeds(
      getDocs(collection(db, 'dogs', DOG_MULTI, 'nutrition_plans')),
    );
    assert.equal(multiPlans.docs.length, 2);
    log('  ✓ plan/meal visibility + multi-active docs presentes');
  } finally {
    await testEnv.cleanup();
  }
}

/**
 * Exporta documentos reais do Emulator (Admin get) para fixture JSON.
 * O teste Dart consome a fixture e roda parsers 5C + semântica do reader
 * (scan → fail-closed) sem precisar de plugins Firebase no harness unitário.
 */
async function exportFixturesForDart() {
  const outDir = path.join(REPO_ROOT, 'temp');
  const outFile = path.join(outDir, 'g4_nutrition_emulator_fixtures.json');
  const {mkdir, writeFile} = await import('node:fs/promises');
  await mkdir(outDir, {recursive: true});

  async function dumpCollection(dogId, collectionId) {
    const snap = await adminDb
      .collection('dogs')
      .doc(dogId)
      .collection(collectionId)
      .get();
    return snap.docs.map((d) => ({
      id: d.id,
      data: serializeFirestoreValue(d.data()),
    }));
  }

  const payload = {
    generatedAt: new Date().toISOString(),
    projectId: PROJECT_ID,
    dogs: {
      [DOG_MEAL_BROKEN]: {
        meal_logs: await dumpCollection(DOG_MEAL_BROKEN, 'meal_logs'),
      },
      [DOG_SUPP_BROKEN]: {
        supplement_logs: await dumpCollection(
          DOG_SUPP_BROKEN,
          'supplement_logs',
        ),
      },
      [DOG_PLAN_BROKEN]: {
        nutrition_plans: await dumpCollection(
          DOG_PLAN_BROKEN,
          'nutrition_plans',
        ),
      },
      [DOG_MULTI]: {
        nutrition_plans: await dumpCollection(DOG_MULTI, 'nutrition_plans'),
      },
      [DOG_VALID]: {
        nutrition_plans: await dumpCollection(DOG_VALID, 'nutrition_plans'),
        meal_logs: await dumpCollection(DOG_VALID, 'meal_logs'),
        supplement_logs: await dumpCollection(DOG_VALID, 'supplement_logs'),
      },
      [DOG_MEAL_LEGACY]: {
        meal_logs: await dumpCollection(DOG_MEAL_LEGACY, 'meal_logs'),
        feeding_events: await dumpCollection(
          DOG_MEAL_LEGACY,
          'feeding_events',
        ),
      },
    },
  };

  await writeFile(outFile, JSON.stringify(payload, null, 2), 'utf8');
  log(`Exported Emulator fixtures → ${outFile}`);
  return outFile;
}

/** Converte Timestamps Admin → maps seconds/nanoseconds (parser 5C). */
function serializeFirestoreValue(value) {
  if (value == null) return null;
  if (value instanceof Timestamp) {
    return {
      seconds: value.seconds,
      nanoseconds: value.nanoseconds,
    };
  }
  if (Array.isArray(value)) {
    return value.map(serializeFirestoreValue);
  }
  if (typeof value === 'object') {
    // Timestamp-like from admin
    if (
      typeof value.toDate === 'function' &&
      typeof value.seconds === 'number'
    ) {
      return {seconds: value.seconds, nanoseconds: value.nanoseconds ?? 0};
    }
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = serializeFirestoreValue(v);
    }
    return out;
  }
  return value;
}

function runDartFixtureTests(fixturePath) {
  const testPath =
    'test/features/health/data/coexistence/nutrition/firestore_nutrition_emulator_fixture_test.dart';
  log(`Running flutter test ${testPath} (Emulator fixtures)…`);

  const env = {
    ...process.env,
    HEALTH_NUTRITION_READER_EMULATOR: '1',
    G4_NUTRITION_EMU_FIXTURE: fixturePath,
  };

  const isWin = process.platform === 'win32';
  const flutterCmd = isWin ? 'flutter.bat' : 'flutter';
  const result = spawnSync(flutterCmd, ['test', testPath], {
    cwd: REPO_ROOT,
    env,
    encoding: 'utf8',
    shell: isWin,
    stdio: 'inherit',
  });

  if (result.status !== 0) {
    throw new Error(
      `flutter fixture test failed with status ${result.status}`,
    );
  }
  log('Dart parsers + reader semantics on Emulator fixtures OK');
}

assertEmulatorHosts();
await seedFixtures();
await proveQueryVisibilityWithClientSdk();
const fixturePath = await exportFixturesForDart();
runDartFixtureTests(fixturePath);
log('\nhealth_nutrition_canonical_readers_emulator_tests: ALL OK');
