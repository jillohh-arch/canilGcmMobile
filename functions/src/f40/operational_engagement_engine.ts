/**
 * F40 Operational Engagement Engine — Server-Side Transactional Operations
 * and Authoritative Coverage Protocol.
 *
 * Implements:
 * 1. `runStartOperationalEngagement`
 * 2. `runEndOperationalEngagement`
 * 3. `runExceptionallyReconcileOperationalEngagement`
 * 4. Authoritative Coverage Evaluation (`evaluateOperationalCoverageInTxn`)
 *
 * Follows:
 * - Functional Policy 5.2 (Operational engagement decoupled from occurrence status).
 * - Functional Policy 5.3 (Any confirmed active crew member can start/end engagements).
 * - Functional Policy 5.5 (Server-derived coverage proof; fail-closed; zero query is INDETERMINATE).
 * - Functional Policy 5.8 (Supervisor-only exceptional reconciliation with explicit grant).
 */

import * as crypto from "crypto";
import {
  resolveTrustedActorInTransaction,
  readAccessProfileGrantInTransaction,
} from "../f10/f10_firestore_authority_adapter";
import {
  EXCEPTIONAL_RECONCILE,
} from "../f10/f10_runtime_authority_contracts";
import {
  OperationalEngagementDoc,
  VehicleOccupancyPointerDoc,
  VehicleOccupancySessionDoc,
  VehicleOccupancyReceiptDoc,
} from "./occupancy_persistence_contracts";
import {
  CoverageVerdict,
} from "./occupancy_domain_contract";

export class OccupancyOperationError extends Error {
  constructor(
    public readonly httpCode:
      | "failed-precondition"
      | "permission-denied"
      | "not-found"
      | "invalid-argument"
      | "internal",
    public readonly appCode:
      | "invalid_state"
      | "restrictions_unavailable"
      | "idempotency_conflict"
      | "permission_denied"
      | "invalid_argument"
      | "not_found",
    message: string,
    public readonly details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "OccupancyOperationError";
  }
}

