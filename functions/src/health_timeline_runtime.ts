/**
 * HealthTimeline productization runtime foundation.
 *
 * Local-only in Gate 5C.5C.2: no Cloud Function export and no scheduler.
 */
import {
  Timestamp,
  type DocumentData,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {
  compareProjection,
  deriveTimelineId,
  projectMealLog,
  projectSupplementLog,
  type MealLogData,
  type ProjectionOperationResult,
  type SupplementLogData,
  type TimelineEntry,
} from "./health_timeline_projection";
import {
  MEAL_ACCEPTANCES,
  MEAL_PERIODS,
  SUPPLEMENT_UNITS,
} from "./health_nutrition_logic";

export type HealthTimelineSourceType = "meal" | "supplement";

export type RuntimeClock = {
  now: () => Date;
};

export type RuntimeLogger = {
  info: (message: string, context?: Record<string, unknown>) => void;
  warn: (message: string, context?: Record<string, unknown>) => void;
  error: (message: string, context?: Record<string, unknown>) => void;
};

export type RuntimeReasonCode =
  | "invalid-source-type"
  | "invalid-dog-id"
  | "invalid-source-id"
  | "invalid-source-path"
  | "cross-dog-source"
  | "malformed-payload"
  | "invalid-timestamp"
  | "invalid-recorded-by";

export class DeterministicInvalidPayloadError extends Error {
  readonly reasonCode: RuntimeReasonCode;
  readonly safeContext: Record<string, unknown>;

  constructor(
    reasonCode: RuntimeReasonCode,
    message: string,
    safeContext: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "DeterministicInvalidPayloadError";
    this.reasonCode = reasonCode;
    this.safeContext = safeContext;
  }
}

export class TransientInfrastructureError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TransientInfrastructureError";
  }
}

export type ValidatedProjectionSource =
  | {
    sourceType: "meal";
    dogId: string;
    sourceId: string;
    data: MealLogData;
  }
  | {
    sourceType: "supplement";
    dogId: string;
    sourceId: string;
    data: SupplementLogData;
  };

export type CanonicalTimelineDocument = {
  timeline_type: "meal" | "supplement";
  source_collection: string;
  source_id: string;
  occurred_at: Timestamp;
  recorded_at: Timestamp;
  projected_at: Timestamp;
  title: string;
  subtitle?: string;
  dog_id: string;
  recorded_by: {
    uid: string;
    name: string;
    internal_role: string;
  };
  status: "final" | "cancelled";
  schema_version: number;
};

const SOURCE_COLLECTION_NAMES: Readonly<Record<HealthTimelineSourceType, string>> =
  Object.freeze({
    meal: "meal_logs",
    supplement: "supplement_logs",
  });

const CANONICAL_TIMELINE_KEYS = Object.freeze([
  "timeline_type",
  "source_collection",
  "source_id",
  "occurred_at",
  "recorded_at",
  "projected_at",
  "title",
  "subtitle",
  "dog_id",
  "recorded_by",
  "status",
  "schema_version",
] as const);

export function canonicalTimelineKeys(): readonly string[] {
  return CANONICAL_TIMELINE_KEYS;
}

export function isHealthTimelineSourceType(
  value: unknown,
): value is HealthTimelineSourceType {
  return value === "meal" || value === "supplement";
}

export function assertSafeDocumentId(
  value: unknown,
  kind: "dog" | "source",
): string {
  const reasonCode = kind === "dog" ? "invalid-dog-id" : "invalid-source-id";
  if (typeof value !== "string") {
    throw new DeterministicInvalidPayloadError(
      reasonCode,
      `${kind}Id deve ser string.`,
    );
  }
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > 1500 ||
    normalized.includes("/") ||
    normalized === "." ||
    normalized === ".." ||
    /^__.*__$/.test(normalized)
  ) {
    throw new DeterministicInvalidPayloadError(
      reasonCode,
      `${kind}Id inválido.`,
      {[`${kind}IdLength`]: normalized.length},
    );
  }
  return normalized;
}

export function sourceCollectionPath(
  sourceType: HealthTimelineSourceType,
  dogId: string,
): string {
  if (!isHealthTimelineSourceType(sourceType)) {
    throw new DeterministicInvalidPayloadError(
      "invalid-source-type",
      "Source type fora da allowlist.",
    );
  }
  const safeDogId = assertSafeDocumentId(dogId, "dog");
  return `dogs/${safeDogId}/${SOURCE_COLLECTION_NAMES[sourceType]}`;
}

