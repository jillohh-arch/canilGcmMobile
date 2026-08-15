/**
 * Testes do callable de emissão de OperationalRestriction (B1).
 * npm run build && node lib/health_restriction_callables_test.js
 *
 * Inclui a prova OBRIGATÓRIA de compatibilidade: o documento produzido pelo
 * writer é alimentado no MESMO parser consumido por readiness e OP-AUTH, sem
 * adapter no meio.
 */
import * as assert from "assert";
import * as crypto from "crypto";

import {
  HealthRestrictionCallableDeps,
  RestrictionCaller,
  runHealthRestrictionIssue,
} from "./health_restriction_callables";
import {
  createIdempotencyMaterial,
  deterministicRestrictionId,
} from "./health_restriction_logic";
import {
  RawDoc,
  resolveRestrictionsEvidence,
} from "./health_readiness_evidence_logic";
import {evaluateShiftRestrictionGuard} from "./shift_restriction_guard";
import {
  DEFAULT_READINESS_CONFIG,
  EvidenceState,
  ReadinessEvidence,
  evaluateReadiness,
} from "./health_readiness_policy";

type JsonMap = Record<string, unknown>;

const actor: RestrictionCaller = {
  uid: "uid-op",
  email: "691755@gcm.com.br",
  ra: "691755",
  name: "Operador",
};

const actorB: RestrictionCaller = {
  uid: "uid-op-b",
  email: "691756@gcm.com.br",
  ra: "691756",
  name: "Operador B",
};

const FIXED_NOW = new Date("2026-08-15T12:00:00.000Z");
const DOC_ID = "hd_evidence001";

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

function idFor(dogId: string, operationId: string): string {
  return deterministicRestrictionId(
    sha256Hex(createIdempotencyMaterial(dogId, operationId)),
  );
}

