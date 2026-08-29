/**
 * Health v1 — Fase 5D Gate 5C.5C.4
 * Testes de Firestore Rules para dogs/{dogId}/health_timeline.
 *
 * Principais regras:
 * 1. Leitura permitida somente para usuários autenticados com acesso ao dog
 * 2. Escrita cliente totalmente proibida
 * 3. Estado interno _health_projection_state completamente invisível ao cliente
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-timeline
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
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const PRIMARY_RA = '691755';
const MEMBER_RA = '691640';
const OUTSIDER_RA = '999999';
const ANONYMOUS = null;

const DOG_A = 'dog-timeline-a';
const DOG_B = 'dog-timeline-b';
const DOG_OTHER = 'dog-timeline-other';

const TIMELINE_ID_A = 'tl1_1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
const TIMELINE_ID_B = 'tl1_fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321';

const testEnv = await initializeTestEnvironment({
  projectId: PROJECT_ID,
});

const tests = [];

function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  if (ra === null) {
    return testEnv.unauthenticatedContext();
  }
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    ra: ra,  // Custom claim required for hasRaClaim()
    access_scope: 'global',  // Default access_scope
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

function timelinePayload({
  dogId = DOG_A,
  sourceType = 'meal',
  sourceId = 'meal123',
  recordedAt = now(),
  occurredAt = now(),
  data = {},
} = {}) {
  const payload = {
    dog_id: dogId,
    timeline_type: sourceType,
    source_collection: `dogs/${dogId}/${sourceType === 'meal' ? 'meal_logs' : 'supplement_logs'}`,
    source_id: sourceId,
    recorded_at: recordedAt,
    occurred_at: occurredAt,
    projected_at: now(),
    data: {
      [sourceType]: data,
    },
    created_at: now(),
  };

  // Campos específicos por tipo
  if (sourceType === 'meal') {
    payload.data.meal = {
      type: 'dry_food',
      quantity_grams: 500,
      provider: 'Royal Canin',
      ...data,
    };
  } else {
    payload.data.supplement = {
      supplement_id: 'vitamin_c',
      dosage: '100mg',
      ...data,
    };
  }

  return payload;
}

function statePayload({
  status = 'open',
  sourceType = 'meal',
  dogId = DOG_A,
  sourceId = 'meal123',
} = {}) {
  return {
    status,
    source_type: sourceType,
    dog_id: dogId,
    source_id: sourceId,
    reason_code: 'invalid-source-payload',
    first_seen_at: now(),
    last_seen_at: now(),
    attempts: 1,
    safe_context: {some: 'context'},
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

/**
 * Fixtures: dois dogs com dados básicos
 * - DOG_A: atribuído ao PRIMARY_RA (conductor/primary handler)
 * - DOG_B: atribuído ao MEMBER_RA
 * - DOG_OTHER: sem atribuição aos users de teste
 */
async function seedTimelineFixtures() {
  await seedFirestore(async (adminDb) => {
    // Dog A - atribuído ao PRIMARY_RA
    await setDoc(doc(adminDb, 'dogs', DOG_A), {
      name: 'Rex A',
      conductorRa: PRIMARY_RA,
      conductor_ra: PRIMARY_RA,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      audit_trail: audit(),
    });

    // Dog B - atribuído ao MEMBER_RA
    await setDoc(doc(adminDb, 'dogs', DOG_B), {
      name: 'Rex B',
      conductorRa: MEMBER_RA,
      conductor_ra: MEMBER_RA,
      handlerId: MEMBER_RA,
      handler_id: MEMBER_RA,
      audit_trail: audit('created', MEMBER_RA),
    });

    // Dog OTHER - sem atribuição aos users de teste
    await setDoc(doc(adminDb, 'dogs', DOG_OTHER), {
      name: 'Rex Other',
      conductorRa: 'other123',
      conductor_ra: 'other123',
      handlerId: 'other123',
      handler_id: 'other123',
      audit_trail: audit('created', 'other123'),
    });

    // Timeline entries para Dog A e Dog B (backend-admin criado)
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A),
      timelinePayload({dogId: DOG_A}));
    await setDoc(doc(adminDb, 'dogs', DOG_B, 'health_timeline', TIMELINE_ID_B),
      timelinePayload({dogId: DOG_B, sourceType: 'supplement'}));

    // Estado interno (deve ser invisível)
    await setDoc(doc(adminDb, '_health_projection_state', 'health_timeline_v1'), {
      lease_owner: 'backend-worker',
      lease_expires_at: Timestamp.fromMillis(now().toMillis() + 3600000),
      lease_revision: 1,
    });
    await setDoc(doc(adminDb, '_health_projection_state/health_timeline_v1/discrepancies', 'hd1_test'),
      statePayload());
  });
}

/**
 * Active shift para permitir acesso quando user tem hasOwnRecordsScope
 */
