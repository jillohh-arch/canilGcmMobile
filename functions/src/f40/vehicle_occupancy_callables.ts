/**
 * F40 Vehicle Occupancy Callables.
 *
 * Implements the HTTPS Callable endpoints for vehicle occupancy operations.
 * Closed-by-default via VEHICLE_OCCUPANCY_SUCCESSION_ENABLED = false.
 *
 * CRITICAL SECURITY CONSTRAINTS:
 * 1. Closed by default: feature flag false blocks execution unless explicitly bypassed in testing.
 * 2. Defensively parses all incoming payloads and rejects malformed types.
 * 3. Discards client claims of trust or administrator bypass.
 * 4. STRICTLY PROHIBITED to export from functions/src/index.ts.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  runSelfRegularizePriorOccupancy,
  SelfRegularizePriorOccupancyRequest,
} from "./occupancy_succession_orchestrator";
import {
  runStartOperationalEngagement,
  runEndOperationalEngagement,
  runExceptionallyReconcileOperationalEngagement,
  OccupancyOperationError,
} from "./operational_engagement_engine";

/**
 * Closed-by-default feature flag. Must remain false until official release gate.
 */
export const VEHICLE_OCCUPANCY_SUCCESSION_ENABLED = false;

export interface CallableExecutionOptions {
  readonly bypassFeatureFlag?: boolean;
  readonly now?: Date;
}

type JsonMap = Record<string, unknown>;

function getFirestoreInstance(db?: FirebaseFirestore.Firestore): FirebaseFirestore.Firestore {
  if (db) return db;
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function assertFeatureEnabled(options?: CallableExecutionOptions): void {
  if (!VEHICLE_OCCUPANCY_SUCCESSION_ENABLED && !options?.bypassFeatureFlag) {
    throw new HttpsError(
      "failed-precondition",
      "A funcionalidade de auto-regularização de viaturas está desabilitada temporariamente.",
      { code: "feature_disabled" },
    );
  }
}

function assertAuthenticated(auth: CallableRequest["auth"]): { uid: string; email?: string } {
  if (!auth || !auth.uid || typeof auth.uid !== "string" || !auth.uid.trim()) {
    throw new HttpsError("unauthenticated", "Autenticação obrigatória.", {
      code: "unauthenticated",
    });
  }
  return {
    uid: auth.uid.trim(),
    email: auth.token?.email ? String(auth.token.email).trim() : undefined,
  };
}

// -----------------------------------------------------------------------------
// 1. Self-Regularize Prior Occupancy
// -----------------------------------------------------------------------------

export async function runVehicleOccupancySelfRegularize(
  data: unknown,
  auth: CallableRequest["auth"],
  dbOverride?: FirebaseFirestore.Firestore,
  options?: CallableExecutionOptions,
): Promise<JsonMap> {
  assertFeatureEnabled(options);
  const user = assertAuthenticated(auth);

  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Payload da requisição inválido.", {
      code: "invalid_argument",
    });
  }

  const raw = data as Record<string, unknown>;
  const operationId = typeof raw.operationId === "string" ? raw.operationId.trim() : "";
  const vehicleId = typeof raw.vehicleId === "string" ? raw.vehicleId.trim() : "";
  const expectedSessionId = typeof raw.expectedSessionId === "string" ? raw.expectedSessionId.trim() : "";
  const expectedGeneration = typeof raw.expectedGeneration === "number" ? raw.expectedGeneration : NaN;
  const incomingCrewId = typeof raw.incomingCrewId === "string" ? raw.incomingCrewId.trim() : "";
  const f10ScheduleSnapshotId = typeof raw.f10ScheduleSnapshotId === "string" ? raw.f10ScheduleSnapshotId.trim() : "";
  const k9AssociationIntent = raw.k9AssociationIntent === "K9_ASSOCIATION_REQUESTED"
    ? "K9_ASSOCIATION_REQUESTED"
    : "NO_K9_ASSOCIATION";
  const dogId = typeof raw.dogId === "string" ? raw.dogId.trim() : null;

  if (
    !operationId ||
    !vehicleId ||
    !expectedSessionId ||
    isNaN(expectedGeneration) ||
    expectedGeneration < 1 ||
    !incomingCrewId ||
    !f10ScheduleSnapshotId
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Campos obrigatórios ausentes ou inválidos na requisição de auto-regularização.",
      { code: "invalid_argument" },
    );
  }

  const inspectionRaw = raw.inspectionEvidence;
  if (!inspectionRaw || typeof inspectionRaw !== "object") {
    throw new HttpsError(
      "invalid-argument",
      "inspectionEvidence é obrigatório para auto-regularização.",
      { code: "invalid_argument" },
    );
  }
  const insp = inspectionRaw as Record<string, unknown>;

  const req: SelfRegularizePriorOccupancyRequest = {
    operationId,
    vehicleId,
    expectedSessionId,
    expectedGeneration,
    incomingCrewId,
    f10ScheduleSnapshotId,
    k9AssociationIntent,
    dogId,
    acknowledgedRestrictionIds: Array.isArray(raw.acknowledgedRestrictionIds)
      ? raw.acknowledgedRestrictionIds.map((id) => String(id).trim()).filter(Boolean)
      : [],
    inspectionEvidence: {
      checklistConfirmed: insp.checklistConfirmed === true,
      physicalKeysInHand: insp.physicalKeysInHand === true,
      vehicleOdometerKm: typeof insp.vehicleOdometerKm === "number" ? insp.vehicleOdometerKm : null,
      checklistRef: typeof insp.checklistRef === "string" ? insp.checklistRef.trim() : null,
      notes: typeof insp.notes === "string" ? insp.notes.trim() : null,
    },
  };

  const db = getFirestoreInstance(dbOverride);

  try {
    const res = await runSelfRegularizePriorOccupancy(
      db,
      { uid: user.uid },
      req,
      { now: options?.now },
    );
    return res as unknown as JsonMap;
  } catch (err: unknown) {
    if (err instanceof OccupancyOperationError) {
      throw new HttpsError(err.httpCode, err.message, {
        code: err.appCode,
        ...err.details,
      });
    }
    const message = err instanceof Error ? err.message : String(err);
    throw new HttpsError("internal", `Falha interna na auto-regularização: ${message}`, {
      code: "internal_error",
    });
  }
}

