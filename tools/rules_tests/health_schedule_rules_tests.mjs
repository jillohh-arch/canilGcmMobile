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

/**
 * SEC-02A.2: o estado declarativo de autorização passou a ser obrigatório.
 * O perfil de acesso é a autoridade de escopo — antes as Rules decidiam pela
 * claim, e a fixture não precisava destes documentos.
 */
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
  for (const ra of [PRIMARY_RA, MEMBER_RA, OUTSIDER_RA]) {
    await setDoc(doc(adminDb, 'users', ra), {
      ra,
      access_profile_id: 'operador_k9',
      access_scope: 'own_records',
    });
  }
}

/**
 * Promove um RA a escopo global VIGENTE (perfil global + espelho sem
 * restrição). Necessário porque, a partir do SEC-02A.2, uma claim
 * `access_scope: 'global'` sozinha não concede amplitude: o documento de perfil
 * é a autoridade de escopo.
 */
async function promoteToGlobalScope(ra) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', ra), {
      ra,
      access_profile_id: 'gestor_global',
      access_scope: 'global',
    });
  });
}

async function seedHealthScheduleFixtures() {
  await seedFirestore(async (adminDb) => {
    await seedAuthorizationState(adminDb);
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

test('health_schedule: escopo global EXPLICITO le get e query operacional', async () => {
  await seedHealthScheduleFixtures();

  // SEC-02A: amplitude exige prova positiva de escopo global. Antes deste gate
  // um token SEM access_scope algum era tratado como global.
  await promoteToGlobalScope(PRIMARY_RA);
  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
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

test('health_schedule: escopo global EXPLICITO le K9 alheio (comportamento legitimo preservado)', async () => {
  await seedHealthScheduleFixtures();

  await promoteToGlobalScope(PRIMARY_RA);
  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertSucceeds(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

// ---------------------------------------------------------------------------
// SEC-02A — regressões de fail-closed.
//
// Cada caso abaixo concedia acesso a QUALQUER K9 antes do gate, porque
// canAccessDogRecord era `!hasOwnRecordsScope() || <vínculo>` e a claim ausente
// tinha default 'global'. Agora exigem prova de escopo global ou de vínculo.
// ---------------------------------------------------------------------------

test('health_schedule: SEC-02A claim access_scope AUSENTE nao concede K9 alheio', async () => {
  await seedHealthScheduleFixtures();

  // Token autenticado sem access_scope e sem ra: nenhuma prova de nada.
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertFails(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

test('health_schedule: SEC-02A claim access_scope MALFORMADA nao concede K9 alheio', async () => {
  await seedHealthScheduleFixtures();

  // 'ownRecords' (camelCase) e 'unit' são os erros de digitação plausíveis;
  // '' e 'GLOBAL' fecham o conjunto. Nenhum pode virar amplitude.
  for (const scope of ['ownRecords', 'unit', '', 'GLOBAL', 'Global']) {
    const db = dbFor(OUTSIDER_RA, {access_scope: scope, ra: OUTSIDER_RA});
    await assertFails(
      getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
    );
  }
});

test('health_schedule: SEC-02A usuario comum nao escala para global por fallback', async () => {
  await seedHealthScheduleFixtures();

  // OUTSIDER é condutor apenas de DOG_OTHER (ver fixture). Sem claim de escopo
  // válida, alcança o próprio K9 por vínculo, e NENHUM outro. Antes do gate a
  // claim ausente liberava os três.
  const db = dbFor(OUTSIDER_RA, {ra: OUTSIDER_RA});
  for (const dogId of [DOG_A, DOG_B]) {
    await assertFails(
      getDocs(operationalHealthScheduleQuery(db, dogId)),
    );
  }
  await assertSucceeds(getDocs(operationalHealthScheduleQuery(db, DOG_OTHER)));
});

test('health_schedule: SEC-02A vinculo de condutor concede mesmo sem claim de escopo', async () => {
  await seedHealthScheduleFixtures();

  // Compatibilidade deliberada: condutor legítimo cuja claim de escopo esteja
  // ausente/obsoleta continua lendo o PRÓPRIO K9 por prova de vínculo — o que
  // não pode acontecer é isso virar acesso amplo (caso anterior).
  const db = dbFor(PRIMARY_RA, {ra: PRIMARY_RA});
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
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

// ---------------------------------------------------------------------------
// SEC-02A.2 — MATRIZ DE TOKEN OBSOLETO (stale token)
//
// O perfil de acesso é a autoridade VIGENTE de escopo. Uma claim antiga não
// pode ampliar autorização enquanto o token não é renovado — só restringir.
// Em todos os casos abaixo a claim diz `global`; o estado atual é que decide.
// ---------------------------------------------------------------------------

/** Sobrescreve o espelho do RA, mantendo o resto da fixture. */
async function setUserMirror(ra, data) {
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'users', ra), data);
  });
}

test('SEC-02A.2 A: perfil own_records + claim global → restrito ao próprio K9', async () => {
  await seedHealthScheduleFixtures();
  // Perfil atual é own_records; a claim obsoleta afirma global.
  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});

  // Próprio K9: permitido, mas por VÍNCULO, não por amplitude.
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  // K9 alheio: claim global não amplia.
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertFails(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

test('SEC-02A.2 B: perfil rebaixado de global para own_records → token antigo não amplia', async () => {
  await seedHealthScheduleFixtures();
  // Simula o rebaixamento: o perfil vigente do RA volta a ser own_records
  // enquanto o token em mãos do usuário ainda diz global.
  await promoteToGlobalScope(PRIMARY_RA);
  await setUserMirror(PRIMARY_RA, {
    ra: PRIMARY_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });

  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertFails(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

test('SEC-02A.2 C: perfil inativo + claim global → DENY', async () => {
  await seedHealthScheduleFixtures();
  await promoteToGlobalScope(PRIMARY_RA);
  await seedFirestore(async (adminDb) => {
    await setDoc(doc(adminDb, 'access_profiles', 'gestor_global'), {
      status: 'inactive',
      scope: 'global',
      permissions: {health: {view: true}},
    });
  });

  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  // Nem o próprio K9: o estado de autorização está inválido.
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
});

test('SEC-02A.2 D: usuário soft-deleted + claim global → DENY', async () => {
  await seedHealthScheduleFixtures();
  await setUserMirror(PRIMARY_RA, {
    ra: PRIMARY_RA,
    access_profile_id: 'gestor_global',
    access_scope: 'global',
    deleted_at: now(),
  });

  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
});

test('SEC-02A.2 E: access_profile inexistente + claim global → DENY', async () => {
  await seedHealthScheduleFixtures();
  await setUserMirror(PRIMARY_RA, {
    ra: PRIMARY_RA,
    access_profile_id: 'perfil_que_nao_existe',
    access_scope: 'global',
  });

  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
});

test('SEC-02A.2 F: espelho users/{ra} inexistente + claim global → DENY', async () => {
  await seedHealthScheduleFixtures();
  await seedFirestore(async (adminDb) => {
    await deleteDoc(doc(adminDb, 'users', PRIMARY_RA));
  });

  // Condutor de DOG_A, claim global, mas sem espelho: nega tudo. Vínculo NÃO
  // compensa estado de autorização ausente.
  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
});

test('SEC-02A.2 G: perfil global + claim own_records → restrição do token vale', async () => {
  await seedHealthScheduleFixtures();
  await promoteToGlobalScope(PRIMARY_RA);

  // Perfil concede global, mas a claim declara own_records: restringe.
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records', ra: PRIMARY_RA});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  // Próprio K9 segue acessível por vínculo.
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
  );
});

test('SEC-02A.2 H: perfil global + claim global → global aprovado preservado', async () => {
  await seedHealthScheduleFixtures();
  await promoteToGlobalScope(PRIMARY_RA);

  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
  await assertSucceeds(getDocs(operationalHealthScheduleQuery(db, DOG_B)));
});

test('SEC-02A.2 escopo malformado no perfil + claim global → DENY', async () => {
  await seedHealthScheduleFixtures();
  for (const scope of ['ownRecords', '', 'unit', 'GLOBAL']) {
    await seedFirestore(async (adminDb) => {
      await setDoc(doc(adminDb, 'access_profiles', 'perfil_scope_ruim'), {
        status: 'active',
        scope,
        permissions: {health: {view: true}},
      });
      await setDoc(doc(adminDb, 'users', PRIMARY_RA), {
        ra: PRIMARY_RA,
        access_profile_id: 'perfil_scope_ruim',
      });
    });

    const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
    await assertFails(
      getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 'sched-a1')),
    );
  }
});

test('SEC-02A.2 admin conserva bypass canônico independente do espelho', async () => {
  await seedHealthScheduleFixtures();
  await seedFirestore(async (adminDb) => {
    await deleteDoc(doc(adminDb, 'users', PRIMARY_RA));
  });

  // Admin explícito (claim server-controlled) não depende de espelho/perfil.
  const adminDb = dbFor(PRIMARY_RA, {admin: true, ra: PRIMARY_RA});
  await assertSucceeds(
    getDoc(doc(adminDb, 'dogs', DOG_B, 'health_schedule', 'sched-b1')),
  );
});

test('health_schedule: colecao vazia retorna list vazia (empty real, nao permission-denied)', async () => {
  await seedFirestore(async (adminDb) => {
    // SEC-02A.2: estado declarativo de autorização é pré-requisito, inclusive
    // nos testes que semeiam apenas o K9.
    await seedAuthorizationState(adminDb);
    await setDoc(doc(adminDb, 'dogs', DOG_EMPTY), {
      name: 'Empty',
      audit_trail: audit(),
    });
  });

  // DOG_EMPTY não tem condutor, então o leitor precisa de escopo global
  // EXPLÍCITO (SEC-02A). O ponto do teste é a distinção entre "vazio real" e
  // "permission-denied" — que só é observável com leitor autorizado.
  await promoteToGlobalScope(PRIMARY_RA);
  const db = dbFor(PRIMARY_RA, {access_scope: 'global', ra: PRIMARY_RA});
  const snap = await assertSucceeds(
    getDocs(operationalHealthScheduleQuery(db, DOG_EMPTY)),
  );
  assert.equal(snap.size, 0);
  assert.equal(snap.empty, true);
});

test('health_schedule: SEC-02A vazio-por-falta-de-permissao NAO se disfarca de vazio real', async () => {
  await seedFirestore(async (adminDb) => {
    await seedAuthorizationState(adminDb);
    await setDoc(doc(adminDb, 'dogs', DOG_EMPTY), {
      name: 'Empty',
      audit_trail: audit(),
    });
  });

  // Leitor sem escopo válido e sem vínculo: deve receber ERRO, nunca uma lista
  // vazia que a UI interpretaria como "não há agendamentos".
  const db = dbFor(OUTSIDER_RA, {ra: OUTSIDER_RA});
  await assertFails(getDocs(operationalHealthScheduleQuery(db, DOG_EMPTY)));
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
