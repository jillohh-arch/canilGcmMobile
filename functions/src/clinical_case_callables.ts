/**
 * Clinical persisted authority — CASE OPEN + EVENT APPEND writer foundation
 * (CLIN-WRITER-1.W3).
 *
 * FIRST server-side write authority over the canonical clinical record. Admin
 * SDK (bypasses Rules); client writes on every clinical level stay permanently
 * DENY (`allow create, update, delete: if false`). A capability authorizes a
 * BACKEND callable command here — never a direct Firestore client write.
 *
 * Two operations, both narrow:
 *
 *   healthOpenClinicalCase   — creates a ClinicalCase AND its opening
 *                              ClinicalEvent atomically, in ONE transaction. A
 *                              ClinicalCase never exists without its opening
 *                              event.
 *   healthAppendClinicalEvent — appends a further ClinicalEvent to an EXISTING,
 *                              non-terminal ClinicalCase.
 *
 * Events always begin in the initial `draft` state; the case begins `open`.
 * There is NO finalize / cancel / amend / discharge / reopen here — those are
 * later gates. Terminal cases (`discharged`, `cancelled`) reject appends
 * fail-closed via the frozen `isTerminalCaseStatus`; this is a read-only
 * precondition, not a lifecycle transition.
 *
 * Identity is SERVER-DERIVED and never trusted from the payload: `dog_id`,
 * `case_id`, `event_id`, `entity_kind`, `schema_version`, `status`,
 * `recorded_at`, `updated_at`, `recorded_by`, `opened_at`, `opened_by`,
 * `opening_event_id`. Any attempt to override one is rejected before any write.
 *
 * Every ClinicalEvent is born carrying `updated_at` — the canonical
 * optimistic-concurrency token (CLIN-WRITER-1.W4.P0), equal to `recorded_at` at
 * creation. This writer never ADVANCES the token, because it never mutates an
 * existing event: replay returns the original result untouched. Advancing it is
 * the responsibility of each future mutation command.
 *
 * Idempotency mirrors the HealthDocument protocol: a non-empty `operationId`
 * keys a durable receipt; same op + same intent replays with zero duplicate
 * fact/audit; same op + different intent is `idempotency-conflict`
 * (failed-precondition), NEVER `already-exists`. IDs are deterministic and
 * replay-stable. Receipt + deterministic audit are written in the SAME
 * transaction as the fact, reads before writes.
 */

import * as crypto from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  ClinicalDomainError,
  isTerminalCaseStatus,
  parseClinicalCaseOpeningType,
  parseClinicalCaseStatus,
  parseClinicalEventType,
} from "./clinical_domain";
import {
  AppErrorCode,
  JsonMap,
  assertDogId,
  logicError,
  normalizeOperationId,
  optionalInstant,
  recordedByPayload,
  stableStringify,
  stringValue,
} from "./health_document_logic";

// ─────────────────────────────────────────────────────────────────────────────
// Canonical constants
// ─────────────────────────────────────────────────────────────────────────────

/** Schema version of both canonical clinical aggregates written here. */
export const CLINICAL_SCHEMA_VERSION = 1;

/**
 * Server-managed constant discriminator of a ClinicalEvent document.
 *
 * Frozen by the schema as SERVER origin: it is emitted here and NEVER accepted
 * from a payload, so a forged `entity_kind` cannot make a foreign document look
 * like a clinical event.
 */
export const CLINICAL_EVENT_ENTITY_KIND = "clinical_event";

/** Initial lifecycle states. Neither is caller-selectable. */
export const CLINICAL_CASE_INITIAL_STATUS = "open";
export const CLINICAL_EVENT_INITIAL_STATUS = "draft";

/** Receipt kinds/operations — distinct per command, so receipts never alias. */
export const CLINICAL_CASE_OPEN_KIND = "clinical_case_open_v1";
export const CLINICAL_CASE_OPEN_OPERATION = "open_clinical_case";
export const CLINICAL_EVENT_APPEND_KIND = "clinical_event_append_v1";
export const CLINICAL_EVENT_APPEND_OPERATION = "append_clinical_event";

export const MAX_CASE_TITLE_LEN = 200;
export const MAX_REASON_LEN = 2000;
export const MAX_ID_LEN = 128;
/** Bounded to keep a single event document well inside the 1 MiB limit. */
export const MAX_CONTENT_BYTES = 64 * 1024;
export const MAX_CONTENT_KEYS = 100;
export const MAX_ATTACHMENT_REFS = 50;

/**
 * Closed payload_type vocabulary — mirror of the Dart `PayloadType` wire values
 * (`lib/features/health/domain/health_v1_enums_ext.dart`).
 *
 * Closed on purpose: `payload_type` selects the CONTRACT of `content`, so an
 * open vocabulary would let a caller persist clinical content no reader can
 * interpret. Not in `clinical_domain.ts` because W1 froze that module's surface;
 * this is the writer's boundary validation, not a domain state machine.
 */
export const CLINICAL_PAYLOAD_TYPES = [
  "consultation_v1",
  "incident_v1",
  "vaccination_v1",
  "exam_request_v1",
  "exam_collection_v1",
  "exam_result_v1",
  "exam_interpretation_v1",
  "treatment_start_v1",
  "treatment_note_v1",
  "dose_note_v1",
  "reevaluation_v1",
  "discharge_v1",
  "reopen_v1",
  "restriction_issued_v1",
  "restriction_ended_v1",
  "surgical_note_v1",
  "general_note_v1",
  "observation_v1",
] as const;