function computeSha256(content: string): string {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

function canonicalizeJson(obj: unknown): string {
  return JSON.stringify(obj, Object.keys(obj as object).sort());
}

/**
 * Checks if actor is an active, confirmed member of the vehicle crew or titular handler.
 */
async function assertActiveCrewMembershipInTxn(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  crewId: string,
  actorRa: string,
  titularHandlerRa?: string,
): Promise<boolean> {
  if (titularHandlerRa && titularHandlerRa.toUpperCase() === actorRa.toUpperCase()) {
    return true;
  }
  const memberRef = db.collection("vehicle_crews").doc(crewId).collection("members").doc(actorRa);
  const snap = await tx.get(memberRef);
  if (!snap.exists) {
    return false;
  }
  const data = snap.data() ?? {};
  return data.status === "active" || data.active === true || data.confirmed === true;
}

// -----------------------------------------------------------------------------
// 1. Start Operational Engagement
// -----------------------------------------------------------------------------

export interface StartOperationalEngagementInput {
  readonly uid: string;
  readonly vehicleId: string;
  readonly expectedSessionId: string;
  readonly expectedGeneration: number;
  readonly operationId: string;
  readonly linkedOccurrenceId?: string | null;
  readonly now?: Date;
}

export interface StartOperationalEngagementResult {
  readonly status: "STARTED";
  readonly engagementId: string;
  readonly vehicleId: string;
  readonly occupancySessionId: string;
  readonly generation: number;
  readonly startedAt: string;
}

export async function runStartOperationalEngagement(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  input: StartOperationalEngagementInput,
): Promise<StartOperationalEngagementResult> {
  const actor = await resolveTrustedActorInTransaction(tx, db, input.uid);
  if (!actor) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Identidade do operador não verificada ou inativa no F10.",
    );
  }

  const receiptRef = db.collection("vehicle_occupancy_receipts").doc(input.operationId);
  const receiptSnap = await tx.get(receiptRef);
  const inputHash = computeSha256(canonicalizeJson(input));

  if (receiptSnap.exists) {
    const receipt = receiptSnap.data() as VehicleOccupancyReceiptDoc;
    if (receipt.inputHash !== inputHash) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        "Operation ID já utilizado com parâmetros diferentes.",
      );
    }
    return receipt.executionResult as unknown as StartOperationalEngagementResult;
  }

  const pointerRef = db.collection("vehicle_occupancy").doc(input.vehicleId);
  const pointerSnap = await tx.get(pointerRef);
  if (!pointerSnap.exists) {
    throw new OccupancyOperationError(
      "not-found",
      "not_found",
      `Pointer da viatura ${input.vehicleId} não encontrado.`,
    );
  }

  const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;
  if (pointer.status !== "active") {
    throw new OccupancyOperationError(
      "failed-precondition",
      "invalid_state",
      `Viatura ${input.vehicleId} em status não operacional: ${pointer.status}.`,
    );
  }

  if (pointer.currentSessionId !== input.expectedSessionId) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "idempotency_conflict",
      `Sessão desatualizada. Esperada: ${input.expectedSessionId}, Vigente: ${pointer.currentSessionId}.`,
    );
  }

  if (pointer.currentGeneration !== input.expectedGeneration) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "idempotency_conflict",
      `Geração desatualizada. Esperada: ${input.expectedGeneration}, Vigente: ${pointer.currentGeneration}.`,
    );
  }

  // Verify actor belongs to current crew
  const isMember = await assertActiveCrewMembershipInTxn(
    tx,
    db,
    pointer.currentCrewId,
    actor.identity.ra,
    pointer.titularHandlerRa,
  );
  if (!isMember) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Operador não é membro ativo da guarnição atualmente ocupante da viatura.",
    );
  }

  const engagementId = `eng_${input.vehicleId}_${input.expectedGeneration}_${input.operationId.substring(0, 8)}`;
  const engagementRef = db.collection("operational_engagements").doc(engagementId);
  const engagementSnap = await tx.get(engagementRef);
  if (engagementSnap.exists) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "idempotency_conflict",
      `Engajamento ${engagementId} já existente.`,
    );
  }

  const serverTs = input.now ?? new Date();
  const engagementDoc: OperationalEngagementDoc = {
    engagementId,
    linkedOccurrenceId: input.linkedOccurrenceId ?? null,
    occupancySessionId: pointer.currentSessionId,
    vehicleId: input.vehicleId,
    vehicleGeneration: pointer.currentGeneration,
    status: "active",
    serverConfirmed: true,
    isBlocking: true,
    startedAt: serverTs,
    startedByRa: actor.identity.ra,
    endedAt: null,
    endedByRa: null,
    exceptionalReconciliation: null,
    createdAt: serverTs,
    updatedAt: serverTs,
  };

  tx.set(engagementRef, engagementDoc);

  // Bump pointer updatedAt to register OCC touch
  tx.update(pointerRef, {
    updatedAt: serverTs,
  });

  const response: StartOperationalEngagementResult = {
    status: "STARTED",
    engagementId,
    vehicleId: input.vehicleId,
    occupancySessionId: pointer.currentSessionId,
    generation: pointer.currentGeneration,
    startedAt: serverTs.toISOString(),
  };

  tx.set(receiptRef, {
    operationId: input.operationId,
    action: "startOperationalEngagement",
    actorRa: actor.identity.ra,
    actorUid: actor.identity.uid,
    vehicleId: input.vehicleId,
    inputHash,
    status: "COMMITTED",
    executionResult: response as unknown as Record<string, unknown>,
    createdAt: serverTs,
  });

  return response;
}

// -----------------------------------------------------------------------------
// 2. End Operational Engagement
// -----------------------------------------------------------------------------

export interface EndOperationalEngagementInput {
  readonly uid: string;
  readonly engagementId: string;
  readonly vehicleId: string;
  readonly expectedSessionId: string;
  readonly expectedGeneration: number;
  readonly operationId: string;
  readonly now?: Date;
}

export interface EndOperationalEngagementResult {
  readonly status: "ENDED";
  readonly engagementId: string;
  readonly vehicleId: string;
  readonly endedAt: string;
}

