/**
 * CLIN-AUTH-BE-3B.A — Clinical Read Contract & Rules Foundation
 *
 * Testes de Firestore Rules para o prontuário clínico v1:
 *   dogs/{dogId}/clinical_cases/{caseId}
 *   dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}
 *   dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}/amendments/{amendId}
 *
 * Contrato sob teste:
 * 1. Leitura exige DUAS pernas: capability EXPLÍCITA `health.read`
 *    (activeProfileGrants, sem bypass admin) E acesso ao K9
 *    (canAccessDogRecord com o dogId ESTRUTURAL do path).
 * 2. Administração técnica NÃO é autoridade clínica: admin sem health.read
 *    explícito é NEGADO.
 * 3. `health.view` NÃO concede leitura clínica (adapter legado recusado como
 *    AUTHORITY CONFLICT — perfil administrador carrega view=true).
 * 4. Todo write de cliente é negado nos três caminhos, Amendment incluído:
 *    nenhum writer clínico existe neste gate.
 * 5. dog_id de payload nunca amplia acesso — dogId vem do path.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:clinical-read
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
  setDoc,
  updateDoc,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

// ─── Atores ──────────────────────────────────────────────────────────────────
// Condutor vinculado ao DOG_A, perfil own_records COM health.read.
const PRIMARY_RA = '691755';
// Estado de autorização VÁLIDO com health.read, porém SEM vínculo com DOG_A.
const OUTSIDER_RA = '999999';
// Perfil global COM health.read — autoridade ampla legítima.
const GLOBAL_RA = '700001';
// Autenticado SEM espelho em users/{ra}.
const NO_MIRROR_RA = '700002';
// Espelho aponta para perfil inexistente.
const NO_PROFILE_RA = '700003';
// Perfil existe, porém inativo.
const INACTIVE_RA = '700004';
// Perfil ATIVO e global, mas SEM a chave health.read (capability ausente).
const NO_CAPABILITY_RA = '700005';
// Perfil ATIVO e global com health.read EXPLICITAMENTE false.
const CAPABILITY_FALSE_RA = '700006';
// Administração técnica: claim admin + role administrador, perfil
// `administrador` com view/create/edit/archive/approve — e SEM health.read.
const TECH_ADMIN_RA = '700007';
// Perfil legado com health.view=true e SEM health.read: prova que o adapter
// legado recusado não vaza leitura clínica.
const LEGACY_VIEW_RA = '700008';
// Condutor do DOG_B, usado para provar isolamento cross-dog.
const DOG_B_RA = '700009';
const ANONYMOUS = null;

const DOG_A = 'dog-clinical-a';
const DOG_B = 'dog-clinical-b';

const CASE_A = 'case-a-1';
const EVENT_A = 'event-a-1';
const AMEND_A = 'amend-a-1';

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

/** Contexto de administração técnica real: claim admin + role administrador. */
function dbForTechAdmin() {
  return dbFor(TECH_ADMIN_RA, {
    admin: true,
    role: 'administrador',
    roles: ['administrador'],
  });
}

function now() {
  return Timestamp.fromDate(new Date('2026-08-21T12:00:00.000Z'));
}

// ─── Payloads sintéticos mínimos ─────────────────────────────────────────────
// Deliberadamente mínimos: as Rules NÃO devem depender do payload clínico para
// decidir dono do registro — dogId já vem do path. Nenhum dado clínico real,
// nenhuma PII.

function casePayload({dogId = DOG_A, clinicalStatus = 'open'} = {}) {
  return {
    dog_id: dogId,
    clinical_status: clinicalStatus,
    opened_at: now(),
    schema_version: 1,
  };
}

function eventPayload({dogId = DOG_A} = {}) {
  return {
    dog_id: dogId,
    case_id: CASE_A,
    event_type: 'consultation',
    recorded_at: now(),
    schema_version: 1,
  };
}

