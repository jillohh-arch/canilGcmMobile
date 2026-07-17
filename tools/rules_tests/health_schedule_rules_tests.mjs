/**
 * Health v1 — Fase 4D Gate 1
 * Testes de Firestore Rules para dogs/{dogId}/health_schedule.
 *
 * Reutiliza a infraestrutura de @firebase/rules-unit-testing + Emulator.
 * Seeds usam withSecurityRulesDisabled (admin do emulator); ações sob teste
 * rodam sempre como cliente autenticado/anônimo.
 *
 * Query operacional alinhada à FirestoreHealthScheduleSource (4C):
 *   where lifecycle_status == open
 *   orderBy scheduled_for ASC
 *   orderBy documentId ASC
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-schedule
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
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const PRIMARY_RA = '691755';
const MEMBER_RA = '691640';
const OUTSIDER_RA = '999999';

const DOG_A = 'dog-schedule-a';
const DOG_B = 'dog-schedule-b';
const DOG_OTHER = 'dog-schedule-other';
const DOG_EMPTY = 'dog-empty-schedule';

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

function healthSchedulePayload({
  scheduleType = 'vaccination',
  title = 'Vacina antirrábica',
  lifecycleStatus = 'open',
  scheduledFor = now(),
} = {}) {
  return {
    schedule_type: scheduleType,
    title,
    scheduled_for: scheduledFor,
    timezone: 'America/Sao_Paulo',
    lifecycle_status: lifecycleStatus,
    source_type: 'manual',
    created_at: now(),
    recorded_by: {
      uid: `uid-${PRIMARY_RA}`,
      name: 'Condutor',
      internal_role: 'condutor',
    },
    schema_version: 1,
  };
}

function activeShiftPayload(ra = PRIMARY_RA, dogId = DOG_A) {
  return {
    shiftId: `shift-${ra}`,
    handlerId: ra,
    auth_uid: `uid-${ra}`,
    handler_email: `${ra}@gcm.com.br`,
    dogId,
    service_dog_id: dogId,
    status: 'active',
    startedAt: now(),
    updatedAt: now(),
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

/** Query operacional da FirestoreHealthScheduleSource (4C/4D). */
function operationalHealthScheduleQuery(db, dogId) {
  return query(
    collection(db, 'dogs', dogId, 'health_schedule'),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    orderBy(documentId(), 'asc'),
    limit(21),
  );
}

async function seedHealthScheduleFixtures() {
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
      doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'sched-a1'),
      healthSchedulePayload({
        title: 'A1 open',
        scheduledFor: Timestamp.fromDate(new Date('2026-07-20T12:00:00.000Z')),
      }),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'sched-a2'),
      healthSchedulePayload({
        title: 'A2 open later',
        scheduledFor: Timestamp.fromDate(new Date('2026-07-21T12:00:00.000Z')),
      }),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'sched-a3-done'),
      healthSchedulePayload({
        title: 'A3 completed',
        lifecycleStatus: 'completed',
        scheduledFor: Timestamp.fromDate(new Date('2026-07-19T12:00:00.000Z')),
      }),
    );
    await setDoc(
      doc(adminDb, 'dogs', DOG_B, 'health_schedule', 'sched-b1'),
      healthSchedulePayload({
        title: 'B1 open',
        scheduledFor: Timestamp.fromDate(new Date('2026-07-20T12:00:00.000Z')),
      }),
    );
  });
}

test('health_schedule: nao autenticado nao le get nem list', async () => {
  await seedHealthScheduleFixtures();

  const anonDb = testEnv.unauthenticatedContext().firestore();
  const ref = doc(anonDb, 'dogs', DOG_A, 'health_schedule', 'sched-a1');

  await assertFails(getDoc(ref));
  await assertFails(getDocs(operationalHealthScheduleQuery(anonDb, DOG_A)));
});

test('health_schedule: autenticado global le get e query operacional', async () => {
  await seedHealthScheduleFixtures();

  // Sem access_scope own_records: canAccessDogRecord permite qualquer K9.
  const db = dbFor(PRIMARY_RA);
  const ref = doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1');

  await assertSucceeds(getDoc(ref));

  const snap = await assertSucceeds(
    getDocs(operationalHealthScheduleQuery(db, DOG_A)),
  );
  assert.equal(snap.size, 2);
  assert.deepEqual(
    snap.docs.map((d) => d.id),
    ['sched-a1', 'sched-a2'],
  );
});

