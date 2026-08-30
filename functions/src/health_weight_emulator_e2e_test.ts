import * as assert from "assert";
import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildHealthWeightCreateRecordHandler,
  createAdminWeightEngineDeps,
  HealthWeightCallableDeps,
} from "./health_weight_callables";
import {WeightCaller} from "./health_weight_logic";

const emuHost = process.env.FIRESTORE_EMULATOR_HOST;

let testCount = 0;
let passCount = 0;
let failCount = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  testCount++;
  try {
    await fn();
    passCount++;
    console.log(`ok - ${name}`);
  } catch (e) {
    failCount++;
    console.error(`FAIL - ${name}`, e);
    throw e;
  }
}

function mockRequest(data: Record<string, unknown>, auth: unknown): any {
  return {data, auth};
}

async function main() {
  if (!emuHost) {
    console.error("ERRO CRÍTICO: FIRESTORE_EMULATOR_HOST não está configurado. O teste E2E exige execução via Firestore Emulator real.");
    process.exit(1);
  }

  console.log(`Conectado ao Firestore Emulator em ${emuHost}...`);

  if (!admin.apps.length) {
    admin.initializeApp({projectId: "canil-gcm"});
  }
  const db = admin.firestore();

  const mockActor: WeightCaller = {
    uid: "usr_emu_001",
    name: "GCM Ragonha",
    ra: "GCM-12345",
    internalRole: "condutor",
  };

  const createDeps = (overrideActor?: WeightCaller, denyCap = false): HealthWeightCallableDeps => ({
    db,
    requireHealthRecordRoutine: async (auth) => {
      if (!auth) {
        throw new HttpsError("unauthenticated", "Não autenticado.");
      }
      if (denyCap) {
        throw new HttpsError("permission-denied", "Sem permissão para health.record_routine.");
      }
      return overrideActor ?? mockActor;
    },
    requireDogAccess: async () => {},
    createEngineDeps: () => createAdminWeightEngineDeps(db),
  });

  // Teste 1: Criação canônica completa com contexto e notas + sentinels resolvidos + tipos Timestamp
  await test("E2E-1: Criação canônica de pesagem no Emulator (Validação de tipos Timestamp, sentinels resolvidos, ausência de PII/legados, denormalização, receipt e audit log)", async () => {
    // 1. criação do K9 de teste
    const dogId = "dog_emu_001";
    await db.collection("dogs").doc(dogId).set({
      name: "Thor",
      breed: "German Shepherd",
    });

    const handler = buildHealthWeightCreateRecordHandler(createDeps());

    // 19. routine explícito é persistido, 22. notes presente é persistido, 5. weight_kg com o valor exato
    const opId = "op_emu_clean_001";
    const weightVal = 32.523; // valor com precisão extra para testar fidelidade
    const res = await handler(mockRequest({
      dogId,
      operationId: opId,
      payload: {
        weightKg: weightVal,
        measuredAt: "2026-08-04T10:00:00.000Z",
        context: "routine",
        notes: "Pesagem E2E R4",
      },
    }, {uid: "usr_emu_001"}));

    // 3. weight_records criado, 27. entityId retornado
    assert.ok(res);
    assert.strictEqual(res!.dogId, dogId);
    assert.strictEqual(res!.weightKg, weightVal); // 5. weight_kg com o valor exato
    assert.strictEqual(res!.wasNoOp, false);
    const entityId = res!.entityId;

    // 4. somente um registro criado em weight_records
    const recordsSnap = await db.collection(`dogs/${dogId}/weight_records`).get();
    assert.strictEqual(recordsSnap.size, 1);

    // 10. receipt criado
    const receiptSnap = await db.doc(`dogs/${dogId}/weight_operations/${opId}`).get();
    assert.strictEqual(receiptSnap.exists, true);
    const receipt = receiptSnap.data()!;
    assert.strictEqual(receipt.operation_id, opId);
    assert.strictEqual(receipt.entity_id, entityId);

    // 11. receipt.processed_at é Timestamp
    assert.ok(receipt.processed_at instanceof admin.firestore.Timestamp, "receipt.processed_at deve ser Timestamp");
    assert.ok(receipt.created_at instanceof admin.firestore.Timestamp, "receipt.created_at deve ser Timestamp");

    // 12. recorded_by.uid correto, 13. recorded_by.name correto, 14. recorded_by.internal_role correto
    const recordSnap = await db.doc(`dogs/${dogId}/weight_records/${entityId}`).get();
    assert.strictEqual(recordSnap.exists, true);
    const rec = recordSnap.data()!;

    assert.strictEqual(rec.weight_kg, weightVal); // 5. weight_kg exato
    assert.strictEqual(rec.schema_version, 1);

    // 6. measured_at é Timestamp, 8. created_at é Timestamp resolvido, 9. updated_at é Timestamp resolvido
    assert.ok(rec.measured_at instanceof admin.firestore.Timestamp, "rec.measured_at deve ser Timestamp");
    assert.ok(rec.created_at instanceof admin.firestore.Timestamp, "rec.created_at deve ser Timestamp");
    assert.ok(rec.updated_at instanceof admin.firestore.Timestamp, "rec.updated_at deve ser Timestamp");

    // Sentinels audit_trail no array: 6. Sentinels Firestore resolvidos
    assert.ok(Array.isArray(rec.audit_trail), "audit_trail deve ser array");
    assert.strictEqual(rec.audit_trail.length, 1);
    assert.ok(rec.audit_trail[0].at instanceof admin.firestore.Timestamp, "audit_trail[0].at deve ser Timestamp resolvido");

    assert.strictEqual(rec.recorded_by.uid, "usr_emu_001"); // 12. uid
    assert.strictEqual(rec.recorded_by.name, "GCM Ragonha"); // 13. name
    assert.strictEqual(rec.recorded_by.internal_role, "condutor"); // 14. internal_role

    // 15. nenhum e-mail persistido, 16. nenhum measured_by, 17. nenhum performed_by
    assert.strictEqual(rec.recorded_by.email, undefined);
    assert.strictEqual(rec.measured_by, undefined);
    assert.strictEqual(rec.performed_by, undefined);

    // 19. routine explícito é persistido, 22. notes presente é persistido
    assert.strictEqual(rec.context, "routine");
    assert.strictEqual(rec.notes, "Pesagem E2E R4");

    // 25. denormalizações do cão atualizadas & 7. dogs._last_weight_at é Timestamp
    const dogSnap = await db.doc(`dogs/${dogId}`).get();
    const dog = dogSnap.data()!;
    assert.strictEqual(dog.weight, weightVal);
    assert.strictEqual(dog._last_weight_kg, weightVal);
    assert.ok(dog._last_weight_at instanceof admin.firestore.Timestamp, "dogs._last_weight_at deve ser Timestamp");
    assert.ok(dog.updated_at instanceof admin.firestore.Timestamp, "dogs.updated_at deve ser Timestamp");
    assert.ok(Array.isArray(dog.audit_trail), "dog.audit_trail deve ser array");

    // 26. audit log criado
    const auditLogsSnap = await db.collection("auditLogs").where("entity_id", "==", entityId).get();
    assert.strictEqual(auditLogsSnap.empty, false);
    const auditLog = auditLogsSnap.docs[0].data();
    assert.ok(auditLog.performed_at instanceof admin.firestore.Timestamp, "auditLog.performed_at deve ser Timestamp");
    assert.ok(auditLog.createdAt instanceof admin.firestore.Timestamp, "auditLog.createdAt deve ser Timestamp");

    // 23. nenhuma escrita em weight_history, 24. nenhuma escrita em health_events
    const historySnap = await db.doc(`dogs/${dogId}/weight_history/${entityId}`).get();
    assert.strictEqual(historySnap.exists, false);

    const eventsSnap = await db.doc(`dogs/${dogId}/health_events/${entityId}`).get();
    assert.strictEqual(eventsSnap.exists, false);
  });

  // Teste 2: Criação válida sem contexto e sem notes
  await test("E2E-2: Criação válida sem contexto e sem notes (Campos omitidos quando ausentes)", async () => {
    // 2. criação válida sem contexto
    const dogId = "dog_emu_002";
    await db.collection("dogs").doc(dogId).set({name: "Max"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const res = await handler(mockRequest({
      dogId,
      operationId: "op_emu_no_ctx_001",
      payload: {
        weightKg: 28.0,
        measuredAt: "2026-08-04T10:30:00.000Z",
      },
    }, {uid: "usr_emu_001"}));

    assert.ok(res);
    const recSnap = await db.doc(`dogs/${dogId}/weight_records/${res!.entityId}`).get();
    const rec = recSnap.data()!;

    // 18. contexto ausente resulta em campo omitido
    assert.strictEqual("context" in rec, false, "context deve ser omitido");
    // 21. notes ausente resulta em campo omitido
    assert.strictEqual("notes" in rec, false, "notes deve ser omitido");
  });

  // Teste 3: Contexto inválido é rejeitado
  await test("E2E-3: Rejeição de contexto inválido", async () => {
    const dogId = "dog_emu_003";
    await db.collection("dogs").doc(dogId).set({name: "Bella"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());

    // 20. contexto inválido é rejeitado
    await assert.rejects(async () => {
      await handler(mockRequest({
        dogId,
        operationId: "op_emu_inv_ctx",
        payload: {
          weightKg: 25.0,
          measuredAt: "2026-08-04T11:00:00.000Z",
          context: "invalid_context_name",
        },
      }, {uid: "usr_emu_001"}));
    });
  });

  // Teste 4: Replay determinístico
  await test("E2E-4: Replay do mesmo operationId (mesmo entityId, wasNoOp=true, ZERO novas gravações)", async () => {
    const dogId = "dog_emu_004";
    await db.collection("dogs").doc(dogId).set({name: "Rex"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const payload = {
      dogId,
      operationId: "op_emu_replay_001",
      payload: {
        weightKg: 28.0,
        measuredAt: "2026-08-04T10:30:00.000Z",
        context: "clinical",
      },
    };

    const res1 = await handler(mockRequest(payload, {uid: "usr_emu_001"}));
    assert.strictEqual(res1!.wasNoOp, false);
    const entityId = res1!.entityId;

    const recordsBefore = await db.collection(`dogs/${dogId}/weight_records`).get();
    const auditsBefore = await db.collection("auditLogs").where("metadata.dog_id", "==", dogId).get();

    const res2 = await handler(mockRequest(payload, {uid: "usr_emu_001"}));
    // 27. replay retorna o mesmo entityId
    assert.strictEqual(res2!.entityId, entityId);
    // 28. replay retorna wasNoOp = true
    assert.strictEqual(res2!.wasNoOp, true);

    const recordsAfter = await db.collection(`dogs/${dogId}/weight_records`).get();
    const auditsAfter = await db.collection("auditLogs").where("metadata.dog_id", "==", dogId).get();

    // 29. replay não cria segundo audit log
    assert.strictEqual(auditsAfter.size, auditsBefore.size);
    // 30. replay não cria segundo WeightRecord
    assert.strictEqual(recordsAfter.size, recordsBefore.size);
  });

  // Teste 5: Conflito de fingerprint falha
  await test("E2E-5: Conflito de fingerprint falha (mesmo operationId com payload diferente)", async () => {
    const dogId = "dog_emu_005";
    await db.collection("dogs").doc(dogId).set({name: "Luna"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const basePayload = {
      dogId,
      operationId: "op_emu_conflict_001",
      payload: {
        weightKg: 25.0,
        measuredAt: "2026-08-04T11:00:00.000Z",
        context: "routine",
      },
    };

    await handler(mockRequest(basePayload, {uid: "usr_emu_001"}));

    // 31. conflito de fingerprint falha
    await assert.rejects(async () => {
      await handler(mockRequest({
        ...basePayload,
        payload: {
          weightKg: 30.0,
          measuredAt: "2026-08-04T11:00:00.000Z",
          context: "routine",
        },
      }, {uid: "usr_emu_001"}));
    });
  });

  // Teste 6: Duas operationIds no mesmo instante criam duas entidades
  await test("E2E-6: Duas operationIds no mesmo instante criam duas entidades distintas", async () => {
    const dogId = "dog_emu_006";
    await db.collection("dogs").doc(dogId).set({name: "Ares"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const measuredAt = "2026-08-04T11:30:00.000Z";

    const res1 = await handler(mockRequest({
      dogId,
      operationId: "op_sim_001",
      payload: {weightKg: 30.0, measuredAt},
    }, {uid: "usr_emu_001"}));

    const res2 = await handler(mockRequest({
      dogId,
      operationId: "op_sim_002",
      payload: {weightKg: 30.0, measuredAt},
    }, {uid: "usr_emu_001"}));

    // 32. duas operationIds no mesmo instante criam duas entidades
    assert.notStrictEqual(res1!.entityId, res2!.entityId);
    const records = await db.collection(`dogs/${dogId}/weight_records`).get();
    assert.strictEqual(records.size, 2);
  });

  // Teste 7: Atomicidade e rollback em falha transacional
  await test("E2E-7: Falha transacional não deixa receipt ou WeightRecord parcial", async () => {
    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const nonExistentDogId = "dog_emu_non_existent_999";
    const opId = "op_emu_fail_atomicity";

    // 36. K9 inexistente é rejeitado
    await assert.rejects(async () => {
      await handler(mockRequest({
        dogId: nonExistentDogId,
        operationId: opId,
        payload: {weightKg: 20.0, measuredAt: "2026-08-04T12:00:00.000Z"},
      }, {uid: "usr_emu_001"}));
    });

    // 33. falha transacional não deixa receipt parcial
    const receiptSnap = await db.doc(`dogs/${nonExistentDogId}/weight_operations/${opId}`).get();
    assert.strictEqual(receiptSnap.exists, false);

    // 34. falha transacional não deixa WeightRecord parcial
    const recordsSnap = await db.collection(`dogs/${nonExistentDogId}/weight_records`).get();
    assert.strictEqual(recordsSnap.empty, true);
  });

  // Teste 8: Timestamp futuro é rejeitado
  await test("E2E-8: Timestamp futuro é rejeitado", async () => {
    const dogId = "dog_emu_008";
    await db.collection("dogs").doc(dogId).set({name: "Zeus"});

    const handler = buildHealthWeightCreateRecordHandler(createDeps());
    const futureDate = new Date(Date.now() + 3600000).toISOString();

    // 35. timestamp futuro é rejeitado
    await assert.rejects(async () => {
      await handler(mockRequest({
        dogId,
        operationId: "op_emu_future",
        payload: {weightKg: 25.0, measuredAt: futureDate},
      }, {uid: "usr_emu_001"}));
    });
  });

  console.log(`\n==================================================`);
  console.log(`RESUMO DA EXECUÇÃO E2E FIRESTORE EMULATOR`);
  console.log(`==================================================`);
  console.log(`Testes executados: ${testCount}`);
  console.log(`Aprovados        : ${passCount}`);
  console.log(`Falhas           : ${failCount}`);
  console.log(`==================================================`);

  if (failCount > 0 || testCount === 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Unhandled error in weight emulator test runner:", err);
  process.exit(1);
});
