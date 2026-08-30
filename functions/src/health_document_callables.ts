/**
 * Callables do HealthDocument canônico (B0-B — fatia mínima de evidência).
 *
 * Admin SDK (bypassa Rules). Client writes em
 * `dogs/{dogId}/health_documents/{documentId}` permanecem negados.
 *
 * Fluxo:
 *
 *   PREPARE → (client upload) → FINALIZE
 *
 * PREPARE não é autoridade: apenas deriva `documentId` e `storagePath` de forma
 * determinística e não escreve nada. FINALIZE é a mutation authority e
 * RECOMPUTA ambos a partir de `dogId` + `operationId`, de modo que nenhum path
 * arbitrário do cliente possa ganhar autoridade clínica.
 */

import * as crypto from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

import {
  AppErrorCode,
  DocumentReceiptResult,
  HEALTH_DOCUMENT_CREATE_KIND,
  HEALTH_DOCUMENT_CREATE_OPERATION,
  HEALTH_DOCUMENT_SCHEMA_VERSION,
  HEALTH_DOCUMENT_SEAL_VERSION,
  HealthDocumentType,
  MAX_DESCRIPTION_LEN,
  MAX_DOCUMENT_BYTES,
  MAX_ISSUER_LEN,
  StorageObjectMetadata,
  assertDocumentDates,
  assertDogId,
  assertReceiptShape,
  assertSealIntentMatches,
  assertTitle,
  canonicalDocumentPath,
  canonicalStoragePath,
  createIdempotencyMaterial,
  decideFinalize,
  deterministicDocumentId,
  fingerprintCreateDocumentIntent,
  healthDocumentRef,
  matchDocumentReceipt,
  normalizeOperationId,
  optionalInstant,
  optionalReferenceId,
  optionalText,
  parseHealthDocumentType,
  recordedByPayload,
  sealFingerprintMaterial,
  sealMetadata,
  stagingStoragePath,
  stringValue,
  verifyStorageObject,
} from "./health_document_logic";

type JsonMap = Record<string, unknown>;

export interface DocumentCaller {
  uid: string;
  email: string;
  ra: string;
  name: string;
}

/**
 * Seam de Storage: produção usa Admin Storage, teste usa fake in-memory.
 *
 * O selo (`sealObject`) existe porque as Firebase Storage Rules não garantem
 * imutabilidade de bytes: `allow create` permite substituir o conteúdo de um
 * objeto existente. A garantia real vem das preconditions do Cloud Storage.
 */
export interface HealthDocumentStorageAdapter {
  /** Metadata do objeto de staging enviado pelo cliente. */
  getObjectMetadata: (path: string) => Promise<StorageObjectMetadata>;
  /**
   * Copia staging → canônico preso à `sourceGeneration`, com destino
   * create-only e metadata de selagem server-owned gravada no destino.
   *
   * `sealed: false` significa que já existe objeto canônico vivo (caso de
   * recuperação), nunca que a cópia foi ignorada silenciosamente.
   */
  sealObject: (params: {
    sourcePath: string;
    sourceGeneration: string;
    destinationPath: string;
    sealMetadata: Record<string, string>;
  }) => Promise<{sealed: boolean}>;
  /** Metadata do objeto canônico já selado. */
  getSealedMetadata: (path: string) => Promise<StorageObjectMetadata>;
  /** Limpeza best-effort do staging após commit. */
  deleteStagingObject: (path: string) => Promise<void>;
}

export interface HealthDocumentCallableDeps {
  db: FirebaseFirestore.Firestore;
  requireHealthCreate: (
    auth: CallableRequest["auth"],
  ) => Promise<DocumentCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: DocumentCaller,
    dogId: string,
    dog: JsonMap,
  ) => Promise<void>;
  isAdministrativeAuthority: (
    auth: CallableRequest["auth"],
    caller: DocumentCaller,
  ) => Promise<boolean>;
  storage: HealthDocumentStorageAdapter;
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
  const message = e.message || "Falha na operação de documento de saúde.";
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

