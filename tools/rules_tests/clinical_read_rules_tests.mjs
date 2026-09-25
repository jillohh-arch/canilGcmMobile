/**
 * CLIN-AUTH-BE-3B.A / CT3.AUTH-HEALTH-01 — Clinical Read Contract & Rules Foundation
 * GATE: CT3.F20.CLINICAL-READ-AUTHORITY-RULES-REPAIR-R1
 *
 * Testes de Firestore Rules para o prontuário clínico v1:
 *   dogs/{dogId}/clinical_cases/{caseId}
 *   dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}
 *   dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}/clinical_amendments/{amendId}
 *   dogs/{dogId}/clinical_cases/{caseId}/exams/{examId}
 *   dogs/{dogId}/treatment_protocols/{protocolId}
 *   dogs/{dogId}/treatment_protocols/{protocolId}/doses/{doseId}
 *
 * Contrato canônico sob teste (CT3.AUTH-HEALTH-01):
 * 1. A autoridade canônica de leitura clínica é `health.view` (NÃO `health.read`).
 *    F10 removeu `health.read` da taxonomia AccessAction, perfis padrão e normalização.
 * 2. Leitura clínica exige DUAS pernas: capability canônica `health.view`
 *    (activeProfileGrants no perfil ativo) E acesso ao K9
 *    (canAccessDogRecord com o dogId ESTRUTURAL do path).
 * 3. health.view = true, health.read ausente -> clinical READ ALLOWED.
 * 4. health.view = false/ausente -> clinical READ DENIED.
 * 5. health.view isolada NÃO concede mutação clínica (create/update/delete negados
 *    a clientes no Firestore; record_clinical, finalize_clinical, amend_clinical
 *    não são concedidos).
 * 6. Administração técnica NÃO tem bypass arbitrário em hasClinicalReadAuthority:
 *    admin lê se e somente se seu perfil ativo contiver health.view=true.
 * 7. Todo write de cliente é negado no prontuário, exames e tratamentos:
 *    mutações canônicas são orquestradas server-side via callables Admin SDK.
 * 8. receipts internos de operação (operations) são estritamente negados a qualquer cliente.
 * 9. dog_id de payload nunca amplia acesso — dogId vem do path.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:clinical-read
 */
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
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

const require = createRequire(import.meta.url);
const {profileGrantsPermission} = require('../../functions/lib/index.js');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';

// ─── Atores ──────────────────────────────────────────────────────────────────
// Condutor vinculado ao DOG_A, perfil operador_k9 (own_records) COM health.view (health.read ausente).
const PRIMARY_RA = '691755';
// Estado de autorização VÁLIDO com health.view, porém SEM vínculo com DOG_A.
const OUTSIDER_RA = '999999';
// Perfil gestor global COM health.view — autoridade ampla legítima (health.read ausente).
const GLOBAL_RA = '700001';
// Autenticado SEM espelho em users/{ra}.
const NO_MIRROR_RA = '700002';
// Espelho aponta para perfil inexistente (no-profile).
const NO_PROFILE_RA = '700003';
// Perfil existe, porém inativo (inactive-profile), mesmo com health.view=true.
const INACTIVE_RA = '700004';
// Perfil ATIVO e global, mas SEM a chave health.view (capability ausente).
const NO_CAPABILITY_RA = '700005';
// Perfil ATIVO e global com health.view EXPLICITAMENTE false.
const CAPABILITY_FALSE_RA = '700006';
// Administração técnica: claim admin + role administrador, perfil `administrador` com health.view=true (health.read ausente).
const TECH_ADMIN_RA = '700007';
// Administração técnica com perfil SEM health.view: prova ausência de bypass admin.
const TECH_ADMIN_NO_VIEW_RA = '700008';
// Condutor do DOG_B, usado para provar isolamento cross-dog.
const DOG_B_RA = '700009';
// Perfil legado/inválido com health.read=true mas SEM health.view: prova que health.read não autoriza.
const OBSOLETE_READ_RA = '700010';
const ANONYMOUS = null;

const DOG_A = 'dog-clinical-a';
const DOG_B = 'dog-clinical-b';

const CASE_A = 'case-a-1';
const EVENT_A = 'event-a-1';
const AMEND_A = 'amend-a-1';
const EXAM_A = 'exam-a-1';
const PROTOCOL_A = 'protocol-a-1';
const DOSE_A = 'dose-a-1';

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