// ── Fake Firestore com concorrência otimista ─────────────────────────────────

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
    /** Modela retry por staleness, como o Firestore real. */
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
  allowIssue?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: RestrictionCaller;
}): HealthRestrictionCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  return {
    db: options.db,
    now: () => FIXED_NOW,
    requireIssueRestriction: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowIssue === false) {
        throw new HttpsError("permission-denied", "sem issue_restriction", {
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

/** K9 + HealthDocument canônico (evidência) já existentes. */
function dbWithDogAndEvidence(extra: Record<string, JsonMap> = {}) {
  return createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [`dogs/dog-1/health_documents/${DOC_ID}`]: {
      document_type: "certificate",
      title: "Atestado veterinário",
      storage_path: `health_documents/dog-1/${DOC_ID}`,
      mime_type: "application/pdf",
      schema_version: 1,
    },
    ...extra,
  });
}

const validProfessional = {
  name: "Dra. Ana Souza",
  registration_type: "CRMV",
  registration_number: "SP-12345",
  clinic: "Clínica Central",
};

const validPayload: JsonMap = {
  dogId: "dog-1",
  operationId: "op-1",
  level: "absolute",
  category: "injury",
  description: "Lesão em membro anterior",
  professional: validProfessional,
  sourceDocument: {health_document_id: DOC_ID},
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

function restrictionDoc(
  db: {_store: Map<string, JsonMap>},
  restrictionId: string,
): JsonMap {
  return db._store.get(
    `dogs/dog-1/operational_restrictions/${restrictionId}`,
  ) as JsonMap;
}

// ── Sucesso e shape canônico ─────────────────────────────────────────────────

async function testIssueSuccess() {
  const db = dbWithDogAndEvidence();
  const restrictionId = idFor("dog-1", "op-1");

  const res = (await runHealthRestrictionIssue(
    mockRequest({
      ...validPayload,
      expectedEnd: "2026-09-15T00:00:00.000Z",
    }),
    depsFor({db}),
  )) as JsonMap;

  assert.strictEqual(res.was_no_op, false, "primeira emissão cria");
  assert.strictEqual(res.restriction_id, restrictionId, "id determinístico");
  assert.strictEqual(res.status, "active", "status server-owned");

  const record = restrictionDoc(db, restrictionId);
  assert.ok(record, "agregado persistido");

  // Shape canônico completo (Schema §2.12), não apenas o mínimo do parser.
  assert.strictEqual(record.status, "active");
  assert.strictEqual(record.level, "absolute");
  assert.strictEqual(record.category, "injury");
  assert.strictEqual(record.description, "Lesão em membro anterior");
  assert.deepStrictEqual(record.activities_restricted, []);
  assert.ok(record.issued_at, "issued_at canônico presente");
  assert.strictEqual(record.schema_version, 1);
  assert.deepStrictEqual(record.recorded_by, {
    uid: actor.uid,
    name: actor.name,
    internal_role: "condutor",
  });
  assert.deepStrictEqual(record.professional, {
    name: "Dra. Ana Souza",
    registration_type: "CRMV",
    registration_number: "SP-12345",
    clinic: "Clínica Central",
    specialty: null,
  });
  assert.deepStrictEqual(record.source_document, {
    health_document_id: DOC_ID,
    description: null,
  });
  assert.ok(record.expected_end, "expected_end persistido quando informado");

  // Nada de Storage nem de lifecycle de encerramento no agregado.
  for (const forbidden of [
    "storage_path",
    "mime_type",
    "storage_url",
    "download_url",
    "seal_fingerprint",
    "checksum_md5",
    "generation",
    "actual_end",
    "ended_by",
    "end_professional",
    "end_source_document",
    "end_reason",
    "cancelled_at",
    "cancel_reason",
    "revision",
    "create_fingerprint",
    "operation_id",
    "fingerprint",
  ]) {
    assert.ok(!(forbidden in record), `agregado não carrega ${forbidden}`);
  }

  // Receipt + audit, exatamente um de cada.
  const receipt = db._store.get(
    `dogs/dog-1/operational_restrictions/${restrictionId}/operations/op-1`,
  ) as JsonMap;
  assert.ok(receipt, "receipt persistido");
  assert.strictEqual(receipt.kind, "health_operational_restriction_issue_v1");
  assert.strictEqual(receipt.operation_type, "issue_restriction");
  assert.strictEqual(receipt.actor_uid, actor.uid);

  const auditKeys = storeKeys(db).filter((k) => k.startsWith("auditLogs/"));
  assert.strictEqual(auditKeys.length, 1, "exatamente um audit");
  const audit = db._store.get(auditKeys[0]) as JsonMap;
  assert.strictEqual(audit.action, "health_operational_restriction_issued");
  assert.strictEqual(audit.entity_type, "operational_restrictions");
  const meta = audit.metadata as JsonMap;
  assert.strictEqual(meta.authority, "operational_restrictions");
  assert.strictEqual(meta.source_document_id, DOC_ID);
  assert.strictEqual(meta.level, "absolute");

  // Audit sem PII clínica duplicada.
  const auditJson = JSON.stringify(audit);
  assert.ok(!auditJson.includes("SP-12345"), "audit sem registro profissional");
  assert.ok(!auditJson.includes("Clínica Central"), "audit sem clínica");
  assert.ok(!auditJson.includes("Lesão em membro"), "audit sem descrição clínica");
}

async function testPartialAndAttention() {
  // partial com atividades.
  const dbPartial = dbWithDogAndEvidence();
  const partial = (await runHealthRestrictionIssue(
    mockRequest({
      ...validPayload,
      operationId: "op-partial",
      level: "partial",
      activitiesRestricted: [" busca ", "guarda", "busca"],
    }),
    depsFor({db: dbPartial}),
  )) as JsonMap;
  const partialRecord = restrictionDoc(
    dbPartial,
    partial.restriction_id as string,
  );
  assert.deepStrictEqual(
    partialRecord.activities_restricted,
    ["busca", "guarda"],
    "atividades normalizadas e deduplicadas",
  );

  // attention sem atividades é válido.
  const dbAttention = dbWithDogAndEvidence();
  const attention = (await runHealthRestrictionIssue(
    mockRequest({
      ...validPayload,
      operationId: "op-attention",
      level: "attention",
    }),
    depsFor({db: dbAttention}),
  )) as JsonMap;
  assert.strictEqual(attention.was_no_op, false);

  // partial SEM atividades é rejeitado ANTES de persistir.
  const dbInvalid = dbWithDogAndEvidence();
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest({...validPayload, level: "partial"}),
        depsFor({db: dbInvalid}),
      ),
    "validation",
    "partial sem atividades",
  );
  assert.ok(
    !storeKeys(dbInvalid).some((k) => k.includes("operational_restrictions")),
    "nada persistido para partial inválido",
  );
}

