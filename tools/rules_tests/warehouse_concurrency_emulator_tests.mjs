/**
 * K9 Ops — F60 Almoxarifado Real Concurrency Tests (Emulator)
 * Location: canil-gcm/tools/rules_tests/warehouse_concurrency_emulator_tests.mjs
 *
 * Scenarios verified against real Firestore emulator transactions:
 * C1 — Concurrent consumption race
 * C2 — Concurrent identical idempotency key replay
 * C3 — Concurrent distinct idempotency keys for same semantic request
 * C4 — Concurrent equipment creation with PAT-K9-001 vs pat-k9-001
 * C5 — Concurrent custody opening for same available equipment
 * C6 — Concurrent stock movement under active InventorySession lock
 */

import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-k9-ops";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = FS_HOST;

console.log(`[CONCURRENCY-TEST] Target emulator: ${FS_HOST}, Project: ${PROJECT_ID}`);

// Import firebase-admin from functions directory so all types (Timestamp, DocumentReference, etc.) match exactly
const adminPath = path.resolve(__dirname, "../../functions/node_modules/firebase-admin");
const admin = (await import(`file://${path.resolve(adminPath, "lib/index.js").replace(/\\/g, "/")}`)).default;

// Initialize Firebase Admin for Emulator using functions' firebase-admin instance
if (admin.apps.length > 0) {
  await Promise.all(admin.apps.map((a) => a?.delete()));
}
const app = admin.initializeApp({ projectId: PROJECT_ID }, "warehouse-concurrency-suite");
const db = admin.firestore(app);
const Timestamp = admin.firestore.Timestamp;

// Import compiled backend transaction functions & callables
const transactionsPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_transactions.js");
const callablesPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_callables.js");

const {
  executeWarehouseConsumption,
  executeWarehouseEntry,
  executeOpenCustody,
  executeStartInventorySession,
} = await import(`file://${transactionsPath.replace(/\\/g, "/")}`);

const {
  reserveEquipmentIdentifier,
} = await import(`file://${callablesPath.replace(/\\/g, "/")}`);

const caller1 = { ra: "100001", name: "Operador 1", uid: "uid-100001" };
const caller2 = { ra: "100002", name: "Operador 2", uid: "uid-100002" };

const results = [];

function recordResult(scenario, description, passed, details = {}) {
  results.push({ scenario, description, passed, details });
  console.log(`[${passed ? "PASS" : "FAIL"}] ${scenario}: ${description}`);
  if (Object.keys(details).length > 0) {
    console.log(`       Details: ${JSON.stringify(details, null, 2)}`);
  }
}

async function runC1() {
  console.log("\n--- Scenario C1: Concurrent consumption race ---");
  const materialId = "mat-c1";
  const batchId = "batch-c1";
  const locId = "loc-c1";
  const posId = `pos_${materialId}_${batchId}_${locId}`;

  // Initial state: position=10, batch=10, material=10
  const now = Timestamp.now();
  await db.collection("inventory_items").doc(materialId).set({
    id: materialId,
    name: "Ração Premium",
    category_id: "alimentacao",
    unit: "kg",
    current_quantity: 10,
    warehouse_managed: true,
    active: true,
    updated_at: now,
  });

  await db.collection("warehouse_batches").doc(batchId).set({
    id: batchId,
    material_id: materialId,
    material_name: "Ração Premium",
    lot_number: "LOTE-C1",
    initial_quantity: 10,
    current_quantity: 10,
    expiration_date: "2029-12-31",
    status: "active",
    created_at: now,
    updated_at: now,
  });

  await db.collection("warehouse_positions").doc(posId).set({
    id: posId,
    material_id: materialId,
    batch_id: batchId,
    lot_number: "LOTE-C1",
    location_id: locId,
    location_name: "Galpão A",
    quantity: 10,
    unit: "kg",
    schema_version: 1,
    updated_at: now,
  });

  // Launch two concurrent consume 7 operations
  const p1 = executeWarehouseConsumption(db, caller1, {
    material_id: materialId,
    batch_id: batchId,
    source_location_id: locId,
    quantity: 7,
    reason: "Consumo C1 - Transação 1",
    idempotency_key: "c1-tx1-key",
  });

  const p2 = executeWarehouseConsumption(db, caller2, {
    material_id: materialId,
    batch_id: batchId,
    source_location_id: locId,
    quantity: 7,
    reason: "Consumo C1 - Transação 2",
    idempotency_key: "c1-tx2-key",
  });

  const [res1, res2] = await Promise.allSettled([p1, p2]);

  const fulfilled = [res1, res2].filter((r) => r.status === "fulfilled");
  const rejected = [res1, res2].filter((r) => r.status === "rejected");

  const finalMat = (await db.collection("inventory_items").doc(materialId).get()).data();
  const finalBatch = (await db.collection("warehouse_batches").doc(batchId).get()).data();
  const finalPos = (await db.collection("warehouse_positions").doc(posId).get()).data();

  const movementsSnap = await db.collection("inventory_movements").where("material_id", "==", materialId).get();

  const passed =
    fulfilled.length === 1 &&
    rejected.length === 1 &&
    finalMat.current_quantity === 3 &&
    finalBatch.current_quantity === 3 &&
    finalPos.quantity === 3 &&
    movementsSnap.size === 1;

  recordResult("C1", "Two concurrent 'consume 7' with 10 on hand: exactly 1 succeeds, 1 fails, final stock = 3", passed, {
    fulfilledCount: fulfilled.length,
    rejectedCount: rejected.length,
    rejectedError: rejected[0]?.reason?.message,
    finalMaterialStock: finalMat?.current_quantity,
    finalBatchStock: finalBatch?.current_quantity,
    finalPositionStock: finalPos?.quantity,
    movementsAccepted: movementsSnap.size,
  });
}

