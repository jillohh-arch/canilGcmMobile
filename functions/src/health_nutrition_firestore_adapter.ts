/**
 * Adapter concreto Admin Firestore ↔ Nutrition mutation engine (5D Gate 2).
 *
 * - getDoc: receipt lookup pré-txn (e decodificação fail-closed)
 * - runTransaction: recheck + plan authority + writes canônicos
 * - server timestamps em campos de autoridade de servidor
 * - zero write em collections legadas
 */
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  NutritionActor,
  NutritionEngineDeps,
  NutritionTxn,
  TxDocSnap,
} from "./health_nutrition_engine";
import {
  FORBIDDEN_LEGACY_WRITE_COLLECTIONS,
  nutritionError,
} from "./health_nutrition_logic";

export type JsonMap = Record<string, unknown>;

/** Campos de autoridade de relógio do servidor (não fatos do cliente). */
const SERVER_TIMESTAMP_FIELDS = new Set([
  "processed_at",
  "recorded_at",
  "performed_at",
  "createdAt",
]);

/** Fatos temporais do cliente / derivados de materialização (não sentinels). */
const CLIENT_INSTANT_FIELDS = new Set([
  "fed_at",
  "administered_at",
  "scheduled_for",
  "valid_from",
  "valid_until",
]);

export function docRefFromPath(
  db: FirebaseFirestore.Firestore,
  path: string,
): FirebaseFirestore.DocumentReference {
  const parts = path.split("/").filter((p) => p.length > 0);
  if (parts.length < 2 || parts.length % 2 !== 0) {
    throw nutritionError(
      "integrity",
      `Path Firestore inválido para DocumentReference: ${path}`,
    );
  }
  let ref: FirebaseFirestore.DocumentReference = db
    .collection(parts[0])
    .doc(parts[1]);
  for (let i = 2; i < parts.length; i += 2) {
    ref = ref.collection(parts[i]).doc(parts[i + 1]);
  }
  return ref;
}

export function assertCanonicalWritePath(path: string): void {
  for (const col of FORBIDDEN_LEGACY_WRITE_COLLECTIONS) {
    if (
      path === col ||
      path.startsWith(`${col}/`) ||
      path.includes(`/${col}/`)
    ) {
      throw nutritionError(
        "integrity",
        `Write proibido em collection legada: ${path}`,
      );
    }
  }
  // Paths canônicos de mutação nutrição:
  // dogs/{id}/meal_logs|supplement_logs|nutrition_operations|nutrition_plans (read)
  // auditLogs/{id}
  if (path.startsWith("auditLogs/")) return;
  const m = path.match(
    /^dogs\/[^/]+\/(meal_logs|supplement_logs|nutrition_operations|nutrition_plans)\/[^/]+$/,
  );
  if (!m) {
    throw nutritionError(
      "integrity",
      `Write path fora do conjunto canônico de nutrição: ${path}`,
    );
  }
}

function convertFirestoreValue(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return value.map(convertFirestoreValue);
  }
  if (typeof value === "object") {
    // FieldValue sentinels / refs — não devem aparecer em reads de docs materializados
    const ctor = (value as {constructor?: {name?: string}}).constructor?.name;
    if (ctor && ctor !== "Object") {
      // Timestamp já tratado; demais objetos opacos → string defensiva
      if (
        typeof (value as {toDate?: () => Date}).toDate === "function"
      ) {
        try {
          return (value as {toDate: () => Date}).toDate().toISOString();
        } catch {
          return value;
        }
      }
      return value;
    }
    const out: JsonMap = {};
    for (const [k, v] of Object.entries(value as JsonMap)) {
      out[k] = convertFirestoreValue(v);
    }
    return out;
  }
  return value;
}

export function firestoreDataToPlain(
  data: FirebaseFirestore.DocumentData | undefined,
): JsonMap {
  if (!data) return {};
  return convertFirestoreValue(data) as JsonMap;
}

function toFirestoreTimestamp(value: unknown): unknown {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value === "string" && value.trim() !== "") {
    const d = new Date(value);
    if (!Number.isNaN(d.getTime())) return Timestamp.fromDate(d);
  }
  return value;
}

/**
 * Prepara payload de escrita:
 * - server timestamps em campos de autoridade
 * - Timestamps Firestore em instants de fato
 * - proíbe paths legados (defense in depth)
 */
