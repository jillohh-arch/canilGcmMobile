/**
 * CLIN-AUTH-BE-4A.I2 — TESTES COMPORTAMENTAIS FOCADOS DOS WRITERS DE ACCESS PROFILE.
 *
 * npm run build && node lib/access_profile_writer_test.js
 *
 * Exercita o seam injetável extraído em CLIN-AUTH-BE-4A.I2.T0
 * (`access_profile_writer_callables.ts`) com fakes de `db`, autorização e
 * trilha de auditoria. NÃO toca Firebase, produção ou staging. Os wrappers
 * `onCall` de produção NÃO são chamados: os invariants vivem nas funções `run*`.
 *
 * O contrato é CONGELADO — o teste se conforma a ele, nunca o contrário.
 * O que estes testes travam:
 *   - tri-state de permissão (omitido preserva / true / false revoga / não-bool rejeita);
 *   - validação do PAR canônico `module.action`;
 *   - contrato de `expectedUpdatedAt` em CREATE vs EDIT;
 *   - atomicidade TOCTOU: AUTHORIZED_OPERATION === EXECUTED_OPERATION;
 *   - concorrência otimista (stale → failed-precondition, zero write);
 *   - `seed_version` server-managed;
 *   - segurança de duplicação;
 *   - ZERO WRITE comprovado em todo caminho de falha (exceção sozinha não prova);
 *   - regressão do lado de LEITURA (sanitizer não lança) e de escopo.
 */
import * as assert from "assert";
import * as admin from "firebase-admin";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  AccessProfileAction,
  AccessProfileWriterCaller,
  AccessProfileWriterDeps,
  isCanonicalCapability,
  runAdminDuplicateAccessProfile,
  runAdminSaveAccessProfile,
  runAdminSeedAccessProfiles,
} from "./access_profile_writer_callables";
import {profileGrantsPermission} from "./index";

type JsonMap = Record<string, unknown>;

const CALLER: AccessProfileWriterCaller = {
  uid: "uid-adm",
  email: "1001@gcm.com.br",
  ra: "1001",
  name: "Administrador",
};

/** Relógio determinístico da trilha de auditoria. */
const AUDIT_AT = 1_700_000_000_000;
/** Primeiro commit do fake. Cada commit avança 1s, gerando T2 ≠ T1. */
const COMMIT_CLOCK = 1_755_000_000_000;
/** `updated_at` armazenado nas fixtures de EDIT. */
const STORED_T1 = 1_700_500_000_000;

// ── Identidade dos sentinels de FieldValue ───────────────────────────────────
// Comparação por construtor: é o que distingue delete/serverTimestamp/arrayUnion
// sem depender de detalhes internos do SDK.
const DELETE_CTOR = admin.firestore.FieldValue.delete().constructor;
const STAMP_CTOR = admin.firestore.FieldValue.serverTimestamp().constructor;
const UNION_CTOR = admin.firestore.FieldValue.arrayUnion("x").constructor;

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isDeleteSentinel(value: unknown): boolean {
  return isPlainObject(value) && value.constructor === DELETE_CTOR;
}
function isStampSentinel(value: unknown): boolean {
  return isPlainObject(value) && value.constructor === STAMP_CTOR;
}
function isUnionSentinel(value: unknown): boolean {
  return isPlainObject(value) && value.constructor === UNION_CTOR;
}

/** Procura recursivamente qualquer FieldValue.delete() num payload de escrita. */
function hasDeleteSentinelDeep(value: unknown): boolean {
  if (isDeleteSentinel(value)) return true;
  if (Array.isArray(value)) return value.some(hasDeleteSentinelDeep);
  if (isPlainObject(value) && value.constructor === Object) {
    return Object.values(value).some(hasDeleteSentinelDeep);
  }
  return false;
}

// ── Fake Firestore ───────────────────────────────────────────────────────────

interface WriteRecord {
  path: string;
  merge: boolean;
  data: JsonMap;
}

/**
 * Fake de Firestore que modela a semântica REAL relevante ao contrato:
 *
 *  - `set(..., {merge:true})` mescla mapas aninhados, então FieldValue.delete()
 *    dentro de `permissions` realmente remove a capability armazenada. Sem
 *    isso, a revogação explícita passaria como no-op sem o teste notar.
 *  - `set(...)` SEM merge rejeita sentinel de delete, como a API real. É o que
 *    prova que o caminho de duplicação não pode vazar um delete.
 *  - `serverTimestamp()` materializa em Timestamp no commit, então
 *    `accessProfileUpdatedAtMillis` observa o mesmo tipo que em produção e a
 *    concorrência otimista pode ser exercitada de verdade.
 *  - a transação só materializa escritas se o callback resolver: qualquer
 *    exceção deixa o store intacto, que é como `_writes()` prova zero write.
 */
