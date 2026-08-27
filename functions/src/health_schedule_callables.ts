/**
 * Callables da Agenda Preventiva (Fase 4E Gate 2 — receipts + fingerprints).
 * Admin SDK (bypass Rules). Client writes continuam negados.
 */
import * as crypto from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  AppErrorCode,
  HEALTH_SCHEDULE_SCHEMA_VERSION,
  OperationReceiptResult,
  OperationType,
  UpdatePatch,
  assertCancelReason,
  assertScheduleType,
  assertScheduledForNotInPast,
  assertTimezone,
  assertTitle,
  createIdempotencyMaterial,
  decideCancel,
  decideComplete,
  decideCreateManual,
  decideUpdateOpen,
  deterministicManualScheduleId,
  fingerprintCancel,
  fingerprintComplete,
  fingerprintCreateIntent,
  fingerprintUpdatePatch,
  initialRevision,
  isAutomaticSource,
  isManualSource,
  matchOperationReceipt,
  nextRevision,
  normalizeOperationId,
  optionalNotes,
  parseExpectedRevision,
  parseUpdatePatch,
  readLifecycle,
  readRevision,
  recordedByPayload,
  stringValue,
} from "./health_schedule_logic";

type JsonMap = Record<string, unknown>;

export interface ScheduleCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface HealthScheduleCallableDeps {
  db: FirebaseFirestore.Firestore;
  requireHealthCreate: (
    auth: CallableRequest["auth"],
  ) => Promise<ScheduleCaller>;
  requireHealthEdit: (
    auth: CallableRequest["auth"],
  ) => Promise<ScheduleCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: ScheduleCaller,
    dogId: string,
    dog: JsonMap,
  ) => Promise<void>;
  /** Autoridade admin real (token admin ou accessLevel admin). */
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: ScheduleCaller,
  ) => Promise<boolean>;
}

function appError(
  http:
    | "invalid-argument"
    | "not-found"
    | "permission-denied"
    | "failed-precondition"
    | "unauthenticated"
    | "internal",
  code: AppErrorCode,
  message: string,
): never {
  throw new HttpsError(http, message, {code});
}

/**
 * HttpsError cross-bundle safe check (evita falha de `instanceof` no worker
 * do Emulator/Functions quando há dual package hazard).
 */
function isHttpsError(err: unknown): err is HttpsError {
  if (!err || typeof err !== "object") return false;
  const e = err as {name?: string; code?: string; httpErrorCode?: unknown};
  return e.name === "HttpsError" ||
    (typeof e.code === "string" && e.httpErrorCode !== undefined);
}

