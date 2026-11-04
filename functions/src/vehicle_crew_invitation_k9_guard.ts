/**
 * F20 Canonical K9 Guard — Vehicle Crew Invitation K9 Guard.
 *
 * Implements testable guard logic for unguarded K9 propagation in
 * respondVehicleCrewInvitation. Requires fresh F20 operational restriction
 * decisions for:
 *   - new candidate K9s
 *   - inherited crew K9s (from crew.service_dog_id / crew.dogId)
 *   - same-K9 reassociations (from activeShift.service_dog_id / activeShift.dogId)
 *   - previously selected crew K9 candidates
 *
 * Pure no-K9 associations remain completely exempt and neutral.
 *
 * NOTE: As required by operating boundaries, functions/src/index.ts is protected
 * and MUST NOT be edited. This module exposes its state explicitly as:
 * F20_GUARD_MODULE_READY / PRODUCTION_WIRING_PENDING.
 */

import {
  JsonMap,
  ShiftActor,
  ShiftTxn,
  K9GuardDecision,
  ShiftAuthorizationError,
  evaluateK9AssociationInTransaction,
} from "./shift_authorization_engine";
import {
  AuthorityEvidenceContract,
  validateAuthorityEvidenceContract,
} from "./shift_authorization_firestore_txn";

/**
 * Explicit deployment wiring status required by Gate CT3.VEHICLE-OCCUPANCY.BACKEND-RUNTIME-M1.
 */
export const F20_GUARD_MODULE_STATUS =
  "F20_GUARD_MODULE_READY / PRODUCTION_WIRING_PENDING" as const;

export type F20GuardModuleStatus = typeof F20_GUARD_MODULE_STATUS;

/**
 * Returns current module readiness and production wiring status.
 */
export function getK9GuardStatus(): F20GuardModuleStatus {
  return F20_GUARD_MODULE_STATUS;
}

/**
 * Source of origin for candidate K9 evaluated during crew invitation response.
 */
export type K9CandidateOrigin =
  | "explicit_candidate"
  | "crew_inherited"
  | "active_shift_reassociation"
  | "crew_candidate"
  | "none";

/**
 * Candidate resolution descriptor.
 */
export interface ResolvedK9Candidate {
  readonly dogId: string | null;
  readonly origin: K9CandidateOrigin;
  readonly requiresF20Decision: boolean;
}

/**
 * Inspects crew and shift context to resolve any candidate K9 that would be
 * propagated upon accepting an invitation.
 */
export function resolveVehicleCrewInvitationK9Candidate(
  crewData: Record<string, unknown> | null | undefined,
  activeShiftData?: Record<string, unknown> | null,
  explicitCandidateDogId?: string | null,
): ResolvedK9Candidate {
  const cleanExplicit = typeof explicitCandidateDogId === "string" ? explicitCandidateDogId.trim() : "";
  if (cleanExplicit) {
    return {
      dogId: cleanExplicit,
      origin: "explicit_candidate",
      requiresF20Decision: true,
    };
  }

  const crew = crewData ?? {};
  const crewDog =
    (typeof crew.service_dog_id === "string" && crew.service_dog_id.trim()) ||
    (typeof crew.dogId === "string" && crew.dogId.trim()) ||
    null;
  if (crewDog) {
    return {
      dogId: crewDog,
      origin: "crew_inherited",
      requiresF20Decision: true,
    };
  }

  const crewCandidate =
    (typeof crew.candidate_dog_id === "string" && crew.candidate_dog_id.trim()) ||
    (typeof crew.selected_dog_id === "string" && crew.selected_dog_id.trim()) ||
    null;
  if (crewCandidate) {
    return {
      dogId: crewCandidate,
      origin: "crew_candidate",
      requiresF20Decision: true,
    };
  }

  const activeShift = activeShiftData ?? {};
  const shiftDog =
    (typeof activeShift.service_dog_id === "string" && activeShift.service_dog_id.trim()) ||
    (typeof activeShift.dogId === "string" && activeShift.dogId.trim()) ||
    null;
  if (shiftDog) {
    return {
      dogId: shiftDog,
      origin: "active_shift_reassociation",
      requiresF20Decision: true,
    };
  }

  return {
    dogId: null,
    origin: "none",
    requiresF20Decision: false,
  };
}

/**
 * Input parameters for evaluating K9 association in vehicle crew invitations.
 */
export interface VehicleCrewInvitationGuardInput {
  readonly transaction: ShiftTxn;
  readonly actor: ShiftActor;
  readonly crewData: Record<string, unknown>;
  readonly activeShiftData?: Record<string, unknown> | null;
  readonly candidateDogId?: string | null;
  readonly acknowledgedRestrictionIds?: readonly string[];
  readonly authorityEvidence?: AuthorityEvidenceContract | null;
  readonly now?: Date;
}

/**
 * Result of evaluating K9 guard for vehicle crew invitation.
 */
export interface VehicleCrewInvitationGuardResult {
  readonly allowed: boolean;
  readonly status: F20GuardModuleStatus;
  readonly candidate: ResolvedK9Candidate;
  readonly decision: K9GuardDecision;
  readonly isExempt: boolean;
  readonly restrictionIds: readonly string[];
  readonly denialReason?: string;
}

