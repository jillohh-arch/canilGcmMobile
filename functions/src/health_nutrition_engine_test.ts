/**
 * Testes do motor Nutrição 5D Gate 1 (transação em memória).
 * npm run build && node lib/health_nutrition_engine_test.js
 */
import * as assert from "assert";
import {
  NutritionActor,
  NutritionEngineDeps,
  NutritionTxn,
  pathNutritionOperation,
  pathNutritionPlan,
  runCreateAdhocMealLog,
  runCreatePlannedMealLog,
  runCreateSupplementLog,
} from "./health_nutrition_engine";
import {
  mealOccurrenceIdV1,
  nutritionOperationReceiptIdV1,
} from "./health_nutrition_logic";

function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  return Promise.resolve()
    .then(() => fn())
    .then(() => {
      console.log(`ok - ${name}`);
    })
    .catch((e) => {
      console.error(`FAIL - ${name}`);
      throw e;
    });
}

const actor: NutritionActor = {
  uid: "uid-1",
  email: "123@gcm.com.br",
  ra: "123",
  name: "Condutor",
};

const actorB: NutritionActor = {
  uid: "uid-B",
  email: "456@gcm.com.br",
  ra: "456",
  name: "Outro",
};

function samplePlan(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    status: "active",
    timezone: "America/Sao_Paulo",
    valid_from: "2026-01-01T00:00:00.000Z",
    meal_schedule: [
      {
        id: "slot-am",
        period: "morning",
        scheduled_time: "07:00",
        target_grams: 300,
      },
    ],
    supplements: [{id: "reg-1", name: "Omega"}],
    ...overrides,
  };
}

function memoryDeps(opts: {
  dogId?: string;
  planId?: string;
  plan?: Record<string, unknown> | null;
  serverNow?: Date;
  /** Mutação executada no início de cada runTransaction (simula TOCTOU). */
  beforeTransaction?: (
    store: Map<string, Record<string, unknown>>,
  ) => void;
}): {
  deps: NutritionEngineDeps;
  store: Map<string, Record<string, unknown>>;
  writes: string[];
  planPath: string;
} {
  const dogId = opts.dogId ?? "dog-1";
  const planId = opts.planId ?? "plan-1";
  const planPath = pathNutritionPlan(dogId, planId);
  const store = new Map<string, Record<string, unknown>>();
  if (opts.plan !== null && opts.plan !== undefined) {
    store.set(planPath, {...opts.plan});
  }
  const writes: string[] = [];
  const read = (path: string) => {
    const data = store.get(path);
    return {exists: data !== undefined, data: data ?? {}};
  };
  const deps: NutritionEngineDeps = {
    serverNow: () => opts.serverNow ?? new Date("2026-07-18T15:00:00.000Z"),
    isAdmin: () => false,
    getDoc: async (path: string) => read(path),
    runTransaction: async <T>(fn: (tx: NutritionTxn) => Promise<T>) => {
      if (opts.beforeTransaction) {
        opts.beforeTransaction(store);
      }
      const tx: NutritionTxn = {
        get: async (path: string) => read(path),
        set: (path: string, data: Record<string, unknown>) => {
          writes.push(path);
          store.set(path, {...data});
        },
      };
      return fn(tx);
    },
  };
  return {deps, store, writes, planPath};
}

function plannedPayload(key: string, extra: Record<string, unknown> = {}) {
  return {
    dogId: "dog-1",
    planId: "plan-1",
    plannedMealId: "slot-am",
    offeredGrams: 300,
    acceptance: "full",
    fedAt: "2026-07-18T10:00:00.000Z",
    idempotencyKey: key,
    ...extra,
  };
}