function mapLogicError(err: unknown): never {
  if (isHttpsError(err)) throw err;
  const e = err as Error & {appCode?: AppErrorCode};
  const code = e.appCode ?? "unexpected";
  const message = e.message || "Falha na operação de agenda.";
  switch (code) {
  case "validation":
    appError("invalid-argument", code, message);
    break;
  case "permission-denied":
    appError("permission-denied", code, message);
    break;
  case "not-found":
    appError("not-found", code, message);
    break;
  case "unauthenticated":
    appError("unauthenticated", code, message);
    break;
  case "conflict":
  case "idempotency-conflict":
  case "already-completed":
  case "already-cancelled":
  case "invalid-transition":
  case "integrity":
    appError("failed-precondition", code, message);
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

/**
 * Extrai o dogId da requisição.
 *
 * Autoridade: o dogId é DERIVADO DO PATH da operação (callable), nunca do
 * payload do cliente. O campo `dog_id` no payload é IGNORADO — ele é gravado
 * pelo servidor na criação e não pode ser fornecido pelo cliente.
 *
 * Comportamento:
 * - `dogId` presente: usa como autoridade, ignora `dog_id` se consistente.
 * - `dogId` presente + `dog_id` divergente: rejeita (sobrescrita proibida).
 * - `dogId` ausente + `dog_id` presente: rejeita (cliente não fornece dog_id).
 * - ambos ausentes: rejeita.
 */
function requireDogId(data: JsonMap): string {
  const dogId = stringValue(data.dogId);
  const dogIdFromPayload = stringValue(data.dog_id);

  if (dogIdFromPayload !== undefined && dogId !== dogIdFromPayload) {
    appError(
      "invalid-argument",
      "validation",
      "dog_id não pode sobrescrever a autoridade de dogId.",
    );
  }

  if (!dogId) {
    appError("invalid-argument", "validation", "dogId é obrigatório.");
  }
  assertDocumentId(dogId, "dogId");
  return dogId;
}

function requireScheduleId(data: JsonMap): string {
  const scheduleId =
    stringValue(data.scheduleId) ?? stringValue(data.schedule_id);
  if (!scheduleId) {
    appError("invalid-argument", "validation", "scheduleId é obrigatório.");
  }
  assertDocumentId(scheduleId, "scheduleId");
  return scheduleId;
}

function parseScheduledFor(raw: unknown): Timestamp {
  if (raw instanceof Timestamp) return raw;
  const d = new Date(String(raw ?? ""));
  if (Number.isNaN(d.getTime())) {
    appError("invalid-argument", "validation", "scheduledFor inválido.");
  }
  return Timestamp.fromDate(d);
}

function toIso(ts: Timestamp | Date): string {
  if (ts instanceof Timestamp) return ts.toDate().toISOString();
  return ts.toISOString();
}

function rejectInjection(data: JsonMap): void {
  const forbidden = [
    "source_type",
    "sourceType",
    "source_id",
    "sourceId",
    "case_id",
    "caseId",
    "lifecycle_status",
    "lifecycleStatus",
    "recorded_by",
    "recordedBy",
    "completed_at",
    "completedAt",
    "completed_by",
    "completedBy",
    "cancelled_at",
    "cancelledAt",
    "cancelled_by",
    "cancelledBy",
    "created_at",
    "createdAt",
    "schema_version",
    "schemaVersion",
    "revision",
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

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

/** Audit canônico determinístico por operação (sem duplicar em replay). */
function auditDocId(
  dogId: string,
  scheduleId: string,
  operationType: OperationType,
  operationId: string,
): string {
  const h = sha256Hex(
    `${dogId}|${scheduleId}|${operationType}|${operationId}`,
  );
  return `hs_audit_${h.slice(0, 40)}`;
}

function operationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  scheduleId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId)
    .collection("operations")
    .doc(operationId);
}

function receiptPayload(params: {
  operationId: string;
  operationType: OperationType;
  actorUid: string;
  fingerprint: string;
  result: OperationReceiptResult;
}): JsonMap {
  return {
    operation_id: params.operationId,
    operation_type: params.operationType,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    result: params.result,
    processed_at: FieldValue.serverTimestamp(),
  };
}

function auditLogPayload(
  caller: ScheduleCaller,
  action: string,
  dogId: string,
  scheduleId: string,
  summary: string,
  metadata?: JsonMap,
): JsonMap {
  const now = FieldValue.serverTimestamp();
  return {
    action,
    entity_type: "health_schedule",
    entity_id: scheduleId,
    entity_path: `dogs/${dogId}/health_schedule/${scheduleId}`,
    summary,
    actor: {
      uid: caller.uid,
      email: caller.email,
      ra: caller.ra,
      name: caller.name,
    },
    metadata: {dog_id: dogId, ...(metadata ?? {})},
    source: "functions",
    performed_at: now,
    createdAt: now,
  };
}

function throwDecisionError(code: AppErrorCode, message: string): never {
  const http =
    code === "permission-denied" ? "permission-denied" : "failed-precondition";
  appError(http, code, message);
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

export async function runHealthScheduleCreateManual(
  request: CallableRequest,
  deps: HealthScheduleCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthCreate(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);
    const dogId = requireDogId(data);
    const operationId = normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
      true,
    );
    const scheduleType = assertScheduleType(
      data.scheduleType ?? data.schedule_type,
    );
    const title = assertTitle(data.title);
    const timezone = assertTimezone(data.timezone);
    const scheduledFor = parseScheduledFor(
      data.scheduledFor ?? data.scheduled_for,
    );
    // Autoridade de tempo: relógio do servidor (granularidade minuto UTC).
    assertScheduledForNotInPast(scheduledFor.toDate(), new Date());
    const dueUntilRaw = data.dueUntil ?? data.due_until;
    let dueUntil: Timestamp | null = null;
    if (dueUntilRaw !== undefined && dueUntilRaw !== null && dueUntilRaw !== "") {
      dueUntil = parseScheduledFor(dueUntilRaw);
    }
    const notes = optionalNotes(data.notes) ?? null;
    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const fingerprint = fingerprintCreateIntent({
      dogId,
      scheduleType,
      title,
      scheduledForIso: toIso(scheduledFor),
      dueUntilIso: dueUntil ? toIso(dueUntil) : null,
      timezone,
      notes,
    });

    const material = createIdempotencyMaterial(caller.uid, dogId, operationId);
    const hash = sha256Hex(material);
    const scheduleId = deterministicManualScheduleId(hash);
    const scheduleRef = deps.db
      .collection("dogs")
      .doc(dogId)
      .collection("health_schedule")
      .doc(scheduleId);
    const opRef = operationRef(deps.db, dogId, scheduleId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, scheduleId, "create_manual", operationId));

    return await deps.db.runTransaction(async (tx) => {
      const [existing, opSnap] = await Promise.all([
        tx.get(scheduleRef),
        tx.get(opRef),
      ]);

      if (opSnap.exists) {
        const op = (opSnap.data() ?? {}) as JsonMap;
        const match = matchOperationReceipt({
          receiptExists: true,
          storedActorUid: stringValue(op.actor_uid),
          storedOperationType: stringValue(op.operation_type),
          storedFingerprint: stringValue(op.fingerprint),
          actorUid: caller.uid,
          operationType: "create_manual",
          fingerprint,
        });
        if (match === "replay") {
          const r = (op.result ?? {}) as JsonMap;
          return {
            dogId,
            scheduleId: stringValue(r.scheduleId) ?? scheduleId,
            revision: r.revision ?? readRevision(
              existing.exists ? (existing.data() ?? {}) as JsonMap : {},
            ),
            wasNoOp: true,
            lifecycleStatus: r.lifecycleStatus ?? "open",
          };
        }
        if (match === "idempotency-conflict") {
          throwDecisionError(
            "idempotency-conflict",
            "Mesma idempotencyKey com intenção diferente da criação original.",
          );
        }
      }

      const storedFp =
        existing.exists ?
          stringValue((existing.data() ?? {}).create_fingerprint) :
          undefined;
      const decision = decideCreateManual({
        docExists: existing.exists,
        storedFingerprint: storedFp,
        requestFingerprint: fingerprint,
      });
      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "noop") {
        const ed = (existing.data() ?? {}) as JsonMap;
        return {
          dogId,
          scheduleId,
          revision: readRevision(ed),
          wasNoOp: true,
          lifecycleStatus: readLifecycle(ed),
        };
      }

      const recordedBy = recordedByPayload(caller, isAdmin);
      const revision = initialRevision();
      const record: JsonMap = {
        dog_id: dogId,
        schedule_type: scheduleType,
        title,
        scheduled_for: scheduledFor,
        timezone,
        lifecycle_status: "open",
        source_type: "manual",
        created_at: FieldValue.serverTimestamp(),
        recorded_by: recordedBy,
        schema_version: HEALTH_SCHEDULE_SCHEMA_VERSION,
        revision,
        create_operation_id: operationId,
        create_fingerprint: fingerprint,
      };
      if (dueUntil) record.due_until = dueUntil;
      if (notes) record.notes = notes;

      const result: OperationReceiptResult = {
        scheduleId,
        revision,
        lifecycleStatus: "open",
        wasNoOp: false,
      };

      tx.set(scheduleRef, record);
      tx.set(opRef, {
        ...receiptPayload({
          operationId,
          operationType: "create_manual",
          actorUid: caller.uid,
          fingerprint,
          result,
        }),
        result: {...result, dogId},
      });
      tx.set(
        auditRef,
        auditLogPayload(
          caller,
          "health_schedule_created",
          dogId,
          scheduleId,
          `Item de agenda criado para K9 ${dogId}`,
          {operation_id: operationId, schedule_type: scheduleType},
        ),
      );

      return {
        dogId,
        scheduleId,
        revision,
        wasNoOp: false,
        lifecycleStatus: "open",
      };
    });
  } catch (err) {
    mapLogicError(err);
  }
}

