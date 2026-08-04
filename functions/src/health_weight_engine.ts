import {
  fingerprintWeightRecord,
  matchWeightReceipt,
  parseWeightCreatePayload,
  WEIGHT_SCHEMA_VERSION,
  WeightCaller,
  WeightMutationResult,
} from "./health_weight_logic";

export type JsonMap = Record<string, unknown>;

export interface WeightTxDocSnap {
  exists: boolean;
  data: JsonMap | undefined;
}

export interface WeightTxn {
  get: (path: string) => Promise<WeightTxDocSnap>;
  set: (path: string, data: JsonMap, options?: {merge?: boolean}) => void;
}

export interface WeightEngineDeps {
  runTransaction: <T>(
    fn: (txn: WeightTxn) => Promise<T>
  ) => Promise<T>;
  createEntityId: () => string;
  serverTimestamp: () => unknown;
  arrayUnion: (...items: unknown[]) => unknown;
  timestampFromDate: (date: Date) => unknown;
}

export interface RunCreateWeightOptions {
  deps: WeightEngineDeps;
  rawPayload: Record<string, unknown>;
  actor: WeightCaller;
  serverNow?: Date;
}

export class WeightEngineError extends Error {
  constructor(
    public readonly httpCode:
      | "invalid-argument"
      | "not-found"
      | "permission-denied"
      | "failed-precondition"
      | "already-exists"
      | "unauthenticated",
    public readonly appCode: string,
    message: string
  ) {
    super(message);
    this.name = "WeightEngineError";
  }
}

export async function runCreateWeightRecord(
  options: RunCreateWeightOptions
): Promise<WeightMutationResult> {
  const {deps, rawPayload, actor, serverNow = new Date()} = options;

  if (actor.internalRole !== "condutor" && actor.internalRole !== "admin") {
    throw new WeightEngineError(
      "permission-denied",
      "invalid_internal_role",
      "Papel interno ausente ou desconhecido."
    );
  }

  let parsed;
  try {
    parsed = parseWeightCreatePayload(rawPayload, serverNow);
  } catch (err) {
    throw new WeightEngineError(
      "invalid-argument",
      "validation_error",
      (err as Error).message
    );
  }

  const {dogId, operationId, weightKg, measuredAt, context, notes} = parsed;
  const measuredAtIso = measuredAt.toISOString();
  const fingerprint = fingerprintWeightRecord({
    dogId,
    weightKg,
    measuredAtIso,
    context,
    notes,
  });

  const receiptPath = `dogs/${dogId}/weight_operations/${operationId}`;
  const dogPath = `dogs/${dogId}`;

  return deps.runTransaction(async (txn) => {
    // 1. Consulta Receipt ANTES de qualquer escrita (Durable Replay)
    const receiptSnap = await txn.get(receiptPath);

    if (receiptSnap.exists) {
      const match = matchWeightReceipt(
        receiptSnap.data,
        dogId,
        fingerprint
      );

      if (match === "replay") {
        const resData = (receiptSnap.data?.result ?? {}) as JsonMap;
        return {
          dogId,
          entityId: (resData.entityId as string) || (receiptSnap.data?.entity_id as string),
          weightKg: (resData.weightKg as number) ?? weightKg,
          revision: (resData.revision as number) ?? 1,
          wasNoOp: true,
        };
      }

      throw new WeightEngineError(
        "failed-precondition",
        "idempotency_conflict",
        "operationId colide com receipt de outra operação ou payload de pesagem diferente."
      );
    }

    // 2. Valida existência do K9
    const dogSnap = await txn.get(dogPath);
    if (!dogSnap.exists) {
      throw new WeightEngineError(
        "not-found",
        "k9_not_found",
        "K9 não encontrado."
      );
    }

    const dogData = dogSnap.data ?? {};
    const dogName =
      (dogData.name as string) || (dogData.nome as string) || dogId;

    // 3. Cria ID de entidade estático para o WeightRecord
    const entityId = deps.createEntityId();
    const recordPath = `dogs/${dogId}/weight_records/${entityId}`;
    const auditLogPath = `auditLogs/${deps.createEntityId()}`;

    const nowSentinel = deps.serverTimestamp();
    const nowTimestamp = deps.timestampFromDate(serverNow);
    const measuredAtTimestamp = deps.timestampFromDate(measuredAt);

    const auditTrailEntry: JsonMap = {
      action: "created",
      at: nowTimestamp,
      by: actor.uid,
      by_name: actor.name,
      by_ra: actor.ra,
      performed_by: actor.uid,
      performed_at: measuredAtIso,
    };

    // Formato canônico Health Timeline: recorded_by { uid, name, internal_role } (Obrigatório e sem PII)
    const recordData: JsonMap = {
      dogId,
      dog_id: dogId,
      weight_kg: weightKg,
      measured_at: measuredAtTimestamp,
      recorded_by: {
        uid: actor.uid,
        name: actor.name,
        internal_role: actor.internalRole,
      },
      schema_version: WEIGHT_SCHEMA_VERSION,
      created_at: nowSentinel,
      updated_at: nowSentinel,
      audit_trail: [auditTrailEntry],
    };

    if (context !== undefined) {
      recordData.context = context;
    }

    if (notes !== undefined) {
      recordData.notes = notes;
    }

    // Receipt minimizado (Sem PII)
    const receiptData: JsonMap = {
      operation_id: operationId,
      operation_type: "create_weight",
      dog_id: dogId,
      entity_id: entityId,
      actor_uid: actor.uid,
      actor: {
        uid: actor.uid,
        name: actor.name,
        internal_role: actor.internalRole,
      },
      fingerprint,
      result: {
        dogId,
        entityId,
        weightKg,
        revision: 1,
      },
      processed_at: nowSentinel,
      created_at: nowSentinel,
    };

    const dogUpdateData: JsonMap = {
      weight: weightKg,
      _last_weight_kg: weightKg,
      _last_weight_at: measuredAtTimestamp,
      updatedAt: nowSentinel,
      updated_at: nowSentinel,
      audit_trail: deps.arrayUnion({
        action: "weight_updated",
        at: nowTimestamp,
        by: actor.uid,
        by_name: actor.name,
        by_ra: actor.ra,
      }),
    };

    const auditLogData: JsonMap = {
      action: "k9_weight_recorded",
      entity_type: "weight",
      entity_id: entityId,
      entity_path: recordPath,
      summary: `Pesagem registrada para ${dogName}: ${weightKg.toFixed(1)} kg`,
      actor: {
        uid: actor.uid,
        name: actor.name,
        ra: actor.ra,
      },
      metadata: {dog_id: dogId, weight_kg: weightKg, context: context ?? null},
      source: "functions",
      performed_at: nowSentinel,
      createdAt: nowSentinel,
    };

    // 4. Execução atômica no Transaction (Option A — Clean Write)
    txn.set(receiptPath, receiptData);
    txn.set(recordPath, recordData);
    txn.set(dogPath, dogUpdateData, {merge: true});
    txn.set(auditLogPath, auditLogData);

    return {
      dogId,
      entityId,
      weightKg,
      revision: 1,
      wasNoOp: false,
    };
  });
}