/** Contexto de administração técnica real: claim admin + role administrador + perfil administrador (health.view=true). */
function dbForTechAdmin() {
  return dbFor(TECH_ADMIN_RA, {
    admin: true,
    role: 'administrador',
    roles: ['administrador'],
  });
}

/** Contexto de administração técnica com perfil sem health.view (prova fail-closed e ausência de bypass admin). */
function dbForTechAdminNoHealthView() {
  return dbFor(TECH_ADMIN_NO_VIEW_RA, {
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

function examPayload({dogId = DOG_A} = {}) {
  return {
    dog_id: dogId,
    case_id: CASE_A,
    exam_id: EXAM_A,
    exam_type: 'blood_work',
    title: 'Hemograma',
    current_stage: 'requested',
    schema_version: 1,
    created_at: now(),
  };
}

function protocolPayload({dogId = DOG_A} = {}) {
  return {
    dog_id: dogId,
    case_id: CASE_A,
    protocol_id: PROTOCOL_A,
    medication_name: 'Amoxicilina',
    status: 'active',
    schema_version: 1,
    created_at: now(),
  };
}

function dosePayload({dogId = DOG_A} = {}) {
  return {
    dog_id: dogId,
    protocol_id: PROTOCOL_A,
    dose_id: DOSE_A,
    status: 'administered',
    schema_version: 1,
    administered_at: now(),
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
 * Fixtures sintéticas de EMULADOR alinhadas a CT3.AUTH-HEALTH-01.
 *
 * `health.view` é a autoridade canônica de leitura clínica.
 * `health.read` foi removido da taxonomia e está ausente de todos os perfis canônicos.
 */
async function seedAuthorizationState(db) {
  // 1. operador_k9: perfil ativo, own_records, COM health.view (health.read AUSENTE)
  await setDoc(doc(db, 'access_profiles', 'operador_k9'), {
    status: 'active',
    scope: 'own_records',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  // 2. gestor: perfil ativo, global, COM health.view (health.read AUSENTE)
  await setDoc(doc(db, 'access_profiles', 'gestor'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: true, create: true, edit: true}},
  });
  // 3. administrador: perfil técnico ativo, global, COM health.view (health.read AUSENTE)
  await setDoc(doc(db, 'access_profiles', 'administrador'), {
    status: 'active',
    scope: 'global',
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
      access: {view: true, create: true, edit: true, approve: true},
    },
  });
  // 4. Perfil ATIVO e global, SEM a chave health.view (capability ausente)
  await setDoc(doc(db, 'access_profiles', 'gestor_sem_health_view'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {create: true, edit: true}},
  });
  // 5. Perfil ATIVO e global com health.view explicitamente false
  await setDoc(doc(db, 'access_profiles', 'gestor_health_view_false'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {view: false, create: true}},
  });
  // 6. Perfil INATIVO com health.view=true: prova fail-closed
  await setDoc(doc(db, 'access_profiles', 'perfil_inativo_health_view'), {
    status: 'inactive',
    scope: 'global',
    permissions: {health: {view: true}},
  });
  // 7. Perfil de admin técnico SEM health.view: prova ausência de bypass admin
  await setDoc(doc(db, 'access_profiles', 'admin_sem_health_view'), {
    status: 'active',
    scope: 'global',
    permissions: {
      access: {view: true, create: true, edit: true, approve: true},
      health: {create: true, edit: true},
    },
  });
  // 8. Perfil com health.read=true (obsoleto) e SEM health.view: prova que health.read NÃO autoriza
  await setDoc(doc(db, 'access_profiles', 'perfil_obsoleto_health_read'), {
    status: 'active',
    scope: 'global',
    permissions: {health: {read: true}},
  });

  // ─── Espelhos de usuário ───────────────────────────────────────────────
  await setDoc(doc(db, 'users', PRIMARY_RA), {
    ra: PRIMARY_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', OUTSIDER_RA), {
    ra: OUTSIDER_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', DOG_B_RA), {
    ra: DOG_B_RA,
    access_profile_id: 'operador_k9',
    access_scope: 'own_records',
  });
  await setDoc(doc(db, 'users', GLOBAL_RA), {
    ra: GLOBAL_RA,
    access_profile_id: 'gestor',
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
    access_profile_id: 'perfil_inativo_health_view',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', NO_CAPABILITY_RA), {
    ra: NO_CAPABILITY_RA,
    access_profile_id: 'gestor_sem_health_view',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', CAPABILITY_FALSE_RA), {
    ra: CAPABILITY_FALSE_RA,
    access_profile_id: 'gestor_health_view_false',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', TECH_ADMIN_RA), {
    ra: TECH_ADMIN_RA,
    access_profile_id: 'administrador',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', TECH_ADMIN_NO_VIEW_RA), {
    ra: TECH_ADMIN_NO_VIEW_RA,
    access_profile_id: 'admin_sem_health_view',
    access_scope: 'global',
  });
  await setDoc(doc(db, 'users', OBSOLETE_READ_RA), {
    ra: OBSOLETE_READ_RA,
    access_profile_id: 'perfil_obsoleto_health_read',
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
        doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'clinical_events', EVENT_A),
        eventPayload({dogId}),
      );
      await setDoc(
        doc(
          db, 'dogs', dogId, 'clinical_cases', CASE_A,
          'clinical_events', EVENT_A, 'clinical_amendments', AMEND_A,
        ),
        amendmentPayload({dogId}),
      );
      await setDoc(
        doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'exams', EXAM_A),
        examPayload({dogId}),
      );
      await setDoc(
        doc(db, 'dogs', dogId, 'treatment_protocols', PROTOCOL_A),
        protocolPayload({dogId}),
      );
      await setDoc(
        doc(db, 'dogs', dogId, 'treatment_protocols', PROTOCOL_A, 'doses', DOSE_A),
        dosePayload({dogId}),
      );
    }
  });
}

