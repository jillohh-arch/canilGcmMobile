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
  runHealthCancelClinicalEvent,
  runHealthFinalizeClinicalEvent,
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
  expectedUpdatedAt: number,
  extra: JsonMap = {},
): JsonMap => ({
  dogId: "dog-1",
  caseId,
  eventId,
  operationId,
  expectedUpdatedAt,
  ...extra,
});

const eventOf = (db: {_store: Map<string, JsonMap>}, p: string): JsonMap =>
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
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", t0)),
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
  const {db, caseId, eventId, casePath, eventPath, t0} = await seedDraftEvent();
  const deps = depsFor({db, now: T1});

  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", t0)),
    deps,
  );
  const t1 = (eventOf(db, eventPath).updated_at as Timestamp).toMillis();
  const opsAfterFirst = opKeys(db, casePath).length;
  const auditsAfterFirst = auditKeys(db).length;

  // K/L — mesma operação, mesma intenção, token ANTIGO T0: replay bem-sucedido.
  const replay = (await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", t0)),
    deps,
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "L: replay não sinalizou no-op");

  // M — replay não avança o token, não duplica receipt nem audit.
  assert.strictEqual(
    (eventOf(db, eventPath).updated_at as Timestamp).toMillis(),
    t1,
    "M: replay avançou o token",
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
      mockRequest(mutationCmd(caseId, eventId, "op-fin-2", t0)),
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
  const {db, caseId, eventId, eventPath, t0} = await seedDraftEvent();
  const deps = depsFor({db, now: T1});

  // O — mesma operação, ator diferente = intenção divergente.
  await runHealthFinalizeClinicalEvent(
    mockRequest(mutationCmd(caseId, eventId, "op-fin-1", t0)),
    deps,
  );
  const t1 = (eventOf(db, eventPath).updated_at as Timestamp).toMillis();
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(caseId, eventId, "op-fin-1", t1), {
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
      mockRequest(mutationCmd(caseId, eventId, "op-fin-3", t1)),
      deps,
    ),
    "conflict",
    "P: refinalizar deveria ser transição ilegal",
  );

  // Q — evento cancelado não finaliza.
  const c = await seedDraftEvent();
  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(c.caseId, c.eventId, "op-can-1", c.t0, {
        cancelReason: "erro de digitação",
      }),
    ),
    depsFor({db: c.db, now: T1}),
  );
  const cT1 = (eventOf(c.db, c.eventPath).updated_at as Timestamp).toMillis();
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(c.caseId, c.eventId, "op-fin-9", cT1)),
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
      mockRequest(mutationCmd(base.caseId, "ce_naoexiste", "op-x", base.t0)),
      depsFor({db: base.db, now: T1}),
    ),
    "not-found",
    "R: evento inexistente",
  );

  // T/U — token de requisição ausente e malformado.
  for (const [bad, label] of [
    [undefined, "T: expectedUpdatedAt ausente"],
    ["1755259200000", "U: expectedUpdatedAt string"],
    [1.5, "U: expectedUpdatedAt fracionário"],
    [Number.NaN, "U: expectedUpdatedAt NaN"],
    [-1, "U: expectedUpdatedAt negativo"],
  ] as Array<[unknown, string]>) {
    const cmd = mutationCmd(base.caseId, base.eventId, "op-t", base.t0);
    if (bad === undefined) delete cmd.expectedUpdatedAt;
    else cmd.expectedUpdatedAt = bad;
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(cmd),
        depsFor({db: base.db, now: T1}),
      ),
      "validation",
      label,
    );
  }

  // S — updated_at armazenado malformado: integrity, zero mutação.
  for (const corrupt of [undefined, "2026-08-15T12:00:00.000Z", 123]) {
    const s = await seedDraftEvent();
    const ev = eventOf(s.db, s.eventPath);
    if (corrupt === undefined) delete ev.updated_at;
    else ev.updated_at = corrupt;
    s.db._store.set(s.eventPath, ev);
    await expectReject(
      () => runHealthFinalizeClinicalEvent(
        mockRequest(mutationCmd(s.caseId, s.eventId, "op-s", s.t0)),
        depsFor({db: s.db, now: T1}),
      ),
      "integrity",
      `S: updated_at armazenado inválido (${String(corrupt)})`,
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
      mockRequest(mutationCmd(m.caseId, m.eventId, "op-mal", m.t0)),
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
      mockRequest(mutationCmd(d.caseId, d.eventId, "op-d", d.t0)),
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
      mockRequest(mutationCmd(v.caseId, v.eventId, "op-v", v.t0)),
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
        mockRequest(mutationCmd(v.caseId, v.eventId, "op-w", v.t0)),
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
          mutationCmd(v.caseId, v.eventId, "op-inj", v.t0, forged as JsonMap),
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
      mutationCmd(d.caseId, d.eventId, "op-can-1", d.t0, {
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
    mockRequest(mutationCmd(f.caseId, f.eventId, "op-fin-1", f.t0)),
    depsFor({db: f.db, now: T1}),
  );
  const finalized = eventOf(f.db, f.eventPath);
  const finalizedAtMs = (finalized.finalized_at as Timestamp).toMillis();
  const fT1 = (finalized.updated_at as Timestamp).toMillis();
  const T2 = new Date("2026-08-17T15:45:00.000Z");

  await runHealthCancelClinicalEvent(
    mockRequest(
      mutationCmd(f.caseId, f.eventId, "op-can-2", fT1, {
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
        mutationCmd(f.caseId, f.eventId, "op-can-3", T2.getTime(), {
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
    const cmd = mutationCmd(base.caseId, base.eventId, "op-r", base.t0);
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
  const cmd = mutationCmd(r.caseId, r.eventId, "op-can-1", r.t0, {
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
        mutationCmd(r.caseId, r.eventId, "op-can-1", rT1, {
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
        mutationCmd(r.caseId, r.eventId, "op-can-9", r.t0, {
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
        mutationCmd(base.caseId, "ce_naoexiste", "op-u", base.t0, reason),
      ),
      depsFor({db: base.db, now: T1}),
    ),
    "not-found",
    "U: evento inexistente",
  );

  // V — updated_at armazenado malformado.
  const v = await seedDraftEvent();
  const vev = eventOf(v.db, v.eventPath);
  delete vev.updated_at;
  v.db._store.set(v.eventPath, vev);
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(mutationCmd(v.caseId, v.eventId, "op-v", v.t0, reason)),
      depsFor({db: v.db, now: T1}),
    ),
    "integrity",
    "V: updated_at armazenado ausente",
  );

  // W/X/Y/Z/AA — escopo e capability.
  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(base.caseId, base.eventId, "op-w", base.t0, reason),
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
          mutationCmd(base.caseId, base.eventId, "op-c", base.t0, reason),
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
          mutationCmd(base.caseId, base.eventId, "op-inj", base.t0, {
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
      mockRequest(mutationCmd(m.caseId, m.eventId, "op-mal", m.t0, reason)),
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
  f.db._store.set(f.eventPath, fev);
  assert.strictEqual(fev.status, "draft", "pré-condição: evento segue draft");

  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(mutationCmd(f.caseId, f.eventId, "op-stale-f", f.t0)),
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
      mutationCmd(f.caseId, f.eventId, "op-fresh-f", advanced.toMillis()),
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
  c.db._store.set(c.eventPath, cev);

  await expectReject(
    () => runHealthCancelClinicalEvent(
      mockRequest(
        mutationCmd(c.caseId, c.eventId, "op-stale-c", c.t0, {
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
      mutationCmd(c.caseId, c.eventId, "op-fresh-c", cAdvanced.toMillis(), {
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
          mutationCmd(s.caseId, s.eventId, "op-pre", s.t0, extra),
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
  const cmdNoToken = mutationCmd(s.caseId, s.eventId, "op-pre2", s.t0);
  delete cmdNoToken.expectedUpdatedAt;
  await expectReject(
    () => runHealthFinalizeClinicalEvent(
      mockRequest(cmdNoToken),
      depsFor({db: s.db, now: T1}),
    ),
    "validation",
    "FINALIZE sem expectedUpdatedAt",
  );
  assert.strictEqual(
    s.db._transactions(),
    txBefore,
    "token ausente abriu transação no Firestore",
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
        mockRequest(mutationCmd(f.caseId, f.eventId, "op-m", f.t0)),
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
          mockRequest(mutationCmd(f.caseId, f.eventId, "op-m", f.t0)),
          depsFor({db: f.db, ...row.opts, now: T1}),
        ),
        "permission-denied",
        `${row.label}: finalize deveria ser negado`,
      );
    }

    // CANCEL
    const c = await seedDraftEvent();
    const cmd = mutationCmd(c.caseId, c.eventId, "op-m", c.t0, {
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
    const staleAt = body.indexOf("assertFreshToken(");
    assert.ok(replayAt > 0, `${label}: matchClinicalReceipt ausente`);
    assert.ok(staleAt > 0, `${label}: assertFreshToken ausente`);
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
