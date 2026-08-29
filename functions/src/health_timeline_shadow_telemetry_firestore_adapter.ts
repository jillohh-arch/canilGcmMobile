// Copyright 2024 GCM Health. All rights reserved.

import * as admin from "firebase-admin";
import {
  HealthTimelineShadowTelemetryAggregatePlan,
  HealthTimelineShadowTelemetryDimensions,
  buildHealthTimelineShadowTelemetryCanonicalString,
  parseHealthTimelineShadowTelemetryPayload,
} from "./health_timeline_shadow_telemetry_backend";

export interface HealthTimelineShadowTelemetryAggregateWriter {
  recordAggregate(
    plan: HealthTimelineShadowTelemetryAggregatePlan,
  ): Promise<void>;
}

export function dimensionsToFirestoreJson(
  dimensions: HealthTimelineShadowTelemetryDimensions,
): Record<string, unknown> {
  if (dimensions.outcomeType === "comparison") {
    return {
      schema_version: 1,
      outcome_type: "comparison",
      primary_count_bucket: dimensions.primaryCountBucket,
      shadow_count_bucket: dimensions.shadowCountBucket,
      matched_count_bucket: dimensions.matchedCountBucket,
      missing_count_bucket: dimensions.missingCountBucket,
      extra_count_bucket: dimensions.extraCountBucket,
      uncorrelated_primary_count_bucket:
        dimensions.uncorrelatedPrimaryCountBucket,
      uncorrelated_shadow_count_bucket:
        dimensions.uncorrelatedShadowCountBucket,
      ambiguous_primary_count_bucket:
        dimensions.ambiguousPrimaryCountBucket,
      ambiguous_shadow_count_bucket:
        dimensions.ambiguousShadowCountBucket,
      ordering_mismatch: dimensions.orderingMismatch,
      latency_bucket: dimensions.latencyBucket,
    };
  }

  if (dimensions.outcomeType === "skipped") {
    return {
      schema_version: 1,
      outcome_type: "skipped",
      skip_kind: dimensions.skipKind,
    };
  }

  return {
    schema_version: 1,
    outcome_type: "failure",
    failure_kind: dimensions.failureKind,
    latency_bucket: dimensions.latencyBucket,
  };
}

export class FirestoreHealthTimelineShadowTelemetryAggregateWriter
  implements HealthTimelineShadowTelemetryAggregateWriter
{
  constructor(private readonly db: admin.firestore.Firestore) {}

  async recordAggregate(
    plan: HealthTimelineShadowTelemetryAggregatePlan,
  ): Promise<void> {
    const docRef = this.db.doc(plan.documentPath);

    await this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, {
          aggregate_schema_version: 1,
          utc_day: plan.utcDay,
          bucket_id: plan.bucketId,
          dimensions: dimensionsToFirestoreJson(plan.dimensions),
          count: 1,
          first_seen_at: admin.firestore.FieldValue.serverTimestamp(),
          last_seen_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const data = snapshot.data() || {};

      if (
        data.aggregate_schema_version !== 1 ||
        data.utc_day !== plan.utcDay ||
        data.bucket_id !== plan.bucketId
      ) {
        throw new Error(
          "shadow_telemetry_aggregate_integrity: Header metadata mismatch",
        );
      }

      const currentCount = data.count;
      if (
        typeof currentCount !== "number" ||
        !Number.isInteger(currentCount) ||
        currentCount < 0 ||
        currentCount >= Number.MAX_SAFE_INTEGER
      ) {
        throw new Error(
          "shadow_telemetry_aggregate_integrity: Invalid count field bounds",
        );
      }

      try {
        const existingDimensions = parseHealthTimelineShadowTelemetryPayload(
          data.dimensions,
        );
        const existingCanonical =
          buildHealthTimelineShadowTelemetryCanonicalString(existingDimensions);
        const planCanonical =
          buildHealthTimelineShadowTelemetryCanonicalString(plan.dimensions);

        if (existingCanonical !== planCanonical) {
          throw new Error("Canonical dimensions mismatch");
        }
      } catch (err) {
        throw new Error(
          `shadow_telemetry_aggregate_integrity: Dimension integrity failure - ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }

      transaction.update(docRef, {
        count: currentCount + 1,
        last_seen_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
}
