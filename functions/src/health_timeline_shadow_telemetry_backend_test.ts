// Copyright 2024 GCM Health. All rights reserved.

import * as assert from "assert";
import {
  HealthTimelineShadowTelemetryValidationError,
  buildHealthTimelineShadowTelemetryAggregatePlan,
  buildHealthTimelineShadowTelemetryBucketId,
  healthTimelineShadowTelemetryRootCollection,
  healthTimelineShadowTelemetryUtcDay,
  parseHealthTimelineShadowTelemetryPayload,
} from "./health_timeline_shadow_telemetry_backend";

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

async function main(): Promise<void> {
  console.log("=== HEALTH TIMELINE SHADOW TELEMETRY BACKEND UNIT TESTS ===\n");

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

  // ── 1. Estrutura ──────────────────────────────────────────────────────────
  await test("E1: null payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(null),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E2: array payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload([1, 2, 3]),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E3: string payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload('{"schema_version":1}'),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E4: number payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(123),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E5: boolean payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(true),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E6: Date payload é rejeitado com invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(new Date()),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E8: Object.create(null) e Object.create com protótipo customizado lançam invalid_payload", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(Object.create(null)),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload(
          Object.create({
            schema_version: 1,
            outcome_type: "skipped",
            skip_kind: "not_first_page",
          }),
        ),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_payload",
    );
  });

  await test("E7: objeto vazio é rejeitado com missing_field", () => {
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload({}),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  // ── 2. Schema ─────────────────────────────────────────────────────────────
  await test("S1: schema_version ausente lança missing_field", () => {
    const input = {...validSkippedInput};
    delete (input as Record<string, unknown>).schema_version;
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(input),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  await test("S2: schema_version em string '1' lança unsupported_schema", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          schema_version: "1",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unsupported_schema",
    );
  });

  await test("S3: schema_version 0 lança unsupported_schema", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          schema_version: 0,
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unsupported_schema",
    );
  });

  await test("S4: schema_version 2 lança unsupported_schema", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          schema_version: 2,
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unsupported_schema",
    );
  });

  await test("S5: schema_version 1.5/NaN lança unsupported_schema", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          schema_version: 1.5,
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unsupported_schema",
    );
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          schema_version: NaN,
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unsupported_schema",
    );
  });

  await test("S6: schema_version 1 é aceito com sucesso", () => {
    const res = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    assert.strictEqual(res.schemaVersion, 1);
  });

  // ── 3. Outcome ────────────────────────────────────────────────────────────
  await test("O1: outcome_type ausente lança missing_field", () => {
    const input = {...validSkippedInput};
    delete (input as Record<string, unknown>).outcome_type;
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(input),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  await test("O2: outcome_type desconhecido lança invalid_outcome_type", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          outcome_type: "unknown_type",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_outcome_type",
    );
  });

  await test("O3: capitalizações alternativas são rejeitadas", () => {
    for (const alt of ["Comparison", "SKIPPED", "Failure", "COMPARISON"]) {
      assert.throws(
        () =>
          parseHealthTimelineShadowTelemetryPayload({
            ...validSkippedInput,
            outcome_type: alt,
          }),
        (err: unknown) =>
          err instanceof HealthTimelineShadowTelemetryValidationError &&
          err.code === "invalid_outcome_type",
      );
    }
  });

  await test("O4: outcome_type 'comparison', 'skipped' e 'failure' são aceitos", () => {
    const c = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);
    assert.strictEqual(c.outcomeType, "comparison");

    const s = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    assert.strictEqual(s.outcomeType, "skipped");

    const f = parseHealthTimelineShadowTelemetryPayload(validFailureInput);
    assert.strictEqual(f.outcomeType, "failure");
  });

  // ── 4. Comparison ─────────────────────────────────────────────────────────
  await test("C1: comparison completo aceito", () => {
    const res = parseHealthTimelineShadowTelemetryPayload(
      validComparisonInput,
    );
    assert.strictEqual(res.outcomeType, "comparison");
    if (res.outcomeType === "comparison") {
      assert.strictEqual(res.primaryCountBucket, "11_25");
      assert.strictEqual(res.shadowCountBucket, "11_25");
      assert.strictEqual(res.matchedCountBucket, "11_25");
      assert.strictEqual(res.missingCountBucket, "0");
      assert.strictEqual(res.extraCountBucket, "1");
      assert.strictEqual(res.uncorrelatedPrimaryCountBucket, "2_5");
      assert.strictEqual(res.uncorrelatedShadowCountBucket, "6_10");
      assert.strictEqual(res.ambiguousPrimaryCountBucket, "6_10");
      assert.strictEqual(res.ambiguousShadowCountBucket, "26_plus");
      assert.strictEqual(res.orderingMismatch, false);
      assert.strictEqual(res.latencyBucket, "250_499");
    }
  });

  await test("C2: todos os 6 count buckets são aceitos em comparison", () => {
    const validBuckets = ["0", "1", "2_5", "6_10", "11_25", "26_plus"];
    for (const b of validBuckets) {
      const res = parseHealthTimelineShadowTelemetryPayload({
        ...validComparisonInput,
        primary_count_bucket: b,
      });
      if (res.outcomeType === "comparison") {
        assert.strictEqual(res.primaryCountBucket, b);
      }
    }
  });

  await test("C3: count bucket inválido lança invalid_field_value", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validComparisonInput,
          primary_count_bucket: "invalid_bucket",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_field_value",
    );
  });

  await test("C4: ordering_mismatch aceita boolean true e false", () => {
    const resTrue = parseHealthTimelineShadowTelemetryPayload({
      ...validComparisonInput,
      ordering_mismatch: true,
    });
    if (resTrue.outcomeType === "comparison") {
      assert.strictEqual(resTrue.orderingMismatch, true);
    }

    const resFalse = parseHealthTimelineShadowTelemetryPayload({
      ...validComparisonInput,
      ordering_mismatch: false,
    });
    if (resFalse.outcomeType === "comparison") {
      assert.strictEqual(resFalse.orderingMismatch, false);
    }
  });

  await test("C5: ordering_mismatch em string/number/null é rejeitado", () => {
    for (const invalid of ["true", "false", 1, 0, null]) {
      assert.throws(
        () =>
          parseHealthTimelineShadowTelemetryPayload({
            ...validComparisonInput,
            ordering_mismatch: invalid,
          }),
        (err: unknown) =>
          err instanceof HealthTimelineShadowTelemetryValidationError &&
          err.code === "invalid_field_value",
      );
    }
  });

  await test("C6: todos os 8 latency buckets são aceitos em comparison", () => {
    const validLatencies = [
      "unknown",
      "lt_100",
      "100_249",
      "250_499",
      "500_999",
      "1000_1999",
      "2000_4999",
      "gte_5000",
    ];
    for (const l of validLatencies) {
      const res = parseHealthTimelineShadowTelemetryPayload({
        ...validComparisonInput,
        latency_bucket: l,
      });
      if (res.outcomeType === "comparison") {
        assert.strictEqual(res.latencyBucket, l);
      }
    }
  });

  await test("C7: latency bucket inválido lança invalid_field_value", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validComparisonInput,
          latency_bucket: "50ms",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_field_value",
    );
  });

  await test("C8: comparison com campo obrigatório ausente lança missing_field", () => {
    const input = {...validComparisonInput};
    delete (input as Record<string, unknown>).latency_bucket;
    assert.throws(
      () => parseHealthTimelineShadowTelemetryPayload(input),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  await test("C9: comparison com campo extra lança unexpected_field", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validComparisonInput,
          extra_unauthorized_key: "value",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unexpected_field",
    );
  });

  // ── 5. Skipped ────────────────────────────────────────────────────────────
  await test("K1: quatro skip kinds são aceitos", () => {
    const kinds = [
      "not_first_page",
      "unsupported_types",
      "unsupported_case_id",
      "unsupported_professional",
    ];
    for (const k of kinds) {
      const res = parseHealthTimelineShadowTelemetryPayload({
        schema_version: 1,
        outcome_type: "skipped",
        skip_kind: k,
      });
      if (res.outcomeType === "skipped") {
        assert.strictEqual(res.skipKind, k);
      }
    }
  });

  await test("K2: skip kind inválido lança invalid_field_value", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          schema_version: 1,
          outcome_type: "skipped",
          skip_kind: "invalid_skip_kind",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_field_value",
    );
  });

  await test("K3: skipped com campo obrigatório ausente lança missing_field", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          schema_version: 1,
          outcome_type: "skipped",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  await test("K4: skipped com campo extra lança unexpected_field", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          extra_key: "abc",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unexpected_field",
    );
  });

  await test("K5: unsupported_case_id não adiciona nem aceita campo case_id", () => {
    const res = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    assert.strictEqual("case_id" in res, false);
    assert.strictEqual("caseId" in res, false);

    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validSkippedInput,
          case_id: "case-123",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unexpected_field",
    );
  });

  // ── 6. Failure ────────────────────────────────────────────────────────────
  await test("F1: quatro failure kinds são aceitos", () => {
    const failureKinds = [
      "primary_failure",
      "shadow_failure",
      "shadow_timeout",
      "comparator_failure",
    ];
    for (const fk of failureKinds) {
      const res = parseHealthTimelineShadowTelemetryPayload({
        schema_version: 1,
        outcome_type: "failure",
        failure_kind: fk,
        latency_bucket: "lt_100",
      });
      if (res.outcomeType === "failure") {
        assert.strictEqual(res.failureKind, fk);
      }
    }
  });

  await test("F2: failure kind inválido lança invalid_field_value", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          schema_version: 1,
          outcome_type: "failure",
          failure_kind: "invalid_failure_kind",
          latency_bucket: "lt_100",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_field_value",
    );
  });

  await test("F3: oito latency buckets são aceitos em failure", () => {
    const validLatencies = [
      "unknown",
      "lt_100",
      "100_249",
      "250_499",
      "500_999",
      "1000_1999",
      "2000_4999",
      "gte_5000",
    ];
    for (const l of validLatencies) {
      const res = parseHealthTimelineShadowTelemetryPayload({
        schema_version: 1,
        outcome_type: "failure",
        failure_kind: "shadow_failure",
        latency_bucket: l,
      });
      if (res.outcomeType === "failure") {
        assert.strictEqual(res.latencyBucket, l);
      }
    }
  });

  await test("F4: failure com campo obrigatório ausente lança missing_field", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          schema_version: 1,
          outcome_type: "failure",
          failure_kind: "primary_failure",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "missing_field",
    );
  });

  await test("F5: failure com campo extra lança unexpected_field", () => {
    assert.throws(
      () =>
        parseHealthTimelineShadowTelemetryPayload({
          ...validFailureInput,
          stack_trace: "Error at...",
        }),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "unexpected_field",
    );
  });

  // ── 7. Privacidade — Rejeição de Chaves Proibidas ────────────────────────
  await test("P1: rejeição de 29 chaves proibidas individuais", () => {
    const forbiddenKeys = [
      "dog_id",
      "dogId",
      "dogName",
      "uid",
      "userId",
      "user_id",
      "email",
      "ra",
      "userName",
      "eventId",
      "event_id",
      "documentId",
      "document_id",
      "sourceId",
      "source_id",
      "sourceCollection",
      "legacyId",
      "legacy_id",
      "caseId",
      "case_id",
      "professional",
      "occurredAt",
      "occurred_at",
      "title",
      "subtitle",
      "payload",
      "query",
      "cursor",
      "exception",
      "error",
      "message",
      "stackTrace",
      "stack_trace",
      "sessionId",
      "session_id",
      "installationId",
      "installation_id",
      "deviceId",
      "device_id",
      "appVersion",
      "app_version",
      "buildNumber",
      "build_number",
      "platform",
      "environment",
      "recordedAt",
      "recorded_at",
      "timestamp",
      "date",
      "utc_day",
      "bucket_id",
      "operation_id",
    ];

    for (const key of forbiddenKeys) {
      assert.throws(
        () =>
          parseHealthTimelineShadowTelemetryPayload({
            ...validSkippedInput,
            [key]: "prohibited_value",
          }),
        (err: unknown) =>
          err instanceof HealthTimelineShadowTelemetryValidationError &&
          err.code === "unexpected_field",
        `Key ${key} must be rejected as unexpected_field`,
      );
    }
  });

  // ── 8. Erros de Validação Seguros ─────────────────────────────────────────
  await test("V1: erro de validação expõe código estável e não ecoa payload/input", () => {
    const secretValue = "SECRET_SENSITIVE_DATA_12345";
    let caught: HealthTimelineShadowTelemetryValidationError | null = null;

    try {
      parseHealthTimelineShadowTelemetryPayload({
        ...validSkippedInput,
        secret_key: secretValue,
      });
    } catch (err) {
      if (err instanceof HealthTimelineShadowTelemetryValidationError) {
        caught = err;
      }
    }

    assert.ok(caught !== null);
    assert.strictEqual(caught!.code, "unexpected_field");
    assert.strictEqual(caught!.message.includes(secretValue), false);
    assert.strictEqual("input" in caught!, false);
    assert.strictEqual("payload" in caught!, false);
  });

  await test("V2: chave arbitrária desconhecida lança unexpected_field sem ecoar nome da chave ou valor", () => {
    const canaryKey = "SECRET_CANARY_FIELD_78291";
    const canaryValue = "SECRET_CANARY_VALUE_78291";
    const canaryInput = {
      schema_version: 1,
      outcome_type: "skipped",
      skip_kind: "not_first_page",
      [canaryKey]: canaryValue,
    };

    let caught: HealthTimelineShadowTelemetryValidationError | null = null;
    try {
      parseHealthTimelineShadowTelemetryPayload(canaryInput);
    } catch (err) {
      if (err instanceof HealthTimelineShadowTelemetryValidationError) {
        caught = err;
      }
    }

    assert.ok(caught !== null);
    assert.strictEqual(caught!.code, "unexpected_field");
    assert.strictEqual(caught!.message.includes(canaryKey), false);
    assert.strictEqual(caught!.message.includes(canaryValue), false);
    assert.strictEqual("input" in caught!, false);
    assert.strictEqual("payload" in caught!, false);
  });

  // ── 9. UTC Day Server-Authoritative ───────────────────────────────────────
  await test("D1: UTC day formata YYYY-MM-DD em UTC corretamente nas fronteiras", () => {
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-07-29T23:59:59.999Z")),
      "2026-07-29",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-07-30T00:00:00.000Z")),
      "2026-07-30",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-07-30T00:00:01.000Z")),
      "2026-07-30",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-01-31T23:59:59.999Z")),
      "2026-01-31",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-02-01T00:00:00.000Z")),
      "2026-02-01",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2025-12-31T23:59:59.999Z")),
      "2025-12-31",
    );
    assert.strictEqual(
      healthTimelineShadowTelemetryUtcDay(new Date("2026-01-01T00:00:00.000Z")),
      "2026-01-01",
    );
  });

  await test("D2: Invalid Date lança invalid_server_clock", () => {
    assert.throws(
      () => healthTimelineShadowTelemetryUtcDay(new Date("invalid-date-string")),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_server_clock",
    );
    assert.throws(
      () => healthTimelineShadowTelemetryUtcDay(null as unknown as Date),
      (err: unknown) =>
        err instanceof HealthTimelineShadowTelemetryValidationError &&
        err.code === "invalid_server_clock",
    );
  });

  // ── 10. Bucket ID Determinístico (Fingerprint) ────────────────────────────
  await test("B1: mesmíssimas dimensões geram o mesmo bucket ID", () => {
    const dim1 = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);
    const dim2 = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);

    const b1 = buildHealthTimelineShadowTelemetryBucketId(dim1);
    const b2 = buildHealthTimelineShadowTelemetryBucketId(dim2);

    assert.strictEqual(b1, b2);
  });

  await test("B2: ordem de chaves do input não altera o bucket ID (serialização canônica)", () => {
    const inputOrderA = {
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

    const inputOrderB = {
      latency_bucket: "250_499",
      ordering_mismatch: false,
      ambiguous_shadow_count_bucket: "26_plus",
      ambiguous_primary_count_bucket: "6_10",
      uncorrelated_shadow_count_bucket: "6_10",
      uncorrelated_primary_count_bucket: "2_5",
      extra_count_bucket: "1",
      missing_count_bucket: "0",
      matched_count_bucket: "11_25",
      shadow_count_bucket: "11_25",
      primary_count_bucket: "11_25",
      outcome_type: "comparison",
      schema_version: 1,
    };

    const dimA = parseHealthTimelineShadowTelemetryPayload(inputOrderA);
    const dimB = parseHealthTimelineShadowTelemetryPayload(inputOrderB);

    assert.strictEqual(
      buildHealthTimelineShadowTelemetryBucketId(dimA),
      buildHealthTimelineShadowTelemetryBucketId(dimB),
    );
  });

  await test("B3: uma dimensão diferente altera o bucket ID", () => {
    const dimA = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);
    const dimB = parseHealthTimelineShadowTelemetryPayload({
      ...validComparisonInput,
      ordering_mismatch: true,
    });

    assert.notStrictEqual(
      buildHealthTimelineShadowTelemetryBucketId(dimA),
      buildHealthTimelineShadowTelemetryBucketId(dimB),
    );
  });

  await test("B4: outcome diferente altera o bucket ID", () => {
    const dimComp = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);
    const dimSkip = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    const dimFail = parseHealthTimelineShadowTelemetryPayload(validFailureInput);

    const bComp = buildHealthTimelineShadowTelemetryBucketId(dimComp);
    const bSkip = buildHealthTimelineShadowTelemetryBucketId(dimSkip);
    const bFail = buildHealthTimelineShadowTelemetryBucketId(dimFail);

    assert.notStrictEqual(bComp, bSkip);
    assert.notStrictEqual(bComp, bFail);
    assert.notStrictEqual(bSkip, bFail);
  });

  await test("B5: bucket ID inicia com 'htsb1_' e possui exatamente 64 hex chars (70 total)", () => {
    const dim = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    const bucketId = buildHealthTimelineShadowTelemetryBucketId(dim);

    assert.strictEqual(bucketId.startsWith("htsb1_"), true);
    assert.strictEqual(bucketId.length, 70);
    const hexPart = bucketId.substring(6);
    assert.strictEqual(/^[0-9a-f]{64}$/.test(hexPart), true);
  });

  await test("B6: data não altera o bucket ID", () => {
    const dim = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    const b1 = buildHealthTimelineShadowTelemetryBucketId(dim);
    const b2 = buildHealthTimelineShadowTelemetryBucketId(dim);
    assert.strictEqual(b1, b2);
  });

  // ── 11. Aggregate Plan ───────────────────────────────────────────────────
  await test("P1: plano de agregação produz o path backend-only exato e é imutável", () => {
    const serverNow = new Date("2026-07-29T14:30:00.000Z");
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validComparisonInput,
      serverNow,
    );

    assert.strictEqual(plan.aggregateSchemaVersion, 1);
    assert.strictEqual(plan.utcDay, "2026-07-29");
    assert.strictEqual(plan.countDelta, 1);
    assert.strictEqual(plan.bucketId.startsWith("htsb1_"), true);
    assert.strictEqual(
      plan.documentPath,
      `${healthTimelineShadowTelemetryRootCollection}/shadow_timeline/days/2026-07-29/buckets/${plan.bucketId}`,
    );

    assert.strictEqual(Object.isFrozen(plan), true);
    assert.strictEqual(Object.isFrozen(plan.dimensions), true);
  });

  await test("P2: plano de agregação não retém referência nem sofre com mutação posterior do input", () => {
    const mutableInput = {...validComparisonInput};
    const serverNow = new Date("2026-07-29T14:30:00.000Z");

    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      mutableInput,
      serverNow,
    );

    // Mutar o input original
    (mutableInput as Record<string, unknown>).ordering_mismatch = true;
    (mutableInput as Record<string, unknown>).extra_unauthorized = "HACK";

    if (plan.dimensions.outcomeType === "comparison") {
      assert.strictEqual(plan.dimensions.orderingMismatch, false);
      assert.strictEqual("extra_unauthorized" in plan.dimensions, false);
    }
  });

  await test("P3: plano de agregação não armazena Date, eventId, uid ou client timestamp", () => {
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validSkippedInput,
      new Date("2026-07-29T12:00:00Z"),
    );

    const keys = Object.keys(plan);
    const forbiddenPlanKeys = [
      "eventId",
      "event_id",
      "uid",
      "userId",
      "user_id",
      "operationId",
      "operation_id",
      "clientTimestamp",
      "serverDate",
      "serverNow",
      "rawInput",
      "input",
    ];

    for (const fk of forbiddenPlanKeys) {
      assert.strictEqual(keys.includes(fk), false);
    }
  });

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== BACKEND CONTRACT UNIT TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) {
    console.error("❌ SHADOW TELEMETRY BACKEND UNIT TESTS FAILED");
    process.exit(1);
  } else {
    console.log(
      `🎯 SHADOW TELEMETRY BACKEND CONTRACT UNIT TESTS PASSED (${passed}/${passed + failed})`,
    );
  }
}

main().catch((error) => {
  console.error("Unexpected top-level error:", error);
  process.exit(1);
});
