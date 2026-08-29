/**
 * HealthTimeline reconciliation orchestrator.
 *
 * Standalone function — testable independently of onSchedule.
 * Reuses the approved reconciliation runtime with per-pass bounded execution.
 *
 * Key guarantees (INITIAL ACTIVATION CONFIG, not SLA):
 * - Each pass executes independently bounded (1 page per pass)
 * - No global budget — backlog in one domain cannot starve another
 * - Lease-protected single-worker execution
 * - Partial failure stops, marks failed, releases safely, throws
 * - Cursor-committed pages survive restart
 *
 * Gate 5C.5C.5 — Local code only. Not deployed.
 */
import {randomUUID} from "crypto";
import type {Firestore} from "firebase-admin/firestore";
import {
  HealthTimelineReconciliationRuntime,
  type ReconciliationPageResult,
} from "./health_timeline_reconciliation";
import {
  FirestoreReconciliationState,
  type LeaseToken,
} from "./health_timeline_reconciliation_state";
import type {
  RuntimeClock,
  RuntimeLogger,
  TransactionalHealthTimelineProjector,
} from "./health_timeline_runtime";

// ─────────────────────────────────────────────────────────────────────────────
// INITIAL ACTIVATION CONFIG — not SLA, not capacity guarantee
// ─────────────────────────────────────────────────────────────────────────────

export interface OrchestratorConfig {
  /** Page size for each pass (default 25). */
  pageSize: number;
  /** Overlap window in milliseconds (default 1h). */
  overlapMs: number;
  /** Lease duration in milliseconds (default 10 min). */
  leaseDurationMs: number;
}

export const DEFAULT_ORCHESTRATOR_CONFIG: OrchestratorConfig = {
  pageSize: 25,
  overlapMs: 3_600_000,
  leaseDurationMs: 600_000,
};

// ─────────────────────────────────────────────────────────────────────────────

export interface PassResult {
  passKey: string;
  result: ReconciliationPageResult | null;
  error?: string;
}

export interface OrchestratorResult {
  runId: string;
  status: "completed" | "failed" | "skipped";
  passes: PassResult[];
  summary: {
    created: number;
    noop: number;
    repaired: number;
    skippedAnomaly: number;
    totalProcessed: number;
  };
}

/**
 * Pass ordering — preserves operational priority.
 *
 * 1. Forward (new sources without timeline) — highest priority
 * 2. Overlap (recent sources near cursor boundary)
 * 3. Historical (older sources never reconciled)
 * 4. Orphan (timeline entries without source)
 * 5. Known discrepancies (previously invalid/anomalous sources)
 *
 * Each pass is independently bounded: 1 page per invocation.
 * No pass can consume the budget of another.
 */
const PASS_SCHEDULE: ReadonlyArray<{
  passKey: string;
  sourceType?: "meal" | "supplement";
}> = [
  {passKey: "meal_forward", sourceType: "meal"},
  {passKey: "supplement_forward", sourceType: "supplement"},
  {passKey: "meal_overlap", sourceType: "meal"},
  {passKey: "supplement_overlap", sourceType: "supplement"},
  {passKey: "meal_historical", sourceType: "meal"},
  {passKey: "supplement_historical", sourceType: "supplement"},
  {passKey: "orphan_global"},
  {passKey: "known_discrepancies_global"},
];