function createFakeDb(initial: Record<string, JsonMap> = {}) {
  const store = new Map<string, JsonMap>();
  for (const [path, data] of Object.entries(initial)) {
    store.set(path, {...data});
  }
  const writes: WriteRecord[] = [];
  let clock = COMMIT_CLOCK;
  let autoId = 0;
  // Ganchos one-shot: simulam um escritor concorrente que age na janela entre
  // a pré-leitura de autorização e a leitura transacional.
  const afterGetHooks = new Map<string, () => void>();

  function materialize(value: unknown, at: number): unknown {
    if (isStampSentinel(value)) return admin.firestore.Timestamp.fromMillis(at);
    if (isUnionSentinel(value)) {
      return (value as unknown as {elements: unknown[]}).elements;
    }
    if (Array.isArray(value)) return value.map((item) => materialize(item, at));
    if (isPlainObject(value) && value.constructor === Object) {
      const out: JsonMap = {};
      for (const [k, v] of Object.entries(value)) out[k] = materialize(v, at);
      return out;
    }
    return value;
  }

  function mergeInto(target: JsonMap, patch: JsonMap, at: number): JsonMap {
    for (const [key, value] of Object.entries(patch)) {
      if (isDeleteSentinel(value)) {
        delete target[key];
        continue;
      }
      if (isStampSentinel(value)) {
        target[key] = admin.firestore.Timestamp.fromMillis(at);
        continue;
      }
      if (isUnionSentinel(value)) {
        const current = Array.isArray(target[key]) ? (target[key] as unknown[]) : [];
        const elements = (value as unknown as {elements: unknown[]}).elements;
        target[key] = [...current, ...elements];
        continue;
      }
      if (isPlainObject(value) && value.constructor === Object) {
        const current = isPlainObject(target[key]) ? {...(target[key] as JsonMap)} : {};
        target[key] = mergeInto(current, value, at);
        continue;
      }
      target[key] = materialize(value, at);
    }
    return target;
  }

  function commitWrite(path: string, data: JsonMap, merge: boolean, at: number) {
    if (!merge && hasDeleteSentinelDeep(data)) {
      // Paridade com a API real: delete só é aceito em update()/set(merge).
      throw new Error(
        `FieldValue.delete() em set() sem merge (path=${path}) — inválido no SDK real.`,
      );
    }
    if (merge) {
      const current = store.get(path);
      store.set(path, mergeInto({...(current ?? {})}, data, at));
    } else {
      store.set(path, materialize(data, at) as JsonMap);
    }
    writes.push({path, merge, data});
  }

  function makeDocRef(path: string) {
    return {
      path,
      id: path.split("/").pop() as string,
      async get() {
        const data = store.get(path);
        const snapshot = {
          exists: data !== undefined,
          id: path.split("/").pop() as string,
          data: () => (data === undefined ? undefined : {...data}),
        };
        const hook = afterGetHooks.get(path);
        if (hook) {
          afterGetHooks.delete(path);
          hook();
        }
        return snapshot;
      },
      async set(data: JsonMap, options?: {merge?: boolean}) {
        const at = clock;
        clock += 1000;
        commitWrite(path, data, options?.merge === true, at);
      },
    };
  }

  const db = {
    collection(col: string) {
      return {
        doc(id?: string) {
          autoId += 1;
          return makeDocRef(`${col}/${id ?? `auto_${autoId}`}`);
        },
        async get() {
          const docs = [...store.entries()]
            .filter(([path]) => path.startsWith(`${col}/`))
            .map(([path, data]) => ({
              id: path.split("/").pop() as string,
              ref: makeDocRef(path),
              data: () => ({...data}),
            }));
          return {docs, empty: docs.length === 0, size: docs.length};
        },
      };
    },
    batch() {
      const staged: Array<{path: string; data: JsonMap; merge: boolean}> = [];
      return {
        set(ref: {path: string}, data: JsonMap, options?: {merge?: boolean}) {
          staged.push({path: ref.path, data, merge: options?.merge === true});
        },
        async commit() {
          const at = clock;
          clock += 1000;
          for (const item of staged) {
            commitWrite(item.path, item.data, item.merge, at);
          }
        },
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{
          exists: boolean;
          data: () => JsonMap | undefined;
        }>;
        set: (ref: {path: string}, data: JsonMap, options?: {merge?: boolean}) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const pending: Array<{path: string; data: JsonMap; merge: boolean}> = [];
      const tx = {
        async get(ref: {path: string}) {
          const data = store.get(ref.path);
          return {
            exists: data !== undefined,
            data: () => (data === undefined ? undefined : {...data}),
          };
        },
        set(ref: {path: string}, data: JsonMap, options?: {merge?: boolean}) {
          pending.push({path: ref.path, data, merge: options?.merge === true});
        },
      };
      // Só materializa se o callback resolver. Exceção ⇒ store intacto.
      const result = await fn(tx);
      const at = clock;
      clock += 1000;
      for (const item of pending) {
        commitWrite(item.path, item.data, item.merge, at);
      }
      return result;
    },
    _store: store,
    _writes: () => writes,
    _doc: (path: string) => store.get(path),
    _onceAfterGet: (path: string, hook: () => void) => {
      afterGetHooks.set(path, hook);
    },
  };
  return db as unknown as FirebaseFirestore.Firestore & {
    _store: Map<string, JsonMap>;
    _writes: () => WriteRecord[];
    _doc: (path: string) => JsonMap | undefined;
    _onceAfterGet: (path: string, hook: () => void) => void;
  };
}

// ── Fake de dependências ─────────────────────────────────────────────────────

interface AuthCall {
  moduleId: string;
  action: AccessProfileAction;
}

function createDeps(
  db: ReturnType<typeof createFakeDb>,
  options: {deny?: boolean} = {},
): AccessProfileWriterDeps & {_authCalls: () => AuthCall[]} {
  const authCalls: AuthCall[] = [];
  return {
    db,
    async requireAccessPermission(auth, moduleId, action) {
      authCalls.push({moduleId, action});
      if (options.deny) {
        throw new HttpsError(
          "permission-denied",
          `Perfil sem permissao para ${moduleId}.${action}.`,
        );
      }
      if (!auth) throw new HttpsError("unauthenticated", "Autenticação obrigatória.");
      return CALLER;
    },
    // Determinístico: o teste observa a trilha sem depender do relógio real.
    auditEntry(action, caller, reason) {
      const entry: JsonMap = {
        action,
        at: admin.firestore.Timestamp.fromMillis(AUDIT_AT),
        by: caller.uid,
        ra: caller.ra,
      };
      if (reason) entry.reason = reason;
      return entry;
    },
    _authCalls: () => authCalls,
  };
}

function makeRequest(data: JsonMap): CallableRequest {
  return {
    auth: {uid: CALLER.uid, token: {}},
    data,
  } as unknown as CallableRequest;
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const PATH = "access_profiles/perfil_teste";

/** Perfil válido enviado pelo cliente. */
function sourceProfile(overrides: JsonMap = {}): JsonMap {
  return {
    id: "perfil_teste",
    name: "Perfil Teste",
    scope: "own_records",
    ...overrides,
  };
}

/** Documento armazenado (before-image) com `updated_at` canônico. */
function storedProfile(overrides: JsonMap = {}): JsonMap {
  return {
    id: "perfil_teste",
    name: "Perfil Teste",
    scope: "own_records",
    status: "active",
    seed_version: 6,
    permissions: {health: {view: true, read: true}, k9: {view: true}},
    updated_at: admin.firestore.Timestamp.fromMillis(STORED_T1),
    ...overrides,
  };
}

// ── Helpers de asserção ──────────────────────────────────────────────────────

async function expectHttpsError(
  fn: () => Promise<unknown>,
  code: string,
  label: string,
): Promise<HttpsError> {
  try {
    await fn();
  } catch (error) {
    assert.ok(
      error instanceof HttpsError,
      `${label}: esperava HttpsError, recebeu ${String(error)}`,
    );
    assert.strictEqual(
      (error as HttpsError).code,
      code,
      `${label}: código de erro divergente`,
    );
    return error as HttpsError;
  }
  throw new assert.AssertionError({
    message: `${label}: esperava falha ${code}, mas a operação teve sucesso`,
  });
}

/**
 * Prova ZERO WRITE. Uma exceção sozinha não é prova: o writer poderia ter
 * escrito antes de falhar, ou a transação poderia ter materializado.
 */
function assertZeroWrites(
  db: ReturnType<typeof createFakeDb>,
  label: string,
  before = 0,
): void {
  assert.strictEqual(
    db._writes().length,
    before,
    `${label}: esperava zero escrita adicional`,
  );
}

function permissionsOf(db: ReturnType<typeof createFakeDb>, path = PATH): JsonMap {
  const doc = db._doc(path) ?? {};
  return (doc.permissions as JsonMap) ?? {};
}

function lastWrite(db: ReturnType<typeof createFakeDb>): WriteRecord {
  const writes = db._writes();
  assert.ok(writes.length > 0, "esperava ao menos uma escrita");
  return writes[writes.length - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// §5 — TRI-STATE DE PERMISSÃO
// ─────────────────────────────────────────────────────────────────────────────

async function testTriStateOmittedPreserves(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  // `health.read` é OMITIDO e o módulo `k9` inteiro é omitido.
  await runAdminSaveAccessProfile(
    makeRequest({
      id: "perfil_teste",
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {view: true}}}),
    }),
    deps,
  );
  const health = permissionsOf(db).health as JsonMap;
  assert.strictEqual(health.view, true, "true explícito deve permanecer true");
  assert.strictEqual(
    health.read,
    true,
    "ação OMITIDA deve ser preservada pelo merge (não revogada)",
  );
  const k9 = permissionsOf(db).k9 as JsonMap;
  assert.strictEqual(k9.view, true, "módulo omitido inteiro deve ser preservado");
  // O payload enviado não pode nem mencionar a chave omitida.
  const written = (lastWrite(db).data.permissions as JsonMap).health as JsonMap;
  assert.ok(!("read" in written), "ação omitida não pode aparecer no payload");
}

async function testTriStateTrueStaysTrue(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile({permissions: {}})});
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {read: true}}}),
    }),
    deps,
  );
  assert.strictEqual(
    (permissionsOf(db).health as JsonMap).read,
    true,
    "true deve ser persistido como true",
  );
}

async function testTriStateFalseRevokesInMerge(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {read: false}}}),
    }),
    deps,
  );
  // O payload precisa carregar o sentinel — é ele que efetiva a revogação.
  const writtenHealth = (lastWrite(db).data.permissions as JsonMap).health as JsonMap;
  assert.ok(
    isDeleteSentinel(writtenHealth.read),
    "false em EDIT/merge deve virar FieldValue.delete()",
  );
  const health = permissionsOf(db).health as JsonMap;
  assert.ok(!("read" in health), "a capability revogada deve desaparecer do documento");
  assert.strictEqual(health.view, true, "capability vizinha não pode ser afetada");
  assert.strictEqual(
    (permissionsOf(db).k9 as JsonMap).view,
    true,
    "módulo vizinho não pode ser afetado",
  );
}

async function testTriStateFalseOmittedInCreate(): Promise<void> {
  const db = createFakeDb();
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      profile: sourceProfile({permissions: {health: {view: true, read: false}}}),
    }),
    deps,
  );
  const written = lastWrite(db);
  assert.ok(
    !hasDeleteSentinelDeep(written.data),
    "CREATE não pode emitir sentinel de delete (documento novo)",
  );
  const health = permissionsOf(db).health as JsonMap;
  assert.strictEqual(health.view, true);
  assert.ok(!("read" in health), "false em CREATE/replace apenas omite a chave");
}

async function testTriStateNonBooleanRejected(): Promise<void> {
  // null, "true", 1 e objetos não são coagidos: são recusados.
  const invalid: Array<[string, unknown]> = [
    ["null", null],
    ["\"true\"", "true"],
    ["1", 1],
    ["0", 0],
    ["{}", {}],
    ["[]", []],
    ["\"false\"", "false"],
  ];
  for (const [label, value] of invalid) {
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: {health: {read: value}}}),
          }),
          deps,
        ),
      "invalid-argument",
      `permissão ${label}`,
    );
    assertZeroWrites(db, `permissão ${label}`);
  }
}

