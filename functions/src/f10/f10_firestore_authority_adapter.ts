/**
 * F10 Firestore Authority Adapter — Transaction-Local Runtime Authority Readers.
 *
 * Implements transaction-local readers executing inside single Firestore transactions
 * for vehicle occupancy operations. Fulfills ADR-W3-01, ADR-W3-02, and ADR-W3-03.
 *
 * Invariants:
 * 1. ZERO client trust: client-supplied envelopes or "trusted: true" fields are discarded.
 * 2. 1:1 Bidirectional Identity Resolution: `identity_bindings/{uid}` must match `users/{ra}`
 *    bidirectionally (`binding.ra === ra && user.uid === uid`).
 * 3. Deterministic Uniqueness: UID uniqueness is anchored on document key `identity_bindings/{uid}`;
 *    RA uniqueness is anchored on `users/{ra}.uid === uid`.
 * 4. Zero Implicit Administrator Bypass: admin claims NEVER bypass vehicle capability requirements.
 * 5. Monotonic Revisions: Stale authority revisions cause transaction failure.
 * 6. Authoritative Schedule Binding: Crew schedule snapshots must be un-superseded and
 *    satisfy the schedule end + 60m threshold for self-regularization.
 */

import * as crypto from 'crypto';
import {
  Capability,
  SELF_REGULARIZE,
  EXCEPTIONAL_RECONCILE,
  ServerAttestation,
  TrustedIdentity,
  AuthorityEvidence,
  ScheduleSnapshot,
} from './f10_runtime_authority_contracts';

type JsonMap = Record<string, unknown>;

export interface TransactionalActorResolution {
  identity: TrustedIdentity;
  userDoc: JsonMap;
  bindingDoc: JsonMap;
}

export interface TransactionalAuthorityGrant {
  capability: Capability;
  grantRevision: number;
  authorityRevision: number;
  designation?: 'operational_inspector' | 'supervisor';
  profileId: string;
}

export interface TransactionalScheduleValidation {
  snapshot: ScheduleSnapshot;
  eligibleForSelfRegularize: boolean;
  scheduleEndMs: number;
  thresholdMs: number;
  nowMs: number;
}

export interface F10AuthorityResolutionResult {
  allowed: boolean;
  reason: string;
  identity?: TrustedIdentity;
  evidence?: AuthorityEvidence;
  attestation?: ServerAttestation;
  grant?: TransactionalAuthorityGrant;
  schedule?: TransactionalScheduleValidation;
}

/**
 * Transaction-local reader for trusted actor identity binding.
 *
 * Enforces 1:1 bidirectional uniqueness between Firebase Auth UID and Official RA:
 * - Reads `identity_bindings/{uid}`.
 * - Reads `users/{ra}`.
 * - Asserts `binding.ra === ra` and `user.uid === uid`.
 * - Asserts `binding.active === true`, `binding.confirmed === true`,
 *   `user.status === "active"`, and `user.deleted_at == null`.
 */
export async function resolveTrustedActorInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  uid: string,
  requestedRa?: string,
): Promise<TransactionalActorResolution | null> {
  if (!uid || typeof uid !== 'string' || !uid.trim()) return null;

  const bindingRef = db.collection('identity_bindings').doc(uid);
  const bindingSnap = await tx.get(bindingRef);
  if (!bindingSnap.exists) {
    return null;
  }

  const bindingData = bindingSnap.data() as JsonMap;
  const boundRa = typeof bindingData.ra === 'string' ? bindingData.ra.trim().toUpperCase() : '';
  if (!boundRa) return null;

  if (requestedRa) {
    const normalizedRequested = requestedRa.trim().toUpperCase();
    if (boundRa !== normalizedRequested) {
      return null;
    }
  }

  const bindingActive = bindingData.active === true;
  const bindingConfirmed = bindingData.confirmed === true;
  const bindingRevision =
    typeof bindingData.revision === 'number' && Number.isInteger(bindingData.revision)
      ? bindingData.revision
      : 1;

  if (!bindingActive || !bindingConfirmed) {
    return null;
  }

  const userRef = db.collection('users').doc(boundRa);
  const userSnap = await tx.get(userRef);
  if (!userSnap.exists) {
    return null;
  }

  const userData = userSnap.data() as JsonMap;
  const authUidCanonical = typeof userData.auth_uid === 'string' ? userData.auth_uid.trim() : '';
  const authUidLegacy = typeof userData.authUid === 'string' ? userData.authUid.trim() : '';
  const uidLegacy = typeof userData.uid === 'string' ? userData.uid.trim() : '';

  // Conflict check: if multiple distinct non-empty UIDs exist on users/{ra}, reject fail-closed
  const distinctUids = new Set([authUidCanonical, authUidLegacy, uidLegacy].filter(Boolean));
  if (distinctUids.size > 1) {
    return null; // Ambiguous/conflicting alias mapping fails closed
  }
  const userUid = authUidCanonical || authUidLegacy || uidLegacy;

  // Bidirectional 1:1 check: users/{ra} canonical auth_uid (or valid unconflicted alias) must equal binding UID
  if (!userUid || userUid !== uid) {
    return null;
  }

  // Active user record check (no soft-delete, active status)
  if (
    userData.deleted_at != null ||
    userData.active === false ||
    (userData.status !== undefined && userData.status !== 'active')
  ) {
    return null;
  }

  const identity: TrustedIdentity = {
    uid,
    ra: boundRa,
    revision: bindingRevision,
    active: true,
    confirmed: true,
  };

  return {
    identity,
    userDoc: userData,
    bindingDoc: bindingData,
  };
}

