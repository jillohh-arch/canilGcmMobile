// Copyright 2024 GCM Health. All rights reserved.

import {createHash} from "crypto";

export type HealthTimelineShadowTelemetryOutcomeType =
  | "comparison"
  | "skipped"
  | "failure";

export type HealthTimelineShadowCountBucket =
  | "0"
  | "1"
  | "2_5"
  | "6_10"
  | "11_25"
  | "26_plus";

export type HealthTimelineShadowLatencyBucket =
  | "unknown"
  | "lt_100"
  | "100_249"
  | "250_499"
  | "500_999"
  | "1000_1999"
  | "2000_4999"
  | "gte_5000";

export type HealthTimelineShadowSkipKind =
  | "not_first_page"
  | "unsupported_types"
  | "unsupported_case_id"
  | "unsupported_professional";

export type HealthTimelineShadowFailureKind =
  | "primary_failure"
  | "shadow_failure"
  | "shadow_timeout"
  | "comparator_failure";

export type HealthTimelineShadowTelemetryValidationErrorCode =
  | "invalid_payload"
  | "unsupported_schema"
  | "missing_field"
  | "unexpected_field"
  | "invalid_outcome_type"
  | "invalid_field_value"
  | "invalid_server_clock";

export class HealthTimelineShadowTelemetryValidationError extends Error {
  readonly code: HealthTimelineShadowTelemetryValidationErrorCode;

  constructor(
    code: HealthTimelineShadowTelemetryValidationErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "HealthTimelineShadowTelemetryValidationError";
    this.code = code;
    Object.setPrototypeOf(
      this,
      HealthTimelineShadowTelemetryValidationError.prototype,
    );
  }
}

export interface HealthTimelineShadowTelemetryComparisonDimensions {
  readonly schemaVersion: 1;
  readonly outcomeType: "comparison";
  readonly primaryCountBucket: HealthTimelineShadowCountBucket;
  readonly shadowCountBucket: HealthTimelineShadowCountBucket;
  readonly matchedCountBucket: HealthTimelineShadowCountBucket;
  readonly missingCountBucket: HealthTimelineShadowCountBucket;
  readonly extraCountBucket: HealthTimelineShadowCountBucket;
  readonly uncorrelatedPrimaryCountBucket: HealthTimelineShadowCountBucket;
  readonly uncorrelatedShadowCountBucket: HealthTimelineShadowCountBucket;
  readonly ambiguousPrimaryCountBucket: HealthTimelineShadowCountBucket;
  readonly ambiguousShadowCountBucket: HealthTimelineShadowCountBucket;
  readonly orderingMismatch: boolean;
  readonly latencyBucket: HealthTimelineShadowLatencyBucket;
}

export interface HealthTimelineShadowTelemetrySkippedDimensions {
  readonly schemaVersion: 1;
  readonly outcomeType: "skipped";
  readonly skipKind: HealthTimelineShadowSkipKind;
}

export interface HealthTimelineShadowTelemetryFailureDimensions {
  readonly schemaVersion: 1;
  readonly outcomeType: "failure";
  readonly failureKind: HealthTimelineShadowFailureKind;
  readonly latencyBucket: HealthTimelineShadowLatencyBucket;
}

export type HealthTimelineShadowTelemetryDimensions =
  | HealthTimelineShadowTelemetryComparisonDimensions
  | HealthTimelineShadowTelemetrySkippedDimensions
  | HealthTimelineShadowTelemetryFailureDimensions;

const VALID_COUNT_BUCKETS: ReadonlySet<string> = new Set([
  "0",
  "1",
  "2_5",
  "6_10",
  "11_25",
  "26_plus",
]);

const VALID_LATENCY_BUCKETS: ReadonlySet<string> = new Set([
  "unknown",
  "lt_100",
  "100_249",
  "250_499",
  "500_999",
  "1000_1999",
  "2000_4999",
  "gte_5000",
]);

const VALID_SKIP_KINDS: ReadonlySet<string> = new Set([
  "not_first_page",
  "unsupported_types",
  "unsupported_case_id",
  "unsupported_professional",
]);

const VALID_FAILURE_KINDS: ReadonlySet<string> = new Set([
  "primary_failure",
  "shadow_failure",
  "shadow_timeout",
  "comparator_failure",
]);

const COMPARISON_ALLOWED_KEYS: ReadonlySet<string> = new Set([
  "schema_version",
  "outcome_type",
  "primary_count_bucket",
  "shadow_count_bucket",
  "matched_count_bucket",
  "missing_count_bucket",
  "extra_count_bucket",
  "uncorrelated_primary_count_bucket",
  "uncorrelated_shadow_count_bucket",
  "ambiguous_primary_count_bucket",
  "ambiguous_shadow_count_bucket",
  "ordering_mismatch",
  "latency_bucket",
]);

const SKIPPED_ALLOWED_KEYS: ReadonlySet<string> = new Set([
  "schema_version",
  "outcome_type",
  "skip_kind",
]);

