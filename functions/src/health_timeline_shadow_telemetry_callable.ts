// Copyright 2024 GCM Health. All rights reserved.

import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  HealthTimelineShadowTelemetryAggregatePlan,
  HealthTimelineShadowTelemetryValidationError,
  buildHealthTimelineShadowTelemetryAggregatePlan,
} from "./health_timeline_shadow_telemetry_backend";

export interface HealthTimelineShadowTelemetryCallableDeps {
  recordAggregate(
    plan: HealthTimelineShadowTelemetryAggregatePlan,
  ): Promise<void>;

  now(): Date;
}

export async function runHealthTimelineRecordShadowTelemetry(
  request: CallableRequest<unknown>,
  deps: HealthTimelineShadowTelemetryCallableDeps,
): Promise<{accepted: true}> {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication required for telemetry submission",
    );
  }

  let plan: HealthTimelineShadowTelemetryAggregatePlan;
  try {
    const serverNow = deps.now();
    plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      request.data,
      serverNow,
    );
  } catch (err) {
    if (err instanceof HealthTimelineShadowTelemetryValidationError) {
      throw new HttpsError("invalid-argument", "Invalid telemetry payload", {
        code: err.code,
      });
    }
    throw new HttpsError("invalid-argument", "Invalid telemetry payload", {
      code: "invalid_payload",
    });
  }

  try {
    await deps.recordAggregate(plan);
  } catch (err) {
    if (err instanceof HttpsError) {
      throw err;
    }
    throw new HttpsError("internal", "Telemetry persistence failed", {
      code: "shadow_telemetry_persistence_failed",
    });
  }

  return {accepted: true};
}
