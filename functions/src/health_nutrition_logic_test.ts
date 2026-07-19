/**
 * Testes unitários — Nutrição 5D Gate 1 (lógica pura).
 * npm run build && node lib/health_nutrition_logic_test.js
 */
import * as assert from "assert";
import {
  assertMealQuantities,
  assertNotFuture,
  decideCreateByFingerprint,
  decidePlannedMealAgainstExisting,
  entitySemanticFingerprintPlannedMeal,
  evaluatePlanEligibility,
  findUtcInstantsForLocalWall,
  fingerprintPlannedMeal,
  localServiceDateFromInstant,
  mealOccurrenceIdV1,
  mealOccurrencePreimage,
  nutritionOperationReceiptIdV1,
  parseAdhocMealCommand,
  parsePlannedMealCommand,
  parseSupplementCommand,
  scheduledForFromLocal,
  sha256Hex,
  adhocMealLogIdV1,
  supplementLogIdV1,
  FORBIDDEN_LEGACY_WRITE_COLLECTIONS,
  CANONICAL_WRITE_COLLECTIONS,
} from "./health_nutrition_logic";

function test(name: string, fn: () => void): void {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`);
    throw e;
  }
}

// ── identity golden ──────────────────────────────────────────────────────────

test("meal occurrence golden preimage + mo1_ id", () => {
  const params = {
    dogId: "dog-1",
    planId: "plan-1",
    plannedMealId: "slot-am",
    localServiceDate: "2026-07-18",
  };
  const pre = mealOccurrencePreimage(params);
  assert.strictEqual(
    pre,
    '["meal_occurrence_v1","dog-1","plan-1","slot-am","2026-07-18"]',
  );
  const expectedHex = sha256Hex(pre);
  const id = mealOccurrenceIdV1(params);
  assert.strictEqual(id, `mo1_${expectedHex}`);
  assert.ok(id.startsWith("mo1_"));
  assert.strictEqual(id.length, 3 + 1 + 64);
});

test("same semantic key → same occurrence id", () => {
  const a = mealOccurrenceIdV1({
    dogId: "d",
    planId: "p",
    plannedMealId: "s",
    localServiceDate: "2026-01-01",
  });
  const b = mealOccurrenceIdV1({
    dogId: "d",
    planId: "p",
    plannedMealId: "s",
    localServiceDate: "2026-01-01",
  });
  assert.strictEqual(a, b);
});

test("dog/plan/slot/date change → different occurrence id", () => {
  const base = {
    dogId: "d",
    planId: "p",
    plannedMealId: "s",
    localServiceDate: "2026-01-01",
  };
  const baseId = mealOccurrenceIdV1(base);
  assert.notStrictEqual(
    mealOccurrenceIdV1({...base, dogId: "d2"}),
    baseId,
  );
  assert.notStrictEqual(
    mealOccurrenceIdV1({...base, planId: "p2"}),
    baseId,
  );
  assert.notStrictEqual(
    mealOccurrenceIdV1({...base, plannedMealId: "s2"}),
    baseId,
  );
  assert.notStrictEqual(
    mealOccurrenceIdV1({...base, localServiceDate: "2026-01-02"}),
    baseId,
  );
});

test("adhoc and supplement ids deterministic", () => {
  const a = adhocMealLogIdV1({
    actorUid: "u1",
    dogId: "d1",
    idempotencyKey: "key-1",
  });
  assert.ok(a.startsWith("ml1_"));
  assert.strictEqual(
    a,
    adhocMealLogIdV1({
      actorUid: "u1",
      dogId: "d1",
      idempotencyKey: "key-1",
    }),
  );
  const s = supplementLogIdV1({
    actorUid: "u1",
    dogId: "d1",
    idempotencyKey: "key-1",
  });
  assert.ok(s.startsWith("sl1_"));
  assert.notStrictEqual(a, s);
});

// ── local service date ───────────────────────────────────────────────────────

test("localServiceDate: 02:30Z → dia anterior em America/Sao_Paulo", () => {
  const instant = new Date("2026-07-19T02:30:00.000Z");
  const d = localServiceDateFromInstant(instant, "America/Sao_Paulo");
  assert.strictEqual(d, "2026-07-18");
});

test("localServiceDate: same instant UTC calendar day in Etc/UTC", () => {
  const instant = new Date("2026-07-19T02:30:00.000Z");
  assert.strictEqual(
    localServiceDateFromInstant(instant, "Etc/UTC"),
    "2026-07-19",
  );
});

test("scheduledFor derivation: 07:00 SP on local date", () => {
  // 2026-07-18 07:00 America/Sao_Paulo = 2026-07-18 10:00Z (UTC-3)
  const sf = scheduledForFromLocal(
    "2026-07-18",
    "07:00",
    "America/Sao_Paulo",
  );
  assert.strictEqual(sf.toISOString(), "2026-07-18T10:00:00.000Z");
});

// ── plan eligibility ─────────────────────────────────────────────────────────

const validFrom = new Date("2026-01-01T00:00:00.000Z");
const validUntil = new Date("2026-06-01T00:00:00.000Z");

test("active + fedAt dentro → aceita", () => {
  const r = evaluatePlanEligibility({
    status: "active",
    validFrom,
    validUntil: null,
    fedAt: new Date("2026-03-01T12:00:00.000Z"),
  });
  assert.strictEqual(r.ok, true);
});

test("active + fedAt antes validFrom → rejeita", () => {
  const r = evaluatePlanEligibility({
    status: "active",
    validFrom,
    validUntil: null,
    fedAt: new Date("2025-12-31T23:59:59.000Z"),
  });
  assert.strictEqual(r.ok, false);
  if (!r.ok) {
    assert.strictEqual(r.code, "nutrition_plan_not_effective_at_fed_at");
  }
});

test("superseded + fedAt dentro → aceita", () => {
  const r = evaluatePlanEligibility({
    status: "superseded",
    validFrom,
    validUntil,
    fedAt: new Date("2026-03-01T00:00:00.000Z"),
  });
  assert.strictEqual(r.ok, true);
});

test("superseded sem validUntil → integrity", () => {
  const r = evaluatePlanEligibility({
    status: "superseded",
    validFrom,
    validUntil: null,
    fedAt: new Date("2026-03-01T00:00:00.000Z"),
  });
  assert.strictEqual(r.ok, false);
  if (!r.ok) assert.strictEqual(r.code, "nutrition_plan_integrity");
});

test("cancelled → rejeita", () => {
  const r = evaluatePlanEligibility({
    status: "cancelled",
    validFrom,
    validUntil: null,
    fedAt: new Date("2026-03-01T00:00:00.000Z"),
  });
  assert.strictEqual(r.ok, false);
  if (!r.ok) assert.strictEqual(r.code, "nutrition_plan_cancelled");
});

test("fedAt exatamente validFrom → aceita", () => {
  const r = evaluatePlanEligibility({
    status: "active",
    validFrom,
    validUntil,
    fedAt: validFrom,
  });
  assert.strictEqual(r.ok, true);
});

test("fedAt exatamente validUntil → rejeita [from, until)", () => {
  const r = evaluatePlanEligibility({
    status: "superseded",
    validFrom,
    validUntil,
    fedAt: validUntil,
  });
  assert.strictEqual(r.ok, false);
});

// ── D42 ──────────────────────────────────────────────────────────────────────

test("D42 matrix + NaN/Inf", () => {
  assert.throws(
    () =>
      assertMealQuantities({
        offeredGrams: Number.NaN,
        consumedGrams: null,
        acceptance: "unknown",
      }),
  );
  assert.throws(
    () =>
      assertMealQuantities({
        offeredGrams: Number.POSITIVE_INFINITY,
        consumedGrams: null,
        acceptance: "unknown",
      }),
  );
  assert.throws(
    () =>
      assertMealQuantities({
        offeredGrams: 100,
        consumedGrams: Number.NEGATIVE_INFINITY,
        acceptance: "unknown",
      }),
  );
  assert.doesNotThrow(() =>
    assertMealQuantities({
      offeredGrams: 100,
      consumedGrams: 0,
      acceptance: "refused",
    }),
  );
  assert.throws(() =>
    assertMealQuantities({
      offeredGrams: 100,
      consumedGrams: null,
      acceptance: "refused",
    }),
  );
  assert.doesNotThrow(() =>
    assertMealQuantities({
      offeredGrams: 100,
      consumedGrams: null,
      acceptance: "full",
    }),
  );
  assert.doesNotThrow(() =>
    assertMealQuantities({
      offeredGrams: 100,
      consumedGrams: 50,
      acceptance: "partial",
    }),
  );
});

test("fedAt futuro rejeitado", () => {
  const now = new Date("2026-07-18T12:00:00.000Z");
  assert.throws(() =>
    assertNotFuture(new Date("2026-07-18T12:00:00.001Z"), now, "fedAt"),
  );
  assert.doesNotThrow(() => assertNotFuture(now, now, "fedAt"));
});

// ── create decision ──────────────────────────────────────────────────────────

test("decideCreate: missing mutate; same fp noop; different conflict", () => {
  assert.strictEqual(
    decideCreateByFingerprint({
      docExists: false,
      storedFingerprint: undefined,
      requestFingerprint: "a",
    }).kind,
    "mutate",
  );
  assert.strictEqual(
    decideCreateByFingerprint({
      docExists: true,
      storedFingerprint: "fp1",
      requestFingerprint: "fp1",
    }).kind,
    "noop",
  );
  const c = decideCreateByFingerprint({
    docExists: true,
    storedFingerprint: "fp1",
    requestFingerprint: "fp2",
  });
  assert.strictEqual(c.kind, "error");
});

// ── command parsers ──────────────────────────────────────────────────────────

test("planned command rejects server-derived fields", () => {
  assert.throws(() =>
    parsePlannedMealCommand({
      dogId: "d",
      planId: "p",
      plannedMealId: "s",
      offeredGrams: 100,
      acceptance: "full",
      fedAt: "2026-07-01T08:00:00.000Z",
      idempotencyKey: "k1",
      period: "morning",
    }),
  );
});

test("adhoc rejects plan link", () => {
  assert.throws(() =>
    parseAdhocMealCommand({
      dogId: "d",
      period: "morning",
      offeredGrams: 100,
      acceptance: "unknown",
      fedAt: "2026-07-01T08:00:00.000Z",
      idempotencyKey: "k1",
      planId: "p",
    }),
  );
});

test("supplement rejects textual dose", () => {
  assert.throws(() =>
    parseSupplementCommand({
      dogId: "d",
      supplementName: "Omega",
      dose: "1 cápsula",
      unit: "mg",
      administeredAt: "2026-07-01T08:00:00.000Z",
      idempotencyKey: "k1",
    }),
  );
});

test("supplementRegimenId sem nutritionPlanId → validation", () => {
  assert.throws(
    () =>
      parseSupplementCommand({
        dogId: "d",
        supplementName: "Omega",
        dose: 10,
        unit: "mg",
        administeredAt: "2026-07-01T08:00:00.000Z",
        supplementRegimenId: "reg-1",
        idempotencyKey: "k1",
      }),
    (e: Error & {detailCode?: string}) =>
      e.detailCode === "supplement_regimen_requires_plan" ||
      e.message.includes("nutritionPlanId"),
  );
});

test("nutritionPlanId sem regimen → permitido", () => {
  const c = parseSupplementCommand({
    dogId: "d",
    supplementName: "Omega",
    dose: 10,
    unit: "mg",
    administeredAt: "2026-07-01T08:00:00.000Z",
    nutritionPlanId: "plan-1",
    idempotencyKey: "k1",
  });
  assert.strictEqual(c.nutritionPlanId, "plan-1");
  assert.strictEqual(c.supplementRegimenId, null);
});

test("receiptId actor-scoped: same operationId different actors → different path id", () => {
  const a = nutritionOperationReceiptIdV1({
    actorUid: "uid-A",
    operationType: "create_planned_meal",
    operationId: "save-1",
  });
  const b = nutritionOperationReceiptIdV1({
    actorUid: "uid-B",
    operationType: "create_planned_meal",
    operationId: "save-1",
  });
  assert.ok(a.startsWith("nr1_"));
  assert.notStrictEqual(a, b);
  assert.strictEqual(
    a,
    nutritionOperationReceiptIdV1({
      actorUid: "uid-A",
      operationType: "create_planned_meal",
      operationId: "save-1",
    }),
  );
});

test("entity semantic fingerprint differs when scheduled_for drifts", () => {
  const base = {
    planId: "p",
    plannedMealId: "s",
    mealOccurrenceId: "mo1_x",
    period: "morning",
    scheduledForIso: "2026-07-18T10:00:00.000Z",
    prescriptionAmountAtTime: 300,
    offeredGrams: 300,
    consumedGrams: null as number | null,
    acceptance: "full",
    fedAtIso: "2026-07-18T10:00:00.000Z",
    observations: null as string | null,
    attachmentRefs: [] as string[],
  };
  const fp1 = entitySemanticFingerprintPlannedMeal(base);
  const fp2 = entitySemanticFingerprintPlannedMeal({
    ...base,
    scheduledForIso: "2026-07-18T11:00:00.000Z",
  });
  assert.notStrictEqual(fp1, fp2);
  const d = decidePlannedMealAgainstExisting({
    docExists: true,
    existingEntityFingerprint: fp1,
    proposedEntityFingerprint: fp2,
  });
  assert.strictEqual(d.kind, "error");
  if (d.kind === "error") {
    assert.strictEqual(d.detailCode, "meal_occurrence_conflict");
  }
});

test("entity semantic no-op when materialization matches", () => {
  const fp = entitySemanticFingerprintPlannedMeal({
    planId: "p",
    plannedMealId: "s",
    mealOccurrenceId: "mo1_x",
    period: "morning",
    scheduledForIso: "2026-07-18T10:00:00.000Z",
    prescriptionAmountAtTime: 300,
    offeredGrams: 300,
    consumedGrams: null,
    acceptance: "full",
    fedAtIso: "2026-07-18T10:00:00.000Z",
    observations: null,
    attachmentRefs: [],
  });
  assert.strictEqual(
    decidePlannedMealAgainstExisting({
      docExists: true,
      existingEntityFingerprint: fp,
      proposedEntityFingerprint: fp,
    }).kind,
    "noop",
  );
});

// ── DST / IANA policy ────────────────────────────────────────────────────────

test("timezone inválido não faz fallback UTC", () => {
  assert.throws(
    () => localServiceDateFromInstant(new Date(), "Not/ARealZone"),
    (e: Error & {detailCode?: string}) =>
      e.detailCode === "invalid_timezone" || e.message.includes("timezone"),
  );
  assert.throws(() =>
    scheduledForFromLocal("2026-07-18", "07:00", "Not/ARealZone"),
  );
});

test("DST America/New_York spring gap: 2023-03-12 02:30 inexistente", () => {
  // US Eastern spring forward 2023-03-12 02:00 → 03:00
  assert.throws(
    () =>
      scheduledForFromLocal("2023-03-12", "02:30", "America/New_York"),
    (e: Error & {detailCode?: string}) =>
      e.detailCode === "local_scheduled_time_nonexistent",
  );
});

test("DST America/New_York fall ambiguity: earlier UTC chosen", () => {
  // 2023-11-05 01:30 America/New_York is ambiguous (EDT then EST).
  const matches = findUtcInstantsForLocalWall(
    2023,
    11,
    5,
    1,
    30,
    "America/New_York",
  );
  assert.ok(
    matches.length >= 2,
    `expected ambiguous matches, got ${matches.length}`,
  );
  const chosen = scheduledForFromLocal(
    "2023-11-05",
    "01:30",
    "America/New_York",
  );
  assert.strictEqual(chosen.getTime(), matches[0].getTime());
  // Earlier offset is EDT (UTC-4): 01:30 → 05:30Z
  assert.strictEqual(chosen.toISOString(), "2023-11-05T05:30:00.000Z");
});

test("DST normal wall time New_York winter", () => {
  const d = scheduledForFromLocal("2023-01-15", "07:00", "America/New_York");
  // EST UTC-5 → 12:00Z
  assert.strictEqual(d.toISOString(), "2023-01-15T12:00:00.000Z");
});

test("fingerprint planned excludes recordedBy", () => {
  const fp = fingerprintPlannedMeal({
    dogId: "d",
    planId: "p",
    plannedMealId: "s",
    offeredGrams: 100,
    consumedGrams: null,
    acceptance: "unknown",
    fedAtIso: "2026-07-01T08:00:00.000Z",
    observations: null,
    attachmentRefs: [],
  });
  assert.ok(!fp.includes("recorded"));
  assert.ok(fp.includes("planned_meal_v1"));
});

test("zero dual-write collection lists", () => {
  assert.ok(FORBIDDEN_LEGACY_WRITE_COLLECTIONS.includes("feeding_events"));
  assert.ok(FORBIDDEN_LEGACY_WRITE_COLLECTIONS.includes("nutrition_supplements"));
  assert.ok(CANONICAL_WRITE_COLLECTIONS.includes("meal_logs"));
  assert.ok(CANONICAL_WRITE_COLLECTIONS.includes("auditLogs"));
});

console.log("\nhealth_nutrition_logic_test: all passed");
