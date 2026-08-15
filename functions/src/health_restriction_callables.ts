/**
 * Callable de emissão de OperationalRestriction — ISSUE (B1).
 *
 * Admin SDK (bypassa Rules). Client writes em
 * `dogs/{dogId}/operational_restrictions/{restrictionId}` permanecem negados.
 *
 * AUTORIDADE: `health.issue_restriction` — deliberadamente distinta de
 * `health.create`. Criar um HealthDocument não é declarar impacto operacional:
 * a restrição decide se um K9 pode ou não trabalhar.
 *
 * FRONTEIRA COM O B0: este módulo não importa nada de Storage. A evidência é o
 * `HealthDocument` canônico existente, citado por identidade.
 *
 * ESCOPO: apenas criação com `status: active`. END/CANCEL são o B2.
 */

import * as crypto from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  AppErrorCode,
  HealthDocumentRefValue,
  IssueReceiptResult,
  OPERATIONAL_RESTRICTION_SCHEMA_VERSION,
  ProfessionalIdentity,
  RESTRICTION_ISSUE_KIND,
  RESTRICTION_ISSUE_OPERATION,
  RestrictionCategory,
  RestrictionLevel,
  assertDescription,
  assertDocumentId,
  assertPartialInvariant,
  assertReceiptShape,
  canonicalHealthDocumentPath,
  canonicalRestrictionPath,
  createIdempotencyMaterial,
  decideIssue,
  deterministicRestrictionId,
  fingerprintIssueIntent,
  matchIssueReceipt,
  normalizeActivities,
  normalizeOperationId,
  optionalInstant,
  parseCategory,
  parseLevel,
  parseProfessionalIdentity,
  parseSourceDocumentRef,
  recordedByPayload,
  stringValue,
} from "./health_restriction_logic";

type JsonMap = Record<string, unknown>;

export interface RestrictionCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

export interface HealthRestrictionCallableDeps {
  db: FirebaseFirestore.Firestore;
  /** Autoridade específica de emissão — nunca `health.create`. */
  requireIssueRestriction: (
    auth: CallableRequest["auth"],
  ) => Promise<RestrictionCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: RestrictionCaller,
    dogId: string,
    dog: JsonMap,
  ) => Promise<void>;
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: RestrictionCaller,
  ) => Promise<boolean>;
  /** Referência única de tempo server-side para a operação. */
  now?: () => Date;
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
 * Checagem estrutural: `instanceof` falha no worker do Emulator/Functions
 * quando há dual package hazard.
 */
function isHttpsError(err: unknown): err is HttpsError {
  if (!err || typeof err !== "object") return false;
  const e = err as {name?: string; code?: string; httpErrorCode?: unknown};
  return (
    e.name === "HttpsError" ||
    (typeof e.code === "string" && e.httpErrorCode !== undefined)
  );
}

function mapLogicError(err: unknown): never {
  if (isHttpsError(err)) throw err;
  const e = err as Error & {appCode?: AppErrorCode};
  const code = e.appCode ?? "unexpected";
  const message = e.message || "Falha na emissão de restrição operacional.";
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
  case "integrity":
    appError("failed-precondition", code, message);
    break;
  default:
    appError("internal", "unexpected", message);
  }
}

function throwDecisionError(code: AppErrorCode, message: string): never {
  const http =
    code === "permission-denied" ? "permission-denied" : "failed-precondition";
  appError(http, code, message);
}

function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}

/** Audit determinístico: um audit lógico por emissão, sem duplicar em replay. */
function auditDocId(
  dogId: string,
  restrictionId: string,
  operationId: string,
): string {
  const h = sha256Hex(
    `${dogId}|${restrictionId}|${RESTRICTION_ISSUE_OPERATION}|${operationId}`,
  );
  return `or_audit_${h.slice(0, 40)}`;
}

function restrictionRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  restrictionId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("operational_restrictions")
    .doc(restrictionId);
}

function operationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  restrictionId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return restrictionRef(db, dogId, restrictionId)
    .collection("operations")
    .doc(operationId);
}

function healthDocumentRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  healthDocumentId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("health_documents")
    .doc(healthDocumentId);
}

function receiptPayload(params: {
  operationId: string;
  actorUid: string;
  fingerprint: string;
  result: IssueReceiptResult;
}): JsonMap {
  return {
    kind: RESTRICTION_ISSUE_KIND,
    operation_id: params.operationId,
    operation_type: RESTRICTION_ISSUE_OPERATION,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    result: {...params.result},
    processed_at: FieldValue.serverTimestamp(),
  };
}

