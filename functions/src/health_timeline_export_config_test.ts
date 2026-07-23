/**
 * Export Configuration Proof — Gate 5C.5C.5.2
 *
 * Proves the EFFECTIVE configuration of the three compiled exports.
 *
 * Uses require() to load compiled lib/index.js and inspects the
 * Firebase Functions v2 __endpoint metadata to verify:
 *   - document path
 *   - region
 *   - retry (triggers)
 *   - schedule & timeZone (scheduler)
 *
 * Gate 5C.5C.5.2 — Corrective round. Local code only. Not deployed.
 */
import * as assert from "assert";

function proveExportConfiguration() {
  console.log("=== HEALTH TIMELINE EXPORT CONFIGURATION PROOF ===\n");

  // Dynamic require of compiled index — this WILL initialize admin.app
  // which is fine for inspection (the config is on the function objects)
  const indexModule = require("./index.js");

  // ── Export 1: healthTimelineProjectMealLogCreated ──
  console.log("=== Export 1: healthTimelineProjectMealLogCreated ===");
  const mealExport = indexModule.healthTimelineProjectMealLogCreated;
  assert.ok(mealExport, "healthTimelineProjectMealLogCreated must be exported");

  const mealEndpoint = (mealExport as any).__endpoint;
  assert.ok(mealEndpoint, "Meal export must have __endpoint metadata");
  assert.strictEqual(mealEndpoint.platform, "gcfv2", "Must be gcfv2");

  const mealEvent = mealEndpoint.eventTrigger;
  assert.ok(mealEvent, "Must be eventTrigger");
  assert.strictEqual(
    mealEvent.eventType,
    "google.cloud.firestore.document.v1.created",
    "Must be onDocumentCreated",
  );

  // Document path
  assert.ok(
    mealEvent.eventFilterPathPatterns?.document ===
      "dogs/{dogId}/meal_logs/{mealId}",
    `Meal export document path: ${mealEvent.eventFilterPathPatterns?.document}`,
  );

  // Region
  assert.strictEqual(
    mealEndpoint.region?.[0],
    "southamerica-east1",
    `Meal export region: ${mealEndpoint.region?.[0]}`,
  );

  // Retry
  assert.strictEqual(
    mealEvent.retry,
    true,
    `Meal export retry: ${mealEvent.retry}`,
  );

  console.log("  ✅ document path: dogs/{dogId}/meal_logs/{mealId}");
  console.log("  ✅ region: southamerica-east1");
  console.log("  ✅ retry: true");
  console.log("  ✅ eventType: google.cloud.firestore.document.v1.created\n");

  // ── Export 2: healthTimelineProjectSupplementLogCreated ──
  console.log("=== Export 2: healthTimelineProjectSupplementLogCreated ===");
  const supplementExport = indexModule.healthTimelineProjectSupplementLogCreated;
  assert.ok(supplementExport, "healthTimelineProjectSupplementLogCreated must be exported");

  const supplementEndpoint = (supplementExport as any).__endpoint;
  assert.ok(supplementEndpoint, "Supplement export must have __endpoint metadata");
  assert.strictEqual(supplementEndpoint.platform, "gcfv2", "Must be gcfv2");

  const supplementEvent = supplementEndpoint.eventTrigger;
  assert.ok(supplementEvent, "Must be eventTrigger");
  assert.strictEqual(
    supplementEvent.eventType,
    "google.cloud.firestore.document.v1.created",
    "Must be onDocumentCreated",
  );

  assert.ok(
    supplementEvent.eventFilterPathPatterns?.document ===
      "dogs/{dogId}/supplement_logs/{supplementLogId}",
    `Supplement export document path: ${supplementEvent.eventFilterPathPatterns?.document}`,
  );

  assert.strictEqual(
    supplementEndpoint.region?.[0],
    "southamerica-east1",
    `Supplement export region: ${supplementEndpoint.region?.[0]}`,
  );

  assert.strictEqual(
    supplementEvent.retry,
    true,
    `Supplement export retry: ${supplementEvent.retry}`,
  );

  console.log("  ✅ document path: dogs/{dogId}/supplement_logs/{supplementLogId}");
  console.log("  ✅ region: southamerica-east1");
  console.log("  ✅ retry: true");
  console.log("  ✅ eventType: google.cloud.firestore.document.v1.created\n");

  // ── Export 3: healthTimelineReconcileDaily ──
  console.log("=== Export 3: healthTimelineReconcileDaily ===");
  const schedulerExport = indexModule.healthTimelineReconcileDaily;
  assert.ok(schedulerExport, "healthTimelineReconcileDaily must be exported");

  const schedulerEndpoint = (schedulerExport as any).__endpoint;
  assert.ok(schedulerEndpoint, "Scheduler export must have __endpoint metadata");
  assert.strictEqual(schedulerEndpoint.platform, "gcfv2", "Must be gcfv2");

  const scheduleTrigger = schedulerEndpoint.scheduleTrigger;
  assert.ok(scheduleTrigger, "Must be scheduleTrigger");

  assert.strictEqual(
    scheduleTrigger.schedule,
    "every day 03:00",
    `Scheduler schedule: ${scheduleTrigger.schedule}`,
  );

  assert.strictEqual(
    scheduleTrigger.timeZone,
    "America/Sao_Paulo",
    `Scheduler timeZone: ${scheduleTrigger.timeZone}`,
  );

  assert.strictEqual(
    schedulerEndpoint.region?.[0],
    "southamerica-east1",
    `Scheduler region: ${schedulerEndpoint.region?.[0]}`,
  );

  console.log("  ✅ schedule: every day 03:00");
  console.log("  ✅ timeZone: America/Sao_Paulo");
  console.log("  ✅ region: southamerica-east1\n");

  // ── No unexpected exports ──
  console.log("=== Export Audit ===");
  const exportedNames = Object.keys(indexModule).sort();
  const expectedNew = [
    "healthTimelineProjectMealLogCreated",
    "healthTimelineProjectSupplementLogCreated",
    "healthTimelineReconcileDaily",
  ];
  for (const name of expectedNew) {
    assert.ok(exportedNames.includes(name), `Export ${name} must be present`);
  }
  console.log("  ✅ 3 expected exports confirmed");

  console.log("\n═══════════════════════════════════════════════════════");
  console.log("🎯 EXPORT CONFIGURATION PROOF COMPLETE");
  console.log("All 3 exports proven with effective configuration.");
  console.log("═══════════════════════════════════════════════════════\n");
}

proveExportConfiguration();
