import * as assert from "assert";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  runCreateWeightRecord,
  WeightEngineDeps,
  WeightEngineError,
  WeightTxDocSnap,
  WeightTxn,
} from "./health_weight_engine";
import {WeightCaller} from "./health_weight_logic";
import {
  buildHealthWeightCreateRecordHandler,
  HealthWeightCallableDeps,
  mapWeightError,
} from "./health_weight_callables";

type Store = Map<string, Record<string, unknown>>;

function createFakeEngineDeps(store: Store): WeightEngineDeps {
  let counter = 100;
  return {
    runTransaction: async <T>(
      fn: (txn: WeightTxn) => Promise<T>
    ): Promise<T> => {
      const localStore = new Map<string, Record<string, unknown>>();
      for (const [k, v] of store.entries()) {
        localStore.set(k, structuredClone(v));
      }

      const pendingWrites: Array<{
        path: string;
        data: Record<string, unknown>;
        merge?: boolean;
      }> = [];

      const txn: WeightTxn = {
        get: async (path: string): Promise<WeightTxDocSnap> => {
          const val = localStore.get(path);
          return {
            exists: val !== undefined,
            data: val ? structuredClone(val) : undefined,
          };
        },
        set: (path: string, data: Record<string, unknown>, options?: {merge?: boolean}) => {
          pendingWrites.push({path, data: structuredClone(data), merge: options?.merge});
          if (options?.merge && localStore.has(path)) {
            localStore.set(path, {...localStore.get(path), ...structuredClone(data)});
          } else {
            localStore.set(path, structuredClone(data));
          }
        },
      };

      const result = await fn(txn);

      for (const write of pendingWrites) {
        if (write.merge && store.has(write.path)) {
          store.set(write.path, {...store.get(write.path), ...write.data});
        } else {
          store.set(write.path, write.data);
        }
      }

      return result;
    },
    createEntityId: () => `id_${++counter}`,
    serverTimestamp: () => "2026-08-04T12:00:00.000Z",
    arrayUnion: (...items: unknown[]) => items,
    timestampFromDate: (d: Date) => ({_seconds: Math.floor(d.getTime() / 1000), _nanoseconds: 0}),
  };
}

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`FAIL - ${name}`, err);
    process.exitCode = 1;
  }
}

const mockActor: WeightCaller = {
  uid: "usr_123",
  ra: "GCM-12345",
  name: "GCM Ragonha",
  internalRole: "condutor",
};

const validPayload = {
  dogId: "dog_a",
  operationId: "op_handler",
  payload: {
    weightKg: 29.5,
    measuredAt: "2026-08-04T10:00:00Z",
  },
};

function callableRequest(data = validPayload): CallableRequest {
  return {
    auth: {uid: "usr_123", token: {}},
    data,
  } as CallableRequest;
}

function handlerDeps(options: {
  capabilityAllowed?: boolean;
  dogAccessAllowed?: boolean;
  engineRuns: {count: number};
}): HealthWeightCallableDeps {
  const store: Store = new Map([["dogs/dog_a", {name: "Bono"}]]);
  const db = {
    collection: (collection: string) => ({
      doc: (id: string) => ({
        get: async () => ({
          exists: collection === "dogs" && id === "dog_a",
          data: () => ({name: "Bono"}),
        }),
      }),
    }),
  } as unknown as HealthWeightCallableDeps["db"];
  return {
    db,
    requireHealthRecordRoutine: async () => {
      if (options.capabilityAllowed === false) {
        throw new HttpsError("permission-denied", "capability denied");
      }
      return mockActor;
    },
    requireDogAccess: async () => {
      if (options.dogAccessAllowed === false) {
        throw new HttpsError("permission-denied", "dog access denied");
      }
    },
    createEngineDeps: () => {
      options.engineRuns.count += 1;
      return createFakeEngineDeps(store);
    },
  };
}

