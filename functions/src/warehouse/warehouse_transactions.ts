/**
 * K9 Ops — F60 Almoxarifado Backend Transaction Primitives
 * Location: canil-gcm/functions/src/warehouse/warehouse_transactions.ts
 */

import * as admin from "firebase-admin";
import {createHash} from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import {
  derivePositionDocId,
  formatBusinessDate,
  isBatchExpiredServer,
} from "./warehouse_domain";

export interface CallerContext {
  ra: string;
  name: string;
  uid: string;
}

/**
 * Checks whether a given position/material/location is inside an active inventory scope.
 * An active session is one with status in ['in_progress', 'reconciling'].
 * Throws warehouse/inventory-scope-locked if locked.
 */
export async function assertInventoryNotLocked(
  db: FirebaseFirestore.Firestore,
  item: {
    material_id: string;
    category_id?: string;
    location_id?: string;
  },
  transaction?: FirebaseFirestore.Transaction,
): Promise<void> {
  if (transaction) await transaction.get(db.collection("warehouse_control").doc("inventory_lock"));
  const activeSessionsQuery = db
    .collection("inventory_sessions")
    .where("status", "in", ["in_progress", "reconciling"]);

  const snapshots = transaction
    ? await transaction.get(activeSessionsQuery)
    : await activeSessionsQuery.get();

  for (const doc of snapshots.docs) {
    const session = doc.data();
    const scopeType = session.scope_type;
    const scopeRefId = session.scope_ref_id;

    if (scopeType === "full_warehouse") {
      throw new HttpsError(
        "failed-precondition",
        "Este estoque está em conferência de inventário geral. Movimentações serão liberadas após a conclusão ou cancelamento da sessão.",
        { code: "warehouse/inventory-scope-locked", sessionId: doc.id },
      );
    }

    if (scopeType === "by_location" && item.location_id && item.location_id === scopeRefId) {
      throw new HttpsError(
        "failed-precondition",
        `O local de estoque ${item.location_id} está em conferência de inventário. Movimentações serão liberadas após a conclusão da sessão.`,
        { code: "warehouse/inventory-scope-locked", sessionId: doc.id, locationId: item.location_id },
      );
    }

    if (scopeType === "by_category" && item.category_id && item.category_id === scopeRefId) {
      throw new HttpsError(
        "failed-precondition",
        `A categoria ${item.category_id} está em conferência de inventário. Movimentações serão liberadas após a conclusão da sessão.`,
        { code: "warehouse/inventory-scope-locked", sessionId: doc.id, categoryId: item.category_id },
      );
    }
  }
}

/**
 * Ensures idempotency: checks if command was already processed.
 */
export async function checkIdempotency(
  db: FirebaseFirestore.Firestore,
  idempotencyKey?: string | null,
  transaction?: FirebaseFirestore.Transaction,
  fingerprint?: string,
): Promise<Record<string, unknown> | null> {
  if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.includes("/") || idempotencyKey.trim().length > 500) {
    throw new HttpsError("invalid-argument", "Chave de idempotência obrigatória e válida para esta operação.");
  }
  const docRef = db.collection("idempotency_keys").doc(idempotencyKey.trim());
  const snap = transaction ? await transaction.get(docRef) : await docRef.get();
  if (snap.exists) {
    const data = snap.data();
    if (!fingerprint || data?.fingerprint !== fingerprint) throw new HttpsError("already-exists", "Chave de idempotência reutilizada para outra operação.");
    return (data?.response as Record<string, unknown>) ?? { idempotent_replay: true };
  }
  return null;
}

