/**
 * HW-4A.2D.1 — LIMITE EFETIVO DE CHUNK e PAGINAÇÃO MULTI-CHUNK.
 *
 * Mede DOIS tetos independentes contra as Rules candidatas do 5R.1:
 *
 *   1. limite da QUERY    — operador `in` do Firestore (documentado: 30)
 *   2. limite das RULES   — orçamento de get()/exists() por query (documentado: 10)
 *
 * O menor vence. GLOBAL curto-circuita em st.global e NÃO faz lookup por cão;
 * OWN_RECORDS precisa de canAccessDogRecord(dogId) por documento avaliado.
 *
 * Fixtures reais: cada cão existe em /dogs, vinculado ao condutor, e possui um
 * health_schedule com dog_id canônico — sem isso o teste mediria apenas o SDK.
 *
 * Execução (a partir de tools/rules_tests):
 *   npm run test:health-schedule-cg-limits
 */
import assert from 'node:assert/strict';
import {
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collectionGroup,
  doc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  startAfter,
  where,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'canil-gcm';
const RA_OWN = '691755';
const RA_GLOBAL = '600001';

const testEnv = await initializeTestEnvironment({projectId: PROJECT_ID});

function auth(ra, claims = {}) {
  return testEnv.authenticatedContext(`uid-${ra}`, {
    email: `${ra}@gcm.com.br`, ra, ...claims,
  });
}
const dbFor = (ra, claims) => auth(ra, claims).firestore();
const now = () => Timestamp.fromDate(new Date('2026-05-31T12:00:00.000Z'));
const dogId = (i) => `chunk-dog-${String(i).padStart(3, '0')}`;

async function seed(dogCount, {schedulesPerDog = 1} = {}) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'access_profiles', 'operador_k9'), {
      status: 'active', scope: 'own_records',
      permissions: {health: {view: true}},
    });
    await setDoc(doc(db, 'access_profiles', 'gestor_global'), {
      status: 'active', scope: 'global',
      permissions: {health: {view: true}},
    });
    await setDoc(doc(db, 'users', RA_OWN), {
      ra: RA_OWN, access_profile_id: 'operador_k9', access_scope: 'own_records',
    });
    await setDoc(doc(db, 'users', RA_GLOBAL), {
      ra: RA_GLOBAL, access_profile_id: 'gestor_global', access_scope: 'global',
    });

    for (let i = 0; i < dogCount; i++) {
      const id = dogId(i);
      // Vínculo REAL de condutor: é o que canAccessDogRecord consulta.
      await setDoc(doc(db, 'dogs', id), {
        name: `K9 ${i}`,
        conductorRa: RA_OWN, conductor_ra: RA_OWN,
        handlerId: RA_OWN, handler_id: RA_OWN,
        active: true,
      });
      for (let s = 0; s < schedulesPerDog; s++) {
        await setDoc(doc(db, 'dogs', id, 'health_schedule', `s-${i}-${s}`), {
          dog_id: id,
          schedule_type: 'vaccination',
          title: `agenda ${i}-${s}`,
          // Timestamps COLIDEM entre cães: pior caso para paginação.
          scheduled_for: Timestamp.fromDate(new Date(`2026-07-${20 + s}T12:00:00.000Z`)),
          timezone: 'America/Sao_Paulo',
          lifecycle_status: 'open',
          source_type: 'manual',
          created_at: now(),
          recorded_by: {uid: `uid-${RA_OWN}`, name: 'C', internal_role: 'condutor'},
          schema_version: 1,
        });
      }
    }
  });
}

/** Separa CONSTRUÇÃO (SDK) de EXECUÇÃO (Rules). */
async function probe(db, ids) {
  let q;
  try {
    q = query(
      collectionGroup(db, 'health_schedule'),
      where('dog_id', 'in', ids),
      where('lifecycle_status', '==', 'open'),
      orderBy('scheduled_for', 'asc'),
      limit(100),
    );
  } catch (e) {
    return {construction: 'SDK_REJECTED', execution: 'NOT_ATTEMPTED', detail: e.message.slice(0, 80)};
  }
  try {
    const snap = await getDocs(q);
    return {construction: 'ACCEPTED', execution: 'ALLOW', size: snap.size};
  } catch (e) {
    const evalErr = /evaluation error/i.test(String(e.message));
    return {
      construction: 'ACCEPTED',
      execution: evalErr ? 'EVALUATION_ERROR' : 'DENY',
      code: e.code,
    };
  }
}

// Fronteira own_records medida em 8/9 — os tamanhos intermediários são
// obrigatórios: sem 6/7/8 o "maior N que passou" mente (mediu 5 por omissão).
const SIZES = [1, 5, 6, 7, 8, 9, 10, 11, 15, 20, 29, 30, 31];
const results = {own: {}, global: {}};

console.log('=== §8 OWN_RECORDS — execucao real sob Rules 5R.1 ===');
console.log('  N   construcao      execucao          docs');
for (const n of SIZES) {
  await seed(n);
  const ids = Array.from({length: n}, (_, i) => dogId(i));
  const r = await probe(dbFor(RA_OWN, {access_scope: 'own_records'}), ids);
  results.own[n] = r;
  console.log(`  ${String(n).padEnd(4)}${r.construction.padEnd(16)}${r.execution.padEnd(18)}${r.size ?? '-'}`);
}

console.log('');
console.log('=== §9 GLOBAL (controle) ===');
console.log('  N   construcao      execucao          docs');
for (const n of [10, 11, 30, 31]) {
  await seed(n);
  const ids = Array.from({length: n}, (_, i) => dogId(i));
  const r = await probe(dbFor(RA_GLOBAL, {access_scope: 'global'}), ids);
  results.global[n] = r;
  console.log(`  ${String(n).padEnd(4)}${r.construction.padEnd(16)}${r.execution.padEnd(18)}${r.size ?? '-'}`);
}

