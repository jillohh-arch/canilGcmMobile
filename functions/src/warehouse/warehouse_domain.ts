/**
 * K9 Ops — F60 Almoxarifado Backend Domain Contracts & Logic
 * Location: canil-gcm/functions/src/warehouse/warehouse_domain.ts
 */

import { HttpsError } from "firebase-functions/v2/https";

export const CANONICAL_BUSINESS_TIMEZONE = "America/Sao_Paulo" as const;

export type StockMovementType =
  | "entry"
  | "consumption"
  | "transfer"
  | "inventory_adjustment"
  | "loss"
  | "disposal";

export interface StockPositionDoc {
  id: string;
  material_id: string;
  batch_id: string;
  lot_number: string;
  location_id: string;
  location_name: string;
  quantity: number;
  unit: string;
  sub_location?: string | null;
  notes?: string | null;
  updated_at: FirebaseFirestore.Timestamp;
  schema_version: 1;
}

export interface StockBatchDoc {
  id: string;
  material_id: string;
  material_name: string;
  lot_number: string;
  initial_quantity: number;
  current_quantity: number;
  expiration_date: string; // YYYY-MM-DD
  received_at: FirebaseFirestore.Timestamp;
  status: "active" | "depleted" | "blocked";
  supplier_name?: string | null;
  invoice_reference?: string | null;
  notes?: string | null;
  created_at: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
}

export interface ConsumableMaterialDoc {
  id: string;
  name: string;
  category_id: string;
  category_name: string;
  unit: string;
  current_quantity: number; // ON-HAND physical
  minimum_quantity: number;
  active: boolean;
  description?: string | null;
  brand?: string | null;
  default_storage_location_id?: string | null;
  storage_conditions?: string | null;
  photo_url?: string | null;
  notes?: string | null;
  created_at: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
  deleted_at?: FirebaseFirestore.Timestamp | null;
  deleted_by?: string | null;
}

export interface EquipmentDoc {
  id: string;
  name: string;
  category_id: string;
  category_name: string;
  identifier_code: string;
  condition: "new" | "good" | "fair" | "damaged";
  status: "available" | "in_custody" | "maintenance" | "damaged" | "retired";
  current_location_id: string;
  current_location_name: string;
  active: boolean;
  brand?: string | null;
  model?: string | null;
  serial_number?: string | null;
  size?: string | null;
  color?: string | null;
  acquisition_date?: string | null;
  assigned_dog_id?: string | null;
  assigned_dog_name?: string | null;
  assigned_vehicle_id?: string | null;
  assigned_vehicle_prefix?: string | null;
  active_custody_id?: string | null;
  photo_url?: string | null;
  notes?: string | null;
  created_at: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
}

export interface EquipmentCustodyDoc {
  id: string;
  equipment_id: string;
  equipment_name: string;
  equipment_code: string;
  borrower_ra: string;
  borrower_name: string;
  dispatched_by_ra: string;
  dispatched_by_name: string;
  dispatched_at: FirebaseFirestore.Timestamp;
  condition_at_dispatch: "new" | "good" | "fair";
  purpose: "daily_duty" | "training" | "operation" | "permanent_assignment";
  status: "active" | "returned" | "cancelled";
  expected_return_at?: FirebaseFirestore.Timestamp | null;
  returned_at?: FirebaseFirestore.Timestamp | null;
  received_by_ra?: string | null;
  received_by_name?: string | null;
  condition_at_return?: "new" | "good" | "fair" | "damaged" | null;
  return_notes?: string | null;
  linked_dog_id?: string | null;
  linked_dog_name?: string | null;
  linked_vehicle_prefix?: string | null;
  dispatch_notes?: string | null;
  idempotency_key?: string | null;
  created_at: FirebaseFirestore.Timestamp;
}

export interface InventorySessionDoc {
  id: string;
  title: string;
  scope_type: "full_warehouse" | "by_location" | "by_category";
  scope_ref_id?: string | null;
  scope_label?: string | null;
  opened_by_ra: string;
  opened_by_name: string;
  opened_at: FirebaseFirestore.Timestamp;
  status: "draft" | "in_progress" | "reconciling" | "homologated" | "cancelled";
  closed_by_ra?: string | null;
  closed_by_name?: string | null;
  closed_at?: FirebaseFirestore.Timestamp | null;
  notes?: string | null;
  total_items?: number;
  counted_items?: number;
  discrepant_items?: number;
  created_at: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
}

export interface InventoryItemCountDoc {
  id: string;
  session_id: string;
  material_id: string;
  material_name: string;
  batch_id: string;
  lot_number: string;
  location_id: string;
  location_name: string;
  stock_position_id: string;
  unit: string;
  expected_quantity: number;
  counted_quantity: number;
  discrepancy: number;
  discrepancy_reason?: string | null;
  counted_by_ra: string;
  counted_by_name: string;
  counted_at: FirebaseFirestore.Timestamp;
}

