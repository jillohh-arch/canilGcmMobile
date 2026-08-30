/**
 * Local-only HealthTimeline reconciliation runtime foundation.
 *
 * No scheduler, trigger registration, Rules, indexes, deploy, or backfill.
 */
import {
  FieldPath,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Query,
  type QueryDocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import {deriveTimelineId} from "./health_timeline_projection";
import {
  DeterministicInvalidPayloadError,
  assertSafeDocumentId,
  parseMealLogSource,
  parseSupplementLogSource,
  sourceCollectionPath,
  sourceDocumentPath,
  type HealthTimelineSourceType,
  type ProjectionRuntimeResult,
  type RuntimeLogger,
  type TransactionalHealthTimelineProjector,
  type ValidatedProjectionSource,
} from "./health_timeline_runtime";
import {
  FirestoreReconciliationState,
  StaleCursorError,
  deriveDiscrepancyId,
  globalPassKey,
  sourcePassKey,
  type DiscrepancyIdentity,
  type DocumentNameCursor,
  type DurableDiscrepancy,
  type LeaseToken,
  type PassState,
  type ReconciliationCursor,
  type ReconciliationReasonCode,
  type RecordedAtQueryCursor,
} from "./health_timeline_reconciliation_state";

export type ReconciliationHooks = {
  beforeSourceProjection?: (
    sourceType: HealthTimelineSourceType,
    documentPath: string,
  ) => void | Promise<void>;
};

export type ReconciliationPageResult = {
  passKey: string;
  fetched: number;
  processed: number;
  created: number;
  noop: number;
  repaired: number;
  skippedAnomaly: number;
  hasMore: boolean;
  cycle: number;
};

type SourcePathIdentity = {
  sourceType: HealthTimelineSourceType;
  dogId: string;
  sourceId: string;
};

type SourceItemResult =
  | {
    status: "projected";
    projection: ProjectionRuntimeResult;
  }
  | {
    status: "skipped_anomaly";
    discrepancyId: string;
    reasonCode: ReconciliationReasonCode;
  };

type ValidatedTimelineIdentity = SourcePathIdentity & {
  timelineId: string;
  timelinePath: string;
};

type TimelineValidation =
  | {
    valid: true;
    identity: ValidatedTimelineIdentity;
  }
  | {
    valid: false;
    identity: DiscrepancyIdentity;
    safeContext: Record<string, string | number | boolean | null>;
  };

const SOURCE_COLLECTION_BY_TYPE: Readonly<
  Record<HealthTimelineSourceType, string>
> = Object.freeze({
  meal: "meal_logs",
  supplement: "supplement_logs",
});

const DEFAULT_PAGE_SIZE = 25;
const DEFAULT_OVERLAP_MS = 60 * 60 * 1000;

function positivePageSize(value: number): number {
  if (!Number.isInteger(value) || value <= 0 || value > 500) {
    throw new Error("Reconciliation page size must be an integer in [1, 500].");
  }
  return value;
}

function emptyResult(passKey: string, cycle: number): ReconciliationPageResult {
  return {
    passKey,
    fetched: 0,
    processed: 0,
    created: 0,
    noop: 0,
    repaired: 0,
    skippedAnomaly: 0,
    hasMore: false,
    cycle,
  };
}

function countItem(
  result: ReconciliationPageResult,
  item: SourceItemResult,
): void {
  result.processed += 1;
  if (item.status === "skipped_anomaly") {
    result.skippedAnomaly += 1;
    return;
  }
  result[item.projection.operation] += 1;
}

function normalizedRecordedAt(value: Timestamp | string): string {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString() === value ?
    value :
    "";
}

export function recordedAtCursorFromSnapshot(
  snapshot: QueryDocumentSnapshot,
): RecordedAtQueryCursor {
  const recordedAt = snapshot.get("recorded_at");
  if (!(recordedAt instanceof Timestamp) && typeof recordedAt !== "string") {
    throw new DeterministicInvalidPayloadError(
      "invalid-timestamp",
      "recorded_at query cursor has an unsupported physical type.",
      {field: "recorded_at"},
    );
  }
  return {
    kind: "recorded_at_name",
    recordedAt,
    normalizedRecordedAt: normalizedRecordedAt(recordedAt),
    documentPath: snapshot.ref.path,
  };
}

export function documentNameCursor(
  snapshot: QueryDocumentSnapshot,
): DocumentNameCursor {
  return {
    kind: "document_name",
    documentPath: snapshot.ref.path,
  };
}

export function parseSourceDocumentPath(
  path: string,
  expectedType?: HealthTimelineSourceType,
): SourcePathIdentity {
  const match = /^dogs\/([^/]+)\/(meal_logs|supplement_logs)\/([^/]+)$/
    .exec(path);
  if (!match) {
    throw new DeterministicInvalidPayloadError(
      "invalid-source-path",
      "Source document path is not canonical.",
    );
  }
  const sourceType: HealthTimelineSourceType =
    match[2] === "meal_logs" ? "meal" : "supplement";
  if (expectedType !== undefined && sourceType !== expectedType) {
    throw new DeterministicInvalidPayloadError(
      "invalid-source-path",
      "Source document path does not match the closed source type.",
    );
  }
  return {
    sourceType,
    dogId: assertSafeDocumentId(match[1], "dog"),
    sourceId: assertSafeDocumentId(match[3], "source"),
  };
}

function safeSourceIdentity(
  path: string,
  sourceType: HealthTimelineSourceType,
): SourcePathIdentity {
  return parseSourceDocumentPath(path, sourceType);
}

function sourceFromData(
  identity: SourcePathIdentity,
  data: DocumentData,
): ValidatedProjectionSource {
  if (identity.sourceType === "meal") {
    return {
      sourceType: "meal",
      dogId: identity.dogId,
      sourceId: identity.sourceId,
      data: parseMealLogSource(data, identity.dogId, identity.sourceId),
    };
  }
  return {
    sourceType: "supplement",
    dogId: identity.dogId,
    sourceId: identity.sourceId,
    data: parseSupplementLogSource(data, identity.dogId, identity.sourceId),
  };
}

function invalidSourceDiscrepancy(
  identity: SourcePathIdentity,
  reasonCode: ReconciliationReasonCode,
): DiscrepancyIdentity {
  return {
    targetKind: "source",
    reasonCode,
    sourceType: identity.sourceType,
    dogId: identity.dogId,
    sourceId: identity.sourceId,
    timelineDocumentPath: null,
  };
}

function timelineInvalid(
  timelinePath: string,
  reasonCode: ReconciliationReasonCode,
  values: {
    sourceType?: HealthTimelineSourceType | null;
    dogId?: string | null;
    sourceId?: string | null;
  } = {},
  safeContext: Record<string, string | number | boolean | null> = {},
): TimelineValidation {
  return {
    valid: false,
    identity: {
      targetKind: "timeline",
      reasonCode,
      sourceType: values.sourceType ?? null,
      dogId: values.dogId ?? null,
      sourceId: values.sourceId ?? null,
      timelineDocumentPath: timelinePath,
    },
    safeContext,
  };
}

export function validateTimelineForOrphanResolution(
  timelinePath: string,
  data: DocumentData,
): TimelineValidation {
  const match = /^dogs\/([^/]+)\/health_timeline\/([^/]+)$/
    .exec(timelinePath);
  if (!match) {
    return timelineInvalid(
      timelinePath,
      "timeline-invalid-path",
      {},
      {segment_count: timelinePath.split("/").length},
    );
  }

  let parentDogId: string;
  let timelineId: string;
  try {
    parentDogId = assertSafeDocumentId(match[1], "dog");
    timelineId = assertSafeDocumentId(match[2], "source");
  } catch {
    return timelineInvalid(timelinePath, "timeline-invalid-path");
  }

  if (data.dog_id !== parentDogId) {
    return timelineInvalid(
      timelinePath,
      "timeline-dog-mismatch",
      {dogId: parentDogId},
    );
  }

  let sourceType: HealthTimelineSourceType;
  if (data.source_collection === `dogs/${parentDogId}/meal_logs`) {
    sourceType = "meal";
  } else if (
    data.source_collection === `dogs/${parentDogId}/supplement_logs`
  ) {
    sourceType = "supplement";
  } else {
    return timelineInvalid(
      timelinePath,
      "timeline-source-collection-invalid",
      {dogId: parentDogId},
    );
  }

  let sourceId: string;
  try {
    sourceId = assertSafeDocumentId(data.source_id, "source");
  } catch {
    return timelineInvalid(
      timelinePath,
      "timeline-source-id-invalid",
      {sourceType, dogId: parentDogId},
    );
  }

  if (data.timeline_type !== sourceType) {
    return timelineInvalid(
      timelinePath,
      "timeline-type-mismatch",
      {sourceType, dogId: parentDogId, sourceId},
    );
  }

  const expectedId = deriveTimelineId({
    sourceCollection: sourceCollectionPath(sourceType, parentDogId),
    sourceId,
  });
  if (expectedId !== timelineId) {
    return timelineInvalid(
      timelinePath,
      "timeline-id-mismatch",
      {sourceType, dogId: parentDogId, sourceId},
    );
  }

  return {
    valid: true,
    identity: {
      sourceType,
      dogId: parentDogId,
      sourceId,
      timelineId,
      timelinePath,
    },
  };
}

function validatedSourceRef(
  db: Firestore,
  identity: SourcePathIdentity,
): DocumentReference {
  return db.doc(sourceDocumentPath(
    identity.sourceType,
    identity.dogId,
    identity.sourceId,
  ));
}

function validatedTimelineRef(
  db: Firestore,
  path: string,
): DocumentReference | null {
  const match = /^dogs\/([^/]+)\/health_timeline\/([^/]+)$/.exec(path);
  if (!match) return null;
  try {
    assertSafeDocumentId(match[1], "dog");
    assertSafeDocumentId(match[2], "source");
    return db.doc(path);
  } catch {
    return null;
  }
}

function validatedCursorReference(
  db: Firestore,
  cursor: ReconciliationCursor,
  expectedSourceType?: HealthTimelineSourceType,
): DocumentReference {
  if (expectedSourceType !== undefined) {
    parseSourceDocumentPath(cursor.documentPath, expectedSourceType);
  } else if (
    !/^dogs\/[^/]+\/health_timeline\/[^/]+$/.test(cursor.documentPath) &&
    !cursor.documentPath.startsWith(
      "_health_projection_state/health_timeline_v1/discrepancies/",
    )
  ) {
    throw new DeterministicInvalidPayloadError(
      "invalid-source-path",
      "Persisted cursor path is outside the closed reconciliation paths.",
    );
  }
  return db.doc(cursor.documentPath);
}

function sourceQuery(
  db: Firestore,
  sourceType: HealthTimelineSourceType,
  cursor: RecordedAtQueryCursor | null,
  pageSize: number,
): Query {
  let query: Query = db.collectionGroup(SOURCE_COLLECTION_BY_TYPE[sourceType])
    .orderBy("recorded_at", "asc")
    .orderBy(FieldPath.documentId(), "asc");
  if (cursor !== null) {
    query = query.startAfter(
      cursor.recordedAt,
      validatedCursorReference(db, cursor, sourceType),
    );
  }
  return query.limit(pageSize);
}

function sourceNameQuery(
  db: Firestore,
  sourceType: HealthTimelineSourceType,
  cursor: DocumentNameCursor | null,
  pageSize: number,
): Query {
  let query: Query = db.collectionGroup(SOURCE_COLLECTION_BY_TYPE[sourceType])
    .orderBy(FieldPath.documentId(), "asc");
  if (cursor !== null) {
    query = query.startAfter(
      validatedCursorReference(db, cursor, sourceType),
    );
  }
  return query.limit(pageSize);
}

function isRecordedAtCursor(
  cursor: ReconciliationCursor | null,
): cursor is RecordedAtQueryCursor {
  return cursor?.kind === "recorded_at_name";
}

function isDocumentNameCursor(
  cursor: ReconciliationCursor | null,
): cursor is DocumentNameCursor {
  return cursor?.kind === "document_name";
}

export class HealthTimelineReconciliationRuntime {
  constructor(
    private readonly db: Firestore,
    private readonly state: FirestoreReconciliationState,
    private readonly projector: TransactionalHealthTimelineProjector,
    private readonly logger: RuntimeLogger,
    private readonly hooks: ReconciliationHooks = {},
  ) {}

  private async writeDiscrepancyAndAdvance(
    transaction: Transaction,
    passKey: string,
    identity: DiscrepancyIdentity,
    nextCursor: ReconciliationCursor,
    safeContext: Record<string, string | number | boolean | null>,
  ): Promise<SourceItemResult> {
    const discrepancy = await this.state.upsertDiscrepancyInTransaction(
      transaction,
      identity,
      safeContext,
    );
    this.state.writePassStateInTransaction(transaction, passKey, {
      cursor: nextCursor,
    });
    return {
      status: "skipped_anomaly",
      discrepancyId: discrepancy.discrepancyId,
      reasonCode: identity.reasonCode,
    };
  }

  private async processSourceItem(params: {
    token: LeaseToken;
    passKey: string;
    sourceType: HealthTimelineSourceType;
    sourceRef: DocumentReference;
    expectedCursor: ReconciliationCursor | null;
    nextCursor: ReconciliationCursor;
    requireTimestampRecordedAt: boolean;
  }): Promise<SourceItemResult> {
    return this.db.runTransaction(async (transaction) => {
      await this.state.assertLeaseInTransaction(transaction, params.token);
      const pass = await this.state.readPassInTransaction(
        transaction,
        params.passKey,
      );
      this.state.assertExpectedCursor(pass, params.expectedCursor);
      const sourceSnapshot = await transaction.get(params.sourceRef);
      const identity = safeSourceIdentity(
        params.sourceRef.path,
        params.sourceType,
      );

      if (!sourceSnapshot.exists) {
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          invalidSourceDiscrepancy(
            identity,
            "source-missing-during-pass",
          ),
          params.nextCursor,
          {pass_key: params.passKey},
        );
      }

      if (this.hooks.beforeSourceProjection) {
        await this.hooks.beforeSourceProjection(
          params.sourceType,
          params.sourceRef.path,
        );
      }

      const raw = sourceSnapshot.data() ?? {};
      if (
        params.requireTimestampRecordedAt &&
        !(raw.recorded_at instanceof Timestamp)
      ) {
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          invalidSourceDiscrepancy(
            identity,
            "unsupported-recorded-at-type",
          ),
          params.nextCursor,
          {
            pass_key: params.passKey,
            physical_type: typeof raw.recorded_at,
          },
        );
      }

      let source: ValidatedProjectionSource;
      try {
        source = sourceFromData(identity, raw);
      } catch (error) {
        if (!(error instanceof DeterministicInvalidPayloadError)) throw error;
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          invalidSourceDiscrepancy(identity, "invalid-source-payload"),
          params.nextCursor,
          {
            pass_key: params.passKey,
            runtime_reason: error.reasonCode,
          },
        );
      }

      const projection = await this.projector.projectInTransaction(
        transaction,
        source,
      );
      this.state.writePassStateInTransaction(transaction, params.passKey, {
        cursor: params.nextCursor,
      });
      return {status: "projected", projection};
    });
  }

  private async completeCursorCycle(params: {
    token: LeaseToken;
    passKey: string;
    expectedCursor: ReconciliationCursor | null;
    cycle: number;
    clearWindow?: boolean;
  }): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      await this.state.assertLeaseInTransaction(transaction, params.token);
      const pass = await this.state.readPassInTransaction(
        transaction,
        params.passKey,
      );
      this.state.assertExpectedCursor(pass, params.expectedCursor);
      this.state.writePassStateInTransaction(transaction, params.passKey, {
        cursor: null,
        cycle: params.cycle + 1,
        ...(params.clearWindow ? {
          windowStart: null,
          windowEnd: null,
          windowActive: false,
        } : {}),
      });
    });
  }

  async runForwardPage(
    token: LeaseToken,
    sourceType: HealthTimelineSourceType,
    pageSize = DEFAULT_PAGE_SIZE,
  ): Promise<ReconciliationPageResult> {
    const size = positivePageSize(pageSize);
    const passKey = sourcePassKey(sourceType, "forward");
    const initial = await this.state.getPassState(passKey);
    if (initial.cursor !== null && !isRecordedAtCursor(initial.cursor)) {
      throw new StaleCursorError("Forward pass has an incompatible cursor.");
    }
    const snapshot = await sourceQuery(
      this.db,
      sourceType,
      initial.cursor,
      size,
    ).get();
    const result = emptyResult(passKey, initial.cycle);
    result.fetched = snapshot.size;
    result.hasMore = snapshot.size === size;
    let expectedCursor = initial.cursor;

    for (const document of snapshot.docs) {
      const nextCursor = recordedAtCursorFromSnapshot(document);
      const item = await this.processSourceItem({
        token,
        passKey,
        sourceType,
        sourceRef: document.ref,
        expectedCursor,
        nextCursor,
        requireTimestampRecordedAt: true,
      });
      countItem(result, item);
      expectedCursor = nextCursor;
    }
    return result;
  }

  private async startOverlapWindow(
    token: LeaseToken,
    sourceType: HealthTimelineSourceType,
    overlapMs: number,
  ): Promise<PassState | null> {
    if (!Number.isFinite(overlapMs) || overlapMs <= 0) {
      throw new Error("Overlap window must be positive.");
    }
    const forwardKey = sourcePassKey(sourceType, "forward");
    const overlapKey = sourcePassKey(sourceType, "overlap");
    const forward = await this.state.getPassState(forwardKey);
    if (
      !isRecordedAtCursor(forward.cursor) ||
      !(forward.cursor.recordedAt instanceof Timestamp)
    ) {
      return null;
    }
    const end = forward.cursor.recordedAt;
    const start = Timestamp.fromMillis(
      Math.max(0, end.toMillis() - overlapMs),
    );
    await this.db.runTransaction(async (transaction) => {
      await this.state.assertLeaseInTransaction(transaction, token);
      const current = await this.state.readPassInTransaction(
        transaction,
        overlapKey,
      );
      if (current.windowActive) return;
      this.state.writePassStateInTransaction(transaction, overlapKey, {
        cursor: null,
        cycle: current.cycle,
        windowStart: start,
        windowEnd: end,
        windowActive: true,
      });
    });
    return this.state.getPassState(overlapKey);
  }

  async runOverlapPage(
    token: LeaseToken,
    sourceType: HealthTimelineSourceType,
    pageSize = DEFAULT_PAGE_SIZE,
    overlapMs = DEFAULT_OVERLAP_MS,
  ): Promise<ReconciliationPageResult> {
    const size = positivePageSize(pageSize);
    const passKey = sourcePassKey(sourceType, "overlap");
    let pass = await this.state.getPassState(passKey);
    if (!pass.windowActive) {
      const started = await this.startOverlapWindow(
        token,
        sourceType,
        overlapMs,
      );
      if (started === null) return emptyResult(passKey, pass.cycle);
      pass = started;
    }
    if (
      !(pass.windowStart instanceof Timestamp) ||
      !(pass.windowEnd instanceof Timestamp) ||
      (pass.cursor !== null && !isRecordedAtCursor(pass.cursor))
    ) {
      throw new StaleCursorError("Overlap pass state is structurally invalid.");
    }

    let query: Query = this.db
      .collectionGroup(SOURCE_COLLECTION_BY_TYPE[sourceType])
      .where("recorded_at", ">=", pass.windowStart)
      .where("recorded_at", "<=", pass.windowEnd)
      .orderBy("recorded_at", "asc")
      .orderBy(FieldPath.documentId(), "asc");
    if (pass.cursor !== null) {
      query = query.startAfter(
        pass.cursor.recordedAt,
        validatedCursorReference(this.db, pass.cursor, sourceType),
      );
    }
    const snapshot = await query.limit(size).get();
    const result = emptyResult(passKey, pass.cycle);
    result.fetched = snapshot.size;
    result.hasMore = snapshot.size === size;
    let expectedCursor = pass.cursor;

    for (const document of snapshot.docs) {
      const nextCursor = recordedAtCursorFromSnapshot(document);
      const item = await this.processSourceItem({
        token,
        passKey,
        sourceType,
        sourceRef: document.ref,
        expectedCursor,
        nextCursor,
        requireTimestampRecordedAt: true,
      });
      countItem(result, item);
      expectedCursor = nextCursor;
    }

    if (!result.hasMore) {
      await this.completeCursorCycle({
        token,
        passKey,
        expectedCursor,
        cycle: pass.cycle,
        clearWindow: true,
      });
    }
    return result;
  }

  async runHistoricalPage(
    token: LeaseToken,
    sourceType: HealthTimelineSourceType,
    pageSize = DEFAULT_PAGE_SIZE,
  ): Promise<ReconciliationPageResult> {
    const size = positivePageSize(pageSize);
    const passKey = sourcePassKey(sourceType, "historical");
    const initial = await this.state.getPassState(passKey);
    if (initial.cursor !== null && !isDocumentNameCursor(initial.cursor)) {
      throw new StaleCursorError("Historical pass has an incompatible cursor.");
    }
    const snapshot = await sourceNameQuery(
      this.db,
      sourceType,
      initial.cursor,
      size,
    ).get();
    const result = emptyResult(passKey, initial.cycle);
    result.fetched = snapshot.size;
    result.hasMore = snapshot.size === size;
    let expectedCursor = initial.cursor;

    for (const document of snapshot.docs) {
      const nextCursor = documentNameCursor(document);
      const item = await this.processSourceItem({
        token,
        passKey,
        sourceType,
        sourceRef: document.ref,
        expectedCursor,
        nextCursor,
        requireTimestampRecordedAt: false,
      });
      countItem(result, item);
      expectedCursor = nextCursor;
    }

    if (!result.hasMore) {
      await this.completeCursorCycle({
        token,
        passKey,
        expectedCursor,
        cycle: initial.cycle,
      });
    }
    return result;
  }

  private async processTimelineItem(params: {
    token: LeaseToken;
    passKey: string;
    timelineRef: DocumentReference;
    expectedCursor: ReconciliationCursor | null;
    nextCursor: DocumentNameCursor;
  }): Promise<SourceItemResult> {
    return this.db.runTransaction(async (transaction) => {
      await this.state.assertLeaseInTransaction(transaction, params.token);
      const pass = await this.state.readPassInTransaction(
        transaction,
        params.passKey,
      );
      this.state.assertExpectedCursor(pass, params.expectedCursor);
      const timelineSnapshot = await transaction.get(params.timelineRef);
      if (!timelineSnapshot.exists) {
        throw new Error(
          "Timeline document disappeared during orphan reconciliation.",
        );
      }

      const validation = validateTimelineForOrphanResolution(
        params.timelineRef.path,
        timelineSnapshot.data() ?? {},
      );
      if (!validation.valid) {
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          validation.identity,
          params.nextCursor,
          validation.safeContext,
        );
      }

      const sourceRef = validatedSourceRef(this.db, validation.identity);
      const sourceSnapshot = await transaction.get(sourceRef);
      if (!sourceSnapshot.exists) {
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          {
            targetKind: "timeline",
            reasonCode: "orphan-source-missing",
            sourceType: validation.identity.sourceType,
            dogId: validation.identity.dogId,
            sourceId: validation.identity.sourceId,
            timelineDocumentPath: validation.identity.timelinePath,
          },
          params.nextCursor,
          {pass_key: params.passKey},
        );
      }

      let source: ValidatedProjectionSource;
      try {
        source = sourceFromData(
          validation.identity,
          sourceSnapshot.data() ?? {},
        );
      } catch (error) {
        if (!(error instanceof DeterministicInvalidPayloadError)) throw error;
        return this.writeDiscrepancyAndAdvance(
          transaction,
          params.passKey,
          {
            targetKind: "source",
            reasonCode: "invalid-source-payload",
            sourceType: validation.identity.sourceType,
            dogId: validation.identity.dogId,
            sourceId: validation.identity.sourceId,
            timelineDocumentPath: validation.identity.timelinePath,
          },
          params.nextCursor,
          {runtime_reason: error.reasonCode},
        );
      }

      const projection = await this.projector.projectInTransaction(
        transaction,
        source,
      );
      this.state.writePassStateInTransaction(transaction, params.passKey, {
        cursor: params.nextCursor,
      });
      return {status: "projected", projection};
    });
  }

  async runOrphanPage(
    token: LeaseToken,
    pageSize = DEFAULT_PAGE_SIZE,
  ): Promise<ReconciliationPageResult> {
    const size = positivePageSize(pageSize);
    const passKey = globalPassKey("orphan");
    const initial = await this.state.getPassState(passKey);
    if (initial.cursor !== null && !isDocumentNameCursor(initial.cursor)) {
      throw new StaleCursorError("Orphan pass has an incompatible cursor.");
    }
    let query: Query = this.db.collectionGroup("health_timeline")
      .orderBy(FieldPath.documentId(), "asc");
    if (initial.cursor !== null) {
      query = query.startAfter(
        validatedCursorReference(this.db, initial.cursor),
      );
    }
    const snapshot = await query.limit(size).get();
    const result = emptyResult(passKey, initial.cycle);
    result.fetched = snapshot.size;
    result.hasMore = snapshot.size === size;
    let expectedCursor = initial.cursor;

    for (const document of snapshot.docs) {
      const nextCursor = documentNameCursor(document);
      const item = await this.processTimelineItem({
        token,
        passKey,
        timelineRef: document.ref,
        expectedCursor,
        nextCursor,
      });
      countItem(result, item);
      expectedCursor = nextCursor;
    }

    if (!result.hasMore) {
      await this.completeCursorCycle({
        token,
        passKey,
        expectedCursor,
        cycle: initial.cycle,
      });
    }
    return result;
  }

  private async reprocessKnownDiscrepancy(params: {
    token: LeaseToken;
    passKey: string;
    discrepancyRef: DocumentReference;
    expectedCursor: ReconciliationCursor | null;
    nextCursor: DocumentNameCursor;
  }): Promise<SourceItemResult> {
    return this.db.runTransaction(async (transaction) => {
      await this.state.assertLeaseInTransaction(transaction, params.token);
      const pass = await this.state.readPassInTransaction(
        transaction,
        params.passKey,
      );
      this.state.assertExpectedCursor(pass, params.expectedCursor);
      const snapshot = await transaction.get(params.discrepancyRef);
      const discrepancy = snapshot.exists ?
        this.state.discrepancyFromSnapshot(
          snapshot.id,
          snapshot.data() ?? {},
        ) :
        null;
      if (discrepancy === null || discrepancy.status !== "open") {
        this.state.writePassStateInTransaction(transaction, params.passKey, {
          cursor: params.nextCursor,
        });
        return {
          status: "skipped_anomaly",
          discrepancyId: snapshot.id,
          reasonCode: "invalid-source-payload",
        };
      }

      const result = await this.tryResolveDiscrepancy(
        transaction,
        discrepancy,
      );
      this.state.writePassStateInTransaction(transaction, params.passKey, {
        cursor: params.nextCursor,
      });
      return result;
    });
  }

  private safeIdentityFromDiscrepancy(
    discrepancy: DurableDiscrepancy,
  ): SourcePathIdentity | null {
    if (
      discrepancy.sourceType === null ||
      discrepancy.dogId === null ||
      discrepancy.sourceId === null
    ) {
      return null;
    }
    try {
      return {
        sourceType: discrepancy.sourceType,
        dogId: assertSafeDocumentId(discrepancy.dogId, "dog"),
        sourceId: assertSafeDocumentId(discrepancy.sourceId, "source"),
      };
    } catch {
      return null;
    }
  }

  private async tryResolveDiscrepancy(
    transaction: Transaction,
    discrepancy: DurableDiscrepancy,
  ): Promise<SourceItemResult> {
    let identity = this.safeIdentityFromDiscrepancy(discrepancy);

    if (identity === null && discrepancy.timelineDocumentPath !== null) {
      const timelineRef = validatedTimelineRef(
        this.db,
        discrepancy.timelineDocumentPath,
      );
      if (timelineRef === null) {
        await this.state.touchOpenDiscrepancyInTransaction(
          transaction,
          discrepancy,
        );
        return {
          status: "skipped_anomaly",
          discrepancyId: discrepancy.discrepancyId,
          reasonCode: discrepancy.reasonCode,
        };
      }
      const timelineSnapshot = await transaction.get(timelineRef);
      if (!timelineSnapshot.exists) {
        await this.state.markDiscrepancyResolvedInTransaction(
          transaction,
          discrepancy,
        );
        return {
          status: "skipped_anomaly",
          discrepancyId: discrepancy.discrepancyId,
          reasonCode: discrepancy.reasonCode,
        };
      }
      const validation = validateTimelineForOrphanResolution(
        timelineRef.path,
        timelineSnapshot.data() ?? {},
      );
      if (!validation.valid) {
        await this.state.touchOpenDiscrepancyInTransaction(
          transaction,
          discrepancy,
        );
        return {
          status: "skipped_anomaly",
          discrepancyId: discrepancy.discrepancyId,
          reasonCode: discrepancy.reasonCode,
        };
      }
      identity = validation.identity;
    }

    if (identity === null) {
      await this.state.touchOpenDiscrepancyInTransaction(
        transaction,
        discrepancy,
      );
      return {
        status: "skipped_anomaly",
        discrepancyId: discrepancy.discrepancyId,
        reasonCode: discrepancy.reasonCode,
      };
    }

    const sourceRef = validatedSourceRef(this.db, identity);
    const sourceSnapshot = await transaction.get(sourceRef);
    if (!sourceSnapshot.exists) {
      await this.state.touchOpenDiscrepancyInTransaction(
        transaction,
        discrepancy,
      );
      return {
        status: "skipped_anomaly",
        discrepancyId: discrepancy.discrepancyId,
        reasonCode: discrepancy.reasonCode,
      };
    }

    const sourceData = sourceSnapshot.data() ?? {};
    if (
      discrepancy.reasonCode === "unsupported-recorded-at-type" &&
      !(sourceData.recorded_at instanceof Timestamp)
    ) {
      await this.state.touchOpenDiscrepancyInTransaction(
        transaction,
        discrepancy,
      );
      return {
        status: "skipped_anomaly",
        discrepancyId: discrepancy.discrepancyId,
        reasonCode: discrepancy.reasonCode,
      };
    }

    let source: ValidatedProjectionSource;
    try {
      source = sourceFromData(identity, sourceData);
    } catch (error) {
      if (!(error instanceof DeterministicInvalidPayloadError)) throw error;
      await this.state.touchOpenDiscrepancyInTransaction(
        transaction,
        discrepancy,
      );
      return {
        status: "skipped_anomaly",
        discrepancyId: discrepancy.discrepancyId,
        reasonCode: discrepancy.reasonCode,
      };
    }

    const projection = await this.projector.projectInTransaction(
      transaction,
      source,
    );
    await this.state.markDiscrepancyResolvedInTransaction(
      transaction,
      discrepancy,
    );
    return {status: "projected", projection};
  }

  async runKnownDiscrepancyPage(
    token: LeaseToken,
    pageSize = DEFAULT_PAGE_SIZE,
  ): Promise<ReconciliationPageResult> {
    const size = positivePageSize(pageSize);
    const passKey = globalPassKey("known_discrepancies");
    const initial = await this.state.getPassState(passKey);
    if (initial.cursor !== null && !isDocumentNameCursor(initial.cursor)) {
      throw new StaleCursorError(
        "Known discrepancy pass has an incompatible cursor.",
      );
    }
    let query: Query = this.db
      .collection("_health_projection_state/health_timeline_v1/discrepancies")
      .where("status", "==", "open")
      .orderBy(FieldPath.documentId(), "asc");
    if (initial.cursor !== null) {
      query = query.startAfter(
        validatedCursorReference(this.db, initial.cursor),
      );
    }
    const snapshot = await query.limit(size).get();
    const result = emptyResult(passKey, initial.cycle);
    result.fetched = snapshot.size;
    result.hasMore = snapshot.size === size;
    let expectedCursor = initial.cursor;

    for (const document of snapshot.docs) {
      const nextCursor = documentNameCursor(document);
      const item = await this.reprocessKnownDiscrepancy({
        token,
        passKey,
        discrepancyRef: document.ref,
        expectedCursor,
        nextCursor,
      });
      countItem(result, item);
      expectedCursor = nextCursor;
    }

    if (!result.hasMore) {
      await this.completeCursorCycle({
        token,
        passKey,
        expectedCursor,
        cycle: initial.cycle,
      });
    }
    return result;
  }

  discrepancyIdFor(identity: DiscrepancyIdentity): string {
    return deriveDiscrepancyId(identity);
  }

  logPage(result: ReconciliationPageResult): void {
    this.logger.info("HealthTimeline reconciliation page completed", {
      passKey: result.passKey,
      fetched: result.fetched,
      processed: result.processed,
      created: result.created,
      noop: result.noop,
      repaired: result.repaired,
      skippedAnomaly: result.skippedAnomaly,
      hasMore: result.hasMore,
      cycle: result.cycle,
    });
  }
}