export function sourceDocumentPath(
  sourceType: HealthTimelineSourceType,
  dogId: string,
  sourceId: string,
): string {
  return `${sourceCollectionPath(sourceType, dogId)}/${assertSafeDocumentId(sourceId, "source")}`;
}

export function timelineDocumentPath(
  dogId: string,
  timelineId: string,
): string {
  return `dogs/${assertSafeDocumentId(dogId, "dog")}/health_timeline/${assertSafeDocumentId(timelineId, "source")}`;
}

function strictIsoDate(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new DeterministicInvalidPayloadError(
      "invalid-timestamp",
      `${field} deve ser Timestamp ou ISO-8601 canônico.`,
      {field},
    );
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString() !== value) {
    throw new DeterministicInvalidPayloadError(
      "invalid-timestamp",
      `${field} contém ISO-8601 inválido.`,
      {field},
    );
  }
  return value;
}

/**
 * Canonical sources currently coexist with strict ISO values emitted by the
 * approved Nutrition callables. Both strict ISO and Firestore Timestamp are
 * accepted at the source boundary; timeline persistence is always Timestamp.
 */
export function firestoreTimestampToPure(
  value: unknown,
  field: string,
): string {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  return strictIsoDate(value, field);
}

export function pureTimestampToFirestore(
  value: unknown,
  field: string,
): Timestamp {
  const iso = strictIsoDate(value, field);
  return Timestamp.fromDate(new Date(iso));
}

function requiredString(
  value: unknown,
  field: string,
  reasonCode: RuntimeReasonCode = "malformed-payload",
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new DeterministicInvalidPayloadError(
      reasonCode,
      `${field} deve ser string não vazia.`,
      {field},
    );
  }
  return value.trim();
}

function optionalString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requiredString(value, field);
}

function requiredCanonicalValue(
  value: unknown,
  field: string,
  allowed: ReadonlySet<string>,
): string {
  const parsed = requiredString(value, field);
  if (!allowed.has(parsed)) {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      `${field} fora do enum canônico.`,
      {field},
    );
  }
  return parsed;
}

function optionalCanonicalValue(
  value: unknown,
  field: string,
  allowed: ReadonlySet<string>,
): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requiredCanonicalValue(value, field, allowed);
}

function requiredFiniteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      `${field} deve ser número finito.`,
      {field},
    );
  }
  return value;
}

function recordedByFromPayload(value: unknown): MealLogData["recorded_by"] {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new DeterministicInvalidPayloadError(
      "invalid-recorded-by",
      "recorded_by deve ser objeto.",
    );
  }
  const raw = value as Record<string, unknown>;
  return {
    uid: requiredString(raw.uid, "recorded_by.uid", "invalid-recorded-by"),
    name: requiredString(raw.name, "recorded_by.name", "invalid-recorded-by"),
    internal_role: requiredString(
      raw.internal_role,
      "recorded_by.internal_role",
      "invalid-recorded-by",
    ),
  };
}

export function parseMealLogSource(
  raw: DocumentData,
  dogId: string,
  sourceId: string,
): MealLogData {
  const safeDogId = assertSafeDocumentId(dogId, "dog");
  const safeSourceId = assertSafeDocumentId(sourceId, "source");
  const offered = requiredFiniteNumber(raw.offered_grams, "offered_grams");
  if (offered <= 0) {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      "offered_grams deve ser maior que zero.",
      {field: "offered_grams"},
    );
  }
  const consumed = raw.consumed_grams === null || raw.consumed_grams === undefined ?
    null :
    requiredFiniteNumber(raw.consumed_grams, "consumed_grams");
  if (consumed !== null && (consumed < 0 || consumed > offered)) {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      "consumed_grams fora do intervalo permitido.",
      {field: "consumed_grams"},
    );
  }
  const explicitKind = raw.kind;
  const inferredKind = raw.plan_id || raw.planned_meal_id ? "planned" : "adhoc";
  const kind = explicitKind === undefined ?
    inferredKind :
    explicitKind === "planned" || explicitKind === "adhoc" ?
      explicitKind :
      (() => {
        throw new DeterministicInvalidPayloadError(
          "malformed-payload",
          "kind inválido.",
          {field: "kind"},
        );
      })();

  return {
    id: safeSourceId,
    dogId: safeDogId,
    kind,
    acceptance: requiredCanonicalValue(
      raw.acceptance,
      "acceptance",
      MEAL_ACCEPTANCES,
    ),
    offered_grams: offered,
    consumed_grams: consumed,
    fed_at: firestoreTimestampToPure(raw.fed_at, "fed_at"),
    recorded_at: firestoreTimestampToPure(raw.recorded_at, "recorded_at"),
    recorded_by: recordedByFromPayload(raw.recorded_by),
    food_name: optionalString(raw.food_name, "food_name"),
    period: optionalCanonicalValue(raw.period, "period", MEAL_PERIODS),
    plan_id: optionalString(raw.plan_id, "plan_id"),
    planned_meal_id: optionalString(raw.planned_meal_id, "planned_meal_id"),
    meal_occurrence_id: optionalString(raw.meal_occurrence_id, "meal_occurrence_id"),
    scheduled_for: raw.scheduled_for === undefined || raw.scheduled_for === null ?
      undefined :
      firestoreTimestampToPure(raw.scheduled_for, "scheduled_for"),
  };
}