export function formatBusinessDate(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: CANONICAL_BUSINESS_TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function isBatchExpiredServer(expirationDate: string, todayString: string): boolean {
  return todayString > expirationDate;
}

export function derivePositionDocId(materialId: string, batchId: string, locationId: string): string {
  const sanitize = (val: string) => val.trim().replace(/[^a-zA-Z0-9_-]/g, "_");
  return `pos_${sanitize(materialId)}_${sanitize(batchId)}_${sanitize(locationId)}`;
}

export function normalizeEquipmentIdentifier(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
  }
  const trimmed = raw.trim();
  if (!trimmed || trimmed.includes("/")) {
    throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
  }
  const normalized = trimmed.normalize("NFC").toLowerCase();
  if (!normalized || normalized.includes("/")) {
    throw new HttpsError("invalid-argument", "Identificador do equipamento inválido.");
  }
  return normalized;
}

export const CANONICAL_WAREHOUSE_STORAGE_BUCKET = "canil-gcm.firebasestorage.app";

export function isWarehouseEmulatorMode(): boolean {
  return (
    process.env.FUNCTIONS_EMULATOR === "true" ||
    Boolean(process.env.FIREBASE_STORAGE_EMULATOR_HOST) ||
    Boolean(process.env.STORAGE_EMULATOR_HOST) ||
    Boolean(process.env.FIREBASE_EMULATOR_HUB)
  );
}

export function isWarehouseAuthorizedBucket(bucket: string): boolean {
  if (!bucket || typeof bucket !== "string") {
    return false;
  }
  const normalized = bucket.trim().toLowerCase();

  // SECURITY: allowlist estática e exata. Nenhum bucket é aceito por derivação
  // de projectId / FIREBASE_CONFIG.storageBucket. Isso impede que um ambiente
  // configurado contra o projeto de staging (k9-ops-staging) ou contra um
  // projeto de terceiros autorize buckets fora da lista abaixo.
  const PRODUCTION_BUCKET_ALLOWLIST = [
    CANONICAL_WAREHOUSE_STORAGE_BUCKET.toLowerCase(),
    "canil-gcm.appspot.com",
  ];

  if (isWarehouseEmulatorMode()) {
    // Emulador: aceita apenas o bucket default do emulador local, sem derivação
    // a partir de variáveis de ambiente (não confia em GCLOUD_PROJECT /
    // FIREBASE_CONFIG apontando para projetos reais).
    PRODUCTION_BUCKET_ALLOWLIST.push("canil-gcm");
  }

  const allowed = new Set<string>(PRODUCTION_BUCKET_ALLOWLIST);
  return allowed.has(normalized);
}

export function validateWarehousePhotoUrl(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "URL da foto deve ser texto.");
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    throw new HttpsError("invalid-argument", "URL da foto não pode ser vazia.");
  }
  if (trimmed.length > 2048) {
    throw new HttpsError("invalid-argument", "URL da foto excede o tamanho máximo permitido.");
  }

  // Canonical Google Cloud Storage URI
  if (trimmed.startsWith("gs://")) {
    const withoutScheme = trimmed.slice("gs://".length);
    const slash = withoutScheme.indexOf("/");
    if (slash < 0) {
      throw new HttpsError(
        "invalid-argument",
        "URL da foto deve pertencer ao caminho canônico de armazenamento (inventory_items/).",
      );
    }
    const bucket = withoutScheme.slice(0, slash);
    if (!isWarehouseAuthorizedBucket(bucket)) {
      throw new HttpsError(
        "invalid-argument",
        "URL da foto deve pertencer ao bucket de armazenamento autorizado.",
      );
    }
    const path = withoutScheme.slice(slash + 1);
    if (
      !path.startsWith("inventory_items/") ||
      path.length <= "inventory_items/".length ||
      path.includes("..")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "URL da foto deve pertencer ao caminho canônico de armazenamento (inventory_items/).",
      );
    }
    return trimmed;
  }

  // HTTP / HTTPS URL
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw new HttpsError("invalid-argument", "URL da foto inválida.");
  }

  const isLocalHost = parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1";
  if (isLocalHost) {
    if (!isWarehouseEmulatorMode()) {
      throw new HttpsError(
        "invalid-argument",
        "URL da foto em localhost é permitida apenas em ambiente de emulador.",
      );
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      throw new HttpsError("invalid-argument", "URL da foto em emulador deve usar HTTP ou HTTPS.");
    }
  } else {
    if (parsed.protocol !== "https:") {
      throw new HttpsError("invalid-argument", "URL da foto deve usar HTTPS seguro.");
    }
  }

  const allowedHosts = new Set([
    "firebasestorage.googleapis.com",
    "storage.googleapis.com",
  ]);
  if (isWarehouseEmulatorMode()) {
    allowedHosts.add("localhost");
    allowedHosts.add("127.0.0.1");
  }

  if (!allowedHosts.has(parsed.hostname)) {
    throw new HttpsError(
      "invalid-argument",
      "URL da foto deve provir de um domínio autorizado do Firebase Storage.",
    );
  }

  // Extract storage bucket and object path
  const parts = parsed.pathname.split("/").filter(Boolean);
  let bucket: string | null = null;
  let objectPath: string | null = null;

  if (parsed.hostname === "storage.googleapis.com") {
    // Format: /{bucket}/{objectPath}
    if (parts.length >= 2) {
      bucket = decodeURIComponent(parts[0]);
      objectPath = decodeURIComponent(parts.slice(1).join("/"));
    }
  } else {
    // Format: /v0/b/{bucket}/o/{objectPath}
    const bucketIndex = parts.indexOf("b");
    const objectIndex = parts.indexOf("o");
    if (bucketIndex >= 0 && objectIndex > bucketIndex && parts[bucketIndex + 1]) {
      bucket = decodeURIComponent(parts[bucketIndex + 1]);
      objectPath = decodeURIComponent(parts.slice(objectIndex + 1).join("/"));
    }
  }

  if (!bucket || !isWarehouseAuthorizedBucket(bucket)) {
    throw new HttpsError(
      "invalid-argument",
      "URL da foto deve pertencer ao bucket de armazenamento autorizado.",
    );
  }

  if (
    !objectPath ||
    !objectPath.startsWith("inventory_items/") ||
    objectPath.length <= "inventory_items/".length ||
    objectPath.includes("..")
  ) {
    throw new HttpsError(
      "invalid-argument",
      "URL da foto deve pertencer ao caminho canônico de armazenamento (inventory_items/).",
    );
  }

  return trimmed;
}

