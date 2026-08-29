/**
 * Readiness v1 — Firestore trigger exports.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Each trigger:
 * - Watches one collection under dogs/{dogId}
 * - Calls the shared projector (never implements readiness logic)
 * - Has retry enabled (transient failures are retried)
 * - Has recursion guard (ignores writes from health_summary/current)
 *
 * The health_events trigger applies a type filter: only vaccination and consultation
 * events call the projector. Other types (medication, symptom, surgery, etc.) are
 * ignored without touching the projector. The before/after check covers update transitions
 * (e.g. medication → consultation still triggers a refresh).
 *
 * IMPORTANT: `admin.firestore()` is called inside the wrapper, not at module load,
 * so that unit tests can import this module without triggering "no app" errors.
 */

import {Change, DocumentSnapshot, onDocumentWritten} from "firebase-functions/v2/firestore";
import type {FirestoreEvent} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {checkRelevant, normalizeEventType} from "./health_readiness_trigger_filter";
import {
  handleWeightRecordTrigger,
  handleHealthEventTrigger,
  handleNutritionPlanTrigger,
  handleRestrictionTrigger,
  ReadinessTriggerParams,
} from "./health_readiness_trigger_handlers";

const region = "southamerica-east1";

/**
 * Extracts the normalized event type from a Firestore document snapshot,
 * or null if absent / not a string.
 */
function extractEventType(snap: DocumentSnapshot | null | undefined): string | null {
  if (!snap?.exists) return null;
  const data = snap.data() as Record<string, unknown> | undefined;
  if (!data) return null;
  return normalizeEventType(data["type"]);
}

/**
 * Returns true iff the given onDocumentWritten event should trigger a readiness
 * recalculation, based on the before/after document types.
 *
 * CREATE  → after.type is relevant → refresh
 * UPDATE  → before.type OR after.type is relevant → refresh
 * DELETE  → before.type is relevant → refresh
 */
export function isRelevantHealthEvent(event: FirestoreEvent<Change<DocumentSnapshot> | undefined>): boolean {
  const beforeType = extractEventType(event.data?.before);
  const afterType = extractEventType(event.data?.after);
  return checkRelevant(beforeType, afterType);
}

// ── Generic wrapper (weight, nutrition, restrictions — always relevant) ──────

function makeGenericWrapper(
  getDb: () => FirebaseFirestore.Firestore,
  handler: (
    params: ReadinessTriggerParams,
    snapshot: DocumentSnapshot | undefined,
    sourcePath: string,
    db: FirebaseFirestore.Firestore,
  ) => Promise<void>,
) {
  return async (
    event: FirestoreEvent<
      Change<DocumentSnapshot> | undefined,
      {dogId: string; [key: string]: string}
    >,
  ) => {
    const dogId = event.params.dogId;
    const otherParams = {...event.params};
    delete (otherParams as Record<string, unknown>)["dogId"];
    const subPath = Object.values(otherParams).join("/");
    const sourcePath = `dogs/${dogId}/${subPath}`;
    const snapshot = event.data?.after;
    await handler(event.params, snapshot, sourcePath, getDb());
  };
}

// ── Health-events wrapper (type-filtered) ────────────────────────────────────

function makeHealthEventWrapper(
  getDb: () => FirebaseFirestore.Firestore,
) {
  return async (
    event: FirestoreEvent<
      Change<DocumentSnapshot> | undefined,
      {dogId: string; eventId: string}
    >,
  ) => {
    if (!isRelevantHealthEvent(event)) return;
    const dogId = event.params.dogId;
    const sourcePath = `dogs/${dogId}/health_events/${event.params.eventId}`;
    const snapshot = event.data?.after;
    await handleHealthEventTrigger(event.params, snapshot, sourcePath, getDb());
  };
}

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

/** Readiness recalculation trigger — weight_records. */
export const healthReadinessProjectWeightRecord = onDocumentWritten(
  {
    document: "dogs/{dogId}/weight_records/{recordId}",
    region,
    retry: true,
  },
  makeGenericWrapper(getDb, handleWeightRecordTrigger),
);

/** Readiness recalculation trigger — health_events (vaccination + consultation only). */
export const healthReadinessProjectHealthEvent = onDocumentWritten(
  {
    document: "dogs/{dogId}/health_events/{eventId}",
    region,
    retry: true,
  },
  makeHealthEventWrapper(getDb),
);

/** Readiness recalculation trigger — nutrition_plans. */
export const healthReadinessProjectNutritionPlan = onDocumentWritten(
  {
    document: "dogs/{dogId}/nutrition_plans/{planId}",
    region,
    retry: true,
  },
  makeGenericWrapper(getDb, handleNutritionPlanTrigger),
);

/** Readiness recalculation trigger — operational_restrictions. */
export const healthReadinessProjectRestriction = onDocumentWritten(
  {
    document: "dogs/{dogId}/operational_restrictions/{restrictionId}",
    region,
    retry: true,
  },
  makeGenericWrapper(getDb, handleRestrictionTrigger),
);
