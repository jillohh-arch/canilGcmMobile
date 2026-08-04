import * as crypto from "crypto";

export const WEIGHT_SCHEMA_VERSION = 1;

export type InternalRole = "condutor" | "admin";

export type CanonicalWeightContext =
  | "routine"
  | "clinical"
  | "pre_op"
  | "post_op";

export const VALID_WEIGHT_CONTEXTS: ReadonlySet<string> = new Set([
  "routine",
  "clinical",
  "pre_op",
  "post_op",
]);

export interface WeightCaller {
  uid: string;
  name: string;
  ra: string;
  internalRole: InternalRole;
}

export interface WeightCreatePayload {
  dogId: string;
  operationId: string;
  weightKg: number;
  measuredAt: Date;
  context?: CanonicalWeightContext;
  notes?: string;
}

export interface WeightMutationResult {
  dogId: string;
  entityId: string;
  weightKg: number;
  revision: number;
  wasNoOp: boolean;
}

export interface WeightReceipt {
  operation_id: string;
  operation_type: "create_weight";
  dog_id: string;
  entity_id: string;
  actor_uid: string;
  actor: {
    uid: string;
    name: string;
    internal_role: InternalRole;
  };
  fingerprint: string;
  result: {
    dogId: string;
    entityId: string;
    weightKg: number;
    revision: number;
  };
  processed_at: unknown;
  created_at: unknown;
}

export function sha256Hex(content: string): string {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

export function fingerprintWeightRecord(params: {
  dogId: string;
  weightKg: number;
  measuredAtIso: string;
  context?: string;
  notes?: string;
}): string {
  const normNotes = (params.notes ?? "").trim();
  const normCtx = params.context ?? "__NONE__";
  const raw = `v1:weight:${params.dogId}:${params.weightKg.toString()}:${params.measuredAtIso}:${normCtx}:${normNotes}`;
  return sha256Hex(raw);
}

export function assertPathSafeId(val: unknown, label: string): string {
  if (typeof val !== "string" || !val.trim()) {
    throw new Error(`${label} é obrigatório e deve ser texto.`);
  }
  const clean = val.trim();
  if (clean.includes("/") || clean.includes("..") || clean.length > 128) {
    throw new Error(`${label} possui formato inválido.`);
  }
  return clean;
}

export function parseWeightCreatePayload(
  raw: Record<string, unknown>,
  serverNow: Date = new Date()
): WeightCreatePayload {
  const dogId = assertPathSafeId(raw.dogId, "dogId");
  const operationId = assertPathSafeId(raw.operationId, "operationId");

  const weightRaw = raw.weightKg;
  if (typeof weightRaw !== "number" || !Number.isFinite(weightRaw)) {
    throw new Error("Peso do K9 deve ser numérico e finito.");
  }
  if (weightRaw <= 0 || weightRaw > 100) {
    throw new Error("Peso do K9 deve ser maior que zero e até 100 kg.");
  }

  const measuredAtRaw = raw.measuredAt;
  let measuredAt: Date;
  if (measuredAtRaw instanceof Date) {
    measuredAt = measuredAtRaw;
  } else if (typeof measuredAtRaw === "string" || typeof measuredAtRaw === "number") {
    measuredAt = new Date(measuredAtRaw);
  } else if (
    measuredAtRaw &&
    typeof measuredAtRaw === "object" &&
    "toDate" in measuredAtRaw &&
    typeof (measuredAtRaw as {toDate: () => Date}).toDate === "function"
  ) {
    measuredAt = (measuredAtRaw as {toDate: () => Date}).toDate();
  } else {
    throw new Error("Data da pesagem é obrigatória e deve ser válida.");
  }

  if (isNaN(measuredAt.getTime())) {
    throw new Error("Data da pesagem é inválida.");
  }

  // Política temporal canônica (assertNotFuture): instant <= serverNow (0ms tolerância)
  if (measuredAt.getTime() > serverNow.getTime()) {
    throw new Error("Data da pesagem não pode estar no futuro.");
  }

  let context: CanonicalWeightContext | undefined;
  if (raw.context !== undefined && typeof raw.context !== "string") {
    throw new Error("Contexto de pesagem deve ser texto quando informado.");
  }
  if (typeof raw.context === "string" && raw.context.trim()) {
    const contextRaw = raw.context.trim();
    if (!VALID_WEIGHT_CONTEXTS.has(contextRaw)) {
      throw new Error(
        `Contexto de pesagem inválido ('${contextRaw}'). Deve ser um de: routine, clinical, pre_op, post_op.`
      );
    }
    context = contextRaw as CanonicalWeightContext;
  }

  let notes: string | undefined;
  if (raw.notes !== undefined && typeof raw.notes !== "string") {
    throw new Error("Observações da pesagem devem ser texto quando informadas.");
  }
  if (typeof raw.notes === "string" && raw.notes.trim()) {
    notes = raw.notes.trim();
    if (notes.length > 1000) {
      throw new Error("Observações da pesagem não podem exceder 1000 caracteres.");
    }
  }

  return {
    dogId,
    operationId,
    weightKg: weightRaw,
    measuredAt,
    context,
    notes,
  };
}

export type ReceiptMatchKind = "missing" | "replay" | "idempotency-conflict";

export function matchWeightReceipt(
  receiptDoc: Record<string, unknown> | undefined,
  expectedDogId: string,
  expectedFingerprint: string
): ReceiptMatchKind {
  if (!receiptDoc) return "missing";

  const recDog = receiptDoc.dog_id ?? receiptDoc.dogId;
  const recfp = receiptDoc.fingerprint;

  if (recDog === expectedDogId && recfp === expectedFingerprint) {
    return "replay";
  }

  return "idempotency-conflict";
}
