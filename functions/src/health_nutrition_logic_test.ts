/**
 * Testes unitários — Nutrição 5D Gate 1 (lógica pura).
 * npm run build && node lib/health_nutrition_logic_test.js
 */
import * as assert from "assert";
import { assertCanonicalWritePath } from "./health_nutrition_firestore_adapter";
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
  parseCreateAndActivateNutritionPlan,
  parseUpdateActiveNutritionPlan,
  parseCancelNutritionPlan,
  fingerprintNutritionPlan,
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

// ── NutritionPlan Tests ──

const baseValidPlanPayload = {
  dogId: "dog-test-123",
  operationId: "op-create-123",
  planData: {
    food_type: "ração super premium light",
    amount_grams_per_day: 400,
    meals_per_day: 2,
    timezone: "America/Sao_Paulo",
    valid_from: "2026-07-20T03:00:00Z",
    valid_until: null,
    meal_schedule: [
      {
        id: "slot-morning",
        period: "morning",
        scheduled_time: "08:00",
        target_grams: 200,
      },
      {
        id: "slot-evening",
        period: "evening",
        scheduled_time: "18:00",
        target_grams: 200,
      },
    ],
    supplements: [
      {
        id: "supp-joint",
        name: "Condroitina + Glucosamina",
        dose: 1,
        unit: "tablet",
        frequency: "daily",
        instructions: "Dar após o treino",
        valid_from: "2026-07-20T03:00:00Z",
        valid_until: null,
      },
    ],
    hydration_ml: 1200,
    special_instructions: "Umedecer levemente os grãos",
    professional: {
      name: "Dr. Ana Cláudia",
      register_number: "CRMV-SP-9876",
      register_state: "SP",
      specialty: "Nutrologia Veterinária",
    },
    source_document: {
      id: "doc-prescription-11",
      type: "prescription",
      issued_by: "Clínica Vet K9",
      issued_at: "2026-07-18T10:00:00Z",
      url: "https://k9ops.net/docs/prescription-11.pdf",
    },
    attachment_refs: ["https://k9ops.net/docs/ref-1.jpg"],
  },
};

const testServerNow = new Date("2026-07-20T12:00:00.000Z");

test("parseCreateAndActivateNutritionPlan: valid payload success", () => {
  const result = parseCreateAndActivateNutritionPlan(baseValidPlanPayload as any, testServerNow);
  assert.strictEqual(result.dogId, "dog-test-123");
  assert.strictEqual(result.operationId, "op-create-123");
  assert.strictEqual(result.planData.food_type, "ração super premium light");
  assert.strictEqual(result.planData.amount_grams_per_day, 400);
  assert.strictEqual(result.planData.meals_per_day, 2);
  assert.strictEqual(result.planData.timezone, "America/Sao_Paulo");
  assert.strictEqual(result.planData.meal_schedule.length, 2);
  assert.strictEqual(result.planData.supplements?.length, 1);
  assert.strictEqual(result.planData.hydration_ml, 1200);
  assert.strictEqual(result.planData.special_instructions, "Umedecer levemente os grãos");
  assert.strictEqual(result.planData.professional?.name, "Dr. Ana Cláudia");
  assert.strictEqual(result.planData.source_document?.id, "doc-prescription-11");
  assert.strictEqual(result.planData.source_document?.type, "prescription");
  assert.strictEqual(result.planData.attachment_refs?.length, 1);
});

test("parseCreateAndActivateNutritionPlan: validations reject invalid timezone", () => {
  const badPayload = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      timezone: "Invalid/Timezone_Name",
    },
  };
  assert.throws(() => {
    parseCreateAndActivateNutritionPlan(badPayload as any, testServerNow);
  }, /timezone inválido/);
});

test("parseCreateAndActivateNutritionPlan: validations reject slot target grams sum mismatch", () => {
  const badPayload = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      amount_grams_per_day: 500, // sum of slots is 400
    },
  };
  assert.throws(() => {
    parseCreateAndActivateNutritionPlan(badPayload as any, testServerNow);
  }, /A soma das refeições.*deve equivaler a amount_grams_per_day/);
});