function amendmentPayload({dogId = DOG_A} = {}) {
  return {
    dog_id: dogId,
    event_id: EVENT_A,
    amendment_type: 'correction',
    reason: 'Correcao de digitacao no campo de observacao.',
    recorded_at: now(),
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
 * SEC-02A.2 + capability clínica.
 *
 * Fixtures sintéticas de EMULADOR. Produção NÃO possui `health.read` hoje e
 * isto é o estado esperado: fixture não é grant aprovado.
 *
 * `health.view` é semeado junto de `health.read` nos perfis clínicos porque é
 * o que os perfis reais já carregam — provar leitura clínica exige que ela
 * venha de `read`, e os casos NO_CAPABILITY/LEGACY_VIEW isolam essa diferença.
 */
async function seedAuthorizationState(db) {
  // Perfis COM autoridade clínica explícita.
  await setDoc(doc(db, 'access_profiles', 'operador_k9_clinico'), {
    status: 'active',
    scope: 'own_records',
    permissions: {health: {view: true, read: true, create: true, edit: true}},
  });
  await setDoc(doc(db, 'access_profiles', 'gestor_global_clinico'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, read: true, create: true, edit: true}},
  });
  // Perfil ATIVO e global, SEM a chave health.read.
  await setDoc(doc(db, 'access_profiles', 'gestor_sem_clinico'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  // Perfil ATIVO e global com health.read explicitamente false.
  await setDoc(doc(db, 'access_profiles', 'gestor_clinico_false'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, read: false, create: true}},
  });
  // Administração técnica: o perfil real mais amplo do sistema, ainda SEM
  // health.read. É o caso central do princípio "admin != autoridade clinica".
  await setDoc(doc(db, 'access_profiles', 'administrador'), {
    status: 'active',
    scope: 'global',
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
      access: {view: true, create: true, edit: true, approve: true},
    },
  });
  // Perfil legado somente-view: prova que o adapter recusado não vaza.
  await setDoc(doc(db, 'access_profiles', 'perfil_legado_view'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true}},
  });
  await setDoc(doc(db, 'access_profiles', 'perfil_inativo_clinico'), {
    status: 'inactive',
    scope: 'global',
    permissions: {health: {view: true, read: true}},
  });

  // ─── Espelhos de usuário ───────────────────────────────────────────────
  await setDoc(doc(db, 'users', PRIMARY_RA), {
    ra: PRIMARY_RA,
    access_profile_id: 'operador_k9_clinico',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', OUTSIDER_RA), {
    ra: OUTSIDER_RA,
    access_profile_id: 'operador_k9_clinico',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', DOG_B_RA), {
    ra: DOG_B_RA,
    access_profile_id: 'operador_k9_clinico',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', GLOBAL_RA), {
    ra: GLOBAL_RA,
    access_profile_id: 'gestor_global_clinico',
    access_scope: 'global',
  });
  // NO_MIRROR_RA: deliberadamente SEM documento em users/{ra}.
  await setDoc(doc(db, 'users', NO_PROFILE_RA), {
    ra: NO_PROFILE_RA,
    access_profile_id: 'perfil_que_nao_existe',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', INACTIVE_RA), {
    ra: INACTIVE_RA,
    access_profile_id: 'perfil_inativo_clinico',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', NO_CAPABILITY_RA), {
    ra: NO_CAPABILITY_RA,
    access_profile_id: 'gestor_sem_clinico',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', CAPABILITY_FALSE_RA), {
    ra: CAPABILITY_FALSE_RA,
    access_profile_id: 'gestor_clinico_false',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', TECH_ADMIN_RA), {
    ra: TECH_ADMIN_RA,
    access_profile_id: 'administrador',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', LEGACY_VIEW_RA), {
    ra: LEGACY_VIEW_RA,
    access_profile_id: 'perfil_legado_view',
    access_scope: 'global',
  });
}

/**
 * Semeia dois K9s e o prontuário sintético de cada um.
 *
 * `dogAssignedToAuth` reconhece exatamente conductorRa / conductor_ra /
 * handlerId / handler_id — usar outro nome de campo faria o vínculo nunca ser
 * reconhecido e transformaria um ALLOW esperado em falso DENY.
 */
async function seedClinicalWorld() {
  await seedFirestore(async (db) => {
    await seedAuthorizationState(db);

    await setDoc(doc(db, 'dogs', DOG_A), {
      name: 'Bono',
      conductorRa: PRIMARY_RA,
      conductor_ra: PRIMARY_RA,
      handlerId: PRIMARY_RA,
      handler_id: PRIMARY_RA,
      status: 'active',
    });
    await setDoc(doc(db, 'dogs', DOG_B), {
      name: 'Aki',
      conductorRa: DOG_B_RA,
      conductor_ra: DOG_B_RA,
      handlerId: DOG_B_RA,
      handler_id: DOG_B_RA,
      status: 'active',
    });

    for (const dogId of [DOG_A, DOG_B]) {
      await setDoc(
        doc(db, 'dogs', dogId, 'clinical_cases', CASE_A),
        casePayload({dogId}),
      );
      await setDoc(
        doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'events', EVENT_A),
        eventPayload({dogId}),
      );
      await setDoc(
        doc(
          db, 'dogs', dogId, 'clinical_cases', CASE_A,
          'events', EVENT_A, 'amendments', AMEND_A,
        ),
        amendmentPayload({dogId}),
      );
    }
  });
}