async function testTriStateMalformedPermissionMaps(): Promise<void> {
  const invalid: Array<[string, unknown]> = [
    ["permissions=null", null],
    ["permissions=\"health\"", "health"],
    ["permissions=[]", []],
    ["permissions=42", 42],
  ];
  for (const [label, value] of invalid) {
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: value}),
          }),
          deps,
        ),
      "invalid-argument",
      label,
    );
    assertZeroWrites(db, label);
  }
  // Mapa de módulo malformado.
  for (const [label, value] of [
    ["health=null", null],
    ["health=[\"read\"]", ["read"]],
    ["health=\"read\"", "read"],
  ] as Array<[string, unknown]>) {
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: {health: value}}),
          }),
          deps,
        ),
      "invalid-argument",
      label,
    );
    assertZeroWrites(db, label);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §6 — PAR CANÔNICO module.action
// ─────────────────────────────────────────────────────────────────────────────

const ACCEPTED_PAIRS: Array<[string, string]> = [
  ["health", "view"],
  ["health", "read"],
  ["health", "manage_nutrition_plan"],
  ["health", "record_routine"],
  ["health", "issue_restriction"],
  ["health", "release_restriction"],
  ["health", "cancel_restriction"],
  // CLIN-WRITER-1.W2 — vocabulário clínico canônico (definição apenas).
  ["health", "record_clinical"],
  ["health", "finalize_clinical"],
  ["health", "amend_clinical"],
  ["health", "manage_clinical_case"],
  ["health", "reopen_clinical_case"],
  ["k9", "view"],
  ["k9", "edit"],
];

const REJECTED_PAIRS: Array<[string, string]> = [
  // módulo inexistente
  ["foo", "read"],
  // typo de módulo
  ["heath", "read"],
  // ação inexistente no módulo
  ["health", "bogus"],
  // case-sensitivity: normalizar viraria concessão de autoridade
  ["health", "Read"],
  // PARES CRUZADOS: cada token existe, o par nunca é legítimo
  ["dashboard", "cancel_restriction"],
  ["me", "manage_nutrition_plan"],
  ["vehicles", "record_routine"],
  ["inventory", "issue_restriction"],
];

async function testCapabilityPairsAccepted(): Promise<void> {
  for (const [moduleId, action] of ACCEPTED_PAIRS) {
    assert.strictEqual(
      isCanonicalCapability(moduleId, action),
      true,
      `${moduleId}.${action} deveria ser canônico`,
    );
    // Prova end-to-end: o par aceito atravessa o writer e é persistido.
    const db = createFakeDb();
    const deps = createDeps(db);
    await runAdminSaveAccessProfile(
      makeRequest({
        profile: sourceProfile({permissions: {[moduleId]: {[action]: true}}}),
      }),
      deps,
    );
    assert.strictEqual(
      ((permissionsOf(db)[moduleId] as JsonMap) ?? {})[action],
      true,
      `${moduleId}.${action} deveria ter sido persistido`,
    );
  }
}

async function testCapabilityPairsRejected(): Promise<void> {
  for (const [moduleId, action] of REJECTED_PAIRS) {
    assert.strictEqual(
      isCanonicalCapability(moduleId, action),
      false,
      `${moduleId}.${action} NÃO deveria ser canônico`,
    );
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: {[moduleId]: {[action]: true}}}),
          }),
          deps,
        ),
      "invalid-argument",
      `${moduleId}.${action}`,
    );
    assertZeroWrites(db, `${moduleId}.${action}`);
  }
}

async function testKnownModuleAndActionIsNotEnough(): Promise<void> {
  // Núcleo do R1: validar "módulo conhecido && ação conhecida" produziria uma
  // matriz cartesiana inválida. Cada par abaixo tem os DOIS tokens válidos.
  const crossed: Array<[string, string]> = [
    ["dashboard", "cancel_restriction"],
    ["me", "manage_nutrition_plan"],
    ["vehicles", "record_routine"],
    ["inventory", "issue_restriction"],
    ["me", "archive"],
    ["k9", "read"],
  ];
  for (const [moduleId, action] of crossed) {
    const moduleExists = isCanonicalCapability(moduleId, "view");
    const actionExistsSomewhere =
      isCanonicalCapability("health", action) || isCanonicalCapability("k9", action);
    assert.ok(moduleExists, `${moduleId} deveria existir como módulo`);
    assert.ok(
      actionExistsSomewhere,
      `${action} deveria existir em algum outro módulo`,
    );
    assert.strictEqual(
      isCanonicalCapability(moduleId, action),
      false,
      `o PAR ${moduleId}.${action} deve ser recusado mesmo com ambos os tokens válidos`,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §7 — CONSISTÊNCIA COM A MATRIZ DE SEED CANÔNICA (default-access-profiles v6)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Pares `module.action` presentes no seed versionado canônico (v6), transcritos
 * do contrato. NÃO é teste de política de atribuição: apenas de que tudo que o
 * seed já contém continua reconhecido pela matriz do writer. Uma divergência
 * aqui significaria que o seeder canônico passaria a ser rejeitado.
 */
const SEED_V6_BASE_MODULES = [
  "dashboard",
  "k9",
  "humans",
  "binomials",
  "vehicles",
  "occurrences",
  "training",
  "training_matrix",
  "inventory",
  "reports",
  "audit",
  "access",
  "settings",
  "shifts",
];
const SEED_V6_BASE_ACTIONS = [
  "view",
  "create",
  "edit",
  "archive",
  "export",
  "approve",
  "audit",
];
const SEED_V6_HEALTH_ACTIONS = [
  "view",
  "read",
  "create",
  "edit",
  "archive",
  "export",
  "approve",
  "audit",
  "manage_nutrition_plan",
];
const SEED_V6_ME_ACTIONS = ["view", "edit"];

async function testSeedMatrixCompatibility(): Promise<void> {
  const pairs: Array<[string, string]> = [];
  for (const moduleId of SEED_V6_BASE_MODULES) {
    for (const action of SEED_V6_BASE_ACTIONS) pairs.push([moduleId, action]);
  }
  for (const action of SEED_V6_HEALTH_ACTIONS) pairs.push(["health", action]);
  for (const action of SEED_V6_ME_ACTIONS) pairs.push(["me", action]);

  assert.strictEqual(pairs.length, 109, "o seed v6 canônico tem 109 pares distintos");
  const unrecognized = pairs.filter(([m, a]) => !isCanonicalCapability(m, a));
  assert.deepStrictEqual(
    unrecognized,
    [],
    "todo par do seed canônico deve ser reconhecido pelo writer",
  );

  // `health.read` é capability VÁLIDA. A política de quem a recebe
  // (instrutor_k9, administrador) é deliberadamente 4B e fica fora do I2.
  assert.strictEqual(isCanonicalCapability("health", "read"), true);

  // Capabilities operacionais emitidas pelo backend, ausentes do seed mas
  // legítimas: se caíssem da matriz, o próprio backend seria rejeitado.
  for (const action of [
    "record_routine",
    "issue_restriction",
    "release_restriction",
    "cancel_restriction",
  ]) {
    assert.strictEqual(
      isCanonicalCapability("health", action),
      true,
      `health.${action} é emitida pelo backend e deve ser canônica`,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §7B — CLIN-WRITER-1.W2: DEFINIÇÃO NÃO É CONCESSÃO
// ─────────────────────────────────────────────────────────────────────────────

/** As cinco capabilities clínicas canônicas. Definição apenas. */
const CLINICAL_CAPABILITIES = [
  "record_clinical",
  "finalize_clinical",
  "amend_clinical",
  "manage_clinical_case",
  "reopen_clinical_case",
];

/**
 * Prova load-bearing do W2: entrar no catálogo canônico torna o par
 * `health.<action>` VÁLIDO PARA CONCESSÃO FUTURA, e nada além disso. Nenhum
 * perfil passa a possuir a capability, e a omissão continua significando
 * NÃO CONCEDIDA.
 */
async function testClinicalCapabilitiesDefinedButNotGranted(): Promise<void> {
  // (a) DEFINIÇÃO: as cinco são reconhecidas como pares canônicos.
  for (const action of CLINICAL_CAPABILITIES) {
    assert.strictEqual(
      isCanonicalCapability("health", action),
      true,
      `health.${action} deveria ser canônica após o W2`,
    );
  }

  // (b) CONCESSÃO ZERO: um perfil armazenado que não pede nada clínico não
  // recebe nada clínico. Definir no catálogo não materializa a chave.
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {view: true}}}),
    }),
    deps,
  );
  const health = (permissionsOf(db).health as JsonMap) ?? {};
  for (const action of CLINICAL_CAPABILITIES) {
    assert.ok(
      !(action in health),
      `health.${action} NÃO deveria existir no perfil: definição não é concessão`,
    );
  }

  // (c) OMISSÃO = NÃO CONCEDIDA: nenhuma capability clínica aparece como
  // `false` placeholder nem como qualquer outro valor materializado.
  for (const action of CLINICAL_CAPABILITIES) {
    assert.strictEqual(
      health[action],
      undefined,
      `health.${action} deve permanecer ausente, não um placeholder`,
    );
  }

  // (d) INVARIANTE health.read: o W2 não altera a política de leitura.
  assert.strictEqual(isCanonicalCapability("health", "read"), true);
  assert.strictEqual(health.read, true, "health.read preservado do stored");

  // (e) MUNDO FECHADO PRESERVADO: nome clínico inventado continua inválido.
  for (const action of [
    "frobnicate",
    "record_clinicals",
    "Record_clinical",
    "open_case",
    "append_event",
    "cancel_event",
    "transition_case",
    "discharge_case",
  ]) {
    assert.strictEqual(
      isCanonicalCapability("health", action),
      false,
      `health.${action} NÃO é vocabulário canônico`,
    );
  }

  // (f) PAR CRUZADO: capability clínica só existe sob `health`.
  for (const moduleId of ["k9", "me", "dashboard", "occurrences", "access"]) {
    for (const action of CLINICAL_CAPABILITIES) {
      assert.strictEqual(
        isCanonicalCapability(moduleId, action),
        false,
        `o PAR ${moduleId}.${action} nunca é legítimo`,
      );
    }
  }
}

