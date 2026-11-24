/**
 * F10 Trusted Runtime Authority Contracts & Pure Invariant Evaluators.
 *
 * Provides pure, zero-dependency types and functions with 100% mathematical
 * parity to the authoritative F10 contracts in Web/Admin (`k9-ops`), verified
 * against `conformance_vectors.v1.json` (v1.1.0).
 *
 * Operating Invariants:
 * - Fail-closed by default.
 * - ZERO implicit administrator bypass.
 * - Bidirectional 1:1 UID/RA identity resolution.
 * - Monotonic authority revisions.
 * - Strict separation between incoming crew self-regularization and
 *   designated exceptional reconciliation.
 */

// ─────────────────────────────────────────────────────────────────────────────
// CAPABILITIES & OUTCOMES
// ─────────────────────────────────────────────────────────────────────────────

export const SELF_REGULARIZE = 'vehicles.self_regularize_prior_occupancy' as const;
export const EXCEPTIONAL_RECONCILE = 'vehicles.exceptionally_reconcile_operational_engagement' as const;
export const EXCEPTIONALLY_RECONCILE = EXCEPTIONAL_RECONCILE;
export const RATIFIED_CAPABILITIES = [SELF_REGULARIZE, EXCEPTIONAL_RECONCILE] as const;

export type Capability = (typeof RATIFIED_CAPABILITIES)[number];

export function isCapability(value: unknown): value is Capability {
  return RATIFIED_CAPABILITIES.includes(value as Capability);
}

export type AuthorityState = 'allowed' | 'denied' | 'unknown' | 'conflicted';

export interface CapabilityDecision {
  state: AuthorityState;
  capability: Capability;
  reason: string;
  evidence?: AuthorityEvidence;
}

// ─────────────────────────────────────────────────────────────────────────────
// TRUSTED IDENTITY & BINDING
// ─────────────────────────────────────────────────────────────────────────────

export interface TrustedIdentity {
  uid: string;
  ra: string;
  revision: number;
  active: boolean;
  confirmed: boolean;
}

export interface IdentityBinding {
  uid: string;
  ra: string;
  active: boolean;
  confirmed: boolean;
  revision: number;
}

const UID_PATTERN = /^[A-Za-z0-9:_-]{3,128}$/;
const RA_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$/;

export function normalizeUid(value: unknown): string | null {
  const v = typeof value === 'string' ? value.trim() : '';
  return UID_PATTERN.test(v) ? v : null;
}

export function normalizeRa(value: unknown): string | null {
  const v = typeof value === 'string' ? value.trim().toUpperCase() : '';
  return RA_PATTERN.test(v) ? v : null;
}

export function validateIdentityBinding(input: Partial<IdentityBinding>): IdentityBinding {
  const uid = normalizeUid(input.uid);
  const ra = normalizeRa(input.ra);
  const revision = input.revision;
  if (
    !uid ||
    !ra ||
    input.active !== true ||
    input.confirmed !== true ||
    typeof revision !== 'number' ||
    !Number.isInteger(revision) ||
    revision < 1
  ) {
    throw new Error('invalid_identity_binding');
  }
  return { uid, ra, active: true, confirmed: true, revision };
}

export function resolveUniqueBinding(
  bindings: readonly IdentityBinding[],
  uid: string,
  requestedRa?: string,
): TrustedIdentity | null {
  const normalizedUid = normalizeUid(uid);
  if (!normalizedUid) return null;
  const active = bindings.filter((b) => b.active);
  if (
    active.some(
      (b) =>
        !normalizeUid(b.uid) ||
        !normalizeRa(b.ra) ||
        b.confirmed !== true ||
        !Number.isInteger(b.revision) ||
        b.revision < 1,
    )
  ) {
    return null;
  }
  const normalized = active.map((b) => ({
    ...b,
    uid: normalizeUid(b.uid)!,
    ra: normalizeRa(b.ra)!,
  }));
  const matches = normalized.filter((b) => b.uid === normalizedUid);
  if (matches.length !== 1) return null;
  const binding = matches[0];
  if (normalized.filter((b) => b.ra === binding.ra).length !== 1) return null;
  if (requestedRa !== undefined && normalizeRa(requestedRa) !== binding.ra) {
    return null;
  }
  return {
    uid: binding.uid,
    ra: binding.ra,
    revision: binding.revision,
    active: true,
    confirmed: true,
  };
}