export async function recordIdempotency(
  db: FirebaseFirestore.Firestore,
  idempotencyKey: string | undefined | null,
  response: Record<string, unknown>,
  transaction: FirebaseFirestore.Transaction,
  fingerprint?: string,
): Promise<void> {
  if (!idempotencyKey || !idempotencyKey.trim()) return;
  const docRef = db.collection("idempotency_keys").doc(idempotencyKey.trim());
  transaction.set(docRef, {
    key: idempotencyKey.trim(),
    response,
    fingerprint,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function commandFingerprint(operation: string, caller: CallerContext, params: Record<string, unknown>): string {
  const {idempotency_key: _key, ...command} = params;
  return createHash("sha256").update(JSON.stringify({operation, uid: caller.uid, command})).digest("hex");
}

type WarehouseWrite = {ref: FirebaseFirestore.DocumentReference; data: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>; mode: "set" | "update"};

async function runWarehouseTransaction<T>(db: FirebaseFirestore.Firestore, work: (transaction: FirebaseFirestore.Transaction) => Promise<T>): Promise<T> {
  return db.runTransaction(async (transaction) => {
    const writes: WarehouseWrite[] = [];
    const deferred = new Proxy(transaction, {
      get(target, property) {
        if (property === "set" || property === "update") return (ref: FirebaseFirestore.DocumentReference, data: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>) => {
          writes.push({ref, data, mode: property});
          return deferred;
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) as FirebaseFirestore.Transaction;
    const result = await work(deferred);
    for (const write of writes) {
      if (write.mode === "set") transaction.set(write.ref, write.data);
      else transaction.update(write.ref, write.data);
    }
    return result;
  });
}

/**
 * 1. ENTRY PRIMITIVE
 */
export async function executeWarehouseEntry(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    material_id: string;
    lot_number: string;
    expiration_date: string; // YYYY-MM-DD
    destination_location_id: string;
    destination_location_name: string;
    quantity: number;
    reason: string;
    unit?: string;
    supplier_name?: string | null;
    invoice_reference?: string | null;
    idempotency_key?: string | null;
    notes?: string | null;
  },
): Promise<{
  movement_id: string;
  batch_id: string;
  position_id: string;
  material_on_hand: number;
  batch_on_hand: number;
  position_quantity: number;
}> {
  if (!Number.isFinite(params.quantity) || params.quantity <= 0) {
    throw new HttpsError("invalid-argument", "Quantidade de entrada deve ser estritamente positiva.");
  }
  if (!params.reason.trim()) {
    throw new HttpsError("invalid-argument", "Motivo de entrada é obrigatório.");
  }

  const fingerprint = commandFingerprint("Entry", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    const materialRef = db.collection("inventory_items").doc(params.material_id);
    const materialSnap = await transaction.get(materialRef);
    if (!materialSnap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }
    const materialData = materialSnap.data() ?? {};
    if (materialData.active === false || materialData.deleted_at != null) throw new HttpsError("failed-precondition", "Material inativo ou arquivado.");

    // Verify inventory lock
    await assertInventoryNotLocked(
      db,
      {
        material_id: params.material_id,
        category_id: materialData.category_id,
        location_id: params.destination_location_id,
      },
      transaction,
    );

    const nowTimestamp = admin.firestore.Timestamp.now();
    const expirationDate = params.expiration_date;
    if (!params.lot_number.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(expirationDate) ||
      !Number.isFinite(Date.parse(`${expirationDate}T00:00:00.000Z`)) ||
      new Date(`${expirationDate}T00:00:00.000Z`).toISOString().slice(0, 10) !== expirationDate) {
      throw new HttpsError("invalid-argument", "Lote ou validade inválidos.");
    }
    const batchId = `batch_${params.material_id}_${params.lot_number.trim()}`;
    const batchRef = db.collection("warehouse_batches").doc(batchId);
    const batchSnap = await transaction.get(batchRef);

    let batchOnHand = 0;
    if (batchSnap.exists) {
      const bData = batchSnap.data() ?? {};
      if (bData.material_id !== params.material_id || bData.expiration_date !== params.expiration_date || bData.status === "blocked") throw new HttpsError("failed-precondition", "Lote incompatível ou bloqueado.");
      batchOnHand = Number(bData.current_quantity || 0) + params.quantity;
      transaction.update(batchRef, {
        current_quantity: batchOnHand,
        status: "active",
        updated_at: nowTimestamp,
      });
    } else {
      batchOnHand = params.quantity;
      transaction.set(batchRef, {
        id: batchId,
        material_id: params.material_id,
        material_name: materialData.name || "Material",
        lot_number: params.lot_number.trim(),
        initial_quantity: params.quantity,
        current_quantity: params.quantity,
        expiration_date: params.expiration_date,
        received_at: nowTimestamp,
        status: "active",
        supplier_name: params.supplier_name || null,
        invoice_reference: params.invoice_reference || null,
        notes: params.notes || null,
        created_at: nowTimestamp,
        updated_at: nowTimestamp,
      });
    }

    // Position
    const positionId = derivePositionDocId(params.material_id, batchId, params.destination_location_id);
    const positionRef = db.collection("warehouse_positions").doc(positionId);
    const positionSnap = await transaction.get(positionRef);

    let positionQuantity = 0;
    if (positionSnap.exists) {
      const pData = positionSnap.data() ?? {};
      positionQuantity = Number(pData.quantity || 0) + params.quantity;
      transaction.update(positionRef, {
        quantity: positionQuantity,
        updated_at: nowTimestamp,
      });
    } else {
      positionQuantity = params.quantity;
      transaction.set(positionRef, {
        id: positionId,
        material_id: params.material_id,
        batch_id: batchId,
        lot_number: params.lot_number.trim(),
        location_id: params.destination_location_id,
        location_name: params.destination_location_name,
        quantity: params.quantity,
        unit: params.unit || materialData.unit || "unidade",
        updated_at: nowTimestamp,
        schema_version: 1,
      });
    }

    // Material total
    const materialBefore = Number(materialData.current_quantity || 0);
    if (!materialData.warehouse_managed && materialBefore !== 0) throw new HttpsError("failed-precondition", "Saldo legado requer reconciliação antes de movimentar lotes.");
    const materialAfter = materialBefore + params.quantity;
    transaction.update(materialRef, {
      current_quantity: materialAfter,
      warehouse_managed: true,
      updated_at: nowTimestamp,
    });

    // StockMovement
    const movementRef = db.collection("inventory_movements").doc();
    transaction.set(movementRef, {
      id: movementRef.id,
      material_id: params.material_id,
      material_name: materialData.name || "Material",
      batch_id: batchId,
      lot_number: params.lot_number.trim(),
      type: "entry",
      quantity: params.quantity,
      delta: params.quantity,
      unit: params.unit || materialData.unit || "unidade",
      reason: params.reason,
      balance_before: materialBefore,
      balance_after: materialAfter,
      destination_location_id: params.destination_location_id,
      destination_location_name: params.destination_location_name,
      performed_by_ra: caller.ra,
      performed_by_name: caller.name,
      performed_by_uid: caller.uid,
      performed_at: nowTimestamp,
      notes: params.notes || null,
      idempotency_key: params.idempotency_key || null,
      created_at: nowTimestamp,
    });

    // Audit
    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_material_entry",
      entity_type: "warehouse_material",
      entity_id: params.material_id,
      summary: `Entrada de ${params.quantity} ${params.unit || materialData.unit} do lote ${params.lot_number} em ${params.destination_location_name}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      movement_id: movementRef.id,
      batch_id: batchId,
      position_id: positionId,
      material_on_hand: materialAfter,
      batch_on_hand: batchOnHand,
      position_quantity: positionQuantity,
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

/**
 * 2. CONSUMPTION PRIMITIVE
 */
export async function executeWarehouseConsumption(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    material_id: string;
    batch_id?: string | null;
    source_location_id: string;
    quantity: number;
    reason: string;
    fefo_override_reason?: string | null;
    related_dog_id?: string | null;
    related_dog_name?: string | null;
    related_user_ra?: string | null;
    related_user_name?: string | null;
    related_occurrence_id?: string | null;
    idempotency_key?: string | null;
    notes?: string | null;
  },
): Promise<{
  movement_id: string;
  material_on_hand: number;
  batch_on_hand: number;
  position_quantity: number;
  allocations?: Array<{ batch_id: string; lot_number: string; allocated: number }>;
}> {
  if (!Number.isFinite(params.quantity) || params.quantity <= 0) {
    throw new HttpsError("invalid-argument", "Quantidade de consumo deve ser estritamente positiva.");
  }
  if (!params.reason.trim()) {
    throw new HttpsError("invalid-argument", "Motivo de consumo é obrigatório.");
  }

  const fingerprint = commandFingerprint("Consumption", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    const materialRef = db.collection("inventory_items").doc(params.material_id);
    const materialSnap = await transaction.get(materialRef);
    if (!materialSnap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }
    const materialData = materialSnap.data() ?? {};
    if (materialData.active === false || materialData.deleted_at != null) throw new HttpsError("failed-precondition", "Material inativo ou arquivado.");

    // Lock check
    await assertInventoryNotLocked(
      db,
      {
        material_id: params.material_id,
        category_id: materialData.category_id,
        location_id: params.source_location_id,
      },
      transaction,
    );

    const now = new Date();
    const todayString = formatBusinessDate(now);
    const nowTimestamp = admin.firestore.Timestamp.fromDate(now);

    // Multi-batch FEFO Consumption when batch_id is not specified or is "auto"
    if (!params.batch_id || params.batch_id === "auto") {
      const batchesSnap = await transaction.get(
        db.collection("warehouse_batches").where("material_id", "==", params.material_id),
      );
      const eligibleBatches = batchesSnap.docs
        .map((d) => ({ id: d.id, ...(d.data() as any) }))
        .filter(
          (b) =>
            b.status !== "blocked" &&
            b.status !== "depleted" &&
            Number(b.current_quantity || 0) > 0 &&
            (!b.expiration_date || !isBatchExpiredServer(b.expiration_date, todayString)),
        );

      eligibleBatches.sort((a, b) => {
        if (a.expiration_date !== b.expiration_date) {
          return String(a.expiration_date || "").localeCompare(String(b.expiration_date || ""));
        }
        const tA = a.received_at
          ? typeof a.received_at.toMillis === "function"
            ? a.received_at.toMillis()
            : new Date(a.received_at).getTime()
          : 0;
        const tB = b.received_at
          ? typeof b.received_at.toMillis === "function"
            ? b.received_at.toMillis()
            : new Date(b.received_at).getTime()
          : 0;
        if (tA !== tB) return tA - tB;
        return String(a.lot_number || "").localeCompare(String(b.lot_number || ""));
      });

      const allocations: Array<{
        batch: any;
        positionRef: FirebaseFirestore.DocumentReference;
        positionData: any;
        posCurrent: number;
        allocated: number;
      }> = [];

      let needed = params.quantity;
      let totalAvailableAtLocation = 0;

      for (const batch of eligibleBatches) {
        if (needed <= 0) break;
        const positionId = derivePositionDocId(params.material_id, batch.id, params.source_location_id);
        const positionRef = db.collection("warehouse_positions").doc(positionId);
        const positionSnap = await transaction.get(positionRef);
        if (!positionSnap.exists) continue;
        const positionData = positionSnap.data() ?? {};
        const posCurrent = Number(positionData.quantity || 0);
        if (posCurrent <= 0) continue;

        const maxAvailable = Math.min(posCurrent, Number(batch.current_quantity || 0));
        totalAvailableAtLocation += maxAvailable;
        const toTake = Math.min(needed, maxAvailable);
        if (toTake > 0) {
          allocations.push({
            batch,
            positionRef,
            positionData,
            posCurrent,
            allocated: toTake,
          });
          needed -= toTake;
        }
      }

      if (needed > 0) {
        throw new HttpsError(
          "failed-precondition",
          `Saldo insuficiente no local de origem para atendimento FEFO multi-lote. Disponível: ${params.quantity - needed}, Solicitado: ${params.quantity}.`,
        );
      }

      let firstMovementId = "";
      for (const alloc of allocations) {
        const posAfter = alloc.posCurrent - alloc.allocated;
        transaction.update(alloc.positionRef, {
          quantity: posAfter,
          updated_at: nowTimestamp,
        });

        const batchRef = db.collection("warehouse_batches").doc(alloc.batch.id);
        const batchBefore = Number(alloc.batch.current_quantity || 0);
        const batchAfter = batchBefore - alloc.allocated;
        const batchNewStatus = batchAfter <= 0 ? "depleted" : alloc.batch.status;
        transaction.update(batchRef, {
          current_quantity: batchAfter,
          status: batchNewStatus,
          updated_at: nowTimestamp,
        });

        const movementRef = db.collection("inventory_movements").doc();
        if (!firstMovementId) firstMovementId = movementRef.id;
        transaction.set(movementRef, {
          id: movementRef.id,
          material_id: params.material_id,
          material_name: materialData.name || "Material",
          batch_id: alloc.batch.id,
          lot_number: alloc.batch.lot_number || "",
          type: "consumption",
          quantity: alloc.allocated,
          delta: -alloc.allocated,
          unit: materialData.unit || "unidade",
          reason: params.reason,
          balance_before: Number(materialData.current_quantity || 0),
          balance_after: Number(materialData.current_quantity || 0) - params.quantity,
          origin_location_id: params.source_location_id,
          origin_location_name: alloc.positionData.location_name || null,
          performed_by_ra: caller.ra,
          performed_by_name: caller.name,
          performed_by_uid: caller.uid,
          performed_at: nowTimestamp,
          related_dog_id: params.related_dog_id || null,
          related_dog_name: params.related_dog_name || null,
          related_user_ra: params.related_user_ra || null,
          related_user_name: params.related_user_name || null,
          related_occurrence_id: params.related_occurrence_id || null,
          notes: params.notes || null,
          idempotency_key: params.idempotency_key ? `${params.idempotency_key}-${alloc.batch.id}` : null,
          created_at: nowTimestamp,
        });
      }

      // Decrement material global
      const matBefore = Number(materialData.current_quantity || 0);
      const matAfter = matBefore - params.quantity;
      transaction.update(materialRef, {
        current_quantity: matAfter,
        updated_at: nowTimestamp,
      });

      const auditRef = db.collection("auditLogs").doc();
      transaction.set(auditRef, {
        action: "warehouse_material_consumption_multi_batch",
        entity_type: "warehouse_material",
        entity_id: params.material_id,
        summary: `Saída FEFO multi-lote de ${params.quantity} ${materialData.unit}: ${params.reason}`,
        actor: caller,
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      const result = {
        movement_id: firstMovementId,
        material_on_hand: matAfter,
        batch_on_hand: 0,
        position_quantity: 0,
        allocations: allocations.map((a) => ({
          batch_id: a.batch.id,
          lot_number: a.batch.lot_number,
          allocated: a.allocated,
        })),
      };

      await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
      return result;
    }

    const batchRef = db.collection("warehouse_batches").doc(params.batch_id);
    const batchSnap = await transaction.get(batchRef);
    if (!batchSnap.exists) {
      throw new HttpsError("not-found", "Lote de estoque não encontrado.");
    }
    const batchData = batchSnap.data() ?? {};
    if (batchData.material_id !== params.material_id) throw new HttpsError("failed-precondition", "Lote não pertence ao material.");
    if (batchData.status === "blocked") {
      throw new HttpsError("failed-precondition", "Lote está bloqueado administrativamente para consumo.");
    }
    if (batchData.status === "depleted" || (batchData.current_quantity || 0) <= 0) {
      throw new HttpsError("failed-precondition", "Lote está esgotado.");
    }
    if (!batchData.expiration_date || isBatchExpiredServer(batchData.expiration_date, todayString)) {
      throw new HttpsError("failed-precondition", "Lote está com validade vencida e não pode ser consumido.");
    }

    // Position check
    const positionId = derivePositionDocId(params.material_id, params.batch_id, params.source_location_id);
    const positionRef = db.collection("warehouse_positions").doc(positionId);
    const positionSnap = await transaction.get(positionRef);
    if (!positionSnap.exists) {
      throw new HttpsError("not-found", "Posição de estoque não encontrada no local indicado.");
    }
    const positionData = positionSnap.data() ?? {};
    if (positionData.material_id !== params.material_id || positionData.batch_id !== params.batch_id) throw new HttpsError("failed-precondition", "Posição não corresponde ao lote.");
    const posCurrent = Number(positionData.quantity || 0);
    if (posCurrent < params.quantity) {
      throw new HttpsError(
        "failed-precondition",
        `Saldo insuficiente no local de origem. Disponível: ${posCurrent}, Solicitado: ${params.quantity}.`,
      );
    }

    // FEFO Override validation: check if an earlier valid batch exists at the same location
    const allBatchesSnap = await transaction.get(
      db.collection("warehouse_batches").where("material_id", "==", params.material_id),
    );
    const earlierBatches = allBatchesSnap.docs
      .map((d) => ({ id: d.id, ...(d.data() as any) }))
      .filter(
        (b) =>
          b.id !== params.batch_id &&
          b.status !== "blocked" &&
          b.status !== "depleted" &&
          Number(b.current_quantity || 0) > 0 &&
          (!b.expiration_date || !isBatchExpiredServer(b.expiration_date, todayString)) &&
          b.expiration_date < (batchData.expiration_date || "9999-99-99"),
      );

    let hasEarlierBatchAtLocation = false;
    for (const eb of earlierBatches) {
      const ebPosId = derivePositionDocId(params.material_id, eb.id, params.source_location_id);
      const ebPosSnap = await transaction.get(db.collection("warehouse_positions").doc(ebPosId));
      if (ebPosSnap.exists && Number(ebPosSnap.data()?.quantity || 0) > 0) {
        hasEarlierBatchAtLocation = true;
        break;
      }
    }

    if (hasEarlierBatchAtLocation) {
      const overrideReason = params.fefo_override_reason ? params.fefo_override_reason.trim() : "";
      if (!overrideReason || overrideReason.length < 4) {
        throw new HttpsError(
          "failed-precondition",
          "A seleção de lote com vencimento posterior (override de FEFO) exige justificativa operacional obrigatória.",
        );
      }
    }

    // Decrement position
    if (Number(batchData.current_quantity || 0) < params.quantity || Number(materialData.current_quantity || 0) < params.quantity) throw new HttpsError("failed-precondition", "Saldo global insuficiente.");
    const posAfter = posCurrent - params.quantity;
    transaction.update(positionRef, {
      quantity: posAfter,
      updated_at: nowTimestamp,
    });

    // Decrement batch
    const batchBefore = Number(batchData.current_quantity || 0);
    if (batchBefore < params.quantity) throw new HttpsError("failed-precondition", "Saldo de lote insuficiente.");
    const batchAfter = batchBefore - params.quantity;
    const batchNewStatus = batchAfter <= 0 ? "depleted" : batchData.status;
    transaction.update(batchRef, {
      current_quantity: batchAfter,
      status: batchNewStatus,
      updated_at: nowTimestamp,
    });

    // Decrement material
    const matBefore = Number(materialData.current_quantity || 0);
    if (matBefore < params.quantity) throw new HttpsError("failed-precondition", "Saldo de material insuficiente.");
    const matAfter = matBefore - params.quantity;
    transaction.update(materialRef, {
      current_quantity: matAfter,
      updated_at: nowTimestamp,
    });

    // StockMovement
    const movementRef = db.collection("inventory_movements").doc();
    transaction.set(movementRef, {
      id: movementRef.id,
      material_id: params.material_id,
      material_name: materialData.name || "Material",
      batch_id: params.batch_id,
      lot_number: batchData.lot_number || "",
      type: "consumption",
      quantity: params.quantity,
      delta: -params.quantity,
      unit: materialData.unit || "unidade",
      reason: params.reason,
      balance_before: matBefore,
      balance_after: matAfter,
      origin_location_id: params.source_location_id,
      origin_location_name: positionData.location_name || null,
      performed_by_ra: caller.ra,
      performed_by_name: caller.name,
      performed_by_uid: caller.uid,
      performed_at: nowTimestamp,
      related_dog_id: params.related_dog_id || null,
      related_dog_name: params.related_dog_name || null,
      related_user_ra: params.related_user_ra || null,
      related_user_name: params.related_user_name || null,
      related_occurrence_id: params.related_occurrence_id || null,
      notes: params.fefo_override_reason
        ? `[Override FEFO: ${params.fefo_override_reason.trim()}] ${params.notes || ""}`.trim()
        : params.notes || null,
      idempotency_key: params.idempotency_key || null,
      created_at: nowTimestamp,
    });

    // Audit
    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_material_consumption",
      entity_type: "warehouse_material",
      entity_id: params.material_id,
      summary: hasEarlierBatchAtLocation
        ? `Saída com override FEFO de ${params.quantity} ${materialData.unit} do lote ${batchData.lot_number}: ${params.reason} (Justificativa: ${params.fefo_override_reason})`
        : `Saída de ${params.quantity} ${materialData.unit} do lote ${batchData.lot_number}: ${params.reason}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      movement_id: movementRef.id,
      material_on_hand: matAfter,
      batch_on_hand: batchAfter,
      position_quantity: posAfter,
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

/**
 * 3. TRANSFER PRIMITIVE
 */
export async function executeWarehouseTransfer(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    material_id: string;
    batch_id: string;
    origin_location_id: string;
    destination_location_id: string;
    destination_location_name: string;
    quantity: number;
    reason: string;
    idempotency_key?: string | null;
    notes?: string | null;
  },
): Promise<{
  movement_id: string;
  origin_position_quantity: number;
  destination_position_quantity: number;
}> {
  if (!Number.isFinite(params.quantity) || params.quantity <= 0) {
    throw new HttpsError("invalid-argument", "Quantidade de transferência deve ser estritamente positiva.");
  }
  if (!params.reason.trim()) {
    throw new HttpsError("invalid-argument", "Motivo de transferência é obrigatório.");
  }
  if (params.origin_location_id === params.destination_location_id) {
    throw new HttpsError("invalid-argument", "Local de destino deve ser diferente do local de origem.");
  }

  const fingerprint = commandFingerprint("Transfer", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    const materialRef = db.collection("inventory_items").doc(params.material_id);
    const materialSnap = await transaction.get(materialRef);
    if (!materialSnap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }
    const materialData = materialSnap.data() ?? {};
    if (materialData.active === false || materialData.deleted_at != null) throw new HttpsError("failed-precondition", "Material inativo ou arquivado.");

    // Check lock on BOTH origin AND destination
    await assertInventoryNotLocked(
      db,
      {
        material_id: params.material_id,
        category_id: materialData.category_id,
        location_id: params.origin_location_id,
      },
      transaction,
    );
    await assertInventoryNotLocked(
      db,
      {
        material_id: params.material_id,
        category_id: materialData.category_id,
        location_id: params.destination_location_id,
      },
      transaction,
    );

    const nowTimestamp = admin.firestore.Timestamp.now();

    // Batch read
    const batchRef = db.collection("warehouse_batches").doc(params.batch_id);
    const batchSnap = await transaction.get(batchRef);
    if (!batchSnap.exists) {
      throw new HttpsError("not-found", "Lote não encontrado.");
    }
    const batchData = batchSnap.data() ?? {};
    if (batchData.material_id !== params.material_id) throw new HttpsError("failed-precondition", "Lote não pertence ao material.");

    // Origin Position
    const originPosId = derivePositionDocId(params.material_id, params.batch_id, params.origin_location_id);
    const originPosRef = db.collection("warehouse_positions").doc(originPosId);
    const originPosSnap = await transaction.get(originPosRef);
    if (!originPosSnap.exists) {
      throw new HttpsError("not-found", "Posição de origem não encontrada.");
    }
    const originData = originPosSnap.data() ?? {};
    if (originData.material_id !== params.material_id || originData.batch_id !== params.batch_id) throw new HttpsError("failed-precondition", "Posição não corresponde ao lote.");
    const originCurrent = Number(originData.quantity || 0);
    if (originCurrent < params.quantity) {
      throw new HttpsError(
        "failed-precondition",
        `Saldo insuficiente no local de origem. Disponível: ${originCurrent}, Solicitado: ${params.quantity}.`,
      );
    }

    // Destination Position
    const destPosId = derivePositionDocId(params.material_id, params.batch_id, params.destination_location_id);
    const destPosRef = db.collection("warehouse_positions").doc(destPosId);
    const destPosSnap = await transaction.get(destPosRef);

    if (batchData.status === "blocked") throw new HttpsError("failed-precondition", "Lote bloqueado.");
    const originAfter = originCurrent - params.quantity;
    transaction.update(originPosRef, {
      quantity: originAfter,
      updated_at: nowTimestamp,
    });

    let destAfter = 0;
    if (destPosSnap.exists) {
      const destData = destPosSnap.data() ?? {};
      destAfter = Number(destData.quantity || 0) + params.quantity;
      transaction.update(destPosRef, {
        quantity: destAfter,
        updated_at: nowTimestamp,
      });
    } else {
      destAfter = params.quantity;
      transaction.set(destPosRef, {
        id: destPosId,
        material_id: params.material_id,
        batch_id: params.batch_id,
        lot_number: batchData.lot_number || "",
        location_id: params.destination_location_id,
        location_name: params.destination_location_name,
        quantity: destAfter,
        unit: originData.unit || materialData.unit || "unidade",
        updated_at: nowTimestamp,
        schema_version: 1,
      });
    }

    // Global batch and material remain delta = 0!
    const totalMat = Number(materialData.current_quantity || 0);

    // Movement
    const movementRef = db.collection("inventory_movements").doc();
    transaction.set(movementRef, {
      id: movementRef.id,
      material_id: params.material_id,
      material_name: materialData.name || "Material",
      batch_id: params.batch_id,
      lot_number: batchData.lot_number || "",
      type: "transfer",
      quantity: params.quantity,
      delta: 0,
      unit: originData.unit || materialData.unit || "unidade",
      reason: params.reason,
      balance_before: totalMat,
      balance_after: totalMat,
      origin_location_id: params.origin_location_id,
      origin_location_name: originData.location_name || null,
      destination_location_id: params.destination_location_id,
      destination_location_name: params.destination_location_name,
      performed_by_ra: caller.ra,
      performed_by_name: caller.name,
      performed_by_uid: caller.uid,
      performed_at: nowTimestamp,
      notes: params.notes || null,
      idempotency_key: params.idempotency_key || null,
      created_at: nowTimestamp,
    });

    // Audit
    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_material_transfer",
      entity_type: "warehouse_material",
      entity_id: params.material_id,
      summary: `Transferência de ${params.quantity} ${originData.unit} do lote ${batchData.lot_number} de ${originData.location_name} para ${params.destination_location_name}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      movement_id: movementRef.id,
      origin_position_quantity: originAfter,
      destination_position_quantity: destAfter,
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

/**
 * 4. LOSS & DISPOSAL PRIMITIVE
 */
export async function executeWarehouseLossDisposal(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    material_id: string;
    batch_id: string;
    location_id: string;
    type: "loss" | "disposal";
    quantity: number;
    reason: string;
    idempotency_key?: string | null;
    notes?: string | null;
  },
): Promise<{
  movement_id: string;
  material_on_hand: number;
  batch_on_hand: number;
  position_quantity: number;
}> {
  if (!Number.isFinite(params.quantity) || params.quantity <= 0) {
    throw new HttpsError("invalid-argument", "Quantidade deve ser estritamente positiva.");
  }
  if (!params.reason.trim()) {
    throw new HttpsError("invalid-argument", "Motivo formal de baixa/perda é obrigatório.");
  }

  const fingerprint = commandFingerprint("LossDisposal", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    const materialRef = db.collection("inventory_items").doc(params.material_id);
    const materialSnap = await transaction.get(materialRef);
    if (!materialSnap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }
    const materialData = materialSnap.data() ?? {};
    if (materialData.active === false || materialData.deleted_at != null) throw new HttpsError("failed-precondition", "Material inativo ou arquivado.");
    await assertInventoryNotLocked(
      db,
      {
        material_id: params.material_id,
        category_id: materialData.category_id,
        location_id: params.location_id,
      },
      transaction,
    );

    const nowTimestamp = admin.firestore.Timestamp.now();
    const batchRef = db.collection("warehouse_batches").doc(params.batch_id);
    const batchSnap = await transaction.get(batchRef);
    if (!batchSnap.exists) {
      throw new HttpsError("not-found", "Lote não encontrado.");
    }
    const batchData = batchSnap.data() ?? {};
    if (batchData.material_id !== params.material_id) throw new HttpsError("failed-precondition", "Lote não pertence ao material.");

    const positionId = derivePositionDocId(params.material_id, params.batch_id, params.location_id);
    const positionRef = db.collection("warehouse_positions").doc(positionId);
    const positionSnap = await transaction.get(positionRef);
    if (!positionSnap.exists) {
      throw new HttpsError("not-found", "Posição física não encontrada.");
    }
    const positionData = positionSnap.data() ?? {};
    if (positionData.material_id !== params.material_id || positionData.batch_id !== params.batch_id) throw new HttpsError("failed-precondition", "Posição não corresponde ao lote.");
    const posCurrent = Number(positionData.quantity || 0);
    if (posCurrent < params.quantity) {
      throw new HttpsError("failed-precondition", "Saldo insuficiente na posição para realizar a baixa.");
    }

    if (Number(batchData.current_quantity || 0) < params.quantity || Number(materialData.current_quantity || 0) < params.quantity) throw new HttpsError("failed-precondition", "Saldo global insuficiente.");
    const posAfter = posCurrent - params.quantity;
    transaction.update(positionRef, {
      quantity: posAfter,
      updated_at: nowTimestamp,
    });

    const batchBefore = Number(batchData.current_quantity || 0);
    if (batchBefore < params.quantity) throw new HttpsError("failed-precondition", "Saldo de lote insuficiente.");
    const batchAfter = batchBefore - params.quantity;
    transaction.update(batchRef, {
      current_quantity: batchAfter,
      status: batchAfter <= 0 ? "depleted" : batchData.status,
      updated_at: nowTimestamp,
    });

    const matBefore = Number(materialData.current_quantity || 0);
    if (matBefore < params.quantity) throw new HttpsError("failed-precondition", "Saldo de material insuficiente.");
    const matAfter = matBefore - params.quantity;
    transaction.update(materialRef, {
      current_quantity: matAfter,
      updated_at: nowTimestamp,
    });

    const movementRef = db.collection("inventory_movements").doc();
    transaction.set(movementRef, {
      id: movementRef.id,
      material_id: params.material_id,
      material_name: materialData.name || "Material",
      batch_id: params.batch_id,
      lot_number: batchData.lot_number || "",
      type: params.type,
      quantity: params.quantity,
      delta: -params.quantity,
      unit: positionData.unit || materialData.unit || "unidade",
      reason: params.reason,
      balance_before: matBefore,
      balance_after: matAfter,
      origin_location_id: params.location_id,
      origin_location_name: positionData.location_name || null,
      performed_by_ra: caller.ra,
      performed_by_name: caller.name,
      performed_by_uid: caller.uid,
      performed_at: nowTimestamp,
      notes: params.notes || null,
      idempotency_key: params.idempotency_key || null,
      created_at: nowTimestamp,
    });

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: params.type === "loss" ? "warehouse_material_loss" : "warehouse_material_disposal",
      entity_type: "warehouse_material",
      entity_id: params.material_id,
      summary: `Baixa (${params.type}) de ${params.quantity} ${positionData.unit} do lote ${batchData.lot_number}: ${params.reason}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      movement_id: movementRef.id,
      material_on_hand: matAfter,
      batch_on_hand: batchAfter,
      position_quantity: posAfter,
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

/**
 * 5. CUSTODY PRIMITIVES
 */
export async function executeOpenCustody(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    equipment_id: string;
    borrower_ra: string;
    borrower_name: string;
    condition_at_dispatch: "new" | "good" | "fair";
    purpose: "daily_duty" | "training" | "operation" | "permanent_assignment";
    expected_return_at?: Date | null;
    linked_dog_id?: string | null;
    linked_dog_name?: string | null;
    linked_vehicle_prefix?: string | null;
    dispatch_notes?: string | null;
    idempotency_key?: string | null;
  },
): Promise<{
  custody_id: string;
  equipment_id: string;
  status: string;
}> {
  const fingerprint = commandFingerprint("OpenCustody", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    if (!params.borrower_ra.trim() || !params.borrower_name.trim() || !["new", "good", "fair"].includes(params.condition_at_dispatch) || !["daily_duty", "training", "operation", "permanent_assignment"].includes(params.purpose) || (params.expected_return_at && !Number.isFinite(params.expected_return_at.getTime()))) throw new HttpsError("invalid-argument", "Dados de cautela inválidos.");
    const equipmentRef = db.collection("warehouse_equipment").doc(params.equipment_id);
    const eqSnap = await transaction.get(equipmentRef);
    if (!eqSnap.exists) {
      throw new HttpsError("not-found", "Equipamento não encontrado.");
    }
    const eqData = eqSnap.data() ?? {};
    if (eqData.active === false || eqData.condition === "damaged" || eqData.condition !== params.condition_at_dispatch) throw new HttpsError("failed-precondition", "Equipamento inativo, danificado ou condição divergente.");
    if (eqData.status !== "available") {
      throw new HttpsError(
        "failed-precondition",
        `Equipamento não está disponível para cautela. Status atual: ${eqData.status}`,
      );
    }
    if (eqData.active_custody_id) {
      throw new HttpsError("failed-precondition", "Equipamento já possui uma cautela ativa vinculada.");
    }

    const nowTimestamp = admin.firestore.Timestamp.now();
    const custodyRef = db.collection("warehouse_custodies").doc();
    const custodyId = custodyRef.id;

    transaction.set(custodyRef, {
      id: custodyId,
      equipment_id: params.equipment_id,
      equipment_name: eqData.name || "Equipamento",
      equipment_code: eqData.identifier_code || params.equipment_id,
      borrower_ra: params.borrower_ra,
      borrower_name: params.borrower_name,
      dispatched_by_ra: caller.ra,
      dispatched_by_name: caller.name,
      dispatched_at: nowTimestamp,
      condition_at_dispatch: params.condition_at_dispatch,
      purpose: params.purpose,
      status: "active",
      expected_return_at: params.expected_return_at ? admin.firestore.Timestamp.fromDate(params.expected_return_at) : null,
      linked_dog_id: params.linked_dog_id || null,
      linked_dog_name: params.linked_dog_name || null,
      linked_vehicle_prefix: params.linked_vehicle_prefix || null,
      dispatch_notes: params.dispatch_notes || null,
      idempotency_key: params.idempotency_key || null,
      created_at: nowTimestamp,
    });

    transaction.update(equipmentRef, {
      status: "in_custody",
      active_custody_id: custodyId,
      updated_at: nowTimestamp,
    });

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_custody_opened",
      entity_type: "warehouse_equipment",
      entity_id: params.equipment_id,
      summary: `Cautela emitida para ${params.borrower_name} (${params.borrower_ra}) do bem ${eqData.identifier_code}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      custody_id: custodyId,
      equipment_id: params.equipment_id,
      status: "in_custody",
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

export const RETURN_CUSTODY_TARGET_STATUSES = ["available", "damaged", "maintenance"] as const;

export async function executeReturnCustody(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    custody_id: string;
    condition_at_return: "new" | "good" | "fair" | "damaged";
    return_notes?: string | null;
    target_equipment_status?: "available" | "damaged" | "maintenance";
    return_location_id?: string | null;
    return_location_name?: string | null;
    idempotency_key?: string | null;
  },
): Promise<{
  custody_id: string;
  equipment_id: string;
  equipment_status: string;
}> {
  const fingerprint = commandFingerprint("ReturnCustody", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    if (!["new", "good", "fair", "damaged"].includes(params.condition_at_return)) {
      throw new HttpsError("invalid-argument", "Condição de devolução inválida.");
    }
    if (
      params.target_equipment_status !== undefined &&
      params.target_equipment_status !== null &&
      (typeof params.target_equipment_status !== "string" ||
        !(RETURN_CUSTODY_TARGET_STATUSES as readonly string[]).includes(params.target_equipment_status))
    ) {
      throw new HttpsError("invalid-argument", "Status resultante de devolução inválido.");
    }
    if (params.condition_at_return === "damaged" && params.target_equipment_status === "available") {
      throw new HttpsError("invalid-argument", "Condição de devolução inválida.");
    }
    // F04: coerencia obrigatoria status x condicao. Um equipamento devolvido como
    // "damaged" exige condicao "damaged" (alinhado a adminWarehouseUpdateEquipmentStatus).
    if (params.target_equipment_status === "damaged" && params.condition_at_return !== "damaged") {
      throw new HttpsError("invalid-argument", "Equipamento devolvido como danificado exige condição de devolução 'damaged'.");
    }
    const custodyRef = db.collection("warehouse_custodies").doc(params.custody_id);
    const custodySnap = await transaction.get(custodyRef);
    if (!custodySnap.exists) {
      throw new HttpsError("not-found", "Cautela não encontrada.");
    }
    const custodyData = custodySnap.data() ?? {};
    if (custodyData.status !== "active") {
      throw new HttpsError("failed-precondition", "Cautela não está ativa.");
    }

    const equipmentRef = db.collection("warehouse_equipment").doc(custodyData.equipment_id);
    const eqSnap = await transaction.get(equipmentRef);
    if (!eqSnap.exists) {
      throw new HttpsError("not-found", "Equipamento vinculado não encontrado.");
    }
    const eqData = eqSnap.data() ?? {};
    if (eqData.active_custody_id !== params.custody_id || eqData.status !== "in_custody") throw new HttpsError("failed-precondition", "Cautela não corresponde ao estado do equipamento.");

    const nowTimestamp = admin.firestore.Timestamp.now();

    // Determine final equipment status
    const finalStatus: "available" | "damaged" | "maintenance" =
      params.target_equipment_status ??
      (params.condition_at_return === "damaged" ? "damaged" : "available");

    transaction.update(custodyRef, {
      status: "returned",
      returned_at: nowTimestamp,
      received_by_ra: caller.ra,
      received_by_name: caller.name,
      condition_at_return: params.condition_at_return,
      return_notes: params.return_notes || null,
    });

    const eqUpdates: Record<string, unknown> = {
      status: finalStatus,
      condition: params.condition_at_return,
      active_custody_id: null,
      updated_at: nowTimestamp,
    };
    if (params.return_location_id && params.return_location_name) {
      eqUpdates.current_location_id = params.return_location_id;
      eqUpdates.current_location_name = params.return_location_name;
    }

    transaction.update(equipmentRef, eqUpdates);

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_custody_returned",
      entity_type: "warehouse_equipment",
      entity_id: custodyData.equipment_id,
      summary: `Cautela devolvida por ${custodyData.borrower_name} do bem ${eqData.identifier_code || custodyData.equipment_code}. Estado: ${params.condition_at_return}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      custody_id: params.custody_id,
      equipment_id: custodyData.equipment_id,
      equipment_status: finalStatus,
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

export async function executeCancelCustody(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    custody_id: string;
    reason: string;
    idempotency_key?: string | null;
  },
): Promise<{
  custody_id: string;
  equipment_id: string;
  equipment_status: string;
}> {
  const reason = params.reason ? params.reason.trim() : "";
  if (!reason) {
    throw new HttpsError("invalid-argument", "Motivo de cancelamento da cautela é obrigatório.");
  }
  const custodyId = params.custody_id ? params.custody_id.trim() : "";
  if (!custodyId) {
    throw new HttpsError("invalid-argument", "Identificador da cautela obrigatório.");
  }

  const fingerprint = commandFingerprint("CancelCustody", caller, params);
  return runWarehouseTransaction(db, async (transaction) => {
    const replay = await checkIdempotency(db, params.idempotency_key, transaction, fingerprint);
    if (replay) return replay as any;

    const custodyRef = db.collection("warehouse_custodies").doc(custodyId);
    const custodySnap = await transaction.get(custodyRef);
    if (!custodySnap.exists) {
      throw new HttpsError("not-found", "Cautela não encontrada.");
    }
    const custodyData = custodySnap.data() ?? {};
    if (custodyData.status !== "active") {
      throw new HttpsError("failed-precondition", "Apenas cautelas ativas podem ser canceladas.");
    }

    const equipmentRef = db.collection("warehouse_equipment").doc(custodyData.equipment_id);
    const eqSnap = await transaction.get(equipmentRef);
    if (!eqSnap.exists) {
      throw new HttpsError("not-found", "Equipamento vinculado à cautela não encontrado.");
    }
    const eqData = eqSnap.data() ?? {};

    const nowTimestamp = admin.firestore.Timestamp.now();

    transaction.update(custodyRef, {
      status: "cancelled",
      cancelled_at: nowTimestamp,
      cancelled_by_ra: caller.ra,
      cancelled_by_name: caller.name,
      cancelled_by_uid: caller.uid,
      cancel_reason: reason,
    });

    transaction.update(equipmentRef, {
      active_custody_id: null,
      status: "available",
      updated_at: nowTimestamp,
    });

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_custody_cancelled",
      entity_type: "warehouse_equipment",
      entity_id: custodyData.equipment_id,
      summary: `Cautela de ${custodyData.borrower_name} (${eqData.identifier_code || custodyData.equipment_code}) cancelada por ${caller.name}: ${reason}`,
      actor: caller,
      metadata: {
        custody_id: custodyId,
        reason,
      },
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      custody_id: custodyId,
      equipment_id: custodyData.equipment_id,
      equipment_status: "available",
    };

    await recordIdempotency(db, params.idempotency_key, result, transaction, fingerprint);
    return result;
  });
}

/**
 * 6. INVENTORY SESSION PRIMITIVES
 */
export async function executeStartInventorySession(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    title: string;
    scope_type: "full_warehouse" | "by_location" | "by_category";
    scope_ref_id?: string | null;
    scope_label?: string | null;
    notes?: string | null;
  },
): Promise<{ session_id: string; total_positions_snapshotted: number }> {
  if (
    !params.title.trim() ||
    !["full_warehouse", "by_location", "by_category"].includes(params.scope_type) ||
    (params.scope_type !== "full_warehouse" && !params.scope_ref_id?.trim())
  ) {
    throw new HttpsError("invalid-argument", "Escopo de inventário inválido.");
  }

  const sessionRef = db.collection("inventory_sessions").doc();
  const sessionId = sessionRef.id;
  const nowTimestamp = admin.firestore.Timestamp.now();

  // 1. Transactional reservation of the single active lock and session initialization in 'building' state
  await runWarehouseTransaction(db, async (transaction) => {
    const lockRef = db.collection("warehouse_control").doc("inventory_lock");
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.data()?.active_session_id) {
      throw new HttpsError(
        "failed-precondition",
        "Já existe uma sessão de inventário ativa no almoxarifado.",
        { code: "warehouse/inventory-session-already-active", sessionId: lockSnap.data()?.active_session_id },
      );
    }
    const activeSessions = await transaction.get(
      db.collection("inventory_sessions").where("status", "in", ["in_progress", "reconciling"]),
    );
    if (!activeSessions.empty) {
      throw new HttpsError(
        "failed-precondition",
        "Já existe uma sessão de inventário ativa no almoxarifado.",
        { code: "warehouse/inventory-session-already-active", sessionId: activeSessions.docs[0].id },
      );
    }

    transaction.set(sessionRef, {
      id: sessionId,
      title: params.title.trim(),
      scope_type: params.scope_type,
      scope_ref_id: params.scope_ref_id || null,
      scope_label: params.scope_label || null,
      opened_by_ra: caller.ra,
      opened_by_name: caller.name,
      opened_at: nowTimestamp,
      status: "in_progress",
      snapshot_status: "building",
      notes: params.notes || null,
      total_items: 0,
      counted_items: 0,
      discrepant_items: 0,
      created_at: nowTimestamp,
      updated_at: nowTimestamp,
    });

    transaction.set(lockRef, {
      active_session_id: sessionId,
      scope_type: params.scope_type,
      scope_ref_id: params.scope_ref_id || null,
      updated_at: nowTimestamp,
    });

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_inventory_started",
      entity_type: "inventory_session",
      entity_id: sessionId,
      summary: `Inventário físico aberto (${params.title.trim()} - escopo: ${params.scope_type}) por ${caller.name}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });
  });

  // 2. Controlled snapshot population in bounded write batches (no arbitrary position cap)
  try {
    let positionsQuery: FirebaseFirestore.Query = db.collection("warehouse_positions");
    if (params.scope_type === "by_location") {
      positionsQuery = positionsQuery.where("location_id", "==", params.scope_ref_id);
    }

    let allowedMaterialIds: Set<string> | null = null;
    if (params.scope_type === "by_category") {
      const materialsSnap = await db.collection("inventory_items").where("category_id", "==", params.scope_ref_id).get();
      allowedMaterialIds = new Set(materialsSnap.docs.map((doc) => doc.id));
    }

    const positionsSnap = await positionsQuery.get();
    let scopedDocs = positionsSnap.docs;
    if (allowedMaterialIds) {
      scopedDocs = scopedDocs.filter((doc) => allowedMaterialIds!.has(doc.data().material_id));
    }

    let writeBatch = typeof db.batch === "function" ? db.batch() : null;
    let batchCount = 0;
    const BATCH_LIMIT = 250;

    for (const posDoc of scopedDocs) {
      const pos = posDoc.data();
      const countRef = sessionRef.collection("counts").doc(posDoc.id);
      const countData = {
        id: posDoc.id,
        session_id: sessionId,
        material_id: pos.material_id,
        material_name: pos.material_name || "Material",
        batch_id: pos.batch_id,
        lot_number: pos.lot_number || "",
        location_id: pos.location_id,
        location_name: pos.location_name || "",
        stock_position_id: posDoc.id,
        unit: pos.unit || "unidade",
        expected_quantity: Number(pos.quantity ?? 0),
        counted_quantity: null,
        discrepancy: null,
        discrepancy_reason: null,
        counted_by_ra: null,
        counted_by_name: null,
        counted_at: null,
        unexpected: false,
      };

      if (writeBatch) {
        writeBatch.set(countRef, countData);
        batchCount++;
        if (batchCount >= BATCH_LIMIT) {
          await writeBatch.commit();
          writeBatch = db.batch();
          batchCount = 0;
        }
      } else {
        await countRef.set(countData);
      }
    }

    if (writeBatch && batchCount > 0) {
      await writeBatch.commit();
    }

    // 3. Completeness verification and atomic activation of counting phase
    const finalCountsSnap = await sessionRef.collection("counts").get();
    if (finalCountsSnap.size !== scopedDocs.length) {
      throw new Error(`Inconsistência de snapshot: esperado ${scopedDocs.length}, gravado ${finalCountsSnap.size}`);
    }

    const completeTimestamp = admin.firestore.Timestamp.now();
    await sessionRef.update({
      snapshot_status: "complete",
      total_items: scopedDocs.length,
      updated_at: completeTimestamp,
    });

    return { session_id: sessionId, total_positions_snapshotted: scopedDocs.length };
  } catch (buildError) {
    // Fail-closed: record failure, keep lock active to avoid ambiguous state
    try {
      await sessionRef.update({
        snapshot_status: "failed",
        updated_at: admin.firestore.Timestamp.now(),
      });
    } catch {
      // ignore secondary error
    }
    throw buildError;
  }
}

export async function executeHomologateInventorySession(
  db: FirebaseFirestore.Firestore,
  caller: CallerContext,
  params: {
    sessionId: string;
    idempotencyKey?: string | null;
    notes?: string | null;
  },
): Promise<{
  session_id: string;
  adjustments_applied: number;
}> {
  const sessionId = params.sessionId;
  const idempotencyKey = params.idempotencyKey;
  const homologationNotes = typeof params.notes === "string" ? params.notes.trim() : "";
  const fingerprint = commandFingerprint(
    "HomologateInventory",
    caller,
    homologationNotes
      ? { sessionId, idempotency_key: idempotencyKey, notes: homologationNotes }
      : { sessionId, idempotency_key: idempotencyKey },
  );
  return runWarehouseTransaction(db, async (transaction) => {
    if (idempotencyKey) {
      const replay = await checkIdempotency(db, idempotencyKey, transaction, fingerprint);
      if (replay) return replay as any;
    }

    const sessionRef = db.collection("inventory_sessions").doc(sessionId);
    const sessionSnap = await transaction.get(sessionRef);
    if (!sessionSnap.exists) {
      throw new HttpsError("not-found", "Sessão de inventário não encontrada.");
    }
    const sessionData = sessionSnap.data() ?? {};

    // Tentativa de re-homologar sem idempotencyKey deve falhar fail-closed
    if (sessionData.status === "homologated") {
      if (idempotencyKey) {
        const result = {
          session_id: sessionId,
          adjustments_applied: sessionData.discrepant_items ?? 0,
        };
        await recordIdempotency(db, idempotencyKey, result, transaction, fingerprint);
        return result;
      }
      throw new HttpsError("failed-precondition", "Sessão de inventário já foi homologada.");
    }

    if (!["in_progress", "reconciling"].includes(sessionData.status)) {
      throw new HttpsError("failed-precondition", "Sessão de inventário não está aberta para homologação.");
    }

    if (sessionData.snapshot_status && sessionData.snapshot_status !== "complete") {
      throw new HttpsError("failed-precondition", "O snapshot do inventário não foi concluído com sucesso.");
    }

    const lockRef = db.collection("warehouse_control").doc("inventory_lock");
    const lock = await transaction.get(lockRef);
    if (lock.data()?.active_session_id !== sessionId) throw new HttpsError("failed-precondition", "Trava do inventário inconsistente.");
    const countsSnap = await transaction.get(sessionRef.collection("counts"));
    if (countsSnap.size !== sessionData.total_items) throw new HttpsError("failed-precondition", "Snapshot de inventário incompleto.");
    const nowTimestamp = admin.firestore.Timestamp.now();
    let adjustmentsApplied = 0;
    const materialBalances = new Map<string, number>();
    const batchBalances = new Map<string, number>();
    for (const countDoc of countsSnap.docs) {
      const count = countDoc.data();
      if (count.counted_quantity === null || count.counted_quantity === undefined || !Number.isFinite(Number(count.counted_quantity)) || Number(count.counted_quantity) < 0) throw new HttpsError("failed-precondition", "Todas as posições devem ser contadas antes da homologação.");
      const diff = Math.round((Number(count.counted_quantity) - Number(count.expected_quantity)) * 1000) / 1000;
      if (diff !== 0 && !String(count.discrepancy_reason || "").trim()) throw new HttpsError("failed-precondition", "Divergência sem justificativa.");
    }
    for (const countDoc of countsSnap.docs) {
      const count = countDoc.data();
      const diff = Math.round((Number(count.counted_quantity || 0) - Number(count.expected_quantity || 0)) * 1000) / 1000;

      if (diff !== 0) {
        if (!count.discrepancy_reason || !count.discrepancy_reason.trim()) {
          throw new HttpsError(
            "failed-precondition",
            `A contagem do item ${count.material_id} no local ${count.location_name} possui divergência (${diff}) sem justificativa obrigatória.`,
          );
        }

        // Apply adjustment to position (cria posição se não existia no caso de item inesperado com expected=0)
        const posRef = db.collection("warehouse_positions").doc(count.stock_position_id);
        const posSnap = await transaction.get(posRef);
        if (posSnap.exists) {
          const currentPosQty = Number(posSnap.data()?.quantity || 0);
          if (currentPosQty !== Number(count.expected_quantity)) throw new HttpsError("failed-precondition", "Posição alterada após abertura do inventário.");
          const newPosQty = currentPosQty + diff;
          if (newPosQty < 0) throw new HttpsError("failed-precondition", "Saldo da posição negativo.");
          transaction.update(posRef, {
            quantity: newPosQty,
            updated_at: nowTimestamp,
          });
        } else {
          // Posição física não existia previamente (ex.: item inesperado)
          if (Number(count.expected_quantity) !== 0) {
            throw new HttpsError("failed-precondition", "Posição do inventário não encontrada.");
          }
          if (diff < 0) throw new HttpsError("failed-precondition", "Saldo da posição negativo.");
          transaction.set(posRef, {
            id: count.stock_position_id,
            material_id: count.material_id,
            batch_id: count.batch_id,
            lot_number: count.lot_number || "",
            location_id: count.location_id,
            location_name: count.location_name || "",
            quantity: diff,
            unit: count.unit || "unidade",
            schema_version: 1,
            updated_at: nowTimestamp,
          });
        }

        // Apply adjustment to batch
        const batchRef = db.collection("warehouse_batches").doc(count.batch_id);
        const batchSnap = await transaction.get(batchRef);
        if (batchSnap.exists) {
          const currentBatchQty = batchBalances.get(count.batch_id) ?? Number(batchSnap.data()?.current_quantity || 0);
          const newBatchQty = currentBatchQty + diff;
          if (newBatchQty < 0) throw new HttpsError("failed-precondition", "Saldo de lote negativo.");
          batchBalances.set(count.batch_id, newBatchQty);
          transaction.update(batchRef, {
            current_quantity: newBatchQty,
            status: newBatchQty === 0 ? "depleted" : batchSnap.data()?.status === "blocked" ? "blocked" : "active",
            updated_at: nowTimestamp,
          });
        } else throw new HttpsError("failed-precondition", "Lote do inventário não encontrado.");

        // Apply adjustment to material
        const matRef = db.collection("inventory_items").doc(count.material_id);
        const matSnap = await transaction.get(matRef);
        let matBefore = 0;
        let matAfter = 0;
        if (matSnap.exists) {
          matBefore = materialBalances.get(count.material_id) ?? Number(matSnap.data()?.current_quantity || 0);
          matAfter = matBefore + diff;
          if (matAfter < 0) throw new HttpsError("failed-precondition", "Saldo de material negativo.");
          materialBalances.set(count.material_id, matAfter);
          transaction.update(matRef, {
            current_quantity: matAfter,
            status: matAfter <= 0 ? "out_of_stock" : "available",
            updated_at: nowTimestamp,
          });
        } else throw new HttpsError("failed-precondition", "Material do inventário não encontrado.");

        // Record inventory_adjustment movement
        const movRef = db.collection("inventory_movements").doc();
        transaction.set(movRef, {
          id: movRef.id,
          material_id: count.material_id,
          material_name: count.material_name || matSnap.data()?.name || "Material",
          batch_id: count.batch_id,
          lot_number: count.lot_number || "",
          type: "inventory_adjustment",
          quantity: Math.abs(diff),
          delta: diff,
          unit: count.unit || "unidade",
          reason: `Ajuste de inventário [Sessão: ${sessionData.title}] - Justificativa: ${count.discrepancy_reason}`,
          balance_before: matBefore,
          balance_after: matAfter,
          origin_location_id: count.location_id,
          origin_location_name: count.location_name,
          inventory_session_id: sessionId,
          inventory_count_id: countDoc.id,
          performed_by_ra: caller.ra,
          performed_by_name: caller.name,
          performed_by_uid: caller.uid,
          performed_at: nowTimestamp,
          created_at: nowTimestamp,
        });

        adjustmentsApplied++;
      }
    }

    transaction.set(lockRef, {active_session_id: null, updated_at: nowTimestamp});
    // F06: parecer de homologacao persistido no campo existente `notes` (sem novo schema),
    // preservando a observacao de abertura quando houver (anexado, nunca sobrescrito).
    const previousSessionNotes = typeof sessionData.notes === "string" ? sessionData.notes.trim() : "";
    const mergedSessionNotes = homologationNotes
      ? (previousSessionNotes
        ? `${previousSessionNotes}\n\n[Homologação] ${homologationNotes}`
        : `[Homologação] ${homologationNotes}`)
      : null;
    // Mark session homologated
    transaction.update(sessionRef, {
      status: "homologated",
      closed_by_ra: caller.ra,
      closed_by_name: caller.name,
      closed_at: nowTimestamp,
      discrepant_items: adjustmentsApplied,
      ...(mergedSessionNotes !== null ? { notes: mergedSessionNotes } : {}),
      updated_at: nowTimestamp,
    });

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: "warehouse_inventory_homologated",
      entity_type: "inventory_session",
      entity_id: sessionId,
      summary: `Sessão de inventário ${sessionData.title} homologada por ${caller.name} com ${adjustmentsApplied} ajustes.`,
      actor: caller,
      ...(homologationNotes ? { metadata: { session_id: sessionId, homologation_notes: homologationNotes } } : {}),
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const result = {
      session_id: sessionId,
      adjustments_applied: adjustmentsApplied,
    };

    if (idempotencyKey) {
      await recordIdempotency(db, idempotencyKey, result, transaction, fingerprint);
    }

    return result;
  });
}