async function main(): Promise<void> {
  await test("planned create → meal_logs + durable registry + 1 audit", async () => {
    const {deps, store, writes} = memoryDeps({plan: samplePlan()});
    const r = await runCreatePlannedMealLog(
      actor,
      plannedPayload("key-plan-1"),
      deps,
    );
    assert.strictEqual(r.wasNoOp, false);
    assert.ok(r.entityId.startsWith("mo1_"));
    const expectedReceipt = nutritionOperationReceiptIdV1({
      actorUid: actor.uid,
      operationType: "create_planned_meal",
      operationId: "key-plan-1",
    });
    assert.ok(store.has(pathNutritionOperation("dog-1", expectedReceipt)));
    assert.ok(writes.some((p) => p.startsWith("auditLogs/")));
    assert.ok(!writes.some((p) => /meal_logs\/[^/]+\/operations\//.test(p)));
    for (const w of writes) {
      assert.ok(!w.includes("feeding_events"));
      assert.ok(!w.includes("nutrition_supplements"));
    }
  });

  await test("planned same key → replay 0 plan dependency on retry", async () => {
    const harness = memoryDeps({plan: samplePlan()});
    const payload = plannedPayload("key-replay");
    await runCreatePlannedMealLog(actor, payload, harness.deps);
    // Remove plan entirely — replay must not need it
    harness.store.delete(harness.planPath);
    const audits1 = [...harness.store.keys()].filter((k) =>
      k.startsWith("auditLogs/"),
    );
    const r2 = await runCreatePlannedMealLog(actor, payload, harness.deps);
    assert.strictEqual(r2.wasNoOp, true);
    const audits2 = [...harness.store.keys()].filter((k) =>
      k.startsWith("auditLogs/"),
    );
    assert.strictEqual(audits2.length, audits1.length);
  });

  await test(
    "same occurrence different key same payload → no-op + new receipt",
    async () => {
      const {deps, store} = memoryDeps({plan: samplePlan()});
      const r1 = await runCreatePlannedMealLog(
        actor,
        plannedPayload("key-A"),
        deps,
      );
      const audits1 = [...store.keys()].filter((k) =>
        k.startsWith("auditLogs/"),
      );
      const r2 = await runCreatePlannedMealLog(
        actor,
        plannedPayload("key-B"),
        deps,
      );
      assert.strictEqual(r1.entityId, r2.entityId);
      assert.strictEqual(r2.wasNoOp, true);
      assert.strictEqual(
        [...store.keys()].filter((k) => k.startsWith("auditLogs/")).length,
        audits1.length,
      );
      const receiptB = nutritionOperationReceiptIdV1({
        actorUid: actor.uid,
        operationType: "create_planned_meal",
        operationId: "key-B",
      });
      assert.ok(store.has(pathNutritionOperation("dog-1", receiptB)));
    },
  );

  await test("same occurrence different payload → conflict", async () => {
    const {deps, store} = memoryDeps({plan: samplePlan()});
    await runCreatePlannedMealLog(actor, plannedPayload("key-A"), deps);
    const audits1 = [...store.keys()].filter((k) =>
      k.startsWith("auditLogs/"),
    );
    await assert.rejects(() =>
      runCreatePlannedMealLog(
        actor,
        plannedPayload("key-B", {
          offeredGrams: 250,
          acceptance: "partial",
          consumedGrams: 100,
        }),
        deps,
      ),
    );
    assert.strictEqual(
      [...store.keys()].filter((k) => k.startsWith("auditLogs/")).length,
      audits1.length,
    );
  });

  await test("adhoc + supplement durable registry", async () => {
    const {deps, store, writes} = memoryDeps({plan: samplePlan()});
    const ra = await runCreateAdhocMealLog(
      actor,
      {
        dogId: "dog-1",
        period: "morning",
        offeredGrams: 100,
        acceptance: "unknown",
        fedAt: "2026-07-18T10:00:00.000Z",
        idempotencyKey: "adhoc-1",
      },
      deps,
    );
    assert.ok(ra.entityId.startsWith("ml1_"));
    const rs = await runCreateSupplementLog(
      actor,
      {
        dogId: "dog-1",
        supplementName: "Omega 3",
        dose: 1000,
        unit: "mg",
        administeredAt: "2026-07-18T10:00:00.000Z",
        nutritionPlanId: "plan-1",
        supplementRegimenId: "reg-1",
        idempotencyKey: "sup-1",
      },
      deps,
    );
    assert.ok(rs.entityId.startsWith("sl1_"));
    assert.ok(writes.every((w) => !w.includes("nutrition_supplements")));
    assert.ok(
      store.has(
        pathNutritionOperation(
          "dog-1",
          nutritionOperationReceiptIdV1({
            actorUid: actor.uid,
            operationType: "create_adhoc_meal",
            operationId: "adhoc-1",
          }),
        ),
      ),
    );
  });

  await test("nutritionPlanId only (no regimen) → plan must exist", async () => {
    const {deps} = memoryDeps({plan: null});
    await assert.rejects(() =>
      runCreateSupplementLog(
        actor,
        {
          dogId: "dog-1",
          supplementName: "Omega",
          dose: 10,
          unit: "mg",
          administeredAt: "2026-07-18T10:00:00.000Z",
          nutritionPlanId: "missing-plan",
          idempotencyKey: "sup-plan-only",
        },
        deps,
      ),
    );
  });

  await test("superseded without validUntil → integrity", async () => {
    const {deps} = memoryDeps({
      plan: samplePlan({status: "superseded", valid_until: null}),
    });
    await assert.rejects(() =>
      runCreatePlannedMealLog(actor, plannedPayload("k-sup"), deps),
    );
  });

  await test("superseded covering fedAt → accept", async () => {
    const {deps} = memoryDeps({
      plan: samplePlan({
        status: "superseded",
        valid_from: "2026-01-01T00:00:00.000Z",
        valid_until: "2026-06-01T00:00:00.000Z",
      }),
    });
    const r = await runCreatePlannedMealLog(
      actor,
      {
        dogId: "dog-1",
        planId: "plan-1",
        plannedMealId: "slot-am",
        offeredGrams: 300,
        acceptance: "full",
        fedAt: "2026-03-01T10:00:00.000Z",
        idempotencyKey: "k-hist",
      },
      deps,
    );
    assert.strictEqual(r.wasNoOp, false);
  });

  await test("occurrence id matches engine document id", async () => {
    const {deps} = memoryDeps({
      plan: samplePlan(),
      serverNow: new Date("2026-07-19T12:00:00.000Z"),
    });
    const r = await runCreatePlannedMealLog(
      actor,
      {
        dogId: "dog-1",
        planId: "plan-1",
        plannedMealId: "slot-am",
        offeredGrams: 300,
        acceptance: "full",
        fedAt: "2026-07-19T02:30:00.000Z",
        idempotencyKey: "k-occ",
      },
      deps,
    );
    assert.strictEqual(
      r.entityId,
      mealOccurrenceIdV1({
        dogId: "dog-1",
        planId: "plan-1",
        plannedMealId: "slot-am",
        localServiceDate: "2026-07-18",
      }),
    );
  });

  await test("cross-actor same key same semantics → 2 receipts", async () => {
    const {deps, store} = memoryDeps({plan: samplePlan()});
    const payload = plannedPayload("save-1");
    const rA = await runCreatePlannedMealLog(actor, payload, deps);
    const rB = await runCreatePlannedMealLog(actorB, payload, deps);
    assert.strictEqual(rB.wasNoOp, true);
    assert.strictEqual(rA.entityId, rB.entityId);
    assert.ok(
      store.has(
        pathNutritionOperation(
          "dog-1",
          nutritionOperationReceiptIdV1({
            actorUid: actor.uid,
            operationType: "create_planned_meal",
            operationId: "save-1",
          }),
        ),
      ),
    );
    assert.ok(
      store.has(
        pathNutritionOperation(
          "dog-1",
          nutritionOperationReceiptIdV1({
            actorUid: actorB.uid,
            operationType: "create_planned_meal",
            operationId: "save-1",
          }),
        ),
      ),
    );
  });

  await test(
    "cross-actor different payload → meal_occurrence_conflict",
    async () => {
      const {deps} = memoryDeps({plan: samplePlan()});
      await runCreatePlannedMealLog(actor, plannedPayload("save-1"), deps);
      try {
        await runCreatePlannedMealLog(
          actorB,
          plannedPayload("save-1", {
            offeredGrams: 250,
            acceptance: "partial",
            consumedGrams: 100,
          }),
          deps,
        );
        assert.fail("expected conflict");
      } catch (e) {
        const err = e as Error & {detailCode?: string; appCode?: string};
        assert.notStrictEqual(err.appCode, "idempotency-conflict");
        assert.strictEqual(err.detailCode, "meal_occurrence_conflict");
      }
    },
  );

  await test("authoritative drift → conflict", async () => {
    const {deps, store} = memoryDeps({plan: samplePlan()});
    const r = await runCreatePlannedMealLog(
      actor,
      plannedPayload("k-auth"),
      deps,
    );
    const mealPath = `dogs/dog-1/meal_logs/${r.entityId}`;
    const meal = store.get(mealPath)!;
    meal.scheduled_for = "2026-07-18T11:00:00.000Z";
    meal.entity_semantic_fingerprint = undefined;
    store.set(mealPath, meal);
    try {
      await runCreatePlannedMealLog(actor, plannedPayload("k-auth-2"), deps);
      assert.fail("expected conflict");
    } catch (e) {
      assert.strictEqual(
        (e as Error & {detailCode?: string}).detailCode,
        "meal_occurrence_conflict",
      );
    }
  });

  await test("same actor same key different fingerprint → idempotency", async () => {
    const {deps} = memoryDeps({plan: samplePlan()});
    await runCreatePlannedMealLog(actor, plannedPayload("same-key"), deps);
    try {
      await runCreatePlannedMealLog(
        actor,
        plannedPayload("same-key", {
          offeredGrams: 200,
          acceptance: "partial",
          consumedGrams: 50,
        }),
        deps,
      );
      assert.fail("expected idempotency conflict");
    } catch (e) {
      assert.strictEqual(
        (e as Error & {appCode?: string}).appCode,
        "idempotency-conflict",
      );
    }
  });

  // ── Durable replay (receipt-first) ─────────────────────────────────────────

  await test("replay after plan cancelled → success", async () => {
    const harness = memoryDeps({plan: samplePlan()});
    const payload = plannedPayload("retry-cancel");
    await runCreatePlannedMealLog(actor, payload, harness.deps);
    harness.store.set(harness.planPath, samplePlan({status: "cancelled"}));
    const r2 = await runCreatePlannedMealLog(actor, payload, harness.deps);
    assert.strictEqual(r2.wasNoOp, true);
  });

  await test("replay after plan removed → success", async () => {
    const harness = memoryDeps({plan: samplePlan()});
    const payload = plannedPayload("retry-gone");
    await runCreatePlannedMealLog(actor, payload, harness.deps);
    harness.store.delete(harness.planPath);
    const r2 = await runCreatePlannedMealLog(actor, payload, harness.deps);
    assert.strictEqual(r2.wasNoOp, true);
  });

  // ── TOCTOU: plan validation inside transaction ─────────────────────────────

  await test(
    "TOCTOU active→cancelled before txn read → reject, zero writes",
    async () => {
      const harness = memoryDeps({
        plan: samplePlan(),
        beforeTransaction: (store) => {
          store.set(
            pathNutritionPlan("dog-1", "plan-1"),
            samplePlan({status: "cancelled"}),
          );
        },
      });
      const writesBefore = harness.writes.length;
      try {
        await runCreatePlannedMealLog(
          actor,
          plannedPayload("toctou-cancel"),
          harness.deps,
        );
        assert.fail("expected cancelled");
      } catch (e) {
        assert.strictEqual(
          (e as Error & {detailCode?: string}).detailCode,
          "nutrition_plan_cancelled",
        );
      }
      // Failure: no success writes of meal/receipt/audit after hook
      const newWrites = harness.writes.slice(writesBefore);
      assert.ok(!newWrites.some((w) => w.includes("/meal_logs/")));
      assert.ok(!newWrites.some((w) => w.includes("/nutrition_operations/")));
      assert.ok(!newWrites.some((w) => w.startsWith("auditLogs/")));
    },
  );

  await test(
    "TOCTOU active→superseded covering fedAt → accept",
    async () => {
      const harness = memoryDeps({
        plan: samplePlan(),
        beforeTransaction: (store) => {
          store.set(
            pathNutritionPlan("dog-1", "plan-1"),
            samplePlan({
              status: "superseded",
              valid_from: "2026-01-01T00:00:00.000Z",
              valid_until: "2026-12-31T00:00:00.000Z",
            }),
          );
        },
      });
      const r = await runCreatePlannedMealLog(
        actor,
        plannedPayload("toctou-super-ok"),
        harness.deps,
      );
      assert.strictEqual(r.wasNoOp, false);
    },
  );

  await test(
    "TOCTOU active→superseded excluding fedAt → reject",
    async () => {
      const harness = memoryDeps({
        plan: samplePlan(),
        beforeTransaction: (store) => {
          store.set(
            pathNutritionPlan("dog-1", "plan-1"),
            samplePlan({
              status: "superseded",
              valid_from: "2026-01-01T00:00:00.000Z",
              valid_until: "2026-07-01T00:00:00.000Z",
            }),
          );
        },
      });
      try {
        await runCreatePlannedMealLog(
          actor,
          plannedPayload("toctou-super-bad"),
          harness.deps,
        );
        assert.fail("expected not effective");
      } catch (e) {
        assert.strictEqual(
          (e as Error & {detailCode?: string}).detailCode,
          "nutrition_plan_not_effective_at_fed_at",
        );
      }
    },
  );

  await test("TOCTOU slot removed before txn → planned_meal_not_found", async () => {
    const harness = memoryDeps({
      plan: samplePlan(),
      beforeTransaction: (store) => {
        store.set(
          pathNutritionPlan("dog-1", "plan-1"),
          samplePlan({
            meal_schedule: [
              {
                id: "other-slot",
                period: "night",
                scheduled_time: "19:00",
                target_grams: 300,
              },
            ],
          }),
        );
      },
    });
    try {
      await runCreatePlannedMealLog(
        actor,
        plannedPayload("toctou-slot"),
        harness.deps,
      );
      assert.fail("expected slot missing");
    } catch (e) {
      assert.strictEqual(
        (e as Error & {detailCode?: string}).detailCode,
        "planned_meal_not_found",
      );
    }
  });

  await test(
    "TOCTOU linked regimen disappears before txn → reject",
    async () => {
      const harness = memoryDeps({
        plan: samplePlan(),
        beforeTransaction: (store) => {
          store.set(
            pathNutritionPlan("dog-1", "plan-1"),
            samplePlan({supplements: [{id: "other-reg"}]}),
          );
        },
      });
      try {
        await runCreateSupplementLog(
          actor,
          {
            dogId: "dog-1",
            supplementName: "Omega",
            dose: 10,
            unit: "mg",
            administeredAt: "2026-07-18T10:00:00.000Z",
            nutritionPlanId: "plan-1",
            supplementRegimenId: "reg-1",
            idempotencyKey: "toctou-reg",
          },
          harness.deps,
        );
        assert.fail("expected regimen missing");
      } catch (e) {
        assert.strictEqual(
          (e as Error & {detailCode?: string}).detailCode,
          "supplement_regimen_not_found",
        );
      }
    },
  );

  await test("sequential double-submit: 1 meal 1 audit 1 receipt", async () => {
    const {deps, store} = memoryDeps({plan: samplePlan()});
    const payload = plannedPayload("double-submit");
    await runCreatePlannedMealLog(actor, payload, deps);
    await runCreatePlannedMealLog(actor, payload, deps);
    assert.strictEqual(
      [...store.keys()].filter((k) =>
        /^dogs\/dog-1\/meal_logs\/[^/]+$/.test(k),
      ).length,
      1,
    );
    assert.strictEqual(
      [...store.keys()].filter((k) => k.startsWith("auditLogs/")).length,
      1,
    );
    assert.strictEqual(
      [...store.keys()].filter((k) =>
        k.includes("/nutrition_operations/"),
      ).length,
      1,
    );
  });

  console.log("\nhealth_nutrition_engine_test: all passed");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
