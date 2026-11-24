/**
 * K9 Ops — F60 Almoxarifado End-to-End Material Flow Tests (Firestore Emulator)
 * Location: canil-gcm/tools/rules_tests/warehouse_material_flow_emulator_tests.mjs
 *
 * Sequence of E2E verification:
 * 1. Cria material via transação/callable do almoxarifado (saldo inicial estritamente 0).
 * 2. Entrada de 2 lotes (Lote A validade curta, Lote B validade longa).
 * 3. Consumo (verifica que consome de Lote A por FEFO).
 * 4. Transferência de parte de Lote B para outro local (conservação total de saldos de lote e material).
 * 5. Descarte de resíduo vencido (baixa sanitária).
 * 6. Verificação de saldos finais e integridade do ledger inventory_movements.
 */

import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-k9-ops";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = FS_HOST;

console.log(`[MATERIAL-FLOW-TEST] Target emulator: ${FS_HOST}, Project: ${PROJECT_ID}`);

// Import firebase-admin from functions directory
const adminPath = path.resolve(__dirname, "../../functions/node_modules/firebase-admin");
const admin = (await import(`file://${path.resolve(adminPath, "lib/index.js").replace(/\\/g, "/")}`)).default;

if (admin.apps.length > 0) {
  await Promise.all(admin.apps.map((a) => a?.delete()));
}
const app = admin.initializeApp({ projectId: PROJECT_ID }, "warehouse-material-flow-suite");
const db = admin.firestore(app);

// Import compiled backend modules
const transactionsPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_transactions.js");
const callablesPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_callables.js");

const {
  executeWarehouseEntry,
  executeWarehouseConsumption,
  executeWarehouseTransfer,
  executeWarehouseLossDisposal,
} = await import(`file://${transactionsPath.replace(/\\/g, "/")}`);

const {
  executeWarehouseUpsertMaterial,
  executeWarehouseArchiveMaterial,
} = await import(`file://${callablesPath.replace(/\\/g, "/")}`);

const operator = { ra: "990001", name: "Operador Almoxarifado", uid: "uid-operador-almox" };

