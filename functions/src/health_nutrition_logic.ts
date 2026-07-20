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
  | "create_supplement_log"
  | "create_nutrition_plan"
  | "update_nutrition_plan"
  | "cancel_nutrition_plan";

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
  "create_fingerprint",
  "createFingerprint",
  "entity_semantic_fingerprint",
  "entitySemanticFingerprint",
  "receipt_id",
  "receiptId",
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

/**
 * Wire temporal: Date | ISO-8601 string | Firestore Timestamp-like
 * ({toDate()} | {seconds|_seconds}).
 * Rejeita objeto arbitrário sem semântica de instante.
 */
export function parseInstant(raw: unknown, field: string): Date {
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) {
      throw nutritionError("validation", `${field} inválido.`);
    }
    return raw;
  }
  if (raw && typeof raw === "object") {
    const obj = raw as {
      toDate?: () => Date;
      seconds?: number;
      _seconds?: number;
      nanoseconds?: number;
      _nanoseconds?: number;
    };
    if (typeof obj.toDate === "function") {
      const d = obj.toDate();
      if (!(d instanceof Date) || Number.isNaN(d.getTime())) {
        throw nutritionError("validation", `${field} inválido.`);
      }
      return d;
    }
    const sec =
      typeof obj.seconds === "number" ?
        obj.seconds :
        typeof obj._seconds === "number" ?
          obj._seconds :
          undefined;
    if (sec !== undefined && Number.isFinite(sec)) {
      const nanos =
        typeof obj.nanoseconds === "number" ?
          obj.nanoseconds :
          typeof obj._nanoseconds === "number" ?
            obj._nanoseconds :
            0;
      const d = new Date(sec * 1000 + Math.floor(nanos / 1e6));
      if (Number.isNaN(d.getTime())) {
        throw nutritionError("validation", `${field} inválido.`);
      }
      return d;
    }
  }
  if (typeof raw === "number" && Number.isFinite(raw)) {
    // epoch millis only (reject tiny epoch-seconds confusion as invalid wire)
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) {
      throw nutritionError("validation", `${field} inválido.`);
    }
    return d;
  }
  if (typeof raw !== "string" || raw.trim() === "") {
    throw nutritionError("validation", `${field} inválido.`);
  }
  const d = new Date(raw);
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

export interface ProfessionalIdentity {
  name: string;
  register_number: string;
  register_state: string;
  specialty?: string | null;
}

export interface HealthDocumentRef {
  id: string;
  type: "prescription" | "laudo" | "exame" | "other";
  issued_by: string;
  issued_at: string;
  url?: string | null;
}

export interface MealScheduleSlot {
  id: string;
  period: "morning" | "afternoon" | "evening" | "night" | "extra";
  scheduled_time: string;
  target_grams: number;
}

export interface NutritionPlanSupplement {
  id: string;
  name: string;
  dose: number;
  unit: "mg" | "g" | "ml" | "scoop" | "tablet" | "drop" | "other";
  frequency: string;
  instructions?: string | null;
  valid_from?: string | null;
  valid_until?: string | null;
}

export interface CreateAndActivateNutritionPlanRequest {
  dogId: string;
  operationId: string;
  planData: {
    food_type: string;
    amount_grams_per_day: number;
    meals_per_day: number;
    timezone: string;
    valid_from: string;
    valid_until?: string | null;
    meal_schedule: MealScheduleSlot[];
    supplements?: NutritionPlanSupplement[];
    hydration_ml?: number | null;
    special_instructions?: string | null;
    professional?: ProfessionalIdentity | null;
    source_document?: HealthDocumentRef | null;
    attachment_refs?: string[];
  };
}

export interface UpdateActiveNutritionPlanRequest {
  dogId: string;
  planId: string;
  operationId: string;
  expectedRevision: number;
  planData: {
    special_instructions?: string | null;
    professional?: ProfessionalIdentity | null;
    source_document?: HealthDocumentRef | null;
    attachment_refs?: string[];
  };
}

export interface CancelNutritionPlanRequest {
  dogId: string;
  planId: string;
  operationId: string;
  expectedRevision: number;
  reason: string;
}