async function seedActiveShift(ra = PRIMARY_RA, dogId = DOG_A) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'active_shifts', ra), {
      shiftId: `shift-${ra}`,
      handlerId: ra,
      auth_uid: `uid-${ra}`,
      handler_email: `${ra}@gcm.com.br`,
      dogId,
      service_dog_id: dogId,
      status: 'active',
      startedAt: now(),
      updatedAt: now(),
    });
  });
}

// ==================== TESTES ====================

test('anonymous timeline read → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(ANONYMOUS);

  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('authenticated authorized dog read → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('authenticated user with global scope can read any dog → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  // PRIMARY_RA com access_scope: 'global' (default) pode ler qualquer dog
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_B, 'health_timeline', TIMELINE_ID_B))
  );
});

test('authenticated with own_records scope + active shift → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();
  await seedActiveShift(PRIMARY_RA, DOG_A);

  // User com hasOwnRecordsScope (access_scope: 'own_records') mas com turno ativo no dog
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('authenticated with own_records scope without access → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();

  // User com hasOwnRecordsScope, sem turno ativo, dog não atribuído
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});

  await assertFails(
    getDoc(doc(db, 'dogs', DOG_OTHER, 'health_timeline', 'any-id'))
  );
});

test('authenticated with own_records scope + dog assignment (no active shift) → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();

  // DOG_A está atribuído ao PRIMARY_RA (conductorRa), mesmo sem active shift
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('client timeline create → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    setDoc(doc(db, 'dogs', DOG_A, 'health_timeline', 'new-id'),
      timelinePayload({dogId: DOG_A}))
  );
});

test('client timeline update → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A),
      {some: 'update'})
  );
});

test('client timeline delete → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    deleteDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('authorized dog-scoped timeline query → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  const timelineQuery = query(
    collection(db, 'dogs', DOG_A, 'health_timeline'),
    orderBy(documentId(), 'asc'),
    limit(10)
  );

  await assertSucceeds(getDocs(timelineQuery));
});

test('dog-scoped timeline query with global scope → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  // User com access_scope: 'global' pode consultar qualquer dog
  const timelineQuery = query(
    collection(db, 'dogs', DOG_B, 'health_timeline'),
    orderBy(documentId(), 'asc'),
    limit(10)
  );

  await assertSucceeds(getDocs(timelineQuery));
});

test('anonymous state read → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(ANONYMOUS);

  await assertFails(
    getDoc(doc(db, '_health_projection_state', 'health_timeline_v1'))
  );
});

test('authenticated state read → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    getDoc(doc(db, '_health_projection_state', 'health_timeline_v1'))
  );
});

test('authenticated state discrepancies read → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    getDoc(doc(db, '_health_projection_state/health_timeline_v1/discrepancies', 'hd1_test'))
  );
});

test('client state create → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    setDoc(doc(db, '_health_projection_state', 'test'),
      {some: 'data'})
  );
});

test('client state update → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    updateDoc(doc(db, '_health_projection_state', 'health_timeline_v1'),
      {lease_revision: 2})
  );
});

test('client state delete → DENY', async () => {
  await clearAll();
  await seedTimelineFixtures();
  const db = dbFor(PRIMARY_RA);

  await assertFails(
    deleteDoc(doc(db, '_health_projection_state', 'health_timeline_v1'))
  );
});

test('admin user always has global scope (ignores access_scope claim) → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();

  // Admin user com access_scope: 'own_records' explícito, mas isAdmin() força global
  const db = dbFor('admin123', {admin: true, access_scope: 'own_records', ra: 'admin123'});

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

test('admin user with global scope timeline read → ALLOW', async () => {
  await clearAll();
  await seedTimelineFixtures();

  // Admin user com access_scope global (default)
  const db = dbFor('admin123', {admin: true});

  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', TIMELINE_ID_A))
  );
});

// ==================== RUNNER ====================

async function run() {
  console.log(`Running ${tests.length} Health Timeline Rules tests...`);

  let passed = 0;
  let failed = 0;
  const failures = [];

  for (const {name, fn} of tests) {
    try {
      await fn();
      console.log(`✓ ${name}`);
      passed++;
    } catch (error) {
      console.log(`✗ ${name}`);
      console.error(`  ${error.message}`);
      failures.push({name, error});
      failed++;
    }
  }

  console.log('\n--- Summary ---');
  console.log(`Total: ${tests.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    console.log('\nFailures:');
    failures.forEach(({name, error}) => {
      console.log(`  ${name}: ${error.message}`);
    });
    process.exit(1);
  }

  console.log('\nAll tests passed!');
  await testEnv.cleanup();
}

// Execute se chamado diretamente
if (import.meta.url === `file://${process.argv[1]}`) {
  run().catch((error) => {
    console.error('Test runner failed:', error);
    process.exit(1);
  });
}

export { tests, run, testEnv };