export async function runHealthScheduleUpdateOpen(
  request: CallableRequest,
  deps: HealthScheduleCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthEdit(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    const dogId = requireDogId(data);
    const scheduleId = requireScheduleId(data);
    const operationId = normalizeOperationId(
      data.operationId ?? data.operation_id,
      true,
    );
    const expectedRevision = parseExpectedRevision(
      data.expectedRevision ?? data.expected_revision,
    );
    const patchRaw = (data.patch ?? data) as JsonMap;
    const patchSource: JsonMap = {...patchRaw};
    delete patchSource.dogId;
    delete patchSource.dog_id;
    delete patchSource.scheduleId;
    delete patchSource.schedule_id;
    delete patchSource.operationId;
    delete patchSource.operation_id;
    delete patchSource.expectedRevision;
    delete patchSource.expected_revision;
    delete patchSource.patch;
    const patch: UpdatePatch = parseUpdatePatch(patchSource);
    const fingerprint = fingerprintUpdatePatch(patch);

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);

    const scheduleRef = deps.db
      .collection("dogs")
      .doc(dogId)
      .collection("health_schedule")
      .doc(scheduleId);
    const opRef = operationRef(deps.db, dogId, scheduleId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, scheduleId, "update_open", operationId));

    return await deps.db.runTransaction(async (tx) => {
      const [snap, opSnap] = await Promise.all([
        tx.get(scheduleRef),
        tx.get(opRef),
      ]);
      if (!snap.exists) {
        appError("not-found", "not-found", "Item de agenda não encontrado.");
      }
      const current = (snap.data() ?? {}) as JsonMap;
      const lifecycle = readLifecycle(current);
      const currentRevision = readRevision(current);

      const opData = opSnap.exists ? ((opSnap.data() ?? {}) as JsonMap) : {};
      const receiptMatch = matchOperationReceipt({
        receiptExists: opSnap.exists,
        storedActorUid: stringValue(opData.actor_uid),
        storedOperationType: stringValue(opData.operation_type),
        storedFingerprint: stringValue(opData.fingerprint),
        actorUid: caller.uid,
        operationType: "update_open",
        fingerprint,
      });

      const decision = decideUpdateOpen({
        lifecycle,
        sourceType: current.source_type,
        currentRevision,
        expectedRevision,
        receiptMatch,
      });

      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "noop") {
        const op = (opSnap.data() ?? {}) as JsonMap;
        const r = (op.result ?? {}) as JsonMap;
        return {
          dogId,
          scheduleId,
          revision: (r.revision as number) ?? currentRevision,
          wasNoOp: true,
          lifecycleStatus: lifecycle,
        };
      }

      const newRevision = nextRevision(currentRevision);
      const update: JsonMap = {
        revision: newRevision,
        last_update_operation_id: operationId,
      };
      if (patch.title !== undefined) update.title = patch.title;
      if (patch.scheduledFor !== undefined) {
        update.scheduled_for = Timestamp.fromDate(
          patch.scheduledFor,
        );
      }
      if (patch.dueUntil === null) {
        update.due_until = FieldValue.delete();
      } else if (patch.dueUntil instanceof Date) {
        update.due_until = Timestamp.fromDate(patch.dueUntil);
      }
      if (patch.timezone !== undefined) update.timezone = patch.timezone;
      if (patch.notes === null) {
        update.notes = FieldValue.delete();
      } else if (typeof patch.notes === "string") {
        update.notes = patch.notes;
      }

      const result: OperationReceiptResult = {
        scheduleId,
        revision: newRevision,
        lifecycleStatus: "open",
        wasNoOp: false,
      };

      tx.update(scheduleRef, update);
      tx.set(
        opRef,
        {
          ...receiptPayload({
            operationId,
            operationType: "update_open",
            actorUid: caller.uid,
            fingerprint,
            result,
          }),
          result: {...result, dogId},
        },
      );
      tx.set(
        auditRef,
        auditLogPayload(
          caller,
          "health_schedule_updated",
          dogId,
          scheduleId,
          `Item de agenda atualizado (${scheduleId})`,
          {operation_id: operationId, revision: newRevision},
        ),
      );

      return {
        dogId,
        scheduleId,
        revision: newRevision,
        wasNoOp: false,
        lifecycleStatus: "open",
      };
    });
  } catch (err) {
    mapLogicError(err);
  }
}

