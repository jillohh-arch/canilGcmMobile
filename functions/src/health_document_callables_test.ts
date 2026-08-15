/**
 * Testes dos callables de HealthDocument com fake Firestore + fake Storage.
 * npm run build && node lib/health_document_callables_test.js
 */
import * as assert from "assert";
import * as crypto from "crypto";

import {
  DocumentCaller,
  HealthDocumentCallableDeps,
  HealthDocumentStorageAdapter,
  runHealthDocumentFinalizeUpload,
  runHealthDocumentPrepareUpload,
} from "./health_document_callables";
import {
  MAX_DOCUMENT_BYTES,
  StorageObjectMetadata,
  createIdempotencyMaterial,
  deterministicDocumentId,
  fingerprintCreateDocumentIntent,
  sealFingerprintMaterial,
  sealMetadata,
} from "./health_document_logic";

type JsonMap = Record<string, unknown>;

const actor: DocumentCaller = {
  uid: "uid-op",
  email: "691755@gcm.com.br",
  ra: "691755",
  name: "Operador",
};

const actorB: DocumentCaller = {
  uid: "uid-op-b",
  email: "691756@gcm.com.br",
  ra: "691756",
  name: "Operador B",
};

const FIXED_NOW = new Date("2026-08-15T12:00:00.000Z");

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

function idFor(dogId: string, operationId: string): string {
  return deterministicDocumentId(
    sha256Hex(createIdempotencyMaterial(dogId, operationId)),
  );
}

// ── Fake Firestore ───────────────────────────────────────────────────────────

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
    /**
     * Modela a concorrência otimista real do Firestore: os paths lidos são
     * rastreados e, se algum deles mudar antes do commit, a transação é
     * reexecutada. Sem isso, duas transações concorrentes leriam ambas
     * "missing" e criariam dois documentos — um artefato do fake, não do
     * comportamento real, que esconderia justamente o recheck que existe para
     * eliminar essa corrida.
     */
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{
          exists: boolean;
          data: () => JsonMap;
        }>;
        set: (ref: {path: string}, data: JsonMap) => void;
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
          set(ref: {path: string}, data: JsonMap) {
            pending.set(ref.path, {...data});
          },
        };
        const result = await fn(tx);
        // Cede o event loop para permitir entrelaçamento real entre transações.
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

/**
 * Fake de Storage que modela a semântica real do selo:
 *
 * - a cópia é presa à `sourceGeneration` (se a generation atual do staging
 *   divergir, falha como a precondition de fonte faria);
 * - o destino é create-only (`ifGenerationMatch: 0`): se já existir objeto
 *   canônico, devolve `sealed: false` em vez de sobrescrever.
 */
function fakeStorage(
  objects: Record<string, StorageObjectMetadata> = {},
): HealthDocumentStorageAdapter & {
  _reads: () => string[];
  _store: Map<string, StorageObjectMetadata>;
  _seals: () => number;
  _deletes: () => string[];
  _failDelete?: boolean;
} {
  const reads: string[] = [];
  const deletes: string[] = [];
  const store = new Map<string, StorageObjectMetadata>();
  for (const [k, v] of Object.entries(objects)) store.set(k, {...v});
  let seals = 0;
  const api = {
    getObjectMetadata: async (path: string) => {
      reads.push(path);
      return store.get(path) ?? {exists: false};
    },
    sealObject: async (params: {
      sourcePath: string;
      sourceGeneration: string;
      destinationPath: string;
      sealMetadata: Record<string, string>;
    }) => {
      const source = store.get(params.sourcePath);
      if (!source || source.exists !== true) {
        const err = new Error("source missing") as Error & {code: number};
        err.code = 404;
        throw err;
      }
      // Precondition de FONTE: generation deve ser exatamente a validada.
      if (String(source.generation) !== params.sourceGeneration) {
        const err = new Error("source generation mismatch") as Error & {
          code: number;
        };
        err.code = 412;
        throw err;
      }
      // Precondition de DESTINO: create-only.
      if (store.has(params.destinationPath)) return {sealed: false};
      seals += 1;
      // O selo é gravado no destino junto com os bytes, no mesmo request.
      store.set(params.destinationPath, {
        ...source,
        generation: `sealed-${seals}`,
        customMetadata: {...params.sealMetadata},
      });
      return {sealed: true};
    },
    getSealedMetadata: async (path: string) => {
      reads.push(path);
      return store.get(path) ?? {exists: false};
    },
    deleteStagingObject: async (path: string) => {
      if (api._failDelete === true) throw new Error("cleanup boom");
      deletes.push(path);
      store.delete(path);
    },
    _reads: () => reads,
    _store: store,
    _seals: () => seals,
    _deletes: () => deletes,
    _failDelete: false,
  };
  return api;
}

const validObject: StorageObjectMetadata = {
  exists: true,
  contentType: "application/pdf",
  size: 4096,
  md5Hash: "md5-abc",
  crc32c: "crc-abc",
  generation: "1723723200000000",
};

/** Staging é o único destino de upload do cliente. */
function stagingFor(dogId: string, documentId: string): string {
  return `health_document_uploads/${dogId}/${documentId}`;
}

/**
 * Reproduz o selo que a produção gravaria para uma intenção, permitindo semear
 * um objeto canônico legítimo em testes de recuperação.
 */
