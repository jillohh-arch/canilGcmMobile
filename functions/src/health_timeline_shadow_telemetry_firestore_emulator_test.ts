// Copyright 2024 GCM Health. All rights reserved.

import * as assert from "assert";
import * as admin from "firebase-admin";
import {
  FirestoreHealthTimelineShadowTelemetryAggregateWriter,
} from "./health_timeline_shadow_telemetry_firestore_adapter";
import {
  buildHealthTimelineShadowTelemetryAggregatePlan,
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
  console.log("=== HEALTH TIMELINE SHADOW TELEMETRY FIRESTORE EMULATOR TESTS ===\n");

  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulatorHost) {
    console.log("⏩ FIRESTORE_EMULATOR_HOST not set — Skipping live emulator E2E tests");
    console.log("(Unit adapter tests in health_timeline_shadow_telemetry_firestore_adapter_test.ts fully verify adapter logic)\n");
    console.log("=== FIRESTORE EMULATOR TEST SUMMARY ===");
    console.log("Passed: 0");
    console.log("Skipped: 1");
    console.log("Failed: 0");
    console.log("🎯 FIRESTORE EMULATOR TESTS SKIPPED GRACEFULLY (0/0)");
    return;
  }

  console.log(`FIRESTORE_EMULATOR_HOST observed: ${emulatorHost}\n`);

  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: "canil-gcm",
    });
  }
  const db = admin.firestore();
  const writer = new FirestoreHealthTimelineShadowTelemetryAggregateWriter(db);

  const testDate = new Date("2026-07-29T12:00:00Z");

  const inputComparisonA = {
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

  const inputComparisonB = {
    ...inputComparisonA,
    ordering_mismatch: true, // Dimensão diferente
  };

  const inputSkipped = {
    schema_version: 1,
    outcome_type: "skipped",
    skip_kind: "not_first_page",
  };

  const planA = buildHealthTimelineShadowTelemetryAggregatePlan(
    inputComparisonA,
    testDate,
  );
  const planB = buildHealthTimelineShadowTelemetryAggregatePlan(
    inputComparisonB,
    testDate,
  );
  const planSkipped = buildHealthTimelineShadowTelemetryAggregatePlan(
    inputSkipped,
    testDate,
  );

  const pathsToClean: string[] = [
    planA.documentPath,
    planB.documentPath,
    planSkipped.documentPath,
  ];

  // Helper de limpeza
  async function cleanup(): Promise<void> {
    for (const p of pathsToClean) {
      try {
        await db.doc(p).delete();
      } catch {
        // Ignora erros de exclusão se o documento não existir
      }
    }
  }

  await cleanup();

  try {
    // ── 1. Primeira Gravação (Create Bucket) ────────────────────────────────
    await test("E2E-1: primeira gravação cria bucket diário com count=1", async () => {
      await writer.recordAggregate(planA);

      const docSnap = await db.doc(planA.documentPath).get();
      assert.strictEqual(docSnap.exists, true);

      const data = docSnap.data()!;
      assert.strictEqual(data.aggregate_schema_version, 1);
      assert.strictEqual(data.utc_day, "2026-07-29");
      assert.strictEqual(data.bucket_id, planA.bucketId);
      assert.strictEqual(data.count, 1);
      assert.ok(data.first_seen_at !== undefined);
      assert.ok(data.last_seen_at !== undefined);
    });

    // ── 2. Segunda Gravação Mesma Dimensão (Increment Count = 2) ────────────
    await test("E2E-2: segunda gravação com mesmíssimas dimensões incrementa o mesmo bucket (count=2)", async () => {
      await writer.recordAggregate(planA);

      const docSnap = await db.doc(planA.documentPath).get();
      assert.strictEqual(docSnap.exists, true);

      const data = docSnap.data()!;
      assert.strictEqual(data.count, 2);
    });

    // ── 3. Dimensões Diferentes Criam Bucket Diferente ──────────────────────
    await test("E2E-3: dimensão diferente cria documento em bucket diferente", async () => {
      await writer.recordAggregate(planB);

      const docSnapB = await db.doc(planB.documentPath).get();
      assert.strictEqual(docSnapB.exists, true);
      assert.strictEqual(docSnapB.data()!.count, 1);

      // Confirmar que planA continua com count=2 e são documentos distintos
      const docSnapA = await db.doc(planA.documentPath).get();
      assert.strictEqual(docSnapA.data()!.count, 2);
      assert.notStrictEqual(planA.documentPath, planB.documentPath);
    });

    // ── 4. Outcome Diferente Cria Bucket Diferente ───────────────────────────
    await test("E2E-4: outcome diferente cria bucket separado", async () => {
      await writer.recordAggregate(planSkipped);

      const docSnapSkipped = await db.doc(planSkipped.documentPath).get();
      assert.strictEqual(docSnapSkipped.exists, true);
      assert.strictEqual(docSnapSkipped.data()!.count, 1);
      assert.strictEqual(docSnapSkipped.data()!.dimensions.outcome_type, "skipped");
    });

    // ── 5. Invariante de Ausência de Event Documents ─────────────────────────
    await test("E2E-5: confirma ausência de coleções de eventos individuais (events/requests/receipts)", async () => {
      const eventsSnap = await db.collection("events").get();
      const requestsSnap = await db.collection("requests").get();
      const receiptsSnap = await db.collection("receipts").get();

      assert.strictEqual(eventsSnap.empty, true);
      assert.strictEqual(requestsSnap.empty, true);
      assert.strictEqual(receiptsSnap.empty, true);
    });

    // ── 6. Rejeição de Documento Corrompido sem Sobrescrita ─────────────────
    await test("E2E-6: documento com integridade corrompida rejeita gravação sem ser sobrescrito", async () => {
      // Corromper o documento planB
      await db.doc(planB.documentPath).update({
        count: "invalid_string_count",
      });

      await assert.rejects(
        () => writer.recordAggregate(planB),
        (err: Error) => err.message.includes("shadow_telemetry_aggregate_integrity"),
      );

      // Confirmar que o valor corrompido não foi sobrescrito por 1 ou 2
      const docSnapCorrupted = await db.doc(planB.documentPath).get();
      assert.strictEqual(
        docSnapCorrupted.data()!.count,
        "invalid_string_count",
      );
    });
  } finally {
    await cleanup();
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== FIRESTORE EMULATOR TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) {
    console.error("❌ FIRESTORE EMULATOR LIVE TESTS FAILED");
    process.exit(1);
  } else {
    console.log(
      `🎯 FIRESTORE EMULATOR LIVE TESTS PASSED (${passed}/${passed + failed})`,
    );
  }
}

main().catch((error) => {
  console.error("Unexpected top-level error in emulator test:", error);
  process.exit(1);
});
