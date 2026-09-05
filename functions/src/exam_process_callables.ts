/**
 * Callables do ciclo clínico de Exames (F20.EXAM-V1).
 *
 * Agregado canônico: dogs/{dogId}/clinical_cases/{caseId}/exams/{examId}
 * Cada transição gera um ClinicalEvent imutável sob clinical_events.
 * Operações idempotentes via receipt em operations/{operationId}.
 * Admin SDK (bypassa Rules); clientes não escrevem diretamente.
 */

import * as crypto from "crypto";
import {Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  ClinicalDomainError,
  isTerminalCaseStatus,
} from "./clinical_domain";
import {
  applyClinicalCaseTransition,
  assertClinicalCasePrecondition,
  assertClinicalReceiptShape,
  mapClinicalError,
  matchClinicalReceipt,
  parseExpectedRevision,
  receiptPayload,
  rejectServerManagedInjection,
} from "./clinical_case_callables";
import {
  JsonMap,
  assertDogId,
  logicError,
  normalizeOperationId,
  recordedByPayload,
  stableStringify,
  stringValue,
} from "./health_document_logic";

export const EXAM_SCHEMA_VERSION = 1;

/**
 * Canonical receipt discriminators for the Exam request operation
 * (CLINICAL-BE.MERGE-I1 §14). Exam receipts now share the frozen Clinical receipt
 * shape, so `assertClinicalReceiptShape` + `matchClinicalReceipt` can enforce
 * actor_uid AND operation_type AND fingerprint instead of a bare fingerprint
 * compare, which could not tell a replay from a foreign operation.
 */
export const EXAM_REQUEST_KIND = "exam_request_v1";
export const EXAM_REQUEST_OPERATION = "request_exam";

export interface ExamCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface ExamProcessCallableDeps {
  db: FirebaseFirestore.Firestore;
  requireRequestExam: (
    auth: CallableRequest["auth"],
  ) => Promise<ExamCaller>;
  requireRecordClinical: (
    auth: CallableRequest["auth"],
  ) => Promise<ExamCaller>;
  requireInterpretExam: (
    auth: CallableRequest["auth"],
  ) => Promise<ExamCaller>;
  requireManageClinicalCase: (
    auth: CallableRequest["auth"],
  ) => Promise<ExamCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: ExamCaller,
    dogId: string,
    dog: Record<string, unknown>,
  ) => Promise<void>;
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: ExamCaller,
  ) => Promise<boolean>;
  now?: () => Date;
}

export function caseRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("clinical_cases")
    .doc(caseId);
}

export function examRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  examId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("exams").doc(examId);
}

export function clinicalEventRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  eventId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("clinical_events").doc(eventId);
}

export function examOperationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  caseId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return caseRef(db, dogId, caseId).collection("operations").doc(operationId);
}

export function sha256Hex(content: string): string {
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

export function deterministicExamId(
  dogId: string,
  caseId: string,
  operationId: string,
): string {
  const hash = sha256Hex(`exam:${dogId}:${caseId}:${operationId}`).slice(0, 16);
  return `exam_${hash}`;
}

export function deterministicEventId(
  dogId: string,
  caseId: string,
  stage: string,
  operationId: string,
): string {
  const hash = sha256Hex(`event:${dogId}:${caseId}:${stage}:${operationId}`).slice(0, 16);
  return `evt_${hash}`;
}

export function deterministicScheduleId(
  dogId: string,
  examId: string,
): string {
  const hash = sha256Hex(`sched:${dogId}:${examId}`).slice(0, 16);
  return `sch_${hash}`;
}

export function auditDocId(
  dogId: string,
  caseId: string,
  operationId: string,
): string {
  return `audit_exam_${sha256Hex(`${dogId}:${caseId}:${operationId}`).slice(0, 20)}`;
}

async function loadDog(
  db: FirebaseFirestore.Firestore,
  dogId: string,
): Promise<JsonMap> {
  const snap = await db.collection("dogs").doc(dogId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `Cão ${dogId} não encontrado.`);
  }
  return (snap.data() ?? {}) as JsonMap;
}