/**
 * O vocabulário clínico não abre caminho de escrita nova: uma capability
 * clínica inválida (typo) continua sendo recusada com ZERO escrita, e o
 * contrato endurecido do writer permanece intacto.
 */
async function testClinicalCapabilityTypoFailsClosed(): Promise<void> {
  for (const action of ["record_clinicial", "finalise_clinical", "amend_clinicals"]) {
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: {health: {[action]: true}}}),
          }),
          deps,
        ),
      "invalid-argument",
      `health.${action}`,
    );
    assertZeroWrites(db, `health.${action}`);
  }
}

/**
 * Concessão explícita continua sendo o ÚNICO caminho: a capability clínica só
 * chega ao documento quando o payload autorizado a pede com `true`, e o
 * tri-state endurecido (`false` → revoga em merge) segue valendo para ela.
 */
async function testClinicalCapabilityRequiresExplicitGrant(): Promise<void> {
  // Concessão explícita persiste.
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {record_clinical: true}}}),
    }),
    deps,
  );
  assert.strictEqual(
    ((permissionsOf(db).health as JsonMap) ?? {}).record_clinical,
    true,
    "concessão explícita deveria persistir",
  );

  // `false` em merge revoga via sentinel de delete — mesmo contrato endurecido.
  const db2 = createFakeDb({
    [PATH]: storedProfile({
      permissions: {health: {view: true, read: true, record_clinical: true}},
    }),
  });
  const deps2 = createDeps(db2);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {record_clinical: false}}}),
    }),
    deps2,
  );
  const written = lastWrite(db2);
  assert.ok(
    hasDeleteSentinelDeep(written.data),
    "record_clinical: false deveria revogar via FieldValue.delete()",
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// §8 — CONTRATO DE CREATE
// ─────────────────────────────────────────────────────────────────────────────

async function testCreateSucceedsWithoutExpectedUpdatedAt(): Promise<void> {
  const db = createFakeDb();
  const deps = createDeps(db);
  const result = await runAdminSaveAccessProfile(
    makeRequest({
      profile: sourceProfile({
        permissions: {health: {view: true, read: true, archive: false}},
        seed_version: 99,
      }),
    }),
    deps,
  );
  assert.deepStrictEqual(result, {id: "perfil_teste", created: true});
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "create"}],
    "CREATE deve exigir exatamente access.create",
  );
  const doc = db._doc(PATH) ?? {};
  assert.strictEqual(doc.status, "active");
  assert.strictEqual(doc.created_by, CALLER.ra, "CREATE registra created_by");
  assert.ok(doc.created_at instanceof admin.firestore.Timestamp);
  // CLIN-AUTH-BE-4A.I2.R1: `seed_version` é server-managed na CRIAÇÃO manual.
  // O cliente enviou 99 e o valor NÃO tem autoridade: um perfil criado à mão
  // não tem proveniência de seed, então 0.
  assert.strictEqual(
    doc.seed_version,
    0,
    "CREATE manual ignora o seed_version do cliente e grava 0",
  );
  const trail = doc.audit_trail as JsonMap[];
  assert.strictEqual(trail.length, 1);
  assert.strictEqual(trail[0].action, "created", "trilha de CREATE registra `created`");
  const health = permissionsOf(db).health as JsonMap;
  assert.strictEqual(health.view, true);
  assert.strictEqual(health.read, true);
  assert.ok(!("archive" in health), "false em CREATE apenas omite");
}

async function testCreateRejectsExpectedUpdatedAt(): Promise<void> {
  const db = createFakeDb();
  const deps = createDeps(db);
  // Documento ausente + expectedUpdatedAt fornecido: aceitar daria a falsa
  // impressão de que a criação foi protegida contra concorrência.
  await expectHttpsError(
    () =>
      runAdminSaveAccessProfile(
        makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
        deps,
      ),
    "invalid-argument",
    "CREATE + expectedUpdatedAt",
  );
  assertZeroWrites(db, "CREATE + expectedUpdatedAt");
  assert.deepStrictEqual(deps._authCalls(), [{moduleId: "access", action: "create"}]);
}

// ─────────────────────────────────────────────────────────────────────────────
// §9 — CONTRATO DE EDIT
// ─────────────────────────────────────────────────────────────────────────────

async function testEditRequiresExpectedUpdatedAt(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  await expectHttpsError(
    () => runAdminSaveAccessProfile(makeRequest({profile: sourceProfile()}), deps),
    "invalid-argument",
    "EDIT sem expectedUpdatedAt",
  );
  assertZeroWrites(db, "EDIT sem expectedUpdatedAt");
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "edit"}],
    "EDIT deve exigir exatamente access.edit",
  );
}

async function testEditRejectsMalformedExpectedUpdatedAt(): Promise<void> {
  const malformed: Array<[string, unknown]> = [
    ["NaN", Number.NaN],
    ["Infinity", Number.POSITIVE_INFINITY],
    ["-Infinity", Number.NEGATIVE_INFINITY],
    ["string numérica", "1700500000000"],
    ["string", "agora"],
    ["null", null],
    ["true", true],
    ["objeto", {millis: STORED_T1}],
    ["Timestamp", admin.firestore.Timestamp.fromMillis(STORED_T1)],
  ];
  for (const [label, value] of malformed) {
    const db = createFakeDb({[PATH]: storedProfile()});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({expectedUpdatedAt: value, profile: sourceProfile()}),
          deps,
        ),
      "invalid-argument",
      `EDIT expectedUpdatedAt ${label}`,
    );
    assertZeroWrites(db, `EDIT expectedUpdatedAt ${label}`);
  }
}

async function testEditStaleIsRejected(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  await expectHttpsError(
    () =>
      runAdminSaveAccessProfile(
        makeRequest({expectedUpdatedAt: STORED_T1 - 1, profile: sourceProfile()}),
        deps,
      ),
    "failed-precondition",
    "EDIT stale",
  );
  assertZeroWrites(db, "EDIT stale");
}

async function testEditExactTimestampSucceeds(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  const result = await runAdminSaveAccessProfile(
    makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
    deps,
  );
  assert.deepStrictEqual(result, {id: "perfil_teste", created: false});
  const doc = db._doc(PATH) ?? {};
  assert.strictEqual(doc.updated_by, CALLER.ra);
  assert.ok(doc.updated_at instanceof admin.firestore.Timestamp);
  assert.notStrictEqual(
    (doc.updated_at as admin.firestore.Timestamp).toMillis(),
    STORED_T1,
    "EDIT deve avançar updated_at",
  );
  const trail = doc.audit_trail as JsonMap[];
  assert.strictEqual(
    trail[trail.length - 1].action,
    "updated",
    "trilha de EDIT registra `updated`",
  );
}

