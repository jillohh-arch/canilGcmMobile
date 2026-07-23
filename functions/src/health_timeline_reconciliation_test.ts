import * as assert from "assert";
import {Timestamp} from "firebase-admin/firestore";
import {
  documentNameCursor,
  parseSourceDocumentPath,
  recordedAtCursorFromSnapshot,
  validateTimelineForOrphanResolution,
} from "./health_timeline_reconciliation";
import {
  StaleCursorError,
  cursorsEqual,
  decideLeaseAcquisition,
  deriveDiscrepancyId,
  discrepancyPath,
  globalPassKey,
  leaseTokenOwnsState,
  reconciliationPassPath,
  reconciliationRunPath,
  serializeCursor,
  sourcePassKey,
  type DiscrepancyIdentity,
  type LeaseToken,
  type RecordedAtQueryCursor,
} from "./health_timeline_reconciliation_state";
import {deriveTimelineId} from "./health_timeline_projection";
import {DeterministicInvalidPayloadError} from "./health_timeline_runtime";

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
    console.error(error);
  }
}

function timelineData(
  dogId = "dog-a",
  sourceId = "same-id",
  sourceType: "meal" | "supplement" = "meal",
): Record<string, unknown> {
  return {
    dog_id: dogId,
    source_collection:
      `dogs/${dogId}/${sourceType === "meal" ? "meal_logs" : "supplement_logs"}`,
    source_id: sourceId,
    timeline_type: sourceType,
  };
}

function timelinePath(
  dogId = "dog-a",
  sourceId = "same-id",
  sourceType: "meal" | "supplement" = "meal",
): string {
  const sourceCollection =
    `dogs/${dogId}/${sourceType === "meal" ? "meal_logs" : "supplement_logs"}`;
  return `dogs/${dogId}/health_timeline/${deriveTimelineId({
    sourceCollection,
    sourceId,
  })}`;
}

function discrepancyIdentity(
  overrides: Partial<DiscrepancyIdentity> = {},
): DiscrepancyIdentity {
  return {
    targetKind: "source",
    reasonCode: "invalid-source-payload",
    sourceType: "meal",
    dogId: "dog-a",
    sourceId: "meal-a",
    timelineDocumentPath: null,
    ...overrides,
  };
}

