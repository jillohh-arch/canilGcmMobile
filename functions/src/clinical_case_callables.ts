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
  assertEventTransition,
  isTerminalCaseStatus,
  parseClinicalCaseOpeningType,
  parseClinicalCaseStatus,
  parseClinicalEventStatus,
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
export const CLINICAL_EVENT_FINALIZE_KIND = "clinical_event_finalize_v1";
export const CLINICAL_EVENT_FINALIZE_OPERATION = "finalize_clinical_event";
export const CLINICAL_EVENT_CANCEL_KIND = "clinical_event_cancel_v1";
export const CLINICAL_EVENT_CANCEL_OPERATION = "cancel_clinical_event";
export const CLINICAL_EVENT_AMEND_KIND = "clinical_event_amend_v1";
export const CLINICAL_EVENT_AMEND_OPERATION = "amend_clinical_event";

/**
 * Frozen amendment type vocabulary (schema §2.3, ADR-002).
 *
 * Closed like `payload_type`: the type states WHY the original record needed a
 * causal complement, and a reader composing the record must be able to interpret
 * every value it encounters.
 */
export const CLINICAL_AMENDMENT_TYPES = [
  "correction",
  "addendum",
  "complement",
] as const;

export type ClinicalAmendmentType = typeof CLINICAL_AMENDMENT_TYPES[number];

/** Only status from which an amendment may be created (ADR-002 §Rules). */
export const CLINICAL_AMENDABLE_EVENT_STATUS = "final";

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
  /**
   * MUST enforce `health.finalize_clinical` EXPLICITLY.
   *
   * A SEPARATE seam from `requireRecordClinical` on purpose: recording a draft
   * and latching it into immutable clinical evidence are different authorities,
   * so `health.record_clinical` must never imply finalisation.
   */
  requireFinalizeClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<ClinicalCaller>;
  /**
   * MUST enforce `health.amend_clinical` EXPLICITLY.
   *
   * Cancelling is the corrective authority over an existing clinical record,
   * which is why it keys on amendment rather than on recording or finalisation.
   *
   * SHARED with amendment creation (W5) on purpose: `health.amend_clinical` is
   * the single corrective authority in the W2 catalogue. Sharing the capability
   * does NOT merge the commands — each keeps its own request vocabulary, receipt
   * kind, fingerprint, audit action and business semantics. A second seam is
   * deliberately NOT introduced: it would let a test assert a state that cannot
   * exist in production (one allowed while the other is denied).
   */
  requireAmendClinical: (
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
  // P0 froze `finalized_by` as NON-EXISTENT in ClinicalEvent v1. Rejecting it at
  // the boundary means a client that believes the field exists is corrected
  // loudly, instead of having it silently dropped and assuming it was stored.
  "finalized_by",
  "finalizedBy",
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

/**
 * `allowedSelectors` narrowly exempts keys that are TARGET IDENTITY for the
 * command being executed, never persisted content.
 *
 * The creation writers exempt nothing: they DERIVE `eventId` deterministically,
 * so a caller supplying one is trying to choose where a new clinical fact lands.
 * A mutation command is the opposite case — it must name the event it acts on,
 * and refusing `eventId` there would make the command unaddressable.
 *
 * The snake_case `event_id` stays forbidden for every command, including
 * mutations: that is the AT-REST server-managed field, and accepting it would let
 * a caller rewrite the stored identity of the document it is mutating.
 */
function rejectServerManagedInjection(
  data: JsonMap,
  allowedSelectors: readonly string[] = [],
): void {
  for (const key of FORBIDDEN_PAYLOAD_KEYS) {
    if (allowedSelectors.includes(key)) continue;
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      throw logicError(
        "validation",
        `Campo server-managed não permitido no payload: ${key}.`,
      );
    }
  }
}

/** The ONLY key a ClinicalEvent mutation command may add to the W3 baseline. */
const EVENT_MUTATION_SELECTORS = ["eventId"] as const;

/**
 * Cancel additionally accepts the camelCase `cancelReason` as declared INPUT.
 *
 * The snake_case `cancel_reason` remains forbidden: that is the persisted field,
 * and the server writes it from the validated, trimmed input. Accepting both
 * would give a caller two ways to state the reason, only one of which is
 * validated.
 */
const EVENT_CANCEL_INPUTS = ["eventId", "cancelReason"] as const;

/**
 * CLOSED key vocabulary of a ClinicalEvent mutation command.
 *
 * A mutation is validated by ALLOWLIST, not by blocklist. The blocklist protects
 * server-managed fields, but it cannot protect a field that is legitimate
 * INPUT elsewhere: `content`, `professional` and `attachmentRefs` are valid on
 * creation, so a blocklist would silently accept them here and let a caller
 * believe a finalisation had rewritten clinical content. Since finalize and
 * cancel accept no replacement payload at all, anything outside this set is a
 * misunderstanding of the command and is rejected before any read.
 */
