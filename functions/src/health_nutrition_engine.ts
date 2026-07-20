/**
 * Motor de mutação Nutrição — Fase 5D Gate 1.
 *
 * Durable replay: receipt consultado ANTES de dependências mutáveis (plano).
 * Fonte de verdade: dogs/{dogId}/nutrition_operations/{receiptId}
 *
 * Testável sem Emulator via deps injetadas.
 * NÃO exporta onCall. NÃO escreve em collections legadas.
 */
import {
  NutritionOperationType,
  adhocMealLogIdV1,
  assertNotFuture,
  decideCreateByFingerprint,
  decidePlannedMealAgainstExisting,
  entitySemanticFingerprintPlannedMeal,
  evaluatePlanEligibility,
  findSlot,
  fingerprintAdhocMeal,
  fingerprintPlannedMeal,
  fingerprintSupplement,
  fingerprintNutritionPlan,
  localServiceDateFromInstant,
  matchNutritionReceipt,
  mealOccurrenceIdV1,
  nutritionError,
  nutritionOperationReceiptIdV1,
  parseAdhocMealCommand,
  parsePlanFromDoc,
  parsePlannedMealCommand,
  parseSupplementCommand,
  parseCreateAndActivateNutritionPlan,
  parseUpdateActiveNutritionPlan,
  parseCancelNutritionPlan,
  parseInstant,
  plannedMealEntityFingerprintFromDoc,
  recordedByPayload,
  scheduledForFromLocal,
  sha256Hex,
  stringValue,
  supplementLogIdV1,
  NUTRITION_SCHEMA_VERSION,
} from "./health_nutrition_logic";

export type JsonMap = Record<string, unknown>;

export type NutritionActor = {
  uid: string;
  email: string;
  ra: string;
  name: string;
};

export type NutritionMutationResult = {
  dogId: string;
  entityId: string;
  entityType: "meal_log" | "supplement_log";
  revision: number;
  wasNoOp: boolean;
  mealOccurrenceId?: string | null;
};

export type NutritionPlanMutationResult = {
  dogId: string;
  planId: string;
  status: "active" | "cancelled";
  revision: number;
  wasNoOp: boolean;
  supersededPlanId?: string | null;
};

export type TxDocSnap = {
  exists: boolean;
  data: JsonMap;
};

export type NutritionTxn = {
  get: (path: string) => Promise<TxDocSnap>;
  set: (path: string, data: JsonMap) => void;
  getActivePlans?: (dogId: string) => Promise<Array<{ id: string; data: JsonMap }>>;
  getMealLogsInWindow?: (dogId: string, start: Date, end: Date) => Promise<Array<{ id: string; data: JsonMap }>>;
  getSupplementLogsInWindow?: (dogId: string, start: Date, end: Date) => Promise<Array<{ id: string; data: JsonMap }>>;
};

export type NutritionEngineDeps = {
  /** Relógio de servidor injetado (nunca Date do cliente). */
  serverNow: () => Date;
  /** true se ator tem autoridade admin para recorded_by.role */
  isAdmin: (actor: NutritionActor) => boolean | Promise<boolean>;
  /**
   * Leitura pontual fora de txn — somente durable receipt lookup antecipado.
   * NÃO é autoridade de NutritionPlan para operação nova.
   */
  getDoc: (path: string) => Promise<TxDocSnap>;
  /** Executa callback em transação atômica (mockável). */
  runTransaction: <T>(fn: (tx: NutritionTxn) => Promise<T>) => Promise<T>;
};

function pathMeal(dogId: string, mealId: string): string {
  return `dogs/${dogId}/meal_logs/${mealId}`;
}

function pathSupp(dogId: string, logId: string): string {
  return `dogs/${dogId}/supplement_logs/${logId}`;
}

/** Path canônico do plano (lido na transaction para operação nova). */
export function pathNutritionPlan(dogId: string, planId: string): string {
  return `dogs/${dogId}/nutrition_plans/${planId}`;
}

/**
 * Durable operation registry (fonte de verdade da idempotência).
 * dogs/{dogId}/nutrition_operations/{receiptId}
 */
export function pathNutritionOperation(
  dogId: string,
  receiptId: string,
): string {
  return `dogs/${dogId}/nutrition_operations/${receiptId}`;
}

function pathAudit(auditId: string): string {
  return `auditLogs/${auditId}`;
}

function assertCanonicalPath(path: string): void {
  const forbidden = [
    "/feeding_events/",
    "/feedings/",
    "/nutritional_prescriptions/",
    "/nutrition_prescriptions/",
    "/nutrition_supplements/",
  ];
  for (const f of forbidden) {
    if (path.includes(f)) {
      throw nutritionError(
        "integrity",
        `Write proibido em collection legada: ${path}`,
      );
    }
  }
  const m = path.match(/^dogs\/[^/]+\/([^/]+)/);
  if (m) {
    const col = m[1];
    if (
      col === "feeding_events" ||
      col === "feedings" ||
      col === "nutritional_prescriptions" ||
      col === "nutrition_prescriptions" ||
      col === "nutrition_supplements"
    ) {
      throw nutritionError(
        "integrity",
        `Write proibido em collection legada: ${col}`,
      );
    }
  }
}

function safeSet(tx: NutritionTxn, path: string, data: JsonMap): void {
  assertCanonicalPath(path);
  tx.set(path, data);
}

function auditId(
  dogId: string,
  entityId: string,
  op: NutritionOperationType,
  key: string,
): string {
  const h = sha256Hex(`${dogId}|${entityId}|${op}|${key}`);
  return `nu_audit_${h.slice(0, 40)}`;
}