test("parseCreateAndActivateNutritionPlan: validations ALLOW duplicate slot period", () => {
  const okPayload = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 200 },
        { id: "s2", period: "morning", scheduled_time: "10:00", target_grams: 200 }, // duplicate 'morning' allowed
      ],
    },
  };
  assert.doesNotThrow(() => {
    parseCreateAndActivateNutritionPlan(okPayload as any, testServerNow);
  });
});

test("parseCreateAndActivateNutritionPlan: validations reject non-numeric supplement dose", () => {
  const badPayload = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      supplements: [
        {
          id: "supp-1",
          name: "S",
          dose: "1 tablet", // string
          unit: "tablet",
          frequency: "daily",
        },
      ],
    },
  };
  assert.throws(() => {
    parseCreateAndActivateNutritionPlan(badPayload as any, testServerNow);
  }, /dose do suplemento deve ser numérica/);
});

test("fingerprintNutritionPlan: deterministic ordering & hashing", () => {
  const fpA = fingerprintNutritionPlan(baseValidPlanPayload.planData as any);

  // Payload B has meal_schedule and supplements in a different physical order
  const shuffledPlanData = {
    ...baseValidPlanPayload.planData,
    meal_schedule: [
      baseValidPlanPayload.planData.meal_schedule[1],
      baseValidPlanPayload.planData.meal_schedule[0],
    ],
  };

  const fpB = fingerprintNutritionPlan(shuffledPlanData as any);
  assert.strictEqual(fpA, fpB, "Fingerprint should be identical regardless of schedule order");
});

test("parseUpdateActiveNutritionPlan: allows administrative changes", () => {
  const updatePayload = {
    dogId: "dog-test-123",
    planId: "plan-active-99",
    operationId: "op-update-456",
    expectedRevision: 4,
    planData: {
      special_instructions: "Colocar ração fria",
      professional: {
        name: "Dr. Ana Cláudia",
        register_number: "CRMV-SP-9876",
        register_state: "SP",
      },
    },
  };
  const result = parseUpdateActiveNutritionPlan(updatePayload as any);
  assert.strictEqual(result.dogId, "dog-test-123");
  assert.strictEqual(result.planId, "plan-active-99");
  assert.strictEqual(result.expectedRevision, 4);
  assert.strictEqual(result.planData.special_instructions, "Colocar ração fria");
  assert.strictEqual(result.planData.professional?.name, "Dr. Ana Cláudia");
});

test("parseUpdateActiveNutritionPlan: rejects structural changes", () => {
  const badUpdatePayload = {
    dogId: "dog-test-123",
    planId: "plan-active-99",
    operationId: "op-update-456",
    expectedRevision: 4,
    planData: {
      special_instructions: "Nova instrução",
      food_type: "ração diferente", // structural field!
    },
  };
  assert.throws(() => {
    parseUpdateActiveNutritionPlan(badUpdatePayload as any);
  }, /Alteração estrutural não permitida no update/);
});

test("parseCancelNutritionPlan: parses cancel with valid reason", () => {
  const cancelPayload = {
    dogId: "dog-test-123",
    planId: "plan-active-99",
    operationId: "op-cancel-789",
    expectedRevision: 5,
    reason: "Indicação clínica",
  };
  const result = parseCancelNutritionPlan(cancelPayload as any);
  assert.strictEqual(result.dogId, "dog-test-123");
  assert.strictEqual(result.planId, "plan-active-99");
  assert.strictEqual(result.expectedRevision, 5);
  assert.strictEqual(result.reason, "Indicação clínica");
});

test("parseCancelNutritionPlan: rejects empty cancel reason", () => {
  const badCancelPayload = {
    dogId: "dog-test-123",
    planId: "plan-active-99",
    operationId: "op-cancel-789",
    expectedRevision: 5,
    reason: "   ", // empty string after trim
  };
  assert.throws(() => {
    parseCancelNutritionPlan(badCancelPayload as any);
  }, /Justificativa \(reason\) é obrigatória/);
});