function sealMetadataFor(
  dogId: string,
  operationId: string,
  overrides: {title?: string} = {},
): Record<string, string> {
  const documentId = idFor(dogId, operationId);
  const finalizeFingerprint = fingerprintCreateDocumentIntent({
    dogId,
    documentType: "certificate",
    title: overrides.title ?? "Atestado veterinário",
    description: null,
    issuer: null,
    issueDateIso: null,
    expiryDateIso: null,
    caseId: null,
    eventId: null,
    examId: null,
  });
  const sealFingerprint = sha256Hex(
    sealFingerprintMaterial({dogId, operationId, finalizeFingerprint}),
  );
  return sealMetadata({sealFingerprint, documentId});
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mockRequest(data: JsonMap, auth: any = {uid: actor.uid, token: {}}): any {
  return {data, auth};
}

function depsFor(options: {
  db: FirebaseFirestore.Firestore;
  storage?: HealthDocumentStorageAdapter;
  allowCreate?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: DocumentCaller;
}): HealthDocumentCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  return {
    db: options.db,
    storage: options.storage ?? fakeStorage(),
    now: () => FIXED_NOW,
    requireHealthCreate: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowCreate === false) {
        throw new HttpsError("permission-denied", "sem health.create", {
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

const validPayload: JsonMap = {
  dogId: "dog-1",
  operationId: "op-1",
  documentType: "certificate",
  title: "Atestado veterinário",
};

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

function storeKeys(db: {_store: Map<string, JsonMap>}): string[] {
  return [...db._store.keys()].sort();
}

// ── PREPARE ──────────────────────────────────────────────────────────────────

async function testPrepare() {
  const db = dbWithDog();
  const deps = depsFor({db});
  const before = storeKeys(db);

  const res = (await runHealthDocumentPrepareUpload(
    mockRequest({dogId: "dog-1", operationId: "op-1"}),
    deps,
  )) as JsonMap;

  const expectedId = idFor("dog-1", "op-1");
  assert.strictEqual(res.document_id, expectedId, "documentId determinístico");
  assert.strictEqual(
    res.upload_path,
    `health_document_uploads/dog-1/${expectedId}`,
    "PREPARE expõe o path de STAGING",
  );
  assert.strictEqual(
    res.storage_path,
    undefined,
    "path canônico não é exposto ao cliente",
  );
  assert.strictEqual(res.dogId, "dog-1", "espelho camelCase");
  assert.strictEqual(res.documentId, expectedId, "espelho camelCase id");

  // ZERO writes.
  assert.deepStrictEqual(storeKeys(db), before, "PREPARE não escreve nada");

  // Repetição devolve exatamente o mesmo par.
  const again = (await runHealthDocumentPrepareUpload(
    mockRequest({dogId: "dog-1", operationId: "op-1"}),
    deps,
  )) as JsonMap;
  assert.strictEqual(again.document_id, res.document_id, "id estável");
  assert.strictEqual(again.upload_path, res.upload_path, "path estável");
  assert.deepStrictEqual(storeKeys(db), before, "repetição também sem write");

  // operationId diferente → identidade diferente.
  const other = (await runHealthDocumentPrepareUpload(
    mockRequest({dogId: "dog-1", operationId: "op-2"}),
    deps,
  )) as JsonMap;
  assert.notStrictEqual(other.document_id, res.document_id, "op diferente");
}

async function testPrepareGuards() {
  const db = dbWithDog();

  // Sem auth: o gate lança HttpsError sem details.code, valida pelo code HTTP.
  // `null` e não `undefined`: default parameter reintroduziria o auth válido.
  let unauthenticated: string | undefined;
  try {
    await runHealthDocumentPrepareUpload(
      mockRequest({dogId: "dog-1", operationId: "op-1"}, null),
      depsFor({db}),
    );
  } catch (err) {
    unauthenticated = (err as {code?: string}).code;
  }
  assert.strictEqual(
    unauthenticated,
    "unauthenticated",
    "sem auth → unauthenticated",
  );

  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({dogId: "dog-1", operationId: "op-1"}),
        depsFor({db, allowCreate: false}),
      ),
    "permission-denied",
    "sem health.create",
  );

  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({dogId: "dog-1", operationId: "op-1"}),
        depsFor({db, dogAccess: false}),
      ),
    "permission-denied",
    "sem acesso ao K9",
  );

  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({dogId: "a/b", operationId: "op-1"}),
        depsFor({db}),
      ),
    "validation",
    "dogId inválido",
  );

  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({dogId: "dog-404", operationId: "op-1"}),
        depsFor({db}),
      ),
    "not-found",
    "K9 inexistente",
  );

  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({dogId: "dog-1"}),
        depsFor({db}),
      ),
    "validation",
    "operationId ausente",
  );

  // Campos server-owned não são aceitos nem no PREPARE.
  await expectReject(
    () =>
      runHealthDocumentPrepareUpload(
        mockRequest({
          dogId: "dog-1",
          operationId: "op-1",
          storagePath: "health_documents/dog-1/forjado",
        }),
        depsFor({db}),
      ),
    "validation",
    "storagePath injetado",
  );
}

// ── FINALIZE: sucesso ────────────────────────────────────────────────────────

