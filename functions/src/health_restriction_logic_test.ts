/**
 * Testes puros do writer de OperationalRestriction — ISSUE (B1).
 * npm run build && node lib/health_restriction_logic_test.js
 */
import * as assert from "assert";
import * as crypto from "crypto";

import {
  PROFESSIONAL_REGISTRATION_TYPES,
  RESTRICTION_CATEGORIES,
  RESTRICTION_ISSUE_KIND,
  RESTRICTION_LEVELS,
  RestrictionIssueIntent,
  assertDescription,
  assertPartialInvariant,
  assertReceiptShape,
  canonicalHealthDocumentPath,
  canonicalRestrictionPath,
  createIdempotencyMaterial,
  decideIssue,
  deterministicRestrictionId,
  fingerprintIssueIntent,
  matchIssueReceipt,
  normalizeActivities,
  normalizeOperationId,
  optionalInstant,
  parseCategory,
  parseLevel,
  parseProfessionalIdentity,
  parseSourceDocumentRef,
  recordedByPayload,
} from "./health_restriction_logic";

type JsonMap = Record<string, unknown>;

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

function idFor(dogId: string, operationId: string): string {
  return deterministicRestrictionId(
    sha256Hex(createIdempotencyMaterial(dogId, operationId)),
  );
}

function expectLogicError(fn: () => unknown, code: string, label: string) {
  try {
    fn();
  } catch (err) {
    const actual = (err as {appCode?: string}).appCode;
    assert.strictEqual(actual, code, `${label}: appCode ${actual} != ${code}`);
    return;
  }
  assert.fail(`${label}: esperava erro ${code}, não lançou`);
}

const validProfessional = {
  name: "Dra. Ana Souza",
  registration_type: "CRMV",
  registration_number: "SP-12345",
  clinic: "Clínica Central",
};

const validRef = {health_document_id: "hd_abc123"};

const baseIntent: RestrictionIssueIntent = {
  dogId: "dog-1",
  level: "absolute",
  category: "injury",
  description: "Lesão em membro anterior",
  activitiesRestricted: [],
  expectedEndIso: null,
  professional: parseProfessionalIdentity(validProfessional),
  sourceDocument: parseSourceDocumentRef(validRef),
};

// ── Identidade determinística ────────────────────────────────────────────────

function testDeterministicIdentity() {
  assert.strictEqual(
    idFor("dog-1", "op-1"),
    idFor("dog-1", "op-1"),
    "mesmos inputs → mesmo id",
  );
  assert.notStrictEqual(
    idFor("dog-1", "op-1"),
    idFor("dog-1", "op-2"),
    "operationId diferente → id diferente",
  );
  assert.notStrictEqual(
    idFor("dog-1", "op-1"),
    idFor("dog-2", "op-1"),
    "dogId diferente → id diferente",
  );

  const id = idFor("dog-1", "op-1");
  assert.ok(id.startsWith("or_"), "prefixo canônico or_");
  assert.strictEqual(id.length, 31, "or_ + 28 hex");
  assert.ok(
    createIdempotencyMaterial("dog-1", "op-1").startsWith(
      RESTRICTION_ISSUE_KIND,
    ),
    "material versionado por kind",
  );

  assert.strictEqual(
    canonicalRestrictionPath("dog-1", id),
    `dogs/dog-1/operational_restrictions/${id}`,
  );
  assert.strictEqual(
    canonicalHealthDocumentPath("dog-1", "hd_x"),
    "dogs/dog-1/health_documents/hd_x",
  );
}

// ── level / category ─────────────────────────────────────────────────────────