async function executePage(
  runtime: HealthTimelineReconciliationRuntime,
  token: LeaseToken,
  pass: typeof PASS_SCHEDULE[number],
  config: OrchestratorConfig,
): Promise<ReconciliationPageResult> {
  const pageSize = config.pageSize;

  switch (pass.passKey) {
    case "meal_forward":
    case "supplement_forward":
      if (!pass.sourceType) throw new Error("Forward pass requires sourceType.");
      return runtime.runForwardPage(token, pass.sourceType, pageSize);

    case "meal_overlap":
    case "supplement_overlap":
      if (!pass.sourceType) throw new Error("Overlap pass requires sourceType.");
      return runtime.runOverlapPage(
        token,
        pass.sourceType,
        pageSize,
        config.overlapMs,
      );

    case "meal_historical":
    case "supplement_historical":
      if (!pass.sourceType) throw new Error("Historical pass requires sourceType.");
      return runtime.runHistoricalPage(token, pass.sourceType, pageSize);

    case "orphan_global":
      return runtime.runOrphanPage(token, pageSize);

    case "known_discrepancies_global":
      return runtime.runKnownDiscrepancyPage(token, pageSize);

    default:
      throw new Error(`Unknown pass key: ${pass.passKey}`);
  }
}

export async function runHealthTimelineReconciliation(
  db: Firestore,
  config: OrchestratorConfig,
  clock: RuntimeClock,
  logger: RuntimeLogger,
  projector: TransactionalHealthTimelineProjector,
): Promise<OrchestratorResult> {
  const state = new FirestoreReconciliationState(db, clock);
  const runtime = new HealthTimelineReconciliationRuntime(
    db,
    state,
    projector,
    logger,
  );

  const runId = `run_${randomUUID()}`;
  const owner = `orchestrator_${randomUUID()}`;

  // 1. Acquire lease
  let token: LeaseToken | null;
  try {
    token = await state.acquireLease(owner, config.leaseDurationMs);
  } catch (error) {
    logger.error("HealthTimeline reconciliation lease acquisition failed", {
      runId,
      owner,
      error: error instanceof Error ? error.message : "unknown",
    });
    return {
      runId,
      status: "failed",
      passes: [],
      summary: {created: 0, noop: 0, repaired: 0, skippedAnomaly: 0, totalProcessed: 0},
    };
  }

  if (!token) {
    logger.info("HealthTimeline reconciliation skipped — lease held by another worker.", {
      runId,
      owner,
    });
    return {
      runId,
      status: "skipped",
      passes: [],
      summary: {created: 0, noop: 0, repaired: 0, skippedAnomaly: 0, totalProcessed: 0},
    };
  }

  // 2. Start run
  const firstPassKey = PASS_SCHEDULE[0].passKey;
  await state.startRun(token, runId, firstPassKey);

  const passes: PassResult[] = [];
  let status: "completed" | "failed" = "failed";

  try {
    // 3. Execute each pass — independently bounded
    for (const pass of PASS_SCHEDULE) {
      let passResult: PassResult;

      try {
        const page = await executePage(runtime, token, pass, config);
        passResult = {passKey: pass.passKey, result: page};
        runtime.logPage(page);
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : "unknown";
        passResult = {
          passKey: pass.passKey,
          result: null,
          error: errorMessage,
        };
        passes.push(passResult);

        // Partial failure: stop, mark failed, release, throw
        logger.error("HealthTimeline reconciliation pass failed", {
          runId,
          passKey: pass.passKey,
          error: errorMessage,
        });

        await state.finishRun(token, runId, "failed").catch(() => undefined);
        await state.releaseLease(token).catch(() => undefined);

        throw error;
      }

      passes.push(passResult);
    }

    status = "completed";
  } finally {
    if (status === "completed") {
      await state.finishRun(token, runId, "completed");
    }
    await state.releaseLease(token);
  }

  // 4. Summarize
  const summary = passes.reduce(
    (acc, p) => {
      if (!p.result) return acc;
      acc.created += p.result.created;
      acc.noop += p.result.noop;
      acc.repaired += p.result.repaired;
      acc.skippedAnomaly += p.result.skippedAnomaly;
      acc.totalProcessed += p.result.processed;
      return acc;
    },
    {created: 0, noop: 0, repaired: 0, skippedAnomaly: 0, totalProcessed: 0},
  );

  logger.info("HealthTimeline reconciliation completed", {
    runId,
    status,
    ...summary,
  });

  return {runId, status, passes, summary};
}