async function testFinalizeSuccess() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const db = dbWithDog();
  const storage = fakeStorage({[path]: validObject});
  const deps = depsFor({db, storage});

  const res = (await runHealthDocumentFinalizeUpload(
    mockRequest({
      ...validPayload,
      description: " Laudo de liberação ",
      issuer: " Clínica Central ",
      issueDate: "2026-08-01T00:00:00.000Z",
      expiryDate: "2027-08-01T00:00:00.000Z",
      caseId: "case-9",
    }),
    deps,
  )) as JsonMap;

  assert.strictEqual(res.was_no_op, false, "primeiro finalize cria");
  assert.strictEqual(res.document_id, documentId);
  assert.deepStrictEqual(
    res.reference,
    {health_document_id: documentId},
    "referência por identidade",
  );

  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const record = db._store.get(docPath) as JsonMap;
  assert.ok(record, "agregado persistido");

  // Contrato canônico obrigatório.
  assert.strictEqual(record.document_type, "certificate");
  assert.strictEqual(record.title, "Atestado veterinário");
  assert.strictEqual(
    record.storage_path,
    canonicalPath,
    "agregado persiste o path CANÔNICO, nunca o staging",
  );
  assert.strictEqual(record.mime_type, "application/pdf", "mime do metadata");
  assert.strictEqual(record.schema_version, 1);
  assert.deepStrictEqual(record.recorded_by, {
    uid: actor.uid,
    name: actor.name,
    internal_role: "condutor",
  });
  assert.ok(record.uploaded_at, "uploaded_at server-side presente");
  assert.strictEqual(record.file_size_bytes, 4096, "size do metadata");

  // Opcionais normalizados/trimados.
  assert.strictEqual(record.description, "Laudo de liberação");
  assert.strictEqual(record.issuer, "Clínica Central");
  assert.strictEqual(record.case_id, "case-9");
  assert.ok(record.issue_date, "issue_date persistido");
  assert.ok(record.expiry_date, "expiry_date persistido");
  assert.ok(!("event_id" in record), "opcional ausente não vira null");
  assert.ok(!("exam_id" in record), "opcional ausente omitido");

  // Metadados de mutação NÃO contaminam o agregado (decisão B0-A.2).
  for (const forbidden of [
    "revision",
    "create_fingerprint",
    "create_operation_id",
    "operation_id",
    "fingerprint",
    "storage_url",
    "download_url",
    "professional",
    "checksum_md5",
    "storage_generation",
  ]) {
    assert.ok(
      !(forbidden in record),
      `agregado não carrega ${forbidden}`,
    );
  }

  // Receipt e audit criados, exatamente um de cada.
  const receiptPath = `${docPath}/operations/op-1`;
  const receipt = db._store.get(receiptPath) as JsonMap;
  assert.ok(receipt, "receipt persistido");
  assert.strictEqual(receipt.kind, "health_document_create_v1");
  assert.strictEqual(receipt.operation_type, "create_document");
  assert.strictEqual(receipt.actor_uid, actor.uid);
  assert.ok(receipt.fingerprint, "fingerprint vive no receipt");

  const auditKeys = storeKeys(db).filter((k) => k.startsWith("auditLogs/"));
  assert.strictEqual(auditKeys.length, 1, "exatamente um audit");
  const audit = db._store.get(auditKeys[0]) as JsonMap;
  assert.strictEqual(audit.action, "health_document_created");
  assert.strictEqual(audit.entity_type, "health_documents");
  assert.strictEqual(audit.entity_path, docPath);
  const meta = audit.metadata as JsonMap;
  assert.strictEqual(meta.checksum_md5, "md5-abc", "checksum no audit");
  assert.strictEqual(meta.size_bytes, 4096);
  // `storage_generation` descreve o objeto CANÔNICO selado (B0-B.R), não a
  // generation do staging — que é registrada separadamente em
  // `source_generation` para rastrear a origem do selo.
  assert.strictEqual(meta.storage_generation, "sealed-1");
  assert.strictEqual(meta.source_generation, "1723723200000000");
  const auditJson = JSON.stringify(audit);
  assert.ok(!auditJson.includes("http"), "audit sem URL");

  // Exatamente três documentos escritos.
  assert.strictEqual(
    storeKeys(db).filter((k) => k !== "dogs/dog-1").length,
    3,
    "agregado + receipt + audit",
  );
}

// ── FINALIZE: replay e conflito ──────────────────────────────────────────────

async function testReplayAndConflict() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const db = dbWithDog();
  const storage = fakeStorage({[path]: validObject});
  const deps = depsFor({db, storage});

  await runHealthDocumentFinalizeUpload(mockRequest(validPayload), deps);
  const afterFirst = storeKeys(db);
  const txnAfterFirst = db._transactions();

  // Replay: mesmo payload, mesmo operationId.
  const replay = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    deps,
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "replay sinalizado");
  assert.strictEqual(replay.document_id, documentId, "mesmo id no replay");
  assert.deepStrictEqual(
    storeKeys(db),
    afterFirst,
    "replay não escreve nada",
  );
  assert.strictEqual(
    db._transactions(),
    txnAfterFirst,
    "replay resolve no fast path, sem transação",
  );

  // Conflito: mesmo operationId, payload diferente.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest({...validPayload, title: "Outro título"}),
        deps,
      ),
    "idempotency-conflict",
    "mesma chave com intenção diferente",
  );
  assert.deepStrictEqual(
    storeKeys(db),
    afterFirst,
    "conflito não cria segundo documento",
  );

  // Outro ator com o mesmo operationId → conflito, não replay.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage, caller: actorB}),
      ),
    "idempotency-conflict",
    "actor divergente",
  );
}

// ── FINALIZE: invariante documento-sem-receipt ───────────────────────────────

