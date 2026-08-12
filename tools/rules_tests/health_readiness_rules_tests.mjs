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

// RA autorizado (escopo global — modelo padrão do ecossistema).
const PRIMARY_RA = '691755';
// RA com own_records scope e SEM vínculo com o K9 → não autorizado.
const OUTSIDER_RA = '999999';
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

/** Semeia o K9 atribuído ao PRIMARY_RA (autoriza canAccessDogRecord). */
async function seedDog(dogId = DOG_A) {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', dogId), {
      name: 'Bono',
      handler_ra: PRIMARY_RA,
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