export async function runEndOperationalEngagement(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  input: EndOperationalEngagementInput,
): Promise<EndOperationalEngagementResult> {
  const actor = await resolveTrustedActorInTransaction(tx, db, input.uid);
  if (!actor) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Identidade do operador não verificada ou inativa no F10.",
    );
  }

  const receiptRef = db.collection("vehicle_occupancy_receipts").doc(input.operationId);
  const receiptSnap = await tx.get(receiptRef);
  const inputHash = computeSha256(canonicalizeJson(input));

  if (receiptSnap.exists) {
    const receipt = receiptSnap.data() as VehicleOccupancyReceiptDoc;
    if (receipt.inputHash !== inputHash) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        "Operation ID já utilizado com parâmetros diferentes.",
      );
    }
    return receipt.executionResult as unknown as EndOperationalEngagementResult;
  }

  const pointerRef = db.collection("vehicle_occupancy").doc(input.vehicleId);
  const pointerSnap = await tx.get(pointerRef);
  if (!pointerSnap.exists) {
    throw new OccupancyOperationError(
      "not-found",
      "not_found",
      `Pointer da viatura ${input.vehicleId} não encontrado.`,
    );
  }

  const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;
  if (pointer.currentGeneration !== input.expectedGeneration) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "idempotency_conflict",
      `Geração desatualizada. Esperada: ${input.expectedGeneration}, Vigente: ${pointer.currentGeneration}.`,
    );
  }

  const isMember = await assertActiveCrewMembershipInTxn(
    tx,
    db,
    pointer.currentCrewId,
    actor.identity.ra,
    pointer.titularHandlerRa,
  );
  if (!isMember) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Operador não é membro ativo da guarnição responsável pelo engajamento.",
    );
  }

  const engagementRef = db.collection("operational_engagements").doc(input.engagementId);
  const engagementSnap = await tx.get(engagementRef);
  if (!engagementSnap.exists) {
    throw new OccupancyOperationError(
      "not-found",
      "not_found",
      `Engajamento ${input.engagementId} não encontrado.`,
    );
  }

  const engagement = engagementSnap.data() as OperationalEngagementDoc;
  if (engagement.vehicleId !== input.vehicleId) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "invalid_argument",
      "Viatura do engajamento não corresponde à informada.",
    );
  }

  if (engagement.status !== "active") {
    throw new OccupancyOperationError(
      "failed-precondition",
      "invalid_state",
      `Engajamento ${input.engagementId} já finalizado (status: ${engagement.status}).`,
    );
  }

  const serverTs = input.now ?? new Date();
  tx.update(engagementRef, {
    status: "ended",
    isBlocking: false,
    endedAt: serverTs,
    endedByRa: actor.identity.ra,
    updatedAt: serverTs,
  });

  const response: EndOperationalEngagementResult = {
    status: "ENDED",
    engagementId: input.engagementId,
    vehicleId: input.vehicleId,
    endedAt: serverTs.toISOString(),
  };

  tx.set(receiptRef, {
    operationId: input.operationId,
    action: "endOperationalEngagement",
    actorRa: actor.identity.ra,
    actorUid: actor.identity.uid,
    vehicleId: input.vehicleId,
    inputHash,
    status: "COMMITTED",
    executionResult: response as unknown as Record<string, unknown>,
    createdAt: serverTs,
  });

  return response;
}

// -----------------------------------------------------------------------------
// 3. Exceptionally Reconcile Operational Engagement (Supervisor Only)
// -----------------------------------------------------------------------------

export interface ExceptionallyReconcileInput {
  readonly uid: string;
  readonly engagementId: string;
  readonly vehicleId: string;
  readonly expectedSessionId: string;
  readonly expectedGeneration: number;
  readonly operationId: string;
  readonly reason: string;
  readonly evidenceRef: string;
  readonly now?: Date;
}

export interface ExceptionallyReconcileResult {
  readonly status: "RECONCILED";
  readonly engagementId: string;
  readonly vehicleId: string;
  readonly reconciledAt: string;
  readonly reconciledByRa: string;
}