async function runC2() {
  console.log("\n--- Scenario C2: Concurrent identical idempotency_key ---");
  const materialId = "mat-c2";
  const locId = "loc-c2";
  const now = Timestamp.now();

  await db.collection("inventory_items").doc(materialId).set({
    id: materialId,
    name: "Guia K9",
    category_id: "equipamentos",
    unit: "unidade",
    current_quantity: 0,
    warehouse_managed: true,
    active: true,
    updated_at: now,
  });

  const sharedIdempotencyKey = "c2-shared-entry-key";

  // Dispatch two concurrent entry operations with identical params & idempotency key
  const entryParams = {
    material_id: materialId,
    lot_number: "LOTE-C2",
    expiration_date: "2029-12-31",
    destination_location_id: locId,
    destination_location_name: "Depósito C2",
    quantity: 5,
    reason: "Entrada C2 Idempotente",
    idempotency_key: sharedIdempotencyKey,
  };

  const p1 = executeWarehouseEntry(db, caller1, entryParams);
  const p2 = executeWarehouseEntry(db, caller1, entryParams);

  const [res1, res2] = await Promise.allSettled([p1, p2]);

  const finalMat = (await db.collection("inventory_items").doc(materialId).get()).data();
  const movementsSnap = await db.collection("inventory_movements").where("material_id", "==", materialId).get();
  const idemSnap = await db.collection("idempotency_keys").doc(sharedIdempotencyKey).get();

  const passed =
    res1.status === "fulfilled" &&
    res2.status === "fulfilled" &&
    res1.value.movement_id === res2.value.movement_id &&
    finalMat.current_quantity === 5 &&
    movementsSnap.size === 1 &&
    idemSnap.exists;

  recordResult("C2", "Same idempotency_key concurrently: effect applied exactly once, safe replay, 1 movement", passed, {
    res1Status: res1.status,
    res2Status: res2.status,
    res1MovementId: res1.value?.movement_id,
    res2MovementId: res2.value?.movement_id,
    finalMaterialStock: finalMat?.current_quantity,
    ledgerMovementsCount: movementsSnap.size,
    idempotencyDocExists: idemSnap.exists,
  });
}