// ─── Refs ────────────────────────────────────────────────────────────────────
const caseRef = (db, dogId = DOG_A, caseId = CASE_A) =>
  doc(db, 'dogs', dogId, 'clinical_cases', caseId);

const eventRef = (db, dogId = DOG_A) =>
  doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'clinical_events', EVENT_A);

const amendRef = (db, dogId = DOG_A) =>
  doc(
    db, 'dogs', dogId, 'clinical_cases', CASE_A,
    'clinical_events', EVENT_A, 'clinical_amendments', AMEND_A,
  );

const examRef = (db, dogId = DOG_A, caseId = CASE_A, examId = EXAM_A) =>
  doc(db, 'dogs', dogId, 'clinical_cases', caseId, 'exams', examId);

const protocolRef = (db, dogId = DOG_A, protocolId = PROTOCOL_A) =>
  doc(db, 'dogs', dogId, 'treatment_protocols', protocolId);

const doseRef = (db, dogId = DOG_A, protocolId = PROTOCOL_A, doseId = DOSE_A) =>
  doc(db, 'dogs', dogId, 'treatment_protocols', protocolId, 'doses', doseId);

const casesCol = (db, dogId = DOG_A) =>
  collection(db, 'dogs', dogId, 'clinical_cases');

// ═════════════════════════════════════════════════════════════════════════════
// POSITIVOS — CR-01..CR-07 (health.view = true, health.read ausente)
// ═════════════════════════════════════════════════════════════════════════════

test('CR-01 operador_k9 com health.view=true e vínculo ao K9 LÊ ClinicalCase (health.read ausente)', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snap = await assertSucceeds(
    getDoc(caseRef(dbFor(PRIMARY_RA, {access_scope: 'own_records'}))),
  );
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().dog_id, DOG_A);
});

test('CR-02 gestor com health.view=true LÊ ClinicalCase (health.read ausente)', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snap = await assertSucceeds(getDoc(caseRef(dbFor(GLOBAL_RA))));
  assert.equal(snap.exists(), true, 'documento deve existir');
  assert.equal(snap.data().clinical_status, 'open');
});

test('CR-03 administrador com health.view=true LÊ ClinicalCase (health.read ausente)', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snap = await assertSucceeds(getDoc(caseRef(dbForTechAdmin())));
  assert.equal(snap.exists(), true, 'admin com perfil portando health.view deve ler prontuario');
  assert.equal(snap.data().clinical_status, 'open');
});

test('CR-04 clinical_events segue a mesma autoridade de leitura (operador_k9, gestor, administrador)', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const db of [
    dbFor(PRIMARY_RA, {access_scope: 'own_records'}),
    dbFor(GLOBAL_RA),
    dbForTechAdmin(),
  ]) {
    const snap = await assertSucceeds(getDoc(eventRef(db)));
    assert.equal(snap.exists(), true, 'evento deve ser legivel');
    assert.equal(snap.data().event_type, 'consultation');
  }
});

