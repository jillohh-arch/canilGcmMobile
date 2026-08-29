/**
 * Testes dos callables de escrita clínica com fake Firestore.
 * npm run build && node lib/clinical_case_callables_test.js
 *
 * Cobre: identidade determinística, abertura atômica de caso+evento, replay sem
 * duplicação de fato/audit, idempotency-conflict, rejeição de injeção de campos
 * server-managed, negação de capability e de escopo de K9, append em caso
 * terminal, caso inexistente, agregado sem receipt (fail-closed) e mapeamento
 * de erro de domínio.
 */
import * as assert from "assert";
import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import {FieldValue, Timestamp} from "firebase-admin/firestore";

import {
  ClinicalCaller,
  ClinicalCaseCallableDeps,
  canonicalCasePath,
  caseIdentityMaterial,
  deterministicCaseId,
  deterministicEventId,
  eventIdentityMaterial,
  openingEventIdFor,
  runHealthAmendClinicalEvent,
  runHealthAppendClinicalEvent,
  runHealthCancelClinicalCase,
  runHealthCancelClinicalEvent,
  runHealthDischargeClinicalCase,
  runHealthFinalizeClinicalEvent,
  runHealthOpenClinicalCase,
  runHealthReopenClinicalCase,
  runHealthTransitionClinicalCase,
} from "./clinical_case_callables";
import {
  isAdminToken,
  isAdminUserRecord,
  profileGrantsPermission,
} from "./index";

type JsonMap = Record<string, unknown>;

// ── Leitura de fonte para as guardas arquiteturais ───────────────────────────

const SRC_DIR = __dirname.endsWith("lib") ?
  path.join(__dirname, "..", "src") :
  __dirname;

function readSource(relative: string): string {
  return fs.readFileSync(path.join(SRC_DIR, relative), "utf8");
}

/** Remove comentários, para que uma menção explicativa não gere falso positivo. */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

const actor: ClinicalCaller = {
  uid: "uid-clin",
  email: "691755@gcm.com.br",
  ra: "691755",
  name: "Operador Clínico",
};

const actorB: ClinicalCaller = {
  uid: "uid-clin-b",
  email: "691756@gcm.com.br",
  ra: "691756",
  name: "Operador Clínico B",
};

const FIXED_NOW = new Date("2026-08-15T12:00:00.000Z");

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

function caseIdFor(dogId: string, operationId: string): string {
  return deterministicCaseId(sha256Hex(caseIdentityMaterial(dogId, operationId)));
}

function eventIdFor(dogId: string, caseId: string, operationId: string): string {
  return deterministicEventId(
    sha256Hex(eventIdentityMaterial(dogId, caseId, operationId)),
  );
}

// ── Fake Firestore ───────────────────────────────────────────────────────────

function isDeleteSentinel(val: unknown): boolean {
  if (!val || typeof val !== "object") return false;
  if (typeof (val as {isEqual?: unknown}).isEqual === "function") {
    try {
      if ((val as {isEqual: (other: unknown) => boolean}).isEqual(FieldValue.delete())) return true;
    } catch (_) {}
  }
  return false;
}

/**
 * Fake com concorrência otimista real: rastreia versões dos paths lidos e
 * reexecuta a transação se algum mudar antes do commit. `set` suporta a opção
 * `{merge: true}` — o append da contagem depende dela para NÃO sobrescrever o
 * `clinical_status` do caso. Sentinelas de `FieldValue` são armazenadas opacas
 * (os testes não asseguram seus valores resolvidos).
 */
function createFakeDb(initial: Record<string, JsonMap> = {}) {
  const store = new Map<string, JsonMap>();
  const versions = new Map<string, number>();
  for (const [k, v] of Object.entries(initial)) store.set(k, {...v});

  let transactions = 0;

  function makeDocRef(parts: string[]) {
    const path = parts.join("/");
    return {
      path,
      id: parts[parts.length - 1],
      collection(c: string) {
        return {doc: (id: string) => makeDocRef([...parts, c, id])};
      },
      async get() {
        const data = store.get(path);
        return {exists: data !== undefined, data: () => ({...(data ?? {})})};
      },
    };
  }

  const db = {
    collection(col: string) {
      return {
        doc(id?: string) {
          return makeDocRef([col, id ?? `auto_${store.size + 1}`]);
        },
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{
          exists: boolean;
          data: () => JsonMap;
        }>;
        set: (
          ref: {path: string},
          data: JsonMap,
          options?: {merge?: boolean},
        ) => void;
        update: (ref: {path: string}, data: JsonMap) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const maxAttempts = 5;
      for (let attempt = 1; ; attempt += 1) {
        transactions += 1;
        const pending = new Map<string, JsonMap>();
        const readVersions = new Map<string, number>();
        const tx = {
          async get(ref: {path: string}) {
            if (!readVersions.has(ref.path)) {
              readVersions.set(ref.path, versions.get(ref.path) ?? 0);
            }
            const data = pending.get(ref.path) ?? store.get(ref.path);
            return {
              exists: data !== undefined,
              data: () => ({...(data ?? {})}),
            };
          },
          set(
            ref: {path: string},
            data: JsonMap,
            options?: {merge?: boolean},
          ) {
            const prev = options?.merge
              ? pending.get(ref.path) ?? store.get(ref.path) ?? {}
              : {};
            const next = {...prev};
            for (const [k, v] of Object.entries(data)) {
              if (isDeleteSentinel(v) || v === undefined) {
                delete next[k];
              } else {
                next[k] = v;
              }
            }
            pending.set(ref.path, next);
          },
          update(ref: {path: string}, data: JsonMap) {
            const prev = pending.get(ref.path) ?? store.get(ref.path);
            if (!prev) throw new Error(`Document not found for update: ${ref.path}`);
            const next = {...prev};
            for (const [k, v] of Object.entries(data)) {
              if (isDeleteSentinel(v) || v === undefined) {
                delete next[k];
              } else {
                next[k] = v;
              }
            }
            pending.set(ref.path, next);
          },
        };
        const result = await fn(tx);
        await new Promise((resolve) => setImmediate(resolve));
        let stale = false;
        for (const [path, version] of readVersions.entries()) {
          if ((versions.get(path) ?? 0) !== version) {
            stale = true;
            break;
          }
        }
        if (stale) {
          if (attempt >= maxAttempts) {
            throw new Error("transaction: too many retries");
          }
          continue;
        }
        for (const [k, v] of pending.entries()) {
          store.set(k, v);
          versions.set(k, (versions.get(k) ?? 0) + 1);
        }
        return result;
      }
    },
    _store: store,
    _transactions: () => transactions,
  };
  return db as unknown as FirebaseFirestore.Firestore & {
    _store: Map<string, JsonMap>;
    _transactions: () => number;
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mockRequest(data: JsonMap, auth: any = {uid: actor.uid, token: {}}): any {
  return {data, auth};
}

/**
 * Cada capability clínica é um gate INDEPENDENTE, exatamente como no wiring real.
 *
 * `allowRecord`/`allowFinalize`/`allowAmend` default `true` e são controlados
 * separadamente: é isso que permite provar que nenhuma capability implica a
 * outra. `now` também é injetável para simular o avanço do relógio entre a
 * criação (T0) e a mutação (T1).
 */
function depsFor(options: {
  db: FirebaseFirestore.Firestore;
  allowRecord?: boolean;
  allowFinalize?: boolean;
  allowAmend?: boolean;
  allowManageCase?: boolean;
  allowReopenCase?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: ClinicalCaller;
  now?: Date;
}): ClinicalCaseCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  const gate = (allowed: boolean | undefined, action: string) => async (
    auth: unknown,
  ): Promise<ClinicalCaller> => {
    if (!auth) throw new HttpsError("unauthenticated", "auth");
    if (allowed === false) {
      throw new HttpsError("permission-denied", `sem health.${action}`, {
        code: "permission-denied",
      });
    }
    return caller;
  };
  return {
    db: options.db,
    now: () => options.now ?? FIXED_NOW,
    requireRecordClinical: gate(options.allowRecord, "record_clinical"),
    requireFinalizeClinical: gate(options.allowFinalize, "finalize_clinical"),
    requireAmendClinical: gate(options.allowAmend, "amend_clinical"),
    requireManageClinicalCase: gate(options.allowManageCase, "manage_clinical_case"),
    requireReopenClinicalCase: gate(options.allowReopenCase, "reopen_clinical_case"),
    requireDogAccess: async () => {
      if (options.dogAccess === false) {
        throw new HttpsError("permission-denied", "sem acesso ao K9", {
          code: "permission-denied",
        });
      }
    },
    isAdministrativeAuthority: async () => options.admin === true,
  };
}

function dbWithDog(extra: Record<string, JsonMap> = {}) {
  return createFakeDb({"dogs/dog-1": {name: "Bono"}, ...extra});
}

const validOpen: JsonMap = {
  dogId: "dog-1",
  operationId: "op-open-1",
  title: "Suspeita de gastrite",
  openingType: "consultation",
  eventType: "consultation",
  occurredAt: "2026-08-15T10:00:00.000Z",
  payloadType: "consultation_v1",
  content: {notes: "vômito intermitente"},
};

function storeKeys(db: {_store: Map<string, JsonMap>}): string[] {
  return [...db._store.keys()].sort();
}

async function expectReject(
  fn: () => Promise<unknown>,
  code: string,
  label: string,
  expectedMessage?: string | RegExp,
) {
  try {
    await fn();
  } catch (err) {
    const details = (err as {details?: {code?: string}}).details;
    assert.strictEqual(
      details?.code,
      code,
      `${label}: code ${details?.code} != ${code}`,
    );
    if (expectedMessage !== undefined) {
      const msg = (err as Error)?.message ?? "";
      if (typeof expectedMessage === "string") {
        assert.strictEqual(
          msg,
          expectedMessage,
          `${label}: message '${msg}' != '${expectedMessage}'`,
        );
      } else {
        assert.match(
          msg,
          expectedMessage,
          `${label}: message '${msg}' does not match ${expectedMessage}`,
        );
      }
    }
    return;
  }
  assert.fail(`${label}: esperava rejeição ${code}`);
}

// ── OPEN CASE ──────────────────────────────────────────────────────────────

async function testOpenSuccess() {
  const db = dbWithDog();
  const deps = depsFor({db});

  const res = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    deps,
  )) as JsonMap;

  const caseId = caseIdFor("dog-1", "op-open-1");
  const eventId = openingEventIdFor(caseId);
  assert.strictEqual(res.case_id, caseId, "caseId determinístico");
  assert.strictEqual(res.opening_event_id, eventId, "openingEventId derivado");
  assert.strictEqual(res.was_no_op, false, "primeira execução não é no-op");

  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  const eventPath = `${casePath}/clinical_events/${eventId}`;
  const caseDoc = db._store.get(casePath) as JsonMap;
  const eventDoc = db._store.get(eventPath) as JsonMap;
  assert.ok(caseDoc, "caso persistido");
  assert.ok(eventDoc, "evento de abertura persistido");

  // Identidade server-derivada no caso.
  assert.strictEqual(caseDoc.clinical_status, "open", "caso abre em open");
  assert.strictEqual(caseDoc.title, "Suspeita de gastrite", "título");
  assert.strictEqual(caseDoc.opening_event_id, eventId, "opening_event_id");
  assert.strictEqual(caseDoc.opening_type, "consultation", "opening_type");
  assert.strictEqual(caseDoc.schema_version, 1, "schema_version do caso");
  assert.strictEqual(caseDoc.event_count, 1, "contador inicia em 1");
  assert.ok(caseDoc.updated_at, "case.updated_at presente na abertura");
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.opened_at as Timestamp).toMillis(),
    "case.updated_at == case.opened_at na abertura",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.last_event_at as Timestamp).toMillis(),
    "case.updated_at == case.last_event_at na abertura",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    FIXED_NOW.getTime(),
    "case.updated_at usa o Timestamp do servidor",
  );
  assert.deepStrictEqual(
    caseDoc.recorded_by,
    {uid: actor.uid, name: actor.name, internal_role: "condutor"},
    "recorded_by não-admin",
  );

  // Identidade server-derivada no evento.
  assert.strictEqual(eventDoc.entity_kind, "clinical_event", "entity_kind");
  assert.strictEqual(eventDoc.status, "draft", "evento inicia em draft");
  assert.strictEqual(eventDoc.event_type, "consultation", "event_type");
  assert.strictEqual(eventDoc.dog_id, "dog-1", "dog_id no evento");
  assert.strictEqual(eventDoc.case_id, caseId, "case_id no evento");
  assert.strictEqual(eventDoc.has_amendments, false, "seed has_amendments");
  assert.strictEqual(eventDoc.amendment_count, 0, "seed amendment_count");
  assert.strictEqual(eventDoc.payload_type, "consultation_v1", "payload_type");
  assert.strictEqual(eventDoc.payload_version, 1, "payload_version default");

  // Receipt sob o caso + audit determinístico.
  const opPath = `${casePath}/operations/op-open-1`;
  const receipt = db._store.get(opPath) as JsonMap;
  assert.ok(receipt, "receipt gravado sob o caso");
  assert.strictEqual(receipt.actor_uid, actor.uid, "receipt.actor_uid");
  assert.strictEqual(
    receipt.operation_type,
    "open_clinical_case",
    "receipt.operation_type",
  );
  const audits = storeKeys(db).filter((k) => k.startsWith("auditLogs/"));
  assert.strictEqual(audits.length, 1, "exatamente 1 audit");
}

async function testOpenReplayNoDuplicate() {
  const db = dbWithDog();
  const deps = depsFor({db});

  await runHealthOpenClinicalCase(mockRequest(validOpen), deps);
  const keysAfterFirst = storeKeys(db);
  const txAfterFirst = db._transactions();

  const res2 = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    deps,
  )) as JsonMap;
  assert.strictEqual(res2.was_no_op, true, "replay é no-op");
  assert.deepStrictEqual(
    storeKeys(db),
    keysAfterFirst,
    "replay não cria nenhum documento novo",
  );
  assert.ok(
    db._transactions() > txAfterFirst,
    "replay ainda abre transação (para ler o receipt)",
  );
  const audits = storeKeys(db).filter((k) => k.startsWith("auditLogs/"));
  assert.strictEqual(audits.length, 1, "replay não duplica audit");
}

async function testOpenIdempotencyConflict() {
  const db = dbWithDog();
  const deps = depsFor({db});

  await runHealthOpenClinicalCase(mockRequest(validOpen), deps);

  // Mesma operationId, intenção diferente → failed-precondition.
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, title: "Outra intenção"}),
        deps,
      ),
    "idempotency-conflict",
    "open conflito de idempotência",
  );
}

async function testOpenDeterministicIds() {
  // IDs derivam de kind|dogId|operationId — sem clock/random/content.
  const a = caseIdFor("dog-1", "op-x");
  const b = caseIdFor("dog-1", "op-x");
  const c = caseIdFor("dog-1", "op-y");
  assert.strictEqual(a, b, "mesma entrada → mesmo caseId");
  assert.notStrictEqual(a, c, "operationId diferente → caseId diferente");
  assert.ok(a.startsWith("cc_"), "prefixo cc_");
  assert.ok(openingEventIdFor(a).startsWith("ce_"), "prefixo ce_");
}

async function testOpenGuards() {
  const db = dbWithDog();

  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest(validOpen),
        depsFor({db, allowRecord: false}),
      ),
    "permission-denied",
    "sem health.record_clinical",
  );

  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest(validOpen),
        depsFor({db, dogAccess: false}),
      ),
    "permission-denied",
    "sem escopo do K9",
  );

  // K9 inexistente.
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, dogId: "ghost"}),
        depsFor({db}),
      ),
    "not-found",
    "K9 inexistente",
  );

  // Sem escrita alguma após qualquer negação.
  assert.deepStrictEqual(
    storeKeys(db),
    ["dogs/dog-1"],
    "negações não escrevem nada",
  );
}

async function testOpenInjectionRejected() {
  const db = dbWithDog();
  const deps = depsFor({db});

  for (const forged of [
    {status: "final"},
    {clinical_status: "discharged"},
    {recorded_by: {uid: "forged"}},
    {opening_event_id: "ce_forged"},
    {schema_version: 99},
    {event_count: 500},
  ]) {
    await expectReject(
      () =>
        runHealthOpenClinicalCase(
          mockRequest({...validOpen, ...forged}),
          deps,
        ),
      "validation",
      `injeção rejeitada: ${Object.keys(forged)[0]}`,
    );
  }
  assert.deepStrictEqual(storeKeys(db), ["dogs/dog-1"], "injeção não escreve");
}

async function testOpenInvalidVocabularies() {
  const db = dbWithDog();
  const deps = depsFor({db});

  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, openingType: "nope"}),
        deps,
      ),
    "validation",
    "openingType desconhecido → invalid-argument",
  );
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, eventType: "nope"}),
        deps,
      ),
    "validation",
    "eventType desconhecido → invalid-argument",
  );
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, payloadType: "nope_v1"}),
        deps,
      ),
    "validation",
    "payloadType fora do vocabulário",
  );
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, occurredAt: "2999-01-01T00:00:00.000Z"}),
        deps,
      ),
    "validation",
    "occurredAt no futuro",
  );
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest({...validOpen, content: {}}),
        deps,
      ),
    "validation",
    "content vazio",
  );
}

async function testOpenAdminRole() {
  const db = dbWithDog();
  const deps = depsFor({db, admin: true});
  await runHealthOpenClinicalCase(mockRequest(validOpen), deps);
  const caseId = caseIdFor("dog-1", "op-open-1");
  const caseDoc = db._store.get(
    `dogs/dog-1/clinical_cases/${caseId}`,
  ) as JsonMap;
  assert.deepStrictEqual(
    caseDoc.recorded_by,
    {uid: actor.uid, name: actor.name, internal_role: "admin"},
    "internal_role admin é apenas classificação de auditoria",
  );
}

async function testOpenAggregateWithoutReceiptFailsClosed() {
  const db = dbWithDog();
  const caseId = caseIdFor("dog-1", "op-open-1");
  // Semeia um caso pré-existente SEM receipt no path determinístico.
  db._store.set(`dogs/dog-1/clinical_cases/${caseId}`, {
    clinical_status: "open",
    title: "órfão",
  });
  await expectReject(
    () => runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db})),
    "integrity",
    "agregado sem receipt falha fechado",
  );
}

// ── APPEND EVENT ─────────────────────────────────────────────────────────────

async function openAndReturnCaseId(
  db: FirebaseFirestore.Firestore & {_store: Map<string, JsonMap>},
): Promise<string> {
  await runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db}));
  return caseIdFor("dog-1", "op-open-1");
}

const appendPayload = (caseId: string, overrides: JsonMap = {}): JsonMap => ({
  dogId: "dog-1",
  caseId,
  operationId: "op-append-1",
  eventType: "treatment_note",
  occurredAt: "2026-08-15T11:00:00.000Z",
  payloadType: "treatment_note_v1",
  content: {notes: "iniciado antibiótico"},
  ...overrides,
});

