import * as assert from "assert";
import {Timestamp} from "firebase-admin/firestore";
import {projectMealLog} from "./health_timeline_projection";
import {
  DeterministicInvalidPayloadError,
  TransientInfrastructureError,
  assertSafeDocumentId,
  canonicalTimelineKeys,
  firestoreTimestampToPure,
  isHealthTimelineSourceType,
  pureTimestampToFirestore,
  serializeCanonicalTimeline,
  sourceCollectionPath,
  sourceDocumentPath,
  timelineDocumentPath,
  type HealthTimelineProjector,
  type RuntimeLogger,
  type ValidatedProjectionSource,
} from "./health_timeline_runtime";
import {
  makeMealLogCreatedHandler,
  makeSupplementLogCreatedHandler,
  type HealthTimelineAnomaly,
  type TriggerHandlerDependencies,
  type TriggerSnapshotLike,
} from "./health_timeline_trigger_handlers";

const FIXED_NOW = new Date("2026-07-23T12:00:00.000Z");

const logger: RuntimeLogger = {
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
};

function mealPayload(): Record<string, unknown> {
  return {
    period: "morning",
    offered_grams: 200,
    consumed_grams: 180,
    acceptance: "partial",
    fed_at: Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z")),
    recorded_at: "2026-07-23T08:05:00.000Z",
    recorded_by: {
      uid: "user-1",
      name: "Condutor Teste",
      internal_role: "condutor",
    },
    food_name: "Ração Teste",
    arbitrary_source_field: "must-not-leak",
  };
}

function supplementPayload(): Record<string, unknown> {
  return {
    supplement_name: "Vitamina",
    dose: 25,
    unit: "mg",
    administered_at: Timestamp.fromDate(
      new Date("2026-07-23T09:00:00.000Z"),
    ),
    recorded_at: Timestamp.fromDate(
      new Date("2026-07-23T09:01:00.000Z"),
    ),
    recorded_by: {
      uid: "user-1",
      name: "Condutor Teste",
      internal_role: "condutor",
    },
  };
}

function snapshot(
  path: string,
  id: string,
  data: Record<string, unknown>,
): TriggerSnapshotLike {
  return {
    exists: true,
    id,
    ref: {path},
    data: () => data,
  };
}

function fakeProjector(
  captured: ValidatedProjectionSource[],
  failure?: Error,
): HealthTimelineProjector {
  return {
    project: async (source) => {
      captured.push(source);
      if (failure) throw failure;
      return {
        operation: "created",
        timelineId: "tl1_unit",
        destinationPath: `dogs/${source.dogId}/health_timeline/tl1_unit`,
      };
    },
  };
}

function handlerDeps(options: {
  captured?: ValidatedProjectionSource[];
  anomalies?: HealthTimelineAnomaly[];
  projectorFailure?: Error;
  sinkFailure?: Error;
} = {}): TriggerHandlerDependencies {
  const captured = options.captured ?? [];
  const anomalies = options.anomalies ?? [];
  return {
    projector: fakeProjector(captured, options.projectorFailure),
    anomalySink: {
      record: async (anomaly) => {
        if (options.sinkFailure) throw options.sinkFailure;
        anomalies.push(anomaly);
      },
    },
    clock: {now: () => new Date(FIXED_NOW)},
    logger,
  };
}

let passed = 0;

async function test(
  name: string,
  body: () => void | Promise<void>,
): Promise<void> {
  await body();
  passed++;
  console.log(`✅ ${name}`);
}

