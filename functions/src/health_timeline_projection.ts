/**
 * Health Timeline Projection Foundation — 5D Gate 5C.5B.2
 *
 * Módulo não-exportado para validação de comportamento local/Emulator.
 * NÃO é Cloud Function ativa. NÃO possui trigger produtivo conectado.
 *
 * Decisões O3-D1 a O3-D8 estão FROZEN (conforme 5C.5B.1).
 *
 * Escopo:
 * - deriveTimelineId (ID determinístico)
 * - MealLog → TimelineEntry projection
 * - SupplementLog → TimelineEntry projection
 * - Equivalence model
 * - Projection idempotency
 * - Reconciliation engine (bounded + incremental)
 * - Orphan detection
 * - Zero legacy writes
 */
import * as crypto from "crypto";

// ─────────────────────────────────────────────────────────────────────────────
// CRYPTO UTILITIES (inlined from health_schedule_logic)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Stable stringify for deterministic serialization.
 * Ensures array order matters and string values are quoted.
 */
function stableStringify(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "number" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map((v) => stableStringify(v)).join(",")}]`;
  }
  if (typeof value === "object") {
    const keys = Object.keys(value as Record<string, unknown>).sort();
    const pairs = keys.map((k) => `${JSON.stringify(k)}:${stableStringify((value as Record<string, unknown>)[k])}`);
    return `{${pairs.join(",")}}`;
  }
  return JSON.stringify(value);
}

/**
 * SHA-256 hex digest.
 */
function sha256Hex(data: string): string {
  return crypto.createHash("sha256").update(data, "utf8").digest("hex");
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────────

export type TimelineType = "meal" | "supplement" | "weight" | "clinical" | "vaccine";

export type SourceCollection =
  | "dogs/{dogId}/meal_logs"
  | "dogs/{dogId}/supplement_logs"
  | "dogs/{dogId}/weight_records"
  | "dogs/{dogId}/clinical_events"
  | "dogs/{dogId}/vaccine_records";

export type ProjectionStatus = "final" | "pending" | "cancelled";

export type TimelineEntry = {
  timeline_type: TimelineType;
  source_collection: string;
  source_id: string;
  occurred_at: string; // ISO-8601
  status: ProjectionStatus;
  recorded_at: string; // ISO-8601
  recorded_by: {
    uid: string;
    name: string;
    internal_role: string;
  };
  // Required fields per §3.1 of HEALTH_V1_FIRESTORE_SCHEMA.md
  dog_id: string;
  projected_at: string; // ISO-8601, set on CREATE/REPAIR
  title: string;
  // Presentation mapping
  subtitle?: string;
  // Metadata
  schema_version: number;
  created_at: string;
  updated_at: string;
};

export type MealLogData = {
  id: string;
  dogId: string;
  kind: "planned" | "adhoc";
  acceptance: string;
  offered_grams: number;
  consumed_grams: number | null;
  fed_at: string; // ISO-8601
  recorded_at: string;
  recorded_by: {
    uid: string;
    name: string;
    internal_role: string;
  };
  food_name?: string;
  period?: string;
  // Planned meal only
  plan_id?: string;
  planned_meal_id?: string;
  meal_occurrence_id?: string;
  scheduled_for?: string;
};

export type SupplementLogData = {
  id: string;
  dogId: string;
  supplement_name: string;
  dose: number;
  unit: string;
  administered_at: string; // ISO-8601
  recorded_at: string;
  recorded_by: {
    uid: string;
    name: string;
    internal_role: string;
  };
  nutrition_plan_id?: string | null;
  supplement_regimen_id?: string | null;
  notes?: string | null;
};

export type EquivalenceResult = "equivalent" | "divergent";

export type ProjectionOperationResult = "created" | "noop" | "repaired";

export type ReconciliationState =
  | "missing"
  | "equivalent"
  | "divergent"
  | "orphan";

export type OrphanCheckResult = {
  source_collection: string;
  source_id: string;
  exists: boolean;
  equivalent?: boolean;
};

// ─────────────────────────────────────────────────────────────────────────────
// DETERMINISTIC TIMELINE ID — O3-D6 FROZEN
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Deriva ID determinístico para health_timeline entry.
 *
 * Fórmula (O3-D6 FROZEN):
 * timelineId = "tl1_" + sha256Hex(stableStringify([
 *   "health_timeline_v1",
 *   source_collection,  // "dogs/{dogId}/meal_logs"
 *   source_id           // document ID only
 * ]))
 *
 * NÃO inclui: occurred_at, recorded_at, title, subtitle, revision
 */
export function deriveTimelineId(params: {
  sourceCollection: SourceCollection | string;
  sourceId: string;
}): string {
  const preimage = stableStringify([
    "health_timeline_v1",
    params.sourceCollection,
    params.sourceId,
  ]);
  return `tl1_${sha256Hex(preimage)}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// PROJECTION: MealLog → TimelineEntry
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Projeta MealLog para TimelineEntry.
 *
 * Mapeamento (O3-D1, O3-D5 FROZEN):
 * - timeline_type: "meal"
 * - source_collection: "dogs/{dogId}/meal_logs"
 * - source_id: MealLog document ID
 * - occurred_at: fed_at
 * - status: "final"
 * - recorded_at: preserve from source
 * - recorded_by: preserve from source
 * - dog_id: derivado do contexto (dogId)
 * - projected_at: definido no momento da projeção (não participa do ID)
 * - title: food_name ou "Refeição"
 * - schema_version: 1
 */
