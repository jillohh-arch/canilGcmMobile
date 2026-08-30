import * as admin from "firebase-admin";
import {logger} from "firebase-functions";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {
  RunCreateWeightOptions,
  runCreateWeightRecord,
  WeightEngineDeps,
  WeightEngineError,
  WeightTxDocSnap,
  WeightTxn,
} from "./health_weight_engine";
import {WeightCaller} from "./health_weight_logic";

export type JsonMap = Record<string, unknown>;

export function createAdminWeightEngineDeps(
  db: admin.firestore.Firestore
): WeightEngineDeps {
  return {
    runTransaction: async <T>(
      fn: (txn: WeightTxn) => Promise<T>
    ): Promise<T> => {
      return db.runTransaction(async (tx) => {
        const wrapperTxn: WeightTxn = {
          get: async (path: string): Promise<WeightTxDocSnap> => {
            const snap = await tx.get(db.doc(path));
            return {
              exists: snap.exists,
              data: snap.data() as JsonMap | undefined,
            };
          },
          set: (path: string, data: JsonMap, options?: {merge?: boolean}) => {
            if (options?.merge) {
              tx.set(db.doc(path), data, {merge: true});
            } else {
              tx.set(db.doc(path), data);
            }
          },
        };
        return fn(wrapperTxn);
      });
    },
    createEntityId: () => db.collection("temp").doc().id,
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
    arrayUnion: (...items: unknown[]) =>
      admin.firestore.FieldValue.arrayUnion(...items),
    timestampFromDate: (d: Date) => admin.firestore.Timestamp.fromDate(d),
  };
}

export function mapWeightError(err: unknown): never {
  if (err instanceof HttpsError) throw err;
  if (err instanceof WeightEngineError) {
    throw new HttpsError(err.httpCode, err.message, {code: err.appCode});
  }

  logger.error("Erro interno no processamento de pesagem:", err);
  throw new HttpsError("internal", "Erro interno no processamento da pesagem.", {code: "internal_error"});
}

export interface HealthWeightCallableDeps {
  db: admin.firestore.Firestore;
  requireHealthRecordRoutine: (
    auth: CallableRequest["auth"]
  ) => Promise<WeightCaller>;
  requireDogAccess: (
    auth: CallableRequest["auth"],
    caller: WeightCaller,
    dogId: string,
    dogData: JsonMap
  ) => Promise<void>;
  createEngineDeps?: () => WeightEngineDeps;
}

export function buildHealthWeightCreateRecordHandler(
  deps: HealthWeightCallableDeps
) {
  return async (request: CallableRequest) => {
    const caller = await deps.requireHealthRecordRoutine(request.auth);

    const data = (request.data ?? {}) as JsonMap;
    const dogId = (data.dogId ?? "") as string;
    const operationId = (data.operationId ?? "") as string;
    const payloadRaw = data.payload;

    if (
      !dogId ||
      typeof dogId !== "string" ||
      !operationId ||
      typeof operationId !== "string" ||
      !payloadRaw ||
      typeof payloadRaw !== "object" ||
      Array.isArray(payloadRaw)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Payload de pesagem inválido. Requer dogId, operationId e objeto payload."
      );
    }

    const payload = payloadRaw as JsonMap;

    const dogSnap = await deps.db.collection("dogs").doc(dogId).get();
    if (!dogSnap.exists) {
      throw new HttpsError("not-found", "K9 não encontrado.");
    }

    await deps.requireDogAccess(
      request.auth,
      caller,
      dogId,
      dogSnap.data() as JsonMap
    );

    const engineDeps = deps.createEngineDeps
      ? deps.createEngineDeps()
      : createAdminWeightEngineDeps(deps.db);

    const opts: RunCreateWeightOptions = {
      deps: engineDeps,
      rawPayload: {
        ...payload,
        dogId,
        operationId,
      },
      actor: caller,
    };

    try {
      const result = await runCreateWeightRecord(opts);
      return result;
    } catch (err) {
      mapWeightError(err);
    }
  };
}
