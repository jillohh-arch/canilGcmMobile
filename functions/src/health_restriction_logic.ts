/**
 * Lógica pura do writer de OperationalRestriction — ISSUE (B1).
 *
 * Sem Firebase Admin: testável com node assert, sem emulador.
 *
 * FRONTEIRA COM O B0 (load-bearing): este módulo NÃO conhece Storage. Não
 * importa adapter, não lê `storage_path`, MD5, generation nem seal fingerprint.
 * Para o writer de restrição, um `HealthDocument` canônico existente É a
 * evidência citável — toda a complexidade de selagem ficou encapsulada atrás
 * daquela autoridade.
 *
 * ESCOPO: apenas `active`. END/CANCEL são o B2, e a autoridade de `cancelled`
 * segue deliberadamente pendente desde o A.2.
 */

export type JsonMap = Record<string, unknown>;

/** Schema version do agregado (Schema §2.12 exige `schema_version`). */
export const OPERATIONAL_RESTRICTION_SCHEMA_VERSION = 1;

/** Discriminador versionado do fingerprint/receipt. */
export const RESTRICTION_ISSUE_KIND =
  "health_operational_restriction_issue_v1";

export const RESTRICTION_ISSUE_OPERATION = "issue_restriction";

export const MAX_DESCRIPTION_LEN = 2000;
export const MAX_ACTIVITY_LEN = 120;
export const MAX_ACTIVITIES = 50;
export const MAX_OPERATION_ID_LEN = 128;
export const MAX_PROFESSIONAL_FIELD_LEN = 200;

/** Levels canônicos (ADR-005; reader rejeita qualquer outro valor). */
export const RESTRICTION_LEVELS = ["absolute", "partial", "attention"] as const;
export type RestrictionLevel = (typeof RESTRICTION_LEVELS)[number];

/** Categorias canônicas (Domain Model §6). */
export const RESTRICTION_CATEGORIES = [
  "injury",
  "post_surgical",
  "medication_effect",
  "behavioral",
  "infectious",
  "chronic",
  "preventive_pending",
  "other",
] as const;
export type RestrictionCategory = (typeof RESTRICTION_CATEGORIES)[number];

/** Tipos de registro profissional canônicos (wire names). */
export const PROFESSIONAL_REGISTRATION_TYPES = [
  "CRMV",
  "CRMV-Z",
  "CRN",
  "CRF",
  "CFMV",
  "other",
] as const;
export type ProfessionalRegistrationType =
  (typeof PROFESSIONAL_REGISTRATION_TYPES)[number];

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

