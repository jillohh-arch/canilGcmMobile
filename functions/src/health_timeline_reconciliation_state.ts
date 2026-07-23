/**
 * Backend-only durable state for HealthTimeline reconciliation.
 *
 * Gate 5C.5C.3 is local-only: this module is not exported by index.ts.
 */
import {createHash} from "crypto";
import {
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {
  assertSafeDocumentId,
  type HealthTimelineSourceType,
  type RuntimeClock,
} from "./health_timeline_runtime";

export const RECONCILIATION_ROOT_PATH =
  "_health_projection_state/health_timeline_v1";

export type ReconciliationPassName =
  | "forward"
  | "overlap"
  | "historical";

export type GlobalPassName = "orphan" | "known_discrepancies";

export type QueryCursorValue = Timestamp | string;

export type RecordedAtQueryCursor = {
  kind: "recorded_at_name";
  recordedAt: QueryCursorValue;
  documentPath: string;
  normalizedRecordedAt: string;
};

export type DocumentNameCursor = {
  kind: "document_name";
  documentPath: string;
};

export type ReconciliationCursor =
  | RecordedAtQueryCursor
  | DocumentNameCursor;

export type LeaseToken = {
  owner: string;
  revision: number;
  expiresAt: Timestamp;
};

export type PersistedLeaseState = {
  owner: string | null;
  revision: number;
  expiresAt: Timestamp | null;
};

export type ReconciliationReasonCode =
  | "invalid-source-payload"
  | "source-missing-during-pass"
  | "unsupported-recorded-at-type"
  | "orphan-source-missing"
  | "timeline-invalid-path"
  | "timeline-dog-mismatch"
  | "timeline-source-collection-invalid"
  | "timeline-source-id-invalid"
  | "timeline-type-mismatch"
  | "timeline-id-mismatch";

export type DiscrepancyTargetKind = "source" | "timeline";
export type DiscrepancyStatus = "open" | "resolved";

export type DiscrepancyIdentity = {
  targetKind: DiscrepancyTargetKind;
  reasonCode: ReconciliationReasonCode;
  sourceType: HealthTimelineSourceType | null;
  dogId: string | null;
  sourceId: string | null;
  timelineDocumentPath: string | null;
};

export type DurableDiscrepancy = DiscrepancyIdentity & {
  discrepancyId: string;
  status: DiscrepancyStatus;
  firstSeenAt: Timestamp;
  lastSeenAt: Timestamp;
  resolvedAt: Timestamp | null;
  attempts: number;
  safeContext: Record<string, string | number | boolean | null>;
};

export type PassState = {
  key: string;
  cursor: ReconciliationCursor | null;
  cycle: number;
  windowStart: Timestamp | null;
  windowEnd: Timestamp | null;
  windowActive: boolean;
};

export class LeaseUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LeaseUnavailableError";
  }
}

export class StaleLeaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StaleLeaseError";
  }
}

export class StaleCursorError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StaleCursorError";
  }
}

export function decideLeaseAcquisition(
  current: PersistedLeaseState,
  requestedOwner: string,
  now: Date,
  durationMs: number,
): LeaseToken | null {
  const owner = assertSafeDocumentId(requestedOwner, "source");
  if (!Number.isFinite(now.getTime())) {
    throw new Error("Lease decision requires a valid current time.");
  }
  if (!Number.isFinite(durationMs) || durationMs <= 0) {
    throw new Error("Lease duration must be positive.");
  }
  if (
    current.owner !== null &&
    current.expiresAt !== null &&
    current.expiresAt.toMillis() > now.getTime()
  ) {
    return null;
  }
  return {
    owner,
    revision: current.revision + 1,
    expiresAt: Timestamp.fromMillis(now.getTime() + durationMs),
  };
}

export function leaseTokenOwnsState(
  token: LeaseToken,
  current: PersistedLeaseState,
  now: Date,
): boolean {
  return current.owner === token.owner &&
    current.revision === token.revision &&
    current.expiresAt !== null &&
    current.expiresAt.toMillis() > now.getTime();
}

function clockDate(clock: RuntimeClock): Date {
  const now = clock.now();
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
    throw new Error("Reconciliation clock returned an invalid Date.");
  }
  return now;
}

function positiveInteger(value: unknown, fallback = 0): number {
  return typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 0 ?
    value :
    fallback;
}

function safeStateKey(value: string): string {
  return assertSafeDocumentId(value, "source");
}

export function sourcePassKey(
  sourceType: HealthTimelineSourceType,
  passName: ReconciliationPassName,
): string {
  return `${sourceType}_${passName}`;
}