test('CR-05 clinical_amendments segue a mesma autoridade de leitura (operador_k9, gestor, administrador)', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const db of [
    dbFor(PRIMARY_RA, {access_scope: 'own_records'}),
    dbFor(GLOBAL_RA),
    dbForTechAdmin(),
  ]) {
    const snap = await assertSucceeds(getDoc(amendRef(db)));
    assert.equal(snap.exists(), true, 'adendo deve ser legivel');
    assert.equal(snap.data().amendment_type, 'correction');
  }
});

test('CR-05b LIST de clinical_cases do K9 autorizado é PERMITIDO (gestor e condutor)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // O path já determina o dogId: LIST não precisa de filtro para ser provável.
  for (const ra of [GLOBAL_RA, PRIMARY_RA]) {
    const snap = await assertSucceeds(getDocs(casesCol(dbFor(ra))));
    assert.equal(snap.size, 1, `um caso visivel para ${ra}`);
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

test('CN-01 não autenticado é NEGADO nos três caminhos e list', async () => {
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

test('CN-03 no-profile: perfil inexistente é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(NO_PROFILE_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CN-04 inactive-profile: perfil INATIVO com health.view=true é NEGADO', async () => {
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
// NEGATIVOS — CAPABILITY CLÍNICA (health.view = false/ausente) — CC-01..CC-04
// ═════════════════════════════════════════════════════════════════════════════

test('CC-01 profile without health.view cannot read clinical case (health.view AUSENTE)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Perfil ativo, escopo global, health.create/edit — sem `view`.
  const db = dbFor(NO_CAPABILITY_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CC-02 health.view == false é NEGADO', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(CAPABILITY_FALSE_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
});

test('CC-03 health.read obsoleto SEM health.view NÃO concede leitura clínica', async () => {
  await clearAll();
  await seedClinicalWorld();

  // OBSOLETE_READ_RA tem health.read=true mas health.view AUSENTE.
  // Prova que health.read foi descontinuado e não é aceito por hasClinicalReadAuthority().
  const db = dbFor(OBSOLETE_READ_RA);
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CC-04 health.create/edit NÃO substituem autoridade de leitura clínica (health.view)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // NO_CAPABILITY_RA tem create=true e edit=true, mas sem view=true.
  const db = dbFor(NO_CAPABILITY_RA);
  await assertFails(getDoc(caseRef(db)));
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — ADMINISTRAÇÃO TÉCNICA E AUSÊNCIA DE BYPASS — CA-01..CA-02
// ═════════════════════════════════════════════════════════════════════════════

test('CA-01 administração técnica SEM health.view no perfil é NEGADA (sem bypass)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Admin técnico real com admin=true mas cujo perfil carece de health.view.
  // Prova que hasClinicalReadAuthority() NÃO possui bypass de admin.
  const db = dbForTechAdminNoHealthView();
  await assertFails(getDoc(caseRef(db)));
  await assertFails(getDoc(eventRef(db)));
  await assertFails(getDoc(amendRef(db)));
  await assertFails(getDocs(casesCol(db)));
});

test('CA-02 admin técnico com health.view NÃO escreve prontuário (writes negados)', async () => {
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
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-admin',
      ),
      amendmentPayload(),
    ),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// NEGATIVOS — ISOLAMENTO CROSS-DOG — CX-01..CX-03
// ═════════════════════════════════════════════════════════════════════════════

test('CX-01 own_records com health.view NÃO lê ClinicalCase de K9 alheio', async () => {
  await clearAll();
  await seedClinicalWorld();

  // PRIMARY_RA tem health.view pleno, mas nenhum vínculo com DOG_B.
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

test('CX-03 estado válido com health.view e SEM vínculo ao K9 é NEGADO (outsider)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // OUTSIDER_RA: perfil ativo own_records COM health.view=true, zero vínculo.
  // Capability sozinha não autoriza: ambas as pernas são obrigatórias.
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
      doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado', 'clinical_events', EVENT_A),
      eventPayload({dogId: DOG_A}),
    );
  });

  // Autoridade é o dogId do PATH (DOG_B), não o campo. Condutor de DOG_A é
  // negado apesar do payload declarar o K9 dele.
  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(getDoc(caseRef(db, DOG_B, 'case-forjado')));
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_B, 'clinical_cases', 'case-forjado', 'clinical_events', EVENT_A)),
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

test('CW-01 ClinicalCase: create/update/delete NEGADOS para leitor autorizado com health.view', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(GLOBAL_RA);
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-novo'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'discharged'}));
  await assertFails(deleteDoc(caseRef(db)));
});

test('CW-02 ClinicalEvent: create/update/delete NEGADOS para leitor autorizado com health.view', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(GLOBAL_RA);
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'clinical_cases', CASE_A, 'clinical_events', 'event-novo'),
      eventPayload(),
    ),
  );
  await assertFails(updateDoc(eventRef(db), {event_type: 'exam'}));
  await assertFails(deleteDoc(eventRef(db)));
});

