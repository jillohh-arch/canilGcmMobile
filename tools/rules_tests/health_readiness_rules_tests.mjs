/**
 * Readiness v1 — Gate 5
 * Testes de Firestore Rules para:
 *   dogs/{dogId}/health_summary/{summaryId}
 *   dogs/{dogId}/operational_restrictions/{restrictionId}
 *
 * Contrato sob teste:
 * 1. Leitura permitida para usuário autenticado com acesso ao K9
 *    (mesmo modelo factual já usado por weight_records / nutrition_plans /
 *     health_events / health_timeline: signedIn() && canAccessDogRecord(dogId)).
 * 2. Escrita cliente totalmente proibida em ambos os caminhos.
 * 3. health_summary é projeção de DISPLAY — nunca autoridade de autorização.
 * 4. operational_restrictions permanece decisão de backend: sem create/update/
 *    delete/release/cancel por cliente.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-readiness
 */
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';

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
  query,
  setDoc,
  updateDoc,
  where,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

// RA vinculado ao K9 sob teste. Sob SEC-02A.2 a autoridade vem do PERFIL
// (own_records) somada ao VÍNCULO com o cão — não da claim `access_scope`.
const PRIMARY_RA = '691755';
// RA com estado de autorização VÁLIDO, porém SEM vínculo com o K9 → negado.
const OUTSIDER_RA = '999999';
// RA cujo perfil resolve escopo global — autoridade ampla legítima.
const GLOBAL_RA = '700001';
// RA autenticado SEM espelho em users/{ra} → estado não resolvível → DENY.
const NO_MIRROR_RA = '700002';
// RA cujo espelho aponta para um perfil que não existe → DENY.
const NO_PROFILE_RA = '700003';
// RA cujo perfil existe mas está inativo → DENY.
const INACTIVE_RA = '700004';
const ANONYMOUS = null;

const DOG_A = 'dog-readiness-a';

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});

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
    ra: ra,
    access_scope: 'global',
    ...claims,
  });
}

function dbFor(ra, claims = {}) {
  return auth(ra, claims).firestore();
}

function now() {
  return Timestamp.fromDate(new Date('2026-08-11T12:00:00.000Z'));
}

/** Snapshot de Prontidão pronto (projection_status: ready). */
function readySummaryPayload({
  readinessStatus = 'operational',
  readinessLabel = 'Operacional',
} = {}) {
  return {
    projection_status: 'ready',
    readiness_status: readinessStatus,
    readiness_label: readinessLabel,
    readiness_reason: 'Sem restrições ativas e dados de saúde em dia.',
    readiness_reason_code: 'no_restrictions_evidence_complete',
    readiness_updated_at: now(),
    projection_attempted_at: now(),
    evaluated_by: 'function_v1',
    data_completeness: {
      has_recent_weight: true,
      has_vaccination_current: true,
      has_recent_consultation: true,
      has_active_nutrition: true,
    },
    active_restrictions: [],
    restriction_count: {absolute: 0, partial: 0, attention: 0},
    open_alerts: [],
    last_evaluated_at: now(),
    technical_blockers: [],
    updated_at: now(),
    schema_version: 1,
  };
}