// ── Compatibilidade com OP-AUTH e readiness (OBRIGATÓRIO) ────────────────────

/** Alimenta o documento produzido no parser real consumido pelos dois. */
function evidenceFor(record: JsonMap, restrictionId: string) {
  const doc: RawDoc = {id: restrictionId, data: record};
  return resolveRestrictionsEvidence({kind: "docs", docs: [doc]});
}

async function testOpAuthCompatibility() {
  const cases: Array<[string, JsonMap]> = [
    ["absolute", {...validPayload, operationId: "op-abs"}],
    [
      "partial",
      {
        ...validPayload,
        operationId: "op-par",
        level: "partial",
        activitiesRestricted: ["busca"],
      },
    ],
    ["attention", {...validPayload, operationId: "op-att", level: "attention"}],
  ];

  for (const [label, payload] of cases) {
    const db = dbWithDogAndEvidence();
    const res = (await runHealthRestrictionIssue(
      mockRequest(payload),
      depsFor({db}),
    )) as JsonMap;
    const restrictionId = res.restriction_id as string;
    const record = restrictionDoc(db, restrictionId);

    // 1. O parser canônico aceita o documento sem "unreliable".
    const evidence = evidenceFor(record, restrictionId);
    assert.strictEqual(
      evidence.kind,
      "restrictions",
      `${label}: parser não classifica como malformed/unavailable`,
    );
    if (evidence.kind !== "restrictions") return;
    assert.strictEqual(evidence.active.length, 1, `${label}: uma ativa`);
    const parsed = evidence.active[0];
    assert.strictEqual(parsed.level, label, `${label}: level reconhecido`);
    assert.strictEqual(parsed.id, restrictionId, `${label}: id preservado`);
    assert.ok(parsed.since instanceof Date, `${label}: since a partir de issued_at`);
    assert.strictEqual(parsed.category, "injury", `${label}: category lida`);

    // 2. O guard de OP-AUTH decide com base nesse mesmo documento.
    const decision = evaluateShiftRestrictionGuard({
      restrictions: {kind: "docs", docs: [{id: restrictionId, data: record}]},
      // Início genérico de turno não é atividade nomeada (taxonomy gap).
      requestedActivity: null,
      now: FIXED_NOW,
    });
    const expectedOutcome =
      label === "absolute" ?
        "blocked_absolute" :
        label === "partial" ?
          "allowed_with_restrictions" :
          "allowed";
    assert.strictEqual(
      decision.outcome,
      expectedOutcome,
      `${label}: OP-AUTH decide ${expectedOutcome}, recebeu ${decision.outcome}`,
    );
  }
}

async function testReadinessSourceNotUnavailable() {
  // Uma restrição emitida pelo writer nunca deve tornar a fonte indisponível.
  const db = dbWithDogAndEvidence();
  const res = (await runHealthRestrictionIssue(
    mockRequest(validPayload),
    depsFor({db}),
  )) as JsonMap;
  const restrictionId = res.restriction_id as string;
  const record = restrictionDoc(db, restrictionId);

  const evidence = evidenceFor(record, restrictionId);
  assert.notStrictEqual(
    evidence.kind,
    "unreliable",
    "fonte não fica unavailable",
  );

  // E o campo temporal canônico é legível mesmo sem `since` explícito.
  assert.ok(!("since" in record), "writer persiste issued_at, não since");
  if (evidence.kind === "restrictions") {
    assert.ok(
      evidence.active[0].since instanceof Date,
      "reader resolve since via issued_at",
    );
  }
}

// ── Auth ─────────────────────────────────────────────────────────────────────

async function testAuthGuards() {
  const db = dbWithDogAndEvidence();

  let unauth: string | undefined;
  try {
    await runHealthRestrictionIssue(
      mockRequest(validPayload, null),
      depsFor({db}),
    );
  } catch (err) {
    unauth = (err as {code?: string}).code;
  }
  assert.strictEqual(unauth, "unauthenticated", "sem auth");

  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db, allowIssue: false}),
      ),
    "permission-denied",
    "sem health.issue_restriction",
  );

  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db, dogAccess: false}),
      ),
    "permission-denied",
    "sem acesso ao K9",
  );

  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest({...validPayload, dogId: "dog-404"}),
        depsFor({db}),
      ),
    "not-found",
    "K9 inexistente",
  );

  // Admin resolve internal_role, não vira profissional.
  const dbAdmin = dbWithDogAndEvidence();
  await runHealthRestrictionIssue(
    mockRequest(validPayload),
    depsFor({db: dbAdmin, admin: true}),
  );
  const record = restrictionDoc(dbAdmin, idFor("dog-1", "op-1"));
  assert.strictEqual(
    (record.recorded_by as JsonMap).internal_role,
    "admin",
    "internal_role admin server-side",
  );
  assert.deepStrictEqual(
    (record.professional as JsonMap).name,
    "Dra. Ana Souza",
    "admin não substitui ProfessionalIdentity",
  );
}

