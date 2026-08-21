/**
 * HealthDocument canônico — B0-B
 * Testes de Rules para:
 *   Firestore  dogs/{dogId}/health_documents/{documentId}
 *   Storage    health_documents/{dogId}/{documentId}
 *
 * Contrato sob teste:
 * 1. Firestore: leitura para autenticado com acesso ao K9; TODA escrita de
 *    cliente negada (o agregado é backend-owned, ver ADR-005 E1/E2 aplicado a
 *    HealthDocument no Schema §2.11).
 * 2. Storage STAGING (`health_document_uploads/{dogId}/{documentId}`): create
 *    para autenticado com acesso ao K9, restrito a contentType permitido e
 *    <= 20 MB. É o único destino de upload do cliente e NÃO é evidência.
 * 3. Storage CANÔNICO (`health_documents/{dogId}/{documentId}`): leitura com
 *    acesso ao K9 e NENHUMA escrita de cliente — nem create. É o invariante
 *    central do B0-B.R, porque `allow create` permitiria substituir bytes de
 *    um documento já finalizado.
 * 4. Path fora dos namespaces declarados continua deny-all.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-document
 */
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
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
  updateDoc,
  Timestamp,
} from 'firebase/firestore';
import {
  deleteObject,
  getMetadata,
  ref,
  uploadBytes,
} from 'firebase/storage';

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

const DOG_A = 'dog-document-a';
const DOC_ID = 'hd_0123456789abcdef0123456789';
const STAGING = `health_document_uploads/${DOG_A}/${DOC_ID}`;
const CANONICAL = `health_documents/${DOG_A}/${DOC_ID}`;

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});

const tests = [];
function test(name, fn) {
  tests.push({name, fn});
}

function auth(ra, claims = {}) {
  if (ra === null) return testEnv.unauthenticatedContext();
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

function storageFor(ra, claims = {}) {
  return auth(ra, claims).storage();
}

function now() {
  return Timestamp.fromDate(new Date('2026-08-15T12:00:00.000Z'));
}

/** Agregado canônico conforme Schema §2.11 (sem metadados de mutação). */
function documentPayload(overrides = {}) {
  return {
    document_type: 'certificate',
    title: 'Atestado veterinário',
    storage_path: `health_documents/${DOG_A}/${DOC_ID}`,
    mime_type: 'application/pdf',
    uploaded_at: now(),
    recorded_by: {
      uid: `uid-${PRIMARY_RA}`,
      name: 'Operador',
      internal_role: 'condutor',
    },
    schema_version: 1,
    file_size_bytes: 4096,
    ...overrides,
  };
}

async function seedFirestore(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

async function seedStorage(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.storage());
  });
}

async function clearAll() {
  await testEnv.clearFirestore();
  if (typeof testEnv.clearStorage === 'function') {
    await testEnv.clearStorage();
  }
}

/**
 * SEC-02A.2 — estado de autorização é PRÉ-REQUISITO, não detalhe de fixture.
 *
 * Antes deste gate a suite dependia apenas da claim `access_scope`, que era o
 * modelo da variante fail-OPEN. Sob SEC-02A.2 o perfil de acesso é a autoridade
 * e `authState()` faz `get()` em `users/{ra}` e `access_profiles/{id}`: sem
 * esses documentos a avaliação nem chega a decidir — ela ERRA, e um erro de
 * avaliação não é prova de DENY.
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
 * K9 atribuído ao PRIMARY_RA → autoriza `canAccessDogRecord` pela via de
 * vínculo.
 *
 * `dogAssignedToAuth` reconhece exatamente `conductorRa`, `conductor_ra`,
 * `handlerId` e `handler_id`. A fixture anterior gravava `handler_ra`, que NÃO
 * é nenhum deles: o vínculo nunca era reconhecido nem na variante antiga.
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

async function seedDocument(dogId = DOG_A, documentId = DOC_ID) {
  await seedFirestore(async (db) => {
    await setDoc(
      doc(db, 'dogs', dogId, 'health_documents', documentId),
      documentPayload(),
    );
  });
}

function bytes(size = 16) {
  return new Uint8Array(size).fill(7);
}

// ── Firestore: leitura ───────────────────────────────────────────────────────

test('Firestore: leitura permitida com acesso ao K9', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID)),
  );
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().document_type, 'certificate');
  assert.equal(
    snap.data().storage_path,
    `health_documents/${DOG_A}/${DOC_ID}`,
  );
});

test('Firestore: leitura negada sem acesso ao K9 (own_records)', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID)),
  );
});

test('Firestore: leitura negada para anônimo', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(ANONYMOUS);
  await assertFails(
    getDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID)),
  );
});

// ── SEC-02A.2: estado de autorização é PRÉ-CONDIÇÃO da leitura ───────────────
//
// Cada caso isola UMA falha do estado de autorização. Todos carregam a claim
// `access_scope: 'global'` (default de `auth()`) DE PROPÓSITO: sob SEC-02A.2 a
// claim não é autoridade e não pode ampliar acesso quando o perfil não resolve.
// Antes deste gate a suite não exercitava nenhum destes caminhos.

/** Contexto SEM a claim `access_scope` — prova que ausência não vira global. */
function dbWithoutScopeClaim(ra) {
  return testEnv
    .authenticatedContext(`uid-${ra}`, {email: `${ra}@gcm.com.br`, ra})
    .firestore();
}