async function main() {
  await test("1. Criação canônica: measured_at é Timestamp, recorded_by completo sem PII, campos legados e revision removidos de weight_records", async () => {
    const store: Store = new Map();
    store.set("dogs/dog_a", {name: "Bono", breed: "Malinois"});
    const deps = createFakeEngineDeps(store);

    const res = await runCreateWeightRecord({
      deps,
      actor: mockActor,
      rawPayload: {
        dogId: "dog_a",
        operationId: "op_001",
        weightKg: 29.5,
        measuredAt: "2026-08-04T10:00:00Z",
        context: "routine",
        notes: "Pesagem mensal ok",
      },
    });

    assert.strictEqual(res.dogId, "dog_a");
    assert.strictEqual(res.weightKg, 29.5);
    assert.strictEqual(res.revision, 1);
    assert.strictEqual(res.wasNoOp, false);
    assert.strictEqual(res.entityId, "id_101");

    const record = store.get("dogs/dog_a/weight_records/id_101")!;
    assert.strictEqual(record.weight_kg, 29.5);
    assert.strictEqual(record.context, "routine");
    assert.strictEqual(record.notes, "Pesagem mensal ok");
    assert.strictEqual(record.schema_version, 1);

    // Persistido como Timestamp (não string ISO)
    assert.strictEqual(typeof (record.measured_at as any)._seconds, "number");

    // Confirma recorded_by canônico (uid, name, internal_role) sem PII
    const recordedBy = record.recorded_by as any;
    assert.strictEqual(recordedBy.uid, "usr_123");
    assert.strictEqual(recordedBy.name, "GCM Ragonha");
    assert.strictEqual(recordedBy.internal_role, "condutor");
    assert.strictEqual(recordedBy.email, undefined);

    // Confirma remoção de campos legados desnecessários da entidade
    assert.strictEqual(record.measured_by, undefined);
    assert.strictEqual(record.performed_by, undefined);
    assert.strictEqual(record.revision, undefined);

    // Confirma denormalização do cão como Timestamp
    const dog = store.get("dogs/dog_a")!;
    assert.strictEqual(dog.weight, 29.5);
    assert.strictEqual(dog._last_weight_kg, 29.5);
    assert.strictEqual(typeof (dog._last_weight_at as any)._seconds, "number");
  });

  await test("2. Contexto e notas opcionais: ausentes são omitidos do documento; presente valida enums", async () => {
    const store: Store = new Map();
    store.set("dogs/dog_a", {name: "Bono"});
    const deps = createFakeEngineDeps(store);

    // Sem contexto nem notas -> campos omitidos
    const resNoCtx = await runCreateWeightRecord({
      deps,
      actor: mockActor,
      rawPayload: {
        dogId: "dog_a",
        operationId: "op_no_ctx",
        weightKg: 28.0,
        measuredAt: "2026-08-04T10:00:00Z",
      },
    });

    const recNoCtx = store.get(`dogs/dog_a/weight_records/${resNoCtx.entityId}`)!;
    assert.strictEqual("context" in recNoCtx, false, "campo context deve ser omitido quando ausente");
    assert.strictEqual("notes" in recNoCtx, false, "campo notes deve ser omitido quando ausente");

    // Rejeita contexto legado (ex: 'canil', 'casa')
    await assert.rejects(
      async () => {
        await runCreateWeightRecord({
          deps,
          actor: mockActor,
          rawPayload: {
            dogId: "dog_a",
            operationId: "op_legacy_ctx",
            weightKg: 28.0,
            measuredAt: "2026-08-04T10:00:00Z",
            context: "canil",
          },
        });
      },
      (err: any) => err instanceof WeightEngineError && err.httpCode === "invalid-argument"
    );
  });

  await test("3. Fingerprint distingue ausência de contexto de context='routine'; Replay determinístico", async () => {
    const store: Store = new Map();
    store.set("dogs/dog_a", {name: "Bono"});
    const deps = createFakeEngineDeps(store);

    const baseNoCtx = {
      dogId: "dog_a",
      operationId: "op_fingerprint_001",
      weightKg: 28.5,
      measuredAt: "2026-08-04T11:00:00Z",
    };

    // 1ª chamada sem contexto -> SUCESSO
    const res1 = await runCreateWeightRecord({deps, actor: mockActor, rawPayload: baseNoCtx});
    assert.strictEqual(res1.wasNoOp, false);

    // Replay sem contexto -> REPLAY (wasNoOp = true)
    const resReplay = await runCreateWeightRecord({deps, actor: mockActor, rawPayload: baseNoCtx});
    assert.strictEqual(resReplay.wasNoOp, true);
    assert.strictEqual(resReplay.entityId, res1.entityId);

    // Mesmo operationId mas alterando para context='routine' -> CONFLITO DE IDEMPOTÊNCIA
    await assert.rejects(
      async () => {
        await runCreateWeightRecord({
          deps,
          actor: mockActor,
          rawPayload: {...baseNoCtx, context: "routine"},
        });
      },
      (err: any) => err instanceof WeightEngineError && err.httpCode === "failed-precondition"
    );
  });

  await test("4. Sanitização de erro interno e wiring de capability", async () => {
    try {
      mapWeightError(new Error("Internal details password=secret"));
    } catch (err: any) {
      assert.strictEqual(err.code, "internal");
      assert.strictEqual(err.message, "Erro interno no processamento da pesagem.");
      assert.strictEqual(err.message.includes("secret"), false);
    }
  });

  await test("5. Precisão de fingerprint reconciliada (canônica, sem arredondamento silencioso)", async () => {
    const store: Store = new Map();
    store.set("dogs/dog_a", {name: "Bono"});
    const deps = createFakeEngineDeps(store);

    // 1. Mesmo número lógico produz mesmo fingerprint & 2. 29.5 e 29.50 são equivalentes após parsing numérico
    const p1 = {dogId: "dog_a", operationId: "op_prec_1", weightKg: 29.5, measuredAt: "2026-08-04T10:00:00Z"};
    const p2 = {dogId: "dog_a", operationId: "op_prec_1", weightKg: 29.50, measuredAt: "2026-08-04T10:00:00Z"};

    const res1 = await runCreateWeightRecord({deps, actor: mockActor, rawPayload: p1});
    assert.strictEqual(res1.wasNoOp, false);

    const res2 = await runCreateWeightRecord({deps, actor: mockActor, rawPayload: p2});
    assert.strictEqual(res2.wasNoOp, true);
    assert.strictEqual(res2.entityId, res1.entityId);

    // 3. Valores realmente diferentes não produzem replay (29.5 vs 29.6 com op_prec_2)
    const store3: Store = new Map();
    store3.set("dogs/dog_a", {name: "Bono"});
    const deps3 = createFakeEngineDeps(store3);

    await runCreateWeightRecord({deps: deps3, actor: mockActor, rawPayload: {dogId: "dog_a", operationId: "op_prec_2", weightKg: 29.5, measuredAt: "2026-08-04T10:00:00Z"}});
    await assert.rejects(
      async () => {
        await runCreateWeightRecord({deps: deps3, actor: mockActor, rawPayload: {dogId: "dog_a", operationId: "op_prec_2", weightKg: 29.6, measuredAt: "2026-08-04T10:00:00Z"}});
      },
      (err: any) => err instanceof WeightEngineError && err.httpCode === "failed-precondition"
    );

    // 4. Mesmo operationId com diferença além da segunda casa decimal (29.523 vs 29.524) NÃO pode ser aceito silenciosamente como replay
    const store4: Store = new Map();
    store4.set("dogs/dog_a", {name: "Bono"});
    const deps4 = createFakeEngineDeps(store4);

    await runCreateWeightRecord({deps: deps4, actor: mockActor, rawPayload: {dogId: "dog_a", operationId: "op_prec_3", weightKg: 29.523, measuredAt: "2026-08-04T10:00:00Z"}});
    await assert.rejects(
      async () => {
        await runCreateWeightRecord({deps: deps4, actor: mockActor, rawPayload: {dogId: "dog_a", operationId: "op_prec_3", weightKg: 29.524, measuredAt: "2026-08-04T10:00:00Z"}});
      },
      (err: any) => err instanceof WeightEngineError && err.httpCode === "failed-precondition"
    );

    // 5. Peso persistido corresponde exatamente ao peso usado no fingerprint (ex: 29.523)
    const record = store4.get(`dogs/dog_a/weight_records/id_101`)!;
    assert.strictEqual(record.weight_kg, 29.523);
  });

  await test("6. internal_role canonico persiste condutor e admin, nunca profile ID", async () => {
    const store: Store = new Map([["dogs/dog_a", {name: "Bono"}]]);
    const deps = createFakeEngineDeps(store);
    const condutor = await runCreateWeightRecord({
      deps,
      actor: {...mockActor, internalRole: "condutor"},
      rawPayload: {...validPayload.payload, dogId: "dog_a", operationId: "op_role_condutor"},
    });
    const admin = await runCreateWeightRecord({
      deps,
      actor: {...mockActor, internalRole: "admin"},
      rawPayload: {...validPayload.payload, dogId: "dog_a", operationId: "op_role_admin"},
    });
    const condutorRole = (store.get(`dogs/dog_a/weight_records/${condutor.entityId}`)!
      .recorded_by as Record<string, unknown>).internal_role;
    const adminRole = (store.get(`dogs/dog_a/weight_records/${admin.entityId}`)!
      .recorded_by as Record<string, unknown>).internal_role;
    assert.strictEqual(condutorRole, "condutor");
    assert.strictEqual(adminRole, "admin");
    assert.notStrictEqual(condutorRole, "operador_k9");
    assert.notStrictEqual(adminRole, "administrador");
  });

  await test("7. internal_role ausente ou desconhecido e rejeitado sem persistencia", async () => {
    for (const internalRole of [undefined, "operador_k9", "operator", "gestor", "instrutor", "vet"]) {
      const store: Store = new Map([["dogs/dog_a", {name: "Bono"}]]);
      await assert.rejects(
        runCreateWeightRecord({
          deps: createFakeEngineDeps(store),
          actor: {...mockActor, internalRole} as unknown as WeightCaller,
          rawPayload: {...validPayload.payload, dogId: "dog_a", operationId: "op_invalid_role"},
        }),
        (err: unknown) => err instanceof WeightEngineError &&
          err.httpCode === "permission-denied" && err.appCode === "invalid_internal_role",
      );
      assert.strictEqual(
        [...store.keys()].some((path) => path.includes("weight_records")),
        false,
      );
    }
  });

  await test("8. context e notes com tipos incorretos retornam invalid-argument", async () => {
    for (const invalidField of [
      {context: 123},
      {context: {}},
      {notes: 123},
      {notes: []},
    ]) {
      const store: Store = new Map([["dogs/dog_a", {name: "Bono"}]]);
      await assert.rejects(
        runCreateWeightRecord({
          deps: createFakeEngineDeps(store),
          actor: mockActor,
          rawPayload: {
            ...validPayload.payload,
            dogId: "dog_a",
            operationId: "op_invalid_optional",
            ...invalidField,
          },
        }),
        (err: unknown) => err instanceof WeightEngineError &&
          err.httpCode === "invalid-argument",
      );
    }
  });

  await test("9. strings opcionais vazias seguem politica explicita de omissao", async () => {
    const store: Store = new Map([["dogs/dog_a", {name: "Bono"}]]);
    const result = await runCreateWeightRecord({
      deps: createFakeEngineDeps(store),
      actor: mockActor,
      rawPayload: {
        ...validPayload.payload,
        dogId: "dog_a",
        operationId: "op_empty_optional",
        context: "   ",
        notes: "   ",
      },
    });
    const record = store.get(`dogs/dog_a/weight_records/${result.entityId}`)!;
    assert.strictEqual("context" in record, false);
    assert.strictEqual("notes" in record, false);
  });

  await test("10. handler permite capability e acesso ao K9 e executa engine", async () => {
    const engineRuns = {count: 0};
    const handler = buildHealthWeightCreateRecordHandler(handlerDeps({engineRuns}));
    const result = await handler(callableRequest());
    assert.strictEqual(result.dogId, "dog_a");
    assert.strictEqual(engineRuns.count, 1);
  });

  await test("11. handler nega capability e nao executa engine", async () => {
    const engineRuns = {count: 0};
    const handler = buildHealthWeightCreateRecordHandler(handlerDeps({
      capabilityAllowed: false,
      engineRuns,
    }));
    await assert.rejects(
      handler(callableRequest()),
      (err: unknown) => err instanceof HttpsError && err.code === "permission-denied",
    );
    assert.strictEqual(engineRuns.count, 0);
  });

  await test("12. handler nega acesso ao K9 e nao executa engine", async () => {
    const engineRuns = {count: 0};
    const handler = buildHealthWeightCreateRecordHandler(handlerDeps({
      dogAccessAllowed: false,
      engineRuns,
    }));
    await assert.rejects(
      handler(callableRequest()),
      (err: unknown) => err instanceof HttpsError && err.code === "permission-denied",
    );
    assert.strictEqual(engineRuns.count, 0);
  });
}

main().catch((err) => {
  console.error("Unhandled error in weight engine test runner:", err);
  process.exit(1);
});
