/**
 * F40 Operational Occupancy Succession Orchestrator.
 *
 * Implements `runSelfRegularizePriorOccupancy` within a single Firestore transaction
 * composing:
 * - F10 Runtime Authority (`f10_firestore_authority_adapter.ts`)
 * - F40 Persistence & Coverage (`occupancy_persistence_contracts.ts`, `operational_engagement_engine.ts`)
 * - F20 Canonical K9 Guard (`shift_authorization_firestore_txn.ts` / `evaluateK9AssociationInTransaction`)
 *
 * Strictly enforces Preconditions 1 through 18 in sequential read-before-write order.
 */

import * as crypto from "crypto";
import {
  resolveTrustedActorInTransaction,
  readAccessProfileGrantInTransaction,
  readAuthoritativeScheduleSnapshotInTransaction,
} from "../f10/f10_firestore_authority_adapter";
import {
  SELF_REGULARIZE,
} from "../f10/f10_runtime_authority_contracts";
import {
  FirestoreShiftTxnAdapter,
} from "../shift_authorization_firestore_txn";
import {
  evaluateK9AssociationInTransaction,
} from "../shift_authorization_engine";
import {
  VehicleOccupancyPointerDoc,
  VehicleOccupancySessionDoc,
  VehicleOccupancyReceiptDoc,
  validateInspectionEvidence,
} from "./occupancy_persistence_contracts";
import {
  CoverageVerdict,
  OccupancySessionState,
} from "./occupancy_domain_contract";
import {
  OccupancyOperationError,
  evaluateOperationalCoverageInTxn,
} from "./operational_engagement_engine";

export interface SelfRegularizePriorOccupancyRequest {
  readonly operationId: string;
  readonly vehicleId: string;
  readonly expectedSessionId: string;
  readonly expectedGeneration: number;
  readonly incomingCrewId: string;
  readonly f10ScheduleSnapshotId: string;
  readonly k9AssociationIntent: "NO_K9_ASSOCIATION" | "K9_ASSOCIATION_REQUESTED";
  readonly dogId?: string | null;
  readonly acknowledgedRestrictionIds?: readonly string[];
  readonly inspectionEvidence: {
    readonly checklistConfirmed: boolean;
    readonly physicalKeysInHand: boolean;
    readonly vehicleOdometerKm?: number | null;
    readonly checklistRef?: string | null;
    readonly notes?: string | null;
  };
}

export interface SelfRegularizePriorOccupancyResponse {
  readonly status: "SUCCESS";
  readonly operationId: string;
  readonly vehicleId: string;
  readonly predecessorSessionId: string;
  readonly predecessorGeneration: number;
  readonly successorSessionId: string;
  readonly successorGeneration: number;
  readonly effectiveCrewId: string;
  readonly effectiveDogId: string | null;
  readonly transitionedAt: string;
  readonly receiptId: string;
  readonly f20Outcome: "ALLOWED" | "NOT_APPLICABLE";
}