export async function runExceptionallyReconcileOperationalEngagement(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  input: ExceptionallyReconcileInput,
): Promise<ExceptionallyReconcileResult> {
  const actor = await resolveTrustedActorInTransaction(tx, db, input.uid);
  if (!actor) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Identidade do supervisor não verificada ou inativa no F10.",
    );
  }

  // F10 Capability check: vehicles.exceptionally_reconcile_operational_engagement
  const grant = await readAccessProfileGrantInTransaction(
    tx,
    db,
    actor.identity.ra,
    actor.userDoc,
    EXCEPTIONAL_RECONCILE,
  );
  if (!grant || !grant.designation) {
    throw new OccupancyOperationError(
      "permission-denied",
      "permission_denied",
      "Reconciliação excepcional requer perfil ativo com designação formal de supervisor ou inspetor.",
    );
  }

  if (!input.reason?.trim() || !input.evidenceRef?.trim()) {
    throw new OccupancyOperationError(
      "invalid-argument",
      "invalid_argument",
      "Reconciliação excepcional exige justificativa detalhada e referência de evidência (ex: rádio CAD/BO).",
    );
  }

  const receiptRef = db.collection("vehicle_occupancy_receipts").doc(input.operationId);
  const receiptSnap = await tx.get(receiptRef);
  const inputHash = computeSha256(canonicalizeJson(input));

  if (receiptSnap.exists) {
    const receipt = receiptSnap.data() as VehicleOccupancyReceiptDoc;
    if (receipt.inputHash !== inputHash) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        "Operation ID já utilizado com parâmetros diferentes.",
      );
    }
    return receipt.executionResult as unknown as ExceptionallyReconcileResult;
  }

  const pointerRef = db.collection("vehicle_occupancy").doc(input.vehicleId);
  const pointerSnap = await tx.get(pointerRef);
  if (!pointerSnap.exists) {
    throw new OccupancyOperationError(
      "not-found",
      "not_found",
      `Pointer da viatura ${input.vehicleId} não encontrado.`,
    );
  }

  const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;
  if (pointer.currentGeneration !== input.expectedGeneration) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "idempotency_conflict",
      `Geração desatualizada. Esperada: ${input.expectedGeneration}, Vigente: ${pointer.currentGeneration}.`,
    );
  }

  const engagementRef = db.collection("operational_engagements").doc(input.engagementId);
  const engagementSnap = await tx.get(engagementRef);
  if (!engagementSnap.exists) {
    throw new OccupancyOperationError(
      "not-found",
      "not_found",
      `Engajamento ${input.engagementId} não encontrado.`,
    );
  }

  const engagement = engagementSnap.data() as OperationalEngagementDoc;
  if (engagement.vehicleId !== input.vehicleId) {
    throw new OccupancyOperationError(
      "failed-precondition",
      "invalid_argument",
      "Viatura do engajamento não corresponde à informada.",
    );
  }

  if (engagement.status !== "active") {
    throw new OccupancyOperationError(
      "failed-precondition",
      "invalid_state",
      `Engajamento ${input.engagementId} já finalizado (status: ${engagement.status}).`,
    );
  }

  const serverTs = input.now ?? new Date();
  tx.update(engagementRef, {
    status: "exceptionally_reconciled",
    isBlocking: false,
    endedAt: serverTs,
    endedByRa: actor.identity.ra,
    exceptionalReconciliation: {
      reconciledAt: serverTs,
      supervisorRa: actor.identity.ra,
      supervisorUid: actor.identity.uid,
      reason: input.reason.trim(),
      evidenceRef: input.evidenceRef.trim(),
      supervisorDesignationSnapshotId: grant.profileId,
    },
    updatedAt: serverTs,
  });

  // Emits immutable audit log
  const auditLogRef = db.collection("auditLogs").doc();
  tx.set(auditLogRef, {
    action: "operational_engagement_exceptionally_reconciled",
    entity_type: "operational_engagement",
    entity_id: input.engagementId,
    actor: {
      uid: actor.identity.uid,
      ra: actor.identity.ra,
      designation: grant.designation,
    },
    vehicleId: input.vehicleId,
    reason: input.reason.trim(),
    evidenceRef: input.evidenceRef.trim(),
    performedAt: serverTs,
  });

  const response: ExceptionallyReconcileResult = {
    status: "RECONCILED",
    engagementId: input.engagementId,
    vehicleId: input.vehicleId,
    reconciledAt: serverTs.toISOString(),
    reconciledByRa: actor.identity.ra,
  };

  tx.set(receiptRef, {
    operationId: input.operationId,
    action: "exceptionallyReconcileOperationalEngagement",
    actorRa: actor.identity.ra,
    actorUid: actor.identity.uid,
    vehicleId: input.vehicleId,
    inputHash,
    status: "COMMITTED",
    executionResult: response as unknown as Record<string, unknown>,
    createdAt: serverTs,
  });

  return response;
}