export const resolveTrustedIdentity = resolveUniqueBinding;

export function validateBindingUniqueness(bindings: readonly IdentityBinding[]): boolean {
  const active = bindings.filter((b) => b.active);
  return (
    new Set(active.map((b) => normalizeUid(b.uid))).size === active.length &&
    new Set(active.map((b) => normalizeRa(b.ra))).size === active.length &&
    active.every((b) => normalizeUid(b.uid) !== null && normalizeRa(b.ra) !== null)
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTHORITY EVIDENCE & REVISIONS
// ─────────────────────────────────────────────────────────────────────────────

export interface AuthorityEvidence {
  identity: TrustedIdentity;
  capability: Capability;
  grantRevision: number;
  authorityRevision: number;
  revocationRevision?: number;
  revokedAt?: string;
  designation?: 'operational_inspector' | 'supervisor';
  evidenceRefs?: readonly string[];
  justification?: string;
  idempotencyKey?: string;
}

export interface AuthorityRevision {
  revision: number;
  issuedAt: string;
  status: 'active' | 'revoked';
  supersedes?: number;
  revokedAt?: string;
}

export function validateRevision(revision: AuthorityRevision): boolean {
  return (
    Number.isInteger(revision.revision) &&
    revision.revision > 0 &&
    Boolean(revision.issuedAt) &&
    (revision.status === 'active' || revision.status === 'revoked')
  );
}

export function assertAuthorityRevision(
  expected: number | undefined,
  current: AuthorityRevision | undefined,
): CapabilityDecision {
  if (expected === undefined || !current || !validateRevision(current)) {
    return {
      state: 'unknown',
      capability: SELF_REGULARIZE,
      reason: 'invalid_authority_revision',
    };
  }
  if (current.status === 'revoked') {
    return {
      state: 'denied',
      capability: SELF_REGULARIZE,
      reason: 'authority_revoked',
    };
  }
  if (expected !== current.revision) {
    return {
      state: 'conflicted',
      capability: SELF_REGULARIZE,
      reason: 'stale_authority_revision',
    };
  }
  return {
    state: 'allowed',
    capability: SELF_REGULARIZE,
    reason: 'authority_revision_current',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CREW SCHEDULE & SNAPSHOTS
// ─────────────────────────────────────────────────────────────────────────────

export interface CrewSchedule {
  scheduleId: string;
  revision: number;
  timezone: string;
  startLocal: string;
  endLocal: string;
  serviceDate: string;
  source: string;
  exceptionRef?: string;
}

export interface CalculatedScheduleWindow {
  scheduleId: string;
  revision: number;
  timezone: string;
  serviceDate: string;
  start: Date;
  end: Date;
  inclusiveStart: true;
  exclusiveEnd: true;
}

export interface ScheduleSnapshot extends Omit<CalculatedScheduleWindow, 'start' | 'end'> {
  start: string;
  end: string;
  snapshotId: string;
  source: string;
  createdAt: string;
  integrity: string;
  supersedesSnapshotId?: string;
}

export interface SupersessionRecord {
  recordId: string;
  supersededSnapshotId: string;
  replacementSnapshotId: string;
  reason: string;
  createdAt: string;
  createdBy: string;
}

const parseTime = (s: string): readonly [number, number] | null => {
  const m = /^(\d{2}):(\d{2})$/.exec(s);
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  return h < 24 && min < 60 ? ([h, min] as const) : null;
};

function dateTimeParts(date: Date, timezone: string): Record<string, number> {
  const values = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date);
  return Object.fromEntries(
    values.filter((p) => p.type !== 'literal').map((p) => [p.type, Number(p.value)]),
  );
}

function localInstant(dateText: string, localTime: string, timezone: string): Date {
  const [year, month, day] = dateText.split('-').map(Number);
  const [hour, minute] = localTime.split(':').map(Number);
  const wall = Date.UTC(year, month - 1, day, hour, minute, 0);
  const calendar = new Date(wall);
  if (
    calendar.getUTCFullYear() !== year ||
    calendar.getUTCMonth() + 1 !== month ||
    calendar.getUTCDate() !== day
  ) {
    throw new Error('invalid_service_date');
  }
  const offsets = new Set<number>();
  for (const hours of [-36, -12, 0, 12, 36]) {
    const sample = new Date(wall + hours * 3600000);
    const p = dateTimeParts(sample, timezone);
    offsets.add(Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - sample.getTime());
  }
  const candidates = [...offsets]
    .map((offset) => new Date(wall - offset))
    .filter((candidate) => {
      const p = dateTimeParts(candidate, timezone);
      return (
        p.year === year &&
        p.month === month &&
        p.day === day &&
        p.hour === hour &&
        p.minute === minute
      );
    });
  if (candidates.length !== 1) {
    throw new Error(candidates.length === 0 ? 'nonexistent_local_time' : 'ambiguous_local_time');
  }
  return candidates[0];
}

export function calculateCrewWindow(schedule: CrewSchedule): CalculatedScheduleWindow {
  if (
    !schedule.scheduleId ||
    !Number.isInteger(schedule.revision) ||
    schedule.revision < 1 ||
    !/^\d{4}-\d{2}-\d{2}$/.test(schedule.serviceDate)
  ) {
    throw new Error('invalid_schedule');
  }
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: schedule.timezone }).format(0);
  } catch {
    throw new Error('invalid_timezone');
  }
  const st = parseTime(schedule.startLocal);
  const en = parseTime(schedule.endLocal);
  if (!st || !en) throw new Error('invalid_local_time');
  const start = localInstant(schedule.serviceDate, schedule.startLocal, schedule.timezone);
  const startMinutes = st[0] * 60 + st[1];
  const endMinutes = en[0] * 60 + en[1];
  const [year, month, day] = schedule.serviceDate.split('-').map(Number);
  const endDate =
    endMinutes <= startMinutes
      ? new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, 10)
      : schedule.serviceDate;
  const end = localInstant(endDate, schedule.endLocal, schedule.timezone);
  if (end <= start) throw new Error('invalid_schedule_interval');
  return {
    scheduleId: schedule.scheduleId,
    revision: schedule.revision,
    timezone: schedule.timezone,
    serviceDate: schedule.serviceDate,
    start,
    end,
    inclusiveStart: true,
    exclusiveEnd: true,
  };
}

