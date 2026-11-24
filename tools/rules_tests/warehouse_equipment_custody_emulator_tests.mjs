/**
 * K9 Ops — F60 Almoxarifado End-to-End Equipment & Custody Tests (Firestore Emulator)
 * Location: canil-gcm/tools/rules_tests/warehouse_equipment_custody_emulator_tests.mjs
 *
 * Sequence of E2E verification:
 * 1. Cadastro de 2 equipamentos (PAT-001 condição good, PAT-002 condição damaged -> status damaged).
 * 2. Rejeição de abertura de cautela em PAT-002 (danificado).
 * 3. Abertura de cautela em PAT-001 para o policial RA 123456. Status vai para in_custody.
 * 4. Tentativa de dupla custódia concorrente em PAT-001 (rejeitada).
 * 5. Tentativa de aposentar PAT-001 durante a cautela (rejeitada).
 * 6. Devolução de cautela de PAT-001 com condição good (status volta para available).
 * 7. Nova cautela e devolução com avaria (damaged -> status damaged).
 * 8. Transição de PAT-002 de damaged para maintenance e posterior reparo para available.
 * 9. Aposentadoria de PAT-002 sem cautela (aprovada).
 * 10. Validação de registros em auditLogs e integridade do índice de identificadores.
 */

import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-k9-ops";
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = FS_HOST;

console.log(`[EQUIPMENT-CUSTODY-TEST] Target emulator: ${FS_HOST}, Project: ${PROJECT_ID}`);

// Import firebase-admin from functions directory
const adminPath = path.resolve(__dirname, "../../functions/node_modules/firebase-admin");
const admin = (await import(`file://${path.resolve(adminPath, "lib/index.js").replace(/\\/g, "/")}`)).default;

if (admin.apps.length > 0) {
  await Promise.all(admin.apps.map((a) => a?.delete()));
}
const app = admin.initializeApp({ projectId: PROJECT_ID }, "warehouse-equipment-custody-suite");
const db = admin.firestore(app);

// Import compiled backend modules
const transactionsPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_transactions.js");
const callablesPath = path.resolve(__dirname, "../../functions/lib/warehouse/warehouse_callables.js");

const {
  executeOpenCustody,
  executeReturnCustody,
  executeCancelCustody,
} = await import(`file://${transactionsPath.replace(/\\/g, "/")}`);

const {
  createWarehouseCallables,
} = await import(`file://${callablesPath.replace(/\\/g, "/")}`);

const operator = { ra: "990001", name: "Operador Almoxarifado", uid: "uid-operador-almox" };
const mockRequirePermission = async () => operator;
const callables = createWarehouseCallables(db, mockRequirePermission);

const callFn = async (fn, data) => fn.run({ data, auth: { uid: operator.uid, token: {} } });