const healthDocumentRef = (db) =>
  doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID);

test('SEC-02A.2: espelho de usuário ausente nega leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // NO_MIRROR_RA não tem documento em users/{ra}: estado não resolvível.
  await assertFails(getDoc(healthDocumentRef(dbFor(NO_MIRROR_RA))));
});

test('SEC-02A.2: perfil de acesso ausente nega leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // Espelho existe e aponta para access_profiles/perfil_que_nao_existe.
  await assertFails(getDoc(healthDocumentRef(dbFor(NO_PROFILE_RA))));
});

test('SEC-02A.2: perfil inativo nega leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // Perfil existe com scope global, porém status: 'inactive'.
  await assertFails(getDoc(healthDocumentRef(dbFor(INACTIVE_RA))));
});

test('SEC-02A.2: claim global NÃO amplia quando o perfil não resolve', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // Este é o vetor exato do defeito SEC-02A: claim dizendo global com estado
  // de autorização irresolvível NÃO pode liberar o registro do K9.
  for (const ra of [NO_MIRROR_RA, NO_PROFILE_RA, INACTIVE_RA]) {
    await assertFails(
      getDoc(healthDocumentRef(dbFor(ra, {access_scope: 'global'}))),
    );
  }
});

test('SEC-02A.2: autoridade global resolvida pelo PERFIL permite leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const snap = await assertSucceeds(
    getDoc(healthDocumentRef(dbFor(GLOBAL_RA))),
  );
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().document_type, 'certificate');
});

test('SEC-02A.2: claim ausente não impede autoridade derivada do perfil', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // Perfil é a autoridade: sem claim `access_scope`, o escopo global do perfil
  // continua valendo. Ausência de claim não restringe nem amplia por si.
  const snap = await assertSucceeds(
    getDoc(healthDocumentRef(dbWithoutScopeClaim(GLOBAL_RA))),
  );
  assert.equal(snap.exists(), true);
});

test('SEC-02A.2: own_records válido sem vínculo com o K9 nega leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // OUTSIDER_RA tem estado de autorização VÁLIDO (users + perfil ativo), mas
  // escopo own_records e nenhum vínculo com DOG_A. Estado válido não basta.
  await assertFails(getDoc(healthDocumentRef(dbFor(OUTSIDER_RA))));
});

test('SEC-02A.2: own_records COM vínculo ao K9 permite leitura', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  // PRIMARY_RA é own_records e é o condutor do DOG_A — via de vínculo.
  const snap = await assertSucceeds(
    getDoc(healthDocumentRef(dbFor(PRIMARY_RA, {access_scope: 'own_records'}))),
  );
  assert.equal(snap.exists(), true);
});

// ── Firestore: escrita de cliente sempre negada ──────────────────────────────

test('Firestore: create de cliente negado mesmo com payload canônico', async () => {
  await clearAll();
  await seedDog();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    setDoc(
      doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID),
      documentPayload(),
    ),
  );
});