// ─── Refs ────────────────────────────────────────────────────────────────────
const caseRef = (db, dogId = DOG_A, caseId = CASE_A) =>
  doc(db, 'dogs', dogId, 'clinical_cases', caseId);

const eventRef = (db, dogId = DOG_A) =>
  doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'events', EVENT_A);

const amendRef = (db, dogId = DOG_A) =>
  doc(
    db, 'dogs', dogId, 'clinical_cases', CASE_A,
    'events', EVENT_A, 'amendments', AMEND_A,
  );

const casesCol = (db, dogId = DOG_A) =>
  collection(db, 'dogs', dogId, 'clinical_cases');

// ═════════════════════════════════════════════════════════════════════════════
// POSITIVOS — CR-01..CR-07
// ═════════════════════════════════════════════════════════════════════════════

test('CR-01 perfil global ATIVO com health.read LÊ ClinicalCase', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snap = await assertSucceeds(getDoc(caseRef(dbFor(GLOBAL_RA))));
  assert.equal(snap.exists(), true, 'documento deve existir');
  assert.equal(snap.data().clinical_status, 'open');
});

test('CR-02 own_records com health.read e vínculo ao K9 LÊ ClinicalCase', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snap = await assertSucceeds(
    getDoc(caseRef(dbFor(PRIMARY_RA, {access_scope: 'own_records'}))),
  );
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().dog_id, DOG_A);
});

test('CR-03 ClinicalEvent é LIDO nas mesmas condições', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const ra of [GLOBAL_RA, PRIMARY_RA]) {
    const snap = await assertSucceeds(getDoc(eventRef(dbFor(ra))));
    assert.equal(snap.exists(), true, `evento deve ser legível por ${ra}`);
    assert.equal(snap.data().event_type, 'consultation');
  }
});

test('CR-04 Amendment é LIDO nas mesmas condições', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const ra of [GLOBAL_RA, PRIMARY_RA]) {
    const snap = await assertSucceeds(getDoc(amendRef(dbFor(ra))));
    assert.equal(snap.exists(), true, `adendo deve ser legível por ${ra}`);
    assert.equal(snap.data().amendment_type, 'correction');
  }
});

test('CR-05 LIST de clinical_cases do K9 autorizado é PERMITIDO', async () => {
  await clearAll();
  await seedClinicalWorld();

  // O path já determina o dogId: LIST não precisa de filtro para ser provável.
  for (const ra of [GLOBAL_RA, PRIMARY_RA]) {
    const snap = await assertSucceeds(getDocs(casesCol(dbFor(ra))));
    assert.equal(snap.size, 1, `um caso visível para ${ra}`);
    assert.equal(snap.docs[0].id, CASE_A);
  }
});

test('CR-06 condutor do DOG_B lê o prontuário do DOG_B (isolamento simétrico)', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(DOG_B_RA, {access_scope: 'own_records'});
  const snap = await assertSucceeds(getDoc(caseRef(db, DOG_B)));
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().dog_id, DOG_B);
});

