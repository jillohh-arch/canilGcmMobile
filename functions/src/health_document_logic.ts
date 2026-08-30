/**
 * Lógica pura do HealthDocument canônico (B0-B — fatia mínima de evidência).
 *
 * Sem Firebase Admin: testável com node assert, sem emulador e sem Storage.
 *
 * CONTRATO (baseline 8807199, ver HEALTH_V1_FIRESTORE_SCHEMA §2.11 e
 * HEALTH_V1_DOMAIN_MODEL §2.10):
 *
 *   Firestore  dogs/{dogId}/health_documents/{documentId}
 *   Storage    health_documents/{dogId}/{documentId}   (sem extensão)
 *
 * O agregado NÃO carrega metadados de mutação (`revision`,
 * `create_fingerprint`, `create_operation_id`): idempotência vive no receipt.
 * A prova de que isso é suficiente está em `decideFinalize`: o receipt é o
 * único gate, e a ausência de receipt com agregado presente é estado
 * impossível dentro do protocolo — fail-closed, nunca replay.
 */

export type JsonMap = Record<string, unknown>;

export const HEALTH_DOCUMENT_SCHEMA_VERSION = 1;

/** Discriminador versionado do fingerprint (evita colisão em mudança futura). */
export const HEALTH_DOCUMENT_CREATE_KIND = "health_document_create_v1";

/** Tipo de operação do receipt. */
export const HEALTH_DOCUMENT_CREATE_OPERATION = "create_document";

export const MAX_TITLE_LEN = 200;
export const MAX_DESCRIPTION_LEN = 2000;
export const MAX_ISSUER_LEN = 200;
export const MAX_OPERATION_ID_LEN = 128;

/** Limite canônico de tamanho do objeto (paridade com storage.rules). */
export const MAX_DOCUMENT_BYTES = 20 * 1024 * 1024;

/**
 * Nove tipos canônicos (HEALTH_V1_DOMAIN_MODEL §2.10).
 *
 * `document_type` descreve a NATUREZA do arquivo. O papel de evidência de uma
 * restrição é relacionamento (`source_document`), nunca um tipo especial —
 * `restriction_evidence` e `vet_release` não existem por decisão B0-A.2.
 */
export const HEALTH_DOCUMENT_TYPES = [
  "prescription",
  "report",
  "certificate",
  "exam_image",
  "exam_pdf",
  "photo",
  "vaccination_card",
  "surgical_report",
  "other",
] as const;

export type HealthDocumentType = (typeof HEALTH_DOCUMENT_TYPES)[number];

/**
 * contentType aceito, espelhando `canWriteHealthAttachment` em storage.rules:
 * imagem, PDF ou documento Office.
 */
export const ALLOWED_IMAGE_PREFIX = "image/";
export const ALLOWED_EXACT_CONTENT_TYPES = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);

export type AppErrorCode =
  | "unauthenticated"
  | "permission-denied"
  | "not-found"
  | "conflict"
  | "idempotency-conflict"
  | "validation"
  | "integrity"
  | "unexpected";

export function logicError(code: AppErrorCode, message: string): Error {
  const err = new Error(message) as Error & {appCode: AppErrorCode};
  err.appCode = code;
  return err;
}

export function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length === 0 ? undefined : text;
}

/** Idêntico ao contrato da Agenda: o id lógico vira segmento de path. */
export const OPERATION_ID_SAFE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export function normalizeOperationId(raw: unknown): string {
  const value = stringValue(raw);
  if (!value) {
    throw logicError(
      "validation",
      "operationId/idempotencyKey é obrigatório.",
    );
  }
  if (value.length > MAX_OPERATION_ID_LEN) {
    throw logicError("validation", "operationId excede o tamanho máximo.");
  }
  if (
    value === "." ||
    value === ".." ||
    value.includes("/") ||
    value.includes("\\") ||
    !OPERATION_ID_SAFE_PATTERN.test(value)
  ) {
    throw logicError(
      "validation",
      "operationId/idempotencyKey contém caracteres inválidos para path.",
    );
  }
  return value;
}

export function assertDogId(raw: unknown): string {
  const value = stringValue(raw);
  if (!value) {
    throw logicError("validation", "dogId é obrigatório.");
  }
  if (value.includes("/") || value.includes("\\") || value.length > 128) {
    throw logicError("validation", "dogId inválido.");
  }
  if (value === "." || value === "..") {
    throw logicError("validation", "dogId inválido.");
  }
  return value;
}