async function testEditRejectsProfileWithoutCanonicalUpdatedAt(): Promise<void> {
  // Documento legado sem `updated_at` canônico: sem before-image comparável,
  // não há como provar que a edição não é um stale write.
  for (const [label, value] of [
    ["ausente", undefined],
    ["número", STORED_T1],
    ["string ISO", "2026-08-22T00:00:00Z"],
    ["null", null],
  ] as Array<[string, unknown]>) {
    const stored = storedProfile();
    if (value === undefined) delete stored.updated_at;
    else stored.updated_at = value;
    const db = createFakeDb({[PATH]: stored});
    const deps = createDeps(db);
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
          deps,
        ),
      "failed-precondition",
      `EDIT updated_at ${label}`,
    );
    assertZeroWrites(db, `EDIT updated_at ${label}`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §10 — TOCTOU: AUTHORIZED_OPERATION === EXECUTED_OPERATION
// ─────────────────────────────────────────────────────────────────────────────

async function testToctouCaseAAbsentStaysAbsent(): Promise<void> {
  // CASO A: pré-auth ABSENT → autoriza create → transação ABSENT → CREATE ok.
  const db = createFakeDb();
  const deps = createDeps(db);
  const result = await runAdminSaveAccessProfile(
    makeRequest({profile: sourceProfile()}),
    deps,
  );
  assert.strictEqual(result.created, true);
  assert.deepStrictEqual(deps._authCalls(), [{moduleId: "access", action: "create"}]);
  assert.strictEqual(db._writes().length, 1);
}

async function testToctouCaseBPresentStaysPresent(): Promise<void> {
  // CASO B: pré-auth PRESENT → autoriza edit → transação PRESENT → EDIT ok.
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  const result = await runAdminSaveAccessProfile(
    makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
    deps,
  );
  assert.strictEqual(result.created, false);
  assert.deepStrictEqual(deps._authCalls(), [{moduleId: "access", action: "edit"}]);
  assert.strictEqual(db._writes().length, 1);
}

async function testToctouCaseCCreateAuthorityCannotEdit(): Promise<void> {
  // CASO C: pré-auth ABSENT (autoriza create); outro processo CRIA o documento
  // na janela. Autoridade de CREATE não pode executar um EDIT.
  const db = createFakeDb();
  const deps = createDeps(db);
  db._onceAfterGet(PATH, () => {
    db._store.set(PATH, storedProfile());
  });
  const error = await expectHttpsError(
    () => runAdminSaveAccessProfile(makeRequest({profile: sourceProfile()}), deps),
    "failed-precondition",
    "TOCTOU C (create→edit)",
  );
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "create"}],
    "a operação autorizada permanece create",
  );
  const details = error.details as JsonMap;
  assert.strictEqual(details.code, "profile-operation-changed");
  assert.strictEqual(details.expected, "create");
  assert.strictEqual(details.actual, "edit");
  assertZeroWrites(db, "TOCTOU C");
}

async function testToctouCaseDEditAuthorityCannotCreate(): Promise<void> {
  // CASO D: pré-auth PRESENT (autoriza edit); o documento DESAPARECE na janela.
  // Autoridade de EDIT não pode executar um CREATE.
  const db = createFakeDb({[PATH]: storedProfile()});
  const deps = createDeps(db);
  db._onceAfterGet(PATH, () => {
    db._store.delete(PATH);
  });
  const error = await expectHttpsError(
    () =>
      runAdminSaveAccessProfile(
        makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
        deps,
      ),
    "failed-precondition",
    "TOCTOU D (edit→create)",
  );
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "edit"}],
    "a operação autorizada permanece edit",
  );
  const details = error.details as JsonMap;
  assert.strictEqual(details.code, "profile-operation-changed");
  assert.strictEqual(details.expected, "edit");
  assert.strictEqual(details.actual, "create");
  assertZeroWrites(db, "TOCTOU D");
}

async function testToctouInvariantAuthorizedEqualsExecuted(): Promise<void> {
  // Invariante de regressão explícito, cobrindo as quatro combinações.
  const scenarios: Array<{
    label: string;
    preExists: boolean;
    duringExists: boolean;
    expectAction: AccessProfileAction;
    expectSuccess: boolean;
  }> = [
    {label: "A", preExists: false, duringExists: false, expectAction: "create", expectSuccess: true},
    {label: "B", preExists: true, duringExists: true, expectAction: "edit", expectSuccess: true},
    {label: "C", preExists: false, duringExists: true, expectAction: "create", expectSuccess: false},
    {label: "D", preExists: true, duringExists: false, expectAction: "edit", expectSuccess: false},
  ];
  for (const s of scenarios) {
    const db = createFakeDb(s.preExists ? {[PATH]: storedProfile()} : {});
    const deps = createDeps(db);
    if (s.preExists !== s.duringExists) {
      db._onceAfterGet(PATH, () => {
        if (s.duringExists) db._store.set(PATH, storedProfile());
        else db._store.delete(PATH);
      });
    }
    const data: JsonMap = {profile: sourceProfile()};
    if (s.preExists) data.expectedUpdatedAt = STORED_T1;
    let failed = false;
    try {
      await runAdminSaveAccessProfile(makeRequest(data), deps);
    } catch {
      failed = true;
    }
    assert.strictEqual(
      failed,
      !s.expectSuccess,
      `caso ${s.label}: sucesso/falha divergente do contrato`,
    );
    const calls = deps._authCalls();
    assert.strictEqual(calls.length, 1, `caso ${s.label}: uma única autorização`);
    assert.strictEqual(
      calls[0].action,
      s.expectAction,
      `caso ${s.label}: AUTHORIZED_OPERATION divergente`,
    );
    if (!s.expectSuccess) assertZeroWrites(db, `caso ${s.label}`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §11 — CONCORRÊNCIA STALE (sem last-write-wins)
// ─────────────────────────────────────────────────────────────────────────────

async function testStaleConcurrencyNoLastWriteWins(): Promise<void> {
  const db = createFakeDb({[PATH]: storedProfile()});
  const depsA = createDeps(db);
  const depsB = createDeps(db);

  // Editor A e Editor B leem a MESMA before-image T1.
  // A revoga health.read e commita, produzindo T2.
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({permissions: {health: {read: false}}}),
    }),
    depsA,
  );
  const afterA = db._doc(PATH) ?? {};
  const t2 = (afterA.updated_at as admin.firestore.Timestamp).toMillis();
  assert.notStrictEqual(t2, STORED_T1, "A deve avançar updated_at para T2");
  assert.ok(
    !("read" in (permissionsOf(db).health as JsonMap)),
    "A revogou health.read",
  );
  const writesAfterA = db._writes().length;

  // B ainda segura T1 e tentaria restaurar health.read — exatamente o stale
  // write que reintroduziria silenciosamente uma capability revogada.
  await expectHttpsError(
    () =>
      runAdminSaveAccessProfile(
        makeRequest({
          expectedUpdatedAt: STORED_T1,
          profile: sourceProfile({permissions: {health: {read: true}}}),
        }),
        depsB,
      ),
    "failed-precondition",
    "editor B stale",
  );
  assertZeroWrites(db, "editor B stale", writesAfterA);
  assert.ok(
    !("read" in (permissionsOf(db).health as JsonMap)),
    "a revogação de A deve sobreviver: nada de last-write-wins",
  );

  // Com a before-image correta (T2), B passa.
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: t2,
      profile: sourceProfile({permissions: {health: {read: true}}}),
    }),
    depsB,
  );
  assert.strictEqual((permissionsOf(db).health as JsonMap).read, true);
}

// ─────────────────────────────────────────────────────────────────────────────
// §12 — ASSERÇÕES DE ZERO WRITE (exceção sozinha não é prova)
// ─────────────────────────────────────────────────────────────────────────────

