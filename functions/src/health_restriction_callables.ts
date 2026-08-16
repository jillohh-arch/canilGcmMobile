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
  CANCEL_METADATA_FIELDS,
  END_METADATA_FIELDS,
  RESTRICTION_CANCEL_KIND,
  RESTRICTION_CANCEL_OPERATION,
  RESTRICTION_END_KIND,
  RESTRICTION_END_OPERATION,
  RESTRICTION_STATUS_CANCELLED,
  RESTRICTION_STATUS_ENDED,
  assertCancelReceiptShape,
  assertEndReceiptShape,
  assertNoTerminalMetadata,
  assertReason,
  decideTerminalTransition,
  fingerprintCancelIntent,
  fingerprintEndIntent,
  matchCancelReceipt,
  matchEndReceipt,
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

/**
 * Audit determinístico: um audit lógico por operação, sem duplicar em replay.
 *
 * `operationType` participa do hash, então ISSUE, END e CANCEL sobre a mesma
 * restrição com o mesmo `operationId` produzem audits distintos.
 */
function auditDocIdFor(
  dogId: string,
  restrictionId: string,
  operationType: string,
  operationId: string,
): string {
  const h = sha256Hex(
    `${dogId}|${restrictionId}|${operationType}|${operationId}`,
  );
  return `or_audit_${h.slice(0, 40)}`;
}

