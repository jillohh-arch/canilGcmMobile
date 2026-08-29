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