function testLevelAndCategory() {
  for (const level of RESTRICTION_LEVELS) {
    assert.strictEqual(parseLevel(level), level, `round-trip ${level}`);
  }
  assert.strictEqual(RESTRICTION_LEVELS.length, 3, "três levels canônicos");
  expectLogicError(() => parseLevel("critical"), "validation", "level unknown");
  expectLogicError(() => parseLevel(""), "validation", "level vazio");
  expectLogicError(() => parseLevel(undefined), "validation", "level ausente");
  // Sem alias legado nem fallback.
  expectLogicError(() => parseLevel("ABSOLUTE"), "validation", "case-sensitive");
  expectLogicError(() => parseLevel("absoluta"), "validation", "pt-br");

  for (const category of RESTRICTION_CATEGORIES) {
    assert.strictEqual(parseCategory(category), category, category);
  }
  assert.strictEqual(RESTRICTION_CATEGORIES.length, 8, "oito categorias");
  expectLogicError(
    () => parseCategory("lesao"),
    "validation",
    "category legado/pt",
  );
  expectLogicError(
    () => parseCategory("desconhecida"),
    "validation",
    "category unknown não cai em other",
  );
  // O reader tolera ausência com default `other`; o writer não.
  expectLogicError(
    () => parseCategory(undefined),
    "validation",
    "category ausente rejeitada no writer",
  );
  assert.strictEqual(parseCategory("other"), "other", "other literal");
}

// ── description / activities / partial ───────────────────────────────────────

function testDescriptionAndActivities() {
  assert.strictEqual(assertDescription("  Lesão  "), "Lesão", "trim");
  expectLogicError(() => assertDescription(""), "validation", "vazia");
  expectLogicError(() => assertDescription("   "), "validation", "whitespace");
  expectLogicError(() => assertDescription(undefined), "validation", "ausente");

  assert.deepStrictEqual(normalizeActivities(undefined), [], "ausente → []");
  assert.deepStrictEqual(normalizeActivities(null), [], "null → []");
  assert.deepStrictEqual(
    normalizeActivities([" busca ", "guarda", "", "  ", "busca"]),
    ["busca", "guarda"],
    "trim + descarta vazios + dedup preservando ordem",
  );
  expectLogicError(
    () => normalizeActivities("busca"),
    "validation",
    "não-lista",
  );
  expectLogicError(
    () => normalizeActivities([{a: 1}]),
    "validation",
    "item não textual",
  );

  // Invariante load-bearing: partial exige atividades.
  assertPartialInvariant("absolute", []);
  assertPartialInvariant("attention", []);
  assertPartialInvariant("partial", ["busca"]);
  expectLogicError(
    () => assertPartialInvariant("partial", []),
    "validation",
    "partial sem atividades",
  );
}

// ── expected_end ─────────────────────────────────────────────────────────────

function testExpectedEnd() {
  assert.strictEqual(
    optionalInstant(undefined, "expected_end"),
    undefined,
    "ausente",
  );
  assert.strictEqual(optionalInstant("", "expected_end"), undefined, "vazio");
  // Futuro é legítimo: é expectativa de reavaliação, não encerramento.
  const future = new Date(Date.now() + 30 * 24 * 3600 * 1000);
  assert.ok(
    optionalInstant(future.toISOString(), "expected_end") instanceof Date,
    "futuro aceito",
  );
  // Passado também: sinaliza vencida/aguardando reavaliação, não encerra.
  const past = new Date(Date.now() - 30 * 24 * 3600 * 1000);
  assert.ok(
    optionalInstant(past.toISOString(), "expected_end") instanceof Date,
    "passado aceito (não auto-encerra)",
  );
  expectLogicError(
    () => optionalInstant("não-data", "expected_end"),
    "validation",
    "inválido",
  );
}

// ── ProfessionalIdentity ─────────────────────────────────────────────────────

