/**
 * HW-3R.1 — Rules para operational_restrictions e health_summary/current.
 *
 * Seeds usam withSecurityRulesDisabled; todas as operações verificadas usam
 * contexto cliente autenticado ou anônimo no Firestore Emulator.
 */
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const HANDLER_RA = '691755';
const OTHER_RA = '691640';
const DOG_A = 'dog-health-read-a';
const DOG_B = 'dog-health-read-b';

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});
const tests = [];

function test(name, fn) {
  tests.push({name, fn});
}

function clientDb(ra = HANDLER_RA) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    access_scope: 'own_records',
    ra,
  }).firestore();
}

function now() {
  return Timestamp.fromDate(new Date('2026-08-10T12:00:00.000Z'));
}

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'dogs', DOG_A), {
      name: 'K9 A',
      conductorRa: HANDLER_RA,
      conductor_ra: HANDLER_RA,
      handlerId: HANDLER_RA,
      handler_id: HANDLER_RA,
      audit_trail: [{action: 'created', by: HANDLER_RA, at: now()}],
    });
    await setDoc(doc(db, 'dogs', DOG_B), {
      name: 'K9 B',
      conductorRa: OTHER_RA,
      conductor_ra: OTHER_RA,
      handlerId: OTHER_RA,
      handler_id: OTHER_RA,
      audit_trail: [{action: 'created', by: OTHER_RA, at: now()}],
    });

    await setDoc(
      doc(db, 'dogs', DOG_A, 'operational_restrictions', 'restriction-a'),
      {status: 'active', reason: 'synthetic-a', created_at: now()},
    );
    await setDoc(
      doc(db, 'dogs', DOG_B, 'operational_restrictions', 'restriction-b'),
      {status: 'active', reason: 'synthetic-b', created_at: now()},
    );
    await setDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current'), {
      readiness: 'restricted',
      updated_at: now(),
    });
    await setDoc(doc(db, 'dogs', DOG_B, 'health_summary', 'current'), {
      readiness: 'ready',
      updated_at: now(),
    });
    await setDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'historical'), {
      readiness: 'ready',
      updated_at: now(),
    });
  });
}

test('operational_restrictions: dog-scope autorizado pode ler', async () => {
  await seedFixtures();
  await assertSucceeds(getDoc(doc(
    clientDb(), 'dogs', DOG_A, 'operational_restrictions', 'restriction-a',
  )));
});

test('operational_restrictions: sem acesso e cross-dog são negados', async () => {
  await seedFixtures();
  const db = clientDb();
  await assertFails(getDoc(doc(
    db, 'dogs', DOG_B, 'operational_restrictions', 'restriction-b',
  )));
});

test('operational_restrictions: não autenticado não pode ler', async () => {
  await seedFixtures();
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(
    db, 'dogs', DOG_A, 'operational_restrictions', 'restriction-a',
  )));
});

test('operational_restrictions: create, update e delete cliente são negados', async () => {
  await seedFixtures();
  const db = clientDb();
  await assertFails(setDoc(
    doc(db, 'dogs', DOG_A, 'operational_restrictions', 'restriction-new'),
    {status: 'active', reason: 'synthetic-new', created_at: now()},
  ));
  const existing = doc(
    db, 'dogs', DOG_A, 'operational_restrictions', 'restriction-a',
  );
  await assertFails(updateDoc(existing, {status: 'released'}));
  await assertFails(deleteDoc(existing));
});

test('health_summary: current autorizado pode ser lido', async () => {
  await seedFixtures();
  await assertSucceeds(getDoc(
    doc(clientDb(), 'dogs', DOG_A, 'health_summary', 'current'),
  ));
});

test('health_summary: sem acesso e cross-dog são negados', async () => {
  await seedFixtures();
  await assertFails(getDoc(
    doc(clientDb(), 'dogs', DOG_B, 'health_summary', 'current'),
  ));
});

test('health_summary: não autenticado não pode ler current', async () => {
  await seedFixtures();
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(
    doc(db, 'dogs', DOG_A, 'health_summary', 'current'),
  ));
});

test('health_summary: IDs não-current são negados', async () => {
  await seedFixtures();
  await assertFails(getDoc(
    doc(clientDb(), 'dogs', DOG_A, 'health_summary', 'historical'),
  ));
});

test('health_summary: create, update e delete current cliente são negados', async () => {
  await seedFixtures();
  const db = clientDb();
  const current = doc(db, 'dogs', DOG_A, 'health_summary', 'current');

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(
      context.firestore(), 'dogs', DOG_A, 'health_summary', 'current',
    ));
  });
  await assertFails(setDoc(current, {readiness: 'tampered'}));

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'dogs', DOG_A, 'health_summary', 'current'),
      {readiness: 'restricted', updated_at: now()},
    );
  });
  await assertFails(updateDoc(current, {readiness: 'tampered'}));
  await assertFails(deleteDoc(current));
});

try {
  let passed = 0;
  for (const {name, fn} of tests) {
    await testEnv.clearFirestore();
    await fn();
    passed += 1;
    console.log(`ok - ${name}`);
  }

  assert.equal(passed, tests.length);
  console.log(`\n${passed} testes HW-3R.1 concluídos com sucesso.`);
} finally {
  await testEnv.cleanup();
}