/**
 * Audit da emissão.
 *
 * Deliberadamente SEM PII clínica duplicada: nada de nome/registro/clínica do
 * profissional nem da descrição clínica completa — esses dados já vivem no
 * agregado, cujo acesso é controlado. O audit registra a operação e sua
 * proveniência, não o conteúdo clínico.
 */
function auditLogPayload(
  caller: RestrictionCaller,
  dogId: string,
  restrictionId: string,
  metadata: JsonMap,
): JsonMap {
  const now = FieldValue.serverTimestamp();
  return {
    action: "health_operational_restriction_issued",
    entity_type: "operational_restrictions",
    entity_id: restrictionId,
    entity_path: canonicalRestrictionPath(dogId, restrictionId),
    summary: `Restrição operacional emitida para K9 ${dogId}`,
    actor: {
      uid: caller.uid,
      email: caller.email,
      ra: caller.ra,
      name: caller.name,
    },
    metadata: {dog_id: dogId, ...metadata},
    source: "functions",
    performed_at: now,
    createdAt: now,
  };
}

/**
 * Campos server-owned ou de lifecycle inaplicável ao ISSUE.
 *
 * Fail-closed explícito: um payload que tente definir `status`, autoria ou
 * qualquer campo de encerramento é rejeitado, nunca ignorado em silêncio.
 */