function testProfessionalIdentity() {
  const parsed = parseProfessionalIdentity({
    ...validProfessional,
    name: "  Dra. Ana Souza  ",
    specialty: " Ortopedia ",
  });
  assert.strictEqual(parsed.name, "Dra. Ana Souza", "name trimado");
  assert.strictEqual(parsed.specialty, "Ortopedia", "specialty trimada");
  assert.strictEqual(parsed.registration_type, "CRMV");

  assert.strictEqual(
    parseProfessionalIdentity(validProfessional).specialty,
    null,
    "specialty opcional → null",
  );

  for (const type of PROFESSIONAL_REGISTRATION_TYPES) {
    assert.strictEqual(
      parseProfessionalIdentity({...validProfessional, registration_type: type})
        .registration_type,
      type,
      `registration_type ${type}`,
    );
  }

  // Obrigatoriedade — professional NÃO é opcional na emissão.
  expectLogicError(
    () => parseProfessionalIdentity(undefined),
    "validation",
    "professional ausente",
  );
  expectLogicError(
    () => parseProfessionalIdentity({}),
    "validation",
    "professional vazio",
  );
  for (const field of ["name", "registration_number", "clinic"]) {
    expectLogicError(
      () => parseProfessionalIdentity({...validProfessional, [field]: ""}),
      "validation",
      `${field} vazio`,
    );
    expectLogicError(
      () => parseProfessionalIdentity({...validProfessional, [field]: "   "}),
      "validation",
      `${field} whitespace`,
    );
  }
  expectLogicError(
    () =>
      parseProfessionalIdentity({
        ...validProfessional,
        registration_type: "CRV",
      }),
    "validation",
    "registration_type unknown",
  );

  // Vocabulário legado explicitamente rejeitado (B0-A.2 E4).
  for (const legacy of [
    "vetName",
    "professionalCrmv",
    "professionalClinic",
    "register_number",
    "register_state",
  ]) {
    expectLogicError(
      () => parseProfessionalIdentity({...validProfessional, [legacy]: "x"}),
      "validation",
      `legado ${legacy} rejeitado`,
    );
  }
}

// ── source_document ─────────────────────────────────────────────────────────

function testSourceDocumentRef() {
  const ref = parseSourceDocumentRef({
    health_document_id: " hd_abc ",
    description: " Laudo ",
  });
  assert.strictEqual(ref.health_document_id, "hd_abc", "id trimado");
  assert.strictEqual(ref.description, "Laudo");
  assert.strictEqual(
    parseSourceDocumentRef(validRef).description,
    null,
    "description opcional",
  );
  assert.strictEqual(
    parseSourceDocumentRef({healthDocumentId: "hd_x"}).health_document_id,
    "hd_x",
    "alias camelCase aceito",
  );

  expectLogicError(
    () => parseSourceDocumentRef(undefined),
    "validation",
    "ref ausente",
  );
  expectLogicError(() => parseSourceDocumentRef({}), "validation", "id ausente");
  expectLogicError(
    () => parseSourceDocumentRef({health_document_id: "a/b"}),
    "validation",
    "id com slash",
  );

  // Storage NUNCA entra na referência: o B0 encapsulou isso.
  for (const forbidden of [
    "url",
    "storage_path",
    "storagePath",
    "storage_url",
    "download_url",
    "mime_type",
    "generation",
    "md5Hash",
  ]) {
    expectLogicError(
      () => parseSourceDocumentRef({...validRef, [forbidden]: "x"}),
      "validation",
      `${forbidden} rejeitado no ref`,
    );
  }
}

// ── Fingerprint ──────────────────────────────────────────────────────────────

function testFingerprint() {
  const a = fingerprintIssueIntent(baseIntent);
  assert.strictEqual(a, fingerprintIssueIntent({...baseIntent}), "estável");
  assert.ok(a.includes(RESTRICTION_ISSUE_KIND), "kind versionado");

  // Cada campo material muda o fingerprint.
  const variants: Array<[string, Partial<RestrictionIssueIntent>]> = [
    ["level", {level: "attention"}],
    ["category", {category: "chronic"}],
    ["description", {description: "Outra descrição"}],
    ["activities", {level: "partial", activitiesRestricted: ["busca"]}],
    ["expectedEnd", {expectedEndIso: "2026-12-01T00:00:00.000Z"}],
    [
      "professional",
      {
        professional: parseProfessionalIdentity({
          ...validProfessional,
          registration_number: "SP-99999",
        }),
      },
    ],
    [
      "sourceDocument",
      {sourceDocument: parseSourceDocumentRef({health_document_id: "hd_zzz"})},
    ],
  ];
  for (const [label, patch] of variants) {
    assert.notStrictEqual(
      a,
      fingerprintIssueIntent({...baseIntent, ...patch}),
      `${label} muda fingerprint`,
    );
  }

  // Server-owned fora do fingerprint.
  for (const forbidden of ["recorded_by", "issued_at", "restrictionId"]) {
    assert.ok(!a.includes(forbidden), `${forbidden} fora do fingerprint`);
  }
}

// ── Receipt e decisão ────────────────────────────────────────────────────────