// A fixed server time for tests: 2026-07-20T12:00:00.000Z
test("CREATE: payload mínimo válido", () => {
  const payload = {
    dogId: "dog-min",
    operationId: "op-min",
    planData: {
      food_type: "ração light",
      amount_grams_per_day: 100,
      meals_per_day: 1,
      timezone: "America/Sao_Paulo",
      valid_from: "2026-07-20T12:00:00Z", // exactly serverNow
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 100 }
      ]
    }
  };
  const result = parseCreateAndActivateNutritionPlan(payload as any, testServerNow);
  assert.strictEqual(result.dogId, "dog-min");
  assert.strictEqual(result.planData.meals_per_day, 1);
  assert.strictEqual(result.planData.meal_schedule.length, 1);
});

test("CREATE: payload completo válido", () => {
  const payload = {
    dogId: "dog-full",
    operationId: "op-full",
    planData: {
      food_type: "ração premium",
      amount_grams_per_day: 300,
      meals_per_day: 2,
      timezone: "America/Sao_Paulo",
      valid_from: "2026-07-20T10:00:00Z", // past but within local day
      valid_until: "2026-07-25T12:00:00Z",
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 150 },
        { id: "s2", period: "afternoon", scheduled_time: "14:00", target_grams: 150 }
      ],
      supplements: [
        { id: "sp1", name: "Glucosamina", dose: 2, unit: "tablet", frequency: "daily" }
      ],
      hydration_ml: 500,
      special_instructions: "Comer devagar",
      professional: { name: "Dr Vet", register_number: "123", register_state: "SP" },
      source_document: { id: "d1", type: "prescription", issued_by: "Clinic", issued_at: "2026-07-19T00:00:00Z" },
      attachment_refs: ["url1"]
    }
  };
  const result = parseCreateAndActivateNutritionPlan(payload as any, testServerNow);
  assert.strictEqual(result.dogId, "dog-full");
  assert.strictEqual(result.planData.supplements?.length, 1);
  assert.strictEqual(result.planData.professional?.name, "Dr Vet");
  assert.strictEqual(result.planData.source_document?.id, "d1");
});

test("CREATE: rejeita chaves server-controlled", () => {
  const serverKeys = ["status", "revision", "schema_version", "schemaVersion", "recorded_by", "recordedBy", "created_at", "createdAt", "updated_at", "updatedAt"];
  for (const k of serverKeys) {
    const payloadWithRootKey = {
      ...baseValidPlanPayload,
      [k]: "val"
    };
    assert.throws(() => {
      parseCreateAndActivateNutritionPlan(payloadWithRootKey as any, testServerNow);
    }, /Campo controlado pelo servidor não permitido/);

    const payloadWithDataKey = {
      ...baseValidPlanPayload,
      planData: {
        ...baseValidPlanPayload.planData,
        [k]: "val"
      }
    };
    assert.throws(() => {
      parseCreateAndActivateNutritionPlan(payloadWithDataKey as any, testServerNow);
    }, /Campo controlado pelo servidor não permitido/);
  }
});

test("CREATE: food_type vazio", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: { ...baseValidPlanPayload.planData, food_type: "   " }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /food_type/);
});

test("CREATE: amount_grams_per_day <= 0", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      amount_grams_per_day: 0,
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 0 }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /amount_grams_per_day/);
});

test("CREATE: meals_per_day <= 0", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: { ...baseValidPlanPayload.planData, meals_per_day: -1 }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /meals_per_day/);
});

test("CREATE: meal_schedule vazio", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: { ...baseValidPlanPayload.planData, meal_schedule: [] }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /meal_schedule/);
});

test("CREATE: slot ID duplicado", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      meal_schedule: [
        { id: "slot-dup", period: "morning", scheduled_time: "08:00", target_grams: 200 },
        { id: "slot-dup", period: "evening", scheduled_time: "18:00", target_grams: 200 }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /id de slot duplicado/);
});

test("CREATE: MealPeriod inválido", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      meals_per_day: 1,
      meal_schedule: [
        { id: "s1", period: "invalid_period", scheduled_time: "08:00", target_grams: 400 }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /period do slot inválido/);
});

test("CREATE: scheduled_time inválido", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      meals_per_day: 1,
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:000", target_grams: 400 }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /scheduled_time/);
});

test("CREATE: target_grams <= 0", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      meals_per_day: 1,
      meal_schedule: [
        { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: -10 }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /target_grams/);
});