async function testZeroWriteFailurePaths(): Promise<void> {
  const cases: Array<{
    label: string;
    stored?: JsonMap;
    data: JsonMap;
    code: string;
    mutate?: (db: ReturnType<typeof createFakeDb>) => void;
    // Tamanho esperado do store ao final. Por padrão é o inicial: nas falhas
    // "puras" o writer sob teste não pode ganhar/perder documentos. Nas duas
    // corridas TOCTOU, o `_onceAfterGet` simula OUTRO writer mutando o store na
    // janela — essa mudança é legítima e não é escrita do writer sob teste
    // (provado por `assertZeroWrites`, pois o hook escreve direto no Map).
    finalSize?: number;
  }> = [
    {
      label: "capability inválida",
      stored: storedProfile(),
      data: {
        expectedUpdatedAt: STORED_T1,
        profile: sourceProfile({permissions: {health: {bogus: true}}}),
      },
      code: "invalid-argument",
    },
    {
      label: "permissão null",
      stored: storedProfile(),
      data: {
        expectedUpdatedAt: STORED_T1,
        profile: sourceProfile({permissions: {health: {read: null}}}),
      },
      code: "invalid-argument",
    },
    {
      label: "permissão não-booleana",
      stored: storedProfile(),
      data: {
        expectedUpdatedAt: STORED_T1,
        profile: sourceProfile({permissions: {health: {read: "true"}}}),
      },
      code: "invalid-argument",
    },
    {
      label: "EDIT sem expectedUpdatedAt",
      stored: storedProfile(),
      data: {profile: sourceProfile()},
      code: "invalid-argument",
    },
    {
      label: "EDIT expectedUpdatedAt malformado",
      stored: storedProfile(),
      data: {expectedUpdatedAt: "ontem", profile: sourceProfile()},
      code: "invalid-argument",
    },
    {
      label: "EDIT expectedUpdatedAt stale",
      stored: storedProfile(),
      data: {expectedUpdatedAt: STORED_T1 - 5, profile: sourceProfile()},
      code: "failed-precondition",
    },
    {
      label: "CREATE com expectedUpdatedAt",
      data: {expectedUpdatedAt: STORED_T1, profile: sourceProfile()},
      code: "invalid-argument",
    },
    {
      label: "corrida CREATE→EDIT",
      data: {profile: sourceProfile()},
      code: "failed-precondition",
      mutate: (db) => db._onceAfterGet(PATH, () => db._store.set(PATH, storedProfile())),
      // O writer autorizado como CREATE aborta; o documento que passou a
      // existir na janela (escrito pelo hook, não pelo writer) permanece.
      finalSize: 1,
    },
    {
      label: "corrida EDIT→CREATE",
      stored: storedProfile(),
      data: {expectedUpdatedAt: STORED_T1, profile: sourceProfile()},
      code: "failed-precondition",
      mutate: (db) => db._onceAfterGet(PATH, () => db._store.delete(PATH)),
      // O writer autorizado como EDIT aborta; o documento removido na janela
      // (pelo hook, não pelo writer) permanece removido.
      finalSize: 0,
    },
    {
      label: "scope ausente",
      data: {profile: {id: "perfil_teste", name: "Perfil Teste"}},
      code: "invalid-argument",
    },
    {
      label: "name ausente",
      data: {profile: {id: "perfil_teste", scope: "global"}},
      code: "invalid-argument",
    },
    {
      label: "id com caracteres inválidos",
      data: {profile: sourceProfile({id: "perfil/teste"})},
      code: "invalid-argument",
    },
  ];

  for (const item of cases) {
    const db = createFakeDb(item.stored ? {[PATH]: item.stored} : {});
    const deps = createDeps(db);
    if (item.mutate) item.mutate(db);
    await expectHttpsError(
      () => runAdminSaveAccessProfile(makeRequest(item.data), deps),
      item.code,
      item.label,
    );
    assertZeroWrites(db, item.label);
    assert.strictEqual(
      db._store.size,
      item.finalSize ?? (item.stored ? 1 : 0),
      `${item.label}: o store divergiu do esperado`,
    );
  }
}

async function testAuthorizationDeniedWritesNothing(): Promise<void> {
  // A autorização é consultada ANTES de qualquer escrita.
  for (const stored of [undefined, storedProfile()]) {
    const db = createFakeDb(stored ? {[PATH]: stored} : {});
    const deps = createDeps(db, {deny: true});
    const data: JsonMap = {profile: sourceProfile()};
    if (stored) data.expectedUpdatedAt = STORED_T1;
    await expectHttpsError(
      () => runAdminSaveAccessProfile(makeRequest(data), deps),
      "permission-denied",
      "autorização negada",
    );
    assertZeroWrites(db, "autorização negada");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// §13 — seed_version SERVER-MANAGED
// ─────────────────────────────────────────────────────────────────────────────

async function testSeedVersionIsServerManaged(): Promise<void> {
  // Cliente desatualizado tentando regredir a versão de seed.
  const db = createFakeDb({[PATH]: storedProfile({seed_version: 6})});
  const deps = createDeps(db);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({seed_version: 99}),
    }),
    deps,
  );
  assert.strictEqual(
    (db._doc(PATH) ?? {}).seed_version,
    6,
    "EDIT deve usar o seed_version ARMAZENADO, não o do cliente",
  );

  // Omissão preserva o armazenado.
  const db2 = createFakeDb({[PATH]: storedProfile({seed_version: 6})});
  const deps2 = createDeps(db2);
  await runAdminSaveAccessProfile(
    makeRequest({expectedUpdatedAt: STORED_T1, profile: sourceProfile()}),
    deps2,
  );
  assert.strictEqual((db2._doc(PATH) ?? {}).seed_version, 6);

  // Perfil existente sem seed_version → 0 (nunca undefined/NaN).
  const stored3 = storedProfile();
  delete stored3.seed_version;
  const db3 = createFakeDb({[PATH]: stored3});
  const deps3 = createDeps(db3);
  await runAdminSaveAccessProfile(
    makeRequest({
      expectedUpdatedAt: STORED_T1,
      profile: sourceProfile({seed_version: 42}),
    }),
    deps3,
  );
  assert.strictEqual((db3._doc(PATH) ?? {}).seed_version, 0);

  // CREATE manual → server-managed 0, qualquer que seja o valor do cliente.
  // O CREATE manual não pode fabricar proveniência de seed.
  const db4 = createFakeDb();
  const deps4 = createDeps(db4);
  await runAdminSaveAccessProfile(
    makeRequest({profile: sourceProfile({seed_version: 7})}),
    deps4,
  );
  assert.strictEqual((db4._doc(PATH) ?? {}).seed_version, 0);

  // CREATE manual com a versão canônica vigente também → 0 (o vetor exato do
  // defeito: o cliente enviando a versão de seed "correta" para se passar por
  // sincronizado).
  const db5 = createFakeDb();
  const deps5 = createDeps(db5);
  await runAdminSaveAccessProfile(
    makeRequest({profile: sourceProfile({seed_version: 6})}),
    deps5,
  );
  assert.strictEqual((db5._doc(PATH) ?? {}).seed_version, 0);

  // CREATE manual sem seed_version → 0.
  const db6 = createFakeDb();
  const deps6 = createDeps(db6);
  await runAdminSaveAccessProfile(makeRequest({profile: sourceProfile()}), deps6);
  assert.strictEqual((db6._doc(PATH) ?? {}).seed_version, 0);
}

async function testSeederRetainsSeedVersionAuthority(): Promise<void> {
  // O seeder NÃO passa storedSeedVersion: ele é a autoridade que avança a
  // versão. Se fosse forçado pelo comportamento de adminSave, a reconciliação
  // de seed nunca conseguiria sair de uma versão antiga.
  const db = createFakeDb({
    "access_profiles/gestor": storedProfile({id: "gestor", seed_version: 3}),
  });
  const deps = createDeps(db);
  await runAdminSeedAccessProfiles(
    makeRequest({
      reconcile: false,
      profiles: [
        {id: "gestor", name: "Gestor", scope: "global", seed_version: 6},
      ],
    }),
    deps,
  );
  assert.strictEqual(
    (db._doc("access_profiles/gestor") ?? {}).seed_version,
    6,
    "o seeder deve poder AVANÇAR seed_version de 3 para 6",
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// §14 — DUPLICAÇÃO
// ─────────────────────────────────────────────────────────────────────────────

async function testDuplicateSafety(): Promise<void> {
  const db = createFakeDb();
  const deps = createDeps(db);
  const result = await runAdminDuplicateAccessProfile(
    makeRequest({
      id: "perfil_copia",
      profile: sourceProfile({
        name: "Perfil Origem",
        permissions: {health: {view: true, read: true, archive: false}},
      }),
    }),
    deps,
  );
  assert.deepStrictEqual(result, {id: "perfil_copia"});
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "create"}],
    "duplicar exige access.create",
  );
  const written = lastWrite(db);
  assert.strictEqual(written.merge, false, "duplicação escreve sem merge");
  assert.ok(
    !hasDeleteSentinelDeep(written.data),
    "nenhum sentinel de delete pode entrar numa escrita sem merge",
  );
  const doc = db._doc("access_profiles/perfil_copia") ?? {};
  assert.strictEqual(doc.status, "inactive", "a cópia nasce inativa");
  assert.strictEqual(doc.name, "Perfil Origem (copia)");
  assert.strictEqual(doc.slug, "perfil_copia");
  const health = (doc.permissions as JsonMap).health as JsonMap;
  assert.strictEqual(health.view, true, "capability true é incluída");
  assert.strictEqual(health.read, true);
  assert.ok(!("archive" in health), "capability false é omitida, sem sentinel");
}

/**
 * CLIN-AUTH-BE-4A.I2.R1 — prova que o fix do CREATE manual NÃO virou
 * "seed_version = 0 em todo lugar".
 *
 * Três callers omitem `storedSeedVersion` no helper compartilhado; se o fix
 * tivesse sido aplicado no DEFAULT do helper em vez do call site do CREATE,
 * duplicate e seeder passariam a gravar 0 e a autoridade canônica de seed
 * morreria silenciosamente. Este teste falha nesse cenário.
 */