export async function runHealthScheduleComplete(
  request: CallableRequest,
  deps: HealthScheduleCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthEdit(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);
    const dogId = requireDogId(data);
    const scheduleId = requireScheduleId(data);
    const operationIdRaw = data.operationId ?? data.operation_id;
    const operationId =
      operationIdRaw === undefined || operationIdRaw === null ||
      String(operationIdRaw).trim() === "" ?
        `complete:${scheduleId}` :
        normalizeOperationId(operationIdRaw, true);

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);
    const fingerprint = fingerprintComplete();

    const scheduleRef = deps.db
      .collection("dogs")
      .doc(dogId)
      .collection("health_schedule")
      .doc(scheduleId);
    const opRef = operationRef(deps.db, dogId, scheduleId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, scheduleId, "complete", operationId));

    return await deps.db.runTransaction(async (tx) => {
      const [snap, opSnap] = await Promise.all([
        tx.get(scheduleRef),
        tx.get(opRef),
      ]);
      if (!snap.exists) {
        appError("not-found", "not-found", "Item de agenda não encontrado.");
      }
      const current = (snap.data() ?? {}) as JsonMap;
      const lifecycle = readLifecycle(current);
      const currentRevision = readRevision(current);

      if (opSnap.exists) {
        const opData = (opSnap.data() ?? {}) as JsonMap;
        const match = matchOperationReceipt({
          receiptExists: true,
          storedActorUid: stringValue(opData.actor_uid),
          storedOperationType: stringValue(opData.operation_type),
          storedFingerprint: stringValue(opData.fingerprint),
          actorUid: caller.uid,
          operationType: "complete",
          fingerprint,
        });
        if (match === "replay") {
          return {
            dogId,
            scheduleId,
            revision: currentRevision,
            wasNoOp: true,
            lifecycleStatus: "completed",
          };
        }
        if (match === "idempotency-conflict") {
          throwDecisionError(
            "idempotency-conflict",
            "operationId colide com receipt de outra operação/ator/intenção.",
          );
        }
      }

      const decision = decideComplete(lifecycle);
      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "noop") {
        // Terminal sem re-auditoria / sem nova revision / sem sobrescrever.
        return {
          dogId,
          scheduleId,
          revision: currentRevision,
          wasNoOp: true,
          lifecycleStatus: "completed",
        };
      }

      const completedBy = recordedByPayload(caller, isAdmin);
      const newRevision = nextRevision(currentRevision);
      const result: OperationReceiptResult = {
        scheduleId,
        revision: newRevision,
        lifecycleStatus: "completed",
        wasNoOp: false,
      };

      tx.update(scheduleRef, {
        lifecycle_status: "completed",
        completed_at: FieldValue.serverTimestamp(),
        completed_by: completedBy,
        revision: newRevision,
        last_lifecycle_operation_id: operationId,
      });
      tx.set(opRef, {
        ...receiptPayload({
          operationId,
          operationType: "complete",
          actorUid: caller.uid,
          fingerprint,
          result,
        }),
        result: {...result, dogId},
      });
      tx.set(
        auditRef,
        auditLogPayload(
          caller,
          "health_schedule_completed",
          dogId,
          scheduleId,
          `Item de agenda concluído (${scheduleId})`,
          {operation_id: operationId},
        ),
      );

      return {
        dogId,
        scheduleId,
        revision: newRevision,
        wasNoOp: false,
        lifecycleStatus: "completed",
      };
    });
  } catch (err) {
    mapLogicError(err);
  }
}