test("CREATE: supplement ID duplicado", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      supplements: [
        { id: "sp-dup", name: "S1", dose: 1, unit: "tablet", frequency: "daily" },
        { id: "sp-dup", name: "S2", dose: 1, unit: "tablet", frequency: "daily" }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /id de suplemento duplicado/);
});

test("CREATE: unit inválida", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      supplements: [
        { id: "sp1", name: "S1", dose: 1, unit: "invalid_unit", frequency: "daily" }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /unit inválido/);
});

test("CREATE: supplement valid_until <= valid_from", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      supplements: [
        {
          id: "sp1",
          name: "S1",
          dose: 1,
          unit: "tablet",
          frequency: "daily",
          valid_from: "2026-07-20T00:00:00Z",
          valid_until: "2026-07-19T23:59:59Z"
        }
      ]
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /valid_until do suplemento deve ser posterior/);
});

test("CREATE: plano valid_until <= valid_from", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      valid_from: "2026-07-20T05:00:00Z",
      valid_until: "2026-07-20T05:00:00Z"
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /valid_until deve ser posterior/);
});

test("CREATE: timezone inválida", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: { ...baseValidPlanPayload.planData, timezone: "XYZ/Abc" }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /timezone inválido/);
});

test("CREATE: plano expirado", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      valid_from: "2026-07-20T04:00:00Z",
      valid_until: "2026-07-20T05:00:00Z" // expired (testServerNow is 12:00:00Z)
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /Plano expirado/);
});

test("CREATE: valid_from futuro", () => {
  const bad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      valid_from: "2026-07-20T12:00:01Z" // serverNow is 12:00:00Z
    }
  };
  assert.throws(() => parseCreateAndActivateNutritionPlan(bad as any, testServerNow), /valid_from no futuro não é permitido/);
});

test("CREATE: retroatividade dia civil local limite", () => {
  // testServerNow = 2026-07-20T12:00:00.000Z. Em America/Sao_Paulo (UTC-3), isso é 2026-07-20 09:00:00.
  // Início do dia local em UTC = 2026-07-20T03:00:00.000Z.
  // 02:59:59Z é no dia anterior (19/07), logo deve ser rejeitado.
  const limitOk = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      valid_from: "2026-07-20T03:00:00Z" // exactly start of today
    }
  };
  const result = parseCreateAndActivateNutritionPlan(limitOk as any, testServerNow);
  assert.strictEqual(result.planData.valid_from, "2026-07-20T03:00:00Z");

  const limitBad = {
    ...baseValidPlanPayload,
    planData: {
      ...baseValidPlanPayload.planData,
      valid_from: "2026-07-20T02:59:59Z" // yesterday!
    }
  };
  assert.throws(() => {
    parseCreateAndActivateNutritionPlan(limitBad as any, testServerNow);
  }, /Vigência do plano anterior ao início do dia civil atual/);
});

// ── UPDATE TESTS ──

test("UPDATE: rejeita individualmente campos estruturais", () => {
  const forbidden = [
    "food_type", "foodType",
    "amount_grams_per_day", "amountGramsPerDay",
    "meals_per_day", "mealsPerDay",
    "meal_schedule", "mealSchedule",
    "supplements",
    "hydration_ml", "hydrationMl",
    "timezone",
    "valid_from", "validFrom",
    "valid_until", "validUntil"
  ];
  for (const k of forbidden) {
    const payload = {
      dogId: "d",
      planId: "p",
      operationId: "op",
      expectedRevision: 1,
      planData: {
        special_instructions: "nova", // chave administrativa válida
        [k]: "val"
      }
    };
    assert.throws(() => {
      parseUpdateActiveNutritionPlan(payload as any);
    }, /Alteração estrutural não permitida no update/);
  }
});

test("UPDATE: campos administrativos permitidos", () => {
  const adminFields = [
    { special_instructions: "nova" },
    { professional: { name: "Dr Vet", register_number: "1", register_state: "SP" } },
    { source_document: { id: "d1", type: "prescription", issued_by: "Vet", issued_at: "2026-07-20T00:00:00Z" } },
    { attachment_refs: ["url"] }
  ];
  for (const f of adminFields) {
    const payload = {
      dogId: "d",
      planId: "p",
      operationId: "op",
      expectedRevision: 2,
      planData: f
    };
    const res = parseUpdateActiveNutritionPlan(payload as any);
    assert.strictEqual(res.expectedRevision, 2);
  }
});