async function testEntityWithoutReceiptFailsClosed() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const docPath = `dogs/dog-1/health_documents/${documentId}`;

  // Documento presente SEM receipt: estado impossível no protocolo.
  const db = dbWithDog({
    [docPath]: {
      document_type: "report",
      title: "Documento de origem desconhecida",
      storage_path: path,
      mime_type: "application/pdf",
      schema_version: 1,
    },
  });
  const storage = fakeStorage({[path]: validObject});

  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage}),
      ),
    "integrity",
    "documento sem receipt falha fechado",
  );

  // E não sobrescreve a evidência preexistente.
  const record = db._store.get(docPath) as JsonMap;
  assert.strictEqual(
    record.title,
    "Documento de origem desconhecida",
    "não sobrescreve documento de origem desconhecida",
  );
}

async function testMalformedReceiptFailsClosed() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const receiptPath =
    `dogs/dog-1/health_documents/${documentId}/operations/op-1`;
  const storage = fakeStorage({[path]: validObject});

  // Receipt sem campos canônicos.
  const dbBroken = dbWithDog({[receiptPath]: {operation_id: "op-1"}});
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbBroken, storage}),
      ),
    "integrity",
    "receipt malformado",
  );

  // Receipt de kind/version incompatível.
  const dbWrongKind = dbWithDog({
    [receiptPath]: {
      kind: "outro_kind_v9",
      operation_id: "op-1",
      operation_type: "create_document",
      actor_uid: actor.uid,
      fingerprint: "fp",
      result: {dogId: "dog-1", documentId},
    },
  });
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbWrongKind, storage}),
      ),
    "integrity",
    "receipt de kind incompatível",
  );
}

// ── FINALIZE: verificação de Storage ─────────────────────────────────────────

async function testStorageVerification() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;

  // Objeto ausente → falha, nenhum documento criado.
  const dbMissing = dbWithDog();
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbMissing, storage: fakeStorage()}),
      ),
    "integrity",
    "objeto ausente",
  );
  assert.deepStrictEqual(
    storeKeys(dbMissing),
    ["dogs/dog-1"],
    "objeto ausente não cria documento sem arquivo",
  );

  // MIME não permitido.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({
            [path]: {exists: true, contentType: "text/html", size: 10},
          }),
        }),
      ),
    "validation",
    "MIME inválido",
  );

  // MIME ausente.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({[path]: {exists: true, size: 10}}),
        }),
      ),
    "integrity",
    "MIME ausente",
  );

  // Acima de 20 MB.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({
            [path]: {
              exists: true,
              contentType: "application/pdf",
              size: MAX_DOCUMENT_BYTES + 1,
            },
          }),
        }),
      ),
    "validation",
    "excede 20 MB",
  );

  // Metadata malformada (size não numérico).
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({
            [path]: {exists: true, contentType: "image/png", size: "abc"},
          }),
        }),
      ),
    "integrity",
    "size malformado",
  );

  // O path verificado é sempre o derivado.
  const storage = fakeStorage({[path]: validObject});
  await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db: dbWithDog(), storage}),
  );
  // Ordem: sonda o canônico primeiro (autoridade), depois valida o staging,
  // e relê o canônico já selado.
  assert.deepStrictEqual(
    storage._reads(),
    [canonicalPath, path, canonicalPath],
    "sondou canônico, validou staging derivado, releu canônico selado",
  );
}

// ── FINALIZE: guards e injeção ───────────────────────────────────────────────

async function testFinalizeGuards() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const storage = fakeStorage({[path]: validObject});

  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbWithDog(), storage, allowCreate: false}),
      ),
    "permission-denied",
    "sem health.create",
  );

  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbWithDog(), storage, dogAccess: false}),
      ),
    "permission-denied",
    "sem acesso ao K9",
  );

  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest({...validPayload, dogId: "dog-404"}),
        depsFor({db: dbWithDog(), storage}),
      ),
    "not-found",
    "K9 inexistente",
  );

  // Injeção de campos server-owned.
  const injections: Array<[string, unknown]> = [
    ["recorded_by", {uid: "evil"}],
    ["recordedBy", {uid: "evil"}],
    ["storage_path", "health_documents/dog-1/forjado"],
    ["storagePath", "health_documents/dog-1/forjado"],
    ["uploaded_at", "2020-01-01T00:00:00.000Z"],
    ["uploadedAt", "2020-01-01T00:00:00.000Z"],
    ["mime_type", "application/pdf"],
    ["mimeType", "application/pdf"],
    ["schema_version", 99],
    ["revision", 5],
    ["create_fingerprint", "forjado"],
    ["create_operation_id", "forjado"],
    ["storage_url", "https://exemplo/x"],
    ["download_url", "https://exemplo/x"],
    ["file_size_bytes", 1],
    ["professional", {name: "Dr X"}],
    ["id", "hd_forjado"],
    ["documentId", "hd_forjado"],
  ];
  for (const [key, value] of injections) {
    await expectReject(
      () =>
        runHealthDocumentFinalizeUpload(
          mockRequest({...validPayload, [key]: value}),
          depsFor({db: dbWithDog(), storage}),
        ),
      "validation",
      `injeção rejeitada: ${key}`,
    );
  }

  // document_type inválido e legado.
  for (const bad of ["laudo", "certificado", "documento", "exame", "xyz"]) {
    await expectReject(
      () =>
        runHealthDocumentFinalizeUpload(
          mockRequest({...validPayload, documentType: bad}),
          depsFor({db: dbWithDog(), storage}),
        ),
      "validation",
      `documentType rejeitado: ${bad}`,
    );
  }

  // title vazio e só-espaços.
  for (const bad of ["", "   ", "\t "]) {
    await expectReject(
      () =>
        runHealthDocumentFinalizeUpload(
          mockRequest({...validPayload, title: bad}),
          depsFor({db: dbWithDog(), storage}),
        ),
      "validation",
      `title rejeitado: ${JSON.stringify(bad)}`,
    );
  }

  // expiry antes de issue.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest({
          ...validPayload,
          issueDate: "2027-01-01T00:00:00.000Z",
          expiryDate: "2026-01-01T00:00:00.000Z",
        }),
        depsFor({db: dbWithDog(), storage}),
      ),
    "validation",
    "expiry antes de issue",
  );
}

