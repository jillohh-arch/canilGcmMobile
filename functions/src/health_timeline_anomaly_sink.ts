/**
 * Durable anomaly sink adapter for HealthTimeline Firestore triggers.
 *
 * Uses the SHARED transactional discrepancy primitive from
 * FirestoreReconciliationState — same logic, same collection, same identity
 * derivation, same schema.
 *
 * Architecture:
 *
 *   FirestoreReconciliationState.upsertDiscrepancyInTransaction(tx, identity, ctx)
 *           ↑                                      ↑
 *   Trigger anomaly sink                   Reconciliation runtime
 *   db.runTransaction(tx => ...)            existing lease/fencing transaction
 *   (no lease)                             (lease/fencing validated)
 *
 * Key guarantees:
 * - Transactional read-then-write: zero lost updates, zero races
 * - Deterministic ID: same anomaly → same document
 * - first_seen_at preserved across concurrent writes
 * - attempts atomically incremented
 * - status consistency under concurrency
 *
 * Gate 5C.5C.5.1 — Corrective round. Local code only. Not deployed.
 */
import {type Firestore} from "firebase-admin/firestore";
import {
  FirestoreReconciliationState,
  type DiscrepancyIdentity,
} from "./health_timeline_reconciliation_state";
import type {RuntimeClock} from "./health_timeline_runtime";
import type {
  HealthTimelineAnomaly,
  HealthTimelineAnomalySink,
} from "./health_timeline_trigger_handlers";

/**
 * Maps trigger RuntimeReasonCode to the reconciliation discrepancy taxonomy.
 * All trigger-detected deterministic invalid payloads map to the same
 * reconciliation category — the specific runtime reason is preserved in safeContext.
 */
function anomalyToDiscrepancyIdentity(
  anomaly: HealthTimelineAnomaly,
): DiscrepancyIdentity {
  return {
    targetKind: "source",
    reasonCode: "invalid-source-payload",
    sourceType: anomaly.sourceType,
    dogId: anomaly.dogId,
    sourceId: anomaly.sourceId,
    timelineDocumentPath: null,
  };
}

export class FirestoreAnomalySink implements HealthTimelineAnomalySink {
  private readonly state: FirestoreReconciliationState;

  constructor(
    db: Firestore,
    clock: RuntimeClock,
  ) {
    // No beforeDiscrepancyWrite hook — triggers don't need test instrumentation.
    // The clock is used by upsertDiscrepancyInTransaction for Timestamp generation.
    this.state = new FirestoreReconciliationState(db, clock);
  }

  async record(anomaly: HealthTimelineAnomaly): Promise<void> {
    const identity = anomalyToDiscrepancyIdentity(anomaly);
    const safeContext: Record<string, string | number | boolean | null> = {
      ...(anomaly.context ?? {}),
      runtime_reason: anomaly.reasonCode,
    };

    // Transactional: uses the shared discrepancy primitive in a Firestore
    // transaction. No reconciliation lease — the primitive does not require one.
    // This guarantees atomic read-then-write: first_seen_at preserved,
    // attempts correctly incremented, no lost updates, no status races.
    await this.state.db.runTransaction(async (transaction) => {
      await this.state.upsertDiscrepancyInTransaction(
        transaction,
        identity,
        safeContext,
      );
    });
  }
}