function restrictionPayload({
  level = 'absolute',
  status = 'active',
} = {}) {
  return {
    level,
    category: 'injury',
    description: 'Lesão em membro anterior',
    status,
    since: now(),
    activities_restricted: [],
    schema_version: 1,
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
 * SEC-02A.2 — estado de autorização é PRÉ-REQUISITO, não detalhe de fixture.
 *
 * Antes desta reconciliação a suite dependia apenas da claim `access_scope`, que
 * era o modelo da variante fail-OPEN. Sob SEC-02A.2 o perfil de acesso é a
 * autoridade e `authState()` faz `get()` em `users/{ra}` e
 * `access_profiles/{id}`: sem esses documentos a avaliação nem chega a decidir —
 * ela ERRA, e um erro de avaliação não é prova de DENY.
 *
 * Semeia o estado MÍNIMO derivado das Rules (nada inventado):
 *   users/{ra}.access_profile_id  -> resolve o perfil
 *   access_profiles/{id}.status   -> 'active'
 *   access_profiles/{id}.scope    -> enum válido ('own_records' | 'global')
 */
async function seedAuthorizationState(db) {
  await setDoc(doc(db, 'access_profiles', 'operador_k9'), {
    status: 'active',
    scope: 'own_records',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  await setDoc(doc(db, 'access_profiles', 'gestor_global'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  // Condutor vinculado ao DOG_A: autoridade por VÍNCULO, escopo restrito.
  await setDoc(doc(db, 'users', PRIMARY_RA), {
    ra: PRIMARY_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });
  // Estado válido, porém SEM vínculo com o K9 — deve continuar negado.
  await setDoc(doc(db, 'users', OUTSIDER_RA), {
    ra: OUTSIDER_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });
  // Autoridade ampla resolvida pelo perfil.
  await setDoc(doc(db, 'users', GLOBAL_RA), {
    ra: GLOBAL_RA,
    access_profile_id: 'gestor_global',
    access_scope: 'global',
  });
  // NO_MIRROR_RA: deliberadamente SEM documento em users/{ra}.
  // Espelho aponta para perfil inexistente.
  await setDoc(doc(db, 'users', NO_PROFILE_RA), {
    ra: NO_PROFILE_RA,
    access_profile_id: 'perfil_que_nao_existe',
    access_scope: 'global',
  });
  // Perfil existe, porém inativo — status é consultado pelo authState().
  await setDoc(doc(db, 'access_profiles', 'perfil_inativo'), {
    status: 'inactive',
    scope: 'global',
    permissions: {health: {view: true}},
  });
  await setDoc(doc(db, 'users', INACTIVE_RA), {
    ra: INACTIVE_RA,
    access_profile_id: 'perfil_inativo',
    access_scope: 'global',
  });
}

/**
 * Semeia o K9 atribuído ao PRIMARY_RA (autoriza `canAccessDogRecord` pela via
 * de vínculo).
 *
 * `dogAssignedToAuth` reconhece exatamente `conductorRa`, `conductor_ra`,
 * `handlerId` e `handler_id`. A fixture anterior gravava `handler_ra`, que NÃO
 * é nenhum deles: o vínculo nunca era reconhecido — passava apenas porque a
 * variante fail-open tratava claim ausente/global como autorização ampla.
 */
async function seedDog(dogId = DOG_A) {
  await seedFirestore(async (db) => {
    await seedAuthorizationState(db);
    await setDoc(doc(db, 'dogs', dogId), {
      name: 'Bono',
      conductorRa: PRIMARY_RA,
      conductor_ra: PRIMARY_RA,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      status: 'active',
    });
  });
}

async function seedSummary(dogId = DOG_A, payload = readySummaryPayload()) {
  await seedFirestore(async (db) => {
    await setDoc(
      doc(db, 'dogs', dogId, 'health_summary', 'current'),
      payload,
    );
  });
}

async function seedRestriction(
  dogId = DOG_A,
  restrictionId = 'r-1',
  payload = restrictionPayload(),
) {
  await seedFirestore(async (db) => {
    await setDoc(
      doc(db, 'dogs', dogId, 'operational_restrictions', restrictionId),
      payload,
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// HEALTH_SUMMARY — RS-01..RS-06
// ═════════════════════════════════════════════════════════════════════════════

test('RS-01 leitor Health autorizado LÊ health_summary/current', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();

  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current')),
  );
  assert.equal(snap.exists(), true, 'documento deve existir');
  assert.equal(snap.data().readiness_status, 'operational');
  assert.equal(snap.data().projection_status, 'ready');
});

test('RS-02 autenticado SEM acesso ao K9 é NEGADO', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();

  // own_records scope + nenhum vínculo com DOG_A (sem atribuição, sem turno).
  const db = dbFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current')),
  );
});

test('RS-03 não autenticado é NEGADO', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();

  const db = dbFor(ANONYMOUS);
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current')),
  );
});

test('RS-04 cliente autorizado NÃO cria health_summary/current', async () => {
  await clearAll();
  await seedDog();
  // Nenhum summary semeado — cliente tenta criar.

  const db = dbFor(PRIMARY_RA);
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'health_summary', 'current'),
      readySummaryPayload(),
    ),
  );
});

test('RS-05 cliente autorizado NÃO atualiza health_summary/current', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();

  const db = dbFor(PRIMARY_RA);
  // Tentativa de auto-promoção clínica: o caso que as Rules precisam barrar.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current'), {
      readiness_status: 'operational',
      readiness_label: 'Operacional',
    }),
  );
});

test('RS-06 cliente autorizado NÃO deleta health_summary/current', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();

  const db = dbFor(PRIMARY_RA);
  await assertFails(
    deleteDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current')),
  );
});

test('RS-07 cliente NÃO escreve documento arbitrário em health_summary', async () => {
  await clearAll();
  await seedDog();

  const db = dbFor(PRIMARY_RA);
  // Fora do contrato v1 (apenas "current"), mas ainda assim negado.
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'health_summary', 'forged'),
      readySummaryPayload(),
    ),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// OPERATIONAL_RESTRICTIONS — RR-01..RR-07
// ═════════════════════════════════════════════════════════════════════════════

test('RR-01 leitor Health autorizado LÊ operational_restrictions', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1')),
  );
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().level, 'absolute');
  assert.equal(snap.data().status, 'active');
});