export type ClinicalPayloadType = typeof CLINICAL_PAYLOAD_TYPES[number];

// ─────────────────────────────────────────────────────────────────────────────
// Seams
// ─────────────────────────────────────────────────────────────────────────────

export interface ClinicalCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface ClinicalCaseCallableDeps {
  db: FirebaseFirestore.Firestore;
  /**
   * MUST enforce `health.record_clinical` EXPLICITLY.
   *
   * `health.read` must never imply write, and technical administration must
   * never imply clinical authority — the wiring supplies the no-admin-bypass
   * path, exactly as the restriction lifecycle does.
   */
  requireRecordClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<ClinicalCaller>;
  /** Structural dog scope — the existing canonical fail-closed helper. */
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: ClinicalCaller,
    dogId: string,
    dog: JsonMap,
  ) => Promise<void>;
  /**
   * AUDIT CLASSIFICATION ONLY (`recorded_by.internal_role`). Never authority —
   * the distinction is load-bearing and mirrors GATE-C.B.
   */
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: ClinicalCaller,
  ) => Promise<boolean>;
  /** Single server-side time reference for the operation. */
  now?: () => Date;
}

// ─────────────────────────────────────────────────────────────────────────────
// Error transport
// ─────────────────────────────────────────────────────────────────────────────

type HttpCode =
  | "invalid-argument"
  | "not-found"
  | "permission-denied"
  | "failed-precondition"
  | "unauthenticated"
  | "internal";

function appError(http: HttpCode, code: AppErrorCode, message: string): never {
  throw new HttpsError(http, message, {code});
}

/** Structural check: `instanceof` is unreliable under dual package hazard. */
function isHttpsError(err: unknown): err is HttpsError {
  if (!err || typeof err !== "object") return false;
  const e = err as {name?: string; code?: string; httpErrorCode?: unknown};
  return (
    e.name === "HttpsError" ||
    (typeof e.code === "string" && e.httpErrorCode !== undefined)
  );
}

/**
 * Maps every internal fault class onto a stable transport identity.
 *
 * The two DOMAIN classes frozen by `clinical_domain.ts` are mapped here — the
 * module deliberately carries no transport dependency, so this is the single
 * place the decision is made:
 *
 *   invalid_value       → invalid-argument   (the input is not acceptable)
 *   illegal_transition  → failed-precondition (state does not permit it)
 *
 * Anything unrecognised degrades to `internal` WITHOUT leaking its message, so
 * a raw TypeError or an internal detail never reaches a client.
 */
function mapClinicalError(err: unknown): never {
  if (isHttpsError(err)) throw err;

  if (err instanceof ClinicalDomainError) {
    const message = err.message || "Operação clínica rejeitada.";
    if (err.kind === "invalid_value") {
      appError("invalid-argument", "validation", message);
    }
    appError("failed-precondition", "conflict", message);
  }

  const e = err as Error & {appCode?: AppErrorCode};
  const code = e.appCode;
  const message = e.message || "Falha na operação clínica.";
  switch (code) {
  case "validation":
    appError("invalid-argument", code, message);
    break;
  case "permission-denied":
    appError("permission-denied", code, message);
    break;
  case "not-found":
    appError("not-found", code, message);
    break;
  case "unauthenticated":
    appError("unauthenticated", code, message);
    break;
  case "conflict":
  case "idempotency-conflict":
  case "integrity":
    appError("failed-precondition", code, message);
    break;
  default:
    // No message pass-through: an unclassified throw is not a client contract.
    appError("internal", "unexpected", "Falha inesperada na operação clínica.");
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payload validation
// ─────────────────────────────────────────────────────────────────────────────

function isPlainObject(value: unknown): value is JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Fields that are SERVER-managed identity or lifecycle.
 *
 * Presence of ANY of them is rejected — silently ignoring them would let a
 * caller believe they had set `status: "final"` or a forged `recorded_by`.
 * Both snake_case and camelCase are listed because the callable boundary
 * accepts mixed clients.
 */
const FORBIDDEN_PAYLOAD_KEYS = [
  "id",
  "dog_id",
  "dogId_",
  "case_id",
  "caseId_",
  "event_id",
  "eventId",
  "entity_kind",
  "entityKind",
  "schema_version",
  "schemaVersion",
  "status",
  "clinical_status",
  "clinicalStatus",
  "recorded_at",
  "recordedAt",
  "recorded_by",
  "recordedBy",
  "opened_at",
  "openedAt",
  "opened_by",
  "openedBy",
  "opening_event_id",
  "openingEventId",
  "finalized_at",
  "finalizedAt",
  "cancelled_at",
  "cancelledAt",
  "cancelled_by",
  "cancelledBy",
  "cancel_reason",
  "cancelReason",
  "closed_at",
  "closedAt",
  "closed_by",
  "closedBy",
  "closure_type",
  "closureType",
  "closure_reason",
  "closureReason",
  "reopen_reason",
  "reopenReason",
  "reopened_at",
  "reopenedAt",
  "reopened_by",
  "reopenedBy",
  "previous_status",
  "previousStatus",
  "reopened_count",
  "reopenedCount",
  "has_amendments",
  "hasAmendments",
  "amendment_count",
  "amendmentCount",
  "last_amended_at",
  "lastAmendedAt",
  "updated_at",
  "updatedAt",
  "deleted_at",
  "deletedAt",
  "deleted_by",
  "deletedBy",
  "delete_reason",
  "deleteReason",
  "migration_batch_id",
  "migrationBatchId",
  "legacy_source",
  "legacySource",
  "legacy_id",
  "legacyId",
  "has_active_restriction",
  "hasActiveRestriction",
  "has_pending_schedule",
  "hasPendingSchedule",
  "active_treatments_count",
  "activeTreatmentsCount",
  "last_event_at",
  "lastEventAt",
  "event_count",
  "eventCount",
  "actor",
  "source",
] as const;

function rejectServerManagedInjection(data: JsonMap): void {
  for (const key of FORBIDDEN_PAYLOAD_KEYS) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      throw logicError(
        "validation",
        `Campo server-managed não permitido no payload: ${key}.`,
      );
    }
  }
}

