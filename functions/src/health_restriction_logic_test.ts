/**
 * Testes puros do writer de OperationalRestriction — ISSUE (B1).
 * npm run build && node lib/health_restriction_logic_test.js
 */
import * as assert from "assert";
import * as crypto from "crypto";

import {
  PROFESSIONAL_REGISTRATION_TYPES,
  RESTRICTION_CATEGORIES,
  CANCEL_METADATA_FIELDS,
  END_METADATA_FIELDS,
  RESTRICTION_CANCEL_KIND,
  RESTRICTION_CANCEL_OPERATION,
  RESTRICTION_END_KIND,
  RESTRICTION_END_OPERATION,
  RESTRICTION_ISSUE_KIND,
  RESTRICTION_LEVELS,
  RestrictionIssueIntent,
  assertCancelReceiptShape,
  assertDescription,
  assertEndReceiptShape,
  assertNoTerminalMetadata,
  assertReason,
  decideTerminalTransition,
  fingerprintCancelIntent,
  fingerprintEndIntent,
  matchCancelReceipt,
  matchEndReceipt,
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


// ── Lifecycle terminal: END / CANCEL (B2) ────────────────────────────────────

function testReason() {
  assert.strictEqual(assertReason("  Liberado  ", "end_reason"), "Liberado");
  expectLogicError(() => assertReason("", "end_reason"), "validation", "vazio");
  expectLogicError(
    () => assertReason("   ", "end_reason"),
    "validation",
    "whitespace-only",
  );
  expectLogicError(
    () => assertReason("\t\n ", "cancel_reason"),
    "validation",
    "tab/newline",
  );
  expectLogicError(
    () => assertReason(undefined, "cancel_reason"),
    "validation",
    "ausente",
  );
}

function testKindsAreDistinct() {
  // Load-bearing: END e CANCEL nunca podem replayar o receipt um do outro.
  assert.notStrictEqual(
    RESTRICTION_END_KIND,
    RESTRICTION_CANCEL_KIND,
    "kinds distintos",
  );
  assert.notStrictEqual(RESTRICTION_END_KIND, RESTRICTION_ISSUE_KIND);
  assert.notStrictEqual(RESTRICTION_CANCEL_KIND, RESTRICTION_ISSUE_KIND);
  assert.notStrictEqual(
    RESTRICTION_END_OPERATION,
    RESTRICTION_CANCEL_OPERATION,
  );
  assert.strictEqual(RESTRICTION_END_OPERATION, "release_restriction");
  assert.strictEqual(RESTRICTION_CANCEL_OPERATION, "cancel_restriction");
}

const endIntent = {
  dogId: "dog-1",
  restrictionId: "or_abc",
  endReason: "Liberado por reavaliação clínica",
  endProfessional: parseProfessionalIdentity(validProfessional),
  endSourceDocument: parseSourceDocumentRef({health_document_id: "hd_release"}),
};

function testEndFingerprint() {
  const a = fingerprintEndIntent(endIntent);
  assert.strictEqual(a, fingerprintEndIntent({...endIntent}), "estável");
  assert.ok(a.includes(RESTRICTION_END_KIND), "kind versionado");

  assert.notStrictEqual(
    a,
    fingerprintEndIntent({...endIntent, endReason: "Outro motivo"}),
    "endReason muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintEndIntent({
      ...endIntent,
      endSourceDocument: parseSourceDocumentRef({
        health_document_id: "hd_outro",
      }),
    }),
    "documento de liberação muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintEndIntent({
      ...endIntent,
      endProfessional: parseProfessionalIdentity({
        ...validProfessional,
        registration_number: "SP-99999",
      }),
    }),
    "profissional muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintEndIntent({...endIntent, restrictionId: "or_outro"}),
    "restrictionId muda fingerprint",
  );

  // Server-owned fora do fingerprint: incluí-los tornaria cada retry único.
  for (const forbidden of ["actual_end", "ended_by", "processed_at"]) {
    assert.ok(!a.includes(forbidden), `${forbidden} fora do fingerprint`);
  }
}