// ── source_document ──────────────────────────────────────────────────────────

async function testSourceDocumentValidation() {
  // Documento inexistente.
  const dbMissing = createFakeDb({"dogs/dog-1": {name: "Bono"}});
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbMissing}),
      ),
    "integrity",
    "HealthDocument inexistente",
  );
  assert.ok(
    !storeKeys(dbMissing).some((k) => k.includes("operational_restrictions")),
    "nada persistido sem evidência",
  );

  // Documento de OUTRO dog não satisfaz (path é por dog).
  const dbOtherDog = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [`dogs/dog-2/health_documents/${DOC_ID}`]: {title: "De outro K9"},
  });
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbOtherDog}),
      ),
    "integrity",
    "documento de outro K9",
  );

  // Legado `documentos` (raiz) não satisfaz.
  const dbLegacy = createFakeDb({
    "dogs/dog-1": {name: "Bono"},
    [`documentos/${DOC_ID}`]: {caoId: "dog-1", tipo: "laudo"},
  });
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbLegacy}),
      ),
    "integrity",
    "legado documentos não é evidência canônica",
  );

  // Documento soft-deleted é rejeitado.
  const dbDeleted = dbWithDogAndEvidence({
    [`dogs/dog-1/health_documents/${DOC_ID}`]: {
      title: "Excluído",
      deleted_at: FIXED_NOW,
    },
  });
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbDeleted}),
      ),
    "integrity",
    "documento excluído",
  );

  // Ref malformado / com dados de Storage.
  const db = dbWithDogAndEvidence();
  for (const badRef of [
    {},
    {health_document_id: ""},
    {health_document_id: "a/b"},
    {health_document_id: DOC_ID, url: "https://x"},
    {health_document_id: DOC_ID, storage_path: "health_documents/dog-1/x"},
    {health_document_id: DOC_ID, mime_type: "application/pdf"},
  ]) {
    await expectReject(
      () =>
        runHealthRestrictionIssue(
          mockRequest({...validPayload, sourceDocument: badRef}),
          depsFor({db}),
        ),
      "validation",
      `ref inválido ${JSON.stringify(badRef)}`,
    );
  }
}

// ── Payload ownership ────────────────────────────────────────────────────────

async function testPayloadOwnership() {
  const db = dbWithDogAndEvidence();
  const injections: Array<[string, unknown]> = [
    ["status", "ended"],
    ["restrictionId", "or_forjado"],
    ["restriction_id", "or_forjado"],
    ["id", "or_forjado"],
    ["recorded_by", {uid: "evil"}],
    ["recordedBy", {uid: "evil"}],
    ["issued_at", "2020-01-01T00:00:00.000Z"],
    ["since", "2020-01-01T00:00:00.000Z"],
    ["schema_version", 99],
    ["revision", 5],
    ["actual_end", "2026-09-01T00:00:00.000Z"],
    ["ended_by", {uid: "x"}],
    ["end_professional", validProfessional],
    ["end_source_document", {health_document_id: DOC_ID}],
    ["end_reason", "liberado"],
    ["cancelled_at", "2026-09-01T00:00:00.000Z"],
    ["cancel_reason", "erro"],
    ["deleted_at", "2026-09-01T00:00:00.000Z"],
    ["is_overdue", true],
    ["actor", {uid: "x"}],
    ["source", "client"],
  ];
  for (const [key, value] of injections) {
    await expectReject(
      () =>
        runHealthRestrictionIssue(
          mockRequest({...validPayload, [key]: value}),
          depsFor({db}),
        ),
      "validation",
      `injeção rejeitada: ${key}`,
    );
  }

  // Level/category/description inválidos.
  for (const bad of ["critical", "ABSOLUTE", "absoluta", ""]) {
    await expectReject(
      () =>
        runHealthRestrictionIssue(
          mockRequest({...validPayload, level: bad}),
          depsFor({db}),
        ),
      "validation",
      `level inválido: ${bad}`,
    );
  }
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest({...validPayload, category: "lesao"}),
        depsFor({db}),
      ),
    "validation",
    "category legada",
  );
  for (const bad of ["", "   "]) {
    await expectReject(
      () =>
        runHealthRestrictionIssue(
          mockRequest({...validPayload, description: bad}),
          depsFor({db}),
        ),
      "validation",
      `description ${JSON.stringify(bad)}`,
    );
  }

  // Professional legado/incompleto.
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest({
          ...validPayload,
          professional: {vetName: "Dr X", professionalCrmv: "123"},
        }),
        depsFor({db}),
      ),
    "validation",
    "professional legado",
  );
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest({...validPayload, professional: undefined}),
        depsFor({db}),
      ),
    "validation",
    "professional ausente",
  );
}