function assertText(raw: unknown, label: string, maxLen: number): string {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", `${label} é obrigatório.`);
  if (value.length > maxLen) {
    throw logicError("validation", `${label} excede o tamanho máximo.`);
  }
  return value;
}

/** Path-segment-safe id supplied by the caller (an EXISTING case id). */
function assertPathId(raw: unknown, label: string): string {
  const value = stringValue(raw);
  if (!value) throw logicError("validation", `${label} é obrigatório.`);
  if (
    value.length > MAX_ID_LEN ||
    value === "." ||
    value === ".." ||
    value.includes("/") ||
    value.includes("\\")
  ) {
    throw logicError("validation", `${label} inválido.`);
  }
  return value;
}

function parsePayloadType(raw: unknown): ClinicalPayloadType {
  const value = stringValue(raw);
  if (
    value !== undefined &&
    (CLINICAL_PAYLOAD_TYPES as readonly string[]).includes(value)
  ) {
    return value as ClinicalPayloadType;
  }
  throw logicError(
    "validation",
    `payload_type inválido: ${JSON.stringify(raw)}. ` +
      `Valores aceitos: ${CLINICAL_PAYLOAD_TYPES.join(", ")}`,
  );
}

function parsePayloadVersion(raw: unknown): number {
  if (raw === undefined || raw === null) return 1;
  if (
    typeof raw !== "number" ||
    !Number.isInteger(raw) ||
    raw < 1 ||
    raw > 1000
  ) {
    throw logicError("validation", "payload_version inválido.");
  }
  return raw;
}

/**
 * Validates clinical `content` structurally, not semantically.
 *
 * Per-`payload_type` field contracts are NOT enforced here: that catalog is
 * documentation-level today and inventing it would be architecture this gate
 * has no authority to freeze. What IS enforced: it is a non-empty plain map,
 * bounded in size, JSON-serialisable, and free of prototype-polluting or
 * undefined-valued keys (Firestore rejects `undefined`).
 */
function assertContent(raw: unknown): JsonMap {
  if (!isPlainObject(raw)) {
    throw logicError("validation", "content é obrigatório e deve ser um mapa.");
  }
  const keys = Object.keys(raw);
  if (keys.length === 0) {
    throw logicError("validation", "content não pode ser vazio.");
  }
  if (keys.length > MAX_CONTENT_KEYS) {
    throw logicError("validation", "content excede o número máximo de campos.");
  }
  for (const key of keys) {
    if (key === "__proto__" || key === "constructor" || key === "prototype") {
      throw logicError("validation", `content contém chave inválida: ${key}.`);
    }
    if (raw[key] === undefined) {
      throw logicError(
        "validation",
        `content.${key} é undefined; envie null ou omita o campo.`,
      );
    }
  }
  let serialized: string;
  try {
    serialized = stableStringify(raw);
  } catch {
    throw logicError("validation", "content não é serializável.");
  }
  if (Buffer.byteLength(serialized, "utf8") > MAX_CONTENT_BYTES) {
    throw logicError("validation", "content excede o tamanho máximo.");
  }
  return raw;
}

/** `attachment_refs` carries HealthDocument IDs — never URLs. */
function assertAttachmentRefs(raw: unknown): string[] | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (!Array.isArray(raw)) {
    throw logicError("validation", "attachment_refs deve ser uma lista.");
  }
  if (raw.length > MAX_ATTACHMENT_REFS) {
    throw logicError("validation", "attachment_refs excede o máximo.");
  }
  const refs: string[] = [];
  for (const item of raw) {
    const value = stringValue(item);
    if (!value) {
      throw logicError("validation", "attachment_refs contém item vazio.");
    }
    if (value.length > MAX_ID_LEN || value.includes("://")) {
      throw logicError(
        "validation",
        "attachment_refs aceita apenas IDs de HealthDocument, não URLs.",
      );
    }
    refs.push(value);
  }
  return refs;
}