export async function runHealthScheduleCancel(
  request: CallableRequest,
  deps: HealthScheduleCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthEdit(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);
    const dogId = requireDogId(data);
    const scheduleId = requireScheduleId(data);
    const operationId = normalizeOperationId(
      data.operationId ?? data.operation_id,
      true,
    );
    const cancelReason = assertCancelReason(
      data.cancelReason ?? data.cancel_reason,
    );
    const fingerprint = fingerprintCancel(cancelReason);

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const scheduleRef = deps.db
      .collection("dogs")
      .doc(dogId)
      .collection("health_schedule")
      .doc(scheduleId);
    const opRef = operationRef(deps.db, dogId, scheduleId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, scheduleId, "cancel", operationId));

    return await deps.db.runTransaction(async (tx) => {
      const [snap, opSnap] = await Promise.all([
        tx.get(scheduleRef),
        tx.get(opRef),
      ]);
      if (!snap.exists) {
        appError("not-found", "not-found", "Item de agenda não encontrado.");
      }
      const current = (snap.data() ?? {}) as JsonMap;
      const lifecycle = readLifecycle(current);
      const currentRevision = readRevision(current);
      const sourceType = stringValue(current.source_type);

      if (sourceType && isAutomaticSource(sourceType)) {
        if (!isAdmin) {
          appError(
            "permission-denied",
            "permission-denied",
            "Cancelamento de item automático exige autoridade administrativa.",
          );
        }
      } else if (sourceType && !isManualSource(sourceType)) {
        appError(
          "failed-precondition",
          "integrity",
          "source_type desconhecido no item de agenda.",
        );
      }

      const opData = opSnap.exists ? ((opSnap.data() ?? {}) as JsonMap) : {};
      const receiptMatch = matchOperationReceipt({
        receiptExists: opSnap.exists,
        storedActorUid: stringValue(opData.actor_uid),
        storedOperationType: stringValue(opData.operation_type),
        storedFingerprint: stringValue(opData.fingerprint),
        actorUid: caller.uid,
        operationType: "cancel",
        fingerprint,
      });

      const decision = decideCancel({lifecycle, receiptMatch});
      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "noop") {
        return {
          dogId,
          scheduleId,
          revision: currentRevision,
          wasNoOp: true,
          lifecycleStatus: "cancelled",
        };
      }

      const cancelledBy = recordedByPayload(caller, isAdmin);
      const newRevision = nextRevision(currentRevision);
      const result: OperationReceiptResult = {
        scheduleId,
        revision: newRevision,
        lifecycleStatus: "cancelled",
        wasNoOp: false,
      };

      tx.update(scheduleRef, {
        lifecycle_status: "cancelled",
        cancelled_at: FieldValue.serverTimestamp(),
        cancelled_by: cancelledBy,
        cancel_reason: cancelReason,
        revision: newRevision,
        last_lifecycle_operation_id: operationId,
      });
      tx.set(opRef, {
        ...receiptPayload({
          operationId,
          operationType: "cancel",
          actorUid: caller.uid,
          fingerprint,
          result,
        }),
        result: {...result, dogId},
      });
      tx.set(
        auditRef,
        auditLogPayload(
          caller,
          "health_schedule_cancelled",
          dogId,
          scheduleId,
          `Item de agenda cancelado (${scheduleId})`,
          {operation_id: operationId, reason: cancelReason},
        ),
      );

      return {
        dogId,
        scheduleId,
        revision: newRevision,
        wasNoOp: false,
        lifecycleStatus: "cancelled",
      };
    });
  } catch (err) {
    mapLogicError(err);
  }
}