test('CW-03 Amendment: create/update/delete NEGADOS para leitor autorizado com health.view', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(GLOBAL_RA);
  await assertFails(
    setDoc(
      doc(
        db, 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-novo',
      ),
      amendmentPayload(),
    ),
  );
  await assertFails(updateDoc(amendRef(db), {reason: 'outra razao'}));
  await assertFails(deleteDoc(amendRef(db)));
});

test('CW-04 condutor vinculado com health.view também NÃO escreve', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbFor(PRIMARY_RA, {access_scope: 'own_records'});
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-novo'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'monitoring'}));
  await assertFails(deleteDoc(caseRef(db)));
});

test('CW-05 admin técnico com health.view também NÃO escreve', async () => {
  await clearAll();
  await seedClinicalWorld();

  const db = dbForTechAdmin();
  await assertFails(setDoc(caseRef(db, DOG_A, 'case-novo-admin'), casePayload()));
  await assertFails(updateDoc(caseRef(db), {clinical_status: 'discharged'}));
  await assertFails(deleteDoc(caseRef(db)));
  await assertFails(
    setDoc(
      doc(
        db, 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-admin',
      ),
      amendmentPayload(),
    ),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// PROVA: health.view NÃO CONCEDE MUTAÇÃO CLÍNICA — MUT-01..MUT-03
// ═════════════════════════════════════════════════════════════════════════════

test('MUT-01 health.view does not grant record_clinical', async () => {
  await clearAll();
  await seedClinicalWorld();

  // 1. Contrato de perfil: profileGrantsPermission com health.view=true NÃO concede record_clinical
  const perfilOperador = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilGestor = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilAdmin = {
    status: 'active',
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
      access: {view: true, create: true, edit: true, approve: true},
    },
  };

  assert.equal(profileGrantsPermission(perfilOperador, 'health', 'record_clinical'), false);
  assert.equal(profileGrantsPermission(perfilGestor, 'health', 'record_clinical'), false);
  assert.equal(profileGrantsPermission(perfilAdmin, 'health', 'record_clinical'), false);

  // 2. Regras de Firestore: escrita direta de cliente em clinical_events é NEGADA
  await assertFails(
    setDoc(
      doc(dbFor(PRIMARY_RA), 'dogs', DOG_A, 'clinical_cases', CASE_A, 'clinical_events', 'ev-client-1'),
      eventPayload(),
    ),
  );
  await assertFails(
    setDoc(
      doc(dbFor(GLOBAL_RA), 'dogs', DOG_A, 'clinical_cases', CASE_A, 'clinical_events', 'ev-client-2'),
      eventPayload(),
    ),
  );
  await assertFails(
    setDoc(
      doc(dbForTechAdmin(), 'dogs', DOG_A, 'clinical_cases', CASE_A, 'clinical_events', 'ev-client-3'),
      eventPayload(),
    ),
  );
});

test('MUT-02 health.view does not grant finalize_clinical', async () => {
  await clearAll();
  await seedClinicalWorld();

  const perfilOperador = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilGestor = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilAdmin = {
    status: 'active',
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
      access: {view: true, create: true, edit: true, approve: true},
    },
  };

  assert.equal(profileGrantsPermission(perfilOperador, 'health', 'finalize_clinical'), false);
  assert.equal(profileGrantsPermission(perfilGestor, 'health', 'finalize_clinical'), false);
  assert.equal(profileGrantsPermission(perfilAdmin, 'health', 'finalize_clinical'), false);

  // Regras de Firestore: update de cliente para finalizar caso é NEGADO
  await assertFails(
    updateDoc(caseRef(dbFor(PRIMARY_RA)), {clinical_status: 'finalized'}),
  );
  await assertFails(
    updateDoc(caseRef(dbFor(GLOBAL_RA)), {clinical_status: 'finalized'}),
  );
  await assertFails(
    updateDoc(caseRef(dbForTechAdmin()), {clinical_status: 'finalized'}),
  );
});

test('MUT-03 health.view does not grant amend_clinical', async () => {
  await clearAll();
  await seedClinicalWorld();

  const perfilOperador = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilGestor = {status: 'active', permissions: {health: {view: true, create: true, edit: true}}};
  const perfilAdmin = {
    status: 'active',
    permissions: {
      health: {view: true, create: true, edit: true, archive: true, approve: true},
      access: {view: true, create: true, edit: true, approve: true},
    },
  };

  assert.equal(profileGrantsPermission(perfilOperador, 'health', 'amend_clinical'), false);
  assert.equal(profileGrantsPermission(perfilGestor, 'health', 'amend_clinical'), false);
  assert.equal(profileGrantsPermission(perfilAdmin, 'health', 'amend_clinical'), false);

  // Regras de Firestore: escrita direta de cliente em clinical_amendments é NEGADA
  await assertFails(
    setDoc(
      doc(
        dbFor(PRIMARY_RA), 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-client',
      ),
      amendmentPayload(),
    ),
  );
  await assertFails(
    setDoc(
      doc(
        dbFor(GLOBAL_RA), 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-client',
      ),
      amendmentPayload(),
    ),
  );
  await assertFails(
    setDoc(
      doc(
        dbForTechAdmin(), 'dogs', DOG_A, 'clinical_cases', CASE_A,
        'clinical_events', EVENT_A, 'clinical_amendments', 'amend-client',
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

test('REG-01 health_documents continua legível SEM exigir capability adicional', async () => {
  await clearAll();
  await seedClinicalWorld();
  await seedFirestore(async (db) => {
    await setDoc(doc(db, 'dogs', DOG_A, 'health_documents', 'doc-1'), {
      storage_path: 'dogs/dog-clinical-a/health/doc-1.pdf',
      schema_version: 1,
    });
  });

  // Compatibilidade: health_documents continua acessível com acesso ao cão
  await assertSucceeds(
    getDoc(doc(dbFor(PRIMARY_RA), 'dogs', DOG_A, 'health_documents', 'doc-1')),
  );
  await assertSucceeds(
    getDoc(doc(dbFor(GLOBAL_RA), 'dogs', DOG_A, 'health_documents', 'doc-1')),
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

  const db = dbFor(PRIMARY_RA);
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

  // Prova que a fundação criou autoridade APENAS para os caminhos canônicos
  await assertFails(
    getDoc(doc(dbFor(GLOBAL_RA), 'dogs', DOG_A, 'clinical_notes', 'n-1')),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// EXAMS SUBCOLLECTION — EXAM-01..EXAM-07 (F20.EXAM-V1)
// ═════════════════════════════════════════════════════════════════════════════

test('EXAM-01 exams follow same read authority: operador_k9, gestor e administrador com health.view leem exam', async () => {
  await clearAll();
  await seedClinicalWorld();

  const snapGlobal = await assertSucceeds(getDoc(examRef(dbFor(GLOBAL_RA))));
  assert.equal(snapGlobal.exists(), true);
  assert.equal(snapGlobal.data().exam_type, 'blood_work');

  const snapConductor = await assertSucceeds(getDoc(examRef(dbFor(PRIMARY_RA))));
  assert.equal(snapConductor.exists(), true);

  const snapAdmin = await assertSucceeds(getDoc(examRef(dbForTechAdmin())));
  assert.equal(snapAdmin.exists(), true);
});

test('EXAM-02 profile without health.view é NEGADO na leitura de exam', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(getDoc(examRef(dbFor(NO_CAPABILITY_RA))));
  await assertFails(getDoc(examRef(dbFor(CAPABILITY_FALSE_RA))));
  await assertFails(getDoc(examRef(dbFor(OBSOLETE_READ_RA))));
  await assertFails(getDoc(examRef(dbFor(ANONYMOUS))));
  await assertFails(getDoc(examRef(dbForTechAdminNoHealthView())));
});

test('EXAM-03 leitor sem acesso ao K9 é NEGADO na leitura de exam', async () => {
  await clearAll();
  await seedClinicalWorld();

  // OUTSIDER_RA tem health.view=true mas não tem vínculo com DOG_A
  await assertFails(getDoc(examRef(dbFor(OUTSIDER_RA))));
});

test('EXAM-04 escrita direta de cliente CREATE exam é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(
    setDoc(examRef(dbFor(GLOBAL_RA), DOG_A, CASE_A, 'exam-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      title: 'Raio-X Não Autorizado',
    }),
  );
  await assertFails(
    setDoc(examRef(dbFor(PRIMARY_RA), DOG_A, CASE_A, 'exam-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      title: 'Tentativa Condutor',
    }),
  );
  await assertFails(
    setDoc(examRef(dbForTechAdmin(), DOG_A, CASE_A, 'exam-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      title: 'Tentativa Admin',
    }),
  );
});

test('EXAM-05 escrita direta de cliente UPDATE exam é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(
    updateDoc(examRef(dbFor(GLOBAL_RA)), {
      current_stage: 'resulted',
    }),
  );
  await assertFails(
    updateDoc(examRef(dbFor(PRIMARY_RA)), {
      current_stage: 'collected',
    }),
  );
});

test('EXAM-06 escrita direta de cliente DELETE exam é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(deleteDoc(examRef(dbFor(GLOBAL_RA))));
  await assertFails(deleteDoc(examRef(dbFor(PRIMARY_RA))));
  await assertFails(deleteDoc(examRef(dbForTechAdmin())));
});

test('EXAM-07 regra de exams não amplia acesso a outros nós clínicos ou K9 alheio', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Condutor de DOG_B não acessa exams de DOG_A
  await assertFails(getDoc(examRef(dbFor(DOG_B_RA), DOG_A)));

  // Leitor sem vínculo não acessa events nem amendments nem exams
  await assertFails(getDoc(eventRef(dbFor(OUTSIDER_RA))));
  await assertFails(getDoc(amendRef(dbFor(OUTSIDER_RA))));
  await assertFails(getDoc(examRef(dbFor(OUTSIDER_RA))));
});

test('OPS-01 receipts de operação são negados a TODO cliente (deny explícito)', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Receipts são infraestrutura interna de idempotência. O deny já era efetivo
  // por ausência de regra; CLINICAL-BE.MERGE-I1 §16 o tornou EXPLÍCITO, e este
  // teste é o que impede um wildcard recursivo futuro de reabri-lo por acidente.
  const opsRef = (db, dogId = DOG_A) =>
    doc(db, 'dogs', dogId, 'clinical_cases', CASE_A, 'operations', 'op-1');

  // Nem o condutor com vínculo e health.view pode ler o receipt.
  await assertFails(getDoc(opsRef(dbFor(PRIMARY_RA))));
  await assertFails(getDoc(opsRef(dbFor(DOG_B_RA), DOG_B)));
  await assertFails(getDoc(opsRef(dbFor(OUTSIDER_RA))));
  // Nem administração técnica: receipts não são dado clínico legível.
  await assertFails(getDoc(opsRef(dbForTechAdmin())));

  // Escrita de cliente também negada, em qualquer identidade.
  await assertFails(setDoc(opsRef(dbFor(PRIMARY_RA)), {kind: 'forjado'}));
  await assertFails(setDoc(opsRef(dbFor(OUTSIDER_RA)), {kind: 'forjado'}));

  // E listar a coleção de receipts não é caminho alternativo.
  await assertFails(
    getDocs(collection(dbFor(PRIMARY_RA), 'dogs', DOG_A, 'clinical_cases', CASE_A, 'operations')),
  );
});

// ═════════════════════════════════════════════════════════════════════════════
// TREATMENT PROTOCOLS & DOSES — TREAT-01..TREAT-07 (F20.TREATMENT-V1)
// ═════════════════════════════════════════════════════════════════════════════

test('TREAT-01 treatment protocols/doses follow same read authority: operador_k9, gestor e administrador com health.view leem', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const db of [
    dbFor(PRIMARY_RA, {access_scope: 'own_records'}),
    dbFor(GLOBAL_RA),
    dbForTechAdmin(),
  ]) {
    const pSnap = await assertSucceeds(getDoc(protocolRef(db)));
    assert.equal(pSnap.exists(), true);
    assert.equal(pSnap.data().medication_name, 'Amoxicilina');

    const dSnap = await assertSucceeds(getDoc(doseRef(db)));
    assert.equal(dSnap.exists(), true);
    assert.equal(dSnap.data().status, 'administered');
  }
});