function parseRequiredString(data: JsonMap, field: string): string {
  const val = stringValue(data[field]);
  if (!val) {
    throw new HttpsError("invalid-argument", `Campo obrigatório ausente: ${field}`);
  }
  return val;
}

/**
 * The caller's MANDATORY optimistic-concurrency precondition on the PARENT
 * ClinicalCase (CLINICAL-BE.MERGE-I1 §14.1, Control Tower override).
 *
 * Requesting an exam can transition the case, so the caller must declare which
 * case revision it believes it is acting on. Absence is `invalid-argument`, never
 * an implicit "whatever is stored" — and there is deliberately NO fallback to 1:
 * a stored case without a revision is corruption (F1.C1), and Firestore's
 * transaction retry is not a substitute for explicit caller intent.
 *
 * Only the "field is missing" message is owned here; the integer rule itself
 * stays single-sourced in `parseExpectedRevision`.
 */
function parseExpectedCaseRevision(raw: unknown): number {
  if (raw === undefined || raw === null) {
    throw logicError(
      "validation",
      "expectedCaseRevision é obrigatório para solicitar um exame.",
    );
  }
  return parseExpectedRevision(raw);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. REQUEST EXAM
// ─────────────────────────────────────────────────────────────────────────────

export const VALID_EXAM_TYPES = new Set([
  "blood_work",
  "imaging",
  "biopsy",
  "culture",
  "parasitology",
  "urinalysis",
  "cardiology",
  "dermatology",
  "ophthalmology",
  "other",
]);

export async function runHealthRequestExam(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  try {
    return await requestExamInternal(request, deps);
  } catch (err) {
    // Only the reused Clinical core communicates through `appCode` /
    // ClinicalDomainError; map those to the frozen client contract
    // (validation → invalid-argument, conflict/integrity/idempotency-conflict →
    // failed-precondition). Everything else — HttpsError raised by the
    // capability/dog-access layer, or an infrastructure failure — must propagate
    // untouched, so this wrapper never reclassifies an error it does not own.
    if (
      err instanceof ClinicalDomainError ||
      (err !== null && typeof err === "object" && "appCode" in err)
    ) {
      mapClinicalError(err);
    }
    throw err;
  }
}

async function requestExamInternal(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRequestExam(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  // Server-managed field protection (§14.7): a client may not smuggle
  // clinical_status, revision, closure/reopen metadata or actor fields. `dog_id`
  // is allow-listed because this callable has always accepted it as the
  // snake_case alias of `dogId` — it is caller identity, not server state.
  rejectServerManagedInjection(data, ["dog_id"]);

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const title = parseRequiredString(data, "title");
  const examType = parseRequiredString(data, "examType");
  if (!VALID_EXAM_TYPES.has(examType)) {
    throw new HttpsError(
      "invalid-argument",
      `Tipo de exame desconhecido ou malformado: ${examType}`,
    );
  }
  const urgency = stringValue(data["urgency"]) ?? "routine";
  const labName = stringValue(data["labName"] ?? data["lab_name"]) ?? null;
  const requestReason = stringValue(data["requestReason"] ?? data["request_reason"]) ?? null;
  const professionalRaw = data["professional"] as JsonMap | undefined;
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);
  const expectedCaseRevision = parseExpectedCaseRevision(
    data["expectedCaseRevision"] ?? data["expected_case_revision"],
  );

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const examId = deterministicExamId(dogId, caseId, operationId);
  const eventId = deterministicEventId(dogId, caseId, "requested", operationId);
  const scheduleId = deterministicScheduleId(dogId, examId);

  const eRef = examRef(deps.db, dogId, caseId, examId);
  const cRef = caseRef(deps.db, dogId, caseId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const schedRef = deps.db
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  // INTENT fingerprint. `expectedCaseRevision` is deliberately EXCLUDED (§14.5):
  // it is a precondition, not intent, so a legitimate replay after a case bump
  // must still be recognised as the same operation.
  const fingerprint = sha256Hex(
    stableStringify({
      action: "request_exam",
      dogId,
      caseId,
      title,
      examType,
      urgency,
      labName,
      requestReason,
      professional: professionalRaw ?? null,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    // REPLAY BEFORE STALE (§14.4): the receipt is resolved before the case is
    // read at all, so a winner replaying with a now-stale token still no-ops.
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const stored = (opSnap.data() ?? {}) as JsonMap;
      assertClinicalReceiptShape(stored, EXAM_REQUEST_KIND, EXAM_REQUEST_OPERATION);
      const match = matchClinicalReceipt({
        receiptExists: true,
        storedActorUid: stringValue(stored["actor_uid"]),
        storedOperationType: stringValue(stored["operation_type"]),
        storedFingerprint: stringValue(stored["fingerprint"]),
        expectedOperationType: EXAM_REQUEST_OPERATION,
        actorUid: caller.uid,
        fingerprint,
      });
      if (match === "idempotency-conflict") {
        // Reused operationId with a different actor, operation type or intent
        // (§14.9, §14.10) — a caller bug, never a race.
        throw logicError(
          "idempotency-conflict",
          `Conflito de idempotência: operationId ${operationId} já utilizado com intent diferente.`,
        );
      }
      if (match === "replay") {
        return (stored["result"] ?? {}) as JsonMap;
      }
    }

    const caseSnap = await tx.get(cRef);
    if (!caseSnap.exists) {
      throw new HttpsError("not-found", `ClinicalCase ${caseId} não encontrado.`);
    }
    const caseData = caseSnap.data() as JsonMap;

    // Stored integrity BEFORE stale, then the MANDATORY OCC precondition.
    // A stored case without a valid `revision` fails closed here as corruption
    // (§14.2) — the old `typeof revision === "number" ? revision : 1` default is
    // gone. A mismatch is a stale/OCC rejection (§14.3).
    const casePrecondition = assertClinicalCasePrecondition(
      caseData,
      expectedCaseRevision,
    );
    if (isTerminalCaseStatus(casePrecondition.status)) {
      throw new HttpsError(
        "failed-precondition",
        `Caso ${caseId} está em estado terminal (${casePrecondition.status}) e não aceita novos exames.`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);

    const examDoc: JsonMap = {
      exam_id: examId,
      case_id: caseId,
      dog_id: dogId,
      exam_type: examType,
      current_stage: "requested",
      title,
      urgency,
      created_at: nowTs,
      requested_at: nowTs,
      recorded_by: recordedBy,
      requested_by: recordedBy,
      schema_version: EXAM_SCHEMA_VERSION,
      revision: 1,
    };
    if (labName) examDoc["lab_name"] = labName;
    if (requestReason) examDoc["request_reason"] = requestReason;
    if (professionalRaw) examDoc["request_professional"] = professionalRaw;

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      exam_id: examId,
      event_type: "exam_request",
      payload_type: "exam_request_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        exam_id: examId,
        exam_type: examType,
        title,
        urgency,
        if_lab_name: labName,
        if_request_reason: requestReason,
      },
      revision: 1,
      schema_version: 1,
    };
    if (professionalRaw) eventDoc["professional"] = professionalRaw;

    // CASE TRANSITION — Option A (§13). `clinical_status` is owned SOLELY by the
    // ClinicalCase lifecycle authority; this writer delegates to that core inside
    // its OWN transaction, so the Exam write and the transition stay atomic and no
    // second transition implementation exists. Not a callable-to-callable call.
    if (casePrecondition.status === "open") {
      applyClinicalCaseTransition({
        tx,
        caseDocRef: cRef,
        storedCase: caseData,
        destination: "under_investigation",
        expectedRevision: expectedCaseRevision,
        nowTimestamp: nowTs,
      });
    }

    // HealthScheduleItem
    const scheduleDoc: JsonMap = {
      dog_id: dogId,
      schedule_type: "exam",
      title: `Exame: ${title}`,
      scheduled_for: nowTs,
      timezone: "America/Sao_Paulo",
      lifecycle_status: "open",
      source_type: "exam_process",
      source_id: examId,
      case_id: caseId,
      created_at: nowTs,
      recorded_by: recordedBy,
      schema_version: 1,
      revision: 1,
    };

    tx.set(eRef, examDoc);
    tx.set(evtRef, eventDoc);
    tx.set(schedRef, scheduleDoc);

    const result: JsonMap = {
      success: true,
      examId,
      eventId,
      scheduleId,
      stage: "requested",
    };

    // Canonical Clinical receipt shape (§14.8): kind + operation_id +
    // operation_type + actor_uid + fingerprint + result, so a later read can
    // distinguish a replay from a foreign operation on the same operationId.
    tx.set(
      opRef,
      receiptPayload({
        kind: EXAM_REQUEST_KIND,
        operationType: EXAM_REQUEST_OPERATION,
        operationId,
        actorUid: caller.uid,
        fingerprint,
        result,
      }),
    );

    tx.set(auditRef, {
      action: "health.request_exam",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. RECORD COLLECTION
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthRecordExamCollection(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const examId = parseRequiredString(data, "examId");
  const collectionSite = stringValue(data["collectionSite"] ?? data["collection_site"]) ?? null;
  const collectionNotes = stringValue(data["collectionNotes"] ?? data["collection_notes"]) ?? null;
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const eventId = deterministicEventId(dogId, caseId, "collected", operationId);
  const eRef = examRef(deps.db, dogId, caseId, examId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "record_collection",
      dogId,
      caseId,
      examId,
      collectionSite,
      collectionNotes,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] === fingerprint) {
        return (receipt["result"] ?? {}) as JsonMap;
      }
      throw new HttpsError(
        "failed-precondition",
        `Conflito de idempotência: operationId ${operationId} já utilizado.`,
      );
    }

    const examSnap = await tx.get(eRef);
    if (!examSnap.exists) {
      throw new HttpsError("not-found", `Exame ${examId} não encontrado.`);
    }
    const examData = examSnap.data() as JsonMap;
    const currentStage = stringValue(examData["current_stage"]);
    if (currentStage !== "requested") {
      throw new HttpsError(
        "failed-precondition",
        `Exame em estágio inválido para coleta: ${currentStage} (esperado: requested).`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);
    const examRev = typeof examData["revision"] === "number" ? examData["revision"] : 1;

    const examUpdate: JsonMap = {
      current_stage: "collected",
      collected_at: nowTs,
      collected_by: recordedBy,
      revision: examRev + 1,
    };
    if (collectionSite) examUpdate["collection_site"] = collectionSite;
    if (collectionNotes) examUpdate["collection_notes"] = collectionNotes;

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      exam_id: examId,
      event_type: "exam_collection",
      payload_type: "exam_collection_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        exam_id: examId,
        if_collection_site: collectionSite,
        if_collection_notes: collectionNotes,
      },
      revision: 1,
      schema_version: 1,
    };

    tx.update(eRef, examUpdate);
    tx.set(evtRef, eventDoc);

    const result: JsonMap = {
      success: true,
      examId,
      eventId,
      stage: "collected",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.record_exam_collection",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. RECORD RESULT
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthRecordExamResult(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const examId = parseRequiredString(data, "examId");
  const resultSummary = parseRequiredString(data, "resultSummary");
  const resultDocumentId = stringValue(data["resultDocumentId"] ?? data["result_document_id"]) ?? null;
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const eventId = deterministicEventId(dogId, caseId, "resulted", operationId);
  const scheduleId = deterministicScheduleId(dogId, examId);

  const eRef = examRef(deps.db, dogId, caseId, examId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const schedRef = deps.db
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "record_result",
      dogId,
      caseId,
      examId,
      resultSummary,
      resultDocumentId,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] === fingerprint) {
        return (receipt["result"] ?? {}) as JsonMap;
      }
      throw new HttpsError(
        "failed-precondition",
        `Conflito de idempotência: operationId ${operationId} já utilizado.`,
      );
    }

    const examSnap = await tx.get(eRef);
    if (!examSnap.exists) {
      throw new HttpsError("not-found", `Exame ${examId} não encontrado.`);
    }
    const examData = examSnap.data() as JsonMap;
    const currentStage = stringValue(examData["current_stage"]);
    if (currentStage !== "collected") {
      throw new HttpsError(
        "failed-precondition",
        `Exame em estágio inválido para resultado: ${currentStage} (esperado: collected).`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);
    const examRev = typeof examData["revision"] === "number" ? examData["revision"] : 1;

    const examUpdate: JsonMap = {
      current_stage: "resulted",
      resulted_at: nowTs,
      result_received_by: recordedBy,
      result_summary: resultSummary,
      revision: examRev + 1,
    };
    if (resultDocumentId) examUpdate["result_document_id"] = resultDocumentId;

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      exam_id: examId,
      event_type: "exam_result",
      payload_type: "exam_result_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      content: {
        exam_id: examId,
        result_summary: resultSummary,
        if_result_document_id: resultDocumentId,
      },
      revision: 1,
      schema_version: 1,
    };
    if (resultDocumentId) {
      eventDoc["attachment_refs"] = [resultDocumentId];
    }

    // Schedule: marca concluído se existir e estiver open
    const schedSnap = await tx.get(schedRef);
    if (schedSnap.exists) {
      const schedData = (schedSnap.data() ?? {}) as JsonMap;
      if (schedData["lifecycle_status"] === "open") {
        const schedRev = typeof schedData["revision"] === "number" ? schedData["revision"] : 1;
        tx.update(schedRef, {
          lifecycle_status: "completed",
          completed_at: nowTs,
          completed_by: recordedBy,
          revision: schedRev + 1,
        });
      }
    }

    tx.update(eRef, examUpdate);
    tx.set(evtRef, eventDoc);

    const result: JsonMap = {
      success: true,
      examId,
      eventId,
      stage: "resulted",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.record_exam_result",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. RECORD INTERPRETATION
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthRecordExamInterpretation(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireInterpretExam(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const examId = parseRequiredString(data, "examId");
  const interpretationText = parseRequiredString(data, "interpretationText");
  const professionalRaw = data["professional"] as JsonMap | undefined;
  const profName = professionalRaw ? stringValue(professionalRaw["name"]) : null;
  const profRegNumber = professionalRaw
    ? stringValue(professionalRaw["registration_number"] ?? professionalRaw["registrationNumber"])
    : null;
  if (!professionalRaw || !profName || !profRegNumber) {
    throw new HttpsError(
      "invalid-argument",
      "Interpretação de exame exige ProfessionalIdentity completa (veterinário responsável).",
    );
  }
  const interpretationDocumentId = stringValue(
    data["interpretationDocumentId"] ?? data["interpretation_document_id"],
  ) ?? null;
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const eventId = deterministicEventId(dogId, caseId, "interpreted", operationId);
  const eRef = examRef(deps.db, dogId, caseId, examId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "record_interpretation",
      dogId,
      caseId,
      examId,
      interpretationText,
      professional: professionalRaw,
      interpretationDocumentId,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] === fingerprint) {
        return (receipt["result"] ?? {}) as JsonMap;
      }
      throw new HttpsError(
        "failed-precondition",
        `Conflito de idempotência: operationId ${operationId} já utilizado.`,
      );
    }

    const examSnap = await tx.get(eRef);
    if (!examSnap.exists) {
      throw new HttpsError("not-found", `Exame ${examId} não encontrado.`);
    }
    const examData = examSnap.data() as JsonMap;
    const currentStage = stringValue(examData["current_stage"]);
    if (currentStage !== "resulted") {
      throw new HttpsError(
        "failed-precondition",
        `Exame em estágio inválido para interpretação: ${currentStage} (esperado: resulted).`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);
    const examRev = typeof examData["revision"] === "number" ? examData["revision"] : 1;

    const examUpdate: JsonMap = {
      current_stage: "interpreted",
      interpreted_at: nowTs,
      interpreted_by: recordedBy,
      interpretation_professional: professionalRaw,
      interpretation_text: interpretationText,
      revision: examRev + 1,
    };
    if (interpretationDocumentId) {
      examUpdate["interpretation_document_id"] = interpretationDocumentId;
    }

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      exam_id: examId,
      event_type: "exam_interpretation",
      payload_type: "exam_interpretation_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      professional: professionalRaw,
      content: {
        exam_id: examId,
        interpretation_text: interpretationText,
        if_interpretation_document_id: interpretationDocumentId,
      },
      revision: 1,
      schema_version: 1,
    };
    if (interpretationDocumentId) {
      eventDoc["attachment_refs"] = [interpretationDocumentId];
    }

    tx.update(eRef, examUpdate);
    tx.set(evtRef, eventDoc);

    const result: JsonMap = {
      success: true,
      examId,
      eventId,
      stage: "interpreted",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.record_exam_interpretation",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. ASSESS OPERATIONAL IMPACT
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthAssessExamImpact(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireRecordClinical(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const examId = parseRequiredString(data, "examId");
  const operationalImpactRaw = data["operationalImpact"] as JsonMap | undefined;
  if (!operationalImpactRaw || !stringValue(operationalImpactRaw["description"])) {
    throw new HttpsError(
      "invalid-argument",
      "Avaliação de impacto exige bloco operational_impact com descrição.",
    );
  }
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const eventId = deterministicEventId(dogId, caseId, "impact_assessed", operationId);
  const eRef = examRef(deps.db, dogId, caseId, examId);
  const evtRef = clinicalEventRef(deps.db, dogId, caseId, eventId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "assess_impact",
      dogId,
      caseId,
      examId,
      operationalImpact: operationalImpactRaw,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] === fingerprint) {
        return (receipt["result"] ?? {}) as JsonMap;
      }
      throw new HttpsError(
        "failed-precondition",
        `Conflito de idempotência: operationId ${operationId} já utilizado.`,
      );
    }

    const examSnap = await tx.get(eRef);
    if (!examSnap.exists) {
      throw new HttpsError("not-found", `Exame ${examId} não encontrado.`);
    }
    const examData = examSnap.data() as JsonMap;
    const currentStage = stringValue(examData["current_stage"]);
    if (currentStage !== "interpreted") {
      throw new HttpsError(
        "failed-precondition",
        `Exame em estágio inválido para avaliação de impacto: ${currentStage} (esperado: interpreted).`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);
    const examRev = typeof examData["revision"] === "number" ? examData["revision"] : 1;

    const examUpdate: JsonMap = {
      current_stage: "impact_assessed",
      impact_assessed_at: nowTs,
      impact_assessed_by: recordedBy,
      operational_impact: operationalImpactRaw,
      revision: examRev + 1,
    };

    const eventDoc: JsonMap = {
      entity_kind: "clinical_event",
      event_id: eventId,
      case_id: caseId,
      dog_id: dogId,
      exam_id: examId,
      event_type: "reevaluation",
      payload_type: "reevaluation_v1",
      payload_version: 1,
      status: "final",
      occurred_at: nowTs,
      recorded_at: nowTs,
      updated_at: nowTs,
      recorded_by: recordedBy,
      operational_impact: operationalImpactRaw,
      content: {
        exam_id: examId,
        evaluation_type: "exam_impact_assessment",
        operational_impact: operationalImpactRaw,
      },
      revision: 1,
      schema_version: 1,
    };

    tx.update(eRef, examUpdate);
    tx.set(evtRef, eventDoc);

    const result: JsonMap = {
      success: true,
      examId,
      eventId,
      stage: "impact_assessed",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.assess_exam_impact",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. CANCEL EXAM
// ─────────────────────────────────────────────────────────────────────────────

export async function runHealthCancelExam(
  request: CallableRequest,
  deps: ExamProcessCallableDeps,
): Promise<JsonMap> {
  const caller = await deps.requireManageClinicalCase(request.auth);
  const data = (request.data ?? {}) as JsonMap;

  const dogId = assertDogId(data["dogId"] ?? data["dog_id"]);
  const caseId = parseRequiredString(data, "caseId");
  const examId = parseRequiredString(data, "examId");
  const cancelReason = parseRequiredString(data, "cancelReason");
  const operationId = normalizeOperationId(data["operationId"] ?? data["operation_id"]);

  const dog = await loadDog(deps.db, dogId);
  await deps.requireDogAccess(request.auth, caller, dogId, dog);
  const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

  const scheduleId = deterministicScheduleId(dogId, examId);
  const eRef = examRef(deps.db, dogId, caseId, examId);
  const schedRef = deps.db
    .collection("dogs")
    .doc(dogId)
    .collection("health_schedule")
    .doc(scheduleId);
  const opRef = examOperationRef(deps.db, dogId, caseId, operationId);
  const auditRef = deps.db
    .collection("auditLogs")
    .doc(auditDocId(dogId, caseId, operationId));

  const nowDate = (deps.now ?? (() => new Date()))();
  const nowTs = Timestamp.fromDate(nowDate);

  const fingerprint = sha256Hex(
    stableStringify({
      action: "cancel_exam",
      dogId,
      caseId,
      examId,
      cancelReason,
    }),
  );

  return await deps.db.runTransaction(async (tx) => {
    const opSnap = await tx.get(opRef);
    if (opSnap.exists) {
      const receipt = opSnap.data() as JsonMap;
      if (receipt["fingerprint"] === fingerprint) {
        return (receipt["result"] ?? {}) as JsonMap;
      }
      throw new HttpsError(
        "failed-precondition",
        `Conflito de idempotência: operationId ${operationId} já utilizado.`,
      );
    }

    const examSnap = await tx.get(eRef);
    if (!examSnap.exists) {
      throw new HttpsError("not-found", `Exame ${examId} não encontrado.`);
    }
    const examData = examSnap.data() as JsonMap;
    const currentStage = stringValue(examData["current_stage"]);
    if (currentStage === "cancelled" || currentStage === "impact_assessed") {
      throw new HttpsError(
        "failed-precondition",
        `Exame em estágio terminal (${currentStage}) não pode ser cancelado.`,
      );
    }

    const recordedBy = recordedByPayload(caller, isAdmin);
    const examRev = typeof examData["revision"] === "number" ? examData["revision"] : 1;

    const examUpdate: JsonMap = {
      current_stage: "cancelled",
      cancelled_at: nowTs,
      cancelled_by: recordedBy,
      cancel_reason: cancelReason,
      revision: examRev + 1,
    };

    // Cancela agendamento preventivo se estiver open
    const schedSnap = await tx.get(schedRef);
    if (schedSnap.exists) {
      const schedData = schedSnap.data() as JsonMap;
      if (schedData["lifecycle_status"] === "open") {
        const schedRev = typeof schedData["revision"] === "number" ? schedData["revision"] : 1;
        tx.update(schedRef, {
          lifecycle_status: "cancelled",
          cancelled_at: nowTs,
          cancelled_by: recordedBy,
          cancel_reason: cancelReason,
          revision: schedRev + 1,
        });
      }
    }

    tx.update(eRef, examUpdate);

    const result: JsonMap = {
      success: true,
      examId,
      stage: "cancelled",
    };

    tx.set(opRef, {
      operation_id: operationId,
      fingerprint,
      result,
      created_at: nowTs,
    });

    tx.set(auditRef, {
      action: "health.cancel_exam",
      actor: recordedBy,
      dog_id: dogId,
      case_id: caseId,
      exam_id: examId,
      timestamp: nowTs,
    });

    return result;
  });
}
