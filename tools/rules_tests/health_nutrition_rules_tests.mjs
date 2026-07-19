/**
 * Health v1 — Fase 5D Gate 4
 * Testes de Firestore Rules para collections canônicas de Nutrição:
 *   dogs/{dogId}/nutrition_plans/{planId}
 *   dogs/{dogId}/meal_logs/{mealId}
 *   dogs/{dogId}/supplement_logs/{logId}
 *   dogs/{dogId}/nutrition_operations/{receiptId}
 *
 * Predicado de leitura alinhado à Agenda (health_schedule):
 *   signedIn() && canAccessDogRecord(dogId)
 *
 * Writes cliente: DENY em todas as collections canônicas.
 * nutrition_operations: DENY total no cliente (read+write).
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-nutrition
 */
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const PRIMARY_RA = '691755';
const MEMBER_RA = '691640';
const OUTSIDER_RA = '999999';

const DOG_A = 'dog-nutrition-a';
const DOG_B = 'dog-nutrition-b';
const DOG_OTHER = 'dog-nutrition-other';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
});

const tests = [];

function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    ...claims,
  });
}

function dbFor(ra, claims = {}) {
  return auth(ra, claims).firestore();
}

function now() {
  return Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
}

function audit(action = 'created', by = PRIMARY_RA) {
  return [{action, by, at: now()}];
}

function planPayload() {
  return {
    food_type: 'Ração',
    amount_grams_per_day: 400,
    meals_per_day: 2,
    meal_schedule: [],
    valid_from: now(),
    timezone: 'America/Sao_Paulo',
    status: 'active',
    recorded_by: {
      uid: `uid-${PRIMARY_RA}`,
      name: 'Condutor',
      internal_role: 'condutor',
    },
    schema_version: 1,
    revision: 1,
  };
}

function mealPayload() {
  return {
    period: 'morning',
    offered_grams: 150,
    acceptance: 'full',
    fed_at: now(),
    recorded_by: {
      uid: `uid-${PRIMARY_RA}`,
      name: 'Condutor',
      internal_role: 'condutor',
    },
    schema_version: 1,
    revision: 1,
  };
}

function supplementPayload() {
  return {
    supplement_name: 'Ômega 3',
    dose: 5,
    unit: 'ml',
    administered_at: now(),
    recorded_by: {
      uid: `uid-${PRIMARY_RA}`,
      name: 'Condutor',
      internal_role: 'condutor',
    },
    schema_version: 1,
    revision: 1,
  };
}

function receiptPayload() {
  return {
    operation_id: 'op-secret',
    fingerprint: 'fp-internal',
    result: 'created',
    created_at: now(),
  };
}

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

async function clearAll() {
  await testEnv.clearFirestore();
}

async function seedNutritionFixtures() {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A), {
      name: 'Rex A',
      conductorRa: PRIMARY_RA,
      conductor_ra: PRIMARY_RA,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      audit_trail: audit(),
    });
    await setDoc(doc(adminDb, 'dogs', DOG_B), {
      name: 'Rex B',
      conductorRa: MEMBER_RA,
      conductor_ra: MEMBER_RA,
      handlerId: MEMBER_RA,
      handler_id: MEMBER_RA,
      audit_trail: audit('created', MEMBER_RA),
    });
    await setDoc(doc(adminDb, 'dogs', DOG_OTHER), {
      name: 'Outro K9',
      conductorRa: OUTSIDER_RA,
      conductor_ra: OUTSIDER_RA,
      audit_trail: audit('created', OUTSIDER_RA),
    });

    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1'),
      planPayload(),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'meal_logs', 'meal-a1'),
      mealPayload(),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'supplement_logs', 'supp-a1'),
      supplementPayload(),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1'),
      receiptPayload(),
    );

    await setDoc(
      doc(adminDb, 'dogs', DOG_B, 'nutrition_plans', 'plan-b1'),
      planPayload(),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_B, 'meal_logs', 'meal-b1'),
      mealPayload(),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_B, 'supplement_logs', 'supp-b1'),
      supplementPayload(),
    );
  });
}

// ── Authorized read (global scope = default sem own_records) ───────────────

test('authorized: le nutrition_plans / meal_logs / supplement_logs', async () => {
  await seedNutritionFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1')),
  );
  await assertSucceeds(getDoc(doc(db, 'dogs', DOG_A, 'meal_logs', 'meal-a1')));
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'supplement_logs', 'supp-a1')),
  );

  await assertSucceeds(
    getDocs(collection(db, 'dogs', DOG_A, 'nutrition_plans')),
  );
  await assertSucceeds(getDocs(collection(db, 'dogs', DOG_A, 'meal_logs')));
  await assertSucceeds(
    getDocs(collection(db, 'dogs', DOG_A, 'supplement_logs')),
  );
});

// ── Unauthenticated ────────────────────────────────────────────────────────