test('Firestore: update de cliente negado (metadados imutáveis)', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID), {
      title: 'Título alterado pelo cliente',
    }),
  );
  // Nem para "corrigir" o próprio storage_path.
  await assertFails(
    updateDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID), {
      storage_path: 'health_documents/outro/forjado',
    }),
  );
});

test('Firestore: delete de cliente negado', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    deleteDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID)),
  );
});

test('Firestore: subcoleção de receipts também nega escrita de cliente', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(PRIMARY_RA);
  await assertFails(
    setDoc(
      doc(
        db,
        'dogs',
        DOG_A,
        'health_documents',
        DOC_ID,
        'operations',
        'op-forjada',
      ),
      {kind: 'health_document_create_v1', fingerprint: 'forjado'},
    ),
  );
});

test('Firestore: Admin SDK (harness) cria — writer é backend', async () => {
  await clearAll();
  await seedDog();
  await seedDocument();
  const db = dbFor(PRIMARY_RA);
  const snap = await assertSucceeds(
    getDoc(doc(db, 'dogs', DOG_A, 'health_documents', DOC_ID)),
  );
  assert.equal(snap.exists(), true, 'seed via Admin SDK é legítimo');
});

// ── Storage STAGING: leitura e create do cliente ─────────────────────────────

test('Storage staging: create permitido com acesso ao K9 (PDF)', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  await assertSucceeds(
    uploadBytes(ref(storage, STAGING), bytes(), {
      contentType: 'application/pdf',
    }),
  );
});

test('Storage staging: create permitido com imagem', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  await assertSucceeds(
    uploadBytes(ref(storage, STAGING), bytes(), {contentType: 'image/jpeg'}),
  );
});

test('Storage staging: create negado sem acesso ao K9', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(
    uploadBytes(ref(storage, STAGING), bytes(), {
      contentType: 'application/pdf',
    }),
  );
});

test('Storage staging: create negado para anonimo', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(ANONYMOUS);
  await assertFails(
    uploadBytes(ref(storage, STAGING), bytes(), {
      contentType: 'application/pdf',
    }),
  );
});

test('Storage staging: create negado com contentType nao permitido', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  await assertFails(
    uploadBytes(ref(storage, STAGING), bytes(), {contentType: 'text/html'}),
  );
  await assertFails(
    uploadBytes(ref(storage, STAGING), bytes(), {
      contentType: 'application/x-msdownload',
    }),
  );
});

test('Storage staging: create negado acima de 20 MB', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  const tooBig = new Uint8Array(20 * 1024 * 1024 + 1).fill(1);
  await assertFails(
    uploadBytes(ref(storage, STAGING), tooBig, {
      contentType: 'application/pdf',
    }),
  );
});

test('Storage staging: leitura permitida com acesso ao K9', async () => {
  await clearAll();
  await seedDog();
  await seedStorage(async (storage) => {
    await uploadBytes(ref(storage, STAGING), bytes(), {
      contentType: 'application/pdf',
    });
  });
  const storage = storageFor(PRIMARY_RA);
  await assertSucceeds(getMetadata(ref(storage, STAGING)));
});

test('Storage staging: overwrite e possivel e NAO e corrupcao', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  const target = ref(storage, STAGING);
  await assertSucceeds(
    uploadBytes(target, bytes(16), {contentType: 'application/pdf'}),
  );
  // Caracterizacao factual: `update: false` nao impede um segundo upload —
  // o Storage avalia como create. Aqui isso e INOCUO por construcao: staging
  // nao e evidencia, e o selo do backend se prende a generation validada,
  // entao trocar bytes depois da validacao faz o FINALIZE falhar em vez de
  // selar outra coisa.
  await assertSucceeds(
    uploadBytes(target, bytes(32), {contentType: 'application/pdf'}),
  );
  const md = await getMetadata(target);
  assert.equal(Number(md.size), 32, 'staging aceita substituicao');
});

// ── Storage CANONICO: nenhuma escrita de cliente ─────────────────────────────

test('Storage canonico: leitura permitida com acesso ao K9', async () => {
  await clearAll();
  await seedDog();
  await seedStorage(async (storage) => {
    await uploadBytes(ref(storage, CANONICAL), bytes(), {
      contentType: 'application/pdf',
    });
  });
  const storage = storageFor(PRIMARY_RA);
  await assertSucceeds(getMetadata(ref(storage, CANONICAL)));
});