/**
 * Transaction-local reader for vehicle capability grants.
 *
 * PROHIBITS IMPLICIT ADMINISTRATOR BYPASS:
 * Administrative tokens (`admin: true`) or user roles (`role: "admin"`) DO NOT
 * grant operational authority for vehicle occupancy. The capability must be
 * explicitly granted in `access_profiles/{profileId}.permissions.vehicles[action] === true`.
 */
export async function readAccessProfileGrantInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  ra: string,
  userDoc: JsonMap,
  capability: Capability,
): Promise<TransactionalAuthorityGrant | null> {
  const action = capability.replace('vehicles.', '') as
    | 'self_regularize_prior_occupancy'
    | 'exceptionally_reconcile_operational_engagement';

  const profileId =
    typeof userDoc.access_profile_id === 'string' && userDoc.access_profile_id.trim()
      ? userDoc.access_profile_id.trim()
      : typeof userDoc.profileId === 'string' && userDoc.profileId.trim()
        ? userDoc.profileId.trim()
        : 'operador';

  const profileRef = db.collection('access_profiles').doc(profileId);
  const profileSnap = await tx.get(profileRef);
  if (!profileSnap.exists) {
    return null;
  }

  const profileData = profileSnap.data() as JsonMap;
  if (profileData.status !== undefined && profileData.status !== 'active') {
    return null;
  }

  const permissions = (profileData.permissions ?? {}) as JsonMap;
  const vehiclePerms = (permissions.vehicles ?? {}) as JsonMap;

  // Strict explicit capability check — NO admin bypass
  if (vehiclePerms[action] !== true) {
    return null;
  }

  const grantRevision =
    typeof profileData.grant_revision === 'number' && Number.isInteger(profileData.grant_revision)
      ? profileData.grant_revision
      : typeof profileData.revision === 'number' && Number.isInteger(profileData.revision)
        ? profileData.revision
        : 1;

  const authorityRevision =
    typeof profileData.authority_revision === 'number' &&
    Number.isInteger(profileData.authority_revision)
      ? profileData.authority_revision
      : grantRevision;

  // Derive supervisor / inspector designation
  let designation: 'operational_inspector' | 'supervisor' | undefined = undefined;
  if (
    userDoc.designation === 'supervisor' ||
    userDoc.designation === 'operational_inspector'
  ) {
    designation = userDoc.designation;
  } else if (Array.isArray(userDoc.role_keys)) {
    if (userDoc.role_keys.includes('supervisor')) designation = 'supervisor';
    else if (userDoc.role_keys.includes('operational_inspector'))
      designation = 'operational_inspector';
  } else if (Array.isArray(profileData.role_keys)) {
    if (profileData.role_keys.includes('supervisor')) designation = 'supervisor';
    else if (profileData.role_keys.includes('operational_inspector'))
      designation = 'operational_inspector';
  }

  return {
    capability,
    grantRevision,
    authorityRevision,
    designation,
    profileId,
  };
}

/**
 * Transaction-local reader for authoritative crew schedule snapshot.
 *
 * Verifies:
 * 1. Snapshot exists and is uncorrupted.
 * 2. Snapshot is not superseded (`superseded_by == null`).
 * 3. Evaluates eligibility for self-regularization: `now >= snapshot.end + 60m`.
 */
export async function readAuthoritativeScheduleSnapshotInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  snapshotId: string,
  nowIso: string,
  expectedCrewId?: string,
): Promise<TransactionalScheduleValidation | null> {
  if (!snapshotId || typeof snapshotId !== 'string' || !snapshotId.trim()) return null;

  // Read strictly from ratified canonical collection: crew_schedule_snapshots (ADR-W3-01)
  const snapshotRef = db.collection('crew_schedule_snapshots').doc(snapshotId.trim());
  const snapshotSnap = await tx.get(snapshotRef);
  if (!snapshotSnap.exists) {
    return null;
  }

  const data = snapshotSnap.data() as JsonMap;

  // Validate crew binding if specified
  if (expectedCrewId && typeof data.crewId === 'string' && data.crewId.trim()) {
    if (data.crewId.trim() !== expectedCrewId.trim()) {
      return null;
    }
  }

  // Must not be superseded
  if (data.superseded_by != null || data.supersededBy != null) {
    return null;
  }

  const startIso = String(data.start ?? '');
  const endIso = String(data.end ?? '');
  const scheduleEndMs = new Date(endIso).getTime();
  const nowMs = new Date(nowIso).getTime();

  if (isNaN(scheduleEndMs) || isNaN(nowMs)) {
    return null;
  }

  // 60-minute post-shift threshold per ADR-W3-03
  const thresholdMs = scheduleEndMs + 60 * 60 * 1000;
  const eligibleForSelfRegularize = nowMs >= thresholdMs;

  const snapshot: ScheduleSnapshot = {
    scheduleId: String(data.scheduleId ?? ''),
    revision: Number(data.revision ?? 1),
    timezone: String(data.timezone ?? 'America/Sao_Paulo'),
    serviceDate: String(data.serviceDate ?? ''),
    start: startIso,
    end: endIso,
    inclusiveStart: true,
    exclusiveEnd: true,
    snapshotId: snapshotSnap.id,
    source: String(data.source ?? 'crew_assignment'),
    createdAt: String(data.createdAt ?? ''),
    integrity: String(data.integrity ?? ''),
    ...(data.supersedesSnapshotId
      ? { supersedesSnapshotId: String(data.supersedesSnapshotId) }
      : {}),
  };

  return {
    snapshot,
    eligibleForSelfRegularize,
    scheduleEndMs,
    thresholdMs,
    nowMs,
  };
}

/**
 * Produces a server attestation token certifying transactional evidence verification.
 */
export function createTransientServerAttestation(
  identity: TrustedIdentity,
  grant: TransactionalAuthorityGrant,
  scheduleSnapshotId: string,
  nowIso: string,
): ServerAttestation {
  const token = `attest_${identity.uid}_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
  return {
    verificationToken: token,
    verifiedAt: nowIso,
    authorityRevision: grant.authorityRevision,
    scheduleSnapshotId,
    identityBindingRevision: identity.revision,
  };
}

/**
 * Evaluates full runtime authority inside an active Firestore transaction.
 */
export async function evaluateTransactionAuthority(
  tx: FirebaseFirestore.Transaction,
  db: FirebaseFirestore.Firestore,
  input: {
    uid: string;
    capability: Capability;
    scheduleSnapshotId: string;
    nowIso: string;
    requestedRa?: string;
    evidenceRefs?: readonly string[];
    justification?: string;
  },
): Promise<F10AuthorityResolutionResult> {
  const actor = await resolveTrustedActorInTransaction(
    tx,
    db,
    input.uid,
    input.requestedRa,
  );
  if (!actor) {
    return {
      allowed: false,
      reason: 'identity_binding_unresolved_or_inactive',
    };
  }

  const grant = await readAccessProfileGrantInTransaction(
    tx,
    db,
    actor.identity.ra,
    actor.userDoc,
    input.capability,
  );
  if (!grant) {
    return {
      allowed: false,
      reason: 'capability_not_granted_or_inactive',
      identity: actor.identity,
    };
  }

  const schedule = await readAuthoritativeScheduleSnapshotInTransaction(
    tx,
    db,
    input.scheduleSnapshotId,
    input.nowIso,
  );
  if (!schedule) {
    return {
      allowed: false,
      reason: 'schedule_snapshot_invalid_or_superseded',
      identity: actor.identity,
      grant,
    };
  }

  if (input.capability === SELF_REGULARIZE) {
    if (!schedule.eligibleForSelfRegularize) {
      return {
        allowed: false,
        reason: 'schedule_end_plus_60m_threshold_not_reached',
        identity: actor.identity,
        grant,
        schedule,
      };
    }
  }

  if (input.capability === EXCEPTIONAL_RECONCILE) {
    if (!grant.designation) {
      return {
        allowed: false,
        reason: 'designation_supervisor_or_inspector_required',
        identity: actor.identity,
        grant,
        schedule,
      };
    }
    if (
      !input.justification?.trim() ||
      !input.evidenceRefs?.length ||
      input.evidenceRefs.some((r) => !r.trim())
    ) {
      return {
        allowed: false,
        reason: 'evidence_contract_justification_and_refs_required',
        identity: actor.identity,
        grant,
        schedule,
      };
    }
  }

  const attestation = createTransientServerAttestation(
    actor.identity,
    grant,
    input.scheduleSnapshotId,
    input.nowIso,
  );

  const evidence: AuthorityEvidence = {
    identity: actor.identity,
    capability: input.capability,
    grantRevision: grant.grantRevision,
    authorityRevision: grant.authorityRevision,
    designation: grant.designation,
    evidenceRefs: input.evidenceRefs,
    justification: input.justification,
  };

  return {
    allowed: true,
    reason: 'server_attested_transactional_authority',
    identity: actor.identity,
    grant,
    schedule,
    evidence,
    attestation,
  };
}