export function globalPassKey(passName: GlobalPassName): string {
  return safeStateKey(`${passName}_global`);
}

export function reconciliationPassPath(key: string): string {
  return `${RECONCILIATION_ROOT_PATH}/passes/${safeStateKey(key)}`;
}

export function reconciliationRunPath(runId: string): string {
  return `${RECONCILIATION_ROOT_PATH}/runs/${safeStateKey(runId)}`;
}

export function discrepancyPath(discrepancyId: string): string {
  return `${RECONCILIATION_ROOT_PATH}/discrepancies/` +
    `${safeStateKey(discrepancyId)}`;
}

function hashIdentity(parts: Array<string | null>): string {
  const preimage = JSON.stringify(["health_timeline_discrepancy_v1", ...parts]);
  return createHash("sha256").update(preimage).digest("hex");
}

export function deriveDiscrepancyId(
  identity: DiscrepancyIdentity,
): string {
  return `hd1_${hashIdentity([
    identity.targetKind,
    identity.reasonCode,
    identity.sourceType,
    identity.dogId,
    identity.sourceId,
    identity.timelineDocumentPath,
  ])}`;
}

function parseCursor(value: unknown): ReconciliationCursor | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  if (
    raw.kind === "document_name" &&
    typeof raw.document_path === "string"
  ) {
    return {
      kind: "document_name",
      documentPath: raw.document_path,
    };
  }
  if (
    raw.kind === "recorded_at_name" &&
    (raw.recorded_at instanceof Timestamp ||
      typeof raw.recorded_at === "string") &&
    typeof raw.document_path === "string" &&
    typeof raw.normalized_recorded_at === "string"
  ) {
    return {
      kind: "recorded_at_name",
      recordedAt: raw.recorded_at,
      documentPath: raw.document_path,
      normalizedRecordedAt: raw.normalized_recorded_at,
    };
  }
  return null;
}

export function serializeCursor(
  cursor: ReconciliationCursor | null,
): DocumentData | null {
  if (cursor === null) return null;
  if (cursor.kind === "document_name") {
    return {
      kind: cursor.kind,
      document_path: cursor.documentPath,
    };
  }
  return {
    kind: cursor.kind,
    recorded_at: cursor.recordedAt,
    normalized_recorded_at: cursor.normalizedRecordedAt,
    document_path: cursor.documentPath,
  };
}

function sameTimestampOrString(
  left: QueryCursorValue,
  right: QueryCursorValue,
): boolean {
  if (left instanceof Timestamp && right instanceof Timestamp) {
    return left.isEqual(right);
  }
  return typeof left === "string" &&
    typeof right === "string" &&
    left === right;
}

export function cursorsEqual(
  left: ReconciliationCursor | null,
  right: ReconciliationCursor | null,
): boolean {
  if (left === null || right === null) return left === right;
  if (left.kind !== right.kind) return false;
  if (left.documentPath !== right.documentPath) return false;
  if (
    left.kind === "recorded_at_name" &&
    right.kind === "recorded_at_name"
  ) {
    return sameTimestampOrString(left.recordedAt, right.recordedAt) &&
      left.normalizedRecordedAt === right.normalizedRecordedAt;
  }
  return true;
}

function passStateFromData(key: string, data: DocumentData): PassState {
  return {
    key,
    cursor: parseCursor(data.cursor),
    cycle: positiveInteger(data.cycle),
    windowStart: data.window_start instanceof Timestamp ?
      data.window_start :
      null,
    windowEnd: data.window_end instanceof Timestamp ?
      data.window_end :
      null,
    windowActive: data.window_active === true,
  };
}

function discrepancyFromData(
  discrepancyId: string,
  data: DocumentData,
): DurableDiscrepancy | null {
  const validSourceType = data.source_type === null ?
    null :
    data.source_type === "meal" || data.source_type === "supplement" ?
      data.source_type :
      undefined;
  if (
    (data.target_kind !== "source" && data.target_kind !== "timeline") ||
    typeof data.reason_code !== "string" ||
    validSourceType === undefined ||
    (data.status !== "open" && data.status !== "resolved") ||
    !(data.first_seen_at instanceof Timestamp) ||
    !(data.last_seen_at instanceof Timestamp)
  ) {
    return null;
  }
  return {
    discrepancyId,
    targetKind: data.target_kind,
    reasonCode: data.reason_code as ReconciliationReasonCode,
    sourceType: validSourceType,
    dogId: typeof data.dog_id === "string" ? data.dog_id : null,
    sourceId: typeof data.source_id === "string" ? data.source_id : null,
    timelineDocumentPath:
      typeof data.timeline_document_path === "string" ?
        data.timeline_document_path :
        null,
    status: data.status,
    firstSeenAt: data.first_seen_at,
    lastSeenAt: data.last_seen_at,
    resolvedAt: data.resolved_at instanceof Timestamp ?
      data.resolved_at :
      null,
    attempts: positiveInteger(data.attempts),
    safeContext:
      data.safe_context &&
      typeof data.safe_context === "object" &&
      !Array.isArray(data.safe_context) ?
        data.safe_context as Record<string, string | number | boolean | null> :
        {},
  };
}

