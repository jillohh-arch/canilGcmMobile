/**
 * Lógica pura — Nutrição Health v1 / Fase 5D Gate 1.
 * Sem Firebase Admin — testável com node assert.
 *
 * Contratos D1–D42 + decisões 5D-A/B/C.
 * Reutiliza helpers de path/fingerprint da Agenda quando estáveis.
 */
import * as crypto from "crypto";
import {
  logicError,
  normalizeOperationId,
  stableStringify,
  stringValue,
  type AppErrorCode,
} from "./health_schedule_logic";

export type {AppErrorCode};
export {logicError, normalizeOperationId, stableStringify, stringValue};

export const NUTRITION_SCHEMA_VERSION = 1;
export const NUTRITION_DEFAULT_TIMEZONE = "America/Sao_Paulo";

export const MEAL_PERIODS = new Set([
  "morning",
  "afternoon",
  "evening",
  "night",
  "extra",
]);

export const MEAL_ACCEPTANCES = new Set([
  "full",
  "partial",
  "refused",
  "unknown",
]);

export const SUPPLEMENT_UNITS = new Set([
  "mg",
  "g",
  "ml",
  "scoop",
  "tablet",
  "drop",
  "other",
]);

export type NutritionOperationType =
  | "create_planned_meal"
  | "create_adhoc_meal"
  | "create_supplement_log";

export type NutritionPlanStatus = "active" | "superseded" | "cancelled";

export type NutritionAppErrorCode =
  | AppErrorCode
  | "failed-precondition";

export function nutritionError(
  code: AppErrorCode | string,
  message: string,
  detailCode?: string,
): Error {
  const err = logicError(
    (code === "failed-precondition" ? "integrity" : code) as AppErrorCode,
    message,
  ) as Error & {appCode: string; detailCode?: string};
  if (detailCode) err.detailCode = detailCode;
  // Preserve original string for taxonomy mapping in Gate 2.
  if (code === "failed-precondition") {
    (err as Error & {appCode: string}).appCode = "failed-precondition";
  }
  return err;
}

// ── numbers ──────────────────────────────────────────────────────────────────

export function assertFinitePositive(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw nutritionError("validation", `${field} deve ser número finito.`);
  }
  if (value <= 0) {
    throw nutritionError("validation", `${field} deve ser maior que zero.`);
  }
  return value;
}

export function assertFiniteNonNegative(
  value: unknown,
  field: string,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw nutritionError("validation", `${field} deve ser número finito.`);
  }
  if (value < 0) {
    throw nutritionError("validation", `${field} não pode ser negativo.`);
  }
  return value;
}

// ── D42 ──────────────────────────────────────────────────────────────────────

export function assertMealQuantities(params: {
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
}): void {
  const {offeredGrams, consumedGrams, acceptance} = params;
  if (!Number.isFinite(offeredGrams) || offeredGrams <= 0) {
    throw nutritionError(
      "validation",
      "offeredGrams deve ser finito e maior que zero.",
    );
  }
  if (consumedGrams !== null) {
    if (!Number.isFinite(consumedGrams)) {
      throw nutritionError(
        "validation",
        "consumedGrams deve ser finito quando presente.",
      );
    }
    if (consumedGrams < 0 || consumedGrams > offeredGrams) {
      throw nutritionError(
        "validation",
        "consumedGrams deve satisfazer 0 <= consumed <= offered.",
      );
    }
  }

  switch (acceptance) {
  case "refused":
    if (consumedGrams !== 0) {
      throw nutritionError(
        "validation",
        "acceptance=refused exige consumedGrams == 0.",
      );
    }
    break;
  case "full":
    if (consumedGrams !== null && consumedGrams !== offeredGrams) {
      throw nutritionError(
        "validation",
        "acceptance=full exige consumed null ou == offeredGrams.",
      );
    }
    break;
  case "partial":
    if (
      consumedGrams !== null &&
        (consumedGrams <= 0 || consumedGrams >= offeredGrams)
    ) {
      throw nutritionError(
        "validation",
        "acceptance=partial exige consumed null ou 0 < consumed < offered.",
      );
    }
    break;
  case "unknown":
    // bounds gerais já validados
    break;
  default:
    throw nutritionError("validation", `acceptance inválido: ${acceptance}`);
  }
}

