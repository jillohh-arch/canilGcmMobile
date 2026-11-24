/**
 * K9 Ops — F60 Almoxarifado Physical Inventory Scale & Completeness Tests (Firestore Emulator)
 * Location: canil-gcm/tools/rules_tests/warehouse_inventory_scale_emulator_tests.mjs
 *
 * Sequence of Scale & Completeness verification:
 * 1. Large Full Warehouse Test: 120 StockPositions snapshotted without arbitrary cap.
 * 2. By Location Scale Test: 80 positions in Loc A, 40 positions in Loc B -> by_location=Loc A yields exactly 80.
 * 3. By Category Scale Test: 70 positions in Cat Food, 50 in Cat Hygiene -> by_category=Food yields exactly 70.
 * 4. Concurrent Movement During Snapshot Build: rejected with warehouse/inventory-scope-locked.
 * 5. Snapshot Completeness Guard: non-complete snapshot rejected for count, reconciliation, and homologation.
 * 6. Empty Full Warehouse: 0 eligible positions produces total_items=0, 0 rows, snapshot_status=complete.
 */

import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-k9-ops";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = FS_HOST;

console.log(`[INVENTORY-SCALE-TEST] Target emulator: ${FS_HOST}, Project: ${PROJECT_ID}`);

// Import firebase-admin from functions directory
const adminPath = path.resolve(__dirname, "../../functions/node_modules/firebase-admin");
const admin = (await import(`file://${path.resolve(adminPath, "lib/index.js").replace(/\\/g, "/")}`)).default;

if (admin.apps.length > 0) {
  await Promise.all(admin.apps.map((a) => a?.delete()));
}
const app = admin.initializeApp({ projectId: PROJECT_ID }, "warehouse-inventory-scale-suite");
const db = admin.firestore(app);

// Import compiled backend modules
const domainPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_domain.js");
const transactionsPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_transactions.js");
const callablesPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_callables.js");

const { derivePositionDocId } = await import(`file://${domainPath.replace(/\\/g, "/")}`);
const { executeWarehouseConsumption } = await import(`file://${transactionsPath.replace(/\\/g, "/")}`);
const { createWarehouseCallables } = await import(`file://${callablesPath.replace(/\\/g, "/")}`);

const operator = { ra: "990001", name: "Auditor Almoxarifado", uid: "uid-auditor-almox" };
const mockRequirePermission = async () => operator;
const callables = createWarehouseCallables(db, mockRequirePermission);

const callFn = async (fn, data) => fn.run({ data, auth: { uid: operator.uid, token: {} } });

async function clearCollections(...colls) {
  for (const c of colls) {
    const snap = await db.collection(c).get();
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    if (snap.size > 0) await batch.commit();
  }
}