async function testSeedVersionFixDidNotLeakToOtherWriters(): Promise<void> {
  // DUPLICATE mantém a semântica congelada: deriva do perfil de origem.
  const db = createFakeDb();
  const deps = createDeps(db);
  await runAdminDuplicateAccessProfile(
    makeRequest({
      id: "perfil_copia",
      profile: sourceProfile({name: "Perfil Origem", seed_version: 6}),
    }),
    deps,
  );
  assert.strictEqual(
    (db._doc("access_profiles/perfil_copia") ?? {}).seed_version,
    6,
    "duplicate NÃO deve ser forçado a 0 pelo fix do CREATE manual",
  );

  // SEEDER mantém autoridade em documento NOVO (não só ao avançar existente).
  const db2 = createFakeDb();
  const deps2 = createDeps(db2);
  await runAdminSeedAccessProfiles(
    makeRequest({
      reconcile: false,
      profiles: [{id: "gestor", name: "Gestor", scope: "global", seed_version: 6}],
    }),
    deps2,
  );
  assert.strictEqual(
    (db2._doc("access_profiles/gestor") ?? {}).seed_version,
    6,
    "seeder criando perfil novo continua afirmando sua versão canônica",
  );
}

async function testDuplicateCollisionFailsClosed(): Promise<void> {
  const db = createFakeDb({
    "access_profiles/perfil_copia": storedProfile({id: "perfil_copia"}),
  });
  const deps = createDeps(db);
  await expectHttpsError(
    () =>
      runAdminDuplicateAccessProfile(
        makeRequest({id: "perfil_copia", profile: sourceProfile()}),
        deps,
      ),
    "already-exists",
    "colisão de destino",
  );
  assertZeroWrites(db, "colisão de destino");
  // O documento existente permanece intacto.
  assert.strictEqual((db._doc("access_profiles/perfil_copia") ?? {}).status, "active");
}

async function testDuplicateRejectsInvalidCapability(): Promise<void> {
  const db = createFakeDb();
  const deps = createDeps(db);
  await expectHttpsError(
    () =>
      runAdminDuplicateAccessProfile(
        makeRequest({
          id: "perfil_copia",
          profile: sourceProfile({permissions: {me: {manage_nutrition_plan: true}}}),
        }),
        deps,
      ),
    "invalid-argument",
    "duplicação com par cruzado",
  );
  assertZeroWrites(db, "duplicação com par cruzado");
}

// ─────────────────────────────────────────────────────────────────────────────
// SEED / RECONCILE (caminho do seeder, sem rede)
// ─────────────────────────────────────────────────────────────────────────────

async function testSeedReconcile(): Promise<void> {
  const db = createFakeDb({
    "access_profiles/gestor": storedProfile({id: "gestor", seed_version: 3}),
    "access_profiles/obsoleto": storedProfile({id: "obsoleto", status: "active"}),
    "access_profiles/ja_inativo": storedProfile({id: "ja_inativo", status: "inactive"}),
  });
  const deps = createDeps(db);
  const result = await runAdminSeedAccessProfiles(
    makeRequest({
      profiles: [
        {id: "gestor", name: "Gestor", scope: "global", seed_version: 6},
        {id: "novo", name: "Novo", scope: "own_records", seed_version: 6},
      ],
    }),
    deps,
  );
  assert.deepStrictEqual(
    deps._authCalls(),
    [{moduleId: "access", action: "approve"}],
    "seed exige access.approve",
  );
  assert.deepStrictEqual(result.created, ["novo"]);
  assert.deepStrictEqual(result.updated, ["gestor"]);
  assert.deepStrictEqual(
    result.archived,
    ["obsoleto"],
    "apenas o perfil ativo fora do seed é inativado",
  );
  assert.strictEqual(
    (db._doc("access_profiles/obsoleto") ?? {}).deprecated_by_seed,
    true,
  );
  assert.strictEqual(
    (db._doc("access_profiles/ja_inativo") ?? {}).deprecated_by_seed,
    undefined,
    "perfil já inativo não é reescrito",
  );
  // Log de auditoria da reconciliação.
  const auditWrites = db._writes().filter((w) => w.path.startsWith("auditLogs/"));
  assert.strictEqual(auditWrites.length, 1);
  assert.strictEqual(auditWrites[0].data.action, "access_profiles_seeded");
}

async function testSeedRejectsEmptyAndInvalid(): Promise<void> {
  for (const [label, data] of [
    ["profiles vazio", {profiles: []}],
    ["profiles ausente", {}],
    ["profiles não-array", {profiles: "gestor"}],
  ] as Array<[string, JsonMap]>) {
    const db = createFakeDb();
    const deps = createDeps(db);
    await expectHttpsError(
      () => runAdminSeedAccessProfiles(makeRequest(data), deps),
      "invalid-argument",
      label,
    );
    assertZeroWrites(db, label);
  }
  // Capability inválida no seed também falha fechado, sem escrita parcial.
  const db = createFakeDb();
  const deps = createDeps(db);
  await expectHttpsError(
    () =>
      runAdminSeedAccessProfiles(
        makeRequest({
          profiles: [
            {id: "ok", name: "Ok", scope: "global"},
            {
              id: "ruim",
              name: "Ruim",
              scope: "global",
              permissions: {vehicles: {record_routine: true}},
            },
          ],
        }),
        deps,
      ),
    "invalid-argument",
    "seed com par cruzado",
  );
  assertZeroWrites(db, "seed com par cruzado");
}

// ─────────────────────────────────────────────────────────────────────────────
// §15 — REGRESSÃO DO LADO DE LEITURA
// ─────────────────────────────────────────────────────────────────────────────