export function resolveEffectiveSchedule(input: {
  crewSchedule: CrewSchedule;
  memberSchedule?: CrewSchedule;
}): CrewSchedule {
  return input.crewSchedule;
}

function stableJson(value: unknown): string {
  if (value instanceof Date) return JSON.stringify(value.toISOString());
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.entries(value)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value) ?? 'null';
}

export function createSnapshot(
  window: CalculatedScheduleWindow,
  source: string,
  snapshotId: string,
  createdAt: string,
  supersedesSnapshotId?: string,
): ScheduleSnapshot {
  if (!source?.trim() || !snapshotId?.trim() || !createdAt?.trim()) {
    throw new Error('invalid_snapshot_metadata');
  }
  const payload = {
    ...window,
    start: window.start.toISOString(),
    end: window.end.toISOString(),
    source,
    snapshotId,
    createdAt,
    ...(supersedesSnapshotId ? { supersedesSnapshotId } : {}),
  };
  const integrity = stableJson(payload);
  return Object.freeze({ ...payload, integrity });
}

export function verifySnapshot(snapshot: ScheduleSnapshot): boolean {
  const { integrity, ...payload } = snapshot;
  return snapshot.start < snapshot.end && integrity === stableJson(payload);
}

export function buildSupersessionRecord(
  oldSnapshot: ScheduleSnapshot,
  replacementSnapshot: ScheduleSnapshot,
  reason: string,
  createdBy: string,
  recordId: string,
  createdAt: string,
): SupersessionRecord {
  if (
    !reason?.trim() ||
    !createdBy?.trim() ||
    !recordId?.trim() ||
    !createdAt?.trim() ||
    oldSnapshot.snapshotId === replacementSnapshot.snapshotId ||
    replacementSnapshot.supersedesSnapshotId !== oldSnapshot.snapshotId ||
    replacementSnapshot.revision <= oldSnapshot.revision
  ) {
    throw new Error('invalid_supersession');
  }
  return Object.freeze({
    recordId,
    supersededSnapshotId: oldSnapshot.snapshotId,
    replacementSnapshotId: replacementSnapshot.snapshotId,
    reason,
    createdBy,
    createdAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// F40 ELIGIBILITY & REFINED CAPABILITY EVALUATOR
// ─────────────────────────────────────────────────────────────────────────────

export interface F40Eligibility {
  activeMembership: boolean;
  confirmed: boolean;
  incomingCrewMember: boolean;
  generation: string;
}

export function evaluateCapability(input: {
  identity?: TrustedIdentity;
  capability: unknown;
  evidence?: AuthorityEvidence;
  f40?: F40Eligibility;
}): CapabilityDecision {
  if (!isCapability(input.capability)) {
    return { state: 'denied', capability: SELF_REGULARIZE, reason: 'unknown_capability' };
  }
  const capability = input.capability;
  const { identity, evidence, f40 } = input;
  if (!identity) {
    return { state: 'unknown', capability, reason: 'trusted_identity_missing' };
  }
  if (!identity.active || !identity.confirmed) {
    return { state: 'denied', capability, reason: 'identity_not_active_confirmed' };
  }
  if (
    !evidence ||
    evidence.capability !== capability ||
    evidence.identity.uid !== identity.uid ||
    evidence.identity.ra !== identity.ra ||
    !Number.isInteger(evidence.grantRevision) ||
    evidence.grantRevision <= 0 ||
    !Number.isInteger(evidence.authorityRevision) ||
    evidence.authorityRevision < evidence.grantRevision
  ) {
    return { state: 'unknown', capability, reason: 'missing_or_untrusted_evidence' };
  }
  if (
    evidence.revokedAt ||
    (evidence.revocationRevision !== undefined &&
      evidence.revocationRevision >= evidence.grantRevision)
  ) {
    return { state: 'denied', capability, reason: 'capability_revoked', evidence };
  }

  // Refined capability separation (RATIFY-W3-02):
  // SELF_REGULARIZE requires confirmed active incoming crew membership.
  if (capability === SELF_REGULARIZE) {
    if (
      !f40 ||
      !f40.activeMembership ||
      !f40.confirmed ||
      !f40.incomingCrewMember ||
      !f40.generation
    ) {
      return { state: 'unknown', capability, reason: 'f40_eligibility_missing', evidence };
    }
  } else if (capability === EXCEPTIONAL_RECONCILE) {
    // EXCEPTIONAL_RECONCILE requires active supervisor/inspector designation
    // and an engagement-specific evidence contract without requiring incoming membership.
    if (
      !evidence.designation ||
      (evidence.designation !== 'operational_inspector' &&
        evidence.designation !== 'supervisor') ||
      !evidence.justification?.trim() ||
      !evidence.evidenceRefs?.length ||
      evidence.evidenceRefs.some((ref) => !ref.trim())
    ) {
      return {
        state: 'denied',
        capability,
        reason: 'designation_evidence_or_justification_missing',
        evidence,
      };
    }
  }

  return { state: 'allowed', capability, reason: 'explicit_evidence_and_eligibility', evidence };
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVER ATTESTATION & RUNTIME AUTHORITY BOUNDARY
// ─────────────────────────────────────────────────────────────────────────────

export interface ServerAttestation {
  verificationToken: string;
  verifiedAt: string;
  authorityRevision: number;
  scheduleSnapshotId: string;
  identityBindingRevision: number;
}

export type BoundaryDecisionState =
  | 'structurally_valid_but_untrusted'
  | 'untrusted_missing_source'
  | 'denied_missing_binding'
  | 'denied_identity_not_active_confirmed'
  | 'denied_ambiguous_binding'
  | 'denied_grant_absent_or_revoked'
  | 'denied_stale_authority'
  | 'denied_capability_not_granted'
  | 'denied_designation_missing'
  | 'denied_schedule_missing'
  | 'denied_schedule_not_authoritative'
  | 'allowed_only_with_server_attestation';

export interface ActorBindingEvidence {
  uid: string;
  ra: string;
  revision: number;
  active: boolean;
  confirmed: boolean;
}

export interface GrantEvidence {
  capability: Capability;
  grantRevision: number;
  authorityRevision: number;
  revocationRevision?: number;
  revokedAt?: string;
  designation?: 'operational_inspector' | 'supervisor';
  evidenceRefs?: readonly string[];
  justification?: string;
}

export interface ScheduleEvidence {
  snapshotId: string;
  revision: number;
  serviceDate: string;
  timezone: string;
  start: string;
  end: string;
  source: string;
  integrity: string;
}

export interface AuthorityEnvelope {
  actor: ActorBindingEvidence;
  grant: GrantEvidence;
  f40?: F40Eligibility;
  schedule: ScheduleEvidence;
  trusted?: unknown;
}

export interface StructuralResult {
  valid: boolean;
  errors: readonly string[];
}

export interface AuthorityBoundaryDecision {
  state: BoundaryDecisionState;
  reason: string;
  structuralResult: StructuralResult;
  attestationPresent: boolean;
}

const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const ISO_INSTANT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;

function validateEnvelopeActor(errors: string[], actor: ActorBindingEvidence): void {
  if (!UID_PATTERN.test(actor.uid)) errors.push('invalid_uid_format');
  if (!RA_PATTERN.test(actor.ra)) errors.push('invalid_ra_format');
  if (!Number.isInteger(actor.revision) || actor.revision < 1) {
    errors.push('invalid_binding_revision');
  }
  if (typeof actor.active !== 'boolean') errors.push('missing_active_flag');
  if (typeof actor.confirmed !== 'boolean') errors.push('missing_confirmed_flag');
}

function validateEnvelopeGrant(errors: string[], grant: GrantEvidence): void {
  if (grant.capability !== SELF_REGULARIZE && grant.capability !== EXCEPTIONAL_RECONCILE) {
    errors.push('unknown_capability');
  }
  if (!Number.isInteger(grant.grantRevision) || grant.grantRevision < 1) {
    errors.push('invalid_grant_revision');
  }
  if (!Number.isInteger(grant.authorityRevision) || grant.authorityRevision < 1) {
    errors.push('invalid_authority_revision');
  }
  if (grant.authorityRevision < grant.grantRevision) {
    errors.push('authority_revision_before_grant');
  }
  if (
    grant.revocationRevision !== undefined &&
    (!Number.isInteger(grant.revocationRevision) || grant.revocationRevision < 1)
  ) {
    errors.push('invalid_revocation_revision');
  }
}

function validateEnvelopeF40(errors: string[], f40: F40Eligibility): void {
  if (typeof f40.activeMembership !== 'boolean') errors.push('missing_f40_active_membership');
  if (typeof f40.confirmed !== 'boolean') errors.push('missing_f40_confirmed');
  if (typeof f40.incomingCrewMember !== 'boolean') errors.push('missing_f40_incoming_crew');
  if (!f40.generation || typeof f40.generation !== 'string') errors.push('missing_f40_generation');
}

function validateEnvelopeSchedule(errors: string[], schedule: ScheduleEvidence): void {
  if (!schedule.snapshotId || typeof schedule.snapshotId !== 'string') {
    errors.push('missing_snapshot_id');
  }
  if (!Number.isInteger(schedule.revision) || schedule.revision < 1) {
    errors.push('invalid_schedule_revision');
  }
  if (!ISO_DATE_PATTERN.test(schedule.serviceDate)) errors.push('invalid_service_date');
  if (!schedule.timezone || typeof schedule.timezone !== 'string') errors.push('missing_timezone');
  if (!ISO_INSTANT_PATTERN.test(schedule.start)) errors.push('invalid_start_instant');
  if (!ISO_INSTANT_PATTERN.test(schedule.end)) errors.push('invalid_end_instant');
  if (!schedule.source || typeof schedule.source !== 'string') errors.push('missing_schedule_source');
  if (!schedule.integrity || typeof schedule.integrity !== 'string') {
    errors.push('missing_schedule_integrity');
  }
  if (schedule.start >= schedule.end) errors.push('schedule_start_not_before_end');
}

export function evaluateStructuralValidity(input: AuthorityEnvelope): StructuralResult {
  const errors: string[] = [];
  if (!input.actor || typeof input.actor !== 'object') {
    errors.push('missing_actor');
    return { valid: false, errors };
  }
  validateEnvelopeActor(errors, input.actor);
  if (!input.grant || typeof input.grant !== 'object') {
    errors.push('missing_grant');
    return { valid: false, errors };
  }
  validateEnvelopeGrant(errors, input.grant);
  if (input.grant.capability === SELF_REGULARIZE) {
    if (!input.f40 || typeof input.f40 !== 'object') {
      errors.push('missing_f40');
      return { valid: false, errors };
    }
    validateEnvelopeF40(errors, input.f40);
  } else if (input.f40) {
    validateEnvelopeF40(errors, input.f40);
  }
  if (!input.schedule || typeof input.schedule !== 'object') {
    errors.push('missing_schedule');
    return { valid: false, errors };
  }
  validateEnvelopeSchedule(errors, input.schedule);
  return { valid: errors.length === 0, errors };
}

export function evaluateTrustedAuthority(
  input: AuthorityEnvelope,
  attestation?: ServerAttestation | null,
): AuthorityBoundaryDecision {
  const structural = evaluateStructuralValidity(input);

  if (!attestation || !attestation.verificationToken || !attestation.verifiedAt) {
    return {
      state: structural.valid ? 'structurally_valid_but_untrusted' : 'untrusted_missing_source',
      reason: structural.valid ? 'no_server_attestation' : 'structural_invalid_and_no_attestation',
      structuralResult: structural,
      attestationPresent: false,
    };
  }

  if (!structural.valid) {
    return {
      state: 'untrusted_missing_source',
      reason: `structural_errors:${structural.errors.join(',')}`,
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  const { actor, grant, f40, schedule } = input;

  if (!actor.active || !actor.confirmed) {
    return {
      state: 'denied_identity_not_active_confirmed',
      reason: 'identity_not_active_or_confirmed',
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  if (actor.revision !== attestation.identityBindingRevision) {
    return {
      state: 'denied_stale_authority',
      reason: 'binding_revision_mismatch',
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  if (
    grant.revokedAt ||
    (grant.revocationRevision !== undefined && grant.revocationRevision >= grant.grantRevision)
  ) {
    return {
      state: 'denied_grant_absent_or_revoked',
      reason: 'grant_revoked',
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  if (grant.authorityRevision !== attestation.authorityRevision) {
    return {
      state: 'denied_stale_authority',
      reason: 'authority_revision_mismatch',
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  if (grant.capability === SELF_REGULARIZE) {
    if (!f40 || !f40.activeMembership || !f40.confirmed || !f40.incomingCrewMember || !f40.generation) {
      return {
        state: 'denied_capability_not_granted',
        reason: 'f40_eligibility_incomplete',
        structuralResult: structural,
        attestationPresent: true,
      };
    }
  }

  if (grant.capability === EXCEPTIONAL_RECONCILE) {
    if (
      !grant.designation ||
      (grant.designation !== 'operational_inspector' && grant.designation !== 'supervisor') ||
      !grant.justification?.trim() ||
      !grant.evidenceRefs?.length ||
      grant.evidenceRefs.some((r) => !r.trim())
    ) {
      return {
        state: 'denied_designation_missing',
        reason: 'exceptional_reconciliation_requires_designation_evidence_justification',
        structuralResult: structural,
        attestationPresent: true,
      };
    }
  }

  if (schedule.snapshotId !== attestation.scheduleSnapshotId) {
    return {
      state: 'denied_schedule_not_authoritative',
      reason: 'schedule_snapshot_mismatch',
      structuralResult: structural,
      attestationPresent: true,
    };
  }

  return {
    state: 'allowed_only_with_server_attestation',
    reason: 'server_verified_all_evidence',
    structuralResult: structural,
    attestationPresent: true,
  };
}
