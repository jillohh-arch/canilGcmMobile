import * as assert from "assert";
import {
  executeWarehouseEntry, executeWarehouseConsumption, executeWarehouseTransfer,
  executeWarehouseLossDisposal, executeOpenCustody,
  executeReturnCustody, executeCancelCustody, executeStartInventorySession, executeHomologateInventorySession,
} from "./warehouse_transactions";
import {
  derivePositionDocId,
  formatBusinessDate,
  isBatchExpiredServer,
  isWarehouseAuthorizedBucket,
  normalizeEquipmentIdentifier,
  reconcileLegacyEquipmentIdentifiers,
  LEGACY_RECONCILIATION_REQUIRED_MESSAGE,
  validateWarehousePhotoUrl,
} from "./warehouse_domain";
import {
  reserveEquipmentIdentifier,
  executeWarehouseUpsertMaterial,
  executeWarehouseArchiveMaterial,
  executeWarehouseUpsertEquipment,
  createWarehouseCallables,
} from "./warehouse_callables";

const caller = {ra: "123", name: "Operador", uid: "uid-123"};
type Data = Record<string, any>;

class FakeDb {
  docs = new Map<string, Data>();
  nextId = 0;
  collection(path: string): any {
    const db = this;
    const createQuery = (filters: Array<{ field: string; op: string; value: any }>, limitCount?: number) => ({
      path,
      filters,
      limitCount,
      doc(id?: string): any {
        const key = `${path}/${id || `generated-${++db.nextId}`}`;
        return {
          id: key.split("/").slice(-1)[0],
          path: key,
          collection(child: string) { return db.collection(`${key}/${child}`); },
          get: async () => {
            const value = db.docs.get(key);
            return { exists: !!value, data: () => value };
          },
          set: async (data: Data) => { db.docs.set(key, { ...data }); },
          update: async (data: Data) => {
            const prev = db.docs.get(key) || {};
            db.docs.set(key, { ...prev, ...data });
          },
        };
      },
      where(field: string, op: string, value: any) {
        return createQuery([...filters, {field, op, value}], limitCount);
      },
      limit(count: number) {
        return createQuery(filters, count);
      },
      get: async () => {
        let entries = [...db.docs].filter(([key]) => key.startsWith(`${path}/`) &&
          key.slice(path.length + 1).split("/").length === 1);
        for (const f of filters) {
          entries = entries.filter(([, v]) => {
            if (f.op === "==") return v[f.field] === f.value;
            if (f.op === ">") return v[f.field] > f.value;
            if (f.op === "<") return v[f.field] < f.value;
            if (f.op === "in") return Array.isArray(f.value) && f.value.includes(v[f.field]);
            return true;
          });
        }
        if (limitCount !== undefined) entries = entries.slice(0, limitCount);
        const docs = entries.map(([key, value]) => ({id: key.split("/").slice(-1)[0], data: () => value}));
        return {docs, size: docs.length, empty: docs.length === 0};
      },
    });
    return createQuery([]);
  }
  batch(): any {
    const operations: (() => void)[] = [];
    return {
      set: (ref: any, data: Data) => {
        operations.push(() => {
          const prev = this.docs.get(ref.path) || {};
          const next = { ...data };
          for (const [k, v] of Object.entries(data)) {
            if (v && typeof v === "object" && "operand" in v && typeof (v as any).operand === "number") {
              const current = typeof prev[k] === "number" ? prev[k] : 0;
              next[k] = current + (v as any).operand;
            }
          }
          this.docs.set(ref.path, next);
        });
        return this;
      },
      update: (ref: any, data: Data) => {
        operations.push(() => {
          const prev = this.docs.get(ref.path) || {};
          const next = { ...prev, ...data };
          for (const [k, v] of Object.entries(data)) {
            if (v && typeof v === "object" && "operand" in v && typeof (v as any).operand === "number") {
              const current = typeof prev[k] === "number" ? prev[k] : 0;
              next[k] = current + (v as any).operand;
            }
          }
          this.docs.set(ref.path, next);
        });
        return this;
      },
      commit: async () => {
        for (const op of operations) op();
      },
    };
  }
  async runTransaction<T>(handler: (transaction: any) => Promise<T>): Promise<T> {
    const writes: (() => void)[] = [];
    const tx = {
      get: async (ref: any): Promise<any> => {
        if (ref.filters !== undefined) {
          return ref.get();
        }
        const value = this.docs.get(ref.path);
        return {exists: !!value, data: () => value};
      },
      set: (ref: any, data: Data) => {
        writes.push(() => {
          const prev = this.docs.get(ref.path) || {};
          const next = { ...data };
          for (const [k, v] of Object.entries(data)) {
            if (v && typeof v === "object" && "operand" in v && typeof (v as any).operand === "number") {
              const current = typeof prev[k] === "number" ? prev[k] : 0;
              next[k] = current + (v as any).operand;
            }
          }
          this.docs.set(ref.path, next);
        });
      },
      update: (ref: any, data: Data) => {
        writes.push(() => {
          const prev = this.docs.get(ref.path) || {};
          const next = { ...prev, ...data };
          for (const [k, v] of Object.entries(data)) {
            if (v && typeof v === "object" && "operand" in v && typeof (v as any).operand === "number") {
              const current = typeof prev[k] === "number" ? prev[k] : 0;
              next[k] = current + (v as any).operand;
            }
          }
          this.docs.set(ref.path, next);
        });
      },
    };
    const result = await handler(tx);
    for (const write of writes) write();
    return result;
  }
}

async function rejects(operation: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(operation, (error: any) => error.code === code);
}

// ---------------------------------------------------------------------------
// F60 B2 — FEFO fixtures determinísticas
// ---------------------------------------------------------------------------
// As fixtures transacionais precisam de validades RELATIVAS à data de execução:
// datas fixas (ex.: 2026-11-01) viram lotes vencidos com o passar do tempo e
// quebram a prioridade FEFO de forma dependente do relógio. A referência é a
// data de negócio canônica (America/Sao_Paulo) e pode ser congelada por
// K9_WAREHOUSE_TEST_DATE=YYYY-MM-DD para reprodução exata de uma execução.
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

const REAL_TODAY = formatBusinessDate(new Date());

function businessDateReference(): string {
  const override = (process.env.K9_WAREHOUSE_TEST_DATE || "").trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(override)) {
    assert.equal(
      new Date(`${override}T00:00:00.000Z`).toISOString().slice(0, 10),
      override,
      "K9_WAREHOUSE_TEST_DATE inválida",
    );
    // Nunca antes do relógio real: validades precisam ficar à frente do
    // "hoje" usado pelo servidor, que não é injetado.
    return override > REAL_TODAY ? override : REAL_TODAY;
  }
  return REAL_TODAY;
}

function businessDatePlusDays(base: string, days: number): string {
  const [year, month, day] = base.split("-").map(Number);
  const shifted = Date.UTC(year, month - 1, day) + days * ONE_DAY_MS;
  return new Date(shifted).toISOString().slice(0, 10);
}

const TEST_TODAY = businessDateReference();
// Margens folgadas: validade não muda de classificação mesmo se a data de
// negócio avançar um dia entre a montagem das fixtures e a execução.
const TEST_DATE_VALID_SOON = businessDatePlusDays(TEST_TODAY, 90);
const TEST_DATE_VALID_LATER = businessDatePlusDays(TEST_TODAY, 180);
const TEST_DATE_VALID_LATEST = businessDatePlusDays(TEST_TODAY, 270);
const TEST_DATE_EXPIRED = businessDatePlusDays(REAL_TODAY, -30);