function auditDocId(
  dogId: string,
  restrictionId: string,
  operationId: string,
): string {
  return auditDocIdFor(
    dogId,
    restrictionId,
    RESTRICTION_ISSUE_OPERATION,
    operationId,
  );
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

function receiptPayloadFor(params: {
  kind: string;
  operationType: string;
  operationId: string;
  actorUid: string;
  fingerprint: string;
  result: JsonMap;
}): JsonMap {
  return {
    kind: params.kind,
    operation_id: params.operationId,
    operation_type: params.operationType,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    result: {...params.result},
    processed_at: FieldValue.serverTimestamp(),
  };
}

function receiptPayload(params: {
  operationId: string;
  actorUid: string;
  fingerprint: string;
  result: IssueReceiptResult;
}): JsonMap {
  return receiptPayloadFor({
    kind: RESTRICTION_ISSUE_KIND,
    operationType: RESTRICTION_ISSUE_OPERATION,
    operationId: params.operationId,
    actorUid: params.actorUid,
    fingerprint: params.fingerprint,
    result: {...params.result},
  });
}

/**
 * Audit da emissão.
 *
 * Deliberadamente SEM PII clínica duplicada: nada de nome/registro/clínica do
 * profissional nem da descrição clínica completa — esses dados já vivem no
 * agregado, cujo acesso é controlado. O audit registra a operação e sua
 * proveniência, não o conteúdo clínico.
 */
function auditLogPayloadFor(
  caller: RestrictionCaller,
  action: string,
  dogId: string,
  restrictionId: string,
  summary: string,
  metadata: JsonMap,
): JsonMap {
  const now = FieldValue.serverTimestamp();
  return {
    action,
    entity_type: "operational_restrictions",
    entity_id: restrictionId,
    entity_path: canonicalRestrictionPath(dogId, restrictionId),
    summary,
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
function auditLogPayload(
  caller: RestrictionCaller,
  dogId: string,
  restrictionId: string,
  metadata: JsonMap,
): JsonMap {
  return auditLogPayloadFor(
    caller,
    "health_operational_restriction_issued",
    dogId,
    restrictionId,
    `Restrição operacional emitida para K9 ${dogId}`,
    metadata,
  );
}

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

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle terminal — END / CANCEL (B2)
//
// Dois comandos SEPARADOS, deliberadamente. Ambos terminam mudando `status`,
// mas as autoridades, as provas exigidas e a afirmação feita pelo usuário são
// diferentes (ADR-005 E12). Um `changeStatus` genérico teria que reintroduzir
// essa distinção via parâmetro — exatamente onde ficaria fácil de errar.
// ─────────────────────────────────────────────────────────────────────────────

export interface HealthRestrictionLifecycleDeps {
  db: FirebaseFirestore.Firestore;
  /** `health.release_restriction` — liberação clínica documentada. */
  requireReleaseRestriction: (
    auth: CallableRequest["auth"],
  ) => Promise<RestrictionCaller>;
  /** `health.cancel_restriction` — invalidação do registro. */
  requireCancelRestriction: (
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

/**
 * Campos materiais da restrição emitida — lifecycle NUNCA os reescreve.
 *
 * Correção material continua sendo CANCEL + nova ISSUE (ADR-005 E7): permitir
 * que END/CANCEL editassem `level`, `description` ou a evidência original
 * transformaria uma transição de lifecycle num update disfarçado.
 */
const MATERIAL_FIELDS_DENYLIST = [
  "level",
  "category",
  "description",
  "activitiesRestricted",
  "activities_restricted",
  "expectedEnd",
  "expected_end",
  "professional",
  "sourceDocument",
  "source_document",
  "issuedAt",
  "issued_at",
  "since",
  "recordedBy",
  "recorded_by",
  "schemaVersion",
  "schema_version",
  "revision",
  "expectedRevision",
  "expected_revision",
  "status",
  "id",
  "restrictionId2",
  "actor",
  "source",
  "deletedAt",
  "deleted_at",
];

const END_OWNED_FIELDS = ["actualEnd", "actual_end", "endedBy", "ended_by"];

const CANCEL_OWNED_FIELDS = [
  "cancelledAt",
  "cancelled_at",
  "cancelledBy",
  "cancelled_by",
];

function rejectLifecycleInjection(
  data: JsonMap,
  extraForbidden: readonly string[],
): void {
  for (const key of [...MATERIAL_FIELDS_DENYLIST, ...extraForbidden]) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      appError(
        "invalid-argument",
        "validation",
        `Campo não permitido no payload: ${key}.`,
      );
    }
  }
}

function terminalResponse(
  dogId: string,
  restrictionId: string,
  status: string,
  wasNoOp: boolean,
): JsonMap {
  return {
    dog_id: dogId,
    restriction_id: restrictionId,
    status,
    was_no_op: wasNoOp,
    // espelho camelCase (paridade Agenda / clientes mistos)
    dogId,
    restrictionId,
    wasNoOp,
  };
}

/**
 * Encerra uma restrição por LIBERAÇÃO CLÍNICA documentada.
 *
 * Exige `health.release_restriction`, a `ProfessionalIdentity` do profissional
 * externo que liberou e um `HealthDocumentRef` canônico da evidência de
 * liberação. Não existe END administrativo (ADR-005 E6).
 *
 * Como o ISSUE, não consulta Storage: o B0 encapsulou isso, e um HealthDocument
 * canônico existente É a evidência citável.
 */
export async function runHealthRestrictionEnd(
  request: CallableRequest,
  deps: HealthRestrictionLifecycleDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireReleaseRestriction(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectLifecycleInjection(data, [
      ...END_OWNED_FIELDS,
      ...CANCEL_OWNED_FIELDS,
      "cancelReason",
      "cancel_reason",
      "cancelProfessional",
      "cancel_professional",
      "cancelSourceDocument",
      "cancel_source_document",
    ]);

    const dogId = assertDocumentId(data.dogId ?? data.dog_id, "dogId");
    const restrictionId = assertDocumentId(
      data.restrictionId ?? data.restriction_id,
      "restrictionId",
    );
    const operationId = normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    );
    const endReason = assertReason(
      data.endReason ?? data.end_reason,
      "end_reason",
    );
    const endProfessional = parseProfessionalIdentity(
      data.endProfessional ?? data.end_professional,
    );
    const endSourceDocument = parseSourceDocumentRef(
      data.endSourceDocument ?? data.end_source_document,
    );

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const fingerprint = fingerprintEndIntent({
      dogId,
      restrictionId,
      endReason,
      endProfessional,
      endSourceDocument,
    });

    const docRef = restrictionRef(deps.db, dogId, restrictionId);
    const opRef = operationRef(deps.db, dogId, restrictionId, operationId);
    const evidenceRef = healthDocumentRef(
      deps.db,
      dogId,
      endSourceDocument.health_document_id,
    );
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocIdFor(
          dogId,
          restrictionId,
          RESTRICTION_END_OPERATION,
          operationId,
        ),
      );

    const nowDate = (deps.now ?? (() => new Date()))();
    const actualEnd = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      // Todos os reads antes de qualquer write.
      const [existing, opSnap, evidenceSnap] = await Promise.all([
        tx.get(docRef),
        tx.get(opRef),
        tx.get(evidenceRef),
      ]);

      let receiptMatch: ReturnType<typeof matchEndReceipt> = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        // Um receipt de CANCEL com o mesmo operationId falha aqui como
        // integridade: kinds distintos são load-bearing, nunca replay cruzado.
        assertEndReceiptShape(stored);
        receiptMatch = matchEndReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          actorUid: caller.uid,
          fingerprint,
        });
      }

      const current = (existing.data() ?? {}) as JsonMap;
      const decision = decideTerminalTransition({
        receiptMatch,
        restrictionExists: existing.exists,
        currentStatus: stringValue(current.status),
      });

      if (decision.kind === "error") {
        if (decision.code === "not-found") {
          appError("not-found", "not-found", decision.message);
        }
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "replay") {
        return terminalResponse(
          dogId,
          restrictionId,
          RESTRICTION_STATUS_ENDED,
          true,
        );
      }

      // Nunca produzir agregado terminal híbrido.
      assertNoTerminalMetadata(current, CANCEL_METADATA_FIELDS, "cancelamento");

      // Evidência da LIBERAÇÃO: canônica, do mesmo K9, sem Storage.
      if (!evidenceSnap.exists) {
        appError(
          "failed-precondition",
          "integrity",
          "HealthDocument citado em end_source_document não existe em " +
            `${canonicalHealthDocumentPath(
              dogId,
              endSourceDocument.health_document_id,
            )}: encerramento exige evidência documental canônica.`,
        );
      }
      const evidence = (evidenceSnap.data() ?? {}) as JsonMap;
      if (evidence.deleted_at !== undefined && evidence.deleted_at !== null) {
        appError(
          "failed-precondition",
          "integrity",
          "HealthDocument citado em end_source_document está excluído.",
        );
      }

      // Altera SOMENTE status + metadata terminal. Os campos materiais da
      // emissão permanecem exatamente como foram registrados.
      const patch: JsonMap = {
        status: RESTRICTION_STATUS_ENDED,
        end_reason: endReason,
        actual_end: actualEnd,
        ended_by: recordedByPayload(caller, isAdmin),
        end_professional: {
          name: endProfessional.name,
          registration_type: endProfessional.registration_type,
          registration_number: endProfessional.registration_number,
          clinic: endProfessional.clinic,
          specialty: endProfessional.specialty,
        },
        end_source_document: {
          health_document_id: endSourceDocument.health_document_id,
          description: endSourceDocument.description,
        },
      };

      tx.update(docRef, patch);
      tx.set(
        opRef,
        receiptPayloadFor({
          kind: RESTRICTION_END_KIND,
          operationType: RESTRICTION_END_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, restrictionId, status: RESTRICTION_STATUS_ENDED},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayloadFor(
          caller,
          "health_operational_restriction_ended",
          dogId,
          restrictionId,
          `Restrição operacional encerrada por liberação clínica — K9 ${dogId}`,
          {
            restriction_id: restrictionId,
            operation_id: operationId,
            end_reason: endReason,
            source_document_id: endSourceDocument.health_document_id,
            authority: "operational_restrictions",
          },
        ),
      );

      return terminalResponse(
        dogId,
        restrictionId,
        RESTRICTION_STATUS_ENDED,
        false,
      );
    });
  } catch (err) {
    mapLogicError(err);
  }
}