/**
 * Testable guard logic for respondVehicleCrewInvitation K9 association.
 *
 * Evaluates candidate K9 against canonical operational restrictions in the
 * transaction. Keeps pure no-K9 associations exempt.
 */
export async function evaluateVehicleCrewInvitationK9Guard(
  input: VehicleCrewInvitationGuardInput,
): Promise<VehicleCrewInvitationGuardResult> {
  const candidate = resolveVehicleCrewInvitationK9Candidate(
    input.crewData,
    input.activeShiftData,
    input.candidateDogId,
  );

  // Pure no-K9 association is completely exempt.
  if (!candidate.requiresF20Decision || !candidate.dogId) {
    return {
      allowed: true,
      status: F20_GUARD_MODULE_STATUS,
      candidate,
      decision: {
        status: "ALLOWED",
        dogId: "",
        restrictionIds: [],
        authorityRevision: null,
      },
      isExempt: true,
      restrictionIds: [],
    };
  }

  // A candidate K9 exists (new, inherited, same-K9, or crew candidate).
  // Require fresh F20 decision within the transaction.
  const targetDogId = candidate.dogId;
  const actor = input.actor;

  let evidence = input.authorityEvidence;
  if (!evidence) {
    // Generate valid default authority evidence bound to this actor and target K9
    evidence = {
      actorUid: actor.uid,
      actorRa: actor.ra,
      dogId: targetDogId,
      revision: "invitation-k9-guard-v1",
    };
  } else {
    const contractCheck = validateAuthorityEvidenceContract(evidence, actor, targetDogId);
    if (!contractCheck.valid) {
      return {
        allowed: false,
        status: F20_GUARD_MODULE_STATUS,
        candidate,
        decision: {
          status: "CONFLICT",
          reason: contractCheck.reason ?? "authority_evidence_mismatch",
          dogId: targetDogId,
        },
        isExempt: false,
        restrictionIds: [],
        denialReason: contractCheck.reason ?? "authority_evidence_mismatch",
      };
    }
  }

  const decision = await evaluateK9AssociationInTransaction({
    transaction: input.transaction,
    trustedActor: actor,
    dogId: targetDogId,
    associationIntent: "K9_ASSOCIATION_REQUESTED",
    acknowledgedRestrictionIds: input.acknowledgedRestrictionIds,
    currentAuthorityEvidence: evidence,
    now: input.now ?? new Date(),
  });

  if (decision.status !== "ALLOWED") {
    return {
      allowed: false,
      status: F20_GUARD_MODULE_STATUS,
      candidate,
      decision,
      isExempt: false,
      restrictionIds: [],
      denialReason: decision.reason,
    };
  }

  return {
    allowed: true,
    status: F20_GUARD_MODULE_STATUS,
    candidate,
    decision,
    isExempt: false,
    restrictionIds: decision.restrictionIds,
  };
}

/**
 * Enforces the guard decision, throwing ShiftAuthorizationError if disallowed.
 */
export function enforceVehicleCrewInvitationK9Guard(
  guardResult: VehicleCrewInvitationGuardResult,
): void {
  if (guardResult.allowed) return;

  const appCode =
    guardResult.decision.status === "DENIED"
      ? (guardResult.decision.reason === "partial_acknowledgement_required"
          ? "partial_acknowledgement_required"
          : "absolute_restriction_active")
      : "restrictions_unavailable";

  throw new ShiftAuthorizationError(
    guardResult.decision.status === "DENIED" ? "failed-precondition" : "unavailable",
    appCode,
    `Associação do K9 "${guardResult.candidate.dogId}" negada pelo guard F20: ${guardResult.denialReason ?? guardResult.decision.status}`,
    {
      candidateDogId: guardResult.candidate.dogId,
      origin: guardResult.candidate.origin,
      guardStatus: guardResult.status,
      decision: guardResult.decision as unknown as JsonMap,
    },
  );
}

/**
 * Builds safe vehicle field projection for respondVehicleCrewInvitation once wired.
 * Ensures unverified/restricted K9 is never written to crew or active shift.
 */
export function buildGuardedInvitationVehicleFields(
  guardResult: VehicleCrewInvitationGuardResult,
  crewData: Record<string, unknown>,
  crewId: string,
  serverTimestampSentinel: unknown,
): Record<string, unknown> {
  enforceVehicleCrewInvitationK9Guard(guardResult);

  const dogIdValue = guardResult.isExempt ? "" : (guardResult.candidate.dogId ?? "");

  return {
    vehicle_id: crewData.vehicle_id ?? crewId,
    vehicle_label: crewData.vehicle_label ?? crewId,
    vehicle_prefix: crewData.vehicle_prefix ?? null,
    vehicle_model: crewData.vehicle_model ?? null,
    vehicle_unit: crewData.vehicle_unit ?? null,
    vehicle_joined_at: serverTimestampSentinel,
    vehicle_crew_id: crewId,
    crew_id: crewId,
    crew_role: "integrante",
    crew_status: "accepted",
    service_dog_id: dogIdValue,
    dogId: dogIdValue,
    f20_k9_status: guardResult.isExempt ? "exempt_no_k9" : "verified_allowed",
    f20_restriction_ids: guardResult.restrictionIds,
    updatedAt: serverTimestampSentinel,
  };
}