export const OPERATION_ID_SAFE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export function normalizeOperationId(raw: unknown): string {
  const value = stringValue(raw);
  if (!value) {
    throw logicError("validation", "operationId/idempotencyKey é obrigatório.");
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

export function assertDocumentId(raw: unknown, label: string): string {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", `${label} é obrigatório.`);
  if (
    value.includes("/") ||
    value.includes("\\") ||
    value === "." ||
    value === ".." ||
    value.length > 128
  ) {
    throw logicError("validation", `${label} inválido.`);
  }
  return value;
}

/** Parse ESTRITO de level: desconhecido é erro, nunca fallback. */
export function parseLevel(raw: unknown): RestrictionLevel {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", "level é obrigatório.");
  if (!(RESTRICTION_LEVELS as readonly string[]).includes(value)) {
    throw logicError(
      "validation",
      `level inválido: ${value}. Canônicos: ${RESTRICTION_LEVELS.join(", ")}.`,
    );
  }
  return value as RestrictionLevel;
}

/**
 * Parse ESTRITO de category.
 *
 * O reader tolera `category` ausente com default `other`, mas o writer NÃO
 * pode: Schema §2.12 marca `category` como obrigatório, e aceitar desconhecido
 * como `other` esconderia dado malformado na origem.
 */
export function parseCategory(raw: unknown): RestrictionCategory {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", "category é obrigatória.");
  if (!(RESTRICTION_CATEGORIES as readonly string[]).includes(value)) {
    throw logicError(
      "validation",
      `category inválida: ${value}. ` +
        `Canônicas: ${RESTRICTION_CATEGORIES.join(", ")}.`,
    );
  }
  return value as RestrictionCategory;
}

/** Descrição é parte material da restrição: não derivada, não vazia. */
export function assertDescription(raw: unknown): string {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", "description é obrigatória.");
  if (value.length > MAX_DESCRIPTION_LEN) {
    throw logicError("validation", "description excede o tamanho máximo.");
  }
  return value;
}

/**
 * Normaliza `activities_restricted`: trim, descarta vazios, remove duplicatas
 * preservando ordem. Permanece FREE-FORM — nenhuma taxonomia é criada aqui
 * (o OP-AUTH ainda não tem `requestedActivity` taxonomizada).
 */
export function normalizeActivities(raw: unknown): string[] {
  if (raw === null || raw === undefined) return [];
  if (!Array.isArray(raw)) {
    throw logicError(
      "validation",
      "activities_restricted deve ser uma lista de strings.",
    );
  }
  if (raw.length > MAX_ACTIVITIES) {
    throw logicError("validation", "activities_restricted excede o limite.");
  }
  const out: string[] = [];
  for (const item of raw) {
    if (item === null || item === undefined) continue;
    if (typeof item !== "string" && typeof item !== "number") {
      throw logicError(
        "validation",
        "activities_restricted contém item não textual.",
      );
    }
    const value = stringValue(item);
    if (!value) continue;
    if (value.length > MAX_ACTIVITY_LEN) {
      throw logicError(
        "validation",
        "activities_restricted contém item muito longo.",
      );
    }
    if (!out.includes(value)) out.push(value);
  }
  return out;
}

/**
 * Invariante load-bearing (ADR-005 E10 / Domain Model §2.11 invariante 5):
 * `partial` exige pelo menos uma atividade.
 *
 * O reader trata `partial` sem atividades como `missing_activities_restricted`
 * e torna a FONTE INTEIRA de restrições daquele K9 inutilizável — o que NEGA
 * ações operacionais críticas. O writer precisa impedir que tal documento
 * chegue à collection.
 */
export function assertPartialInvariant(
  level: RestrictionLevel,
  activities: readonly string[],
): void {
  if (level === "partial" && activities.length === 0) {
    throw logicError(
      "validation",
      "level partial exige activities_restricted com pelo menos uma atividade.",
    );
  }
}

/**
 * Instante de negócio (`expected_end`).
 *
 * Pode legitimamente estar no futuro — é expectativa clínica de reavaliação.
 * NÃO encerra a restrição, não agenda job, não altera status: `active`
 * permanece `active` até END/CANCEL explícito.
 */
export function optionalInstant(raw: unknown, label: string): Date | undefined {
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

// ─────────────────────────────────────────────────────────────────────────────
// ProfessionalIdentity — decisão clínica EXTERNA
// ─────────────────────────────────────────────────────────────────────────────

export interface ProfessionalIdentity {
  readonly name: string;
  readonly registration_type: ProfessionalRegistrationType;
  readonly registration_number: string;
  readonly clinic: string;
  readonly specialty: string | null;
}

/**
 * Valida `ProfessionalIdentity` canônica — OBRIGATÓRIA na emissão.
 *
 * Deliberadamente NÃO reutiliza o parser de nutrição: aquele trata
 * `professional` como opcional (name vazio devolve `null` silenciosamente) e
 * aceita `clinic` nulo. Para restrição, ambos seriam furos: uma restrição sem
 * profissional identificado não é decisão clínica transcrita.
 *
 * Também NÃO aceita o vocabulário legado (`vetName`, `professionalCrmv`,
 * `professionalClinic`) nem o alias `register_number`: promover legado exigiria
 * uma regra de derivação que o domínio não possui (decisão B0-A.2 E4).
 */
export function parseProfessionalIdentity(raw: unknown): ProfessionalIdentity {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw logicError(
      "validation",
      "professional é obrigatório: a restrição transcreve uma decisão " +
        "clínica externa identificada.",
    );
  }
  const obj = raw as Record<string, unknown>;

  for (const legacy of [
    "vetName",
    "professionalCrmv",
    "professionalClinic",
    "register_number",
    "register_state",
  ]) {
    if (Object.prototype.hasOwnProperty.call(obj, legacy)) {
      throw logicError(
        "validation",
        `professional.${legacy} é vocabulário legado e não é aceito: ` +
          "use o shape canônico ProfessionalIdentity.",
      );
    }
  }

  const name = stringValue(obj.name);
  if (!name) {
    throw logicError("validation", "professional.name é obrigatório.");
  }
  if (name.length > MAX_PROFESSIONAL_FIELD_LEN) {
    throw logicError("validation", "professional.name excede o tamanho.");
  }

  const registrationType = stringValue(obj.registration_type);
  if (!registrationType) {
    throw logicError(
      "validation",
      "professional.registration_type é obrigatório.",
    );
  }
  if (
    !(PROFESSIONAL_REGISTRATION_TYPES as readonly string[]).includes(
      registrationType,
    )
  ) {
    throw logicError(
      "validation",
      `professional.registration_type inválido: ${registrationType}. ` +
        `Canônicos: ${PROFESSIONAL_REGISTRATION_TYPES.join(", ")}.`,
    );
  }

  const registrationNumber = stringValue(obj.registration_number);
  if (!registrationNumber) {
    throw logicError(
      "validation",
      "professional.registration_number é obrigatório.",
    );
  }
  if (registrationNumber.length > MAX_PROFESSIONAL_FIELD_LEN) {
    throw logicError(
      "validation",
      "professional.registration_number excede o tamanho.",
    );
  }

  const clinic = stringValue(obj.clinic);
  if (!clinic) {
    throw logicError("validation", "professional.clinic é obrigatório.");
  }
  if (clinic.length > MAX_PROFESSIONAL_FIELD_LEN) {
    throw logicError("validation", "professional.clinic excede o tamanho.");
  }

  const specialty = stringValue(obj.specialty) ?? null;
  if (specialty !== null && specialty.length > MAX_PROFESSIONAL_FIELD_LEN) {
    throw logicError("validation", "professional.specialty excede o tamanho.");
  }

  return {
    name,
    registration_type: registrationType as ProfessionalRegistrationType,
    registration_number: registrationNumber,
    clinic,
    specialty,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HealthDocumentRef — evidência citável por IDENTIDADE
// ─────────────────────────────────────────────────────────────────────────────

export interface HealthDocumentRefValue {
  readonly health_document_id: string;
  readonly description: string | null;
}

/**
 * Extrai o `HealthDocumentRef` canônico.
 *
 * Só identidade: `health_document_id` (+ `description` opcional). URL, path,
 * MIME, generation e seal ficam FORA — o B0 encapsulou Storage, e para o B1
 * a existência do HealthDocument canônico é a evidência.
 */
export function parseSourceDocumentRef(raw: unknown): HealthDocumentRefValue {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw logicError(
      "validation",
      "source_document é obrigatório: a emissão exige evidência documental " +
        "canônica.",
    );
  }
  const obj = raw as Record<string, unknown>;

  for (const forbidden of [
    "url",
    "storage_path",
    "storagePath",
    "storage_url",
    "storageUrl",
    "download_url",
    "downloadUrl",
    "mime_type",
    "mimeType",
    "generation",
    "md5Hash",
    "checksum_md5",
  ]) {
    if (Object.prototype.hasOwnProperty.call(obj, forbidden)) {
      throw logicError(
        "validation",
        `source_document.${forbidden} não é aceito: a referência canônica é ` +
          "apenas health_document_id.",
      );
    }
  }

  const id = assertDocumentId(
    obj.health_document_id ?? obj.healthDocumentId,
    "source_document.health_document_id",
  );
  const description = stringValue(obj.description) ?? null;
  if (description !== null && description.length > MAX_DESCRIPTION_LEN) {
    throw logicError(
      "validation",
      "source_document.description excede o tamanho.",
    );
  }
  return {health_document_id: id, description};
}

// ─────────────────────────────────────────────────────────────────────────────
// Identidade determinística e fingerprint
// ─────────────────────────────────────────────────────────────────────────────

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
 * Deriva de kind/version + dogId + operationId. Não usa relógio, random,
 * `sourceDocumentId`, registro profissional, descrição nem level — a
 * identidade precisa ser estável entre retries do MESMO comando.
 */
export function createIdempotencyMaterial(
  dogId: string,
  operationId: string,
): string {
  return `${RESTRICTION_ISSUE_KIND}|${dogId}|${operationId}`;
}

export function deterministicRestrictionId(hashHex: string): string {
  return `or_${hashHex.slice(0, 28)}`;
}

export function canonicalRestrictionPath(
  dogId: string,
  restrictionId: string,
): string {
  return `dogs/${dogId}/operational_restrictions/${restrictionId}`;
}

export function canonicalHealthDocumentPath(
  dogId: string,
  healthDocumentId: string,
): string {
  return `dogs/${dogId}/health_documents/${healthDocumentId}`;
}

export interface RestrictionIssueIntent {
  readonly dogId: string;
  readonly level: RestrictionLevel;
  readonly category: RestrictionCategory;
  readonly description: string;
  readonly activitiesRestricted: readonly string[];
  readonly expectedEndIso: string | null;
  readonly professional: ProfessionalIdentity;
  readonly sourceDocument: HealthDocumentRefValue;
}

/**
 * Fingerprint da INTENÇÃO do cliente.
 *
 * Cobre todo o input material normalizado. Fora, deliberadamente:
 * `operationId` (é a chave do receipt — incluí-lo tornaria todo fingerprint
 * único e mataria a detecção de conflito), `recorded_by`, `issued_at` e o
 * `restrictionId` derivado — todos server-owned.
 */
export function fingerprintIssueIntent(intent: RestrictionIssueIntent): string {
  return stableStringify({
    kind: RESTRICTION_ISSUE_KIND,
    dogId: intent.dogId,
    level: intent.level,
    category: intent.category,
    description: intent.description,
    // Ordem preservada: a lista é semanticamente ordenada pelo emissor.
    activitiesRestricted: [...intent.activitiesRestricted],
    expectedEnd: intent.expectedEndIso,
    professional: {
      name: intent.professional.name,
      registration_type: intent.professional.registration_type,
      registration_number: intent.professional.registration_number,
      clinic: intent.professional.clinic,
      specialty: intent.professional.specialty,
    },
    sourceDocument: {
      health_document_id: intent.sourceDocument.health_document_id,
      description: intent.sourceDocument.description,
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt e decisão de criação
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptMatch = "replay" | "idempotency-conflict" | "missing";

/**
 * Receipt malformado ≠ ausente: fail-closed, nunca "missing".
 *
 * `kind` e `operationType` são parâmetros porque ISSUE, END e CANCEL têm
 * receipts distintos e NÃO podem ser interpretados um pelo outro. Um receipt
 * de END lido por CANCEL (mesmo `operationId`) é violação de integridade, não
 * replay — ver `RESTRICTION_*_KIND`.
 */
export function assertReceiptShapeOf(
  data: JsonMap,
  kind: string,
  operationType: string,
): void {
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
  if (stringValue(data.kind) !== kind) {
    throw logicError(
      "integrity",
      `Receipt de kind/version incompatível com ${kind}.`,
    );
  }
  if (stringValue(data.operation_type) !== operationType) {
    throw logicError("integrity", "Receipt de operation_type incompatível.");
  }
}

/** Receipt do ISSUE (B1). */
export function assertReceiptShape(data: JsonMap): void {
  assertReceiptShapeOf(data, RESTRICTION_ISSUE_KIND, RESTRICTION_ISSUE_OPERATION);
}

/** Replay só quando actor + operation_type + fingerprint batem TODOS. */
export function matchReceiptOf(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly actorUid: string;
  readonly fingerprint: string;
  readonly operationType: string;
}): ReceiptMatch {
  if (!params.receiptExists) return "missing";
  if (params.storedActorUid !== params.actorUid) {
    return "idempotency-conflict";
  }
  if (params.storedOperationType !== params.operationType) {
    return "idempotency-conflict";
  }
  if (params.storedFingerprint !== params.fingerprint) {
    return "idempotency-conflict";
  }
  return "replay";
}

export function matchIssueReceipt(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly actorUid: string;
  readonly fingerprint: string;
}): ReceiptMatch {
  return matchReceiptOf({...params, operationType: RESTRICTION_ISSUE_OPERATION});
}

export type IssueDecision =
  | {readonly kind: "create"}
  | {readonly kind: "replay"}
  | {
      readonly kind: "error";
      readonly code: AppErrorCode;
      readonly message: string;
    };

/**
 * Decisão canônica do ISSUE.
 *
 * "Restrição existe SEM receipt" é estado impossível dentro do protocolo —
 * receipt e agregado são escritos na MESMA transação. Se aparecer, é
 * corrupção, bypass ou escrita manual, e a operação para em vez de assumir
 * replay (o que sobrescreveria autoridade operacional de origem desconhecida).
 */
export function decideIssue(params: {
  readonly receiptMatch: ReceiptMatch;
  readonly restrictionExists: boolean;
}): IssueDecision {
  if (params.receiptMatch === "replay") return {kind: "replay"};
  if (params.receiptMatch === "idempotency-conflict") {
    return {
      kind: "error",
      code: "idempotency-conflict",
      message:
        "Mesma idempotencyKey com intenção diferente da emissão original.",
    };
  }
  if (params.restrictionExists) {
    return {
      kind: "error",
      code: "integrity",
      message:
        "OperationalRestriction já existe sem receipt correspondente: " +
        "violação de invariante do protocolo de emissão.",
    };
  }
  return {kind: "create"};
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

export interface IssueReceiptResult {
  readonly dogId: string;
  readonly restrictionId: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle terminal — END / CANCEL (B2)
//
// Dois comandos de domínio SEPARADOS. Ambos terminam alterando `status`, mas as
// autoridades, as provas exigidas e as afirmações feitas pelo usuário são
// diferentes (ADR-005 E12), então não existe writer genérico de status.
// ─────────────────────────────────────────────────────────────────────────────

/** Discriminadores versionados — load-bearing: END e CANCEL nunca se replayam. */
export const RESTRICTION_END_KIND = "health_operational_restriction_end_v1";
export const RESTRICTION_CANCEL_KIND =
  "health_operational_restriction_cancel_v1";

export const RESTRICTION_END_OPERATION = "release_restriction";
export const RESTRICTION_CANCEL_OPERATION = "cancel_restriction";

export const MAX_REASON_LEN = 2000;

/** Estados terminais: nunca reabrem (ADR-005 E12). */
export const RESTRICTION_STATUS_ACTIVE = "active";
export const RESTRICTION_STATUS_ENDED = "ended";
export const RESTRICTION_STATUS_CANCELLED = "cancelled";

/** Razão é parte material da transição: obrigatória, não derivada. */
export function assertReason(raw: unknown, label: string): string {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", `${label} é obrigatório.`);
  if (value.length > MAX_REASON_LEN) {
    throw logicError("validation", `${label} excede o tamanho máximo.`);
  }
  return value;
}

export function canonicalRestrictionOperationPath(
  dogId: string,
  restrictionId: string,
  operationId: string,
): string {
  return `${canonicalRestrictionPath(dogId, restrictionId)}/operations/${operationId}`;
}

export interface RestrictionEndIntent {
  readonly dogId: string;
  readonly restrictionId: string;
  readonly endReason: string;
  readonly endProfessional: ProfessionalIdentity;
  readonly endSourceDocument: HealthDocumentRefValue;
}

/**
 * Fingerprint da intenção de END.
 *
 * Inclui só o payload material do cliente. Fora: `actual_end`, `ended_by` e
 * qualquer timestamp gerado pela operação — todos server-owned, e incluí-los
 * tornaria cada retry um fingerprint novo.
 */
export function fingerprintEndIntent(intent: RestrictionEndIntent): string {
  return stableStringify({
    kind: RESTRICTION_END_KIND,
    dogId: intent.dogId,
    restrictionId: intent.restrictionId,
    endReason: intent.endReason,
    endProfessional: {
      name: intent.endProfessional.name,
      registration_type: intent.endProfessional.registration_type,
      registration_number: intent.endProfessional.registration_number,
      clinic: intent.endProfessional.clinic,
      specialty: intent.endProfessional.specialty,
    },
    endSourceDocument: {
      health_document_id: intent.endSourceDocument.health_document_id,
      description: intent.endSourceDocument.description,
    },
  });
}

export interface RestrictionCancelIntent {
  readonly dogId: string;
  readonly restrictionId: string;
  readonly cancelReason: string;
}

/** Fingerprint da intenção de CANCEL — sem professional, sem documento. */
export function fingerprintCancelIntent(
  intent: RestrictionCancelIntent,
): string {
  return stableStringify({
    kind: RESTRICTION_CANCEL_KIND,
    dogId: intent.dogId,
    restrictionId: intent.restrictionId,
    cancelReason: intent.cancelReason,
  });
}

export function assertEndReceiptShape(data: JsonMap): void {
  assertReceiptShapeOf(data, RESTRICTION_END_KIND, RESTRICTION_END_OPERATION);
}

export function assertCancelReceiptShape(data: JsonMap): void {
  assertReceiptShapeOf(
    data,
    RESTRICTION_CANCEL_KIND,
    RESTRICTION_CANCEL_OPERATION,
  );
}

export function matchEndReceipt(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly actorUid: string;
  readonly fingerprint: string;
}): ReceiptMatch {
  return matchReceiptOf({...params, operationType: RESTRICTION_END_OPERATION});
}

export function matchCancelReceipt(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly actorUid: string;
  readonly fingerprint: string;
}): ReceiptMatch {
  return matchReceiptOf({
    ...params,
    operationType: RESTRICTION_CANCEL_OPERATION,
  });
}

export type TerminalDecision =
  | {readonly kind: "transition"}
  | {readonly kind: "replay"}
  | {
      readonly kind: "error";
      readonly code: AppErrorCode;
      readonly message: string;
    };

/**
 * Decisão canônica das transições terminais.
 *
 * Ordem load-bearing: o RECEIPT é a autoridade de replay idempotente e é
 * consultado ANTES do status. Sem isso, um retry legítimo da MESMA operação
 * veria a restrição já terminal e receberia conflito espúrio.
 *
 * Só depois o status decide: apenas `active` transiciona. Restrição já terminal
 * por OUTRA operação é `conflict` — terminal nunca reabre (ADR-005 E12), e a
 * segunda transição concorrente perde aqui.
 */
export function decideTerminalTransition(params: {
  readonly receiptMatch: ReceiptMatch;
  readonly restrictionExists: boolean;
  readonly currentStatus: string | undefined;
}): TerminalDecision {
  if (params.receiptMatch === "replay") return {kind: "replay"};
  if (params.receiptMatch === "idempotency-conflict") {
    return {
      kind: "error",
      code: "idempotency-conflict",
      message:
        "Mesma idempotencyKey com intenção diferente da operação original.",
    };
  }
  if (!params.restrictionExists) {
    return {
      kind: "error",
      code: "not-found",
      message: "Restrição operacional não encontrada.",
    };
  }
  const status = stringValue(params.currentStatus);
  if (!status) {
    return {
      kind: "error",
      code: "integrity",
      message: "Restrição sem status legível: recusando transição.",
    };
  }
  if (status === RESTRICTION_STATUS_ACTIVE) return {kind: "transition"};
  if (
    status === RESTRICTION_STATUS_ENDED ||
    status === RESTRICTION_STATUS_CANCELLED
  ) {
    return {
      kind: "error",
      code: "conflict",
      message:
        `Restrição já está em estado terminal (${status}): ` +
        "estados terminais não reabrem.",
    };
  }
  return {
    kind: "error",
    code: "integrity",
    message: `Status não suportado para transição: ${status}.`,
  };
}

/**
 * Exclusividade de metadata terminal — invariante load-bearing.
 *
 * Um agregado nunca pode carregar os dois conjuntos: `ended` com metadata de
 * cancel, ou `cancelled` com metadata de end, seria um terminal híbrido sem
 * significado clínico. A restrição `active` produzida pelo B1 naturalmente não
 * tem nenhum dos dois, então esta checagem só falha diante de corrupção.
 */
export const END_METADATA_FIELDS = [
  "actual_end",
  "ended_by",
  "end_reason",
  "end_professional",
  "end_source_document",
] as const;

export const CANCEL_METADATA_FIELDS = [
  "cancelled_at",
  "cancelled_by",
  "cancel_reason",
] as const;

export function assertNoTerminalMetadata(
  current: JsonMap,
  fields: readonly string[],
  label: string,
): void {
  for (const field of fields) {
    const value = current[field];
    if (value !== undefined && value !== null) {
      throw logicError(
        "integrity",
        `Restrição ativa já carrega metadata de ${label} (${field}): ` +
          "recusando produzir agregado terminal híbrido.",
      );
    }
  }
}
