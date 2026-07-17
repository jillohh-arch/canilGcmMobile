/**
 * Lógica pura da Agenda Preventiva (Fase 4E Gate 2 — idempotência durável).
 * Sem Firebase Admin — testável com node assert.
 */

export type JsonMap = Record<string, unknown>;

export const HEALTH_SCHEDULE_SCHEMA_VERSION = 1;

export const SCHEDULE_TYPES = new Set([
  "dose",
  "vaccination",
  "exam",
  "consultation",
  "weighing",
  "reevaluation",
  "deworming",
  "bath",
  "general",
]);

export const AUTOMATIC_SOURCE_TYPES = new Set([
  "treatment_protocol",
  "clinical_case",
  "exam_process",
  "preventive",
]);

export const MANUAL_SOURCE = "manual";

export const MAX_CANCEL_REASON_LEN = 500;
export const MAX_TITLE_LEN = 200;
export const MAX_NOTES_LEN = 2000;
export const MAX_OPERATION_ID_LEN = 128;

/**
 * Token seguro para segmento de path Firestore:
 * operations/{operationId}
 *
 * - trim (via stringValue)
 * - 1..128 chars
 * - começa com alfanumérico
 * - apenas [A-Za-z0-9._-]
 * - sem `/`, `\`, espaços ou segmentos `.` / `..`
 *
 * O ID lógico validado é usado diretamente no path (sem hash físico).
 */
export const OPERATION_ID_SAFE_PATTERN =
  /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

export type AppErrorCode =
  | "unauthenticated"
  | "permission-denied"
  | "not-found"
  | "conflict"
  | "idempotency-conflict"
  | "already-completed"
  | "already-cancelled"
  | "invalid-transition"
  | "validation"
  | "integrity"
  | "unexpected";

export type OperationType =
  | "create_manual"
  | "update_open"
  | "complete"
  | "cancel";

export function stringValue(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined;
  const text = String(value).trim();
  return text.length === 0 ? undefined : text;
}

export function normalizeOperationId(raw: unknown, required: boolean): string {
  const value = stringValue(raw);
  if (!value) {
    if (required) {
      throw logicError("validation", "operationId/idempotencyKey é obrigatório.");
    }
    return "";
  }
  if (value.length > MAX_OPERATION_ID_LEN) {
    throw logicError("validation", "operationId excede o tamanho máximo.");
  }
  if (
    value === "." ||
    value === ".." ||
    value.includes("/") ||
    value.includes("\\") ||
    !OPERATION_ID_SAFE_PATTERN.test(value)
  ) {
    throw logicError(
      "validation",
      "operationId/idempotencyKey contém caracteres inválidos para path.",
    );
  }
  return value;
}

export function logicError(code: AppErrorCode, message: string): Error {
  const err = new Error(message) as Error & {appCode: AppErrorCode};
  err.appCode = code;
  return err;
}

/** revision ausente/legado → 0; mutação bem-sucedida avança monotônico. */
export function readRevision(data: JsonMap): number {
  const r = data.revision;
  if (typeof r === "number" && Number.isInteger(r) && r >= 0) return r;
  if (typeof r === "string" && r.trim() !== "") {
    const n = Number(r.trim());
    if (Number.isInteger(n) && n >= 0) return n;
  }
  return 0;
}

export function nextRevision(current: number): number {
  return current + 1;
}

export function initialRevision(): number {
  return 1;
}

export function parseExpectedRevision(raw: unknown): number {
  if (typeof raw === "number" && Number.isInteger(raw) && raw >= 0) return raw;
  if (typeof raw === "string" && raw.trim() !== "") {
    const n = Number(raw.trim());
    if (Number.isInteger(n) && n >= 0) return n;
  }
  throw logicError("validation", "expectedRevision inválida.");
}

export function assertScheduleType(value: unknown): string {
  const t = stringValue(value);
  if (!t || !SCHEDULE_TYPES.has(t)) {
    throw logicError("validation", "scheduleType inválido.");
  }
  return t;
}

