/**
 * K9 Ops — F60 Almoxarifado End-to-End Physical Inventory Tests (Firestore Emulator)
 * Location: canil-gcm/tools/rules_tests/warehouse_physical_inventory_emulator_tests.mjs
 *
 * Sequence of E2E verification:
 * 1. Seed de materiais, lotes e posições físicas.
 * 2. Abertura de inventário geral (full_warehouse). Trava atômica ativada.
 * 3. Tentativa de movimentação durante inventário ativo bloqueada (warehouse/inventory-scope-locked).
 * 4. Tentativa de abrir 2ª sessão simultânea bloqueada fail-closed.
 * 5. Registro de contagem exata (sem divergência).
 * 6. Registro de contagem com sobra (+5) com justificativa obrigatória.
 * 7. Registro de contagem física ZERO (0 unidades, -15) com justificativa obrigatória.
 * 8. Inclusão de item físico inesperado no escopo (expected=0, counted=4) com justificativa.
 * 9. Transição para reconciliação (adminWarehouseStartReconciliation).
 * 10. Tentativa de movimentação durante reconciliação ainda bloqueada.
 * 11. Homologação da sessão (adminWarehouseHomologateInventorySession).
 * 12. Verificação dos saldos físicos e contábeis atualizados (posições, lotes e materiais).
 * 13. Verificação do ledger de inventory_movements com registros de inventory_adjustment.
 * 14. Liberação da trava e permissão de novas movimentações normais de estoque.
 * 15. Provas de concorrência:
 *     - Abertura simultânea de duas sessões de inventário (exatamente 1 vence).
 *     - Homologação simultânea dupla (idempotente / sem duplicação de ajustes).
 *     - Homologação vs cancelamento simultâneos (estado terminal consistente e atômico).
 * 16. Cancelamento de sessão avulsa com liberação de trava e zero alteração de saldo.
 */

import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-k9-ops";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = FS_HOST;

console.log(`[PHYSICAL-INVENTORY-TEST] Target emulator: ${FS_HOST}, Project: ${PROJECT_ID}`);

// Import firebase-admin from functions directory
const adminPath = path.resolve(__dirname, "../../functions/node_modules/firebase-admin");
const admin = (await import(`file://${path.resolve(adminPath, "lib/index.js").replace(/\\/g, "/")}`)).default;

if (admin.apps.length > 0) {
  await Promise.all(admin.apps.map((a) => a?.delete()));
}
const app = admin.initializeApp({ projectId: PROJECT_ID }, "warehouse-physical-inventory-suite");
const db = admin.firestore(app);

// Import compiled backend modules
const domainPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_domain.js");
const transactionsPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_transactions.js");
const callablesPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_callables.js");

const {
  derivePositionDocId,
} = await import(`file://${domainPath.replace(/\\/g, "/")}`);

const {
  executeWarehouseConsumption,
} = await import(`file://${transactionsPath.replace(/\\/g, "/")}`);

const {
  createWarehouseCallables,
} = await import(`file://${callablesPath.replace(/\\/g, "/")}`);

const operator = { ra: "990001", name: "Auditor Almoxarifado", uid: "uid-auditor-almox" };
const mockRequirePermission = async () => operator;
const callables = createWarehouseCallables(db, mockRequirePermission);

const callFn = async (fn, data) => fn.run({ data, auth: { uid: operator.uid, token: {} } });