/** Audit determinístico: um audit lógico por operação, sem duplicar em replay. */
function auditDocId(
  dogId: string,
  documentId: string,
  operationId: string,
): string {
  const h = sha256Hex(
    `${dogId}|${documentId}|${HEALTH_DOCUMENT_CREATE_OPERATION}|${operationId}`,
  );
  return `hd_audit_${h.slice(0, 40)}`;
}

function documentRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  documentId: string,
): FirebaseFirestore.DocumentReference {
  return db
    .collection("dogs")
    .doc(dogId)
    .collection("health_documents")
    .doc(documentId);
}

function operationRef(
  db: FirebaseFirestore.Firestore,
  dogId: string,
  documentId: string,
  operationId: string,
): FirebaseFirestore.DocumentReference {
  return documentRef(db, dogId, documentId)
    .collection("operations")
    .doc(operationId);
}

function receiptPayload(params: {
  operationId: string;
  actorUid: string;
  fingerprint: string;
  result: DocumentReceiptResult;
}): JsonMap {
  return {
    kind: HEALTH_DOCUMENT_CREATE_KIND,
    operation_id: params.operationId,
    operation_type: HEALTH_DOCUMENT_CREATE_OPERATION,
    actor_uid: params.actorUid,
    fingerprint: params.fingerprint,
    result: {
      ...params.result,
      reference: healthDocumentRef(params.result.documentId),
    },
    processed_at: FieldValue.serverTimestamp(),
  };
}