function testCancelFingerprint() {
  const base = {
    dogId: "dog-1",
    restrictionId: "or_abc",
    cancelReason: "Registro duplicado",
  };
  const a = fingerprintCancelIntent(base);
  assert.strictEqual(a, fingerprintCancelIntent({...base}), "estável");
  assert.ok(a.includes(RESTRICTION_CANCEL_KIND), "kind versionado");
  assert.notStrictEqual(
    a,
    fingerprintCancelIntent({...base, cancelReason: "K9 incorreto"}),
    "razão muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintCancelIntent({...base, restrictionId: "or_outro"}),
    "restrictionId muda fingerprint",
  );

  // CANCEL não carrega prova clínica nem timestamp.
  for (const forbidden of [
    "professional",
    "source_document",
    "cancelled_at",
    "cancelled_by",
  ]) {
    assert.ok(!a.includes(forbidden), `${forbidden} fora do fingerprint`);
  }

  // END e CANCEL da mesma restrição produzem fingerprints diferentes.
  assert.notStrictEqual(
    a,
    fingerprintEndIntent(endIntent),
    "END e CANCEL nunca colidem",
  );
}

function testTerminalReceiptShapes() {
  const endReceipt: JsonMap = {
    kind: RESTRICTION_END_KIND,
    operation_id: "op-1",
    operation_type: RESTRICTION_END_OPERATION,
    actor_uid: "uid-1",
    fingerprint: "fp",
    result: {dogId: "dog-1", restrictionId: "or_x"},
  };
  assertEndReceiptShape(endReceipt);

  const cancelReceipt: JsonMap = {
    kind: RESTRICTION_CANCEL_KIND,
    operation_id: "op-1",
    operation_type: RESTRICTION_CANCEL_OPERATION,
    actor_uid: "uid-1",
    fingerprint: "fp",
    result: {dogId: "dog-1", restrictionId: "or_x"},
  };
  assertCancelReceiptShape(cancelReceipt);

  // Colisão cruzada: cada comando rejeita o receipt do outro.
  expectLogicError(
    () => assertEndReceiptShape(cancelReceipt),
    "integrity",
    "END rejeita receipt de CANCEL",
  );
  expectLogicError(
    () => assertCancelReceiptShape(endReceipt),
    "integrity",
    "CANCEL rejeita receipt de END",
  );
  // E ambos rejeitam receipt de ISSUE.
  const issueReceipt: JsonMap = {
    kind: RESTRICTION_ISSUE_KIND,
    operation_id: "op-1",
    operation_type: "issue_restriction",
    actor_uid: "uid-1",
    fingerprint: "fp",
    result: {},
  };
  expectLogicError(
    () => assertEndReceiptShape(issueReceipt),
    "integrity",
    "END rejeita receipt de ISSUE",
  );
  expectLogicError(
    () => assertCancelReceiptShape(issueReceipt),
    "integrity",
    "CANCEL rejeita receipt de ISSUE",
  );

  for (const key of Object.keys(endReceipt)) {
    const broken = {...endReceipt};
    delete broken[key];
    expectLogicError(
      () => assertEndReceiptShape(broken),
      "integrity",
      `receipt END sem ${key}`,
    );
  }

  // Match por operationType.
  const base = {
    receiptExists: true,
    storedActorUid: "uid-1",
    storedFingerprint: "fp",
    actorUid: "uid-1",
    fingerprint: "fp",
  };
  assert.strictEqual(
    matchEndReceipt({...base, storedOperationType: RESTRICTION_END_OPERATION}),
    "replay",
  );
  assert.strictEqual(
    matchEndReceipt({
      ...base,
      storedOperationType: RESTRICTION_CANCEL_OPERATION,
    }),
    "idempotency-conflict",
    "operationType de CANCEL não é replay de END",
  );
  assert.strictEqual(
    matchCancelReceipt({
      ...base,
      storedOperationType: RESTRICTION_CANCEL_OPERATION,
    }),
    "replay",
  );
  assert.strictEqual(
    matchCancelReceipt({...base, receiptExists: false}),
    "missing",
  );
}

