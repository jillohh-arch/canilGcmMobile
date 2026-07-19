/**
 * Callables Nutrição Health v1 — Fase 5D Gate 2.
 *
 * Ordem externa (obrigatória):
 * 1. auth
 * 2. health.create
 * 3. dog access
 * 4. actor resolution
 * 5. engine (receipt-first interno)
 *
 * Admin SDK writes; zero dual-write legado; zero Rules neste gate.
 */
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  NutritionActor,
  NutritionEngineDeps,
  NutritionMutationResult,
  runCreateAdhocMealLog,
  runCreatePlannedMealLog,
  runCreateSupplementLog,
} from "./health_nutrition_engine";
import {createNutritionFirestoreEngineDeps} from "./health_nutrition_firestore_adapter";
import {
  stringValue,
} from "./health_nutrition_logic";

export type JsonMap = Record<string, unknown>;

export interface HealthNutritionCallableDeps {
  db: FirebaseFirestore.Firestore;
  requireHealthCreate: (
    auth: CallableRequest["auth"],
  ) => Promise<NutritionActor>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: NutritionActor,
    dogId: string,
    dog: JsonMap,
  ) => Promise<void>;
  /** Autoridade admin real (token admin ou accessLevel admin). */
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: NutritionActor,
  ) => Promise<boolean>;
  /**
   * Opcional: injeta engine deps (testes unitários com fake store).
   * Produção: adapter Admin Firestore.
   */
  createEngineDeps?: (opts: {
    isAdmin: (actor: NutritionActor) => boolean | Promise<boolean>;
  }) => NutritionEngineDeps;
}

function appError(
  http:
    | "invalid-argument"
    | "not-found"
    | "permission-denied"
    | "failed-precondition"
    | "unauthenticated"
    | "already-exists"
    | "aborted"
    | "internal",
  code: string,
  message: string,
): never {
  throw new HttpsError(http, message, {code});
}

/**
 * HttpsError cross-bundle safe (paridade Agenda / Emulator dual package).
 */
function isHttpsError(err: unknown): err is HttpsError {
  if (!err || typeof err !== "object") return false;
  const e = err as {name?: string; code?: string; httpErrorCode?: unknown};
  return (
    e.name === "HttpsError" ||
    (typeof e.code === "string" && e.httpErrorCode !== undefined)
  );
}

/**
 * NutritionMutationError / logicError → HttpsError.
 * Preferência: consistência com Agenda (conflict/idempotency → failed-precondition),
 * com details.code estáveis para o cliente.
 */
export function mapNutritionError(err: unknown): never {
  if (isHttpsError(err)) throw err;

  const e = err as Error & {appCode?: string; detailCode?: string};
  const appCode = e.appCode ?? "unexpected";
  const detail = e.detailCode ?? appCode;
  const message = e.message || "Falha na operação de nutrição.";

  switch (appCode) {
  case "validation":
    appError("invalid-argument", detail, message);
    break;
  case "permission-denied":
    appError("permission-denied", detail, message);
    break;
  case "not-found":
    appError("not-found", detail, message);
    break;
  case "unauthenticated":
    appError("unauthenticated", detail, message);
    break;
  case "idempotency-conflict":
    // Agenda: failed-precondition + code; Gate 2 aceita already-exists —
    // mantemos paridade Agenda com details.code = idempotency_conflict.
    appError("failed-precondition", detail || "idempotency_conflict", message);
    break;
  case "conflict":
  case "already-completed":
  case "already-cancelled":
  case "invalid-transition":
  case "integrity":
  case "failed-precondition":
    appError("failed-precondition", detail, message);
    break;
  default:
    appError("internal", "unexpected", message);
  }
}

function assertDocumentId(id: string, label: string): void {
  if (!id || id.includes("/") || id.length > 128) {
    appError("invalid-argument", "validation", `${label} inválido.`);
  }
}

function requireDogId(data: JsonMap): string {
  const dogId = stringValue(data.dogId) ?? stringValue(data.dog_id);
  if (!dogId) {
    appError("invalid-argument", "validation", "dogId é obrigatório.");
  }
  assertDocumentId(dogId, "dogId");
  return dogId;
}

/**
 * Campos server-authoritative / injection — rejeitar explicitamente
 * (paridade Agenda rejectInjection + Gate 1 forbidden).
 */
function rejectServerAuthoritativeInjection(data: JsonMap): void {
  const forbidden = [
    "recorded_by",
    "recordedBy",
    "recorded_at",
    "recordedAt",
    "schema_version",
    "schemaVersion",
    "revision",
    "create_fingerprint",
    "createFingerprint",
    "entity_semantic_fingerprint",
    "entitySemanticFingerprint",
    "receipt_id",
    "receiptId",
    "actor",
    "user_name",
    "userName",
    "role",
    "internal_role",
    "internalRole",
    "source",
    "create_operation_id",
    "createOperationId",
  ];
  for (const key of forbidden) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      appError(
        "invalid-argument",
        "validation",
        `Campo não permitido no payload: ${key}.`,
      );
    }
  }
}

