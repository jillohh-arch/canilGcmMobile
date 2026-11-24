/**
 * F40 Operational Occupancy Persistence Contracts.
 *
 * Defines canonical schemas, validators, and provenance contracts for:
 * 1. Root Pointer: `vehicle_occupancy/{vehicleId}`
 * 2. Session Record: `vehicle_occupancy_sessions/{sessionId}`
 * 3. Operational Engagement: `operational_engagements/{engagementId}`
 * 4. Command Receipt: `vehicle_occupancy_receipts/{operationId}`
 * 5. Physical Inspection and Possession Declarations
 * 6. Coverage Provenance & Evaluation Inputs
 *
 * Distinguishes:
 * - Client-declared state: operator checklists, odometers, operation intentions.
 * - Server-confirmed state: UID/RA bindings, server timestamps, verified coverages.
 * - Persisted state: documents stored within canonical collections.
 * - Derived state: coverage verdicts, eligibility calculations.
 */

export const SCHEMA_VERSION = 1;

// -----------------------------------------------------------------------------
// 1. Root Pointer: vehicle_occupancy/{vehicleId}
// -----------------------------------------------------------------------------

export type VehicleOccupancyPointerStatus =
  | "active"
  | "conflicted"
  | "locked"
  | "transitioning";

export interface VehicleOccupancyPointerDoc {
  readonly vehicleId: string;
  readonly currentSessionId: string;
  readonly currentGeneration: number;
  readonly status: VehicleOccupancyPointerStatus;
  readonly currentCrewId: string;
  readonly titularHandlerRa: string;
  readonly serviceDogId: string | null;
  readonly lastTransitionAt: unknown;
  readonly lastTransitionByRa: string;
  readonly lastTransitionOperationId: string;
  readonly schemaVersion: number;
  readonly updatedAt: unknown;
}

// -----------------------------------------------------------------------------
// 2. Session Record: vehicle_occupancy_sessions/{sessionId}
// -----------------------------------------------------------------------------

export type OccupancySessionStateType =
  | "active"
  | "selfRegularizationRequested"
  | "coverageValidated"
  | "successionAllowed"
  | "successionDenied"
  | "conflicted"
  | "stale";

export interface VehicleInspectionDeclaration {
  readonly checklistConfirmed: boolean;
  readonly physicalKeysInHand: boolean;
  readonly vehicleOdometerKm?: number | null;
  readonly checklistRef?: string | null;
  readonly notes?: string | null;
}

export interface PhysicalPossessionDeclaration {
  readonly acknowledged: boolean;
  readonly physicalKeysInHand: boolean;
  readonly recordedAt: unknown;
  readonly actorRa: string;
}

export interface OccupancyAuditEntry {
  readonly action: string;
  readonly fromState: string;
  readonly toState: string;
  readonly performedAt: unknown;
  readonly performedByRa: string;
  readonly reason: string | null;
}

export interface VehicleOccupancySessionDoc {
  readonly sessionId: string;
  readonly vehicleId: string;
  readonly crewId: string;
  readonly generation: number;
  readonly predecessorSessionId: string | null;
  readonly successorSessionId: string | null;
  readonly state: OccupancySessionStateType;
  readonly serviceDogId: string | null;
  readonly f20GuardReceiptId: string | null;
  readonly f10ScheduleSnapshotId: string;
  readonly admissionProtocol?: "CANONICAL_V1" | "LEGACY_UNPROVEN" | null;
  readonly inspectionEvidence: {
    readonly acknowledged: boolean;
    readonly physicalKeysInHand: boolean;
    readonly recordedAt: unknown;
    readonly recordedByRa: string;
    readonly checklistRef: string | null;
    readonly notes: string | null;
    readonly vehicleOdometerKm: number | null;
  };
  readonly possessionAcknowledgment: {
    readonly acknowledged: boolean;
    readonly physicalKeysInHand: boolean;
    readonly recordedAt: unknown;
    readonly actorRa: string;
  };
  readonly startedAt: unknown;
  readonly startedByRa: string;
  readonly endedAt: unknown | null;
  readonly endedByRa: string | null;
  readonly auditTrail: ReadonlyArray<OccupancyAuditEntry>;
  readonly createdAt: unknown;
  readonly updatedAt: unknown;
}

// -----------------------------------------------------------------------------
// 3. Operational Engagement: operational_engagements/{engagementId}
// -----------------------------------------------------------------------------

export type OperationalEngagementStatus =
  | "active"
  | "ended"
  | "exceptionally_reconciled";

