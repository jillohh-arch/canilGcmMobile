/**
 * Testes dos handlers Nutrition callables (fake Firestore + engine memory).
 * npm run build && node lib/health_nutrition_callables_test.js
 */
import * as assert from "assert";
import {
  runHealthNutritionCreateMealLog,
  runHealthNutritionCreateSupplementLog,
  runHealthNutritionCreateAndActivatePlan,
  runHealthNutritionUpdateActivePlan,
  runHealthNutritionCancelPlan,
  HealthNutritionCallableDeps,
  mapNutritionError,
} from "./health_nutrition_callables";
import {
  NutritionActor,
  NutritionEngineDeps,
  NutritionTxn,
  pathNutritionOperation,
  pathNutritionPlan,
} from "./health_nutrition_engine";
import {
  mealOccurrenceIdV1,
  nutritionError,
  nutritionOperationReceiptIdV1,
} from "./health_nutrition_logic";

type JsonMap = Record<string, unknown>;

const actor: NutritionActor = {
  uid: "uid-op",
  email: "691755@gcm.com.br",
  ra: "691755",
  name: "Operador",
};

function createFakeDb(initial: Record<string, JsonMap> = {}) {
  const store = new Map<string, JsonMap>();
  for (const [k, v] of Object.entries(initial)) {
    store.set(k, {...v});
  }

  function pathOf(parts: string[]): string {
    return parts.join("/");
  }

  function makeDocRef(parts: string[]) {
    const path = pathOf(parts);
    return {
      path,
      id: parts[parts.length - 1],
      collection(c: string) {
        return {
          doc(id: string) {
            return makeDocRef([...parts, c, id]);
          },
        };
      },
      async get() {
        const data = store.get(path);
        return {
          exists: data !== undefined,
          data: () => ({...(data ?? {})}),
        };
      },
    };
  }

  const db = {
    collection(col: string) {
      return {
        doc(id?: string) {
          const docId = id ?? `auto_${store.size + 1}`;
          return makeDocRef([col, docId]);
        },
      };
    },
    async runTransaction<T>(
      fn: (tx: {
        get: (ref: {path: string}) => Promise<{exists: boolean; data: () => JsonMap}>;
        set: (ref: {path: string}, data: JsonMap) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const pending = new Map<string, JsonMap>();
      const tx = {
        async get(ref: {path: string}) {
          const data = pending.get(ref.path) ?? store.get(ref.path);
          return {
            exists: data !== undefined,
            data: () => ({...(data ?? {})}),
          };
        },
        set(ref: {path: string}, data: JsonMap) {
          pending.set(ref.path, {...data});
        },
      };
      const result = await fn(tx);
      for (const [k, v] of pending.entries()) {
        store.set(k, v);
      }
      return result;
    },
    _store: store,
  };

  return db as unknown as FirebaseFirestore.Firestore & {
    _store: Map<string, JsonMap>;
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mockRequest(data: JsonMap, auth: any): any {
  return {data, auth};
}

function samplePlan(): JsonMap {
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
  };
}

function memoryEngineFactory(store: Map<string, JsonMap>, serverNow: Date) {
  return (opts: {
    isAdmin: (a: NutritionActor) => boolean | Promise<boolean>;
  }): NutritionEngineDeps => {
    const read = (path: string) => {
      const data = store.get(path);
      return {exists: data !== undefined, data: data ?? {}};
    };
    return {
      serverNow: () => serverNow,
      isAdmin: opts.isAdmin,
      getDoc: async (path: string) => read(path),
      runTransaction: async <T>(fn: (tx: NutritionTxn) => Promise<T>) => {
        const pending = new Map<string, JsonMap>();
        const tx: NutritionTxn = {
          get: async (path: string) => {
            const data = pending.get(path) ?? store.get(path);
            return {exists: data !== undefined, data: {...(data ?? {})}};
          },
          set: (path: string, data: JsonMap) => {
            pending.set(path, {...data});
          },
          getActivePlans: async (dogId: string) => [...store.entries()]
            .filter(([path, data]) => path.startsWith(`dogs/${dogId}/nutrition_plans/`) && data.status === "active")
            .map(([path, data]) => ({id: path.split("/").pop()!, data})),
          getMealLogsInWindow: async () => [],
          getSupplementLogsInWindow: async () => [],
        };
        const result = await fn(tx);
        for (const [k, v] of pending.entries()) {
          store.set(k, v);
        }
        return result;
      },
    };
  };
}

function depsFor(options: {
  db: FirebaseFirestore.Firestore & {_store: Map<string, JsonMap>};
  allowCreate?: boolean;
  allowManage?: boolean;
  dogAccess?: boolean;
  admin?: boolean;
  caller?: NutritionActor;
  serverNow?: Date;
}): HealthNutritionCallableDeps {
  const caller = options.caller ?? actor;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const {HttpsError} = require("firebase-functions/v2/https");
  const store = options.db._store;
  const serverNow =
    options.serverNow ?? new Date("2026-07-18T15:00:00.000Z");
  return {
    db: options.db,
    requireHealthCreate: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowCreate === false) {
        throw new HttpsError("permission-denied", "no create", {
          code: "permission-denied",
        });
      }
      return caller;
    },
    requireManageNutritionPlan: async (auth) => {
      if (!auth) throw new HttpsError("unauthenticated", "auth");
      if (options.allowManage === false) {
        throw new HttpsError("permission-denied", "no manage", {code: "permission-denied"});
      }
      return caller;
    },
    requireDogAccess: async () => {
      if (options.dogAccess === false) {
        throw new HttpsError("permission-denied", "no dog", {
          code: "permission-denied",
        });
      }
    },
    isAdministrativeAuthority: async () => options.admin === true,
    createEngineDeps: memoryEngineFactory(store, serverNow),
  };
}

function countByPrefix(store: Map<string, JsonMap>, prefix: string): number {
  let n = 0;
  for (const path of store.keys()) {
    if (path.startsWith(prefix)) n++;
  }
  return n;
}

function countAudit(store: Map<string, JsonMap>): number {
  return countByPrefix(store, "auditLogs/");
}

function countLegacy(store: Map<string, JsonMap>): number {
  let n = 0;
  for (const path of store.keys()) {
    if (
      path.includes("/feeding_events/") ||
      path.includes("/feedings/") ||
      path.includes("/nutritional_prescriptions/") ||
      path.includes("/nutrition_prescriptions/") ||
      path.includes("/nutrition_supplements/")
    ) {
      n++;
    }
  }
  return n;
}

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

async function main(): Promise<void> {
  await test("meal unauthenticated → unauthenticated", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest({mode: "planned", dog_id: "dog-1"}, null),
          depsFor({db, allowCreate: true}),
        ),
      (e: {code?: string}) => e.code === "unauthenticated",
    );
  });

  await test("meal permission denied health.create", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {mode: "planned", dog_id: "dog-1"},
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: false}),
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );
  });

  await test("meal dog access denied", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: "dog-1",
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "op-denydog",
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: false}),
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );
  });

  await test("planned payload success + response contract", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: "dog-1",
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          consumed_grams: 300,
          acceptance: "full",
          fed_at: "2026-07-10T10:00:00.000Z",
          operation_id: "op-planned-1",
        },
        auth,
      ),
      deps,
    );
    assert.strictEqual(r.was_no_op, false);
    assert.strictEqual(r.wasNoOp, false);
    assert.ok(typeof r.meal_id === "string");
    assert.ok(String(r.meal_id).startsWith("mo1_"));
    assert.strictEqual(r.meal_id, r.meal_occurrence_id);
    assert.strictEqual(r.revision, 1);
    assert.strictEqual(countByPrefix(db._store, "dogs/dog-1/meal_logs/"), 1);
    assert.strictEqual(
      countByPrefix(db._store, "dogs/dog-1/nutrition_operations/"),
      1,
    );
    assert.strictEqual(countAudit(db._store), 1);
    assert.strictEqual(countLegacy(db._store), 0);
  });

  await test("mode missing → validation", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {dog_id: "dog-1", operation_id: "x"},
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: true}),
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "invalid-argument",
    );
  });

  await test("server-authoritative field injection rejected", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "adhoc",
              dog_id: "dog-1",
              period: "morning",
              offered_grams: 100,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "inj-1",
              recorded_by: {uid: "evil"},
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: true}),
        ),
      (e: {code?: string}) => e.code === "invalid-argument",
    );
  });

  await test("planned rejects period injection", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: "dog-1",
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "period-inj",
              period: "evening",
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: true}),
        ),
      (e: {code?: string}) => e.code === "invalid-argument",
    );
  });

  await test("adhoc success", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    const r = await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "adhoc",
          dog_id: "dog-1",
          period: "extra",
          offered_grams: 150,
          acceptance: "partial",
          consumed_grams: 80,
          fed_at: "2026-07-10T18:00:00.000Z",
          operation_id: "adhoc-1",
        },
        {uid: actor.uid, token: {}},
      ),
      depsFor({db, allowCreate: true, dogAccess: true}),
    );
    assert.strictEqual(r.was_no_op, false);
    assert.ok(String(r.meal_id).startsWith("ml1_"));
    assert.strictEqual(r.meal_occurrence_id, null);
    const meal = [...db._store.entries()].find(([p]) =>
      p.includes("/meal_logs/"),
    );
    assert.ok(meal);
    assert.strictEqual(meal![1].plan_id, null);
    assert.strictEqual(meal![1].meal_occurrence_id, null);
  });

  await test("supplement success + dose string rejected", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "Rex"}});
    await assert.rejects(
      () =>
        runHealthNutritionCreateSupplementLog(
          mockRequest(
            {
              dog_id: "dog-1",
              supplement_name: "Omega",
              dose: "10mg",
              unit: "mg",
              administered_at: "2026-07-10T12:00:00.000Z",
              operation_id: "supp-str",
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: true}),
        ),
      (e: {code?: string}) => e.code === "invalid-argument",
    );

    const r = await runHealthNutritionCreateSupplementLog(
      mockRequest(
        {
          dog_id: "dog-1",
          supplement_name: "Omega",
          dose: 10,
          unit: "mg",
          administered_at: "2026-07-10T12:00:00.000Z",
          operation_id: "supp-1",
        },
        {uid: actor.uid, token: {}},
      ),
      depsFor({db, allowCreate: true, dogAccess: true}),
    );
    assert.strictEqual(r.was_no_op, false);
    assert.ok(String(r.supplement_log_id).startsWith("sl1_"));
  });

  await test("replay was_no_op + no second audit", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    const payload = {
      mode: "planned",
      dog_id: "dog-1",
      plan_id: "plan-1",
      planned_meal_id: "slot-am",
      offered_grams: 300,
      acceptance: "full",
      fed_at: "2026-07-10T10:00:00.000Z",
      operation_id: "op-replay",
    };
    const r1 = await runHealthNutritionCreateMealLog(
      mockRequest(payload, auth),
      deps,
    );
    const r2 = await runHealthNutritionCreateMealLog(
      mockRequest(payload, auth),
      deps,
    );
    assert.strictEqual(r1.was_no_op, false);
    assert.strictEqual(r2.was_no_op, true);
    assert.strictEqual(r1.meal_id, r2.meal_id);
    assert.strictEqual(countAudit(db._store), 1);
    assert.strictEqual(countByPrefix(db._store, "dogs/dog-1/meal_logs/"), 1);
  });

  await test("idempotency conflict mapping", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: "dog-1",
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: "2026-07-10T10:00:00.000Z",
          operation_id: "op-idem",
        },
        auth,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: "dog-1",
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 250,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "op-idem",
            },
            auth,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "failed-precondition" &&
        (e.details?.code === "idempotency_conflict" ||
          e.details?.code === "idempotency-conflict"),
    );
  });

  await test("engine conflict → failed-precondition + detail", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    const deps = depsFor({db, allowCreate: true, dogAccess: true});
    const auth = {uid: actor.uid, token: {}};
    const fedAt = "2026-07-10T10:00:00.000Z";
    await runHealthNutritionCreateMealLog(
      mockRequest(
        {
          mode: "planned",
          dog_id: "dog-1",
          plan_id: "plan-1",
          planned_meal_id: "slot-am",
          offered_grams: 300,
          acceptance: "full",
          fed_at: fedAt,
          operation_id: "op-a",
        },
        auth,
      ),
      deps,
    );
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: "dog-1",
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 200,
              acceptance: "partial",
              consumed_grams: 100,
              fed_at: fedAt,
              operation_id: "op-b",
            },
            auth,
          ),
          deps,
        ),
      (e: {code?: string; details?: {code?: string}}) =>
        e.code === "failed-precondition" &&
        e.details?.code === "meal_occurrence_conflict",
    );
  });

  await test("mapNutritionError preserves detailCode", async () => {
    try {
      mapNutritionError(
        nutritionError(
          "failed-precondition",
          "plano cancelado",
          "nutrition_plan_cancelled",
        ),
      );
      assert.fail("expected throw");
    } catch (e) {
      const err = e as {code?: string; details?: {code?: string}};
      assert.strictEqual(err.code, "failed-precondition");
      assert.strictEqual(err.details?.code, "nutrition_plan_cancelled");
    }
  });

  await test("auth order: no engine without dog access (no writes)", async () => {
    const db = createFakeDb({
      "dogs/dog-1": {name: "Rex"},
      [pathNutritionPlan("dog-1", "plan-1")]: samplePlan(),
    });
    await assert.rejects(
      () =>
        runHealthNutritionCreateMealLog(
          mockRequest(
            {
              mode: "planned",
              dog_id: "dog-1",
              plan_id: "plan-1",
              planned_meal_id: "slot-am",
              offered_grams: 300,
              acceptance: "full",
              fed_at: "2026-07-10T10:00:00.000Z",
              operation_id: "op-order",
            },
            {uid: actor.uid, token: {}},
          ),
          depsFor({db, allowCreate: true, dogAccess: false}),
        ),
      (e: {code?: string}) => e.code === "permission-denied",
    );
    assert.strictEqual(countByPrefix(db._store, "dogs/dog-1/meal_logs/"), 0);
    assert.strictEqual(
      countByPrefix(db._store, "dogs/dog-1/nutrition_operations/"),
      0,
    );
  });

  // receipt id path sanity for planned occurrence id equality
  await test("occurrence id equals meal id (engine contract)", async () => {
    const occurrence = mealOccurrenceIdV1({
      dogId: "dog-1",
      planId: "plan-1",
      plannedMealId: "slot-am",
      localServiceDate: "2026-07-10",
    });
    assert.ok(occurrence.startsWith("mo1_"));
    const rid = nutritionOperationReceiptIdV1({
      actorUid: actor.uid,
      operationType: "create_planned_meal",
      operationId: "x",
    });
    assert.ok(rid.startsWith("nr1_"));
    assert.ok(pathNutritionOperation("dog-1", rid).includes("nutrition_operations"));
  });

  const planCreate = (operationId: string) => ({dogId: "dog-1", operationId, planData: {
    food_type: "Ração", amount_grams_per_day: 300, meals_per_day: 1,
    timezone: "America/Sao_Paulo", valid_from: "2026-07-18T14:00:00.000Z",
    meal_schedule: [{id: "slot", period: "morning", scheduled_time: "07:00", target_grams: 300}],
  }});

  await test("plan callable unauthenticated", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "K9"}});
    await assert.rejects(() => runHealthNutritionCreateAndActivatePlan(mockRequest(planCreate("p-auth"), undefined),
      depsFor({db})), (e: {code?: string}) => e.code === "unauthenticated");
  });
  await test("plan callable requires health.manage_nutrition_plan", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "K9"}});
    await assert.rejects(() => runHealthNutritionCreateAndActivatePlan(mockRequest(planCreate("p-denied"),
      {uid: actor.uid, token: {}}), depsFor({db, allowManage: false})),
    (e: {code?: string}) => e.code === "permission-denied");
  });
  await test("plan callable requires dog access", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "K9"}});
    await assert.rejects(() => runHealthNutritionCreateAndActivatePlan(mockRequest(planCreate("p-dog"),
      {uid: actor.uid, token: {}}), depsFor({db, dogAccess: false})),
    (e: {code?: string}) => e.code === "permission-denied");
  });
  await test("plan create/update/cancel callable success contracts", async () => {
    const db = createFakeDb({"dogs/dog-1": {name: "K9"}});
    const deps = depsFor({db, allowManage: true, dogAccess: true, admin: true});
    const created = await runHealthNutritionCreateAndActivatePlan(mockRequest(planCreate("p-create"),
      {uid: actor.uid, token: {}}), deps);
    assert.strictEqual(created.status, "active");
    const planId = created.planId as string;
    const updated = await runHealthNutritionUpdateActivePlan(mockRequest({dogId: "dog-1", planId,
      operationId: "p-update", expectedRevision: 1, planData: {special_instructions: "nova"}},
    {uid: actor.uid, token: {}}), deps);
    assert.strictEqual(updated.revision, 2);
    const cancelled = await runHealthNutritionCancelPlan(mockRequest({dogId: "dog-1", planId,
      operationId: "p-cancel", expectedRevision: 2, reason: "clínico"},
    {uid: actor.uid, token: {}}), deps);
    assert.strictEqual(cancelled.status, "cancelled");
  });

  console.log("\nAll health_nutrition_callables tests passed.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