const FAILURE_ALLOWED_KEYS: ReadonlySet<string> = new Set([
  "schema_version",
  "outcome_type",
  "failure_kind",
  "latency_bucket",
]);

function validateNoExtraKeys(
  actualKeys: string[],
  allowedKeys: ReadonlySet<string>,
): void {
  for (const key of actualKeys) {
    if (!allowedKeys.has(key)) {
      throw new HealthTimelineShadowTelemetryValidationError(
        "unexpected_field",
        "Unexpected key present in payload",
      );
    }
  }
}

function parseCountBucket(
  value: unknown,
  fieldName: string,
): HealthTimelineShadowCountBucket {
  if (typeof value !== "string" || !VALID_COUNT_BUCKETS.has(value)) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_field_value",
      `Invalid count bucket for field: ${fieldName}`,
    );
  }
  return value as HealthTimelineShadowCountBucket;
}

function parseLatencyBucket(
  value: unknown,
  fieldName: string,
): HealthTimelineShadowLatencyBucket {
  if (typeof value !== "string" || !VALID_LATENCY_BUCKETS.has(value)) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_field_value",
      `Invalid latency bucket for field: ${fieldName}`,
    );
  }
  return value as HealthTimelineShadowLatencyBucket;
}

export function parseHealthTimelineShadowTelemetryPayload(
  input: unknown,
): HealthTimelineShadowTelemetryDimensions {
  if (
    input === null ||
    typeof input !== "object" ||
    Array.isArray(input) ||
    Object.getPrototypeOf(input) !== Object.prototype
  ) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_payload",
      "Payload must be a plain non-null object",
    );
  }

  const record = input as Record<string, unknown>;
  const keys = Object.keys(record);

  if (!("schema_version" in record)) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "missing_field",
      "Field schema_version is required",
    );
  }

  const schemaVersion = record.schema_version;
  if (
    typeof schemaVersion !== "number" ||
    !Number.isInteger(schemaVersion) ||
    schemaVersion !== 1
  ) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "unsupported_schema",
      "Field schema_version must be integer 1",
    );
  }

  if (!("outcome_type" in record)) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "missing_field",
      "Field outcome_type is required",
    );
  }

  const outcomeType = record.outcome_type;
  if (
    outcomeType !== "comparison" &&
    outcomeType !== "skipped" &&
    outcomeType !== "failure"
  ) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_outcome_type",
      "Invalid outcome_type value",
    );
  }

  if (outcomeType === "comparison") {
    validateNoExtraKeys(keys, COMPARISON_ALLOWED_KEYS);

    if (keys.length !== COMPARISON_ALLOWED_KEYS.size) {
      throw new HealthTimelineShadowTelemetryValidationError(
        "missing_field",
        "Comparison payload is missing required fields",
      );
    }

    if (typeof record.ordering_mismatch !== "boolean") {
      throw new HealthTimelineShadowTelemetryValidationError(
        "invalid_field_value",
        "Field ordering_mismatch must be boolean",
      );
    }

    const comparisonDimensions: HealthTimelineShadowTelemetryComparisonDimensions =
      {
        schemaVersion: 1,
        outcomeType: "comparison",
        primaryCountBucket: parseCountBucket(
          record.primary_count_bucket,
          "primary_count_bucket",
        ),
        shadowCountBucket: parseCountBucket(
          record.shadow_count_bucket,
          "shadow_count_bucket",
        ),
        matchedCountBucket: parseCountBucket(
          record.matched_count_bucket,
          "matched_count_bucket",
        ),
        missingCountBucket: parseCountBucket(
          record.missing_count_bucket,
          "missing_count_bucket",
        ),
        extraCountBucket: parseCountBucket(
          record.extra_count_bucket,
          "extra_count_bucket",
        ),
        uncorrelatedPrimaryCountBucket: parseCountBucket(
          record.uncorrelated_primary_count_bucket,
          "uncorrelated_primary_count_bucket",
        ),
        uncorrelatedShadowCountBucket: parseCountBucket(
          record.uncorrelated_shadow_count_bucket,
          "uncorrelated_shadow_count_bucket",
        ),
        ambiguousPrimaryCountBucket: parseCountBucket(
          record.ambiguous_primary_count_bucket,
          "ambiguous_primary_count_bucket",
        ),
        ambiguousShadowCountBucket: parseCountBucket(
          record.ambiguous_shadow_count_bucket,
          "ambiguous_shadow_count_bucket",
        ),
        orderingMismatch: record.ordering_mismatch,
        latencyBucket: parseLatencyBucket(
          record.latency_bucket,
          "latency_bucket",
        ),
      };

    return Object.freeze(comparisonDimensions);
  }

  if (outcomeType === "skipped") {
    validateNoExtraKeys(keys, SKIPPED_ALLOWED_KEYS);

    if (keys.length !== SKIPPED_ALLOWED_KEYS.size) {
      throw new HealthTimelineShadowTelemetryValidationError(
        "missing_field",
        "Skipped payload is missing required fields",
      );
    }

    const skipKind = record.skip_kind;
    if (typeof skipKind !== "string" || !VALID_SKIP_KINDS.has(skipKind)) {
      throw new HealthTimelineShadowTelemetryValidationError(
        "invalid_field_value",
        "Field skip_kind has invalid value",
      );
    }

    const skippedDimensions: HealthTimelineShadowTelemetrySkippedDimensions = {
      schemaVersion: 1,
      outcomeType: "skipped",
      skipKind: skipKind as HealthTimelineShadowSkipKind,
    };

    return Object.freeze(skippedDimensions);
  }

  validateNoExtraKeys(keys, FAILURE_ALLOWED_KEYS);

  if (keys.length !== FAILURE_ALLOWED_KEYS.size) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "missing_field",
      "Failure payload is missing required fields",
    );
  }

  const failureKind = record.failure_kind;
  if (
    typeof failureKind !== "string" ||
    !VALID_FAILURE_KINDS.has(failureKind)
  ) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_field_value",
      "Field failure_kind has invalid value",
    );
  }

  const failureDimensions: HealthTimelineShadowTelemetryFailureDimensions = {
    schemaVersion: 1,
    outcomeType: "failure",
    failureKind: failureKind as HealthTimelineShadowFailureKind,
    latencyBucket: parseLatencyBucket(
      record.latency_bucket,
      "latency_bucket",
    ),
  };

  return Object.freeze(failureDimensions);
}