async function main(): Promise<void> {
  console.log("\n=== HEALTH TIMELINE RUNTIME UNIT TESTS ===\n");

  await test("closed source enum accepts only meal/supplement", () => {
    assert.strictEqual(isHealthTimelineSourceType("meal"), true);
    assert.strictEqual(isHealthTimelineSourceType("supplement"), true);
    assert.strictEqual(isHealthTimelineSourceType("arbitrary"), false);
  });

  await test("source path builder uses fixed collection allowlist", () => {
    assert.strictEqual(
      sourceCollectionPath("meal", "dog-1"),
      "dogs/dog-1/meal_logs",
    );
    assert.strictEqual(
      sourceDocumentPath("supplement", "dog-1", "supp-1"),
      "dogs/dog-1/supplement_logs/supp-1",
    );
  });

  await test("invalid dog/source IDs are rejected", () => {
    assert.throws(
      () => assertSafeDocumentId("", "dog"),
      DeterministicInvalidPayloadError,
    );
    assert.throws(
      () => assertSafeDocumentId("bad/id", "source"),
      DeterministicInvalidPayloadError,
    );
  });

  await test("destination path is canonical and dog-scoped", () => {
    assert.strictEqual(
      timelineDocumentPath("dog-1", "tl1_hash"),
      "dogs/dog-1/health_timeline/tl1_hash",
    );
  });

  await test("Timestamp codec converts Firestore Timestamp to pure ISO", () => {
    const timestamp = Timestamp.fromDate(
      new Date("2026-07-23T10:11:12.345Z"),
    );
    assert.strictEqual(
      firestoreTimestampToPure(timestamp, "occurred_at"),
      "2026-07-23T10:11:12.345Z",
    );
  });

  await test("Timestamp codec round-trip preserves the instant", () => {
    const iso = "2026-07-23T10:11:12.345Z";
    const encoded = pureTimestampToFirestore(iso, "recorded_at");
    assert.ok(encoded instanceof Timestamp);
    assert.strictEqual(
      firestoreTimestampToPure(encoded, "recorded_at"),
      iso,
    );
  });

  await test("invalid timestamp is deterministic-invalid", () => {
    assert.throws(
      () => pureTimestampToFirestore("not-a-date", "recorded_at"),
      DeterministicInvalidPayloadError,
    );
    assert.throws(
      () => firestoreTimestampToPure(123, "recorded_at"),
      DeterministicInvalidPayloadError,
    );
  });

  await test("serializer persists exact canonical allowlist and Timestamps", () => {
    const pure = projectMealLog({
      id: "meal-1",
      dogId: "dog-1",
      kind: "adhoc",
      acceptance: "full",
      offered_grams: 200,
      consumed_grams: 200,
      fed_at: "2026-07-23T08:00:00.000Z",
      recorded_at: "2026-07-23T08:01:00.000Z",
      recorded_by: {
        uid: "user-1",
        name: "Condutor",
        internal_role: "condutor",
      },
    }, "tl1_unit");
    const withExtra = {
      ...pure,
      projected_at: "2026-07-23T08:02:00.000Z",
      TEST_CONFIG: {bad: true},
      arbitrary_source_field: "must-not-leak",
    };
    const serialized = serializeCanonicalTimeline(withExtra);
    assert.deepStrictEqual(
      Object.keys(serialized).sort(),
      [...canonicalTimelineKeys()].sort(),
    );
    assert.ok(serialized.occurred_at instanceof Timestamp);
    assert.ok(serialized.recorded_at instanceof Timestamp);
    assert.ok(serialized.projected_at instanceof Timestamp);
    assert.strictEqual("TEST_CONFIG" in serialized, false);
    assert.strictEqual("arbitrary_source_field" in serialized, false);
  });

  await test("serializer omits undefined optional subtitle", () => {
    const serialized = serializeCanonicalTimeline({
      timeline_type: "meal",
      source_collection: "dogs/dog-1/meal_logs",
      source_id: "meal-1",
      occurred_at: "2026-07-23T08:00:00.000Z",
      recorded_at: "2026-07-23T08:01:00.000Z",
      projected_at: "2026-07-23T08:02:00.000Z",
      title: "Refeição",
      subtitle: undefined,
      dog_id: "dog-1",
      recorded_by: {
        uid: "user-1",
        name: "Condutor",
        internal_role: "condutor",
      },
      status: "final",
      schema_version: 1,
      created_at: "ignored",
      updated_at: "ignored",
    });
    assert.strictEqual("subtitle" in serialized, false);
    assert.strictEqual(
      Object.values(serialized).some((value) => value === undefined),
      false,
    );
  });

  await test("meal handler fixes source type and parses validated source", async () => {
    const captured: ValidatedProjectionSource[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({captured}));
    const result = await handler({
      params: {dogId: "dog-1", mealId: "meal-1"},
      snapshot: snapshot(
        "dogs/dog-1/meal_logs/meal-1",
        "meal-1",
        mealPayload(),
      ),
    });
    assert.strictEqual(result.status, "projected");
    assert.strictEqual(captured.length, 1);
    assert.strictEqual(captured[0].sourceType, "meal");
  });

  await test("supplement handler fixes source type", async () => {
    const captured: ValidatedProjectionSource[] = [];
    const handler = makeSupplementLogCreatedHandler(handlerDeps({captured}));
    await handler({
      params: {dogId: "dog-1", supplementLogId: "supp-1"},
      snapshot: snapshot(
        "dogs/dog-1/supplement_logs/supp-1",
        "supp-1",
        supplementPayload(),
      ),
    });
    assert.strictEqual(captured[0].sourceType, "supplement");
  });

  await test("cross-dog ref becomes anomaly with zero projection", async () => {
    const captured: ValidatedProjectionSource[] = [];
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(
      handlerDeps({captured, anomalies}),
    );
    const result = await handler({
      params: {dogId: "dog-1", mealId: "meal-1"},
      snapshot: snapshot(
        "dogs/dog-2/meal_logs/meal-1",
        "meal-1",
        mealPayload(),
      ),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "cross-dog-source",
    });
    assert.strictEqual(captured.length, 0);
    assert.strictEqual(anomalies.length, 1);
  });

  await test("wrong source collection becomes deterministic anomaly", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({anomalies}));
    const result = await handler({
      params: {dogId: "dog-1", mealId: "meal-1"},
      snapshot: snapshot(
        "dogs/dog-1/supplement_logs/meal-1",
        "meal-1",
        mealPayload(),
      ),
    });
    assert.strictEqual(result.status, "anomaly");
    assert.strictEqual(anomalies[0].reasonCode, "invalid-source-path");
  });

  await test("invalid source ID becomes anomaly without dereference", async () => {
    const captured: ValidatedProjectionSource[] = [];
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(
      handlerDeps({captured, anomalies}),
    );
    const result = await handler({
      params: {dogId: "dog-1", mealId: "bad/id"},
      snapshot: snapshot(
        "dogs/dog-1/meal_logs/bad-id",
        "bad-id",
        mealPayload(),
      ),
    });
    assert.strictEqual(result.status, "anomaly");
    assert.strictEqual(captured.length, 0);
    assert.strictEqual(anomalies[0].reasonCode, "invalid-source-id");
  });

  await test("malformed payload records anomaly and returns success", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({anomalies}));
    const result = await handler({
      params: {dogId: "dog-1", mealId: "meal-1"},
      snapshot: snapshot(
        "dogs/dog-1/meal_logs/meal-1",
        "meal-1",
        {...mealPayload(), fed_at: "invalid"},
      ),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "invalid-timestamp",
    });
    assert.strictEqual(anomalies.length, 1);
  });

  await test("non-canonical meal enum becomes deterministic anomaly", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({anomalies}));
    const result = await handler({
      params: {dogId: "dog-1", mealId: "meal-1"},
      snapshot: snapshot(
        "dogs/dog-1/meal_logs/meal-1",
        "meal-1",
        {...mealPayload(), acceptance: "mostly"},
      ),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "malformed-payload",
    });
    assert.strictEqual(anomalies.length, 1);
  });

  await test("non-canonical supplement unit becomes anomaly", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeSupplementLogCreatedHandler(
      handlerDeps({anomalies}),
    );
    const result = await handler({
      params: {dogId: "dog-1", supplementLogId: "supp-1"},
      snapshot: snapshot(
        "dogs/dog-1/supplement_logs/supp-1",
        "supp-1",
        {...supplementPayload(), unit: "capsule"},
      ),
    });
    assert.deepStrictEqual(result, {
      status: "anomaly",
      reasonCode: "malformed-payload",
    });
    assert.strictEqual(anomalies.length, 1);
  });

  await test("missing snapshot is transient and is rethrown", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({anomalies}));
    await assert.rejects(
      () => handler({
        params: {dogId: "dog-1", mealId: "meal-1"},
      }),
      TransientInfrastructureError,
    );
    assert.strictEqual(anomalies.length, 0);
  });

  await test("anomaly sink failure is never swallowed", async () => {
    const sinkFailure = new Error("sink unavailable");
    const handler = makeMealLogCreatedHandler(
      handlerDeps({sinkFailure}),
    );
    await assert.rejects(
      () => handler({
        params: {dogId: "dog-1", mealId: "meal-1"},
        snapshot: snapshot(
          "dogs/dog-2/meal_logs/meal-1",
          "meal-1",
          mealPayload(),
        ),
      }),
      /sink unavailable/,
    );
  });

  await test("transient projector failure is propagated, not anomalized", async () => {
    const anomalies: HealthTimelineAnomaly[] = [];
    const handler = makeMealLogCreatedHandler(handlerDeps({
      anomalies,
      projectorFailure: new Error("firestore unavailable"),
    }));
    await assert.rejects(
      () => handler({
        params: {dogId: "dog-1", mealId: "meal-1"},
        snapshot: snapshot(
          "dogs/dog-1/meal_logs/meal-1",
          "meal-1",
          mealPayload(),
        ),
      }),
      /firestore unavailable/,
    );
    assert.strictEqual(anomalies.length, 0);
  });

  console.log(`\n🎯 HEALTH TIMELINE RUNTIME UNIT TESTS PASSED (${passed}/${passed})\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
