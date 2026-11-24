/**
 * K9 Ops — F60 Almoxarifado Backend Callables
 * Location: canil-gcm/functions/src/warehouse/warehouse_callables.ts
 */

import * as admin from "firebase-admin";
import {createHash} from "crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  LEGACY_RECONCILIATION_REQUIRED_MESSAGE,
  derivePositionDocId,
  formatBusinessDate,
  isBatchExpiredServer,
  normalizeEquipmentIdentifier,
  validateWarehousePhotoUrl,
} from "./warehouse_domain";
import {
  assertInventoryNotLocked,
  executeCancelCustody,
  executeHomologateInventorySession,
  executeOpenCustody,
  executeReturnCustody,
  executeStartInventorySession,
  executeWarehouseConsumption,
  executeWarehouseEntry,
  executeWarehouseLossDisposal,
  executeWarehouseTransfer,
} from "./warehouse_transactions";

const region = "southamerica-east1";

export async function reserveEquipmentIdentifier(
  db: FirebaseFirestore.Firestore,
  transaction: FirebaseFirestore.Transaction,
  id: string,
  code: string,
  existingEquipment = false,
): Promise<void> {
  const normalized = normalizeEquipmentIdentifier(code);
  const canonicalRef = db.collection("warehouse_equipment_identifiers").doc(normalized);
  const legacyHashRef = db.collection("warehouse_equipment_codes").doc(createHash("sha256").update(normalized).digest("hex"));

  const [canonicalSnap, legacyHashSnap] = await Promise.all([
    transaction.get(canonicalRef),
    transaction.get(legacyHashRef),
  ]);

  if (canonicalSnap.exists) {
    const ownerId = canonicalSnap.data()?.equipment_id;
    if (ownerId && ownerId !== id) {
      throw new HttpsError("already-exists", "Identificador de equipamento já cadastrado.");
    }
    // Documento canônico já indexado pertence a este equipamento
    return;
  }

  // Se canonicalRef não existe, mas legacyHashRef existe com outro proprietário:
  if (legacyHashSnap.exists) {
    const ownerId = legacyHashSnap.data()?.equipment_id;
    if (ownerId && ownerId !== id) {
      throw new HttpsError("already-exists", "Identificador de equipamento já cadastrado.");
    }
  }

  // Se já é um equipamento existente sendo atualizado mas sem índice canônico:
  if (existingEquipment) {
    const nowTimestamp = admin.firestore.Timestamp.now();
    transaction.set(canonicalRef, {
      equipment_id: id,
      identifier_code: code.trim(),
      normalized_identifier: normalized,
      created_at: nowTimestamp,
      updated_at: nowTimestamp,
    });
    transaction.set(legacyHashRef, {
      identifier_code: code.trim(),
      equipment_id: id,
    });
    return;
  }

  // Novo equipamento (não existente):
  // Verifica se a reconciliação legada foi certificada como completa
  const statusRef = db.collection("warehouse_control").doc("legacy_reconciliation_status");
  const statusSnap = await transaction.get(statusRef);
  const statusData = statusSnap.data();
  const isCertified = statusSnap.exists && (
    statusData?.status === "completed" ||
    statusData?.legacyReconciliationStatus === "completed" ||
    statusData?.reconciled === true
  );

  if (!isCertified) {
    throw new HttpsError("failed-precondition", LEGACY_RECONCILIATION_REQUIRED_MESSAGE);
  }

  const nowTimestamp = admin.firestore.Timestamp.now();
  transaction.set(canonicalRef, {
    equipment_id: id,
    identifier_code: code.trim(),
    normalized_identifier: normalized,
    created_at: nowTimestamp,
    updated_at: nowTimestamp,
  });
  transaction.set(legacyHashRef, {
    identifier_code: code.trim(),
    equipment_id: id,
  });
}


type CallerAuth = {
  uid: string;
  token: admin.auth.DecodedIdToken;
};

interface CallerIdentity {
  ra: string;
  name: string;
  uid: string;
}

export type PermissionChecker = (
  auth: CallerAuth | undefined,
  module: "inventory",
  action: "view" | "create" | "edit" | "archive" | "export" | "audit",
) => Promise<CallerIdentity>;

function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length === 0 ? undefined : text;
}

function requiredString(data: Record<string, any>, key: string): string {
  const value = stringValue(data[key]);
  if (!value) {
    throw new HttpsError("invalid-argument", `Campo obrigatório ausente: ${key}.`);
  }
  return value;
}

function optionalString(data: Record<string, any>, key: string): string | null {
  return stringValue(data[key]) ?? null;
}

function optionalNumberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;
  const parsed = Number(value.trim());
  return Number.isFinite(parsed) ? parsed : null;
}