async function runC3() {
  console.log("\n--- Scenario C3: Concurrent distinct idempotency_keys with same semantic body ---");
  const materialId = "mat-c3";
  const locId = "loc-c3";
  const now = Timestamp.now();

  await db.collection("inventory_items").doc(materialId).set({
    id: materialId,
    name: "Coleira K9",
    category_id: "equipamentos",
    unit: "unidade",
    current_quantity: 0,
    warehouse_managed: true,
    active: true,
    updated_at: now,
  });

  const p1 = executeWarehouseEntry(db, caller1, {
    material_id: materialId,
    lot_number: "LOTE-C3",
    expiration_date: "2029-12-31",
    destination_location_id: locId,
    destination_location_name: "Depósito C3",
    quantity: 5,
    reason: "Entrada C3 Distinta 1",
    idempotency_key: "c3-key-alpha",
  });

  const p2 = executeWarehouseEntry(db, caller2, {
    material_id: materialId,
    lot_number: "LOTE-C3",
    expiration_date: "2029-12-31",
    destination_location_id: locId,
    destination_location_name: "Depósito C3",
    quantity: 5,
    reason: "Entrada C3 Distinta 2",
    idempotency_key: "c3-key-beta",
  });

  const [res1, res2] = await Promise.allSettled([p1, p2]);

  const finalMat = (await db.collection("inventory_items").doc(materialId).get()).data();
  const movementsSnap = await db.collection("inventory_movements").where("material_id", "==", materialId).get();

  const passed =
    res1.status === "fulfilled" &&
    res2.status === "fulfilled" &&
    res1.value.movement_id !== res2.value.movement_id &&
    finalMat.current_quantity === 10 &&
    movementsSnap.size === 2;

  recordResult("C3", "Distinct idempotency_keys: both processed as independent commands, final stock = 10", passed, {
    res1Status: res1.status,
    res2Status: res2.status,
    finalMaterialStock: finalMat?.current_quantity,
    movementsRecorded: movementsSnap.size,
  });
}