function planId(actorUid: string, operationId: string): string {
  return `nutrition_plan_${sha256Hex(`${actorUid}|create_nutrition_plan|${operationId}`).slice(0, 32)}`;
}

function planFingerprint(value: unknown): string {
  return sha256Hex(JSON.stringify(value));
}

function auditPayload(
  actor: NutritionActor,
  action: string,
  entityType: string,
  entityId: string,
  entityPath: string,
  dogId: string,
  summary: string,
  serverNow: Date,
): JsonMap {
  return {
    action,
    entity_type: entityType,
    entity_id: entityId,
    entity_path: entityPath,
    summary,
    actor: {
      uid: actor.uid,
      email: actor.email,
      ra: actor.ra,
      name: actor.name,
    },
    metadata: {dog_id: dogId},
    source: "functions",
    performed_at: serverNow.toISOString(),
    createdAt: serverNow.toISOString(),
  };
}

function durableReceiptPayload(params: {
  receiptId: string;
  operationId: string;
  operationType: NutritionOperationType;
  actorUid: string;
  fingerprint: string;
  entityType: "meal_log" | "supplement_log";
  entityId: string;
  mealOccurrenceId?: string | null;
  result: JsonMap;
  serverNow: Date;
}): JsonMap {
  return {
    receipt_id: params.receiptId,
    operation_id: params.operationId,
    operation_type: params.operationType,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    entity_type: params.entityType,
    entity_id: params.entityId,
    meal_occurrence_id: params.mealOccurrenceId ?? null,
    result: params.result,
    processed_at: params.serverNow.toISOString(),
  };
}

function iso(d: Date): string {
  return d.toISOString();
}

function readStoredFingerprint(data: JsonMap): string | undefined {
  return (
    stringValue(data.create_fingerprint) ??
    stringValue(data.createFingerprint) ??
    undefined
  );
}

function resultFromReceipt(data: JsonMap): NutritionMutationResult {
  const r = (data.result ?? {}) as JsonMap;
  const entityType =
    (stringValue(data.entity_type) as "meal_log" | "supplement_log" | undefined) ??
    "meal_log";
  const entityId =
    stringValue(data.entity_id) ??
    stringValue(r.mealId) ??
    stringValue(r.logId) ??
    "";
  return {
    dogId: stringValue(r.dogId) ?? "",
    entityId,
    entityType,
    revision: Number(r.revision ?? 1),
    wasNoOp: true,
    mealOccurrenceId:
      data.meal_occurrence_id === null || data.meal_occurrence_id === undefined ?
        (entityType === "meal_log" ? null : undefined) :
        stringValue(data.meal_occurrence_id) ?? null,
  };
}

/**
 * Consulta durable receipt (fonte de verdade).
 * Não carrega plano / entidade.
 */
/**
 * Receipt malformado ≠ missing.
 * Documento presente sem campos canônicos → integrity (fail-closed).
 */
function assertReceiptShape(data: JsonMap): void {
  const required = [
    "receipt_id",
    "operation_id",
    "operation_type",
    "actor_uid",
    "fingerprint",
    "entity_type",
    "entity_id",
    "result",
  ];
  for (const key of required) {
    if (data[key] === undefined || data[key] === null || data[key] === "") {
      throw nutritionError(
        "integrity",
        `Receipt malformado: campo obrigatório ausente (${key}).`,
        "receipt_integrity",
      );
    }
  }
  if (typeof data.result !== "object" || Array.isArray(data.result)) {
    throw nutritionError(
      "integrity",
      "Receipt malformado: result inválido.",
      "receipt_integrity",
    );
  }
}

async function resolveDurableReceipt(params: {
  deps: NutritionEngineDeps;
  dogId: string;
  actorUid: string;
  operationType: NutritionOperationType;
  operationId: string;
  fingerprint: string;
  snap?: TxDocSnap;
}): Promise<"missing" | NutritionMutationResult> {
  const receiptId = nutritionOperationReceiptIdV1({
    actorUid: params.actorUid,
    operationType: params.operationType,
    operationId: params.operationId,
  });
  const path = pathNutritionOperation(params.dogId, receiptId);
  const snap = params.snap ?? (await params.deps.getDoc(path));
  if (!snap.exists) return "missing";

  assertReceiptShape(snap.data);

  const match = matchNutritionReceipt({
    receiptExists: true,
    storedActorUid: stringValue(snap.data.actor_uid),
    storedOperationType: stringValue(snap.data.operation_type) as
      | NutritionOperationType
      | undefined,
    storedFingerprint: stringValue(snap.data.fingerprint),
    actorUid: params.actorUid,
    operationType: params.operationType,
    fingerprint: params.fingerprint,
  });
  if (match === "replay") {
    const out = resultFromReceipt(snap.data);
    out.dogId = params.dogId;
    return out;
  }
  if (match === "idempotency-conflict") {
    throw nutritionError(
      "idempotency-conflict",
      "Mesma operationId (mesmo ator/tipo) com intenção diferente.",
      "idempotency_conflict",
    );
  }
  return "missing";
}

function planFromTxnSnap(
  dogId: string,
  planId: string,
  snap: TxDocSnap,
): ReturnType<typeof parsePlanFromDoc> {
  if (!snap.exists) {
    throw nutritionError(
      "not-found",
      "NutritionPlan não encontrado.",
      "nutrition_plan_not_found",
    );
  }
  return parsePlanFromDoc(planId, dogId, snap.data);
}

// ── Planned meal ─────────────────────────────────────────────────────────────