async function testAppendSuccess() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const deps = depsFor({db});

  const res = (await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    deps,
  )) as JsonMap;
  assert.strictEqual(res.was_no_op, false, "append não é no-op");

  const eventId = eventIdFor("dog-1", caseId, "op-append-1");
  assert.strictEqual(res.event_id, eventId, "eventId determinístico");
  const eventDoc = db._store.get(
    `dogs/dog-1/clinical_cases/${caseId}/clinical_events/${eventId}`,
  ) as JsonMap;
  assert.ok(eventDoc, "evento persistido");
  assert.strictEqual(eventDoc.status, "draft", "append inicia em draft");
  assert.strictEqual(eventDoc.event_type, "treatment_note", "event_type");

  const caseDoc = db._store.get(
    `dogs/dog-1/clinical_cases/${caseId}`,
  ) as JsonMap;
  // clinical_status intacto — append NÃO é transição de ciclo de vida.
  assert.strictEqual(caseDoc.clinical_status, "open", "status intacto");
  assert.ok(caseDoc.updated_at, "case.updated_at presente após append");
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.last_event_at as Timestamp).toMillis(),
    "case.updated_at == case.last_event_at após append",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (eventDoc.recorded_at as Timestamp).toMillis(),
    "case.updated_at == eventDoc.recorded_at",
  );

  const audits = storeKeys(db).filter((k) => k.startsWith("auditLogs/"));
  assert.strictEqual(audits.length, 2, "1 audit de abertura + 1 de append");
}

async function testAppendReplayNoDuplicate() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const deps = depsFor({db});

  await runHealthAppendClinicalEvent(mockRequest(appendPayload(caseId)), deps);
  const keys = storeKeys(db);
  const res2 = (await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    deps,
  )) as JsonMap;
  assert.strictEqual(res2.was_no_op, true, "replay do append é no-op");
  assert.deepStrictEqual(storeKeys(db), keys, "replay não escreve novos docs");
}

async function testAppendIdempotencyConflict() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const deps = depsFor({db});

  await runHealthAppendClinicalEvent(mockRequest(appendPayload(caseId)), deps);
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId, {content: {notes: "outra"}})),
        deps,
      ),
    "idempotency-conflict",
    "append conflito de idempotência",
  );
}

async function testAppendCaseNotFound() {
  const db = dbWithDog();
  const deps = depsFor({db});
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload("cc_inexistente")),
        deps,
      ),
    "not-found",
    "append em caso inexistente",
  );
}

async function testAppendTerminalRejected() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  // Marca o caso como terminal fora de banda (simula gate de discharge futuro).
  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  db._store.set(casePath, {
    ...(db._store.get(casePath) as JsonMap),
    clinical_status: "discharged",
  });
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db}),
      ),
    "conflict",
    "append em caso terminal falha fechado",
  );
}

async function testAppendCorruptStatusFailsClosed() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  db._store.set(casePath, {
    ...(db._store.get(casePath) as JsonMap),
    clinical_status: "estado_impossivel",
  });
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db}),
      ),
    "validation",
    "status persistido fora do vocabulário → invalid-argument",
  );
}

async function testAppendGuardsAndInjection() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);

  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db, allowRecord: false}),
      ),
    "permission-denied",
    "append sem health.record_clinical",
  );
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db, dogAccess: false}),
      ),
    "permission-denied",
    "append sem escopo do K9",
  );
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId, {status: "final"})),
        depsFor({db}),
      ),
    "validation",
    "append rejeita injeção de status",
  );
}

async function testAppendEventWithoutReceiptFailsClosed() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const eventId = eventIdFor("dog-1", caseId, "op-append-1");
  // Semeia o evento determinístico SEM receipt correspondente.
  db._store.set(
    `dogs/dog-1/clinical_cases/${caseId}/clinical_events/${eventId}`,
    {entity_kind: "clinical_event", status: "draft"},
  );
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db}),
      ),
    "integrity",
    "evento sem receipt falha fechado",
  );
}

// ── Receipt malformado ───────────────────────────────────────────────────────

/**
 * Um receipt que EXISTE mas é ilegível é CORRUPÇÃO, não "ausente".
 *
 * Esta é a fronteira que sustenta toda a autoridade de idempotência: se um
 * receipt malformado fosse tratado como ausente, o writer criaria um SEGUNDO
 * fato clínico para uma operação que já produziu um. A auditoria W3.A1 provou o
 * comportamento correto contra o emulador Firestore real; a cobertura abaixo o
 * fixa na suíte commitada, porque uma mutação que desativa
 * `assertClinicalReceiptShape` sobrevivia a todos os testes daqui.
 */

/** Campos cuja ausência precisa ser detectada como corrupção. */
const RECEIPT_REQUIRED_FIELDS = [
  "kind",
  "operation_id",
  "operation_type",
  "actor_uid",
  "fingerprint",
  "result",
];

/** Receipt bem formado de abertura, usado como base das variantes corrompidas. */
function wellFormedOpenReceipt(caseId: string, eventId: string): JsonMap {
  return {
    kind: "clinical_case_open_v1",
    operation_id: "op-open-1",
    operation_type: "open_clinical_case",
    actor_uid: actor.uid,
    fingerprint: "fp-qualquer",
    result: {dogId: "dog-1", caseId, eventId},
  };
}

async function testOpenMalformedReceiptFailsClosed() {
  const caseId = caseIdFor("dog-1", "op-open-1");
  const eventId = openingEventIdFor(caseId);
  const opPath = `dogs/dog-1/clinical_cases/${caseId}/operations/op-open-1`;

  // Um campo obrigatório ausente por vez: nenhuma variante pode ser tratada
  // como "receipt ausente" e virar uma segunda abertura.
  for (const missing of RECEIPT_REQUIRED_FIELDS) {
    const corrupt = wellFormedOpenReceipt(caseId, eventId);
    delete corrupt[missing];

    const db = dbWithDog();
    db._store.set(opPath, corrupt);
    const keysBefore = storeKeys(db);

    await expectReject(
      () => runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db})),
      "integrity",
      `receipt de abertura sem "${missing}" falha fechado`,
    );

    // Nenhum fato clínico novo, nenhum receipt substituto, nenhum audit.
    assert.deepStrictEqual(
      storeKeys(db),
      keysBefore,
      `receipt sem "${missing}": store não pode ganhar documentos`,
    );
    assert.deepStrictEqual(
      db._store.get(opPath),
      corrupt,
      `receipt sem "${missing}": receipt corrompido não pode ser sobrescrito`,
    );
    assert.strictEqual(
      db._store.get(`dogs/dog-1/clinical_cases/${caseId}`),
      undefined,
      `receipt sem "${missing}": nenhum caso clínico criado`,
    );
    assert.strictEqual(
      storeKeys(db).filter((k) => k.startsWith("auditLogs/")).length,
      0,
      `receipt sem "${missing}": nenhum audit de sucesso`,
    );
  }

  // Valor presente porém vazio também é ilegível, não "ausente".
  for (const empty of [null, ""]) {
    const corrupt = wellFormedOpenReceipt(caseId, eventId);
    corrupt.fingerprint = empty;
    const db = dbWithDog();
    db._store.set(opPath, corrupt);
    await expectReject(
      () => runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db})),
      "integrity",
      `receipt com fingerprint ${JSON.stringify(empty)} falha fechado`,
    );
    assert.strictEqual(
      db._store.get(`dogs/dog-1/clinical_cases/${caseId}`),
      undefined,
      "nenhum caso criado sob receipt de fingerprint vazio",
    );
  }

  // `kind` de outro comando não é aceito como receipt desta operação: um
  // receipt legítimo de OUTRA família nunca autoriza replay aqui.
  const crossKind = wellFormedOpenReceipt(caseId, eventId);
  crossKind.kind = "clinical_event_append_v1";
  const dbCross = dbWithDog();
  dbCross._store.set(opPath, crossKind);
  await expectReject(
    () => runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db: dbCross})),
    "integrity",
    "receipt de kind alheio não é aceito na abertura",
  );
  assert.strictEqual(
    dbCross._store.get(`dogs/dog-1/clinical_cases/${caseId}`),
    undefined,
    "kind cruzado não pode abrir caso",
  );
}

async function testAppendMalformedReceiptFailsClosed() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const eventId = eventIdFor("dog-1", caseId, "op-append-1");
  const opPath =
    `dogs/dog-1/clinical_cases/${caseId}/operations/op-append-1`;
  const eventPath =
    `dogs/dog-1/clinical_cases/${caseId}/clinical_events/${eventId}`;

  // Receipt de append sem `actor_uid`: ilegível, logo corrupção.
  db._store.set(opPath, {
    kind: "clinical_event_append_v1",
    operation_id: "op-append-1",
    operation_type: "append_clinical_event",
    fingerprint: "fp-qualquer",
    result: {dogId: "dog-1", caseId, eventId},
  });
  const keysBefore = storeKeys(db);
  const caseBefore = {...(db._store.get(
    `dogs/dog-1/clinical_cases/${caseId}`,
  ) as JsonMap)};

  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId)),
        depsFor({db}),
      ),
    "integrity",
    "receipt de append malformado falha fechado",
  );

  assert.deepStrictEqual(
    storeKeys(db),
    keysBefore,
    "append sob receipt malformado não pode criar documentos",
  );
  assert.strictEqual(
    db._store.get(eventPath),
    undefined,
    "nenhum evento clínico criado",
  );
  // O agregado não pode ter sido tocado: nem contador, nem last_event_at.
  assert.deepStrictEqual(
    db._store.get(`dogs/dog-1/clinical_cases/${caseId}`),
    caseBefore,
    "caso não pode ser mutado por append recusado",
  );
  assert.strictEqual(
    storeKeys(db).filter((k) => k.startsWith("auditLogs/")).length,
    1,
    "somente o audit da abertura permanece",
  );
}

// ── Token de concorrência do ClinicalEvent (W4.P0) ───────────────────────────

/**
 * `updated_at` é a autoridade canônica de concorrência otimista do
 * ClinicalEvent (decisão da Control Tower em CLIN-WRITER-1.W4.P0).
 *
 * O contrato que estes testes fixam é o de NASCIMENTO do token: todo evento
 * canônico já existe com `updated_at`, igual a `recorded_at` na criação. Sem
 * isso, um comando futuro de mutação compararia o `expectedUpdatedAt` do
 * chamador contra um campo ausente — e não haveria como distinguir "token
 * obsoleto" de "evento nunca teve token".
 *
 * Este writer NÃO avança o token: ele nunca muta um evento existente. Avançar é
 * responsabilidade de cada comando de mutação (W4 em diante).
 */

/** Lê o documento de evento canônico direto do store do fake. */
function eventDocOf(
  db: {_store: Map<string, JsonMap>},
  caseId: string,
  eventId: string,
): JsonMap {
  const path = `dogs/dog-1/clinical_cases/${caseId}/clinical_events/${eventId}`;
  const doc = db._store.get(path);
  assert.ok(doc, `evento não encontrado em ${path}`);
  return doc as JsonMap;
}

/** Asserção compartilhada: o token nasce presente, Timestamp e == recorded_at. */
function assertBornWithToken(event: JsonMap, label: string) {
  const updatedAt = event.updated_at;
  const recordedAt = event.recorded_at;

  assert.ok(
    updatedAt !== undefined && updatedAt !== null,
    `${label}: evento canônico nasceu SEM updated_at`,
  );
  // Mesmo tipo de instante que `recorded_at`: um Timestamp do servidor, nunca
  // string nem número. `toMillis` é o que o contrato de wire exige.
  assert.ok(
    typeof (updatedAt as Timestamp)?.toMillis === "function",
    `${label}: updated_at não é Timestamp (toMillis ausente)`,
  );
  assert.strictEqual(
    (updatedAt as Timestamp).toMillis(),
    (recordedAt as Timestamp).toMillis(),
    `${label}: na criação updated_at deve ser igual a recorded_at`,
  );
  // O token é derivado do relógio do servidor injetado, nunca do payload.
  assert.strictEqual(
    (updatedAt as Timestamp).toMillis(),
    FIXED_NOW.getTime(),
    `${label}: updated_at não veio do relógio do servidor`,
  );
}

async function testOpenEventBornWithConcurrencyToken() {
  const db = dbWithDog();
  const caseId = caseIdFor("dog-1", "op-open-1");
  const eventId = openingEventIdFor(caseId);

  await runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db}));

  assertBornWithToken(eventDocOf(db, caseId, eventId), "OPEN");
}

async function testAppendEventBornWithConcurrencyToken() {
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const eventId = eventIdFor("dog-1", caseId, "op-append-1");

  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db}),
  );

  assertBornWithToken(eventDocOf(db, caseId, eventId), "APPEND");
}

async function testConcurrencyTokenIsServerOwned() {
  // O cliente não escolhe o token. `updated_at`/`updatedAt` já estão na lista de
  // chaves proibidas do W3; aqui provamos que a proteção cobre o campo NOVO —
  // caso contrário o chamador poderia nascer com um token forjado e derrotar
  // qualquer verificação de concorrência futura.
  const db = dbWithDog();
  const deps = depsFor({db});

  for (const forged of [
    {updated_at: "2020-01-01T00:00:00.000Z"},
    {updatedAt: 1},
  ]) {
    await expectReject(
      () =>
        runHealthOpenClinicalCase(
          mockRequest({...validOpen, ...forged}),
          deps,
        ),
      "validation",
      `OPEN rejeita token forjado: ${Object.keys(forged)[0]}`,
    );
  }
  assert.deepStrictEqual(
    storeKeys(db),
    ["dogs/dog-1"],
    "token forjado não pode escrever nada",
  );

  // Mesma proteção no APPEND, sobre um caso real já aberto.
  const dbAppend = dbWithDog();
  const caseId = await openAndReturnCaseId(dbAppend);
  const keysBefore = storeKeys(dbAppend);
  for (const forged of [
    {updated_at: "2020-01-01T00:00:00.000Z"},
    {updatedAt: 1},
  ]) {
    await expectReject(
      () =>
        runHealthAppendClinicalEvent(
          mockRequest(appendPayload(caseId, forged)),
          depsFor({db: dbAppend}),
        ),
      "validation",
      `APPEND rejeita token forjado: ${Object.keys(forged)[0]}`,
    );
  }
  assert.deepStrictEqual(
    storeKeys(dbAppend),
    keysBefore,
    "token forjado no append não pode escrever nada",
  );
}

async function testReplayDoesNotAdvanceConcurrencyToken() {
  // Um replay é a MESMA verdade, não uma nova mutação: se ele avançasse o token,
  // um retry de rede invalidaria silenciosamente o `expectedUpdatedAt` que o
  // chamador acabou de ler — exatamente o modo de falha que o token existe para
  // impedir.
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const openingId = openingEventIdFor(caseId);
  const openingBefore = {...eventDocOf(db, caseId, openingId)};

  await runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db}));
  assert.deepStrictEqual(
    eventDocOf(db, caseId, openingId),
    openingBefore,
    "replay de OPEN não pode reescrever o evento de abertura",
  );

  const eventId = eventIdFor("dog-1", caseId, "op-append-1");
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db}),
  );
  const appendBefore = {...eventDocOf(db, caseId, eventId)};

  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db}),
  );
  assert.deepStrictEqual(
    eventDocOf(db, caseId, eventId),
    appendBefore,
    "replay de APPEND não pode avançar updated_at",
  );
}

async function testIdempotencyConflictLeavesTokenIntact() {
  // Conflito de intenção não é mutação: zero evento novo, token intacto.
  const db = dbWithDog();
  const caseId = await openAndReturnCaseId(db);
  const eventId = eventIdFor("dog-1", caseId, "op-append-1");

  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db}),
  );
  const before = {...eventDocOf(db, caseId, eventId)};
  const keysBefore = storeKeys(db);

  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId, {content: {notes: "outra coisa"}})),
        depsFor({db}),
      ),
    "idempotency-conflict",
    "mesma operationId com intenção diferente",
  );

  assert.deepStrictEqual(
    storeKeys(db),
    keysBefore,
    "conflito não pode criar um segundo evento",
  );
  assert.deepStrictEqual(
    eventDocOf(db, caseId, eventId),
    before,
    "conflito não pode alterar updated_at do evento existente",
  );
}

// ── Token de concorrência do ClinicalCase (CLIN-WRITER-1.W6.P0.F1) ───────────