export async function executeWarehouseUpsertMaterial(
  db: FirebaseFirestore.Firestore,
  caller: CallerIdentity,
  params: {
    mode: "create" | "edit";
    id?: string;
    profile: {
      id?: string;
      name: string;
      category_id: string;
      category_name?: string;
      unit: string;
      minimum_quantity?: number | string;
      minimumQuantity?: number | string;
      min_stock?: number | string;
      brand?: string;
      supplier_name?: string;
      supplierName?: string;
      description?: string;
      notes?: string;
      storage_conditions?: string;
      storageConditions?: string;
      current_quantity?: number;
      currentQuantity?: number;
      photo_url?: string | null;
      photo_remove?: boolean;
    };
    photo_url?: string | null;
    photo_remove?: boolean;
    current_quantity?: number;
  },
): Promise<{ id: string; created?: boolean; updated?: boolean; current_quantity: number; status: string; photo_url?: string | null }> {
  const mode = params.mode;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de material inválido.");
  }
  const rawProfile = (params.profile ?? {}) as Record<string, any>;
  const nestedProfile = (rawProfile.profile && typeof rawProfile.profile === "object")
    ? rawProfile.profile
    : (rawProfile.data && typeof rawProfile.data === "object")
    ? rawProfile.data
    : {};
  const profile = { ...nestedProfile, ...rawProfile };

  const name = requiredString(profile, "name");
  const categoryId = requiredString(profile, "category_id");
  const unit = requiredString(profile, "unit");
  const minimumQuantityRaw = profile.minimum_quantity ?? profile.minimumQuantity ?? profile.min_stock;
  const minimumQuantity = optionalNumberValue(minimumQuantityRaw);
  if (minimumQuantity === null || minimumQuantity < 0) {
    throw new HttpsError("invalid-argument", "Quantidade mínima deve ser um número não negativo.");
  }

  const requestedId = stringValue(params.id) ?? stringValue(profile.id);
  const materialId = requestedId ?? name.trim().toLowerCase().replace(/[^a-z0-9_-]/g, "_");
  if (materialId.includes("/")) {
    throw new HttpsError("invalid-argument", "Identificador do material inválido.");
  }

  const rawPhotoRemove = params.photo_remove !== undefined
    ? params.photo_remove
    : profile.photo_remove;
  const isPhotoRemove = rawPhotoRemove === true;

  const rawPhotoUrl = params.photo_url !== undefined
    ? params.photo_url
    : profile.photo_url;

  if (isPhotoRemove && rawPhotoUrl) {
    throw new HttpsError(
      "invalid-argument",
      "Não é permitido fornecer photo_url e photo_remove simultaneamente.",
    );
  }

  let validatedPhotoUrl: string | null | undefined = undefined;
  if (isPhotoRemove) {
    validatedPhotoUrl = null;
  } else if (rawPhotoUrl !== undefined && rawPhotoUrl !== null) {
    validatedPhotoUrl = validateWarehousePhotoUrl(rawPhotoUrl);
  }

  const brand = optionalString(profile, "brand");
  const supplierName = optionalString(profile, "supplier_name") ?? optionalString(profile, "supplierName");
  const description = optionalString(profile, "description");
  const notes = optionalString(profile, "notes");
  const storageConditions = optionalString(profile, "storage_conditions") ?? optionalString(profile, "storageConditions");
  const categoryName = optionalString(profile, "category_name") ?? optionalString(profile, "categoryName") ?? categoryId;

  const ref = db.collection("inventory_items").doc(materialId);

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (mode === "create" && snap.exists) {
      throw new HttpsError("already-exists", "Já existe um material cadastrado com este identificador.");
    }
    if (mode === "edit" && !snap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }

    const existingData = snap.data() ?? {};
    const nowTimestamp = admin.firestore.Timestamp.now();

    if (mode === "create") {
      const newRecord: Record<string, any> = {
        id: materialId,
        name,
        category_id: categoryId,
        category_name: categoryName,
        unit,
        current_quantity: 0,
        minimum_quantity: minimumQuantity,
        status: "out_of_stock",
        active: true,
        warehouse_managed: true,
        brand,
        supplier_name: supplierName,
        description,
        notes,
        storage_conditions: storageConditions,
        photo_url: validatedPhotoUrl ?? null,
        created_at: nowTimestamp,
        updated_at: nowTimestamp,
      };
      transaction.set(ref, newRecord);

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_material_created",
        entity_type: "warehouse_material",
        entity_id: materialId,
        summary: `Material criado no almoxarifado: ${name}`,
        actor: caller,
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { id: materialId, created: true, current_quantity: 0, status: "out_of_stock", photo_url: newRecord.photo_url };
    }

    // mode === 'edit'
    if (
      params.current_quantity !== undefined ||
      profile.current_quantity !== undefined ||
      profile.currentQuantity !== undefined
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Não é permitido alterar saldo físico diretamente pelo cadastro de material.",
      );
    }

    // Não permite alterar unit se houver lotes com saldo
    if (unit !== existingData.unit) {
      const batchesWithBalance = await transaction.get(
        db.collection("warehouse_batches")
          .where("material_id", "==", materialId)
          .where("current_quantity", ">", 0),
      );
      if (!batchesWithBalance.empty) {
        throw new HttpsError(
          "failed-precondition",
          "Não é permitido alterar a unidade de medida de material com lotes em estoque.",
        );
      }
    }

    // Se a categoria foi alterada, impede alteração caso haja inventário ativo no escopo da categoria
    if (existingData.category_id && categoryId !== existingData.category_id) {
      await assertInventoryNotLocked(db, { material_id: materialId, category_id: existingData.category_id }, transaction);
      await assertInventoryNotLocked(db, { material_id: materialId, category_id: categoryId }, transaction);
    }

    const currentQuantity = Number(existingData.current_quantity || 0);
    let calculatedStatus = existingData.status || "active";
    if (currentQuantity === 0) {
      calculatedStatus = "out_of_stock";
    } else if (currentQuantity <= minimumQuantity) {
      calculatedStatus = "low_stock";
    } else {
      calculatedStatus = "in_stock";
    }

    const updates: Record<string, any> = {
      name,
      category_id: categoryId,
      category_name: categoryName,
      unit,
      minimum_quantity: minimumQuantity,
      warehouse_managed: true,
      brand,
      supplier_name: supplierName,
      description,
      notes,
      storage_conditions: storageConditions,
      status: calculatedStatus,
      updated_at: nowTimestamp,
    };

    if (isPhotoRemove) {
      updates.photo_url = null;
    } else if (typeof validatedPhotoUrl === "string") {
      updates.photo_url = validatedPhotoUrl;
    } else {
      // Preserve existing photo when fields are omitted or null without explicit photo_remove
      if (existingData.photo_url !== undefined) {
        updates.photo_url = existingData.photo_url;
      }
    }

    transaction.update(ref, updates);

    transaction.set(db.collection("auditLogs").doc(), {
      action: "warehouse_material_updated",
      entity_type: "warehouse_material",
      entity_id: materialId,
      summary: `Material atualizado no almoxarifado: ${name}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const finalPhotoUrl = updates.photo_url !== undefined
      ? updates.photo_url
      : (existingData.photo_url ?? null);

    return { id: materialId, updated: true, current_quantity: currentQuantity, status: calculatedStatus, photo_url: finalPhotoUrl };
  });
}

export async function executeWarehouseArchiveMaterial(
  db: FirebaseFirestore.Firestore,
  caller: CallerIdentity,
  params: { id: string; reason: string },
): Promise<{ id: string; archived: true }> {
  const materialId = requiredString(params, "id");
  const reason = requiredString(params, "reason");

  if (materialId.includes("/")) {
    throw new HttpsError("invalid-argument", "Identificador do material inválido.");
  }

  const ref = db.collection("inventory_items").doc(materialId);

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Material não encontrado.");
    }
    const materialData = snap.data() ?? {};
    const currentQuantity = Number(materialData.current_quantity || 0);
    if (currentQuantity > 0) {
      throw new HttpsError(
        "failed-precondition",
        "Não é permitido arquivar material com estoque físico.",
      );
    }

    const nowTimestamp = admin.firestore.Timestamp.now();
    transaction.update(ref, {
      active: false,
      status: "inactive",
      deleted_at: nowTimestamp,
      deleted_by: caller.uid,
      delete_reason: reason,
      deleted_reason: reason,
      updated_at: nowTimestamp,
    });

    transaction.set(db.collection("auditLogs").doc(), {
      action: "warehouse_material_archived",
      entity_type: "warehouse_material",
      entity_id: materialId,
      summary: `Material arquivado no almoxarifado: ${materialData.name || materialId}`,
      actor: caller,
      metadata: { reason },
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    return { id: materialId, archived: true };
  });
}

export async function executeWarehouseUpsertEquipment(
  db: FirebaseFirestore.Firestore,
  caller: CallerIdentity,
  params: {
    mode: "create" | "edit";
    id?: string;
    data: Record<string, any>;
  },
): Promise<{ id: string; saved: true; created?: boolean; updated?: boolean; status: string; photo_url?: string | null }> {
  const mode = params.mode;
  if (!["create", "edit"].includes(mode)) {
    throw new HttpsError("invalid-argument", "Modo de equipamento inválido.");
  }

  const rawData = (params.data ?? {}) as Record<string, any>;
  const nestedData = (rawData.profile && typeof rawData.profile === "object")
    ? rawData.profile
    : (rawData.data && typeof rawData.data === "object")
    ? rawData.data
    : {};
  const data = { ...nestedData, ...rawData };

  const id = stringValue(params.id) ?? stringValue(data.id) ?? stringValue(data.equipment_id);
  const targetId = id || db.collection("warehouse_equipment").doc().id;
  if (targetId.includes("/")) {
    throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
  }

  const rawPhotoRemove = data.photo_remove;
  const isPhotoRemove = rawPhotoRemove === true;
  const rawPhotoUrl = data.photo_url;

  if (isPhotoRemove && rawPhotoUrl) {
    throw new HttpsError(
      "invalid-argument",
      "Não é permitido fornecer photo_url e photo_remove simultaneamente.",
    );
  }

  let validatedPhotoUrl: string | null | undefined = undefined;
  if (isPhotoRemove) {
    validatedPhotoUrl = null;
  } else if (rawPhotoUrl !== undefined && rawPhotoUrl !== null) {
    validatedPhotoUrl = validateWarehousePhotoUrl(rawPhotoUrl);
  }

  const ref = db.collection("warehouse_equipment").doc(targetId);
  const nowTimestamp = admin.firestore.Timestamp.now();

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (mode === "create" && snap.exists) {
      throw new HttpsError("already-exists", "Equipamento já cadastrado com este identificador.");
    }
    if (mode === "edit" && !snap.exists) {
      throw new HttpsError("not-found", "Equipamento não encontrado.");
    }

    const previous = snap.data() ?? {};

    if (mode === "create") {
      const name = requiredString(data, "name");
      const categoryId = requiredString(data, "category_id");
      const currentLocationId = requiredString(data, "current_location_id");
      const condition = requiredString(data, "condition");
      if (!["new", "good", "fair", "damaged"].includes(condition)) {
        throw new HttpsError("invalid-argument", "Condição do equipamento inválida.");
      }
      const identifierCodeRaw = requiredString(data, "identifier_code");
      const normalizedIdentifier = normalizeEquipmentIdentifier(identifierCodeRaw);

      await reserveEquipmentIdentifier(db, transaction, targetId, identifierCodeRaw, false);

      const initialStatus = condition === "damaged" ? "damaged" : "available";

      const newEquipment: Record<string, any> = {
        id: targetId,
        name,
        category_id: categoryId,
        category_name: stringValue(data.category_name) ?? categoryId,
        identifier_code: identifierCodeRaw.trim(),
        normalized_identifier: normalizedIdentifier,
        condition,
        status: initialStatus,
        current_location_id: currentLocationId,
        current_location_name: stringValue(data.current_location_name) ?? "",
        active: true,
        brand: optionalString(data, "brand"),
        model: optionalString(data, "model"),
        serial_number: optionalString(data, "serial_number"),
        size: optionalString(data, "size"),
        color: optionalString(data, "color"),
        acquisition_date: optionalString(data, "acquisition_date"),
        assigned_dog_id: optionalString(data, "assigned_dog_id"),
        assigned_dog_name: optionalString(data, "assigned_dog_name"),
        assigned_vehicle_id: optionalString(data, "assigned_vehicle_id"),
        assigned_vehicle_prefix: optionalString(data, "assigned_vehicle_prefix"),
        active_custody_id: null,
        photo_url: validatedPhotoUrl ?? null,
        notes: optionalString(data, "notes"),
        created_at: nowTimestamp,
        updated_at: nowTimestamp,
      };

      transaction.set(ref, newEquipment);

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_equipment_created",
        entity_type: "warehouse_equipment",
        entity_id: targetId,
        summary: `Equipamento cadastrado: ${name} (${identifierCodeRaw.trim()})`,
        actor: caller,
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { id: targetId, saved: true, created: true, status: initialStatus, photo_url: newEquipment.photo_url };
    }

    // mode === 'edit'
    if (data.identifier_code !== undefined) {
      const incomingNormalized = normalizeEquipmentIdentifier(data.identifier_code);
      const existingNormalized = previous.normalized_identifier ||
        (previous.identifier_code ? normalizeEquipmentIdentifier(previous.identifier_code) : "");
      if (incomingNormalized !== existingNormalized) {
        throw new HttpsError("failed-precondition", "Proibido alterar identifier_code de equipamento existente.");
      }
    }

    if (data.status !== undefined && data.status !== previous.status) {
      throw new HttpsError(
        "failed-precondition",
        "Status do equipamento não pode ser alterado diretamente pelo formulário de edição.",
      );
    }

    const isCautelado = previous.active_custody_id != null || previous.status === "in_custody";
    if (isCautelado) {
      if (data.condition !== undefined && data.condition !== previous.condition) {
        throw new HttpsError(
          "failed-precondition",
          "Equipamento em cautela ativa não pode ter sua condição alterada.",
        );
      }
      if (data.current_location_id !== undefined && data.current_location_id !== previous.current_location_id) {
        throw new HttpsError(
          "failed-precondition",
          "Equipamento em cautela ativa não pode ter sua localização alterada.",
        );
      }
    }

    let newCondition = previous.condition;
    if (data.condition !== undefined) {
      const condStr = String(data.condition).trim();
      if (!["new", "good", "fair", "damaged"].includes(condStr)) {
        throw new HttpsError("invalid-argument", "Condição do equipamento inválida.");
      }
      newCondition = condStr;
    }

    const name = data.name !== undefined ? requiredString(data, "name") : previous.name;
    const categoryId = data.category_id !== undefined ? requiredString(data, "category_id") : previous.category_id;
    const currentLocationId = data.current_location_id !== undefined ?
      requiredString(data, "current_location_id") : previous.current_location_id;

    const updates: Record<string, any> = {
      name,
      category_id: categoryId,
      category_name: data.category_name !== undefined ?
        (stringValue(data.category_name) ?? categoryId) : (previous.category_name || categoryId),
      condition: newCondition,
      current_location_id: currentLocationId,
      current_location_name: data.current_location_name !== undefined ?
        (stringValue(data.current_location_name) ?? "") : (previous.current_location_name || ""),
      brand: data.brand !== undefined ? optionalString(data, "brand") : previous.brand || null,
      model: data.model !== undefined ? optionalString(data, "model") : previous.model || null,
      serial_number: data.serial_number !== undefined ?
        optionalString(data, "serial_number") : previous.serial_number || null,
      size: data.size !== undefined ? optionalString(data, "size") : previous.size || null,
      color: data.color !== undefined ? optionalString(data, "color") : previous.color || null,
      notes: data.notes !== undefined ? optionalString(data, "notes") : previous.notes || null,
      updated_at: nowTimestamp,
    };

    if (isPhotoRemove) {
      updates.photo_url = null;
    } else if (typeof validatedPhotoUrl === "string") {
      updates.photo_url = validatedPhotoUrl;
    } else {
      if (previous.photo_url !== undefined) {
        updates.photo_url = previous.photo_url;
      }
    }

    transaction.update(ref, updates);

    transaction.set(db.collection("auditLogs").doc(), {
      action: "warehouse_equipment_updated",
      entity_type: "warehouse_equipment",
      entity_id: targetId,
      summary: `Equipamento atualizado: ${name}`,
      actor: caller,
      source: "functions",
      performed_at: nowTimestamp,
      createdAt: nowTimestamp,
    });

    const finalPhotoUrl = updates.photo_url !== undefined
      ? updates.photo_url
      : (previous.photo_url ?? null);

    return { id: targetId, saved: true, updated: true, status: previous.status, photo_url: finalPhotoUrl };
  });
}

export function createWarehouseCallables(
  db: FirebaseFirestore.Firestore,
  requireAccessPermission: PermissionChecker,
) {
  const adminWarehouseUpsertMaterial = onCall({ region }, async (request) => {
    const data = (request.data ?? {}) as Record<string, any>;
    const mode = (data.mode || (data.id ? "edit" : "create")) as "create" | "edit";
    if (!["create", "edit"].includes(mode)) {
      throw new HttpsError("invalid-argument", "Modo de material inválido.");
    }
    const caller = await requireAccessPermission(
      request.auth as CallerAuth,
      "inventory",
      mode === "create" ? "create" : "edit",
    );
    const profile = (data.profile && typeof data.profile === "object")
      ? data.profile
      : (data.data && typeof data.data === "object")
      ? data.data
      : data;
    return executeWarehouseUpsertMaterial(db, caller, {
      mode,
      id: data.id,
      profile,
      photo_url: data.photo_url,
      photo_remove: data.photo_remove,
    });
  });

  const adminWarehouseArchiveMaterial = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "archive");
    const data = (request.data ?? {}) as Record<string, any>;
    const id = String(data.id || data.material_id || "").trim();
    const reason = String(data.reason || "").trim();
    return executeWarehouseArchiveMaterial(db, caller, { id, reason });
  });

  const adminWarehouseEntry = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    const data = (request.data ?? {}) as Record<string, any>;
    return executeWarehouseEntry(db, caller, {
      material_id: String(data.material_id || "").trim(),
      lot_number: String(data.lot_number || "").trim(),
      expiration_date: String(data.expiration_date || "").trim(),
      destination_location_id: String(data.destination_location_id || "").trim(),
      destination_location_name: String(data.destination_location_name || data.destinationLocationName || "").trim(),
      quantity: Number(data.quantity),
      reason: String(data.reason || "").trim(),
      unit: data.unit ? String(data.unit) : undefined,
      supplier_name: data.supplier_name ? String(data.supplier_name) : null,
      invoice_reference: data.invoice_reference ? String(data.invoice_reference) : null,
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
      notes: data.notes ? String(data.notes) : null,
    });
  });

  const adminWarehouseConsumption = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    const data = (request.data ?? {}) as Record<string, any>;
    return executeWarehouseConsumption(db, caller, {
      material_id: String(data.material_id || "").trim(),
      batch_id: String(data.batch_id || "").trim(),
      source_location_id: String(data.source_location_id || data.origin_location_id || "").trim(),
      quantity: Number(data.quantity),
      reason: String(data.reason || "").trim(),
      fefo_override_reason: data.fefo_override_reason ? String(data.fefo_override_reason).trim() : null,
      related_dog_id: data.related_dog_id ? String(data.related_dog_id) : null,
      related_dog_name: data.related_dog_name ? String(data.related_dog_name) : null,
      related_user_ra: data.related_user_ra ? String(data.related_user_ra) : null,
      related_user_name: data.related_user_name ? String(data.related_user_name) : null,
      related_occurrence_id: data.related_occurrence_id ? String(data.related_occurrence_id) : null,
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
      notes: data.notes ? String(data.notes) : null,
    });
  });

  const adminWarehouseTransfer = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    const data = (request.data ?? {}) as Record<string, any>;
    return executeWarehouseTransfer(db, caller, {
      material_id: String(data.material_id || "").trim(),
      batch_id: String(data.batch_id || "").trim(),
      origin_location_id: String(data.origin_location_id || "").trim(),
      destination_location_id: String(data.destination_location_id || "").trim(),
      destination_location_name: String(data.destination_location_name || data.destinationLocationName || "").trim(),
      quantity: Number(data.quantity),
      reason: String(data.reason || "").trim(),
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
      notes: data.notes ? String(data.notes) : null,
    });
  });

  const adminWarehouseLossDisposal = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    const data = (request.data ?? {}) as Record<string, any>;
    const type = data.type === "loss" ? "loss" : "disposal";
    return executeWarehouseLossDisposal(db, caller, {
      material_id: String(data.material_id || "").trim(),
      batch_id: String(data.batch_id || "").trim(),
      location_id: String(data.location_id || data.origin_location_id || "").trim(),
      type,
      quantity: Number(data.quantity),
      reason: String(data.reason || "").trim(),
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
      notes: data.notes ? String(data.notes) : null,
    });
  });

  const adminWarehouseUpsertEquipment = onCall({ region }, async (request) => {
    const raw = (request.data ?? {}) as Record<string, any>;
    const id = stringValue(raw.id) ?? stringValue(raw.equipment_id);
    const mode = (raw.mode || (id ? "edit" : "create")) as "create" | "edit";
    if (!["create", "edit"].includes(mode)) {
      throw new HttpsError("invalid-argument", "Modo de equipamento inválido.");
    }
    const caller = await requireAccessPermission(
      request.auth as CallerAuth,
      "inventory",
      mode === "create" ? "create" : "edit",
    );
    return executeWarehouseUpsertEquipment(db, caller, { mode, id, data: raw });
  });

  const adminWarehouseRetireEquipment = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "archive");
    const data = (request.data ?? {}) as Record<string, any>;
    const equipmentId = requiredString(data, "equipment_id" in data ? "equipment_id" : "id");
    const reason = requiredString(data, "reason");

    if (equipmentId.includes("/")) {
      throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
    }

    const ref = db.collection("warehouse_equipment").doc(equipmentId);
    return db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Equipamento não encontrado.");
      }
      const eqData = snap.data() ?? {};
      if (eqData.active_custody_id != null || eqData.status === "in_custody") {
        throw new HttpsError("failed-precondition", "Equipamento com cautela ativa não pode ser baixado/aposentado.");
      }
      if (eqData.status === "retired") {
        throw new HttpsError("failed-precondition", "Equipamento já se encontra baixado/aposentado.");
      }

      const nowTimestamp = admin.firestore.Timestamp.now();
      transaction.update(ref, {
        status: "retired",
        active: false,
        retired_at: nowTimestamp,
        retired_by: caller.uid,
        retire_reason: reason,
        updated_at: nowTimestamp,
      });

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_equipment_retired",
        entity_type: "warehouse_equipment",
        entity_id: equipmentId,
        summary: `Equipamento aposentado/baixado: ${eqData.name || equipmentId}. Motivo: ${reason}`,
        actor: caller,
        metadata: {
          equipment_id: equipmentId,
          reason,
        },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { id: equipmentId, retired: true, status: "retired" };
    });
  });

  const adminWarehouseUpdateEquipmentStatus = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "edit");
    const data = (request.data ?? {}) as Record<string, any>;
    const equipmentId = requiredString(data, "equipment_id" in data ? "equipment_id" : "id");
    const targetStatus = requiredString(data, "target_status");

    if (equipmentId.includes("/")) {
      throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
    }

    if (!["available", "maintenance", "damaged"].includes(targetStatus)) {
      throw new HttpsError("invalid-argument", "Status alvo de equipamento inválido.");
    }

    const ref = db.collection("warehouse_equipment").doc(equipmentId);
    return db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Equipamento não encontrado.");
      }
      const eqData = snap.data() ?? {};
      if (eqData.active_custody_id != null || eqData.status === "in_custody") {
        throw new HttpsError("failed-precondition", "Equipamento em cautela ativa não pode mudar status operacional.");
      }
      if (eqData.status === "retired") {
        throw new HttpsError("failed-precondition", "Equipamento aposentado/baixado não pode mudar de status.");
      }

      let resultingCondition = eqData.condition || "good";
      if (data.condition !== undefined && data.condition !== null) {
        const condStr = String(data.condition).trim();
        if (!["new", "good", "fair", "damaged"].includes(condStr)) {
          throw new HttpsError("invalid-argument", "Condição física informada inválida.");
        }
        resultingCondition = condStr;
      }

      if (targetStatus === "available" && resultingCondition === "damaged") {
        throw new HttpsError(
          "invalid-argument",
          "Equipamento com condição danificado não pode ser marcado como disponível.",
        );
      }
      if (targetStatus === "damaged" && resultingCondition !== "damaged") {
        resultingCondition = "damaged";
      }

      const nowTimestamp = admin.firestore.Timestamp.now();
      const updates: Record<string, any> = {
        status: targetStatus,
        condition: resultingCondition,
        updated_at: nowTimestamp,
      };
      if (data.notes !== undefined) {
        updates.notes = optionalString(data, "notes");
      }

      transaction.update(ref, updates);

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_equipment_status_changed",
        entity_type: "warehouse_equipment",
        entity_id: equipmentId,
        summary: `Status de equipamento alterado para ${targetStatus} (condição: ${resultingCondition})`,
        actor: caller,
        metadata: {
          previous_status: eqData.status,
          target_status: targetStatus,
          condition: resultingCondition,
          notes: data.notes || null,
        },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return {
        id: equipmentId,
        status: targetStatus,
        condition: resultingCondition,
      };
    });
  });

  const adminWarehouseOpenCustody = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    const data = (request.data ?? {}) as Record<string, any>;
    return executeOpenCustody(db, caller, {
      equipment_id: String(data.equipment_id || "").trim(),
      borrower_ra: String(data.borrower_ra || "").trim(),
      borrower_name: String(data.borrower_name || "").trim(),
      condition_at_dispatch: data.condition_at_dispatch || "good",
      purpose: data.purpose || "daily_duty",
      expected_return_at: data.expected_return_at ? new Date(data.expected_return_at) : null,
      linked_dog_id: data.linked_dog_id ? String(data.linked_dog_id) : null,
      linked_dog_name: data.linked_dog_name ? String(data.linked_dog_name) : null,
      linked_vehicle_prefix: data.linked_vehicle_prefix ? String(data.linked_vehicle_prefix) : null,
      dispatch_notes: data.dispatch_notes ? String(data.dispatch_notes) : null,
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
    });
  });

  const adminWarehouseReturnCustody = onCall({ region }, async (request) => {
    let caller: CallerIdentity;
    try {
      caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "create");
    } catch {
      caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "edit");
    }
    const data = (request.data ?? {}) as Record<string, any>;
    return executeReturnCustody(db, caller, {
      custody_id: String(data.custody_id || "").trim(),
      // F04 (NEON-FINDINGS-CLOSURE-R1): sem coercao silenciosa para "good".
      // Ausente/invalido e rejeitado fail-closed por executeReturnCustody (zero mutacoes).
      condition_at_return: data.condition_at_return,
      return_notes: data.return_notes ? String(data.return_notes) : null,
      target_equipment_status: data.target_equipment_status,
      return_location_id: data.return_location_id ? String(data.return_location_id) : null,
      return_location_name: data.return_location_name ? String(data.return_location_name) : null,
      idempotency_key: data.idempotency_key ? String(data.idempotency_key) : null,
    });
  });

  const adminWarehouseCancelCustody = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "edit");
    const data = (request.data ?? {}) as Record<string, any>;
    const custodyId = String(data.custody_id || "").trim();
    const reason = String(data.reason || "").trim();
    const idempotencyKey = data.idempotency_key ? String(data.idempotency_key) : null;
    return executeCancelCustody(db, caller, {
      custody_id: custodyId,
      reason,
      idempotency_key: idempotencyKey,
    });
  });

  const adminWarehouseOpenInventorySession = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    return executeStartInventorySession(db, caller, {
      title: String(data.title || "Inventário Físico").trim(),
      scope_type: data.scope_type || "full_warehouse",
      scope_ref_id: data.scope_ref_id ? String(data.scope_ref_id) : null,
      scope_label: data.scope_label ? String(data.scope_label) : null,
      notes: data.notes ? String(data.notes) : null,
    });
  });

  const adminWarehouseRecordInventoryCount = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    const sessionId = requiredString(data, "session_id");
    const countId = requiredString(data, "count_id");
    const countedQuantity = optionalNumberValue(data.counted_quantity);
    const discrepancyReason = optionalString(data, "discrepancy_reason");

    if (countedQuantity === null || countedQuantity < 0) {
      throw new HttpsError("invalid-argument", "Quantidade contada deve ser um número maior ou igual a zero.");
    }

    return db.runTransaction(async (transaction) => {
      const sessionRef = db.collection("inventory_sessions").doc(sessionId);
      const countRef = sessionRef.collection("counts").doc(countId);
      const sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists) throw new HttpsError("not-found", "Sessão não encontrada.");
      const sessionData = sessionSnap.data() ?? {};
      if (!["in_progress", "reconciling"].includes(sessionData.status)) {
        throw new HttpsError("failed-precondition", "Sessão não está aberta para contagem.");
      }
      if (sessionData.snapshot_status && sessionData.snapshot_status !== "complete") {
        throw new HttpsError(
          "failed-precondition",
          "O snapshot do inventário não está pronto para contagem física.",
        );
      }
      const countSnap = await transaction.get(countRef);
      if (!countSnap.exists) throw new HttpsError("not-found", "Registro de contagem não encontrado.");
      const countData = countSnap.data() ?? {};
      const expectedQuantity = Number(countData.expected_quantity ?? 0);
      const diff = Math.round((countedQuantity - expectedQuantity) * 1000) / 1000;
      const trimmedReason = discrepancyReason ? discrepancyReason.trim() : null;
      if (diff !== 0 && !trimmedReason) {
        throw new HttpsError("invalid-argument", "Justificativa obrigatória para divergência.");
      }
      const nowTimestamp = admin.firestore.Timestamp.now();
      transaction.update(countRef, {
        counted_quantity: countedQuantity,
        discrepancy: diff,
        discrepancy_reason: diff !== 0 ? trimmedReason : (trimmedReason || null),
        counted_by_ra: caller.ra,
        counted_by_name: caller.name,
        counted_at: nowTimestamp,
      });

      const isFirstCount = countData.counted_quantity === null || countData.counted_quantity === undefined;
      if (isFirstCount) {
        transaction.update(sessionRef, {
          counted_items: admin.firestore.FieldValue.increment(1),
          updated_at: nowTimestamp,
        });
      }

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_inventory_count_recorded",
        entity_type: "inventory_count",
        entity_id: countId,
        summary: `Contagem física registrada para posição ${countId} na sessão ${sessionId}: ${countedQuantity} (divergência: ${diff})`,
        actor: caller,
        metadata: {
          session_id: sessionId,
          count_id: countId,
          expected_quantity: expectedQuantity,
          counted_quantity: countedQuantity,
          discrepancy: diff,
        },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { count_id: countId, discrepancy: diff, recorded: true };
    });
  });

  const adminWarehouseAddUnexpectedCount = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    const sessionId = requiredString(data, "session_id");
    const materialId = requiredString(data, "material_id");
    const batchId = requiredString(data, "batch_id");
    const locationId = requiredString(data, "location_id");
    const countedQuantity = optionalNumberValue(data.counted_quantity);
    const discrepancyReason = requiredString(data, "discrepancy_reason");

    if (countedQuantity === null || countedQuantity <= 0) {
      throw new HttpsError("invalid-argument", "Quantidade contada inesperada deve ser maior que zero.");
    }

    return db.runTransaction(async (transaction) => {
      const sessionRef = db.collection("inventory_sessions").doc(sessionId);
      const sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists) throw new HttpsError("not-found", "Sessão não encontrada.");
      const sessionData = sessionSnap.data() ?? {};
      if (sessionData.status !== "in_progress") {
        throw new HttpsError("failed-precondition", "Inclusão de item inesperado permitida apenas durante contagem em andamento.");
      }

      const materialRef = db.collection("inventory_items").doc(materialId);
      const batchRef = db.collection("warehouse_batches").doc(batchId);
      const [matSnap, batchSnap] = await Promise.all([
        transaction.get(materialRef),
        transaction.get(batchRef),
      ]);

      if (!matSnap.exists) throw new HttpsError("not-found", "Material não encontrado no catálogo.");
      if (!batchSnap.exists) throw new HttpsError("not-found", "Lote não encontrado no catálogo.");

      const matData = matSnap.data() ?? {};
      const batchData = batchSnap.data() ?? {};

      if (batchData.material_id !== materialId) {
        throw new HttpsError("failed-precondition", "Lote informado não pertence ao material.");
      }

      const posId = derivePositionDocId(materialId, batchId, locationId);
      const countRef = sessionRef.collection("counts").doc(posId);
      const countSnap = await transaction.get(countRef);

      // F06: resolve o nome legivel do local a partir de posicoes fisicas existentes
      // (fonte canonica `warehouse_positions`); fallback conservador ao id.
      const locationPosSnap = await transaction.get(
        db.collection("warehouse_positions").where("location_id", "==", locationId).limit(1),
      );
      const resolvedLocationName = locationPosSnap.docs
        .map((d) => stringValue(d.data()?.location_name))
        .find((n): n is string => typeof n === "string" && n.length > 0) ?? locationId;

      if (countSnap.exists) {
        throw new HttpsError("already-exists", "Já existe uma contagem cadastrada para esta posição nesta sessão.");
      }

      const nowTimestamp = admin.firestore.Timestamp.now();
      transaction.set(countRef, {
        id: posId,
        session_id: sessionId,
        material_id: materialId,
        material_name: matData.name || "Material",
        batch_id: batchId,
        lot_number: batchData.lot_number || "",
        location_id: locationId,
        location_name: resolvedLocationName,
        stock_position_id: posId,
        unit: matData.unit || "unidade",
        expected_quantity: 0,
        counted_quantity: countedQuantity,
        discrepancy: countedQuantity,
        discrepancy_reason: discrepancyReason.trim(),
        counted_by_ra: caller.ra,
        counted_by_name: caller.name,
        counted_at: nowTimestamp,
        unexpected: true,
      });

      transaction.update(sessionRef, {
        total_items: admin.firestore.FieldValue.increment(1),
        counted_items: admin.firestore.FieldValue.increment(1),
        updated_at: nowTimestamp,
      });

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_inventory_unexpected_item_added",
        entity_type: "inventory_count",
        entity_id: posId,
        summary: `Item inesperado adicionado ao inventário ${sessionId}: ${matData.name} (lote ${batchData.lot_number}) no local ${locationId} com quantidade ${countedQuantity}`,
        actor: caller,
        metadata: {
          session_id: sessionId,
          count_id: posId,
          material_id: materialId,
          batch_id: batchId,
          location_id: locationId,
          counted_quantity: countedQuantity,
          discrepancy_reason: discrepancyReason.trim(),
        },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { count_id: posId, discrepancy: countedQuantity, recorded: true };
    });
  });

  const adminWarehouseStartReconciliation = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    const sessionId = requiredString(data, "session_id");

    return db.runTransaction(async (transaction) => {
      const sessionRef = db.collection("inventory_sessions").doc(sessionId);
      const sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists) throw new HttpsError("not-found", "Sessão não encontrada.");
      const sessionData = sessionSnap.data() ?? {};
      if (sessionData.status !== "in_progress") {
        throw new HttpsError("failed-precondition", "Sessão não está em andamento para iniciar reconciliação.");
      }
      if (sessionData.snapshot_status && sessionData.snapshot_status !== "complete") {
        throw new HttpsError(
          "failed-precondition",
          "O snapshot do inventário não foi concluído com sucesso.",
        );
      }

      const countsSnap = await transaction.get(sessionRef.collection("counts"));
      for (const countDoc of countsSnap.docs) {
        const c = countDoc.data() ?? {};
        if (c.counted_quantity === null || c.counted_quantity === undefined) {
          throw new HttpsError("failed-precondition", "Todas as posições devem ser contadas antes de iniciar a reconciliação.");
        }
        const diff = Math.round((Number(c.counted_quantity) - Number(c.expected_quantity ?? 0)) * 1000) / 1000;
        if (diff !== 0 && !String(c.discrepancy_reason || "").trim()) {
          throw new HttpsError("failed-precondition", `Divergência não justificada na posição ${countDoc.id}.`);
        }
      }

      const nowTimestamp = admin.firestore.Timestamp.now();
      transaction.update(sessionRef, {
        status: "reconciling",
        updated_at: nowTimestamp,
      });

      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_inventory_reconciliation_started",
        entity_type: "inventory_session",
        entity_id: sessionId,
        summary: `Reconciliação de inventário iniciada para sessão ${sessionId} por ${caller.name}`,
        actor: caller,
        metadata: { session_id: sessionId },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });

      return { session_id: sessionId, status: "reconciling" };
    });
  });

  const adminWarehouseHomologateInventorySession = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    const sessionId = requiredString(data, "session_id");
    const idempotencyKey = optionalString(data, "idempotency_key");
    const homologationNotes = optionalString(data, "notes");
    return executeHomologateInventorySession(db, caller, {
      sessionId,
      idempotencyKey,
      notes: homologationNotes,
    });
  });

  const adminWarehouseCancelInventorySession = onCall({ region }, async (request) => {
    const caller = await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
    const data = (request.data ?? {}) as Record<string, any>;
    const sessionId = requiredString(data, "session_id");
    const reason = requiredString(data, "reason");
    return db.runTransaction(async (transaction) => {
      const sessionRef = db.collection("inventory_sessions").doc(sessionId);
      const lockRef = db.collection("warehouse_control").doc("inventory_lock");
      const snap = await transaction.get(sessionRef);
      const lock = await transaction.get(lockRef);
      if (!snap.exists) throw new HttpsError("not-found", "Sessão de inventário não encontrada.");
      const sessionData = snap.data() ?? {};
      if (sessionData.status === "homologated" || sessionData.status === "cancelled") {
        throw new HttpsError("failed-precondition", `Sessão de inventário já encerrada (${sessionData.status}).`);
      }
      if (!["in_progress", "reconciling"].includes(sessionData.status) || lock.data()?.active_session_id !== sessionId) {
        throw new HttpsError("failed-precondition", "Sessão não está ativa.");
      }
      const nowTimestamp = admin.firestore.Timestamp.now();
      transaction.update(sessionRef, {
        status: "cancelled",
        closed_by_ra: caller.ra,
        closed_by_name: caller.name,
        closed_at: nowTimestamp,
        notes: reason,
        updated_at: nowTimestamp,
      });
      transaction.set(lockRef, { active_session_id: null, updated_at: nowTimestamp });
      transaction.set(db.collection("auditLogs").doc(), {
        action: "warehouse_inventory_cancelled",
        entity_type: "inventory_session",
        entity_id: sessionId,
        summary: `Inventário cancelado: ${sessionId}. Motivo: ${reason}`,
        actor: caller,
        metadata: { session_id: sessionId, reason },
        source: "functions",
        performed_at: nowTimestamp,
        createdAt: nowTimestamp,
      });
      return { session_id: sessionId, cancelled: true };
    });
  });

  const adminWarehouseGetOverview = onCall({ region }, async (request) => {
    await requireAccessPermission(request.auth as CallerAuth, "inventory", "view");
    let canAudit = false;
    try {
      await requireAccessPermission(request.auth as CallerAuth, "inventory", "audit");
      canAudit = true;
    } catch (err: unknown) {
      if ((err as { code?: string })?.code === "permission-denied") {
        canAudit = false;
      } else {
        throw err;
      }
    }
    const now = new Date();
    const todayString = formatBusinessDate(now);
    return getWarehouseOverviewData(db, now, todayString, { includeAuditSession: canAudit });
  });

  return {
    adminWarehouseUpsertMaterial,
    adminWarehouseArchiveMaterial,
    adminWarehouseEntry,
    adminWarehouseConsumption,
    adminWarehouseTransfer,
    adminWarehouseLossDisposal,
    adminWarehouseUpsertEquipment,
    adminWarehouseRetireEquipment,
    adminWarehouseUpdateEquipmentStatus,
    adminWarehouseOpenCustody,
    adminWarehouseReturnCustody,
    adminWarehouseCancelCustody,
    adminWarehouseOpenInventorySession,
    adminWarehouseRecordInventoryCount,
    adminWarehouseAddUnexpectedCount,
    adminWarehouseStartReconciliation,
    adminWarehouseHomologateInventorySession,
    adminWarehouseCancelInventorySession,
    adminWarehouseGetOverview,
  };
}

function daysDifferenceServer(targetDate?: string | null, baseDate?: string | null): number {
  if (!targetDate || typeof targetDate !== "string" || !baseDate || typeof baseDate !== "string") {
    return 99999;
  }
  const [y1, m1, d1] = targetDate.split("-").map(Number);
  const [y2, m2, d2] = baseDate.split("-").map(Number);
  if (!y1 || !m1 || !d1 || !y2 || !m2 || !d2) return 99999;
  return Math.round((Date.UTC(y1, m1 - 1, d1) - Date.UTC(y2, m2 - 1, d2)) / 86400000);
}

export async function getWarehouseOverviewData(
  db: FirebaseFirestore.Firestore,
  now: Date,
  todayString: string,
  options?: { includeAuditSession?: boolean },
) {
  const includeAuditSession = options?.includeAuditSession ?? true;

  const materialsSnap = await db.collection("inventory_items").where("active", "==", true).get();
  const materials = materialsSnap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }));

  const batchesSnap = await db.collection("warehouse_batches").where("current_quantity", ">", 0).get();
  const batches = batchesSnap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }));

  const equipmentSnap = await db.collection("warehouse_equipment").where("active", "==", true).get();
  const equipment = equipmentSnap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }));

  const custodiesSnap = await db.collection("warehouse_custodies").where("status", "==", "active").get();
  const custodies = custodiesSnap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }));

  let sessions: any[] = [];
  if (includeAuditSession) {
    const sessionsSnap = await db.collection("inventory_sessions").where("status", "in", ["in_progress", "reconciling"]).get();
    sessions = sessionsSnap.docs.map((d) => ({ id: d.id, ...(d.data() as any) }));
  }

  let movementsSnap: any;
  try {
    movementsSnap = await (db.collection("inventory_movements") as any).orderBy("performed_at", "desc").limit(10).get();
  } catch {
    movementsSnap = await db.collection("inventory_movements").limit(10).get();
  }
  const movements = movementsSnap.docs.map((d: any) => ({ id: d.id, ...(d.data() as any) }));

  const batchesByMaterial = new Map<string, any[]>();
  for (const b of batches) {
    const list = batchesByMaterial.get(b.material_id) || [];
    list.push(b);
    batchesByMaterial.set(b.material_id, list);
  }

  let outOfStockCount = 0;
  let lowStockCount = 0;
  let expiredBatchesWithStockCount = 0;
  let expiringSoonBatchesWithStockCount = 0;

  const alerts: any[] = [];

  for (const m of materials) {
    const mBatches = batchesByMaterial.get(m.id) || [];
    const available = mBatches.reduce((acc, b) => {
      const isEligible =
        b.status !== "blocked" &&
        b.status !== "depleted" &&
        Number(b.current_quantity || 0) > 0 &&
        (!b.expiration_date || !isBatchExpiredServer(b.expiration_date, todayString));
      return isEligible ? acc + Math.max(0, Number(b.current_quantity || 0)) : acc;
    }, 0);

    const minQty = Number(m.minimum_quantity ?? 0);
    if (available <= 0) {
      outOfStockCount++;
      alerts.push({
        id: `alert-out-of-stock-${m.id}`,
        kind: "out_of_stock",
        severity: "critical",
        title: `Material sem estoque disponível: ${m.name}`,
        description: `Saldo disponível é 0 ${m.unit || "un"} (Estoque físico ON-HAND: ${m.current_quantity ?? 0} ${m.unit || "un"}).`,
        entity_type: "material",
        entity_id: m.id,
        href: `/warehouse/materials/${m.id}`,
      });
    } else if (available <= minQty) {
      lowStockCount++;
      alerts.push({
        id: `alert-low-stock-${m.id}`,
        kind: "low_stock",
        severity: "warning",
        title: `Estoque baixo: ${m.name}`,
        description: `Disponível: ${available} ${m.unit || "un"} (Mínimo definido: ${minQty} ${m.unit || "un"}).`,
        entity_type: "material",
        entity_id: m.id,
        href: `/warehouse/materials/${m.id}`,
      });
    }
  }

  for (const b of batches) {
    const currentQty = Number(b.current_quantity || 0);
    if (currentQty <= 0) continue;

    if (isBatchExpiredServer(b.expiration_date, todayString)) {
      expiredBatchesWithStockCount++;
      alerts.push({
        id: `alert-expired-batch-${b.id}`,
        kind: "expired_batch_with_on_hand",
        severity: "critical",
        title: `Lote vencido em estoque físico: Lote ${b.lot_number}`,
        description: `${b.material_name || "Material"} - ${currentQty} unidades vencidas em ${b.expiration_date}.`,
        entity_type: "batch",
        entity_id: b.id,
        href: `/warehouse/batches`,
        occurred_or_due_at: b.expiration_date,
      });
    } else {
      const diff = daysDifferenceServer(b.expiration_date, todayString);
      if (diff >= 0 && diff <= 30) {
        expiringSoonBatchesWithStockCount++;
        alerts.push({
          id: `alert-expiring-soon-${b.id}`,
          kind: "expiring_soon",
          severity: "warning",
          title: `Lote próximo do vencimento: Lote ${b.lot_number}`,
          description: `${b.material_name || "Material"} - Vence em ${b.expiration_date} (${currentQty} unidades restantes).`,
          entity_type: "batch",
          entity_id: b.id,
          href: `/warehouse/batches`,
          occurred_or_due_at: b.expiration_date,
        });
      }
    }
  }

  const activeEquipment = equipment.filter((e) => e.status !== "retired");
  const availableEq = activeEquipment.filter((e) => e.status === "available").length;
  const inCustodyEq = activeEquipment.filter((e) => e.status === "in_custody").length;
  const maintenanceEq = activeEquipment.filter((e) => e.status === "maintenance").length;
  const damagedEq = activeEquipment.filter((e) => e.status === "damaged").length;

  for (const e of activeEquipment) {
    if (e.status === "damaged") {
      alerts.push({
        id: `alert-damaged-eq-${e.id}`,
        kind: "damaged_equipment",
        severity: "warning",
        title: `Equipamento danificado: ${e.name} (${e.identifier_code})`,
        description: `Equipamento registrado como danificado. Requer avaliação ou reparo.`,
        entity_type: "equipment",
        entity_id: e.id,
        href: `/warehouse/equipment/${e.id}`,
      });
    } else if (e.status === "maintenance") {
      alerts.push({
        id: `alert-maintenance-eq-${e.id}`,
        kind: "maintenance_equipment",
        severity: "warning",
        title: `Equipamento em manutenção: ${e.name} (${e.identifier_code})`,
        description: `Equipamento sob manutenção/reparo temporário.`,
        entity_type: "equipment",
        entity_id: e.id,
        href: `/warehouse/equipment/${e.id}`,
      });
    }
  }

  let overdueCustodiesCount = 0;
  for (const c of custodies) {
    let isOverdue = false;
    if (c.expected_return_at) {
      const returnTime = typeof c.expected_return_at.toDate === "function"
        ? c.expected_return_at.toDate().getTime()
        : new Date(c.expected_return_at).getTime();
      if (now.getTime() > returnTime) {
        isOverdue = true;
      }
    }

    if (isOverdue) {
      overdueCustodiesCount++;
      const returnDateStr = typeof c.expected_return_at.toDate === "function"
        ? formatBusinessDate(c.expected_return_at.toDate())
        : String(c.expected_return_at).slice(0, 10);
      alerts.push({
        id: `alert-overdue-custody-${c.id}`,
        kind: "overdue_custody",
        severity: "critical",
        title: `Cautela atrasada: ${c.equipment_name} (${c.equipment_code})`,
        description: `Policial: ${c.borrower_name} (${c.borrower_ra}) - Previsão de retorno era ${returnDateStr}.`,
        entity_type: "custody",
        entity_id: c.id,
        href: `/warehouse/custody`,
        occurred_or_due_at: returnDateStr,
      });
    }
  }

  let activeSessionSummary: any = null;
  let attentionRequired = false;

  if (includeAuditSession && sessions.length > 0) {
    const s = sessions[0];
    const snapshotStatus = s.snapshot_status || "complete";
    activeSessionSummary = {
      id: s.id,
      title: s.title,
      scope_type: s.scope_type,
      scope_ref_id: s.scope_ref_id || null,
      status: s.status,
      snapshot_status: snapshotStatus,
      opened_by_name: s.opened_by_name,
      opened_at: s.opened_at,
      total_items: Number(s.total_items ?? 0),
      counted_items: Number(s.counted_items ?? 0),
    };

    if (snapshotStatus === "failed") {
      attentionRequired = true;
      alerts.push({
        id: `alert-inv-failed-${s.id}`,
        kind: "inventory_snapshot_failed",
        severity: "critical",
        title: `Falha na montagem de inventário: ${s.title}`,
        description: `A construção do snapshot de posições falhou. A sessão requer cancelamento ou intervenção.`,
        entity_type: "inventory_session",
        entity_id: s.id,
        href: `/warehouse/inventory/${s.id}`,
      });
    } else if (snapshotStatus === "building") {
      alerts.push({
        id: `alert-inv-building-${s.id}`,
        kind: "inventory_snapshot_building",
        severity: "info",
        title: `Inventário em inicialização: ${s.title}`,
        description: `Snapshot de posições físicas sendo construído. Aguarde a finalização antes de contar.`,
        entity_type: "inventory_session",
        entity_id: s.id,
        href: `/warehouse/inventory/${s.id}`,
      });
    } else {
      alerts.push({
        id: `alert-inv-active-${s.id}`,
        kind: "active_inventory",
        severity: "info",
        title: `Inventário físico em andamento: ${s.title}`,
        description: `Escopo: ${s.scope_type}. Aberto por ${s.opened_by_name}.`,
        entity_type: "inventory_session",
        entity_id: s.id,
        href: `/warehouse/inventory/${s.id}`,
      });
    }
  }

  const severityRank: Record<string, number> = { critical: 0, warning: 1, info: 2 };
  alerts.sort((a, b) => {
    const rankDiff = (severityRank[a.severity] ?? 99) - (severityRank[b.severity] ?? 99);
    if (rankDiff !== 0) return rankDiff;
    if (a.occurred_or_due_at && b.occurred_or_due_at) {
      const dateCompare = a.occurred_or_due_at.localeCompare(b.occurred_or_due_at);
      if (dateCompare !== 0) return dateCompare;
    }
    return a.title.localeCompare(b.title);
  });

  const boundedAlerts = alerts.slice(0, 20);

  let overallStatus: "normal" | "warning" | "attention" = "normal";
  if (alerts.some((a) => a.severity === "critical")) {
    overallStatus = "attention";
  } else if (alerts.some((a) => a.severity === "warning")) {
    overallStatus = "warning";
  }

  const recentMovements = movements.slice(0, 10).map((m: any) => ({
    id: m.id,
    type: m.type || "unknown",
    material_name: m.material_name || m.item_name || "Material",
    quantity: Number(m.quantity ?? 0),
    unit: m.unit || "un",
    lot_number: m.lot_number || m.lot || null,
    origin_location_name: m.origin_location_name || null,
    destination_location_name: m.destination_location_name || null,
    performed_by_name: m.performed_by_name || null,
    performed_at: m.performed_at || m.created_at || null,
  }));

  return {
    generated_at: now.toISOString(),
    overall_status: overallStatus,
    materials: {
      active_materials: materials.length,
      out_of_stock: outOfStockCount,
      low_stock: lowStockCount,
      expired_batches_with_stock: expiredBatchesWithStockCount,
      expiring_soon_batches_with_stock: expiringSoonBatchesWithStockCount,
    },
    equipment: {
      total_active: activeEquipment.length,
      available: availableEq,
      in_custody: inCustodyEq,
      maintenance: maintenanceEq,
      damaged: damagedEq,
    },
    custody: {
      active: custodies.length,
      overdue: overdueCustodiesCount,
    },
    inventory: {
      active_session: activeSessionSummary,
      attention_required: attentionRequired,
    },
    alerts: boundedAlerts,
    recent_movements: recentMovements,
  };
}