export function prepareWriteData(data: JsonMap): JsonMap {
  const out: JsonMap = {};
  for (const [key, value] of Object.entries(data)) {
    if (SERVER_TIMESTAMP_FIELDS.has(key)) {
      out[key] = FieldValue.serverTimestamp();
      continue;
    }
    if (CLIENT_INSTANT_FIELDS.has(key)) {
      if (value === null || value === undefined) {
        out[key] = value;
      } else {
        out[key] = toFirestoreTimestamp(value);
      }
      continue;
    }
    if (value && typeof value === "object" && !Array.isArray(value)) {
      const ctor = (value as {constructor?: {name?: string}}).constructor?.name;
      if (ctor === "Object") {
        out[key] = prepareWriteData(value as JsonMap);
        continue;
      }
    }
    out[key] = value;
  }
  return out;
}

export function snapFromFirestore(
  snap: FirebaseFirestore.DocumentSnapshot,
): TxDocSnap {
  return {
    exists: snap.exists,
    data: firestoreDataToPlain(snap.data()),
  };
}

/**
 * Decodifica receipt Firestore para o contrato do engine.
 * Malformado → integrity (não missing).
 */
export function decodeNutritionReceiptDoc(
  snap: TxDocSnap,
): TxDocSnap {
  if (!snap.exists) return snap;
  const d = snap.data;
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
    if (d[key] === undefined || d[key] === null || d[key] === "") {
      throw nutritionError(
        "integrity",
        `Receipt malformado: campo obrigatório ausente (${key}).`,
        "receipt_integrity",
      );
    }
  }
  if (typeof d.result !== "object" || Array.isArray(d.result)) {
    throw nutritionError(
      "integrity",
      "Receipt malformado: result inválido.",
      "receipt_integrity",
    );
  }
  return snap;
}

/**
 * MealLog existente: preserva campos do entity_semantic_fingerprint.
 * Documento irrecuperável → integrity/conflict no engine via fingerprint.
 */
export function decodeMealLogDoc(snap: TxDocSnap): TxDocSnap {
  if (!snap.exists) return snap;
  // fail-closed só se documento existe mas sem qualquer semântica útil
  const d = snap.data;
  const hasSemantic =
    !!d.entity_semantic_fingerprint ||
    (!!d.meal_occurrence_id && !!d.acceptance && d.offered_grams !== undefined);
  if (!hasSemantic && !d.create_fingerprint) {
    throw nutritionError(
      "integrity",
      "MealLog existente malformado (sem fingerprint/semântica recuperável).",
      "meal_occurrence_conflict",
    );
  }
  return snap;
}

export type NutritionFirestoreAdapterOptions = {
  /** Relógio injetável (testes). Default: new Date(). */
  serverNow?: () => Date;
  isAdmin?: (actor: NutritionActor) => boolean | Promise<boolean>;
};

/**
 * Constrói NutritionEngineDeps sobre Admin Firestore.
 */
export function createNutritionFirestoreEngineDeps(
  db: FirebaseFirestore.Firestore,
  options: NutritionFirestoreAdapterOptions = {},
): NutritionEngineDeps {
  return {
    serverNow: options.serverNow ?? (() => new Date()),
    isAdmin: options.isAdmin ?? (() => false),
    getDoc: async (path: string): Promise<TxDocSnap> => {
      const snap = await docRefFromPath(db, path).get();
      const plain = snapFromFirestore(snap);
      // Receipts: decode fail-closed
      if (path.includes("/nutrition_operations/")) {
        return decodeNutritionReceiptDoc(plain);
      }
      return plain;
    },
    runTransaction: async <T>(
      fn: (tx: NutritionTxn) => Promise<T>,
    ): Promise<T> => {
      return db.runTransaction(async (firestoreTx) => {
        const adapterTx: NutritionTxn = {
          get: async (path: string): Promise<TxDocSnap> => {
            const snap = await firestoreTx.get(docRefFromPath(db, path));
            const plain = snapFromFirestore(snap);
            if (path.includes("/nutrition_operations/")) {
              return decodeNutritionReceiptDoc(plain);
            }
            if (path.includes("/meal_logs/")) {
              return decodeMealLogDoc(plain);
            }
            return plain;
          },
          set: (path: string, data: JsonMap): void => {
            assertCanonicalWritePath(path);
            const prepared = prepareWriteData(data);
            firestoreTx.set(docRefFromPath(db, path), prepared);
          },
        };
        return fn(adapterTx);
      });
    },
  };
}