function parseProfessionalIdentity(val: unknown): ProfessionalIdentity | null {
  if (!val || typeof val !== "object" || Array.isArray(val)) return null;
  const obj = val as Record<string, unknown>;
  const name = stringValue(obj.name);
  const register_number = stringValue(obj.register_number) ?? stringValue(obj.registerNumber);
  const register_state = stringValue(obj.register_state) ?? stringValue(obj.registerState);
  const specialty = stringValue(obj.specialty) ?? null;

  if (!name || !register_number || !register_state) {
    throw nutritionError("validation", "ProfessionalIdentity incompleto (name, register_number, register_state obrigatórios).");
  }
  return {
    name,
    register_number,
    register_state,
    specialty,
  };
}

function parseHealthDocumentRef(val: unknown): HealthDocumentRef | null {
  if (!val || typeof val !== "object" || Array.isArray(val)) return null;
  const obj = val as Record<string, unknown>;
  const id = stringValue(obj.id);
  const typeStr = stringValue(obj.type);
  const issued_by = stringValue(obj.issued_by) ?? stringValue(obj.issuedBy);
  const issued_at = stringValue(obj.issued_at) ?? stringValue(obj.issuedAt);
  const url = stringValue(obj.url) ?? null;

  if (!id || !typeStr || !issued_by || !issued_at) {
    throw nutritionError("validation", "HealthDocumentRef incompleto (id, type, issued_by, issued_at obrigatórios).");
  }
  if (!["prescription", "laudo", "exame", "other"].includes(typeStr)) {
    throw nutritionError("validation", `HealthDocumentRef.type inválido: ${typeStr}`);
  }
  return {
    id,
    type: typeStr as any,
    issued_by,
    issued_at,
    url,
  };
}