export async function runCreatePlannedMealLog(
  actor: NutritionActor,
  rawCommand: Record<string, unknown>,
  deps: NutritionEngineDeps,
): Promise<NutritionMutationResult> {
  // 1–4: parse + operation fingerprint (somente inputs do cliente) + receiptId
  const cmd = parsePlannedMealCommand(rawCommand);
  const opType: NutritionOperationType = "create_planned_meal";
  const operationFingerprint = fingerprintPlannedMeal({
    dogId: cmd.dogId,
    planId: cmd.planId,
    plannedMealId: cmd.plannedMealId,
    offeredGrams: cmd.offeredGrams,
    consumedGrams: cmd.consumedGrams,
    acceptance: cmd.acceptance,
    fedAtIso: iso(cmd.fedAt),
    observations: cmd.observations,
    attachmentRefs: cmd.attachmentRefs,
  });
  const receiptId = nutritionOperationReceiptIdV1({
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
  });
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);

  // Durable receipt FIRST — ZERO plan read
  const early = await resolveDurableReceipt({
    deps,
    dogId: cmd.dogId,
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
    fingerprint: operationFingerprint,
  });
  if (early !== "missing") {
    return early;
  }

  // Operação nova: fedAt vs server clock (input do cliente, não estado do plano)
  const serverNow = deps.serverNow();
  assertNotFuture(cmd.fedAt, serverNow, "fedAt");

  const isAdmin = await Promise.resolve(deps.isAdmin(actor));
  const recordedBy = recordedByPayload(actor, isAdmin);
  const planPath = pathNutritionPlan(cmd.dogId, cmd.planId);

  return deps.runTransaction(async (tx) => {
    // 1) recheck receipt
    const opSnap = await tx.get(receiptPath);
    const recheck = await resolveDurableReceipt({
      deps,
      dogId: cmd.dogId,
      actorUid: actor.uid,
      operationType: opType,
      operationId: cmd.idempotencyKey,
      fingerprint: operationFingerprint,
      snap: opSnap,
    });
    if (recheck !== "missing") {
      return recheck;
    }

    // 2–4) plan snapshot AUTORITATIVO (transactional) — derivação + eligibility
    const planSnap = await tx.get(planPath);
    const plan = planFromTxnSnap(cmd.dogId, cmd.planId, planSnap);
    const eligibility = evaluatePlanEligibility({
      status: plan.status,
      validFrom: plan.validFrom,
      validUntil: plan.validUntil,
      fedAt: cmd.fedAt,
    });
    if (!eligibility.ok) {
      throw nutritionError(
        eligibility.code === "nutrition_plan_not_found" ?
          "not-found" :
          "failed-precondition",
        eligibility.message,
        eligibility.code,
      );
    }

    const slot = findSlot(plan, cmd.plannedMealId);
    const localServiceDate = localServiceDateFromInstant(
      cmd.fedAt,
      plan.timezone,
    );
    const scheduledFor = scheduledForFromLocal(
      localServiceDate,
      slot.scheduledTime,
      plan.timezone,
    );
    const occurrenceId = mealOccurrenceIdV1({
      dogId: cmd.dogId,
      planId: cmd.planId,
      plannedMealId: cmd.plannedMealId,
      localServiceDate,
    });
    const mealId = occurrenceId;
    const proposedEntityFingerprint = entitySemanticFingerprintPlannedMeal({
      planId: cmd.planId,
      plannedMealId: cmd.plannedMealId,
      mealOccurrenceId: occurrenceId,
      period: slot.period,
      scheduledForIso: iso(scheduledFor),
      prescriptionAmountAtTime: slot.targetGrams,
      offeredGrams: cmd.offeredGrams,
      consumedGrams: cmd.consumedGrams,
      acceptance: cmd.acceptance,
      fedAtIso: iso(cmd.fedAt),
      observations: cmd.observations,
      attachmentRefs: cmd.attachmentRefs,
    });

    // 5–6) existing meal + decision
    const mealPath = pathMeal(cmd.dogId, mealId);
    const mealSnap = await tx.get(mealPath);
    const existingEntityFp = mealSnap.exists ?
      plannedMealEntityFingerprintFromDoc(mealSnap.data) :
      undefined;
    const decision = decidePlannedMealAgainstExisting({
      docExists: mealSnap.exists,
      existingEntityFingerprint: existingEntityFp,
      proposedEntityFingerprint,
    });
    if (decision.kind === "error") {
      throw nutritionError(
        decision.code,
        decision.message,
        decision.detailCode,
      );
    }

    if (decision.kind === "noop") {
      const rev = Number(mealSnap.data.revision ?? 1);
      const result: JsonMap = {
        dogId: cmd.dogId,
        mealId,
        revision: rev,
        wasNoOp: true,
        mealOccurrenceId: occurrenceId,
      };
      safeSet(
        tx,
        receiptPath,
        durableReceiptPayload({
          receiptId,
          operationId: cmd.idempotencyKey,
          operationType: opType,
          actorUid: actor.uid,
          fingerprint: operationFingerprint,
          entityType: "meal_log",
          entityId: mealId,
          mealOccurrenceId: occurrenceId,
          result,
          serverNow,
        }),
      );
      return {
        dogId: cmd.dogId,
        entityId: mealId,
        entityType: "meal_log" as const,
        revision: rev,
        wasNoOp: true,
        mealOccurrenceId: occurrenceId,
      };
    }

    // 7) atomic create
    const revision = 1;
    const record: JsonMap = {
      period: slot.period,
      offered_grams: cmd.offeredGrams,
      consumed_grams: cmd.consumedGrams,
      acceptance: cmd.acceptance,
      fed_at: iso(cmd.fedAt),
      plan_id: cmd.planId,
      planned_meal_id: cmd.plannedMealId,
      meal_occurrence_id: occurrenceId,
      scheduled_for: iso(scheduledFor),
      prescription_amount_at_time: slot.targetGrams,
      observations: cmd.observations,
      attachment_refs: cmd.attachmentRefs,
      recorded_by: recordedBy,
      recorded_at: iso(serverNow),
      schema_version: NUTRITION_SCHEMA_VERSION,
      revision,
      source: "mobile_callable",
      create_fingerprint: operationFingerprint,
      entity_semantic_fingerprint: proposedEntityFingerprint,
      create_operation_id: cmd.idempotencyKey,
    };
    const result: JsonMap = {
      dogId: cmd.dogId,
      mealId,
      revision,
      wasNoOp: false,
      mealOccurrenceId: occurrenceId,
    };

    safeSet(tx, mealPath, record);
    safeSet(
      tx,
      receiptPath,
      durableReceiptPayload({
        receiptId,
        operationId: cmd.idempotencyKey,
        operationType: opType,
        actorUid: actor.uid,
        fingerprint: operationFingerprint,
        entityType: "meal_log",
        entityId: mealId,
        mealOccurrenceId: occurrenceId,
        result,
        serverNow,
      }),
    );
    safeSet(
      tx,
      pathAudit(
        auditId(cmd.dogId, mealId, opType, `${actor.uid}|${cmd.idempotencyKey}`),
      ),
      auditPayload(
        actor,
        "health.nutrition.meal_log.create_planned",
        "meal_log",
        mealId,
        mealPath,
        cmd.dogId,
        "Create planned MealLog",
        serverNow,
      ),
    );

    return {
      dogId: cmd.dogId,
      entityId: mealId,
      entityType: "meal_log" as const,
      revision,
      wasNoOp: false,
      mealOccurrenceId: occurrenceId,
    };
  });
}

