/**
 * Readiness v1 — callable refresh handler.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Allows authenticated callers to force a readiness re-evaluation for a specific
 * K9. This is useful when:
 * - Evidence was migrated from a legacy source
 * - An admin wants to force recalculation after bulk data fixes
 * - A client needs to verify current readiness state
 *
 * Auth: required. The caller must be authenticated.
 * Dog access: the caller must have health.read permission for the dog.
 *
 * The callable does NOT accept a readiness_status from the client. It reads all
 * evidence server-side and evaluates independently. It calls the SAME projector
 * used by the triggers.
 */

import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {buildReadinessProjectorDeps} from "./health_readiness_trigger_handlers";
import {evaluateHealthReadiness} from "./health_readiness_projector";
import {
  classifyConvergence,
  ConvergenceReport,
  readObservedReadyGeneration,
} from "./health_readiness_generation";

export interface ReadinessRefreshResult {
  readonly dogId: string;
  readonly projectionStatus: "ready" | "unavailable";
  readonly readinessStatus: string | null;
  readonly readinessLabel: string | null;
  readonly readinessReasonCode: string | null;
  readonly technicalBlockers: readonly string[];
  readonly operation: string;
  /**
   * Causal barrier for this refresh (B4-R.C2). ADDITIVE — every field above
   * keeps its frozen name and meaning.
   *
   * Deliberately separate from `ok`: `ok` remains the legacy "the callable ran
   * under its contract" signal, so an already-shipped client that only reads
   * `response['ok']` is unaffected. It is therefore valid and expected to see
   * `ok: true` together with a non-confirmed convergence.
   */
  readonly convergence: ConvergenceReport;
}

export interface ReadinessRefreshError {
  readonly dogId: string;
  readonly code: string;
  readonly message: string;
}

export type ReadinessRefreshResponse =
  | {ok: true; result: ReadinessRefreshResult}
  | {ok: false; error: ReadinessRefreshError};

export interface HealthReadinessCallableDeps {
  /**
   * Authenticates the caller. Throws HttpsError if unauthenticated.
   * Returns the caller's uid.
   */
  requireAuth: (auth: CallableRequest["auth"]) => Promise<{uid: string}>;
  /**
   * Validates that the caller has health.read permission for this dog.
   * Throws HttpsError("permission-denied") if not authorized.
   */
  requireHealthReadAccess: (uid: string, dogId: string) => Promise<void>;
}

function isValidDogId(dogId: unknown): dogId is string {
  return (
    typeof dogId === "string" &&
    dogId.trim().length > 0 &&
    dogId.length <= 128 &&
    !dogId.includes("/") &&
    dogId !== "." &&
    dogId !== ".."
  );
}

export function buildHealthReadinessRefreshHandler(
  deps: HealthReadinessCallableDeps,
  db: FirebaseFirestore.Firestore,
) {
  return async function healthReadinessRefresh(
    request: CallableRequest,
  ): Promise<ReadinessRefreshResponse> {
    // 1. Authenticate.
    let callerUid: string;
    try {
      callerUid = (await deps.requireAuth(request.auth)).uid;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("unauthenticated", "Autenticacao obrigatoria.");
    }

    // 2. Validate request payload — do NOT accept readiness_status from client.
    const data = request.data as Record<string, unknown> | undefined;
    if (!isValidDogId(data?.dogId)) {
      return {
        ok: false,
        error: {
          dogId: String(data?.dogId ?? "undefined"),
          code: "invalid_dog_id",
          message: "dogId e obrigatorio e deve ser um ID valido.",
        },
      };
    }
    const dogId = String(data.dogId);

    // Guard against a client trying to pass a pre-computed readiness result.
    if (data.readinessStatus !== undefined) {
      logger.warn("healthReadinessRefresh: client attempted to pass readinessStatus", {
        callerUid,
        dogId,
        attemptedValue: String(data.readinessStatus),
      });
      // Return error, do not proceed.
      return {
        ok: false,
        error: {
          dogId,
          code: "invalid_payload",
          message: "O servidor nao aceita readiness_status do cliente.",
        },
      };
    }

    // 3. Authorize.
    try {
      await deps.requireHealthReadAccess(callerUid, dogId);
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "permission-denied",
        "Voce nao tem acesso a este cao.",
      );
    }

    // 4. Call the same projector used by the triggers.
    const result = await evaluateHealthReadiness(dogId, buildReadinessProjectorDeps(db));

    if (result.projectionStatus === "ready") {
      logger.info("healthReadinessRefresh: success", {callerUid, dogId});
    } else {
      logger.warn("healthReadinessRefresh: unavailable", {
        callerUid,
        dogId,
        technicalBlockers: result.technicalBlockers,
      });
    }

    // 5. Reread the summary — this is the causal observation point.
    //
    // C1 read this only on the ready path, purely to source the two display
    // labels. C2 needs it on every path, because `observedGeneration` must be
    // reported even when the projection came back unavailable. A failed reread
    // stays best-effort and yields a null observation, which can only ever make
    // convergence LESS confirmed — never more.
    const snapshot = await db
      .collection("dogs")
      .doc(dogId)
      .collection("health_summary")
      .doc("current")
      .get()
      .catch(() => null);

    const snapshotData = snapshot?.exists ?
      snapshot.data() as Record<string, unknown> :
      null;

    // Legacy label derivation stays gated on the ready path exactly as before,
    // so the two display fields keep their frozen values byte for byte.
    const readySnapshotData = result.operation === "ready" ? snapshotData : null;

    const isUnavailableResult = result.operation !== "ready";

    const convergence: ConvergenceReport = classifyConvergence({
      requiredGeneration: result.requiredGeneration,
      observedGeneration: readObservedReadyGeneration(snapshotData),
      observedProjectionStatus: snapshotData?.["projection_status"],
      isUnavailableResult,
    });

    if (convergence.status !== "confirmed") {
      // Never silent: an unproven barrier is a diagnosable condition, even
      // though `ok` stays true for legacy compatibility.
      logger.warn("healthReadinessRefresh: convergence not confirmed", {
        callerUid,
        dogId,
        convergenceStatus: convergence.status,
        requiredGeneration: convergence.requiredGeneration,
        observedGeneration: convergence.observedGeneration,
        operation: result.operation,
        applyOutcome: result.applyOutcome,
      });
    }

    return {
      ok: true,
      result: {
        dogId,
        projectionStatus: result.projectionStatus,
        readinessStatus: result.readinessStatus,
        readinessLabel: readySnapshotData?.["readiness_label"] as string | null ?? null,
        readinessReasonCode:
          readySnapshotData?.["readiness_reason_code"] as string | null ?? null,
        technicalBlockers: result.technicalBlockers,
        operation: result.operation,
        convergence,
      },
    };
  };
}