async function testCaseConcurrencyTokenLifecycle() {
  const db = dbWithDog();
  const t0 = new Date("2026-08-15T10:00:00.000Z");
  const t1 = new Date("2026-08-15T11:00:00.000Z");
  const t2 = new Date("2026-08-15T12:00:00.000Z");
  const t3 = new Date("2026-08-15T13:00:00.000Z");
  const t4 = new Date("2026-08-15T14:00:00.000Z");

  // 1. OPEN: case.updated_at nasce igual a opened_at e last_event_at (T0)
  await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: t0}),
  );
  const caseId = caseIdFor("dog-1", "op-open-1");
  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  let caseDoc = db._store.get(casePath) as JsonMap;

  assert.ok(caseDoc.updated_at, "case.updated_at deve existir na abertura");
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t0.getTime(),
    "OPEN: updated_at == T0",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.opened_at as Timestamp).toMillis(),
    "OPEN: updated_at == opened_at",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.last_event_at as Timestamp).toMillis(),
    "OPEN: updated_at == last_event_at",
  );

  // Replay de OPEN não avança case.updated_at
  await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: t1}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t0.getTime(),
    "OPEN replay não avança case.updated_at",
  );

  // 2. APPEND: case.updated_at avança para T1 (last_event_at == appendedEvent.recorded_at)
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db, now: t1}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  const eventId = eventIdFor("dog-1", caseId, "op-append-1");
  const eventDoc = db._store.get(
    `dogs/dog-1/clinical_cases/${caseId}/clinical_events/${eventId}`,
  ) as JsonMap;

  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "APPEND: updated_at avança para T1",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (caseDoc.last_event_at as Timestamp).toMillis(),
    "APPEND: updated_at == last_event_at",
  );
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    (eventDoc.recorded_at as Timestamp).toMillis(),
    "APPEND: updated_at == appendedEvent.recorded_at",
  );

  // Replay de APPEND não avança case.updated_at
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db, now: t2}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "APPEND replay não avança case.updated_at",
  );

  // Conflito de APPEND não avança case.updated_at
  await expectReject(
    () =>
      runHealthAppendClinicalEvent(
        mockRequest(appendPayload(caseId, {content: {notes: "divergente"}})),
        depsFor({db, now: t2}),
      ),
    "idempotency-conflict",
    "append conflito",
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "APPEND conflict não avança case.updated_at",
  );

  // 3. W4 FINALIZE: mutação exclusiva de evento NÃO altera case.updated_at
  await runHealthFinalizeClinicalEvent(
    mockRequest({
      dogId: "dog-1",
      caseId,
      eventId,
      operationId: "op-finalize-1",
      expectedRevision: 1,
    }),
    depsFor({db, now: t2}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "FINALIZE não altera case.updated_at",
  );

  // 4. W5 AMEND: emenda de evento NÃO altera case.updated_at
  await runHealthAmendClinicalEvent(
    mockRequest({
      dogId: "dog-1",
      caseId,
      eventId,
      operationId: "op-amend-1",
      expectedRevision: 2,
      amendmentType: "addendum",
      reason: "observação clínica complementar",
      content: {note: "evolução estável"},
    }),
    depsFor({db, now: t3}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "AMEND não altera case.updated_at",
  );

  // 5. W4 CANCEL: cancelamento de evento NÃO altera case.updated_at
  await runHealthCancelClinicalEvent(
    mockRequest({
      dogId: "dog-1",
      caseId,
      eventId,
      operationId: "op-cancel-1",
      expectedRevision: 3,
      cancelReason: "registro duplicado pelo veterinário",
    }),
    depsFor({db, now: t4}),
  );
  caseDoc = db._store.get(casePath) as JsonMap;
  assert.strictEqual(
    (caseDoc.updated_at as Timestamp).toMillis(),
    t1.getTime(),
    "CANCEL não altera case.updated_at",
  );
}

// ── Idempotência cruzada entre atores ────────────────────────────────────────

async function testCrossActorOperationIdConflict() {
  const db = dbWithDog();
  await runHealthOpenClinicalCase(mockRequest(validOpen), depsFor({db}));
  // Outro ator reutiliza a MESMA operationId → o id colide e o receipt gate
  // resolve como conflito explícito, nunca duplicando o fato clínico.
  await expectReject(
    () =>
      runHealthOpenClinicalCase(
        mockRequest(validOpen, {uid: actorB.uid, token: {}}),
        depsFor({db, caller: actorB}),
      ),
    "idempotency-conflict",
    "operationId reutilizada por outro ator",
  );
}

// ── Guarda arquitetural: sem bypass administrativo na autoridade clínica ─────

/**
 * Prova ARQUITETURAL, no mesmo espírito de `restriction_capability_test.ts`.
 *
 * `requireClinicalCapability` vive em `index.ts` e depende de leituras de
 * Firestore, então um teste comportamental exigiria emulador. O que esta guarda
 * protege é o invariante que o gate existe para garantir: identidade
 * administrativa, por si só, NÃO concede `health.record_clinical`.
 *
 * Sem esta guarda, alguém "unificando" o caminho clínico de volta no helper
 * genérico — ou simplesmente adicionando um atalho de admin — reintroduziria o
 * bypass sem que nenhum teste falhasse (mutação MUT6 da auditoria W3.A1).
 * Administração técnica não é autoridade clínica.
 */
const CLINICAL_CAPABILITY_FN = "async function requireClinicalCapability";

/** Corpo textual de `requireClinicalCapability`, sem comentários. */
function clinicalCapabilityBody(): string {
  const indexCode = stripComments(readSource("index.ts"));
  const start = indexCode.indexOf(CLINICAL_CAPABILITY_FN);
  assert.ok(start > 0, "requireClinicalCapability não encontrada em index.ts");
  const end = indexCode.indexOf("\n}", start);
  assert.ok(end > start, "corpo de requireClinicalCapability não delimitado");
  return indexCode.slice(start, end);
}

async function testClinicalCapabilityHasNoAdminBypass() {
  const body = clinicalCapabilityBody();

  // Atalhos administrativos conhecidos da plataforma. Qualquer um deles no
  // corpo tornaria a capability clínica decorativa para admins técnicos.
  for (const forbidden of [
    "isAdminToken",
    "isAdminUserRecord",
    "isAdminAccessLevel",
    "isAdministrativeHealthAuthority",
    "requireAccessPermission",
    "requireAnyAccessPermission",
  ]) {
    assert.ok(
      !body.includes(forbidden),
      `bypass reintroduzido: ${forbidden} apareceu na autoridade clínica`,
    );
  }

  // Rede de segurança para um atalho escrito à mão (`token.admin === true`,
  // `user.admin`, `claims.admin`) que não passe pelos helpers acima.
  assert.ok(
    !/\badmin\b\s*(===|==|!==|!=)/.test(body) &&
      !/\.admin\b/.test(body) &&
      !/\badmin\s*:/.test(body),
    "atalho administrativo manual apareceu na autoridade clínica",
  );

  // A autoridade real precisa continuar sendo o grant explícito do perfil.
  assert.ok(
    body.includes("profileGrantsPermission("),
    "a autoridade clínica deixou de consultar o grant explícito do perfil",
  );
  assert.ok(
    body.includes("\"health\""),
    "a autoridade clínica deixou de exigir o módulo health",
  );
  // Escopo estrutural de K9 segue sendo gate separado e obrigatório.
  assert.ok(
    !body.includes("requireDogRecordAccess"),
    "capability e escopo de K9 não podem ser fundidos em um único gate",
  );
}

async function testClinicalCallablesUseDedicatedAuthority() {
  const indexCode = stripComments(readSource("index.ts"));

  // O writer clínico precisa exigir a capability própria, não uma genérica.
  assert.ok(
    /requireClinicalCapability\(\s*auth\s*,\s*"record_clinical"\s*\)/.test(
      indexCode,
    ),
    "o writer clínico não está exigindo health.record_clinical dedicado",
  );

  // Os dois callables deste gate precisam compartilhar os deps que carregam
  // aquela autoridade — nunca montar um caminho paralelo.
  for (const callable of [
    "healthOpenClinicalCase",
    "healthAppendClinicalEvent",
  ]) {
    const start = indexCode.indexOf(`export const ${callable} =`);
    assert.ok(start > 0, `${callable} não encontrado em index.ts`);
    const body = indexCode.slice(start, indexCode.indexOf("});", start));
    assert.ok(
      body.includes("clinicalCaseDeps"),
      `${callable} não está usando clinicalCaseDeps`,
    );
    for (const forbidden of ["isAdminToken", "isAdminUserRecord"]) {
      assert.ok(
        !body.includes(forbidden),
        `${callable} ganhou atalho administrativo: ${forbidden}`,
      );
    }
  }

  // O bypass administrativo GENÉRICO da plataforma permanece intacto: o escopo
  // aprovado é cirúrgico, o resto da plataforma não muda.
  const generic = indexCode.indexOf("async function requireAccessPermission");
  assert.ok(generic > 0, "requireAccessPermission não encontrada");
  const genericBody = indexCode.slice(
    generic,
    indexCode.indexOf("\n}", generic),
  );
  assert.ok(
    genericBody.includes("isAdminToken(auth.token)") &&
      genericBody.includes("isAdminUserRecord(user)"),
    "o bypass genérico desapareceu — fora do escopo deste gate",
  );
}

async function testAdminIdentityAloneDoesNotGrantRecordClinical() {
  // Prova COMPORTAMENTAL do invariante, sobre o helper canônico de leitura de
  // grant que a autoridade clínica usa. Perfil de administrador SEM o par
  // `health.record_clinical` não pode ser autorizado a escrever registro
  // clínico — nem quando o token/espelho o identificam como admin.
  const adminToken = {admin: true, role: "administrador"} as never;
  assert.strictEqual(isAdminToken(adminToken), true, "token é admin de fato");
  assert.strictEqual(
    isAdminUserRecord({admin: true, accessLevel: "administrador"}),
    true,
    "espelho é admin de fato",
  );

  const adminProfileSemGrant: JsonMap = {
    status: "active",
    permissions: {
      health: {
        view: true,
        read: true,
        create: true,
        edit: true,
        audit: true,
        export: true,
        approve: true,
        archive: true,
      },
    },
  };
  assert.strictEqual(
    profileGrantsPermission(adminProfileSemGrant, "health", "record_clinical" as never),
    false,
    "administrador sem o par explícito NÃO recebe record_clinical",
  );
  // `health.read` tampouco implica escrita clínica.
  assert.strictEqual(
    profileGrantsPermission({status: "active", permissions: {health: {read: true}}},
      "health", "record_clinical" as never),
    false,
    "health.read não implica record_clinical",
  );
  // Só o par exato concede.
  assert.strictEqual(
    profileGrantsPermission(
      {status: "active", permissions: {health: {record_clinical: true}}},
      "health",
      "record_clinical" as never,
    ),
    true,
    "o par exato concede",
  );
  // Perfil inativo não conserva autoridade nem com o grant.
  assert.strictEqual(
    profileGrantsPermission(
      {status: "inactive", permissions: {health: {record_clinical: true}}},
      "health",
      "record_clinical" as never,
    ),
    false,
    "perfil inativo não concede",
  );
}

// ── EVENT MUTATION (FINALIZE / CANCEL) ─────────────────────────────────────

const T1 = new Date("2026-08-16T09:30:00.000Z");

/** Cria um caso+evento draft em T0 e devolve tudo o que uma mutação precisa. */
async function seedDraftEvent(options: {admin?: boolean} = {}) {
  const db = dbWithDog();
  const res = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, admin: options.admin}),
  )) as JsonMap;
  const caseId = res.case_id as string;
  const eventId = res.opening_event_id as string;
  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  const eventPath = `${casePath}/clinical_events/${eventId}`;
  const event = db._store.get(eventPath) as JsonMap;
  const t0 = (event.updated_at as Timestamp).toMillis();
  return {db, caseId, eventId, casePath, eventPath, t0};
}

const mutationCmd = (
  caseId: string,
  eventId: string,
  operationId: string,
  expectedRevision: number,
  extra: JsonMap = {},
): JsonMap => ({
  dogId: "dog-1",
  caseId,
  eventId,
  operationId,
  expectedRevision,
  ...extra,
});

const eventOf = (db: {_store: Map<string, JsonMap>}, p: string): JsonMap =>
  db._store.get(p) as JsonMap;

const caseOf = (db: {_store: Map<string, JsonMap>}, p: string): JsonMap =>
  db._store.get(p) as JsonMap;

const auditKeys = (db: {_store: Map<string, JsonMap>}): string[] =>
  [...db._store.keys()].filter((k) => k.startsWith("auditLogs/"));

const opKeys = (
  db: {_store: Map<string, JsonMap>},
  casePath: string,
): string[] =>
  [...db._store.keys()].filter((k) => k.startsWith(`${casePath}/operations/`));

/** Campos clínicos que NENHUMA mutação de status pode alterar. */
const CONTENT_FIELDS = [
  "dog_id",
  "case_id",
  "entity_kind",
  "event_type",
  "occurred_at",
  "recorded_at",
  "recorded_by",
  "payload_type",
  "payload_version",
  "content",
  "has_amendments",
  "amendment_count",
  "schema_version",
];

function assertContentPreserved(
  before: JsonMap,
  after: JsonMap,
  label: string,
): void {
  for (const f of CONTENT_FIELDS) {
    assert.deepStrictEqual(after[f], before[f], `${label}: ${f} foi alterado`);
  }
}

async function testFinalizeSuccess() {
  const {db, caseId, eventId, casePath, eventPath, t0} = await seedDraftEvent();
  const before = {...eventOf(db, eventPath)};
  const caseBefore = {...(db._store.get(casePath) as JsonMap)};
  const auditsBefore = auditKeys(db).length;

  const res = (await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", 1)),
    depsFor({db, now: T1}),
  )) as JsonMap;

  // A/B — sucesso e status persistido.
  assert.strictEqual(res.was_no_op, false, "primeira finalização não é no-op");
  assert.strictEqual(res.status, "final", "resposta declara final");
  const after = eventOf(db, eventPath);
  assert.strictEqual(after.status, "final", "B: status final persistido");

  // C/D/E — finalized_at real, updated_at igual, token avançou.
  const finalizedAt = after.finalized_at as Timestamp;
  assert.ok(
    finalizedAt && typeof finalizedAt.toMillis === "function",
    "C: finalized_at não é Timestamp",
  );
  assert.strictEqual(
    (after.updated_at as Timestamp).toMillis(),
    finalizedAt.toMillis(),
    "D: updated_at != finalized_at",
  );
  assert.strictEqual(
    finalizedAt.toMillis(),
    T1.getTime(),
    "C: finalized_at não veio do relógio do servidor",
  );
  assert.strictEqual(
    (after.updated_at as Timestamp).toMillis() > t0,
    true,
    "E: token não avançou de T0 para T1",
  );

  // F — conteúdo clínico preservado.
  assertContentPreserved(before, after, "F");

  // G — finalized_by não existe.
  assert.strictEqual(after.finalized_by, undefined, "G: finalized_by persistido");
  assert.strictEqual(after.cancelled_at, undefined, "cancelled_at vazou");
  assert.strictEqual(after.cancel_reason, undefined, "cancel_reason vazou");

  // H — documento do caso intacto.
  assert.deepStrictEqual(
    db._store.get(casePath),
    caseBefore,
    "H: documento do caso foi alterado pela finalização",
  );

  // I/J — exatamente um receipt novo e um audit novo.
  assert.ok(
    opKeys(db, casePath).includes(`${casePath}/operations/op-fin-1`),
    "I: receipt da finalização ausente",
  );
  assert.strictEqual(
    auditKeys(db).length,
    auditsBefore + 1,
    "J: finalização não gerou exatamente 1 audit",
  );
  const audit = db._store.get(
    auditKeys(db).find((k) => {
      const a = db._store.get(k) as JsonMap;
      return a.action === "clinical_event_finalized";
    }) as string,
  ) as JsonMap;
  assert.ok(audit, "J: audit de finalização ausente");
  assert.strictEqual(
    (audit.metadata as JsonMap).previous_status,
    "draft",
    "audit registra status anterior",
  );
}

async function testFinalizeReplayAndStale() {
  const {db, caseId, eventId, casePath, eventPath} = await seedDraftEvent();
  const deps = depsFor({db, now: T1});

  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", 1)),
    deps,
  );
  const opsAfterFirst = opKeys(db, casePath).length;
  const auditsAfterFirst = auditKeys(db).length;

  // K/L — mesma operação, mesma intenção, token ANTIGO T0: replay bem-sucedido.
  const replay = (await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", 1)),
    deps,
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "L: replay não sinalizou no-op");

  // M — replay não avança o token, não duplica receipt nem audit.
  assert.strictEqual(
    eventOf(db, eventPath).revision,
    2,
    "M: replay avançou a revision",
  );
  assert.strictEqual(
    opKeys(db, casePath).length,
    opsAfterFirst,
    "M: replay criou receipt novo",
  );
  assert.strictEqual(
    auditKeys(db).length,
    auditsAfterFirst,
    "M: replay criou audit novo",
  );

  // N — operação NOVA com token velho: stale, fail-closed.
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(caseId, eventId, "op-fin-2", 1)),
      deps,
    ),
    "conflict",
    "N: nova operação com token velho deveria falhar stale",
  );
  assert.strictEqual(
    auditKeys(db).length,
    auditsAfterFirst,
    "N: requisição stale gerou audit",
  );
}

async function testFinalizeConflictAndIllegalTransitions() {
  const {db, caseId, eventId} = await seedDraftEvent();
  const deps = depsFor({db, now: T1});

  // O — mesma operação, ator diferente = intenção divergente.
  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", 1)),
    deps,
  );
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(caseId, eventId, "op-fin-1", 2), {
        uid: actorB.uid,
        token: {},
      }),
      depsFor({db, now: T1, caller: actorB}),
    ),
    "idempotency-conflict",
    "O: receipt de outro ator deveria conflitar",
  );

  // P — nova operação sobre evento JÁ final: transição ilegal, não idempotência.
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(caseId, eventId, "op-fin-3", 2)),
      deps,
    ),
    "conflict",
    "P: refinalizar deveria ser transição ilegal",
  );

  // Q — evento cancelado não finaliza.
  const c = await seedDraftEvent();
  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(c.caseId, c.eventId, "op-can-1", 1, {
        cancelReason: "erro de digitação",
      }),
    ),
    depsFor({db: c.db, now: T1}),
  );
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(c.caseId, c.eventId, "op-fin-9", 2)),
      depsFor({db: c.db, now: T1}),
    ),
    "conflict",
    "Q: evento cancelado não pode finalizar",
  );
}

async function testFinalizeTokenAndIntegrityFailures() {
  const base = await seedDraftEvent();

  // R — evento inexistente.
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(base.caseId, "ce_naoexiste", "op-x", 1)),
      depsFor({db: base.db, now: T1}),
    ),
    "not-found",
    "R: evento inexistente",
  );

  // T/U — token de requisição ausente e malformado. O piso é 1: revision 0 e
  // ausência NÃO são toleradas (divergência deliberada do Schedule legado).
  for (const [bad, label] of [
    [undefined, "T: expectedRevision ausente"],
    ["1", "U: expectedRevision string"],
    [1.5, "U: expectedRevision fracionário"],
    [Number.NaN, "U: expectedRevision NaN"],
    [Number.POSITIVE_INFINITY, "U: expectedRevision Infinity"],
    [-1, "U: expectedRevision negativo"],
    [0, "U: expectedRevision zero (sem tolerância legada)"],
    [true, "U: expectedRevision boolean"],
    [null, "U: expectedRevision null"],
    [Number.MAX_SAFE_INTEGER + 1, "U: expectedRevision inteiro inseguro"],
  ] as Array<[unknown, string]>) {
    const cmd = mutationCmd(base.caseId, base.eventId, "op-t", 1);
    if (bad === undefined) delete cmd.expectedRevision;
    else cmd.expectedRevision = bad;
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(cmd),
        depsFor({db: base.db, now: T1}),
      ),
      "validation",
      label,
    );
  }

  // T2 — expectedUpdatedAt foi RETIRADO: o vocabulário fechado o recusa mesmo
  // quando acompanhado de um expectedRevision válido. Prova autoridade única.
  for (const legacy of ["expectedUpdatedAt", "expected_updated_at"]) {
    const cmd = mutationCmd(base.caseId, base.eventId, "op-t2", 1);
    cmd[legacy] = 1755259200000;
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(cmd),
        depsFor({db: base.db, now: T1}),
      ),
      "validation",
      `T2: ${legacy} retirado do contrato clínico`,
    );
  }

  // S — revision armazenada malformada: integrity, zero mutação. Inclui 0 e
  // ausência: Clinical NÃO herda a tolerância legada do Schedule, e
  // MAX_SAFE_INTEGER falha porque não pode avançar com segurança.
  for (const corrupt of [
    undefined, "1", 0, -1, 1.5, Number.NaN, true, null,
    Number.MAX_SAFE_INTEGER,
  ] as unknown[]) {
    const s = await seedDraftEvent();
    const ev = eventOf(s.db, s.eventPath);
    if (corrupt === undefined) delete ev.revision;
    else ev.revision = corrupt as never;
    s.db._store.set(s.eventPath, ev);
    const expected = corrupt === Number.MAX_SAFE_INTEGER ?
      Number.MAX_SAFE_INTEGER :
      1;
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(mutationCmd(s.caseId, s.eventId, "op-s", expected)),
        depsFor({db: s.db, now: T1}),
      ),
      "integrity",
      `S: revision armazenada inválida (${String(corrupt)})`,
    );
    assert.strictEqual(
      eventOf(s.db, s.eventPath).status,
      "draft",
      "S: evento mutado apesar da integridade violada",
    );
  }

  // AC — receipt malformado: integrity, zero mutação.
  const m = await seedDraftEvent();
  m.db._store.set(`${m.casePath}/operations/op-mal`, {
    kind: "clinical_event_finalize_v1",
    operation_id: "op-mal",
    // operation_type ausente = receipt corrompido
    actor_uid: actor.uid,
    fingerprint: "x",
    result: {},
  });
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(m.caseId, m.eventId, "op-mal", 1)),
      depsFor({db: m.db, now: T1}),
    ),
    "integrity",
    "AC: receipt malformado deveria falhar fechado",
  );
  assert.strictEqual(
    eventOf(m.db, m.eventPath).status,
    "draft",
    "AC: evento mutado apesar de receipt corrompido",
  );

  // Integridade estrutural: dog_id divergente do caminho.
  const d = await seedDraftEvent();
  const dev = eventOf(d.db, d.eventPath);
  dev.dog_id = "dog-outro";
  d.db._store.set(d.eventPath, dev);
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(d.caseId, d.eventId, "op-d", 1)),
      depsFor({db: d.db, now: T1}),
    ),
    "integrity",
    "dog_id divergente do caminho deveria falhar fechado",
  );
}