// ── Ad hoc meal ──────────────────────────────────────────────────────────────

export async function runCreateAdhocMealLog(
  actor: NutritionActor,
  rawCommand: Record<string, unknown>,
  deps: NutritionEngineDeps,
): Promise<NutritionMutationResult> {
  const cmd = parseAdhocMealCommand(rawCommand);
  const opType: NutritionOperationType = "create_adhoc_meal";
  const fingerprint = fingerprintAdhocMeal({
    dogId: cmd.dogId,
    period: cmd.period,
    offeredGrams: cmd.offeredGrams,
    consumedGrams: cmd.consumedGrams,
    acceptance: cmd.acceptance,
    fedAtIso: iso(cmd.fedAt),
    observations: cmd.observations,
    attachmentRefs: cmd.attachmentRefs,
  });
  const receiptId = nutritionOperationReceiptIdV1({
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
  });
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);

  const early = await resolveDurableReceipt({
    deps,
    dogId: cmd.dogId,
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
    fingerprint,
  });
  if (early !== "missing") {
    return early;
  }

  const serverNow = deps.serverNow();
  assertNotFuture(cmd.fedAt, serverNow, "fedAt");

  const mealId = adhocMealLogIdV1({
    actorUid: actor.uid,
    dogId: cmd.dogId,
    idempotencyKey: cmd.idempotencyKey,
  });
  const isAdmin = await Promise.resolve(deps.isAdmin(actor));
  const recordedBy = recordedByPayload(actor, isAdmin);

  return deps.runTransaction(async (tx) => {
    const opSnap = await tx.get(receiptPath);
    const recheck = await resolveDurableReceipt({
      deps,
      dogId: cmd.dogId,
      actorUid: actor.uid,
      operationType: opType,
      operationId: cmd.idempotencyKey,
      fingerprint,
      snap: opSnap,
    });
    if (recheck !== "missing") {
      return recheck;
    }

    const mealPath = pathMeal(cmd.dogId, mealId);
    const mealSnap = await tx.get(mealPath);

    const decision = decideCreateByFingerprint({
      docExists: mealSnap.exists,
      storedFingerprint: mealSnap.exists ?
        readStoredFingerprint(mealSnap.data) :
        undefined,
      requestFingerprint: fingerprint,
    });
    if (decision.kind === "error") {
      throw nutritionError(decision.code, decision.message, decision.detailCode);
    }
    if (decision.kind === "noop") {
      const rev = Number(mealSnap.data.revision ?? 1);
      const result: JsonMap = {
        dogId: cmd.dogId,
        mealId,
        revision: rev,
        wasNoOp: true,
      };
      safeSet(
        tx,
        receiptPath,
        durableReceiptPayload({
          receiptId,
          operationId: cmd.idempotencyKey,
          operationType: opType,
          actorUid: actor.uid,
          fingerprint,
          entityType: "meal_log",
          entityId: mealId,
          mealOccurrenceId: null,
          result,
          serverNow,
        }),
      );
      return {
        dogId: cmd.dogId,
        entityId: mealId,
        entityType: "meal_log" as const,
        revision: rev,
        wasNoOp: true,
        mealOccurrenceId: null,
      };
    }

    const revision = 1;
    const record: JsonMap = {
      period: cmd.period,
      offered_grams: cmd.offeredGrams,
      consumed_grams: cmd.consumedGrams,
      acceptance: cmd.acceptance,
      fed_at: iso(cmd.fedAt),
      plan_id: null,
      planned_meal_id: null,
      meal_occurrence_id: null,
      scheduled_for: null,
      prescription_amount_at_time: null,
      observations: cmd.observations,
      attachment_refs: cmd.attachmentRefs,
      recorded_by: recordedBy,
      recorded_at: iso(serverNow),
      schema_version: NUTRITION_SCHEMA_VERSION,
      revision,
      source: "mobile_callable",
      create_fingerprint: fingerprint,
      create_operation_id: cmd.idempotencyKey,
    };
    const result: JsonMap = {
      dogId: cmd.dogId,
      mealId,
      revision,
      wasNoOp: false,
    };

    safeSet(tx, mealPath, record);
    safeSet(
      tx,
      receiptPath,
      durableReceiptPayload({
        receiptId,
        operationId: cmd.idempotencyKey,
        operationType: opType,
        actorUid: actor.uid,
        fingerprint,
        entityType: "meal_log",
        entityId: mealId,
        mealOccurrenceId: null,
        result,
        serverNow,
      }),
    );
    safeSet(
      tx,
      pathAudit(
        auditId(cmd.dogId, mealId, opType, `${actor.uid}|${cmd.idempotencyKey}`),
      ),
      auditPayload(
        actor,
        "health.nutrition.meal_log.create_adhoc",
        "meal_log",
        mealId,
        mealPath,
        cmd.dogId,
        "Create ad hoc MealLog",
        serverNow,
      ),
    );

    return {
      dogId: cmd.dogId,
      entityId: mealId,
      entityType: "meal_log" as const,
      revision,
      wasNoOp: false,
      mealOccurrenceId: null,
    };
  });
}