/**
 * Parse ESTRITO de `document_type`.
 *
 * Sem fallback para `other`: um valor desconhecido esconderia dado malformado.
 * Vocabulário legado (`laudo`, `certificado`, `documento`, `exame`) NÃO é
 * mapeado — decisão B0-A.2.
 */
export function parseHealthDocumentType(raw: unknown): HealthDocumentType {
  const value = stringValue(raw);
  if (!value) {
    throw logicError("validation", "documentType é obrigatório.");
  }
  if (!(HEALTH_DOCUMENT_TYPES as readonly string[]).includes(value)) {
    throw logicError(
      "validation",
      `documentType inválido: ${value}. ` +
        `Valores canônicos: ${HEALTH_DOCUMENT_TYPES.join(", ")}.`,
    );
  }
  return value as HealthDocumentType;
}

/** Título obrigatório, validado APÓS trim (um título só de espaços é vazio). */
export function assertTitle(raw: unknown): string {
  const value = stringValue(raw);
  if (!value) {
    throw logicError("validation", "title é obrigatório.");
  }
  if (value.length > MAX_TITLE_LEN) {
    throw logicError("validation", "title excede o tamanho máximo.");
  }
  return value;
}

export function optionalText(
  raw: unknown,
  maxLen: number,
  label: string,
): string | undefined {
  const value = stringValue(raw);
  if (value === undefined) return undefined;
  if (value.length > maxLen) {
    throw logicError("validation", `${label} excede o tamanho máximo.`);
  }
  return value;
}

/** Referência opcional a caso/evento/exame — id opaco, nunca path. */
export function optionalReferenceId(
  raw: unknown,
  label: string,
): string | undefined {
  const value = stringValue(raw);
  if (value === undefined) return undefined;
  if (value.includes("/") || value.includes("\\") || value.length > 128) {
    throw logicError("validation", `${label} inválido.`);
  }
  return value;
}

/**
 * Instante de negócio (data do documento). Aceita ISO-8601 ou epoch ms.
 *
 * NÃO aplica "não pode estar no futuro": `expiry_date` legitimamente está no
 * futuro, e `issue_date` é fato do documento externo, não de persistência.
 */
export function optionalInstant(
  raw: unknown,
  label: string,
): Date | undefined {
  if (raw === null || raw === undefined || raw === "") return undefined;
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) {
      throw logicError("validation", `${label} inválido.`);
    }
    return raw;
  }
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const fromEpoch = new Date(raw);
    if (Number.isNaN(fromEpoch.getTime())) {
      throw logicError("validation", `${label} inválido.`);
    }
    return fromEpoch;
  }
  const text = stringValue(raw);
  if (!text) throw logicError("validation", `${label} inválido.`);
  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) {
    throw logicError("validation", `${label} inválido.`);
  }
  return parsed;
}

/** Invariante documental preservada de HealthDocument (Dart §2.10). */
export function assertDocumentDates(
  issueDate: Date | undefined,
  expiryDate: Date | undefined,
): void {
  if (issueDate && expiryDate && expiryDate.getTime() < issueDate.getTime()) {
    throw logicError(
      "validation",
      "expiry_date não pode ser anterior a issue_date.",
    );
  }
}

export function isAllowedContentType(raw: unknown): boolean {
  const value = stringValue(raw);
  if (!value) return false;
  const normalized = value.toLowerCase();
  if (normalized.startsWith(ALLOWED_IMAGE_PREFIX)) return true;
  return ALLOWED_EXACT_CONTENT_TYPES.has(normalized);
}