export function parseSupplementLogSource(
  raw: DocumentData,
  dogId: string,
  sourceId: string,
): SupplementLogData {
  const safeDogId = assertSafeDocumentId(dogId, "dog");
  const safeSourceId = assertSafeDocumentId(sourceId, "source");
  const dose = requiredFiniteNumber(raw.dose, "dose");
  if (dose <= 0) {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      "dose deve ser maior que zero.",
      {field: "dose"},
    );
  }
  return {
    id: safeSourceId,
    dogId: safeDogId,
    supplement_name: requiredString(raw.supplement_name, "supplement_name"),
    dose,
    unit: requiredCanonicalValue(raw.unit, "unit", SUPPLEMENT_UNITS),
    administered_at: firestoreTimestampToPure(
      raw.administered_at,
      "administered_at",
    ),
    recorded_at: firestoreTimestampToPure(raw.recorded_at, "recorded_at"),
    recorded_by: recordedByFromPayload(raw.recorded_by),
    nutrition_plan_id: optionalString(
      raw.nutrition_plan_id,
      "nutrition_plan_id",
    ) ?? null,
    supplement_regimen_id: optionalString(
      raw.supplement_regimen_id,
      "supplement_regimen_id",
    ) ?? null,
    notes: optionalString(raw.notes, "notes") ?? null,
  };
}

function expectedProjection(
  source: ValidatedProjectionSource,
  timelineId: string,
  nowIso: string,
): TimelineEntry {
  const projected = source.sourceType === "meal" ?
    projectMealLog(source.data, timelineId) :
    projectSupplementLog(source.data, timelineId);
  return {
    ...projected,
    projected_at: nowIso,
    created_at: nowIso,
    updated_at: nowIso,
  };
}

export function serializeCanonicalTimeline(
  entry: TimelineEntry & Record<string, unknown>,
): CanonicalTimelineDocument {
  if (entry.timeline_type !== "meal" && entry.timeline_type !== "supplement") {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      "timeline_type fora do pipeline permitido.",
    );
  }
  if (entry.status !== "final" && entry.status !== "cancelled") {
    throw new DeterministicInvalidPayloadError(
      "malformed-payload",
      "status de timeline inválido.",
    );
  }
  const serialized: CanonicalTimelineDocument = {
    timeline_type: entry.timeline_type,
    source_collection: requiredString(
      entry.source_collection,
      "source_collection",
    ),
    source_id: assertSafeDocumentId(entry.source_id, "source"),
    occurred_at: pureTimestampToFirestore(entry.occurred_at, "occurred_at"),
    recorded_at: pureTimestampToFirestore(entry.recorded_at, "recorded_at"),
    projected_at: pureTimestampToFirestore(entry.projected_at, "projected_at"),
    title: requiredString(entry.title, "title"),
    dog_id: assertSafeDocumentId(entry.dog_id, "dog"),
    recorded_by: recordedByFromPayload(entry.recorded_by),
    status: entry.status,
    schema_version: requiredFiniteNumber(
      entry.schema_version,
      "schema_version",
    ),
  };
  if (entry.subtitle !== undefined) {
    serialized.subtitle = requiredString(entry.subtitle, "subtitle");
  }
  return serialized;
}