test('sem auth: deny get/list nas 3 collections canônicas', async () => {
  await seedNutritionFixtures();
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(
    getDoc(doc(anon, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1')),
  );
  await assertFails(getDoc(doc(anon, 'dogs', DOG_A, 'meal_logs', 'meal-a1')));
  await assertFails(
    getDoc(doc(anon, 'dogs', DOG_A, 'supplement_logs', 'supp-a1')),
  );
  await assertFails(
    getDocs(collection(anon, 'dogs', DOG_A, 'nutrition_plans')),
  );
});

// ── own_records sem acesso ao dog ──────────────────────────────────────────

test('own_records sem dog access: deny leitura canônica', async () => {
  await seedNutritionFixtures();
  // PRIMARY tem own_records e está assigned a DOG_A, não a DOG_OTHER.
  const db = dbFor(PRIMARY_RA, {ra: PRIMARY_RA, access_scope: 'own_records'});

  await assertFails(
    getDoc(doc(db, 'dogs', DOG_OTHER, 'nutrition_plans', 'plan-x')),
  );
  // Seed plan on OTHER for completeness
  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'dogs', DOG_OTHER, 'nutrition_plans', 'plan-x'),
      planPayload(),
    );
  });
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_OTHER, 'nutrition_plans', 'plan-x')),
  );
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_OTHER, 'meal_logs', 'meal-x')),
  );
});

test('own_records com dog access: allow leitura do próprio dog', async () => {
  await seedNutritionFixtures();
  const db = dbFor(PRIMARY_RA, {ra: PRIMARY_RA, access_scope: 'own_records'});

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1')),
  );
  await assertSucceeds(getDoc(doc(db, 'dogs', DOG_A, 'meal_logs', 'meal-a1')));
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'supplement_logs', 'supp-a1')),
  );
});

// ── Cross-dog ──────────────────────────────────────────────────────────────

test('dog A owner com own_records não lê dog B', async () => {
  await seedNutritionFixtures();
  const db = dbFor(PRIMARY_RA, {ra: PRIMARY_RA, access_scope: 'own_records'});

  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'nutrition_plans', 'plan-b1')),
  );
  await assertFails(getDoc(doc(db, 'dogs', DOG_B, 'meal_logs', 'meal-b1')));
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'supplement_logs', 'supp-b1')),
  );
});

// ── Direct writes denied ───────────────────────────────────────────────────

for (const col of ['nutrition_plans', 'meal_logs', 'supplement_logs']) {
  test(`${col}: create/update/delete negados mesmo autenticado`, async () => {
    await seedNutritionFixtures();
    const db = dbFor(PRIMARY_RA);
    const id = col === 'nutrition_plans' ? 'plan-new' : `${col}-new`;
    const payload =
      col === 'nutrition_plans'
        ? planPayload()
        : col === 'meal_logs'
          ? mealPayload()
          : supplementPayload();

    await assertFails(setDoc(doc(db, 'dogs', DOG_A, col, id), payload));

    const existing =
      col === 'nutrition_plans'
        ? 'plan-a1'
        : col === 'meal_logs'
          ? 'meal-a1'
          : 'supp-a1';
    await assertFails(
      updateDoc(doc(db, 'dogs', DOG_A, col, existing), {revision: 99}),
    );
    await assertFails(deleteDoc(doc(db, 'dogs', DOG_A, col, existing)));
  });
}

test('admin claim no cliente ainda não grava canônico', async () => {
  await seedNutritionFixtures();
  const db = dbFor(PRIMARY_RA, {admin: true, ra: PRIMARY_RA});

  await assertFails(
    setDoc(doc(db, 'dogs', DOG_A, 'meal_logs', 'meal-admin'), mealPayload()),
  );
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'supplement_logs', 'supp-admin'),
      supplementPayload(),
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'nutrition_plans', 'plan-admin'),
      planPayload(),
    ),
  );
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1'), {
      status: 'archived',
    }),
  );
  await assertFails(
    deleteDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'plan-a1')),
  );
});

// ── nutrition_operations: total deny ───────────────────────────────────────

test('nutrition_operations: get/list/create/update/delete deny para qualquer cliente', async () => {
  await seedNutritionFixtures();

  const anon = testEnv.unauthenticatedContext().firestore();
  await assertFails(
    getDoc(doc(anon, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1')),
  );

  const user = dbFor(PRIMARY_RA);
  await assertFails(
    getDoc(doc(user, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1')),
  );
  await assertFails(
    getDocs(collection(user, 'dogs', DOG_A, 'nutrition_operations')),
  );
  await assertFails(
    setDoc(
      doc(user, 'dogs', DOG_A, 'nutrition_operations', 'receipt-new'),
      receiptPayload(),
    ),
  );
  await assertFails(
    updateDoc(doc(user, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1'), {
      result: 'hacked',
    }),
  );
  await assertFails(
    deleteDoc(doc(user, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1')),
  );

  const adminClient = dbFor(PRIMARY_RA, {admin: true, ra: PRIMARY_RA});
  await assertFails(
    getDoc(
      doc(adminClient, 'dogs', DOG_A, 'nutrition_operations', 'receipt-a1'),
    ),
  );
  await assertFails(
    setDoc(
      doc(adminClient, 'dogs', DOG_A, 'nutrition_operations', 'receipt-admin'),
      receiptPayload(),
    ),
  );
});

// ── Runner ─────────────────────────────────────────────────────────────────

let failed = 0;
for (const {name, fn} of tests) {
  try {
    await clearAll();
    await fn();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`  ✗ ${name}`);
    console.error(err);
  }
}

await testEnv.cleanup();

if (failed > 0) {
  console.error(`\n${failed} teste(s) falharam`);
  process.exit(1);
}

console.log(`\n${tests.length} testes de Rules Nutrição canônica OK`);
