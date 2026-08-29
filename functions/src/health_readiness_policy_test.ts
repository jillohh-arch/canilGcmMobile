/**
 * Readiness v1 — pure evaluator test matrix (R1..R20).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Ratified contract under test: the four completeness gates are weight (90d),
 * vaccination currency, consultation (180d) and an active nutrition plan.
 * Exam is informational and must never gate readiness.
 *
 * Harness idiom matches the existing functions tests: plain `assert`, a local
 * `test()` helper, single `main()`, non-zero exit on assertion failure.
 */

import * as assert from "assert";
import {
  DEFAULT_READINESS_CONFIG,
  EvidenceState,
  evaluateReadiness,
  isVaccinationCurrent,
  isWithinMaxAge,
  ReadinessAlert,
  ReadinessConfig,
  ReadinessDecision,
  ReadinessEvidence,
  ReadinessRestriction,
} from "./health_readiness_policy";

const NOW = new Date("2026-08-11T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

function daysAgo(days: number): Date {
  return new Date(NOW.getTime() - days * MILLIS_PER_DAY);
}

function daysAhead(days: number): Date {
  return new Date(NOW.getTime() + days * MILLIS_PER_DAY);
}

function present<T>(value: T): EvidenceState<T> {
  return {kind: "present", value};
}

const ABSENT: EvidenceState<never> = {kind: "absent"};

function unreliable(reasonCode: string): EvidenceState<never> {
  return {kind: "unreliable", reasonCode};
}

function restriction(
  overrides: Partial<ReadinessRestriction> & Pick<ReadinessRestriction, "id" | "level">,
): ReadinessRestriction {
  return {
    category: "other",
    description: `restrição ${overrides.id}`,
    activitiesRestricted: overrides.level === "partial" ? ["patrulha"] : [],
    since: daysAgo(3),
    expectedEnd: null,
    ...overrides,
  };
}

/** Complete, healthy evidence with no restrictions — the R2 baseline. */
function completeEvidence(overrides: Partial<ReadinessEvidence> = {}): ReadinessEvidence {
  return {
    now: NOW,
    activeRestrictions: [],
    latestWeightAt: present(daysAgo(1)),
    vaccination: present({nextDueAt: daysAhead(200)}),
    latestConsultationAt: present(daysAgo(1)),
    nutrition: present({activePlanCount: 1}),
    latestExamAt: present(daysAgo(10)),
    config: DEFAULT_READINESS_CONFIG,
    ...overrides,
  };
}

function decisionOf(evidence: ReadinessEvidence): ReadinessDecision {
  const evaluation = evaluateReadiness(evidence);
  assert.strictEqual(
    evaluation.outcome,
    "decided",
    `expected a clinical decision, got ${JSON.stringify(evaluation)}`,
  );
  if (evaluation.outcome !== "decided") throw new Error("unreachable");
  return evaluation.decision;
}

function alertCodes(alerts: readonly ReadinessAlert[]): string[] {
  return alerts.map((alert) => alert.code);
}

let failed = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  // ── R1 ────────────────────────────────────────────────────────────────────
  await test("R1 no evidence at all -> not_evaluated", () => {
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: ABSENT,
        vaccination: ABSENT,
        latestConsultationAt: ABSENT,
        nutrition: present({activePlanCount: 0}),
        latestExamAt: ABSENT,
      }),
    );
    assert.strictEqual(decision.readinessStatus, "not_evaluated");
    assert.strictEqual(decision.readinessLabel, "Não Avaliado");
    assert.deepStrictEqual(decision.restrictionCount, {
      absolute: 0,
      partial: 0,
      attention: 0,
    });
  });

  // ── R2 ────────────────────────────────────────────────────────────────────
  await test("R2 complete evidence, no restrictions -> operational, no alerts", () => {
    const decision = decisionOf(completeEvidence());
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.strictEqual(decision.readinessLabel, "Operacional");
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
    assert.deepStrictEqual(decision.activeRestrictions, []);
    // Exactly the four ratified gates — no exam key.
    assert.deepStrictEqual(decision.completeness, {
      hasRecentWeight: true,
      hasVaccinationCurrent: true,
      hasRecentConsultation: true,
      hasActiveNutrition: true,
    });
    assert.deepStrictEqual(Object.keys(decision.completeness).sort(), [
      "hasActiveNutrition",
      "hasRecentConsultation",
      "hasRecentWeight",
      "hasVaccinationCurrent",
    ]);
  });

  // ── R3 ────────────────────────────────────────────────────────────────────
  await test("R3 weight older than 90d -> operational_attention", () => {
    const decision = decisionOf(
      completeEvidence({latestWeightAt: present(daysAgo(91))}),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.completeness.hasRecentWeight, false);
    assert.ok(alertCodes(decision.openAlerts).includes("weight_overdue"));
  });

  // ── R4 — boundary semantics frozen: exactly 90d is STILL RECENT ───────────
  await test("R4 weight exactly at 90d boundary -> operational (inclusive)", () => {
    const decision = decisionOf(
      completeEvidence({latestWeightAt: present(daysAgo(90))}),
    );
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.strictEqual(decision.completeness.hasRecentWeight, true);
    assert.strictEqual(isWithinMaxAge(daysAgo(90), NOW, 90), true);
    // One millisecond past the boundary is stale.
    const justPast = new Date(NOW.getTime() - (90 * MILLIS_PER_DAY + 1));
    assert.strictEqual(isWithinMaxAge(justPast, NOW, 90), false);
  });

  // ── R5 — consultation IS a gate (ratified) ────────────────────────────────
  await test("R5 consultation older than 180d -> operational_attention", () => {
    const decision = decisionOf(
      completeEvidence({latestConsultationAt: present(daysAgo(181))}),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.completeness.hasRecentConsultation, false);
    const alert = decision.openAlerts.find(
      (candidate) => candidate.code === "consultation_overdue",
    );
    assert.ok(alert, "expected consultation_overdue alert");
    assert.strictEqual(alert?.severity, "attention");
  });

  // ── R6 — boundary semantics frozen: exactly 180d is STILL RECENT ──────────
  await test("R6 consultation exactly at 180d boundary -> operational (inclusive)", () => {
    const decision = decisionOf(
      completeEvidence({latestConsultationAt: present(daysAgo(180))}),
    );
    assert.strictEqual(decision.completeness.hasRecentConsultation, true);
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.strictEqual(isWithinMaxAge(daysAgo(180), NOW, 180), true);
    const justPast = new Date(NOW.getTime() - (180 * MILLIS_PER_DAY + 1));
    assert.strictEqual(isWithinMaxAge(justPast, NOW, 180), false);
  });

  // ── EXAM IS NOT A GATE — the two decisive proofs ──────────────────────────
  await test("EXAM-1 absent exam + four gates complete -> operational", () => {
    const decision = decisionOf(completeEvidence({latestExamAt: ABSENT}));
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
  });

  await test("EXAM-2 recent exam cannot rescue a stale consultation", () => {
    const decision = decisionOf(
      completeEvidence({
        latestExamAt: present(NOW),
        latestConsultationAt: present(daysAgo(400)),
      }),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.completeness.hasRecentConsultation, false);
    assert.ok(alertCodes(decision.openAlerts).includes("consultation_overdue"));
  });

  await test("EXAM-3 stale exam never demotes and emits no readiness alert", () => {
    const decision = decisionOf(
      completeEvidence({latestExamAt: present(daysAgo(3650))}),
    );
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
    assert.ok(!alertCodes(decision.openAlerts).includes("exam_overdue"));
  });

  await test("EXAM-4 there is no exam threshold in the config contract", () => {
    assert.deepStrictEqual(Object.keys(DEFAULT_READINESS_CONFIG).sort(), [
      "consultationMaxAgeDays",
      "weightMaxAgeDays",
    ]);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(
        DEFAULT_READINESS_CONFIG,
        "examMaxAgeDays",
      ),
      "examMaxAgeDays must not exist in readiness v1",
    );
  });

  await test("EXAM-5 exam alone still proves an evaluation happened", () => {
    // Exam does not gate, but it is recognized factual health evidence, so the
    // K9 is not "never evaluated" — it is incomplete.
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: ABSENT,
        vaccination: ABSENT,
        latestConsultationAt: ABSENT,
        nutrition: present({activePlanCount: 0}),
        latestExamAt: present(daysAgo(5)),
      }),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.notStrictEqual(decision.readinessStatus, "not_evaluated");
  });

  // ── R7 ────────────────────────────────────────────────────────────────────
  await test("R7 vaccination overdue -> operational_attention", () => {
    const decision = decisionOf(
      completeEvidence({vaccination: present({nextDueAt: daysAgo(1)})}),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.completeness.hasVaccinationCurrent, false);
    assert.ok(alertCodes(decision.openAlerts).includes("vaccination_overdue"));
  });

  await test("R7b vaccination due exactly now is still current", () => {
    assert.strictEqual(isVaccinationCurrent(NOW, NOW), true);
    const decision = decisionOf(
      completeEvidence({vaccination: present({nextDueAt: NOW})}),
    );
    assert.strictEqual(decision.completeness.hasVaccinationCurrent, true);
    assert.strictEqual(decision.readinessStatus, "operational");
  });

  // ── R8 ────────────────────────────────────────────────────────────────────
  await test("R8 no active nutrition plan -> operational_attention", () => {
    const decision = decisionOf(
      completeEvidence({nutrition: present({activePlanCount: 0})}),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.completeness.hasActiveNutrition, false);
    assert.ok(alertCodes(decision.openAlerts).includes("nutrition_plan_missing"));
  });

  // ── R8b — CORRECTED: >1 active plans = technical conflict, NOT clinical ─────
  // Multiple active plans are a data-integrity invariant violation. The projector
  // must not emit a clinical state from contradictory evidence.
  await test("R8b >1 active plans -> technical indeterminate, no clinical state", () => {
    const evaluation = evaluateReadiness(
      completeEvidence({nutrition: present({activePlanCount: 2})}),
    );
    assert.strictEqual(
      evaluation.outcome,
      "indeterminate",
      "expected indeterminate for nutrition conflict",
    );
    assert.strictEqual(evaluation.reasonCode, "nutrition_active_plan_conflict");
  });

  // ── R9 ────────────────────────────────────────────────────────────────────
  await test("R9 active absolute restriction -> temporarily_unfit", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [restriction({id: "r-abs", level: "absolute"})],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "temporarily_unfit");
    assert.strictEqual(decision.readinessLabel, "Temporariamente Inapto");
    assert.deepStrictEqual(decision.restrictionCount, {
      absolute: 1,
      partial: 0,
      attention: 0,
    });
    assert.ok(alertCodes(decision.openAlerts).includes("restriction_absolute"));
  });

  // ── R10 ───────────────────────────────────────────────────────────────────
  await test("R10 active partial restriction -> fit_with_restrictions", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [restriction({id: "r-par", level: "partial"})],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "fit_with_restrictions");
    assert.strictEqual(decision.readinessLabel, "Apto com Restrições");
    assert.deepStrictEqual(decision.activeRestrictions[0].activitiesRestricted, [
      "patrulha",
    ]);
  });

  // ── R11 ───────────────────────────────────────────────────────────────────
  await test("R11 active attention restriction -> operational_attention", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [restriction({id: "r-att", level: "attention"})],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "operational_attention");
    assert.strictEqual(decision.readinessLabel, "Operacional com Atenção");
  });

  // ── R12 ───────────────────────────────────────────────────────────────────
  await test("R12 absolute + partial + attention -> unfit, all three listed", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({id: "r-att", level: "attention"}),
          restriction({id: "r-abs", level: "absolute"}),
          restriction({id: "r-par", level: "partial"}),
        ],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "temporarily_unfit");
    assert.strictEqual(decision.activeRestrictions.length, 3);
    // Most restrictive first, deterministically.
    assert.deepStrictEqual(
      decision.activeRestrictions.map((r) => r.level),
      ["absolute", "partial", "attention"],
    );
    assert.deepStrictEqual(decision.restrictionCount, {
      absolute: 1,
      partial: 1,
      attention: 1,
    });
  });

  // ── R13 ───────────────────────────────────────────────────────────────────
  await test("R13 partial + attention -> fit_with_restrictions, both listed", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({id: "r-att", level: "attention"}),
          restriction({id: "r-par", level: "partial"}),
        ],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "fit_with_restrictions");
    assert.strictEqual(decision.activeRestrictions.length, 2);
    assert.deepStrictEqual(decision.restrictionCount, {
      absolute: 0,
      partial: 1,
      attention: 1,
    });
  });

  // ── R14 ───────────────────────────────────────────────────────────────────
  await test("R14 expected_end in the past + status active -> still binding, overdue", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({
            id: "r-abs",
            level: "absolute",
            since: daysAgo(40),
            expectedEnd: daysAgo(5),
          }),
        ],
      }),
    );
    // A lapsed expected_end does NOT end a restriction.
    assert.strictEqual(decision.readinessStatus, "temporarily_unfit");
    assert.strictEqual(decision.activeRestrictions[0].isOverdue, true);
    assert.ok(alertCodes(decision.openAlerts).includes("restriction_overdue"));
  });

  await test("R14b expected_end in the future -> binding, not overdue", () => {
    const decision = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({id: "r-par", level: "partial", expectedEnd: daysAhead(5)}),
        ],
      }),
    );
    assert.strictEqual(decision.activeRestrictions[0].isOverdue, false);
    assert.ok(!alertCodes(decision.openAlerts).includes("restriction_overdue"));
  });

  // ── R15 / R16 — filtered upstream; the evaluator only sees active ones ────
  await test("R15 ended absolute restriction does not reach evaluator -> operational", () => {
    // The reader passes only status == active. An ended restriction is absent.
    const decision = decisionOf(completeEvidence({activeRestrictions: []}));
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(decision.restrictionCount, {
      absolute: 0,
      partial: 0,
      attention: 0,
    });
  });

  await test("R16 cancelled restriction does not reach evaluator -> operational", () => {
    const decision = decisionOf(completeEvidence({activeRestrictions: []}));
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
  });

  // ── R17 — the decisive clinical separation ────────────────────────────────
  await test("R17 symptom 5/5 without restriction does NOT create unfit", () => {
    // A symptom is clinical evidence, never an operational restriction. The
    // evaluator has no symptom input at all: that is the structural guarantee.
    const decision = decisionOf(completeEvidence({activeRestrictions: []}));
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.notStrictEqual(decision.readinessStatus, "temporarily_unfit");
    assert.notStrictEqual(decision.readinessStatus, "fit_with_restrictions");
    // Guard the invariant structurally: no evidence field mentions symptoms.
    const evidenceKeys = Object.keys(completeEvidence());
    assert.ok(
      !evidenceKeys.some((key) => /symptom|sintoma|intercorren/i.test(key)),
      `evidence must not carry symptom inputs, got: ${evidenceKeys.join(",")}`,
    );
  });

  // ── R18 ───────────────────────────────────────────────────────────────────
  await test("R18 incomplete data + active absolute -> absolute wins", () => {
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: present(daysAgo(400)),
        vaccination: present({nextDueAt: daysAgo(30)}),
        nutrition: present({activePlanCount: 0}),
        activeRestrictions: [restriction({id: "r-abs", level: "absolute"})],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "temporarily_unfit");
    // Completeness pendencies remain visible as alerts.
    const codes = alertCodes(decision.openAlerts);
    assert.ok(codes.includes("restriction_absolute"));
    assert.ok(codes.includes("weight_overdue"));
    assert.ok(codes.includes("vaccination_overdue"));
    assert.ok(codes.includes("nutrition_plan_missing"));
  });

  // ── R19 ───────────────────────────────────────────────────────────────────
  await test("R19 no evaluation + incomplete -> not_evaluated wins", () => {
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: ABSENT,
        vaccination: ABSENT,
        latestConsultationAt: ABSENT,
        nutrition: present({activePlanCount: 0}),
        latestExamAt: ABSENT,
      }),
    );
    assert.strictEqual(decision.readinessStatus, "not_evaluated");
    assert.notStrictEqual(decision.readinessStatus, "operational_attention");
  });

  // ── R20 ───────────────────────────────────────────────────────────────────
  await test("R20 malformed gating source -> indeterminate, never operational", () => {
    for (const field of [
      "latestWeightAt",
      "vaccination",
      "latestConsultationAt",
      "nutrition",
    ] as const) {
      const evaluation = evaluateReadiness(
        completeEvidence({[field]: unreliable("malformed")} as Partial<ReadinessEvidence>),
      );
      assert.strictEqual(
        evaluation.outcome,
        "indeterminate",
        `${field} unreliable must be indeterminate`,
      );
      if (evaluation.outcome === "indeterminate") {
        assert.ok(evaluation.reasonCode.includes("malformed"));
      }
    }
  });

  await test("R20b unreliable source never becomes not_evaluated", () => {
    const evaluation = evaluateReadiness(
      completeEvidence({
        latestWeightAt: unreliable("inconclusive"),
        vaccination: ABSENT,
        latestConsultationAt: ABSENT,
        nutrition: present({activePlanCount: 0}),
        latestExamAt: ABSENT,
      }),
    );
    // Absent everything else would be not_evaluated, but an unreadable source
    // must not be laundered into a clinical claim.
    assert.strictEqual(evaluation.outcome, "indeterminate");
  });

  await test("R20c active restriction outranks an unreliable source", () => {
    // A professional decision is not suppressed by unrelated read failure.
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: unreliable("malformed"),
        activeRestrictions: [restriction({id: "r-abs", level: "absolute"})],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "temporarily_unfit");
  });

  await test("unreliable exam (informational) does not block the verdict", () => {
    const decision = decisionOf(
      completeEvidence({latestExamAt: unreliable("malformed")}),
    );
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
  });

  // ── determinism / idempotence ─────────────────────────────────────────────
  await test("determinism: same evidence yields byte-identical decisions", () => {
    const build = (): ReadinessEvidence =>
      completeEvidence({
        latestWeightAt: present(daysAgo(120)),
        activeRestrictions: [
          restriction({id: "r-b", level: "attention"}),
          restriction({id: "r-a", level: "attention"}),
        ],
      });
    const first = decisionOf(build());
    const second = decisionOf(build());
    assert.deepStrictEqual(second, first);
  });

  await test("restriction ordering is independent of input order", () => {
    const forward = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({id: "r-a", level: "partial"}),
          restriction({id: "r-b", level: "absolute"}),
        ],
      }),
    );
    const reversed = decisionOf(
      completeEvidence({
        activeRestrictions: [
          restriction({id: "r-b", level: "absolute"}),
          restriction({id: "r-a", level: "partial"}),
        ],
      }),
    );
    assert.deepStrictEqual(
      reversed.activeRestrictions.map((r) => r.id),
      forward.activeRestrictions.map((r) => r.id),
    );
  });

  await test("thresholds come from config, not from inlined constants", () => {
    // Tightening the config alone must change the outcome.
    const tightWeight: ReadinessConfig = {
      ...DEFAULT_READINESS_CONFIG,
      weightMaxAgeDays: 10,
    };
    const weightDecision = decisionOf(
      completeEvidence({latestWeightAt: present(daysAgo(30)), config: tightWeight}),
    );
    assert.strictEqual(weightDecision.completeness.hasRecentWeight, false);
    assert.strictEqual(weightDecision.readinessStatus, "operational_attention");

    const tightConsultation: ReadinessConfig = {
      ...DEFAULT_READINESS_CONFIG,
      consultationMaxAgeDays: 5,
    };
    const consultationDecision = decisionOf(
      completeEvidence({
        latestConsultationAt: present(daysAgo(30)),
        config: tightConsultation,
      }),
    );
    assert.strictEqual(consultationDecision.completeness.hasRecentConsultation, false);
    assert.strictEqual(consultationDecision.readinessStatus, "operational_attention");
  });

  await test("ratified defaults are 90 (weight) and 180 (consultation)", () => {
    assert.strictEqual(DEFAULT_READINESS_CONFIG.weightMaxAgeDays, 90);
    assert.strictEqual(DEFAULT_READINESS_CONFIG.consultationMaxAgeDays, 180);
  });

  // ── Bono fixture (§31) ────────────────────────────────────────────────────
  await test("BONO fixture: weight today, vaccine current, plan active, consulta today", () => {
    const decision = decisionOf(
      completeEvidence({
        latestWeightAt: present(NOW),
        vaccination: present({nextDueAt: daysAhead(365)}),
        latestConsultationAt: present(NOW),
        nutrition: present({activePlanCount: 1}),
        latestExamAt: ABSENT,
        activeRestrictions: [],
      }),
    );
    assert.strictEqual(decision.readinessStatus, "operational");
    assert.deepStrictEqual(decision.completeness, {
      hasRecentWeight: true,
      hasVaccinationCurrent: true,
      hasRecentConsultation: true,
      hasActiveNutrition: true,
    });
    assert.deepStrictEqual(alertCodes(decision.openAlerts), []);
    assert.deepStrictEqual(decision.activeRestrictions, []);
  });

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed`);
    process.exitCode = 1;
    return;
  }
  console.log("health_readiness_policy_test: all passed");
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