async function testFinalizeAuthorizationMatrix() {
  // V — escopo de K9.
  const v = await seedDraftEvent();
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(v.caseId, v.eventId, "op-v", 1)),
      depsFor({db: v.db, now: T1, dogAccess: false}),
    ),
    "permission-denied",
    "V: escopo de K9 negado",
  );

  // W/X/Y/Z/AA — capability.
  const cases: Array<[string, Parameters<typeof depsFor>[0]]> = [
    ["W: sem finalize_clinical", {db: v.db, allowFinalize: false}],
    [
      "X: só record_clinical",
      {db: v.db, allowRecord: true, allowFinalize: false, allowAmend: false},
    ],
    [
      "Y: só amend_clinical",
      {db: v.db, allowFinalize: false, allowAmend: true},
    ],
    [
      "Z: só health.read (nenhuma capability clínica)",
      {db: v.db, allowRecord: false, allowFinalize: false, allowAmend: false},
    ],
    [
      "AA: admin sem grant",
      {db: v.db, admin: true, allowFinalize: false},
    ],
  ];
  for (const [label, opts] of cases) {
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(mutationCmd(v.caseId, v.eventId, "op-w", 1)),
        depsFor({...opts, now: T1}),
      ),
      "permission-denied",
      label,
    );
  }
  assert.strictEqual(
    eventOf(v.db, v.eventPath).status,
    "draft",
    "negação deixou o evento mutado",
  );

  // AB — injeção de campo server-owned: zero escrita.
  for (const forged of [
    {status: "final"},
    {finalized_at: "2020-01-01T00:00:00.000Z"},
    {finalizedAt: 1},
    {finalized_by: {uid: "x"}},
    {updated_at: 1},
    {updatedAt: 1},
    {recorded_by: {uid: "x"}},
    {content: {notes: "reescrito"}},
  ]) {
    const before = {...eventOf(v.db, v.eventPath)};
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(
          mutationCmd(v.caseId, v.eventId, "op-inj", 1, forged as JsonMap),
        ),
        depsFor({db: v.db, now: T1}),
      ),
      "validation",
      `AB: injeção de ${Object.keys(forged)[0]}`,
    );
    assert.deepStrictEqual(
      eventOf(v.db, v.eventPath),
      before,
      `AB: injeção de ${Object.keys(forged)[0]} escreveu`,
    );
  }
}

async function testCancelFromDraftAndFinal() {
  // A — draft → cancelled.
  const d = await seedDraftEvent();
  const dBefore = {...eventOf(d.db, d.eventPath)};
  const dCaseBefore = {...(d.db._store.get(d.casePath) as JsonMap)};
  const res = (await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(d.caseId, d.eventId, "op-can-1", 1, {
        cancelReason: "  registrado no K9 errado  ",
      }),
    ),
    depsFor({db: d.db, now: T1}),
  )) as JsonMap;
  assert.strictEqual(res.was_no_op, false, "A: cancelamento não é no-op");
  const dAfter = eventOf(d.db, d.eventPath);
  assert.strictEqual(dAfter.status, "cancelled", "A: status cancelled");

  // F — motivo persistido trimado.
  assert.strictEqual(
    dAfter.cancel_reason,
    "registrado no K9 errado",
    "F: cancel_reason não foi trimado",
  );
  // G/H — metadados server-owned.
  const cancelledAt = dAfter.cancelled_at as Timestamp;
  assert.ok(
    cancelledAt && typeof cancelledAt.toMillis === "function",
    "G: cancelled_at não é Timestamp",
  );
  assert.strictEqual(
    cancelledAt.toMillis(),
    T1.getTime(),
    "G: cancelled_at não veio do relógio do servidor",
  );
  assert.deepStrictEqual(
    dAfter.cancelled_by,
    {uid: actor.uid, name: actor.name, internal_role: "condutor"},
    "H: cancelled_by não é derivado do servidor",
  );
  // I/J — token igual ao cancelled_at e avançado.
  assert.strictEqual(
    (dAfter.updated_at as Timestamp).toMillis(),
    cancelledAt.toMillis(),
    "I: updated_at != cancelled_at",
  );
  assert.strictEqual(
    (dAfter.updated_at as Timestamp).toMillis() > d.t0,
    true,
    "J: token não avançou",
  );
  // K — draft cancelado nunca ganha finalized_at.
  assert.strictEqual(
    dAfter.finalized_at,
    undefined,
    "K: draft cancelado ganhou finalized_at",
  );
  // M/N/O — conteúdo e caso intactos.
  assertContentPreserved(dBefore, dAfter, "M");
  assert.deepStrictEqual(
    d.db._store.get(d.casePath),
    dCaseBefore,
    "N/O: documento do caso alterado pelo cancelamento",
  );

  // B/L — final → cancelled preserva finalized_at.
  const f = await seedDraftEvent();
  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(f.caseId, f.eventId, "op-fin-1", 1)),
    depsFor({db: f.db, now: T1}),
  );
  const finalized = eventOf(f.db, f.eventPath);
  const finalizedAtMs = (finalized.finalized_at as Timestamp).toMillis();
  const T2 = new Date("2026-08-17T15:45:00.000Z");

  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(f.caseId, f.eventId, "op-can-2", 2, {
        cancelReason: "laudo emitido em duplicidade",
      }),
    ),
    depsFor({db: f.db, now: T2}),
  );
  const fAfter = eventOf(f.db, f.eventPath);
  assert.strictEqual(fAfter.status, "cancelled", "B: final → cancelled");
  assert.strictEqual(
    (fAfter.finalized_at as Timestamp).toMillis(),
    finalizedAtMs,
    "L: finalized_at original não foi preservado",
  );
  assert.strictEqual(
    (fAfter.updated_at as Timestamp).toMillis(),
    T2.getTime(),
    "token não avançou para o instante do cancelamento",
  );
  assertContentPreserved(finalized, fAfter, "M(final)");

  // C — cancelled é terminal: nova operação é transição ilegal.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(f.caseId, f.eventId, "op-can-3", 2, {
          cancelReason: "de novo",
        }),
      ),
      depsFor({db: f.db, now: T2}),
    ),
    "conflict",
    "C: recancelar deveria ser transição ilegal",
  );
}

async function testCancelReasonAndReplay() {
  const base = await seedDraftEvent();

  // D/E — motivo ausente e vazio.
  for (const [bad, label] of [
    [undefined, "D: cancelReason ausente"],
    ["", "E: cancelReason vazio"],
    ["   ", "E: cancelReason só espaços"],
    [42, "E: cancelReason não-string"],
  ] as Array<[unknown, string]>) {
    const cmd = mutationCmd(base.caseId, base.eventId, "op-r", 1);
    if (bad !== undefined) cmd.cancelReason = bad;
    await expectReject(
      () => runHealthCancelClinicalEvent(
        mockRequest(cmd),
        depsFor({db: base.db, now: T1}),
      ),
      "validation",
      label,
    );
  }
  assert.strictEqual(
    eventOf(base.db, base.eventPath).status,
    "draft",
    "motivo inválido mutou o evento",
  );

  // P/Q/R — replay com token antigo.
  const r = await seedDraftEvent();
  const deps = depsFor({db: r.db, now: T1});
  const cmd = mutationCmd(r.caseId, r.eventId, "op-can-1", 1, {
    cancelReason: "duplicado",
  });
  await runHealthCancelClinicalEvent(mockRequest(cmd), deps);
  const rT1 = (eventOf(r.db, r.eventPath).updated_at as Timestamp).toMillis();
  const opsAfter = opKeys(r.db, r.casePath).length;
  const auditsAfter = auditKeys(r.db).length;

  const replay = (await runHealthCancelClinicalEvent(
    mockRequest(cmd),
    deps,
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "P/Q: replay não sinalizou no-op");
  assert.strictEqual(
    (eventOf(r.db, r.eventPath).updated_at as Timestamp).toMillis(),
    rT1,
    "R: replay avançou o token",
  );
  assert.strictEqual(
    opKeys(r.db, r.casePath).length,
    opsAfter,
    "R: replay duplicou receipt",
  );
  assert.strictEqual(
    auditKeys(r.db).length,
    auditsAfter,
    "R: replay duplicou audit",
  );

  // S — mesma operação com motivo DIFERENTE é intenção divergente.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(r.caseId, r.eventId, "op-can-1", 2, {
          cancelReason: "motivo completamente diferente",
        }),
      ),
      deps,
    ),
    "idempotency-conflict",
    "S: motivo divergente deveria conflitar",
  );

  // T — nova operação com token velho: stale.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(r.caseId, r.eventId, "op-can-9", 1, {
          cancelReason: "outro",
        }),
      ),
      deps,
    ),
    "conflict",
    "T: nova operação com token velho deveria falhar stale",
  );
}

async function testCancelIntegrityAndAuthorization() {
  const base = await seedDraftEvent();
  const reason = {cancelReason: "motivo válido"};

  // U — evento inexistente.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(base.caseId, "ce_naoexiste", "op-u", 1, reason),
      ),
      depsFor({db: base.db, now: T1}),
    ),
    "not-found",
    "U: evento inexistente",
  );

  // V — revision armazenada malformada.
  const v = await seedDraftEvent();
  const vev = eventOf(v.db, v.eventPath);
  delete vev.revision;
  v.db._store.set(v.eventPath, vev);
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(mutationCmd(v.caseId, v.eventId, "op-v", 1, reason)),
      depsFor({db: v.db, now: T1}),
    ),
    "integrity",
    "V: revision armazenada ausente",
  );

  // W/X/Y/Z/AA — escopo e capability.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(base.caseId, base.eventId, "op-w", 1, reason),
      ),
      depsFor({db: base.db, now: T1, dogAccess: false}),
    ),
    "permission-denied",
    "W: escopo de K9 negado",
  );
  const denials: Array<[string, Parameters<typeof depsFor>[0]]> = [
    ["X: sem amend_clinical", {db: base.db, allowAmend: false}],
    [
      "Y: só finalize_clinical",
      {db: base.db, allowFinalize: true, allowAmend: false},
    ],
    [
      "Z: só record_clinical",
      {db: base.db, allowRecord: true, allowFinalize: false, allowAmend: false},
    ],
    [
      "AA: health.read apenas",
      {db: base.db, allowRecord: false, allowFinalize: false, allowAmend: false},
    ],
    ["AB: admin sem grant", {db: base.db, admin: true, allowAmend: false}],
  ];
  for (const [label, opts] of denials) {
    await expectReject(
      () => runHealthCancelClinicalEvent(
        mockRequest(
          mutationCmd(base.caseId, base.eventId, "op-c", 1, reason),
        ),
        depsFor({...opts, now: T1}),
      ),
      "permission-denied",
      label,
    );
  }

  // AC — injeção server-owned.
  for (const forged of [
    {status: "cancelled"},
    {cancelled_at: "2020-01-01T00:00:00.000Z"},
    {cancelledAt: 1},
    {cancelled_by: {uid: "x"}},
    {cancel_reason: "injetado"},
    {updated_at: 1},
    {finalized_at: 1},
  ]) {
    const before = {...eventOf(base.db, base.eventPath)};
    await expectReject(
      () => runHealthCancelClinicalEvent(
        mockRequest(
          mutationCmd(base.caseId, base.eventId, "op-inj", 1, {
            ...reason,
            ...forged,
          } as JsonMap),
        ),
        depsFor({db: base.db, now: T1}),
      ),
      "validation",
      `AC: injeção de ${Object.keys(forged)[0]}`,
    );
    assert.deepStrictEqual(
      eventOf(base.db, base.eventPath),
      before,
      `AC: injeção de ${Object.keys(forged)[0]} escreveu`,
    );
  }

  // AD — receipt malformado.
  const m = await seedDraftEvent();
  m.db._store.set(`${m.casePath}/operations/op-mal`, {
    kind: "clinical_event_cancel_v1",
    operation_id: "op-mal",
    operation_type: "cancel_clinical_event",
    actor_uid: actor.uid,
    // fingerprint ausente = receipt corrompido
    result: {},
  });
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(mutationCmd(m.caseId, m.eventId, "op-mal", 1, reason)),
      depsFor({db: m.db, now: T1}),
    ),
    "integrity",
    "AD: receipt malformado deveria falhar fechado",
  );
  assert.strictEqual(
    eventOf(m.db, m.eventPath).status,
    "draft",
    "AD: evento mutado apesar de receipt corrompido",
  );
}

/**
 * ISOLA a precondição de concorrência de qualquer outra causa de rejeição.
 *
 * Necessário porque um evento já `final` recusa uma nova finalização por DUAS
 * razões independentes — token velho E transição ilegal — e ambas mapeiam para
 * `conflict`. Um teste que só olhasse o código não distinguiria as duas, e a
 * remoção do stale-check passaria despercebida.
 *
 * Aqui a transição continua LEGAL (`draft → final`, `draft → cancelled`) e o
 * token é a ÚNICA coisa errada: outro writer avançou `updated_at` enquanto o
 * chamador olhava a versão antiga. Se o stale-check for removido, estas
 * mutações passam a ser aceitas e o teste falha.
 */
async function testStaleTokenIsTheSoleRejectionCause() {
  // FINALIZE — draft com token avançado por terceiro.
  const f = await seedDraftEvent();
  const fev = eventOf(f.db, f.eventPath);
  const advanced = Timestamp.fromMillis(f.t0 + 5000);
  fev.updated_at = advanced;
  fev.revision = 7;
  f.db._store.set(f.eventPath, fev);
  assert.strictEqual(fev.status, "draft", "pré-condição: evento segue draft");

  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(f.caseId, f.eventId, "op-stale-f", 1)),
      depsFor({db: f.db, now: T1}),
    ),
    "conflict",
    "FINALIZE: token velho com transição legal deve falhar stale",
  );
  const fAfter = eventOf(f.db, f.eventPath);
  assert.strictEqual(
    fAfter.status,
    "draft",
    "FINALIZE stale mutou o evento apesar do token velho",
  );
  assert.strictEqual(
    (fAfter.updated_at as Timestamp).toMillis(),
    advanced.toMillis(),
    "FINALIZE stale sobrescreveu o token de terceiro",
  );
  assert.strictEqual(
    fAfter.finalized_at,
    undefined,
    "FINALIZE stale persistiu finalized_at",
  );

  // Com o token CORRETO a mesma transição é aceita: prova que a rejeição acima
  // veio do token e não de uma proibição estrutural.
  await runHealthFinalizeClinicalEvent(
    mockRequest(
      mutationCmd(f.caseId, f.eventId, "op-fresh-f", 7),
    ),
    depsFor({db: f.db, now: T1}),
  );
  assert.strictEqual(
    eventOf(f.db, f.eventPath).status,
    "final",
    "token correto deveria permitir a MESMA transição",
  );

  // CANCEL — mesma isolação.
  const c = await seedDraftEvent();
  const cev = eventOf(c.db, c.eventPath);
  const cAdvanced = Timestamp.fromMillis(c.t0 + 5000);
  cev.updated_at = cAdvanced;
  cev.revision = 7;
  c.db._store.set(c.eventPath, cev);

  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(c.caseId, c.eventId, "op-stale-c", 1, {
          cancelReason: "motivo válido",
        }),
      ),
      depsFor({db: c.db, now: T1}),
    ),
    "conflict",
    "CANCEL: token velho com transição legal deve falhar stale",
  );
  assert.strictEqual(
    eventOf(c.db, c.eventPath).status,
    "draft",
    "CANCEL stale mutou o evento",
  );

  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(c.caseId, c.eventId, "op-fresh-c", 7, {
        cancelReason: "motivo válido",
      }),
    ),
    depsFor({db: c.db, now: T1}),
  );
  assert.strictEqual(
    eventOf(c.db, c.eventPath).status,
    "cancelled",
    "token correto deveria permitir o MESMO cancelamento",
  );
}

/**
 * Validação de entrada acontece ANTES de qualquer trabalho no Firestore.
 *
 * O domínio congelado também recusa motivo vazio, então sem esta asserção a
 * verificação de fronteira seria redundante e poderia ser removida sem quebrar
 * nada. A propriedade real é: um comando malformado nunca abre transação.
 */
async function testMalformedInputRejectedBeforeAnyRead() {
  const s = await seedDraftEvent();
  const txBefore = s.db._transactions();

  const bad: Array<[JsonMap, string]> = [
    [{cancelReason: "   "}, "motivo em branco"],
    [{cancelReason: ""}, "motivo vazio"],
    [{}, "motivo ausente"],
  ];
  for (const [extra, label] of bad) {
    await expectReject(
      () => runHealthCancelClinicalEvent(
        mockRequest(
          mutationCmd(s.caseId, s.eventId, "op-pre", 1, extra),
        ),
        depsFor({db: s.db, now: T1}),
      ),
      "validation",
      `CANCEL ${label}`,
    );
  }
  assert.strictEqual(
    s.db._transactions(),
    txBefore,
    "entrada malformada abriu transação no Firestore",
  );

  // Idem para o token de requisição no finalize.
  const cmdNoToken = mutationCmd(s.caseId, s.eventId, "op-pre2", 1);
  delete cmdNoToken.expectedRevision;
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(cmdNoToken),
      depsFor({db: s.db, now: T1}),
    ),
    "validation",
    "FINALIZE sem expectedRevision",
  );
  assert.strictEqual(
    s.db._transactions(),
    txBefore,
    "token ausente abriu transação no Firestore",
  );
}

// ── AMENDMENTS (W5) ────────────────────────────────────────────────────────

const T2 = new Date("2026-08-17T15:45:00.000Z");
const T3 = new Date("2026-08-18T08:15:00.000Z");

/** Cria um evento e o FINALIZA: o único estado emendável. */
async function seedFinalEvent(options: {admin?: boolean} = {}) {
  const s = await seedDraftEvent(options);
  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(s.caseId, s.eventId, "op-seed-fin", 1)),
    depsFor({db: s.db, now: T1, admin: options.admin}),
  );
  const ev = eventOf(s.db, s.eventPath);
  return {
    ...s,
    tFinal: (ev.updated_at as Timestamp).toMillis(),
    finalizedAt: (ev.finalized_at as Timestamp).toMillis(),
  };
}

const amendCmd = (
  caseId: string,
  eventId: string,
  operationId: string,
  expectedRevision: number,
  extra: JsonMap = {},
): JsonMap => ({
  dogId: "dog-1",
  caseId,
  eventId,
  operationId,
  expectedRevision,
  amendmentType: "correction",
  reason: "corrige dose registrada",
  content: {notes: "dose correta: 5mg"},
  ...extra,
});

const amendKeys = (
  db: {_store: Map<string, JsonMap>},
  eventPath: string,
): string[] =>
  [...db._store.keys()]
    .filter((k) => k.startsWith(`${eventPath}/clinical_amendments/`))
    .sort();

/**
 * Campos clínicos do PAI que uma emenda nunca pode tocar.
 *
 * Não é `CONTENT_FIELDS`: aquele conjunto trata `has_amendments`/`amendment_count`
 * como imutáveis, o que vale para finalize/cancel mas NÃO para a emenda — esses
 * dois são exatamente os metadados derivados que o W5 tem autoridade para mover.
 * Confundir os dois conjuntos tornaria o teste de preservação de conteúdo
 * impossível de satisfazer, ou (pior) mascararia uma reescrita real.
 */
const AMEND_IMMUTABLE_PARENT_FIELDS = [
  "dog_id",
  "case_id",
  "entity_kind",
  "event_type",
  "occurred_at",
  "recorded_at",
  "recorded_by",
  "payload_type",
  "payload_version",
  "content",
  "schema_version",
  "status",
  "finalized_at",
];

function assertParentClinicalPayloadPreserved(
  before: JsonMap,
  after: JsonMap,
  label: string,
): void {
  for (const f of AMEND_IMMUTABLE_PARENT_FIELDS) {
    assert.deepStrictEqual(
      after[f],
      before[f],
      `${label}: campo clínico do pai alterado: ${f}`,
    );
  }
}