test('CR-07 claim access_scope ausente não impede autoridade do perfil', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Perfil é a autoridade sob SEC-02A.2: ausência de claim não restringe.
  //
  // PRECISÃO TERMINOLÓGICA: a claim AUSENTE neste caso é `access_scope`.
  // A claim `ra` permanece deliberadamente PRESENTE e válida — identidade
  // (`ra`) e escopo legado (`access_scope`) são variáveis distintas.
  // Ausência de `ra` é coberta por CI-01..CI-03; este caso prova apenas que
  // autoridade derivada do PERFIL não exige a claim legada `access_scope`.
  const db = testEnv
    .authenticatedContext(`uid-${GLOBAL_RA}`, {
      email: `${GLOBAL_RA}@gcm.com.br`,
      ra: GLOBAL_RA,
    })
    .firestore();
  await assertSucceeds(getDoc(caseRef(db)));
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — ESTADO DE AUTORIZAÇÃO — CN-01..CN-05
// ═════════════════════════════════════════════════════════════════════════════

test('CN-01 não autenticado é NEGADO nos três caminhos', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(ANONYMOUS);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CN-02 espelho de usuário ausente é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(NO_MIRROR_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CN-03 perfil de acesso ausente é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(NO_PROFILE_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CN-04 perfil INATIVO com health.read=true é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  // A capability existe no documento, mas o perfil está inativo:
  // activeProfileGrants exige status == 'active'.
  const db = dbFor(INACTIVE_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CN-05 claim global NÃO amplia quando o perfil não resolve', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Vetor exato do defeito SEC-02A, agora sobre o prontuário clínico.
  for (const ra of [NO_MIRROR_RA, NO_PROFILE_RA, INACTIVE_RA]) {
    const db = dbFor(ra, {access_scope: 'global'});
    await assertFails(getDoc(caseRef(db)));
    await assertFails(getDoc(eventRef(db)));
    await assertFails(getDoc(amendRef(db)));
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — IDENTIDADE (claim `ra`) — CI-01..CI-03
//
// hasClinicalReadAuthority() abre com signedIn() && hasRaClaim(). A claim `ra`
// é a IDENTIDADE que sustenta toda a cadeia: currentAccessProfileId() resolve
// users/{request.auth.token.ra} para descobrir o perfil, e canAccessDogRecord()
// depende do mesmo RA para o vínculo com o K9. Sem `ra` válida não existe
// sujeito a autorizar — e a cadeia precisa falhar FECHADA nesse ponto.
//
// Estes casos isolam hasRaClaim() como ÚNICA variável causal: o ator é
// uid-GLOBAL_RA, cujo perfil `gestor_global_clinico` está ATIVO, é global e
// concede health.read — com `ra` válida a leitura é PERMITIDA (CR-01). CI-01 e
// CI-02 reafirmam isso com um CONTROLE POSITIVO explícito, de modo que o DENY
// não possa ser atribuído a capability ausente nem a falta de vínculo.
// ═════════════════════════════════════════════════════════════════════════════

test('CI-01 autenticado SEM claim ra é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Mesmo uid e mesmo perfil clínico pleno de CR-01, porém a claim `ra` foi
  // OMITIDA. hasRaClaim() lê token.get('ra', '') e falha fechado ANTES de
  // qualquer get() de users/ ou access_profiles/.
  const db = testEnv
    .authenticatedContext(`uid-${GLOBAL_RA}`, {
      email: `${GLOBAL_RA}@gcm.com.br`,
      access_scope: 'global',
    })
    .firestore();
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));

  // CONTROLE POSITIVO: o MESMO ator, agora COM `ra`, é PERMITIDO. Prova que o
  // DENY acima decorre da identidade ausente, não do estado das fixtures.
  await assertSucceeds(getDoc(caseRef(dbFor(GLOBAL_RA))));
});

test('CI-02 claim ra vazia é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  // `ra: ''` é string PRESENTE mas de size() == 0. hasRaClaim() exige
  // size() > 0: string vazia NÃO é identidade.
  const db = dbFor(GLOBAL_RA, {ra: ''});
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));

  await assertSucceeds(getDoc(caseRef(dbFor(GLOBAL_RA))));
});