export function assertAcceptance(value: unknown): string {
  const a = stringValue(value);
  if (!a || !MEAL_ACCEPTANCES.has(a)) {
    throw nutritionError("validation", "acceptance inválido.");
  }
  return a;
}

export function assertMealPeriod(value: unknown): string {
  const p = stringValue(value);
  if (!p || !MEAL_PERIODS.has(p)) {
    throw nutritionError("validation", "period inválido.");
  }
  return p;
}

export function assertSupplementUnit(value: unknown): string {
  const u = stringValue(value);
  if (!u || !SUPPLEMENT_UNITS.has(u)) {
    throw nutritionError("validation", "unit inválido.");
  }
  return u;
}

// ── temporal ─────────────────────────────────────────────────────────────────

/** fedAt/administeredAt não podem ser futuros (serverNow autoridade). */
export function assertNotFuture(instant: Date, serverNow: Date, field: string): void {
  if (Number.isNaN(instant.getTime())) {
    throw nutritionError("validation", `${field} inválido.`);
  }
  if (instant.getTime() > serverNow.getTime()) {
    throw nutritionError("validation", `${field} não pode estar no futuro.`);
  }
}

/**
 * 5D-A — local_service_date = data civil de fedAt no timezone IANA do plano.
 * Usa Intl (Node 22, sem dependência nova). Não usa device TZ.
 */
export function localServiceDateFromInstant(
  instant: Date,
  timezone: string,
): string {
  const tz = stringValue(timezone);
  if (!tz) {
    throw nutritionError("validation", "timezone é obrigatório.", "missing_timezone");
  }
  try {
    // en-CA → YYYY-MM-DD
    const fmt = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const parts = fmt.formatToParts(instant);
    const y = parts.find((p) => p.type === "year")?.value;
    const m = parts.find((p) => p.type === "month")?.value;
    const d = parts.find((p) => p.type === "day")?.value;
    if (!y || !m || !d) {
      throw new Error("formatToParts incomplete");
    }
    return `${y}-${m}-${d}`;
  } catch {
    throw nutritionError(
      "validation",
      `timezone inválido ou não suportado: ${tz}`,
      "invalid_timezone",
    );
  }
}

export function assertLocalServiceDateIso(iso: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
    throw nutritionError("integrity", "localServiceDate inválida.");
  }
  return iso;
}

/**
 * Política IANA / DST (determinística, documentada):
 *
 * - **inexistente** (spring-forward gap): `integrity` /
 *   `local_scheduled_time_nonexistent` — nunca ajusta +1h silenciosamente.
 * - **ambíguo** (fall-back overlap): escolhe o instante UTC **mais cedo**
 *   (earlier / first offset).
 * - timezone inválido: `validation` / `invalid_timezone` — sem fallback UTC.
 *
 * Combina YYYY-MM-DD + HH:mm no timezone IANA → Date UTC via Intl.
 */
export function scheduledForFromLocal(
  localServiceDate: string,
  scheduledTimeHHmm: string,
  timezone: string,
): Date {
  assertLocalServiceDateIso(localServiceDate);
  const tz = stringValue(timezone);
  if (!tz) {
    throw nutritionError(
      "validation",
      "timezone é obrigatório.",
      "missing_timezone",
    );
  }
  // Probe invalid timezone early (no silent UTC fallback).
  try {
    localServiceDateFromInstant(new Date("2020-01-01T12:00:00.000Z"), tz);
  } catch {
    throw nutritionError(
      "validation",
      `timezone inválido ou não suportado: ${tz}`,
      "invalid_timezone",
    );
  }

  const tm = stringValue(scheduledTimeHHmm);
  if (!tm || !/^([01]\d|2[0-3]):([0-5]\d)$/.test(tm)) {
    throw nutritionError(
      "integrity",
      "scheduled_time do slot inválido (HH:mm).",
    );
  }
  const [ys, ms, ds] = localServiceDate.split("-").map(Number);
  const [hh, mm] = tm.split(":").map(Number);

  const matches = findUtcInstantsForLocalWall(ys, ms, ds, hh, mm, tz);
  if (matches.length === 0) {
    throw nutritionError(
      "integrity",
      `Horário local inexistente em ${tz}: ${localServiceDate} ${tm} (DST gap).`,
      "local_scheduled_time_nonexistent",
    );
  }
  // Ambiguous → earlier UTC (matches sorted ascending).
  return matches[0];
}