test('TREAT-02 profile without health.view é NEGADO na leitura de treatment_protocol e dose', async () => {
  await clearAll();
  await seedClinicalWorld();

  for (const ra of [NO_CAPABILITY_RA, CAPABILITY_FALSE_RA, OBSOLETE_READ_RA]) {
    await assertFails(getDoc(protocolRef(dbFor(ra))));
    await assertFails(getDoc(doseRef(dbFor(ra))));
  }

  await assertFails(getDoc(protocolRef(dbFor(ANONYMOUS))));
  await assertFails(getDoc(doseRef(dbFor(ANONYMOUS))));

  await assertFails(getDoc(protocolRef(dbForTechAdminNoHealthView())));
  await assertFails(getDoc(doseRef(dbForTechAdminNoHealthView())));
});

test('TREAT-03 leitor sem acesso ao K9 é NEGADO na leitura de treatment_protocol e dose', async () => {
  await clearAll();
  await seedClinicalWorld();

  // OUTSIDER_RA tem health.view=true mas não tem vínculo com DOG_A
  await assertFails(getDoc(protocolRef(dbFor(OUTSIDER_RA))));
  await assertFails(getDoc(doseRef(dbFor(OUTSIDER_RA))));

  // Condutor de DOG_B não acessa treatment_protocol nem doses de DOG_A
  await assertFails(getDoc(protocolRef(dbFor(DOG_B_RA), DOG_A)));
  await assertFails(getDoc(doseRef(dbFor(DOG_B_RA), DOG_A)));
});