/** Optional external `ProfessionalIdentity` (PII). Author != professional. */
function assertProfessional(raw: unknown): JsonMap | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (!isPlainObject(raw)) {
    throw logicError("validation", "professional deve ser um mapa.");
  }
  const name = assertText(raw.name, "professional.name", MAX_CASE_TITLE_LEN);
  const professional: JsonMap = {name};
  const allowed: Array<[string, string]> = [
    ["registration_type", "registrationType"],
    ["registration_number", "registrationNumber"],
    ["clinic", "clinic"],
  ];
  for (const [snake, camel] of allowed) {
    const value = stringValue(raw[snake] ?? raw[camel]);
    if (value !== undefined) {
      if (value.length > MAX_CASE_TITLE_LEN) {
        throw logicError("validation", `professional.${snake} muito longo.`);
      }
      professional[snake] = value;
    }
  }
  return professional;
}

/** `occurred_at` is CLIENT-supplied clinical time, but must not be in the future. */
function assertOccurredAt(raw: unknown, now: Date): Date {
  const parsed = optionalInstant(raw, "occurred_at");
  if (parsed === undefined) {
    throw logicError("validation", "occurred_at é obrigatório.");
  }
  // Small tolerance for client clock skew; a far-future clinical fact is a bug.
  const skewMs = 5 * 60 * 1000;
  if (parsed.getTime() > now.getTime() + skewMs) {
    throw logicError("validation", "occurred_at não pode estar no futuro.");
  }
  return parsed;
}

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic identity
// ─────────────────────────────────────────────────────────────────────────────

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

/**
 * Identity material — derives ONLY from kind + structural scope + operationId.
 *
 * No clock, no random, no content: a retry of the same logical operation must
 * reproduce the same id. Actor is deliberately excluded so that two actors
 * reusing one operationId COLLIDE on the same id and are resolved as an
 * explicit conflict by the receipt gate, instead of silently creating a
 * duplicate clinical fact.
 */
export function caseIdentityMaterial(dogId: string, operationId: string): string {
  return `${CLINICAL_CASE_OPEN_KIND}|${dogId}|${operationId}`;
}

export function eventIdentityMaterial(
  dogId: string,
  caseId: string,
  operationId: string,
): string {
  return `${CLINICAL_EVENT_APPEND_KIND}|${dogId}|${caseId}|${operationId}`;
}

export function deterministicCaseId(hashHex: string): string {
  return `cc_${hashHex.slice(0, 28)}`;
}

export function deterministicEventId(hashHex: string): string {
  return `ce_${hashHex.slice(0, 28)}`;
}

/**
 * The opening event id is derived from the CASE identity, not independently.
 *
 * Consequence: case and opening event are one identity pair, so a replay of
 * case-open reproduces both ids and cannot orphan or duplicate either.
 */
export function openingEventIdFor(caseId: string): string {
  return deterministicEventId(sha256Hex(`opening_event|${caseId}`));
}

export function canonicalCasePath(dogId: string, caseId: string): string {
  return `dogs/${dogId}/clinical_cases/${caseId}`;
}

export function canonicalEventPath(
  dogId: string,
  caseId: string,
  eventId: string,
): string {
  return `${canonicalCasePath(dogId, caseId)}/clinical_events/${eventId}`;
}

/** Citable reference — identity only, no copied metadata. */
export function clinicalCaseRef(caseId: string): JsonMap {
  return {clinical_case_id: caseId};
}

export function clinicalEventRef(caseId: string, eventId: string): JsonMap {
  return {clinical_case_id: caseId, clinical_event_id: eventId};
}

// ─────────────────────────────────────────────────────────────────────────────
// Intent fingerprints
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fingerprint of the CLIENT's intent.
 *
 * Contains only caller-controlled business payload. Deliberately EXCLUDED:
 * `operationId` (it is the receipt key — including it would make every
 * fingerprint unique and destroy conflict detection) and every server-derived
 * field. Absent optionals normalise to `null`, so "omitted" and "explicit null"
 * are the same intent rather than two.
 */
export function fingerprintOpenCaseIntent(intent: {
  readonly dogId: string;
  readonly title: string;
  readonly openingType: string;
  readonly eventType: string;
  readonly occurredAtIso: string;
  readonly payloadType: string;
  readonly payloadVersion: number;
  readonly content: JsonMap;
  readonly professional: JsonMap | null;
  readonly attachmentRefs: readonly string[] | null;
}): string {
  return sha256Hex(
    [
      CLINICAL_CASE_OPEN_KIND,
      intent.dogId,
      intent.title,
      intent.openingType,
      intent.eventType,
      intent.occurredAtIso,
      intent.payloadType,
      String(intent.payloadVersion),
      stableStringify(intent.content),
      stableStringify(intent.professional),
      stableStringify(intent.attachmentRefs),
    ].join("|"),
  );
}

