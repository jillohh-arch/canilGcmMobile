/**
 * Fail-closed activation guard for healthTimelineReconcileDaily.
 *
 * Stage D.2A — Local implementation only. Not deployed.
 *
 * Purpose:
 *   Allows structural deployment of the scheduler export without risking
 *   uncontrolled production reconciliation before Stage E authorization.
 *
 * Contract:
 *   - Default (absent or unrecognized value): disabled.
 *   - Explicit value "true": enabled.
 *   - Any other value (including "false", "1", "yes", empty): disabled.
 *   - No exception is thrown for disabled state.
 *
 * Env var: HEALTH_TIMELINE_RECONCILIATION_ENABLED
 */

export interface ActivationGuardResult {
  enabled: boolean;
}

/**
 * Reads and parses the activation guard from process.env.
 *
 * Fail-closed by design: only the exact string "true" enables reconciliation.
 * Any absent, empty, invalid, or ambiguous value disables it.
 */
export function readActivationGuard(
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
): ActivationGuardResult {
  const raw = env["HEALTH_TIMELINE_RECONCILIATION_ENABLED"];
  const enabled = raw === "true";
  return {enabled};
}