test("UPDATE: combinação de campos administrativos", () => {
  const payload = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: 3,
    planData: {
      special_instructions: "nova",
      professional: { name: "Dr Vet", register_number: "1", register_state: "SP" },
      attachment_refs: ["url1", "url2"]
    }
  };
  const res = parseUpdateActiveNutritionPlan(payload as any);
  assert.strictEqual(res.planData.special_instructions, "nova");
  assert.strictEqual(res.planData.professional?.name, "Dr Vet");
});

test("UPDATE: payload vazio rejeitado", () => {
  const payload = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: 3,
    planData: {}
  };
  assert.throws(() => parseUpdateActiveNutritionPlan(payload as any), /pelo menos uma chave administrativa/);
});

test("UPDATE: chaves explicitamente nulas aceitas", () => {
  const p1 = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: 3,
    planData: {
      special_instructions: null
    }
  };
  const res1 = parseUpdateActiveNutritionPlan(p1 as any);
  assert.strictEqual(res1.planData.special_instructions, null);

  const p2 = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: 3,
    planData: {
      professional: null
    }
  };
  const res2 = parseUpdateActiveNutritionPlan(p2 as any);
  assert.strictEqual(res2.planData.professional, null);
});

test("UPDATE: expectedRevision inválida", () => {
  const payloads = [
    { dogId: "d", planId: "p", operationId: "o", expectedRevision: 0, planData: {} },
    { dogId: "d", planId: "p", operationId: "o", expectedRevision: -5, planData: {} },
    { dogId: "d", planId: "p", operationId: "o", expectedRevision: "1", planData: {} }
  ];
  for (const p of payloads) {
    assert.throws(() => parseUpdateActiveNutritionPlan(p as any), /expectedRevision/);
  }
});

// ── CANCEL TESTS ──

test("CANCEL: reason válido", () => {
  const payload = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: 5,
    reason: "Motivo Clínico"
  };
  const res = parseCancelNutritionPlan(payload as any);
  assert.strictEqual(res.reason, "Motivo Clínico");
});

test("CANCEL: reason vazio ou whitespace", () => {
  const payloads = [
    { dogId: "d", planId: "p", operationId: "o", expectedRevision: 5, reason: "" },
    { dogId: "d", planId: "p", operationId: "o", expectedRevision: 5, reason: "     " }
  ];
  for (const p of payloads) {
    assert.throws(() => parseCancelNutritionPlan(p as any), /Justificativa.*reason.*obrigatória/);
  }
});

test("CANCEL: expectedRevision inválida", () => {
  const payload = {
    dogId: "d",
    planId: "p",
    operationId: "op",
    expectedRevision: -1,
    reason: "Ok"
  };
  assert.throws(() => parseCancelNutritionPlan(payload as any), /expectedRevision/);
});

test("CANCEL: operationId inválido", () => {
  const payloads = [
    { dogId: "d", planId: "p", operationId: "", expectedRevision: 1, reason: "Ok" },
    { dogId: "d", planId: "p", operationId: 123, expectedRevision: 1, reason: "Ok" }
  ];
  for (const p of payloads) {
    assert.throws(() => parseCancelNutritionPlan(p as any), /operationId/);
  }
});

// ── FINGERPRINT & RECEIPTS ──

