/**
 * Unit tests for the fail-closed activation guard.
 *
 * Stage D.2A — Local implementation only. Not deployed.
 *
 * Verifies:
 *   1. Guard absent → disabled, reconciler called 0 times.
 *   2. Guard false → disabled, reconciler called 0 times.
 *   3. Guard true (explicit) → enabled, reconciler called exactly 1 time.
 *   4. Guard invalid/ambiguous values → disabled (fail-closed), reconciler 0 times.
 *   5. Guard enabled + reconciler throws → error propagates (no false success).
 *   6. readActivationGuard is pure — does not mutate env.
 */
import * as assert from "assert";
import {readActivationGuard} from "./health_timeline_activation_guard";

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

/**
 * Simulates the handler behavior driven by the guard result.
 * reconcilerCallCount tracks invocations without any Firestore access.
 */
async function runHandlerWithGuard(
  env: Record<string, string | undefined>,
  reconcilerImpl: () => Promise<void>,
): Promise<{reconcilerCallCount: number}> {
  let reconcilerCallCount = 0;
  const guard = readActivationGuard(env);
  if (!guard.enabled) {
    return {reconcilerCallCount};
  }
  reconcilerCallCount++;
  await reconcilerImpl();
  return {reconcilerCallCount};
}

async function main(): Promise<void> {
  console.log("=== HEALTH TIMELINE ACTIVATION GUARD UNIT TESTS ===\n");

  // ── Test 1: guard absent ──────────────────────────────────────────────────
  await test("absent env var → disabled, reconciler called 0 times", async () => {
    const result = await runHandlerWithGuard({}, async () => {
      throw new Error("reconciler must not be called when guard is absent");
    });
    assert.strictEqual(result.reconcilerCallCount, 0);
    assert.strictEqual(readActivationGuard({}).enabled, false);
  });

  // ── Test 2: guard false ───────────────────────────────────────────────────
  await test('HEALTH_TIMELINE_RECONCILIATION_ENABLED="false" → disabled', async () => {
    const env = {HEALTH_TIMELINE_RECONCILIATION_ENABLED: "false"};
    const result = await runHandlerWithGuard(env, async () => {
      throw new Error("reconciler must not be called when guard is false");
    });
    assert.strictEqual(result.reconcilerCallCount, 0);
    assert.strictEqual(readActivationGuard(env).enabled, false);
  });

  // ── Test 3: guard true ────────────────────────────────────────────────────
  await test('HEALTH_TIMELINE_RECONCILIATION_ENABLED="true" → enabled, reconciler called exactly 1 time', async () => {
    const env = {HEALTH_TIMELINE_RECONCILIATION_ENABLED: "true"};
    const result = await runHandlerWithGuard(env, async () => {
      // Reconciler invoked with no-op (no Firestore in this test)
    });
    assert.strictEqual(result.reconcilerCallCount, 1);
    assert.strictEqual(readActivationGuard(env).enabled, true);
  });

  // ── Test 4: guard invalid/ambiguous values → fail-closed ─────────────────
  await test("invalid/ambiguous values → disabled (fail-closed)", async () => {
    const invalidValues = ["1", "yes", "TRUE", "True", "on", "enabled", "0", "", " "];
    for (const value of invalidValues) {
      const env = {HEALTH_TIMELINE_RECONCILIATION_ENABLED: value};
      const result = await runHandlerWithGuard(env, async () => {
        throw new Error(`reconciler must not be called for value "${value}"`);
      });
      assert.strictEqual(result.reconcilerCallCount, 0, `Expected 0 for value "${value}"`);
      assert.strictEqual(
        readActivationGuard(env).enabled,
        false,
        `Expected disabled for value "${value}"`,
      );
    }
  });

  // ── Test 5: guard true + reconciler throws → error propagates ────────────
  await test("guard true + reconciler throws → error propagates (no false success)", async () => {
    const env = {HEALTH_TIMELINE_RECONCILIATION_ENABLED: "true"};
    const expectedError = new Error("reconciler-failure-sentinel");
    let caughtError: Error | null = null;
    try {
      await runHandlerWithGuard(env, async () => {
        throw expectedError;
      });
    } catch (e) {
      caughtError = e as Error;
    }
    assert.ok(caughtError !== null, "Error must have propagated");
    assert.strictEqual(caughtError, expectedError, "Must be the exact same error instance");
  });

  // ── Test 6: readActivationGuard is pure ───────────────────────────────────
  await test("readActivationGuard is pure — same input produces same output", async () => {
    const envEnabled: Record<string, string | undefined> = {
      HEALTH_TIMELINE_RECONCILIATION_ENABLED: "true",
    };
    assert.strictEqual(readActivationGuard(envEnabled).enabled, true);
    assert.strictEqual(readActivationGuard(envEnabled).enabled, true);

    const envDisabled: Record<string, string | undefined> = {
      HEALTH_TIMELINE_RECONCILIATION_ENABLED: "false",
    };
    assert.strictEqual(readActivationGuard(envDisabled).enabled, false);
  });

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n=== ACTIVATION GUARD UNIT TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) {
    console.error("❌ ACTIVATION GUARD TESTS FAILED");
    process.exit(1);
  } else {
    console.log(
      `🎯 HEALTH TIMELINE ACTIVATION GUARD UNIT TESTS PASSED (${passed}/${passed + failed})`,
    );
  }
}

main().catch((error) => {
  console.error("Unexpected top-level error:", error);
  process.exit(1);
});
