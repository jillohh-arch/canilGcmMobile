/**
 * Clinical server-domain parity — CLIN-WRITER-1.W1.
 *
 * PURE DOMAIN SLICE. This module is a byte-for-semantics mirror of the Dart
 * Clinical state machines so that a future backend writer can enforce the SAME
 * invariants the mobile domain already enforces, instead of re-deriving them.
 *
 * Dart authority mirrored here (do not diverge without a paired change):
 *   lib/features/health/domain/health_v1_enums.dart
 *     - `ClinicalCaseStatus`      + `ClinicalCaseStatusWire.wireName`
 *     - `ClinicalEventStatus`     + `ClinicalEventStatusWire.wireName`
 *     - `ClinicalCaseOpeningType` + `ClinicalCaseOpeningTypeWire.wireName`
 *     - `ClinicalEventType`       + `ClinicalEventTypeWire.wireName`
 *   lib/features/health/domain/health_v1_transitions.dart
 *     - `ClinicalCaseTransitions._normalTransitions` / `reopenDestinations`
 *     - `ClinicalEventTransitions._allowedTransitions`
 *   lib/features/health/domain/health_v1_models.dart
 *     - ClinicalEvent cancellation-metadata completeness invariants
 *
 * HARD CONSTRAINTS (W1 scope):
 *   - NO firebase-admin, NO firebase-functions, NO Firestore, NO HttpsError.
 *   - NO permission/capability evaluation.
 *   - NO clock: every instant is an explicit caller-supplied argument.
 *   - Deterministic and side-effect free.
 *
 * The error model deliberately distinguishes two classes so that a LATER
 * transport layer can map them without re-inspecting messages:
 *   INVALID_VALUE      → (future) invalid-argument
 *   ILLEGAL_TRANSITION → (future) failed-precondition
 * That mapping is NOT performed here; this module has no transport dependency.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Error model
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fault class of a domain rejection.
 *
 * `invalid_value` = the input itself is not acceptable (unknown wire value,
 * missing required metadata, metadata supplied where it is forbidden).
 * `illegal_transition` = the inputs are individually well-formed but the
 * requested state change is not permitted from the current state.
 */
export type ClinicalDomainFaultKind = "invalid_value" | "illegal_transition";

/** Stable domain error codes. Values match the Dart `HealthDomainException` codes. */
export const CLINICAL_DOMAIN_ERROR_CODES = [
  "invalid_case_transition",
  "invalid_case_reopen",
  "missing_reopen_reason",
  "invalid_event_transition",
  "missing_cancel_reason",
  "missing_cancellation_metadata",
  "unexpected_cancellation_metadata",
  "unknown_case_status",
  "unknown_event_status",
  "unknown_event_type",
  "unknown_case_opening_type",
] as const;

export type ClinicalDomainErrorCode = typeof CLINICAL_DOMAIN_ERROR_CODES[number];

/**
 * Pure domain error. Carries no transport identity on purpose — see the module
 * header for why the invalid-argument / failed-precondition decision is
 * deferred to a future writer slice.
 */
export class ClinicalDomainError extends Error {
  constructor(
    readonly code: ClinicalDomainErrorCode,
    readonly kind: ClinicalDomainFaultKind,
    message: string,
  ) {
    super(message);
    this.name = "ClinicalDomainError";
  }
}

function invalidValue(
  code: ClinicalDomainErrorCode,
  message: string,
): ClinicalDomainError {
  return new ClinicalDomainError(code, "invalid_value", message);
}