export interface ExceptionalReconciliationMetadata {
  readonly reconciledAt: unknown;
  readonly supervisorRa: string;
  readonly supervisorUid: string;
  readonly reason: string;
  readonly evidenceRef: string;
  readonly supervisorDesignationSnapshotId?: string;
}

export interface OperationalEngagementDoc {
  readonly engagementId: string;
  readonly linkedOccurrenceId: string | null;
  readonly occupancySessionId: string;
  readonly vehicleId: string;
  readonly vehicleGeneration: number;
  readonly status: OperationalEngagementStatus;
  readonly serverConfirmed: boolean;
  readonly isBlocking: boolean;
  readonly startedAt: unknown;
  readonly startedByRa: string;
  readonly endedAt: unknown | null;
  readonly endedByRa: string | null;
  readonly exceptionalReconciliation: ExceptionalReconciliationMetadata | null;
  readonly createdAt: unknown;
  readonly updatedAt: unknown;
}

// -----------------------------------------------------------------------------
// 4. Command Receipt: vehicle_occupancy_receipts/{operationId}
// -----------------------------------------------------------------------------

export type VehicleOccupancyReceiptStatus = "COMMITTED" | "DENIED" | "CONFLICT";

export interface VehicleOccupancyReceiptDoc {
  readonly operationId: string;
  readonly action:
    | "selfRegularizePriorOccupancy"
    | "exceptionallyReconcileOperationalEngagement"
    | "startOperationalEngagement"
    | "endOperationalEngagement";
  readonly actorRa: string;
  readonly actorUid: string;
  readonly vehicleId: string;
  readonly expectedSessionId?: string;
  readonly expectedGeneration?: number;
  readonly inputHash: string;
  readonly status: VehicleOccupancyReceiptStatus;
  readonly executionResult: Record<string, unknown>;
  readonly createdAt: unknown;
}

// -----------------------------------------------------------------------------
// 5. Coverage Provenance & Evidence Contracts
// -----------------------------------------------------------------------------

export type EvidenceProvenanceKind =
  | "SERVER_OCCURRENCE_DISPATCH"
  | "SERVER_PATROL_END_SIGNOFF"
  | "SUPERVISOR_EXCEPTIONAL_RECONCILIATION"
  | "UNVERIFIED_CLIENT_CLAIM";

export interface CoverageProvenance {
  readonly provenanceKind: EvidenceProvenanceKind;
  readonly verifiedByServer: boolean;
  readonly recordedAtMs: number;
  readonly sourceRef: string;
}

export interface ServerConfirmedEngagementItem {
  readonly engagementId: string;
  readonly isBlocking: boolean;
  readonly status: OperationalEngagementStatus;
  readonly sessionMatches: boolean;
  readonly generationMatches: boolean;
}

export interface ServerCoverageProof {
  readonly hasAuthoritativeClearance: boolean;
  readonly activeBlockingCount: number;
  readonly activeEngagements: readonly ServerConfirmedEngagementItem[];
  readonly clearanceProvenance: CoverageProvenance | null;
}

// -----------------------------------------------------------------------------
// 6. Validation Functions (Fail-Closed)
// -----------------------------------------------------------------------------

export function validateMonotonicGeneration(current: number, candidate: number): boolean {
  if (!Number.isInteger(current) || current < 1) return false;
  if (!Number.isInteger(candidate) || candidate < 1) return false;
  return candidate === current + 1;
}

export function validateInspectionEvidence(
  evidence: unknown,
): { readonly valid: boolean; readonly reason?: string } {
  if (!evidence || typeof evidence !== "object") {
    return { valid: false, reason: "Dados de vistoria física ausentes ou inválidos." };
  }
  const e = evidence as Record<string, unknown>;
  if (e.checklistConfirmed !== true) {
    return { valid: false, reason: "Vistoria física (checklist) deve ser confirmada pelo condutor." };
  }
  if (e.physicalKeysInHand !== true) {
    return { valid: false, reason: "Posse física das chaves da viatura deve ser confirmada pelo condutor." };
  }
  if (e.vehicleOdometerKm !== undefined && e.vehicleOdometerKm !== null) {
    if (typeof e.vehicleOdometerKm !== "number" || e.vehicleOdometerKm < 0) {
      return { valid: false, reason: "Odômetro deve ser um número positivo." };
    }
  }
  return { valid: true };
}