export function assertTimezone(value: unknown): string {
  const tz = stringValue(value);
  if (!tz) throw logicError("validation", "timezone é obrigatório.");
  if (!/^[A-Za-z0-9_+\-\/]+$/.test(tz) || tz.length > 64) {
    throw logicError("validation", "timezone inválido.");
  }
  return tz;
}

export function assertTitle(value: unknown): string {
  const title = stringValue(value);
  if (!title) throw logicError("validation", "title é obrigatório.");
  if (title.length > MAX_TITLE_LEN) {
    throw logicError("validation", "title excede o tamanho máximo.");
  }
  return title;
}

export function assertCancelReason(value: unknown): string {
  const reason = stringValue(value);
  if (!reason) throw logicError("validation", "cancelReason é obrigatório.");
  if (reason.length > MAX_CANCEL_REASON_LEN) {
    throw logicError("validation", "cancelReason excede o tamanho máximo.");
  }
  return reason;
}

export function optionalNotes(value: unknown): string | undefined {
  if (value === null || value === undefined || String(value).trim() === "") {
    return undefined;
  }
  const notes = String(value).trim();
  if (notes.length > MAX_NOTES_LEN) {
    throw logicError("validation", "notes excede o tamanho máximo.");
  }
  return notes;
}

export function isAutomaticSource(sourceType: unknown): boolean {
  const s = stringValue(sourceType);
  return s !== undefined && AUTOMATIC_SOURCE_TYPES.has(s);
}

export function isManualSource(sourceType: unknown): boolean {
  return stringValue(sourceType) === MANUAL_SOURCE;
}

export function deterministicManualScheduleId(hashHex: string): string {
  return `m_${hashHex.slice(0, 28)}`;
}

export function createIdempotencyMaterial(
  actorUid: string,
  dogId: string,
  operationId: string,
): string {
  return `${actorUid}|${dogId}|create_manual|${operationId}`;
}