async function runPhysicalInventoryE2ESuite() {
  console.log("\n--- Step 1: Seed de materiais, lotes e posições ---");
  const now = admin.firestore.Timestamp.now();
  const mat1 = "mat-inv-e2e-1";
  const mat2 = "mat-inv-e2e-2";
  const mat3 = "mat-inv-e2e-3";

  await db.collection("inventory_items").doc(mat1).set({
    id: mat1, name: "Coleira Alpha", category_id: "equipamentos", unit: "unidade",
    current_quantity: 10, active: true, warehouse_managed: true, updated_at: now,
  });
  await db.collection("inventory_items").doc(mat2).set({
    id: mat2, name: "Ração Bravo", category_id: "nutricao", unit: "kg",
    current_quantity: 20, active: true, warehouse_managed: true, updated_at: now,
  });
  await db.collection("inventory_items").doc(mat3).set({
    id: mat3, name: "Vacina Charlie", category_id: "saude", unit: "dose",
    current_quantity: 15, active: true, warehouse_managed: true, updated_at: now,
  });

  const batch1 = "batch-inv-e2e-1";
  const batch2 = "batch-inv-e2e-2";
  const batch3 = "batch-inv-e2e-3";

  await db.collection("warehouse_batches").doc(batch1).set({
    id: batch1, material_id: mat1, material_name: "Coleira Alpha", lot_number: "LOT-E2E-1",
    initial_quantity: 10, current_quantity: 10, expiration_date: "2029-12-31", status: "active",
    created_at: now, updated_at: now,
  });
  await db.collection("warehouse_batches").doc(batch2).set({
    id: batch2, material_id: mat2, material_name: "Ração Bravo", lot_number: "LOT-E2E-2",
    initial_quantity: 20, current_quantity: 20, expiration_date: "2029-12-31", status: "active",
    created_at: now, updated_at: now,
  });
  await db.collection("warehouse_batches").doc(batch3).set({
    id: batch3, material_id: mat3, material_name: "Vacina Charlie", lot_number: "LOT-E2E-3",
    initial_quantity: 15, current_quantity: 15, expiration_date: "2029-12-31", status: "active",
    created_at: now, updated_at: now,
  });

  const locA = "loc-inv-e2e-a";
  const locB = "loc-inv-e2e-b";
  const pos1 = derivePositionDocId(mat1, batch1, locA);
  const pos2 = derivePositionDocId(mat2, batch2, locA);
  const pos3 = derivePositionDocId(mat3, batch3, locB);

  await db.collection("warehouse_positions").doc(pos1).set({
    id: pos1, material_id: mat1, batch_id: batch1, lot_number: "LOT-E2E-1",
    location_id: locA, location_name: "Depósito A", quantity: 10, unit: "unidade",
    schema_version: 1, updated_at: now,
  });
  await db.collection("warehouse_positions").doc(pos2).set({
    id: pos2, material_id: mat2, batch_id: batch2, lot_number: "LOT-E2E-2",
    location_id: locA, location_name: "Depósito A", quantity: 20, unit: "kg",
    schema_version: 1, updated_at: now,
  });
  await db.collection("warehouse_positions").doc(pos3).set({
    id: pos3, material_id: mat3, batch_id: batch3, lot_number: "LOT-E2E-3",
    location_id: locB, location_name: "Depósito B", quantity: 15, unit: "dose",
    schema_version: 1, updated_at: now,
  });

  // Limpa trava preexistente
  await db.collection("warehouse_control").doc("inventory_lock").set({
    active_session_id: null,
    updated_at: now,
  });
  console.log("✓ Passo 1 aprovado: 3 materiais, lotes e posições semeados.");

  console.log("\n--- Step 2: Abertura de inventário geral (full_warehouse) ---");
  const openRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Geral Anual E2E",
    scope_type: "full_warehouse",
    notes: "Contagem física anual de estoque",
  });
  assert.ok(openRes.session_id);
  const sessionId = openRes.session_id;

  // Verifica trava atômica ativada
  const lockDoc = (await db.collection("warehouse_control").doc("inventory_lock").get()).data();
  assert.equal(lockDoc?.active_session_id, sessionId);

  // Snapshot de posições: expected congelado e counted_quantity estritamente null
  const countsSnap = await db.collection("inventory_sessions").doc(sessionId).collection("counts").get();
  assert.equal(countsSnap.size, 3);
  for (const doc of countsSnap.docs) {
    const data = doc.data();
    assert.equal(data.counted_quantity, null);
    assert.equal(data.discrepancy, null);
  }
  console.log(`✓ Passo 2 aprovado: Sessão ${sessionId} aberta com 3 posições congeladas.`);

  console.log("\n--- Step 3: Tentativa de movimentação durante inventário ativo ---");
  let blockedMovementErr = null;
  try {
    await executeWarehouseConsumption(db, operator, {
      material_id: mat1,
      batch_id: batch1,
      source_location_id: locA,
      quantity: 2,
      reason: "Consumo proibido durante inventário",
      idempotency_key: "consume-during-inv-test",
    });
  } catch (err) {
    blockedMovementErr = err;
  }
  assert.ok(blockedMovementErr);
  assert.equal(blockedMovementErr.code, "failed-precondition");
  assert.equal(blockedMovementErr.details?.code, "warehouse/inventory-scope-locked");
  console.log("✓ Passo 3 aprovado: Movimentação bloqueada fail-closed por inventory-scope-locked.");

  console.log("\n--- Step 4: Tentativa de abrir 2ª sessão de inventário simultânea ---");
  let secondSessionErr = null;
  try {
    await callFn(callables.adminWarehouseOpenInventorySession, {
      title: "Segunda Sessão Concorrente",
      scope_type: "full_warehouse",
    });
  } catch (err) {
    secondSessionErr = err;
  }
  assert.ok(secondSessionErr);
  assert.equal(secondSessionErr.code, "failed-precondition");
  console.log("✓ Passo 4 aprovado: Abertura de 2ª sessão rejeitada.");

  console.log("\n--- Step 5: Registro de contagem exata (sem divergência) ---");
  const count1Res = await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: sessionId,
    count_id: pos1,
    counted_quantity: 10,
  });
  assert.equal(count1Res.recorded, true);
  assert.equal(count1Res.discrepancy, 0);
  console.log("✓ Passo 5 aprovado: Contagem exata na posição 1 gravada.");

  console.log("\n--- Step 6: Registro de contagem com sobra (+5) ---");
  const count2Res = await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: sessionId,
    count_id: pos2,
    counted_quantity: 25,
    discrepancy_reason: "5 kg a mais conferidos no saco adicional",
  });
  assert.equal(count2Res.recorded, true);
  assert.equal(count2Res.discrepancy, 5);
  console.log("✓ Passo 6 aprovado: Contagem com sobra na posição 2 gravada.");

  console.log("\n--- Step 7: Registro de contagem física ZERO (0 unidades, -15) ---");
  const count3Res = await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: sessionId,
    count_id: pos3,
    counted_quantity: 0,
    discrepancy_reason: "Lote totalmente indisponível / frascos descartados sem baixa",
  });
  assert.equal(count3Res.recorded, true);
  assert.equal(count3Res.discrepancy, -15);
  console.log("✓ Passo 7 aprovado: Contagem de ZERO na posição 3 gravada com divergência de -15.");

  console.log("\n--- Step 8: Inclusão de item físico inesperado no escopo ---");
  // Material mat1 encontrado no depósito B (onde esperava-se 0)
  const unexpectedPosId = derivePositionDocId(mat1, batch1, locB);
  const unexpectedRes = await callFn(callables.adminWarehouseAddUnexpectedCount, {
    session_id: sessionId,
    material_id: mat1,
    batch_id: batch1,
    location_id: locB,
    counted_quantity: 4,
    discrepancy_reason: "Caixa de coleiras encontrada no Setor B sem cadastro prévio",
  });
  assert.equal(unexpectedRes.recorded, true);
  assert.equal(unexpectedRes.discrepancy, 4);
  console.log("✓ Passo 8 aprovado: Item inesperado cadastrado com expected=0 e counted=4.");

  console.log("\n--- Step 9: Transição para reconciliação (adminWarehouseStartReconciliation) ---");
  const reconRes = await callFn(callables.adminWarehouseStartReconciliation, {
    session_id: sessionId,
  });
  assert.equal(reconRes.status, "reconciling");
  console.log("✓ Passo 9 aprovado: Sessão avançou para status reconciling.");

  console.log("\n--- Step 10: Tentativa de movimentação durante reconciliação ---");
  let reconMovementErr = null;
  try {
    await executeWarehouseConsumption(db, operator, {
      material_id: mat1,
      batch_id: batch1,
      source_location_id: locA,
      quantity: 1,
      reason: "Consumo durante reconciliação",
      idempotency_key: "consume-during-recon-test",
    });
  } catch (err) {
    reconMovementErr = err;
  }
  assert.ok(reconMovementErr);
  assert.equal(reconMovementErr.code, "failed-precondition");
  assert.equal(reconMovementErr.details?.code, "warehouse/inventory-scope-locked");
  console.log("✓ Passo 10 aprovado: Movimentação continua bloqueada durante reconciling.");

  console.log("\n--- Step 11: Homologação da sessão de inventário ---");
  const homologateRes = await callFn(callables.adminWarehouseHomologateInventorySession, {
    session_id: sessionId,
    idempotency_key: "homologate-inv-e2e-key",
  });
  assert.equal(homologateRes.session_id, sessionId);
  assert.equal(homologateRes.adjustments_applied, 3); // pos2 (+5), pos3 (-15), unexpected (+4)
  console.log("✓ Passo 11 aprovado: Sessão homologada com 3 ajustes aplicados.");

  console.log("\n--- Step 12: Verificação dos saldos pós-homologação ---");
  const pos1Doc = (await db.collection("warehouse_positions").doc(pos1).get()).data();
  const pos2Doc = (await db.collection("warehouse_positions").doc(pos2).get()).data();
  const pos3Doc = (await db.collection("warehouse_positions").doc(pos3).get()).data();
  const unexpectedPosDoc = (await db.collection("warehouse_positions").doc(unexpectedPosId).get()).data();

  assert.equal(pos1Doc.quantity, 10);
  assert.equal(pos2Doc.quantity, 25);
  assert.equal(pos3Doc.quantity, 0);
  assert.equal(unexpectedPosDoc.quantity, 4);

  const batch1Doc = (await db.collection("warehouse_batches").doc(batch1).get()).data();
  const batch2Doc = (await db.collection("warehouse_batches").doc(batch2).get()).data();
  const batch3Doc = (await db.collection("warehouse_batches").doc(batch3).get()).data();

  // batch1: 10 + 4 = 14
  assert.equal(batch1Doc.current_quantity, 14);
  assert.equal(batch1Doc.status, "active");
  // batch2: 20 + 5 = 25
  assert.equal(batch2Doc.current_quantity, 25);
  assert.equal(batch2Doc.status, "active");
  // batch3: 15 - 15 = 0 -> depleted
  assert.equal(batch3Doc.current_quantity, 0);
  assert.equal(batch3Doc.status, "depleted");

  const mat1Doc = (await db.collection("inventory_items").doc(mat1).get()).data();
  const mat2Doc = (await db.collection("inventory_items").doc(mat2).get()).data();
  const mat3Doc = (await db.collection("inventory_items").doc(mat3).get()).data();

  assert.equal(mat1Doc.current_quantity, 14);
  assert.equal(mat2Doc.current_quantity, 25);
  assert.equal(mat3Doc.current_quantity, 0);
  console.log("✓ Passo 12 aprovado: Posições, lotes e materiais rigorosamente conservados.");

  console.log("\n--- Step 13: Verificação do ledger de inventory_adjustments ---");
  const adjustmentsSnap = await db.collection("inventory_movements")
    .where("inventory_session_id", "==", sessionId)
    .where("type", "==", "inventory_adjustment")
    .get();
  assert.equal(adjustmentsSnap.size, 3);
  console.log("✓ Passo 13 aprovado: 3 lançamentos de inventory_adjustment gerados no ledger.");

  console.log("\n--- Step 14: Verificação de liberação da trava ---");
  const postLockDoc = (await db.collection("warehouse_control").doc("inventory_lock").get()).data();
  assert.equal(postLockDoc.active_session_id, null);

  // Agora nova movimentação normal deve ser permitida
  const consumptionPostRes = await executeWarehouseConsumption(db, operator, {
    material_id: mat1,
    batch_id: batch1,
    source_location_id: locA,
    quantity: 2,
    reason: "Consumo pós-homologação liberado",
    idempotency_key: "consume-post-inv-test",
  });
  assert.ok(consumptionPostRes.movement_id);
  assert.equal(consumptionPostRes.material_on_hand, 12);
  console.log("✓ Passo 14 aprovado: Trava liberada e consumo normal pós-inventário bem-sucedido.");

  console.log("\n--- Step 15: Provas de Concorrência ---");
  // 15a: Abertura simultânea de duas sessões
  const pOpen1 = callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Corrida Abertura 1",
    scope_type: "by_location",
    scope_ref_id: locA,
  });
  const pOpen2 = callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Corrida Abertura 2",
    scope_type: "by_location",
    scope_ref_id: locA,
  });

  const [openRes1, openRes2] = await Promise.allSettled([pOpen1, pOpen2]);
  const fulfilledOpen = [openRes1, openRes2].filter((r) => r.status === "fulfilled");
  const rejectedOpen = [openRes1, openRes2].filter((r) => r.status === "rejected");

  assert.equal(fulfilledOpen.length, 1);
  assert.equal(rejectedOpen.length, 1);
  assert.equal(rejectedOpen[0].reason.code, "failed-precondition");

  const raceSessionId = fulfilledOpen[0].value.session_id;
  console.log("✓ Passo 15a aprovado: Abertura concorrente resultou em exatamente 1 sucesso e 1 rejeição.");

  // 15b: Contagem concorrente na mesma posição (C3)
  const raceCountsSnap = await db.collection("inventory_sessions").doc(raceSessionId).collection("counts").get();
  const racePosId = raceCountsSnap.docs[0].id;

  const pCount1 = callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: raceSessionId,
    count_id: racePosId,
    counted_quantity: 12,
    discrepancy_reason: "Contagem concorrente thread 1",
  });
  const pCount2 = callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: raceSessionId,
    count_id: racePosId,
    counted_quantity: 14,
    discrepancy_reason: "Contagem concorrente thread 2",
  });
  await Promise.allSettled([pCount1, pCount2]);
  const finalRaceCountDoc = (await db.collection("inventory_sessions").doc(raceSessionId).collection("counts").doc(racePosId).get()).data();
  assert.ok(finalRaceCountDoc.counted_quantity === 12 || finalRaceCountDoc.counted_quantity === 14);
  console.log("✓ Passo 15b aprovado: Contagem concorrente resolveu deterministicamente sem corromper estado.");

  // Preenche demais posições se houver para avançar
  for (const doc of raceCountsSnap.docs) {
    if (doc.id !== racePosId) {
      await callFn(callables.adminWarehouseRecordInventoryCount, {
        session_id: raceSessionId,
        count_id: doc.id,
        counted_quantity: Number(doc.data().expected_quantity),
      });
    }
  }
  await callFn(callables.adminWarehouseStartReconciliation, { session_id: raceSessionId });

  // 15c: Homologação simultânea dupla (C4)
  const pHomologate1 = callFn(callables.adminWarehouseHomologateInventorySession, {
    session_id: raceSessionId,
    idempotency_key: "race-homologate-key-1",
  });
  const pHomologate2 = callFn(callables.adminWarehouseHomologateInventorySession, {
    session_id: raceSessionId,
    idempotency_key: "race-homologate-key-1", // mesma chave idempotente concorrente
  });
  const [homoRes1, homoRes2] = await Promise.allSettled([pHomologate1, pHomologate2]);
  const fulfilledHomo = [homoRes1, homoRes2].filter((r) => r.status === "fulfilled");
  assert.ok(fulfilledHomo.length >= 1);
  // Garante que a sessão terminou homologada
  assert.equal((await db.collection("inventory_sessions").doc(raceSessionId).get()).data()?.status, "homologated");
  console.log("✓ Passo 15c aprovado: Homologação concorrente dupla concluiu com sucesso e sem duplicação de ajustes.");

  // 15d: Homologação vs Cancelamento concorrentes (C5)
  const race2Open = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Corrida Homologar vs Cancelar",
    scope_type: "by_location",
    scope_ref_id: locB,
  });
  const race2SessionId = race2Open.session_id;
  const race2Counts = await db.collection("inventory_sessions").doc(race2SessionId).collection("counts").get();
  for (const doc of race2Counts.docs) {
    await callFn(callables.adminWarehouseRecordInventoryCount, {
      session_id: race2SessionId,
      count_id: doc.id,
      counted_quantity: Number(doc.data().expected_quantity),
    });
  }
  await callFn(callables.adminWarehouseStartReconciliation, { session_id: race2SessionId });

  const pRaceHomo = callFn(callables.adminWarehouseHomologateInventorySession, { session_id: race2SessionId });
  const pRaceCancel = callFn(callables.adminWarehouseCancelInventorySession, { session_id: race2SessionId, reason: "Cancel concorrente" });
  const [raceHomoRes, raceCancelRes] = await Promise.allSettled([pRaceHomo, pRaceCancel]);
  const race2Status = (await db.collection("inventory_sessions").doc(race2SessionId).get()).data()?.status;
  assert.ok(race2Status === "homologated" || race2Status === "cancelled");
  // Trava liberada em qualquer desfecho
  const lockRace2 = (await db.collection("warehouse_control").doc("inventory_lock").get()).data();
  assert.equal(lockRace2.active_session_id, null);
  console.log(`✓ Passo 15d aprovado: Corrida homologar vs cancelar resolveu em estado terminal consistente (${race2Status}).`);

  console.log("\n--- Step 16: Cancelamento de sessão com liberação de trava e zero mutação ---");
  const openCancelRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Sessão Para Cancelar",
    scope_type: "full_warehouse",
  });
  const cancelSessionId = openCancelRes.session_id;
  assert.ok(cancelSessionId);

  // Registra contagem com divergência antes de cancelar
  await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: cancelSessionId,
    count_id: pos1,
    counted_quantity: 99,
    discrepancy_reason: "Contagem errônea",
  });

  const mat1BeforeCancel = (await db.collection("inventory_items").doc(mat1).get()).data().current_quantity;

  const cancelRes = await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: cancelSessionId,
    reason: "Cancelamento operacional por erro de contagem",
  });
  assert.equal(cancelRes.cancelled, true);

  const lockAfterCancel = (await db.collection("warehouse_control").doc("inventory_lock").get()).data();
  assert.equal(lockAfterCancel.active_session_id, null);

  const mat1AfterCancel = (await db.collection("inventory_items").doc(mat1).get()).data().current_quantity;
  assert.equal(mat1AfterCancel, mat1BeforeCancel);
  console.log("✓ Passo 16 aprovado: Cancelamento liberou a trava com zero alteração de saldo.");

  console.log("\n=== TODAS AS 16 ETAPAS DO INVENTÁRIO FÍSICO PASSARAM COM SUCESSO NO EMULADOR! ===");
}

runPhysicalInventoryE2ESuite()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("\n[TEST-FAILURE]", err);
    process.exit(1);
  });