export const LEGACY_RECONCILIATION_REQUIRED_MESSAGE =
  "Índices legados de equipamento exigem reconciliação antes de novos cadastros.";

export type LegacyEquipmentClassification =
  | "UNIQUE"
  | "DUPLICATE"
  | "MISSING_IDENTIFIER"
  | "INVALID";

export interface LegacyEquipmentEntry {
  equipment_id: string;
  raw_identifier?: unknown;
  normalized_identifier?: string;
  status: LegacyEquipmentClassification;
  error?: string;
}

export interface LegacyEquipmentReconciliationReport {
  total: number;
  indexable: number;
  duplicates: number;
  missing: number;
  invalid: number;
  entries: LegacyEquipmentEntry[];
  duplicatesDetail: Record<string, string[]>;
}

export function reconcileLegacyEquipmentIdentifiers(
  records: Array<{ id: string; data?: Record<string, any> | null } | Record<string, any>>,
): LegacyEquipmentReconciliationReport {
  const entries: LegacyEquipmentEntry[] = [];
  const byNormalized = new Map<string, string[]>();

  for (const item of records) {
    const rawId = item.id !== undefined ? String(item.id).trim() : "";
    const rawData = item.data !== undefined ? (item.data ?? {}) : item;
    const rawCode = rawData.identifier_code !== undefined ? rawData.identifier_code : (rawId || undefined);
    const equipmentId = rawId || (typeof rawData.id === "string" ? rawData.id.trim() : "");

    if (!equipmentId) {
      entries.push({
        equipment_id: "",
        raw_identifier: rawCode,
        status: "INVALID",
        error: "ID de equipamento ausente",
      });
      continue;
    }

    if (rawCode === undefined || rawCode === null || (typeof rawCode === "string" && !rawCode.trim())) {
      entries.push({
        equipment_id: equipmentId,
        raw_identifier: rawCode,
        status: "MISSING_IDENTIFIER",
        error: "Identificador ausente ou em branco",
      });
      continue;
    }

    let normalized: string;
    try {
      normalized = normalizeEquipmentIdentifier(rawCode);
    } catch {
      entries.push({
        equipment_id: equipmentId,
        raw_identifier: rawCode,
        status: "INVALID",
        error: "Identificador inválido para normalização",
      });
      continue;
    }

    const existingGroup = byNormalized.get(normalized);
    if (existingGroup) {
      existingGroup.push(equipmentId);
    } else {
      byNormalized.set(normalized, [equipmentId]);
    }

    entries.push({
      equipment_id: equipmentId,
      raw_identifier: rawCode,
      normalized_identifier: normalized,
      status: "UNIQUE", // revisado na segunda passada se houver colisão
    });
  }

  const duplicatesDetail: Record<string, string[]> = {};
  for (const [norm, ids] of byNormalized.entries()) {
    if (ids.length > 1) {
      duplicatesDetail[norm] = ids;
    }
  }

  for (const entry of entries) {
    if (entry.status === "UNIQUE" && entry.normalized_identifier) {
      const ids = duplicatesDetail[entry.normalized_identifier];
      if (ids && ids.length > 1) {
        entry.status = "DUPLICATE";
        entry.error = `Identificador colide com equipamentos: ${ids.filter((x) => x !== entry.equipment_id).join(", ")}`;
      }
    }
  }

  const indexable = entries.filter((e) => e.status === "UNIQUE").length;
  const duplicates = entries.filter((e) => e.status === "DUPLICATE").length;
  const missing = entries.filter((e) => e.status === "MISSING_IDENTIFIER").length;
  const invalid = entries.filter((e) => e.status === "INVALID").length;

  return {
    total: entries.length,
    indexable,
    duplicates,
    missing,
    invalid,
    entries,
    duplicatesDetail,
  };
}
