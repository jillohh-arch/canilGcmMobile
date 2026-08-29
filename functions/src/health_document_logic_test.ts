/**
 * Testes puros do HealthDocument logic (B0-B).
 * npm run build && node lib/health_document_logic_test.js
 */
import * as assert from "assert";
import * as crypto from "crypto";

import {
  HEALTH_DOCUMENT_CREATE_KIND,
  HEALTH_DOCUMENT_TYPES,
  MAX_DOCUMENT_BYTES,
  assertDocumentDates,
  assertDogId,
  assertReceiptShape,
  assertSealIntentMatches,
  assertSealedObjectMatches,
  assertTitle,
  canonicalDocumentPath,
  canonicalStoragePath,
  createIdempotencyMaterial,
  decideFinalize,
  deterministicDocumentId,
  fingerprintCreateDocumentIntent,
  healthDocumentRef,
  isAllowedContentType,
  matchDocumentReceipt,
  normalizeOperationId,
  optionalInstant,
  optionalReferenceId,
  parseHealthDocumentType,
  HEALTH_DOCUMENT_SEAL_VERSION,
  SEAL_FINGERPRINT_KEY,
  SEAL_VERSION_KEY,
  recordedByPayload,
  sealFingerprintMaterial,
  sealMetadata,
  stagingStoragePath,
  verifyStorageObject,
} from "./health_document_logic";

type JsonMap = Record<string, unknown>;

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