async function runScaleTests() {
  const now = admin.firestore.Timestamp.now();

  console.log("\n--- TEST 1: Large Full-Warehouse Inventory (120 StockPositions) ---");
  await clearCollections("warehouse_positions", "warehouse_batches", "inventory_items", "inventory_sessions");
  await db.collection("warehouse_control").doc("inventory_lock").set({ active_session_id: null, updated_at: now });

  // Seed 120 positions in bounded batches
  const TOTAL_POSITIONS = 120;
  let seedBatch = db.batch();
  let seedWrites = 0;

  for (let i = 1; i <= TOTAL_POSITIONS; i++) {
    const matId = `mat-scale-${i}`;
    const batchId = `batch-scale-${i}`;
    const locId = `loc-scale-${(i % 5) + 1}`;
    const posId = derivePositionDocId(matId, batchId, locId);

    seedBatch.set(db.collection("inventory_items").doc(matId), {
      id: matId, name: `Material Escala ${i}`, category_id: "geral", unit: "unidade",
      current_quantity: 10, active: true, warehouse_managed: true, updated_at: now,
    });
    seedBatch.set(db.collection("warehouse_batches").doc(batchId), {
      id: batchId, material_id: matId, lot_number: `LOT-SCALE-${i}`, current_quantity: 10,
      initial_quantity: 10, expiration_date: "2029-12-31", status: "active", created_at: now, updated_at: now,
    });
    seedBatch.set(db.collection("warehouse_positions").doc(posId), {
      id: posId, material_id: matId, batch_id: batchId, lot_number: `LOT-SCALE-${i}`,
      location_id: locId, location_name: `Local ${locId}`, quantity: 10, unit: "unidade",
      schema_version: 1, updated_at: now,
    });
    seedWrites += 3;
    if (seedWrites >= 300) {
      await seedBatch.commit();
      seedBatch = db.batch();
      seedWrites = 0;
    }
  }
  if (seedWrites > 0) await seedBatch.commit();

  const allPositionsSnap = await db.collection("warehouse_positions").get();
  assert.equal(allPositionsSnap.size, TOTAL_POSITIONS);

  // Open full warehouse inventory
  const openLargeRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Geral em Escala (120 Posições)",
    scope_type: "full_warehouse",
    notes: "Comprovação de ausência de teto de 75",
  });
  assert.ok(openLargeRes.session_id);
  const largeSessionId = openLargeRes.session_id;

  const sessionLargeDoc = (await db.collection("inventory_sessions").doc(largeSessionId).get()).data();
  assert.equal(sessionLargeDoc.snapshot_status, "complete");
  assert.equal(sessionLargeDoc.total_items, TOTAL_POSITIONS);

  const largeCountsSnap = await db.collection("inventory_sessions").doc(largeSessionId).collection("counts").get();
  assert.equal(largeCountsSnap.size, TOTAL_POSITIONS);

  const countIds = new Set(largeCountsSnap.docs.map((d) => d.id));
  assert.equal(countIds.size, TOTAL_POSITIONS); // zero duplicatas

  for (const posDoc of allPositionsSnap.docs) {
    assert.ok(countIds.has(posDoc.id), `Posição ${posDoc.id} não encontrada no snapshot!`);
  }

  console.log(`✓ Teste 1 APROVADO:`);
  console.log(`  ELIGIBLE:    ${TOTAL_POSITIONS}`);
  console.log(`  SNAPSHOTTED: ${largeCountsSnap.size}`);
  console.log(`  MISSING:     0`);
  console.log(`  DUPLICATE:   0`);

  // Cancela sessão 1 para liberar trava
  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: largeSessionId, reason: "Conclusão de teste de escala",
  });

  console.log("\n--- TEST 2: By-Location Scale Test (80 em Loc A, 40 em Loc B) ---");
  await clearCollections("warehouse_positions", "warehouse_batches", "inventory_items", "inventory_sessions");
  await db.collection("warehouse_control").doc("inventory_lock").set({ active_session_id: null, updated_at: now });

  const locA = "LOC-ESCALA-A";
  const locB = "LOC-ESCALA-B";

  let locBatch = db.batch();
  let locWrites = 0;

  for (let i = 1; i <= 80; i++) {
    const matId = `mat-loc-a-${i}`;
    const batchId = `batch-loc-a-${i}`;
    const posId = derivePositionDocId(matId, batchId, locA);

    locBatch.set(db.collection("inventory_items").doc(matId), {
      id: matId, name: `Mat A ${i}`, category_id: "geral", unit: "un", current_quantity: 5, active: true, warehouse_managed: true, updated_at: now,
    });
    locBatch.set(db.collection("warehouse_batches").doc(batchId), {
      id: batchId, material_id: matId, lot_number: `LOT-A-${i}`, current_quantity: 5, status: "active", updated_at: now,
    });
    locBatch.set(db.collection("warehouse_positions").doc(posId), {
      id: posId, material_id: matId, batch_id: batchId, location_id: locA, location_name: "Local A", quantity: 5, unit: "un", updated_at: now,
    });
    locWrites += 3;
    if (locWrites >= 300) {
      await locBatch.commit();
      locBatch = db.batch();
      locWrites = 0;
    }
  }

  for (let i = 1; i <= 40; i++) {
    const matId = `mat-loc-b-${i}`;
    const batchId = `batch-loc-b-${i}`;
    const posId = derivePositionDocId(matId, batchId, locB);

    locBatch.set(db.collection("inventory_items").doc(matId), {
      id: matId, name: `Mat B ${i}`, category_id: "geral", unit: "un", current_quantity: 5, active: true, warehouse_managed: true, updated_at: now,
    });
    locBatch.set(db.collection("warehouse_batches").doc(batchId), {
      id: batchId, material_id: matId, lot_number: `LOT-B-${i}`, current_quantity: 5, status: "active", updated_at: now,
    });
    locBatch.set(db.collection("warehouse_positions").doc(posId), {
      id: posId, material_id: matId, batch_id: batchId, location_id: locB, location_name: "Local B", quantity: 5, unit: "un", updated_at: now,
    });
    locWrites += 3;
    if (locWrites >= 300) {
      await locBatch.commit();
      locBatch = db.batch();
      locWrites = 0;
    }
  }
  if (locWrites > 0) await locBatch.commit();

  const openLocRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Local A (80 Posições)",
    scope_type: "by_location",
    scope_ref_id: locA,
  });
  const locSessionId = openLocRes.session_id;

  const locCountsSnap = await db.collection("inventory_sessions").doc(locSessionId).collection("counts").get();
  assert.equal(locCountsSnap.size, 80);
  for (const doc of locCountsSnap.docs) {
    assert.equal(doc.data().location_id, locA);
  }
  console.log(`✓ Teste 2 APROVADO: by_location=${locA} capturou exatamente 80 posições, zero de Loc B.`);

  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: locSessionId, reason: "Fim do teste loc A",
  });

  console.log("\n--- TEST 3: By-Category Scale Test (70 em FOOD, 50 em HYGIENE) ---");
  await clearCollections("warehouse_positions", "warehouse_batches", "inventory_items", "inventory_sessions");
  await db.collection("warehouse_control").doc("inventory_lock").set({ active_session_id: null, updated_at: now });

  const catFood = "cat-food";
  const catHygiene = "cat-hygiene";
  let catBatch = db.batch();
  let catWrites = 0;

  for (let i = 1; i <= 70; i++) {
    const matId = `mat-food-${i}`;
    const batchId = `batch-food-${i}`;
    const posId = derivePositionDocId(matId, batchId, "LOC-1");

    catBatch.set(db.collection("inventory_items").doc(matId), {
      id: matId, name: `Alimento ${i}`, category_id: catFood, unit: "kg", current_quantity: 2, active: true, warehouse_managed: true, updated_at: now,
    });
    catBatch.set(db.collection("warehouse_batches").doc(batchId), {
      id: batchId, material_id: matId, lot_number: `LOT-FOOD-${i}`, current_quantity: 2, status: "active", updated_at: now,
    });
    catBatch.set(db.collection("warehouse_positions").doc(posId), {
      id: posId, material_id: matId, batch_id: batchId, location_id: "LOC-1", location_name: "Depósito 1", quantity: 2, unit: "kg", updated_at: now,
    });
    catWrites += 3;
    if (catWrites >= 300) {
      await catBatch.commit();
      catBatch = db.batch();
      catWrites = 0;
    }
  }

  for (let i = 1; i <= 50; i++) {
    const matId = `mat-hyg-${i}`;
    const batchId = `batch-hyg-${i}`;
    const posId = derivePositionDocId(matId, batchId, "LOC-1");

    catBatch.set(db.collection("inventory_items").doc(matId), {
      id: matId, name: `Higiene ${i}`, category_id: catHygiene, unit: "un", current_quantity: 2, active: true, warehouse_managed: true, updated_at: now,
    });
    catBatch.set(db.collection("warehouse_batches").doc(batchId), {
      id: batchId, material_id: matId, lot_number: `LOT-HYG-${i}`, current_quantity: 2, status: "active", updated_at: now,
    });
    catBatch.set(db.collection("warehouse_positions").doc(posId), {
      id: posId, material_id: matId, batch_id: batchId, location_id: "LOC-1", location_name: "Depósito 1", quantity: 2, unit: "un", updated_at: now,
    });
    catWrites += 3;
    if (catWrites >= 300) {
      await catBatch.commit();
      catBatch = db.batch();
      catWrites = 0;
    }
  }
  if (catWrites > 0) await catBatch.commit();

  const openCatRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Categoria Food (70 Posições)",
    scope_type: "by_category",
    scope_ref_id: catFood,
  });
  const catSessionId = openCatRes.session_id;

  const catCountsSnap = await db.collection("inventory_sessions").doc(catSessionId).collection("counts").get();
  assert.equal(catCountsSnap.size, 70);
  for (const doc of catCountsSnap.docs) {
    assert.ok(doc.data().material_id.startsWith("mat-food-"));
  }
  console.log(`✓ Teste 3 APROVADO: by_category=${catFood} capturou exatamente 70 posições, zero de Hygiene.`);

  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: catSessionId, reason: "Fim do teste cat food",
  });

  console.log("\n--- TEST 4: Concurrent Movement During Snapshot Build ---");
  // Simula sessão em 'building'
  const simSessionRef = db.collection("inventory_sessions").doc();
  await simSessionRef.set({
    id: simSessionRef.id,
    title: "Sessão Em Construção",
    scope_type: "full_warehouse",
    status: "in_progress",
    snapshot_status: "building",
    opened_by_ra: operator.ra,
    opened_by_name: operator.name,
    opened_at: now,
    total_items: 0,
    created_at: now,
    updated_at: now,
  });
  await db.collection("warehouse_control").doc("inventory_lock").set({
    active_session_id: simSessionRef.id,
    scope_type: "full_warehouse",
    updated_at: now,
  });

  let blockedMovementErr = null;
  try {
    await executeWarehouseConsumption(db, operator, {
      material_id: "mat-food-1",
      batch_id: "batch-food-1",
      source_location_id: "LOC-1",
      quantity: 1,
      reason: "Consumo durante construção de snapshot",
      idempotency_key: "consume-during-build-test",
    });
  } catch (err) {
    blockedMovementErr = err;
  }
  assert.ok(blockedMovementErr);
  assert.equal(blockedMovementErr.code, "failed-precondition");
  assert.equal(blockedMovementErr.details?.code, "warehouse/inventory-scope-locked");
  console.log("✓ Teste 4 APROVADO: Movimentação bloqueada com warehouse/inventory-scope-locked durante building.");

  console.log("\n--- TEST 5: Snapshot Completeness Guard ---");
  // Contagem, reconciliação e homologação devem rejeitar se snapshot_status !== 'complete'
  let countBlockedErr = null;
  try {
    await callFn(callables.adminWarehouseRecordInventoryCount, {
      session_id: simSessionRef.id,
      count_id: "qualquer-id",
      counted_quantity: 1,
    });
  } catch (err) {
    countBlockedErr = err;
  }
  assert.ok(countBlockedErr);
  assert.equal(countBlockedErr.code, "failed-precondition");

  let reconBlockedErr = null;
  try {
    await callFn(callables.adminWarehouseStartReconciliation, {
      session_id: simSessionRef.id,
    });
  } catch (err) {
    reconBlockedErr = err;
  }
  assert.ok(reconBlockedErr);
  assert.equal(reconBlockedErr.code, "failed-precondition");

  let homoBlockedErr = null;
  try {
    await callFn(callables.adminWarehouseHomologateInventorySession, {
      session_id: simSessionRef.id,
    });
  } catch (err) {
    homoBlockedErr = err;
  }
  assert.ok(homoBlockedErr);
  assert.equal(homoBlockedErr.code, "failed-precondition");

  console.log("✓ Teste 5 APROVADO: Contagem, reconciliação e homologação bloqueadas para snapshot incompleto.");

  // Cancelamento da sessão simulada limpa a trava
  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: simSessionRef.id, reason: "Limpeza de sessão simulada",
  });

  console.log("\n--- TEST 6: Empty Full-Warehouse Inventory (0 eligible positions) ---");
  await clearCollections("warehouse_positions", "warehouse_batches", "inventory_items", "inventory_sessions");
  await db.collection("warehouse_control").doc("inventory_lock").set({ active_session_id: null, updated_at: now });

  const emptyOpenRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Geral em Almoxarifado Vazio",
    scope_type: "full_warehouse",
    notes: "Sem posições físicas existentes",
  });
  const emptySessionId = emptyOpenRes.session_id;

  const emptySessionDoc = (await db.collection("inventory_sessions").doc(emptySessionId).get()).data();
  assert.equal(emptySessionDoc.snapshot_status, "complete");
  assert.equal(emptySessionDoc.total_items, 0);

  const emptyCountsSnap = await db.collection("inventory_sessions").doc(emptySessionId).collection("counts").get();
  assert.equal(emptyCountsSnap.size, 0);

  console.log("✓ Teste 6 APROVADO: Almoxarifado vazio gerou total_items=0 e snapshot_status=complete.");

  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: emptySessionId, reason: "Limpeza de inventário vazio",
  });

  console.log("\n=== TODOS OS 6 TESTES DE ESCALA E COMPLETUDE PASSARAM COM SUCESSO! ===");
}

runScaleTests()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("\n[SCALE-TEST-FAILURE]", err);
    process.exit(1);
  });