test('TREAT-04 escrita direta de cliente CREATE treatment_protocol e dose é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(
    setDoc(protocolRef(dbFor(GLOBAL_RA), DOG_A, 'tp-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      medication_name: 'Dipirona',
    }),
  );
  await assertFails(
    setDoc(doseRef(dbFor(GLOBAL_RA), DOG_A, PROTOCOL_A, 'dose-nova'), {
      dog_id: DOG_A,
      protocol_id: PROTOCOL_A,
      status: 'administered',
    }),
  );

  await assertFails(
    setDoc(protocolRef(dbFor(PRIMARY_RA), DOG_A, 'tp-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      medication_name: 'Dipirona',
    }),
  );
  await assertFails(
    setDoc(doseRef(dbFor(PRIMARY_RA), DOG_A, PROTOCOL_A, 'dose-nova'), {
      dog_id: DOG_A,
      protocol_id: PROTOCOL_A,
      status: 'administered',
    }),
  );

  await assertFails(
    setDoc(protocolRef(dbForTechAdmin(), DOG_A, 'tp-novo'), {
      dog_id: DOG_A,
      case_id: CASE_A,
      medication_name: 'Dipirona',
    }),
  );
  await assertFails(
    setDoc(doseRef(dbForTechAdmin(), DOG_A, PROTOCOL_A, 'dose-nova'), {
      dog_id: DOG_A,
      protocol_id: PROTOCOL_A,
      status: 'administered',
    }),
  );
});