function illegalTransition(
  code: ClinicalDomainErrorCode,
  message: string,
): ClinicalDomainError {
  return new ClinicalDomainError(code, "illegal_transition", message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire vocabularies
// ─────────────────────────────────────────────────────────────────────────────

/**
 * ClinicalCase lifecycle status. Values ARE the persisted wire values, so the
 * Dart `wireName` extension needs no separate mapping table here.
 */
export const CLINICAL_CASE_STATUSES = [
  "open",
  "under_investigation",
  "under_treatment",
  "monitoring",
  "discharged",
  "cancelled",
] as const;

export type ClinicalCaseStatus = typeof CLINICAL_CASE_STATUSES[number];

/**
 * ClinicalEvent status.
 *
 * NOTE the deliberate asymmetry: the Dart enum member is `finalised` but its
 * wire value is `"final"` (`health_v1_enums.dart:214`). The wire value is what
 * is persisted, therefore the wire value is what this module models.
 */
export const CLINICAL_EVENT_STATUSES = ["draft", "final", "cancelled"] as const;

export type ClinicalEventStatus = typeof CLINICAL_EVENT_STATUSES[number];

/** Why a ClinicalCase was opened. */
export const CLINICAL_CASE_OPENING_TYPES = [
  "incident",
  "consultation",
  "preventive",
  "administrative",
] as const;

export type ClinicalCaseOpeningType = typeof CLINICAL_CASE_OPENING_TYPES[number];

/** The 18 canonical ClinicalEvent types, in Dart declaration order. */
export const CLINICAL_EVENT_TYPES = [
  "consultation",
  "incident",
  "vaccination",
  "exam_request",
  "exam_collection",
  "exam_result",
  "exam_interpretation",
  "treatment_start",
  "treatment_note",
  "dose_note",
  "reevaluation",
  "discharge",
  "reopen",
  "restriction_issued",
  "restriction_ended",
  "surgical_note",
  "general_note",
  "observation",
] as const;

export type ClinicalEventType = typeof CLINICAL_EVENT_TYPES[number];

// ─────────────────────────────────────────────────────────────────────────────
// Strict parsers
//
// Strict, not defensive: the Dart client parsers tolerate unknown values
// (`ParsedHealthEnum.unknown`) because a READER must survive forward-written
// data. A WRITER must not — an unrecognised value on the way IN is a rejected
// input, never a silently stored one.
// ─────────────────────────────────────────────────────────────────────────────

function parseFrom<T extends string>(
  vocabulary: readonly T[],
  value: unknown,
  code: ClinicalDomainErrorCode,
  label: string,
): T {
  if (typeof value === "string" && (vocabulary as readonly string[]).includes(value)) {
    return value as T;
  }
  throw invalidValue(
    code,
    `${label} inválido: ${JSON.stringify(value)}. ` +
      `Valores aceitos: ${vocabulary.join(", ")}`,
  );
}

export function parseClinicalCaseStatus(value: unknown): ClinicalCaseStatus {
  return parseFrom(
    CLINICAL_CASE_STATUSES,
    value,
    "unknown_case_status",
    "status do caso clínico",
  );
}

export function parseClinicalEventStatus(value: unknown): ClinicalEventStatus {
  return parseFrom(
    CLINICAL_EVENT_STATUSES,
    value,
    "unknown_event_status",
    "status do evento clínico",
  );
}

export function parseClinicalEventType(value: unknown): ClinicalEventType {
  return parseFrom(
    CLINICAL_EVENT_TYPES,
    value,
    "unknown_event_type",
    "tipo do evento clínico",
  );
}

export function parseClinicalCaseOpeningType(
  value: unknown,
): ClinicalCaseOpeningType {
  return parseFrom(
    CLINICAL_CASE_OPENING_TYPES,
    value,
    "unknown_case_opening_type",
    "tipo de abertura do caso clínico",
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ClinicalCase state machine
// ─────────────────────────────────────────────────────────────────────────────

/** Mirror of `ClinicalCaseTransitions._normalTransitions`. */
const CASE_TRANSITIONS: Readonly<
  Record<ClinicalCaseStatus, readonly ClinicalCaseStatus[]>
> = {
  open: [
    "under_investigation",
    "under_treatment",
    "monitoring",
    "discharged",
    "cancelled",
  ],
  under_investigation: [
    "open",
    "under_treatment",
    "monitoring",
    "discharged",
    "cancelled",
  ],
  under_treatment: ["under_investigation", "monitoring", "discharged", "cancelled"],
  monitoring: ["under_investigation", "under_treatment", "discharged", "cancelled"],
  discharged: [],
  cancelled: [],
};

/**
 * Mirror of `ClinicalCaseTransitions.reopenDestinations`.
 *
 * `discharged` and `cancelled` are excluded: reopening into a terminal state is
 * not a reopen. Note that reopen is NOT reachable from `cancelled` either —
 * only a discharged case may be reopened (see `assertCaseReopen`).
 */
const CASE_REOPEN_DESTINATIONS: readonly ClinicalCaseStatus[] = [
  "open",
  "under_investigation",
  "under_treatment",
  "monitoring",
];

/** Terminal = no outgoing normal transition exists. */
export function isTerminalCaseStatus(status: ClinicalCaseStatus): boolean {
  return CASE_TRANSITIONS[status].length === 0;
}

export function allowedCaseTransitions(
  status: ClinicalCaseStatus,
): readonly ClinicalCaseStatus[] {
  return CASE_TRANSITIONS[status];
}

export function canTransitionCase(
  from: ClinicalCaseStatus,
  to: ClinicalCaseStatus,
): boolean {
  return CASE_TRANSITIONS[from].includes(to);
}

export function isCaseReopenDestination(status: ClinicalCaseStatus): boolean {
  return CASE_REOPEN_DESTINATIONS.includes(status);
}

export function caseReopenDestinations(): readonly ClinicalCaseStatus[] {
  return CASE_REOPEN_DESTINATIONS;
}

/**
 * Asserts a normal ClinicalCase lifecycle transition.
 *
 * Throws `invalid_case_transition` / `illegal_transition` when not permitted,
 * matching `ClinicalCaseTransitions.transition`.
 */
export function assertCaseTransition(
  from: ClinicalCaseStatus,
  to: ClinicalCaseStatus,
): void {
  if (!canTransitionCase(from, to)) {
    throw illegalTransition(
      "invalid_case_transition",
      `Transição ${from} → ${to} não permitida`,
    );
  }
}

/** Normalised, validated reopen intent. */
export interface ClinicalCaseReopenIntent {
  readonly destination: ClinicalCaseStatus;
  readonly reason: string;
}

/**
 * Validates a ClinicalCase reopen and returns the normalised intent.
 *
 * Mirrors `ClinicalCaseTransitions.reopen` ordering exactly: the origin/destination
 * check runs BEFORE the reason check, so a reopen of a non-discharged case fails
 * as `invalid_case_reopen` even when the reason is also blank.
 *
 * The returned `reason` is trimmed — the trimmed form is what the Dart aggregate
 * persists, so a future writer must store this value, not the raw input.
 */
export function assertCaseReopen(
  from: ClinicalCaseStatus,
  destination: ClinicalCaseStatus,
  reason: string,
): ClinicalCaseReopenIntent {
  if (from !== "discharged" || !isCaseReopenDestination(destination)) {
    throw illegalTransition(
      "invalid_case_reopen",
      "Somente caso discharged pode ser reaberto para destino permitido",
    );
  }
  const normalizedReason = reason.trim();
  if (normalizedReason.length === 0) {
    throw invalidValue("missing_reopen_reason", "reopen_reason é obrigatório");
  }
  return {destination, reason: normalizedReason};
}

// ─────────────────────────────────────────────────────────────────────────────
// ClinicalEvent state machine
// ─────────────────────────────────────────────────────────────────────────────

/** Mirror of `ClinicalEventTransitions._allowedTransitions`. */
const EVENT_TRANSITIONS: Readonly<
  Record<ClinicalEventStatus, readonly ClinicalEventStatus[]>
> = {
  draft: ["final", "cancelled"],
  final: ["cancelled"],
  cancelled: [],
};

export function isTerminalEventStatus(status: ClinicalEventStatus): boolean {
  return EVENT_TRANSITIONS[status].length === 0;
}

export function allowedEventTransitions(
  status: ClinicalEventStatus,
): readonly ClinicalEventStatus[] {
  return EVENT_TRANSITIONS[status];
}

export function canTransitionEvent(
  from: ClinicalEventStatus,
  to: ClinicalEventStatus,
): boolean {
  return EVENT_TRANSITIONS[from].includes(to);
}

/**
 * THE finalization invariant, stated positively.
 *
 * A `final` (or `cancelled`) ClinicalEvent is content-immutable: `type`,
 * `occurred_at`, `payload_type`, `payload_version`, `content` and
 * `attachment_refs` may never be rewritten. Only `draft` content is editable.
 *
 * Cancelling a `final` event is NOT a content edit — it appends cancellation
 * metadata and preserves the original content. Correction of finalised content
 * is an amendment (a separate causal record), never a mutation.
 */
export function isEventContentImmutable(status: ClinicalEventStatus): boolean {
  return status !== "draft";
}

/** Inverse of {@link isEventContentImmutable}; exists to keep call sites readable. */
export function isEventContentEditable(status: ClinicalEventStatus): boolean {
  return !isEventContentImmutable(status);
}

/**
 * Authorship/instant of a cancellation. Structural only — a future writer is
 * responsible for deriving `uid` from `request.auth`, never from the payload.
 */
export interface ClinicalActor {
  readonly uid: string;
  readonly name: string;
  readonly internalRole: string;
}

/** Cancellation metadata as supplied by a caller (all optional at the boundary). */
export interface ClinicalEventCancellationInput {
  readonly cancelReason?: string | null;
  readonly cancelledAt?: Date | null;
  readonly cancelledBy?: ClinicalActor | null;
}

/** Validated, normalised cancellation metadata. */
export interface ClinicalEventCancellation {
  readonly cancelReason: string;
  readonly cancelledAt: Date;
  readonly cancelledBy: ClinicalActor;
}

/**
 * Result of validating a ClinicalEvent status transition.
 *
 * `cancellation` is present if and only if `to === "cancelled"`, which lets a
 * writer persist the terminal patch without re-deciding what is required.
 */
export interface ClinicalEventTransitionResult {
  readonly from: ClinicalEventStatus;
  readonly to: ClinicalEventStatus;
  readonly cancellation: ClinicalEventCancellation | null;
}

function isPresent(value: unknown): boolean {
  return value !== undefined && value !== null;
}

/**
 * Validates a ClinicalEvent status transition plus its cancellation metadata.
 *
 * Mirrors `ClinicalEventTransitions.transition` check-for-check and in the same
 * order:
 *   1. transition legality            → invalid_event_transition
 *   2. when cancelling: reason        → missing_cancel_reason
 *   3. when cancelling: instant+actor → missing_cancellation_metadata
 *   4. when NOT cancelling: no metadata at all → unexpected_cancellation_metadata
 */
export function assertEventTransition(
  from: ClinicalEventStatus,
  to: ClinicalEventStatus,
  cancellation: ClinicalEventCancellationInput = {},
): ClinicalEventTransitionResult {
  if (!canTransitionEvent(from, to)) {
    throw illegalTransition(
      "invalid_event_transition",
      `Transição ${from} → ${to} não permitida`,
    );
  }

  const {cancelReason, cancelledAt, cancelledBy} = cancellation;

  if (to === "cancelled") {
    if (!isPresent(cancelReason) || (cancelReason as string).trim().length === 0) {
      throw invalidValue("missing_cancel_reason", "cancel_reason é obrigatório");
    }
    if (!isPresent(cancelledAt) || !isPresent(cancelledBy)) {
      throw invalidValue(
        "missing_cancellation_metadata",
        "Cancelamento exige instante e autoria",
      );
    }
    return {
      from,
      to,
      cancellation: {
        cancelReason: (cancelReason as string).trim(),
        cancelledAt: cancelledAt as Date,
        cancelledBy: cancelledBy as ClinicalActor,
      },
    };
  }

  if (isPresent(cancelReason) || isPresent(cancelledAt) || isPresent(cancelledBy)) {
    throw invalidValue(
      "unexpected_cancellation_metadata",
      "Metadados de cancelamento só são aceitos ao cancelar",
    );
  }
  return {from, to, cancellation: null};
}

/**
 * Cancellation-metadata completeness invariant of a ClinicalEvent AT REST,
 * independent of any transition — mirror of the `ClinicalEvent` constructor
 * checks in `health_v1_models.dart`.
 *
 * Applied by a future writer to any event document it is about to persist,
 * including one it did not itself transition.
 */
export function assertEventCancellationConsistency(
  status: ClinicalEventStatus,
  cancellation: ClinicalEventCancellationInput = {},
): void {
  const {cancelReason, cancelledAt, cancelledBy} = cancellation;
  const parts = [cancelReason, cancelledAt, cancelledBy];
  const hasAny = parts.some(isPresent);
  const hasAll = parts.every(isPresent);

  if (hasAny && !hasAll) {
    throw invalidValue(
      "missing_cancellation_metadata",
      "Metadados de cancelamento devem ser completos",
    );
  }
  if (status === "cancelled" && !hasAll) {
    throw invalidValue(
      "missing_cancellation_metadata",
      "Evento cancelado exige motivo, instante e autoria",
    );
  }
  if (status !== "cancelled" && hasAny) {
    throw invalidValue(
      "unexpected_cancellation_metadata",
      "Evento não cancelado não pode ter metadados de cancelamento",
    );
  }
  if (hasAll && (cancelReason as string).trim().length === 0) {
    throw invalidValue("missing_cancel_reason", "cancel_reason é obrigatório");
  }
}