/**
 * Encontra instantes UTC cujo wall-clock em [timezone] é exatamente
 * year-month-day hour:minute. Ordenado ascendente.
 */
export function findUtcInstantsForLocalWall(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  timezone: string,
): Date[] {
  const center = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  const found = new Map<number, Date>();
  // Varrer ±14h em passos de 15 min e convergir cada vizinhança.
  for (let deltaMin = -14 * 60; deltaMin <= 14 * 60; deltaMin += 15) {
    let utcMs = center + deltaMin * 60 * 1000;
    for (let i = 0; i < 5; i++) {
      const local = zonedParts(new Date(utcMs), timezone);
      const asIfUtc = Date.UTC(
        local.year,
        local.month - 1,
        local.day,
        local.hour,
        local.minute,
        0,
        0,
      );
      const target = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
      const delta = target - asIfUtc;
      utcMs += delta;
      if (delta === 0) break;
    }
    const check = zonedParts(new Date(utcMs), timezone);
    if (
      check.year === year &&
      check.month === month &&
      check.day === day &&
      check.hour === hour &&
      check.minute === minute
    ) {
      const key = Math.round(utcMs / 60000) * 60000;
      if (!found.has(key)) {
        found.set(key, new Date(key));
      }
    }
  }
  return [...found.values()].sort((a, b) => a.getTime() - b.getTime());
}

function zonedParts(
  instant: Date,
  timezone: string,
): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
} {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const parts = fmt.formatToParts(instant);
  const get = (t: string) =>
    Number(parts.find((p) => p.type === t)?.value ?? NaN);
  let hour = get("hour");
  // Some engines report 24:00 as hour 24
  if (hour === 24) hour = 0;
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour,
    minute: get("minute"),
    second: get("second"),
  };
}

// ── 5D-B plan eligibility ────────────────────────────────────────────────────

export type PlanEligibility =
  | {ok: true}
  | {ok: false; code: string; message: string};

/**
 * Vigência no instante fedAt: [validFrom, validUntil)
 * status: active|superseded ok se vigência cobre; cancelled nunca;
 * superseded sem validUntil → integrity.
 */
export function evaluatePlanEligibility(params: {
  status: string;
  validFrom: Date;
  validUntil: Date | null;
  fedAt: Date;
}): PlanEligibility {
  const status = stringValue(params.status) ?? "";
  if (status === "cancelled") {
    return {
      ok: false,
      code: "nutrition_plan_cancelled",
      message: "Plano cancelado não é elegível para refeição planejada.",
    };
  }
  if (status !== "active" && status !== "superseded") {
    return {
      ok: false,
      code: "nutrition_plan_integrity",
      message: `Status de plano não suportado: ${status}`,
    };
  }
  if (status === "superseded" && params.validUntil === null) {
    return {
      ok: false,
      code: "nutrition_plan_integrity",
      message:
        "Plano superseded sem validUntil não permite validar vigência histórica.",
    };
  }
  if (params.fedAt.getTime() < params.validFrom.getTime()) {
    return {
      ok: false,
      code: "nutrition_plan_not_effective_at_fed_at",
      message: "fedAt anterior a validFrom do plano.",
    };
  }
  if (
    params.validUntil !== null &&
    params.fedAt.getTime() >= params.validUntil.getTime()
  ) {
    return {
      ok: false,
      code: "nutrition_plan_not_effective_at_fed_at",
      message: "fedAt fora da vigência (validUntil exclusivo).",
    };
  }
  return {ok: true};
}

// ── identity 5D-C ────────────────────────────────────────────────────────────

export function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

/**
 * Preimage JSON canônico (array) versionado.
 * NÃO usa Object.hash / locale / server TZ.
 */
export function mealOccurrencePreimage(params: {
  dogId: string;
  planId: string;
  plannedMealId: string;
  localServiceDate: string;
}): string {
  return stableStringify([
    "meal_occurrence_v1",
    params.dogId,
    params.planId,
    params.plannedMealId,
    params.localServiceDate,
  ]);
}