// -----------------------------------------------------------------------------
// 2. Exceptionally Reconcile Operational Engagement
// -----------------------------------------------------------------------------

export async function runVehicleOccupancyExceptionallyReconcile(
  data: unknown,
  auth: CallableRequest["auth"],
  dbOverride?: FirebaseFirestore.Firestore,
  options?: CallableExecutionOptions,
): Promise<JsonMap> {
  assertFeatureEnabled(options);
  const user = assertAuthenticated(auth);

  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Payload da requisição inválido.", {
      code: "invalid_argument",
    });
  }

  const raw = data as Record<string, unknown>;
  const operationId = typeof raw.operationId === "string" ? raw.operationId.trim() : "";
  const engagementId = typeof raw.engagementId === "string" ? raw.engagementId.trim() : "";
  const vehicleId = typeof raw.vehicleId === "string" ? raw.vehicleId.trim() : "";
  const expectedSessionId = typeof raw.expectedSessionId === "string" ? raw.expectedSessionId.trim() : "";
  const expectedGeneration = typeof raw.expectedGeneration === "number" ? raw.expectedGeneration : NaN;
  const reason = typeof raw.reason === "string" ? raw.reason.trim() : "";
  const evidenceRef = typeof raw.evidenceRef === "string" ? raw.evidenceRef.trim() : "";

  if (
    !operationId ||
    !engagementId ||
    !vehicleId ||
    !expectedSessionId ||
    isNaN(expectedGeneration) ||
    !reason ||
    !evidenceRef
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Campos obrigatórios ausentes para reconciliação excepcional.",
      { code: "invalid_argument" },
    );
  }

  const db = getFirestoreInstance(dbOverride);

  try {
    return await db.runTransaction(async (tx) => {
      const res = await runExceptionallyReconcileOperationalEngagement(tx, db, {
        uid: user.uid,
        engagementId,
        vehicleId,
        expectedSessionId,
        expectedGeneration,
        operationId,
        reason,
        evidenceRef,
        now: options?.now,
      });
      return res as unknown as JsonMap;
    });
  } catch (err: unknown) {
    if (err instanceof OccupancyOperationError) {
      throw new HttpsError(err.httpCode, err.message, {
        code: err.appCode,
        ...err.details,
      });
    }
    const message = err instanceof Error ? err.message : String(err);
    throw new HttpsError("internal", `Falha interna na reconciliação: ${message}`, {
      code: "internal_error",
    });
  }
}

// -----------------------------------------------------------------------------
// 3. Start Operational Engagement
// -----------------------------------------------------------------------------