test('RR-02 query status == active funciona para leitor autorizado', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction(DOG_A, 'r-active', restrictionPayload({status: 'active'}));
  await seedRestriction(DOG_A, 'r-ended', restrictionPayload({status: 'ended'}));

  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDocs(
      query(
        collection(db, 'dogs', DOG_A, 'operational_restrictions'),
        where('status', '==', 'active'),
      ),
    ),
  );
  assert.equal(snap.size, 1, 'somente a restrição ativa retorna');
  assert.equal(snap.docs[0].id, 'r-active');
});

test('RR-03 autenticado SEM acesso ao K9 é NEGADO', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1')),
  );
});

test('RR-04 não autenticado é NEGADO', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(ANONYMOUS);
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1')),
  );
});

test('RR-05 cliente autorizado NÃO cria restrição', async () => {
  await clearAll();
  await seedDog();

  const db = dbFor(PRIMARY_RA);
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'operational_restrictions', 'forged'),
      restrictionPayload(),
    ),
  );
});

test('RR-06 cliente autorizado NÃO altera restrição existente', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(PRIMARY_RA);
  // Auto-liberação: rebaixar nível de restrição pelo cliente.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1'), {
      level: 'attention',
    }),
  );
});

test('RR-07 cliente autorizado NÃO encerra restrição (release/cancel)', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(PRIMARY_RA);
  // Encerrar por status.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1'), {
      status: 'ended',
    }),
  );
  // Cancelar por status.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1'), {
      status: 'cancelled',
    }),
  );
});

test('RR-08 cliente autorizado NÃO deleta restrição', async () => {
  await clearAll();
  await seedDog();
  await seedRestriction();

  const db = dbFor(PRIMARY_RA);
  await assertFails(
    deleteDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1')),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// REGRESSÃO — caminhos Health existentes preservados
// ═════════════════════════════════════════════════════════════════════════════

test('REG-01 weight_records: leitura autorizada permanece permitida', async () => {
  await clearAll();
  await seedDog();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'weight_records', 'w-1'), {
      dogId: DOG_A,
      weight_kg: 28.8,
      measured_at: now(),
      schema_version: 1,
    });
  });

  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'weight_records', 'w-1')),
  );
});

test('REG-02 nutrition_plans: leitura permitida, escrita cliente segue negada', async () => {
  await clearAll();
  await seedDog();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'p-1'), {
      status: 'active',
      schema_version: 1,
    });
  });

  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'p-1')),
  );
  await assertFails(
    setDoc(doc(db, 'dogs', DOG_A, 'nutrition_plans', 'p-2'), {
      status: 'active',
    }),
  );
});

test('REG-03 health_events: leitura e criação auditada permanecem inalteradas', async () => {
  await clearAll();
  await seedDog();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'health_events', 'e-1'), {
      dogId: DOG_A,
      date: now(),
      type: 'consultation',
      created_by: PRIMARY_RA,
      created_at: now(),
    });
  });

  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_events', 'e-1')),
  );
});

test('REG-04 health_timeline: contrato de projeção preservado', async () => {
  await clearAll();
  await seedDog();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'health_timeline', 'tl-1'), {
      dog_id: DOG_A,
      timeline_type: 'meal',
      recorded_at: now(),
    });
  });

  const db = dbFor(PRIMARY_RA);
  await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_timeline', 'tl-1')),
  );
  await assertFails(
    setDoc(doc(db, 'dogs', DOG_A, 'health_timeline', 'tl-2'), {
      dog_id: DOG_A,
    }),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// AUTORIDADE — summary nunca autoriza
// ═════════════════════════════════════════════════════════════════════════════

test('AUTH-01 summary "operational" não concede escrita em restrição', async () => {
  await clearAll();
  await seedDog();
  // Summary diz operacional…
  await seedSummary(DOG_A, readySummaryPayload({readinessStatus: 'operational'}));
  await seedRestriction();

  const db = dbFor(PRIMARY_RA);
  // …e mesmo assim nenhuma escrita de restrição é liberada por causa disso.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1'), {
      status: 'ended',
    }),
  );
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-new'),
      restrictionPayload(),
    ),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// SEC-02A.2 — ESTADO DE AUTORIZAÇÃO É PRÉ-CONDIÇÃO DA LEITURA
//
// A cobertura anterior provava apenas "sem vínculo com o K9" e "anônimo". Nenhum
// caso exercitava um estado de autorização IRRESOLVÍVEL, que é exatamente o
// vetor do defeito SEC-02A: claim dizendo `global` com espelho/perfil ausente
// liberava QUALQUER K9. Todos os casos abaixo carregam a claim
// `access_scope: 'global'` DE PROPÓSITO — sob SEC-02A.2 ela não é autoridade.
//
// Nenhum destes casos aceita erro de avaliação como prova: `assertFails`
// observa recusa, e os pares positivos (SEC-06/SEC-07) provam que a negação não
// vem de fixture quebrada.
// ═════════════════════════════════════════════════════════════════════════════