function rejectInjection(data: JsonMap): void {
  const forbidden = [
    "id",
    "restrictionId",
    "restriction_id",
    "status",
    "recordedBy",
    "recorded_by",
    "issuedAt",
    "issued_at",
    "since",
    "schemaVersion",
    "schema_version",
    "revision",
    "createFingerprint",
    "create_fingerprint",
    "createOperationId",
    "create_operation_id",
    "actualEnd",
    "actual_end",
    "endedBy",
    "ended_by",
    "endProfessional",
    "end_professional",
    "endSourceDocument",
    "end_source_document",
    "endReason",
    "end_reason",
    "cancelledAt",
    "cancelled_at",
    "cancelledBy",
    "cancelled_by",
    "cancelReason",
    "cancel_reason",
    "deletedAt",
    "deleted_at",
    "isOverdue",
    "is_overdue",
    "actor",
    "source",
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

interface ParsedIssueInput {
  readonly dogId: string;
  readonly operationId: string;
  readonly level: RestrictionLevel;
  readonly category: RestrictionCategory;
  readonly description: string;
  readonly activitiesRestricted: string[];
  readonly expectedEnd?: Date;
  readonly professional: ProfessionalIdentity;
  readonly sourceDocument: HealthDocumentRefValue;
}

function parseIssueInput(data: JsonMap): ParsedIssueInput {
  const dogId = assertDocumentId(data.dogId ?? data.dog_id, "dogId");
  const operationId = normalizeOperationId(
    data.idempotencyKey ?? data.operationId ?? data.operation_id,
  );
  const level = parseLevel(data.level);
  const category = parseCategory(data.category);
  const description = assertDescription(data.description);
  const activitiesRestricted = normalizeActivities(
    data.activitiesRestricted ?? data.activities_restricted,
  );
  assertPartialInvariant(level, activitiesRestricted);
  const expectedEnd = optionalInstant(
    data.expectedEnd ?? data.expected_end,
    "expected_end",
  );
  const professional = parseProfessionalIdentity(data.professional);
  const sourceDocument = parseSourceDocumentRef(
    data.sourceDocument ?? data.source_document,
  );

  return {
    dogId,
    operationId,
    level,
    category,
    description,
    activitiesRestricted,
    expectedEnd,
    professional,
    sourceDocument,
  };
}

function issueResponse(
  dogId: string,
  restrictionId: string,
  wasNoOp: boolean,
): JsonMap {
  return {
    dog_id: dogId,
    restriction_id: restrictionId,
    status: "active",
    was_no_op: wasNoOp,
    // espelho camelCase (paridade Agenda / clientes mistos)
    dogId,
    restrictionId,
    wasNoOp,
  };
}

/**
 * Emite uma OperationalRestriction canônica (`status: active`).
 *
 * O writer NÃO decide clinicamente e NÃO calcula prontidão: registra de forma
 * canônica uma decisão clínica externa já documentada. A projeção de readiness
 * acontece pelo trigger existente em `operational_restrictions`, sem
 * acoplamento explícito aqui.
 */
export async function runHealthRestrictionIssue(
  request: CallableRequest,
  deps: HealthRestrictionCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireIssueRestriction(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);

    const input = parseIssueInput(data);
    const {dogId, operationId} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    // Identidade SEMPRE recomputada — nunca vinda do cliente.
    const restrictionId = deterministicRestrictionId(
      sha256Hex(createIdempotencyMaterial(dogId, operationId)),
    );

    const fingerprint = fingerprintIssueIntent({
      dogId,
      level: input.level,
      category: input.category,
      description: input.description,
      activitiesRestricted: input.activitiesRestricted,
      expectedEndIso: input.expectedEnd ?
        input.expectedEnd.toISOString() :
        null,
      professional: input.professional,
      sourceDocument: input.sourceDocument,
    });

    const docRef = restrictionRef(deps.db, dogId, restrictionId);
    const opRef = operationRef(deps.db, dogId, restrictionId, operationId);
    const evidenceRef = healthDocumentRef(
      deps.db,
      dogId,
      input.sourceDocument.health_document_id,
    );
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, restrictionId, operationId));

    const nowDate = (deps.now ?? (() => new Date()))();
    const issuedAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      // Todos os reads antes de qualquer write. A existência da evidência
      // participa do gate da mutação: uma restrição não pode citar um
      // HealthDocument que não existe.
      const [existing, opSnap, evidenceSnap] = await Promise.all([
        tx.get(docRef),
        tx.get(opRef),
        tx.get(evidenceRef),
      ]);

      let receiptMatch: ReturnType<typeof matchIssueReceipt> = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertReceiptShape(stored);
        receiptMatch = matchIssueReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          actorUid: caller.uid,
          fingerprint,
        });
      }

      const decision = decideIssue({
        receiptMatch,
        restrictionExists: existing.exists,
      });

      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "replay") {
        return issueResponse(dogId, restrictionId, true);
      }

      // Evidência canônica: precisa existir e pertencer a ESTE K9 (garantido
      // pelo path). Nenhuma leitura de Storage — o B0 encapsulou isso.
      if (!evidenceSnap.exists) {
        appError(
          "failed-precondition",
          "integrity",
          "HealthDocument citado em source_document não existe em " +
            `${canonicalHealthDocumentPath(
              dogId,
              input.sourceDocument.health_document_id,
            )}: emissão exige evidência documental canônica.`,
        );
      }
      const evidence = (evidenceSnap.data() ?? {}) as JsonMap;
      if (evidence.deleted_at !== undefined && evidence.deleted_at !== null) {
        appError(
          "failed-precondition",
          "integrity",
          "HealthDocument citado está marcado como excluído.",
        );
      }

      const record: JsonMap = {
        // `status` é sempre server-owned: ISSUE cria exclusivamente `active`.
        status: "active",
        level: input.level,
        category: input.category,
        description: input.description,
        activities_restricted: input.activitiesRestricted,
        // Canônico do Schema §2.12; o reader aceita `since` ?? `issued_at`.
        issued_at: issuedAt,
        recorded_by: recordedByPayload(caller, isAdmin),
        professional: {
          name: input.professional.name,
          registration_type: input.professional.registration_type,
          registration_number: input.professional.registration_number,
          clinic: input.professional.clinic,
          specialty: input.professional.specialty,
        },
        source_document: {
          health_document_id: input.sourceDocument.health_document_id,
          description: input.sourceDocument.description,
        },
        schema_version: OPERATIONAL_RESTRICTION_SCHEMA_VERSION,
      };
      if (input.expectedEnd !== undefined) {
        record.expected_end = Timestamp.fromDate(input.expectedEnd);
      }

      const result: IssueReceiptResult = {dogId, restrictionId};

      tx.set(docRef, record);
      tx.set(
        opRef,
        receiptPayload({
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result,
        }),
      );
      tx.set(
        auditRef,
        auditLogPayload(caller, dogId, restrictionId, {
          restriction_id: restrictionId,
          operation_id: operationId,
          level: input.level,
          category: input.category,
          source_document_id: input.sourceDocument.health_document_id,
          authority: "operational_restrictions",
        }),
      );

      return issueResponse(dogId, restrictionId, false);
    });
  } catch (err) {
    mapLogicError(err);
  }
}