// ── Supplement log ───────────────────────────────────────────────────────────

export async function runCreateSupplementLog(
  actor: NutritionActor,
  rawCommand: Record<string, unknown>,
  deps: NutritionEngineDeps,
): Promise<NutritionMutationResult> {
  const cmd = parseSupplementCommand(rawCommand);
  const opType: NutritionOperationType = "create_supplement_log";
  const fingerprint = fingerprintSupplement({
    dogId: cmd.dogId,
    supplementName: cmd.supplementName,
    dose: cmd.dose,
    unit: cmd.unit,
    administeredAtIso: iso(cmd.administeredAt),
    nutritionPlanId: cmd.nutritionPlanId,
    supplementRegimenId: cmd.supplementRegimenId,
    notes: cmd.notes,
    batchNumber: cmd.batchNumber,
    protocolId: cmd.protocolId,
  });
  const receiptId = nutritionOperationReceiptIdV1({
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
  });
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);

  const early = await resolveDurableReceipt({
    deps,
    dogId: cmd.dogId,
    actorUid: actor.uid,
    operationType: opType,
    operationId: cmd.idempotencyKey,
    fingerprint,
  });
  if (early !== "missing") {
    return early;
  }

  const serverNow = deps.serverNow();
  assertNotFuture(cmd.administeredAt, serverNow, "administeredAt");

  const logId = supplementLogIdV1({
    actorUid: actor.uid,
    dogId: cmd.dogId,
    idempotencyKey: cmd.idempotencyKey,
  });
  const isAdmin = await Promise.resolve(deps.isAdmin(actor));
  const recordedBy = recordedByPayload(actor, isAdmin);

  return deps.runTransaction(async (tx) => {
    const opSnap = await tx.get(receiptPath);
    const recheck = await resolveDurableReceipt({
      deps,
      dogId: cmd.dogId,
      actorUid: actor.uid,
      operationType: opType,
      operationId: cmd.idempotencyKey,
      fingerprint,
      snap: opSnap,
    });
    if (recheck !== "missing") {
      return recheck;
    }

    // Plano: autoridade transacional
    // - nutritionPlanId presente → plano deve existir
    // - + regimen → regimen ∈ plan.supplements
    if (cmd.nutritionPlanId) {
      const planSnap = await tx.get(
        pathNutritionPlan(cmd.dogId, cmd.nutritionPlanId),
      );
      const plan = planFromTxnSnap(cmd.dogId, cmd.nutritionPlanId, planSnap);
      if (cmd.supplementRegimenId) {
        const found = plan.supplements.some(
          (s) => s.id === cmd.supplementRegimenId,
        );
        if (!found) {
          throw nutritionError(
            "not-found",
            "supplementRegimenId não existe no plano informado.",
            "supplement_regimen_not_found",
          );
        }
      }
    }

    const logPath = pathSupp(cmd.dogId, logId);
    const logSnap = await tx.get(logPath);

    const decision = decideCreateByFingerprint({
      docExists: logSnap.exists,
      storedFingerprint: logSnap.exists ?
        readStoredFingerprint(logSnap.data) :
        undefined,
      requestFingerprint: fingerprint,
    });
    if (decision.kind === "error") {
      throw nutritionError(decision.code, decision.message, decision.detailCode);
    }
    if (decision.kind === "noop") {
      const rev = Number(logSnap.data.revision ?? 1);
      const result: JsonMap = {
        dogId: cmd.dogId,
        logId,
        revision: rev,
        wasNoOp: true,
      };
      safeSet(
        tx,
        receiptPath,
        durableReceiptPayload({
          receiptId,
          operationId: cmd.idempotencyKey,
          operationType: opType,
          actorUid: actor.uid,
          fingerprint,
          entityType: "supplement_log",
          entityId: logId,
          result,
          serverNow,
        }),
      );
      return {
        dogId: cmd.dogId,
        entityId: logId,
        entityType: "supplement_log" as const,
        revision: rev,
        wasNoOp: true,
      };
    }

    const revision = 1;
    const record: JsonMap = {
      supplement_name: cmd.supplementName,
      dose: cmd.dose,
      unit: cmd.unit,
      administered_at: iso(cmd.administeredAt),
      nutrition_plan_id: cmd.nutritionPlanId,
      supplement_regimen_id: cmd.supplementRegimenId,
      notes: cmd.notes,
      batch_number: cmd.batchNumber,
      protocol_id: cmd.protocolId,
      recorded_by: recordedBy,
      recorded_at: iso(serverNow),
      schema_version: NUTRITION_SCHEMA_VERSION,
      revision,
      source: "mobile_callable",
      create_fingerprint: fingerprint,
      create_operation_id: cmd.idempotencyKey,
    };
    const result: JsonMap = {
      dogId: cmd.dogId,
      logId,
      revision,
      wasNoOp: false,
    };

    safeSet(tx, logPath, record);
    safeSet(
      tx,
      receiptPath,
      durableReceiptPayload({
        receiptId,
        operationId: cmd.idempotencyKey,
        operationType: opType,
        actorUid: actor.uid,
        fingerprint,
        entityType: "supplement_log",
        entityId: logId,
        result,
        serverNow,
      }),
    );
    safeSet(
      tx,
      pathAudit(
        auditId(cmd.dogId, logId, opType, `${actor.uid}|${cmd.idempotencyKey}`),
      ),
      auditPayload(
        actor,
        "health.nutrition.supplement_log.create",
        "supplement_log",
        logId,
        logPath,
        cmd.dogId,
        "Create SupplementLog",
        serverNow,
      ),
    );

    return {
      dogId: cmd.dogId,
      entityId: logId,
      entityType: "supplement_log" as const,
      revision,
      wasNoOp: false,
    };
  });
}