// ── FINALIZE: admin e concorrência ───────────────────────────────────────────

async function testAdminRole() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const db = dbWithDog();
  await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage: fakeStorage({[path]: validObject}), admin: true}),
  );
  const record = db._store.get(
    `dogs/dog-1/health_documents/${documentId}`,
  ) as JsonMap;
  assert.deepStrictEqual(
    record.recorded_by,
    {uid: actor.uid, name: actor.name, internal_role: "admin"},
    "internal_role admin vem do servidor",
  );
  // Admin não vira ProfessionalIdentity.
  assert.ok(!("professional" in record), "admin não é profissional clínico");
}

async function testConcurrentFinalize() {
  const documentId = idFor("dog-1", "op-1");
  const path = stagingFor("dog-1", documentId);
  const docPath = `dogs/dog-1/health_documents/${documentId}`;

  // Idênticos e concorrentes: um cria, o outro é no-op.
  const db = dbWithDog();
  const deps = depsFor({db, storage: fakeStorage({[path]: validObject})});
  const results = (await Promise.all([
    runHealthDocumentFinalizeUpload(mockRequest(validPayload), deps),
    runHealthDocumentFinalizeUpload(mockRequest(validPayload), deps),
  ])) as JsonMap[];

  const created = results.filter((r) => r.was_no_op === false);
  assert.strictEqual(created.length, 1, "exatamente um create efetivo");
  assert.strictEqual(
    results.filter((r) => r.was_no_op === true).length,
    1,
    "o outro é replay/no-op",
  );
  assert.ok(db._store.get(docPath), "documento único presente");
  assert.strictEqual(
    storeKeys(db).filter((k) => k.startsWith("auditLogs/")).length,
    1,
    "exatamente um audit lógico",
  );
  assert.strictEqual(
    storeKeys(db).filter((k) => k.includes("/operations/")).length,
    1,
    "exatamente um receipt",
  );

  // Concorrentes com payload divergente: um vence, o outro conflita.
  const db2 = dbWithDog();
  const deps2 = depsFor({db: db2, storage: fakeStorage({[path]: validObject})});
  const settled = await Promise.allSettled([
    runHealthDocumentFinalizeUpload(mockRequest(validPayload), deps2),
    runHealthDocumentFinalizeUpload(
      mockRequest({...validPayload, title: "Divergente"}),
      deps2,
    ),
  ]);
  const fulfilled = settled.filter((s) => s.status === "fulfilled");
  assert.ok(fulfilled.length >= 1, "ao menos um conclui");
  assert.strictEqual(
    storeKeys(db2).filter((k) => k === docPath).length,
    1,
    "nunca cria segundo documento",
  );
}

// ── SELO canônico (B0-B.R) ───────────────────────────────────────────────────

async function testSealHappyPath() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const db = dbWithDog();
  const storage = fakeStorage({[staging]: validObject});

  await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  );

  assert.strictEqual(storage._seals(), 1, "selou exatamente uma vez");
  assert.ok(storage._store.has(canonicalPath), "objeto canônico criado");
  assert.deepStrictEqual(
    storage._deletes(),
    [staging],
    "staging limpo best-effort após commit",
  );
  assert.ok(!storage._store.has(staging), "staging removido");

  const record = db._store.get(
    `dogs/dog-1/health_documents/${documentId}`,
  ) as JsonMap;
  assert.strictEqual(
    record.storage_path,
    canonicalPath,
    "agregado aponta para o canônico",
  );
  assert.ok(
    !String(record.storage_path).includes("health_document_uploads"),
    "staging nunca vira storage_path",
  );

  // Metadata do agregado e do audit descreve o objeto CANÔNICO.
  const auditKey = storeKeys(db).find((k) => k.startsWith("auditLogs/"))!;
  const audit = db._store.get(auditKey) as JsonMap;
  const meta = audit.metadata as JsonMap;
  assert.strictEqual(
    meta.storage_generation,
    "sealed-1",
    "audit registra a generation do canônico",
  );
  assert.strictEqual(
    meta.source_generation,
    validObject.generation,
    "audit também registra a generation de origem selada",
  );
}

async function testSealSourceMissing() {
  const db = dbWithDog();
  // Nada no staging: o cliente não subiu.
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage: fakeStorage()}),
      ),
    "integrity",
    "objeto de staging ausente",
  );
  assert.deepStrictEqual(
    storeKeys(db),
    ["dogs/dog-1"],
    "sem documento sem arquivo",
  );
}

async function testSealSourceGenerationChanged() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const db = dbWithDog();
  const storage = fakeStorage({[staging]: validObject});

  // Substitui os bytes do staging ENTRE a validação e a cópia. É exatamente o
  // que a precondition de fonte existe para impedir: selar evidência diferente
  // da que o operador submeteu.
  const original = storage.getObjectMetadata;
  storage.getObjectMetadata = async (path: string) => {
    const result = await original(path);
    storage._store.set(staging, {...validObject, generation: "999"});
    return result;
  };

  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage}),
      ),
    "unexpected",
    "generation da fonte mudou → falha",
  );
  assert.strictEqual(storage._seals(), 0, "nada foi selado");
}

