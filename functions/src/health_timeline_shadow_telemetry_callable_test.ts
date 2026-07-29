// Copyright 2024 GCM Health. All rights reserved.

import * as assert from "assert";
import {HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {
  HealthTimelineShadowTelemetryCallableDeps,
  runHealthTimelineRecordShadowTelemetry,
} from "./health_timeline_shadow_telemetry_callable";
import {HealthTimelineShadowTelemetryAggregatePlan} from "./health_timeline_shadow_telemetry_backend";

type TestFn = () => void | Promise<void>;
let passed = 0;
let failed = 0;

async function test(name: string, fn: TestFn): Promise<void> {
  try {
    await fn();
    passed++;
    console.log(`✅ ${name}`);
  } catch (error) {
    failed++;
    console.error(`❌ ${name}`);
    console.error(error instanceof Error ? error.message : error);
  }
}

function makeFakeRequest(
  data: unknown,
  auth: {uid: string; token?: Record<string, unknown>} | null = {
    uid: "test-uid-12345",
  },
): CallableRequest<unknown> {
  return {
    data,
    auth: auth ? (auth as any) : undefined,
    rawRequest: {} as any,
    acceptsStreaming: false,
  };
}

async function main(): Promise<void> {
  console.log("=== HEALTH TIMELINE SHADOW TELEMETRY CALLABLE UNIT TESTS ===\n");

  const serverNow = new Date("2026-07-29T15:00:00Z");

  const validComparisonInput = {
    schema_version: 1,
    outcome_type: "comparison",
    primary_count_bucket: "11_25",
    shadow_count_bucket: "11_25",
    matched_count_bucket: "11_25",
    missing_count_bucket: "0",
    extra_count_bucket: "1",
    uncorrelated_primary_count_bucket: "2_5",
    uncorrelated_shadow_count_bucket: "6_10",
    ambiguous_primary_count_bucket: "6_10",
    ambiguous_shadow_count_bucket: "26_plus",
    ordering_mismatch: false,
    latency_bucket: "250_499",
  };

  const validSkippedInput = {
    schema_version: 1,
    outcome_type: "skipped",
    skip_kind: "unsupported_case_id",
  };

  const validFailureInput = {
    schema_version: 1,
    outcome_type: "failure",
    failure_kind: "shadow_timeout",
    latency_bucket: "gte_5000",
  };

  // ── 1. Autenticação ───────────────────────────────────────────────────────
  await test("C1: requisição sem auth lança unauthenticated e não invoca adapter", async () => {
    let adapterCalled = false;
    const req = makeFakeRequest(validSkippedInput, null);
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        adapterCalled = true;
      },
      now: () => serverNow,
    };

    await assert.rejects(
      () => runHealthTimelineRecordShadowTelemetry(req, deps),
      (err: HttpsError) =>
        err instanceof HttpsError && err.code === "unauthenticated",
    );
    assert.strictEqual(adapterCalled, false);
  });

  // ── 2. Fluxos Válidos e Resposta ─────────────────────────────────────────
  await test("C2: chamada comparison válida retorna {accepted: true} e chama adapter 1 vez", async () => {
    let recordCount = 0;
    let recordedPlan: HealthTimelineShadowTelemetryAggregatePlan | null = null;
    const req = makeFakeRequest(validComparisonInput);

    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async (plan) => {
        recordCount++;
        recordedPlan = plan;
      },
      now: () => serverNow,
    };

    const res = await runHealthTimelineRecordShadowTelemetry(req, deps);
    assert.deepStrictEqual(res, {accepted: true});
    assert.strictEqual(recordCount, 1);
    assert.ok(recordedPlan !== null);
    assert.strictEqual(
      (recordedPlan as any).utcDay,
      "2026-07-29",
    );
  });

  await test("C3: chamada skipped válida chama adapter 1 vez", async () => {
    let recordCount = 0;
    const req = makeFakeRequest(validSkippedInput);
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        recordCount++;
      },
      now: () => serverNow,
    };

    const res = await runHealthTimelineRecordShadowTelemetry(req, deps);
    assert.deepStrictEqual(res, {accepted: true});
    assert.strictEqual(recordCount, 1);
  });

  await test("C4: chamada failure válida chama adapter 1 vez", async () => {
    let recordCount = 0;
    const req = makeFakeRequest(validFailureInput);
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        recordCount++;
      },
      now: () => serverNow,
    };

    const res = await runHealthTimelineRecordShadowTelemetry(req, deps);
    assert.deepStrictEqual(res, {accepted: true});
    assert.strictEqual(recordCount, 1);
  });

  // ── 3. Relógio Injetado e Não-Retenção de Auth ────────────────────────────
  await test("C5: relógio injetado determina utcDay e plano não retém UID ou auth token", async () => {
    let recordedPlan: HealthTimelineShadowTelemetryAggregatePlan | null = null;
    const customNow = new Date("2026-12-31T23:59:59.999Z");
    const secretUid = "SECRET_USER_UID_99999";
    const req = makeFakeRequest(validSkippedInput, {
      uid: secretUid,
      token: {email: "user@test.com"},
    });

    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async (plan) => {
        recordedPlan = plan;
      },
      now: () => customNow,
    };

    await runHealthTimelineRecordShadowTelemetry(req, deps);
    assert.ok(recordedPlan !== null);
    const plan =
      recordedPlan as unknown as HealthTimelineShadowTelemetryAggregatePlan;
    assert.strictEqual(plan.utcDay, "2026-12-31");

    const planKeys = Object.keys(plan);
    assert.strictEqual(planKeys.includes("uid"), false);
    assert.strictEqual(planKeys.includes("auth"), false);
    assert.strictEqual(planKeys.includes("token"), false);
    assert.strictEqual(JSON.stringify(plan).includes(secretUid), false);
  });

  // ── 4. Erros de Validação e Mapeamento Seguros ────────────────────────────
  await test("C6: schema versão inválido lança invalid-argument", async () => {
    let adapterCalled = false;
    const req = makeFakeRequest({
      ...validSkippedInput,
      schema_version: 2,
    });
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        adapterCalled = true;
      },
      now: () => serverNow,
    };

    await assert.rejects(
      () => runHealthTimelineRecordShadowTelemetry(req, deps),
      (err: HttpsError) =>
        err instanceof HttpsError &&
        err.code === "invalid-argument" &&
        (err.details as any)?.code === "unsupported_schema",
    );
    assert.strictEqual(adapterCalled, false);
  });

  await test("C7: outcome inválido lança invalid-argument", async () => {
    let adapterCalled = false;
    const req = makeFakeRequest({
      ...validSkippedInput,
      outcome_type: "unknown_outcome",
    });
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        adapterCalled = true;
      },
      now: () => serverNow,
    };

    await assert.rejects(
      () => runHealthTimelineRecordShadowTelemetry(req, deps),
      (err: HttpsError) =>
        err instanceof HttpsError &&
        err.code === "invalid-argument" &&
        (err.details as any)?.code === "invalid_outcome_type",
    );
    assert.strictEqual(adapterCalled, false);
  });

  await test("C8: chave extra desconhecida ou chave server-controlled lança invalid-argument sem ecoar canary", async () => {
    const canaryKey = "SECRET_CANARY_KEY_777";
    const canaryVal = "SECRET_CANARY_VAL_777";
    const serverControlledKeys = [
      "utc_day",
      "bucket_id",
      "document_path",
      "count",
      "first_seen_at",
      "last_seen_at",
      "aggregate_schema_version",
      canaryKey,
    ];

    for (const key of serverControlledKeys) {
      let adapterCalled = false;
      const req = makeFakeRequest({
        ...validSkippedInput,
        [key]: canaryVal,
      });
      const deps: HealthTimelineShadowTelemetryCallableDeps = {
        recordAggregate: async () => {
          adapterCalled = true;
        },
        now: () => serverNow,
      };

      let caught: HttpsError | null = null;
      try {
        await runHealthTimelineRecordShadowTelemetry(req, deps);
      } catch (err) {
        if (err instanceof HttpsError) {
          caught = err;
        }
      }

      assert.ok(caught !== null, `Key ${key} must throw HttpsError`);
      assert.strictEqual(caught!.code, "invalid-argument");
      assert.strictEqual(caught!.message.includes(canaryKey), false);
      assert.strictEqual(caught!.message.includes(canaryVal), false);
      assert.strictEqual(adapterCalled, false);
    }
  });

  // ── 5. Mapeamento de Falhas de Persistência ──────────────────────────────
  await test("C9: falha do adapter é mapeada para HttpsError internal sem ecoar mensagem/stack original", async () => {
    const sensitiveErrorMsg = "INTERNAL_FIRESTORE_SECRET_STACK_TRACE_123";
    const req = makeFakeRequest(validSkippedInput);
    const deps: HealthTimelineShadowTelemetryCallableDeps = {
      recordAggregate: async () => {
        throw new Error(sensitiveErrorMsg);
      },
      now: () => serverNow,
    };

    let caught: HttpsError | null = null;
    try {
      await runHealthTimelineRecordShadowTelemetry(req, deps);
    } catch (err) {
      if (err instanceof HttpsError) {
        caught = err;
      }
    }

    assert.ok(caught !== null);
    assert.strictEqual(caught!.code, "internal");
    assert.strictEqual(
      (caught!.details as any)?.code,
      "shadow_telemetry_persistence_failed",
    );
    assert.strictEqual(caught!.message.includes(sensitiveErrorMsg), false);
  });

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== CALLABLE UNIT TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) {
    console.error("❌ CALLABLE UNIT TESTS FAILED");
    process.exit(1);
  } else {
    console.log(
      `🎯 SHADOW TELEMETRY CALLABLE UNIT TESTS PASSED (${passed}/${passed + failed})`,
    );
  }
}

main().catch((error) => {
  console.error("Unexpected top-level error:", error);
  process.exit(1);
});