export function fingerprintAppendEventIntent(intent: {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventType: string;
  readonly occurredAtIso: string;
  readonly payloadType: string;
  readonly payloadVersion: number;
  readonly content: JsonMap;
  readonly professional: JsonMap | null;
  readonly attachmentRefs: readonly string[] | null;
}): string {
  return sha256Hex(
    [
      CLINICAL_EVENT_APPEND_KIND,
      intent.dogId,
      intent.caseId,
      intent.eventType,
      intent.occurredAtIso,
      intent.payloadType,
      String(intent.payloadVersion),
      stableStringify(intent.content),
      stableStringify(intent.professional),
      stableStringify(intent.attachmentRefs),
    ].join("|"),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipts
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptMatch = "replay" | "idempotency-conflict" | "missing";

/**
 * A receipt that exists but is unreadable is CORRUPTION, not "missing".
 *
 * Treating it as missing would let the writer create a second clinical fact for
 * an operation that already produced one.
 */
export function assertClinicalReceiptShape(
  data: JsonMap,
  expectedKind: string,
  expectedOperation: string,
): void {
  for (const key of [
    "kind",
    "operation_id",
    "operation_type",
    "actor_uid",
    "fingerprint",
    "result",
  ]) {
    const value = data[key];
    if (value === undefined || value === null || value === "") {
      throw logicError(
        "integrity",
        `Receipt clínico malformado: campo obrigatório ausente (${key}).`,
      );
    }
  }
  if (stringValue(data.kind) !== expectedKind) {
    throw logicError(
      "integrity",
      `Receipt clínico de kind/version incompatível com ${expectedKind}.`,
    );
  }
  if (stringValue(data.operation_type) !== expectedOperation) {
    throw logicError(
      "integrity",
      "Receipt clínico de operation_type incompatível.",
    );
  }
}

export function matchClinicalReceipt(params: {
  readonly receiptExists: boolean;
  readonly storedActorUid?: string;
  readonly storedOperationType?: string;
  readonly storedFingerprint?: string;
  readonly expectedOperationType: string;
  readonly actorUid: string;
  readonly fingerprint: string;
}): ReceiptMatch {
  if (!params.receiptExists) return "missing";
  if (params.storedActorUid !== params.actorUid) return "idempotency-conflict";
  if (params.storedOperationType !== params.expectedOperationType) {
    return "idempotency-conflict";
  }
  if (params.storedFingerprint !== params.fingerprint) {
    return "idempotency-conflict";
  }
  return "replay";
}

function receiptPayload(params: {
  kind: string;
  operationType: string;
  operationId: string;
  actorUid: string;
  fingerprint: string;
  result: JsonMap;
}): JsonMap {
  return {
    kind: params.kind,
    operation_id: params.operationId,
    operation_type: params.operationType,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    result: params.result,
    processed_at: FieldValue.serverTimestamp(),
  };
}

/** Deterministic audit id: one logical audit per operation, never duplicated. */
function auditDocId(
  operation: string,
  dogId: string,
  caseId: string,
  eventId: string,
  operationId: string,
): string {
  const h = sha256Hex(
    `${operation}|${dogId}|${caseId}|${eventId}|${operationId}`,
  );
  return `clin_audit_${h.slice(0, 40)}`;
}

function auditLogPayload(params: {
  action: string;
  caller: ClinicalCaller;
  entityType: string;
  entityId: string;
  entityPath: string;
  summary: string;
  metadata: JsonMap;
}): JsonMap {
  const now = FieldValue.serverTimestamp();
  return {
    action: params.action,
    entity_type: params.entityType,
    entity_id: params.entityId,
    entity_path: params.entityPath,
    summary: params.summary,
    actor: {
      uid: params.caller.uid,
      email: params.caller.email,
      ra: params.caller.ra,
      name: params.caller.name,
    },
    metadata: params.metadata,
    source: "functions",
    performed_at: now,
    createdAt: now,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Refs
// ─────────────────────────────────────────────────────────────────────────────

function caseRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("clinical_cases")
    .doc(caseId);
}

function eventRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  eventId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("clinical_events").doc(eventId);
}

/**
 * Operation receipts live UNDER the case.
 *
 * That keeps the durable idempotency proof inside the same aggregate the
 * operation wrote, so it shares the aggregate's read authority instead of
 * needing a separate top-level collection with its own Rules surface.
 */
function caseOperationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("operations").doc(operationId);
}

async function loadDog(
  db: FirebaseFirestore.Firestore,
  dogId: string,
): Promise<JsonMap> {
  const snap = await db.collection("dogs").doc(dogId).get();
  if (!snap.exists) {
    throw logicError("not-found", "K9 não encontrado.");
  }
  return (snap.data() ?? {}) as JsonMap;
}

// ─────────────────────────────────────────────────────────────────────────────
// Event document construction
// ─────────────────────────────────────────────────────────────────────────────

interface EventFacts {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
  readonly eventType: string;
  readonly occurredAt: Date;
  readonly payloadType: ClinicalPayloadType;
  readonly payloadVersion: number;
  readonly content: JsonMap;
  readonly professional?: JsonMap;
  readonly attachmentRefs?: string[];
}

/**
 * Builds the canonical ClinicalEvent document.
 *
 * Every SERVER-origin field is written from arguments derived here or from the
 * authenticated caller — none can be reached by the payload. `status` is always
 * the initial `draft`: this writer has no finalize authority.
 *
 * `has_amendments`/`amendment_count` are seeded because the schema marks them
 * REQUIRED and server-managed; a reader must never have to treat their absence
 * as "unknown".
 *
 * `updated_at` is the canonical optimistic-concurrency authority of the
 * ClinicalEvent (CLIN-WRITER-1.W4.P0). Every event is BORN with it — equal to
 * `recorded_at`, from the same server Timestamp — so that a mutation command can
 * always compare a caller's `expectedUpdatedAt` against a field that provably
 * exists. An event created without the token could never be safely mutated.
 */
function clinicalEventDocument(
  facts: EventFacts,
  caller: ClinicalCaller,
  isAdmin: boolean,
  recordedAt: Timestamp,
): JsonMap {
  const record: JsonMap = {
    dog_id: facts.dogId,
    case_id: facts.caseId,
    entity_kind: CLINICAL_EVENT_ENTITY_KIND,
    event_type: facts.eventType,
    status: CLINICAL_EVENT_INITIAL_STATUS,
    occurred_at: Timestamp.fromDate(facts.occurredAt),
    recorded_at: recordedAt,
    // Same Timestamp instance as `recorded_at`: on creation the two are the
    // same fact, and no mutation has happened yet.
    updated_at: recordedAt,
    recorded_by: recordedByPayload(caller, isAdmin),
    payload_type: facts.payloadType,
    payload_version: facts.payloadVersion,
    content: facts.content,
    has_amendments: false,
    amendment_count: 0,
    schema_version: CLINICAL_SCHEMA_VERSION,
  };
  if (facts.professional !== undefined) {
    record.professional = facts.professional;
  }
  if (facts.attachmentRefs !== undefined) {
    record.attachment_refs = facts.attachmentRefs;
  }
  return record;
}

// ─────────────────────────────────────────────────────────────────────────────
// OPEN CLINICAL CASE
// ─────────────────────────────────────────────────────────────────────────────

interface ParsedOpenCaseInput {
  readonly dogId: string;
  readonly operationId: string;
  readonly title: string;
  readonly openingType: string;
  readonly eventType: string;
  readonly occurredAt: Date;
  readonly payloadType: ClinicalPayloadType;
  readonly payloadVersion: number;
  readonly content: JsonMap;
  readonly professional?: JsonMap;
  readonly attachmentRefs?: string[];
}

function parseOpenCaseInput(data: JsonMap, now: Date): ParsedOpenCaseInput {
  return {
    dogId: assertDogId(data.dogId ?? data.dog_id),
    operationId: normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    ),
    title: assertText(data.title, "title", MAX_CASE_TITLE_LEN),
    // Frozen domain parsers: unknown wire value is a rejected input, never
    // silently stored (`unknown_case_opening_type` / `unknown_event_type`).
    openingType: parseClinicalCaseOpeningType(
      data.openingType ?? data.opening_type,
    ),
    eventType: parseClinicalEventType(data.eventType ?? data.event_type),
    occurredAt: assertOccurredAt(data.occurredAt ?? data.occurred_at, now),
    payloadType: parsePayloadType(data.payloadType ?? data.payload_type),
    payloadVersion: parsePayloadVersion(
      data.payloadVersion ?? data.payload_version,
    ),
    content: assertContent(data.content),
    professional: assertProfessional(data.professional),
    attachmentRefs: assertAttachmentRefs(
      data.attachmentRefs ?? data.attachment_refs,
    ),
  };
}

