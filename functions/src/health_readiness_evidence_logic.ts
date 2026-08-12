/**
 * Readiness v1 — pure evidence classification.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * This module holds the shape-recognition rules for every readiness evidence
 * source. It is PURE: it receives already-fetched raw documents and returns
 * classified evidence. No Firestore, no Admin SDK, no clock.
 *
 * Governing principle (K9 Ops: "estado vazio não é automaticamente sucesso"):
 * a query error, a malformed document and a genuinely empty collection are
 * three DIFFERENT outcomes and must never collapse into one another.
 *
 * ── Coexistence status of each source ────────────────────────────────────────
 *   weight_records         CANONICAL
 *   nutrition_plans        CANONICAL
 *   operational_restrictions CANONICAL (may legitimately be empty today)
 *   health_events          COEXISTENCE BRIDGE for vaccination + consultation
 *
 * The target authorities remain `dogs/{dogId}/vaccination_records` and
 * `clinical_cases/{caseId}/events/{eventId}`. Runtime inventory proved neither
 * has a factual writer on this branch, so READINESS-V1 temporarily authorizes
 * narrow server-side adapters over `health_events`. When the canonical
 * aggregates exist they WIN — see `resolveVaccinationEvidence`, which refuses
 * to fall back silently once canonical records are present.
 */

import {
  EvidenceState,
  NutritionEvidenceValue,
  ReadinessRestriction,
  VaccinationEvidenceValue,
} from "./health_readiness_policy";

/** A raw Firestore document reduced to what the pure layer needs. */
export interface RawDoc {
  readonly id: string;
  readonly data: Readonly<Record<string, unknown>>;
}

/**
 * Outcome of fetching one collection.
 *
 * `failed` preserves a query/permission/index error so it can never be read as
 * "no records".
 */
export type RawQuery =
  | {readonly kind: "docs"; readonly docs: readonly RawDoc[]}
  | {readonly kind: "failed"; readonly reasonCode: string};

// ─────────────────────────────────────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────────────────────────────────────

/** Duck-typed Firestore Timestamp, so this module needs no Admin SDK import. */
interface TimestampLike {
  toDate: () => Date;
}

function isTimestampLike(value: unknown): value is TimestampLike {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as {toDate?: unknown}).toDate === "function"
  );
}

/**
 * Strictly converts a persisted temporal value to a Date.
 *
 * Accepts a Firestore Timestamp or an ISO-8601 string (historical documents in
 * this ecosystem carry both). Returns null for anything else, including a
 * pending `serverTimestamp()` sentinel, which has no `toDate`.
 */
export function readInstant(value: unknown): Date | null {
  if (isTimestampLike(value)) {
    const date = value.toDate();
    if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
    return date;
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return null;
    return parsed;
  }
  return null;
}

function readNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function readStringList(value: unknown): readonly string[] | null {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) return null;
  const out: string[] = [];
  for (const entry of value) {
    const parsed = readNonEmptyString(entry);
    if (parsed === null) return null;
    out.push(parsed);
  }
  return out;
}

/**
 * A `health_events` document is soft-deleted (and therefore invalid as
 * evidence) when any recognized soft-delete marker is present.
 *
 * Both spellings are checked because the Dart writer emits snake_case
 * (`deleted_at`) while historical/legacy documents may carry camelCase.
 */