export function mealOccurrenceIdV1(params: {
  dogId: string;
  planId: string;
  plannedMealId: string;
  localServiceDate: string;
}): string {
  const hex = sha256Hex(mealOccurrencePreimage(params));
  return `mo1_${hex}`;
}

export function adhocMealLogIdV1(params: {
  actorUid: string;
  dogId: string;
  idempotencyKey: string;
}): string {
  const pre = stableStringify([
    "meal_log_adhoc_v1",
    params.actorUid,
    params.dogId,
    params.idempotencyKey,
  ]);
  return `ml1_${sha256Hex(pre)}`;
}

export function supplementLogIdV1(params: {
  actorUid: string;
  dogId: string;
  idempotencyKey: string;
}): string {
  const pre = stableStringify([
    "supplement_log_v1",
    params.actorUid,
    params.dogId,
    params.idempotencyKey,
  ]);
  return `sl1_${sha256Hex(pre)}`;
}

/**
 * ID físico do receipt (actor-scoped). operationId lógico permanece no body.
 *
 * Preimage:
 * ["nutrition_operation_receipt_v1", actorUid, operationType, operationId]
 */
export function nutritionOperationReceiptIdV1(params: {
  actorUid: string;
  operationType: NutritionOperationType;
  operationId: string;
}): string {
  const pre = stableStringify([
    "nutrition_operation_receipt_v1",
    params.actorUid,
    params.operationType,
    params.operationId,
  ]);
  return `nr1_${sha256Hex(pre)}`;
}

// ── fingerprints ─────────────────────────────────────────────────────────────

export function fingerprintPlannedMeal(intent: {
  dogId: string;
  planId: string;
  plannedMealId: string;
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
  fedAtIso: string;
  observations: string | null;
  attachmentRefs: string[];
}): string {
  return stableStringify({
    kind: "planned_meal_v1",
    dogId: intent.dogId,
    planId: intent.planId,
    plannedMealId: intent.plannedMealId,
    offeredGrams: intent.offeredGrams,
    consumedGrams: intent.consumedGrams,
    acceptance: intent.acceptance,
    fedAt: intent.fedAtIso,
    observations: intent.observations,
    attachmentRefs: [...intent.attachmentRefs].sort(),
  });
}

export function fingerprintAdhocMeal(intent: {
  dogId: string;
  period: string;
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
  fedAtIso: string;
  observations: string | null;
  attachmentRefs: string[];
}): string {
  return stableStringify({
    kind: "adhoc_meal_v1",
    dogId: intent.dogId,
    period: intent.period,
    offeredGrams: intent.offeredGrams,
    consumedGrams: intent.consumedGrams,
    acceptance: intent.acceptance,
    fedAt: intent.fedAtIso,
    observations: intent.observations,
    attachmentRefs: [...intent.attachmentRefs].sort(),
  });
}

export function fingerprintSupplement(intent: {
  dogId: string;
  supplementName: string;
  dose: number;
  unit: string;
  administeredAtIso: string;
  nutritionPlanId: string | null;
  supplementRegimenId: string | null;
  notes: string | null;
  batchNumber: string | null;
  protocolId: string | null;
}): string {
  return stableStringify({
    kind: "supplement_log_v1",
    dogId: intent.dogId,
    supplementName: intent.supplementName,
    dose: intent.dose,
    unit: intent.unit,
    administeredAt: intent.administeredAtIso,
    nutritionPlanId: intent.nutritionPlanId,
    supplementRegimenId: intent.supplementRegimenId,
    notes: intent.notes,
    batchNumber: intent.batchNumber,
    protocolId: intent.protocolId,
  });
}

/**
 * Fingerprint do MealLog **canônico materializado** (planejado).
 * Inclui campos autoritativos server-derived + execução.
 * Usado para semantic no-op / occurrence conflict — NÃO para idempotência de transporte.
 */
export function entitySemanticFingerprintPlannedMeal(entity: {
  planId: string;
  plannedMealId: string;
  mealOccurrenceId: string;
  period: string;
  scheduledForIso: string;
  prescriptionAmountAtTime: number;
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
  fedAtIso: string;
  observations: string | null;
  attachmentRefs: string[];
}): string {
  return stableStringify({
    kind: "planned_meal_entity_v1",
    plan_id: entity.planId,
    planned_meal_id: entity.plannedMealId,
    meal_occurrence_id: entity.mealOccurrenceId,
    period: entity.period,
    scheduled_for: entity.scheduledForIso,
    prescription_amount_at_time: entity.prescriptionAmountAtTime,
    offered_grams: entity.offeredGrams,
    consumed_grams: entity.consumedGrams,
    acceptance: entity.acceptance,
    fed_at: entity.fedAtIso,
    observations: entity.observations,
    attachment_refs: [...entity.attachmentRefs].sort(),
  });
}