// --- limites efetivos ------------------------------------------------------
const maxOk = (m) => SIZES.filter((n) => m[n]?.execution === 'ALLOW').pop() ?? 0;
const OWN_MAX = maxOk(results.own);
const GLOBAL_MAX = [10, 11, 30, 31].filter((n) => results.global[n]?.execution === 'ALLOW').pop() ?? 0;

console.log('');
console.log('=== §10 CONTRATO DE CHUNK MEDIDO ===');
console.log(`  OWN_RECORDS_MAX_DOG_IDS_PER_QUERY = ${OWN_MAX}`);
console.log(`  GLOBAL_MAX_DOG_IDS_PER_QUERY      = ${GLOBAL_MAX}`);

// --- §16/§17/§18 paginação multi-chunk -------------------------------------
console.log('');
console.log('=== §16 PAGINACAO MULTI-CHUNK (own_records, chunks do tamanho medido) ===');
const TOTAL_DOGS = Math.max(OWN_MAX * 2 + 1, 3);
await seed(TOTAL_DOGS, {schedulesPerDog: 2});
const db = dbFor(RA_OWN, {access_scope: 'own_records'});
const allIds = Array.from({length: TOTAL_DOGS}, (_, i) => dogId(i));
const chunks = [];
for (let i = 0; i < allIds.length; i += OWN_MAX) chunks.push(allIds.slice(i, i + OWN_MAX));
console.log(`  cães=${TOTAL_DOGS} chunkSize=${OWN_MAX} chunks=${chunks.length} docsEsperados=${TOTAL_DOGS * 2}`);

// verdade sintética: união ordenada por (scheduled_for, path)
const truth = [];
for (const c of chunks) {
  const snap = await assertSucceeds(getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', c),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(500),
  )));
  snap.docs.forEach((d) => truth.push({path: d.ref.path, at: d.data().scheduled_for.toMillis()}));
}
truth.sort((a, b) => a.at - b.at || a.path.localeCompare(b.path));
console.log(`  verdade global = ${truth.length} docs`);

// Candidato B: um cursor por chunk (multi-cursor), merge por (scheduled_for, path)
const PAGE = 5;
const cursors = new Array(chunks.length).fill(null);
const buffers = chunks.map(() => []);
const paged = [];
async function refill(ci) {
  if (buffers[ci].length > 0) return;
  const base = [
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', chunks[ci]),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
  ];
  const q = cursors[ci]
    ? query(...base, startAfter(cursors[ci]), limit(PAGE))
    : query(...base, limit(PAGE));
  const snap = await getDocs(q);
  if (snap.empty) return;
  cursors[ci] = snap.docs[snap.docs.length - 1];
  snap.docs.forEach((d) => buffers[ci].push({
    path: d.ref.path, at: d.data().scheduled_for.toMillis(), ci,
  }));
}
let pages = 0;
while (true) {
  await Promise.all(chunks.map((_, ci) => refill(ci)));
  const heads = buffers.map((b) => b[0]).filter(Boolean);
  if (heads.length === 0) break;
  const page = [];
  for (let k = 0; k < PAGE; k++) {
    const hs = buffers.map((b) => b[0]).filter(Boolean);
    if (hs.length === 0) break;
    hs.sort((a, b) => a.at - b.at || a.path.localeCompare(b.path));
    const win = hs[0];
    buffers[win.ci].shift();
    page.push(win.path);
    await refill(win.ci);
  }
  if (page.length === 0) break;
  paged.push(...page);
  pages++;
  if (pages > 50) break;
}

console.log(`  paginas=${pages} docsPaginados=${paged.length}`);
const dup = paged.length !== new Set(paged).size;
const ordered = JSON.stringify(paged) === JSON.stringify(truth.map((t) => t.path));
console.log(`  duplicatas       ${dup ? 'SIM' : 'NAO'}`);
console.log(`  cobertura exata  ${paged.length === truth.length ? 'SIM' : 'NAO'}`);
console.log(`  ordem identica   ${ordered ? 'SIM' : 'NAO'}`);
console.log(`  VEREDITO multi-cursor: ${!dup && ordered ? 'FUNCIONA' : 'FALHA'}`);

// Candidato A: cursor global único reaplicado a todos os chunks
console.log('');
console.log('=== §16 Candidato A: cursor global unico em todos os chunks ===');
let aVerdict = 'NAO_TESTAVEL';
try {
  const first = await getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', chunks[0]),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    limit(PAGE),
  ));
  const shared = first.docs[first.docs.length - 1];
  const other = await getDocs(query(
    collectionGroup(db, 'health_schedule'),
    where('dog_id', 'in', chunks[chunks.length - 1]),
    where('lifecycle_status', '==', 'open'),
    orderBy('scheduled_for', 'asc'),
    startAfter(shared),
    limit(PAGE),
  ));
  aVerdict = `EXECUTOU (retornou ${other.size}) — cursor de outro chunk NAO garante fronteira global`;
} catch (e) {
  aVerdict = `REJEITADO: ${String(e.message).slice(0, 90)}`;
}
console.log(`  ${aVerdict}`);

await testEnv.cleanup();
console.log('');
console.log(`RESUMO: own=${OWN_MAX} global=${GLOBAL_MAX} multiCursor=${!dup && ordered ? 'OK' : 'FALHOU'}`);
assert.ok(OWN_MAX > 0, 'own_records deve autorizar pelo menos 1 cão');
process.exit(0);
