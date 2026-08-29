/**
 * HEALTH-V1-OP-AUTH — camada de transporte do mutation owner de turno.
 *
 * Wrapper fino no padrão Health v1: o `onCall` exportado em `index.ts` monta as
 * deps e delega; toda a lógica vive no engine, exercitável por teste unitário.
 *
 * Stage HEALTH-V1-OP-AUTH — implementação local. Não deployado.
 */

import * as admin from "firebase-admin";
// Import modular, idiomático do repo (health_schedule_callables /
// health_nutrition_firestore_adapter). O namespace `admin.firestore.*` resolve
// para undefined sob `__importStar` no runtime compilado — só o transporte real
// no emulador expõe isso, porque o fake de teste injeta as próprias deps.
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";
import {RawQuery} from "./health_readiness_evidence_logic";
import {
  JsonMap,
  runShiftAuthorizedCommand,
  ShiftActor,
  ShiftAuthorizationError,
  ShiftAuthorizedAction,
  ShiftCommandInput,
  ShiftEngineDeps,
  ShiftTxDocSnap,
  ShiftTxn,
  VehicleInput,
} from "./shift_authorization_engine";

/** Deps reais em Admin SDK. */
export function createAdminShiftEngineDeps(
  db: admin.firestore.Firestore,
): ShiftEngineDeps {
  return {
    runTransaction: async <T>(fn: (txn: ShiftTxn) => Promise<T>): Promise<T> => {
      return db.runTransaction(async (tx) => {
        const wrapper: ShiftTxn = {
          get: async (path: string): Promise<ShiftTxDocSnap> => {
            const snap = await tx.get(db.doc(path));
            return {exists: snap.exists, data: snap.data() as JsonMap | undefined};
          },
          getCollection: async (path: string): Promise<RawQuery> => {
            // Leitura transacional: a autorização não pode enxergar um estado
            // diferente daquele em que a mutação será aplicada.
            try {
              const snap = await tx.get(db.collection(path));
              return {
                kind: "docs",
                docs: snap.docs.map((doc) => ({
                  id: doc.id,
                  data: doc.data() as JsonMap,
                })),
              };
            } catch (error) {
              // Falha de leitura NUNCA vira "sem restrições" — o guard trata
              // `failed` como fail-closed.
              logger.error("Falha ao ler restrições operacionais", {path, error});
              return {kind: "failed", reasonCode: "restrictions_query_failed"};
            }
          },
          set: (path: string, data: JsonMap, options?: {merge?: boolean}) => {
            if (options?.merge) {
              tx.set(db.doc(path), data, {merge: true});
            } else {
              tx.set(db.doc(path), data);
            }
          },
        };
        return fn(wrapper);
      });
    },
    createEntityId: () => db.collection("temp").doc().id,
    serverTimestamp: () => FieldValue.serverTimestamp(),
    timestampFromDate: (date: Date) => Timestamp.fromDate(date),
    arrayUnion: (...items: unknown[]) => FieldValue.arrayUnion(...items),
    deleteField: () => FieldValue.delete(),
    activeShiftVehicleId: async (ra: string) => {
      const snap = await db.collection("active_shifts").doc(ra).get();
      if (!snap.exists) return null;
      const data = snap.data() ?? {};
      const vehicleId = data.vehicle_id;
      return typeof vehicleId === "string" && vehicleId.trim() !== "" ?
        vehicleId.trim() :
        null;
    },
    activeCrewMemberRas: async (vehicleId: string, excludingRa: string) => {
      const snap = await db
        .collection("active_shifts")
        .where("vehicle_id", "==", vehicleId)
        .where("status", "==", "active")
        .get();
      return snap.docs
        .map((doc) => doc.id)
        .filter((ra) => ra !== excludingRa);
    },
  };
}

/** Traduz erro de domínio para o transporte, preservando o código de aplicação. */
export function mapShiftAuthorizationError(error: unknown): never {
  if (error instanceof HttpsError) throw error;
  if (error instanceof ShiftAuthorizationError) {
    throw new HttpsError(error.httpCode, error.message, {
      code: error.appCode,
      ...(error.details ?? {}),
    });
  }
  logger.error("Erro interno na autorização de turno:", error);
  throw new HttpsError("internal", "Erro interno ao processar a operação de turno.", {
    code: "internal_error",
  });
}

const VALID_ACTIONS: readonly ShiftAuthorizedAction[] = [
  "start_shift",
  "switch_dog",
  "assume_vehicle",
];

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpsError("invalid-argument", `${field} inválido.`);
  }
  return value.trim();
}