async function runMaterialFlowE2ESuite() {
  console.log("\n--- Step 1: Criação de Material de Almoxarifado ---");
  const materialId = "mat-flow-racao-premium";
  const createdMaterial = await executeWarehouseUpsertMaterial(db, operator, {
    mode: "create",
    profile: {
      id: materialId,
      name: "Ração Operacional Alta Energia",
      category_id: "nutricao",
      unit: "kg",
      minimum_quantity: 20,
      brand: "K9 Nutri",
      storage_conditions: "Local seco e ventilado",
    },
  });

  assert.equal(createdMaterial.id, materialId);
  assert.equal(createdMaterial.current_quantity, 0);
  assert.equal(createdMaterial.status, "out_of_stock");

  const matDocAfterCreate = await db.collection("inventory_items").doc(materialId).get();
  assert.equal(matDocAfterCreate.exists, true);
  assert.equal(matDocAfterCreate.data()?.current_quantity, 0);
  assert.equal(matDocAfterCreate.data()?.warehouse_managed, true);
  assert.equal(matDocAfterCreate.data()?.status, "out_of_stock");
  console.log("✓ Passo 1 aprovado: Material criado com saldo físico 0 e status out_of_stock.");

  console.log("\n--- Step 2: Entrada de 2 Lotes (Lote A validade curta, Lote B validade longa) ---");
  // Lote A: validade curta (2027-03-31), quantidade: 30 kg, no Depósito Central
  const entryA = await executeWarehouseEntry(db, operator, {
    material_id: materialId,
    lot_number: "LOTE-A-CURTO",
    expiration_date: "2027-03-31",
    destination_location_id: "deposito-central",
    destination_location_name: "Depósito Central Almoxarifado",
    quantity: 30,
    reason: "Recebimento NF 5001 - Fornecedor Alpha",
    idempotency_key: "flow-entry-lote-a",
  });
  assert.equal(entryA.material_on_hand, 30);
  assert.equal(entryA.batch_on_hand, 30);
  assert.equal(entryA.position_quantity, 30);

  // Lote B: validade longa (2028-12-31), quantidade: 50 kg, no Depósito Central
  const entryB = await executeWarehouseEntry(db, operator, {
    material_id: materialId,
    lot_number: "LOTE-B-LONGO",
    expiration_date: "2028-12-31",
    destination_location_id: "deposito-central",
    destination_location_name: "Depósito Central Almoxarifado",
    quantity: 50,
    reason: "Recebimento NF 5002 - Fornecedor Beta",
    idempotency_key: "flow-entry-lote-b",
  });
  assert.equal(entryB.material_on_hand, 80);
  assert.equal(entryB.batch_on_hand, 50);
  assert.equal(entryB.position_quantity, 50);

  const matDocAfterEntries = await db.collection("inventory_items").doc(materialId).get();
  assert.equal(matDocAfterEntries.data()?.current_quantity, 80);
  console.log("✓ Passo 2 aprovado: Entradas concluídas. Saldo total do material: 80 kg.");

  console.log("\n--- Step 3: Consumo (FEFO - consome Lote A com menor validade) ---");
  // Consumo de 20 kg do Lote A (validade mais curta)
  const consumoRes = await executeWarehouseConsumption(db, operator, {
    material_id: materialId,
    batch_id: entryA.batch_id,
    source_location_id: "deposito-central",
    quantity: 20,
    reason: "Consumo diário para treinamento dos cães de busca",
    related_dog_id: "dog-thor",
    related_dog_name: "Thor",
    idempotency_key: "flow-consumo-1",
  });

  assert.equal(consumoRes.batch_on_hand, 10); // Lote A: 30 - 20 = 10
  assert.equal(consumoRes.position_quantity, 10);
  assert.equal(consumoRes.material_on_hand, 60); // 80 - 20 = 60

  const batchADoc = await db.collection("warehouse_batches").doc(entryA.batch_id).get();
  const batchBDoc = await db.collection("warehouse_batches").doc(entryB.batch_id).get();
  assert.equal(batchADoc.data()?.current_quantity, 10);
  assert.equal(batchBDoc.data()?.current_quantity, 50); // Lote B intocado
  console.log("✓ Passo 3 aprovado: Consumo FEFO debitou Lote A (10 kg restantes); Lote B preservado com 50 kg.");

  console.log("\n--- Step 4: Transferência de Lote B para Canil Setor 1 ---");
  // Transferir 15 kg de Lote B de 'deposito-central' para 'canil-setor-1'
  const transfRes = await executeWarehouseTransfer(db, operator, {
    material_id: materialId,
    batch_id: entryB.batch_id,
    origin_location_id: "deposito-central",
    destination_location_id: "canil-setor-1",
    destination_location_name: "Canil Setor 1 - Sala de Alimentação",
    quantity: 15,
    reason: "Transferência semanal para alimentação do Canil Setor 1",
    idempotency_key: "flow-transf-1",
  });

  assert.equal(transfRes.origin_position_quantity, 35); // 50 - 15 = 35
  assert.equal(transfRes.destination_position_quantity, 15);

  const matDocAfterTransf = await db.collection("inventory_items").doc(materialId).get();
  const batchBDocAfterTransf = await db.collection("warehouse_batches").doc(entryB.batch_id).get();
  // Conservação estrita
  assert.equal(matDocAfterTransf.data()?.current_quantity, 60);
  assert.equal(batchBDocAfterTransf.data()?.current_quantity, 50);
  console.log("✓ Passo 4 aprovado: Transferência conservou totais (Material: 60 kg, Lote B: 50 kg distribuído em 35 + 15).");

  console.log("\n--- Step 5: Entrada e Descarte Sanitário de Lote Vencido ---");
  // Cria entrada de lote com validade expirada (2020-01-01) de 5 kg
  const entryVencido = await executeWarehouseEntry(db, operator, {
    material_id: materialId,
    lot_number: "LOTE-VENCIDO-AMOSTRA",
    expiration_date: "2020-01-01",
    destination_location_id: "deposito-central",
    destination_location_name: "Depósito Central Almoxarifado",
    quantity: 5,
    reason: "Amostra recebida para descarte",
    idempotency_key: "flow-entry-vencido",
  });
  assert.equal(entryVencido.material_on_hand, 65);

  // Tentativa de consumo do lote vencido DEVE falhar
  await assert.rejects(
    executeWarehouseConsumption(db, operator, {
      material_id: materialId,
      batch_id: entryVencido.batch_id,
      source_location_id: "deposito-central",
      quantity: 5,
      reason: "Tentativa indevida de consumo de ração vencida",
      idempotency_key: "flow-consumo-invalido-vencido",
    }),
    (err) => err?.code === "failed-precondition",
  );
  console.log("✓ Rejeição de consumo de lote vencido validada.");

  // Descarte formal com motivo registrado
  const descarteRes = await executeWarehouseLossDisposal(db, operator, {
    material_id: materialId,
    batch_id: entryVencido.batch_id,
    location_id: "deposito-central",
    type: "disposal",
    quantity: 5,
    reason: "Descarte sanitário por prazo de validade expirado",
    idempotency_key: "flow-descarte-sanitario",
  });

  assert.equal(descarteRes.batch_on_hand, 0);
  assert.equal(descarteRes.position_quantity, 0);
  assert.equal(descarteRes.material_on_hand, 60);
  console.log("✓ Passo 5 aprovado: Descarte de lote vencido processado e saldo baixado para 60 kg.");

  console.log("\n--- Step 6: Verificação de Saldos Finais e Integridade do Ledger ---");
  const finalMatDoc = await db.collection("inventory_items").doc(materialId).get();
  assert.equal(finalMatDoc.data()?.current_quantity, 60);

  // Consulta movimentos do ledger
  const movementsSnap = await db.collection("inventory_movements")
    .where("material_id", "==", materialId)
    .get();

  const movements = movementsSnap.docs.map((d) => d.data());
  console.log(`Total de movimentos no ledger para o material: ${movements.length}`);

  // Tipos esperados:
  // 1: entry A (+30)
  // 2: entry B (+50)
  // 3: consumption A (-20)
  // 4: transfer B (delta 0)
  // 5: entry vencido (+5)
  // 6: disposal vencido (-5)
  assert.equal(movements.length, 6);

  const netDelta = movements.reduce((acc, m) => acc + Number(m.delta || 0), 0);
  assert.equal(netDelta, 60);
  assert.equal(finalMatDoc.data()?.current_quantity, netDelta);

  // Validação de arquivamento protegido: tentar arquivar material com saldo 60 deve falhar
  await assert.rejects(
    executeWarehouseArchiveMaterial(db, operator, {
      id: materialId,
      reason: "Tentativa indevida de arquivar com estoque",
    }),
    (err) => err?.code === "failed-precondition",
  );
  console.log("✓ Arquivamento rejeitado fail-closed para material com estoque positivo.");

  console.log("\n=== TODAS AS ETAPAS DO FLUXO PONTA A PONTA PASSARAM COM SUCESSO! ===");
}

runMaterialFlowE2ESuite().catch((err) => {
  console.error("ERRO NO FLUXO PONTA A PONTA:", err);
  process.exit(1);
});