async function testAmendSuccessAndParentMetadata() {
  const s = await seedFinalEvent();
  const before = {...eventOf(s.db, s.eventPath)};
  const caseBefore = {...(s.db._store.get(s.casePath) as JsonMap)};
  const auditsBefore = auditKeys(s.db).length;
  const opsBefore = opKeys(s.db, s.casePath).length;

  const res = (await runHealthAmendClinicalEvent(
    mockRequest(
      amendCmd(s.caseId, s.eventId, "op-am-1", 2, {
        reason: "   corrige a dose registrada   ",
      }),
    ),
    depsFor({db: s.db, now: T2}),
  )) as JsonMap;

  // 1/2 — emenda criada no caminho canônico aninhado.
  assert.strictEqual(res.was_no_op, false, "1: primeira emenda não é no-op");
  const paths = amendKeys(s.db, s.eventPath);
  assert.strictEqual(paths.length, 1, "2: esperava 1 emenda, obtive " + paths.length);
  const amendPath = paths[0];
  assert.ok(
    /\/clinical_amendments\/ca_[0-9a-f]{28}$/.test(amendPath),
    "2: caminho/ID canônico divergente: " + amendPath,
  );
  // Nunca o caminho histórico.
  assert.strictEqual(
    [...s.db._store.keys()].some((k) => /\/amendments\//.test(k)),
    false,
    "2: coleção histórica /amendments/ foi usada",
  );

  const after = eventOf(s.db, s.eventPath);
  // 3/4 — pai continua final, conteúdo original intacto.
  assert.strictEqual(after.status, "final", "3: status do pai mudou");
  assertParentClinicalPayloadPreserved(before, after, "4");
  assert.strictEqual(
    (after.finalized_at as Timestamp).toMillis(),
    s.finalizedAt,
    "15: finalized_at alterado",
  );

  // 5..9 — shape exato da emenda.
  const a = s.db._store.get(amendPath) as JsonMap;
  assert.deepStrictEqual(
    Object.keys(a).sort(),
    ["content", "payload_type", "payload_version", "reason", "recorded_at",
      "recorded_by", "schema_version", "type"].sort(),
    "5: shape da emenda divergente: " + JSON.stringify(Object.keys(a)),
  );
  assert.strictEqual(a.type, "correction", "6: type");
  assert.strictEqual(a.reason, "corrige a dose registrada", "7: reason não trimado");
  assert.strictEqual(
    (a.recorded_at as Timestamp).toMillis(),
    T2.getTime(),
    "8: recorded_at não é do servidor",
  );
  assert.deepStrictEqual(
    a.recorded_by,
    {uid: actor.uid, name: actor.name, internal_role: "condutor"},
    "9: recorded_by não é server-derived",
  );
  // payload herdado do pai, não do cliente.
  assert.strictEqual(a.payload_type, before.payload_type, "payload_type herdado");
  assert.strictEqual(a.payload_version, before.payload_version, "payload_version herdado");
  assert.strictEqual(a.schema_version, 1, "schema_version");
  // `professional` NÃO existe na v1 congelada da emenda.
  assert.strictEqual(a.professional, undefined, "professional não pertence à emenda v1");
  assert.deepStrictEqual(a.content, {notes: "dose correta: 5mg"}, "content da emenda");

  // 11..14 — metadados derivados do pai.
  assert.strictEqual(after.has_amendments, true, "11: has_amendments");
  assert.strictEqual(after.amendment_count, 1, "12: amendment_count");
  const lastAmended = after.last_amended_at as Timestamp;
  assert.ok(lastAmended && typeof lastAmended.toMillis === "function", "13: last_amended_at");
  assert.strictEqual(lastAmended.toMillis(), T2.getTime(), "13: instante do servidor");
  assert.strictEqual(
    (after.updated_at as Timestamp).toMillis(),
    lastAmended.toMillis(),
    "14: updated_at != last_amended_at",
  );

  // 16..18 — caso intacto, um receipt, um audit.
  assert.deepStrictEqual(
    s.db._store.get(s.casePath),
    caseBefore,
    "16: documento do caso foi alterado",
  );
  assert.strictEqual(
    opKeys(s.db, s.casePath).length,
    opsBefore + 1,
    "17: receipts != +1",
  );
  assert.ok(
    opKeys(s.db, s.casePath).includes(`${s.casePath}/operations/op-am-1`),
    "17: receipt case-scoped ausente",
  );
  assert.strictEqual(
    auditKeys(s.db).length,
    auditsBefore + 1,
    "18: audits != +1",
  );
  const audit = s.db._store.get(
    auditKeys(s.db).find((k) => {
      const x = s.db._store.get(k) as JsonMap;
      return x.action === "clinical_event_amended";
    }) as string,
  ) as JsonMap;
  assert.ok(audit, "18: audit de emenda ausente");
  const meta = audit.metadata as JsonMap;
  assert.strictEqual(meta.amendment_type, "correction", "audit: tipo");
  assert.strictEqual(meta.amendment_count, 1, "audit: contagem");
  assert.strictEqual(meta.event_status, "final", "audit: status do pai");
  assert.strictEqual(audit.entity_type, "clinical_amendments", "audit: entity_type");
}

async function testSecondAmendmentIsSibling() {
  const s = await seedFinalEvent();
  await runHealthAmendClinicalEvent(
    mockRequest(amendCmd(s.caseId, s.eventId, "op-am-1", 2)),
    depsFor({db: s.db, now: T2}),
  );
  const firstPath = amendKeys(s.db, s.eventPath)[0];
  const firstDoc = {...(s.db._store.get(firstPath) as JsonMap)};
  const tokenAfterFirst = eventOf(s.db, s.eventPath).revision as number;

  // 19/20 — segunda emenda legítima com token renovado.
  await runHealthAmendClinicalEvent(
    mockRequest(
      amendCmd(s.caseId, s.eventId, "op-am-2", tokenAfterFirst, {
        amendmentType: "addendum",
        reason: "acrescenta observação do plantão",
        content: {notes: "reavaliar em 24h"},
      }),
    ),
    depsFor({db: s.db, now: T3}),
  );
  const after = eventOf(s.db, s.eventPath);
  assert.strictEqual(after.amendment_count, 2, "19: contagem != 2");
  assert.strictEqual(after.has_amendments, true, "19: has_amendments");
  assert.strictEqual(
    (after.last_amended_at as Timestamp).toMillis(),
    T3.getTime(),
    "20: last_amended_at não avançou",
  );
  assert.strictEqual(after.status, "final", "pai deixou de ser final");

  // 21/22 — a primeira emenda permanece imutável e ambas coexistem.
  const all = amendKeys(s.db, s.eventPath);
  assert.strictEqual(all.length, 2, "21: esperava 2 emendas irmãs");
  assert.deepStrictEqual(
    s.db._store.get(firstPath),
    firstDoc,
    "22: a primeira emenda foi reescrita",
  );
  // Modelo causal PLANO: nada aninhado sob uma emenda.
  assert.strictEqual(
    [...s.db._store.keys()].some((k) =>
      /\/clinical_amendments\/[^/]+\/clinical_amendments\//.test(k)),
    false,
    "modelo recursivo de emenda-de-emenda apareceu",
  );
}

async function testAmendParentEligibility() {
  // 23 — draft negado.
  const d = await seedDraftEvent();
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(d.caseId, d.eventId, "op-am-d", 1)),
      depsFor({db: d.db, now: T2}),
    ),
    "conflict",
    "23: draft deveria negar emenda",
  );
  assert.strictEqual(
    amendKeys(d.db, d.eventPath).length,
    0,
    "23: emenda criada sobre draft",
  );
  assert.strictEqual(
    eventOf(d.db, d.eventPath).has_amendments,
    false,
    "23: metadados do draft mutados",
  );

  // 24 — cancelled negado.
  const c = await seedDraftEvent();
  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(c.caseId, c.eventId, "op-can", 1, {cancelReason: "erro"}),
    ),
    depsFor({db: c.db, now: T1}),
  );
  const cTok = eventOf(c.db, c.eventPath).revision as number;
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(c.caseId, c.eventId, "op-am-c", cTok)),
      depsFor({db: c.db, now: T2}),
    ),
    "conflict",
    "24: cancelled deveria negar emenda",
  );
  assert.strictEqual(amendKeys(c.db, c.eventPath).length, 0, "24: emenda criada");

  // 25 — evento inexistente.
  const s = await seedFinalEvent();
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(s.caseId, "ce_naoexiste", "op-am-x", 2)),
      depsFor({db: s.db, now: T2}),
    ),
    "not-found",
    "25: evento inexistente",
  );

  // 26 — status persistido corrompido.
  const k = await seedFinalEvent();
  const kev = eventOf(k.db, k.eventPath);
  kev.status = "meio_final";
  k.db._store.set(k.eventPath, kev);
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(k.caseId, k.eventId, "op-am-k", 2)),
      depsFor({db: k.db, now: T2}),
    ),
    "validation",
    "26: status corrompido deveria falhar fechado",
  );
  assert.strictEqual(amendKeys(k.db, k.eventPath).length, 0, "26: emenda criada");
}

async function testAmendConcurrency() {
  const s = await seedFinalEvent();

  // 27/28 — token obrigatório e malformado.
  const bad: Array<[unknown, string]> = [
    [undefined, "27: ausente"],
    ["1755259200000", "28: string"],
    [1.5, "28: fracionário"],
    [Number.NaN, "28: NaN"],
    [-1, "28: negativo"],
  ];
  for (const [v, label] of bad) {
    const c = amendCmd(s.caseId, s.eventId, "op-am-t", 2);
    if (v === undefined) delete c.expectedRevision;
    else c.expectedRevision = v;
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(c),
        depsFor({db: s.db, now: T2}),
      ),
      "validation",
      "CONCURRENCY " + label,
    );
  }
  assert.strictEqual(amendKeys(s.db, s.eventPath).length, 0, "token inválido criou emenda");

  // 29 — revision armazenada malformada (inclui 0, sem tolerância legada).
  for (const corrupt of [undefined, "2", 0, -1, 1.5, true] as unknown[]) {
    const m = await seedFinalEvent();
    const ev = eventOf(m.db, m.eventPath);
    if (corrupt === undefined) delete ev.revision;
    else ev.revision = corrupt as never;
    m.db._store.set(m.eventPath, ev);
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(m.caseId, m.eventId, "op-am-s", 2)),
        depsFor({db: m.db, now: T2}),
      ),
      "integrity",
      "29: revision armazenada inválida (" + String(corrupt) + ")",
    );
    assert.strictEqual(amendKeys(m.db, m.eventPath).length, 0, "29: emenda criada");
  }

  // 30 — token velho (transição legal, token é a ÚNICA falha).
  const st = await seedFinalEvent();
  const stev = eventOf(st.db, st.eventPath);
  const advanced = Timestamp.fromMillis(st.tFinal + 5000);
  stev.updated_at = advanced;
  stev.revision = 7;
  st.db._store.set(st.eventPath, stev);
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(st.caseId, st.eventId, "op-am-stale", 2)),
      depsFor({db: st.db, now: T2}),
    ),
    "conflict",
    "30: token velho deveria falhar stale",
  );
  assert.strictEqual(amendKeys(st.db, st.eventPath).length, 0, "30: emenda criada");
  assert.strictEqual(
    eventOf(st.db, st.eventPath).amendment_count,
    0,
    "30: contagem incrementada por requisição stale",
  );
  // Com o token correto a MESMA emenda é aceita: prova que a rejeição foi do token.
  await runHealthAmendClinicalEvent(
    mockRequest(
      amendCmd(st.caseId, st.eventId, "op-am-fresh", 7),
    ),
    depsFor({db: st.db, now: T2}),
  );
  assert.strictEqual(
    eventOf(st.db, st.eventPath).amendment_count,
    1,
    "token correto deveria permitir a mesma emenda",
  );

  // 31..33 — replay com token PRE-mutação.
  const r = await seedFinalEvent();
  const cmd = amendCmd(r.caseId, r.eventId, "op-am-1", 2);
  await runHealthAmendClinicalEvent(mockRequest(cmd), depsFor({db: r.db, now: T2}));
  const tokenAfter = (eventOf(r.db, r.eventPath).updated_at as Timestamp).toMillis();
  const amendsAfter = amendKeys(r.db, r.eventPath).length;
  const auditsAfter = auditKeys(r.db).length;
  const opsAfter = opKeys(r.db, r.casePath).length;

  const replay = (await runHealthAmendClinicalEvent(
    mockRequest(cmd),
    depsFor({db: r.db, now: T3}),
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "31: replay não sinalizou no-op");
  const afterReplay = eventOf(r.db, r.eventPath);
  assert.strictEqual(afterReplay.amendment_count, 1, "32: replay incrementou a contagem");
  assert.strictEqual(
    (afterReplay.updated_at as Timestamp).toMillis(),
    tokenAfter,
    "33: replay avançou o token",
  );
  assert.strictEqual(
    (afterReplay.last_amended_at as Timestamp).toMillis(),
    T2.getTime(),
    "33: replay avançou last_amended_at",
  );
  assert.strictEqual(amendKeys(r.db, r.eventPath).length, amendsAfter, "31: replay duplicou emenda");
  assert.strictEqual(auditKeys(r.db).length, auditsAfter, "31: replay duplicou audit");
  assert.strictEqual(opKeys(r.db, r.casePath).length, opsAfter, "31: replay duplicou receipt");

  // 34 — operação NOVA com token velho.
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(r.caseId, r.eventId, "op-am-9", 2)),
      depsFor({db: r.db, now: T3}),
    ),
    "conflict",
    "34: nova operação com token velho",
  );
  assert.strictEqual(
    eventOf(r.db, r.eventPath).amendment_count,
    1,
    "34: stale incrementou a contagem",
  );
}

async function testAmendIdempotencyAndReceipts() {
  const s = await seedFinalEvent();
  const base = amendCmd(s.caseId, s.eventId, "op-am-1", 2);
  await runHealthAmendClinicalEvent(mockRequest(base), depsFor({db: s.db, now: T2}));
  const tok = eventOf(s.db, s.eventPath).revision as number;
  const countBefore = eventOf(s.db, s.eventPath).amendment_count;

  // 35..37 — mesma operationId, intenção divergente.
  const divergent: Array<[string, JsonMap]> = [
    ["35: tipo diferente", {amendmentType: "addendum"}],
    ["36: motivo diferente", {reason: "outro motivo completamente distinto"}],
    ["37: conteúdo diferente", {content: {notes: "conteúdo diferente"}}],
  ];
  for (const [label, extra] of divergent) {
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(s.caseId, s.eventId, "op-am-1", tok, extra)),
        depsFor({db: s.db, now: T3}),
      ),
      "idempotency-conflict",
      label,
    );
  }
  assert.strictEqual(
    eventOf(s.db, s.eventPath).amendment_count,
    countBefore,
    "conflito alterou a contagem",
  );
  assert.strictEqual(amendKeys(s.db, s.eventPath).length, 1, "conflito criou emenda");

  // Ordem de chaves do content NÃO muda a intenção lógica (serializador estável).
  const reordered = amendCmd(s.caseId, s.eventId, "op-am-1", tok, {
    content: {notes: "dose correta: 5mg"},
  });
  const replay = (await runHealthAmendClinicalEvent(
    mockRequest(reordered),
    depsFor({db: s.db, now: T3}),
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "content equivalente deveria replayar");

  // 38/39 — receipt malformado falha fechado e NÃO é sobrescrito.
  const m = await seedFinalEvent();
  const corrupt: JsonMap = {
    kind: "clinical_event_amend_v1",
    operation_id: "op-mal",
    // operation_type ausente
    actor_uid: actor.uid,
    fingerprint: "x",
    result: {},
  };
  m.db._store.set(`${m.casePath}/operations/op-mal`, corrupt);
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(m.caseId, m.eventId, "op-mal", 2)),
      depsFor({db: m.db, now: T2}),
    ),
    "integrity",
    "38: receipt malformado",
  );
  assert.strictEqual(amendKeys(m.db, m.eventPath).length, 0, "38: emenda criada");
  assert.deepStrictEqual(
    m.db._store.get(`${m.casePath}/operations/op-mal`),
    corrupt,
    "39: receipt corrompido foi sobrescrito",
  );

  // Emenda existente sem receipt = corrupção (ID determinístico).
  const o = await seedFinalEvent();
  const orphanId = (await (async () => {
    await runHealthAmendClinicalEvent(
      mockRequest(amendCmd(o.caseId, o.eventId, "op-orphan", 2)),
      depsFor({db: o.db, now: T2}),
    );
    return amendKeys(o.db, o.eventPath)[0];
  })());
  o.db._store.delete(`${o.casePath}/operations/op-orphan`);
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(
        amendCmd(
          o.caseId,
          o.eventId,
          "op-orphan",
          (eventOf(o.db, o.eventPath).updated_at as Timestamp).toMillis(),
        ),
      ),
      depsFor({db: o.db, now: T3}),
    ),
    "integrity",
    "emenda órfã deveria falhar fechado",
  );
  assert.ok(o.db._store.get(orphanId), "emenda órfã foi apagada");
}

async function testAmendAuthorizationAndInjection() {
  const s = await seedFinalEvent();

  // 40..43 — capability e escopo.
  const denials: Array<[string, Parameters<typeof depsFor>[0]]> = [
    ["40: sem amend_clinical", {db: s.db, allowAmend: false}],
    ["41: só record_clinical", {db: s.db, allowRecord: true, allowFinalize: false, allowAmend: false}],
    ["41: só finalize_clinical", {db: s.db, allowFinalize: true, allowAmend: false}],
    ["41: só health.read", {db: s.db, allowRecord: false, allowFinalize: false, allowAmend: false}],
    ["43: admin sem grant", {db: s.db, admin: true, allowAmend: false}],
  ];
  for (const [label, opts] of denials) {
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(s.caseId, s.eventId, "op-am-w", 2)),
        depsFor({...opts, now: T2}),
      ),
      "permission-denied",
      label,
    );
  }
  // 42 — escopo de K9 é gate independente.
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(s.caseId, s.eventId, "op-am-dog", 2)),
      depsFor({db: s.db, now: T2, allowAmend: true, dogAccess: false}),
    ),
    "permission-denied",
    "42: escopo de K9 negado",
  );
  assert.strictEqual(amendKeys(s.db, s.eventPath).length, 0, "negação criou emenda");
  assert.strictEqual(
    eventOf(s.db, s.eventPath).has_amendments,
    false,
    "negação mutou metadados do pai",
  );

  // 44..46 — injeção de identidade/servidor e substituição do pai.
  const forged: Array<[string, JsonMap]> = [
    ["status", {status: "draft"}],
    ["updated_at", {updated_at: 1}],
    ["updatedAt", {updatedAt: 1}],
    ["finalized_at", {finalized_at: 1}],
    ["finalizedAt", {finalizedAt: 1}],
    ["has_amendments", {has_amendments: true}],
    ["amendment_count", {amendment_count: 99}],
    ["last_amended_at", {last_amended_at: 1}],
    ["recorded_at", {recorded_at: 1}],
    ["recorded_by", {recorded_by: {uid: "x"}}],
    ["dog_id", {dog_id: "dog-2"}],
    ["case_id", {case_id: "cc_outro"}],
    ["event_id", {event_id: "ce_outro"}],
    ["amendment_id", {amendment_id: "ca_forjado"}],
    ["amendId", {amendId: "ca_forjado"}],
    ["schema_version", {schema_version: 2}],
    ["event_type", {event_type: "incident"}],
    ["eventType", {eventType: "incident"}],
    ["occurred_at", {occurred_at: "2026-01-01T00:00:00.000Z"}],
    ["occurredAt", {occurredAt: "2026-01-01T00:00:00.000Z"}],
    ["payload_type", {payload_type: "incident_v1"}],
    ["payloadType", {payloadType: "incident_v1"}],
    ["payload_version", {payload_version: 9}],
    ["professional", {professional: {name: "x"}}],
    ["attachment_refs", {attachment_refs: ["a"]}],
    ["attachmentRefs", {attachmentRefs: ["a"]}],
    ["chave desconhecida", {qualquerCoisa: 1}],
  ];
  for (const [label, extra] of forged) {
    const before = {...eventOf(s.db, s.eventPath)};
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(s.caseId, s.eventId, "op-am-inj", 2, extra)),
        depsFor({db: s.db, now: T2}),
      ),
      "validation",
      "44/45/46: injeção de " + label,
    );
    assert.deepStrictEqual(
      eventOf(s.db, s.eventPath),
      before,
      "injeção de " + label + " escreveu no pai",
    );
    assert.strictEqual(
      amendKeys(s.db, s.eventPath).length,
      0,
      "injeção de " + label + " criou emenda",
    );
  }

  // Vocabulário de emenda inválido / campos obrigatórios ausentes.
  const invalid: Array<[string, JsonMap]> = [
    ["tipo inválido", {amendmentType: "retificacao"}],
    ["tipo vazio", {amendmentType: ""}],
    ["motivo vazio", {reason: "   "}],
    ["content não-mapa", {content: "texto"}],
    ["content array", {content: []}],
  ];
  for (const [label, extra] of invalid) {
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(s.caseId, s.eventId, "op-am-v", 2, extra)),
        depsFor({db: s.db, now: T2}),
      ),
      "validation",
      "vocabulário: " + label,
    );
  }
  for (const missing of ["amendmentType", "reason", "content"]) {
    const c = amendCmd(s.caseId, s.eventId, "op-am-m", 2);
    delete c[missing];
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(c),
        depsFor({db: s.db, now: T2}),
      ),
      "validation",
      "campo obrigatório ausente: " + missing,
    );
  }
}