function testReceiptAndDecision() {
  const fp = fingerprintIssueIntent(baseIntent);
  const base = {
    receiptExists: true,
    storedActorUid: "uid-1",
    storedOperationType: "issue_restriction",
    storedFingerprint: fp,
    actorUid: "uid-1",
    fingerprint: fp,
  };
  assert.strictEqual(matchIssueReceipt(base), "replay");
  assert.strictEqual(
    matchIssueReceipt({...base, receiptExists: false}),
    "missing",
  );
  assert.strictEqual(
    matchIssueReceipt({...base, storedActorUid: "outro"}),
    "idempotency-conflict",
    "actor divergente",
  );
  assert.strictEqual(
    matchIssueReceipt({...base, storedFingerprint: "x"}),
    "idempotency-conflict",
  );
  assert.strictEqual(
    matchIssueReceipt({...base, storedOperationType: "outra"}),
    "idempotency-conflict",
  );
  assert.strictEqual(
    matchIssueReceipt({...base, storedFingerprint: undefined}),
    "idempotency-conflict",
    "campo ausente é conflito, não replay",
  );

  const valid: JsonMap = {
    kind: RESTRICTION_ISSUE_KIND,
    operation_id: "op-1",
    operation_type: "issue_restriction",
    actor_uid: "uid-1",
    fingerprint: fp,
    result: {dogId: "dog-1", restrictionId: "or_x"},
  };
  assertReceiptShape(valid);
  for (const key of Object.keys(valid)) {
    const broken = {...valid};
    delete broken[key];
    expectLogicError(
      () => assertReceiptShape(broken),
      "integrity",
      `receipt sem ${key}`,
    );
  }
  expectLogicError(
    () => assertReceiptShape({...valid, kind: "outro_v9"}),
    "integrity",
    "kind incompatível",
  );

  assert.deepStrictEqual(
    decideIssue({receiptMatch: "missing", restrictionExists: false}),
    {kind: "create"},
  );
  assert.deepStrictEqual(
    decideIssue({receiptMatch: "replay", restrictionExists: true}),
    {kind: "replay"},
  );
  const conflict = decideIssue({
    receiptMatch: "idempotency-conflict",
    restrictionExists: true,
  });
  assert.strictEqual((conflict as {code: string}).code, "idempotency-conflict");

  // Restrição sem receipt é estado impossível: fail-closed, nunca replay.
  const invariant = decideIssue({
    receiptMatch: "missing",
    restrictionExists: true,
  });
  assert.strictEqual(invariant.kind, "error");
  assert.strictEqual((invariant as {code: string}).code, "integrity");
}

function testOperationIdAndRecordedBy() {
  assert.strictEqual(normalizeOperationId(" op-1 "), "op-1");
  expectLogicError(() => normalizeOperationId(""), "validation", "vazio");
  expectLogicError(() => normalizeOperationId("a/b"), "validation", "slash");
  expectLogicError(() => normalizeOperationId(".."), "validation", "dotdot");

  const caller = {uid: "uid-1", name: "Operador", ra: "691755"};
  assert.deepStrictEqual(recordedByPayload(caller, false), {
    uid: "uid-1",
    name: "Operador",
    internal_role: "condutor",
  });
  assert.deepStrictEqual(recordedByPayload(caller, true), {
    uid: "uid-1",
    name: "Operador",
    internal_role: "admin",
  });
  // RecordedBy nunca carrega dado profissional externo.
  const payload = recordedByPayload(caller, false);
  assert.ok(!("registration_number" in payload), "sem registro profissional");
  assert.ok(!("clinic" in payload), "sem clínica");
}

const tests: Array<[string, () => void]> = [
  ["identidade determinística", testDeterministicIdentity],
  ["level e category estritos", testLevelAndCategory],
  ["description e activities", testDescriptionAndActivities],
  ["expected_end", testExpectedEnd],
  ["ProfessionalIdentity", testProfessionalIdentity],
  ["source_document ref", testSourceDocumentRef],
  ["fingerprint", testFingerprint],
  ["receipt e decisão", testReceiptAndDecision],
  ["operationId e recorded_by", testOperationIdAndRecordedBy],
];

let failures = 0;
for (const [name, fn] of tests) {
  try {
    fn();
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
