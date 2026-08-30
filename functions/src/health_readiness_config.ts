/**
 * Readiness v1 — server-side configuration owner.
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * This module is the ONLY runtime owner of the readiness thresholds. The pure
 * evaluator (`health_readiness_policy.ts`) never reads Firebase: it receives a
 * resolved `ReadinessConfig`. Configuration lives server-side only — the client
 * has no say in readiness thresholds.
 *
 * Ratified defaults (READINESS-V1 human decision):
 *   HEALTH_READINESS_WEIGHT_MAX_AGE_DAYS       = 90
 *   HEALTH_READINESS_CONSULTATION_MAX_AGE_DAYS = 180
 *
 * There is deliberately no exam parameter: exam is not a readiness gate.
 */

import {defineInt} from "firebase-functions/params";
import {ReadinessConfig} from "./health_readiness_policy";

/**
 * Typed server-side parameters.
 *
 * Declared at module scope so the Functions runtime can discover them for
 * deploy-time prompting/validation, per the firebase-functions params contract.
 */
export const weightMaxAgeDaysParam = defineInt(
  "HEALTH_READINESS_WEIGHT_MAX_AGE_DAYS",
  {
    default: 90,
    description:
      "Idade máxima (dias) de uma pesagem para contar como recente na prontidão.",
  },
);

export const consultationMaxAgeDaysParam = defineInt(
  "HEALTH_READINESS_CONSULTATION_MAX_AGE_DAYS",
  {
    default: 180,
    description:
      "Idade máxima (dias) de uma consulta para contar como recente na prontidão.",
  },
);

/** Ratified fallbacks, used when a param resolves to a non-usable value. */
const RATIFIED_WEIGHT_MAX_AGE_DAYS = 90;
const RATIFIED_CONSULTATION_MAX_AGE_DAYS = 180;

/**
 * Narrow surface so callers/tests can supply resolved values without depending
 * on the Firebase params runtime.
 */
export interface ReadinessConfigSource {
  weightMaxAgeDays: () => number;
  consultationMaxAgeDays: () => number;
}

export const paramsConfigSource: ReadinessConfigSource = {
  weightMaxAgeDays: () => weightMaxAgeDaysParam.value(),
  consultationMaxAgeDays: () => consultationMaxAgeDaysParam.value(),
};

/**
 * A threshold must be a finite positive integer. Anything else (0, negative,
 * fractional, NaN) is a misconfiguration: fall back to the ratified default
 * rather than evaluating readiness against a nonsensical window.
 */
function usableThreshold(raw: number, ratifiedDefault: number): number {
  if (!Number.isFinite(raw)) return ratifiedDefault;
  if (!Number.isInteger(raw)) return ratifiedDefault;
  if (raw <= 0) return ratifiedDefault;
  return raw;
}

/**
 * Resolves the readiness configuration at the Functions boundary.
 *
 * Call this once per invocation and pass the result down; never read params
 * from inside domain logic.
 */
export function resolveReadinessConfig(
  source: ReadinessConfigSource = paramsConfigSource,
): ReadinessConfig {
  return {
    weightMaxAgeDays: usableThreshold(
      source.weightMaxAgeDays(),
      RATIFIED_WEIGHT_MAX_AGE_DAYS,
    ),
    consultationMaxAgeDays: usableThreshold(
      source.consultationMaxAgeDays(),
      RATIFIED_CONSULTATION_MAX_AGE_DAYS,
    ),
  };
}