// ── Idempotência ─────────────────────────────────────────────────────────────

async function testIdempotency() {
  const db = dbWithDogAndEvidence();
  const restrictionId = idFor("dog-1", "op-1");

  await runHealthRestrictionIssue(mockRequest(validPayload), depsFor({db}));
  const afterFirst = storeKeys(db);

  const replay = (await runHealthRestrictionIssue(
    mockRequest(validPayload),
    depsFor({db}),
  )) as JsonMap;
  assert.strictEqual(replay.was_no_op, true, "replay");
  assert.strictEqual(replay.restriction_id, restrictionId);
  assert.deepStrictEqual(storeKeys(db), afterFirst, "replay não escreve");

  // Mesma chave, cada divergência material → conflito.
  const divergences: Array<[string, JsonMap]> = [
    ["level", {level: "attention"}],
    ["description", {description: "Outra"}],
    ["category", {category: "chronic"}],
    ["activities", {level: "partial", activitiesRestricted: ["busca"]}],
    [
      "professional",
      {professional: {...validProfessional, registration_number: "SP-999"}},
    ],
    ["sourceDocument", {sourceDocument: {health_document_id: "hd_outro"}}],
    ["expectedEnd", {expectedEnd: "2026-12-01T00:00:00.000Z"}],
  ];
  for (const [label, patch] of divergences) {
    await expectReject(
      () =>
        runHealthRestrictionIssue(
          mockRequest({...validPayload, ...patch}),
          depsFor({db}),
        ),
      "idempotency-conflict",
      `divergência em ${label}`,
    );
  }
  assert.deepStrictEqual(storeKeys(db), afterFirst, "conflitos não escrevem");

  // Outro ator com a mesma chave → conflito.
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db, caller: actorB}),
      ),
    "idempotency-conflict",
    "actor divergente",
  );
}

async function testEntityWithoutReceiptFailsClosed() {
  const restrictionId = idFor("dog-1", "op-1");
  const path = `dogs/dog-1/operational_restrictions/${restrictionId}`;
  const db = dbWithDogAndEvidence({
    [path]: {
      status: "active",
      level: "absolute",
      category: "injury",
      description: "Origem desconhecida",
      schema_version: 1,
    },
  });

  await expectReject(
    () => runHealthRestrictionIssue(mockRequest(validPayload), depsFor({db})),
    "integrity",
    "restrição sem receipt falha fechado",
  );
  assert.strictEqual(
    (db._store.get(path) as JsonMap).description,
    "Origem desconhecida",
    "não sobrescreve autoridade de origem desconhecida",
  );
}

async function testMalformedReceiptFailsClosed() {
  const restrictionId = idFor("dog-1", "op-1");
  const receiptPath =
    `dogs/dog-1/operational_restrictions/${restrictionId}/operations/op-1`;

  const dbBroken = dbWithDogAndEvidence({
    [receiptPath]: {operation_id: "op-1"},
  });
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbBroken}),
      ),
    "integrity",
    "receipt malformado",
  );

  const dbWrongKind = dbWithDogAndEvidence({
    [receiptPath]: {
      kind: "outro_kind_v9",
      operation_id: "op-1",
      operation_type: "issue_restriction",
      actor_uid: actor.uid,
      fingerprint: "fp",
      result: {dogId: "dog-1", restrictionId},
    },
  });
  await expectReject(
    () =>
      runHealthRestrictionIssue(
        mockRequest(validPayload),
        depsFor({db: dbWrongKind}),
      ),
    "integrity",
    "receipt de kind incompatível",
  );
}