async function testSealMissingGeneration() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({
            [staging]: {
              exists: true,
              contentType: "application/pdf",
              size: 10,
              md5Hash: "m",
            },
          }),
        }),
      ),
    "integrity",
    "sem generation não há como selar",
  );
}

async function testSealMissingChecksum() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({
          db: dbWithDog(),
          storage: fakeStorage({
            [staging]: {
              exists: true,
              contentType: "application/pdf",
              size: 10,
              generation: "7",
            },
          }),
        }),
      ),
    "integrity",
    "sem md5 nem crc32c a integridade não é verificável",
  );
}

/**
 * B0-B.R2 — o gap que esta rodada corrige.
 *
 * Janela: selo OK, transação Firestore falhou, então NÃO existe receipt com o
 * fingerprint F1 em lugar durável. Um segundo FINALIZE com o MESMO operationId
 * e payload DIFERENTE (F2), com bytes de staging idênticos, não pode conseguir
 * associar P2 aos bytes selados por P1 — isso furaria a promessa
 * "same operationId + different payload → conflict" após falha parcial.
 *
 * A prova durável passa a viver na metadata server-owned do objeto canônico.
 */
async function testSealedIntentBindingRejectsDifferentPayload() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const storage = fakeStorage({[staging]: validObject});

  // FINALIZE #1 com P1: selo acontece, Firestore falha.
  const db = dbWithDog();
  const realTxn = db.runTransaction.bind(db);
  (db as unknown as {runTransaction: unknown}).runTransaction = async () => {
    throw new Error("firestore indisponível");
  };
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage}),
      ),
    "unexpected",
    "P1: falha após o selo",
  );
  assert.strictEqual(storage._seals(), 1, "selo de P1 aconteceu");
  assert.ok(storage._store.has(canonicalPath), "bytes canônicos de P1");
  assert.ok(!db._store.get(docPath), "sem HealthDocument");
  assert.ok(
    !storeKeys(db).some((k) => k.includes("/operations/")),
    "sem receipt: nada durável no Firestore prova F1",
  );

  // FINALIZE #2: mesmo operationId, payload DIFERENTE, bytes iguais.
  (db as unknown as {runTransaction: unknown}).runTransaction = realTxn;
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest({...validPayload, title: "Intenção diferente"}),
        depsFor({db, storage}),
      ),
    "idempotency-conflict",
    "P2 não pode herdar bytes selados por P1",
  );

  assert.ok(
    !db._store.get(docPath),
    "nenhum HealthDocument criado com a intenção divergente",
  );
  assert.strictEqual(storage._seals(), 1, "não selou de novo");

  // E o retry legítimo com P1 ainda conclui.
  const ok = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  )) as JsonMap;
  assert.strictEqual(ok.was_no_op, false, "retry com P1 conclui");
  assert.ok(db._store.get(docPath), "documento criado para a intenção correta");
}

async function testSealedButNotCommittedRecovery() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;

  // Janela de crash: selo OK, transação Firestore não commitou. Storage e
  // Firestore não compartilham transação, então este estado é legítimo — e é
  // DIFERENTE de "documento existe sem receipt", que é corrupção.
  const db = dbWithDog();
  const storage = fakeStorage({
    [staging]: validObject,
    // Selo legítimo da MESMA intenção, como a tentativa anterior teria gravado.
    [canonicalPath]: {
      ...validObject,
      generation: "sealed-anterior",
      customMetadata: sealMetadataFor("dog-1", "op-1"),
    },
  });

  const res = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  )) as JsonMap;

  assert.strictEqual(res.was_no_op, false, "retry conclui a criação");
  assert.strictEqual(storage._seals(), 0, "não selou de novo");
  assert.ok(db._store.get(docPath), "HealthDocument agora existe");
  assert.strictEqual(
    storage._store.get(canonicalPath)!.generation,
    "sealed-anterior",
    "objeto canônico preexistente NÃO foi sobrescrito",
  );
}

/**
 * Divergência de SELO — não de bytes — é o que decide.
 *
 * Um canônico com selo válido para esta intenção prova que seus bytes foram
 * validados no momento do selo: o destino é create-only via precondition, o
 * cliente não escreve no canônico, e o backend só cria canônico copiando um
 * staging validado com generation presa. Logo, "selo válido + staging atual
 * diferente" é apenas o caso C (staging sobrescrito depois do selo) e deve
 * RECUPERAR.
 *
 * O que precisa falhar fechado é selo de OUTRA intenção — coberto aqui e em
 * `testSealedIntentBindingRejectsDifferentPayload`. A comparação byte-a-byte
 * (`assertSealedObjectMatches`) segue testada na suíte de lógica pura.
 */