async function runEquipmentCustodyE2ESuite() {
  console.log("\n--- Certificando warehouse_control para permitir reservas canônicas ---");
  await db.collection("warehouse_control").doc("legacy_reconciliation_status").set({
    status: "completed",
    certified_at: new Date().toISOString(),
  });

  console.log("\n--- Step 1: Cadastro de 2 equipamentos (PAT-001 good, PAT-002 damaged) ---");
  const eq1Res = await callFn(callables.adminWarehouseUpsertEquipment, {
    mode: "create",
    name: "Coleira Tática K9 Patrulhamento",
    category_id: "equipamentos",
    identifier_code: "PAT-001",
    condition: "good",
    current_location_id: "armazem-central",
    current_location_name: "Armazém Central Almoxarifado",
  });
  assert.equal(eq1Res.saved, true);
  assert.equal(eq1Res.status, "available");

  const eq1Doc = await db.collection("warehouse_equipment").doc(eq1Res.id).get();
  assert.equal(eq1Doc.exists, true);
  assert.equal(eq1Doc.data()?.status, "available");
  assert.equal(eq1Doc.data()?.condition, "good");
  assert.equal(eq1Doc.data()?.identifier_code, "PAT-001");
  assert.equal(eq1Doc.data()?.normalized_identifier, "pat-001");

  const eq2Res = await callFn(callables.adminWarehouseUpsertEquipment, {
    mode: "create",
    name: "Guia Avariada de Treinamento",
    category_id: "equipamentos",
    identifier_code: "PAT-002",
    condition: "damaged",
    current_location_id: "armazem-central",
    current_location_name: "Armazém Central Almoxarifado",
  });
  assert.equal(eq2Res.saved, true);
  assert.equal(eq2Res.status, "damaged");

  const eq2Doc = await db.collection("warehouse_equipment").doc(eq2Res.id).get();
  assert.equal(eq2Doc.exists, true);
  assert.equal(eq2Doc.data()?.status, "damaged");
  assert.equal(eq2Doc.data()?.condition, "damaged");
  console.log("✓ Passo 1 aprovado: PAT-001 criado com status available e PAT-002 com status damaged.");

  console.log("\n--- Step 2: Rejeição de abertura de cautela em PAT-002 (danificado) ---");
  await assert.rejects(
    executeOpenCustody(db, operator, {
      equipment_id: eq2Res.id,
      borrower_ra: "123456",
      borrower_name: "GCM Santos",
      condition_at_dispatch: "good",
      purpose: "daily_duty",
      idempotency_key: "e2e-open-damaged-rejected",
    }),
    (err) => err?.code === "failed-precondition",
  );
  console.log("✓ Passo 2 aprovado: Abertura de cautela em equipamento danificado rejeitada fail-closed.");

  console.log("\n--- Step 3: Abertura de cautela em PAT-001 para o policial RA 123456 ---");
  const openCustodyRes = await executeOpenCustody(db, operator, {
    equipment_id: eq1Res.id,
    borrower_ra: "123456",
    borrower_name: "GCM Santos",
    condition_at_dispatch: "good",
    purpose: "daily_duty",
    linked_dog_name: "K9 Thor",
    dispatch_notes: "Cautela para turno operacional diurno",
    idempotency_key: "e2e-open-pat001-custody",
  });
  assert.equal(openCustodyRes.status, "in_custody");
  assert.ok(openCustodyRes.custody_id);

  const eq1AfterCustody = await db.collection("warehouse_equipment").doc(eq1Res.id).get();
  assert.equal(eq1AfterCustody.data()?.status, "in_custody");
  assert.equal(eq1AfterCustody.data()?.active_custody_id, openCustodyRes.custody_id);

  const custodyDoc = await db.collection("warehouse_custodies").doc(openCustodyRes.custody_id).get();
  assert.equal(custodyDoc.exists, true);
  assert.equal(custodyDoc.data()?.status, "active");
  assert.equal(custodyDoc.data()?.borrower_ra, "123456");
  console.log("✓ Passo 3 aprovado: Cautela emitida, status do equipamento alterado para in_custody.");

  console.log("\n--- Step 4: Tentativa de dupla custódia concorrente em PAT-001 ---");
  await assert.rejects(
    executeOpenCustody(db, operator, {
      equipment_id: eq1Res.id,
      borrower_ra: "654321",
      borrower_name: "GCM Silva",
      condition_at_dispatch: "good",
      purpose: "daily_duty",
      idempotency_key: "e2e-open-pat001-dup-rejected",
    }),
    (err) => err?.code === "failed-precondition",
  );
  console.log("✓ Passo 4 aprovado: Dupla custódia no mesmo equipamento rejeitada.");

  console.log("\n--- Step 5: Tentativa de aposentar PAT-001 durante a cautela ---");
  await assert.rejects(
    callFn(callables.adminWarehouseRetireEquipment, {
      equipment_id: eq1Res.id,
      reason: "Tentativa indevida de baixa com cautela ativa",
    }),
    (err) => err?.code === "failed-precondition",
  );
  console.log("✓ Passo 5 aprovado: Aposentadoria de equipamento sob cautela bloqueada.");

  console.log("\n--- Step 6: Devolução de cautela de PAT-001 com condição good ---");
  const returnGoodRes = await executeReturnCustody(db, operator, {
    custody_id: openCustodyRes.custody_id,
    condition_at_return: "good",
    return_notes: "Devolução sem avarias ao término do plantão",
    idempotency_key: "e2e-return-pat001-good",
  });
  assert.equal(returnGoodRes.equipment_status, "available");

  const eq1AfterGoodReturn = await db.collection("warehouse_equipment").doc(eq1Res.id).get();
  assert.equal(eq1AfterGoodReturn.data()?.status, "available");
  assert.equal(eq1AfterGoodReturn.data()?.active_custody_id, null);
  assert.equal(eq1AfterGoodReturn.data()?.condition, "good");

  const custodyAfterReturn = await db.collection("warehouse_custodies").doc(openCustodyRes.custody_id).get();
  assert.equal(custodyAfterReturn.data()?.status, "returned");
  console.log("✓ Passo 6 aprovado: Cautela encerrada e equipamento restaurado para status available.");

  console.log("\n--- Step 7: Nova cautela e devolução com avaria (damaged -> status damaged) ---");
  const openCustody2 = await executeOpenCustody(db, operator, {
    equipment_id: eq1Res.id,
    borrower_ra: "778899",
    borrower_name: "GCM Oliveira",
    condition_at_dispatch: "good",
    purpose: "operation",
    idempotency_key: "e2e-open-pat001-round2",
  });
  assert.equal(openCustody2.status, "in_custody");

  // Devolução com condição damaged
  const returnDamagedRes = await executeReturnCustody(db, operator, {
    custody_id: openCustody2.custody_id,
    condition_at_return: "damaged",
    return_notes: "Fivela de aço rompida durante operação",
    idempotency_key: "e2e-return-pat001-dmg",
  });
  assert.equal(returnDamagedRes.equipment_status, "damaged");

  const eq1AfterDmgReturn = await db.collection("warehouse_equipment").doc(eq1Res.id).get();
  assert.equal(eq1AfterDmgReturn.data()?.status, "damaged");
  assert.equal(eq1AfterDmgReturn.data()?.condition, "damaged");
  assert.equal(eq1AfterDmgReturn.data()?.active_custody_id, null);
  console.log("✓ Passo 7 aprovado: Devolução com avaria atualizou condição e status para damaged.");

  console.log("\n--- Step 8: Transição de PAT-002 de damaged para maintenance e posterior reparo para available ---");
  const maintRes = await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eq2Res.id,
    target_status: "maintenance",
    notes: "Encaminhado para costura especializada",
  });
  assert.equal(maintRes.status, "maintenance");

  const eq2InMaint = await db.collection("warehouse_equipment").doc(eq2Res.id).get();
  assert.equal(eq2InMaint.data()?.status, "maintenance");

  // Retorno da manutenção após reparo com nova condição good
  const repOkRes = await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eq2Res.id,
    target_status: "available",
    condition: "good",
    notes: "Costura refeita e aprovada nos testes de tração",
  });
  assert.equal(repOkRes.status, "available");
  assert.equal(repOkRes.condition, "good");

  const eq2Repaired = await db.collection("warehouse_equipment").doc(eq2Res.id).get();
  assert.equal(eq2Repaired.data()?.status, "available");
  assert.equal(eq2Repaired.data()?.condition, "good");
  console.log("✓ Passo 8 aprovado: PAT-002 transitou damaged -> maintenance -> available com sucesso.");

  console.log("\n--- Step 9: Aposentadoria de PAT-002 sem cautela (aprovada) ---");
  const retireRes = await callFn(callables.adminWarehouseRetireEquipment, {
    equipment_id: eq2Res.id,
    reason: "Baixa por obsolescência técnica de modelo antigo",
  });
  assert.equal(retireRes.retired, true);
  assert.equal(retireRes.status, "retired");

  const eq2RetiredDoc = await db.collection("warehouse_equipment").doc(eq2Res.id).get();
  assert.equal(eq2RetiredDoc.data()?.status, "retired");
  assert.equal(eq2RetiredDoc.data()?.active, false);
  assert.equal(eq2RetiredDoc.data()?.retire_reason, "Baixa por obsolescência técnica de modelo antigo");
  assert.equal(eq2RetiredDoc.data()?.retired_by, operator.uid);
  console.log("✓ Passo 9 aprovado: Aposentadoria formal de equipamento concluída com auditoria.");

  console.log("\n--- Step 10: Validação de registros em auditLogs e integridade do índice de identificadores ---");
  const idxPat1 = await db.collection("warehouse_equipment_identifiers").doc("pat-001").get();
  const idxPat2 = await db.collection("warehouse_equipment_identifiers").doc("pat-002").get();
  assert.equal(idxPat1.exists, true);
  assert.equal(idxPat1.data()?.equipment_id, eq1Res.id);
  assert.equal(idxPat2.exists, true);
  assert.equal(idxPat2.data()?.equipment_id, eq2Res.id);

  const auditLogsSnap = await db.collection("auditLogs")
    .where("entity_type", "==", "warehouse_equipment")
    .get();
  assert.ok(auditLogsSnap.size >= 6, `Esperado pelo menos 6 auditLogs para equipamentos, encontrado: ${auditLogsSnap.size}`);

  const actions = auditLogsSnap.docs.map((d) => d.data()?.action);
  assert.ok(actions.includes("warehouse_equipment_created"));
  assert.ok(actions.includes("warehouse_custody_opened"));
  assert.ok(actions.includes("warehouse_custody_returned"));
  assert.ok(actions.includes("warehouse_equipment_status_changed"));
  assert.ok(actions.includes("warehouse_equipment_retired"));
  console.log(`✓ Passo 10 aprovado: ${auditLogsSnap.size} auditLogs verificados. Índices canônicos intactos.`);

  console.log("\n=== TODAS AS ETAPAS DO VERTICAL DE EQUIPAMENTOS E CAUTELAS PASSARAM COM SUCESSO! ===");
}

runEquipmentCustodyE2ESuite().catch((err) => {
  console.error("ERRO NO FLUXO DE EQUIPAMENTOS E CAUTELA:", err);
  process.exit(1);
});