async function testReadSideRegression(): Promise<void> {
  assert.strictEqual(
    profileGrantsPermission(
      {status: "active", permissions: {health: {read: true}}},
      "health",
      "read",
    ),
    true,
    "true armazenado concede",
  );
  assert.strictEqual(
    profileGrantsPermission(
      {status: "active", permissions: {health: {read: false}}},
      "health",
      "read",
    ),
    false,
    "false armazenado não concede",
  );
  for (const malformed of ["true", 1, {}, [], null, "yes"]) {
    assert.strictEqual(
      profileGrantsPermission(
        {status: "active", permissions: {health: {read: malformed}}},
        "health",
        "read",
      ),
      false,
      `valor malformado ${JSON.stringify(malformed)} não pode conceder`,
    );
  }
  // O sanitizer de LEITURA não lança diante de dados que o lado de ESCRITA
  // recusaria. Se lançasse, um documento legado tornaria a autoridade
  // inavaliável — falha aberta ou indisponibilidade, nunca decisão limpa.
  const legacy: JsonMap = {
    status: "active",
    permissions: {
      bogus_module: {read: true},
      health: {read: "true", view: true},
      me: {manage_nutrition_plan: true},
    },
  };
  assert.strictEqual(profileGrantsPermission(legacy, "health", "read"), false);
  assert.strictEqual(profileGrantsPermission(legacy, "health", "view"), true);

  // ASSIMETRIA LEITURA/ESCRITA (ver ACHADO 1 no relatório) — caracterizada,
  // não corrigida. O caminho de ESCRITA valida a chave COMO VEIO e recusa
  // `health.Read`; o caminho de LEITURA NORMALIZA a chave (lowercase, acentos,
  // não-alfanuméricos) antes de comparar. Logo um documento legado com uma
  // variante de caixa CONCEDE health.read, embora o writer atual jamais
  // pudesse produzi-lo. Comportamento idêntico ao baseline HEAD.
  for (const variant of ["Read", "READ", " read ", "__read__"]) {
    assert.strictEqual(
      profileGrantsPermission(
        {status: "active", permissions: {health: {[variant]: true}}},
        "health",
        "read",
      ),
      true,
      `LEITURA normaliza ${JSON.stringify(variant)} para read (vigente)`,
    );
    await expectHttpsError(
      () =>
        runAdminSaveAccessProfile(
          makeRequest({
            expectedUpdatedAt: STORED_T1,
            profile: sourceProfile({permissions: {health: {[variant]: true}}}),
          }),
          createDeps(createFakeDb({[PATH]: storedProfile()})),
        ),
      "invalid-argument",
      `ESCRITA recusa ${JSON.stringify(variant)}`,
    );
  }
  // Perfil inativo nunca concede, mesmo com a capability presente.
  assert.strictEqual(
    profileGrantsPermission(
      {status: "inactive", permissions: {health: {read: true}}},
      "health",
      "read",
    ),
    false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// §16 — REGRESSÃO DE ESCOPO (nunca virar global por omissão/typo)
// ─────────────────────────────────────────────────────────────────────────────

async function testScopeNeverBecomesGlobal(): Promise<void> {
  const invalid: Array<[string, unknown]> = [
    ["ausente", undefined],
    ["vazio", ""],
    ["ownRecords", "ownRecords"],
    ["GLOBAL", "GLOBAL"],
    ["null", null],
    ["número", 1],
    ["objeto", {}],
    ["own-records", "own-records"],
  ];
  for (const [label, value] of invalid) {
    const db = createFakeDb();
    const deps = createDeps(db);
    const profile: JsonMap = {id: "perfil_teste", name: "Perfil Teste"};
    if (value !== undefined) profile.scope = value;
    const error = await expectHttpsError(
      () => runAdminSaveAccessProfile(makeRequest({profile}), deps),
      "invalid-argument",
      `scope ${label}`,
    );
    assert.strictEqual(
      (error.details as JsonMap).code,
      "invalid-access-scope",
      `scope ${label}: erro estruturado esperado`,
    );
    assertZeroWrites(db, `scope ${label}`);
    assert.strictEqual(
      db._doc(PATH),
      undefined,
      `scope ${label}: nada pode ser persistido como global`,
    );
  }
  // Os dois valores canônicos passam e são gravados literalmente.
  for (const scope of ["global", "own_records"]) {
    const db = createFakeDb();
    const deps = createDeps(db);
    await runAdminSaveAccessProfile(
      makeRequest({profile: sourceProfile({scope})}),
      deps,
    );
    assert.strictEqual((db._doc(PATH) ?? {}).scope, scope);
  }
  // Escopo inválido também bloqueia duplicação e seed.
  const dbDup = createFakeDb();
  await expectHttpsError(
    () =>
      runAdminDuplicateAccessProfile(
        makeRequest({
          id: "perfil_copia",
          profile: {id: "perfil_teste", name: "Origem", scope: "ownRecords"},
        }),
        createDeps(dbDup),
      ),
    "invalid-argument",
    "duplicação com scope inválido",
  );
  assertZeroWrites(dbDup, "duplicação com scope inválido");

  const dbSeed = createFakeDb();
  await expectHttpsError(
    () =>
      runAdminSeedAccessProfiles(
        makeRequest({profiles: [{id: "gestor", name: "Gestor", scope: "Global"}]}),
        createDeps(dbSeed),
      ),
    "invalid-argument",
    "seed com scope inválido",
  );
  assertZeroWrites(dbSeed, "seed com scope inválido");
}

// ─────────────────────────────────────────────────────────────────────────────
// §17 — CONTRATO DE CÓDIGOS DE ERRO (asserção por código, não por mensagem)
// ─────────────────────────────────────────────────────────────────────────────

async function testErrorCodeContract(): Promise<void> {
  const expectations: Array<[string, string, JsonMap, JsonMap | undefined]> = [
    [
      "permissão inválida",
      "invalid-argument",
      {
        expectedUpdatedAt: STORED_T1,
        profile: sourceProfile({permissions: {health: {read: 1}}}),
      },
      storedProfile(),
    ],
    [
      "capability inválida",
      "invalid-argument",
      {
        expectedUpdatedAt: STORED_T1,
        profile: sourceProfile({permissions: {health: {nope: true}}}),
      },
      storedProfile(),
    ],
    [
      "EDIT sem expectedUpdatedAt",
      "invalid-argument",
      {profile: sourceProfile()},
      storedProfile(),
    ],
    [
      "CREATE com expectedUpdatedAt",
      "invalid-argument",
      {expectedUpdatedAt: STORED_T1, profile: sourceProfile()},
      undefined,
    ],
    [
      "stale",
      "failed-precondition",
      {expectedUpdatedAt: STORED_T1 - 1, profile: sourceProfile()},
      storedProfile(),
    ],
  ];
  for (const [label, code, data, stored] of expectations) {
    const db = createFakeDb(stored ? {[PATH]: stored} : {});
    await expectHttpsError(
      () => runAdminSaveAccessProfile(makeRequest(data), createDeps(db)),
      code,
      label,
    );
  }
  // "operação mudou" é failed-precondition COM sentinel estruturado.
  const db = createFakeDb();
  db._onceAfterGet(PATH, () => db._store.set(PATH, storedProfile()));
  const error = await expectHttpsError(
    () =>
      runAdminSaveAccessProfile(makeRequest({profile: sourceProfile()}), createDeps(db)),
    "failed-precondition",
    "operação mudou",
  );
  assert.strictEqual((error.details as JsonMap).code, "profile-operation-changed");
}

// ─────────────────────────────────────────────────────────────────────────────

const tests: Array<[string, () => Promise<void>]> = [
  ["tri-state: omitido preserva", testTriStateOmittedPreserves],
  ["tri-state: true permanece true", testTriStateTrueStaysTrue],
  ["tri-state: false revoga em merge", testTriStateFalseRevokesInMerge],
  ["tri-state: false omite em create/replace", testTriStateFalseOmittedInCreate],
  ["tri-state: não-booleano recusado", testTriStateNonBooleanRejected],
  ["tri-state: mapas malformados recusados", testTriStateMalformedPermissionMaps],
  ["capability: pares aceitos", testCapabilityPairsAccepted],
  ["capability: pares recusados", testCapabilityPairsRejected],
  ["capability: módulo+ação conhecidos não bastam", testKnownModuleAndActionIsNotEnough],
  ["seed v6: matriz compatível", testSeedMatrixCompatibility],
  ["clínico: definido mas não concedido", testClinicalCapabilitiesDefinedButNotGranted],
  ["clínico: typo falha fechado", testClinicalCapabilityTypoFailsClosed],
  ["clínico: exige concessão explícita", testClinicalCapabilityRequiresExplicitGrant],
  ["CREATE: sucesso sem expectedUpdatedAt", testCreateSucceedsWithoutExpectedUpdatedAt],
  ["CREATE: expectedUpdatedAt proibido", testCreateRejectsExpectedUpdatedAt],
  ["EDIT: expectedUpdatedAt obrigatório", testEditRequiresExpectedUpdatedAt],
  ["EDIT: expectedUpdatedAt malformado", testEditRejectsMalformedExpectedUpdatedAt],
  ["EDIT: stale recusado", testEditStaleIsRejected],
  ["EDIT: timestamp exato aceito", testEditExactTimestampSucceeds],
  ["EDIT: updated_at não canônico falha fechado", testEditRejectsProfileWithoutCanonicalUpdatedAt],
  ["TOCTOU A: absent→absent", testToctouCaseAAbsentStaysAbsent],
  ["TOCTOU B: present→present", testToctouCaseBPresentStaysPresent],
  ["TOCTOU C: create não executa edit", testToctouCaseCCreateAuthorityCannotEdit],
  ["TOCTOU D: edit não executa create", testToctouCaseDEditAuthorityCannotCreate],
  ["TOCTOU: AUTHORIZED === EXECUTED", testToctouInvariantAuthorizedEqualsExecuted],
  ["concorrência: sem last-write-wins", testStaleConcurrencyNoLastWriteWins],
  ["zero write: caminhos de falha", testZeroWriteFailurePaths],
  ["zero write: autorização negada", testAuthorizationDeniedWritesNothing],
  ["seed_version: server-managed", testSeedVersionIsServerManaged],
  ["seed_version: seeder retém autoridade", testSeederRetainsSeedVersionAuthority],
  ["seed_version: fix não vazou para outros writers", testSeedVersionFixDidNotLeakToOtherWriters],
  ["duplicação: segurança do payload", testDuplicateSafety],
  ["duplicação: colisão falha fechado", testDuplicateCollisionFailsClosed],
  ["duplicação: capability inválida", testDuplicateRejectsInvalidCapability],
  ["seed: reconciliação", testSeedReconcile],
  ["seed: entradas inválidas", testSeedRejectsEmptyAndInvalid],
  ["leitura: regressão do sanitizer", testReadSideRegression],
  ["escopo: nunca vira global", testScopeNeverBecomesGlobal],
  ["contrato de códigos de erro", testErrorCodeContract],
];

(async () => {
  let failures = 0;
  for (const [name, fn] of tests) {
    try {
      await fn();
      console.log(`ok   ${name}`);
    } catch (err) {
      failures += 1;
      console.error(`FAIL ${name}: ${(err as Error).message}`);
    }
  }
  if (failures > 0) {
    console.error(`\n${failures} teste(s) falharam.`);
    process.exit(1);
  }
  console.log(`\n${tests.length} grupos de teste ok.`);
})();
