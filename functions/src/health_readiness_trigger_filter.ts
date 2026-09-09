/**
 * Readiness v1 — shared health event type filter.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Contains the health_event type discriminator used by the Firestore trigger
 * (for pre-filtering) and by any unit tests that need to verify the filter behavior
 * without a Firestore runtime.
 *
 * The pure function `checkRelevant` tests the before/after type combination logic.
 * The trigger module wraps it with Firestore document extraction.
 */

export const RELEVANT_HEALTH_EVENT_TYPES = new Set(["vaccination", "consultation"]);

/**
 * Normalizes a health event type value using the same semantics as the
 * evidence readers (trim + lowercase).
 */
export function normalizeEventType(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed.toLowerCase();
}

/**
 * Returns true iff the given normalized event type is readiness-relevant.
 */
export function isRelevantHealthEventType(type: string): boolean {
  return RELEVANT_HEALTH_EVENT_TYPES.has(normalizeEventType(type) ?? "");
}

/**
 * Pure logic: given the normalized before/after event types (or null if absent),
 * should the readiness projector be invoked?
 *
 * CREATE  → after is relevant    → true
 * UPDATE  → before OR after relevant → true
 * DELETE  → before is relevant   → true
 */
export function checkRelevant(
  beforeType: string | null,
  afterType: string | null,
): boolean {
  const b = beforeType ?? "";
  const a = afterType ?? "";
  return isRelevantHealthEventType(b) || isRelevantHealthEventType(a);
}

// ── Canonical Clinical Event filter ──────────────────────────────────────────

interface ClinicalEventTriggerSnapshot {
  readonly isConsultation: boolean;
  readonly isFinal: boolean;
  readonly occurredAtMs: number | null;
}

function parseClinicalEventSnapshot(
  data: Readonly<Record<string, unknown>> | null | undefined,
): ClinicalEventTriggerSnapshot {
  if (!data) {
    return {isConsultation: false, isFinal: false, occurredAtMs: null};
  }
  for (const key of ["deleted_at", "deletedAt"]) {
    if (data[key] !== undefined && data[key] !== null) {
      return {isConsultation: false, isFinal: false, occurredAtMs: null};
    }
  }
  const eventType = normalizeEventType(data["event_type"] ?? data["eventType"]);
  const payloadType = normalizeEventType(data["payload_type"] ?? data["payloadType"]);
  const isConsultation = eventType === "consultation" && payloadType === "consultation_v1";

  const status = normalizeEventType(data["status"]);
  const isFinal = isConsultation && status === "final";

  let occurredAtMs: number | null = null;
  const rawOccurred = data["occurred_at"] ?? data["occurredAt"];
  if (rawOccurred) {
    if (
      typeof rawOccurred === "object" &&
      rawOccurred !== null &&
      typeof (rawOccurred as {toDate?: unknown}).toDate === "function"
    ) {
      const d = (rawOccurred as {toDate: () => Date}).toDate();
      if (d instanceof Date && !Number.isNaN(d.getTime())) {
        occurredAtMs = d.getTime();
      }
    } else if (typeof rawOccurred === "string" && rawOccurred.trim() !== "") {
      const d = new Date(rawOccurred);
      if (!Number.isNaN(d.getTime())) {
        occurredAtMs = d.getTime();
      }
    }
  }

  return {
    isConsultation,
    isFinal,
    occurredAtMs,
  };
}

/**
 * Evaluates whether a write to dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}
 * should trigger a readiness recalculation.
 *
 * Pure function: accepts raw before and after document data.
 */
export function checkRelevantClinicalEvent(
  beforeData: Readonly<Record<string, unknown>> | null | undefined,
  afterData: Readonly<Record<string, unknown>> | null | undefined,
): boolean {
  const before = parseClinicalEventSnapshot(beforeData);
  const after = parseClinicalEventSnapshot(afterData);

  // If neither side was or is a consultation event, ignore.
  if (!before.isConsultation && !after.isConsultation) {
    return false;
  }

  // Lifecycle transition affecting readiness:
  // draft -> final, or final -> cancelled / deleted / soft-deleted
  if (before.isFinal !== after.isFinal) {
    return true;
  }

  // Both final: recalculate iff the factual consultation date changed
  if (before.isFinal && after.isFinal) {
    return before.occurredAtMs !== after.occurredAtMs;
  }

  // Both non-final (draft -> draft, draft -> cancelled, draft created)
  return false;
}