async function testConcurrency() {
  // Idênticas: uma cria, a outra é no-op.
  const db = dbWithDogAndEvidence();
  const deps = depsFor({db});
  const results = (await Promise.all([
    runHealthRestrictionIssue(mockRequest(validPayload), deps),
    runHealthRestrictionIssue(mockRequest(validPayload), deps),
  ])) as JsonMap[];
  assert.strictEqual(
    results.filter((r) => r.was_no_op === false).length,
    1,
    "exatamente uma criação",
  );
  assert.strictEqual(
    storeKeys(db).filter((k) => k.startsWith("auditLogs/")).length,
    1,
    "um audit lógico",
  );
  assert.strictEqual(
    storeKeys(db).filter((k) => k.includes("/operations/")).length,
    1,
    "um receipt",
  );

  // Divergentes: nunca cria duas restrições.
  const db2 = dbWithDogAndEvidence();
  const deps2 = depsFor({db: db2});
  await Promise.allSettled([
    runHealthRestrictionIssue(mockRequest(validPayload), deps2),
    runHealthRestrictionIssue(
      mockRequest({...validPayload, description: "Divergente"}),
      deps2,
    ),
  ]);
  assert.strictEqual(
    storeKeys(db2).filter(
      (k) => k.includes("operational_restrictions/") && !k.includes("/operations/"),
    ).length,
    1,
    "uma única restrição",
  );
}

async function testMultipleActiveRestrictions() {
  // Emitir uma segunda restrição NÃO encerra nem altera a primeira.
  const db = dbWithDogAndEvidence();
  const first = (await runHealthRestrictionIssue(
    mockRequest(validPayload),
    depsFor({db}),
  )) as JsonMap;
  const second = (await runHealthRestrictionIssue(
    mockRequest({
      ...validPayload,
      operationId: "op-2",
      level: "attention",
      description: "Segunda restrição",
    }),
    depsFor({db}),
  )) as JsonMap;

  assert.notStrictEqual(
    first.restriction_id,
    second.restriction_id,
    "ids distintos",
  );
  const firstRecord = restrictionDoc(db, first.restriction_id as string);
  assert.strictEqual(firstRecord.status, "active", "primeira segue ativa");
  assert.ok(!("actual_end" in firstRecord), "primeira não foi encerrada");
  assert.ok(!("ended_by" in firstRecord), "sem supersede implícito");

  // O parser reconhece as duas como ativas.
  const docs: RawDoc[] = [
    {id: first.restriction_id as string, data: firstRecord},
    {
      id: second.restriction_id as string,
      data: restrictionDoc(db, second.restriction_id as string),
    },
  ];
  const evidence = resolveRestrictionsEvidence({kind: "docs", docs});
  assert.strictEqual(evidence.kind, "restrictions");
  if (evidence.kind === "restrictions") {
    assert.strictEqual(evidence.active.length, 2, "duas ativas coexistem");
  }
}

/**
 * B1.R — prova end-to-end: writer → parser canônico → readiness evaluator.
 *
 * O elo que faltava. Os testes anteriores provaram que o documento do writer é
 * aceito pelo parser e decidido pelo OP-AUTH; este fecha o segundo consumidor,
 * mostrando o ESTADO FINAL de prontidão.
 *
 * Nada do contrato sob teste é mockado: o documento é o que o writer persiste,
 * `resolveRestrictionsEvidence` é o parser real e `evaluateReadiness` é a
 * policy real. Apenas as evidências Health periféricas (peso, vacina,
 * consulta, nutrição, exame) são um fixture completo e saudável, para que a
 * restrição seja a ÚNICA variável que move o veredito.
 */
function present<T>(value: T): EvidenceState<T> {
  return {kind: "present", value};
}

const READINESS_NOW = new Date("2026-08-15T18:00:00.000Z");
const DAY_MS = 24 * 60 * 60 * 1000;