/** Metadados de emenda corrompidos no pai falham fechado, sem normalização. */
async function testAmendParentMetadataIntegrity() {
  const cases: Array<[string, JsonMap]> = [
    ["has_amendments não-booleano", {has_amendments: "sim"}],
    ["amendment_count string", {amendment_count: "1"}],
    ["amendment_count negativo", {amendment_count: -1}],
    ["amendment_count fracionário", {amendment_count: 1.5}],
    ["last_amended_at ilegível", {last_amended_at: "2026-08-17T00:00:00.000Z"}],
    ["contagem sem flag", {has_amendments: false, amendment_count: 3}],
  ];
  for (const [label, patch] of cases) {
    const s = await seedFinalEvent();
    const ev = eventOf(s.db, s.eventPath);
    Object.assign(ev, patch);
    s.db._store.set(s.eventPath, ev);
    await expectReject(
      () => runHealthAmendClinicalEvent(
        mockRequest(amendCmd(s.caseId, s.eventId, "op-am-i", 2)),
        depsFor({db: s.db, now: T2}),
      ),
      "integrity",
      "metadados corrompidos: " + label,
    );
    assert.strictEqual(
      amendKeys(s.db, s.eventPath).length,
      0,
      label + ": emenda criada apesar da corrupção",
    );
  }

  // Pai sem payload canônico não pode ser descrito por uma emenda.
  const p = await seedFinalEvent();
  const pev = eventOf(p.db, p.eventPath);
  delete pev.payload_type;
  p.db._store.set(p.eventPath, pev);
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(p.caseId, p.eventId, "op-am-p", 2)),
      depsFor({db: p.db, now: T2}),
    ),
    "integrity",
    "pai sem payload_type",
  );
}

/**
 * Guarda arquitetural: a emenda NUNCA escreve conteúdo clínico no pai.
 *
 * Estrutural, não só comportamental: se um dia o patch do pai passasse a
 * carregar um campo clínico, nenhum teste de caixa-preta necessariamente
 * falharia — este falha.
 */
async function testAmendWriterHasNoParentContentPath() {
  const src = stripComments(readSource("clinical_case_callables.ts"));
  const body = src.slice(src.indexOf("export async function runHealthAmendClinicalEvent"));

  assert.ok(body.includes("deps.requireAmendClinical("), "emenda exige amend_clinical");
  assert.strictEqual(
    body.includes("deps.requireRecordClinical(") ||
      body.includes("deps.requireFinalizeClinical("),
    false,
    "emenda não pode usar outra seam de capability",
  );

  // Ordem obrigatória: replay antes do stale-check.
  const replayAt = body.indexOf("matchClinicalReceipt(");
  const staleAt = body.indexOf("assertFreshRevision(");
  assert.ok(replayAt > 0 && staleAt > 0, "checagens ausentes");
  assert.ok(replayAt < staleAt, "stale-check precede o replay (ordenação P0 violada)");

  // O patch do pai é metadata-only: extrai o bloco tx.set(eRef, ...).
  // Line-ending agnostic: the source is checked out with CRLF on Windows, so a
  // literal "\n" here would never match and the guard would pass vacuously.
  const i = body.search(/tx\.set\(\s*eRef,/);
  assert.ok(i > 0, "patch do pai não encontrado");
  const patch = body.slice(i, body.indexOf("{merge: true},", i));
  for (const forbidden of ["content", "status", "finalized_at", "event_type",
    "occurred_at", "payload_type", "payload_version", "recorded_at", "recorded_by",
    "professional", "attachment_refs"]) {
    assert.strictEqual(
      new RegExp("\\b" + forbidden + "\\s*:").test(patch),
      false,
      `patch do pai contém campo proibido: ${forbidden}`,
    );
  }
  for (const required of ["has_amendments", "amendment_count", "last_amended_at",
    "updated_at"]) {
    assert.ok(
      new RegExp("\\b" + required + "\\s*:").test(patch),
      `patch do pai não escreve ${required}`,
    );
  }
  // Nenhum spread de payload do cliente no comando.
  assert.strictEqual(
    /\.\.\.\s*(data|input|request)/.test(body),
    false,
    "spread de payload do cliente presente na emenda",
  );
  // Caminho canônico, nunca o histórico. A coleção é construída no helper
  // `amendmentRef`, definido ANTES do comando — por isso a asserção da coleção
  // olha o módulo inteiro, e a do comando verifica que ele usa o helper.
  assert.ok(
    src.includes("collection(\"clinical_amendments\")"),
    "coleção canônica clinical_amendments ausente no writer",
  );
  assert.ok(
    body.includes("amendmentRef(deps.db"),
    "o comando não usa o helper canônico amendmentRef",
  );
  assert.strictEqual(
    /collection\("amendments"\)/.test(src),
    false,
    "coleção histórica amendments presente no writer",
  );
  // Create-only: nenhum callable de update/delete de emenda.
  for (const forbidden of ["runHealthUpdateClinicalAmendment",
    "runHealthDeleteClinicalAmendment", "runHealthCancelClinicalAmendment"]) {
    assert.strictEqual(src.includes(forbidden), false, `writer expõe ${forbidden}`);
  }
  // O wiring real liga a capability exata E entrega as deps canônicas intactas.
  //
  // Verificar apenas a string da capability não bastaria: o callable poderia
  // sobrescrever `requireAmendClinical` no ponto de injeção e passar a exigir
  // outra autoridade sem que nenhuma string mudasse.
  const index = stripComments(readSource("index.ts"));
  assert.ok(
    index.includes("healthAmendClinicalEvent = onCall"),
    "index não exporta healthAmendClinicalEvent",
  );
  const wiring = index.slice(index.indexOf("healthAmendClinicalEvent = onCall"));
  const call = wiring.slice(0, wiring.indexOf("});") + 3);
  assert.ok(
    /runHealthAmendClinicalEvent\(request,\s*clinicalCaseDeps\)/.test(call),
    "a emenda deve receber clinicalCaseDeps sem sobrescrita: " + call,
  );
  assert.strictEqual(
    /\.\.\.\s*clinicalCaseDeps/.test(call),
    false,
    "wiring da emenda sobrescreve deps canônicas",
  );
  assert.ok(
    index.includes("requireClinicalCapability(auth, \"amend_clinical\")"),
    "index deve ligar amend_clinical",
  );
}

/** §20 — nenhuma capability clínica implica outra. */
async function testCrossCapabilityMatrix() {
  const matrix: Array<{
    label: string;
    opts: Omit<Parameters<typeof depsFor>[0], "db">;
    finalize: "allow" | "deny";
    cancel: "allow" | "deny";
  }> = [
    {
      label: "só record_clinical",
      opts: {allowRecord: true, allowFinalize: false, allowAmend: false},
      finalize: "deny",
      cancel: "deny",
    },
    {
      label: "só finalize_clinical",
      opts: {allowRecord: false, allowFinalize: true, allowAmend: false},
      finalize: "allow",
      cancel: "deny",
    },
    {
      label: "só amend_clinical",
      opts: {allowRecord: false, allowFinalize: false, allowAmend: true},
      finalize: "deny",
      cancel: "allow",
    },
    {
      label: "somente leitura",
      opts: {allowRecord: false, allowFinalize: false, allowAmend: false},
      finalize: "deny",
      cancel: "deny",
    },
    {
      label: "admin sem grant clínico",
      opts: {
        admin: true,
        allowRecord: false,
        allowFinalize: false,
        allowAmend: false,
      },
      finalize: "deny",
      cancel: "deny",
    },
  ];

  for (const row of matrix) {
    // FINALIZE
    const f = await seedDraftEvent();
    if (row.finalize === "allow") {
      await runHealthFinalizeClinicalEvent(
        mockRequest(mutationCmd(f.caseId, f.eventId, "op-m", 1)),
        depsFor({db: f.db, ...row.opts, now: T1}),
      );
      assert.strictEqual(
        eventOf(f.db, f.eventPath).status,
        "final",
        `${row.label}: finalize deveria ser permitido`,
      );
    } else {
      await expectReject(
        () => runHealthFinalizeClinicalEvent(
          mockRequest(mutationCmd(f.caseId, f.eventId, "op-m", 1)),
          depsFor({db: f.db, ...row.opts, now: T1}),
        ),
        "permission-denied",
        `${row.label}: finalize deveria ser negado`,
      );
    }

    // CANCEL
    const c = await seedDraftEvent();
    const cmd = mutationCmd(c.caseId, c.eventId, "op-m", 1, {
      cancelReason: "matriz",
    });
    if (row.cancel === "allow") {
      await runHealthCancelClinicalEvent(
        mockRequest(cmd),
        depsFor({db: c.db, ...row.opts, now: T1}),
      );
      assert.strictEqual(
        eventOf(c.db, c.eventPath).status,
        "cancelled",
        `${row.label}: cancel deveria ser permitido`,
      );
    } else {
      await expectReject(
        () => runHealthCancelClinicalEvent(
          mockRequest(cmd),
          depsFor({db: c.db, ...row.opts, now: T1}),
        ),
        "permission-denied",
        `${row.label}: cancel deveria ser negado`,
      );
    }
  }
}

/**
 * Guarda arquitetural: cada comando de mutação usa sua PRÓPRIA seam de
 * capability. Se um deles voltasse a chamar `requireRecordClinical`, a
 * separação de autoridade viraria decorativa e nenhum teste de caixa-preta
 * necessariamente falharia.
 */
async function testMutationCommandsUseDedicatedCapabilitySeams() {
  const src = stripComments(readSource("clinical_case_callables.ts"));
  const finalize = src.slice(src.indexOf("export async function runHealthFinalizeClinicalEvent"));
  const finalizeBody = finalize.slice(0, finalize.indexOf("export async function runHealthCancelClinicalEvent"));
  const cancelBody = src.slice(src.indexOf("export async function runHealthCancelClinicalEvent"));

  assert.ok(
    finalizeBody.includes("deps.requireFinalizeClinical("),
    "finalize deve exigir requireFinalizeClinical",
  );
  assert.strictEqual(
    finalizeBody.includes("deps.requireRecordClinical("),
    false,
    "finalize não pode usar requireRecordClinical",
  );
  assert.strictEqual(
    finalizeBody.includes("deps.requireAmendClinical("),
    false,
    "finalize não pode usar requireAmendClinical",
  );

  assert.ok(
    cancelBody.includes("deps.requireAmendClinical("),
    "cancel deve exigir requireAmendClinical",
  );
  assert.strictEqual(
    cancelBody.includes("deps.requireRecordClinical("),
    false,
    "cancel não pode usar requireRecordClinical",
  );
  assert.strictEqual(
    cancelBody.includes("deps.requireFinalizeClinical("),
    false,
    "cancel não pode usar requireFinalizeClinical",
  );

  // Ordenação obrigatória: replay ANTES do stale-check, nos dois comandos.
  for (const [label, body] of [
    ["finalize", finalizeBody],
    ["cancel", cancelBody],
  ] as Array<[string, string]>) {
    const replayAt = body.indexOf("matchClinicalReceipt(");
    const staleAt = body.indexOf("assertFreshRevision(");
    assert.ok(replayAt > 0, `${label}: matchClinicalReceipt ausente`);
    assert.ok(staleAt > 0, `${label}: assertFreshRevision ausente`);
    assert.ok(
      replayAt < staleAt,
      `${label}: stale-check precede o replay (ordenação P0 violada)`,
    );
  }

  // O wiring real precisa ligar as capabilities exatas.
  const index = stripComments(readSource("index.ts"));
  assert.ok(
    index.includes("requireClinicalCapability(auth, \"finalize_clinical\")"),
    "index deve ligar finalize_clinical",
  );
  assert.ok(
    index.includes("requireClinicalCapability(auth, \"amend_clinical\")"),
    "index deve ligar amend_clinical",
  );
}

/**
 * REVISION as the sole optimistic-concurrency authority
 * (CLIN-WRITER-1.W6.P0.F1.C1).
 *
 * Every mutation here runs on ONE IDENTICAL clock instant on purpose. F1.C0
 * proved the previous `updated_at.toMillis()` token could not distinguish a
 * stale caller from a fresh one when two successful mutations shared a
 * millisecond, which let a DISTINCT stale operation through and broke W5's
 * frozen "exactly one winner" contract. These guards fail if the authority ever
 * regresses to a wall-clock value: the old token would compare equal here.
 *
 * Deliberately NOT using the hourly `t0..t4` spacing of the older concurrency
 * tests — that spacing is exactly why the defect stayed hidden.
 */
async function testRevisionConcurrencyAuthority() {
  const FIXED = new Date("2026-09-01T12:00:00.000Z");

  // ── creation: both aggregates are born at revision 1 ────────────────────────
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED}),
  )) as JsonMap;
  const caseId = openRes.case_id as string;
  const casePath = `dogs/dog-1/clinical_cases/${caseId}`;
  const openingPath =
    `${casePath}/clinical_events/${openRes.opening_event_id as string}`;
  assert.strictEqual(
    (db._store.get(casePath) as JsonMap).revision, 1,
    "OPEN: case nasce em revision 1",
  );
  assert.strictEqual(
    eventOf(db, openingPath).revision, 1,
    "OPEN: evento de abertura nasce em revision 1",
  );

  // ── W3 APPEND advances the CASE revision; the new event is born at 1 ────────
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId)),
    depsFor({db, now: FIXED}),
  );
  assert.strictEqual(
    (db._store.get(casePath) as JsonMap).revision, 2,
    "APPEND: case revision 1 -> 2 no MESMO milissegundo",
  );
  const appendedPath =
    `${casePath}/clinical_events/${eventIdFor("dog-1", caseId, "op-append-1")}`;
  assert.strictEqual(
    eventOf(db, appendedPath).revision, 1,
    "APPEND: evento anexado nasce em revision 1",
  );
  // A second distinct append advances it again — same instant.
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId, {operationId: "op-append-2"})),
    depsFor({db, now: FIXED}),
  );
  assert.strictEqual(
    (db._store.get(casePath) as JsonMap).revision, 3,
    "APPEND: segundo append avança para 3 (relógio irrelevante)",
  );
  // Replay must NOT advance it.
  await runHealthAppendClinicalEvent(
    mockRequest(appendPayload(caseId, {operationId: "op-append-2"})),
    depsFor({db, now: FIXED}),
  );
  assert.strictEqual(
    (db._store.get(casePath) as JsonMap).revision, 3,
    "APPEND replay: revision NÃO avança",
  );

  // ── D: W4 stale-after-finalize, one clock instant ──────────────────────────
  const d = await seedDraftEvent();
  const dDeps = depsFor({db: d.db, now: FIXED});
  const finRes = (await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(d.caseId, d.eventId, "op-c1-fin", 1)),
    dDeps,
  )) as JsonMap;
  assert.strictEqual(finRes.revision, 2, "FINALIZE: response revision = 2");
  assert.strictEqual(
    eventOf(d.db, d.eventPath).revision, 2,
    "FINALIZE: stored revision = 2",
  );
  // A DISTINCT operation still holding revision 1 must fail stale, even though
  // its clock instant is identical to the winner's.
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(d.caseId, d.eventId, "op-c1-stale", 1)),
      dDeps,
    ),
    "conflict",
    "D: operação distinta com revision pré-mutação deve falhar stale",
  );
  assert.strictEqual(
    amendKeys(d.db, d.eventPath).length, 0,
    "D: emenda stale criou documento",
  );

  // ── A/B/C: W5 same-instant race, replay, and intent conflict ───────────────
  const s = await seedFinalEvent();
  const sDeps = depsFor({db: s.db, now: FIXED});
  const revBefore = eventOf(s.db, s.eventPath).revision as number;
  const winner = (await runHealthAmendClinicalEvent(
    mockRequest(amendCmd(s.caseId, s.eventId, "op-c1-A", revBefore)),
    sDeps,
  )) as JsonMap;
  assert.strictEqual(
    winner.revision, revBefore + 1, "A: vencedor avança exatamente 1",
  );
  const opsAfterWinner = opKeys(s.db, s.casePath).length;
  const auditsAfterWinner = auditKeys(s.db).length;

  // B — a DISTINCT amendment reusing the SAME token at the SAME instant loses.
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(s.caseId, s.eventId, "op-c1-B", revBefore, {
        amendmentType: "addendum",
        reason: "segunda intenção distinta",
        content: {note: "outro conteúdo"},
      })),
      sDeps,
    ),
    "conflict",
    "B: segunda emenda distinta no MESMO ms deve falhar stale",
  );
  assert.strictEqual(
    eventOf(s.db, s.eventPath).amendment_count, 1,
    "B: exactly-one-winner — contagem deve ser 1",
  );
  assert.strictEqual(
    amendKeys(s.db, s.eventPath).length, 1,
    "B: exactly-one-winner — um único documento de emenda",
  );
  assert.strictEqual(
    eventOf(s.db, s.eventPath).revision, revBefore + 1,
    "B: perdedor não avançou a revision",
  );
  assert.strictEqual(
    opKeys(s.db, s.casePath).length, opsAfterWinner,
    "B: perdedor criou receipt",
  );
  assert.strictEqual(
    auditKeys(s.db).length, auditsAfterWinner,
    "B: perdedor criou audit",
  );

  // B2 — the winner's replay carries its ORIGINAL (now stale) token and still
  // no-ops, returning the revision IT produced. Replay-before-stale preserved.
  const replay = (await runHealthAmendClinicalEvent(
    mockRequest(amendCmd(s.caseId, s.eventId, "op-c1-A", revBefore)),
    sDeps,
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "B2: replay do vencedor é no-op");
  assert.strictEqual(
    replay.revision, revBefore + 1,
    "B2: replay retorna a revision que ELE produziu",
  );
  assert.strictEqual(
    eventOf(s.db, s.eventPath).revision, revBefore + 1,
    "B2: replay não avançou a revision",
  );
  assert.strictEqual(
    amendKeys(s.db, s.eventPath).length, 1, "B2: replay duplicou emenda",
  );

  // C — same operationId, DIFFERENT intent: conflict, never stale.
  await expectReject(
    () => runHealthAmendClinicalEvent(
      mockRequest(amendCmd(s.caseId, s.eventId, "op-c1-A", revBefore, {
        reason: "intenção divergente",
      })),
      sDeps,
    ),
    "idempotency-conflict",
    "C: mesma operação com intenção distinta é conflito, não stale",
  );

  // ── receipt + audit agree with the stored revision ─────────────────────────
  const receipt = s.db._store.get(
    `${s.casePath}/operations/op-c1-A`,
  ) as JsonMap;
  assert.strictEqual(
    (receipt.result as JsonMap).revision, revBefore + 1,
    "receipt guarda a revision resultante",
  );
  const amendAudit = auditKeys(s.db)
    .map((k) => s.db._store.get(k) as JsonMap)
    .find((a) => a.action === "clinical_event_amended") as JsonMap;
  assert.strictEqual(
    (amendAudit.metadata as JsonMap).event_revision, revBefore + 1,
    "audit registra event_revision resultante",
  );

  // The SAME four-way agreement must hold for FINALIZE and CANCEL, not only for
  // AMEND. Without these, a writer could report one revision while persisting
  // another — the receipt would then replay a number that never existed.
  const fin = await seedDraftEvent();
  const finQRes = (await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(fin.caseId, fin.eventId, "op-c1-finq", 1)),
    depsFor({db: fin.db, now: FIXED}),
  )) as JsonMap;
  const finStored = eventOf(fin.db, fin.eventPath).revision;
  const finReceipt = fin.db._store.get(
    `${fin.casePath}/operations/op-c1-finq`,
  ) as JsonMap;
  const finAudit = auditKeys(fin.db)
    .map((key) => fin.db._store.get(key) as JsonMap)
    .find((a) => a.action === "clinical_event_finalized") as JsonMap;
  assert.strictEqual(finStored, 2, "FINALIZE: revision persistida = 2");
  assert.strictEqual(
    finQRes.revision, finStored, "FINALIZE: response == persistida",
  );
  assert.strictEqual(
    (finReceipt.result as JsonMap).revision, finStored,
    "FINALIZE: receipt.result.revision == persistida",
  );
  assert.strictEqual(
    (finAudit.metadata as JsonMap).event_revision, finStored,
    "FINALIZE: audit.event_revision == persistida",
  );

  const can = await seedFinalEvent();
  const canRev = eventOf(can.db, can.eventPath).revision as number;
  const canResp = (await runHealthCancelClinicalEvent(
    mockRequest(mutationCmd(can.caseId, can.eventId, "op-c1-canq", canRev, {
      cancelReason: "registro duplicado pelo veterinário",
    })),
    depsFor({db: can.db, now: FIXED}),
  )) as JsonMap;
  const canStored = eventOf(can.db, can.eventPath).revision;
  const canReceipt = can.db._store.get(
    `${can.casePath}/operations/op-c1-canq`,
  ) as JsonMap;
  const canAudit = auditKeys(can.db)
    .map((key) => can.db._store.get(key) as JsonMap)
    .find((a) => a.action === "clinical_event_cancelled") as JsonMap;
  assert.strictEqual(
    canStored, canRev + 1, "CANCEL: revision persistida avançou 1",
  );
  assert.strictEqual(
    canResp.revision, canStored, "CANCEL: response == persistida",
  );
  assert.strictEqual(
    (canReceipt.result as JsonMap).revision, canStored,
    "CANCEL: receipt.result.revision == persistida",
  );
  assert.strictEqual(
    (canAudit.metadata as JsonMap).event_revision, canStored,
    "CANCEL: audit.event_revision == persistida",
  );

  // ── CANCEL advances the event revision by exactly 1 ────────────────────────
  const k = await seedFinalEvent();
  const kRev = eventOf(k.db, k.eventPath).revision as number;
  const canRes = (await runHealthCancelClinicalEvent(
    mockRequest(mutationCmd(k.caseId, k.eventId, "op-c1-can", kRev, {
      cancelReason: "registro duplicado",
    })),
    depsFor({db: k.db, now: FIXED}),
  )) as JsonMap;
  assert.strictEqual(canRes.revision, kRev + 1, "CANCEL: response revision +1");
  assert.strictEqual(
    eventOf(k.db, k.eventPath).revision, kRev + 1,
    "CANCEL: stored revision +1",
  );

  // ── overflow fails closed: never produce an unsafe integer ─────────────────
  const o = await seedDraftEvent();
  const oev = eventOf(o.db, o.eventPath);
  oev.revision = Number.MAX_SAFE_INTEGER;
  o.db._store.set(o.eventPath, oev);
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(
        mutationCmd(o.caseId, o.eventId, "op-c1-ovf", Number.MAX_SAFE_INTEGER),
      ),
      depsFor({db: o.db, now: FIXED}),
    ),
    "integrity",
    "overflow: revision em MAX_SAFE_INTEGER não pode avançar",
  );
  assert.strictEqual(
    eventOf(o.db, o.eventPath).status, "draft",
    "overflow: evento mutado apesar do fail-closed",
  );

  // ── the case token is NOT the concurrency authority any more: event-only
  //    mutations leave the case revision untouched ────────────────────────────
  const w = await seedFinalEvent();
  const caseRevBefore = (w.db._store.get(w.casePath) as JsonMap).revision;
  await runHealthAmendClinicalEvent(
    mockRequest(amendCmd(
      w.caseId, w.eventId, "op-c1-nd",
      eventOf(w.db, w.eventPath).revision as number,
    )),
    depsFor({db: w.db, now: FIXED}),
  );
  assert.strictEqual(
    (w.db._store.get(w.casePath) as JsonMap).revision, caseRevBefore,
    "AMEND não altera a revision do caso",
  );
}