async function testSealedMismatchFailsClosed() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;

  // Selo de intenção DIFERENTE → conflito, sem criar documento.
  const alienSeal = sealMetadataFor("dog-1", "op-1", {
    title: "Outra intenção",
  });
  const dbAlien = dbWithDog();
  const storageAlien = fakeStorage({
    [staging]: validObject,
    [canonicalPath]: {
      ...validObject,
      generation: "s1",
      customMetadata: alienSeal,
    },
  });
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbAlien, storage: storageAlien}),
      ),
    "idempotency-conflict",
    "selo de outra intenção falha fechado",
  );
  assert.ok(!dbAlien._store.get(docPath), "nenhum documento criado");
  assert.strictEqual(storageAlien._seals(), 0, "nunca re-sela");

  // Selo VÁLIDO com staging divergente → recupera (caso C), sem re-selar.
  const dbOk = dbWithDog();
  const storageOk = fakeStorage({
    [staging]: {...validObject, md5Hash: "md5-outro", generation: "outra"},
    [canonicalPath]: {
      ...validObject,
      generation: "s1",
      customMetadata: sealMetadataFor("dog-1", "op-1"),
    },
  });
  const res = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db: dbOk, storage: storageOk}),
  )) as JsonMap;
  assert.strictEqual(res.was_no_op, false, "selo válido recupera");
  assert.strictEqual(storageOk._seals(), 0, "sem novo selo");
  const record = dbOk._store.get(docPath) as JsonMap;
  assert.strictEqual(
    record.mime_type,
    validObject.contentType,
    "metadata vem do canônico, não do staging divergente",
  );
}

async function testFirestoreFailureAfterSealIsRetryable() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const storage = fakeStorage({[staging]: validObject});

  // Primeira tentativa: selo OK, transação explode.
  const dbBroken = dbWithDog();
  const realTxn = dbBroken.runTransaction.bind(dbBroken);
  (dbBroken as unknown as {runTransaction: unknown}).runTransaction =
    async () => {
      throw new Error("firestore indisponível");
    };
  await expectReject(
    () =>
      runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db: dbBroken, storage}),
      ),
    "unexpected",
    "falha de Firestore após o selo",
  );
  assert.strictEqual(storage._seals(), 1, "selo aconteceu");
  assert.ok(storage._store.has(canonicalPath), "bytes canônicos permanecem");
  assert.ok(
    !dbBroken._store.get(docPath),
    "sem HealthDocument → bytes ainda NÃO são evidência clínica",
  );

  // Retry no mesmo db, agora com a transação funcionando.
  (dbBroken as unknown as {runTransaction: unknown}).runTransaction = realTxn;
  const res = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db: dbBroken, storage}),
  )) as JsonMap;
  assert.strictEqual(res.was_no_op, false, "retry cria o documento");
  assert.strictEqual(storage._seals(), 1, "não produziu segundo canônico");
  assert.ok(dbBroken._store.get(docPath), "documento criado no retry");
}

async function testCleanupFailureDoesNotInvalidate() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const db = dbWithDog();
  const storage = fakeStorage({[staging]: validObject});
  storage._failDelete = true;

  // Falha de limpeza NÃO pode transformar finalize bem-sucedido em erro.
  const res = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  )) as JsonMap;

  assert.strictEqual(res.was_no_op, false, "finalize concluiu");
  assert.ok(db._store.get(docPath), "HealthDocument permanece válido");
  assert.ok(
    storage._store.has(staging),
    "staging sobra como orphan sem autoridade",
  );
}

async function testReplayDoesNotReseal() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const db = dbWithDog();
  const storage = fakeStorage({[staging]: validObject});

  await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  );
  const sealsAfterFirst = storage._seals();
  const deletesAfterFirst = storage._deletes().length;

  const replay = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db, storage}),
  )) as JsonMap;

  assert.strictEqual(replay.was_no_op, true, "replay");
  assert.strictEqual(
    storage._seals(),
    sealsAfterFirst,
    "replay não sela novamente",
  );
  assert.strictEqual(
    storage._deletes().length,
    deletesAfterFirst,
    "replay não re-limpa staging",
  );
  assert.strictEqual(
    replay.storage_path,
    `health_documents/dog-1/${documentId}`,
    "replay devolve o path canônico",
  );
}

/**
 * R2 casos C e D: depois de um selo bem-sucedido, o staging pode ser
 * sobrescrito ou desaparecer. A autoridade da recuperação é o SELO no objeto
 * canônico, não o staging — do contrário um overwrite acidental tornaria um
 * documento já selado irrecuperável.
 */
async function testRecoveryIndependentOfStaging() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const sealedCanonical = {
    ...validObject,
    generation: "sealed-anterior",
    customMetadata: sealMetadataFor("dog-1", "op-1"),
  };

  // C: staging SOBRESCRITO com bytes diferentes após o selo.
  const dbC = dbWithDog();
  const storageC = fakeStorage({
    [staging]: {
      ...validObject,
      generation: "outra",
      md5Hash: "md5-diferente",
      crc32c: "crc-diferente",
    },
    [canonicalPath]: sealedCanonical,
  });
  const resC = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db: dbC, storage: storageC}),
  )) as JsonMap;
  assert.strictEqual(resC.was_no_op, false, "C: retry conclui");
  assert.ok(dbC._store.get(docPath), "C: documento criado via selo");
  assert.strictEqual(storageC._seals(), 0, "C: não re-selou");

  // D: staging AUSENTE após o selo.
  const dbD = dbWithDog();
  const storageD = fakeStorage({[canonicalPath]: sealedCanonical});
  const resD = (await runHealthDocumentFinalizeUpload(
    mockRequest(validPayload),
    depsFor({db: dbD, storage: storageD}),
  )) as JsonMap;
  assert.strictEqual(resD.was_no_op, false, "D: retry conclui");
  assert.ok(dbD._store.get(docPath), "D: documento criado via selo");
}