function testDecideTerminalTransition() {
  // Receipt tem prioridade sobre status: retry legítimo da MESMA operação não
  // pode receber conflito espúrio só porque já está terminal.
  assert.deepStrictEqual(
    decideTerminalTransition({
      receiptMatch: "replay",
      restrictionExists: true,
      currentStatus: "ended",
    }),
    {kind: "replay"},
    "replay mesmo já terminal",
  );

  assert.deepStrictEqual(
    decideTerminalTransition({
      receiptMatch: "missing",
      restrictionExists: true,
      currentStatus: "active",
    }),
    {kind: "transition"},
    "active transiciona",
  );

  const conflictFp = decideTerminalTransition({
    receiptMatch: "idempotency-conflict",
    restrictionExists: true,
    currentStatus: "active",
  });
  assert.strictEqual((conflictFp as {code: string}).code, "idempotency-conflict");

  // Terminal por OUTRA operação → conflict, nunca reabre.
  for (const status of ["ended", "cancelled"]) {
    const terminal = decideTerminalTransition({
      receiptMatch: "missing",
      restrictionExists: true,
      currentStatus: status,
    });
    assert.strictEqual(terminal.kind, "error", `${status} não transiciona`);
    assert.strictEqual(
      (terminal as {code: string}).code,
      "conflict",
      `${status} → conflict`,
    );
  }

  const missing = decideTerminalTransition({
    receiptMatch: "missing",
    restrictionExists: false,
    currentStatus: undefined,
  });
  assert.strictEqual((missing as {code: string}).code, "not-found");

  // Status ausente ou desconhecido é fail-closed, nunca "assume active".
  for (const bad of [undefined, "", "   ", "paused", "draft"]) {
    const invalid = decideTerminalTransition({
      receiptMatch: "missing",
      restrictionExists: true,
      currentStatus: bad,
    });
    assert.strictEqual(invalid.kind, "error", `status ${bad} falha`);
    assert.strictEqual(
      (invalid as {code: string}).code,
      "integrity",
      `status ${bad} → integrity`,
    );
  }
}

function testTerminalExclusivity() {
  // Uma restrição active do B1 não carrega nenhum dos dois conjuntos.
  const active: JsonMap = {
    status: "active",
    level: "absolute",
    description: "Lesão",
  };
  assertNoTerminalMetadata(active, END_METADATA_FIELDS, "encerramento");
  assertNoTerminalMetadata(active, CANCEL_METADATA_FIELDS, "cancelamento");

  // Agregado com metadata de END não pode receber CANCEL.
  for (const field of END_METADATA_FIELDS) {
    expectLogicError(
      () =>
        assertNoTerminalMetadata(
          {...active, [field]: "x"},
          END_METADATA_FIELDS,
          "encerramento",
        ),
      "integrity",
      `metadata END presente (${field})`,
    );
  }
  for (const field of CANCEL_METADATA_FIELDS) {
    expectLogicError(
      () =>
        assertNoTerminalMetadata(
          {...active, [field]: "x"},
          CANCEL_METADATA_FIELDS,
          "cancelamento",
        ),
      "integrity",
      `metadata CANCEL presente (${field})`,
    );
  }

  // `null` explícito não conta como presente (campo nunca escrito).
  assertNoTerminalMetadata(
    {...active, actual_end: null, ended_by: null},
    END_METADATA_FIELDS,
    "encerramento",
  );

  assert.strictEqual(END_METADATA_FIELDS.length, 5, "cinco campos de END");
  assert.strictEqual(CANCEL_METADATA_FIELDS.length, 3, "três campos de CANCEL");
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
  ["reason obrigatória (END/CANCEL)", testReason],
  ["kinds END/CANCEL distintos", testKindsAreDistinct],
  ["fingerprint END", testEndFingerprint],
  ["fingerprint CANCEL", testCancelFingerprint],
  ["receipt shapes terminais", testTerminalReceiptShapes],
  ["decisão de transição terminal", testDecideTerminalTransition],
  ["exclusividade de metadata terminal", testTerminalExclusivity],
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