/**
 * Persistence-boundary actor hygiene (CLIN-WRITER-1.W6.P0.K1).
 *
 * Two things must hold at once: the canonical server-derived actor still passes
 * strict validation, AND the writer no longer manufactures a role when one is
 * missing. The old `?? "condutor"` fallback would have defeated any downstream
 * validator, so its absence is asserted against the source text — a behavioural
 * test alone cannot prove a fallback is gone when the happy path never needs it.
 */
async function testPersistedActorBoundary() {
  // A — canonical server-derived actor (condutor) survives the strict adapter.
  const d = await seedDraftEvent();
  await runHealthCancelClinicalEvent(
    mockRequest(mutationCmd(d.caseId, d.eventId, "op-k1-can", 1, {
      cancelReason: "registro duplicado",
    })),
    depsFor({db: d.db, now: T1}),
  );
  const dAfter = eventOf(d.db, d.eventPath);
  assert.strictEqual(dAfter.status, "cancelled", "A: cancelamento falhou");
  assert.deepStrictEqual(
    dAfter.cancelled_by,
    {uid: actor.uid, name: actor.name, internal_role: "condutor"},
    "A: cancelled_by persistido deve manter o shape snake_case canônico",
  );

  // B — the admin branch of recordedByPayload also passes: proves the adapter
  // READS internal_role instead of defaulting it. Under the old fallback an
  // unread key still produced "condutor", so "admin" would have been lost.
  const a = await seedDraftEvent({admin: true});
  await runHealthCancelClinicalEvent(
    mockRequest(mutationCmd(a.caseId, a.eventId, "op-k1-adm", 1, {
      cancelReason: "registro duplicado",
    })),
    depsFor({db: a.db, now: T1, admin: true}),
  );
  assert.strictEqual(
    ((eventOf(a.db, a.eventPath).cancelled_by as JsonMap).internal_role),
    "admin",
    "B: papel admin foi perdido/sobrescrito pela adaptação",
  );

  // C — the dangerous precedent is gone and the strict adapter is in its place.
  const src = stripComments(readSource("clinical_case_callables.ts"));
  assert.strictEqual(
    src.includes("?? \"condutor\""),
    false,
    "C: fallback `?? \"condutor\"` reintroduzido — mascara ator corrompido",
  );
  assert.strictEqual(
    /internalRole:\s*stringValue\(/.test(src),
    false,
    "C: adaptação manual de ator reintroduzida fora da fronteira estrita",
  );
  const cancelBody = src.slice(
    src.indexOf("export async function runHealthCancelClinicalEvent"),
  );
  assert.ok(
    cancelBody.includes("actorFromPersistedShape("),
    "C: CANCEL deve adaptar o ator pela fronteira estrita",
  );

  // D — the boundary is the ONLY place snake_case meets the domain: pure domain
  // must never learn the persisted key.
  const domainSrc = stripComments(readSource("clinical_domain.ts"));
  assert.strictEqual(
    domainSrc.includes("internal_role:"),
    false,
    "D: clinical_domain.ts não pode ler a chave persistida internal_role",
  );
  assert.ok(
    domainSrc.includes("export function assertClinicalActor("),
    "D: validador canônico de ator deve viver no domínio puro",
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// W6 Lifecycle Writers Integration Tests
// ─────────────────────────────────────────────────────────────────────────────

async function testLifecycleTransitionActiveMatrix(): Promise<void> {
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;

  // Active-to-active valid transitions sequence (covers multiple pairs)
  // open(rev 1) -> under_investigation(rev 2)
  const t1 = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t1",
      expectedRevision: 1,
      destination: "under_investigation",
    }),
    depsFor({db, now: T1}),
  );
  assert.deepStrictEqual(t1, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "under_investigation",
    revision: 2,
    wasNoOp: false,
  });

  const casePath = canonicalCasePath("dog-1", caseId);
  const caseAfterT1 = {...caseOf(db, casePath)};
  const opsAfterT1 = opKeys(db, casePath).length;
  const auditsAfterT1 = auditKeys(db).length;

  // Replay t1 com expectedRevision alterado/stale (prova que expectedRevision não contamina fingerprint semântico)
  const t1Replay = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t1",
      expectedRevision: 99,
      destination: "under_investigation",
    }),
    depsFor({db, now: T1}),
  );
  assert.deepStrictEqual(t1Replay, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "under_investigation",
    revision: 2,
    wasNoOp: true,
  });
  assert.deepStrictEqual(caseOf(db, casePath), caseAfterT1);
  assert.strictEqual(opKeys(db, casePath).length, opsAfterT1);
  assert.strictEqual(auditKeys(db).length, auditsAfterT1);

  // Idempotency conflict on op-t1
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-t1",
        expectedRevision: 1,
        destination: "monitoring",
      }),
      depsFor({db, now: T1}),
    ),
    "idempotency-conflict",
    "transição com idempotência divergente",
  );

  // under_investigation(rev 2) -> under_treatment(rev 3)
  const t2 = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t2",
      expectedRevision: 2,
      destination: "under_treatment",
    }),
    depsFor({db, now: T1}),
  );
  assert.strictEqual(t2?.revision, 3);
  assert.strictEqual(t2?.clinicalStatus, "under_treatment");

  // under_treatment(rev 3) -> monitoring(rev 4)
  const t3 = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t3",
      expectedRevision: 3,
      destination: "monitoring",
    }),
    depsFor({db, now: T1}),
  );
  assert.strictEqual(t3?.revision, 4);
  assert.strictEqual(t3?.clinicalStatus, "monitoring");

  // monitoring(rev 4) -> under_investigation(rev 5)
  const t4 = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t4",
      expectedRevision: 4,
      destination: "under_investigation",
    }),
    depsFor({db, now: T1}),
  );
  assert.strictEqual(t4?.revision, 5);
  assert.strictEqual(t4?.clinicalStatus, "under_investigation");

  // under_investigation(rev 5) -> open(rev 6)
  const t5 = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-t5",
      expectedRevision: 5,
      destination: "open",
    }),
    depsFor({db, now: T1}),
  );
  assert.strictEqual(t5?.revision, 6);
  assert.strictEqual(t5?.clinicalStatus, "open");

  // Same status transition rejected (open -> open)
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-same-status",
        expectedRevision: 6,
        destination: "open",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "transição para mesmo status",
  );

  // Terminal status destination rejected in generic transition
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-term-dest",
        expectedRevision: 6,
        destination: "discharged",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "transição para status terminal",
  );

  // Stale expectedRevision rejected
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-stale-trans",
        expectedRevision: 4,
        destination: "under_investigation",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "transição com expectedRevision desatualizado",
  );

  // Dual-invalid: Stale expectedRevision (4 != 6) combined with ineligible transition destination (open -> open).
  // OCC freshness MUST precede transition eligibility checking (M28 killer).
  const caseBeforeDual = {...caseOf(db, canonicalCasePath("dog-1", caseId))};
  const opsBeforeDual = opKeys(db, canonicalCasePath("dog-1", caseId)).length;
  const auditsBeforeDual = auditKeys(db).length;

  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-dual-invalid-trans",
        expectedRevision: 4,
        destination: "open",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "transição com expectedRevision desatualizado e destino inelegível (OCC precede elegibilidade)",
    "Registro clínico alterado por outra operação. Recarregue antes de mutar.",
  );
  assert.deepStrictEqual(caseOf(db, canonicalCasePath("dog-1", caseId)), caseBeforeDual);
  assert.strictEqual(opKeys(db, canonicalCasePath("dog-1", caseId)).length, opsBeforeDual);
  assert.strictEqual(auditKeys(db).length, auditsBeforeDual);
}

async function testLifecycleDischarge(): Promise<void> {
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;

  // Discharge active case
  const dRes = await runHealthDischargeClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-dc-1",
      expectedRevision: 1,
      closureReason: "  Paciente 100% recuperado do quadro clínico  ",
    }),
    depsFor({db, now: T1}),
  );
  assert.deepStrictEqual(dRes, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "discharged",
    revision: 2,
    wasNoOp: false,
  });

  const casePath = canonicalCasePath("dog-1", caseId);
  const cDoc = caseOf(db, casePath);
  assert.strictEqual(cDoc.clinical_status, "discharged");
  assert.strictEqual(cDoc.closure_type, "discharge");
  assert.strictEqual(cDoc.closure_reason, "Paciente 100% recuperado do quadro clínico");
  assert.strictEqual(cDoc.revision, 2);
  assert.ok(cDoc.closed_at);
  assert.deepStrictEqual(cDoc.closed_by, {
    uid: actor.uid,
    name: actor.name,
    internal_role: "condutor",
  });

  const caseAfterDischarge = {...caseOf(db, casePath)};
  const opsAfterDischarge = opKeys(db, casePath).length;
  const auditsAfterDischarge = auditKeys(db).length;

  // Replay com expectedRevision alterado/stale (prova que expectedRevision não contamina fingerprint semântico)
  const dReplay = await runHealthDischargeClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-dc-1",
      expectedRevision: 99,
      closureReason: "Paciente 100% recuperado do quadro clínico",
    }),
    depsFor({db, now: T1}),
  );
  assert.deepStrictEqual(dReplay, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "discharged",
    revision: 2,
    wasNoOp: true,
  });
  assert.deepStrictEqual(caseOf(db, casePath), caseAfterDischarge);
  assert.strictEqual(opKeys(db, casePath).length, opsAfterDischarge);
  assert.strictEqual(auditKeys(db).length, auditsAfterDischarge);

  // Idempotency conflict
  await expectReject(
    () => runHealthDischargeClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-dc-1",
        expectedRevision: 1,
        closureReason: "Outro motivo de alta",
      }),
      depsFor({db, now: T1}),
    ),
    "idempotency-conflict",
    "alta com motivo divergente",
  );

  // Discharging an already discharged case fails
  await expectReject(
    () => runHealthDischargeClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-dc-2",
        expectedRevision: 2,
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "alta em caso já discharged",
  );
}

async function testLifecycleCancelCase(): Promise<void> {
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;

  // Missing reason rejected
  await expectReject(
    () => runHealthCancelClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-cc-no-reason",
        expectedRevision: 1,
      }),
      depsFor({db, now: T1}),
    ),
    "validation",
    "cancelamento sem motivo",
  );

  // Cancel active case
  const cRes = await runHealthCancelClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-cc-1",
      expectedRevision: 1,
      closureReason: "  Abertura realizada em duplicidade pelo condutor  ",
    }),
    depsFor({db, now: T1, admin: true}),
  );
  assert.deepStrictEqual(cRes, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "cancelled",
    revision: 2,
    wasNoOp: false,
  });

  const casePath = canonicalCasePath("dog-1", caseId);
  const cDoc = caseOf(db, casePath);
  assert.strictEqual(cDoc.clinical_status, "cancelled");
  assert.strictEqual(cDoc.closure_type, "cancelled");
  assert.strictEqual(cDoc.closure_reason, "Abertura realizada em duplicidade pelo condutor");
  assert.strictEqual(cDoc.revision, 2);
  assert.deepStrictEqual(cDoc.closed_by, {
    uid: actor.uid,
    name: actor.name,
    internal_role: "admin",
  });

  const caseAfterCancel = {...caseOf(db, casePath)};
  const opsAfterCancel = opKeys(db, casePath).length;
  const auditsAfterCancel = auditKeys(db).length;

  // Replay com expectedRevision alterado/stale (prova que expectedRevision não contamina fingerprint semântico)
  const cReplay = await runHealthCancelClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-cc-1",
      expectedRevision: 99,
      closureReason: "Abertura realizada em duplicidade pelo condutor",
    }),
    depsFor({db, now: T1, admin: true}),
  );
  assert.deepStrictEqual(cReplay, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "cancelled",
    revision: 2,
    wasNoOp: true,
  });
  assert.deepStrictEqual(caseOf(db, casePath), caseAfterCancel);
  assert.strictEqual(opKeys(db, casePath).length, opsAfterCancel);
  assert.strictEqual(auditKeys(db).length, auditsAfterCancel);

  // Idempotency conflict on op-cc-1 (motivo divergente)
  await expectReject(
    () => runHealthCancelClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-cc-1",
        expectedRevision: 1,
        closureReason: "Outro motivo divergente de cancelamento",
      }),
      depsFor({db, now: T1, admin: true}),
    ),
    "idempotency-conflict",
    "cancelamento com motivo divergente",
  );

  // Cancelled case cannot be transitioned or cancelled again
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-trans-cancelled",
        expectedRevision: 2,
        destination: "open",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "transição de caso cancelado",
  );
  await expectReject(
    () => runHealthCancelClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-cc-2",
        expectedRevision: 2,
        closureReason: "Tentativa de cancelamento duplo",
      }),
      depsFor({db, now: T1}),
    ),
    "conflict",
    "cancelamento de caso cancelado",
  );
}