export function isSoftDeleted(data: Readonly<Record<string, unknown>>): boolean {
  for (const key of ["deleted_at", "deletedAt"]) {
    const value = data[key];
    if (value !== undefined && value !== null) return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Weight — CANONICAL
// ─────────────────────────────────────────────────────────────────────────────

export type WeightCandidateKind =
  | "valid"
  | "invalidated"
  | "malformed"
  | "unsupported";

/**
 * Mirrors the Dart `WeightCurrentBlocker` taxonomy
 * (lib/features/health/domain/weight_collection_policy.dart).
 */
export type WeightBlocker = "malformed" | "unsupported" | "duplicateEntityId";

export interface WeightCandidate {
  readonly entityId: string;
  readonly kind: WeightCandidateKind;
  readonly measuredAt: Date | null;
  /**
   * FACTUAL `recorded_at` — second canonical sort key.
   *
   * Null for deployed v1 and recognized legacy records, which do not persist a
   * factual recording instant. `created_at` is NEVER promoted here: doing so
   * would make the server pick a different "current" weight than the
   * homologated Mobile authority when two records tie on `measured_at`.
   *
   * Parity target: `compareWeightCanonicalOrder` in
   * lib/features/health/domain/weight_collection_policy.dart, whose signature
   * accepts only (measuredAt, recordedAt, entityId).
   */
  readonly recordedAt: Date | null;
  /**
   * Compatibility metadata mirroring Dart's `orderingFallbackAt`.
   *
   * Preserved for diagnostics only. It MUST NOT participate in comparison or
   * current-weight selection — exactly as the Dart parser stores it at
   * weight_assessment_document_parser.dart:254 without any selection code
   * reading it.
   */
  readonly orderingFallbackAt: Date | null;
}

export interface WeightCollectionAnalysis {
  readonly kind: "current" | "none" | "inconclusive";
  readonly current: WeightCandidate | null;
  readonly blockers: readonly WeightBlocker[];
}

/**
 * Canonical weight ordering: measured_at DESC → recorded_at DESC → entityId DESC.
 *
 * A present `recorded_at` beats an absent one, matching the Dart comparator.
 */
export function compareWeightCanonicalOrder(
  a: WeightCandidate,
  b: WeightCandidate,
): number {
  const aMeasured = a.measuredAt?.getTime() ?? 0;
  const bMeasured = b.measuredAt?.getTime() ?? 0;
  if (aMeasured !== bMeasured) return bMeasured - aMeasured;

  // FACTUAL recorded_at only. `orderingFallbackAt`/`created_at` is deliberately
  // not consulted: for two v1 records (both null) entityId decides.
  const aRecorded = a.recordedAt;
  const bRecorded = b.recordedAt;
  if (aRecorded !== null && bRecorded === null) return -1;
  if (aRecorded === null && bRecorded !== null) return 1;
  if (aRecorded !== null && bRecorded !== null) {
    const diff = bRecorded.getTime() - aRecorded.getTime();
    if (diff !== 0) return diff;
  }

  // entityId DESC by UTF-16 code unit, so ordering never depends on locale.
  if (a.entityId === b.entityId) return 0;
  return a.entityId > b.entityId ? -1 : 1;
}

/**
 * Target-v2 discriminator fields.
 *
 * Mirrors `_targetFields` in the Dart parser
 * (weight_assessment_document_parser.dart:56-69). Presence of any of these on a
 * `schema_version == 1` document is a hybrid v1/v2 shape — malformed, never
 * silently accepted.
 */
const WEIGHT_TARGET_V2_FIELDS: readonly string[] = Object.freeze([
  "record_type",
  "origin_record_type",
  "status",
  "revision",
  "recorded_at",
  "information_source",
  "location",
  "measurement_condition",
  "equipment_state",
  "reading_quality",
  "bcs",
  "bcs_source",
  "attachment_refs",
  "clinical_links",
]);

function hasAnyTargetV2Field(data: Readonly<Record<string, unknown>>): boolean {
  return WEIGHT_TARGET_V2_FIELDS.some((field) => field in data);
}

/**
 * Validates the canonical `recorded_by` envelope: {uid, name, internal_role}.
 *
 * This is the provenance discriminator that distinguishes a genuine deployed-v1
 * record from a legacy write that merely happens to carry weight_kg/measured_at.
 */
function hasCanonicalRecordedBy(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const envelope = value as Record<string, unknown>;
  return (
    readNonEmptyString(envelope["uid"]) !== null &&
    readNonEmptyString(envelope["name"]) !== null &&
    readNonEmptyString(envelope["internal_role"]) !== null
  );
}

function malformedWeight(entityId: string): WeightCandidate {
  return {
    entityId,
    kind: "malformed",
    measuredAt: null,
    recordedAt: null,
    orderingFallbackAt: null,
  };
}

/**
 * Classifies one raw weight document, mirroring the homologated Mobile parser.
 *
 * Recognized shapes:
 *   - deployed v1: `schema_version == 1`, NO target-v2 field, finite positive
 *     `weight_kg`, factual `measured_at`, canonical `recorded_by` envelope, and
 *     embedded dog identity (when present) agreeing with the path dogId.
 *     `recordedAt` is null by definition; `created_at` is kept only as
 *     `orderingFallbackAt`.
 *   - target v2: `schema_version == 2` with a FACTUAL `recorded_at`.
 *
 * Anything else — including a legacy write with valid weight but no canonical
 * provenance envelope, or a hybrid v1/v2 shape — is malformed/unsupported and
 * escalates the collection to inconclusive rather than being guessed at.
 */
export function classifyWeightDoc(doc: RawDoc, dogId?: string): WeightCandidate {
  const data = doc.data;

  const invalidatedAt = data["invalidated_at"] ?? data["invalidatedAt"];
  if (invalidatedAt !== undefined && invalidatedAt !== null) {
    return {
      entityId: doc.id,
      kind: "invalidated",
      measuredAt: null,
      recordedAt: null,
      orderingFallbackAt: null,
    };
  }
  if (isSoftDeleted(data)) {
    return {
      entityId: doc.id,
      kind: "invalidated",
      measuredAt: null,
      recordedAt: null,
      orderingFallbackAt: null,
    };
  }

  const rawSchema = data["schema_version"];
  if (typeof rawSchema !== "number" || !Number.isInteger(rawSchema) || rawSchema < 1) {
    return malformedWeight(doc.id);
  }
  if (rawSchema > 2) {
    return {
      entityId: doc.id,
      kind: "unsupported",
      measuredAt: null,
      recordedAt: null,
      orderingFallbackAt: null,
    };
  }

  const rawWeight = data["weight_kg"];
  const weightOk =
    typeof rawWeight === "number" && Number.isFinite(rawWeight) && rawWeight > 0;
  const measuredAt = readInstant(data["measured_at"]);
  if (!weightOk || measuredAt === null) {
    return malformedWeight(doc.id);
  }

  // Canonical provenance envelope is mandatory for both recognized versions.
  if (!hasCanonicalRecordedBy(data["recorded_by"])) {
    return malformedWeight(doc.id);
  }

  // Embedded dog identity must not contradict the path — guards cross-dog
  // contamination.
  if (dogId !== undefined) {
    const embedded =
      readNonEmptyString(data["dog_id"]) ?? readNonEmptyString(data["dogId"]);
    if (embedded !== null && embedded !== dogId) {
      return malformedWeight(doc.id);
    }
  }

  const orderingFallbackAt = readInstant(data["created_at"]);

  if (rawSchema === 1) {
    // Hybrid v1/v2 is malformed, matching the Dart parser's hybridV1V2 branch.
    if (hasAnyTargetV2Field(data)) {
      return malformedWeight(doc.id);
    }
    return {
      entityId: doc.id,
      kind: "valid",
      measuredAt,
      // Deployed v1 has no factual recording instant.
      recordedAt: null,
      orderingFallbackAt,
    };
  }

  // Target v2 requires a FACTUAL recorded_at.
  const recordedAt = readInstant(data["recorded_at"]);
  if (recordedAt === null) {
    return malformedWeight(doc.id);
  }
  return {
    entityId: doc.id,
    kind: "valid",
    measuredAt,
    recordedAt,
    orderingFallbackAt,
  };
}

/**
 * Selects the current weight, order-of-input independent.
 *
 * Any blocking candidate (malformed/unsupported/duplicate id) escalates the
 * whole collection to `inconclusive`: we must not silently present an older
 * reading as current when the newest document could not be understood.
 */
export function analyzeWeightCollection(
  docs: readonly RawDoc[],
  dogId?: string,
): WeightCollectionAnalysis {
  const candidates = docs.map((doc) => classifyWeightDoc(doc, dogId));
  const blockers: WeightBlocker[] = [];

  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (seen.has(candidate.entityId)) blockers.push("duplicateEntityId");
    seen.add(candidate.entityId);
    if (candidate.kind === "malformed") blockers.push("malformed");
    if (candidate.kind === "unsupported") blockers.push("unsupported");
  }

  if (blockers.length > 0) {
    return {kind: "inconclusive", current: null, blockers};
  }

  const valid = candidates
    .filter((candidate) => candidate.kind === "valid")
    .sort(compareWeightCanonicalOrder);

  if (valid.length === 0) {
    return {kind: "none", current: null, blockers: []};
  }
  return {kind: "current", current: valid[0], blockers: []};
}

export function resolveWeightEvidence(
  query: RawQuery,
  dogId?: string,
): EvidenceState<Date> {
  if (query.kind === "failed") {
    return {kind: "unreliable", reasonCode: query.reasonCode};
  }
  const analysis = analyzeWeightCollection(query.docs, dogId);
  if (analysis.kind === "inconclusive") {
    return {kind: "unreliable", reasonCode: "inconclusive"};
  }
  if (analysis.kind === "none" || analysis.current?.measuredAt == null) {
    return {kind: "absent"};
  }
  return {kind: "present", value: analysis.current.measuredAt};
}

// ─────────────────────────────────────────────────────────────────────────────
// health_events — COEXISTENCE BRIDGE
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Recognized `type` values, exactly as emitted by the two factual writers
 * (`health_service.dart` via `HealthLogModel.toJson()`, and
 * `adminCreateHealthEvent`). Both write the canonical English token; the
 * Portuguese legacy labels are normalized by `mapLegacyLogType` BEFORE
 * persistence, so only these tokens are accepted here.
 *
 * No heuristic, no "looks like a vaccination" matching.
 */
const VACCINATION_TYPE = "vaccination";
const CONSULTATION_TYPE = "consultation";
const EXAM_TYPE = "exam";

/**
 * Normalizes the discriminator for comparison only: trims and lowercases.
 * Does NOT translate or guess. An unrecognized token is ignored, never coerced.
 */
export function normalizeEventType(value: unknown): string | null {
  const raw = readNonEmptyString(value);
  return raw === null ? null : raw.toLowerCase();
}

/** Classification of a single health_event against one expected type. */
export type EventClassification =
  | {readonly kind: "match"; readonly at: Date; readonly nextDueAt: Date | null}
  | {readonly kind: "ignored"}
  | {readonly kind: "malformed"};

/**
 * Classifies a `health_events` document for a given recognized type.
 *
 * - a different (or absent) `type` → `ignored`, never malformed: unrelated
 *   events must not poison the source;
 * - the expected type but an unusable factual `date` → `malformed`, so it can
 *   never be silently promoted to valid evidence;
 * - soft-deleted → `ignored`.
 */
export function classifyHealthEvent(
  doc: RawDoc,
  expectedType: string,
): EventClassification {
  const data = doc.data;
  const type = normalizeEventType(data["type"]);

  if (type !== expectedType) return {kind: "ignored"};
  if (isSoftDeleted(data)) return {kind: "ignored"};

  // `date` is the factual date of the event (application date for a
  // vaccination, attendance date for a consultation).
  const at = readInstant(data["date"]);
  if (at === null) return {kind: "malformed"};

  // camelCase `nextDueDate` is the only spelling either writer emits.
  const rawNextDue = data["nextDueDate"];
  let nextDueAt: Date | null = null;
  if (rawNextDue !== undefined && rawNextDue !== null) {
    nextDueAt = readInstant(rawNextDue);
    if (nextDueAt === null) return {kind: "malformed"};
  }

  return {kind: "match", at, nextDueAt};
}

/**
 * Deterministically selects the latest factual event of a recognized type.
 *
 * Ties on the factual date are broken by document id DESC so the result never
 * depends on query order.
 */
function latestRecognizedEvent(
  docs: readonly RawDoc[],
  expectedType: string,
): {latest: {at: Date; nextDueAt: Date | null; id: string} | null; malformed: boolean} {
  let latest: {at: Date; nextDueAt: Date | null; id: string} | null = null;
  let malformed = false;

  for (const doc of docs) {
    const classified = classifyHealthEvent(doc, expectedType);
    if (classified.kind === "malformed") {
      malformed = true;
      continue;
    }
    if (classified.kind === "ignored") continue;

    const candidate = {at: classified.at, nextDueAt: classified.nextDueAt, id: doc.id};
    if (latest === null) {
      latest = candidate;
      continue;
    }
    const diff = candidate.at.getTime() - latest.at.getTime();
    if (diff > 0 || (diff === 0 && candidate.id > latest.id)) {
      latest = candidate;
    }
  }

  return {latest, malformed};
}

/**
 * Consultation evidence.
 *
 * TARGET AUTHORITY: `clinical_cases/{caseId}/events/{eventId}`.
 * RUNTIME SOURCE (coexistence): `dogs/{dogId}/health_events` with
 * `type == "consultation"`.
 *
 * An exam is a different event type and can never be read as a consultation.
 */
export function resolveConsultationEvidence(query: RawQuery): EvidenceState<Date> {
  if (query.kind === "failed") {
    return {kind: "unreliable", reasonCode: query.reasonCode};
  }
  const {latest, malformed} = latestRecognizedEvent(query.docs, CONSULTATION_TYPE);
  if (latest !== null) return {kind: "present", value: latest.at};
  // A malformed consultation-like document must not read as "none recorded".
  if (malformed) return {kind: "unreliable", reasonCode: "malformed"};
  return {kind: "absent"};
}

/**
 * Vaccination evidence — currency is a `next_due` comparison.
 *
 * TARGET AUTHORITY: `dogs/{dogId}/vaccination_records`.
 * RUNTIME SOURCE (coexistence): `dogs/{dogId}/health_events` with
 * `type == "vaccination"`.
 *
 * Canonical precedence is enforced: when the canonical query returns any
 * document, the coexistence bridge is NOT consulted. There is no silent
 * fallback that would let a legacy event override the canonical aggregate.
 */
export function resolveVaccinationEvidence(
  canonical: RawQuery,
  coexistence: RawQuery,
): EvidenceState<VaccinationEvidenceValue> {
  if (canonical.kind === "failed") {
    return {kind: "unreliable", reasonCode: canonical.reasonCode};
  }

  // Canonical aggregate wins whenever it holds records.
  if (canonical.docs.length > 0) {
    return resolveCanonicalVaccination(canonical.docs);
  }

  if (coexistence.kind === "failed") {
    return {kind: "unreliable", reasonCode: coexistence.reasonCode};
  }

  const {latest, malformed} = latestRecognizedEvent(coexistence.docs, VACCINATION_TYPE);
  if (latest !== null) {
    // A dose with no next_due cannot prove currency.
    if (latest.nextDueAt === null) {
      return {kind: "absent"};
    }
    return {kind: "present", value: {nextDueAt: latest.nextDueAt}};
  }
  if (malformed) return {kind: "unreliable", reasonCode: "malformed"};
  return {kind: "absent"};
}

/**
 * Canonical `vaccination_records` reading.
 *
 * This collection has no factual writer on this branch, so the shape is treated
 * conservatively: `next_due` (or `next_due_at`) plus a factual application
 * instant. Anything unrecognized is unreliable rather than absent, because a
 * canonical record we cannot parse is a fault, not an absence.
 */
function resolveCanonicalVaccination(
  docs: readonly RawDoc[],
): EvidenceState<VaccinationEvidenceValue> {
  let latest: {appliedAt: Date; nextDueAt: Date; id: string} | null = null;
  let malformed = false;

  for (const doc of docs) {
    const data = doc.data;
    const status = normalizeEventType(data["status"] ?? data["record_status"]);
    if (status === "cancelled" || status === "invalidated") continue;
    if (isSoftDeleted(data)) continue;

    const appliedAt =
      readInstant(data["applied_at"]) ?? readInstant(data["administered_at"]);
    const nextDueAt =
      readInstant(data["next_due"]) ?? readInstant(data["next_due_at"]);

    if (appliedAt === null || nextDueAt === null) {
      malformed = true;
      continue;
    }

    const candidate = {appliedAt, nextDueAt, id: doc.id};
    if (latest === null) {
      latest = candidate;
      continue;
    }
    const diff = candidate.appliedAt.getTime() - latest.appliedAt.getTime();
    if (diff > 0 || (diff === 0 && candidate.id > latest.id)) {
      latest = candidate;
    }
  }

  if (latest !== null) return {kind: "present", value: {nextDueAt: latest.nextDueAt}};
  if (malformed) return {kind: "unreliable", reasonCode: "malformed"};
  return {kind: "absent"};
}

/**
 * Exam evidence — INFORMATIONAL ONLY.
 *
 * Used solely to help prove `hasAnyHealthEvaluation`. It is not a completeness
 * gate, has no threshold, and produces no readiness alert. Kept deliberately
 * narrow and isolated.
 */
export function resolveExamEvidence(query: RawQuery): EvidenceState<Date> {
  if (query.kind === "failed") {
    // Never blocks the verdict: the evaluator excludes exam from its guard.
    return {kind: "unreliable", reasonCode: query.reasonCode};
  }
  const {latest, malformed} = latestRecognizedEvent(query.docs, EXAM_TYPE);
  if (latest !== null) return {kind: "present", value: latest.at};
  if (malformed) return {kind: "unreliable", reasonCode: "malformed"};
  return {kind: "absent"};
}

// ─────────────────────────────────────────────────────────────────────────────
// Nutrition — CANONICAL
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Counts factual `active` nutrition plans.
 *
 * Exactly one is expected. Zero is missing; more than one is a CONFLICT that
 * must never be reduced to a single arbitrary plan. A malformed active-like
 * document is unreliable, not absent.
 */
export function resolveNutritionEvidence(
  query: RawQuery,
): EvidenceState<NutritionEvidenceValue> {
  if (query.kind === "failed") {
    return {kind: "unreliable", reasonCode: query.reasonCode};
  }

  let activeCount = 0;
  let malformed = false;

  for (const doc of query.docs) {
    const data = doc.data;
    if (isSoftDeleted(data)) continue;

    const rawStatus = data["status"];
    if (rawStatus === undefined || rawStatus === null) continue;

    const status = normalizeEventType(rawStatus);
    if (status === null) {
      // A status field present but unusable: cannot be judged inactive safely.
      malformed = true;
      continue;
    }
    if (status !== "active") continue;

    activeCount++;
  }

  // Any malformed plan blocks the invariant, regardless of what else parsed.
  // A valid active plan must NOT mask a malformed plan: if we cannot prove the
  // full lifecycle of a document, the source is unreliable.
  if (malformed) {
    return {kind: "unreliable", reasonCode: "malformed"};
  }
  // A conflict is reported faithfully; the evaluator turns >1 into unavailable.
  return {kind: "present", value: {activePlanCount: activeCount}};
}

// ─────────────────────────────────────────────────────────────────────────────
// Operational restrictions — CANONICAL
// ─────────────────────────────────────────────────────────────────────────────

export type RestrictionsEvidence =
  | {readonly kind: "restrictions"; readonly active: readonly ReadinessRestriction[]}
  | {readonly kind: "unreliable"; readonly reasonCode: string};

const RESTRICTION_LEVELS = ["absolute", "partial", "attention"] as const;
const RESTRICTION_STATUSES = ["active", "ended", "cancelled"] as const;

function isSupportedLevel(
  value: string | null,
): value is (typeof RESTRICTION_LEVELS)[number] {
  return value !== null && (RESTRICTION_LEVELS as readonly string[]).includes(value);
}

/**
 * Parses active operational restrictions.
 *
 * A malformed restriction NEVER disappears into "no restrictions": the whole
 * source becomes unreliable, because silently dropping a restriction could
 * present a restricted K9 as operational.
 *
 * Restrictions are never inferred from symptoms, surgery, medication,
 * consultation, exam or timeline — only this collection is read.
 */
export function resolveRestrictionsEvidence(query: RawQuery): RestrictionsEvidence {
  if (query.kind === "failed") {
    return {kind: "unreliable", reasonCode: query.reasonCode};
  }

  const active: ReadinessRestriction[] = [];

  for (const doc of query.docs) {
    const data = doc.data;

    const status = normalizeEventType(data["status"]);
    if (status === null) {
      return {kind: "unreliable", reasonCode: "malformed_status"};
    }
    if (!(RESTRICTION_STATUSES as readonly string[]).includes(status)) {
      // An unknown lifecycle value cannot be assumed inactive.
      return {kind: "unreliable", reasonCode: "unsupported_status"};
    }
    // Only active restrictions influence readiness. ended/cancelled are
    // legitimately skipped without inspecting their remaining fields.
    if (status !== "active") continue;

    const level = normalizeEventType(data["level"]);
    if (!isSupportedLevel(level)) {
      return {kind: "unreliable", reasonCode: "unsupported_level"};
    }

    const description = readNonEmptyString(data["description"]);
    if (description === null) {
      return {kind: "unreliable", reasonCode: "malformed_description"};
    }

    const since =
      readInstant(data["since"]) ?? readInstant(data["issued_at"]);
    if (since === null) {
      return {kind: "unreliable", reasonCode: "malformed_since"};
    }

    const activitiesRestricted = readStringList(data["activities_restricted"]);
    if (activitiesRestricted === null) {
      return {kind: "unreliable", reasonCode: "malformed_activities"};
    }
    // Domain invariant: a partial restriction must say what it restricts.
    if (level === "partial" && activitiesRestricted.length === 0) {
      return {kind: "unreliable", reasonCode: "missing_activities_restricted"};
    }

    let expectedEnd: Date | null = null;
    const rawExpectedEnd = data["expected_end"];
    if (rawExpectedEnd !== undefined && rawExpectedEnd !== null) {
      expectedEnd = readInstant(rawExpectedEnd);
      if (expectedEnd === null) {
        return {kind: "unreliable", reasonCode: "malformed_expected_end"};
      }
    }

    const category = normalizeEventType(data["category"]) ?? "other";

    active.push({
      id: doc.id,
      level,
      category,
      description,
      activitiesRestricted,
      since,
      expectedEnd,
    });
  }

  return {kind: "restrictions", active};
}