function existingTimelineToPure(
  raw: DocumentData,
): TimelineEntry | null {
  try {
    const timelineType = raw.timeline_type;
    const status = raw.status;
    if (
      (timelineType !== "meal" && timelineType !== "supplement") ||
      (status !== "final" && status !== "cancelled")
    ) {
      return null;
    }
    const projectedAt = firestoreTimestampToPure(
      raw.projected_at,
      "projected_at",
    );
    return {
      timeline_type: timelineType,
      source_collection: requiredString(
        raw.source_collection,
        "source_collection",
      ),
      source_id: assertSafeDocumentId(raw.source_id, "source"),
      occurred_at: firestoreTimestampToPure(raw.occurred_at, "occurred_at"),
      status,
      recorded_at: firestoreTimestampToPure(raw.recorded_at, "recorded_at"),
      recorded_by: recordedByFromPayload(raw.recorded_by),
      dog_id: assertSafeDocumentId(raw.dog_id, "dog"),
      projected_at: projectedAt,
      title: requiredString(raw.title, "title"),
      subtitle: optionalString(raw.subtitle, "subtitle"),
      schema_version: requiredFiniteNumber(
        raw.schema_version,
        "schema_version",
      ),
      created_at: projectedAt,
      updated_at: projectedAt,
    };
  } catch (error) {
    if (error instanceof DeterministicInvalidPayloadError) return null;
    throw error;
  }
}

export type ProjectionRuntimeResult = {
  operation: ProjectionOperationResult;
  timelineId: string;
  destinationPath: string;
};

export interface HealthTimelineProjector {
  project(source: ValidatedProjectionSource): Promise<ProjectionRuntimeResult>;
}

export interface TransactionalHealthTimelineProjector
  extends HealthTimelineProjector {
  projectInTransaction(
    transaction: Transaction,
    source: ValidatedProjectionSource,
  ): Promise<ProjectionRuntimeResult>;
}

export class FirestoreHealthTimelineRuntime
implements TransactionalHealthTimelineProjector {
  constructor(
    private readonly db: Firestore,
    private readonly clock: RuntimeClock,
    private readonly logger: RuntimeLogger,
  ) {}

  async project(
    source: ValidatedProjectionSource,
  ): Promise<ProjectionRuntimeResult> {
    const result = await this.db.runTransaction(
      (transaction) => this.projectInTransaction(transaction, source),
    );
    this.logCommittedResult(source, result);
    return result;
  }

  async projectInTransaction(
    transaction: Transaction,
    source: ValidatedProjectionSource,
  ): Promise<ProjectionRuntimeResult> {
    const dogId = assertSafeDocumentId(source.dogId, "dog");
    const sourceId = assertSafeDocumentId(source.sourceId, "source");
    const sourceCollection = sourceCollectionPath(source.sourceType, dogId);
    const timelineId = deriveTimelineId({
      sourceCollection,
      sourceId,
    });
    const destinationPath = timelineDocumentPath(dogId, timelineId);
    const destinationRef = this.db.doc(destinationPath);

    const existingSnapshot = await transaction.get(destinationRef);
    const now = this.clock.now();
    if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
      throw new Error("Runtime clock returned an invalid Date.");
    }
    const expected = expectedProjection(
      source,
      timelineId,
      now.toISOString(),
    );

    let operation: ProjectionOperationResult;
    if (!existingSnapshot.exists) {
      transaction.create(
        destinationRef,
        serializeCanonicalTimeline(expected),
      );
      operation = "created";
    } else {
      const existing = existingTimelineToPure(existingSnapshot.data() ?? {});
      if (
        existing !== null &&
        compareProjection(expected, existing) === "equivalent"
      ) {
        operation = "noop";
      } else {
        transaction.set(
          destinationRef,
          serializeCanonicalTimeline(expected),
        );
        operation = "repaired";
      }
    }

    return {operation, timelineId, destinationPath};
  }

  private logCommittedResult(
    source: ValidatedProjectionSource,
    result: ProjectionRuntimeResult,
  ): void {
    const {operation, timelineId} = result;
    const dogId = source.dogId;
    const sourceId = source.sourceId;
    const context = {sourceType: source.sourceType, dogId, sourceId, timelineId};
    if (operation === "repaired") {
      this.logger.warn("HealthTimeline projection repaired", context);
    } else {
      this.logger.info("HealthTimeline projection completed", {
        ...context,
        operation,
      });
    }
  }
}