function idFor(dogId: string, operationId: string): string {
  return deterministicDocumentId(
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

const baseIntent = {
  dogId: "dog-1",
  documentType: "certificate" as const,
  title: "Atestado veterinário",
  description: null,
  issuer: null,
  issueDateIso: null,
  expiryDateIso: null,
  caseId: null,
  eventId: null,
  examId: null,
};

// ── Identidade determinística ────────────────────────────────────────────────

function testDeterministicIdentity() {
  const a = idFor("dog-1", "op-1");
  const b = idFor("dog-1", "op-1");
  assert.strictEqual(a, b, "mesmos inputs → mesmo id");

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

  assert.ok(a.startsWith("hd_"), "prefixo canônico hd_");
  assert.strictEqual(a.length, 31, "hd_ + 28 hex");

  // Identidade não depende de relógio nem de payload de negócio.
  assert.ok(
    createIdempotencyMaterial("dog-1", "op-1").startsWith(
      HEALTH_DOCUMENT_CREATE_KIND,
    ),
    "material versionado por kind",
  );

  assert.strictEqual(
    canonicalStoragePath("dog-1", a),
    `health_documents/dog-1/${a}`,
    "storage path canônico sem extensão",
  );
  assert.strictEqual(
    canonicalDocumentPath("dog-1", a),
    `dogs/dog-1/health_documents/${a}`,
    "firestore path distinto do storage path",
  );
  assert.ok(
    !canonicalStoragePath("dog-1", a).includes("."),
    "storage path não carrega extensão",
  );
}

// ── operationId / dogId ──────────────────────────────────────────────────────

function testOperationId() {
  assert.strictEqual(normalizeOperationId(" op-1 "), "op-1", "trim");
  expectLogicError(() => normalizeOperationId(""), "validation", "vazio");
  expectLogicError(() => normalizeOperationId(undefined), "validation", "ausente");
  expectLogicError(() => normalizeOperationId("a/b"), "validation", "slash");
  expectLogicError(() => normalizeOperationId("a\\b"), "validation", "backslash");
  expectLogicError(() => normalizeOperationId(".."), "validation", "dotdot");
  expectLogicError(() => normalizeOperationId("."), "validation", "dot");
  expectLogicError(() => normalizeOperationId("-x"), "validation", "inicia com -");
  expectLogicError(
    () => normalizeOperationId("a".repeat(129)),
    "validation",
    "excede tamanho",
  );

  assert.strictEqual(assertDogId(" dog-1 "), "dog-1", "dogId trim");
  expectLogicError(() => assertDogId(""), "validation", "dogId vazio");
  expectLogicError(() => assertDogId("a/b"), "validation", "dogId com slash");
  expectLogicError(() => assertDogId(".."), "validation", "dogId dotdot");
}

// ── document_type: parse estrito ─────────────────────────────────────────────

function testDocumentType() {
  for (const value of HEALTH_DOCUMENT_TYPES) {
    assert.strictEqual(
      parseHealthDocumentType(value),
      value,
      `round-trip ${value}`,
    );
  }
  assert.strictEqual(
    HEALTH_DOCUMENT_TYPES.length,
    9,
    "exatamente nove tipos canônicos",
  );

  // Vocabulário legado NÃO é mapeado.
  for (const legacy of ["laudo", "certificado", "documento", "exame"]) {
    expectLogicError(
      () => parseHealthDocumentType(legacy),
      "validation",
      `legado ${legacy} rejeitado`,
    );
  }

  // Sem fallback silencioso para `other`.
  expectLogicError(
    () => parseHealthDocumentType("qualquer_coisa"),
    "validation",
    "desconhecido não cai em other",
  );
  expectLogicError(
    () => parseHealthDocumentType(""),
    "validation",
    "vazio rejeitado",
  );
  assert.strictEqual(
    parseHealthDocumentType("other"),
    "other",
    "other só a partir do literal other",
  );

  // Tipos inexistentes por decisão B0-A.2.
  expectLogicError(
    () => parseHealthDocumentType("restriction_evidence"),
    "validation",
    "restriction_evidence não existe",
  );
  expectLogicError(
    () => parseHealthDocumentType("vet_release"),
    "validation",
    "vet_release não existe",
  );
}

// ── title / campos opcionais ─────────────────────────────────────────────────

function testTitleAndOptionals() {
  assert.strictEqual(assertTitle(" Laudo "), "Laudo", "title trimado");
  expectLogicError(() => assertTitle(""), "validation", "title vazio");
  // Defeito corrigido: título só de espaços não pode passar.
  expectLogicError(() => assertTitle("   "), "validation", "title whitespace");
  expectLogicError(() => assertTitle("\t\n "), "validation", "title tab/newline");
  expectLogicError(() => assertTitle(undefined), "validation", "title ausente");

  assert.strictEqual(
    optionalReferenceId(undefined, "case_id"),
    undefined,
    "ref ausente → undefined",
  );
  expectLogicError(
    () => optionalReferenceId("a/b", "case_id"),
    "validation",
    "ref com slash",
  );

  assert.strictEqual(
    optionalInstant(undefined, "issue_date"),
    undefined,
    "instante ausente",
  );
  expectLogicError(
    () => optionalInstant("não-data", "issue_date"),
    "validation",
    "instante inválido",
  );

  // expiry_date no futuro é legítimo e não deve ser rejeitado.
  const future = new Date(Date.now() + 365 * 24 * 3600 * 1000);
  assert.ok(
    optionalInstant(future.toISOString(), "expiry_date") instanceof Date,
    "expiry_date futuro aceito",
  );

  assertDocumentDates(new Date("2026-01-01"), new Date("2027-01-01"));
  expectLogicError(
    () => assertDocumentDates(new Date("2027-01-01"), new Date("2026-01-01")),
    "validation",
    "expiry antes de issue",
  );
}

// ── Fingerprint ──────────────────────────────────────────────────────────────

function testFingerprint() {
  const a = fingerprintCreateDocumentIntent(baseIntent);
  const b = fingerprintCreateDocumentIntent({...baseIntent});
  assert.strictEqual(a, b, "estável para mesma intenção");

  assert.notStrictEqual(
    a,
    fingerprintCreateDocumentIntent({...baseIntent, title: "Outro"}),
    "title muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintCreateDocumentIntent({...baseIntent, documentType: "report"}),
    "documentType muda fingerprint",
  );
  assert.notStrictEqual(
    a,
    fingerprintCreateDocumentIntent({...baseIntent, caseId: "case-1"}),
    "caseId muda fingerprint",
  );

  assert.ok(a.includes(HEALTH_DOCUMENT_CREATE_KIND), "kind versionado incluso");

  // Campos server-owned não participam: não há como o cliente influenciá-los.
  assert.ok(!a.includes("storage_path"), "storage_path fora do fingerprint");
  assert.ok(!a.includes("recorded_by"), "recorded_by fora do fingerprint");
  assert.ok(!a.includes("uploaded_at"), "uploaded_at fora do fingerprint");
  assert.ok(!a.includes("mime"), "mime_type fora do fingerprint");
}

// ── Receipt match ────────────────────────────────────────────────────────────

function testReceiptMatch() {
  const fp = fingerprintCreateDocumentIntent(baseIntent);
  const base = {
    receiptExists: true,
    storedActorUid: "uid-1",
    storedOperationType: "create_document",
    storedFingerprint: fp,
    actorUid: "uid-1",
    fingerprint: fp,
  };

  assert.strictEqual(matchDocumentReceipt(base), "replay", "match exato");
  assert.strictEqual(
    matchDocumentReceipt({...base, receiptExists: false}),
    "missing",
    "receipt ausente",
  );
  assert.strictEqual(
    matchDocumentReceipt({...base, storedActorUid: "outro"}),
    "idempotency-conflict",
    "actor divergente",
  );
  assert.strictEqual(
    matchDocumentReceipt({...base, storedFingerprint: "outro"}),
    "idempotency-conflict",
    "fingerprint divergente",
  );
  assert.strictEqual(
    matchDocumentReceipt({...base, storedOperationType: "outra_op"}),
    "idempotency-conflict",
    "operation_type divergente",
  );
  // Campo ausente nunca iguala string → fail-closed.
  assert.strictEqual(
    matchDocumentReceipt({...base, storedFingerprint: undefined}),
    "idempotency-conflict",
    "fingerprint ausente é conflito, não replay",
  );
}

function testReceiptShape() {
  const valid: JsonMap = {
    kind: HEALTH_DOCUMENT_CREATE_KIND,
    operation_id: "op-1",
    operation_type: "create_document",
    actor_uid: "uid-1",
    fingerprint: "fp",
    result: {dogId: "dog-1", documentId: "hd_x"},
  };
  assertReceiptShape(valid);

  for (const key of Object.keys(valid)) {
    const broken = {...valid};
    delete broken[key];
    expectLogicError(
      () => assertReceiptShape(broken),
      "integrity",
      `receipt sem ${key} é integrity`,
    );
  }

  expectLogicError(
    () => assertReceiptShape({...valid, kind: "outro_kind_v9"}),
    "integrity",
    "kind/version incompatível",
  );
  expectLogicError(
    () => assertReceiptShape({...valid, operation_type: "outra"}),
    "integrity",
    "operation_type incompatível",
  );
}

// ── decideFinalize: o gate que substitui fingerprint no agregado ─────────────

function testDecideFinalize() {
  assert.deepStrictEqual(
    decideFinalize({receiptMatch: "missing", documentExists: false}),
    {kind: "create"},
    "sem receipt e sem documento → create",
  );
  assert.deepStrictEqual(
    decideFinalize({receiptMatch: "replay", documentExists: true}),
    {kind: "replay"},
    "receipt compatível → replay",
  );

  const conflict = decideFinalize({
    receiptMatch: "idempotency-conflict",
    documentExists: true,
  });
  assert.strictEqual(conflict.kind, "error");
  assert.strictEqual(
    (conflict as {code: string}).code,
    "idempotency-conflict",
    "fingerprint divergente → conflito",
  );

  // Núcleo da decisão: documento sem receipt é estado impossível e deve
  // FALHAR FECHADO, nunca ser tratado como no-op.
  const invariant = decideFinalize({
    receiptMatch: "missing",
    documentExists: true,
  });
  assert.strictEqual(invariant.kind, "error", "documento sem receipt falha");
  assert.strictEqual(
    (invariant as {code: string}).code,
    "integrity",
    "violação de invariante é integrity, não replay",
  );
}

// ── Verificação de Storage ───────────────────────────────────────────────────

function testVerifyStorageObject() {
  const base = {
    exists: true as const,
    contentType: "application/pdf",
    size: 1024,
    md5Hash: "abc",
    crc32c: "crc",
    generation: "17",
  };

  const ok = verifyStorageObject(base);
  assert.strictEqual(ok.contentType, "application/pdf");
  assert.strictEqual(ok.sizeBytes, 1024);
  assert.strictEqual(ok.md5Hash, "abc");
  assert.strictEqual(ok.crc32c, "crc");
  assert.strictEqual(ok.generation, "17");

  // GCS devolve size e generation numéricos-como-string.
  assert.strictEqual(
    verifyStorageObject({...base, contentType: "image/jpeg", size: "2048"})
      .sizeBytes,
    2048,
    "size string é aceito",
  );

  expectLogicError(
    () => verifyStorageObject({exists: false}),
    "integrity",
    "objeto ausente falha fechado",
  );
  expectLogicError(
    () => verifyStorageObject({...base, contentType: undefined}),
    "integrity",
    "sem contentType",
  );
  expectLogicError(
    () => verifyStorageObject({...base, size: undefined}),
    "integrity",
    "sem size",
  );
  expectLogicError(
    () => verifyStorageObject({...base, size: "abc"}),
    "integrity",
    "size não numérico",
  );
  expectLogicError(
    () => verifyStorageObject({...base, size: 0}),
    "integrity",
    "objeto vazio",
  );
  expectLogicError(
    () => verifyStorageObject({...base, contentType: "text/html"}),
    "validation",
    "contentType não permitido",
  );
  expectLogicError(
    () => verifyStorageObject({...base, size: MAX_DOCUMENT_BYTES + 1}),
    "validation",
    "excede 20 MB",
  );

  // B0-B.R: generation é obrigatória — sem ela não há como prender o selo.
  expectLogicError(
    () => verifyStorageObject({...base, generation: undefined}),
    "integrity",
    "sem generation falha fechado",
  );

  // B0-B.R: pelo menos um checksum forte é obrigatório.
  expectLogicError(
    () =>
      verifyStorageObject({...base, md5Hash: undefined, crc32c: undefined}),
    "integrity",
    "sem md5 e sem crc32c falha fechado",
  );
  // Apenas um dos dois basta.
  assert.strictEqual(
    verifyStorageObject({...base, md5Hash: undefined}).crc32c,
    "crc",
    "crc32c sozinho é suficiente",
  );
  assert.strictEqual(
    verifyStorageObject({...base, crc32c: undefined}).md5Hash,
    "abc",
    "md5 sozinho é suficiente",
  );

  // Limite exato é aceito.
  assert.strictEqual(
    verifyStorageObject({...base, size: MAX_DOCUMENT_BYTES}).sizeBytes,
    MAX_DOCUMENT_BYTES,
    "20 MB exato aceito",
  );

  assert.ok(isAllowedContentType("image/png"));
  assert.ok(isAllowedContentType("application/pdf"));
  assert.ok(isAllowedContentType("application/msword"));
  assert.ok(
    isAllowedContentType(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ),
  );
  assert.ok(!isAllowedContentType("text/plain"));
  assert.ok(!isAllowedContentType(""));
  assert.ok(!isAllowedContentType(undefined));
}

// ── recorded_by / ref ────────────────────────────────────────────────────────

function testRecordedByAndRef() {
  const caller = {uid: "uid-1", name: "Operador", ra: "691755"};
  assert.deepStrictEqual(
    recordedByPayload(caller, false),
    {uid: "uid-1", name: "Operador", internal_role: "condutor"},
  );
  assert.deepStrictEqual(
    recordedByPayload(caller, true),
    {uid: "uid-1", name: "Operador", internal_role: "admin"},
  );
  assert.deepStrictEqual(
    recordedByPayload({uid: "u", name: "", ra: "691755"}, false),
    {uid: "u", name: "691755", internal_role: "condutor"},
    "fallback de name para RA",
  );

  // Ref é identidade: nada de título, tipo, path, mime, URL ou profissional.
  const ref = healthDocumentRef("hd_abc");
  assert.deepStrictEqual(ref, {health_document_id: "hd_abc"});
  assert.strictEqual(Object.keys(ref).length, 1, "ref carrega só a identidade");
}

// ── Selo: staging vs canônico (B0-B.R) ───────────────────────────────────────

function testStagingPathSeparation() {
  const documentId = idFor("dog-1", "op-1");
  const staging = stagingStoragePath("dog-1", documentId);
  const canonical = canonicalStoragePath("dog-1", documentId);

  assert.strictEqual(
    staging,
    `health_document_uploads/dog-1/${documentId}`,
    "staging namespace",
  );
  assert.notStrictEqual(staging, canonical, "namespaces são distintos");
  assert.ok(
    !staging.startsWith("health_documents/"),
    "staging não colide com o prefixo canônico",
  );
  assert.ok(!staging.includes("."), "staging também sem extensão");
  // Ambos determinísticos a partir de dogId + documentId.
  assert.strictEqual(
    stagingStoragePath("dog-1", documentId),
    staging,
    "staging estável",
  );
}

function testAssertSealedObjectMatches() {
  const staging = {
    contentType: "application/pdf",
    sizeBytes: 4096,
    md5Hash: "md5-abc",
    crc32c: "crc-abc",
    generation: "1",
  };

  // Igual em size/contentType/checksums → recuperação legítima.
  assertSealedObjectMatches({
    canonical: {...staging, generation: "sealed-1"},
    staging,
  });

  expectLogicError(
    () =>
      assertSealedObjectMatches({
        canonical: {...staging, sizeBytes: 999, generation: "s"},
        staging,
      }),
    "integrity",
    "size divergente",
  );
  expectLogicError(
    () =>
      assertSealedObjectMatches({
        canonical: {...staging, contentType: "image/png", generation: "s"},
        staging,
      }),
    "integrity",
    "contentType divergente",
  );
  expectLogicError(
    () =>
      assertSealedObjectMatches({
        canonical: {...staging, md5Hash: "md5-outro", generation: "s"},
        staging,
      }),
    "integrity",
    "md5 divergente",
  );
  expectLogicError(
    () =>
      assertSealedObjectMatches({
        canonical: {...staging, crc32c: "crc-outro", generation: "s"},
        staging,
      }),
    "integrity",
    "crc32c divergente",
  );

  // Sem checksum comparável em comum → fail-closed, nunca "assume igual".
  expectLogicError(
    () =>
      assertSealedObjectMatches({
        canonical: {
          ...staging,
          md5Hash: null,
          crc32c: null,
          generation: "s",
        },
        staging,
      }),
    "integrity",
    "nenhum checksum comparável",
  );

  // Um checksum comparável basta.
  assertSealedObjectMatches({
    canonical: {...staging, md5Hash: null, generation: "s"},
    staging: {...staging, md5Hash: null},
  });
}


// ── Selo: fingerprint de intenção (B0-B.R2) ──────────────────────────────────

function testSealFingerprint() {
  const fp1 = fingerprintCreateDocumentIntent(baseIntent);
  const fp2 = fingerprintCreateDocumentIntent({
    ...baseIntent,
    title: "Outro título",
  });

  const m = (finalizeFingerprint: string, operationId = "op-1") =>
    sealFingerprintMaterial({dogId: "dog-1", operationId, finalizeFingerprint});

  assert.strictEqual(m(fp1), m(fp1), "mesma intenção → mesmo material");
  assert.notStrictEqual(
    m(fp1),
    m(fp2),
    "payload diferente → seal material diferente",
  );
  assert.notStrictEqual(
    m(fp1, "op-1"),
    m(fp1, "op-2"),
    "operationId diferente → seal material diferente",
  );
  assert.ok(
    m(fp1).includes("health_document_seal_v1"),
    "material versionado",
  );

  // Não carrega persistência nem URL.
  for (const forbidden of ["recorded_by", "uploaded_at", "http", "generation"]) {
    assert.ok(
      !m(fp1).includes(forbidden),
      `seal material não inclui ${forbidden}`,
    );
  }

  const meta = sealMetadata({sealFingerprint: "fp", documentId: "hd_x"});
  assert.strictEqual(meta[SEAL_VERSION_KEY], HEALTH_DOCUMENT_SEAL_VERSION);
  assert.strictEqual(meta[SEAL_FINGERPRINT_KEY], "fp");
}

function testAssertSealIntentMatches() {
  const valid = sealMetadata({sealFingerprint: "fp-1", documentId: "hd_x"});

  assertSealIntentMatches({
    metadata: valid,
    expectedSealFingerprint: "fp-1",
  });

  // Ausência total de metadata: objeto de origem desconhecida.
  expectLogicError(
    () =>
      assertSealIntentMatches({
        metadata: undefined,
        expectedSealFingerprint: "fp-1",
      }),
    "integrity",
    "sem metadata de selo",
  );
  expectLogicError(
    () =>
      assertSealIntentMatches({metadata: {}, expectedSealFingerprint: "fp-1"}),
    "integrity",
    "metadata vazia",
  );
  expectLogicError(
    () =>
      assertSealIntentMatches({
        metadata: {...valid, [SEAL_VERSION_KEY]: "9"},
        expectedSealFingerprint: "fp-1",
      }),
    "integrity",
    "versão incompatível",
  );
  expectLogicError(
    () =>
      assertSealIntentMatches({
        metadata: {[SEAL_VERSION_KEY]: "1"},
        expectedSealFingerprint: "fp-1",
      }),
    "integrity",
    "fingerprint ausente",
  );

  // Fingerprint divergente é CONFLITO de idempotência, não integridade: o
  // objeto está íntegro; errado é associá-lo a outra intenção.
  expectLogicError(
    () =>
      assertSealIntentMatches({
        metadata: valid,
        expectedSealFingerprint: "fp-outro",
      }),
    "idempotency-conflict",
    "selo de outra intenção",
  );
}

const tests: Array<[string, () => void]> = [
  ["identidade determinística", testDeterministicIdentity],
  ["operationId/dogId", testOperationId],
  ["document_type estrito", testDocumentType],
  ["title e opcionais", testTitleAndOptionals],
  ["fingerprint", testFingerprint],
  ["receipt match", testReceiptMatch],
  ["receipt shape", testReceiptShape],
  ["decideFinalize", testDecideFinalize],
  ["verificação de Storage", testVerifyStorageObject],
  ["recorded_by e ref", testRecordedByAndRef],
  ["separação staging/canônico", testStagingPathSeparation],
  ["comparação de objeto selado", testAssertSealedObjectMatches],
  ["seal fingerprint", testSealFingerprint],
  ["validação de intenção do selo", testAssertSealIntentMatches],
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