test('health_schedule: autenticado global le K9 B (modelo atual sem isolamento global)', async () => {
  await seedHealthScheduleFixtures();

  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertSucceeds(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

test('health_schedule: own_records sem atribuicao nem turno e negado (get e list)', async () => {
  await seedHealthScheduleFixtures();

  const restricted = dbFor(OUTSIDER_RA, {
    access_scope: 'own_records',
    ra: OUTSIDER_RA,
  });

  await assertFails(
    getDoc(doc(restricted, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  await assertFails(
    getDocs(operationalHealthScheduleQuery(restricted, DOG_A)),
  );
});

test('health_schedule: own_records com K9 atribuido pode ler; K9 alheio negado', async () => {
  await seedHealthScheduleFixtures();

  const ownDb = dbFor(PRIMARY_RA, {
    access_scope: 'own_records',
    ra: PRIMARY_RA,
  });

  await assertSucceeds(
    getDoc(doc(ownDb, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  const page = await assertSucceeds(
    getDocs(operationalHealthScheduleQuery(ownDb, DOG_A)),
  );
  assert.equal(page.size, 2);

  await assertFails(
    getDoc(doc(ownDb, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertFails(getDocs(operationalHealthScheduleQuery(ownDb, DOG_B)));
});

test('health_schedule: own_records com turno ativo no K9 B pode ler o B', async () => {
  await seedHealthScheduleFixtures();

  await seedFirestore(async (adminDb) => {
    await setDoc(
      doc(adminDb, 'active_shifts', PRIMARY_RA),
      activeShiftPayload(PRIMARY_RA, DOG_B),
    );
  });

  const ownDb = dbFor(PRIMARY_RA, {
    access_scope: 'own_records',
    ra: PRIMARY_RA,
  });

  await assertSucceeds(
    getDoc(doc(ownDb, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertSucceeds(getDocs(operationalHealthScheduleQuery(ownDb, DOG_B)));
});

test('health_schedule: writes cliente negados mesmo para leitor autorizado', async () => {
  await seedHealthScheduleFixtures();

  const db = dbFor(PRIMARY_RA);
  const newRef = doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-new');
  const existingRef = doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1');

  await assertFails(setDoc(newRef, healthSchedulePayload({title: 'Novo item'})));
  await assertFails(updateDoc(existingRef, {title: 'Alterado indevidamente'}));
  await assertFails(deleteDoc(existingRef));
});

test('health_schedule: admin le mas create/update/delete cliente continuam negados', async () => {
  await seedHealthScheduleFixtures();

  const adminDb = dbFor(PRIMARY_RA, {
    admin: true,
    role: 'admin',
    ra: PRIMARY_RA,
  });
  const existingRef = doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'sched-a1');
  const newRef = doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'sched-admin-new');

  await assertSucceeds(getDoc(existingRef));
  await assertSucceeds(
    getDocs(operationalHealthScheduleQuery(adminDb, DOG_A)),
  );

  await assertFails(
    setDoc(newRef, healthSchedulePayload({title: 'Admin create'})),
  );
  await assertFails(updateDoc(existingRef, {title: 'Admin update'}));
  await assertFails(deleteDoc(existingRef));
});

test('health_schedule: colecao vazia retorna list vazia (empty real, nao permission-denied)', async () => {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_EMPTY), {
      name: 'Empty',
      audit_trail: audit(),
    });
  });

  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDocs(operationalHealthScheduleQuery(db, DOG_EMPTY)),
  );
  assert.equal(snap.size, 0);
  assert.equal(snap.empty, true);
});

try {
  let passed = 0;
  for (const {name, fn} of tests) {
    await clearAll();
    await fn();
    passed += 1;
    console.log(`ok - ${name}`);
  }

  assert.equal(passed, tests.length);
  console.log(
    `\n${passed} testes health_schedule (Rules 4D) concluidos com sucesso.`,
  );
} finally {
  await testEnv.cleanup();
}