export async function runVehicleOccupancyStartEngagement(
  data: unknown,
  auth: CallableRequest["auth"],
  dbOverride?: FirebaseFirestore.Firestore,
  options?: CallableExecutionOptions,
): Promise<JsonMap> {
  assertFeatureEnabled(options);
  const user = assertAuthenticated(auth);

  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Payload da requisição inválido.", {
      code: "invalid_argument",
    });
  }

  const raw = data as Record<string, unknown>;
  const operationId = typeof raw.operationId === "string" ? raw.operationId.trim() : "";
  const vehicleId = typeof raw.vehicleId === "string" ? raw.vehicleId.trim() : "";
  const expectedSessionId = typeof raw.expectedSessionId === "string" ? raw.expectedSessionId.trim() : "";
  const expectedGeneration = typeof raw.expectedGeneration === "number" ? raw.expectedGeneration : NaN;
  const linkedOccurrenceId = typeof raw.linkedOccurrenceId === "string" ? raw.linkedOccurrenceId.trim() : null;

  if (!operationId || !vehicleId || !expectedSessionId || isNaN(expectedGeneration)) {
    throw new HttpsError(
      "invalid-argument",
      "Campos obrigatórios ausentes para iniciar engajamento operacional.",
      { code: "invalid_argument" },
    );
  }

  const db = getFirestoreInstance(dbOverride);

  try {
    return await db.runTransaction(async (tx) => {
      const res = await runStartOperationalEngagement(tx, db, {
        uid: user.uid,
        vehicleId,
        expectedSessionId,
        expectedGeneration,
        operationId,
        linkedOccurrenceId,
        now: options?.now,
      });
      return res as unknown as JsonMap;
    });
  } catch (err: unknown) {
    if (err instanceof OccupancyOperationError) {
      throw new HttpsError(err.httpCode, err.message, {
        code: err.appCode,
        ...err.details,
      });
    }
    const message = err instanceof Error ? err.message : String(err);
    throw new HttpsError("internal", `Falha interna ao iniciar engajamento: ${message}`, {
      code: "internal_error",
    });
  }
}

// -----------------------------------------------------------------------------
// 4. End Operational Engagement
// -----------------------------------------------------------------------------

export async function runVehicleOccupancyEndEngagement(
  data: unknown,
  auth: CallableRequest["auth"],
  dbOverride?: FirebaseFirestore.Firestore,
  options?: CallableExecutionOptions,
): Promise<JsonMap> {
  assertFeatureEnabled(options);
  const user = assertAuthenticated(auth);

  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Payload da requisição inválido.", {
      code: "invalid_argument",
    });
  }

  const raw = data as Record<string, unknown>;
  const operationId = typeof raw.operationId === "string" ? raw.operationId.trim() : "";
  const engagementId = typeof raw.engagementId === "string" ? raw.engagementId.trim() : "";
  const vehicleId = typeof raw.vehicleId === "string" ? raw.vehicleId.trim() : "";
  const expectedSessionId = typeof raw.expectedSessionId === "string" ? raw.expectedSessionId.trim() : "";
  const expectedGeneration = typeof raw.expectedGeneration === "number" ? raw.expectedGeneration : NaN;

  if (!operationId || !engagementId || !vehicleId || !expectedSessionId || isNaN(expectedGeneration)) {
    throw new HttpsError(
      "invalid-argument",
      "Campos obrigatórios ausentes para finalizar engajamento operacional.",
      { code: "invalid_argument" },
    );
  }

  const db = getFirestoreInstance(dbOverride);

  try {
    return await db.runTransaction(async (tx) => {
      const res = await runEndOperationalEngagement(tx, db, {
        uid: user.uid,
        engagementId,
        vehicleId,
        expectedSessionId,
        expectedGeneration,
        operationId,
        now: options?.now,
      });
      return res as unknown as JsonMap;
    });
  } catch (err: unknown) {
    if (err instanceof OccupancyOperationError) {
      throw new HttpsError(err.httpCode, err.message, {
        code: err.appCode,
        ...err.details,
      });
    }
    const message = err instanceof Error ? err.message : String(err);
    throw new HttpsError("internal", `Falha interna ao finalizar engajamento: ${message}`, {
      code: "internal_error",
    });
  }
}

// -----------------------------------------------------------------------------
// Cloud Functions v2 Triggers (NOT EXPORTED IN functions/src/index.ts)
// -----------------------------------------------------------------------------

export const vehicleOccupancySelfRegularizePriorOccupancy = onCall(
  { region: "southamerica-east1" },
  async (request) => {
    return runVehicleOccupancySelfRegularize(request.data, request.auth);
  },
);

export const vehicleOccupancyExceptionallyReconcileOperationalEngagement = onCall(
  { region: "southamerica-east1" },
  async (request) => {
    return runVehicleOccupancyExceptionallyReconcile(request.data, request.auth);
  },
);

export const vehicleOccupancyStartOperationalEngagement = onCall(
  { region: "southamerica-east1" },
  async (request) => {
    return runVehicleOccupancyStartEngagement(request.data, request.auth);
  },
);

export const vehicleOccupancyEndOperationalEngagement = onCall(
  { region: "southamerica-east1" },
  async (request) => {
    return runVehicleOccupancyEndEngagement(request.data, request.auth);
  },
);