async function testLifecycleReopen(): Promise<void> {
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;

  // Discharge case (rev 1 -> rev 2)
  await runHealthDischargeClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-dc-before-reopen",
      expectedRevision: 1,
      closureReason: "Alta provisória",
    }),
    depsFor({db, now: T1}),
  );

  // Reopen requires an explicit destination: all three accepted input forms
  // are deliberately absent, and validation must fail without mutating the case.
  const casePath = canonicalCasePath("dog-1", caseId);
  const dischargedBeforeMissingDestination = {...caseOf(db, casePath)};
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-reopen-missing-destination",
        expectedRevision: 2,
        reopenReason: "Recidiva que exige destino explícito",
      }),
      depsFor({db, now: T2}),
    ),
    "validation",
    "reabertura sem destination/targetStatus/target_status",
  );
  assert.deepStrictEqual(caseOf(db, casePath), dischargedBeforeMissingDestination);
  assert.strictEqual(
    db._store.get(`${casePath}/operations/op-reopen-missing-destination`),
    undefined,
  );

  // Reopen discharged case (rev 2 -> rev 3, reopened_count: 1)
  const rRes = await runHealthReopenClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-reopen-1",
      expectedRevision: 2,
      destination: "under_investigation",
      reopenReason: "  Recidiva dos sintomas observada em patrulhamento  ",
    }),
    depsFor({db, now: T2}),
  );
  assert.deepStrictEqual(rRes, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "under_investigation",
    revision: 3,
    wasNoOp: false,
  });

  const cDoc = caseOf(db, canonicalCasePath("dog-1", caseId));
  assert.strictEqual(cDoc.clinical_status, "under_investigation");
  assert.strictEqual(cDoc.previous_status, "discharged");
  assert.strictEqual(cDoc.reopen_reason, "Recidiva dos sintomas observada em patrulhamento");
  assert.strictEqual(cDoc.reopened_count, 1);
  assert.strictEqual(cDoc.revision, 3);
  assert.ok(cDoc.reopened_at);
  assert.deepStrictEqual(cDoc.reopened_by, {
    uid: actor.uid,
    name: actor.name,
    internal_role: "condutor",
  });

  // Verify all 4 closure fields were deleted
  assert.strictEqual(cDoc.closed_at, undefined);
  assert.strictEqual(cDoc.closed_by, undefined);
  assert.strictEqual(cDoc.closure_type, undefined);
  assert.strictEqual(cDoc.closure_reason, undefined);

  const caseAfterReopen = {...caseOf(db, casePath)};
  const opsAfterReopen = opKeys(db, casePath).length;
  const auditsAfterReopen = auditKeys(db).length;

  // Replay com expectedRevision alterado/stale (prova que expectedRevision não contamina fingerprint semântico)
  const rReplay = await runHealthReopenClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-reopen-1",
      expectedRevision: 99,
      destination: "under_investigation",
      reopenReason: "Recidiva dos sintomas observada em patrulhamento",
    }),
    depsFor({db, now: T2}),
  );
  assert.deepStrictEqual(rReplay, {
    dogId: "dog-1",
    caseId,
    clinicalStatus: "under_investigation",
    revision: 3,
    wasNoOp: true,
  });
  assert.deepStrictEqual(caseOf(db, casePath), caseAfterReopen);
  assert.strictEqual(opKeys(db, casePath).length, opsAfterReopen);
  assert.strictEqual(auditKeys(db).length, auditsAfterReopen);

  // Idempotency conflict on op-reopen-1 (destino divergente)
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-reopen-1",
        expectedRevision: 2,
        destination: "open",
        reopenReason: "Recidiva dos sintomas observada em patrulhamento",
      }),
      depsFor({db, now: T2}),
    ),
    "idempotency-conflict",
    "reabertura com destino divergente",
  );

  // Idempotency conflict on op-reopen-1 (motivo divergente)
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-reopen-1",
        expectedRevision: 2,
        destination: "under_investigation",
        reopenReason: "Outro motivo de reabertura divergente",
      }),
      depsFor({db, now: T2}),
    ),
    "idempotency-conflict",
    "reabertura com motivo divergente",
  );

  // Second cycle: Discharge again (rev 3 -> rev 4)
  await runHealthDischargeClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-dc-second",
      expectedRevision: 3,
      closureReason: "Segunda alta após tratamento",
    }),
    depsFor({db, now: T2}),
  );

  // Reopen again with a distinct actor (rev 4 -> rev 5, reopened_count: 2)
  const r2Res = await runHealthReopenClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-reopen-2",
      expectedRevision: 4,
      destination: "monitoring",
      reopenReason: "Reabertura para monitoramento pós-alta",
    }, {uid: actorB.uid, token: {}}),
    depsFor({db, now: T2, caller: actorB}),
  );
  assert.strictEqual(r2Res?.revision, 5);
  assert.strictEqual(r2Res?.clinicalStatus, "monitoring");

  const cDoc2 = caseOf(db, canonicalCasePath("dog-1", caseId));
  assert.strictEqual(cDoc2.reopened_count, 2);
  assert.deepStrictEqual(cDoc2.reopened_by, {
    uid: actorB.uid,
    name: actorB.name,
    internal_role: "condutor",
  });
  assert.notDeepStrictEqual(cDoc2.reopened_by, cDoc.reopened_by);
  assert.strictEqual(cDoc2.closed_at, undefined);

  // Reopening active case rejected
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-reopen-active",
        expectedRevision: 5,
        destination: "open",
        reopenReason: "Motivo qualquer",
      }),
      depsFor({db, now: T2}),
    ),
    "conflict",
    "reabertura de caso ativo",
  );
}

async function testLifecycleStoredIntegrityFailClosed(): Promise<void> {
  const casePath = "dogs/dog-1/clinical_cases/cc-corrupt";

  // 1. Corrupt clinical_status
  const db1 = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [casePath]: {
      case_id: "cc-corrupt",
      dog_id: "dog-1",
      clinical_status: "unknown_corrupt_status",
      revision: 1,
    },
  });
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId: "cc-corrupt",
        operationId: "op-corrupt-1",
        expectedRevision: 1,
        destination: "open",
      }),
      depsFor({db: db1, now: T1}),
    ),
    "integrity",
    "caso com status corrompido",
  );

  // 2. Corrupt revision (< 1 or non-integer)
  const db2 = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [casePath]: {
      case_id: "cc-corrupt",
      dog_id: "dog-1",
      clinical_status: "open",
      revision: 0,
    },
  });
  await expectReject(
    () => runHealthDischargeClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId: "cc-corrupt",
        operationId: "op-corrupt-2",
        expectedRevision: 1,
      }),
      depsFor({db: db2, now: T1}),
    ),
    "integrity",
    "caso com revision 0",
  );

  // 3. Active case with corrupt closure metadata (unexpected_closure_metadata)
  const db3 = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [casePath]: {
      case_id: "cc-corrupt",
      dog_id: "dog-1",
      clinical_status: "open",
      revision: 1,
      closed_at: Timestamp.fromDate(FIXED_NOW),
      closure_type: "discharge",
    },
  });
  // Integrity check runs BEFORE expectedRevision OCC check:
  // even if expectedRevision is wrong (999), it must fail on integrity, not conflict.
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId: "cc-corrupt",
        operationId: "op-corrupt-3",
        expectedRevision: 999,
        destination: "under_investigation",
      }),
      depsFor({db: db3, now: T1}),
    ),
    "integrity",
    "caso ativo com metadados de fechamento",
  );

  // 4. Discharged case with malformed closed_by actor
  const db4 = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [casePath]: {
      case_id: "cc-corrupt",
      dog_id: "dog-1",
      clinical_status: "discharged",
      revision: 2,
      closed_at: Timestamp.fromDate(FIXED_NOW),
      closed_by: {uid: "", name: "Dr Vet", internal_role: "veterinario"},
      closure_type: "discharge",
    },
  });
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId: "cc-corrupt",
        operationId: "op-corrupt-4",
        expectedRevision: 2,
        destination: "open",
        reopenReason: "Tentativa de reabrir caso com ator corrompido",
      }),
      depsFor({db: db4, now: T1}),
    ),
    "integrity",
    "caso discharged com ator malformado",
  );

  // 5. Complete coherent reopen history with malformed persisted reopened_by.
  // Integrity must win over stale OCC, and the rejected command must be side-effect free.
  const db5 = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [casePath]: {
      case_id: "cc-corrupt",
      dog_id: "dog-1",
      clinical_status: "open",
      revision: 5,
      reopened_at: Timestamp.fromDate(T1),
      reopened_by: {uid: "", name: "Dr Vet", internal_role: "veterinario"},
      previous_status: "discharged",
      reopen_reason: "Recidiva confirmada",
      reopened_count: 1,
    },
  });
  const beforeMalformedReopenedBy = {...caseOf(db5, casePath)};
  const opsBeforeMalformedReopenedBy = opKeys(db5, casePath).length;
  const auditsBeforeMalformedReopenedBy = auditKeys(db5).length;
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId: "cc-corrupt",
        operationId: "op-corrupt-5",
        expectedRevision: 999,
        destination: "under_investigation",
      }),
      depsFor({db: db5, now: T2}),
    ),
    "integrity",
    "caso com reopened_by persistido malformado antes de OCC",
  );
  assert.deepStrictEqual(caseOf(db5, casePath), beforeMalformedReopenedBy);
  assert.strictEqual(opKeys(db5, casePath).length, opsBeforeMalformedReopenedBy);
  assert.strictEqual(
    db5._store.get(`${casePath}/operations/op-corrupt-5`),
    undefined,
  );
  assert.strictEqual(
    auditKeys(db5).length,
    auditsBeforeMalformedReopenedBy,
  );
}

async function testLifecycleGuardsAndAuthorization(): Promise<void> {
  const db = dbWithDog();
  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;

  // 1. Transition denied without manage_clinical_case
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-guard-1",
        expectedRevision: 1,
        destination: "under_investigation",
      }),
      depsFor({db, now: T1, allowManageCase: false}),
    ),
    "permission-denied",
    "transição sem manage_clinical_case",
  );

  // 2. Discharge denied without manage_clinical_case
  await expectReject(
    () => runHealthDischargeClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-guard-2",
        expectedRevision: 1,
      }),
      depsFor({db, now: T1, allowManageCase: false}),
    ),
    "permission-denied",
    "alta sem manage_clinical_case",
  );

  // 3. Cancel denied without manage_clinical_case
  await expectReject(
    () => runHealthCancelClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-guard-3",
        expectedRevision: 1,
        closureReason: "Motivo valido",
      }),
      depsFor({db, now: T1, allowManageCase: false}),
    ),
    "permission-denied",
    "cancelamento sem manage_clinical_case",
  );

  // 4. Reopen denied without reopen_clinical_case (even with manage_clinical_case)
  await expectReject(
    () => runHealthReopenClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-guard-4",
        expectedRevision: 1,
        destination: "open",
        reopenReason: "Motivo valido",
      }),
      depsFor({db, now: T1, allowManageCase: true, allowReopenCase: false}),
    ),
    "permission-denied",
    "reabertura sem reopen_clinical_case",
  );

  // 5. Server-managed injection rejected
  await expectReject(
    () => runHealthTransitionClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-inject-1",
        expectedRevision: 1,
        destination: "under_investigation",
        closed_at: "2026-08-28T00:00:00Z",
      }),
      depsFor({db, now: T1}),
    ),
    "validation",
    "injeção de campo server-managed",
  );

  // 6. Unknown mutation keys rejected
  await expectReject(
    () => runHealthDischargeClinicalCase(
      mockRequest({
        dogId: "dog-1",
        caseId,
        operationId: "op-unknown-key",
        expectedRevision: 1,
        content: {diagnosis: "forged"},
      }),
      depsFor({db, now: T1}),
    ),
    "validation",
    "chave desconhecida rejeitada",
  );
}

async function testLifecycleCaseOnlyInvariants(): Promise<void> {
  const initialSummary: JsonMap = {
    readiness_status: "in_training",
    updated_at: "2026-08-01T00:00:00Z",
  };
  const summaryPath = "dogs/dog-1/health_summary/current";
  const initialTimelineEntry: JsonMap = {
    timeline_type: "vaccine",
    title: "Initial vaccine",
    created_at: "2026-08-01T00:00:00Z",
  };
  const timelinePath = "dogs/dog-1/health_timeline/existing-sentinel";
  const db = dbWithDog({
    [summaryPath]: initialSummary,
    [timelinePath]: initialTimelineEntry,
  });

  const getTimelineDocs = (): Record<string, unknown> => {
    const entries: Record<string, unknown> = {};
    for (const [k, v] of db._store.entries()) {
      if (k.startsWith("dogs/dog-1/health_timeline/")) {
        entries[k] = JSON.parse(JSON.stringify(v));
      }
    }
    return entries;
  };

  const openRes = (await runHealthOpenClinicalCase(
    mockRequest(validOpen),
    depsFor({db, now: FIXED_NOW}),
  )) as JsonMap;
  assert.ok(openRes);
  const caseId = openRes.case_id as string;
  const initialCase = caseOf(db, canonicalCasePath("dog-1", caseId));
  const initialEventCount = initialCase.event_count;
  const initialLastEventAt = initialCase.last_event_at;
  const initialOpeningEventId = initialCase.opening_event_id;

  const beforeTimeline = getTimelineDocs();

  // Run transition
  const transRes = await runHealthTransitionClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-case-only-1",
      expectedRevision: 1,
      destination: "under_investigation",
    }),
    depsFor({db, now: T1}),
  );
  assert.ok(transRes);

  const afterTransitionTimeline = getTimelineDocs();
  assert.deepStrictEqual(
    afterTransitionTimeline,
    beforeTimeline,
    "Projeção de timeline (health_timeline) não pode ser mutada por transição de caso clínico",
  );

  // Run discharge
  await runHealthDischargeClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-case-only-2",
      expectedRevision: 2,
      closureReason: "Alta",
    }),
    depsFor({db, now: T1}),
  );

  // Run reopen
  await runHealthReopenClinicalCase(
    mockRequest({
      dogId: "dog-1",
      caseId,
      operationId: "op-case-only-3",
      expectedRevision: 3,
      destination: "open",
      reopenReason: "Reabertura",
    }),
    depsFor({db, now: T2}),
  );

  // Verify case aggregate invariant fields never changed
  const finalCase = caseOf(db, canonicalCasePath("dog-1", caseId));
  assert.strictEqual(finalCase.event_count, initialEventCount);
  assert.deepStrictEqual(finalCase.last_event_at, initialLastEventAt);
  assert.strictEqual(finalCase.opening_event_id, initialOpeningEventId);

  // Verify only 1 clinical_event document exists in the entire subcollection (the opening event)
  const eventDocs = [...db._store.keys()].filter((k) =>
    k.startsWith(`dogs/dog-1/clinical_cases/${caseId}/clinical_events/`),
  );
  assert.strictEqual(
    eventDocs.length,
    1,
    "Nenhum novo ClinicalEvent deve ter sido criado pelas operações de ciclo de vida",
  );

  // Verify readiness summary was NOT mutated/overwritten/merged by lifecycle writers
  const finalSummary = db._store.get(summaryPath);
  assert.deepStrictEqual(
    finalSummary,
    initialSummary,
    "Resumo de prontidão (health_summary/current) não pode ser mutado por operações de ciclo de vida do caso clínico",
  );

  // Verify health timeline was NOT mutated/created across all lifecycle operations
  const finalTimeline = getTimelineDocs();
  assert.deepStrictEqual(
    finalTimeline,
    beforeTimeline,
    "Projeção de timeline (health_timeline) não pode ser mutada por operações de ciclo de vida do caso clínico",
  );
}

const tests: Array<[string, () => Promise<void>]> = [
  ["OPEN sucesso e shape canônico", testOpenSuccess],
  ["OPEN replay sem duplicação", testOpenReplayNoDuplicate],
  ["OPEN conflito de idempotência", testOpenIdempotencyConflict],
  ["OPEN IDs determinísticos", testOpenDeterministicIds],
  ["OPEN guards de capability/escopo/K9", testOpenGuards],
  ["OPEN rejeita injeção de campos server-managed", testOpenInjectionRejected],
  ["OPEN vocabulários inválidos", testOpenInvalidVocabularies],
  ["OPEN ator admin é só classificação", testOpenAdminRole],
  ["OPEN agregado sem receipt falha fechado", testOpenAggregateWithoutReceiptFailsClosed],
  ["APPEND sucesso sem transição de status", testAppendSuccess],
  ["APPEND replay sem duplicação", testAppendReplayNoDuplicate],
  ["APPEND conflito de idempotência", testAppendIdempotencyConflict],
  ["APPEND caso inexistente", testAppendCaseNotFound],
  ["APPEND caso terminal rejeitado", testAppendTerminalRejected],
  ["APPEND status corrompido falha fechado", testAppendCorruptStatusFailsClosed],
  ["APPEND guards e injeção", testAppendGuardsAndInjection],
  ["APPEND evento sem receipt falha fechado", testAppendEventWithoutReceiptFailsClosed],
  ["OPEN receipt malformado falha fechado", testOpenMalformedReceiptFailsClosed],
  ["APPEND receipt malformado falha fechado", testAppendMalformedReceiptFailsClosed],
  ["OPEN evento nasce com token de concorrência", testOpenEventBornWithConcurrencyToken],
  ["APPEND evento nasce com token de concorrência", testAppendEventBornWithConcurrencyToken],
  ["Token de concorrência é server-owned", testConcurrencyTokenIsServerOwned],
  ["Replay não avança o token de concorrência", testReplayDoesNotAdvanceConcurrencyToken],
  ["Conflito de idempotência preserva o token", testIdempotencyConflictLeavesTokenIntact],
  ["Token de concorrência do caso (OPEN/APPEND/Replay/W4/W5)", testCaseConcurrencyTokenLifecycle],
  ["Idempotência cruzada entre atores", testCrossActorOperationIdConflict],
  ["ARQ autoridade clínica sem bypass administrativo", testClinicalCapabilityHasNoAdminBypass],
  ["ARQ callables clínicos usam autoridade dedicada", testClinicalCallablesUseDedicatedAuthority],
  ["ARQ identidade admin não concede record_clinical", testAdminIdentityAloneDoesNotGrantRecordClinical],
  ["FINALIZE draft→final e latch de imutabilidade", testFinalizeSuccess],
  ["FINALIZE replay antes de stale", testFinalizeReplayAndStale],
  ["FINALIZE conflito e transições ilegais", testFinalizeConflictAndIllegalTransitions],
  ["FINALIZE token e integridade fail-closed", testFinalizeTokenAndIntegrityFailures],
  ["FINALIZE matriz de autorização e injeção", testFinalizeAuthorizationMatrix],
  ["CANCEL draft→cancelled e final→cancelled", testCancelFromDraftAndFinal],
  ["CANCEL motivo, replay e conflito", testCancelReasonAndReplay],
  ["CANCEL integridade e autorização", testCancelIntegrityAndAuthorization],
  ["Token velho é a ÚNICA causa da rejeição", testStaleTokenIsTheSoleRejectionCause],
  ["Entrada malformada rejeitada antes de qualquer leitura", testMalformedInputRejectedBeforeAnyRead],
  ["Matriz cruzada de capabilities clínicas", testCrossCapabilityMatrix],
  ["ARQ comandos de mutação usam seams dedicadas", testMutationCommandsUseDedicatedCapabilitySeams],
  ["AMEND emenda criada e metadados do pai", testAmendSuccessAndParentMetadata],
  ["AMEND segunda emenda é irmã plana", testSecondAmendmentIsSibling],
  ["AMEND elegibilidade do pai (final apenas)", testAmendParentEligibility],
  ["AMEND concorrência e replay", testAmendConcurrency],
  ["AMEND idempotência e receipts", testAmendIdempotencyAndReceipts],
  ["AMEND autorização e injeção", testAmendAuthorizationAndInjection],
  ["AMEND integridade de metadados do pai", testAmendParentMetadataIntegrity],
  ["REVISION é a autoridade única de concorrência (relógio fixo)",
    testRevisionConcurrencyAuthority],
  ["ARQ emenda não tem caminho para o conteúdo do pai", testAmendWriterHasNoParentContentPath],
  ["ATOR fronteira de persistência estrita sem default", testPersistedActorBoundary],
  ["LIFECYCLE transição ativa e matriz de estados", testLifecycleTransitionActiveMatrix],
  ["LIFECYCLE alta (discharge) e snapshot de fechamento", testLifecycleDischarge],
  ["LIFECYCLE cancelamento de caso e motivo obrigatório", testLifecycleCancelCase],
  ["LIFECYCLE reabertura e deleção de metadados de fechamento", testLifecycleReopen],
  ["LIFECYCLE integridade armazenada falha fechada antes de OCC", testLifecycleStoredIntegrityFailClosed],
  ["LIFECYCLE matriz de autorização, capabilities e guards", testLifecycleGuardsAndAuthorization],
  ["LIFECYCLE invariantes case-only (sem eventos extras)", testLifecycleCaseOnlyInvariants],
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
