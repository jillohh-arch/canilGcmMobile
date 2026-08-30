// Copyright 2024 GCM Health. All rights reserved.

import * as assert from "assert";
import {
  FirestoreHealthTimelineShadowTelemetryAggregateWriter,
  dimensionsToFirestoreJson,
} from "./health_timeline_shadow_telemetry_firestore_adapter";
import {
  buildHealthTimelineShadowTelemetryAggregatePlan,
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

class FakeDocumentSnapshot {
  constructor(
    public readonly exists: boolean,
    private readonly docData?: Record<string, unknown>,
  ) {}

  data(): Record<string, unknown> | undefined {
    return this.docData ? JSON.parse(JSON.stringify(this.docData)) : undefined;
  }
}

class FakeTransaction {
  public getCount = 0;
  public setCount = 0;
  public updateCount = 0;
  public setData: {docPath: string; data: Record<string, unknown>} | null = null;
  public updateData: {docPath: string; data: Record<string, unknown>} | null =
    null;

  constructor(private readonly store: Map<string, Record<string, unknown>>) {}

  async get(docRef: FakeDocumentReference): Promise<FakeDocumentSnapshot> {
    this.getCount++;
    const docData = this.store.get(docRef.path);
    if (!docData) {
      return new FakeDocumentSnapshot(false);
    }
    return new FakeDocumentSnapshot(true, docData);
  }

  set(docRef: FakeDocumentReference, data: Record<string, unknown>): void {
    this.setCount++;
    this.setData = {docPath: docRef.path, data};
    this.store.set(docRef.path, JSON.parse(JSON.stringify(data)));
  }

  update(docRef: FakeDocumentReference, data: Record<string, unknown>): void {
    this.updateCount++;
    this.updateData = {docPath: docRef.path, data};
    const existing = this.store.get(docRef.path) || {};
    const updated = {...existing, ...JSON.parse(JSON.stringify(data))};
    this.store.set(docRef.path, updated);
  }
}

class FakeDocumentReference {
  constructor(
    public readonly path: string,
    public readonly store: Map<string, Record<string, unknown>>,
  ) {}
}

class FakeFirestore {
  public store = new Map<string, Record<string, unknown>>();
  public transactionCount = 0;

  doc(path: string): FakeDocumentReference {
    return new FakeDocumentReference(path, this.store);
  }

  async runTransaction<T>(
    updateFunction: (transaction: FakeTransaction) => Promise<T>,
  ): Promise<T> {
    this.transactionCount++;
    const txn = new FakeTransaction(this.store);
    return updateFunction(txn);
  }
}

async function main(): Promise<void> {
  console.log("=== HEALTH TIMELINE SHADOW TELEMETRY FIRESTORE ADAPTER UNIT TESTS ===\n");

  const serverNow = new Date("2026-07-29T12:00:00Z");

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

  // ── 1. Conversão de Dimensões ─────────────────────────────────────────────
  await test("A1: conversão de dimensões comparison produz JsonMap sanitizado exato", () => {
    const dim = parseHealthTimelineShadowTelemetryPayload(validComparisonInput);
    const json = dimensionsToFirestoreJson(dim);
    assert.strictEqual(Object.keys(json).length, 13);
    assert.strictEqual(json.schema_version, 1);
    assert.strictEqual(json.outcome_type, "comparison");
    assert.strictEqual(json.ordering_mismatch, false);
    assert.strictEqual(json.latency_bucket, "250_499");
  });

  await test("A2: conversão de dimensões skipped produz JsonMap sanitizado exato", () => {
    const dim = parseHealthTimelineShadowTelemetryPayload(validSkippedInput);
    const json = dimensionsToFirestoreJson(dim);
    assert.strictEqual(Object.keys(json).length, 3);
    assert.strictEqual(json.schema_version, 1);
    assert.strictEqual(json.outcome_type, "skipped");
    assert.strictEqual(json.skip_kind, "unsupported_case_id");
  });

  await test("A3: conversão de dimensões failure produz JsonMap sanitizado exato", () => {
    const dim = parseHealthTimelineShadowTelemetryPayload(validFailureInput);
    const json = dimensionsToFirestoreJson(dim);
    assert.strictEqual(Object.keys(json).length, 4);
    assert.strictEqual(json.schema_version, 1);
    assert.strictEqual(json.outcome_type, "failure");
    assert.strictEqual(json.failure_kind, "shadow_timeout");
    assert.strictEqual(json.latency_bucket, "gte_5000");
  });

  // ── 2. Gravação de Documento Ausente (Create) ──────────────────────────────
  await test("A4: documento ausente gera set com count=1 no path exato e com timestamps", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validComparisonInput,
      serverNow,
    );

    await writer.recordAggregate(plan);

    assert.strictEqual(fakeDb.transactionCount, 1);
    const savedData = fakeDb.store.get(plan.documentPath);
    assert.ok(savedData !== undefined);
    assert.strictEqual(savedData!.aggregate_schema_version, 1);
    assert.strictEqual(savedData!.utc_day, "2026-07-29");
    assert.strictEqual(savedData!.bucket_id, plan.bucketId);
    assert.strictEqual(savedData!.count, 1);
    assert.ok(savedData!.first_seen_at !== undefined);
    assert.ok(savedData!.last_seen_at !== undefined);

    // Confirmar apenas campos permitidos no documento criado
    const allowedDocKeys = [
      "aggregate_schema_version",
      "utc_day",
      "bucket_id",
      "dimensions",
      "count",
      "first_seen_at",
      "last_seen_at",
    ];
    assert.deepStrictEqual(Object.keys(savedData!).sort(), allowedDocKeys.sort());
  });

  // ── 3. Gravação de Documento Existente (Update) ───────────────────────────
  await test("A5: documento existente incrementa count (+1) e preserva first_seen_at e dimensões", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validComparisonInput,
      serverNow,
    );

    // Gravação 1 (create)
    await writer.recordAggregate(plan);
    const initialData = fakeDb.store.get(plan.documentPath)!;
    assert.strictEqual(initialData.count, 1);

    // Simular que first_seen_at foi gravado com um timestamp específico
    initialData.first_seen_at = "SENTINEL_FIRST_SEEN";
    fakeDb.store.set(plan.documentPath, initialData);

    // Gravação 2 (update)
    await writer.recordAggregate(plan);
    const updatedData = fakeDb.store.get(plan.documentPath)!;

    assert.strictEqual(updatedData.count, 2);
    assert.strictEqual(updatedData.first_seen_at, "SENTINEL_FIRST_SEEN");
    assert.strictEqual(updatedData.utc_day, "2026-07-29");
    assert.strictEqual(updatedData.bucket_id, plan.bucketId);
    assert.strictEqual(updatedData.aggregate_schema_version, 1);
  });

  // ── 4. Validações de Integridade (Fail-Closed) ────────────────────────────
  await test("A6: schema inconsistente no documento lança erro de integridade e não altera documento", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validSkippedInput,
      serverNow,
    );

    await writer.recordAggregate(plan);
    const initialData = fakeDb.store.get(plan.documentPath)!;
    initialData.aggregate_schema_version = 2; // Schema inválido
    fakeDb.store.set(plan.documentPath, initialData);

    await assert.rejects(
      () => writer.recordAggregate(plan),
      (err: Error) => err.message.includes("shadow_telemetry_aggregate_integrity"),
    );

    assert.strictEqual(fakeDb.store.get(plan.documentPath)!.count, 1);
  });

  await test("A7: utc_day inconsistente no documento lança erro de integridade", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validSkippedInput,
      serverNow,
    );

    await writer.recordAggregate(plan);
    const initialData = fakeDb.store.get(plan.documentPath)!;
    initialData.utc_day = "2026-07-28"; // Dia incompatível
    fakeDb.store.set(plan.documentPath, initialData);

    await assert.rejects(
      () => writer.recordAggregate(plan),
      (err: Error) => err.message.includes("shadow_telemetry_aggregate_integrity"),
    );
  });

  await test("A8: bucket_id inconsistente no documento lança erro de integridade", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validSkippedInput,
      serverNow,
    );

    await writer.recordAggregate(plan);
    const initialData = fakeDb.store.get(plan.documentPath)!;
    initialData.bucket_id = "htsb1_corrupted_id";
    fakeDb.store.set(plan.documentPath, initialData);

    await assert.rejects(
      () => writer.recordAggregate(plan),
      (err: Error) => err.message.includes("shadow_telemetry_aggregate_integrity"),
    );
  });

  await test("A9: dimensões corrompidas ou incompatíveis no documento lançam erro de integridade", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validSkippedInput,
      serverNow,
    );

    await writer.recordAggregate(plan);
    const initialData = fakeDb.store.get(plan.documentPath)!;
    // Alterar skip_kind armazenado no documento
    (initialData.dimensions as Record<string, unknown>).skip_kind =
      "not_first_page";
    fakeDb.store.set(plan.documentPath, initialData);

    await assert.rejects(
      () => writer.recordAggregate(plan),
      (err: Error) => err.message.includes("shadow_telemetry_aggregate_integrity"),
    );
  });

  // ── 5. Validação dos Limites do Campo Count ───────────────────────────────
  await test("A10: count ausente, string, negativo, fracionário, Infinity ou MAX_SAFE_INTEGER lançam erro de integridade", async () => {
    const invalidCounts = [
      undefined,
      "1",
      -1,
      1.5,
      Infinity,
      Number.MAX_SAFE_INTEGER,
    ];

    for (const badCount of invalidCounts) {
      const fakeDb = new FakeFirestore();
      const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
        fakeDb as any,
      );
      const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
        validSkippedInput,
        serverNow,
      );

      await writer.recordAggregate(plan);
      const initialData = fakeDb.store.get(plan.documentPath)!;
      initialData.count = badCount;
      fakeDb.store.set(plan.documentPath, initialData);

      await assert.rejects(
        () => writer.recordAggregate(plan),
        (err: Error) =>
          err.message.includes("shadow_telemetry_aggregate_integrity"),
        `Count bad value ${badCount} must be rejected`,
      );
    }
  });

  // ── 6. Invariantes de Isolamento e Zero Documentos Individuais ────────────
  await test("A11: N chamadas para o mesmo bucket criam exatamente 1 documento com count N e zero subcoleções/eventos", async () => {
    const fakeDb = new FakeFirestore();
    const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(
      fakeDb as any,
    );
    const plan = buildHealthTimelineShadowTelemetryAggregatePlan(
      validFailureInput,
      serverNow,
    );

    for (let i = 0; i < 5; i++) {
      await writer.recordAggregate(plan);
    }

    assert.strictEqual(fakeDb.store.size, 1);
    assert.strictEqual(fakeDb.store.get(plan.documentPath)!.count, 5);
  });

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== FIRESTORE ADAPTER UNIT TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) {
    console.error("❌ FIRESTORE ADAPTER UNIT TESTS FAILED");
    process.exit(1);
  } else {
    console.log(
      `🎯 FIRESTORE ADAPTER UNIT TESTS PASSED (${passed}/${passed + failed})`,
    );
  }
}

main().catch((error) => {
  console.error("Unexpected top-level error:", error);
  process.exit(1);
});