export function projectMealLog(
  mealLog: MealLogData,
  timelineId: string,
): TimelineEntry {
  const now = new Date().toISOString();
  const sourceCollection = `dogs/${mealLog.dogId}/meal_logs`;

  // PROTOTYPE PRESENTATION MAPPING
  const foodLabel = mealLog.food_name || "Refeição";
  const kindLabel = mealLog.kind === "planned" ? "Planejada" : "Avulsa";
  const acceptanceLabel = mealLog.acceptance === "full" ? "Completa" :
    mealLog.acceptance === "partial" ? "Parcial" :
      mealLog.acceptance === "refused" ? "Recusada" : mealLog.acceptance;
  const title = `${foodLabel}`;
  const subtitle = `${kindLabel} · ${acceptanceLabel}`;

  return {
    timeline_type: "meal",
    source_collection: sourceCollection,
    source_id: mealLog.id,
    occurred_at: mealLog.fed_at,
    status: "final",
    recorded_at: mealLog.recorded_at,
    recorded_by: mealLog.recorded_by,
    dog_id: mealLog.dogId,
    projected_at: now,
    title,
    subtitle,
    schema_version: 1,
    created_at: now,
    updated_at: now,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// PROJECTION: SupplementLog → TimelineEntry
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Projeta SupplementLog para TimelineEntry.
 *
 * Mapeamento (O3-D1, O3-D5 FROZEN):
 * - timeline_type: "supplement"
 * - source_collection: "dogs/{dogId}/supplement_logs"
 * - source_id: SupplementLog document ID
 * - occurred_at: administered_at
 * - status: "final"
 * - recorded_at: preserve from source
 * - recorded_by: preserve from source
 * - dog_id: derivado do contexto (dogId)
 * - projected_at: definido no momento da projeção (não participa do ID)
 * - title: supplement_name
 * - schema_version: 1
 */
export function projectSupplementLog(
  supplementLog: SupplementLogData,
  timelineId: string,
): TimelineEntry {
  const now = new Date().toISOString();
  const sourceCollection = `dogs/${supplementLog.dogId}/supplement_logs`;

  // PROTOTYPE PRESENTATION MAPPING
  const title = supplementLog.supplement_name;
  const subtitle = `${supplementLog.dose} ${supplementLog.unit}`;

  return {
    timeline_type: "supplement",
    source_collection: sourceCollection,
    source_id: supplementLog.id,
    occurred_at: supplementLog.administered_at,
    status: "final",
    recorded_at: supplementLog.recorded_at,
    recorded_by: supplementLog.recorded_by,
    dog_id: supplementLog.dogId,
    projected_at: now,
    title,
    subtitle,
    schema_version: 1,
    created_at: now,
    updated_at: now,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// EQUIVALENCE MODEL
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compara projeção esperada com projeção materializada.
 *
 * Campos comparados (autoridade da fonte canônica):
 * - timeline_type
 * - source_collection
 * - source_id
 * - occurred_at
 * - status
 * - recorded_at
 * - recorded_by.uid
 * - dog_id
 * - title
 * - subtitle (quando presente)
 * - schema_version
 *
 * Campos NÃO comparados (operação/execução):
 * - projected_at (timestamp de projeção, volátil)
 * - created_at, updated_at (timestamps de execução)
 * - recorded_by.name (pode variar sem afetar equivalência)
 */
export function compareProjection(
  expected: TimelineEntry,
  actual: TimelineEntry | null,
): EquivalenceResult {
  if (actual === null) {
    return "divergent"; // MISSING is treated as divergent for repair
  }

  // Campos de identidade de fonte (devem ser idênticos)
  if (expected.timeline_type !== actual.timeline_type) return "divergent";
  if (expected.source_collection !== actual.source_collection) return "divergent";
  if (expected.source_id !== actual.source_id) return "divergent";
  if (expected.occurred_at !== actual.occurred_at) return "divergent";
  if (expected.status !== actual.status) return "divergent";

  // Campos de registro (devem ser preservados completamente)
  if (expected.recorded_at !== actual.recorded_at) return "divergent";
  if (expected.recorded_by.uid !== actual.recorded_by.uid) return "divergent";
  if (expected.recorded_by.name !== actual.recorded_by.name) return "divergent";
  if (expected.recorded_by.internal_role !== actual.recorded_by.internal_role) return "divergent";

  // Campos derivados persistidos (devem ser equivalentes)
  if (expected.dog_id !== actual.dog_id) return "divergent";
  if (expected.title !== actual.title) return "divergent";
  if (expected.subtitle !== actual.subtitle) return "divergent";
  if (expected.schema_version !== actual.schema_version) return "divergent";

  return "equivalent";
}

// ─────────────────────────────────────────────────────────────────────────────
// PROJECTION OPERATION
// ─────────────────────────────────────────────────────────────────────────────

export type SourceToProject = {
  type: "meal" | "supplement";
  mealLog?: MealLogData;
  supplementLog?: SupplementLogData;
};

/**
 * Determina o estado e retorna o que fazer com a projeção.
 *
 * Estados:
 * - MISSING: fonte existe, entry não existe → CREATE
 * - EQUIVALENT: fonte + entry existem, conteúdo igual → NO-OP
 * - DIVERGENT: fonte + entry existem, conteúdo diferente → REPAIR
 */
export function determineProjectionAction(params: {
  source: SourceToProject;
  existingEntry: TimelineEntry | null;
  expectedEntry: TimelineEntry;
}): { state: ReconciliationState; operation: ProjectionOperationResult | null } {
  if (params.existingEntry === null) {
    return { state: "missing", operation: "created" };
  }

  const equivalence = compareProjection(params.expectedEntry, params.existingEntry);

  if (equivalence === "equivalent") {
    return { state: "equivalent", operation: "noop" };
  }

  return { state: "divergent", operation: "repaired" };
}

// ─────────────────────────────────────────────────────────────────────────────
// LEGACY / DEDUPE CLASSIFICATION — O3-D7 FROZEN
// ─────────────────────────────────────────────────────────────────────────────

export type LegacyClassification =
  | "strong_match"
  | "weak_match"
  | "no_safe_match";

/**
 * Classifica equivalência entre fontes canônicas e legadas.
 *
 * O3-D7 FROZEN:
 * - feeding_events × feedings com legacy_id compartilhado → STRONG_MATCH
 * - MealLog × feeding_events/feedings sem vínculo explícito → NO_SAFE_MATCH
 * - WEAK_MATCH nunca autoriza auto-dedupe
 */
export function classifyLegacyEquivalence(params: {
  canonicalType: "meal_log" | "supplement_log";
  legacyType: string;
  hasExplicitLink: boolean;
}): LegacyClassification {
  const { canonicalType, legacyType, hasExplicitLink } = params;

  // STRONG_MATCH: apenas se vínculo explícito comprovado
  if (hasExplicitLink) {
    // feeding_events × feedings historicamente dual-written
    if (canonicalType === "meal_log" &&
        (legacyType === "feeding_events" || legacyType === "feedings")) {
      return "strong_match";
    }
  }

  // NO_SAFE_MATCH: sem vínculo explícito
  if (!hasExplicitLink) {
    return "no_safe_match";
  }

  // WEAK_MATCH: coincidência sem vínculo (nunca usa para auto-dedupe)
  return "weak_match";
}

/**
 * nutrition_supplements (regime/prescription) ≠ SupplementLog (factual).
 *
 * O3-D8 FROZEN: NUNCA converter nutrition_supplements em supplement timeline
 * sem evidência factual independente de administração.
 */
export function isSupplementRegimen(_regimen: unknown): boolean {
  // PROTOTYPE: marca como regimen para separação
  // Em produção, verificaria estrutura do documento
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// OPERATION INSTRUMENTATION
// ─────────────────────────────────────────────────────────────────────────────

export type OperationCounts = {
  sourceReads: number;
  timelineReads: number;
  timelineCreates: number;
  timelineRepairs: number;
  noOps: number;
  orphanChecks: number;
};

export function createOperationCounter(): OperationCounts & {
  snapshot: () => OperationCounts;
  reset: () => void;
} {
  const counts: OperationCounts = {
    sourceReads: 0,
    timelineReads: 0,
    timelineCreates: 0,
    timelineRepairs: 0,
    noOps: 0,
    orphanChecks: 0,
  };

  return {
    ...counts,
    snapshot: () => ({ ...counts }),
    reset: () => {
      counts.sourceReads = 0;
      counts.timelineReads = 0;
      counts.timelineCreates = 0;
      counts.timelineRepairs = 0;
      counts.noOps = 0;
      counts.orphanChecks = 0;
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CURSOR TYPES FOR BOUNDED RECONCILIATION
// ─────────────────────────────────────────────────────────────────────────────

export type CursorState = {
  last_processed_id: string | null;
  last_timestamp: string | null; // ISO-8601
  page_count: number;
};

export type WatermarkState = {
  dogId: string;
  max_occurred_at: string; // ISO-8601
  last_reconciliation_run: string; // ISO-8601
};

// ─────────────────────────────────────────────────────────────────────────────
// TEST CONFIGURATION (NOT PRODUCTION CONTRACT)
// ─────────────────────────────────────────────────────────────────────────────

export const TEST_CONFIG = {
  /** TEST CONFIGURATION ONLY — NOT PRODUCTION CONTRACT */
  FRESHNESS_OVERLAP_MS: 60 * 60 * 1000, // 1 hour overlap
  HISTORICAL_PAGE_SIZE: 3,
  ORPHAN_PAGE_SIZE: 3,
  HISTORICAL_FREQUENCY: "weekly",
  ORPHAN_FREQUENCY: "daily",
} as const;