// ── NutritionPlan administrative mutations ─────────────────────────────────

function requirePlanTxnReaders(tx: NutritionTxn): Required<Pick<NutritionTxn,
  "getActivePlans" | "getMealLogsInWindow" | "getSupplementLogsInWindow">> {
  if (!tx.getActivePlans || !tx.getMealLogsInWindow || !tx.getSupplementLogsInWindow) {
    throw nutritionError("integrity", "Adapter transacional de NutritionPlan incompleto.", "internal-integrity-error");
  }
  return {
    getActivePlans: tx.getActivePlans,
    getMealLogsInWindow: tx.getMealLogsInWindow,
    getSupplementLogsInWindow: tx.getSupplementLogsInWindow,
  };
}

function planResultFromReceipt(data: JsonMap, dogId: string): NutritionPlanMutationResult {
  assertReceiptShape(data);
  const result = data.result as JsonMap;
  const storedPlanId = stringValue(data.entity_id) ?? stringValue(result.planId);
  const status = stringValue(result.status);
  const revision = Number(result.revision);
  if (!storedPlanId || (status !== "active" && status !== "cancelled") || !Number.isInteger(revision)) {
    throw nutritionError("integrity", "Receipt de NutritionPlan malformado.", "receipt-integrity");
  }
  return {
    dogId,
    planId: storedPlanId,
    status,
    revision,
    wasNoOp: true,
    supersededPlanId: result.supersededPlanId === null ? null : stringValue(result.supersededPlanId),
  };
}

async function resolvePlanReceipt(params: {
  deps: NutritionEngineDeps; dogId: string; actorUid: string;
  operationType: NutritionOperationType; operationId: string; fingerprint: string;
  snap?: TxDocSnap;
}): Promise<"missing" | NutritionPlanMutationResult> {
  const receiptId = nutritionOperationReceiptIdV1(params);
  const snap = params.snap ?? await params.deps.getDoc(pathNutritionOperation(params.dogId, receiptId));
  if (!snap.exists) return "missing";
  assertReceiptShape(snap.data);
  if (stringValue(snap.data.receipt_id) !== receiptId ||
      stringValue(snap.data.operation_id) !== params.operationId ||
      stringValue(snap.data.entity_type) !== "nutrition_plan") {
    throw nutritionError("integrity", "Receipt de NutritionPlan inconsistente.", "receipt-integrity");
  }
  const match = matchNutritionReceipt({
    receiptExists: true,
    storedActorUid: stringValue(snap.data.actor_uid),
    storedOperationType: stringValue(snap.data.operation_type) as NutritionOperationType | undefined,
    storedFingerprint: stringValue(snap.data.fingerprint),
    actorUid: params.actorUid,
    operationType: params.operationType,
    fingerprint: params.fingerprint,
  });
  if (match === "replay") return planResultFromReceipt(snap.data, params.dogId);
  if (match === "idempotency-conflict") {
    throw nutritionError("idempotency-conflict", "operationId reutilizada com payload diferente.", "idempotency-conflict");
  }
  return "missing";
}

function planReceiptPayload(params: {
  receiptId: string; operationId: string; operationType: NutritionOperationType;
  actorUid: string; fingerprint: string; planId: string; result: JsonMap; serverNow: Date;
}): JsonMap {
  return {
    receipt_id: params.receiptId,
    operation_id: params.operationId,
    operation_type: params.operationType,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    entity_type: "nutrition_plan",
    entity_id: params.planId,
    result: params.result,
    processed_at: params.serverNow,
  };
}

function activePlanIntegrity(active: Array<{id: string; data: JsonMap}>): void {
  if (active.length > 1) {
    throw nutritionError("integrity", "Mais de um NutritionPlan active.", "integrity-conflict");
  }
}

function hasExecutionInWindow(
  docs: Array<{id: string; data: JsonMap}>, field: string, start: Date, end: Date,
): boolean {
  for (const doc of docs) {
    let instant: Date;
    try {
      instant = parseInstant(doc.data[field], `${field}:${doc.id}`);
    } catch {
      throw nutritionError("integrity", `Registro nutricional com ${field} malformado.`, "retroactive-plan-conflict");
    }
    if (instant.getTime() >= start.getTime() && instant.getTime() < end.getTime()) return true;
  }
  return false;
}