/** Lê entity fingerprint de um documento existente (ou recompute a partir dos campos). */
export function plannedMealEntityFingerprintFromDoc(
  data: Record<string, unknown>,
): string {
  const stored = stringValue(data.entity_semantic_fingerprint);
  if (stored) return stored;

  const num = (v: unknown): number | null => {
    if (v === null || v === undefined || v === "") return null;
    if (typeof v === "number" && Number.isFinite(v)) return v;
    return null;
  };
  const instantIso = (v: unknown): string => {
    if (typeof v === "string") return new Date(v).toISOString();
    if (v instanceof Date) return v.toISOString();
    return String(v ?? "");
  };
  const attachments = Array.isArray(data.attachment_refs) ?
    (data.attachment_refs as unknown[])
        .map((x) => stringValue(x))
        .filter((x): x is string => !!x) :
    [];

  return entitySemanticFingerprintPlannedMeal({
    planId: stringValue(data.plan_id) ?? "",
    plannedMealId: stringValue(data.planned_meal_id) ?? "",
    mealOccurrenceId: stringValue(data.meal_occurrence_id) ?? "",
    period: stringValue(data.period) ?? "",
    scheduledForIso: instantIso(data.scheduled_for),
    prescriptionAmountAtTime: num(data.prescription_amount_at_time) ?? 0,
    offeredGrams: num(data.offered_grams) ?? 0,
    consumedGrams: num(data.consumed_grams),
    acceptance: stringValue(data.acceptance) ?? "",
    fedAtIso: instantIso(data.fed_at),
    observations: stringValue(data.observations) ?? null,
    attachmentRefs: attachments,
  });
}

/**
 * Decisão occurrence × documento existente.
 * Compara **entity semantic fingerprint** (estado canônico), não só client fingerprint.
 */
export function decidePlannedMealAgainstExisting(params: {
  docExists: boolean;
  existingEntityFingerprint: string | undefined;
  proposedEntityFingerprint: string;
}): CreateEntityDecision {
  if (!params.docExists) return {kind: "mutate"};
  if (!params.existingEntityFingerprint) {
    return {
      kind: "error",
      code: "conflict",
      message:
        "MealLog da occurrence existe sem fingerprint semântico recuperável.",
      detailCode: "meal_occurrence_conflict",
    };
  }
  if (params.existingEntityFingerprint === params.proposedEntityFingerprint) {
    return {kind: "noop"};
  }
  return {
    kind: "error",
    code: "conflict",
    message:
      "Conflito na mesma meal_occurrence_id: estado canônico diverge " +
      "(inclui campos autoritativos derivados).",
    detailCode: "meal_occurrence_conflict",
  };
}

// ── create decisions ─────────────────────────────────────────────────────────

export type CreateEntityDecision =
  | {kind: "mutate"}
  | {kind: "noop"}
  | {kind: "error"; code: AppErrorCode; message: string; detailCode?: string};

/**
 * Documento existente + fingerprint da criação original (campo create_fingerprint).
 */
export function decideCreateByFingerprint(params: {
  docExists: boolean;
  storedFingerprint: string | undefined;
  requestFingerprint: string;
}): CreateEntityDecision {
  if (!params.docExists) return {kind: "mutate"};
  if (!params.storedFingerprint) {
    return {
      kind: "error",
      code: "conflict",
      message: "Documento já existe sem fingerprint compatível.",
      detailCode: "meal_occurrence_conflict",
    };
  }
  if (params.storedFingerprint === params.requestFingerprint) {
    return {kind: "noop"};
  }
  return {
    kind: "error",
    code: "conflict",
    message: "Conflito: documento existente com payload diferente.",
    detailCode: "meal_occurrence_conflict",
  };
}

export type ReceiptMatch = "replay" | "idempotency-conflict" | "missing";