test('CI-03 admin técnico SEM claim ra é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Composição das duas ausências de autoridade: administração técnica não
  // concede autoridade clínica (CA-01) e identidade ausente derruba a cadeia
  // (CI-01). Nem a claim admin nem o role administrador substituem `ra`.
  const db = testEnv
    .authenticatedContext(`uid-${TECH_ADMIN_RA}`, {
      email: `${TECH_ADMIN_RA}@gcm.com.br`,
      access_scope: 'global',
      admin: true,
      role: 'administrador',
      roles: ['administrador'],
    })
    .firestore();
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — CAPABILITY CLÍNICA — CC-01..CC-04
// ═════════════════════════════════════════════════════════════════════════════

test('CC-01 health.read AUSENTE é NEGADO mesmo com perfil global ativo', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Perfil ativo, escopo global, health.view/create/edit — sem `read`.
  const db = dbFor(NO_CAPABILITY_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CC-02 health.read == false é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(CAPABILITY_FALSE_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CC-03 health.view=true SEM health.read NÃO concede leitura clínica', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Adapter legado `read || view` foi RECUSADO (AUTHORITY CONFLICT): este caso
  // é a prova executável de que health.view não vaza prontuário.
  const db = dbFor(LEGACY_VIEW_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CC-04 health.create/edit NÃO substituem autoridade de leitura clínica', async () => {
  await clearAll();
  await seedClinicalWorld();

  // NO_CAPABILITY_RA tem create=true e edit=true. Escrever não é ler.
  const db = dbFor(NO_CAPABILITY_RA);
  await assertFails(getDoc(caseRef(db)));
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — ADMINISTRAÇÃO TÉCNICA != AUTORIDADE CLÍNICA — CA-01..CA-02
// ═════════════════════════════════════════════════════════════════════════════

test('CA-01 administração técnica SEM health.read explícito é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Claim admin + role administrador + perfil `administrador` (o mais amplo
  // do sistema: view/create/edit/archive/approve) e ainda assim SEM health.read.
  //
  // Este é o caso que impede que `hasAccessPermission` — que abre com
  // `isAdmin() ||` — seja usado como gate clínico.
  const db = dbForTechAdmin();
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CA-02 admin técnico também NÃO alcança o prontuário do outro K9', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbForTechAdmin();
  await assertFails(getDoc(caseRef(db, DOG_B)));
  await assertFails(getDoc(eventRef(db, DOG_B)));
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — ISOLAMENTO CROSS-DOG — CX-01..CX-03
// ═════════════════════════════════════════════════════════════════════════════

test('CX-01 own_records com health.read NÃO lê ClinicalCase de K9 alheio', async () => {
  await clearAll();
  await seedClinicalWorld();

  // PRIMARY_RA tem capability clínica plena, mas nenhum vínculo com DOG_B.
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(getDoc(caseRef(db, DOG_B)));
});

test('CX-02 Event e Amendment de K9 alheio são NEGADOS', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(getDoc(eventRef(db, DOG_B)));
  await assertFails(getDoc(amendRef(db, DOG_B)));
  await assertFails(getDocs(casesCol(db, DOG_B)));
});

test('CX-03 estado válido com health.read e SEM vínculo é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  // OUTSIDER_RA: perfil ativo own_records COM health.read, zero vínculo.
  // Capability sozinha não autoriza: as duas pernas são obrigatórias.
  const db = dbFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

// ═════════════════════════════════════════════════════════════════════════════
// PAYLOAD FORJADO NÃO AMPLIA ACESSO — CP-01..CP-02
// ═════════════════════════════════════════════════════════════════════════════

test('CP-01 dog_id de payload apontando para o K9 do leitor NÃO abre K9 alheio', async () => {
  await clearAll();
  await seedClinicalWorld();
  // Documento FISICAMENTE sob DOG_B, mas declarando dog_id = DOG_A.
  await seedFirestore(async (db) => {
    await setDoc(
      doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado'),
      casePayload({dogId: DOG_A}),
    );
    await setDoc(
      doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado', 'events', EVENT_A),
      eventPayload({dogId: DOG_A}),
    );
  });

  // Autoridade é o dogId do PATH (DOG_B), não o campo. Condutor de DOG_A é
  // negado apesar do payload declarar o K9 dele.
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(getDoc(caseRef(db, DOG_B, 'case-forjado')));
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado', 'events', EVENT_A)),
  );
});

test('CP-02 dog_id divergente NÃO nega o dono estrutural do path', async () => {
  await clearAll();
  await seedClinicalWorld();
  await seedFirestore(async (db) => {
    await setDoc(
      doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado'),
      casePayload({dogId: DOG_A}),
    );
  });

  // Contraprova de que CP-01 mede o path e não uma fixture quebrada: o dono de
  // DOG_B continua lendo o documento que vive sob DOG_B.
  const db = dbFor(DOG_B_RA, {access_scope: 'own_records'});
  const snap = await assertSucceeds(getDoc(caseRef(db, DOG_B, 'case-forjado')));
  assert.equal(snap.exists(), true);
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGAÇÃO DE ESCRITA — CW-01..CW-05
// Nenhum writer clínico existe neste gate: create/update/delete negados para
// TODOS os atores, inclusive quem tem autoridade de leitura plena.
// ═════════════════════════════════════════════════════════════════════════════

test('CW-01 ClinicalCase: create/update/delete NEGADOS para leitor autorizado', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(GLOBAL_RA);
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-novo'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'discharged'}));
  await assertFails(deleteDoc(caseRef(db)));
});

test('CW-02 ClinicalEvent: create/update/delete NEGADOS para leitor autorizado', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(GLOBAL_RA);
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'clinical_cases', CASE_A, 'events', 'event-novo'),
      eventPayload(),
    ),
  );
  await assertFails(updateDoc(eventRef(db), {event_type: 'exam'}));
  await assertFails(deleteDoc(eventRef(db)));
});

test('CW-03 Amendment: create NEGADO — append-only não tem writer neste gate', async () => {
  await clearAll();
  await seedClinicalWorld();

  // O contrato futuro prevê Amendment append-only, mas health.amend_record e
  // o callable correspondente estão AUSENTES: create de cliente é DENY.
  const db = dbFor(GLOBAL_RA);
  await assertFails(
    setDoc(
      doc(
        db, 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'events', EVENT_A, 'amendments', 'amend-novo',
      ),
      amendmentPayload(),
    ),
  );
  await assertFails(updateDoc(amendRef(db), {reason: 'outra razao'}));
  await assertFails(deleteDoc(amendRef(db)));
});

test('CW-04 condutor vinculado com health.read também NÃO escreve', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-novo'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'monitoring'}));
  await assertFails(deleteDoc(caseRef(db)));
});

test('CW-05 admin técnico NÃO escreve prontuário', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbForTechAdmin();
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-admin'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'discharged'}));
  await assertFails(deleteDoc(caseRef(db)));
  await assertFails(
    setDoc(
      doc(
        db, 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'events', EVENT_A, 'amendments', 'amend-admin',
      ),
      amendmentPayload(),
    ),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// SEM COLLECTION-GROUP NESTA FUNDAÇÃO — CG-01
// ═════════════════════════════════════════════════════════════════════════════

test('CG-01 collection-group de clinical_cases NÃO é autorizado neste gate', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Nenhuma regra recursiva `/{path=**}/clinical_cases/{caseId}` foi criada.
  // A leitura cross-dog global é decisão de gate próprio (precedente
  // HW-4A.2C.5R: essa fronteira exige análise de overlap/list/get/índice).
  const {collectionGroup, getDocs: getGroupDocs} = await import('firebase/firestore');
  const db = dbFor(GLOBAL_RA);
  await assertFails(getGroupDocs(collectionGroup(db, 'clinical_cases')));
});

// ═════════════════════════════════════════════════════════════════════════════
// REGRESSÃO — caminhos Health vizinhos preservados
// ═════════════════════════════════════════════════════════════════════════════

test('REG-01 health_documents continua legível SEM exigir health.read', async () => {
  await clearAll();
  await seedClinicalWorld();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'health_documents', 'doc-1'), {
      storage_path: 'dogs/dog-clinical-a/health/doc-1.pdf',
      schema_version: 1,
    });
  });

  // Compatibilidade deliberada: os caminhos Health já reconciliados NÃO foram
  // migrados para capability clínica neste gate. NO_CAPABILITY_RA (sem
  // health.read, escopo global) continua lendo.
  await assertSucceeds(
    getDoc(doc(dbFor(NO_CAPABILITY_RA), 'dogs', DOG_A, 'health_documents', 'doc-1')),
  );
});