const EVENT_MUTATION_ALLOWED_KEYS = [
  "dogId",
  "dog_id",
  "caseId",
  "case_id",
  "eventId",
  "operationId",
  "operation_id",
  "idempotencyKey",
  "expectedUpdatedAt",
  "expected_updated_at",
] as const;

function rejectUnknownMutationKeys(
  data: JsonMap,
  extraAllowed: readonly string[] = [],
): void {
  for (const key of Object.keys(data)) {
    if (EVENT_MUTATION_ALLOWED_KEYS.includes(key as never)) continue;
    if (extraAllowed.includes(key)) continue;
    throw logicError(
      "validation",
      `Campo não aceito por um comando de mutação clínica: ${key}.`,
    );
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

/**
 * The caller's optimistic-concurrency token, as frozen by CLIN-WRITER-1.W4.P0.
 *
 * Epoch MILLISECONDS, matching the hardened access-profile writer convention.
 * Absence and malformation are both `invalid-argument`: the request itself is
 * unusable, which is a different fault from a well-formed token that lost the
 * race (`failed-precondition`). Collapsing the two would tell a client to
 * "reload and retry" when the real problem is that it never sent a token.
 */
function assertExpectedUpdatedAt(raw: unknown): number {
  if (raw === undefined || raw === null) {
    throw logicError(
      "validation",
      "expectedUpdatedAt é obrigatório para mutar um evento clínico.",
    );
  }
  if (
    typeof raw !== "number" ||
    !Number.isFinite(raw) ||
    !Number.isInteger(raw) ||
    raw < 0
  ) {
    throw logicError(
      "validation",
      "expectedUpdatedAt deve ser epoch em milissegundos (number).",
    );
  }
  return raw;
}

/**
 * Reads the STORED concurrency authority off a ClinicalEvent.
 *
 * A canonical event is BORN with `updated_at` (P0), so a stored event without a
 * readable Timestamp is CORRUPTION, not a legacy shape to be tolerated. Failing
 * closed here is what stops a mutation from proceeding with no precondition at
 * all. `recorded_at`, `finalized_at`, `snapshot.updateTime` and the client clock
 * are deliberately NOT fallbacks — each would silently restore the stale-write
 * hole the token exists to close.
 */
function storedUpdatedAtMillis(event: JsonMap): number {
  const raw = event.updated_at as {toMillis?: unknown} | undefined;
  if (
    raw === undefined ||
    raw === null ||
    typeof raw.toMillis !== "function"
  ) {
    throw logicError(
      "integrity",
      "Evento clínico sem updated_at canônico: " +
        "recarregue o evento antes de mutar.",
    );
  }
  const millis = (raw.toMillis as () => unknown)();
  if (typeof millis !== "number" || !Number.isFinite(millis)) {
    throw logicError(
      "integrity",
      "Evento clínico com updated_at ilegível.",
    );
  }
  return millis;
}

/** Stale precondition. NEVER retried automatically: the caller must re-read. */
function assertFreshToken(storedMillis: number, expected: number): void {
  if (storedMillis !== expected) {
    throw logicError(
      "conflict",
      "Evento clínico alterado por outra operação. " +
        "Recarregue antes de mutar.",
    );
  }
}

/** `cancelReason` is the only clinical content a cancellation may carry. */
function assertCancelReason(raw: unknown): string {
  if (raw === undefined || raw === null) {
    throw logicError("validation", "cancelReason é obrigatório.");
  }
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw logicError("validation", "cancelReason não pode ser vazio.");
  }
  if (raw.length > MAX_REASON_LEN) {
    throw logicError("validation", "cancelReason muito longo.");
  }
  return raw.trim();
}

/** Frozen amendment vocabulary (§2.3). Unknown values are never coerced. */
function parseAmendmentType(raw: unknown): ClinicalAmendmentType {
  const value = stringValue(raw);
  if (!value) {
    throw logicError("validation", "amendmentType é obrigatório.");
  }
  if (!(CLINICAL_AMENDMENT_TYPES as readonly string[]).includes(value)) {
    throw logicError(
      "validation",
      `amendmentType inválido: "${value}". Valores aceitos: ` +
        `${CLINICAL_AMENDMENT_TYPES.join(", ")}.`,
    );
  }
  return value as ClinicalAmendmentType;
}

/**
 * The amendment's justification. REQUIRED by the frozen schema.
 *
 * An amendment without a stated reason would be indistinguishable from a silent
 * rewrite of the record, which is exactly what the immutability model exists to
 * prevent.
 */
function assertAmendmentReason(raw: unknown): string {
  if (raw === undefined || raw === null) {
    throw logicError("validation", "reason é obrigatório.");
  }
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw logicError("validation", "reason não pode ser vazio.");
  }
  if (raw.length > MAX_REASON_LEN) {
    throw logicError("validation", "reason muito longo.");
  }
  return raw.trim();
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
 * Amendment identity material.
 *
 * Keyed on the PARENT EVENT plus the operationId, so a network retry of the same
 * amendment reproduces the same id and cannot create a second causal fact. The
 * caller never chooses it.
 */
export function amendmentIdentityMaterial(
  dogId: string,
  caseId: string,
  eventId: string,
  operationId: string,
): string {
  return `${CLINICAL_EVENT_AMEND_KIND}|${dogId}|${caseId}|${eventId}|${operationId}`;
}

export function deterministicAmendmentId(hashHex: string): string {
  return `ca_${hashHex.slice(0, 28)}`;
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

export function canonicalAmendmentPath(
  dogId: string,
  caseId: string,
  eventId: string,
  amendmentId: string,
): string {
  return (
    `${canonicalEventPath(dogId, caseId, eventId)}` +
    `/clinical_amendments/${amendmentId}`
  );
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

export function clinicalAmendmentRef(
  caseId: string,
  eventId: string,
  amendmentId: string,
): JsonMap {
  return {
    clinical_case_id: caseId,
    clinical_event_id: eventId,
    clinical_amendment_id: amendmentId,
  };
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

/**
 * Fingerprint of a FINALIZE intent.
 *
 * `expectedUpdatedAt` is deliberately EXCLUDED. A legitimate network retry of an
 * already-applied finalisation still carries the pre-mutation token, so
 * including it would make the replay look like a different intent and raise a
 * spurious `idempotency-conflict` for an operation that already succeeded. The
 * token is a precondition on the CURRENT state, not part of what was requested.
 */
export function fingerprintFinalizeEventIntent(intent: {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
}): string {
  return sha256Hex(
    [
      CLINICAL_EVENT_FINALIZE_KIND,
      intent.dogId,
      intent.caseId,
      intent.eventId,
    ].join("|"),
  );
}

/**
 * Fingerprint of a CANCEL intent.
 *
 * Includes the trimmed reason — cancelling the same event for a DIFFERENT stated
 * reason under the same `operationId` is a genuine intent divergence and must
 * surface as `idempotency-conflict`, not silently replay the first reason.
 * `expectedUpdatedAt` is excluded for the same reason as in finalize.
 */
export function fingerprintCancelEventIntent(intent: {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
  readonly cancelReason: string;
}): string {
  return sha256Hex(
    [
      CLINICAL_EVENT_CANCEL_KIND,
      intent.dogId,
      intent.caseId,
      intent.eventId,
      intent.cancelReason,
    ].join("|"),
  );
}

/**
 * Fingerprint of an AMEND intent.
 *
 * Includes every caller-controlled business input: the target event, the
 * amendment type, the normalized reason and the canonical amendment content.
 * Amending the same event twice under one `operationId` with different content is
 * a genuine intent divergence and must surface as `idempotency-conflict` rather
 * than silently replaying the first correction.
 *
 * `content` goes through `stableStringify`, so a map with the same entries in a
 * different insertion order is the SAME logical intent — otherwise a client that
 * merely reserialised its payload would be told its retry conflicted.
 *
 * `expectedUpdatedAt` is excluded, exactly as in finalize/cancel: it is a
 * precondition on current state, not part of what was requested.
 */
export function fingerprintAmendEventIntent(intent: {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
  readonly amendmentType: string;
  readonly reason: string;
  readonly content: JsonMap;
}): string {
  return sha256Hex(
    [
      CLINICAL_EVENT_AMEND_KIND,
      intent.dogId,
      intent.caseId,
      intent.eventId,
      intent.amendmentType,
      intent.reason,
      stableStringify(intent.content),
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
 * Amendments live UNDER the ClinicalEvent they correct.
 *
 * `clinical_amendments`, never the historical `amendments`: W1b renamed it to
 * escape the collection-group collision with the occurrences domain, and no
 * alias is retained.
 */
function amendmentRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  eventId: string,
  amendmentId: string,
): FirebaseFirestore.DocumentReference {
  return eventRef(db, dogId, caseId, eventId)
    .collection("clinical_amendments")
    .doc(amendmentId);
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
        updated_at: recordedAt,
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
        {
          event_count: FieldValue.increment(1),
          last_event_at: recordedAt,
          updated_at: recordedAt,
        },
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

// ─────────────────────────────────────────────────────────────────────────────
// EVENT MUTATION — shared identity and integrity
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Command identity common to every ClinicalEvent mutation.
 *
 * Narrow BY DESIGN: a mutation command names the event and proves which version
 * of it the caller saw. It carries no replacement clinical payload, so there is
 * no code path by which a caller could rewrite finalised evidence.
 */
interface ParsedEventMutationInput {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
  readonly operationId: string;
  readonly expectedUpdatedAt: number;
}

function parseEventMutationInput(data: JsonMap): ParsedEventMutationInput {
  return {
    dogId: assertDogId(data.dogId ?? data.dog_id),
    caseId: assertPathId(data.caseId ?? data.case_id, "caseId"),
    eventId: assertPathId(data.eventId ?? data.event_id, "eventId"),
    operationId: normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    ),
    expectedUpdatedAt: assertExpectedUpdatedAt(
      data.expectedUpdatedAt ?? data.expected_updated_at,
    ),
  };
}

function eventMutationResponse(params: {
  dogId: string;
  caseId: string;
  eventId: string;
  status: string;
  wasNoOp: boolean;
}): JsonMap {
  const {dogId, caseId, eventId, status, wasNoOp} = params;
  return {
    dog_id: dogId,
    case_id: caseId,
    event_id: eventId,
    status,
    reference: clinicalEventRef(caseId, eventId),
    was_no_op: wasNoOp,
    dogId,
    caseId,
    eventId,
    wasNoOp,
  };
}

/**
 * Structural integrity of a stored ClinicalEvent about to be mutated.
 *
 * Every check FAILS CLOSED. Corrupt clinical evidence is never repaired in
 * passing: an event whose identity does not match the path it was found at, or
 * whose `schema_version` this writer does not understand, is refused rather than
 * normalised, because a mutation would then be persisting an interpretation the
 * server cannot justify.
 */
function assertStoredEventIntegrity(
  event: JsonMap,
  dogId: string,
  caseId: string,
): void {
  if (stringValue(event.entity_kind) !== CLINICAL_EVENT_ENTITY_KIND) {
    throw logicError(
      "integrity",
      "Documento não é um ClinicalEvent canônico.",
    );
  }
  if (stringValue(event.dog_id) !== dogId) {
    throw logicError(
      "integrity",
      "ClinicalEvent com dog_id divergente do caminho canônico.",
    );
  }
  if (stringValue(event.case_id) !== caseId) {
    throw logicError(
      "integrity",
      "ClinicalEvent com case_id divergente do caminho canônico.",
    );
  }
  if (event.schema_version !== CLINICAL_SCHEMA_VERSION) {
    throw logicError(
      "integrity",
      "ClinicalEvent de schema_version não suportada por este writer.",
    );
  }
}

/**
 * Reads the parent event's amendment counters, refusing corrupt values.
 *
 * The schema marks `has_amendments`/`amendment_count` REQUIRED and server-managed,
 * so a W3-born event always carries `false`/`0`. A non-boolean flag or a
 * non-integer/negative count is CORRUPTION: incrementing from it would persist a
 * count the server cannot justify, and silently coercing it to 0 would erase the
 * evidence that earlier amendments exist. Both fail closed.
 *
 * `last_amended_at` is optional (absent before the first amendment) but must be a
 * Timestamp when present.
 */
function assertAmendmentMetadataIntegrity(event: JsonMap): number {
  const flag = event.has_amendments;
  if (flag !== undefined && typeof flag !== "boolean") {
    throw logicError(
      "integrity",
      "ClinicalEvent com has_amendments corrompido.",
    );
  }
  const count = event.amendment_count;
  if (count !== undefined) {
    if (
      typeof count !== "number" ||
      !Number.isInteger(count) ||
      count < 0
    ) {
      throw logicError(
        "integrity",
        "ClinicalEvent com amendment_count corrompido.",
      );
    }
  }
  const last = event.last_amended_at as {toMillis?: unknown} | undefined;
  if (
    last !== undefined &&
    last !== null &&
    typeof last.toMillis !== "function"
  ) {
    throw logicError(
      "integrity",
      "ClinicalEvent com last_amended_at ilegível.",
    );
  }
  // A count without the flag (or vice versa) is an inconsistent aggregate.
  if (typeof count === "number" && count > 0 && flag === false) {
    throw logicError(
      "integrity",
      "ClinicalEvent com has_amendments inconsistente com amendment_count.",
    );
  }
  return typeof count === "number" ? count : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// FINALIZE CLINICAL EVENT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Latches a `draft` ClinicalEvent into immutable clinical evidence.
 *
 * THE immutability latch. After this returns, no writer in this module can
 * rewrite the event's clinical content — the only remaining transition is
 * cancellation, which appends metadata and preserves content.
 *
 * The mutation is an EXPLICIT three-field patch (`status`, `finalized_at`,
 * `updated_at`), never a spread of caller data, so the set of fields a
 * finalisation can touch is bounded by this function rather than by the request.
 * `finalized_by` does NOT exist in ClinicalEvent v1 (P0): the finalising actor
 * is provenance of the audit entry and the operation receipt.
 *
 * ORDER IS LOAD-BEARING: the receipt is inspected BEFORE the concurrency token.
 * A network retry of a request that already succeeded still carries the
 * pre-mutation token, so checking staleness first would reject an operation that
 * genuinely completed. Replay is decided on operation identity, not on state.
 *
 * Being already `final` is NOT idempotent. Only a same-operation receipt replays;
 * a NEW operationId targeting a `final` event is an illegal transition, because
 * "someone else already finalised this" is a different fact from "your request
 * was applied".
 */
export async function runHealthFinalizeClinicalEvent(
  request: CallableRequest,
  deps: ClinicalCaseCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireFinalizeClinical(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerManagedInjection(data, EVENT_MUTATION_SELECTORS);
    rejectUnknownMutationKeys(data);

    const nowDate = (deps.now ?? (() => new Date()))();
    const input = parseEventMutationInput(data);
    const {dogId, caseId, eventId, operationId, expectedUpdatedAt} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);

    const fingerprint = fingerprintFinalizeEventIntent({dogId, caseId, eventId});

    const eRef = eventRef(deps.db, dogId, caseId, eventId);
    const opRef = caseOperationRef(deps.db, dogId, caseId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocId(
          CLINICAL_EVENT_FINALIZE_OPERATION,
          dogId,
          caseId,
          eventId,
          operationId,
        ),
      );

    const finalizedAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      const [eventSnap, opSnap] = await Promise.all([
        tx.get(eRef),
        tx.get(opRef),
      ]);

      // ── 1. RECEIPT FIRST (replay / conflict), BEFORE any state check ──────
      let match: ReceiptMatch = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertClinicalReceiptShape(
          stored,
          CLINICAL_EVENT_FINALIZE_KIND,
          CLINICAL_EVENT_FINALIZE_OPERATION,
        );
        match = matchClinicalReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          expectedOperationType: CLINICAL_EVENT_FINALIZE_OPERATION,
          actorUid: caller.uid,
          fingerprint,
        });
      }

      if (match === "idempotency-conflict") {
        throw logicError(
          "idempotency-conflict",
          "Mesma operationId com intenção diferente da finalização original.",
        );
      }
      if (match === "replay") {
        return eventMutationResponse({
          dogId,
          caseId,
          eventId,
          status: "final",
          wasNoOp: true,
        });
      }

      // ── 2. only now: the event and its integrity ──────────────────────────
      if (!eventSnap.exists) {
        throw logicError("not-found", "Evento clínico não encontrado.");
      }
      const event = (eventSnap.data() ?? {}) as JsonMap;
      assertStoredEventIntegrity(event, dogId, caseId);

      // ── 3. concurrency precondition ───────────────────────────────────────
      assertFreshToken(storedUpdatedAtMillis(event), expectedUpdatedAt);

      // ── 4. transition legality, decided by the FROZEN domain authority ────
      const currentStatus = parseClinicalEventStatus(event.status);
      assertEventTransition(currentStatus, "final");

      // ── 5. atomic mutation + receipt + audit ──────────────────────────────
      // EXPLICIT fields only. `updated_at` carries the SAME Timestamp as
      // `finalized_at`: they are one fact.
      tx.set(
        eRef,
        {
          status: "final",
          finalized_at: finalizedAt,
          updated_at: finalizedAt,
        },
        {merge: true},
      );
      tx.set(
        opRef,
        receiptPayload({
          kind: CLINICAL_EVENT_FINALIZE_KIND,
          operationType: CLINICAL_EVENT_FINALIZE_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, caseId, eventId},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload({
          action: "clinical_event_finalized",
          caller,
          entityType: "clinical_events",
          entityId: eventId,
          entityPath: canonicalEventPath(dogId, caseId, eventId),
          summary:
            `Evento clínico finalizado no caso ${caseId} do K9 ${dogId}`,
          metadata: {
            dog_id: dogId,
            case_id: caseId,
            event_id: eventId,
            operation_id: operationId,
            previous_status: currentStatus,
            event_status: "final",
          },
        }),
      );

      return eventMutationResponse({
        dogId,
        caseId,
        eventId,
        status: "final",
        wasNoOp: false,
      });
    });
  } catch (err) {
    mapClinicalError(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CANCEL CLINICAL EVENT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Cancels a ClinicalEvent from `draft` or from `final`.
 *
 * Cancellation is NOT a content edit and NOT a delete. The original clinical
 * content, its authorship and its chronology all survive; what changes is the
 * status plus the cancellation metadata. `finalized_at` is deliberately absent
 * from the patch, so a `final → cancelled` event keeps the historical fact that
 * it was once finalised, and a `draft → cancelled` event never acquires one.
 *
 * `cancelled_by` is SERVER-derived from the authenticated caller via the same
 * `recordedByPayload` shape the creation writer uses, so authorship of a
 * cancellation is exactly as trustworthy as authorship of the record.
 *
 * Same replay-before-stale ordering as finalisation, and the same rule that
 * being already `cancelled` is not idempotent: `cancelled` is terminal in the
 * frozen domain, so a NEW operationId against it is an illegal transition.
 */
export async function runHealthCancelClinicalEvent(
  request: CallableRequest,
  deps: ClinicalCaseCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireAmendClinical(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerManagedInjection(data, EVENT_CANCEL_INPUTS);
    rejectUnknownMutationKeys(data, ["cancelReason"]);

    const nowDate = (deps.now ?? (() => new Date()))();
    const input = parseEventMutationInput(data);
    const {dogId, caseId, eventId, operationId, expectedUpdatedAt} = input;
    const cancelReason = assertCancelReason(
      data.cancelReason ?? data.cancel_reason,
    );

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const fingerprint = fingerprintCancelEventIntent({
      dogId,
      caseId,
      eventId,
      cancelReason,
    });

    const eRef = eventRef(deps.db, dogId, caseId, eventId);
    const opRef = caseOperationRef(deps.db, dogId, caseId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocId(
          CLINICAL_EVENT_CANCEL_OPERATION,
          dogId,
          caseId,
          eventId,
          operationId,
        ),
      );

    const cancelledAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      const [eventSnap, opSnap] = await Promise.all([
        tx.get(eRef),
        tx.get(opRef),
      ]);

      // ── 1. RECEIPT FIRST (replay / conflict), BEFORE any state check ──────
      let match: ReceiptMatch = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertClinicalReceiptShape(
          stored,
          CLINICAL_EVENT_CANCEL_KIND,
          CLINICAL_EVENT_CANCEL_OPERATION,
        );
        match = matchClinicalReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          expectedOperationType: CLINICAL_EVENT_CANCEL_OPERATION,
          actorUid: caller.uid,
          fingerprint,
        });
      }

      if (match === "idempotency-conflict") {
        throw logicError(
          "idempotency-conflict",
          "Mesma operationId com intenção diferente do cancelamento original.",
        );
      }
      if (match === "replay") {
        return eventMutationResponse({
          dogId,
          caseId,
          eventId,
          status: "cancelled",
          wasNoOp: true,
        });
      }

      // ── 2. only now: the event and its integrity ──────────────────────────
      if (!eventSnap.exists) {
        throw logicError("not-found", "Evento clínico não encontrado.");
      }
      const event = (eventSnap.data() ?? {}) as JsonMap;
      assertStoredEventIntegrity(event, dogId, caseId);

      // ── 3. concurrency precondition ───────────────────────────────────────
      assertFreshToken(storedUpdatedAtMillis(event), expectedUpdatedAt);

      // ── 4. transition legality + cancellation metadata completeness, both
      //       decided by the FROZEN domain authority in one call ─────────────
      const currentStatus = parseClinicalEventStatus(event.status);
      const cancelledBy = recordedByPayload(caller, isAdmin);
      const transition = assertEventTransition(currentStatus, "cancelled", {
        cancelReason,
        cancelledAt: nowDate,
        cancelledBy: {
          uid: caller.uid,
          name: stringValue(cancelledBy.name) ?? caller.uid,
          internalRole: stringValue(cancelledBy.internal_role) ?? "condutor",
        },
      });

      // ── 5. atomic mutation + receipt + audit ──────────────────────────────
      // EXPLICIT fields only. `finalized_at` is NOT in this patch: on
      // `final → cancelled` the stored value survives untouched, and on
      // `draft → cancelled` it must stay absent.
      tx.set(
        eRef,
        {
          status: "cancelled",
          cancel_reason: transition.cancellation?.cancelReason ?? cancelReason,
          cancelled_at: cancelledAt,
          cancelled_by: cancelledBy,
          updated_at: cancelledAt,
        },
        {merge: true},
      );
      tx.set(
        opRef,
        receiptPayload({
          kind: CLINICAL_EVENT_CANCEL_KIND,
          operationType: CLINICAL_EVENT_CANCEL_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, caseId, eventId},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload({
          action: "clinical_event_cancelled",
          caller,
          entityType: "clinical_events",
          entityId: eventId,
          entityPath: canonicalEventPath(dogId, caseId, eventId),
          summary:
            `Evento clínico cancelado no caso ${caseId} do K9 ${dogId}`,
          metadata: {
            dog_id: dogId,
            case_id: caseId,
            event_id: eventId,
            operation_id: operationId,
            previous_status: currentStatus,
            event_status: "cancelled",
            cancel_reason: cancelReason,
          },
        }),
      );

      return eventMutationResponse({
        dogId,
        caseId,
        eventId,
        status: "cancelled",
        wasNoOp: false,
      });
    });
  } catch (err) {
    mapClinicalError(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMEND CLINICAL EVENT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Closed key vocabulary of the amendment command.
 *
 * `content` IS accepted here — but it is the content of the NEW amendment
 * document, never a replacement for the parent event's content. The parent patch
 * below is an explicit metadata-only write, so the two can never be confused.
 */
const EVENT_AMEND_ALLOWED_KEYS = [
  "dogId",
  "dog_id",
  "caseId",
  "case_id",
  "eventId",
  "operationId",
  "operation_id",
  "idempotencyKey",
  "expectedUpdatedAt",
  "expected_updated_at",
  "amendmentType",
  "reason",
  "content",
] as const;

/** Selector + business inputs exempt from the server-managed blocklist. */
const EVENT_AMEND_INPUTS = [
  "eventId",
  "amendmentType",
  "reason",
  "content",
] as const;

function rejectUnknownAmendKeys(data: JsonMap): void {
  for (const key of Object.keys(data)) {
    if (EVENT_AMEND_ALLOWED_KEYS.includes(key as never)) continue;
    throw logicError(
      "validation",
      `Campo não aceito por um comando de emenda clínica: ${key}.`,
    );
  }
}

interface ParsedAmendInput {
  readonly dogId: string;
  readonly caseId: string;
  readonly eventId: string;
  readonly operationId: string;
  readonly expectedUpdatedAt: number;
  readonly amendmentType: ClinicalAmendmentType;
  readonly reason: string;
  readonly content: JsonMap;
}

function parseAmendInput(data: JsonMap): ParsedAmendInput {
  return {
    dogId: assertDogId(data.dogId ?? data.dog_id),
    caseId: assertPathId(data.caseId ?? data.case_id, "caseId"),
    eventId: assertPathId(data.eventId, "eventId"),
    operationId: normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    ),
    expectedUpdatedAt: assertExpectedUpdatedAt(
      data.expectedUpdatedAt ?? data.expected_updated_at,
    ),
    amendmentType: parseAmendmentType(data.amendmentType),
    reason: assertAmendmentReason(data.reason),
    content: assertContent(data.content),
  };
}

/**
 * Builds the canonical ClinicalAmendment document (schema §2.3).
 *
 * `payload_type`/`payload_version` are INHERITED from the parent event rather
 * than accepted from the caller: the schema requires them to equal the parent's,
 * and deriving them server-side removes the possibility of an amendment claiming
 * a contract its parent never had. `professional` does NOT exist in amendment v1
 * — it is deliberately absent rather than copied from the parent.
 */
function clinicalAmendmentDocument(
  input: ParsedAmendInput,
  parent: JsonMap,
  caller: ClinicalCaller,
  isAdmin: boolean,
  recordedAt: Timestamp,
): JsonMap {
  return {
    type: input.amendmentType,
    reason: input.reason,
    payload_type: parent.payload_type,
    payload_version: parent.payload_version,
    content: input.content,
    recorded_by: recordedByPayload(caller, isAdmin),
    recorded_at: recordedAt,
    schema_version: CLINICAL_SCHEMA_VERSION,
  };
}

function amendResponse(params: {
  dogId: string;
  caseId: string;
  eventId: string;
  amendmentId: string;
  amendmentCount: number;
  wasNoOp: boolean;
}): JsonMap {
  const {dogId, caseId, eventId, amendmentId, amendmentCount, wasNoOp} = params;
  return {
    dog_id: dogId,
    case_id: caseId,
    event_id: eventId,
    amendment_id: amendmentId,
    amendment_count: amendmentCount,
    reference: clinicalAmendmentRef(caseId, eventId, amendmentId),
    was_no_op: wasNoOp,
    dogId,
    caseId,
    eventId,
    amendmentId,
    amendmentCount,
    wasNoOp,
  };
}

/**
 * Appends an immutable correction/addendum/complement to a FINAL ClinicalEvent.
 *
 * THE consequence of the W4 immutability latch. A finalised clinical fact is
 * never rewritten: a correction becomes a SEPARATE causal document under
 * `clinical_amendments`, and the parent keeps `status: final` forever. There is
 * no "amended" state — `has_amendments` signals that complements exist
 * (ADR-002 §7).
 *
 * Eligibility is `final` ONLY. A `draft` is still editable through its own
 * pre-final workflow, so amending it would be a second, redundant path to the
 * same outcome; a `cancelled` event is terminal historical evidence and must not
 * accrue new clinical meaning.
 *
 * The parent write is metadata-only and explicit: `has_amendments`,
 * `amendment_count`, `last_amended_at`, `updated_at`. `status`, `finalized_at`,
 * `content`, `occurred_at` and every other clinical field are absent from the
 * patch by construction, so no amendment can alter the record it corrects.
 *
 * Amendments are CREATE-ONLY (ADR-002 §7.3): this module offers no update or
 * delete path, and correcting a previous amendment means writing another sibling
 * amendment against the same original event — never an amendment-of-amendment.
 *
 * Same replay-before-stale ordering as the other mutation commands.
 */
export async function runHealthAmendClinicalEvent(
  request: CallableRequest,
  deps: ClinicalCaseCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireAmendClinical(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerManagedInjection(data, EVENT_AMEND_INPUTS);
    rejectUnknownAmendKeys(data);

    const nowDate = (deps.now ?? (() => new Date()))();
    const input = parseAmendInput(data);
    const {dogId, caseId, eventId, operationId, expectedUpdatedAt} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const amendmentId = deterministicAmendmentId(
      sha256Hex(
        amendmentIdentityMaterial(dogId, caseId, eventId, operationId),
      ),
    );

    const fingerprint = fingerprintAmendEventIntent({
      dogId,
      caseId,
      eventId,
      amendmentType: input.amendmentType,
      reason: input.reason,
      content: input.content,
    });

    const eRef = eventRef(deps.db, dogId, caseId, eventId);
    const aRef = amendmentRef(deps.db, dogId, caseId, eventId, amendmentId);
    const opRef = caseOperationRef(deps.db, dogId, caseId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocId(
          CLINICAL_EVENT_AMEND_OPERATION,
          dogId,
          caseId,
          eventId,
          operationId,
        ),
      );

    const amendedAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      const [eventSnap, amendSnap, opSnap] = await Promise.all([
        tx.get(eRef),
        tx.get(aRef),
        tx.get(opRef),
      ]);

      // ── 1. RECEIPT FIRST (replay / conflict), BEFORE any state check ──────
      let match: ReceiptMatch = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertClinicalReceiptShape(
          stored,
          CLINICAL_EVENT_AMEND_KIND,
          CLINICAL_EVENT_AMEND_OPERATION,
        );
        match = matchClinicalReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          expectedOperationType: CLINICAL_EVENT_AMEND_OPERATION,
          actorUid: caller.uid,
          fingerprint,
        });
      }

      if (match === "idempotency-conflict") {
        throw logicError(
          "idempotency-conflict",
          "Mesma operationId com intenção diferente da emenda original.",
        );
      }
      if (match === "replay") {
        const stored = (eventSnap.data() ?? {}) as JsonMap;
        const count = typeof stored.amendment_count === "number" ?
          stored.amendment_count :
          0;
        return amendResponse({
          dogId,
          caseId,
          eventId,
          amendmentId,
          amendmentCount: count,
          wasNoOp: true,
        });
      }

      // ── 2. only now: the parent event and its integrity ───────────────────
      if (!eventSnap.exists) {
        throw logicError("not-found", "Evento clínico não encontrado.");
      }
      const event = (eventSnap.data() ?? {}) as JsonMap;
      assertStoredEventIntegrity(event, dogId, caseId);
      const currentCount = assertAmendmentMetadataIntegrity(event);

      // An amendment document existing without its receipt is corruption: the
      // deterministic id means only THIS operation could have written it.
      if (amendSnap.exists) {
        throw logicError(
          "integrity",
          "Emenda clínica existe sem receipt da operação: " +
            "recusando sobrescrever evidência clínica.",
        );
      }

      // ── 3. concurrency precondition ───────────────────────────────────────
      assertFreshToken(storedUpdatedAtMillis(event), expectedUpdatedAt);

      // ── 4. eligibility, decided against the FROZEN status vocabulary ──────
      const currentStatus = parseClinicalEventStatus(event.status);
      if (currentStatus !== CLINICAL_AMENDABLE_EVENT_STATUS) {
        throw logicError(
          "conflict",
          `Evento clínico ${currentStatus} não aceita emendas: ` +
            "somente um evento final pode ser emendado.",
        );
      }

      // The amendment inherits the parent's payload contract; a parent without
      // one cannot be described by an amendment.
      if (
        stringValue(event.payload_type) === undefined ||
        typeof event.payload_version !== "number"
      ) {
        throw logicError(
          "integrity",
          "Evento clínico sem payload_type/payload_version canônicos.",
        );
      }

      // ── 5. atomic amendment + parent metadata + receipt + audit ───────────
      tx.set(
        aRef,
        clinicalAmendmentDocument(input, event, caller, isAdmin, amendedAt),
      );
      // EXPLICIT metadata-only patch. `status`, `finalized_at` and every
      // clinical field are absent by construction: the parent stays `final` and
      // its content is untouched.
      // `amendment_count` is written as an EXPLICIT number, not
      // `FieldValue.increment(1)`. The transaction already read the current count
      // and validated it, and `expectedUpdatedAt` serialises competing mutations,
      // so there is no lost-update to defend against. An explicit value keeps the
      // stored count, the audit entry and the response provably equal — with a
      // sentinel, the server would report a number it never actually wrote.
      tx.set(
        eRef,
        {
          has_amendments: true,
          amendment_count: currentCount + 1,
          last_amended_at: amendedAt,
          updated_at: amendedAt,
        },
        {merge: true},
      );
      tx.set(
        opRef,
        receiptPayload({
          kind: CLINICAL_EVENT_AMEND_KIND,
          operationType: CLINICAL_EVENT_AMEND_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, caseId, eventId, amendmentId},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload({
          action: "clinical_event_amended",
          caller,
          entityType: "clinical_amendments",
          entityId: amendmentId,
          entityPath: canonicalAmendmentPath(
            dogId,
            caseId,
            eventId,
            amendmentId,
          ),
          summary:
            `Emenda clínica registrada no evento ${eventId} do K9 ${dogId}`,
          metadata: {
            dog_id: dogId,
            case_id: caseId,
            event_id: eventId,
            amendment_id: amendmentId,
            operation_id: operationId,
            amendment_type: input.amendmentType,
            reason: input.reason,
            event_status: currentStatus,
            amendment_count: currentCount + 1,
          },
        }),
      );

      return amendResponse({
        dogId,
        caseId,
        eventId,
        amendmentId,
        amendmentCount: currentCount + 1,
        wasNoOp: false,
      });
    });
  } catch (err) {
    mapClinicalError(err);
  }
}