async function runC4() {
  console.log("\n--- Scenario C4: Concurrent equipment creation with PAT-K9-001 vs pat-k9-001 ---");

  // Mark legacy reconciliation certified
  await db.collection("warehouse_control").doc("legacy_reconciliation_status").set({
    status: "completed",
    certified_at: Timestamp.now(),
  });

  const eqId1 = "eq-c4-upper";
  const eqId2 = "eq-c4-lower";
  const code1 = "PAT-K9-001";
  const code2 = "pat-k9-001";

  // Simulate upsert equipment transaction: reserve identifier + create doc
  const upsertEquipment = async (id, code, caller) => {
    return db.runTransaction(async (transaction) => {
      await reserveEquipmentIdentifier(db, transaction, id, code, false);
      const eqRef = db.collection("warehouse_equipment").doc(id);
      transaction.set(eqRef, {
        id,
        name: "Coleira de Proteção",
        category_id: "equipamentos",
        identifier_code: code,
        condition: "good",
        status: "available",
        current_location_id: "loc-base",
        current_location_name: "Base Central",
        active: true,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
      return { id, code };
    });
  };

  const p1 = upsertEquipment(eqId1, code1, caller1);
  const p2 = upsertEquipment(eqId2, code2, caller2);

  const [res1, res2] = await Promise.allSettled([p1, p2]);

  const fulfilled = [res1, res2].filter((r) => r.status === "fulfilled");
  const rejected = [res1, res2].filter((r) => r.status === "rejected");

  const canonicalIndexSnap = await db.collection("warehouse_equipment_identifiers").doc("pat-k9-001").get();
  const eqUpperSnap = await db.collection("warehouse_equipment").doc(eqId1).get();
  const eqLowerSnap = await db.collection("warehouse_equipment").doc(eqId2).get();

  const totalCreated = (eqUpperSnap.exists ? 1 : 0) + (eqLowerSnap.exists ? 1 : 0);

  const passed =
    fulfilled.length === 1 &&
    rejected.length === 1 &&
    rejected[0].reason?.code === "already-exists" &&
    canonicalIndexSnap.exists &&
    totalCreated === 1 &&
    canonicalIndexSnap.data()?.equipment_id === fulfilled[0].value.id;

  recordResult("C4", "Concurrent PAT-K9-001 and pat-k9-001: exactly 1 creates, 1 canonical index, 0 orphans", passed, {
    winnerId: fulfilled[0]?.value?.id,
    rejectedError: rejected[0]?.reason?.message,
    rejectedCode: rejected[0]?.reason?.code,
    canonicalIndexOwner: canonicalIndexSnap.data()?.equipment_id,
    totalEquipmentDocsCreated: totalCreated,
  });
}

async function runC5() {
  console.log("\n--- Scenario C5: Concurrent custody opening for same available equipment ---");
  const eqId = "eq-c5-custody";
  const now = Timestamp.now();

  await db.collection("warehouse_equipment").doc(eqId).set({
    id: eqId,
    name: "Coleira de Condução C5",
    category_id: "equipamentos",
    identifier_code: "COLEIRA-C5",
    condition: "good",
    status: "available",
    active_custody_id: null,
    current_location_id: "loc-base",
    current_location_name: "Base",
    active: true,
    created_at: now,
    updated_at: now,
  });

  const p1 = executeOpenCustody(db, caller1, {
    equipment_id: eqId,
    borrower_ra: "200001",
    borrower_name: "Agente Silva",
    condition_at_dispatch: "good",
    purpose: "daily_duty",
    idempotency_key: "c5-custody-tx1",
  });

  const p2 = executeOpenCustody(db, caller2, {
    equipment_id: eqId,
    borrower_ra: "200002",
    borrower_name: "Agente Santos",
    condition_at_dispatch: "good",
    purpose: "daily_duty",
    idempotency_key: "c5-custody-tx2",
  });

  const [res1, res2] = await Promise.allSettled([p1, p2]);

  const fulfilled = [res1, res2].filter((r) => r.status === "fulfilled");
  const rejected = [res1, res2].filter((r) => r.status === "rejected");

  const finalEq = (await db.collection("warehouse_equipment").doc(eqId).get()).data();
  const custodiesSnap = await db.collection("warehouse_custodies").where("equipment_id", "==", eqId).get();
  const activeCustodies = custodiesSnap.docs.filter((d) => d.data().status === "active");

  const passed =
    fulfilled.length === 1 &&
    rejected.length === 1 &&
    rejected[0].reason?.code === "failed-precondition" &&
    finalEq.status === "in_custody" &&
    finalEq.active_custody_id === fulfilled[0].value.custody_id &&
    activeCustodies.length === 1;

  recordResult("C5", "Concurrent open custody on same equipment: exactly 1 succeeds, status=in_custody, 1 active custody", passed, {
    winnerCustodyId: fulfilled[0]?.value?.custody_id,
    rejectedError: rejected[0]?.reason?.message,
    finalEquipmentStatus: finalEq?.status,
    activeCustodiesCount: activeCustodies.length,
  });
}

async function runC6(iterations = 25) {
  console.log(`\n--- Scenario C6: Concurrent stock movement vs InventorySession activation race (${iterations} iterations) ---`);
  let inventoryWon = 0;
  let movementWon = 0;
  let invalidOutcomes = 0;

  for (let i = 1; i <= iterations; i++) {
    const materialId = `mat-c6-race-${i}`;
    const batchId = `batch-c6-race-${i}`;
    const locId = `loc-c6-race-${i}`;
    const posId = `pos_${materialId}_${batchId}_${locId}`;
    const now = Timestamp.now();

    // Reset inventory lock document
    await db.collection("warehouse_control").doc("inventory_lock").set({
      active_session_id: null,
      updated_at: now,
    });

    // Seed initial stock: 10 units
    await db.collection("inventory_items").doc(materialId).set({
      id: materialId,
      name: `Material C6 ${i}`,
      category_id: "geral",
      unit: "unidade",
      current_quantity: 10,
      warehouse_managed: true,
      active: true,
      updated_at: now,
    });

    await db.collection("warehouse_batches").doc(batchId).set({
      id: batchId,
      material_id: materialId,
      material_name: `Material C6 ${i}`,
      lot_number: `LOTE-C6-${i}`,
      initial_quantity: 10,
      current_quantity: 10,
      expiration_date: "2029-12-31",
      status: "active",
      created_at: now,
      updated_at: now,
    });

    await db.collection("warehouse_positions").doc(posId).set({
      id: posId,
      material_id: materialId,
      batch_id: batchId,
      lot_number: `LOTE-C6-${i}`,
      location_id: locId,
      location_name: `Local C6 ${i}`,
      quantity: 10,
      unit: "unidade",
      schema_version: 1,
      updated_at: now,
    });

    // Dispatch both operations concurrently (temporal overlap)
    const pInventory = executeStartInventorySession(db, caller1, {
      title: `Inventário Concorrente Iteração ${i}`,
      scope_type: "by_location",
      scope_ref_id: locId,
    });

    const pMovement = executeWarehouseConsumption(db, caller2, {
      material_id: materialId,
      batch_id: batchId,
      source_location_id: locId,
      quantity: 2,
      reason: `Consumo concorrente C6 iteração ${i}`,
      idempotency_key: `c6-race-key-${i}`,
    });

    const [resInv, resMove] = await Promise.allSettled([pInventory, pMovement]);

    // Inspect final state
    const finalMat = (await db.collection("inventory_items").doc(materialId).get()).data();
    const finalBatch = (await db.collection("warehouse_batches").doc(batchId).get()).data();
    const finalPos = (await db.collection("warehouse_positions").doc(posId).get()).data();
    const movementsSnap = await db.collection("inventory_movements").where("material_id", "==", materialId).get();

    let sessionId = null;
    let expectedQuantityInSnapshot = null;
    if (resInv.status === "fulfilled") {
      sessionId = resInv.value.session_id;
      const countDoc = await db.collection("inventory_sessions").doc(sessionId).collection("counts").doc(posId).get();
      if (countDoc.exists) {
        expectedQuantityInSnapshot = countDoc.data().expected_quantity;
      }
    }

    // Outcome A: Inventory won first
    if (
      resInv.status === "fulfilled" &&
      resMove.status === "rejected" &&
      resMove.reason?.code === "failed-precondition" &&
      resMove.reason?.details?.code === "warehouse/inventory-scope-locked" &&
      finalMat.current_quantity === 10 &&
      finalBatch.current_quantity === 10 &&
      finalPos.quantity === 10 &&
      movementsSnap.size === 0 &&
      expectedQuantityInSnapshot === 10
    ) {
      inventoryWon++;
    }
    // Outcome B: Movement won before inventory snapshot
    else if (
      resInv.status === "fulfilled" &&
      resMove.status === "fulfilled" &&
      finalMat.current_quantity === 8 &&
      finalBatch.current_quantity === 8 &&
      finalPos.quantity === 8 &&
      movementsSnap.size === 1 &&
      expectedQuantityInSnapshot === 8
    ) {
      // Test subsequent movement while lock is active
      let subsequentError = null;
      try {
        await executeWarehouseConsumption(db, caller2, {
          material_id: materialId,
          batch_id: batchId,
          source_location_id: locId,
          quantity: 1,
          reason: `Consumo subsequente pós-lock iter ${i}`,
          idempotency_key: `c6-subsequent-key-${i}`,
        });
      } catch (err) {
        subsequentError = err;
      }

      const postSubsequentMat = (await db.collection("inventory_items").doc(materialId).get()).data();
      if (
        subsequentError?.code === "failed-precondition" &&
        subsequentError?.details?.code === "warehouse/inventory-scope-locked" &&
        postSubsequentMat.current_quantity === 8
      ) {
        movementWon++;
      } else {
        invalidOutcomes++;
      }
    } else {
      invalidOutcomes++;
    }

    // Clean up session if opened
    if (sessionId) {
      await db.collection("inventory_sessions").doc(sessionId).update({
        status: "cancelled",
      });
    }
  }

  const passed = invalidOutcomes === 0 && (inventoryWon + movementWon === iterations);

  recordResult("C6", `Temporal concurrency race between InventorySession activation and stock movement (${iterations} iterations)`, passed, {
    totalIterations: iterations,
    inventoryWon,
    movementWon,
    invalidOutcomes,
  });
}

async function main() {
  console.log("=== STARTING REAL CONCURRENCY EMULATOR SUITE (C1-C6) ===");
  try {
    await runC1();
    await runC2();
    await runC3();
    await runC4();
    await runC5();
    await runC6();

    console.log("\n================ CONCURRENCY RESULTS ================");
    console.table(
      results.map((r) => ({
        Cenário: r.scenario,
        Status: r.passed ? "PASS" : "FAIL",
        Descrição: r.description,
      })),
    );

    const allPassed = results.every((r) => r.passed);
    if (!allPassed) {
      console.error("\n[FAILURE] One or more concurrency scenarios failed!");
      process.exitCode = 1;
    } else {
      console.log(`\n[SUCCESS] All ${results.length} concurrency scenarios passed real emulator testing!`);
    }
  } catch (err) {
    console.error("\n[FATAL ERROR IN SUITE]", err);
    process.exitCode = 1;
  } finally {
    await app.delete();
  }
}

main();