/** Representação canônica determinística (JSON estável por chaves ordenadas). */
export function stableStringify(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "number" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map((v) => stableStringify(v)).join(",")}]`;
  }
  if (typeof value === "object") {
    const obj = value as JsonMap;
    const keys = Object.keys(obj).sort();
    return `{${keys
      .map((k) => `${JSON.stringify(k)}:${stableStringify(obj[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(String(value));
}

export function fingerprintCreateIntent(intent: {
  dogId: string;
  scheduleType: string;
  title: string;
  scheduledForIso: string;
  dueUntilIso: string | null;
  timezone: string;
  notes: string | null;
}): string {
  return stableStringify({
    dogId: intent.dogId,
    scheduleType: intent.scheduleType,
    title: intent.title,
    scheduledFor: intent.scheduledForIso,
    dueUntil: intent.dueUntilIso,
    timezone: intent.timezone,
    notes: intent.notes,
  });
}

export function fingerprintUpdatePatch(patch: UpdatePatch): string {
  const body: JsonMap = {};
  if (patch.title !== undefined) body.title = patch.title;
  if (patch.scheduledFor !== undefined) {
    body.scheduledFor = patch.scheduledFor.toISOString();
  }
  if (patch.dueUntil !== undefined) {
    body.dueUntil =
      patch.dueUntil === null ? null : patch.dueUntil.toISOString();
  }
  if (patch.timezone !== undefined) body.timezone = patch.timezone;
  if (patch.notes !== undefined) body.notes = patch.notes;
  return stableStringify(body);
}

export function fingerprintCancel(reason: string): string {
  return stableStringify({cancelReason: reason.trim()});
}

export function fingerprintComplete(): string {
  return stableStringify({op: "complete"});
}

/**
 * Identidade lógica da operação remota (escopo dogId+scheduleId no path):
 *   actor_uid + operation_type + operationId
 *
 * Replay só quando receipt existente bate em TODOS:
 *   stored.actor_uid == current actor
 *   stored.operation_type == requested type
 *   stored.fingerprint == current fingerprint
 *
 * Qualquer divergência → idempotency-conflict (nunca replay).
 * Ordem de validação: actor → type → fingerprint.
 */
export function matchOperationReceipt(params: {
  receiptExists: boolean;
  storedActorUid?: string;
  storedOperationType?: string;
  storedFingerprint?: string;
  actorUid: string;
  operationType: string;
  fingerprint: string;
}): "replay" | "idempotency-conflict" | "missing" {
  if (!params.receiptExists) return "missing";
  if (params.storedActorUid !== params.actorUid) {
    return "idempotency-conflict";
  }
  if (params.storedOperationType !== params.operationType) {
    return "idempotency-conflict";
  }
  if (params.storedFingerprint !== params.fingerprint) {
    return "idempotency-conflict";
  }
  return "replay";
}

export type LifecycleStatus = "open" | "completed" | "cancelled";

export function readLifecycle(data: JsonMap): LifecycleStatus {
  const s = stringValue(data.lifecycle_status);
  if (s === "open" || s === "completed" || s === "cancelled") return s;
  throw logicError("integrity", "lifecycle_status inválido ou ausente.");
}

export type CompleteDecision =
  | {kind: "mutate"}
  | {kind: "noop"}
  | {kind: "error"; code: AppErrorCode; message: string};

export function decideComplete(lifecycle: LifecycleStatus): CompleteDecision {
  if (lifecycle === "completed") return {kind: "noop"};
  if (lifecycle === "cancelled") {
    return {
      kind: "error",
      code: "invalid-transition",
      message: "Não é possível concluir item cancelado.",
    };
  }
  return {kind: "mutate"};
}

export type CancelDecision =
  | {kind: "mutate"}
  | {kind: "noop"}
  | {kind: "error"; code: AppErrorCode; message: string};

/**
 * Receipt decide replay; se não há receipt e já cancelled → already-cancelled
 * (outra operação ou legado).
 */
export function decideCancel(params: {
  lifecycle: LifecycleStatus;
  receiptMatch: "replay" | "idempotency-conflict" | "missing";
}): CancelDecision {
  if (params.receiptMatch === "replay") return {kind: "noop"};
  if (params.receiptMatch === "idempotency-conflict") {
    return {
      kind: "error",
      code: "idempotency-conflict",
      message:
        "Mesma operationId com cancelReason diferente da operação original.",
    };
  }
  if (params.lifecycle === "completed") {
    return {
      kind: "error",
      code: "invalid-transition",
      message: "Não é possível cancelar item concluído.",
    };
  }
  if (params.lifecycle === "cancelled") {
    return {
      kind: "error",
      code: "already-cancelled",
      message:
        "Item já cancelado por outra operação; cancel_reason não pode ser substituído.",
    };
  }
  return {kind: "mutate"};
}

export type UpdateDecision =
  | {kind: "mutate"}
  | {kind: "noop"}
  | {kind: "error"; code: AppErrorCode; message: string};

/**
 * Receipt tem prioridade sobre revision (retry tardio após outra op).
 * Sem receipt: exige revision + open + manual.
 */
export function decideUpdateOpen(params: {
  lifecycle: LifecycleStatus;
  sourceType: unknown;
  currentRevision: number;
  expectedRevision: number;
  receiptMatch: "replay" | "idempotency-conflict" | "missing";
}): UpdateDecision {
  if (params.receiptMatch === "replay") return {kind: "noop"};
  if (params.receiptMatch === "idempotency-conflict") {
    return {
      kind: "error",
      code: "idempotency-conflict",
      message: "Mesma operationId com patch diferente da operação original.",
    };
  }
  if (params.currentRevision !== params.expectedRevision) {
    return {
      kind: "error",
      code: "conflict",
      message: "Revisão stale: o item foi alterado desde a leitura.",
    };
  }
  if (params.lifecycle !== "open") {
    if (params.lifecycle === "completed") {
      return {
        kind: "error",
        code: "already-completed",
        message: "Somente itens open podem ser editados.",
      };
    }
    if (params.lifecycle === "cancelled") {
      return {
        kind: "error",
        code: "already-cancelled",
        message: "Somente itens open podem ser editados.",
      };
    }
  }
  if (!isManualSource(params.sourceType)) {
    return {
      kind: "error",
      code: "permission-denied",
      message: "Itens automáticos não podem ser editados por este callable.",
    };
  }
  return {kind: "mutate"};
}

export type CreateDecision =
  | {kind: "mutate"}
  | {kind: "noop"}
  | {kind: "error"; code: AppErrorCode; message: string};

/**
 * Create: isolamento por id determinístico (uid|dogId|create_manual|key).
 * Se o doc já existe, só o fingerprint da intenção decide replay vs conflict.
 */
export function decideCreateManual(params: {
  docExists: boolean;
  storedFingerprint: string | undefined;
  requestFingerprint: string;
}): CreateDecision {
  if (!params.docExists) return {kind: "mutate"};
  if (!params.storedFingerprint) {
    return {
      kind: "error",
      code: "conflict",
      message: "Documento de criação já existe sem fingerprint compatível.",
    };
  }
  if (params.storedFingerprint === params.requestFingerprint) {
    return {kind: "noop"};
  }
  return {
    kind: "error",
    code: "idempotency-conflict",
    message:
      "Mesma idempotencyKey com intenção diferente da criação original.",
  };
}

export function recordedByPayload(caller: {
  uid: string;
  name: string;
  ra: string;
}, isAdmin: boolean): JsonMap {
  return {
    uid: caller.uid,
    name: caller.name || caller.ra || caller.uid,
    internal_role: isAdmin ? "admin" : "condutor",
  };
}

export type UpdatePatch = {
  title?: string;
  scheduledFor?: Date;
  dueUntil?: Date | null;
  timezone?: string;
  notes?: string | null;
};

export function parseUpdatePatch(data: JsonMap): UpdatePatch {
  const patch: UpdatePatch = {};
  let any = false;
  if (data.title !== undefined) {
    patch.title = assertTitle(data.title);
    any = true;
  }
  if (data.scheduledFor !== undefined || data.scheduled_for !== undefined) {
    const raw = data.scheduledFor ?? data.scheduled_for;
    const d = new Date(String(raw ?? ""));
    if (Number.isNaN(d.getTime())) {
      throw logicError("validation", "scheduledFor inválido.");
    }
    patch.scheduledFor = d;
    any = true;
  }
  if (data.clearDueUntil === true || data.clear_due_until === true) {
    patch.dueUntil = null;
    any = true;
  } else if (data.dueUntil !== undefined || data.due_until !== undefined) {
    const raw = data.dueUntil ?? data.due_until;
    if (raw === null || raw === "") {
      patch.dueUntil = null;
    } else {
      const d = new Date(String(raw ?? ""));
      if (Number.isNaN(d.getTime())) {
        throw logicError("validation", "dueUntil inválido.");
      }
      patch.dueUntil = d;
    }
    any = true;
  }
  if (data.timezone !== undefined) {
    patch.timezone = assertTimezone(data.timezone);
    any = true;
  }
  if (data.clearNotes === true || data.clear_notes === true) {
    patch.notes = null;
    any = true;
  } else if (data.notes !== undefined) {
    patch.notes = optionalNotes(data.notes) ?? null;
    any = true;
  }
  if (!any) {
    throw logicError("validation", "updateOpen exige ao menos um campo mutável.");
  }
  const forbidden = [
    "source_type",
    "source_id",
    "case_id",
    "lifecycle_status",
    "recorded_by",
    "completed_at",
    "completed_by",
    "cancelled_at",
    "cancelled_by",
    "cancel_reason",
    "created_at",
    "schema_version",
    "revision",
  ];
  for (const key of forbidden) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      throw logicError(
        "validation",
        `Campo não permitido no patch: ${key}.`,
      );
    }
  }
  return patch;
}

/** Resultado canônico armazenado no operation receipt. */
export type OperationReceiptResult = {
  scheduleId: string;
  revision: number;
  lifecycleStatus: LifecycleStatus;
  wasNoOp: boolean;
};