export function parseCreateAndActivateNutritionPlan(
  data: Record<string, unknown>,
  serverNow: Date = new Date(),
): CreateAndActivateNutritionPlanRequest {
  const forbiddenServerFields = [
    "status",
    "revision",
    "schema_version", "schemaVersion",
    "recorded_by", "recordedBy",
    "created_at", "createdAt",
    "updated_at", "updatedAt"
  ];
  for (const k of forbiddenServerFields) {
    if (Object.prototype.hasOwnProperty.call(data, k)) {
      throw nutritionError("validation", `Campo controlado pelo servidor não permitido na raiz: ${k}.`);
    }
  }

  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  if (dogId.includes("/") || dogId.length > 128) {
    throw nutritionError("validation", "dogId inválido.");
  }

  const rawOpId = data.operationId ?? data.operation_id;
  if (rawOpId !== undefined && typeof rawOpId !== "string") {
    throw nutritionError("validation", "operationId deve ser string.");
  }
  const operationId = normalizeOperationId(rawOpId, true);

  const planDataRaw = data.planData ?? data.plan_data;
  if (!planDataRaw || typeof planDataRaw !== "object" || Array.isArray(planDataRaw)) {
    throw nutritionError("validation", "planData é obrigatório e deve ser objeto.");
  }
  const pd = planDataRaw as Record<string, unknown>;

  for (const k of forbiddenServerFields) {
    if (Object.prototype.hasOwnProperty.call(pd, k)) {
      throw nutritionError("validation", `Campo controlado pelo servidor não permitido em planData: ${k}.`);
    }
  }

  const food_type = stringValue(pd.food_type) ?? stringValue(pd.foodType);
  if (!food_type || !food_type.trim()) throw nutritionError("validation", "food_type é obrigatório e não pode ser vazio.");

  const amount_grams_per_day = pd.amount_grams_per_day ?? pd.amountGramsPerDay;
  assertFinitePositive(amount_grams_per_day, "amount_grams_per_day");

  const meals_per_day = pd.meals_per_day ?? pd.mealsPerDay;
  assertFinitePositive(meals_per_day, "meals_per_day");

  const timezone = stringValue(pd.timezone) ?? NUTRITION_DEFAULT_TIMEZONE;
  try {
    localServiceDateFromInstant(serverNow, timezone);
  } catch {
    throw nutritionError("validation", "timezone inválido.", "invalid_timezone");
  }

  const valid_from = stringValue(pd.valid_from) ?? stringValue(pd.validFrom);
  if (!valid_from) throw nutritionError("validation", "valid_from é obrigatório.");
  const validFromDate = parseInstant(valid_from, "valid_from");

  if (validFromDate.getTime() > serverNow.getTime()) {
    throw nutritionError("validation", "valid_from no futuro não é permitido na v1.");
  }

  const localTodayStr = localServiceDateFromInstant(serverNow, timezone);
  const startOfToday = scheduledForFromLocal(localTodayStr, "00:00", timezone);
  if (validFromDate.getTime() < startOfToday.getTime()) {
    throw nutritionError("validation", "Vigência do plano anterior ao início do dia civil atual.");
  }

  const valid_until_raw = pd.valid_until ?? pd.validUntil;
  let valid_until: string | null = null;
  if (valid_until_raw !== undefined && valid_until_raw !== null && valid_until_raw !== "") {
    valid_until = stringValue(valid_until_raw) ?? null;
    const validUntilDate = parseInstant(valid_until, "valid_until");
    if (validUntilDate.getTime() <= validFromDate.getTime()) {
      throw nutritionError("validation", "valid_until deve ser posterior a valid_from.");
    }
    if (validUntilDate.getTime() <= serverNow.getTime()) {
      throw nutritionError("validation", "Plano expirado não pode ser ativado.");
    }
  }

  const scheduleRaw = pd.meal_schedule ?? pd.mealSchedule;
  if (!Array.isArray(scheduleRaw) || scheduleRaw.length === 0) {
    throw nutritionError("validation", "meal_schedule é obrigatório e não pode ser vazio.");
  }

  if (Number(meals_per_day) !== scheduleRaw.length) {
    throw nutritionError("validation", "meals_per_day deve ser igual ao número de slots em meal_schedule.");
  }

  const meal_schedule: MealScheduleSlot[] = [];
  const slotIds = new Set<string>();
  let totalTarget = 0;

  for (const item of scheduleRaw) {
    if (!item || typeof item !== "object") {
      throw nutritionError("validation", "slot de meal_schedule inválido.");
    }
    const m = item as Record<string, unknown>;
    const id = stringValue(m.id);
    if (!id || id.trim() === "") throw nutritionError("validation", "id do slot é obrigatório.");
    if (slotIds.has(id)) throw nutritionError("validation", `id de slot duplicado: ${id}`);
    slotIds.add(id);

    const period = stringValue(m.period);
    if (!period || !MEAL_PERIODS.has(period)) {
      throw nutritionError("validation", `period do slot inválido ou não suportado: ${period}`);
    }

    const scheduled_time = stringValue(m.scheduled_time) ?? stringValue(m.scheduledTime);
    if (!scheduled_time || !/^([01]\d|2[0-3]):([0-5]\d)$/.test(scheduled_time)) {
      throw nutritionError("validation", "scheduled_time do slot deve estar no formato HH:mm.");
    }

    const target_grams = m.target_grams ?? m.targetGrams;
    assertFinitePositive(target_grams, `target_grams do slot ${id}`);
    totalTarget += Number(target_grams);

    meal_schedule.push({
      id,
      period: period as any,
      scheduled_time,
      target_grams: Number(target_grams),
    });
  }

  if (Math.abs(totalTarget - Number(amount_grams_per_day)) > 0.01) {
    throw nutritionError("validation", "A soma das refeições (target_grams) deve equivaler a amount_grams_per_day.");
  }

  const supplementsRaw = pd.supplements;
  const supplements: NutritionPlanSupplement[] = [];
  const suppIds = new Set<string>();
  if (Array.isArray(supplementsRaw)) {
    for (const item of supplementsRaw) {
      if (!item || typeof item !== "object") {
        throw nutritionError("validation", "suplemento inválido.");
      }
      const s = item as Record<string, unknown>;
      const id = stringValue(s.id);
      if (!id || id.trim() === "") throw nutritionError("validation", "id do suplemento é obrigatório.");
      if (suppIds.has(id)) throw nutritionError("validation", `id de suplemento duplicado: ${id}`);
      suppIds.add(id);

      const name = stringValue(s.name);
      if (!name) throw nutritionError("validation", "name do suplemento é obrigatório.");

      const dose = s.dose;
      if (typeof dose === "string") throw nutritionError("validation", "dose do suplemento deve ser numérica.");
      assertFinitePositive(dose, `dose do suplemento ${id}`);

      const unit = assertSupplementUnit(s.unit);

      const frequency = stringValue(s.frequency);
      if (!frequency) throw nutritionError("validation", "frequency do suplemento é obrigatório.");

      const instructions = stringValue(s.instructions) ?? null;
      const val_from = stringValue(s.valid_from) ?? stringValue(s.validFrom) ?? null;
      let valFromDateSupp: Date | null = null;
      if (val_from) {
        valFromDateSupp = parseInstant(val_from, "supplements.valid_from");
      }

      const val_until = stringValue(s.valid_until) ?? stringValue(s.validUntil) ?? null;
      if (val_until) {
        const valUntilDateSupp = parseInstant(val_until, "supplements.valid_until");
        if (valFromDateSupp && valUntilDateSupp.getTime() <= valFromDateSupp.getTime()) {
          throw nutritionError("validation", "valid_until do suplemento deve ser posterior ao valid_from.");
        }
      }

      supplements.push({
        id,
        name,
        dose: Number(dose),
        unit: unit as any,
        frequency,
        instructions,
        valid_from: val_from,
        valid_until: val_until,
      });
    }
  }

  const hydration_ml = pd.hydration_ml ?? pd.hydrationMl;
  let hydration: number | null = null;
  if (hydration_ml !== undefined && hydration_ml !== null && hydration_ml !== "") {
    assertFinitePositive(hydration_ml, "hydration_ml");
    hydration = Number(hydration_ml);
  }

  const special_instructions = stringValue(pd.special_instructions) ?? stringValue(pd.specialInstructions) ?? null;
  const professional = parseProfessionalIdentity(pd.professional);
  const source_document = parseHealthDocumentRef(pd.source_document ?? pd.sourceDocument);

  const attachmentRefsRaw = pd.attachment_refs ?? pd.attachmentRefs;
  const attachment_refs: string[] = [];
  if (Array.isArray(attachmentRefsRaw)) {
    for (const r of attachmentRefsRaw) {
      const url = stringValue(r);
      if (url) attachment_refs.push(url);
    }
  }

  return {
    dogId,
    operationId,
    planData: {
      food_type,
      amount_grams_per_day: Number(amount_grams_per_day),
      meals_per_day: Number(meals_per_day),
      timezone,
      valid_from,
      valid_until,
      meal_schedule,
      supplements,
      hydration_ml: hydration,
      special_instructions,
      professional,
      source_document,
      attachment_refs,
    },
  };
}

