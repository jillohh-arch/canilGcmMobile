/**
 * Readiness v1 — Firestore trigger handlers.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Thin handlers for readiness recalculation triggers. Each handler:
 * 1. Extracts dogId from trigger params
 * 2. Guards against recursion (ignores writes FROM health_summary/current)
 * 3. Delegates to the shared projector
 * 4. Propagates errors for transient failures (retry semantics handled at export)
 *
 * The trigger export itself lives in health_readiness_triggers.ts.
 * The callable lives in health_readiness_callable.ts.
 * No logic lives here — all semantics live in the projector.
 */

import type {DocumentSnapshot} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions";
import {evaluateHealthReadiness, ProjectorDeps} from "./health_readiness_projector";
import {resolveReadinessConfig} from "./health_readiness_config";

/** Paths that the projector writes to — trigger must ignore writes from these. */
const PROJECTOR_WRITE_PATHS = new Set([
  "dogs/{dogId}/health_summary/current",
]);

export interface ReadinessTriggerParams {
  dogId: string;
}

/**
 * Guards against recursion: if the triggering document is inside a path that the
 * projector itself writes to, skip without error.
 *
 * Firestore triggers fire for ALL writes, including writes made by Admin SDK
 * (which bypasses rules). If the readiness projector writes to
 * `health_summary/current` and that document update fires a trigger, we must not
 * re-run the projector.
 */
function isRecursion(sourcePath: string): boolean {
  // Normalize: /dogs/dogId/weight_records/docId → weight_records
  const segments = sourcePath.split("/").filter(Boolean);
  if (segments.length < 2) return false;
  const collection = segments[segments.length - 2];
  const docId = segments[segments.length - 1];
  const full = `dogs/{dogId}/${collection}/${docId}`;
  return PROJECTOR_WRITE_PATHS.has(full);
}

/**
 * Builds the projector deps using the injected firestore instance.
 *
 * Using a factory (not module-level `admin.firestore()`) allows the handlers to be
 * tested without initializing Firebase. The real trigger exports inject `admin.firestore()`;
 * unit tests inject a fake.
 */
export function buildReadinessProjectorDeps(
  db: FirebaseFirestore.Firestore,
): ProjectorDeps {
  return {
    firestore: {
      readSubcollection: async (dogId, collection) => {
        try {
          const snap = await db
            .collection("dogs")
            .doc(dogId)
            .collection(collection)
            .get();
          return {
            kind: "docs" as const,
            docs: snap.docs.map((d) => ({id: d.id, data: d.data()})),
          };
        } catch (err) {
          return {kind: "failed" as const, reasonCode: String(err)};
        }
      },
      readCurrentSummary: async (dogId) => {
        try {
          const doc = await db
            .collection("dogs")
            .doc(dogId)
            .collection("health_summary")
            .doc("current")
            .get();
          return doc.exists ? (doc.data() as Record<string, unknown>) : null;
        } catch {
          return null;
        }
      },
      writeCurrentSummary: async (dogId, payload) => {
        await db
          .collection("dogs")
          .doc(dogId)
          .collection("health_summary")
          .doc("current")
          .set(payload, {merge: true});
      },
    },
    logger: {
      info: (message, context) => logger.info(message, context ?? {}),
      warn: (message, context) => logger.warn(message, context ?? {}),
      error: (message, context) => logger.error(message, context ?? {}),
    },
    config: resolveReadinessConfig(),
    now: () => new Date(),
  };
}

/**
 * Common handler body shared by all readiness triggers.
 *
 * Handles: weight_records, health_events (relevant types), nutrition_plans,
 * operational_restrictions.
 */
export async function runReadinessProjection(
  params: ReadinessTriggerParams,
  sourcePath: string,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  const {dogId} = params;

  if (isRecursion(sourcePath)) {
    logger.info("Readiness trigger recursion guard: skipping self-triggered write", {
      dogId,
      sourcePath,
    });
    return;
  }

  if (
    typeof dogId !== "string" ||
    dogId.trim() === "" ||
    dogId.length > 128 ||
    dogId.includes("/")
  ) {
    logger.error("Readiness trigger received invalid dogId", {dogId, sourcePath});
    return;
  }

  try {
    const result = await evaluateHealthReadiness(dogId, buildReadinessProjectorDeps(db));
    if (result.projectionStatus === "ready") {
      logger.info("Readiness projected", {
        dogId,
        readinessStatus: result.readinessStatus,
      });
    } else {
      logger.warn("Readiness projection unavailable", {
        dogId,
        technicalBlockers: result.technicalBlockers,
      });
    }
  } catch (err) {
    logger.error("Readiness projection threw", {dogId, sourcePath, error: String(err)});
    // Re-throw so the trigger runtime retries on transient failures.
    throw err;
  }
}

/**
 * Weight records trigger handler.
 * Fires on create/update/delete of any weight record.
 * A change to weight (including the sole record being deleted) affects readiness.
 */
export async function handleWeightRecordTrigger(
  params: ReadinessTriggerParams,
  snapshot: DocumentSnapshot | undefined,
  sourcePath: string,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  if (!snapshot) {
    logger.info("Readiness weight trigger: received event without snapshot");
    return;
  }
  await runReadinessProjection(params, sourcePath, db);
}

/**
 * Health events trigger handler.
 * Fires on create/update/delete of any health event.
 * Only vaccination, consultation, and exam affect readiness.
 * We delegate to the projector (which re-reads all evidence) rather than
 * trying to selectively filter here — simpler and more robust.
 */
export async function handleHealthEventTrigger(
  params: ReadinessTriggerParams,
  snapshot: DocumentSnapshot | undefined,
  sourcePath: string,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  if (!snapshot) {
    logger.info("Readiness health_event trigger: received event without snapshot");
    return;
  }
  await runReadinessProjection(params, sourcePath, db);
}

/**
 * Nutrition plans trigger handler.
 * Fires on create/update/delete of any nutrition plan.
 */
export async function handleNutritionPlanTrigger(
  params: ReadinessTriggerParams,
  snapshot: DocumentSnapshot | undefined,
  sourcePath: string,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  if (!snapshot) {
    logger.info("Readiness nutrition trigger: received event without snapshot");
    return;
  }
  await runReadinessProjection(params, sourcePath, db);
}

/**
 * Operational restrictions trigger handler.
 * Fires on create/update/delete of any restriction.
 */
export async function handleRestrictionTrigger(
  params: ReadinessTriggerParams,
  snapshot: DocumentSnapshot | undefined,
  sourcePath: string,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  if (!snapshot) {
    logger.info("Readiness restriction trigger: received event without snapshot");
    return;
  }
  await runReadinessProjection(params, sourcePath, db);
}