function planRevision(data: JsonMap): number {
  const revision = Number(data.revision);
  if (!Number.isInteger(revision) || revision < 1) {
    throw nutritionError("integrity", "NutritionPlan com revision inválida.", "internal-integrity-error");
  }
  return revision;
}

function assertActiveTarget(planIdValue: string, target: TxDocSnap, active: Array<{id: string; data: JsonMap}>): JsonMap {
  if (!target.exists) throw nutritionError("not-found", "NutritionPlan não encontrado.", "plan-not-found");
  const status = stringValue(target.data.status);
  if (status === "cancelled") throw nutritionError("already-cancelled", "NutritionPlan já cancelado.", "already-cancelled");
  if (status !== "active") throw nutritionError("failed-precondition", "NutritionPlan não está active.", "invalid-lifecycle");
  activePlanIntegrity(active);
  if (active.length !== 1 || active[0].id !== planIdValue) {
    throw nutritionError("integrity", "Plano alvo não corresponde ao único active.", "integrity-conflict");
  }
  return target.data;
}

function assertExpectedRevision(data: JsonMap, expected: number): number {
  const current = planRevision(data);
  if (current !== expected) {
    throw nutritionError("failed-precondition", "Revision desatualizada.", "revision-conflict");
  }
  return current;
}

function planAudit(actor: NutritionActor, action: string, dogId: string, planIdValue: string,
  operationType: NutritionOperationType, operationId: string, serverNow: Date, metadata: JsonMap): JsonMap {
  return {
    ...auditPayload(actor, action, "nutrition_plan", planIdValue,
      pathNutritionPlan(dogId, planIdValue), dogId, action, serverNow),
    metadata: {dog_id: dogId, operation_type: operationType, operation_id: operationId, source: "web", ...metadata},
  };
}

export async function runCreateAndActivateNutritionPlan(
  actor: NutritionActor, rawCommand: Record<string, unknown>, deps: NutritionEngineDeps,
): Promise<NutritionPlanMutationResult> {
  const serverNow = deps.serverNow();
  const cmd = parseCreateAndActivateNutritionPlan(rawCommand, serverNow);
  const operationType: NutritionOperationType = "create_nutrition_plan";
  const fingerprint = planFingerprint({operationType, dogId: cmd.dogId, planData: cmd.planData,
    structuralFingerprint: fingerprintNutritionPlan(cmd.planData)});
  const receiptId = nutritionOperationReceiptIdV1({actorUid: actor.uid, operationType, operationId: cmd.operationId});
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);
  const newPlanId = planId(actor.uid, cmd.operationId);
  const audit = auditId(cmd.dogId, newPlanId, operationType, `${actor.uid}|${cmd.operationId}`);
  const replay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid, operationType,
    operationId: cmd.operationId, fingerprint});
  if (replay !== "missing") return replay;
  const recordedBy = recordedByPayload(actor, await deps.isAdmin(actor));
  const validFrom = parseInstant(cmd.planData.valid_from, "valid_from");

  return deps.runTransaction(async (tx) => {
    const readers = requirePlanTxnReaders(tx);
    const receiptSnap = await tx.get(receiptPath);
    const active = await readers.getActivePlans(cmd.dogId);
    let mealLogs: Array<{id: string; data: JsonMap}> = [];
    let supplementLogs: Array<{id: string; data: JsonMap}> = [];
    if (validFrom.getTime() < serverNow.getTime()) {
      mealLogs = await readers.getMealLogsInWindow(cmd.dogId, validFrom, serverNow);
      supplementLogs = await readers.getSupplementLogsInWindow(cmd.dogId, validFrom, serverNow);
    }
    const txReplay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid,
      operationType, operationId: cmd.operationId, fingerprint, snap: receiptSnap});
    if (txReplay !== "missing") return txReplay;
    activePlanIntegrity(active);
    if (hasExecutionInWindow(mealLogs, "fed_at", validFrom, serverNow) ||
        hasExecutionInWindow(supplementLogs, "administered_at", validFrom, serverNow)) {
      throw nutritionError("failed-precondition", "Execução nutricional já existe na janela retroativa.", "retroactive-plan-conflict");
    }
    const previous = active[0];
    if (previous) {
      const previousFrom = parseInstant(previous.data.valid_from, "active.valid_from");
      if (validFrom.getTime() <= previousFrom.getTime()) {
        throw nutritionError("validation", "Novo valid_from deve ser posterior ao plano active.", "invalid-validity-window");
      }
    }
    const supersededPlanId = previous?.id ?? null;
    if (previous) {
      safeSet(tx, pathNutritionPlan(cmd.dogId, previous.id), {
        ...previous.data, status: "superseded", valid_until: validFrom,
        revision: planRevision(previous.data) + 1, updated_at: serverNow,
      });
    }
    const newPlan: JsonMap = {
      ...cmd.planData,
      valid_from: validFrom,
      valid_until: cmd.planData.valid_until ? parseInstant(cmd.planData.valid_until, "valid_until") : null,
      status: "active", revision: 1, schema_version: 1, recorded_by: recordedBy,
      created_at: serverNow, updated_at: serverNow,
    };
    const result: JsonMap = {success: true, planId: newPlanId, status: "active", revision: 1, supersededPlanId};
    safeSet(tx, pathNutritionPlan(cmd.dogId, newPlanId), newPlan);
    safeSet(tx, receiptPath, planReceiptPayload({receiptId, operationId: cmd.operationId, operationType,
      actorUid: actor.uid, fingerprint, planId: newPlanId, result, serverNow}));
    safeSet(tx, pathAudit(audit), planAudit(actor, "create_and_activate_nutrition_plan", cmd.dogId,
      newPlanId, operationType, cmd.operationId, serverNow, {revision: 1, superseded_plan_id: supersededPlanId}));
    return {dogId: cmd.dogId, planId: newPlanId, status: "active", revision: 1,
      wasNoOp: false, supersededPlanId};
  });
}