export function matchNutritionReceipt(params: {
  receiptExists: boolean;
  storedActorUid?: string;
  storedOperationType?: string;
  storedFingerprint?: string;
  actorUid: string;
  operationType: NutritionOperationType;
  fingerprint: string;
}): ReceiptMatch {
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

// ── command validation ───────────────────────────────────────────────────────

export type PlannedMealCommand = {
  kind: "planned";
  dogId: string;
  planId: string;
  plannedMealId: string;
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
  fedAt: Date;
  observations: string | null;
  attachmentRefs: string[];
  idempotencyKey: string;
};

export type AdhocMealCommand = {
  kind: "adhoc";
  dogId: string;
  period: string;
  offeredGrams: number;
  consumedGrams: number | null;
  acceptance: string;
  fedAt: Date;
  observations: string | null;
  attachmentRefs: string[];
  idempotencyKey: string;
};

export type SupplementCommand = {
  dogId: string;
  supplementName: string;
  dose: number;
  unit: string;
  administeredAt: Date;
  nutritionPlanId: string | null;
  supplementRegimenId: string | null;
  notes: string | null;
  batchNumber: string | null;
  protocolId: string | null;
  idempotencyKey: string;
};

/** Campos server-authority comuns a meal creates (cliente não envia). */
const FORBIDDEN_MEAL_SERVER_FIELDS = [
  "recorded_by",
  "recordedBy",
  "recorded_at",
  "recordedAt",
  "schema_version",
  "schemaVersion",
  "revision",
  "scheduled_for",
  "scheduledFor",
  "prescription_amount_at_time",
  "prescriptionAmountAtTime",
  "meal_occurrence_id",
  "mealOccurrenceId",
  "local_service_date",
  "localServiceDate",
];

export function rejectForbiddenClientFields(
  data: Record<string, unknown>,
  extra: string[] = [],
): void {
  for (const key of [...FORBIDDEN_MEAL_SERVER_FIELDS, ...extra]) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      throw nutritionError(
        "validation",
        `Campo não permitido no payload: ${key}.`,
      );
    }
  }
}

function parseOptionalNumber(raw: unknown): number | null {
  if (raw === undefined || raw === null || raw === "") return null;
  if (typeof raw !== "number") {
    throw nutritionError("validation", "consumedGrams inválido.");
  }
  return raw;
}

function parseInstant(raw: unknown, field: string): Date {
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) {
      throw nutritionError("validation", `${field} inválido.`);
    }
    return raw;
  }
  const d = new Date(String(raw ?? ""));
  if (Number.isNaN(d.getTime())) {
    throw nutritionError("validation", `${field} inválido.`);
  }
  return d;
}

function parseAttachmentRefs(raw: unknown): string[] {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw nutritionError("validation", "attachmentRefs deve ser array.");
  }
  const out: string[] = [];
  for (const item of raw) {
    const s = stringValue(item);
    if (s) out.push(s);
  }
  return out;
}