async function main(): Promise<void> {
  assert.match(formatBusinessDate(new Date("2026-01-01T01:00:00Z")), /^2025-12-31$/);
  assert.equal(isBatchExpiredServer("2025-12-31", "2026-01-01"), true);

  // 1. Testes de normalização canônica
  assert.equal(normalizeEquipmentIdentifier(" SERIAL-1 "), "serial-1");
  assert.equal(normalizeEquipmentIdentifier("SERIAL-1"), "serial-1");
  assert.equal(normalizeEquipmentIdentifier("serial-1"), "serial-1");
  assert.equal(normalizeEquipmentIdentifier("Serial-1"), "serial-1");
  assert.equal(normalizeEquipmentIdentifier("  CÃO-01\u0301  ".normalize("NFD")), "cão-01́".toLowerCase().normalize("NFC"));
  assert.throws(() => normalizeEquipmentIdentifier(""), (e: any) => e.code === "invalid-argument");
  assert.throws(() => normalizeEquipmentIdentifier("   "), (e: any) => e.code === "invalid-argument");
  assert.throws(() => normalizeEquipmentIdentifier("code/with/slash"), (e: any) => e.code === "invalid-argument");
  assert.throws(() => normalizeEquipmentIdentifier(null), (e: any) => e.code === "invalid-argument");
  assert.throws(() => normalizeEquipmentIdentifier(123), (e: any) => e.code === "invalid-argument");

  // 2. Testes de reconciliação legada dry-run (pura)
  const legacyFixtures = [
    { id: "eq-1", identifier_code: "SERIAL-A" },
    { id: "eq-2", identifier_code: "serial-a" }, // duplicata
    { id: "eq-3", identifier_code: "Serial-B" },
    { id: "eq-4", identifier_code: "" },         // missing
    { id: "eq-5", identifier_code: "invalid/slash" }, // invalid
    { id: "eq-6" }, // usa id como código -> "eq-6"
  ];
  const reconReport = reconcileLegacyEquipmentIdentifiers(legacyFixtures);
  assert.equal(reconReport.total, 6);
  assert.equal(reconReport.duplicates, 2); // eq-1 e eq-2
  assert.equal(reconReport.missing, 1);    // eq-4
  assert.equal(reconReport.invalid, 1);    // eq-5
  assert.equal(reconReport.indexable, 2);  // eq-3 e eq-6
  assert.deepEqual(reconReport.duplicatesDetail["serial-a"], ["eq-1", "eq-2"]);

  // 3. Testes operacionais de reserva de identificador de equipamento
  const db = new FakeDb();

  // Novo equipamento quando reconciliação NÃO certificada -> falha fechada com failed-precondition
  await rejects(
    db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-new", "SERIAL-1")),
    "failed-precondition",
  );
  try {
    await db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-new", "SERIAL-1"));
    assert.fail("Deveria ter falhado");
  } catch (err: any) {
    assert.equal(err.message, LEGACY_RECONCILIATION_REQUIRED_MESSAGE);
  }

  // Equipamento existente sendo atualizado é permitido mesmo antes da certificação
  await db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-existing", "SERIAL-EXISTING", true));
  assert.equal(db.docs.get("warehouse_equipment_identifiers/serial-existing")?.equipment_id, "eq-existing");

  // Certifica reconciliação legada no warehouse_control
  db.docs.set("warehouse_control/legacy_reconciliation_status", {
    status: "completed",
    certified_at: new Date().toISOString(),
  });

  // Novo cadastro permitido após certificação
  await db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-1", "SERIAL-1"));
  // Colisão em caixa diferente com id diferente -> already-exists
  await rejects(db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-2", "serial-1")), "already-exists");
  await rejects(db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-2", "Serial-1")), "already-exists");
  // Mesma reserva pelo mesmo proprietário -> idempotente
  await db.runTransaction((tx) => reserveEquipmentIdentifier(db as any, tx, "eq-1", "SERIAL-1"));

  // Verificação de índice exato sem varredura em larga escala (scale-safe)
  const scaleDb = new FakeDb();
  scaleDb.docs.set("warehouse_control/legacy_reconciliation_status", { status: "completed" });
  for (let i = 0; i < 600; i++) {
    // Insere direto no índice canônico para simular 600 docs
    scaleDb.docs.set(`warehouse_equipment_identifiers/code-${i}`, {
      equipment_id: `eq-${i}`,
      identifier_code: `CODE-${i}`,
      normalized_identifier: `code-${i}`,
    });
  }
  // Cadastro de item 601 não falha com teto ou varredura: consulta apenas o doc exato
  await scaleDb.runTransaction((tx) => reserveEquipmentIdentifier(scaleDb as any, tx, "eq-601", "CODE-601"));
  assert.equal(scaleDb.docs.get("warehouse_equipment_identifiers/code-601")?.equipment_id, "eq-601");
  // Colisão no scaleDb
  await rejects(scaleDb.runTransaction((tx) => reserveEquipmentIdentifier(scaleDb as any, tx, "eq-other", "code-601")), "already-exists");

  db.docs.set("inventory_items/m", {id: "m", name: "Material", unit: "un", category_id: "cat", current_quantity: 0, active: true});
  const base = {material_id: "m", lot_number: "L1", expiration_date: TEST_DATE_VALID_LATER, destination_location_id: "loc", destination_location_name: "Local", quantity: 5, reason: "Recebimento", idempotency_key: "key-1"};
  const beforeInvalidEntries = db.docs.size;
  await rejects(executeWarehouseEntry(db as any, caller, {...base, quantity: NaN}), "invalid-argument");
  await rejects(executeWarehouseEntry(db as any, caller, {...base, expiration_date: "2026-02-30"}), "invalid-argument");
  await rejects(executeWarehouseEntry(db as any, caller, {...base, expiration_date: "2026-02-29"}), "invalid-argument");
  await rejects(executeWarehouseEntry(db as any, caller, {...base, expiration_date: "2026-13-01"}), "invalid-argument");
  assert.equal(db.docs.size, beforeInvalidEntries);
  const entry = await executeWarehouseEntry(db as any, caller, base);
  assert.equal(entry.material_on_hand, 5);
  assert.deepEqual(await executeWarehouseEntry(db as any, caller, base), entry);
  await rejects(executeWarehouseEntry(db as any, caller, {...base, quantity: 7}), "already-exists");
  const batch_id = entry.batch_id;
  const consumption = {material_id: "m", batch_id, source_location_id: "loc", quantity: 2, reason: "Uso", idempotency_key: "consume-1"};
  await rejects(executeWarehouseEntry(db as any, caller, {...base, idempotency_key: ""}), "invalid-argument");
  await rejects(executeWarehouseConsumption(db as any, caller, {...consumption, idempotency_key: null}), "invalid-argument");
  const session = await executeStartInventorySession(db as any, caller, {title: "Contagem", scope_type: "full_warehouse"});
  assert.equal(db.docs.get(`inventory_sessions/${session.session_id}/counts/${entry.position_id}`)?.counted_quantity, null);
  await rejects(executeWarehouseConsumption(db as any, caller, consumption), "failed-precondition");
  await rejects(executeHomologateInventorySession(db as any, caller, { sessionId: session.session_id }), "failed-precondition");
  db.docs.set(`inventory_sessions/${session.session_id}/counts/${entry.position_id}`, {
    ...db.docs.get(`inventory_sessions/${session.session_id}/counts/${entry.position_id}`), counted_quantity: 4, discrepancy_reason: "Conferido",
  });
  const homologation = await executeHomologateInventorySession(db as any, caller, { sessionId: session.session_id });
  assert.equal(homologation.adjustments_applied, 1);
  assert.equal(db.docs.get("inventory_items/m")?.current_quantity, 4);
  assert.equal(db.docs.get(`warehouse_positions/${derivePositionDocId("m", batch_id, "loc")}`)?.quantity, 4);
  await rejects(executeHomologateInventorySession(db as any, caller, { sessionId: session.session_id }), "failed-precondition");
  const consumed = await executeWarehouseConsumption(db as any, caller, consumption);
  assert.deepEqual(await executeWarehouseConsumption(db as any, caller, consumption), consumed);
  assert.equal(db.docs.get("inventory_items/m")?.current_quantity, 2);
  db.docs.set("warehouse_equipment/eq", {id: "eq", active: true, condition: "good", status: "available", name: "Coleira"});
  const open = await executeOpenCustody(db as any, caller, {equipment_id: "eq", borrower_ra: "456", borrower_name: "Agente", condition_at_dispatch: "good", purpose: "training", idempotency_key: "custody-open"});
  assert.deepEqual(await executeOpenCustody(db as any, caller, {equipment_id: "eq", borrower_ra: "456", borrower_name: "Agente", condition_at_dispatch: "good", purpose: "training", idempotency_key: "custody-open"}), open);
  await rejects(executeOpenCustody(db as any, caller, {equipment_id: "eq", borrower_ra: "456", borrower_name: "Agente", condition_at_dispatch: "good", purpose: "training", idempotency_key: "custody-open-2"}), "failed-precondition");
  await rejects(executeReturnCustody(db as any, caller, {custody_id: open.custody_id, condition_at_return: "damaged", target_equipment_status: "available", idempotency_key: "invalid-return"}), "invalid-argument");
  // Regression tests for Challenges 1 & 2: reject "retired", empty, arbitrary, and non-string target_equipment_status with zero mutations
  const invalidReturnTargets: Array<{ cond: "new" | "good" | "fair" | "damaged"; target: any; key: string }> = [
    { cond: "damaged", target: "retired", key: "invalid-return-dmg-retired" },
    { cond: "good", target: "retired", key: "invalid-return-good-retired" },
    { cond: "new", target: "retired", key: "invalid-return-new-retired" },
    { cond: "fair", target: "retired", key: "invalid-return-fair-retired" },
    { cond: "good", target: "invalid_status", key: "invalid-return-arbitrary" },
    { cond: "damaged", target: "unknown", key: "invalid-return-unknown" },
    { cond: "good", target: "", key: "invalid-return-empty" },
    { cond: "good", target: 123, key: "invalid-return-number" },
  ];
  for (const tc of invalidReturnTargets) {
    await rejects(
      executeReturnCustody(db as any, caller, {
        custody_id: open.custody_id,
        condition_at_return: tc.cond,
        target_equipment_status: tc.target,
        idempotency_key: tc.key,
      }),
      "invalid-argument",
    );
    assert.equal(db.docs.get("warehouse_equipment/eq")?.status, "in_custody");
    assert.equal(db.docs.get("warehouse_equipment/eq")?.active_custody_id, open.custody_id);
    assert.equal(db.docs.get(`warehouse_custodies/${open.custody_id}`)?.status, "active");
    assert.equal(db.docs.get(`idempotency_keys/${tc.key}`), undefined);
  }
  await executeReturnCustody(db as any, caller, {custody_id: open.custody_id, condition_at_return: "damaged", idempotency_key: "custody-return"});
  assert.equal(db.docs.get("warehouse_equipment/eq")?.status, "damaged");
  const second = await executeWarehouseEntry(db as any, caller, {...base, destination_location_id: "loc2", destination_location_name: "Local 2", quantity: 3, idempotency_key: "key-2"});
  const byCategory = await executeStartInventorySession(db as any, caller, {title: "Categoria", scope_type: "by_category", scope_ref_id: "cat"});
  assert.equal(byCategory.total_positions_snapshotted, 2);
  for (const [id, quantity] of [[entry.position_id, 3], [second.position_id, 4]] as const) {
    const path = `inventory_sessions/${byCategory.session_id}/counts/${id}`;
    db.docs.set(path, {...db.docs.get(path), counted_quantity: quantity, discrepancy_reason: "Conferido"});
  }
  await executeHomologateInventorySession(db as any, caller, { sessionId: byCategory.session_id });
  assert.equal(db.docs.get("inventory_items/m")?.current_quantity, 7);
  assert.equal(db.docs.get(`warehouse_batches/${entry.batch_id}`)?.current_quantity, 7);

  // === F60 TEST EXPANSION: MATERIALS, BATCHES, POSITIONS, TRANSFERS, LOSS, IDEMPOTENCY ===
  // Test 1: Criação de material com saldo zero
  const createMaterialRes = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "create",
    profile: {
      id: "mat-test-1",
      name: "Coleira Tática K9",
      category_id: "equipamentos",
      unit: "unidade",
      minimum_quantity: 5,
      brand: "K9 Gear",
    },
  });
  assert.equal(createMaterialRes.id, "mat-test-1");
  assert.equal(createMaterialRes.current_quantity, 0);
  assert.equal(createMaterialRes.status, "out_of_stock");
  const matTest1Doc = db.docs.get("inventory_items/mat-test-1");
  assert.equal(matTest1Doc?.current_quantity, 0);
  assert.equal(matTest1Doc?.warehouse_managed, true);
  assert.equal(matTest1Doc?.active, true);

  // Test 1b: Rejeição de ID duplicado em modo create
  await rejects(
    executeWarehouseUpsertMaterial(db as any, caller, {
      mode: "create",
      profile: {
        id: "mat-test-1",
        name: "Coleira Tática Duplicada",
        category_id: "equipamentos",
        unit: "unidade",
        minimum_quantity: 2,
      },
    }),
    "already-exists",
  );

  // Test 2: Edição de metadados sem alterar saldo
  const editMaterialRes = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "edit",
    id: "mat-test-1",
    profile: {
      name: "Coleira Tática K9 Pro",
      category_id: "equipamentos",
      unit: "unidade",
      minimum_quantity: 10,
      description: "Versão Pro reforçada",
    },
  });
  assert.equal(editMaterialRes.current_quantity, 0);
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.name, "Coleira Tática K9 Pro");
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.minimum_quantity, 10);
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.current_quantity, 0);

  // Test 2b: Rejeitar tentativa de alterar saldo diretamente no modo edit
  await rejects(
    executeWarehouseUpsertMaterial(db as any, caller, {
      mode: "edit",
      id: "mat-test-1",
      profile: {
        name: "Coleira Tática K9 Pro",
        category_id: "equipamentos",
        unit: "unidade",
        minimum_quantity: 10,
        current_quantity: 50,
      },
    }),
    "failed-precondition",
  );

  // Test 3: Arquivamento de material
  // Test 3a: Arquivamento com saldo = 0 é aceito
  const archiveRes = await executeWarehouseArchiveMaterial(db as any, caller, {
    id: "mat-test-1",
    reason: "Item descontinuado pelo fabricante",
  });
  assert.equal(archiveRes.archived, true);
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.active, false);
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.status, "inactive");
  assert.equal(db.docs.get("inventory_items/mat-test-1")?.delete_reason, "Item descontinuado pelo fabricante");

  // Reativar material para os testes seguintes
  db.docs.set("inventory_items/mat-test-1", {
    ...db.docs.get("inventory_items/mat-test-1"),
    active: true,
    status: "out_of_stock",
    deleted_at: null,
  });

  // Test 4: Entrada com novo lote e reabastecimento de lote existente
  const entry1 = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-test-1",
    lot_number: "LOTE-101",
    expiration_date: TEST_DATE_VALID_LATER,
    destination_location_id: "loc-armario-1",
    destination_location_name: "Armário 1",
    quantity: 20,
    reason: "Recebimento NF 1001",
    idempotency_key: "idem-entry-101",
  });
  assert.equal(entry1.material_on_hand, 20);
  assert.equal(entry1.batch_on_hand, 20);
  assert.equal(entry1.position_quantity, 20);

  // Test 3b: Arquivamento rejeitado quando saldo > 0
  await rejects(
    executeWarehouseArchiveMaterial(db as any, caller, {
      id: "mat-test-1",
      reason: "Tentativa com saldo > 0",
    }),
    "failed-precondition",
  );

  // Test 4b: Reabastecimento do mesmo lote na mesma posição
  const entry1Reorder = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-test-1",
    lot_number: "LOTE-101",
    expiration_date: TEST_DATE_VALID_LATER,
    destination_location_id: "loc-armario-1",
    destination_location_name: "Armário 1",
    quantity: 15,
    reason: "Recebimento complemento",
    idempotency_key: "idem-entry-101-reorder",
  });
  assert.equal(entry1Reorder.material_on_hand, 35);
  assert.equal(entry1Reorder.batch_on_hand, 35);
  assert.equal(entry1Reorder.position_quantity, 35);

  // Test 5: Rejeição de entrada com lote existente mas validade conflitante
  await rejects(
    executeWarehouseEntry(db as any, caller, {
      material_id: "mat-test-1",
      lot_number: "LOTE-101",
      expiration_date: TEST_DATE_VALID_LATEST, // Validade diferente da original
      destination_location_id: "loc-armario-1",
      destination_location_name: "Armário 1",
      quantity: 10,
      reason: "Entrada conflitante",
      idempotency_key: "idem-entry-conflict",
    }),
    "failed-precondition",
  );

  // Test 6: Rejeição de alteração de unit se houver lotes com saldo
  await rejects(
    executeWarehouseUpsertMaterial(db as any, caller, {
      mode: "edit",
      id: "mat-test-1",
      profile: {
        name: "Coleira Tática K9 Pro",
        category_id: "equipamentos",
        unit: "caixa", // Alteração proibida pois saldo > 0
        minimum_quantity: 10,
      },
    }),
    "failed-precondition",
  );

  // Test 7: Consumo FEFO, lotes vencidos e lotes bloqueados
  // Cria material de ração
  await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "create",
    profile: {
      id: "mat-racao",
      name: "Ração K9 Super Performance",
      category_id: "nutricao",
      unit: "kg",
      minimum_quantity: 20,
    },
  });

  // Entrada de Lote A (validade mais curta: 2027-01-01)
  const entryLoteA = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-racao",
    lot_number: "LOTE-A",
    expiration_date: TEST_DATE_VALID_SOON,
    destination_location_id: "deposito-principal",
    destination_location_name: "Depósito Principal",
    quantity: 50,
    reason: "Recebimento lote A",
    idempotency_key: "idem-racao-a",
  });

  // Entrada de Lote B (validade mais longa: 2028-01-01)
  const entryLoteB = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-racao",
    lot_number: "LOTE-B",
    expiration_date: TEST_DATE_VALID_LATEST,
    destination_location_id: "deposito-principal",
    destination_location_name: "Depósito Principal",
    quantity: 50,
    reason: "Recebimento lote B",
    idempotency_key: "idem-racao-b",
  });
  assert.equal(db.docs.get("inventory_items/mat-racao")?.current_quantity, 100);

  // Entrada de Lote Vencido (validade passada: 2020-01-01)
  const entryLoteVencido = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-racao",
    lot_number: "LOTE-VENCIDO",
    expiration_date: TEST_DATE_EXPIRED,
    destination_location_id: "deposito-principal",
    destination_location_name: "Depósito Principal",
    quantity: 10,
    reason: "Recebimento lote vencido para teste",
    idempotency_key: "idem-racao-vencido",
  });

  // Rejeição de consumo de lote vencido
  await rejects(
    executeWarehouseConsumption(db as any, caller, {
      material_id: "mat-racao",
      batch_id: entryLoteVencido.batch_id,
      source_location_id: "deposito-principal",
      quantity: 5,
      reason: "Tentativa de consumir lote vencido",
      idempotency_key: "idem-consumo-vencido",
    }),
    "failed-precondition",
  );

  // Bloquear administrativamente Lote B
  db.docs.set(`warehouse_batches/${entryLoteB.batch_id}`, {
    ...db.docs.get(`warehouse_batches/${entryLoteB.batch_id}`),
    status: "blocked",
  });

  // Rejeição de consumo de lote bloqueado
  await rejects(
    executeWarehouseConsumption(db as any, caller, {
      material_id: "mat-racao",
      batch_id: entryLoteB.batch_id,
      source_location_id: "deposito-principal",
      quantity: 10,
      reason: "Tentativa de consumir lote bloqueado",
      idempotency_key: "idem-consumo-bloqueado",
    }),
    "failed-precondition",
  );

  // Desbloqueia Lote B
  db.docs.set(`warehouse_batches/${entryLoteB.batch_id}`, {
    ...db.docs.get(`warehouse_batches/${entryLoteB.batch_id}`),
    status: "active",
  });

  // Consumo respeita FEFO: consome de Lote A (menor validade)
  const consumoA = await executeWarehouseConsumption(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteA.batch_id,
    source_location_id: "deposito-principal",
    quantity: 30,
    reason: "Alimentação diária canil",
    idempotency_key: "idem-consumo-a-1",
  });
  assert.equal(consumoA.batch_on_hand, 20); // Lote A: 50 - 30 = 20
  assert.equal(consumoA.material_on_hand, 80); // 110 - 30 = 80

  // Test 8: Transferência: conserva totais de material e lote, decrementa origem, incrementa destino; rejeita origem == destino
  await rejects(
    executeWarehouseTransfer(db as any, caller, {
      material_id: "mat-racao",
      batch_id: entryLoteB.batch_id,
      origin_location_id: "deposito-principal",
      destination_location_id: "deposito-principal", // Origem == Destino
      destination_location_name: "Depósito Principal",
      quantity: 15,
      reason: "Transferência inválida mesma origem/destino",
      idempotency_key: "idem-transf-invalida",
    }),
    "invalid-argument",
  );

  const matBeforeTransf = db.docs.get("inventory_items/mat-racao")?.current_quantity;
  const batchBBeforeTransf = db.docs.get(`warehouse_batches/${entryLoteB.batch_id}`)?.current_quantity;

  const transfRes = await executeWarehouseTransfer(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteB.batch_id,
    origin_location_id: "deposito-principal",
    destination_location_id: "canil-box-01",
    destination_location_name: "Canil Box 01",
    quantity: 15,
    reason: "Abastecimento Box 01",
    idempotency_key: "idem-transf-ok",
  });
  assert.equal(transfRes.origin_position_quantity, 35); // 50 - 15 = 35
  assert.equal(transfRes.destination_position_quantity, 15);
  // Conservação estrita de totais de material e lote
  assert.equal(db.docs.get("inventory_items/mat-racao")?.current_quantity, matBeforeTransf);
  assert.equal(db.docs.get(`warehouse_batches/${entryLoteB.batch_id}`)?.current_quantity, batchBBeforeTransf);

  // Test 9: Perda e descarte: requer motivo; descarte de estoque vencido funciona; saldo reduz
  // Rejeição sem motivo
  await rejects(
    executeWarehouseLossDisposal(db as any, caller, {
      material_id: "mat-racao",
      batch_id: entryLoteVencido.batch_id,
      location_id: "deposito-principal",
      type: "disposal",
      quantity: 10,
      reason: "   ",
      idempotency_key: "idem-descarte-sem-motivo",
    }),
    "invalid-argument",
  );

  // Descarte de lote vencido funciona com sucesso
  const matBeforeDescarte = db.docs.get("inventory_items/mat-racao")?.current_quantity;
  const descarteRes = await executeWarehouseLossDisposal(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteVencido.batch_id,
    location_id: "deposito-principal",
    type: "disposal",
    quantity: 10,
    reason: "Descarte sanitário de lote com validade expirada",
    idempotency_key: "idem-descarte-vencido-ok",
  });
  assert.equal(descarteRes.position_quantity, 0);
  assert.equal(descarteRes.batch_on_hand, 0);
  assert.equal(descarteRes.material_on_hand, matBeforeDescarte - 10);

  // Test 10: Replay idempotente em todas as mutações
  // Replay de entrada
  const replayEntry = await executeWarehouseEntry(db as any, caller, {
    material_id: "mat-racao",
    lot_number: "LOTE-A",
    expiration_date: TEST_DATE_VALID_SOON,
    destination_location_id: "deposito-principal",
    destination_location_name: "Depósito Principal",
    quantity: 50,
    reason: "Recebimento lote A",
    idempotency_key: "idem-racao-a",
  });
  assert.deepEqual(replayEntry, entryLoteA);

  // Replay de consumo
  const replayConsumo = await executeWarehouseConsumption(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteA.batch_id,
    source_location_id: "deposito-principal",
    quantity: 30,
    reason: "Alimentação diária canil",
    idempotency_key: "idem-consumo-a-1",
  });
  assert.deepEqual(replayConsumo, consumoA);

  // Replay de transferência
  const replayTransf = await executeWarehouseTransfer(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteB.batch_id,
    origin_location_id: "deposito-principal",
    destination_location_id: "canil-box-01",
    destination_location_name: "Canil Box 01",
    quantity: 15,
    reason: "Abastecimento Box 01",
    idempotency_key: "idem-transf-ok",
  });
  assert.deepEqual(replayTransf, transfRes);

  // Replay de descarte
  const replayDescarte = await executeWarehouseLossDisposal(db as any, caller, {
    material_id: "mat-racao",
    batch_id: entryLoteVencido.batch_id,
    location_id: "deposito-principal",
    type: "disposal",
    quantity: 10,
    reason: "Descarte sanitário de lote com validade expirada",
    idempotency_key: "idem-descarte-vencido-ok",
  });
  assert.deepEqual(replayDescarte, descarteRes);

  // === F60 TEST EXPANSION: EQUIPMENT & CUSTODY OPERATIONAL VERTICAL ===
  const mockRequirePermission = async () => caller;
  const callables = createWarehouseCallables(db as any, mockRequirePermission as any);

  // Helper para simular chamada onCall local
  const callFn = async (fn: any, data: any) => fn.run({ data, auth: { uid: caller.uid, token: {} } });

  // 1. Criação de equipamento com status available e reserva de identificador canônico
  const eqCreateRes = await callFn(callables.adminWarehouseUpsertEquipment, {
    mode: "create",
    name: "Coleira de Rastreio K9",
    category_id: "equipamentos",
    identifier_code: "PAT-001",
    condition: "good",
    current_location_id: "armazem-central",
  });
  assert.equal(eqCreateRes.saved, true);
  assert.equal(eqCreateRes.status, "available");
  const eq1Doc = db.docs.get(`warehouse_equipment/${eqCreateRes.id}`);
  assert.equal(eq1Doc?.name, "Coleira de Rastreio K9");
  assert.equal(eq1Doc?.identifier_code, "PAT-001");
  assert.equal(eq1Doc?.normalized_identifier, "pat-001");
  assert.equal(eq1Doc?.status, "available");
  assert.equal(eq1Doc?.condition, "good");
  assert.equal(eq1Doc?.active, true);
  assert.equal(db.docs.get("warehouse_equipment_identifiers/pat-001")?.equipment_id, eqCreateRes.id);

  // 1b. Criação de equipamento danificado: status inicial DEVE ser damaged
  const eqDamagedRes = await callFn(callables.adminWarehouseUpsertEquipment, {
    mode: "create",
    name: "Guia Avariada Antiga",
    category_id: "equipamentos",
    identifier_code: "PAT-002",
    condition: "damaged",
    current_location_id: "armazem-central",
  });
  assert.equal(eqDamagedRes.saved, true);
  assert.equal(eqDamagedRes.status, "damaged");
  assert.equal(db.docs.get(`warehouse_equipment/${eqDamagedRes.id}`)?.status, "damaged");

  // 2. Rejeição de código duplicado normalizado (case-insensitive / trim)
  await rejects(
    callFn(callables.adminWarehouseUpsertEquipment, {
      mode: "create",
      name: "Coleira Duplicada",
      category_id: "equipamentos",
      identifier_code: " pat-001 ",
      condition: "new",
      current_location_id: "armazem-central",
    }),
    "already-exists",
  );

  // 3. Edição de metadados: proibido mudar identificador e proibido mudar status diretamente
  // Proibido alterar identifier_code
  await rejects(
    callFn(callables.adminWarehouseUpsertEquipment, {
      mode: "edit",
      id: eqCreateRes.id,
      identifier_code: "PAT-001-NEW",
    }),
    "failed-precondition",
  );

  // Proibido alterar status diretamente
  await rejects(
    callFn(callables.adminWarehouseUpsertEquipment, {
      mode: "edit",
      id: eqCreateRes.id,
      status: "retired",
    }),
    "failed-precondition",
  );

  // Edição válida de metadados
  const eqEditRes = await callFn(callables.adminWarehouseUpsertEquipment, {
    mode: "edit",
    id: eqCreateRes.id,
    name: "Coleira de Rastreio K9 Profissional",
    brand: "K9 Elite",
    notes: "Utilizada para busca rural",
  });
  assert.equal(eqEditRes.saved, true);
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.name, "Coleira de Rastreio K9 Profissional");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.brand, "K9 Elite");

  // 4. Transição de status fora de cautela via adminWarehouseUpdateEquipmentStatus
  // Enviar para manutenção
  const maintRes = await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eqCreateRes.id,
    target_status: "maintenance",
    notes: "Ajuste na fivela de fixação",
  });
  assert.equal(maintRes.status, "maintenance");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.status, "maintenance");

  // Rejeição: tentar colocar em available mantendo condição damaged
  await rejects(
    callFn(callables.adminWarehouseUpdateEquipmentStatus, {
      equipment_id: eqCreateRes.id,
      target_status: "available",
      condition: "damaged",
    }),
    "invalid-argument",
  );

  // Retornar da manutenção com reparo (condição good -> status available)
  const repOkRes = await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eqCreateRes.id,
    target_status: "available",
    condition: "good",
    notes: "Fivela reparada e inspecionada",
  });
  assert.equal(repOkRes.status, "available");
  assert.equal(repOkRes.condition, "good");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.status, "available");

  // 5. Cautela: abertura transiciona para in_custody e vincula active_custody_id
  const openCustodyRes = await executeOpenCustody(db as any, caller, {
    equipment_id: eqCreateRes.id,
    borrower_ra: "GCM-5544",
    borrower_name: "GCM Silva",
    condition_at_dispatch: "good",
    purpose: "operation",
    idempotency_key: "custody-open-eq1",
  });
  assert.equal(openCustodyRes.status, "in_custody");
  assert.ok(openCustodyRes.custody_id);
  const eqAfterCustody = db.docs.get(`warehouse_equipment/${eqCreateRes.id}`);
  assert.equal(eqAfterCustody?.status, "in_custody");
  assert.equal(eqAfterCustody?.active_custody_id, openCustodyRes.custody_id);

  // 5b. Rejeição de nova cautela no mesmo bem (dupla custódia)
  await rejects(
    executeOpenCustody(db as any, caller, {
      equipment_id: eqCreateRes.id,
      borrower_ra: "GCM-9988",
      borrower_name: "GCM Souza",
      condition_at_dispatch: "good",
      purpose: "daily_duty",
      idempotency_key: "custody-open-eq1-dup",
    }),
    "failed-precondition",
  );

  // 5c. Rejeição de cautela para equipamento danificado (PAT-002)
  await rejects(
    executeOpenCustody(db as any, caller, {
      equipment_id: eqDamagedRes.id,
      borrower_ra: "GCM-5544",
      borrower_name: "GCM Silva",
      condition_at_dispatch: "fair",
      purpose: "daily_duty",
      idempotency_key: "custody-open-damaged",
    }),
    "failed-precondition",
  );

  // 5d. Bloqueio fail-closed de aposentadoria de equipamento com cautela ativa
  await rejects(
    callFn(callables.adminWarehouseRetireEquipment, {
      equipment_id: eqCreateRes.id,
      reason: "Tentativa de descarte durante operação",
    }),
    "failed-precondition",
  );

  // 5e. Bloqueio de alteração de condição ou localização durante cautela ativa
  await rejects(
    callFn(callables.adminWarehouseUpsertEquipment, {
      mode: "edit",
      id: eqCreateRes.id,
      condition: "fair",
    }),
    "failed-precondition",
  );

  // 6. Devolução de cautela com avaria: condição damaged -> status damaged
  const returnDamagedRes = await executeReturnCustody(db as any, caller, {
    custody_id: openCustodyRes.custody_id,
    condition_at_return: "damaged",
    return_notes: "Fivela rompeu durante intervenção tática",
    idempotency_key: "custody-return-eq1-dmg",
  });
  assert.equal(returnDamagedRes.equipment_status, "damaged");
  const eqAfterDmgReturn = db.docs.get(`warehouse_equipment/${eqCreateRes.id}`);
  assert.equal(eqAfterDmgReturn?.status, "damaged");
  assert.equal(eqAfterDmgReturn?.condition, "damaged");
  assert.equal(eqAfterDmgReturn?.active_custody_id, null);

  // 7. Replay idempotente em ReturnCustody
  const replayReturn = await executeReturnCustody(db as any, caller, {
    custody_id: openCustodyRes.custody_id,
    condition_at_return: "damaged",
    return_notes: "Fivela rompeu durante intervenção tática",
    idempotency_key: "custody-return-eq1-dmg",
  });
  assert.deepEqual(replayReturn, returnDamagedRes);

  // 8. Re-cautela após reparo: reparar PAT-001 -> available
  await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eqCreateRes.id,
    target_status: "available",
    condition: "fair",
    notes: "Costura refeita e testada",
  });
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.status, "available");

  // Nova cautela para testar cancelamento administrativo
  const openCustody2 = await executeOpenCustody(db as any, caller, {
    equipment_id: eqCreateRes.id,
    borrower_ra: "GCM-1122",
    borrower_name: "GCM Pereira",
    condition_at_dispatch: "fair",
    purpose: "training",
    idempotency_key: "custody-open-eq1-round2",
  });
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.active_custody_id, openCustody2.custody_id);

  // Cancelamento administrativo da cautela restaura equipamento para available
  const cancelCustodyRes = await executeCancelCustody(db as any, caller, {
    custody_id: openCustody2.custody_id,
    reason: "Treinamento cancelado por condições climáticas severas",
    idempotency_key: "custody-cancel-eq1",
  });
  assert.equal(cancelCustodyRes.equipment_status, "available");
  assert.equal(cancelCustodyRes.custody_id, openCustody2.custody_id);
  const eqAfterCancel = db.docs.get(`warehouse_equipment/${eqCreateRes.id}`);
  assert.equal(eqAfterCancel?.status, "available");
  assert.equal(eqAfterCancel?.active_custody_id, null);
  assert.equal(db.docs.get(`warehouse_custodies/${openCustody2.custody_id}`)?.status, "cancelled");

  // Replay idempotente do cancelamento
  const replayCancel = await executeCancelCustody(db as any, caller, {
    custody_id: openCustody2.custody_id,
    reason: "Treinamento cancelado por condições climáticas severas",
    idempotency_key: "custody-cancel-eq1",
  });
  assert.deepEqual(replayCancel, cancelCustodyRes);

  // 8b. Validação via callable adminWarehouseReturnCustody (Challenges 1 & 2 + Minor Finding 4)
  const openCustody3 = await executeOpenCustody(db as any, caller, {
    equipment_id: eqCreateRes.id,
    borrower_ra: "GCM-7788",
    borrower_name: "GCM Costa",
    condition_at_dispatch: "fair",
    purpose: "operation",
    idempotency_key: "custody-open-eq1-round3",
  });
  await rejects(
    callFn(callables.adminWarehouseReturnCustody, {
      custody_id: openCustody3.custody_id,
      condition_at_return: "damaged",
      target_equipment_status: "retired",
      idempotency_key: "callable-ret-dmg-retired",
    }),
    "invalid-argument",
  );
  await rejects(
    callFn(callables.adminWarehouseReturnCustody, {
      custody_id: openCustody3.custody_id,
      condition_at_return: "good",
      target_equipment_status: "retired",
      idempotency_key: "callable-ret-good-retired",
    }),
    "invalid-argument",
  );
  await rejects(
    callFn(callables.adminWarehouseReturnCustody, {
      custody_id: openCustody3.custody_id,
      condition_at_return: "good",
      target_equipment_status: "invalid_status",
      idempotency_key: "callable-ret-invalid",
    }),
    "invalid-argument",
  );
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.status, "in_custody");
  assert.equal(db.docs.get(`warehouse_custodies/${openCustody3.custody_id}`)?.status, "active");

  // F04 (NEON-FINDINGS-CLOSURE-R1): omitted / null / empty / blank / non-string condition_at_return
  // must fail closed (invalid-argument) with ZERO mutations — never coerced to "good".
  const snapshotBeforeF04 = JSON.stringify([
    db.docs.get(`warehouse_equipment/${eqCreateRes.id}`),
    db.docs.get(`warehouse_custodies/${openCustody3.custody_id}`),
  ]);
  const auditCountBeforeF04 = [...db.docs.keys()].filter((k) => k.startsWith("auditLogs/")).length;
  for (const [label, badCondition] of [
    ["undefined", undefined],
    ["null", null],
    ["empty", ""],
    ["blank", "   "],
    ["number", 1],
    ["unknown", "excellent"],
  ] as Array<[string, unknown]>) {
    await rejects(
      callFn(callables.adminWarehouseReturnCustody, {
        custody_id: openCustody3.custody_id,
        condition_at_return: badCondition,
        idempotency_key: `callable-ret-f04-${label}`,
      }),
      "invalid-argument",
    );
  }
  // State/condition coherence: status "damaged" requires condition "damaged" (fail-closed, 0 mutations).
  for (const cond of ["good", "fair", "new"]) {
    await rejects(
      callFn(callables.adminWarehouseReturnCustody, {
        custody_id: openCustody3.custody_id,
        condition_at_return: cond,
        target_equipment_status: "damaged",
        idempotency_key: `callable-ret-f04-desync-${cond}`,
      }),
      "invalid-argument",
    );
  }
  assert.equal(
    JSON.stringify([
      db.docs.get(`warehouse_equipment/${eqCreateRes.id}`),
      db.docs.get(`warehouse_custodies/${openCustody3.custody_id}`),
    ]),
    snapshotBeforeF04,
    "F04: rejected returns must not mutate equipment or custody",
  );
  assert.equal(
    [...db.docs.keys()].filter((k) => k.startsWith("auditLogs/")).length,
    auditCountBeforeF04,
    "F04: rejected returns must not write audit logs",
  );
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.condition, "fair", "F04: fair must not be silently upgraded to good");

  // Devolução coerente de equipamento danificado: status "damaged" + condição "damaged".
  const returnGoodAsDamaged = await callFn(callables.adminWarehouseReturnCustody, {
    custody_id: openCustody3.custody_id,
    condition_at_return: "damaged",
    target_equipment_status: "damaged",
    return_notes: "Suspeita de trinca interna para vistoria",
    idempotency_key: "callable-ret-good-damaged",
  });
  assert.equal(returnGoodAsDamaged.equipment_status, "damaged");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.status, "damaged");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.condition, "damaged");
  assert.equal(db.docs.get(`warehouse_equipment/${eqCreateRes.id}`)?.active_custody_id, null);

  // Restaurar eq1 para available após teste
  await callFn(callables.adminWarehouseUpdateEquipmentStatus, {
    equipment_id: eqCreateRes.id,
    target_status: "available",
    condition: "good",
    notes: "Vistoria concluída sem avaria estrutural",
  });

  // 9. Aposentadoria de equipamento (baixa definitiva) com motivo
  const retireRes = await callFn(callables.adminWarehouseRetireEquipment, {
    equipment_id: eqDamagedRes.id,
    reason: "Desgaste total sem viabilidade econômica de reparo",
  });
  assert.equal(retireRes.retired, true);
  assert.equal(retireRes.status, "retired");
  const eqDamagedDoc = db.docs.get(`warehouse_equipment/${eqDamagedRes.id}`);
  assert.equal(eqDamagedDoc?.status, "retired");
  assert.equal(eqDamagedDoc?.active, false);
  assert.equal(eqDamagedDoc?.retire_reason, "Desgaste total sem viabilidade econômica de reparo");

  // Rejeição ao tentar aposentar novamente
  await rejects(
    callFn(callables.adminWarehouseRetireEquipment, {
      equipment_id: eqDamagedRes.id,
      reason: "Segunda tentativa de baixa",
    }),
    "failed-precondition",
  );

  // === F60 PHYSICAL INVENTORY V1 OPERATIONAL SUITE ===
  console.log("Testing Physical Inventory V1 Callables and Transactions...");

  // Limpar posições remanescentes de testes anteriores para garantir escopo limpo do inventário
  for (const key of [...db.docs.keys()]) {
    if (key.startsWith("warehouse_positions/")) {
      db.docs.delete(key);
    }
  }

  // Setup de materiais e posições para teste de inventário
  const matInv1 = "mat-inv-1";
  const matInv2 = "mat-inv-2";
  db.docs.set(`inventory_items/${matInv1}`, {
    id: matInv1, name: "Coleira Alpha", category_id: "equipamentos",
    unit: "unidade", current_quantity: 10, active: true, warehouse_managed: true,
  });
  db.docs.set(`inventory_items/${matInv2}`, {
    id: matInv2, name: "Ração Bravo", category_id: "nutricao",
    unit: "kg", current_quantity: 20, active: true, warehouse_managed: true,
  });

  const batchInv1 = "batch-inv-1";
  const batchInv2 = "batch-inv-2";
  db.docs.set(`warehouse_batches/${batchInv1}`, {
    id: batchInv1, material_id: matInv1, lot_number: "LOT-A1",
    current_quantity: 10, status: "active",
  });
  db.docs.set(`warehouse_batches/${batchInv2}`, {
    id: batchInv2, material_id: matInv2, lot_number: "LOT-B1",
    current_quantity: 20, status: "active",
  });

  const locInvA = "loc-inv-a";
  const locInvB = "loc-inv-b";
  const posInv1 = derivePositionDocId(matInv1, batchInv1, locInvA);
  const posInv2 = derivePositionDocId(matInv2, batchInv2, locInvB);
  db.docs.set(`warehouse_positions/${posInv1}`, {
    id: posInv1, material_id: matInv1, batch_id: batchInv1, lot_number: "LOT-A1",
    location_id: locInvA, location_name: "Setor A", quantity: 10, unit: "unidade", schema_version: 1,
  });
  db.docs.set(`warehouse_positions/${posInv2}`, {
    id: posInv2, material_id: matInv2, batch_id: batchInv2, lot_number: "LOT-B1",
    location_id: locInvB, location_name: "Setor B", quantity: 20, unit: "kg", schema_version: 1,
  });

  // Reset inventory lock
  db.docs.set("warehouse_control/inventory_lock", { active_session_id: null });

  // 1. Abertura de sessão de inventário físico geral
  const invOpenRes = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário Geral F60",
    scope_type: "full_warehouse",
    notes: "Contagem anual física",
  });
  assert.ok(invOpenRes.session_id);
  const invSessionId = invOpenRes.session_id;

  // Verifica trava atômica ativada
  assert.equal(db.docs.get("warehouse_control/inventory_lock")?.active_session_id, invSessionId);

  // Snapshot de posições: expected congelado e counted_quantity estritamente null
  const countDoc1 = db.docs.get(`inventory_sessions/${invSessionId}/counts/${posInv1}`);
  const countDoc2 = db.docs.get(`inventory_sessions/${invSessionId}/counts/${posInv2}`);
  assert.equal(countDoc1?.expected_quantity, 10);
  assert.equal(countDoc1?.counted_quantity, null); // NÃO pode ser 0!
  assert.equal(countDoc1?.discrepancy, null);
  assert.equal(countDoc2?.expected_quantity, 20);
  assert.equal(countDoc2?.counted_quantity, null);

  // 2. Tentativa de abrir 2ª sessão enquanto uma está ativa -> failed-precondition (inventory-session-already-active)
  await rejects(
    callFn(callables.adminWarehouseOpenInventorySession, {
      title: "Segunda sessão simultânea",
      scope_type: "full_warehouse",
    }),
    "failed-precondition",
  );

  // 3. Diferença rigorosa entre null (não contado) e 0 (contado zero):
  // Reconciliação DEVE ser bloqueada se houver posições não contadas (null)
  await rejects(
    callFn(callables.adminWarehouseStartReconciliation, {
      session_id: invSessionId,
    }),
    "failed-precondition",
  );

  // 4. Contagem da posição 1: divergência sem justificativa DEVE ser rejeitada
  await rejects(
    callFn(callables.adminWarehouseRecordInventoryCount, {
      session_id: invSessionId,
      count_id: posInv1,
      counted_quantity: 8, // diff = -2
      discrepancy_reason: "", // sem motivo!
    }),
    "invalid-argument",
  );

  // Contagem da posição 1 com justificativa obrigatória
  const recordCount1 = await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: invSessionId,
    count_id: posInv1,
    counted_quantity: 8,
    discrepancy_reason: "2 unidades extraviadas em treinamento externo",
  });
  assert.equal(recordCount1.recorded, true);
  assert.equal(recordCount1.discrepancy, -2);
  const updatedCount1 = db.docs.get(`inventory_sessions/${invSessionId}/counts/${posInv1}`);
  assert.equal(updatedCount1?.counted_quantity, 8);
  assert.equal(updatedCount1?.discrepancy, -2);
  assert.equal(updatedCount1?.discrepancy_reason, "2 unidades extraviadas em treinamento externo");

  // Reconciliação ainda bloqueada pois posição 2 permanece null
  await rejects(
    callFn(callables.adminWarehouseStartReconciliation, {
      session_id: invSessionId,
    }),
    "failed-precondition",
  );

  // Contagem física de ZERO na posição 2 (counted_quantity = 0, divergência = -20)
  const recordCount2 = await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: invSessionId,
    count_id: posInv2,
    counted_quantity: 0,
    discrepancy_reason: "Lote totalmente utilizado sem registro prévio",
  });
  assert.equal(recordCount2.recorded, true);
  assert.equal(recordCount2.discrepancy, -20);
  const updatedCount2 = db.docs.get(`inventory_sessions/${invSessionId}/counts/${posInv2}`);
  assert.equal(updatedCount2?.counted_quantity, 0); // 0 é valor de contagem válido!

  // 5. Adição de item físico inesperado (expected = 0)
  // Material matInv1 com lote batchInv1 encontrado inesperadamente no Setor B (onde não havia posição)
  const unexpectedPosId = derivePositionDocId(matInv1, batchInv1, locInvB);
  const unexpectedAddRes = await callFn(callables.adminWarehouseAddUnexpectedCount, {
    session_id: invSessionId,
    material_id: matInv1,
    batch_id: batchInv1,
    location_id: locInvB,
    counted_quantity: 3,
    discrepancy_reason: "Caixa encontrada no fundo da prateleira do Setor B",
  });
  assert.equal(unexpectedAddRes.recorded, true);
  assert.equal(unexpectedAddRes.discrepancy, 3);
  const unexpectedDoc = db.docs.get(`inventory_sessions/${invSessionId}/counts/${unexpectedPosId}`);
  assert.equal(unexpectedDoc?.expected_quantity, 0);
  assert.equal(unexpectedDoc?.counted_quantity, 3);
  assert.equal(unexpectedDoc?.discrepancy, 3);
  assert.equal(unexpectedDoc?.discrepancy_reason, "Caixa encontrada no fundo da prateleira do Setor B");
  // F06: location_name resolved from canonical warehouse_positions (not the raw location id).
  assert.equal(unexpectedDoc?.location_name, "Setor B");

  // Rejeição ao tentar adicionar o mesmo item inesperado novamente (already-exists)
  await rejects(
    callFn(callables.adminWarehouseAddUnexpectedCount, {
      session_id: invSessionId,
      material_id: matInv1,
      batch_id: batchInv1,
      location_id: locInvB,
      counted_quantity: 1,
      discrepancy_reason: "Tentativa de duplicata",
    }),
    "already-exists",
  );

  // 6. Transição para reconciliação agora que todas as posições foram contadas
  const reconStartRes = await callFn(callables.adminWarehouseStartReconciliation, {
    session_id: invSessionId,
  });
  assert.equal(reconStartRes.status, "reconciling");
  assert.equal(db.docs.get(`inventory_sessions/${invSessionId}`)?.status, "reconciling");

  // Tentativa de adicionar item inesperado durante reconciliação deve falhar (apenas in_progress)
  await rejects(
    callFn(callables.adminWarehouseAddUnexpectedCount, {
      session_id: invSessionId,
      material_id: matInv2,
      batch_id: batchInv2,
      location_id: locInvA,
      counted_quantity: 1,
      discrepancy_reason: "Tarde demais",
    }),
    "failed-precondition",
  );

  // 7. Homologação da sessão de inventário
  const homologateRes = await callFn(callables.adminWarehouseHomologateInventorySession, {
    session_id: invSessionId,
    idempotency_key: "homologate-inv-f60-key",
    notes: "Parecer final: divergências justificadas.",
  });
  assert.equal(homologateRes.session_id, invSessionId);
  assert.equal(homologateRes.adjustments_applied, 3); // posInv1 (-2), posInv2 (-20), unexpectedPos (+3)
  // F06: homologation notes persisted on the existing `notes` field, opening note preserved.
  assert.equal(
    db.docs.get(`inventory_sessions/${invSessionId}`)?.notes,
    "Contagem anual física\n\n[Homologação] Parecer final: divergências justificadas.",
  );

  // Verificação dos saldos pós-homologação:
  // posInv1: 10 - 2 = 8
  assert.equal(db.docs.get(`warehouse_positions/${posInv1}`)?.quantity, 8);
  // posInv2: 20 - 20 = 0
  assert.equal(db.docs.get(`warehouse_positions/${posInv2}`)?.quantity, 0);
  // unexpectedPos: 0 + 3 = 3 (posição física criada)
  assert.equal(db.docs.get(`warehouse_positions/${unexpectedPosId}`)?.quantity, 3);

  // Lotes:
  // batchInv1: inicial 10, pos1 teve -2, unexpected teve +3 => 10 - 2 + 3 = 11
  assert.equal(db.docs.get(`warehouse_batches/${batchInv1}`)?.current_quantity, 11);
  assert.equal(db.docs.get(`warehouse_batches/${batchInv1}`)?.status, "active");
  // batchInv2: inicial 20, pos2 teve -20 => 0 => depleted
  assert.equal(db.docs.get(`warehouse_batches/${batchInv2}`)?.current_quantity, 0);
  assert.equal(db.docs.get(`warehouse_batches/${batchInv2}`)?.status, "depleted");

  // Materiais:
  // matInv1: inicial 10 => 11
  assert.equal(db.docs.get(`inventory_items/${matInv1}`)?.current_quantity, 11);
  // matInv2: inicial 20 => 0 => out_of_stock
  assert.equal(db.docs.get(`inventory_items/${matInv2}`)?.current_quantity, 0);
  assert.equal(db.docs.get(`inventory_items/${matInv2}`)?.status, "out_of_stock");

  // Verificação de liberação da trava
  assert.equal(db.docs.get("warehouse_control/inventory_lock")?.active_session_id, null);
  assert.equal(db.docs.get(`inventory_sessions/${invSessionId}`)?.status, "homologated");

  // 8. Replay idempotente da homologação
  const replayHomologate = await callFn(callables.adminWarehouseHomologateInventorySession, {
    session_id: invSessionId,
    idempotency_key: "homologate-inv-f60-key",
    notes: "Parecer final: divergências justificadas.",
  });
  assert.deepEqual(replayHomologate, homologateRes);

  // 9. Sessão homologada é imutável: contagem ou cancelamento devem falhar
  await rejects(
    callFn(callables.adminWarehouseRecordInventoryCount, {
      session_id: invSessionId,
      count_id: posInv1,
      counted_quantity: 10,
      discrepancy_reason: "Mutação pós-homologação",
    }),
    "failed-precondition",
  );
  await rejects(
    callFn(callables.adminWarehouseCancelInventorySession, {
      session_id: invSessionId,
      reason: "Tentativa de cancelar sessão homologada",
    }),
    "failed-precondition",
  );

  // 10. Teste de cancelamento de sessão de inventário: libera trava sem qualquer mutação de estoque
  const invOpenCancel = await callFn(callables.adminWarehouseOpenInventorySession, {
    title: "Inventário a ser cancelado",
    scope_type: "full_warehouse",
    notes: "Teste de cancelamento",
  });
  assert.ok(invOpenCancel.session_id);
  const cancelSessionId = invOpenCancel.session_id;
  assert.equal(db.docs.get("warehouse_control/inventory_lock")?.active_session_id, cancelSessionId);

  // Registrar uma contagem divergente antes do cancelamento
  await callFn(callables.adminWarehouseRecordInventoryCount, {
    session_id: cancelSessionId,
    count_id: posInv1,
    counted_quantity: 50,
    discrepancy_reason: "Contagem errônea que causará cancelamento",
  });

  // Saldo antes do cancelamento
  const mat1BeforeCancel = db.docs.get(`inventory_items/${matInv1}`)?.current_quantity;

  // Cancelar sessão
  const cancelRes = await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: cancelSessionId,
    reason: "Erro operacional de contagem",
  });
  assert.equal(cancelRes.cancelled, true);

  // Trava liberada
  assert.equal(db.docs.get("warehouse_control/inventory_lock")?.active_session_id, null);
  assert.equal(db.docs.get(`inventory_sessions/${cancelSessionId}`)?.status, "cancelled");

  // Saldo físico ZERO mutação
  assert.equal(db.docs.get(`inventory_items/${matInv1}`)?.current_quantity, mat1BeforeCancel);

  // Imutabilidade de sessão cancelada
  await rejects(
    callFn(callables.adminWarehouseCancelInventorySession, {
      session_id: cancelSessionId,
      reason: "Cancelar novamente",
    }),
    "failed-precondition",
  );

  // === F60 OVERVIEW & ALERTS READ MODEL TEST ===
  console.log("Testing Overview & Alerts Read Model Callable...");
  const overviewRes = await callFn(callables.adminWarehouseGetOverview, {});
  assert.ok(overviewRes.generated_at);
  assert.ok(["normal", "warning", "attention"].includes(overviewRes.overall_status));
  assert.ok(typeof overviewRes.materials.active_materials === "number");
  assert.ok(typeof overviewRes.materials.out_of_stock === "number");
  assert.ok(typeof overviewRes.materials.low_stock === "number");
  assert.ok(typeof overviewRes.equipment.total_active === "number");
  assert.ok(typeof overviewRes.equipment.available === "number");
  assert.ok(typeof overviewRes.custody.active === "number");
  assert.ok(typeof overviewRes.custody.overdue === "number");
  assert.ok(Array.isArray(overviewRes.alerts));
  assert.ok(Array.isArray(overviewRes.recent_movements));

  // Alertas ordenados por severidade (critical antes de warning, warning antes de info)
  const rank: Record<string, number> = { critical: 0, warning: 1, info: 2 };
  for (let i = 1; i < overviewRes.alerts.length; i++) {
    const prevRank = rank[overviewRes.alerts[i - 1].severity] ?? 99;
    const currRank = rank[overviewRes.alerts[i].severity] ?? 99;
    assert.ok(prevRank <= currRank, `Alertas devem estar ordenados por severidade decrescente (${prevRank} <= ${currRank})`);
  }

  // === F60 OPTION B SEGREGATION: OVERVIEW INVENTORY AUDIT DISCLOSURE TEST ===
  console.log("Testing Option B: Overview Inventory Audit Segregation Callable...");
  const sessAuditTestId = "sess-overview-audit-test";
  db.docs.set(`inventory_sessions/${sessAuditTestId}`, {
    id: sessAuditTestId,
    title: "Auditoria Restrita 2026",
    scope_type: "full_warehouse",
    status: "in_progress",
    snapshot_status: "complete",
    opened_by_name: "Almoxarife Chefe",
    opened_at: new Date(),
    total_items: 50,
    counted_items: 20,
  });

  // 1. Caller with inventory.view ONLY (e.g. operador_k9)
  const viewOnlyChecker = async (_auth: any, _module: string, action: string) => {
    if (action === "view") return caller;
    throw new (class extends Error { code = "permission-denied"; })("Perfil sem permissao para inventory.audit.");
  };
  const viewOnlyCallables = createWarehouseCallables(db as any, viewOnlyChecker as any);
  const viewOnlyOverview = await (viewOnlyCallables.adminWarehouseGetOverview as any).run({
    data: {},
    auth: { uid: caller.uid, token: {} },
  });

  assert.equal(viewOnlyOverview.inventory.active_session, null, "View-only caller must NOT receive active_session");
  assert.equal(viewOnlyOverview.inventory.attention_required, false, "View-only caller must not see inventory attention_required");
  const viewOnlyInvAlerts = viewOnlyOverview.alerts.filter((a: any) =>
    ["active_inventory", "inventory_snapshot_building", "inventory_snapshot_failed"].includes(a.kind),
  );
  assert.equal(viewOnlyInvAlerts.length, 0, "View-only caller must NOT receive any inventory audit alerts");

  // 2. Caller with inventory.view AND inventory.audit (e.g. almoxarifado / admin)
  const auditCallables = createWarehouseCallables(db as any, async () => caller);
  const auditOverview = await (auditCallables.adminWarehouseGetOverview as any).run({
    data: {},
    auth: { uid: caller.uid, token: {} },
  });

  assert.ok(auditOverview.inventory.active_session, "Audit caller must receive active_session");
  assert.equal(auditOverview.inventory.active_session.id, sessAuditTestId);
  assert.equal(auditOverview.inventory.active_session.title, "Auditoria Restrita 2026");
  const auditInvAlerts = auditOverview.alerts.filter((a: any) => a.kind === "active_inventory");
  assert.ok(auditInvAlerts.length > 0, "Audit caller must receive active_inventory alert");

  // 3. Caller with neither permission
  const noPermChecker = async () => {
    throw new (class extends Error { code = "permission-denied"; })("Perfil sem permissao.");
  };
  const noPermCallables = createWarehouseCallables(db as any, noPermChecker as any);
  await rejects(
    (noPermCallables.adminWarehouseGetOverview as any).run({
      data: {},
      auth: { uid: caller.uid, token: {} },
    }),
    "permission-denied",
  );

  // Clean up test session
  db.docs.delete(`inventory_sessions/${sessAuditTestId}`);

  // === F60 PRE-STAGING HARDENING: FEFO MULTI-BATCH ATOMICITY TEST ===
  console.log("Testing FEFO Multi-Batch Atomicity & Insufficient Stock Rollback...");
  const matMulti = "mat-multi-fefo";
  const batchMultiA = "batch-multi-a";
  const batchMultiB = "batch-multi-b";
  const locMulti = "loc-multi";

  db.docs.set(`inventory_items/${matMulti}`, {
    id: matMulti, name: "Suplemento Canino Multi", category_id: "nutricao", unit: "kg",
    current_quantity: 30, active: true, warehouse_managed: true,
  });

  // Batch A: 10 kg, vence mais cedo (2026-11-01)
  db.docs.set(`warehouse_batches/${batchMultiA}`, {
    id: batchMultiA, material_id: matMulti, lot_number: "LOT-MULTI-A",
    initial_quantity: 10, current_quantity: 10, expiration_date: TEST_DATE_VALID_SOON, status: "active",
  });
  // Batch B: 20 kg, vence mais tarde (2026-12-01)
  db.docs.set(`warehouse_batches/${batchMultiB}`, {
    id: batchMultiB, material_id: matMulti, lot_number: "LOT-MULTI-B",
    initial_quantity: 20, current_quantity: 20, expiration_date: TEST_DATE_VALID_LATER, status: "active",
  });

  const posMultiA = derivePositionDocId(matMulti, batchMultiA, locMulti);
  const posMultiB = derivePositionDocId(matMulti, batchMultiB, locMulti);

  db.docs.set(`warehouse_positions/${posMultiA}`, {
    id: posMultiA, material_id: matMulti, batch_id: batchMultiA, lot_number: "LOT-MULTI-A",
    location_id: locMulti, location_name: "Setor Multi", quantity: 10, unit: "kg", schema_version: 1,
  });
  db.docs.set(`warehouse_positions/${posMultiB}`, {
    id: posMultiB, material_id: matMulti, batch_id: batchMultiB, lot_number: "LOT-MULTI-B",
    location_id: locMulti, location_name: "Setor Multi", quantity: 20, unit: "kg", schema_version: 1,
  });

  // Teste de saldo insuficiente no multi-lote: pedido 50 kg (disponível: 30 kg) -> deve falhar fechado com ZERO mutação
  await rejects(
    executeWarehouseConsumption(db as any, caller, {
      material_id: matMulti,
      source_location_id: locMulti,
      quantity: 50,
      reason: "Consumo excessivo que deve falhar",
      idempotency_key: "excess-multi-consume",
    }),
    "failed-precondition",
  );
  // Garante que nada foi alterado
  assert.equal(db.docs.get(`inventory_items/${matMulti}`)?.current_quantity, 30);
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiA}`)?.current_quantity, 10);
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiB}`)?.current_quantity, 20);

  // Consumo FEFO de 25 kg sem especificar batch_id (Batch A 10 kg + Batch B 15 kg)
  const multiConsumeRes = await executeWarehouseConsumption(db as any, caller, {
    material_id: matMulti,
    source_location_id: locMulti,
    quantity: 25,
    reason: "Consumo FEFO multi-lote comprovado",
    idempotency_key: "valid-multi-consume-key",
  });
  assert.ok(multiConsumeRes.movement_id);
  assert.equal(multiConsumeRes.material_on_hand, 5); // 30 - 25 = 5

  // Batch A consumiu 10 kg -> saldo 0, status depleted
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiA}`)?.current_quantity, 0);
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiA}`)?.status, "depleted");
  assert.equal(db.docs.get(`warehouse_positions/${posMultiA}`)?.quantity, 0);

  // Batch B consumiu 15 kg -> saldo 5, status active
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiB}`)?.current_quantity, 5);
  assert.equal(db.docs.get(`warehouse_batches/${batchMultiB}`)?.status, "active");
  assert.equal(db.docs.get(`warehouse_positions/${posMultiB}`)?.quantity, 5);

  // Material total = 5 kg
  assert.equal(db.docs.get(`inventory_items/${matMulti}`)?.current_quantity, 5);

  // === F60 PRE-STAGING HARDENING: ACTIVE INVENTORY vs METADATA MUTATION TEST ===
  console.log("Testing by_category Active Inventory Scope Guard against category changes...");
  const catLocked = "cat-locked";
  const catTarget = "cat-target";
  const matCategoryTest = "mat-cat-test";

  db.docs.set(`inventory_items/${matCategoryTest}`, {
    id: matCategoryTest, name: "Material Cat Test", category_id: catLocked, unit: "un",
    current_quantity: 10, active: true, warehouse_managed: true,
  });

  // Abre inventário por categoria em catLocked
  const invCatSession = await executeStartInventorySession(db as any, caller, {
    title: "Inventário Categoria Bloqueada",
    scope_type: "by_category",
    scope_ref_id: catLocked,
  });
  assert.ok(invCatSession.session_id);

  // Tenta alterar category_id do material para catTarget enquanto inventário está ativo -> DEVE FALHAR
  await rejects(
    callFn(callables.adminWarehouseUpsertMaterial, {
      mode: "edit",
      id: matCategoryTest,
      profile: {
        name: "Material Cat Test",
        category_id: catTarget, // categoria alterada!
        unit: "un",
        minimum_quantity: 5,
      },
    }),
    "failed-precondition",
  );

  // Edição sem alterar categoria (ex.: mudar apenas nome/descrição) DEVE passar
  const harmlessEdit = await callFn(callables.adminWarehouseUpsertMaterial, {
    mode: "edit",
    id: matCategoryTest,
    profile: {
      name: "Material Cat Test Renomeado",
      category_id: catLocked, // categoria idêntica mantida
      unit: "un",
      minimum_quantity: 5,
    },
  });
  assert.equal(harmlessEdit.updated, true);

  // Cancela sessão de inventário para liberar trava
  await callFn(callables.adminWarehouseCancelInventorySession, {
    session_id: invCatSession.session_id,
    reason: "Fim do teste de guarda de categoria",
  });

  // === F60 PRE-STAGING HARDENING: TEMPORAL BOUNDARY TESTS ===
  console.log("Testing Temporal Boundaries (Expiry & Custody Overdue)...");
  // Expiry boundaries:
  // Ontem -> expirado
  assert.equal(isBatchExpiredServer("2026-10-05", "2026-10-06"), true);
  // Hoje -> VÁLIDO o dia todo (isBatchExpiredServer === false)
  assert.equal(isBatchExpiredServer("2026-10-06", "2026-10-06"), false);
  // Amanhã -> VÁLIDO
  assert.equal(isBatchExpiredServer("2026-10-07", "2026-10-06"), false);

  // Custody overdue boundaries:
  const refReturnInstant = new Date("2026-10-06T15:00:00.000Z");
  // Antes do prazo:
  const beforeReturnInstant = new Date("2026-10-06T14:59:59.999Z");
  assert.equal(beforeReturnInstant.getTime() > refReturnInstant.getTime(), false);
  // Exatamente no prazo:
  assert.equal(refReturnInstant.getTime() > refReturnInstant.getTime(), false); // NÃO atrasado!
  // Após o prazo:
  const afterReturnInstant = new Date("2026-10-06T15:00:00.001Z");
  assert.equal(afterReturnInstant.getTime() > refReturnInstant.getTime(), true); // Atrasado!

  // === F60 CLOSEOUT EVIDENCE 3: ALTERNATE VALID FEFO BATCH TEST ===
  console.log("Testing Alternate Valid FEFO Batch with and without justification...");
  const matAlt = "mat-alt-fefo-closeout";
  const batchAltA = "batch-alt-a-closeout";
  const batchAltB = "batch-alt-b-closeout";
  const locAlt = "loc-alt-closeout";

  db.docs.set(`inventory_items/${matAlt}`, {
    id: matAlt, name: "Material Alternate FEFO", category_id: "geral", unit: "un",
    current_quantity: 20, active: true, warehouse_managed: true,
  });

  // Batch A: 10 un, validade 2026-11-01 (mais cedo)
  db.docs.set(`warehouse_batches/${batchAltA}`, {
    id: batchAltA, material_id: matAlt, lot_number: "LOT-ALT-A",
    initial_quantity: 10, current_quantity: 10, expiration_date: TEST_DATE_VALID_SOON, status: "active",
  });
  // Batch B: 10 un, validade 2026-12-01 (posterior)
  db.docs.set(`warehouse_batches/${batchAltB}`, {
    id: batchAltB, material_id: matAlt, lot_number: "LOT-ALT-B",
    initial_quantity: 10, current_quantity: 10, expiration_date: TEST_DATE_VALID_LATER, status: "active",
  });

  const posAltA = derivePositionDocId(matAlt, batchAltA, locAlt);
  const posAltB = derivePositionDocId(matAlt, batchAltB, locAlt);

  db.docs.set(`warehouse_positions/${posAltA}`, {
    id: posAltA, material_id: matAlt, batch_id: batchAltA, lot_number: "LOT-ALT-A",
    location_id: locAlt, location_name: "Local Alt", quantity: 10, unit: "un", schema_version: 1,
  });
  db.docs.set(`warehouse_positions/${posAltB}`, {
    id: posAltB, material_id: matAlt, batch_id: batchAltB, lot_number: "LOT-ALT-B",
    location_id: locAlt, location_name: "Local Alt", quantity: 10, unit: "un", schema_version: 1,
  });

  // Case A: Escolhe explicitamente Batch B sem justificativa -> DEVE REJEITAR com ZERO mutação
  await rejects(
    executeWarehouseConsumption(db as any, caller, {
      material_id: matAlt,
      batch_id: batchAltB,
      source_location_id: locAlt,
      quantity: 4,
      reason: "Consumo de lote B sem justificativa de override",
      fefo_override_reason: "", // sem justificativa!
      idempotency_key: "alt-b-no-reason",
    }),
    "failed-precondition",
  );
  assert.equal(db.docs.get(`inventory_items/${matAlt}`)?.current_quantity, 20);
  assert.equal(db.docs.get(`warehouse_batches/${batchAltA}`)?.current_quantity, 10);
  assert.equal(db.docs.get(`warehouse_batches/${batchAltB}`)?.current_quantity, 10);

  // Case B: Escolhe explicitamente Batch B com justificativa válida -> DEVE ACEITAR
  const acceptAltRes = await executeWarehouseConsumption(db as any, caller, {
    material_id: matAlt,
    batch_id: batchAltB,
    source_location_id: locAlt,
    quantity: 4,
    reason: "Consumo de lote B com justificativa válida",
    fefo_override_reason: "Reserva operacional para instrução especializada",
    idempotency_key: "alt-b-valid-reason",
  });
  assert.ok(acceptAltRes.movement_id);
  assert.equal(acceptAltRes.material_on_hand, 16);
  assert.equal(db.docs.get(`inventory_items/${matAlt}`)?.current_quantity, 16);
  assert.equal(db.docs.get(`warehouse_batches/${batchAltA}`)?.current_quantity, 10); // Batch A intocado!
  assert.equal(db.docs.get(`warehouse_batches/${batchAltB}`)?.current_quantity, 6);  // Batch B debitou 4!

  // Replay idempotente do Case B
  const replayAltRes = await executeWarehouseConsumption(db as any, caller, {
    material_id: matAlt,
    batch_id: batchAltB,
    source_location_id: locAlt,
    quantity: 4,
    reason: "Consumo de lote B com justificativa válida",
    fefo_override_reason: "Reserva operacional para instrução especializada",
    idempotency_key: "alt-b-valid-reason",
  });
  assert.deepEqual(replayAltRes, acceptAltRes);
  assert.equal(db.docs.get(`inventory_items/${matAlt}`)?.current_quantity, 16); // Saldo não foi duplicado!

  // -------------------------------------------------------------
  // F60 PHOTO CONTRACT & COMPATIBILITY TESTS (CT3.F60.WAREHOUSE-BACKEND-PHOTO-CLOSURE-R1)
  // -------------------------------------------------------------
  console.log("Testing F60 Warehouse Photo Contract & Lifecycle...");

  // A. validateWarehousePhotoUrl Tests - PRODUCTION MODE
  const validProductionPhotoUrls = [
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2Fmaterial-123%2F1698000000000.jpg?alt=media&token=abcdef",
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/inventory_items%2Fequipment-VIP-001%2F1700000000.png",
    "https://storage.googleapis.com/canil-gcm.appspot.com/inventory_items/equipment-001/1700000000.webp",
    "https://storage.googleapis.com/canil-gcm.firebasestorage.app/inventory_items/equipment-001/1700000000.webp",
    "gs://canil-gcm.firebasestorage.app/inventory_items/material-foo/pic.webp",
    "gs://canil-gcm.appspot.com/inventory_items/material-foo/pic.webp",
  ];

  for (const url of validProductionPhotoUrls) {
    assert.equal(validateWarehousePhotoUrl(url), url.trim());
  }

  // Invalid photo URLs in production mode that MUST be rejected
  const invalidProductionPhotoUrls = [
    null,
    undefined,
    12345,
    "",
    "   ",
    "a".repeat(2049),
    "javascript:alert(1)",
    "ftp://example.com/inventory_items/photo.jpg",
    "https://evil-storage.com/inventory_items/pic.jpg",
    "https://attacker.com/v0/b/canil-gcm/o/inventory_items%2Fpic.jpg",
    // Localhost rejected in production mode
    "http://127.0.0.1:9199/v0/b/canil-gcm/o/inventory_items%2Fequipment-123%2Fphoto.png",
    "http://localhost:9199/v0/b/canil-gcm/o/inventory_items%2Fmaterial-456%2Fphoto.jpg",
    // Unauthorized / foreign buckets rejected
    "https://storage.googleapis.com/test-bucket/inventory_items/item.jpg",
    "https://firebasestorage.googleapis.com/v0/b/evil-bucket/o/inventory_items%2Fitem.jpg",
    "gs://evil-bucket/inventory_items/pic.webp",
    // Wrong collections rejected
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/dogs%2Fdog-1%2Fphoto.jpg",
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/users%2Fuser-1%2Fphoto.jpg",
    "https://storage.googleapis.com/canil-gcm.appspot.com/users/avatar.png",
    "https://storage.googleapis.com/canil-gcm.appspot.com/occurrences/event.jpg",
    "gs://canil-gcm.appspot.com/dogs/photo.jpg",
    // Directory traversal and malformed paths rejected
    "https://storage.googleapis.com/canil-gcm.appspot.com/inventory_items/../../etc/passwd",
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2F..%2Fsecret.jpg",
    "gs://canil-gcm.appspot.com/inventory_items/../escape.jpg",
    "gs://canil-gcm.appspot.com/inventory_items/",
    "https://firebasestorage.googleapis.com/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2F",
  ];

  for (const invalid of invalidProductionPhotoUrls) {
    assert.throws(
      () => validateWarehousePhotoUrl(invalid),
      (err: any) => err.code === "invalid-argument",
      `Expected invalid photo url to throw invalid-argument in production mode: ${invalid}`,
    );
  }

  // A1.1 SECURITY REGRESSION (CT4.WEB-P0.SECURITY-AND-PROMOTION-READINESS-R1):
  // staging buckets e buckets arbitrários NUNCA são autorizados, mesmo quando
  // GCLOUD_PROJECT / FIREBASE_CONFIG apontam para o projeto de staging.
  {
    const savedGcloudProject = process.env.GCLOUD_PROJECT;
    const savedFirebaseConfig = process.env.FIREBASE_CONFIG;
    try {
      process.env.GCLOUD_PROJECT = "k9-ops-staging";
      process.env.FIREBASE_CONFIG = JSON.stringify({
        projectId: "k9-ops-staging",
        storageBucket: "k9-ops-staging.firebasestorage.app",
      });

      const stagingBuckets = [
        "k9-ops-staging.firebasestorage.app",
        "k9-ops-staging.appspot.com",
      ];
      for (const bucket of stagingBuckets) {
        assert.equal(
          isWarehouseAuthorizedBucket(bucket),
          false,
          `Expected staging bucket to be rejected: ${bucket}`,
        );
      }

      // Derivações por prefixo semelhante e buckets de terceiros também falham.
      const similarBuckets = [
        "canil-gcm.firebasestorage.app.evil.com",
        "canil-gcm.appspot.com.evil.com",
        "canil-gcm2.appspot.com",
        "k9-ops-staging2.firebasestorage.app",
        "third-party-bucket",
      ];
      for (const bucket of similarBuckets) {
        assert.equal(
          isWarehouseAuthorizedBucket(bucket),
          false,
          `Expected foreign/similar bucket to be rejected: ${bucket}`,
        );
      }

      // Configuração contraditória (projeto != bucket) não altera o resultado:
      // apenas buckets canônicos de produção continuam autorizados.
      process.env.GCLOUD_PROJECT = "canil-gcm";
      process.env.FIREBASE_CONFIG = JSON.stringify({
        projectId: "canil-gcm",
        storageBucket: "k9-ops-staging.appspot.com",
      });
      assert.equal(isWarehouseAuthorizedBucket("k9-ops-staging.appspot.com"), false);
      assert.equal(isWarehouseAuthorizedBucket("canil-gcm.firebasestorage.app"), true);
      assert.equal(isWarehouseAuthorizedBucket("canil-gcm.appspot.com"), true);
    } finally {
      if (savedGcloudProject === undefined) delete process.env.GCLOUD_PROJECT;
      else process.env.GCLOUD_PROJECT = savedGcloudProject;
      if (savedFirebaseConfig === undefined) delete process.env.FIREBASE_CONFIG;
      else process.env.FIREBASE_CONFIG = savedFirebaseConfig;
    }
  }

  // A2. validateWarehousePhotoUrl Tests - EMULATOR MODE
  const prevEmu = process.env.FUNCTIONS_EMULATOR;
  try {
    process.env.FUNCTIONS_EMULATOR = "true";

    const validEmulatorUrls = [
      "http://127.0.0.1:9199/v0/b/canil-gcm/o/inventory_items%2Fequipment-123%2Fphoto.png",
      "http://localhost:9199/v0/b/canil-gcm/o/inventory_items%2Fmaterial-456%2Fphoto.jpg",
      "http://localhost:9199/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2Fmaterial-456%2Fphoto.jpg",
      "https://firebasestorage.googleapis.com/v0/b/canil-gcm.firebasestorage.app/o/inventory_items%2Fmaterial-123%2F1698000000000.jpg",
    ];

    for (const url of validEmulatorUrls) {
      assert.equal(validateWarehousePhotoUrl(url), url.trim());
    }

    // Invalid URLs in emulator mode (bucket or path still enforced)
    const invalidEmulatorUrls = [
      "http://127.0.0.1:9199/v0/b/unauthorized-bucket/o/inventory_items%2Fphoto.png",
      "http://localhost:9199/v0/b/canil-gcm/o/dogs%2Fdog-1%2Fphoto.jpg",
      "http://localhost:9199/v0/b/canil-gcm/o/inventory_items%2F..%2Fphoto.jpg",
      "http://localhost:9199/v0/b/canil-gcm/o/inventory_items%2F",
    ];

    for (const invalid of invalidEmulatorUrls) {
      assert.throws(
        () => validateWarehousePhotoUrl(invalid),
        (err: any) => err.code === "invalid-argument",
        `Expected invalid photo url to throw invalid-argument in emulator mode: ${invalid}`,
      );
    }
  } finally {
    if (prevEmu === undefined) {
      delete process.env.FUNCTIONS_EMULATOR;
    } else {
      process.env.FUNCTIONS_EMULATOR = prevEmu;
    }
  }

  // B. Material Photo Lifecycle Tests
  const matPhotoTestId = "mat-photo-test-01";
  const validMatPhoto1 = "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/inventory_items%2Fmat-1%2Fphoto1.jpg";
  const validMatPhoto2 = "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/inventory_items%2Fmat-1%2Fphoto2.png";

  // 1. Material CREATE with valid photo_url
  const createdMatWithPhoto = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "create",
    id: matPhotoTestId,
    profile: {
      name: "Ração Super Premium K9",
      category_id: "cat-alimentos",
      unit: "kg",
      min_stock: 50,
      photo_url: validMatPhoto1,
    },
  });
  assert.equal(createdMatWithPhoto.id, matPhotoTestId);
  assert.equal(createdMatWithPhoto.photo_url, validMatPhoto1);
  const matDocAfterCreate = db.docs.get(`inventory_items/${matPhotoTestId}`);
  assert.equal(matDocAfterCreate?.photo_url, validMatPhoto1);
  assert.equal(matDocAfterCreate?.warehouse_managed, true);

  // 2. Material CREATE without photo
  const matNoPhotoId = "mat-no-photo-01";
  const createdMatNoPhoto = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "create",
    id: matNoPhotoId,
    profile: {
      name: "Guia Simples",
      category_id: "cat-equip",
      unit: "unidade",
      minimum_quantity: 5,
    },
  });
  assert.equal(createdMatNoPhoto.photo_url, null);
  assert.equal(db.docs.get(`inventory_items/${matNoPhotoId}`)?.photo_url, null);

  // 3. Material CREATE with contradictory photo_remove and photo_url -> REJECT
  await rejects(
    executeWarehouseUpsertMaterial(db as any, caller, {
      mode: "create",
      id: "mat-invalid-photo-01",
      profile: {
        name: "Item Conflitante",
        category_id: "cat-alimentos",
        unit: "kg",
        minimum_quantity: 10,
        photo_url: validMatPhoto1,
        photo_remove: true,
      },
    }),
    "invalid-argument",
  );

  // 4. Material CREATE with invalid photo_url -> REJECT with zero mutations
  await rejects(
    executeWarehouseUpsertMaterial(db as any, caller, {
      mode: "create",
      id: "mat-unauth-photo-01",
      profile: {
        name: "Item Foto Não Autorizada",
        category_id: "cat-alimentos",
        unit: "kg",
        minimum_quantity: 10,
        photo_url: "https://evil.com/malicious.jpg",
      },
    }),
    "invalid-argument",
  );
  assert.equal(db.docs.get("inventory_items/mat-unauth-photo-01"), undefined);

  // 5. Material EDIT replacing photo (validMatPhoto1 -> validMatPhoto2)
  const updatedMatWithNewPhoto = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "edit",
    id: matPhotoTestId,
    profile: {
      name: "Ração Super Premium K9 Atualizada",
      category_id: "cat-alimentos",
      unit: "kg",
      minimum_quantity: 60,
      photo_url: validMatPhoto2,
    },
  });
  assert.equal(updatedMatWithNewPhoto.photo_url, validMatPhoto2);
  assert.equal(db.docs.get(`inventory_items/${matPhotoTestId}`)?.photo_url, validMatPhoto2);

  // 6. Material EDIT omitting photo fields -> PRESERVES existing photo
  const updatedMatOmitPhoto = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "edit",
    id: matPhotoTestId,
    profile: {
      name: "Ração Super Premium K9 Nome Novo",
      category_id: "cat-alimentos",
      unit: "kg",
      minimum_quantity: 60,
      // photo_url and photo_remove omitted!
    },
  });
  assert.equal(updatedMatOmitPhoto.photo_url, validMatPhoto2);
  assert.equal(db.docs.get(`inventory_items/${matPhotoTestId}`)?.photo_url, validMatPhoto2);

  // 7. Material EDIT with explicit photo_remove: true -> REMOVES photo (persists null)
  const updatedMatRemovePhoto = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "edit",
    id: matPhotoTestId,
    profile: {
      name: "Ração Super Premium K9 Sem Foto",
      category_id: "cat-alimentos",
      unit: "kg",
      minimum_quantity: 60,
      photo_url: null,
      photo_remove: true,
    },
  });
  assert.equal(updatedMatRemovePhoto.photo_url, null);
  assert.equal(db.docs.get(`inventory_items/${matPhotoTestId}`)?.photo_url, null);

  // 8. Legacy material record without photo -> remains valid and null on edit
  db.docs.set("inventory_items/mat-legacy-no-photo", {
    id: "mat-legacy-no-photo",
    name: "Material Legado Sem Foto",
    category_id: "cat-legado",
    unit: "unidade",
    minimum_quantity: 1,
    current_quantity: 0,
    warehouse_managed: true,
    status: "out_of_stock",
    active: true,
    // photo_url undefined
  });
  const updatedLegacyMat = await executeWarehouseUpsertMaterial(db as any, caller, {
    mode: "edit",
    id: "mat-legacy-no-photo",
    profile: {
      name: "Material Legado Atualizado",
      category_id: "cat-legado",
      unit: "unidade",
      minimum_quantity: 2,
    },
  });
  assert.ok(updatedLegacyMat.updated);
  assert.equal(db.docs.get("inventory_items/mat-legacy-no-photo")?.name, "Material Legado Atualizado");
  assert.equal(db.docs.get("inventory_items/mat-legacy-no-photo")?.photo_url, undefined);

  // C. Equipment Photo Lifecycle Tests
  // Setup legacy reconciliation status in DB so new equipment creation is allowed
  db.docs.set("warehouse_control/legacy_reconciliation_status", { status: "completed" });

  const eqPhotoTestId = "eq-photo-test-01";
  const validEqPhoto1 = "https://storage.googleapis.com/canil-gcm.appspot.com/inventory_items/equipment-EQP-001/1700000000.jpg";
  const validEqPhoto2 = "https://firebasestorage.googleapis.com/v0/b/canil-gcm.appspot.com/o/inventory_items%2Fequipment-EQP-001%2F1700000001.webp";

  // 1. Equipment CREATE with valid photo_url
  const createdEqWithPhoto = await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "create",
    id: eqPhotoTestId,
    data: {
      name: "Coleira Tática K9",
      identifier_code: "EQP-PHOTO-01",
      category_id: "cat-tatico",
      condition: "new",
      current_location_id: "loc-almox-01",
      photo_url: validEqPhoto1,
    },
  });
  assert.equal(createdEqWithPhoto.id, eqPhotoTestId);
  assert.equal(createdEqWithPhoto.photo_url, validEqPhoto1);
  const eqDocAfterCreate = db.docs.get(`warehouse_equipment/${eqPhotoTestId}`);
  assert.equal(eqDocAfterCreate?.photo_url, validEqPhoto1);
  assert.equal(eqDocAfterCreate?.status, "available");

  // 2. Equipment CREATE without photo
  const eqNoPhotoId = "eq-no-photo-01";
  const createdEqNoPhoto = await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "create",
    id: eqNoPhotoId,
    data: {
      name: "Peitoral K9",
      identifier_code: "EQP-NO-PHOTO-01",
      category_id: "cat-tatico",
      condition: "good",
      current_location_id: "loc-almox-01",
    },
  });
  assert.equal(createdEqNoPhoto.photo_url, null);
  assert.equal(db.docs.get(`warehouse_equipment/${eqNoPhotoId}`)?.photo_url, null);

  // 3. Equipment CREATE with contradictory photo_remove and photo_url -> REJECT
  await rejects(
    executeWarehouseUpsertEquipment(db as any, caller, {
      mode: "create",
      id: "eq-invalid-photo-01",
      data: {
        name: "Coleira Inválida",
        identifier_code: "EQP-INV-01",
        category_id: "cat-tatico",
        condition: "good",
        current_location_id: "loc-almox-01",
        photo_url: validEqPhoto1,
        photo_remove: true,
      },
    }),
    "invalid-argument",
  );

  // 4. Equipment CREATE with invalid photo_url -> REJECT with zero mutations
  await rejects(
    executeWarehouseUpsertEquipment(db as any, caller, {
      mode: "create",
      id: "eq-unauth-photo-01",
      data: {
        name: "Coleira Foto Não Autorizada",
        identifier_code: "EQP-UNAUTH-01",
        category_id: "cat-tatico",
        condition: "good",
        current_location_id: "loc-almox-01",
        photo_url: "https://evil.com/equipment.png",
      },
    }),
    "invalid-argument",
  );
  assert.equal(db.docs.get("warehouse_equipment/eq-unauth-photo-01"), undefined);

  // 5. Equipment EDIT replacing photo (validEqPhoto1 -> validEqPhoto2)
  const updatedEqWithNewPhoto = await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "edit",
    id: eqPhotoTestId,
    data: {
      name: "Coleira Tática K9 Editada",
      photo_url: validEqPhoto2,
    },
  });
  assert.equal(updatedEqWithNewPhoto.photo_url, validEqPhoto2);
  assert.equal(db.docs.get(`warehouse_equipment/${eqPhotoTestId}`)?.photo_url, validEqPhoto2);

  // 6. Equipment EDIT omitting photo fields -> PRESERVES existing photo
  const updatedEqOmitPhoto = await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "edit",
    id: eqPhotoTestId,
    data: {
      name: "Coleira Tática K9 Nome Alterado",
      // photo fields omitted!
    },
  });
  assert.equal(updatedEqOmitPhoto.photo_url, validEqPhoto2);
  assert.equal(db.docs.get(`warehouse_equipment/${eqPhotoTestId}`)?.photo_url, validEqPhoto2);

  // 7. Equipment EDIT with explicit photo_remove: true -> REMOVES photo (persists null)
  const updatedEqRemovePhoto = await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "edit",
    id: eqPhotoTestId,
    data: {
      name: "Coleira Tática K9 Sem Foto",
      photo_url: null,
      photo_remove: true,
    },
  });
  assert.equal(updatedEqRemovePhoto.photo_url, null);
  assert.equal(db.docs.get(`warehouse_equipment/${eqPhotoTestId}`)?.photo_url, null);

  // 8. Legacy equipment without photo -> preserved
  db.docs.set("warehouse_equipment/eq-legacy-no-photo", {
    id: "eq-legacy-no-photo",
    name: "Equipamento Legado",
    identifier_code: "EQP-LEG-01",
    category_id: "cat-tatico",
    condition: "good",
    status: "available",
    current_location_id: "loc-almox-01",
    active: true,
    // photo_url undefined
  });
  await executeWarehouseUpsertEquipment(db as any, caller, {
    mode: "edit",
    id: "eq-legacy-no-photo",
    data: {
      name: "Equipamento Legado Atualizado",
    },
  });
  assert.equal(db.docs.get("warehouse_equipment/eq-legacy-no-photo")?.name, "Equipamento Legado Atualizado");
  assert.equal(db.docs.get("warehouse_equipment/eq-legacy-no-photo")?.photo_url, undefined);

  // D. Verify all 19 Warehouse Functions & Permission Denials
  console.log("Verifying all 19 Warehouse Functions & Callable exports...");
  let mockAuthFails = false;
  const permMockRequirePermission = async (auth: any, mod: string, act: string) => {
    if (mockAuthFails || !auth) {
      throw new (class extends Error { code = "permission-denied"; })("Acesso negado.");
    }
    return caller;
  };

  const all19Callables = createWarehouseCallables(db as any, permMockRequirePermission as any);

  const expected19Functions = [
    "adminWarehouseUpsertMaterial",
    "adminWarehouseArchiveMaterial",
    "adminWarehouseEntry",
    "adminWarehouseConsumption",
    "adminWarehouseTransfer",
    "adminWarehouseLossDisposal",
    "adminWarehouseUpsertEquipment",
    "adminWarehouseRetireEquipment",
    "adminWarehouseUpdateEquipmentStatus",
    "adminWarehouseOpenCustody",
    "adminWarehouseReturnCustody",
    "adminWarehouseCancelCustody",
    "adminWarehouseOpenInventorySession",
    "adminWarehouseRecordInventoryCount",
    "adminWarehouseAddUnexpectedCount",
    "adminWarehouseStartReconciliation",
    "adminWarehouseHomologateInventorySession",
    "adminWarehouseCancelInventorySession",
    "adminWarehouseGetOverview",
  ];

  for (const fnName of expected19Functions) {
    assert.equal(typeof (all19Callables as any)[fnName], "function", `Expected ${fnName} to be a callable function`);
  }
  assert.equal(Object.keys(all19Callables).length, 19, "Must export exactly 19 warehouse functions");

  // Test permission-denied propagation
  mockAuthFails = true;
  await rejects(
    (all19Callables.adminWarehouseUpsertMaterial as any).run({
      auth: null,
      data: { name: "Teste Sem Permissao" },
    }),
    "permission-denied",
  );

  await rejects(
    (all19Callables.adminWarehouseUpsertEquipment as any).run({
      auth: null,
      data: { name: "Equip Sem Permissao" },
    }),
    "permission-denied",
  );
  mockAuthFails = false;

  console.log("Warehouse domain and transaction tests passed");
}
main().catch((error) => {console.error(error); process.exitCode = 1;});