/** Contexto SEM a claim `access_scope` — prova que ausência não vira global. */
function dbWithoutScopeClaim(ra) {
  return testEnv
    .authenticatedContext(`uid-${ra}`, {email: `${ra}@gcm.com.br`, ra})
    .firestore();
}

const summaryRef = (db) => doc(db, 'dogs', DOG_A, 'health_summary', 'current');

test('SEC-01 espelho de usuário ausente NEGA leitura do summary', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // NO_MIRROR_RA não tem documento em users/{ra}: estado não resolvível.
  await assertFails(getDoc(summaryRef(dbFor(NO_MIRROR_RA))));
});

test('SEC-02 perfil de acesso ausente NEGA leitura do summary', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // Espelho existe e aponta para access_profiles/perfil_que_nao_existe.
  await assertFails(getDoc(summaryRef(dbFor(NO_PROFILE_RA))));
});

test('SEC-03 perfil inativo NEGA leitura do summary', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // Perfil existe com scope global, porém status: 'inactive'.
  await assertFails(getDoc(summaryRef(dbFor(INACTIVE_RA))));
});

test('SEC-04 claim global NÃO amplia quando o perfil não resolve', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  await seedRestriction();
  // Vetor exato do defeito SEC-02A, agora sobre as duas projeções de leitura.
  for (const ra of [NO_MIRROR_RA, NO_PROFILE_RA, INACTIVE_RA]) {
    const db = dbFor(ra, {access_scope: 'global'});
    await assertFails(getDoc(summaryRef(db)));
    await assertFails(
      getDoc(doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-1')),
    );
  }
});

test('SEC-05 own_records VÁLIDO sem vínculo ao K9 NEGA leitura', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // OUTSIDER_RA tem estado de autorização VÁLIDO (users + perfil ativo), mas
  // escopo own_records e nenhum vínculo com DOG_A. Estado válido não basta.
  await assertFails(getDoc(summaryRef(dbFor(OUTSIDER_RA))));
});

test('SEC-06 autoridade global resolvida pelo PERFIL permite leitura', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  const snap = await assertSucceeds(getDoc(summaryRef(dbFor(GLOBAL_RA))));
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().projection_status, 'ready');
});

test('SEC-07 claim ausente não impede autoridade derivada do perfil', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // Perfil é a autoridade: sem claim `access_scope`, o escopo global do perfil
  // continua valendo. Ausência de claim não amplia nem restringe por si.
  const snap = await assertSucceeds(
    getDoc(summaryRef(dbWithoutScopeClaim(GLOBAL_RA))),
  );
  assert.equal(snap.exists(), true);
});

test('SEC-08 estado irresolvível também NEGA escrita (não só leitura)', async () => {
  await clearAll();
  await seedDog();
  await seedSummary();
  // Writes de cliente já são negados para todos; aqui provamos que um estado
  // de autorização quebrado não abre exceção em nenhuma direção.
  for (const ra of [NO_MIRROR_RA, NO_PROFILE_RA, INACTIVE_RA]) {
    const db = dbFor(ra, {access_scope: 'global'});
    await assertFails(
      setDoc(summaryRef(db), readySummaryPayload()),
    );
    await assertFails(
      setDoc(
        doc(db, 'dogs', DOG_A, 'operational_restrictions', 'r-forjada'),
        restrictionPayload(),
      ),
    );
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Runner
// ═════════════════════════════════════════════════════════════════════════════

async function run() {
  let passed = 0;
  let failed = 0;
  const failures = [];

  for (const {name, fn} of tests) {
    try {
      await fn();
      console.log(`ok - ${name}`);
      passed++;
    } catch (error) {
      console.error(`FAIL - ${name}`);
      console.error(`  ${error.message}`);
      failures.push({name, error});
      failed++;
    }
  }

  console.log(`\nPassed: ${passed}`);
  console.log(`Failed: ${failed}`);

  if (failed > 0) {
    console.log('\nFailures:');
    failures.forEach(({name, error}) => {
      console.log(`  ${name}: ${error.message}`);
    });
    await testEnv.cleanup();
    process.exit(1);
  }

  console.log('\nhealth_readiness_rules_tests: all passed');
  await testEnv.cleanup();
}

// Guard de entrypoint robusto em Windows e POSIX.
//
// `file://${process.argv[1]}` NÃO casa no Windows: argv[1] é um caminho
// `C:\...` com barras invertidas, enquanto import.meta.url é
// `file:///C:/...`. Com a comparação naive o runner nunca executa e o
// processo termina com exit 0 — um falso verde. `pathToFileURL` normaliza
// as duas formas.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().catch((error) => {
    console.error('Test runner failed:', error);
    process.exit(1);
  });
}

export {tests, run, testEnv};