test('REG-02 health_summary e health_schedule preservam o predicado anterior', async () => {
  await clearAll();
  await seedClinicalWorld();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current'), {
      projection_status: 'ready',
      readiness_status: 'operational',
      schema_version: 1,
    });
    await setDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 's-1'), {
      dog_id: DOG_A,
      completed: false,
      schema_version: 1,
    });
  });

  const db = dbFor(NO_CAPABILITY_RA);
  await assertSucceeds(getDoc(doc(db, 'dogs', DOG_A, 'health_summary', 'current')));
  await assertSucceeds(getDoc(doc(db, 'dogs', DOG_A, 'health_schedule', 's-1')));
});

test('REG-03 wildcard terminal segue negando coleção clínica desconhecida', async () => {
  await clearAll();
  await seedClinicalWorld();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'clinical_notes', 'n-1'), {
      dog_id: DOG_A,
    });
  });

  // Prova que a fundação criou autoridade APENAS para os três caminhos
  // canônicos — nenhum match permissivo novo alcança vizinhança clínica.
  await assertFails(
    getDoc(doc(dbFor(GLOBAL_RA), 'dogs', DOG_A, 'clinical_notes', 'n-1')),
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

  console.log('\nclinical_read_rules_tests: all passed');
  await testEnv.cleanup();
}

// Guard de entrypoint robusto em Windows e POSIX: `file://${process.argv[1]}`
// NÃO casa no Windows e produziria exit 0 sem executar nada — falso verde.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().catch((error) => {
    console.error('Test runner failed:', error);
    process.exit(1);
  });
}

export {tests, run, testEnv};