export function healthTimelineShadowTelemetryUtcDay(serverNow: Date): string {
  if (
    !(serverNow instanceof Date) ||
    isNaN(serverNow.getTime())
  ) {
    throw new HealthTimelineShadowTelemetryValidationError(
      "invalid_server_clock",
      "Invalid server clock date",
    );
  }

  const year = serverNow.getUTCFullYear();
  const month = String(serverNow.getUTCMonth() + 1).padStart(2, "0");
  const day = String(serverNow.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function buildHealthTimelineShadowTelemetryCanonicalString(
  dimensions: HealthTimelineShadowTelemetryDimensions,
): string {
  if (dimensions.outcomeType === "comparison") {
    return [
      "v1",
      "comparison",
      `primary=${dimensions.primaryCountBucket}`,
      `shadow=${dimensions.shadowCountBucket}`,
      `matched=${dimensions.matchedCountBucket}`,
      `missing=${dimensions.missingCountBucket}`,
      `extra=${dimensions.extraCountBucket}`,
      `uncor_pri=${dimensions.uncorrelatedPrimaryCountBucket}`,
      `uncor_sha=${dimensions.uncorrelatedShadowCountBucket}`,
      `amb_pri=${dimensions.ambiguousPrimaryCountBucket}`,
      `amb_sha=${dimensions.ambiguousShadowCountBucket}`,
      `ordering=${dimensions.orderingMismatch}`,
      `latency=${dimensions.latencyBucket}`,
    ].join(":");
  }

  if (dimensions.outcomeType === "skipped") {
    return [
      "v1",
      "skipped",
      `skip_kind=${dimensions.skipKind}`,
    ].join(":");
  }

  return [
    "v1",
    "failure",
    `failure_kind=${dimensions.failureKind}`,
    `latency=${dimensions.latencyBucket}`,
  ].join(":");
}

export function buildHealthTimelineShadowTelemetryBucketId(
  dimensions: HealthTimelineShadowTelemetryDimensions,
): string {
  const canonical = buildHealthTimelineShadowTelemetryCanonicalString(dimensions);
  const hash = createHash("sha256").update(canonical, "utf8").digest("hex");
  return `htsb1_${hash}`;
}

export const healthTimelineShadowTelemetryRootCollection = "health_observability";

export function buildHealthTimelineShadowTelemetryDocumentPath(
  utcDay: string,
  bucketId: string,
): string {
  return `${healthTimelineShadowTelemetryRootCollection}/shadow_timeline/days/${utcDay}/buckets/${bucketId}`;
}

export interface HealthTimelineShadowTelemetryAggregatePlan {
  readonly aggregateSchemaVersion: 1;
  readonly utcDay: string;
  readonly bucketId: string;
  readonly documentPath: string;
  readonly dimensions: HealthTimelineShadowTelemetryDimensions;
  readonly countDelta: 1;
}

export function buildHealthTimelineShadowTelemetryAggregatePlan(
  input: unknown,
  serverNow: Date,
): HealthTimelineShadowTelemetryAggregatePlan {
  const dimensions = parseHealthTimelineShadowTelemetryPayload(input);
  const utcDay = healthTimelineShadowTelemetryUtcDay(serverNow);
  const bucketId = buildHealthTimelineShadowTelemetryBucketId(dimensions);
  const documentPath = buildHealthTimelineShadowTelemetryDocumentPath(
    utcDay,
    bucketId,
  );

  const plan: HealthTimelineShadowTelemetryAggregatePlan = {
    aggregateSchemaVersion: 1,
    utcDay,
    bucketId,
    documentPath,
    dimensions,
    countDelta: 1,
  };

  return Object.freeze(plan);
}