test("FINGERPRINT: determinismo com reordenação de chaves e arrays", () => {
  const pA = {
    food_type: "premium",
    amount_grams_per_day: 300,
    meals_per_day: 2,
    timezone: "America/Sao_Paulo",
    valid_from: "2026-07-20T00:00:00Z",
    valid_until: null,
    meal_schedule: [
      { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 150 },
      { id: "s2", period: "afternoon", scheduled_time: "14:00", target_grams: 150 }
    ],
    supplements: [
      { id: "sp1", name: "A", dose: 1, unit: "tablet", frequency: "daily" },
      { id: "sp2", name: "B", dose: 1, unit: "tablet", frequency: "daily" }
    ]
  };

  const pB = {
    timezone: "America/Sao_Paulo",
    amount_grams_per_day: 300,
    food_type: "premium",
    meals_per_day: 2,
    valid_from: "2026-07-20T00:00:00Z",
    valid_until: null,
    meal_schedule: [
      { id: "s2", scheduled_time: "14:00", period: "afternoon", target_grams: 150 },
      { id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 150 }
    ],
    supplements: [
      { name: "B", id: "sp2", unit: "tablet", dose: 1, frequency: "daily" },
      { name: "A", id: "sp1", dose: 1, unit: "tablet", frequency: "daily" }
    ]
  };

  const fpA = fingerprintNutritionPlan(pA as any);
  const fpB = fingerprintNutritionPlan(pB as any);
  assert.strictEqual(fpA, fpB, "Fingerprint deve ser idêntico com reordenação");
});

test("FINGERPRINT: alteração estrutural altera fingerprint", () => {
  const pA = {
    food_type: "premium",
    amount_grams_per_day: 300,
    meals_per_day: 1,
    timezone: "America/Sao_Paulo",
    valid_from: "2026-07-20T00:00:00Z",
    meal_schedule: [{ id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 300 }]
  };
  const pB = {
    ...pA,
    amount_grams_per_day: 310, // diff
    meal_schedule: [{ id: "s1", period: "morning", scheduled_time: "08:00", target_grams: 310 }]
  };
  assert.notStrictEqual(fingerprintNutritionPlan(pA as any), fingerprintNutritionPlan(pB as any));
});

test("RECEIPTS: nutritionOperationReceiptIdV1 com novas operações", () => {
  const rCreate = nutritionOperationReceiptIdV1({
    actorUid: "actor-1",
    operationType: "create_nutrition_plan",
    operationId: "op-1"
  });
  const rUpdate = nutritionOperationReceiptIdV1({
    actorUid: "actor-1",
    operationType: "update_nutrition_plan",
    operationId: "op-1"
  });
  assert.ok(rCreate.startsWith("nr1_"));
  assert.ok(rUpdate.startsWith("nr1_"));
  assert.notStrictEqual(rCreate, rUpdate, "Receipts de tipos de operação diferente devem ser distintos");
});

// ── FIRESTORE ADAPTER SECURITY ──

test("ADAPTER SECURITY: assertCanonicalWritePath allowlists & blocking", () => {
  // Allowed shape of plan
  assert.doesNotThrow(() => assertCanonicalWritePath("dogs/dog-1/nutrition_plans/plan-1"));

  // Allowed shape of logs
  assert.doesNotThrow(() => assertCanonicalWritePath("dogs/dog-1/meal_logs/log-1"));
  assert.doesNotThrow(() => assertCanonicalWritePath("dogs/dog-1/supplement_logs/log-1"));
  assert.doesNotThrow(() => assertCanonicalWritePath("dogs/dog-1/nutrition_operations/op-1"));
  assert.doesNotThrow(() => assertCanonicalWritePath("auditLogs/audit-1"));

  // Forbidden shapes of nutrition_plans
  assert.throws(() => assertCanonicalWritePath("dogs/dog-1/nutrition_plans"), /Write path fora do conjunto/);
  assert.throws(() => assertCanonicalWritePath("nutrition_plans/plan-1"), /Write path fora do conjunto/);
  assert.throws(() => assertCanonicalWritePath("dogs/dog-1/nutrition_plans/plan-1/nested"), /Write path fora do conjunto/);

  // Forbidden legacy write collections
  assert.throws(() => assertCanonicalWritePath("dogs/dog-1/nutritional_prescriptions/presc-1"), /Write proibido em collection legada/);
  assert.throws(() => assertCanonicalWritePath("dogs/dog-1/nutrition_prescriptions/presc-1"), /Write proibido em collection legada/);

  // Arbitrary paths
  assert.throws(() => assertCanonicalWritePath("dogs/dog-1/arbitrary/path-1"), /Write path fora do conjunto/);
  assert.throws(() => assertCanonicalWritePath("arbitrary_collection/doc-1"), /Write path fora do conjunto/);
});

console.log("\nhealth_nutrition_logic_test: all passed");