function readDogId(value: unknown): string {
  const dogId = requireString(value, "dogId");
  if (
    dogId.length > 128 ||
    dogId.includes("/") ||
    dogId === "." ||
    dogId === ".."
  ) {
    throw new HttpsError("invalid-argument", "dogId invalido.");
  }
  return dogId;
}

function readOptionalString(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function readVehicle(value: unknown): VehicleInput | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object") {
    throw new HttpsError("invalid-argument", "vehicle inválido.");
  }
  const raw = value as JsonMap;
  const id = requireString(raw.id, "vehicle.id");
  const crewSize = raw.crew_size ?? raw.crewSize;
  return {
    id,
    label: readOptionalString(raw.label),
    prefix: readOptionalString(raw.prefix),
    modelName: readOptionalString(raw.model_name ?? raw.modelName),
    unit: readOptionalString(raw.unit),
    crewSize: typeof crewSize === "number" ? crewSize : null,
  };
}

function readAcknowledgedIds(value: unknown): readonly string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) {
    throw new HttpsError(
      "invalid-argument",
      "acknowledgedRestrictionIds deve ser uma lista.",
    );
  }
  const out: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string" || entry.trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        "acknowledgedRestrictionIds contém id inválido.",
      );
    }
    out.push(entry.trim());
  }
  return out;
}

export function parseShiftCommandInput(
  data: unknown,
): ShiftCommandInput {
  const raw = (data ?? {}) as JsonMap;
  const action = requireString(raw.action, "action") as ShiftAuthorizedAction;
  if (!VALID_ACTIONS.includes(action)) {
    throw new HttpsError("invalid-argument", `action desconhecida: ${action}.`);
  }

  const startedAtRaw = readOptionalString(raw.startedAt);
  let startedAt: Date | undefined;
  if (startedAtRaw !== null) {
    const parsed = new Date(startedAtRaw);
    if (Number.isNaN(parsed.getTime())) {
      throw new HttpsError("invalid-argument", "startedAt inválido.");
    }
    startedAt = parsed;
  }

  return {
    action,
    dogId: readDogId(raw.dogId),
    operationId: requireString(raw.operationId, "operationId"),
    acknowledgedRestrictionIds: readAcknowledgedIds(
      raw.acknowledgedRestrictionIds,
    ),
    startedAt,
    handlerName: readOptionalString(raw.handlerName),
    shiftGroupId: readOptionalString(raw.shiftGroupId),
    shiftGroupCode: readOptionalString(raw.shiftGroupCode),
    shiftGroupLabel: readOptionalString(raw.shiftGroupLabel),
    vehicle: readVehicle(raw.vehicle),
    role: readOptionalString(raw.role),
  };
}

export interface ShiftAuthorizationCallableDeps {
  readonly db: admin.firestore.Firestore;
  /**
   * Autoriza o chamador para a ação operacional e devolve a identidade factual.
   *
   * A identidade é sempre derivada do token, nunca do payload: um cliente não
   * pode operar turno alheio informando outro RA.
   */
  readonly requireShiftActor: (
    auth: CallableRequest["auth"],
  ) => Promise<ShiftActor>;
  /** Acesso ao K9 (mesmas vias das Rules, reproduzidas para o Admin SDK). */
  readonly requireDogAccess: (
    auth: CallableRequest["auth"],
    actor: ShiftActor,
    dogId: string,
  ) => Promise<void>;
  readonly createEngineDeps?: () => ShiftEngineDeps;
  readonly now?: () => Date;
}

export function buildShiftAuthorizedCommandHandler(
  deps: ShiftAuthorizationCallableDeps,
) {
  return async (request: CallableRequest) => {
    // Ordem explícita: auth → payload válido → acesso ao K9 → guard → mutação.
    const actor = await deps.requireShiftActor(request.auth);
    const input = parseShiftCommandInput(request.data);
    await deps.requireDogAccess(request.auth, actor, input.dogId);

    const engineDeps =
      deps.createEngineDeps?.() ?? createAdminShiftEngineDeps(deps.db);
    const now = deps.now?.() ?? new Date();

    try {
      const result = await runShiftAuthorizedCommand(
        engineDeps,
        actor,
        input,
        now,
      );
      return {
        ok: true,
        action: result.action,
        dogId: result.dogId,
        decision: result.decision,
        restrictions: result.restrictions,
        acknowledgementRecorded: result.acknowledgementRecorded,
        shiftId: result.shiftId,
        wasNoOp: result.wasNoOp,
      };
    } catch (error) {
      return mapShiftAuthorizationError(error);
    }
  };
}