/** R2 casos E, F, G: selo ausente ou malformado é sempre fail-closed. */
async function testMalformedSealFailsClosed() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const valid = sealMetadataFor("dog-1", "op-1");

  const cases: Array<[string, Record<string, string> | undefined]> = [
    ["E: sem metadata de selo", undefined],
    ["E: metadata vazia", {}],
    ["F: seal_version divergente", {...valid, k9_health_seal_version: "9"}],
    ["F: seal_version ausente", {k9_health_seal_fingerprint: valid.k9_health_seal_fingerprint}],
    ["G: fingerprint ausente", {k9_health_seal_version: "1"}],
    ["G: fingerprint vazio", {...valid, k9_health_seal_fingerprint: ""}],
    ["G: fingerprint forjado", {...valid, k9_health_seal_fingerprint: "forjado"}],
  ];

  for (const [label, customMetadata] of cases) {
    const storage = fakeStorage({
      [staging]: validObject,
      [canonicalPath]: {...validObject, generation: "s", customMetadata},
    });
    const db = dbWithDog();
    let rejected = false;
    try {
      await runHealthDocumentFinalizeUpload(
        mockRequest(validPayload),
        depsFor({db, storage}),
      );
    } catch (err) {
      rejected = true;
      const code = (err as {details?: {code?: string}}).details?.code;
      assert.ok(
        code === "integrity" || code === "idempotency-conflict",
        `${label}: código fail-closed esperado, recebeu ${code}`,
      );
    }
    assert.ok(rejected, `${label}: deveria falhar fechado`);
    assert.ok(
      !db._store.get(`dogs/dog-1/health_documents/${documentId}`),
      `${label}: nenhum documento criado`,
    );
  }
}

/**
 * R2 concorrência: duas intenções diferentes com o mesmo operationId, ambas
 * sem receipt. No máximo um canônico, e nenhum HealthDocument associado a um
 * fingerprint diferente do que selou os bytes.
 */
async function testConcurrentDifferentPayloads() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingFor("dog-1", documentId);
  const canonicalPath = `health_documents/dog-1/${documentId}`;
  const docPath = `dogs/dog-1/health_documents/${documentId}`;
  const db = dbWithDog();
  const storage = fakeStorage({[staging]: validObject});
  const deps = depsFor({db, storage});

  const settled = await Promise.allSettled([
    runHealthDocumentFinalizeUpload(mockRequest(validPayload), deps),
    runHealthDocumentFinalizeUpload(
      mockRequest({...validPayload, title: "Intenção concorrente"}),
      deps,
    ),
  ]);

  const fulfilled = settled.filter((s) => s.status === "fulfilled");
  assert.ok(fulfilled.length <= 1, "no máximo uma conclui");
  assert.strictEqual(storage._seals(), 1, "exatamente um objeto canônico");

  // O selo pertence a uma única intenção.
  const seal = storage._store.get(canonicalPath)!.customMetadata!;
  const sealA = sealMetadataFor("dog-1", "op-1").k9_health_seal_fingerprint;
  const sealB = sealMetadataFor("dog-1", "op-1", {
    title: "Intenção concorrente",
  }).k9_health_seal_fingerprint;
  const sealed = seal.k9_health_seal_fingerprint;
  assert.ok(
    sealed === sealA || sealed === sealB,
    "selo corresponde a uma das duas intenções",
  );

  // Se houve documento, ele pertence à intenção que selou.
  const record = db._store.get(docPath) as JsonMap | undefined;
  if (record) {
    const expectedTitle =
      sealed === sealA ? "Atestado veterinário" : "Intenção concorrente";
    assert.strictEqual(
      record.title,
      expectedTitle,
      "documento pertence à intenção que selou os bytes",
    );
  }
}

const tests: Array<[string, () => Promise<void>]> = [
  ["PREPARE determinístico e sem write", testPrepare],
  ["PREPARE guards", testPrepareGuards],
  ["FINALIZE sucesso e shape canônico", testFinalizeSuccess],
  ["FINALIZE replay e conflito", testReplayAndConflict],
  ["FINALIZE documento sem receipt falha fechado", testEntityWithoutReceiptFailsClosed],
  ["FINALIZE receipt malformado falha fechado", testMalformedReceiptFailsClosed],
  ["FINALIZE verificação de Storage", testStorageVerification],
  ["FINALIZE guards e injeção", testFinalizeGuards],
  ["FINALIZE actor admin", testAdminRole],
  ["FINALIZE concorrência", testConcurrentFinalize],
  ["SELO caminho feliz e cleanup", testSealHappyPath],
  ["SELO fonte ausente", testSealSourceMissing],
  ["SELO generation da fonte mudou", testSealSourceGenerationChanged],
  ["SELO metadata sem generation", testSealMissingGeneration],
  ["SELO metadata sem checksum", testSealMissingChecksum],
  ["R2 bind de intenção rejeita payload divergente", testSealedIntentBindingRejectsDifferentPayload],
  ["SELO recuperação sealed-but-not-committed", testSealedButNotCommittedRecovery],
  ["SELO divergência de intenção falha fechado", testSealedMismatchFailsClosed],
  ["SELO falha de Firestore é retryable", testFirestoreFailureAfterSealIsRetryable],
  ["SELO falha de cleanup não invalida", testCleanupFailureDoesNotInvalidate],
  ["SELO replay não re-sela", testReplayDoesNotReseal],
  ["R2 recuperação independe do staging (C/D)", testRecoveryIndependentOfStaging],
  ["R2 selo ausente/malformado falha fechado (E/F/G)", testMalformedSealFailsClosed],
  ["R2 concorrência com payloads divergentes", testConcurrentDifferentPayloads],
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