export type DiscrepancyWriteHook = (
  identity: DiscrepancyIdentity,
) => void | Promise<void>;

export class FirestoreReconciliationState {
  readonly rootRef: DocumentReference;

  constructor(
    readonly db: Firestore,
    private readonly clock: RuntimeClock,
    private readonly beforeDiscrepancyWrite?: DiscrepancyWriteHook,
  ) {
    this.rootRef = db.doc(RECONCILIATION_ROOT_PATH);
  }

  passRef(key: string): DocumentReference {
    return this.db.doc(reconciliationPassPath(key));
  }

  discrepancyRef(discrepancyId: string): DocumentReference {
    return this.db.doc(discrepancyPath(discrepancyId));
  }

  async startRun(
    token: LeaseToken,
    runId: string,
    passKey: string,
  ): Promise<void> {
    const ref = this.db.doc(reconciliationRunPath(runId));
    await this.db.runTransaction(async (transaction) => {
      await this.assertLeaseInTransaction(transaction, token);
      transaction.create(ref, {
        schema_version: 1,
        pass_key: safeStateKey(passKey),
        lease_owner: token.owner,
        lease_revision: token.revision,
        status: "running",
        started_at: Timestamp.fromDate(clockDate(this.clock)),
        completed_at: null,
      });
    });
  }