function rejectPlannedTransportExtras(data: JsonMap): void {
  const forbidden = [
    "period",
    "scheduled_for",
    "scheduledFor",
    "meal_occurrence_id",
    "mealOccurrenceId",
    "local_service_date",
    "localServiceDate",
    "prescription_amount_at_time",
    "prescriptionAmountAtTime",
  ];
  for (const key of forbidden) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      appError(
        "invalid-argument",
        "validation",
        `Campo não permitido no payload planned: ${key}.`,
      );
    }
  }
}

function rejectAdhocTransportExtras(data: JsonMap): void {
  const forbidden = [
    "plan_id",
    "planId",
    "planned_meal_id",
    "plannedMealId",
    "meal_occurrence_id",
    "mealOccurrenceId",
    "scheduled_for",
    "scheduledFor",
    "prescription_amount_at_time",
    "prescriptionAmountAtTime",
  ];
  for (const key of forbidden) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      appError(
        "invalid-argument",
        "validation",
        `Campo não permitido no payload adhoc: ${key}.`,
      );
    }
  }
}

async function loadDog(
  db: FirebaseFirestore.Firestore,
  dogId: string,
): Promise<JsonMap> {
  const snap = await db.collection("dogs").doc(dogId).get();
  if (!snap.exists) {
    appError("not-found", "not-found", "K9 não encontrado.");
  }
  return (snap.data() ?? {}) as JsonMap;
}

function mealResponse(result: NutritionMutationResult): JsonMap {
  return {
    dog_id: result.dogId,
    meal_id: result.entityId,
    revision: result.revision,
    was_no_op: result.wasNoOp,
    meal_occurrence_id:
      result.mealOccurrenceId === undefined ? null : result.mealOccurrenceId,
    // espelho camelCase (paridade Agenda / clientes mistos)
    dogId: result.dogId,
    mealId: result.entityId,
    wasNoOp: result.wasNoOp,
    mealOccurrenceId:
      result.mealOccurrenceId === undefined ? null : result.mealOccurrenceId,
  };
}

function supplementResponse(result: NutritionMutationResult): JsonMap {
  return {
    dog_id: result.dogId,
    supplement_log_id: result.entityId,
    revision: result.revision,
    was_no_op: result.wasNoOp,
    dogId: result.dogId,
    supplementLogId: result.entityId,
    wasNoOp: result.wasNoOp,
  };
}

function resolveMode(data: JsonMap): "planned" | "adhoc" {
  const mode = stringValue(data.mode);
  if (mode !== "planned" && mode !== "adhoc") {
    appError(
      "invalid-argument",
      "validation",
      'mode é obrigatório e deve ser "planned" ou "adhoc".',
    );
  }
  return mode;
}

function buildEngineDeps(
  deps: HealthNutritionCallableDeps,
  auth: CallableRequest["auth"],
  caller: NutritionActor,
): NutritionEngineDeps {
  const isAdmin = async (actor: NutritionActor) => {
    // engine passa o mesmo actor resolvido
    void actor;
    return deps.isAdministrativeAuthority(auth, caller);
  };
  if (deps.createEngineDeps) {
    return deps.createEngineDeps({isAdmin});
  }
  return createNutritionFirestoreEngineDeps(deps.db, {isAdmin});
}

/**
 * healthNutritionCreateMealLog — modos planned | adhoc (discriminador explícito).
 */
export async function runHealthNutritionCreateMealLog(
  request: CallableRequest,
  deps: HealthNutritionCallableDeps,
): Promise<JsonMap> {
  try {
    // 1–2. auth + health.create (helper existente via deps)
    const caller = await deps.requireHealthCreate(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerAuthoritativeInjection(data);

    const mode = resolveMode(data);
    const dogId = requireDogId(data);

    // 3. dog access (antes do engine / receipt)
    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);

    // 4. actor = caller (server-authoritative; nada do payload)
    // 5. engine
    const engineDeps = buildEngineDeps(deps, request.auth, caller);

    if (mode === "planned") {
      rejectPlannedTransportExtras(data);
      const result = await runCreatePlannedMealLog(caller, data, engineDeps);
      return mealResponse(result);
    }

    rejectAdhocTransportExtras(data);
    const result = await runCreateAdhocMealLog(caller, data, engineDeps);
    return mealResponse(result);
  } catch (err) {
    mapNutritionError(err);
  }
}

/**
 * healthNutritionCreateSupplementLog
 */
export async function runHealthNutritionCreateSupplementLog(
  request: CallableRequest,
  deps: HealthNutritionCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthCreate(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectServerAuthoritativeInjection(data);

    const dogId = requireDogId(data);
    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);

    const engineDeps = buildEngineDeps(deps, request.auth, caller);
    const result = await runCreateSupplementLog(caller, data, engineDeps);
    return supplementResponse(result);
  } catch (err) {
    mapNutritionError(err);
  }
}