function computeSha256(content: string): string {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

function canonicalizeJson(obj: unknown): string {
  return JSON.stringify(obj, Object.keys(obj as object).sort());
}

/**
 * Runs the atomic self-regularization succession transaction.
 */
export async function runSelfRegularizePriorOccupancy(
  db: FirebaseFirestore.Firestore,
  actor: { readonly uid: string; readonly ra?: string },
  request: SelfRegularizePriorOccupancyRequest,
  options?: { readonly now?: Date },
): Promise<SelfRegularizePriorOccupancyResponse> {
  const inputHash = computeSha256(canonicalizeJson(request));
  const receiptRef = db.collection("vehicle_occupancy_receipts").doc(request.operationId);
  const pointerRef = db.collection("vehicle_occupancy").doc(request.vehicleId);
  const vehicleRef = db.collection("vehicles").doc(request.vehicleId);

  // Execute in single atomic transaction with Condition D identity-first replay verification
  return await db.runTransaction(async (tx) => {
    const now = options?.now ?? new Date();
    const nowIso = now.toISOString();

    // =========================================================================
    // STEP 1: TRANSACTIONAL READS (ALL READS BEFORE ALL WRITES)
    // =========================================================================

    // 1. Authenticated UID & Trusted F10 Identity Resolution (Precondition 1)
    const actorResolution = await resolveTrustedActorInTransaction(
      tx,
      db,
      actor.uid,
      actor.ra,
    );
    if (!actorResolution) {
      throw new OccupancyOperationError(
        "permission-denied",
        "permission_denied",
        "Identidade do operador não verificada, inativa ou sem vínculo 1:1 UID/RA no F10.",
      );
    }
    const trustedActor = actorResolution.identity;
    if (!trustedActor.active || !trustedActor.confirmed) {
      throw new OccupancyOperationError(
        "permission-denied",
        "permission_denied",
        "Identidade do operador inativa ou revogada no F10.",
      );
    }

    // 2. Receipt Lookup & Idempotency / Replay Verification (Condition D)
    const txReceiptSnap = await tx.get(receiptRef);
    if (txReceiptSnap.exists) {
      const receipt = txReceiptSnap.data() as VehicleOccupancyReceiptDoc;
      if (receipt.inputHash !== inputHash) {
        throw new OccupancyOperationError(
          "failed-precondition",
          "idempotency_conflict",
          "Operation ID já utilizado com parâmetros diferentes.",
        );
      }
      if (
        receipt.actorUid !== trustedActor.uid ||
        receipt.actorRa.toUpperCase() !== trustedActor.ra.toUpperCase()
      ) {
        throw new OccupancyOperationError(
          "failed-precondition",
          "idempotency_conflict",
          "Recibo de operação pertence a outro operador (conflito de identidade em replay).",
        );
      }
      if (receipt.vehicleId !== request.vehicleId) {
        throw new OccupancyOperationError(
          "failed-precondition",
          "idempotency_conflict",
          "Recibo de operação pertence a outra viatura.",
        );
      }
      if (receipt.expectedSessionId && receipt.expectedSessionId !== request.expectedSessionId) {
        throw new OccupancyOperationError(
          "failed-precondition",
          "idempotency_conflict",
          "Recibo de operação pertence a outra sessão esperada.",
        );
      }
      if (
        receipt.expectedGeneration !== undefined &&
        receipt.expectedGeneration !== request.expectedGeneration
      ) {
        throw new OccupancyOperationError(
          "failed-precondition",
          "idempotency_conflict",
          "Recibo de operação pertence a outra geração esperada.",
        );
      }
      // Exact replay: Return cached historical response with ZERO writes
      return receipt.executionResult as unknown as SelfRegularizePriorOccupancyResponse;
    }

    // 3. Read Pointer
    const pointerSnap = await tx.get(pointerRef);

    // 4. Read Vehicle Catalog Document
    const vehicleSnap = await tx.get(vehicleRef);

    // 5. Read F10 Explicit Capability Grant (Precondition 2 - No Admin Bypass)
    const grant = await readAccessProfileGrantInTransaction(
      tx,
      db,
      trustedActor.ra,
      actorResolution.userDoc,
      SELF_REGULARIZE,
    );
    if (!grant) {
      throw new OccupancyOperationError(
        "permission-denied",
        "permission_denied",
        "Operador não possui grant explícito: vehicles.self_regularize_prior_occupancy.",
      );
    }

    // 6. Read Incoming Crew Membership (Precondition 3)
    const incomingCrewRef = db.collection("vehicle_crews").doc(request.incomingCrewId);
    const incomingCrewSnap = await tx.get(incomingCrewRef);
    const incomingMemberRef = incomingCrewRef.collection("members").doc(trustedActor.ra);
    const incomingMemberSnap = await tx.get(incomingMemberRef);

    let isIncomingMember = false;
    if (incomingCrewSnap.exists) {
      const crewData = incomingCrewSnap.data() ?? {};
      if (
        typeof crewData.titular_handler_id === "string" &&
        crewData.titular_handler_id.toUpperCase() === trustedActor.ra.toUpperCase()
      ) {
        isIncomingMember = true;
      }
    }
    if (!isIncomingMember && incomingMemberSnap.exists) {
      const memberData = incomingMemberSnap.data() ?? {};
      if (
        memberData.status === "active" ||
        memberData.active === true ||
        memberData.confirmed === true
      ) {
        isIncomingMember = true;
      }
    }
    if (!isIncomingMember) {
      throw new OccupancyOperationError(
        "permission-denied",
        "permission_denied",
        `Operador ${trustedActor.ra} não é membro confirmado da guarnição entrante ${request.incomingCrewId}.`,
      );
    }

    // 7. Read Authoritative Schedule Snapshot (Precondition 4 - End + 60m)
    const scheduleValidation = await readAuthoritativeScheduleSnapshotInTransaction(
      tx,
      db,
      request.f10ScheduleSnapshotId,
      nowIso,
    );
    if (!scheduleValidation) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_state",
        `Snapshot de escala ${request.f10ScheduleSnapshotId} inexistente, inválido ou substituído por correção (superseded).`,
      );
    }
    if (!scheduleValidation.eligibleForSelfRegularize) {
      const diffMs = scheduleValidation.thresholdMs - scheduleValidation.nowMs;
      const minutesRemaining = Math.max(1, Math.ceil(diffMs / 60000));
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_state",
        `Limiar temporal de auto-regularização não atingido. Fim da escala + 60 minutos exige mais ${minutesRemaining} minuto(s).`,
      );
    }

    // 8. Precondition 5: Physical Possession & Inspection Evidence
    const inspectionCheck = validateInspectionEvidence(request.inspectionEvidence);
    if (!inspectionCheck.valid) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_argument",
        inspectionCheck.reason ?? "Evidência de vistoria ou posse física inválida.",
      );
    }

    // 9. Precondition 6: Vehicle Catalog & Pointer Exists
    if (!vehicleSnap.exists || vehicleSnap.data()?.active === false) {
      throw new OccupancyOperationError(
        "not-found",
        "not_found",
        `Viatura ${request.vehicleId} inexistente ou inativa no cadastro.`,
      );
    }
    if (!pointerSnap.exists) {
      throw new OccupancyOperationError(
        "not-found",
        "invalid_state",
        `Pointer de ocupação não inicializado para a viatura ${request.vehicleId}.`,
      );
    }

    const pointer = pointerSnap.data() as VehicleOccupancyPointerDoc;

    // 10. Precondition 7: Expected Session ID Validation
    if (pointer.currentSessionId !== request.expectedSessionId) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        `Sessão esperada desatualizada. Esperada: ${request.expectedSessionId}, Vigente: ${pointer.currentSessionId}.`,
      );
    }

    // 11. Precondition 8: Expected Generation Validation
    if (pointer.currentGeneration !== request.expectedGeneration) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        `Geração esperada desatualizada. Esperada: ${request.expectedGeneration}, Vigente: ${pointer.currentGeneration}.`,
      );
    }

    // 12. Precondition 9: Pointer Status Active
    if (pointer.status !== "active") {
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_state",
        `Pointer da viatura está em estado inválido para sucessão: ${pointer.status}.`,
      );
    }

    // 13. Read Predecessor Session (Precondition 10 & 11)
    const predSessionRef = db.collection("vehicle_occupancy_sessions").doc(pointer.currentSessionId);
    const predSessionSnap = await tx.get(predSessionRef);
    if (!predSessionSnap.exists) {
      throw new OccupancyOperationError(
        "not-found",
        "invalid_state",
        `Documento da sessão predecessora ${pointer.currentSessionId} não encontrado.`,
      );
    }
    const predSession = predSessionSnap.data() as VehicleOccupancySessionDoc;

    if (
      predSession.state === OccupancySessionState.stale ||
      predSession.state === OccupancySessionState.successionAllowed ||
      predSession.state === OccupancySessionState.successionDenied ||
      predSession.state === OccupancySessionState.conflicted
    ) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_state",
        `Sessão predecessora está em estado terminal: ${predSession.state}.`,
      );
    }

    // 14. Precondition 12: No Conflicting Successor Already Registered
    if (predSession.successorSessionId !== null && predSession.successorSessionId !== undefined) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "idempotency_conflict",
        `Sessão predecessora já possui sucessora registrada: ${predSession.successorSessionId}.`,
      );
    }

    // 15. Preconditions 13 & 14: Coverage Evaluation
    const coverageEval = await evaluateOperationalCoverageInTxn(
      tx,
      db,
      request.vehicleId,
      predSession,
    );
    if (coverageEval.verdict === CoverageVerdict.BLOCKING) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "invalid_state",
        "Sucessão bloqueada: viatura possui engajamento operacional em andamento.",
      );
    }
    if (coverageEval.verdict !== CoverageVerdict.PROVEN_CLEAR) {
      throw new OccupancyOperationError(
        "failed-precondition",
        "restrictions_unavailable",
        "Cobertura indeterminada: não há evidência autoritativa de encerramento do turno anterior (falha fechada).",
      );
    }

    // 16. Precondition 15: Fresh F20 K9 Guard Decision
    let effectiveServiceDogId: string | null = null;
    let f20ReceiptId: string | null = null;

    if (request.k9AssociationIntent === "K9_ASSOCIATION_REQUESTED") {
      const cleanDogId = typeof request.dogId === "string" ? request.dogId.trim() : "";
      if (!cleanDogId) {
        throw new OccupancyOperationError(
          "invalid-argument",
          "invalid_argument",
          "dogId é obrigatório quando k9AssociationIntent é K9_ASSOCIATION_REQUESTED.",
        );
      }

      const shiftTxnAdapter = new FirestoreShiftTxnAdapter(tx, db);
      const k9Decision = await evaluateK9AssociationInTransaction({
        transaction: shiftTxnAdapter,
        trustedActor: {
          uid: trustedActor.uid,
          ra: trustedActor.ra,
          email: `${trustedActor.ra.toLowerCase()}@canilgcm.com`,
          name: trustedActor.ra,
        },
        dogId: cleanDogId,
        associationIntent: "K9_ASSOCIATION_REQUESTED",
        acknowledgedRestrictionIds: request.acknowledgedRestrictionIds ?? [],
        operationContext: `vehicle_succession:${request.vehicleId}:gen${pointer.currentGeneration + 1}`,
        currentAuthorityEvidence: {
          actorUid: trustedActor.uid,
          actorRa: trustedActor.ra,
          dogId: cleanDogId,
        },
        now,
      });

      if (k9Decision.status === "DENIED") {
        if (k9Decision.reason === "partial_acknowledgement_required") {
          throw new OccupancyOperationError(
            "failed-precondition",
            "invalid_state",
            "K9 apto com restrições. É necessária a ciência do responsável antes de assumir a viatura.",
            {
              code: "partial_acknowledgement_required",
            },
          );
        }
        throw new OccupancyOperationError(
          "failed-precondition",
          "invalid_state",
          `K9 inapto para operação. Restrição ativa: ${k9Decision.reason}`,
          {
            code: "absolute_restriction_active",
            reason: k9Decision.reason,
          },
        );
      }
      if (k9Decision.status !== "ALLOWED") {
        throw new OccupancyOperationError(
          "failed-precondition",
          "restrictions_unavailable",
          `Não foi possível verificar as restrições canônicas do K9 (${k9Decision.reason}). F20 guard falhou fechado.`,
        );
      }

      effectiveServiceDogId = cleanDogId;
      f20ReceiptId = `f20_${request.operationId.substring(0, 8)}`;
    } else {
      effectiveServiceDogId = null;
    }

    // =========================================================================
    // STEP 2: TRANSACTIONAL WRITES (PRECONDITIONS 16, 17, 18)
    // =========================================================================

    const nextGeneration = pointer.currentGeneration + 1;
    const newSessionId = `sess_${request.vehicleId}_g${nextGeneration}_${request.operationId.substring(0, 8)}`;
    const newSessionRef = db.collection("vehicle_occupancy_sessions").doc(newSessionId);

    // 18.1 Update Predecessor Session (State: successionAllowed, successorSessionId: newSessionId)
    const existingAudit = predSession.auditTrail ? [...predSession.auditTrail] : [];
    existingAudit.push({
      action: "SUCCESSION_COMMITTED",
      fromState: String(predSession.state),
      toState: OccupancySessionState.successionAllowed,
      performedAt: now,
      performedByRa: trustedActor.ra,
      reason: "Auto-regularização autorizada e confirmada.",
    });

    tx.update(predSessionRef, {
      state: OccupancySessionState.successionAllowed,
      successorSessionId: newSessionId,
      endedAt: now,
      endedByRa: trustedActor.ra,
      auditTrail: existingAudit,
      updatedAt: now,
    });

    // 18.2 Create Successor Session Document
    const newSessionDoc: VehicleOccupancySessionDoc = {
      sessionId: newSessionId,
      vehicleId: request.vehicleId,
      crewId: request.incomingCrewId,
      generation: nextGeneration,
      predecessorSessionId: pointer.currentSessionId,
      successorSessionId: null,
      state: OccupancySessionState.active,
      admissionProtocol: "CANONICAL_V1",
      serviceDogId: effectiveServiceDogId,
      f20GuardReceiptId: f20ReceiptId,
      f10ScheduleSnapshotId: request.f10ScheduleSnapshotId,
      inspectionEvidence: {
        acknowledged: true,
        physicalKeysInHand: request.inspectionEvidence.physicalKeysInHand,
        recordedAt: now,
        recordedByRa: trustedActor.ra,
        checklistRef: request.inspectionEvidence.checklistRef ?? null,
        notes: request.inspectionEvidence.notes ?? null,
        vehicleOdometerKm: request.inspectionEvidence.vehicleOdometerKm ?? null,
      },
      possessionAcknowledgment: {
        acknowledged: true,
        physicalKeysInHand: request.inspectionEvidence.physicalKeysInHand,
        recordedAt: now,
        actorRa: trustedActor.ra,
      },
      startedAt: now,
      startedByRa: trustedActor.ra,
      endedAt: null,
      endedByRa: null,
      auditTrail: [
        {
          action: "SESSION_INITIALIZED",
          fromState: "none",
          toState: OccupancySessionState.active,
          performedAt: now,
          performedByRa: trustedActor.ra,
          reason: "Sessão iniciada via auto-regularização autorizada.",
        },
      ],
      createdAt: now,
      updatedAt: now,
    };
    tx.set(newSessionRef, newSessionDoc);

    // 18.3 Update Vehicle Occupancy Root Pointer
    tx.update(pointerRef, {
      currentSessionId: newSessionId,
      currentGeneration: nextGeneration,
      currentCrewId: request.incomingCrewId,
      titularHandlerRa: trustedActor.ra,
      serviceDogId: effectiveServiceDogId,
      status: "active",
      lastTransitionAt: now,
      lastTransitionByRa: trustedActor.ra,
      lastTransitionOperationId: request.operationId,
      updatedAt: now,
    });

    // 18.4 Write Idempotency Receipt
    const responsePayload: SelfRegularizePriorOccupancyResponse = {
      status: "SUCCESS",
      operationId: request.operationId,
      vehicleId: request.vehicleId,
      predecessorSessionId: pointer.currentSessionId,
      predecessorGeneration: pointer.currentGeneration,
      successorSessionId: newSessionId,
      successorGeneration: nextGeneration,
      effectiveCrewId: request.incomingCrewId,
      effectiveDogId: effectiveServiceDogId,
      transitionedAt: nowIso,
      receiptId: request.operationId,
      f20Outcome: f20ReceiptId ? "ALLOWED" : "NOT_APPLICABLE",
    };

    tx.set(receiptRef, {
      operationId: request.operationId,
      action: "selfRegularizePriorOccupancy",
      actorRa: trustedActor.ra,
      actorUid: trustedActor.uid,
      vehicleId: request.vehicleId,
      expectedSessionId: request.expectedSessionId,
      expectedGeneration: request.expectedGeneration,
      inputHash,
      status: "COMMITTED",
      executionResult: responsePayload as unknown as Record<string, unknown>,
      createdAt: now,
    });

    // 18.5 Write Immutable Audit Log
    const auditLogRef = db.collection("auditLogs").doc();
    tx.set(auditLogRef, {
      action: "vehicle_occupancy_self_regularized",
      entity_type: "vehicle_occupancy",
      entity_id: request.vehicleId,
      summary: `Auto-regularização da viatura ${request.vehicleId} pela guarnição ${request.incomingCrewId} (Geração ${nextGeneration})`,
      actor: {
        uid: trustedActor.uid,
        ra: trustedActor.ra,
      },
      metadata: {
        operationId: request.operationId,
        predecessorSessionId: pointer.currentSessionId,
        successorSessionId: newSessionId,
        predecessorGeneration: pointer.currentGeneration,
        successorGeneration: nextGeneration,
        f20ReceiptId,
      },
      source: "functions",
      performed_at: now,
      createdAt: now,
    });

    // 18.6 Dual-Write Bridge (Legacy Collections Mirroring)
    const legacyCrewRef = db.collection("vehicle_crews").doc(request.incomingCrewId);
    tx.set(
      legacyCrewRef,
      {
        id: request.incomingCrewId,
        vehicle_id: request.vehicleId,
        service_dog_id: effectiveServiceDogId ?? "",
        titular_handler_id: trustedActor.ra,
        active: true,
        updated_at: now,
      },
      { merge: true },
    );

    const legacyActiveShiftRef = db.collection("active_shifts").doc(trustedActor.ra);
    tx.set(
      legacyActiveShiftRef,
      {
        vehicle_id: request.vehicleId,
        vehicle_crew_id: request.incomingCrewId,
        crew_id: request.incomingCrewId,
        service_dog_id: effectiveServiceDogId ?? "",
        dogId: effectiveServiceDogId ?? "",
        updatedAt: now,
      },
      { merge: true },
    );

    return responsePayload;
  });
}