function auditLogPayload(
  caller: DocumentCaller,
  dogId: string,
  documentId: string,
  metadata: JsonMap,
): JsonMap {
  const now = FieldValue.serverTimestamp();
  return {
    action: "health_document_created",
    entity_type: "health_documents",
    entity_id: documentId,
    entity_path: canonicalDocumentPath(dogId, documentId),
    summary: `Documento de saúde registrado para K9 ${dogId}`,
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
 * Campos server-owned nunca aceitos do cliente.
 *
 * `storage_path` e `mime_type` estão aqui deliberadamente: o primeiro é
 * recomputado, o segundo vem do metadata verificado do objeto.
 */
function rejectInjection(data: JsonMap): void {
  const forbidden = [
    "id",
    "documentId",
    "document_id",
    "storagePath",
    "storage_path",
    "storageUrl",
    "storage_url",
    "downloadUrl",
    "download_url",
    "url",
    "mimeType",
    "mime_type",
    "recordedBy",
    "recorded_by",
    "uploadedAt",
    "uploaded_at",
    "schemaVersion",
    "schema_version",
    "revision",
    "createFingerprint",
    "create_fingerprint",
    "createOperationId",
    "create_operation_id",
    "fileSizeBytes",
    "file_size_bytes",
    "checksumMd5",
    "checksum_md5",
    "storageGeneration",
    "storage_generation",
    "deletedAt",
    "deleted_at",
    "deletedBy",
    "deleted_by",
    "deleteReason",
    "delete_reason",
    "professional",
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

interface ResolvedIdentity {
  readonly documentId: string;
  /** Destino do upload do cliente — NÃO é evidência canônica. */
  readonly uploadPath: string;
  /** Path selado pelo backend; é o que vai para `storage_path`. */
  readonly storagePath: string;
}

/** Identidade derivada — reproduzível por PREPARE e FINALIZE. */
function resolveIdentity(dogId: string, operationId: string): ResolvedIdentity {
  const documentId = deterministicDocumentId(
    sha256Hex(createIdempotencyMaterial(dogId, operationId)),
  );
  return {
    documentId,
    uploadPath: stagingStoragePath(dogId, documentId),
    storagePath: canonicalStoragePath(dogId, documentId),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PREPARE
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Deriva a identidade canônica e o Storage path reservado. ZERO writes.
 *
 * Repetir com o mesmo `dogId` + `operationId` devolve exatamente o mesmo
 * `documentId` e o mesmo `storagePath`.
 */
export async function runHealthDocumentPrepareUpload(
  request: CallableRequest,
  deps: HealthDocumentCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthCreate(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);

    const dogId = assertDogId(data.dogId ?? data.dog_id);
    const operationId = normalizeOperationId(
      data.idempotencyKey ?? data.operationId ?? data.operation_id,
    );

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);

    const {documentId, uploadPath} = resolveIdentity(dogId, operationId);

    // Só `uploadPath` é exposto: o path canônico é derivado no servidor e o
    // cliente não tem o que fazer com ele — não pode escrever lá, e o
    // HealthDocument devolve a referência depois do selo.
    return {
      dog_id: dogId,
      document_id: documentId,
      upload_path: uploadPath,
      max_bytes: MAX_DOCUMENT_BYTES,
      // espelho camelCase (paridade Agenda / clientes mistos)
      dogId,
      documentId,
      uploadPath,
    };
  } catch (err) {
    mapLogicError(err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FINALIZE
// ─────────────────────────────────────────────────────────────────────────────

interface ParsedFinalizeInput {
  readonly dogId: string;
  readonly operationId: string;
  readonly documentType: HealthDocumentType;
  readonly title: string;
  readonly description?: string;
  readonly issuer?: string;
  readonly issueDate?: Date;
  readonly expiryDate?: Date;
  readonly caseId?: string;
  readonly eventId?: string;
  readonly examId?: string;
}

function parseFinalizeInput(data: JsonMap): ParsedFinalizeInput {
  const dogId = assertDogId(data.dogId ?? data.dog_id);
  const operationId = normalizeOperationId(
    data.idempotencyKey ?? data.operationId ?? data.operation_id,
  );
  const documentType = parseHealthDocumentType(
    data.documentType ?? data.document_type,
  );
  const title = assertTitle(data.title);
  const description = optionalText(
    data.description,
    MAX_DESCRIPTION_LEN,
    "description",
  );
  const issuer = optionalText(data.issuer, MAX_ISSUER_LEN, "issuer");
  const issueDate = optionalInstant(
    data.issueDate ?? data.issue_date,
    "issue_date",
  );
  const expiryDate = optionalInstant(
    data.expiryDate ?? data.expiry_date,
    "expiry_date",
  );
  assertDocumentDates(issueDate, expiryDate);
  const caseId = optionalReferenceId(data.caseId ?? data.case_id, "case_id");
  const eventId = optionalReferenceId(
    data.eventId ?? data.event_id,
    "event_id",
  );
  const examId = optionalReferenceId(data.examId ?? data.exam_id, "exam_id");

  return {
    dogId,
    operationId,
    documentType,
    title,
    description,
    issuer,
    issueDate,
    expiryDate,
    caseId,
    eventId,
    examId,
  };
}

function replayResponse(
  dogId: string,
  documentId: string,
  storagePath: string,
): JsonMap {
  return {
    dog_id: dogId,
    document_id: documentId,
    storage_path: storagePath,
    reference: healthDocumentRef(documentId),
    was_no_op: true,
    dogId,
    documentId,
    storagePath,
    wasNoOp: true,
  };
}

/**
 * Cria o HealthDocument canônico depois de verificar o objeto no Storage.
 *
 * Ordem: receipt fast path → verificação de Storage → transação (recheck de
 * receipt, gate de invariante, três writes atômicos).
 */
export async function runHealthDocumentFinalizeUpload(
  request: CallableRequest,
  deps: HealthDocumentCallableDeps,
): Promise<JsonMap> {
  try {
    const caller = await deps.requireHealthCreate(request.auth);
    const data = (request.data ?? {}) as JsonMap;
    rejectInjection(data);

    const input = parseFinalizeInput(data);
    const {dogId, operationId} = input;

    const dog = await loadDog(deps.db, dogId);
    await deps.requireDogAccess(request.auth, caller, dogId, dog);
    const isAdmin = await deps.isAdministrativeAuthority(request.auth, caller);

    // Identidade SEMPRE recomputada — nunca vinda do cliente.
    const {documentId, uploadPath, storagePath} = resolveIdentity(
      dogId,
      operationId,
    );

    const fingerprint = fingerprintCreateDocumentIntent({
      dogId,
      documentType: input.documentType,
      title: input.title,
      description: input.description ?? null,
      issuer: input.issuer ?? null,
      issueDateIso: input.issueDate ? input.issueDate.toISOString() : null,
      expiryDateIso: input.expiryDate ? input.expiryDate.toISOString() : null,
      caseId: input.caseId ?? null,
      eventId: input.eventId ?? null,
      examId: input.examId ?? null,
    });

    const docRef = documentRef(deps.db, dogId, documentId);
    const opRef = operationRef(deps.db, dogId, documentId, operationId);
    const auditRef = deps.db
      .collection("auditLogs")
      .doc(auditDocId(dogId, documentId, operationId));

    // Fast path: replay legítimo não deve depender do estado atual do objeto,
    // que pode ter sofrido problema operacional posterior fora do controle do
    // cliente. A transação revalida para eliminar corrida.
    const earlySnap = await opRef.get();
    if (earlySnap.exists) {
      const stored = (earlySnap.data() ?? {}) as JsonMap;
      assertReceiptShape(stored);
      const match = matchDocumentReceipt({
        receiptExists: true,
        storedActorUid: stringValue(stored.actor_uid),
        storedOperationType: stringValue(stored.operation_type),
        storedFingerprint: stringValue(stored.fingerprint),
        actorUid: caller.uid,
        fingerprint,
      });
      if (match === "replay") {
        return replayResponse(dogId, documentId, storagePath);
      }
      if (match === "idempotency-conflict") {
        throwDecisionError(
          "idempotency-conflict",
          "Mesma idempotencyKey com intenção diferente da criação original.",
        );
      }
    }

    // Fingerprint de SELAGEM: deriva do fingerprint da intenção, então herda
    // sua sensibilidade a qualquer diferença material do payload. É a prova
    // durável de qual intenção produziu os bytes canônicos, necessária porque
    // na janela "selado / não commitado" ainda não existe receipt.
    const sealFingerprint = sha256Hex(
      sealFingerprintMaterial({
        dogId,
        operationId,
        finalizeFingerprint: fingerprint,
      }),
    );

    // O objeto CANÔNICO é a autoridade — não o staging.
    //
    // Ordem deliberada: se o canônico já existe, o selo nele decide tudo, e o
    // staging é irrelevante. Depois de um selo bem-sucedido o staging pode ter
    // sido sobrescrito por um retry do cliente ou já apagado pela limpeza
    // best-effort; exigi-lo aqui tornaria um documento legitimamente selado
    // irrecuperável.
    const existing = await deps.storage.getSealedMetadata(storagePath);

    let canonicalMetadata: StorageObjectMetadata;
    let sourceGeneration: string | null = null;

    if (existing.exists) {
      canonicalMetadata = existing;
    } else {
      // Valida o staging enviado pelo cliente e captura a generation exata.
      const staged = verifyStorageObject(
        await deps.storage.getObjectMetadata(uploadPath),
      );
      sourceGeneration = staged.generation;

      // Sela com dupla precondition (fonte presa à generation validada,
      // destino create-only) e metadata de selagem gravada na própria cópia.
      // `sealed: false` = outra execução selou entre a leitura e a cópia; o
      // veredito fica com a verificação de selo abaixo.
      await deps.storage.sealObject({
        sourcePath: uploadPath,
        sourceGeneration: staged.generation,
        destinationPath: storagePath,
        sealMetadata: sealMetadata({sealFingerprint, documentId}),
      });

      canonicalMetadata = await deps.storage.getSealedMetadata(storagePath);
    }

    // Metadata factual do canônico (existência, MIME, size, generation,
    // checksum) — é ela que descreve o agregado e o audit.
    const canonical = verifyStorageObject(canonicalMetadata);

    // Selo verificado SEMPRE, inclusive após um copy bem-sucedido: retorno de
    // sucesso não prova que a metadata foi gravada como esperado.
    assertSealIntentMatches({
      metadata: canonicalMetadata.customMetadata,
      expectedSealFingerprint: sealFingerprint,
    });

    const nowDate = (deps.now ?? (() => new Date()))();
    const uploadedAt = Timestamp.fromDate(nowDate);
    const verified = canonical;

    const committed = await deps.db.runTransaction(async (tx) => {
      const [docSnap, opSnap] = await Promise.all([
        tx.get(docRef),
        tx.get(opRef),
      ]);

      let receiptMatch: ReturnType<typeof matchDocumentReceipt> = "missing";
      if (opSnap.exists) {
        const stored = (opSnap.data() ?? {}) as JsonMap;
        assertReceiptShape(stored);
        receiptMatch = matchDocumentReceipt({
          receiptExists: true,
          storedActorUid: stringValue(stored.actor_uid),
          storedOperationType: stringValue(stored.operation_type),
          storedFingerprint: stringValue(stored.fingerprint),
          actorUid: caller.uid,
          fingerprint,
        });
      }

      const decision = decideFinalize({
        receiptMatch,
        documentExists: docSnap.exists,
      });

      if (decision.kind === "error") {
        throwDecisionError(decision.code, decision.message);
      }
      if (decision.kind === "replay") {
        return replayResponse(dogId, documentId, storagePath);
      }

      const record: JsonMap = {
        document_type: input.documentType,
        title: input.title,
        storage_path: storagePath,
        mime_type: verified.contentType,
        uploaded_at: uploadedAt,
        recorded_by: recordedByPayload(caller, isAdmin),
        schema_version: HEALTH_DOCUMENT_SCHEMA_VERSION,
        file_size_bytes: verified.sizeBytes,
      };
      if (input.description !== undefined) {
        record.description = input.description;
      }
      if (input.issuer !== undefined) record.issuer = input.issuer;
      if (input.issueDate !== undefined) {
        record.issue_date = Timestamp.fromDate(input.issueDate);
      }
      if (input.expiryDate !== undefined) {
        record.expiry_date = Timestamp.fromDate(input.expiryDate);
      }
      if (input.caseId !== undefined) record.case_id = input.caseId;
      if (input.eventId !== undefined) record.event_id = input.eventId;
      if (input.examId !== undefined) record.exam_id = input.examId;

      const result: DocumentReceiptResult = {dogId, documentId};

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
        auditLogPayload(caller, dogId, documentId, {
          operation_id: operationId,
          // Todos os valores abaixo descrevem o objeto CANÔNICO selado,
          // nunca a metadata do staging.
          storage_path: storagePath,
          document_type: input.documentType,
          mime_type: verified.contentType,
          size_bytes: verified.sizeBytes,
          checksum_md5: verified.md5Hash,
          checksum_crc32c: verified.crc32c,
          storage_generation: verified.generation,
          source_generation: sourceGeneration,
          seal_version: HEALTH_DOCUMENT_SEAL_VERSION,
        }),
      );

      return {
        dog_id: dogId,
        document_id: documentId,
        storage_path: storagePath,
        reference: healthDocumentRef(documentId),
        was_no_op: false,
        dogId,
        documentId,
        storagePath,
        wasNoOp: false,
      };
    });

    // Limpeza do staging é BEST-EFFORT e acontece só depois do commit.
    //
    // Falhar aqui não invalida um HealthDocument já criado: a evidência
    // canônica está selada e o Firestore commitado. Converter isso em erro
    // transformaria uma finalização bem-sucedida em documento clínico
    // "falhado", que é pior do que deixar resíduo. O resíduo é um orphan de
    // upload sem autoridade alguma.
    if (committed.wasNoOp !== true) {
      try {
        await deps.storage.deleteStagingObject(uploadPath);
      } catch (cleanupErr) {
        logger.warn(
          "[healthDocumentFinalizeUpload] falha na limpeza best-effort do " +
            `staging ${uploadPath} (documento canônico permanece válido)`,
          cleanupErr,
        );
      }
    }

    return committed;
  } catch (err) {
    mapLogicError(err);
  }
}