// -----------------------------------------------------------------------------
// 4. Authoritative Coverage Protocol (Fail-Closed)
// -----------------------------------------------------------------------------

export interface AuthoritativeCoverageEvaluation {
  readonly verdict: CoverageVerdict;
  readonly activeBlockingCount: number;
  readonly activeEngagements: readonly OperationalEngagementDoc[];
  readonly clearanceProvenanceRef: string | null;
  readonly reason: string;
}

/**
 * Evaluates operational coverage inside transaction.
 *
 * Requirements:
 * 1. Blocking engagements take absolute priority -> CoverageVerdict.BLOCKING.
 * 2. Empty or unproven evidence fails closed -> CoverageVerdict.INDETERMINATE.
 * 3. PROVEN_CLEAR requires 0 active blocking engagements AND positive
 *    server-attested clearance proof in predecessor session audit trail.
 */
export async function evaluateOperationalCoverageInTxn(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  vehicleId: string,
  predecessorSessionDoc: VehicleOccupancySessionDoc,
): Promise<AuthoritativeCoverageEvaluation> {
  const engagementsSnap = await tx.get(
    db.collection("operational_engagements")
      .where("vehicleId", "==", vehicleId)
      .where("occupancySessionId", "==", predecessorSessionDoc.sessionId)
      .where("status", "==", "active"),
  );

  const activeEngagements = engagementsSnap.docs.map(
    (d) => d.data() as OperationalEngagementDoc,
  );

  const blockingEngagements = activeEngagements.filter(
    (e) => e.isBlocking !== false && e.status === "active",
  );

  if (blockingEngagements.length > 0) {
    return {
      verdict: CoverageVerdict.BLOCKING,
      activeBlockingCount: blockingEngagements.length,
      activeEngagements: blockingEngagements,
      clearanceProvenanceRef: null,
      reason: `Viatura com ${blockingEngagements.length} engajamento(s) operacional(is) em andamento.`,
    };
  }

  // 2. Provenance and admission cutover check (Condition A)
  // If the session was admitted under canonical protocol (CANONICAL_V1) or has verified positive clearance:
  // - CANONICAL_V1 sessions are fenced against direct client writers.
  // - If 0 active engagements exist, an event-free CANONICAL_V1 session is PROVEN_CLEAR
  //   without requiring the outgoing crew to have logged an artificial audit event.
  // - If the session is LEGACY_UNPROVEN (or lacks canonical admission protocol), fail closed to INDETERMINATE.
  const isCanonicalSession = predecessorSessionDoc.admissionProtocol === "CANONICAL_V1";

  const clearanceAudit = predecessorSessionDoc.auditTrail?.find(
    (a) =>
      a.action === "MISSION_COMPLETED" ||
      a.action === "RETURNED_TO_BASE" ||
      a.action === "PATROL_CONCLUDED" ||
      a.action === "COVERAGE_CLEARED_BY_BASE",
  );

  if (!isCanonicalSession && !clearanceAudit) {
    return {
      verdict: CoverageVerdict.INDETERMINATE,
      activeBlockingCount: 0,
      activeEngagements: [],
      clearanceProvenanceRef: null,
      reason: "Sessão predecessora sem protocolo de admissão canônico ou proveniência comprovada (LEGACY_UNPROVEN; falha fechada conforme Condição A).",
    };
  }

  const clearanceProvenance = isCanonicalSession
    ? "CANONICAL_ADMISSION_PROTOCOL_V1"
    : (clearanceAudit?.action ?? "UNKNOWN");

  return {
    verdict: CoverageVerdict.PROVEN_CLEAR,
    activeBlockingCount: 0,
    activeEngagements: [],
    clearanceProvenanceRef: clearanceProvenance,
    reason: `Cobertura comprovada limpa por proveniência autoritativa: ${clearanceProvenance}.`,
  };
}