export function parseUpdateActiveNutritionPlan(
  data: Record<string, unknown>,
): UpdateActiveNutritionPlanRequest {
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  if (dogId.includes("/") || dogId.length > 128) {
    throw nutritionError("validation", "dogId inválido.");
  }

  const planId = stringValue(data.planId) ?? stringValue(data.plan_id);
  if (!planId) throw nutritionError("validation", "planId é obrigatório.");
  if (planId.includes("/") || planId.length > 128) {
    throw nutritionError("validation", "planId inválido.");
  }

  const rawOpId = data.operationId ?? data.operation_id;
  if (rawOpId !== undefined && typeof rawOpId !== "string") {
    throw nutritionError("validation", "operationId deve ser string.");
  }
  const operationId = normalizeOperationId(rawOpId, true);

  const expectedRevision = data.expectedRevision ?? data.expected_revision;
  if (typeof expectedRevision !== "number" || !Number.isInteger(expectedRevision) || expectedRevision < 1) {
    throw nutritionError("validation", "expectedRevision deve ser inteiro positivo.");
  }

  const planDataRaw = data.planData ?? data.plan_data;
  if (!planDataRaw || typeof planDataRaw !== "object" || Array.isArray(planDataRaw)) {
    throw nutritionError("validation", "planData é obrigatório e deve ser objeto.");
  }
  const pd = planDataRaw as Record<string, unknown>;

  const allowedAdminKeys = [
    "special_instructions", "specialInstructions",
    "professional",
    "source_document", "sourceDocument",
    "attachment_refs", "attachmentRefs"
  ];
  const hasAdminKey = allowedAdminKeys.some(k => Object.prototype.hasOwnProperty.call(pd, k));
  if (!hasAdminKey) {
    throw nutritionError("validation", "planData do update deve conter pelo menos uma chave administrativa.");
  }

  const forbiddenStructural = [
    "food_type", "foodType",
    "amount_grams_per_day", "amountGramsPerDay",
    "meals_per_day", "mealsPerDay",
    "meal_schedule", "mealSchedule",
    "supplements",
    "hydration_ml", "hydrationMl",
    "timezone",
    "valid_from", "validFrom",
    "valid_until", "validUntil"
  ];
  for (const k of forbiddenStructural) {
    if (Object.prototype.hasOwnProperty.call(pd, k)) {
      throw nutritionError("validation", `Alteração estrutural não permitida no update: ${k}. Crie um novo plano.`);
    }
  }

  const special_instructions = stringValue(pd.special_instructions) ?? stringValue(pd.specialInstructions) ?? null;
  const professional = parseProfessionalIdentity(pd.professional);
  const source_document = parseHealthDocumentRef(pd.source_document ?? pd.sourceDocument);

  const attachmentRefsRaw = pd.attachment_refs ?? pd.attachmentRefs;
  const attachment_refs: string[] = [];
  if (Array.isArray(attachmentRefsRaw)) {
    for (const r of attachmentRefsRaw) {
      const url = stringValue(r);
      if (url) attachment_refs.push(url);
    }
  }

  const planData: UpdateActiveNutritionPlanRequest["planData"] = {};
  if (Object.prototype.hasOwnProperty.call(pd, "special_instructions") || Object.prototype.hasOwnProperty.call(pd, "specialInstructions")) planData.special_instructions = special_instructions;
  if (Object.prototype.hasOwnProperty.call(pd, "professional")) planData.professional = professional;
  if (Object.prototype.hasOwnProperty.call(pd, "source_document") || Object.prototype.hasOwnProperty.call(pd, "sourceDocument")) planData.source_document = source_document;
  if (Object.prototype.hasOwnProperty.call(pd, "attachment_refs") || Object.prototype.hasOwnProperty.call(pd, "attachmentRefs")) planData.attachment_refs = attachment_refs;

  return {
    dogId,
    planId,
    operationId,
    expectedRevision: Number(expectedRevision),
    planData,
  };
}