export function validatePointerDoc(
  data: unknown,
): { readonly valid: boolean; readonly errors: string[] } {
  const errors: string[] = [];
  if (!data || typeof data !== "object") {
    errors.push("Documento pointer inválido.");
    return { valid: false, errors };
  }
  const p = data as Record<string, unknown>;
  if (typeof p.vehicleId !== "string" || !p.vehicleId.trim()) {
    errors.push("vehicleId obrigatório.");
  }
  if (typeof p.currentSessionId !== "string" || !p.currentSessionId.trim()) {
    errors.push("currentSessionId obrigatório.");
  }
  if (typeof p.currentGeneration !== "number" || p.currentGeneration < 1 || !Number.isInteger(p.currentGeneration)) {
    errors.push("currentGeneration deve ser inteiro positivo.");
  }
  if (p.status !== "active" && p.status !== "conflicted" && p.status !== "locked" && p.status !== "transitioning") {
    errors.push(`Status inválido: ${p.status}`);
  }
  if (typeof p.currentCrewId !== "string" || !p.currentCrewId.trim()) {
    errors.push("currentCrewId obrigatório.");
  }
  if (typeof p.titularHandlerRa !== "string" || !p.titularHandlerRa.trim()) {
    errors.push("titularHandlerRa obrigatório.");
  }
  return { valid: errors.length === 0, errors };
}

export function validateSessionDoc(
  data: unknown,
): { readonly valid: boolean; readonly errors: string[] } {
  const errors: string[] = [];
  if (!data || typeof data !== "object") {
    errors.push("Documento de sessão inválido.");
    return { valid: false, errors };
  }
  const s = data as Record<string, unknown>;
  if (typeof s.sessionId !== "string" || !s.sessionId.trim()) {
    errors.push("sessionId obrigatório.");
  }
  if (typeof s.vehicleId !== "string" || !s.vehicleId.trim()) {
    errors.push("vehicleId obrigatório.");
  }
  if (typeof s.crewId !== "string" || !s.crewId.trim()) {
    errors.push("crewId obrigatório.");
  }
  if (typeof s.generation !== "number" || s.generation < 1 || !Number.isInteger(s.generation)) {
    errors.push("generation deve ser inteiro positivo.");
  }
  const validStates = [
    "active",
    "selfRegularizationRequested",
    "coverageValidated",
    "successionAllowed",
    "successionDenied",
    "conflicted",
    "stale",
  ];
  if (!validStates.includes(String(s.state))) {
    errors.push(`Estado de sessão inválido: ${s.state}`);
  }
  return { valid: errors.length === 0, errors };
}

export function validateEngagementDoc(
  data: unknown,
): { readonly valid: boolean; readonly errors: string[] } {
  const errors: string[] = [];
  if (!data || typeof data !== "object") {
    errors.push("Documento de engajamento inválido.");
    return { valid: false, errors };
  }
  const e = data as Record<string, unknown>;
  if (typeof e.engagementId !== "string" || !e.engagementId.trim()) {
    errors.push("engagementId obrigatório.");
  }
  if (typeof e.vehicleId !== "string" || !e.vehicleId.trim()) {
    errors.push("vehicleId obrigatório.");
  }
  if (typeof e.occupancySessionId !== "string" || !e.occupancySessionId.trim()) {
    errors.push("occupancySessionId obrigatório.");
  }
  if (typeof e.vehicleGeneration !== "number" || e.vehicleGeneration < 1 || !Number.isInteger(e.vehicleGeneration)) {
    errors.push("vehicleGeneration deve ser inteiro positivo.");
  }
  if (e.status !== "active" && e.status !== "ended" && e.status !== "exceptionally_reconciled") {
    errors.push(`Status de engajamento inválido: ${e.status}`);
  }
  return { valid: errors.length === 0, errors };
}

export function validateReceiptDoc(
  data: unknown,
): { readonly valid: boolean; readonly errors: string[] } {
  const errors: string[] = [];
  if (!data || typeof data !== "object") {
    errors.push("Documento de recibo inválido.");
    return { valid: false, errors };
  }
  const r = data as Record<string, unknown>;
  if (typeof r.operationId !== "string" || !r.operationId.trim()) {
    errors.push("operationId obrigatório.");
  }
  if (typeof r.inputHash !== "string" || !r.inputHash.trim()) {
    errors.push("inputHash obrigatório.");
  }
  if (r.status !== "COMMITTED" && r.status !== "DENIED" && r.status !== "CONFLICT") {
    errors.push(`Status de recibo inválido: ${r.status}`);
  }
  return { valid: errors.length === 0, errors };
}