  async finishRun(
    token: LeaseToken,
    runId: string,
    status: "completed" | "failed",
  ): Promise<void> {
    const ref = this.db.doc(reconciliationRunPath(runId));
    await this.db.runTransaction(async (transaction) => {
      await this.assertLeaseInTransaction(transaction, token);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw new Error("Reconciliation run state does not exist.");
      }
      transaction.set(ref, {
        status,
        completed_at: Timestamp.fromDate(clockDate(this.clock)),
      }, {merge: true});
    });
  }

  async acquireLease(
    owner: string,
    durationMs: number,
  ): Promise<LeaseToken | null> {
    const safeOwner = assertSafeDocumentId(owner, "source");
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      throw new Error("Lease duration must be positive.");
    }
    return this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(this.rootRef);
      const data = snapshot.data() ?? {};
      const now = clockDate(this.clock);
      const token = decideLeaseAcquisition({
        owner: typeof data.lease_owner === "string" ?
          data.lease_owner :
          null,
        revision: positiveInteger(data.lease_revision),
        expiresAt: data.lease_expires_at instanceof Timestamp ?
          data.lease_expires_at :
          null,
      }, safeOwner, now, durationMs);
      if (token === null) return null;
      transaction.set(this.rootRef, {
        schema_version: 1,
        lease_owner: token.owner,
        lease_revision: token.revision,
        lease_expires_at: token.expiresAt,
        lease_acquired_at: Timestamp.fromDate(now),
      }, {merge: true});
      return token;
    });
  }

  async releaseLease(token: LeaseToken): Promise<boolean> {
    return this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(this.rootRef);
      const data = snapshot.data() ?? {};
      if (
        data.lease_owner !== token.owner ||
        data.lease_revision !== token.revision
      ) {
        return false;
      }
      transaction.set(this.rootRef, {
        lease_owner: null,
        lease_expires_at: Timestamp.fromDate(clockDate(this.clock)),
        lease_released_at: Timestamp.fromDate(clockDate(this.clock)),
      }, {merge: true});
      return true;
    });
  }

  async assertLeaseInTransaction(
    transaction: Transaction,
    token: LeaseToken,
  ): Promise<void> {
    const snapshot = await transaction.get(this.rootRef);
    const data = snapshot.data() ?? {};
    if (!leaseTokenOwnsState(token, {
      owner: typeof data.lease_owner === "string" ? data.lease_owner : null,
      revision: positiveInteger(data.lease_revision),
      expiresAt: data.lease_expires_at instanceof Timestamp ?
        data.lease_expires_at :
        null,
    }, clockDate(this.clock))) {
      throw new StaleLeaseError(
        "Reconciliation worker no longer owns the active fencing token.",
      );
    }
  }

  async getPassState(key: string): Promise<PassState> {
    const safeKey = safeStateKey(key);
    const snapshot = await this.passRef(safeKey).get();
    return passStateFromData(safeKey, snapshot.data() ?? {});
  }

  async readPassInTransaction(
    transaction: Transaction,
    key: string,
  ): Promise<PassState> {
    const safeKey = safeStateKey(key);
    const snapshot = await transaction.get(this.passRef(safeKey));
    return passStateFromData(safeKey, snapshot.data() ?? {});
  }

  assertExpectedCursor(
    state: PassState,
    expected: ReconciliationCursor | null,
  ): void {
    if (!cursorsEqual(state.cursor, expected)) {
      throw new StaleCursorError(
        `Pass ${state.key} cursor changed while the page was processing.`,
      );
    }
  }

  writePassStateInTransaction(
    transaction: Transaction,
    key: string,
    values: {
      cursor?: ReconciliationCursor | null;
      cycle?: number;
      windowStart?: Timestamp | null;
      windowEnd?: Timestamp | null;
      windowActive?: boolean;
    },
  ): void {
    const payload: DocumentData = {
      schema_version: 1,
      updated_at: Timestamp.fromDate(clockDate(this.clock)),
    };
    if ("cursor" in values) payload.cursor = serializeCursor(values.cursor ?? null);
    if (values.cycle !== undefined) payload.cycle = values.cycle;
    if ("windowStart" in values) payload.window_start = values.windowStart ?? null;
    if ("windowEnd" in values) payload.window_end = values.windowEnd ?? null;
    if (values.windowActive !== undefined) {
      payload.window_active = values.windowActive;
    }
    transaction.set(this.passRef(key), payload, {merge: true});
  }

  async upsertDiscrepancyInTransaction(
    transaction: Transaction,
    identity: DiscrepancyIdentity,
    safeContext: Record<string, string | number | boolean | null> = {},
  ): Promise<DurableDiscrepancy> {
    const discrepancyId = deriveDiscrepancyId(identity);
    const ref = this.discrepancyRef(discrepancyId);
    const snapshot = await transaction.get(ref);
    const existing = discrepancyFromData(
      discrepancyId,
      snapshot.data() ?? {},
    );
    if (this.beforeDiscrepancyWrite) {
      await this.beforeDiscrepancyWrite(identity);
    }
    const now = Timestamp.fromDate(clockDate(this.clock));
    const discrepancy: DurableDiscrepancy = {
      ...identity,
      discrepancyId,
      status: "open",
      firstSeenAt: existing?.firstSeenAt ?? now,
      lastSeenAt: now,
      resolvedAt: null,
      attempts: (existing?.attempts ?? 0) + 1,
      safeContext,
    };
    transaction.set(ref, {
      schema_version: 1,
      target_kind: discrepancy.targetKind,
      reason_code: discrepancy.reasonCode,
      source_type: discrepancy.sourceType,
      dog_id: discrepancy.dogId,
      source_id: discrepancy.sourceId,
      timeline_document_path: discrepancy.timelineDocumentPath,
      status: discrepancy.status,
      first_seen_at: discrepancy.firstSeenAt,
      last_seen_at: discrepancy.lastSeenAt,
      resolved_at: null,
      attempts: discrepancy.attempts,
      safe_context: discrepancy.safeContext,
    });
    return discrepancy;
  }

  async markDiscrepancyResolvedInTransaction(
    transaction: Transaction,
    discrepancy: DurableDiscrepancy,
  ): Promise<void> {
    if (this.beforeDiscrepancyWrite) {
      await this.beforeDiscrepancyWrite(discrepancy);
    }
    const now = Timestamp.fromDate(clockDate(this.clock));
    transaction.set(this.discrepancyRef(discrepancy.discrepancyId), {
      status: "resolved",
      last_seen_at: now,
      resolved_at: now,
      attempts: discrepancy.attempts + 1,
    }, {merge: true});
  }

  async touchOpenDiscrepancyInTransaction(
    transaction: Transaction,
    discrepancy: DurableDiscrepancy,
  ): Promise<void> {
    if (this.beforeDiscrepancyWrite) {
      await this.beforeDiscrepancyWrite(discrepancy);
    }
    transaction.set(this.discrepancyRef(discrepancy.discrepancyId), {
      status: "open",
      last_seen_at: Timestamp.fromDate(clockDate(this.clock)),
      attempts: discrepancy.attempts + 1,
    }, {merge: true});
  }

  discrepancyFromSnapshot(
    discrepancyId: string,
    data: DocumentData,
  ): DurableDiscrepancy | null {
    return discrepancyFromData(discrepancyId, data);
  }
}