export function parseCancelNutritionPlan(
  data: Record<string, unknown>,
): CancelNutritionPlanRequest {
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) throw nutritionError("validation", "dogId é obrigatório.");
  if (dogId.includes("/") || dogId.length > 128) {
    throw nutritionError("validation", "dogId inválido.");
  }

  const planId = stringValue(data.planId) ?? stringValue(data.plan_id);
  if (!planId) throw nutritionError("validation", "planId é obrigatório.");
  if (planId.includes("/") || planId.length > 128) {
    throw nutritionError("validation", "planId inválido.");
  }

  const rawOpId = data.operationId ?? data.operation_id;
  if (rawOpId !== undefined && typeof rawOpId !== "string") {
    throw nutritionError("validation", "operationId deve ser string.");
  }
  const operationId = normalizeOperationId(rawOpId, true);

  const expectedRevision = data.expectedRevision ?? data.expected_revision;
  if (typeof expectedRevision !== "number" || !Number.isInteger(expectedRevision) || expectedRevision < 1) {
    throw nutritionError("validation", "expectedRevision deve ser inteiro positivo.");
  }

  const reason = stringValue(data.reason);
  if (!reason || !reason.trim()) {
    throw nutritionError("validation", "Justificativa (reason) é obrigatória e não pode ser vazia.");
  }

  return {
    dogId,
    planId,
    operationId,
    expectedRevision: Number(expectedRevision),
    reason: reason.trim(),
  };
}

export function fingerprintNutritionPlan(
  planData: CreateAndActivateNutritionPlanRequest["planData"],
): string {
  const structural = {
    food_type: stringValue(planData.food_type) ?? "",
    amount_grams_per_day: Number(planData.amount_grams_per_day ?? 0),
    meals_per_day: Number(planData.meals_per_day ?? 0),
    timezone: stringValue(planData.timezone) ?? NUTRITION_DEFAULT_TIMEZONE,
    valid_from: stringValue(planData.valid_from) ?? "",
    valid_until: stringValue(planData.valid_until) ?? null,
    hydration_ml: planData.hydration_ml !== undefined && planData.hydration_ml !== null ? Number(planData.hydration_ml) : null,
    meal_schedule: Array.isArray(planData.meal_schedule)
      ? planData.meal_schedule.map((m) => ({
          id: stringValue(m.id) ?? "",
          period: stringValue(m.period) ?? "",
          scheduled_time: stringValue(m.scheduled_time) ?? "",
          target_grams: Number(m.target_grams ?? 0),
        })).sort((a, b) => a.id.localeCompare(b.id))
      : [],
    supplements: Array.isArray(planData.supplements)
      ? planData.supplements.map((s) => ({
          id: stringValue(s.id) ?? "",
          name: stringValue(s.name) ?? "",
          dose: Number(s.dose ?? 0),
          unit: stringValue(s.unit) ?? "",
          frequency: stringValue(s.frequency) ?? "",
          instructions: stringValue(s.instructions) ?? null,
          valid_from: stringValue(s.valid_from) ?? null,
          valid_until: stringValue(s.valid_until) ?? null,
        })).sort((a, b) => a.id.localeCompare(b.id))
      : [],
  };
  return sha256Hex(stableStringify(structural));
}
