/**
 * Health v1 — HW-4A.2C.5
 * Fundação de segurança da Agenda Preventiva GLOBAL (collection group).
 *
 * Prova adversarial multi-K9 de:
 *   match /{path=**}/health_schedule/{scheduleId}
 *
 * Reutiliza a infraestrutura canônica de @firebase/rules-unit-testing + Emulator
 * e as fixtures de estado de autorização do SEC-02A.2 (access_profiles + users).
 *
 * Seeds usam withSecurityRulesDisabled (admin do emulator); as ações sob teste
 * rodam sempre como cliente autenticado/anônimo.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-schedule-cg
 */
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  startAfter,
  updateDoc,
  where,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

const RA_A = '691755';        // condutor do DOG_A
const RA_B = '691640';        // condutor do DOG_B
const RA_AB = '691700';       // condutor de A e B (binding duplo)
const RA_NONE = '999999';     // sem K9
const RA_GLOBAL = '600001';   // escopo global vigente

const DOG_A = 'cg-dog-a';
const DOG_B = 'cg-dog-b';
const DOG_C = 'cg-dog-c-foreign';

const PAGE_SIZE = 21;

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});

const tests = [];
function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`,
    ra,
    ...claims,
  });
}
function dbFor(ra, claims = {}) {
  return auth(ra, claims).firestore();
}
function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}
function now() {
  return Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
}
function audit(action = 'created', by = RA_A) {
  return [{action, by, at: now()}];
}
async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

/**
 * Payload canônico da Agenda + dog_id explícito (contrato pós-migração
 * HW-4A.2C.4). `dogIdOverride` existe SOMENTE para os casos adversariais de
 * integridade (§10) — nunca representa escrita legítima.
 */
function schedulePayload({
  dogId,
  title = 'Vacina antirrábica',
  lifecycleStatus = 'open',
  scheduledFor = now(),
  dogIdField = 'dog_id',
  omitDogId = false,
  dogIdValue = undefined,
} = {}) {
  const base = {
    schedule_type: 'vaccination',
    title,
    scheduled_for: scheduledFor,
    timezone: 'America/Sao_Paulo',
    lifecycle_status: lifecycleStatus,
    source_type: 'manual',
    created_at: now(),
    recorded_by: {
      uid: `uid-${RA_A}`,
      name: 'Condutor',
      internal_role: 'condutor',
    },
    schema_version: 1,
  };
  if (omitDogId) return base;
  base[dogIdField] = dogIdValue === undefined ? dogId : dogIdValue;
  return base;
}

/** SEC-02A.2: perfil de acesso é a autoridade de escopo. */
async function seedAuthorizationState(adminDb) {
  await setDoc(doc(adminDb, 'access_profiles', 'operador_k9'), {
    status: 'active',
    scope: 'own_records',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  await setDoc(doc(adminDb, 'access_profiles', 'gestor_global'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  for (const ra of [RA_A, RA_B, RA_AB, RA_NONE]) {
    await setDoc(doc(adminDb, 'users', ra), {
      ra,
      access_profile_id: 'operador_k9',
      access_scope: 'own_records',
    });
  }
  await setDoc(doc(adminDb, 'users', RA_GLOBAL), {
    ra: RA_GLOBAL,
    access_profile_id: 'gestor_global',
    access_scope: 'global',
  });
}

/**
 * Fixtures adversariais multi-K9 (§8). Produção tem dados de um único cão;
 * isolamento entre cães só pode ser provado sinteticamente.
 *
 * DOG_A -> RA_A (e RA_AB)
 * DOG_B -> RA_B (e RA_AB)
 * DOG_C -> RA_NONE (estrangeiro para A e B)
 */
async function seedMultiDogFixtures() {
  await seedFirestore(async (adminDb) => {
    await seedAuthorizationState(adminDb);

    await setDoc(doc(adminDb, 'dogs', DOG_A), {
      name: 'K9 A',
      conductorRa: RA_A,
      conductor_ra: RA_A,
      handlerId: RA_A,
      handler_id: RA_A,
      audit_trail: audit(),
    });
    await setDoc(doc(adminDb, 'dogs', DOG_B), {
      name: 'K9 B',
      conductorRa: RA_B,
      conductor_ra: RA_B,
      handlerId: RA_B,
      handler_id: RA_B,
      audit_trail: audit('created', RA_B),
    });
    await setDoc(doc(adminDb, 'dogs', DOG_C), {
      name: 'K9 C estrangeiro',
      conductorRa: RA_NONE,
      conductor_ra: RA_NONE,
      audit_trail: audit('created', RA_NONE),
    });

    const T20 = Timestamp.fromDate(new Date('2026-07-20T12:00:00.000Z'));
    const T21 = Timestamp.fromDate(new Date('2026-07-21T12:00:00.000Z'));
    const T19 = Timestamp.fromDate(new Date('2026-07-19T12:00:00.000Z'));

    // A: open / open(mesmo timestamp de B) / completed / cancelled
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a1-open'),
      schedulePayload({dogId: DOG_A, title: 'A1 open', scheduledFor: T19}));
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a2-open-tie'),
      schedulePayload({dogId: DOG_A, title: 'A2 open tie', scheduledFor: T20}));
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a3-done'),
      schedulePayload({dogId: DOG_A, title: 'A3 completed', lifecycleStatus: 'completed', scheduledFor: T19}));
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a4-cancelled'),
      schedulePayload({dogId: DOG_A, title: 'A4 cancelled', lifecycleStatus: 'cancelled', scheduledFor: T19}));

    // B: open / open(mesmo timestamp de A)
    await setDoc(doc(adminDb, 'dogs', DOG_B, 'health_schedule', 'b1-open'),
      schedulePayload({dogId: DOG_B, title: 'B1 open', scheduledFor: T21}));
    await setDoc(doc(adminDb, 'dogs', DOG_B, 'health_schedule', 'b2-open-tie'),
      schedulePayload({dogId: DOG_B, title: 'B2 open tie', scheduledFor: T20}));

    // C: open (estrangeiro)
    await setDoc(doc(adminDb, 'dogs', DOG_C, 'health_schedule', 'c1-open'),
      schedulePayload({dogId: DOG_C, title: 'C1 open', scheduledFor: T20}));
  });
}

/** Promove RA a escopo global vigente. */
async function promoteToGlobal(ra) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', ra), {
      ra,
      access_profile_id: 'gestor_global',
      access_scope: 'global',
    });
  });
}

/** Vincula RA_AB a DOG_A e DOG_B (binding duplo por condutor). */
async function bindDualDog() {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A), {
      name: 'K9 A',
      conductorRa: RA_AB,
      conductor_ra: RA_AB,
      handlerId: RA_AB,
      handler_id: RA_AB,
      audit_trail: audit(),
    });
    await setDoc(doc(adminDb, 'dogs', DOG_B), {
      name: 'K9 B',
      conductorRa: RA_AB,
      conductor_ra: RA_AB,
      handlerId: RA_AB,
      handler_id: RA_AB,
      audit_trail: audit(),
    });
  });
}

// ---------------------------------------------------------------------------
// §13 formas de query
// ---------------------------------------------------------------------------

/**
 * GLOBAL sem restrição de dog_id. Sob a identidade ESTRITA do 5R esta forma é
 * NEGADA por contrato (Rules não são filtros: o motor não consegue provar que
 * TODO documento correspondente tem dog_id canônico a partir de um filtro de
 * lifecycle_status, nem de orderBy/inequality sobre dog_id).
 */
function globalUnrestrictedQuery(db, pageSize = PAGE_SIZE) {
  return query(
    collectionGroup(db, 'health_schedule'),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(pageSize),
  );
}

/**
 * GLOBAL operacional PROVADO: restringe por dog_id enumerado (chunks de <= 30).
 * A amplitude vem do escopo (global lê QUALQUER cão), não da ausência de filtro.
 */
function globalAgendaQuery(db, pageSize = PAGE_SIZE, dogIds = [DOG_A, DOG_B, DOG_C]) {
  return query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', dogIds),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(pageSize),
  );
}

/** OWN_RECORDS: collection group restrita aos K9s autorizados. */
function ownRecordsAgendaQuery(db, dogIds, pageSize = PAGE_SIZE) {
  return query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', dogIds),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(pageSize),
  );
}

// ===========================================================================
// §6 GLOBAL
// ===========================================================================

test('CG global: escopo global VIGENTE le agenda multi-K9', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  const snap = await assertSucceeds(getDocs(globalAgendaQuery(db)));
  const dogs = new Set(snap.docs.map((d) => d.data().dog_id));
  assert.ok(dogs.size >= 3, `global deve alcancar varios K9s, veio ${dogs.size}`);
  assert.ok(snap.docs.every((d) => d.data().lifecycle_status === 'open'));
});

test('CG global: claim global OBSOLETA com perfil own_records NAO amplia', async () => {
  await seedMultiDogFixtures();
  // Perfil vigente de RA_A é own_records; a claim mente dizendo global.
  const db = dbFor(RA_A, {access_scope: 'global'});
  await assertFails(getDocs(globalAgendaQuery(db)));
});

test('CG global: perfil AUSENTE nega', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', RA_GLOBAL), {
      ra: RA_GLOBAL,
      access_profile_id: 'perfil_inexistente',
      access_scope: 'global',
    });
  });
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(globalAgendaQuery(db)));
});

test('CG global: perfil INATIVO nega', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'access_profiles', 'gestor_global'), {
      status: 'inactive',
      scope: 'global',
      permissions: {health: {view: true}},
    });
  });
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(globalAgendaQuery(db)));
});

test('CG global: usuario SOFT-DELETED nega', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', RA_GLOBAL), {
      ra: RA_GLOBAL,
      access_profile_id: 'gestor_global',
      access_scope: 'global',
      deleted_at: now(),
    });
  });
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(globalAgendaQuery(db)));
});

test('CG global: scope MALFORMADO no perfil nega', async () => {
  await seedMultiDogFixtures();
  for (const bad of ['', 'GLOBAL', 'todos', 'own', 42]) {
    await seedFirestore(async (adminDb) => {
      await setDoc(doc(adminDb, 'access_profiles', 'gestor_global'), {
        status: 'active',
        scope: bad,
        permissions: {health: {view: true}},
      });
    });
    const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
    await assertFails(getDocs(globalAgendaQuery(db)));
  }
});

test('CG global: usuario INEXISTENTE nega', async () => {
  await seedMultiDogFixtures();
  const db = dbFor('000000', {access_scope: 'global'});
  await assertFails(getDocs(globalAgendaQuery(db)));
});

test('CG global: ANONIMO nega', async () => {
  await seedMultiDogFixtures();
  await assertFails(getDocs(globalAgendaQuery(anonDb())));
});

test('CG global: token SEM claim ra nega', async () => {
  await seedMultiDogFixtures();
  const db = testEnv.authenticatedContext('uid-sem-ra', {}).firestore();
  await assertFails(getDocs(globalAgendaQuery(db)));
});

// ===========================================================================
// §7 OWN_RECORDS
// ===========================================================================

test('CG own_records: query IRRESTRITA e NEGADA', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(globalUnrestrictedQuery(db)));
});

test('CG own_records: OWN_A com dog_id IN [A] e permitido', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  const snap = await assertSucceeds(getDocs(ownRecordsAgendaQuery(db, [DOG_A])));
  assert.ok(snap.docs.length > 0, 'A deve ver a propria agenda');
  assert.ok(snap.docs.every((d) => d.data().dog_id === DOG_A));
});

test('CG own_records: OWN_A com dog_id IN [B] e NEGADO', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(ownRecordsAgendaQuery(db, [DOG_B])));
});

test('CG own_records: OWN_A com dog_id IN [A,B] e NEGADO', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(ownRecordsAgendaQuery(db, [DOG_A, DOG_B])));
});

test('CG own_records: OWN_A com dog_id IN [A,C] e NEGADO', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(ownRecordsAgendaQuery(db, [DOG_A, DOG_C])));
});

test('CG own_records: OWN_A_B com binding duplo le A e B', async () => {
  await seedMultiDogFixtures();
  await bindDualDog();
  const db = dbFor(RA_AB, {access_scope: 'own_records'});
  const snap = await assertSucceeds(getDocs(ownRecordsAgendaQuery(db, [DOG_A, DOG_B])));
  const dogs = new Set(snap.docs.map((d) => d.data().dog_id));
  assert.ok(dogs.has(DOG_A) && dogs.has(DOG_B), `esperado A e B, veio ${[...dogs]}`);
});

test('CG own_records: OWN_NONE com dog_id IN [A] e NEGADO', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_NONE, {access_scope: 'own_records'});
  await assertFails(getDocs(ownRecordsAgendaQuery(db, [DOG_A])));
});

test('CG own_records: stale global claim mantem comportamento own', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'global'});
  // Não amplia: irrestrita nega...
  await assertFails(getDocs(globalAgendaQuery(db)));
  // ...e restrita ao próprio K9 continua funcionando.
  const snap = await assertSucceeds(getDocs(ownRecordsAgendaQuery(db, [DOG_A])));
  assert.ok(snap.docs.every((d) => d.data().dog_id === DOG_A));
});

test('CG own_records: ANONIMO com dog_id IN [A] e NEGADO', async () => {
  await seedMultiDogFixtures();
  await assertFails(getDocs(ownRecordsAgendaQuery(anonDb(), [DOG_A])));
});

// ===========================================================================
// §10 integridade adversarial de dog_id
// ===========================================================================

test('CG integridade: dog_id AUSENTE nao e alcancavel por own_records', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a-nodogid'),
      schedulePayload({omitDogId: true, title: 'sem dog_id'}));
  });
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  const snap = await assertSucceeds(getDocs(ownRecordsAgendaQuery(db, [DOG_A])));
  assert.ok(!snap.docs.some((d) => d.id === 'a-nodogid'),
    'documento sem dog_id nao pode aparecer na query IN');
});

test('CG integridade: dog_id VAZIO nega leitura direta', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a-empty'),
      schedulePayload({dogIdValue: '', title: 'dog_id vazio'}));
  });
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', '==', ''),
    limit(5),
  )));
});

test('CG integridade: dog_id de TIPO ERRADO nega', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a-wrongtype'),
      schedulePayload({dogIdValue: 12345, title: 'dog_id numerico'}));
  });
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', '==', 12345),
    limit(5),
  )));
});

/**
 * LIMITE ESTRUTURAL DOCUMENTADO: documento fisicamente sob DOG_A declarando
 * dog_id = DOG_B. As Rules de collection group NÃO alcançam o pai do path,
 * então decidem por dog_id.
 *
 * Consequência: OWN_A NÃO ganha acesso pela localização física, e OWN_B
 * consegue ler um documento cujo pai real é DOG_A. Isso NÃO é falha das Rules
 * — é o limite do Firestore. Divergência de dog_id é INCIDENTE DE INTEGRIDADE,
 * prevenido pelo writer canônico + migração, nunca reparado pelas Rules.
 */
test('CG integridade: MISMATCH dog_id nao concede acesso ao dono estrutural', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a-mismatch'),
      schedulePayload({dogIdValue: DOG_B, title: 'mismatch'}));
  });
  const dbA = dbFor(RA_A, {access_scope: 'own_records'});
  const snapA = await assertSucceeds(getDocs(ownRecordsAgendaQuery(dbA, [DOG_A])));
  assert.ok(!snapA.docs.some((d) => d.id === 'a-mismatch'),
    'OWN_A nao pode alcancar via localizacao estrutural');
});

test('CG integridade: MISMATCH dog_id e alcancavel pelo dono DECLARADO (limite conhecido)', async () => {
  await seedMultiDogFixtures();
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', 'a-mismatch'),
      schedulePayload({dogIdValue: DOG_B, title: 'mismatch'}));
  });
  const dbB = dbFor(RA_B, {access_scope: 'own_records'});
  const snapB = await assertSucceeds(getDocs(ownRecordsAgendaQuery(dbB, [DOG_B])));
  assert.ok(snapB.docs.some((d) => d.id === 'a-mismatch'),
    'limite documentado: CG decide por dog_id, nao pelo pai estrutural');
});

// ===========================================================================
// HW-4A.2C.5R — IDENTIDADE ESTRITA: aliases legados NUNCA substituem dog_id
//
// Contrato canônico desta coleção: a identidade denormalizada aceita pela
// fronteira de segurança collection-group é EXCLUSIVAMENTE `dog_id`.
// `dogId` e `caoId` existem em outros domínios (coexistência legada) e não
// podem autorizar Health Schedule pela porta dos fundos.
// ===========================================================================

/** Semeia um doc FISICAMENTE sob DOG_A que declara identidade de DOG_B via alias. */
async function seedAliasCase(docId, fields) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', docId), {
      schedule_type: 'vaccination',
      title: 'alias legado',
      scheduled_for: Timestamp.fromDate(new Date('2026-07-20T12:00:00.000Z')),
      timezone: 'America/Sao_Paulo',
      lifecycle_status: 'open',
      source_type: 'manual',
      created_at: now(),
      recorded_by: {uid: `uid-${RA_A}`, name: 'Condutor', internal_role: 'condutor'},
      schema_version: 1,
      ...fields,
    });
  });
}

const ALIAS_CASES = [
  ['CASE A: dog_id AUSENTE + dogId=B', 'alias-a', {dogId: DOG_B}],
  ['CASE B: dog_id AUSENTE + caoId=B', 'alias-b', {caoId: DOG_B}],
  ['CASE C: dog_id VAZIO + dogId=B', 'alias-c', {dog_id: '', dogId: DOG_B}],
  ['CASE D: dog_id TIPO ERRADO + caoId=B', 'alias-d', {dog_id: 12345, caoId: DOG_B}],
];

for (const [label, docId, fields] of ALIAS_CASES) {
  test(`5R alias direto: OWN_B NAO le doc sob DOG_A — ${label}`, async () => {
    await seedMultiDogFixtures();
    await seedAliasCase(docId, fields);
    const dbB = dbFor(RA_B, {access_scope: 'own_records'});
    await assertFails(getDoc(doc(dbB, 'dogs', DOG_A, 'health_schedule', docId)));
  });

  test(`5R alias CG: OWN_B NAO alcanca via query no alias — ${label}`, async () => {
    await seedMultiDogFixtures();
    await seedAliasCase(docId, fields);
    const dbB = dbFor(RA_B, {access_scope: 'own_records'});
    const aliasField = 'dogId' in fields ? 'dogId' : 'caoId';
    await assertFails(getDocs(query(
      collectionGroup(dbB, 'health_schedule'),
      where(aliasField, '==', DOG_B),
      limit(5),
    )));
  });
}

/**
 * A regra ANINHADA (dogs/{dogId}/health_schedule) é autoridade de PATH e não
 * depende de dog_id — comportamento canônico preexistente que este gate NÃO
 * altera. Logo o dono estrutural continua lendo por caminho direto, mesmo que o
 * documento não tenha dog_id canônico. O que a regra recursiva não pode fazer é
 * conceder isso a TERCEIROS via alias (provado nos CASE A–D acima).
 */
test('5R alias: dono ESTRUTURAL mantem leitura direta (autoridade de path preservada)', async () => {
  await seedMultiDogFixtures();
  await seedAliasCase('alias-own', {dogId: DOG_A});
  const dbA = dbFor(RA_A, {access_scope: 'own_records'});
  await assertSucceeds(getDoc(doc(dbA, 'dogs', DOG_A, 'health_schedule', 'alias-own')));
});

/**
 * §7 — decisão de política: fail-closed também para GLOBAL.
 * Após a migração, TODO documento canônico carrega dog_id. Um documento sem
 * identidade canônica não é legível pela regra recursiva nem para global,
 * para não criar ambiguidade de namespace.
 */
test('5R politica global: GLOBAL nao le doc sem dog_id canonico via CG recursiva', async () => {
  await seedMultiDogFixtures();
  await seedAliasCase('alias-global', {dogId: DOG_B});
  const dbG = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(query(
    collectionGroup(dbG, 'health_schedule'),
    where('dogId', '==', DOG_B),
    limit(5),
  )));
});

test('5R politica global: GLOBAL continua lendo agenda canonica multi-K9', async () => {
  await seedMultiDogFixtures();
  await seedAliasCase('alias-global-2', {dogId: DOG_B});
  const dbG = dbFor(RA_GLOBAL, {access_scope: 'global'});
  const snap = await assertSucceeds(getDocs(globalAgendaQuery(dbG)));
  assert.ok(snap.docs.every((d) => typeof d.data().dog_id === 'string' && d.data().dog_id.length > 0));
  assert.ok(!snap.docs.some((d) => d.id === 'alias-global-2'));
});

/**
 * CONSEQUÊNCIA ARQUITETURAL da identidade estrita (Rules não são filtros).
 *
 * Com `dog_id` exigido FORA do OR, o motor precisa provar que TODO documento
 * correspondente à query tem dog_id canônico. Só igualdade/`in` prova isso;
 * filtro por lifecycle_status, orderBy('dog_id') e inequality (`>`/`!=`) NÃO
 * provam — logo a query global irrestrita é negada mesmo com dados 100%
 * canônicos. A amplitude do GLOBAL passa a vir do ESCOPO (pode enumerar
 * qualquer cão), não da ausência de filtro.
 */
test('5R forma de query: GLOBAL irrestrita NEGADA mesmo com dados canonicos', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(globalUnrestrictedQuery(db)));
});

test('5R forma de query: orderBy/inequality em dog_id NAO provam identidade', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'), orderBy('dog_id'), limit(5))));
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'), where('dog_id', '>', ''), limit(5))));
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'), where('dog_id', '!=', ''), limit(5))));
});

test('5R forma de query: GLOBAL com dog_id IN enumerado e PERMITIDA', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  const snap = await assertSucceeds(getDocs(globalAgendaQuery(db)));
  const dogs = new Set(snap.docs.map((d) => d.data().dog_id));
  assert.ok(dogs.size >= 3, `global deve alcancar varios K9s, veio ${dogs.size}`);
});

test('5R forma de query: GLOBAL enumera K9 de TERCEIRO (amplitude preservada)', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  // DOG_C não é do gestor; escopo global mesmo assim autoriza.
  const snap = await assertSucceeds(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', [DOG_C]),
    limit(5))));
  assert.ok(snap.docs.length > 0 && snap.docs.every((d) => d.data().dog_id === DOG_C));
});

test('5R forma de query: OWN_A nao ganha amplitude enumerando terceiros', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', [DOG_A, DOG_B, DOG_C]),
    limit(5))));
});

// ===========================================================================
// HW-4A.2C.5R.1 — SUPERFÍCIE MÍNIMA: a regra recursiva autoriza só LIST.
//
// `read` cobre get + list. A Agenda Global precisa da regra recursiva apenas
// para QUERY. O detalhe individual continua sob a regra aninhada, que é
// autoridade de PATH. Reduzindo para `list`, a limitação de mismatch deixa de
// afetar GET individual.
// ===========================================================================

const MISMATCH_GET = 'mismatch-get';

async function seedMismatchGet(fields = {dog_id: DOG_B}) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'dogs', DOG_A, 'health_schedule', MISMATCH_GET), {
      schedule_type: 'vaccination',
      title: 'mismatch get',
      scheduled_for: Timestamp.fromDate(new Date('2026-07-20T12:00:00.000Z')),
      timezone: 'America/Sao_Paulo',
      lifecycle_status: 'open',
      source_type: 'manual',
      created_at: now(),
      recorded_by: {uid: `uid-${RA_A}`, name: 'Condutor', internal_role: 'condutor'},
      schema_version: 1,
      ...fields,
    });
  });
}

const getMismatch = (db) => getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', MISMATCH_GET));

test('5R.1 GET: OWN_B NAO abre doc fisico de A com dog_id=B', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  await assertFails(getMismatch(dbFor(RA_B, {access_scope: 'own_records'})));
});

test('5R.1 GET: OWN_B NAO abre doc de A sem dog_id + dogId=B', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dogId: DOG_B});
  await assertFails(getMismatch(dbFor(RA_B, {access_scope: 'own_records'})));
});

test('5R.1 GET: OWN_B NAO abre doc de A sem dog_id + caoId=B', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({caoId: DOG_B});
  await assertFails(getMismatch(dbFor(RA_B, {access_scope: 'own_records'})));
});

test('5R.1 GET: OWN_A abre doc do proprio K9 (autoridade de path)', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  await assertSucceeds(getMismatch(dbFor(RA_A, {access_scope: 'own_records'})));
});

test('5R.1 GET: GLOBAL abre doc fisico de A', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  await assertSucceeds(getMismatch(dbFor(RA_GLOBAL, {access_scope: 'global'})));
});

test('5R.1 GET: ANONIMO nega', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  await assertFails(getMismatch(anonDb()));
});

test('5R.1 GET: auth quebrada (perfil ausente) nega', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', RA_B), {
      ra: RA_B, access_profile_id: 'perfil_inexistente', access_scope: 'own_records',
    });
  });
  await assertFails(getMismatch(dbFor(RA_B, {access_scope: 'own_records'})));
});

/**
 * §6 — `allow list` vale para QUERY em geral, não só collectionGroup(). Uma
 * query na coleção física de A filtrando dog_id==B tem seu resultado decidido
 * pela regra recursiva, que confia em dog_id. Comportamento medido, não inferido.
 */
test('5R.1 LIST por-cao: OWN_B consultando dogs/A/health_schedule com dog_id==B', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dog_id: DOG_B});
  const dbB = dbFor(RA_B, {access_scope: 'own_records'});
  // MEDIDO: ALLOW. A regra recursiva `list` decide por dog_id e não alcança o
  // pai estrutural, então isto vale para QUALQUER query — não só collectionGroup.
  // O limite remanescente de mismatch é de LIST/QUERY, e é contido por
  // integridade de dado (writer canônico + migração + auditoria), nunca por path
  // introspection (não suportado).
  const snap = await assertSucceeds(getDocs(query(
    collection(dbB, 'dogs', DOG_A, 'health_schedule'),
    where('dog_id', '==', DOG_B),
    limit(5),
  )));
  assert.equal(snap.size, 1, 'limite documentado: LIST decide por dog_id declarado');
});

test('5R.1 LIST por-cao: OWN_B NAO lista doc de A sem dog_id canonico (alias)', async () => {
  await seedMultiDogFixtures();
  await seedMismatchGet({dogId: DOG_B});
  const dbB = dbFor(RA_B, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collection(dbB, 'dogs', DOG_A, 'health_schedule'),
    where('dogId', '==', DOG_B),
    limit(5),
  )));
});

// ===========================================================================
// §11 regressão de leitura direta por K9
// ===========================================================================

test('regressao direta: OWN_A le dogs/A/health_schedule', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertSucceeds(getDocs(query(
    collection(db, 'dogs', DOG_A, 'health_schedule'),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    orderBy(documentId(), 'asc'),
    limit(PAGE_SIZE),
  )));
});

test('regressao direta: OWN_A NAO le dogs/B/health_schedule', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collection(db, 'dogs', DOG_B, 'health_schedule'),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(PAGE_SIZE),
  )));
});

test('regressao direta: OWN_A NAO le dogs/C/health_schedule', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(getDocs(query(
    collection(db, 'dogs', DOG_C, 'health_schedule'),
    limit(PAGE_SIZE),
  )));
});

test('regressao direta: GLOBAL le A e B diretamente', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  for (const d of [DOG_A, DOG_B, DOG_C]) {
    await assertSucceeds(getDocs(query(
      collection(db, 'dogs', d, 'health_schedule'),
      limit(PAGE_SIZE),
    )));
  }
});

test('regressao direta: ANONIMO nao le agenda direta', async () => {
  await seedMultiDogFixtures();
  await assertFails(getDocs(query(
    collection(anonDb(), 'dogs', DOG_A, 'health_schedule'),
    limit(PAGE_SIZE),
  )));
});

// ===========================================================================
// §12 writes permanecem negados
// ===========================================================================

test('writes: cliente own_records nao cria/atualiza/deleta', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_A, {access_scope: 'own_records'});
  await assertFails(setDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'novo'),
    schedulePayload({dogId: DOG_A})));
  await assertFails(updateDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'a1-open'),
    {title: 'hack'}));
  await assertFails(deleteDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'a1-open')));
});

test('writes: cliente GLOBAL nao cria/atualiza/deleta', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  await assertFails(setDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'novo-g'),
    schedulePayload({dogId: DOG_A})));
  await assertFails(updateDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'a1-open'),
    {title: 'hack'}));
  await assertFails(deleteDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'a1-open')));
});

// ===========================================================================
// §14 limite do operador IN
// ===========================================================================

/**
 * §14 — o teto de 30 valores por `in` agora vale TAMBÉM para GLOBAL, porque a
 * identidade estrita obriga o escopo amplo a enumerar dog_id. Acima de 30 K9s,
 * o futuro reader precisa de bounded chunking nos DOIS escopos.
 */
test('IN limit: GLOBAL com 31 dog_ids e rejeitado (chunking obrigatorio)', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  const ids31 = Array.from({length: 31}, (_, i) => `dog-${i}`);
  let rejected = false;
  try {
    await getDocs(query(
      collectionGroup(db, 'health_schedule'),
      where('dog_id', 'in', ids31),
      where('lifecycle_status', '==', 'open'),
      orderBy('scheduled_for', 'asc'),
      limit(PAGE_SIZE),
    ));
  } catch {
    rejected = true;
  }
  assert.equal(rejected, true, 'GLOBAL tambem esta sujeito ao teto de 30');
});

test('IN limit: GLOBAL em 2 chunks de <=30 cobre o catalogo inteiro', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});
  const chunk1 = [DOG_A, ...Array.from({length: 29}, (_, i) => `filler-${i}`)];
  const chunk2 = [DOG_B, DOG_C];
  const seen = new Set();
  for (const chunk of [chunk1, chunk2]) {
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(db, 'health_schedule'),
      where('dog_id', 'in', chunk),
      where('lifecycle_status', '==', 'open'),
      orderBy('scheduled_for', 'asc'),
      limit(PAGE_SIZE),
    )));
    snap.docs.forEach((d) => seen.add(d.data().dog_id));
  }
  assert.ok(seen.has(DOG_A) && seen.has(DOG_B) && seen.has(DOG_C),
    `chunking deve cobrir A, B e C — veio ${[...seen]}`);
});

test('IN limit: 30 valores aceitos e 31 rejeitados', async () => {
  await seedMultiDogFixtures();
  await promoteToGlobal(RA_GLOBAL);
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});

  const ids30 = Array.from({length: 30}, (_, i) => `dog-${i}`);
  await assertSucceeds(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', ids30),
    limit(PAGE_SIZE),
  )));

  const ids31 = Array.from({length: 31}, (_, i) => `dog-${i}`);
  let rejected = false;
  try {
    await getDocs(query(
      collectionGroup(db, 'health_schedule'),
      where('dog_id', 'in', ids31),
      limit(PAGE_SIZE),
    ));
  } catch {
    rejected = true;
  }
  assert.equal(rejected, true, '31 valores devem ser rejeitados pelo SDK/backend');
});

// ===========================================================================
// §15 paginação com timestamps duplicados
// ===========================================================================

test('paginacao global: ordem estavel, sem duplicatas nem saltos', async () => {
  await seedMultiDogFixtures();
  const db = dbFor(RA_GLOBAL, {access_scope: 'global'});

  const full = await assertSucceeds(getDocs(globalAgendaQuery(db, 50)));
  const expected = full.docs.map((d) => d.ref.path);

  const seen = [];
  let cursor = null;
  for (let page = 0; page < 10; page++) {
    const q = cursor
      ? query(
        collectionGroup(db, 'health_schedule'),
        where('dog_id', 'in', [DOG_A, DOG_B, DOG_C]),
        where('lifecycle_status', '==', 'open'),
        orderBy('scheduled_for', 'asc'),
        startAfter(cursor),
        limit(2),
      )
      : query(
        collectionGroup(db, 'health_schedule'),
        where('dog_id', 'in', [DOG_A, DOG_B, DOG_C]),
        where('lifecycle_status', '==', 'open'),
        orderBy('scheduled_for', 'asc'),
        limit(2),
      );
    const snap = await assertSucceeds(getDocs(q));
    if (snap.empty) break;
    seen.push(...snap.docs.map((d) => d.ref.path));
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < 2) break;
  }

  assert.deepEqual(seen, expected, 'paginacao deve cobrir exatamente o conjunto');
  assert.equal(new Set(seen).size, seen.length, 'nenhuma duplicata');
});

// ---------------------------------------------------------------------------

let pass = 0;
let fail = 0;
for (const {name, fn} of tests) {
  try {
    await testEnv.clearFirestore();
    await fn();
    console.log(`  ok  ${name}`);
    pass++;
  } catch (error) {
    console.error(`  FAIL ${name}`);
    console.error(`       code=${error?.code || '(none)'} ${String(error?.message || error).replace(/\s+/g, ' ').slice(0, 400)}`);
    fail++;
  }
}
await testEnv.cleanup();
console.log('');
console.log(`RESULTADO: ${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