/**
 * Invalida o REGISTRO de uma restrição.
 *
 * Exige `health.cancel_restriction`. NÃO exige `ProfessionalIdentity` nem
 * `HealthDocumentRef` — exigi-los transformaria invalidação administrativa numa
 * pseudo-liberação clínica (ADR-005 E12).
 *
 * CANCEL não afirma melhora clínica, mas remove o efeito operacional da
 * restrição: é por isso que tem capability própria e não é CRUD comum.
 */
export async function runHealthRestrictionCancel(
  request: CallableRequest,
  deps: HealthRestrictionLifecycleDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireCancelRestriction(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectLifecycleInjection(data, [
      ...CANCEL_OWNED_FIELDS,
      ...END_OWNED_FIELDS,
      "endReason",
      "end_reason",
      "endProfessional",
      "end_professional",
      "endSourceDocument",
      "end_source_document",
      // CANCEL não carrega prova clínica: enviar professional/documento é erro
      // de contrato, não campo opcional a ser ignorado em silêncio.
      "cancelProfessional",
      "cancel_professional",
      "cancelSourceDocument",
      "cancel_source_document",
    ]);

    const dogId = assertDocumentId(data.dogId ?? data.dog_id, "dogId");
    const restrictionId = assertDocumentId(
      data.restrictionId ?? data.restriction_id,
      "restrictionId",
    );
    const operationId = normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    );
    const cancelReason = assertReason(
      data.cancelReason ?? data.cancel_reason,
      "cancel_reason",
    );

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    const fingerprint = fingerprintCancelIntent({
      dogId,
      restrictionId,
      cancelReason,
    });

    const docRef = restrictionRef(deps.db, dogId, restrictionId);
    const opRef = operationRef(deps.db, dogId, restrictionId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(
        auditDocIdFor(
          dogId,
          restrictionId,
          RESTRICTION_CANCEL_OPERATION,
          operationId,
        ),
      );

    const nowDate = (deps.now ?? (() => new Date()))();
    const cancelledAt = Timestamp.fromDate(nowDate);

    return await deps.db.runTransaction(async (tx) => {
      const [existing, opSnap] = await Promise.all([
        tx.get(docRef),
        tx.get(opRef),
      ]);

      let receiptMatch: ReturnType<typeof matchCancelReceipt> = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertCancelReceiptShape(stored);
        receiptMatch = matchCancelReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          actorUid: caller.uid,
          fingerprint,
        });
      }

      const current = (existing.data() ?? {}) as JsonMap;
      const decision = decideTerminalTransition({
        receiptMatch,
        restrictionExists: existing.exists,
        currentStatus: stringValue(current.status),
      });

      if (decision.kind === "error") {
        if (decision.code === "not-found") {
          appError("not-found", "not-found", decision.message);
        }
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "replay") {
        return terminalResponse(
          dogId,
          restrictionId,
          RESTRICTION_STATUS_CANCELLED,
          true,
        );
      }

      assertNoTerminalMetadata(current, END_METADATA_FIELDS, "encerramento");

      const patch: JsonMap = {
        status: RESTRICTION_STATUS_CANCELLED,
        cancel_reason: cancelReason,
        cancelled_at: cancelledAt,
        cancelled_by: recordedByPayload(caller, isAdmin),
      };

      tx.update(docRef, patch);
      tx.set(
        opRef,
        receiptPayloadFor({
          kind: RESTRICTION_CANCEL_KIND,
          operationType: RESTRICTION_CANCEL_OPERATION,
          operationId,
          actorUid: caller.uid,
          fingerprint,
          result: {dogId, restrictionId, status: RESTRICTION_STATUS_CANCELLED},
        }),
      );
      tx.set(
        auditRef,
        auditLogPayloadFor(
          caller,
          "health_operational_restriction_cancelled",
          dogId,
          restrictionId,
          `Registro de restrição operacional invalidado — K9 ${dogId}`,
          {
            restriction_id: restrictionId,
            operation_id: operationId,
            cancel_reason: cancelReason,
            authority: "operational_restrictions",
          },
        ),
      );

      return terminalResponse(
        dogId,
        restrictionId,
        RESTRICTION_STATUS_CANCELLED,
        false,
      );
    });
  } catch (err) {
    mapLogicError(err);
  }
}