async function main(): Promise<void> {
  console.log("\n=== HEALTH TIMELINE RECONCILIATION UNIT TESTS ===\n");

  await test("A — state paths and keys are deterministic", () => {
    assert.strictEqual(
      reconciliationPassPath("meal_forward"),
      "_health_projection_state/health_timeline_v1/passes/meal_forward",
    );
    assert.strictEqual(
      reconciliationRunPath("run-1"),
      "_health_projection_state/health_timeline_v1/runs/run-1",
    );
    assert.ok(discrepancyPath(`hd1_${"a".repeat(64)}`).endsWith("a".repeat(64)));
  });

  await test("B — source and pass state are strictly separated", () => {
    const keys = new Set([
      sourcePassKey("meal", "forward"),
      sourcePassKey("supplement", "forward"),
      sourcePassKey("meal", "overlap"),
      sourcePassKey("meal", "historical"),
      globalPassKey("orphan"),
      globalPassKey("known_discrepancies"),
    ]);
    assert.strictEqual(keys.size, 6);
  });

  await test("C — Timestamp cursor serialization preserves physical type", () => {
    const at = Timestamp.fromMillis(123456);
    const cursor: RecordedAtQueryCursor = {
      kind: "recorded_at_name",
      recordedAt: at,
      normalizedRecordedAt: at.toDate().toISOString(),
      documentPath: "dogs/dog-a/meal_logs/meal-a",
    };
    const serialized = serializeCursor(cursor);
    assert.ok(serialized?.recorded_at instanceof Timestamp);
    assert.ok((serialized?.recorded_at as Timestamp).isEqual(at));
  });

  await test("C2 — ISO cursor serialization preserves string physical type", () => {
    const cursor: RecordedAtQueryCursor = {
      kind: "recorded_at_name",
      recordedAt: "2026-07-23T08:00:00.000Z",
      normalizedRecordedAt: "2026-07-23T08:00:00.000Z",
      documentPath: "dogs/dog-a/meal_logs/meal-a",
    };
    assert.strictEqual(
      serializeCursor(cursor)?.recorded_at,
      "2026-07-23T08:00:00.000Z",
    );
  });

  await test("D — full document name distinguishes same local ID", () => {
    const left = {
      kind: "document_name" as const,
      documentPath: "dogs/dog-a/meal_logs/same-id",
    };
    const right = {
      kind: "document_name" as const,
      documentPath: "dogs/dog-b/meal_logs/same-id",
    };
    assert.strictEqual(cursorsEqual(left, right), false);
  });

  await test("E — lease acquisition creates next fencing revision", () => {
    const token = decideLeaseAcquisition(
      {owner: null, revision: 4, expiresAt: null},
      "worker-a",
      new Date(1000),
      5000,
    );
    assert.strictEqual(token?.revision, 5);
    assert.strictEqual(token?.owner, "worker-a");
  });

  await test("F — valid lease denies a second acquisition", () => {
    const token = decideLeaseAcquisition(
      {
        owner: "worker-a",
        revision: 1,
        expiresAt: Timestamp.fromMillis(5000),
      },
      "worker-b",
      new Date(1000),
      5000,
    );
    assert.strictEqual(token, null);
  });

  await test("G — expired lease permits takeover with new fencing token", () => {
    const token = decideLeaseAcquisition(
      {
        owner: "worker-a",
        revision: 8,
        expiresAt: Timestamp.fromMillis(999),
      },
      "worker-b",
      new Date(1000),
      5000,
    );
    assert.strictEqual(token?.owner, "worker-b");
    assert.strictEqual(token?.revision, 9);
  });

  await test("H — stale fencing token cannot own newer state", () => {
    const stale: LeaseToken = {
      owner: "worker-a",
      revision: 1,
      expiresAt: Timestamp.fromMillis(9000),
    };
    assert.strictEqual(leaseTokenOwnsState(stale, {
      owner: "worker-b",
      revision: 2,
      expiresAt: Timestamp.fromMillis(9000),
    }, new Date(1000)), false);
  });

  await test("I — stale owner cannot release newer same-owner revision", () => {
    const stale: LeaseToken = {
      owner: "worker-a",
      revision: 3,
      expiresAt: Timestamp.fromMillis(9000),
    };
    assert.strictEqual(leaseTokenOwnsState(stale, {
      owner: "worker-a",
      revision: 4,
      expiresAt: Timestamp.fromMillis(9000),
    }, new Date(1000)), false);
  });

  await test("J — forward cursor equality includes timestamp and full name", () => {
    const at = Timestamp.fromMillis(1000);
    const base: RecordedAtQueryCursor = {
      kind: "recorded_at_name",
      recordedAt: at,
      normalizedRecordedAt: at.toDate().toISOString(),
      documentPath: "dogs/dog-a/meal_logs/same-id",
    };
    assert.strictEqual(cursorsEqual(base, {...base}), true);
    assert.strictEqual(
      cursorsEqual(base, {
        ...base,
        documentPath: "dogs/dog-b/meal_logs/same-id",
      }),
      false,
    );
  });

  await test("K — overlap cursor key cannot alias forward cursor key", () => {
    assert.notStrictEqual(
      sourcePassKey("meal", "overlap"),
      sourcePassKey("meal", "forward"),
    );
  });

  await test("L — overlap fixed-window cursor retains normalized instant", () => {
    const at = Timestamp.fromMillis(2000);
    const fake = {
      get: (field: string) => field === "recorded_at" ? at : undefined,
      ref: {path: "dogs/dog-a/meal_logs/meal-a"},
    };
    const cursor = recordedAtCursorFromSnapshot(fake as never);
    assert.strictEqual(cursor.normalizedRecordedAt, at.toDate().toISOString());
  });

  await test("M — historical cursor is document-name only", () => {
    const fake = {ref: {path: "dogs/dog-a/meal_logs/meal-a"}};
    assert.deepStrictEqual(documentNameCursor(fake as never), {
      kind: "document_name",
      documentPath: "dogs/dog-a/meal_logs/meal-a",
    });
  });

  await test("N — discrepancy ID is deterministic", () => {
    const identity = discrepancyIdentity();
    assert.strictEqual(
      deriveDiscrepancyId(identity),
      deriveDiscrepancyId({...identity}),
    );
    assert.match(deriveDiscrepancyId(identity), /^hd1_[0-9a-f]{64}$/);
  });

  await test("O — discrepancy identity changes with lifecycle cause", () => {
    assert.notStrictEqual(
      deriveDiscrepancyId(discrepancyIdentity()),
      deriveDiscrepancyId(discrepancyIdentity({
        reasonCode: "orphan-source-missing",
      })),
    );
  });

  await test("P — valid orphan identity resolves only through allowlist", () => {
    const path = timelinePath();
    const result = validateTimelineForOrphanResolution(
      path,
      timelineData(),
    );
    assert.strictEqual(result.valid, true);
    if (result.valid) {
      assert.strictEqual(result.identity.sourceType, "meal");
      assert.strictEqual(result.identity.dogId, "dog-a");
    }
  });

  await test("Q — cross-dog source collection is rejected", () => {
    const result = validateTimelineForOrphanResolution(timelinePath(), {
      ...timelineData(),
      source_collection: "dogs/dog-b/meal_logs",
    });
    assert.strictEqual(result.valid, false);
    if (!result.valid) {
      assert.strictEqual(
        result.identity.reasonCode,
        "timeline-source-collection-invalid",
      );
    }
  });

  await test("R1 — timeline outside canonical nested path is rejected", () => {
    const result = validateTimelineForOrphanResolution(
      `health_timeline/${"x".repeat(68)}`,
      timelineData(),
    );
    assert.strictEqual(result.valid, false);
  });

  await test("R2 — dog_id mismatch is rejected", () => {
    const result = validateTimelineForOrphanResolution(timelinePath(), {
      ...timelineData(),
      dog_id: "dog-b",
    });
    assert.strictEqual(result.valid, false);
    if (!result.valid) {
      assert.strictEqual(result.identity.reasonCode, "timeline-dog-mismatch");
    }
  });

  await test("R3 — slash-containing source ID is rejected", () => {
    const result = validateTimelineForOrphanResolution(timelinePath(), {
      ...timelineData(),
      source_id: "bad/id",
    });
    assert.strictEqual(result.valid, false);
  });

  await test("R4 — timeline/source type mismatch is rejected", () => {
    const result = validateTimelineForOrphanResolution(timelinePath(), {
      ...timelineData(),
      timeline_type: "supplement",
    });
    assert.strictEqual(result.valid, false);
  });

  await test("R5 — deterministic timeline ID mismatch is rejected", () => {
    const result = validateTimelineForOrphanResolution(
      "dogs/dog-a/health_timeline/tl1_" + "0".repeat(64),
      timelineData(),
    );
    assert.strictEqual(result.valid, false);
  });

  await test("S — invalid source paths never become dereferenceable", () => {
    assert.throws(
      () => parseSourceDocumentPath("dogs/dog-a/meal_logs/bad/id"),
      DeterministicInvalidPayloadError,
    );
    assert.throws(
      () => parseSourceDocumentPath("arbitrary/path"),
      DeterministicInvalidPayloadError,
    );
  });

  await test("T — stale cursor is a closed failure type", () => {
    const error = new StaleCursorError("changed");
    assert.strictEqual(error.name, "StaleCursorError");
  });

  await test("U — persisted discrepancy identity contains no raw payload", () => {
    const identity = discrepancyIdentity();
    assert.deepStrictEqual(Object.keys(identity).sort(), [
      "dogId",
      "reasonCode",
      "sourceId",
      "sourceType",
      "targetKind",
      "timelineDocumentPath",
    ].sort());
  });

  console.log("\n=== UNIT TEST SUMMARY ===");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (failed > 0) process.exitCode = 1;
  else {
    console.log(
      `🎯 HEALTH TIMELINE RECONCILIATION UNIT TESTS PASSED (${passed}/${passed})`,
    );
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
