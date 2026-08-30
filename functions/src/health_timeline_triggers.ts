/**
 * Thin Firebase Firestore trigger wrappers for HealthTimeline projection.
 *
 * Each wrapper:
 * 1. Receives a Firebase onDocumentCreated event
 * 2. Extracts snapshot + params
 * 3. Delegates to an approved handler from health_timeline_trigger_handlers.ts
 * 4. Propagates transient errors (throw → retry, requires retry:true on export)
 * 5. Returns successfully for deterministic invalid payloads (anomaly already persisted)
 *
 * Gate 5C.5C.5 — Local code only. Not deployed.
 */
import {logger} from "firebase-functions";
import type {FirestoreEvent, QueryDocumentSnapshot} from "firebase-functions/v2/firestore";
import {
  makeMealLogCreatedHandler,
  makeSupplementLogCreatedHandler,
  type TriggerHandlerDependencies,
} from "./health_timeline_trigger_handlers";

export type TriggerWrapperDependencies = TriggerHandlerDependencies;

/**
 * Produces a thin onDocumentCreated callback for meal_logs.
 *
 * The returned function is suitable as the second argument to
 * onDocumentCreated({document: "dogs/{dogId}/meal_logs/{mealId}", region, retry: true}, ...).
 */
export function healthTimelineProjectMealLogCreatedWrapper(
  deps: TriggerWrapperDependencies,
): (
  event: FirestoreEvent<
    QueryDocumentSnapshot | undefined,
    {dogId: string; mealId: string}
  >
) => Promise<void> {
  const handler = makeMealLogCreatedHandler(deps);

  return async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.info("HealthTimeline meal_logs trigger received event without snapshot.");
      return;
    }
    await handler({
      params: event.params as Record<string, unknown>,
      snapshot,
    });
  };
}

/**
 * Produces a thin onDocumentCreated callback for supplement_logs.
 *
 * The returned function is suitable as the second argument to
 * onDocumentCreated({document: "dogs/{dogId}/supplement_logs/{supplementLogId}", region, retry: true}, ...).
 */
export function healthTimelineProjectSupplementLogCreatedWrapper(
  deps: TriggerWrapperDependencies,
): (
  event: FirestoreEvent<
    QueryDocumentSnapshot | undefined,
    {dogId: string; supplementLogId: string}
  >
) => Promise<void> {
  const handler = makeSupplementLogCreatedHandler(deps);

  return async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.info("HealthTimeline supplement_logs trigger received event without snapshot.");
      return;
    }
    await handler({
      params: event.params as Record<string, unknown>,
      snapshot,
    });
  };
}