test('Storage canonico: leitura negada sem acesso ao K9', async () => {
  await clearAll();
  await seedDog();
  await seedStorage(async (storage) => {
    await uploadBytes(ref(storage, CANONICAL), bytes(), {
      contentType: 'application/pdf',
    });
  });
  const storage = storageFor(OUTSIDER_RA, {access_scope: 'own_records'});
  await assertFails(getMetadata(ref(storage, CANONICAL)));
});

test('Storage canonico: CREATE de cliente NEGADO — invariante central', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  // Este e o teste que justifica todo o B0-B.R: se o cliente pudesse criar
  // aqui, poderia tambem substituir os bytes de um documento ja finalizado,
  // e o storage_path de uma OperationalRestriction deixaria de apontar para a
  // evidencia aprovada.
  await assertFails(
    uploadBytes(ref(storage, CANONICAL), bytes(), {
      contentType: 'application/pdf',
    }),
  );
});

test('Storage canonico: overwrite de cliente NEGADO', async () => {
  await clearAll();
  await seedDog();
  // Objeto selado pelo backend (harness usa Admin, que ignora Rules).
  await seedStorage(async (storage) => {
    await uploadBytes(ref(storage, CANONICAL), bytes(16), {
      contentType: 'application/pdf',
    });
  });
  const storage = storageFor(PRIMARY_RA);
  await assertFails(
    uploadBytes(ref(storage, CANONICAL), bytes(32), {
      contentType: 'application/pdf',
    }),
  );
  // Bytes selados permanecem intactos.
  await seedStorage(async (adminStorage) => {
    const md = await getMetadata(ref(adminStorage, CANONICAL));
    assert.equal(Number(md.size), 16, 'evidencia selada nao foi alterada');
  });
});

test('Storage canonico: delete de cliente negado', async () => {
  await clearAll();
  await seedDog();
  await seedStorage(async (storage) => {
    await uploadBytes(ref(storage, CANONICAL), bytes(), {
      contentType: 'application/pdf',
    });
  });
  const storage = storageFor(PRIMARY_RA);
  await assertFails(deleteObject(ref(storage, CANONICAL)));
});

test('Storage canonico: create negado com qualquer MIME valido', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  // Nao ha combinacao de payload que autorize o cliente: negacao e absoluta.
  for (const contentType of [
    'application/pdf',
    'image/jpeg',
    'application/msword',
  ]) {
    await assertFails(
      uploadBytes(ref(storage, CANONICAL), bytes(8), {contentType}),
    );
  }
});

// ── Storage: fora dos namespaces declarados ──────────────────────────────────

test('Storage: path fora dos namespaces continua deny-all', async () => {
  await clearAll();
  await seedDog();
  const storage = storageFor(PRIMARY_RA);
  // Raiz do staging sem dogId.
  await assertFails(
    uploadBytes(ref(storage, 'health_document_uploads/solto'), bytes(), {
      contentType: 'application/pdf',
    }),
  );
  // Profundidade extra nao coberta pela regra de dois segmentos.
  await assertFails(
    uploadBytes(ref(storage, `${STAGING}/extra`), bytes(), {
      contentType: 'application/pdf',
    }),
  );
  // Namespace inventado.
  await assertFails(
    uploadBytes(ref(storage, `health_docs/${DOG_A}/${DOC_ID}`), bytes(), {
      contentType: 'application/pdf',
    }),
  );
});
async function run() {
  let passed = 0;
  let failed = 0;
  const failures = [];
  for (const {name, fn} of tests) {
    try {
      await fn();
      console.log(`PASS - ${name}`);
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
  console.log('\nhealth_document_rules_tests: all passed');
  await testEnv.cleanup();
}

// Guard de entrypoint robusto em Windows e POSIX (pathToFileURL normaliza
// `C:\...` de argv[1] contra o `file:///C:/...` de import.meta.url).
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().catch((error) => {
    console.error('Test runner failed:', error);
    process.exit(1);
  });
}

export {tests, run, testEnv};
