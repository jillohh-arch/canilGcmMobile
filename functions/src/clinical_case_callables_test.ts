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
import {Timestamp} from "firebase-admin/firestore";

import {
  ClinicalCaller,
  ClinicalCaseCallableDeps,
  caseIdentityMaterial,
  deterministicCaseId,
  eventIdentityMaterial,
  deterministicEventId,
  openingEventIdFor,
  runHealthAppendClinicalEvent,
  runHealthOpenClinicalCase,
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
            pending.set(ref.path, {...prev, ...data});
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

function depsFor(options: {
  db: FirebaseFirestore.Firestore;
  allowRecord?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: ClinicalCaller;
}): ClinicalCaseCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  return {
    db: options.db,
    now: () => FIXED_NOW,
    requireRecordClinical: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowRecord === false) {
        throw new HttpsError("permission-denied", "sem health.record_clinical", {
          code: "permission-denied",
        });
      }
      return caller;
    },
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
  ["Idempotência cruzada entre atores", testCrossActorOperationIdConflict],
  ["ARQ autoridade clínica sem bypass administrativo", testClinicalCapabilityHasNoAdminBypass],
  ["ARQ callables clínicos usam autoridade dedicada", testClinicalCallablesUseDedicatedAuthority],
  ["ARQ identidade admin não concede record_clinical", testAdminIdentityAloneDoesNotGrantRecordClinical],
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