export async function runUpdateActiveNutritionPlan(
  actor: NutritionActor, rawCommand: Record<string, unknown>, deps: NutritionEngineDeps,
): Promise<NutritionPlanMutationResult> {
  const cmd = parseUpdateActiveNutritionPlan(rawCommand);
  const serverNow = deps.serverNow();
  const operationType: NutritionOperationType = "update_nutrition_plan";
  const fingerprint = planFingerprint({operationType, ...cmd});
  const receiptId = nutritionOperationReceiptIdV1({actorUid: actor.uid, operationType, operationId: cmd.operationId});
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);
  const audit = auditId(cmd.dogId, cmd.planId, operationType, `${actor.uid}|${cmd.operationId}`);
  const replay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid, operationType,
    operationId: cmd.operationId, fingerprint});
  if (replay !== "missing") return replay;
  return deps.runTransaction(async (tx) => {
    const readers = requirePlanTxnReaders(tx);
    const receiptSnap = await tx.get(receiptPath);
    const target = await tx.get(pathNutritionPlan(cmd.dogId, cmd.planId));
    const active = await readers.getActivePlans(cmd.dogId);
    const txReplay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid, operationType,
      operationId: cmd.operationId, fingerprint, snap: receiptSnap});
    if (txReplay !== "missing") return txReplay;
    const currentData = assertActiveTarget(cmd.planId, target, active);
    const currentRevision = assertExpectedRevision(currentData, cmd.expectedRevision);
    const nextRevision = currentRevision + 1;
    const changedFields = Object.keys(cmd.planData);
    const result: JsonMap = {success: true, planId: cmd.planId, status: "active", revision: nextRevision};
    safeSet(tx, pathNutritionPlan(cmd.dogId, cmd.planId), {...currentData, ...cmd.planData,
      revision: nextRevision, updated_at: serverNow});
    safeSet(tx, receiptPath, planReceiptPayload({receiptId, operationId: cmd.operationId, operationType,
      actorUid: actor.uid, fingerprint, planId: cmd.planId, result, serverNow}));
    safeSet(tx, pathAudit(audit), planAudit(actor, "update_active_nutrition_plan", cmd.dogId, cmd.planId,
      operationType, cmd.operationId, serverNow, {previous_revision: currentRevision,
        revision: nextRevision, changed_fields: changedFields}));
    return {dogId: cmd.dogId, planId: cmd.planId, status: "active", revision: nextRevision, wasNoOp: false};
  });
}

export async function runCancelNutritionPlan(
  actor: NutritionActor, rawCommand: Record<string, unknown>, deps: NutritionEngineDeps,
): Promise<NutritionPlanMutationResult> {
  const cmd = parseCancelNutritionPlan(rawCommand);
  const serverNow = deps.serverNow();
  const operationType: NutritionOperationType = "cancel_nutrition_plan";
  const fingerprint = planFingerprint({operationType, ...cmd});
  const receiptId = nutritionOperationReceiptIdV1({actorUid: actor.uid, operationType, operationId: cmd.operationId});
  const receiptPath = pathNutritionOperation(cmd.dogId, receiptId);
  const audit = auditId(cmd.dogId, cmd.planId, operationType, `${actor.uid}|${cmd.operationId}`);
  const replay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid, operationType,
    operationId: cmd.operationId, fingerprint});
  if (replay !== "missing") return replay;
  return deps.runTransaction(async (tx) => {
    const readers = requirePlanTxnReaders(tx);
    const receiptSnap = await tx.get(receiptPath);
    const target = await tx.get(pathNutritionPlan(cmd.dogId, cmd.planId));
    const active = await readers.getActivePlans(cmd.dogId);
    const txReplay = await resolvePlanReceipt({deps, dogId: cmd.dogId, actorUid: actor.uid, operationType,
      operationId: cmd.operationId, fingerprint, snap: receiptSnap});
    if (txReplay !== "missing") return txReplay;
    const currentData = assertActiveTarget(cmd.planId, target, active);
    const currentRevision = assertExpectedRevision(currentData, cmd.expectedRevision);
    const nextRevision = currentRevision + 1;
    const result: JsonMap = {success: true, planId: cmd.planId, status: "cancelled", revision: nextRevision};
    safeSet(tx, pathNutritionPlan(cmd.dogId, cmd.planId), {...currentData, status: "cancelled",
      valid_until: serverNow, revision: nextRevision, updated_at: serverNow});
    safeSet(tx, receiptPath, planReceiptPayload({receiptId, operationId: cmd.operationId, operationType,
      actorUid: actor.uid, fingerprint, planId: cmd.planId, result, serverNow}));
    safeSet(tx, pathAudit(audit), planAudit(actor, "cancel_nutrition_plan", cmd.dogId, cmd.planId,
      operationType, cmd.operationId, serverNow, {previous_revision: currentRevision,
        revision: nextRevision, reason: cmd.reason}));
    return {dogId: cmd.dogId, planId: cmd.planId, status: "cancelled", revision: nextRevision, wasNoOp: false};
  });
}