export function parsePlannedMealCommand(
  data: Record<string, unknown>,
): PlannedMealCommand {
  rejectForbiddenClientFields(data, ["period"]); // period is server-derived
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  const planId = stringValue(data.planId) ?? stringValue(data.plan_id);
  const plannedMealId =
    stringValue(data.plannedMealId) ?? stringValue(data.planned_meal_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  if (!planId) throw nutritionError("validation", "planId é obrigatório.");
  if (!plannedMealId) {
    throw nutritionError("validation", "plannedMealId é obrigatório.");
  }
  const offeredGrams = assertFinitePositive(
    data.offeredGrams ?? data.offered_grams,
    "offeredGrams",
  );
  const consumedGrams = parseOptionalNumber(
    data.consumedGrams ?? data.consumed_grams,
  );
  const acceptance = assertAcceptance(data.acceptance);
  assertMealQuantities({offeredGrams, consumedGrams, acceptance});
  const fedAt = parseInstant(data.fedAt ?? data.fed_at, "fedAt");
  const observations =
    stringValue(data.observations) ?? stringValue(data.notes) ?? null;
  const attachmentRefs = parseAttachmentRefs(
    data.attachmentRefs ?? data.attachment_refs,
  );
  const idempotencyKey = normalizeOperationId(
    data.idempotencyKey ?? data.operationId ?? data.operation_id,
    true,
  );
  return {
    kind: "planned",
    dogId,
    planId,
    plannedMealId,
    offeredGrams,
    consumedGrams,
    acceptance,
    fedAt,
    observations,
    attachmentRefs,
    idempotencyKey,
  };
}

export function parseAdhocMealCommand(
  data: Record<string, unknown>,
): AdhocMealCommand {
  rejectForbiddenClientFields(data, [
    "planId",
    "plan_id",
    "plannedMealId",
    "planned_meal_id",
  ]);
  // Ensure plan links not present even if not in forbidden list via values
  if (
    stringValue(data.planId) ||
    stringValue(data.plan_id) ||
    stringValue(data.plannedMealId) ||
    stringValue(data.planned_meal_id) ||
    stringValue(data.mealOccurrenceId) ||
    stringValue(data.meal_occurrence_id)
  ) {
    throw nutritionError(
      "validation",
      "Refeição avulsa não pode ter planId/plannedMealId/mealOccurrenceId.",
    );
  }
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  const period = assertMealPeriod(data.period);
  const offeredGrams = assertFinitePositive(
    data.offeredGrams ?? data.offered_grams,
    "offeredGrams",
  );
  const consumedGrams = parseOptionalNumber(
    data.consumedGrams ?? data.consumed_grams,
  );
  const acceptance = assertAcceptance(data.acceptance);
  assertMealQuantities({offeredGrams, consumedGrams, acceptance});
  const fedAt = parseInstant(data.fedAt ?? data.fed_at, "fedAt");
  const observations =
    stringValue(data.observations) ?? stringValue(data.notes) ?? null;
  const attachmentRefs = parseAttachmentRefs(
    data.attachmentRefs ?? data.attachment_refs,
  );
  const idempotencyKey = normalizeOperationId(
    data.idempotencyKey ?? data.operationId ?? data.operation_id,
    true,
  );
  return {
    kind: "adhoc",
    dogId,
    period,
    offeredGrams,
    consumedGrams,
    acceptance,
    fedAt,
    observations,
    attachmentRefs,
    idempotencyKey,
  };
}

export function parseSupplementCommand(
  data: Record<string, unknown>,
): SupplementCommand {
  for (const key of [
    "recorded_by",
    "recordedBy",
    "recorded_at",
    "recordedAt",
    "schema_version",
    "schemaVersion",
    "revision",
  ]) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      throw nutritionError(
        "validation",
        `Campo não permitido no payload: ${key}.`,
      );
    }
  }
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  const supplementName =
    stringValue(data.supplementName) ?? stringValue(data.supplement_name);
  if (!supplementName) {
    throw nutritionError("validation", "supplementName é obrigatório.");
  }
  // Dose must be numeric — reject strings
  const doseRaw = data.dose;
  if (typeof doseRaw === "string") {
    throw nutritionError(
      "validation",
      "dose canônica deve ser numérica (não textual).",
    );
  }
  const dose = assertFinitePositive(doseRaw, "dose");
  const unit = assertSupplementUnit(data.unit);
  const administeredAt = parseInstant(
    data.administeredAt ?? data.administered_at,
    "administeredAt",
  );
  const nutritionPlanId =
    stringValue(data.nutritionPlanId) ??
    stringValue(data.nutrition_plan_id) ??
    null;
  const supplementRegimenId =
    stringValue(data.supplementRegimenId) ??
    stringValue(data.supplement_regimen_id) ??
    null;
  // regimen id só tem identidade dentro do plano.
  if (supplementRegimenId && !nutritionPlanId) {
    throw nutritionError(
      "validation",
      "supplementRegimenId exige nutritionPlanId.",
      "supplement_regimen_requires_plan",
    );
  }
  // nutritionPlanId sem regimen: permitido (snapshot/vínculo fraco intencional).
  const notes = stringValue(data.notes) ?? null;
  const batchNumber =
    stringValue(data.batchNumber) ?? stringValue(data.batch_number) ?? null;
  const protocolId =
    stringValue(data.protocolId) ?? stringValue(data.protocol_id) ?? null;
  const idempotencyKey = normalizeOperationId(
    data.idempotencyKey ?? data.operationId ?? data.operation_id,
    true,
  );
  return {
    dogId,
    supplementName,
    dose,
    unit,
    administeredAt,
    nutritionPlanId,
    supplementRegimenId,
    notes,
    batchNumber,
    protocolId,
    idempotencyKey,
  };
}