/** Fixture saudável mínimo — não altera precedence, threshold nem policy. */
function healthyEvidence(
  activeRestrictions: ReadinessEvidence["activeRestrictions"],
): ReadinessEvidence {
  return {
    now: READINESS_NOW,
    activeRestrictions,
    latestWeightAt: present(new Date(READINESS_NOW.getTime() - 1 * DAY_MS)),
    vaccination: present({
      nextDueAt: new Date(READINESS_NOW.getTime() + 200 * DAY_MS),
    }),
    latestConsultationAt: present(
      new Date(READINESS_NOW.getTime() - 1 * DAY_MS),
    ),
    nutrition: present({activePlanCount: 1}),
    latestExamAt: present(new Date(READINESS_NOW.getTime() - 10 * DAY_MS)),
    config: DEFAULT_READINESS_CONFIG,
  };
}

async function testReadinessEndToEnd() {
  const cases: Array<[string, JsonMap, string]> = [
    [
      "absolute",
      {...validPayload, operationId: "op-e2e-abs"},
      "temporarily_unfit",
    ],
    [
      "partial",
      {
        ...validPayload,
        operationId: "op-e2e-par",
        level: "partial",
        activitiesRestricted: ["atividade operacional de teste"],
      },
      "fit_with_restrictions",
    ],
    [
      "attention",
      {...validPayload, operationId: "op-e2e-att", level: "attention"},
      "operational_attention",
    ],
  ];

  for (const [label, payload, expectedStatus] of cases) {
    // 1. WRITER — documento real que seria persistido.
    const db = dbWithDogAndEvidence();
    const res = (await runHealthRestrictionIssue(
      mockRequest(payload),
      depsFor({db}),
    )) as JsonMap;
    const restrictionId = res.restriction_id as string;
    const record = restrictionDoc(db, restrictionId);

    // 2. PARSER CANÔNICO — o mesmo consumido por readiness e OP-AUTH.
    const evidence = resolveRestrictionsEvidence({
      kind: "docs",
      docs: [{id: restrictionId, data: record}],
    });
    assert.notStrictEqual(
      evidence.kind,
      "unreliable",
      `${label}: fonte não pode ficar unreliable/unavailable`,
    );
    assert.strictEqual(
      evidence.kind,
      "restrictions",
      `${label}: parser aceita o documento do writer`,
    );
    if (evidence.kind !== "restrictions") return;
    assert.strictEqual(evidence.active.length, 1, `${label}: uma ativa`);

    const parsed = evidence.active[0];
    // `issued_at` do writer é aceito como `since` factual pelo consumidor.
    assert.ok(
      parsed.since instanceof Date,
      `${label}: issued_at compatível com since`,
    );
    assert.strictEqual(
      parsed.since.getTime(),
      FIXED_NOW.getTime(),
      `${label}: since preserva o instante de emissão`,
    );
    if (label === "partial") {
      assert.deepStrictEqual(
        [...parsed.activitiesRestricted],
        ["atividade operacional de teste"],
        "partial: activities_restricted chega intacto ao parser",
      );
    }

    // 3. READINESS EVALUATOR REAL — estado final.
    const evaluation = evaluateReadiness(healthyEvidence(evidence.active));
    assert.strictEqual(
      evaluation.outcome,
      "decided",
      `${label}: readiness decide (got ${JSON.stringify(evaluation)})`,
    );
    if (evaluation.outcome !== "decided") return;
    assert.strictEqual(
      evaluation.decision.readinessStatus,
      expectedStatus,
      `${label}: readiness final ${expectedStatus}, ` +
        `recebeu ${evaluation.decision.readinessStatus}`,
    );
  }
}

const tests: Array<[string, () => Promise<void>]> = [
  ["ISSUE sucesso e shape canônico", testIssueSuccess],
  ["ISSUE partial e attention", testPartialAndAttention],
  ["compatibilidade OP-AUTH (obrigatória)", testOpAuthCompatibility],
  ["compatibilidade readiness/evidence", testReadinessSourceNotUnavailable],
  ["readiness end-to-end (B1.R)", testReadinessEndToEnd],
  ["auth guards", testAuthGuards],
  ["source_document validação", testSourceDocumentValidation],
  ["payload ownership", testPayloadOwnership],
  ["idempotência e conflito", testIdempotency],
  ["restrição sem receipt falha fechado", testEntityWithoutReceiptFailsClosed],
  ["receipt malformado falha fechado", testMalformedReceiptFailsClosed],
  ["concorrência", testConcurrency],
  ["múltiplas restrições ativas coexistem", testMultipleActiveRestrictions],
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