test('TREAT-05 escrita direta de cliente UPDATE treatment_protocol e dose é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(
    updateDoc(protocolRef(dbFor(GLOBAL_RA)), {
      status: 'completed',
    }),
  );
  await assertFails(
    updateDoc(doseRef(dbFor(GLOBAL_RA)), {
      status: 'skipped',
    }),
  );

  await assertFails(
    updateDoc(protocolRef(dbFor(PRIMARY_RA)), {
      status: 'paused',
    }),
  );
  await assertFails(
    updateDoc(doseRef(dbFor(PRIMARY_RA)), {
      status: 'skipped',
    }),
  );
});

test('TREAT-06 escrita direta de cliente DELETE treatment_protocol e dose é NEGADA', async () => {
  await clearAll();
  await seedClinicalWorld();

  await assertFails(deleteDoc(protocolRef(dbFor(GLOBAL_RA))));
  await assertFails(deleteDoc(doseRef(dbFor(GLOBAL_RA))));

  await assertFails(deleteDoc(protocolRef(dbFor(PRIMARY_RA))));
  await assertFails(deleteDoc(doseRef(dbFor(PRIMARY_RA))));

  await assertFails(deleteDoc(protocolRef(dbForTechAdmin())));
  await assertFails(deleteDoc(doseRef(dbForTechAdmin())));
});

test('TREAT-07 regra de treatment_protocols não amplia acesso a outros nós clínicos ou K9 alheio', async () => {
  await clearAll();
  await seedClinicalWorld();

  // Condutor de DOG_B não acessa treatment_protocols nem doses de DOG_A
  await assertFails(getDoc(protocolRef(dbFor(DOG_B_RA), DOG_A)));
  await assertFails(getDoc(doseRef(dbFor(DOG_B_RA), DOG_A)));

  // Leitor sem vínculo não acessa events nem amendments nem protocols nem doses
  await assertFails(getDoc(protocolRef(dbFor(OUTSIDER_RA))));
  await assertFails(getDoc(doseRef(dbFor(OUTSIDER_RA))));
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