/** Representação canônica determinística (chaves ordenadas). */
export function stableStringify(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "number" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map((v) => stableStringify(v)).join(",")}]`;
  }
  if (typeof value === "object") {
    const obj = value as JsonMap;
    const keys = Object.keys(obj).sort();
    return `{${keys
      .map((k) => `${JSON.stringify(k)}:${stableStringify(obj[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(String(value));
}

/**
 * Material da identidade determinística.
 *
 * Deriva de kind/version + dogId + operationId. NÃO usa relógio, random,
 * filename, title nem mimeType — a identidade precisa ser reproduzível por
 * PREPARE e por FINALIZE de forma independente.
 *
 * O `actorUid` fica FORA de propósito: PREPARE e FINALIZE do mesmo operador
 * derivam o mesmo id, e dois operadores diferentes reusando o mesmo
 * operationId colidem no mesmo documentId — colisão que o gate de receipt
 * resolve como conflito explícito em vez de criar documento duplicado.
 */
export function createIdempotencyMaterial(
  dogId: string,
  operationId: string,
): string {
  return `${HEALTH_DOCUMENT_CREATE_KIND}|${dogId}|${operationId}`;
}

export function deterministicDocumentId(hashHex: string): string {
  return `hd_${hashHex.slice(0, 28)}`;
}

/** Storage path canônico, sem extensão (B0-A.2). Cliente NUNCA escreve aqui. */
export function canonicalStoragePath(
  dogId: string,
  documentId: string,
): string {
  return `health_documents/${dogId}/${documentId}`;
}

/**
 * Storage path de STAGING — único destino de upload do cliente.
 *
 * Existe porque `allow create` das Firebase Storage Rules NÃO impede a
 * substituição dos bytes de um objeto já existente (comprovado no emulador:
 * um segundo upload no mesmo path é avaliado como create e troca o conteúdo).
 * Logo, bytes gravados pelo cliente não podem ser a evidência canônica.
 *
 * Staging é explicitamente NÃO canônico: sobrescrever aqui antes do FINALIZE
 * não corrompe evidência, porque o selo backend se prende a uma `generation`
 * exata.
 */
export function stagingStoragePath(
  dogId: string,
  documentId: string,
): string {
  return `health_document_uploads/${dogId}/${documentId}`;
}

/** Path Firestore do agregado — distinto do path de Storage. */
export function canonicalDocumentPath(
  dogId: string,
  documentId: string,
): string {
  return `dogs/${dogId}/health_documents/${documentId}`;
}

export interface HealthDocumentIntent {
  readonly dogId: string;
  readonly documentType: HealthDocumentType;
  readonly title: string;
  readonly description: string | null;
  readonly issuer: string | null;
  readonly issueDateIso: string | null;
  readonly expiryDateIso: string | null;
  readonly caseId: string | null;
  readonly eventId: string | null;
  readonly examId: string | null;
}

/**
 * Fingerprint da INTENÇÃO do cliente.
 *
 * Inclui somente payload de negócio controlado pelo cliente. Fora, de forma
 * deliberada: `operationId` (é a chave do receipt — incluí-lo tornaria todo
 * fingerprint único e mataria a detecção de conflito), `recorded_by`,
 * `uploaded_at`, `storage_path`, `mime_type` e qualquer URL — todos derivados
 * pelo servidor.
 *
 * Opcionais ausentes normalizam para `null`, então "omitido" e "null explícito"
 * produzem um único fingerprint.
 */
export function fingerprintCreateDocumentIntent(
  intent: HealthDocumentIntent,
): string {
  return stableStringify({
    kind: HEALTH_DOCUMENT_CREATE_KIND,
    dogId: intent.dogId,
    documentType: intent.documentType,
    title: intent.title,
    description: intent.description,
    issuer: intent.issuer,
    issueDate: intent.issueDateIso,
    expiryDate: intent.expiryDateIso,
    caseId: intent.caseId,
    eventId: intent.eventId,
    examId: intent.examId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Selo: vínculo durável entre bytes canônicos e a intenção que os produziu
// ─────────────────────────────────────────────────────────────────────────────

/** Versão do protocolo de selagem, gravada na metadata do objeto canônico. */
export const HEALTH_DOCUMENT_SEAL_VERSION = "1";

/** Chaves de metadata server-owned no objeto canônico. */
export const SEAL_VERSION_KEY = "k9_health_seal_version";
export const SEAL_FINGERPRINT_KEY = "k9_health_seal_fingerprint";
export const SEAL_DOCUMENT_ID_KEY = "k9_health_document_id";

/**
 * Material do fingerprint de selagem.
 *
 * Existe porque, na janela "Storage selado / Firestore não commitado", NÃO há
 * receipt — logo não há nada durável no Firestore provando qual intenção
 * produziu aqueles bytes. Sem isso, um segundo FINALIZE com o mesmo
 * `operationId` e payload DIFERENTE poderia herdar bytes selados pela
 * intenção anterior, furando a promessa
 * "mesmo operationId + payload diferente → conflito".
 *
 * Deriva do fingerprint canônico do FINALIZE, então herda sua sensibilidade a
 * qualquer diferença material do payload. Não inclui `recorded_by`,
 * `uploaded_at`, generation nem qualquer URL: é intenção, não persistência.
 */
export function sealFingerprintMaterial(params: {
  readonly dogId: string;
  readonly operationId: string;
  readonly finalizeFingerprint: string;
}): string {
  return stableStringify([
    `health_document_seal_v${HEALTH_DOCUMENT_SEAL_VERSION}`,
    params.dogId,
    params.operationId,
    params.finalizeFingerprint,
  ]);
}

/** Metadata server-owned a gravar no destino canônico durante a cópia. */
export function sealMetadata(params: {
  readonly sealFingerprint: string;
  readonly documentId: string;
}): Record<string, string> {
  return {
    [SEAL_VERSION_KEY]: HEALTH_DOCUMENT_SEAL_VERSION,
    [SEAL_FINGERPRINT_KEY]: params.sealFingerprint,
    [SEAL_DOCUMENT_ID_KEY]: params.documentId,
  };
}

/**
 * Valida o selo gravado no objeto canônico contra a intenção atual.
 *
 * Fail-closed em todos os desvios: metadata ausente (objeto de origem
 * desconhecida), versão inesperada, ou fingerprint divergente. Nunca reescreve
 * a metadata para forçar correspondência.
 *
 * Divergência de fingerprint é `idempotency-conflict` — mesmo `operationId`,
 * intenção diferente — e não `integrity`, porque o objeto em si está íntegro;
 * o que está errado é tentar associá-lo a outra intenção.
 */
export function assertSealIntentMatches(params: {
  readonly metadata: Readonly<Record<string, string>> | undefined;
  readonly expectedSealFingerprint: string;
}): void {
  const metadata = params.metadata;
  if (!metadata) {
    throw logicError(
      "integrity",
      "Objeto canônico existe sem metadata de selagem: origem desconhecida, " +
        "recusando associar a esta operação.",
    );
  }
  const version = stringValue(metadata[SEAL_VERSION_KEY]);
  if (!version) {
    throw logicError(
      "integrity",
      "Objeto canônico existe sem seal_version: origem desconhecida.",
    );
  }
  if (version !== HEALTH_DOCUMENT_SEAL_VERSION) {
    throw logicError(
      "integrity",
      `Objeto canônico com seal_version incompatível: ${version}.`,
    );
  }
  const fingerprint = stringValue(metadata[SEAL_FINGERPRINT_KEY]);
  if (!fingerprint) {
    throw logicError(
      "integrity",
      "Objeto canônico sem seal_fingerprint: não é possível provar qual " +
        "intenção o selou.",
    );
  }
  if (fingerprint !== params.expectedSealFingerprint) {
    throw logicError(
      "idempotency-conflict",
      "Objeto canônico foi selado por uma intenção diferente com a mesma " +
        "idempotencyKey: recusando associar outro payload à evidência selada.",
    );
  }
}

export type ReceiptMatch = "replay" | "idempotency-conflict" | "missing";

/**
 * Receipt malformado ≠ ausente.
 *
 * Um documento de receipt presente mas sem os campos canônicos é violação de
 * integridade (fail-closed) — nunca tratado como "missing", o que abriria a
 * porta para um segundo create.
 */
export function assertReceiptShape(data: JsonMap): void {
  const required = [
    "kind",
    "operation_id",
    "operation_type",
    "actor_uid",
    "fingerprint",
    "result",
  ];
  for (const key of required) {
    const value = data[key];
    if (value === undefined || value === null || value === "") {
      throw logicError(
        "integrity",
        `Receipt malformado: campo obrigatório ausente (${key}).`,
      );
    }
  }
  if (stringValue(data.kind) !== HEALTH_DOCUMENT_CREATE_KIND) {
    throw logicError(
      "integrity",
      "Receipt de kind/version incompatível com health_document_create_v1.",
    );
  }
  if (
    stringValue(data.operation_type) !== HEALTH_DOCUMENT_CREATE_OPERATION
  ) {
    throw logicError(
      "integrity",
      "Receipt de operation_type incompatível.",
    );
  }
}

/**
 * Replay só quando actor + operation_type + fingerprint batem TODOS.
 * Qualquer divergência é conflito, nunca replay. Campo ausente é `undefined` e
 * nunca iguala a string fornecida — fail-closed por construção.
 */
export function matchDocumentReceipt(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly actorUid: string;
  readonly fingerprint: string;
}): ReceiptMatch {
  if (!params.receiptExists) return "missing";
  if (params.storedActorUid !== params.actorUid) {
    return "idempotency-conflict";
  }
  if (params.storedOperationType !== HEALTH_DOCUMENT_CREATE_OPERATION) {
    return "idempotency-conflict";
  }
  if (params.storedFingerprint !== params.fingerprint) {
    return "idempotency-conflict";
  }
  return "replay";
}

export type FinalizeDecision =
  | {readonly kind: "create"}
  | {readonly kind: "replay"}
  | {readonly kind: "error"; readonly code: AppErrorCode; readonly message: string};

/**
 * Decisão canônica do FINALIZE.
 *
 * Esta função é a prova de que o agregado não precisa de `create_fingerprint`:
 * o receipt é o único gate de idempotência, e a combinação
 * "documento existe SEM receipt" é estado impossível no protocolo — o writer
 * escreve receipt e agregado na MESMA transação, logo nunca produz um sem o
 * outro. Se aparecer, é corrupção, bypass ou escrita manual, e a operação
 * precisa parar em vez de assumir replay (o que sobrescreveria silenciosamente
 * evidência clínica de origem desconhecida).
 */
export function decideFinalize(params: {
  readonly receiptMatch: ReceiptMatch;
  readonly documentExists: boolean;
}): FinalizeDecision {
  if (params.receiptMatch === "replay") return {kind: "replay"};
  if (params.receiptMatch === "idempotency-conflict") {
    return {
      kind: "error",
      code: "idempotency-conflict",
      message:
        "Mesma idempotencyKey com intenção diferente da criação original.",
    };
  }
  if (params.documentExists) {
    return {
      kind: "error",
      code: "integrity",
      message:
        "HealthDocument já existe sem receipt correspondente: " +
        "violação de invariante do protocolo de criação.",
    };
  }
  return {kind: "create"};
}

export interface StorageObjectMetadata {
  readonly exists: boolean;
  readonly contentType?: string;
  /** Tamanho em bytes; string é aceita porque GCS devolve numérico-como-string. */
  readonly size?: number | string;
  readonly md5Hash?: string;
  readonly crc32c?: string;
  readonly generation?: number | string;
  /** Custom metadata do objeto (`metadata.metadata` no GCS). */
  readonly customMetadata?: Readonly<Record<string, string>>;
}

export interface VerifiedStorageObject {
  readonly contentType: string;
  readonly sizeBytes: number;
  readonly md5Hash: string | null;
  readonly crc32c: string | null;
  readonly generation: string;
}

function parseSizeBytes(raw: number | string | undefined): number {
  if (typeof raw === "number") {
    if (!Number.isFinite(raw) || !Number.isInteger(raw) || raw < 0) {
      throw logicError("integrity", "Metadata do objeto com size inválido.");
    }
    return raw;
  }
  const text = stringValue(raw);
  if (!text) {
    throw logicError("integrity", "Metadata do objeto sem size.");
  }
  const parsed = Number(text);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed < 0) {
    throw logicError("integrity", "Metadata do objeto com size inválido.");
  }
  return parsed;
}

/**
 * Verificação fail-closed do objeto de STAGING.
 *
 * Objeto ausente NUNCA degrada para "documento sem arquivo": um HealthDocument
 * cujo `storage_path` não resolve não é evidência de nada.
 *
 * `generation` é OBRIGATÓRIA: é ela que prende o selo a estes bytes exatos.
 * Sem generation não há como provar que o objeto copiado é o objeto validado,
 * então a operação falha em vez de copiar "o que estiver lá".
 *
 * `contentType` é declarado no upload (não byte-sniffed) — limitação factual
 * reconhecida do B0. `size`, `md5Hash`, `crc32c` e `generation` são computados
 * pelo GCS e portanto confiáveis.
 */
export function verifyStorageObject(
  metadata: StorageObjectMetadata,
): VerifiedStorageObject {
  if (!metadata.exists) {
    throw logicError(
      "integrity",
      "Objeto não encontrado no Storage path de upload. " +
        "Faça o upload antes de finalizar.",
    );
  }
  const contentType = stringValue(metadata.contentType);
  if (!contentType) {
    throw logicError(
      "integrity",
      "Metadata do objeto sem contentType.",
    );
  }
  if (!isAllowedContentType(contentType)) {
    throw logicError(
      "validation",
      `contentType não permitido para HealthDocument: ${contentType}.`,
    );
  }
  const sizeBytes = parseSizeBytes(metadata.size);
  if (sizeBytes === 0) {
    throw logicError("integrity", "Objeto vazio no Storage.");
  }
  if (sizeBytes > MAX_DOCUMENT_BYTES) {
    throw logicError(
      "validation",
      `Objeto excede o limite de ${MAX_DOCUMENT_BYTES} bytes.`,
    );
  }
  const generation = stringValue(metadata.generation);
  if (!generation) {
    throw logicError(
      "integrity",
      "Metadata do objeto sem generation: não é possível selar evidência " +
        "sem prender a cópia a uma versão exata.",
    );
  }
  const md5Hash = stringValue(metadata.md5Hash) ?? null;
  const crc32c = stringValue(metadata.crc32c) ?? null;
  if (md5Hash === null && crc32c === null) {
    // MD5 pode faltar em modos de upload compostos; sem NENHUM checksum forte
    // não há como provar equivalência byte-a-byte na recuperação.
    throw logicError(
      "integrity",
      "Metadata do objeto sem checksum (md5Hash/crc32c): " +
        "integridade da evidência não é verificável.",
    );
  }
  return {contentType, sizeBytes, md5Hash, crc32c, generation};
}

/**
 * Prova que o objeto canônico já selado corresponde exatamente à evidência
 * validada no staging.
 *
 * Usado APENAS no cenário legítimo de recuperação: o selo no Storage teve
 * sucesso mas a transação Firestore não commitou. Storage e Firestore não
 * compartilham transação, então esse estado é possível sem corrupção.
 *
 * Nunca sobrescreve o canônico para forçar correspondência: divergência é
 * fail-closed. Comparação por metadata server-side (checksum + size +
 * contentType), nunca por URL nem por checksum vindo do cliente.
 */
export function assertSealedObjectMatches(params: {
  readonly canonical: VerifiedStorageObject;
  readonly staging: VerifiedStorageObject;
}): void {
  const {canonical, staging} = params;
  if (canonical.sizeBytes !== staging.sizeBytes) {
    throw logicError(
      "integrity",
      "Objeto canônico já existe com tamanho divergente da evidência " +
        "enviada: recusando sobrescrever evidência clínica.",
    );
  }
  if (canonical.contentType !== staging.contentType) {
    throw logicError(
      "integrity",
      "Objeto canônico já existe com contentType divergente da evidência " +
        "enviada.",
    );
  }
  const md5Comparable =
    canonical.md5Hash !== null && staging.md5Hash !== null;
  const crcComparable =
    canonical.crc32c !== null && staging.crc32c !== null;
  if (!md5Comparable && !crcComparable) {
    throw logicError(
      "integrity",
      "Objeto canônico já existe sem checksum comparável: " +
        "equivalência de bytes não é verificável.",
    );
  }
  if (md5Comparable && canonical.md5Hash !== staging.md5Hash) {
    throw logicError(
      "integrity",
      "Objeto canônico já existe com md5 divergente: " +
        "recusando sobrescrever evidência clínica.",
    );
  }
  if (crcComparable && canonical.crc32c !== staging.crc32c) {
    throw logicError(
      "integrity",
      "Objeto canônico já existe com crc32c divergente: " +
        "recusando sobrescrever evidência clínica.",
    );
  }
}

export function recordedByPayload(
  caller: {readonly uid: string; readonly name: string; readonly ra: string},
  isAdmin: boolean,
): JsonMap {
  return {
    uid: caller.uid,
    name: caller.name || caller.ra || caller.uid,
    internal_role: isAdmin ? "admin" : "condutor",
  };
}

export interface DocumentReceiptResult {
  readonly dogId: string;
  readonly documentId: string;
}

/** Referência citável — identidade, sem metadados copiados. */
export function healthDocumentRef(documentId: string): JsonMap {
  return {health_document_id: documentId};
}