function openCaseResponse(params: {
  dogId: string;
  caseId: string;
  eventId: string;
  wasNoOp: boolean;
}): JsonMap {
  const {dogId, caseId, eventId, wasNoOp} = params;
  return {
    dog_id: dogId,
    case_id: caseId,
    opening_event_id: eventId,
    reference: clinicalCaseRef(caseId),
    was_no_op: wasNoOp,
    // camelCase mirror — Agenda parity for mixed clients.
    dogId,
    caseId,
    openingEventId: eventId,
    wasNoOp,
  };
}

/**
 * Opens a ClinicalCase together with its opening ClinicalEvent, atomically.
 *
 * The case and its opening event are written in ONE transaction with the
 * receipt and the audit: four documents, all or nothing. A ClinicalCase can
 * therefore never be observed without the event that opened it, which is what
 * makes `opening_event_id` a trustworthy reference instead of a hopeful one.
 */
export async function runHealthOpenClinicalCase(
  request: CallableRequest,
  deps: ClinicalCaseCallableDeps,
): Promise<JsonMap> {
  try {
    // Capability FIRST: no work happens for an unauthorised caller.
    const caller = await deps.requireRecordClinical(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerManagedInjection(data);

    const nowDate = (deps.now ?? (() => new Date()))();
    const input = parseOpenCaseInput(data, nowDate);
    const {dogId, operationId} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    // Identity ALWAYS recomputed server-side — never from the client.
    const caseId = deterministicCaseId(
      sha256Hex(caseIdentityMaterial(dogId, operationId)),
    );
    const eventId = openingEventIdFor(caseId);

    const fingerprint = fingerprintOpenCaseIntent({
      dogId,
      title: input.title,
      openingType: input.openingType,
      eventType: input.eventType,
      occurredAtIso: input.occurredAt.toISOString(),
      payloadType: input.payloadType,
      payloadVersion: input.payloadVersion,
      content: input.content,
      professional: input.professional ?? null,
      attachmentRefs: input.attachmentRefs ?? null,
    });

    const cRef = caseRef(deps.db, dogId, caseId);
    const eRef = eventRef(deps.db, dogId, caseId, eventId);
    const opRef = caseOperationRef(deps.db, dogId, caseId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocId(
          CLINICAL_CASE_OPEN_OPERATION,
          dogId,
          caseId,
          eventId,
          operationId,
        ),
      );

    const recordedAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      // ALL reads before ANY write.
      const [caseSnap, eventSnap, opSnap] = await Promise.all([
        tx.get(cRef),
        tx.get(eRef),
        tx.get(opRef),
      ]);

      let match: ReceiptMatch = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertClinicalReceiptShape(
          stored,
          CLINICAL_CASE_OPEN_KIND,
          CLINICAL_CASE_OPEN_OPERATION,
        );
        match = matchClinicalReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          expectedOperationType: CLINICAL_CASE_OPEN_OPERATION,
          actorUid: caller.uid,
          fingerprint,
        });
      }

      if (match === "idempotency-conflict") {
        // failed-precondition, NOT already-exists: the operation key was reused
        // with a different intent, which is a caller bug, not a race.
        throw logicError(
          "idempotency-conflict",
          "Mesma operationId com intenção diferente da abertura original.",
        );
      }
      if (match === "replay") {
        // Zero duplicate fact, zero duplicate audit.
        return openCaseResponse({dogId, caseId, eventId, wasNoOp: true});
      }

      // No receipt, but the aggregate exists: an impossible protocol state.
      // Fail closed rather than overwrite clinical evidence of unknown origin.
      if (caseSnap.exists || eventSnap.exists) {
        throw logicError(
          "integrity",
          "Caso/evento clínico existe sem receipt da operação: " +
            "recusando sobrescrever evidência clínica.",
        );
      }

      const caseDocument: JsonMap = {
        clinical_status: CLINICAL_CASE_INITIAL_STATUS,
        title: input.title,
        opened_at: recordedAt,
        opened_by: recordedByPayload(caller, isAdmin),
        opening_event_id: eventId,
        opening_type: input.openingType,
        recorded_by: recordedByPayload(caller, isAdmin),
        reopened_count: 0,
        event_count: 1,
        last_event_at: recordedAt,
        schema_version: CLINICAL_SCHEMA_VERSION,
      };
      if (input.professional !== undefined) {
        caseDocument.primary_professional = input.professional;
      }

      const eventDocument = clinicalEventDocument(
        {
          dogId,
          caseId,
          eventId,
          eventType: input.eventType,
          occurredAt: input.occurredAt,
          payloadType: input.payloadType,
          payloadVersion: input.payloadVersion,
          content: input.content,
          professional: input.professional,
          attachmentRefs: input.attachmentRefs,
        },
        caller,
        isAdmin,
        recordedAt,
      );

      tx.set(cRef, caseDocument);
      tx.set(eRef, eventDocument);
      tx.set(
        opRef,
        receiptPayload({
          kind: CLINICAL_CASE_OPEN_KIND,
          operationType: CLINICAL_CASE_OPEN_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, caseId, eventId},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload({
          action: "clinical_case_opened",
          caller,
          entityType: "clinical_cases",
          entityId: caseId,
          entityPath: canonicalCasePath(dogId, caseId),
          summary: `Caso clínico aberto para K9 ${dogId}`,
          metadata: {
            dog_id: dogId,
            case_id: caseId,
            opening_event_id: eventId,
            operation_id: operationId,
            opening_type: input.openingType,
            event_type: input.eventType,
            payload_type: input.payloadType,
            clinical_status: CLINICAL_CASE_INITIAL_STATUS,
            event_status: CLINICAL_EVENT_INITIAL_STATUS,
          },
        }),
      );

      return openCaseResponse({dogId, caseId, eventId, wasNoOp: false});
    });
  } catch (err) {
    mapClinicalError(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPEND CLINICAL EVENT
// ─────────────────────────────────────────────────────────────────────────────

interface ParsedAppendEventInput {
  readonly dogId: string;
  readonly caseId: string;
  readonly operationId: string;
  readonly eventType: string;
  readonly occurredAt: Date;
  readonly payloadType: ClinicalPayloadType;
  readonly payloadVersion: number;
  readonly content: JsonMap;
  readonly professional?: JsonMap;
  readonly attachmentRefs?: string[];
}

function parseAppendEventInput(
  data: JsonMap,
  now: Date,
): ParsedAppendEventInput {
  return {
    dogId: assertDogId(data.dogId ?? data.dog_id),
    caseId: assertPathId(data.caseId ?? data.case_id, "caseId"),
    operationId: normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    ),
    eventType: parseClinicalEventType(data.eventType ?? data.event_type),
    occurredAt: assertOccurredAt(data.occurredAt ?? data.occurred_at, now),
    payloadType: parsePayloadType(data.payloadType ?? data.payload_type),
    payloadVersion: parsePayloadVersion(
      data.payloadVersion ?? data.payload_version,
    ),
    content: assertContent(data.content),
    professional: assertProfessional(data.professional),
    attachmentRefs: assertAttachmentRefs(
      data.attachmentRefs ?? data.attachment_refs,
    ),
  };
}

function appendEventResponse(params: {
  dogId: string;
  caseId: string;
  eventId: string;
  wasNoOp: boolean;
}): JsonMap {
  const {dogId, caseId, eventId, wasNoOp} = params;
  return {
    dog_id: dogId,
    case_id: caseId,
    event_id: eventId,
    reference: clinicalEventRef(caseId, eventId),
    was_no_op: wasNoOp,
    dogId,
    caseId,
    eventId,
    wasNoOp,
  };
}

/**
 * Appends a ClinicalEvent to an existing ClinicalCase.
 *
 * The case must EXIST and must not be terminal. "Terminal" is read from the
 * frozen domain authority (`isTerminalCaseStatus`), so this writer does not
 * hold a second opinion about the lifecycle. Note what this is NOT: no case
 * transition happens here. `clinical_status` is untouched; only the derived
 * counters (`event_count`, `last_event_at`) advance, and they are server-managed
 * by definition.
 *
 * A persisted `clinical_status` outside the frozen vocabulary is treated as
 * corruption and fails closed — appending to a case whose state cannot be
 * interpreted would be writing into an unknown lifecycle.
 */
export async function runHealthAppendClinicalEvent(
  request: CallableRequest,
  deps: ClinicalCaseCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireRecordClinical(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerManagedInjection(data);

    const nowDate = (deps.now ?? (() => new Date()))();
    const input = parseAppendEventInput(data, nowDate);
    const {dogId, caseId, operationId} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const eventId = deterministicEventId(
      sha256Hex(eventIdentityMaterial(dogId, caseId, operationId)),
    );

    const fingerprint = fingerprintAppendEventIntent({
      dogId,
      caseId,
      eventType: input.eventType,
      occurredAtIso: input.occurredAt.toISOString(),
      payloadType: input.payloadType,
      payloadVersion: input.payloadVersion,
      content: input.content,
      professional: input.professional ?? null,
      attachmentRefs: input.attachmentRefs ?? null,
    });

    const cRef = caseRef(deps.db, dogId, caseId);
    const eRef = eventRef(deps.db, dogId, caseId, eventId);
    const opRef = caseOperationRef(deps.db, dogId, caseId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocId(
          CLINICAL_EVENT_APPEND_OPERATION,
          dogId,
          caseId,
          eventId,
          operationId,
        ),
      );

    const recordedAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      const [caseSnap, eventSnap, opSnap] = await Promise.all([
        tx.get(cRef),
        tx.get(eRef),
        tx.get(opRef),
      ]);

      let match: ReceiptMatch = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertClinicalReceiptShape(
          stored,
          CLINICAL_EVENT_APPEND_KIND,
          CLINICAL_EVENT_APPEND_OPERATION,
        );
        match = matchClinicalReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          expectedOperationType: CLINICAL_EVENT_APPEND_OPERATION,
          actorUid: caller.uid,
          fingerprint,
        });
      }

      if (match === "idempotency-conflict") {
        throw logicError(
          "idempotency-conflict",
          "Mesma operationId com intenção diferente do evento original.",
        );
      }
      if (match === "replay") {
        return appendEventResponse({dogId, caseId, eventId, wasNoOp: true});
      }

      // An event may only exist inside a real case.
      if (!caseSnap.exists) {
        throw logicError("not-found", "Caso clínico não encontrado.");
      }

      if (eventSnap.exists) {
        throw logicError(
          "integrity",
          "Evento clínico existe sem receipt da operação: " +
            "recusando sobrescrever evidência clínica.",
        );
      }

      const caseData = (caseSnap.data() ?? {}) as JsonMap;
      // Throws `unknown_case_status` (invalid_value → invalid-argument) when the
      // persisted status is outside the frozen vocabulary. Never coerced.
      const currentStatus = parseClinicalCaseStatus(caseData.clinical_status);
      if (isTerminalCaseStatus(currentStatus)) {
        throw logicError(
          "conflict",
          `Caso clínico ${currentStatus} não aceita novos eventos.`,
        );
      }

      const eventDocument = clinicalEventDocument(
        {
          dogId,
          caseId,
          eventId,
          eventType: input.eventType,
          occurredAt: input.occurredAt,
          payloadType: input.payloadType,
          payloadVersion: input.payloadVersion,
          content: input.content,
          professional: input.professional,
          attachmentRefs: input.attachmentRefs,
        },
        caller,
        isAdmin,
        recordedAt,
      );

      tx.set(eRef, eventDocument);
      // Derived counters only. `clinical_status` is deliberately NOT in this
      // patch: appending an event is not a lifecycle transition.
      tx.set(
        cRef,
        {event_count: FieldValue.increment(1), last_event_at: recordedAt},
        {merge: true},
      );
      tx.set(
        opRef,
        receiptPayload({
          kind: CLINICAL_EVENT_APPEND_KIND,
          operationType: CLINICAL_EVENT_APPEND_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, caseId, eventId},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload({
          action: "clinical_event_appended",
          caller,
          entityType: "clinical_events",
          entityId: eventId,
          entityPath: canonicalEventPath(dogId, caseId, eventId),
          summary: `Evento clínico registrado no caso ${caseId} do K9 ${dogId}`,
          metadata: {
            dog_id: dogId,
            case_id: caseId,
            event_id: eventId,
            operation_id: operationId,
            event_type: input.eventType,
            payload_type: input.payloadType,
            event_status: CLINICAL_EVENT_INITIAL_STATUS,
            case_status: currentStatus,
          },
        }),
      );

      return appendEventResponse({dogId, caseId, eventId, wasNoOp: false});
    });
  } catch (err) {
    mapClinicalError(err);
  }
}