// ── plan/slot resolution helpers (pure on maps) ──────────────────────────────

export type MealScheduleSlotData = {
  id: string;
  period: string;
  scheduledTime: string;
  targetGrams: number;
};

export type NutritionPlanData = {
  id: string;
  dogId: string;
  status: string;
  timezone: string;
  validFrom: Date;
  validUntil: Date | null;
  mealSchedule: MealScheduleSlotData[];
  supplements: Array<{id: string}>;
};

export function parsePlanFromDoc(
  planId: string,
  dogId: string,
  data: Record<string, unknown>,
): NutritionPlanData {
  const status = stringValue(data.status);
  if (!status) {
    throw nutritionError(
      "integrity",
      "Plano sem status.",
      "nutrition_plan_integrity",
    );
  }
  const timezone =
    stringValue(data.timezone) ?? NUTRITION_DEFAULT_TIMEZONE;
  const validFromRaw = data.valid_from ?? data.validFrom;
  const validFrom = parseInstant(validFromRaw, "valid_from");
  const vuRaw = data.valid_until ?? data.validUntil;
  let validUntil: Date | null = null;
  if (vuRaw !== undefined && vuRaw !== null && vuRaw !== "") {
    validUntil = parseInstant(vuRaw, "valid_until");
  }
  const scheduleRaw = data.meal_schedule ?? data.mealSchedule;
  if (!Array.isArray(scheduleRaw)) {
    throw nutritionError(
      "integrity",
      "meal_schedule ausente ou inválido.",
      "nutrition_plan_integrity",
    );
  }
  const mealSchedule: MealScheduleSlotData[] = [];
  for (const item of scheduleRaw) {
    if (!item || typeof item !== "object") {
      throw nutritionError(
        "integrity",
        "slot de meal_schedule inválido.",
        "nutrition_plan_integrity",
      );
    }
    const m = item as Record<string, unknown>;
    const id = stringValue(m.id);
    const period = stringValue(m.period);
    const scheduledTime =
      stringValue(m.scheduled_time) ?? stringValue(m.scheduledTime);
    const target = m.target_grams ?? m.targetGrams;
    if (!id || !period || !scheduledTime || typeof target !== "number") {
      throw nutritionError(
        "integrity",
        "slot incompleto no meal_schedule.",
        "nutrition_plan_integrity",
      );
    }
    mealSchedule.push({
      id,
      period,
      scheduledTime,
      targetGrams: target,
    });
  }
  const supplementsRaw = data.supplements;
  const supplements: Array<{id: string}> = [];
  if (Array.isArray(supplementsRaw)) {
    for (const s of supplementsRaw) {
      if (s && typeof s === "object") {
        const id = stringValue((s as Record<string, unknown>).id);
        if (id) supplements.push({id});
      }
    }
  }
  return {
    id: planId,
    dogId,
    status,
    timezone,
    validFrom,
    validUntil,
    mealSchedule,
    supplements,
  };
}

export function findSlot(
  plan: NutritionPlanData,
  plannedMealId: string,
): MealScheduleSlotData {
  const slot = plan.mealSchedule.find((s) => s.id === plannedMealId);
  if (!slot) {
    throw nutritionError(
      "not-found",
      "plannedMealId não encontrado no plano.",
      "planned_meal_not_found",
    );
  }
  return slot;
}

export function recordedByPayload(
  caller: {uid: string; name: string; ra: string},
  isAdmin: boolean,
): Record<string, string> {
  return {
    uid: caller.uid,
    name: caller.name || caller.ra || caller.uid,
    internal_role: isAdmin ? "admin" : "condutor",
  };
}

/** Collections legadas proibidas para o engine (zero dual-write). */
export const FORBIDDEN_LEGACY_WRITE_COLLECTIONS = [
  "feeding_events",
  "feedings",
  "nutritional_prescriptions",
  "nutrition_prescriptions",
  "nutrition_supplements",
] as const;

export const CANONICAL_WRITE_COLLECTIONS = [
  "meal_logs",
  "supplement_logs",
  "auditLogs",
  "operations",
] as const;
