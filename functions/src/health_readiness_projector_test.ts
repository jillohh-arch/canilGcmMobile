/**
 * Readiness v1 — projector tests (Gate 3, PJT-01..PJT-18).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Exercises the pure snapshot builder and the projector orchestration against
 * an in-memory Firestore fake. The real persistence boundary is covered
 * separately by the emulator suite.
 */

import * as assert from "assert";
import {
  DEFAULT_READINESS_CONFIG,
  evaluateReadiness,
  ReadinessEvidence,
} from "./health_readiness_policy";
import {RawDoc, RawQuery} from "./health_readiness_evidence_logic";
import {
  buildReadinessSnapshotWrite,
  buildTechnicalBlockers,
  deriveLastEvaluatedAt,
  ReadySnapshot,
  READINESS_OWNED_FIELDS,
} from "./health_readiness_snapshot";
import {
  evaluateHealthReadiness,
  hasPreviousValidReadiness,
  ProjectorDeps,
  ProjectorFirestore,
} from "./health_readiness_projector";

const NOW = new Date("2026-08-11T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

function daysAgo(days: number): Date {
  return new Date(NOW.getTime() - days * MILLIS_PER_DAY);
}

function daysAhead(days: number): Date {
  return new Date(NOW.getTime() + days * MILLIS_PER_DAY);
}

function ts(date: Date): {toDate: () => Date} {
  return {toDate: () => date};
}

function doc(id: string, data: Record<string, unknown>): RawDoc {
  return {id, data};
}

/** DEPLOYED V1 weight shape (schema_version 1, no target-v2 field). */
function weightDoc(id: string, overrides: Record<string, unknown> = {}): RawDoc {
  return doc(id, {
    dogId: "dog-1",
    dog_id: "dog-1",
    weight_kg: 28.8,
    measured_at: ts(daysAgo(1)),
    recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
    schema_version: 1,
    created_at: ts(daysAgo(1)),
    ...overrides,
  });
}

function eventDoc(
  id: string,
  type: string,
  overrides: Record<string, unknown> = {},
): RawDoc {
  return doc(id, {
    dogId: "dog-1",
    date: ts(daysAgo(1)),
    type,
    healthObservations: "",
    ...overrides,
  });
}

function restrictionDoc(
  id: string,
  overrides: Record<string, unknown> = {},
): RawDoc {
  return doc(id, {
    level: "absolute",
    category: "injury",
    description: "Lesão em membro anterior",
    status: "active",
    since: ts(daysAgo(5)),
    activities_restricted: [],
    schema_version: 1,
    ...overrides,
  });
}

interface FakeSources {
  weight_records?: RawQuery;
  vaccination_records?: RawQuery;
  health_events?: RawQuery;
  nutrition_plans?: RawQuery;
  operational_restrictions?: RawQuery;
}

const EMPTY: RawQuery = {kind: "docs", docs: []};

/** Bono-equivalent: recent weight, current vaccine, recent consulta, plan. */
function completeSources(overrides: FakeSources = {}): FakeSources {
  return {
    weight_records: {kind: "docs", docs: [weightDoc("w-1")]},
    vaccination_records: EMPTY,
    health_events: {
      kind: "docs",
      docs: [
        eventDoc("e-vac", "vaccination", {
          subtype: "Antirrábica",
          date: ts(daysAgo(2)),
          nextDueDate: ts(daysAhead(363)),
        }),
        eventDoc("e-con", "consultation", {date: ts(daysAgo(3))}),
      ],
    },
    nutrition_plans: {kind: "docs", docs: [doc("p-1", {status: "active"})]},
    operational_restrictions: EMPTY,
    ...overrides,
  };
}

interface Fake {
  readonly deps: ProjectorDeps;
  readonly store: Map<string, Record<string, unknown>>;
  writeCount: number;
}

function createFake(
  sources: FakeSources,
  existingSummary: Record<string, unknown> | null = null,
): Fake {
  const store = new Map<string, Record<string, unknown>>();
  if (existingSummary !== null) {
    store.set("dog-1", {...existingSummary});
  }
  const state = {writeCount: 0};

  const firestore: ProjectorFirestore = {
    readSubcollection: async (_dogId, collection) => {
      const query = (sources as Record<string, RawQuery | undefined>)[collection];
      return query ?? EMPTY;
    },
    readCurrentSummary: async (dogId) => store.get(dogId) ?? null,
    writeCurrentSummary: async (dogId, payload) => {
      state.writeCount += 1;
      // Emulates set(..., {merge: true}).
      const previous = store.get(dogId) ?? {};
      store.set(dogId, {...previous, ...payload});
    },
  };

  const deps: ProjectorDeps = {
    firestore,
    logger: {info: () => {}, warn: () => {}, error: () => {}},
    config: DEFAULT_READINESS_CONFIG,
    now: () => NOW,
  };

  return {
    deps,
    store,
    get writeCount() {
      return state.writeCount;
    },
  } as Fake;
}

function storedSummary(fake: Fake): Record<string, unknown> {
  const stored = fake.store.get("dog-1");
  assert.ok(stored, "expected a persisted summary");
  return stored as Record<string, unknown>;
}

/** Builds a ready snapshot directly from evidence, bypassing Firestore. */
function readySnapshotOf(
  overrides: Partial<ReadinessEvidence> = {},
): ReadySnapshot {
  const evidence: ReadinessEvidence = {
    now: NOW,
    activeRestrictions: [],
    latestWeightAt: {kind: "present", value: daysAgo(1)},
    vaccination: {kind: "present", value: {nextDueAt: daysAhead(200)}},
    latestConsultationAt: {kind: "present", value: daysAgo(1)},
    nutrition: {kind: "present", value: {activePlanCount: 1}},
    latestExamAt: {kind: "absent"},
    config: DEFAULT_READINESS_CONFIG,
    ...overrides,
  };
  const write = buildReadinessSnapshotWrite({
    evaluation: evaluateReadiness(evidence),
    now: NOW,
    instants: {weightAt: daysAgo(1), consultationAt: daysAgo(1)},
    hasPreviousValidSnapshot: false,
  });
  assert.strictEqual(write.kind, "ready", "expected a ready snapshot");
  if (write.kind !== "ready") throw new Error("unreachable");
  return write.payload;
}

let failures = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failures += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  // ── PJT-01 ────────────────────────────────────────────────────────────────
  await test("PJT-01 Bono-like complete fixture -> operational, ready, no alerts", async () => {
    const fake = createFake(completeSources());
    const result = await evaluateHealthReadiness("dog-1", fake.deps);

    assert.strictEqual(result.projectionStatus, "ready");
    assert.strictEqual(result.readinessStatus, "operational");
    assert.deepStrictEqual(result.technicalBlockers, []);

    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_status"], "ready");
    assert.strictEqual(stored["readiness_status"], "operational");
    assert.strictEqual(stored["readiness_label"], "Operacional");
    assert.strictEqual(
      stored["readiness_reason_code"],
      "no_restrictions_evidence_complete",
    );
    assert.strictEqual(stored["evaluated_by"], "function_v1");
    assert.deepStrictEqual(stored["open_alerts"], []);
    assert.deepStrictEqual(stored["active_restrictions"], []);
    assert.deepStrictEqual(stored["restriction_count"], {
      absolute: 0,
      partial: 0,
      attention: 0,
    });
    assert.deepStrictEqual(stored["data_completeness"], {
      has_recent_weight: true,
      has_vaccination_current: true,
      has_recent_consultation: true,
      has_active_nutrition: true,
    });
  });

  // ── PJT-02..04 ────────────────────────────────────────────────────────────
  await test("PJT-02 absolute restriction -> temporarily_unfit", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [restrictionDoc("r-abs", {level: "absolute"})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "temporarily_unfit");
    const stored = storedSummary(fake);
    assert.strictEqual(stored["readiness_label"], "Temporariamente Inapto");
    assert.strictEqual(
      stored["readiness_reason_code"],
      "restriction_absolute_active",
    );
  });

  await test("PJT-03 partial restriction -> fit_with_restrictions", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [
            restrictionDoc("r-par", {
              level: "partial",
              activities_restricted: ["busca"],
            }),
          ],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "fit_with_restrictions");
    const stored = storedSummary(fake);
    assert.strictEqual(stored["readiness_label"], "Apto com Restrições");
    const restrictions = stored["active_restrictions"] as Array<
      Record<string, unknown>
    >;
    assert.deepStrictEqual(restrictions[0]["activities_restricted"], ["busca"]);
  });

  await test("PJT-04 attention restriction -> operational_attention", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [restrictionDoc("r-att", {level: "attention"})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "operational_attention");
    assert.strictEqual(
      storedSummary(fake)["readiness_label"],
      "Operacional com Atenção",
    );
  });

  // ── PJT-05 ────────────────────────────────────────────────────────────────
  await test("PJT-05 no factual evaluation -> not_evaluated", async () => {
    const fake = createFake({
      weight_records: EMPTY,
      vaccination_records: EMPTY,
      health_events: EMPTY,
      nutrition_plans: EMPTY,
      operational_restrictions: EMPTY,
    });
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "not_evaluated");
    const stored = storedSummary(fake);
    assert.strictEqual(stored["readiness_label"], "Não Avaliado");
    assert.strictEqual(
      stored["readiness_reason_code"],
      "no_factual_health_evaluation",
    );
    assert.strictEqual(stored["last_evaluated_at"], null);
  });

  // ── PJT-06 ────────────────────────────────────────────────────────────────
  await test("PJT-06 stale consultation -> operational_attention + alert", async () => {
    const fake = createFake(
      completeSources({
        health_events: {
          kind: "docs",
          docs: [
            eventDoc("e-vac", "vaccination", {
              date: ts(daysAgo(2)),
              nextDueDate: ts(daysAhead(363)),
            }),
            eventDoc("e-con", "consultation", {date: ts(daysAgo(200))}),
          ],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "operational_attention");
    const stored = storedSummary(fake);
    const alerts = stored["open_alerts"] as Array<Record<string, unknown>>;
    assert.ok(alerts.some((alert) => alert["code"] === "consultation_overdue"));
    const completeness = stored["data_completeness"] as Record<string, unknown>;
    assert.strictEqual(completeness["has_recent_consultation"], false);
  });

  // ── PJT-07 / PJT-08 — exam is not a gate ─────────────────────────────────
  await test("PJT-07 exam absent + four gates complete -> operational", async () => {
    const fake = createFake(completeSources());
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "operational");
    assert.deepStrictEqual(storedSummary(fake)["open_alerts"], []);
  });

  await test("PJT-08 recent exam cannot rescue a stale consultation", async () => {
    const fake = createFake(
      completeSources({
        health_events: {
          kind: "docs",
          docs: [
            eventDoc("e-vac", "vaccination", {
              date: ts(daysAgo(2)),
              nextDueDate: ts(daysAhead(363)),
            }),
            eventDoc("e-con", "consultation", {date: ts(daysAgo(400))}),
            eventDoc("e-exam", "exam", {date: ts(NOW)}),
          ],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "operational_attention");
    const alerts = storedSummary(fake)["open_alerts"] as Array<
      Record<string, unknown>
    >;
    assert.ok(alerts.some((alert) => alert["code"] === "consultation_overdue"));
    assert.ok(!alerts.some((alert) => alert["code"] === "exam_overdue"));
  });

  // ── PJT-09 ────────────────────────────────────────────────────────────────
  await test("PJT-09 lapsed expected_end stays listed, counted, overdue", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [
            restrictionDoc("r-abs", {
              level: "absolute",
              expected_end: ts(daysAgo(3)),
            }),
          ],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "temporarily_unfit");
    const stored = storedSummary(fake);
    const restrictions = stored["active_restrictions"] as Array<
      Record<string, unknown>
    >;
    assert.strictEqual(restrictions.length, 1);
    assert.strictEqual(restrictions[0]["is_overdue"], true);
    assert.deepStrictEqual(stored["restriction_count"], {
      absolute: 1,
      partial: 0,
      attention: 0,
    });
    const alerts = stored["open_alerts"] as Array<Record<string, unknown>>;
    assert.ok(alerts.some((alert) => alert["code"] === "restriction_overdue"));
  });

  // ── PJT-10 ────────────────────────────────────────────────────────────────
  await test("PJT-10 multiple restrictions: highest decides, all listed", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [
            restrictionDoc("r-att", {level: "attention"}),
            restrictionDoc("r-abs", {level: "absolute"}),
            restrictionDoc("r-par", {
              level: "partial",
              activities_restricted: ["busca"],
            }),
          ],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.readinessStatus, "temporarily_unfit");
    const stored = storedSummary(fake);
    const restrictions = stored["active_restrictions"] as Array<
      Record<string, unknown>
    >;
    assert.strictEqual(restrictions.length, 3);
    assert.deepStrictEqual(
      restrictions.map((entry) => entry["level"]),
      ["absolute", "partial", "attention"],
    );
    assert.deepStrictEqual(stored["restriction_count"], {
      absolute: 1,
      partial: 1,
      attention: 1,
    });
  });

  // ── PJT-11..14 — technical failures never become clinical ────────────────
  await test("PJT-11 technical source failure -> no clinical result", async () => {
    const fake = createFake(
      completeSources({
        weight_records: {kind: "failed", reasonCode: "permission_denied"},
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);
    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_status"], "unavailable");
    // Nothing clinical was fabricated.
    assert.strictEqual(stored["readiness_status"], undefined);
    assert.notStrictEqual(stored["readiness_status"], "not_evaluated");
    assert.ok((stored["technical_blockers"] as string[]).length > 0);
  });

  await test("PJT-12 nutrition active conflict -> technical unavailable, not attention", async () => {
    // >1 active plan is a conflict the projector must not resolve clinically.
    // (Only one is malformed here, but the result is the same: unreliable.)
    const fake = createFake(
      completeSources({
        nutrition_plans: {
          kind: "docs",
          docs: [doc("p-1", {status: "active"}), doc("p-2", {status: 42})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);
  });

  // ── PJT-12B — 1 valid active + 1 malformed: technical unavailable ─────────
  await test("PJT-12B 1 valid active + 1 malformed -> unavailable, not clinical", async () => {
    // Malformed blocks the invariant even when a valid active plan exists.
    const fake = createFake(
      completeSources({
        nutrition_plans: {
          kind: "docs",
          docs: [doc("p-1", {status: "active"}), doc("p-2", {status: 42})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);
    assert.ok(
      result.technicalBlockers.some((b) => b.includes("malformed")),
    );
  });

  // ── PJT-12C — 0 active: clinical missing, not technical ──────────────────
  await test("PJT-12C 0 active + otherwise valid collection -> operational_attention", async () => {
    // A genuinely empty nutrition collection is a clinical completeness gap, not a
    // technical failure. This is the correct contrast with PJT-12B.
    const snapshot = readySnapshotOf({
      nutrition: {kind: "present", value: {activePlanCount: 0}},
    });
    assert.strictEqual(snapshot.readiness_status, "operational_attention");
    const alerts = snapshot.open_alerts;
    assert.ok(alerts.some((a) => a.code === "nutrition_plan_missing"));
    assert.ok(!alerts.some((a) => a.code === "nutrition_plan_conflict"));
  });

  await test("PJT-13 malformed Weight blocker -> technical unavailable", async () => {
    const fake = createFake(
      completeSources({
        weight_records: {
          kind: "docs",
          docs: [weightDoc("w-ok"), doc("w-bad", {weight_kg: "muito"})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.ok(
      result.technicalBlockers.some((code) => code.includes("inconclusive")),
    );
  });

  await test("PJT-14 restriction query failure -> technical unavailable", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "failed",
          reasonCode: "permission_denied",
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.strictEqual(result.readinessStatus, null);
    assert.ok(
      result.technicalBlockers.some((code) => code.startsWith("restrictions_source")),
    );
  });

  await test("PJT-14b malformed restriction never yields operational", async () => {
    const fake = createFake(
      completeSources({
        operational_restrictions: {
          kind: "docs",
          docs: [restrictionDoc("r-bad", {level: "severe"})],
        },
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.projectionStatus, "unavailable");
    assert.notStrictEqual(result.readinessStatus, "operational");
  });

  // ── PJT-15 / PJT-16 — clinical time vs projection time ───────────────────
  await test("PJT-15 last_evaluated_at differs from readiness_updated_at", async () => {
    const fake = createFake(
      completeSources({
        weight_records: {
          kind: "docs",
          docs: [weightDoc("w-1", {measured_at: ts(daysAgo(30))})],
        },
        health_events: {
          kind: "docs",
          docs: [
            eventDoc("e-vac", "vaccination", {
              date: ts(daysAgo(20)),
              nextDueDate: ts(daysAhead(345)),
            }),
            eventDoc("e-con", "consultation", {date: ts(daysAgo(10))}),
          ],
        },
      }),
    );
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    // Projection time is now; clinical time is the newest factual event.
    assert.deepStrictEqual(stored["readiness_updated_at"], NOW);
    assert.deepStrictEqual(stored["last_evaluated_at"], daysAgo(10));
    assert.notDeepStrictEqual(stored["last_evaluated_at"], stored["readiness_updated_at"]);
  });

  await test("PJT-16 exam advances last_evaluated_at but not completeness", async () => {
    const fake = createFake(
      completeSources({
        weight_records: {
          kind: "docs",
          docs: [weightDoc("w-1", {measured_at: ts(daysAgo(30))})],
        },
        health_events: {
          kind: "docs",
          docs: [
            eventDoc("e-vac", "vaccination", {
              date: ts(daysAgo(20)),
              nextDueDate: ts(daysAhead(345)),
            }),
            eventDoc("e-con", "consultation", {date: ts(daysAgo(10))}),
            eventDoc("e-exam", "exam", {date: ts(daysAgo(2))}),
          ],
        },
      }),
    );
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    // Exam is the newest factual evidence, so it sets clinical time.
    assert.deepStrictEqual(stored["last_evaluated_at"], daysAgo(2));
    // But it contributes no completeness key and no alert.
    assert.deepStrictEqual(Object.keys(stored["data_completeness"] as object).sort(), [
      "has_active_nutrition",
      "has_recent_consultation",
      "has_recent_weight",
      "has_vaccination_current",
    ]);
  });

  await test("PJT-16b nutrition activation alone does not manufacture clinical time", async () => {
    const fake = createFake({
      weight_records: EMPTY,
      vaccination_records: EMPTY,
      health_events: EMPTY,
      nutrition_plans: {kind: "docs", docs: [doc("p-1", {status: "active"})]},
      operational_restrictions: EMPTY,
    });
    await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(storedSummary(fake)["last_evaluated_at"], null);
  });

  // ── PJT-17 ────────────────────────────────────────────────────────────────
  await test("PJT-17 data_completeness has exactly four keys, no has_recent_exam", () => {
    const snapshot = readySnapshotOf();
    const keys = Object.keys(snapshot.data_completeness).sort();
    assert.deepStrictEqual(keys, [
      "has_active_nutrition",
      "has_recent_consultation",
      "has_recent_weight",
      "has_vaccination_current",
    ]);
    assert.strictEqual(keys.length, 4);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(
        snapshot.data_completeness,
        "has_recent_exam",
      ),
      "has_recent_exam must never be persisted",
    );
  });

  // ── PJT-18 ────────────────────────────────────────────────────────────────
  await test("PJT-18 no score / dog.weight / legacy _last_* output fields", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    const serialized = JSON.stringify(stored);
    for (const forbidden of [
      "score",
      "readinessStreak",
      "readiness_score",
      "_last_weight",
      "_last_vaccine",
      "_last_exam",
      "weight_kg",
      "dog.weight",
    ]) {
      assert.ok(
        !serialized.includes(forbidden),
        `snapshot must not contain ${forbidden}`,
      );
    }
  });

  // ── Snapshot completeness / merge safety ─────────────────────────────────
  await test("SNAP every readiness-owned field is written on success", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    for (const field of READINESS_OWNED_FIELDS) {
      assert.ok(field in stored, `missing owned field ${field}`);
    }
  });

  await test("SNAP unrelated summary slices survive the readiness write", async () => {
    const fake = createFake(completeSources(), {
      // A hypothetical future slice owned by another projection.
      nutrition_today: {meals: 2},
      readiness_status: "temporarily_unfit",
    });
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    assert.deepStrictEqual(stored["nutrition_today"], {meals: 2});
    // Readiness-owned field was refreshed, not preserved.
    assert.strictEqual(stored["readiness_status"], "operational");
  });

  await test("SNAP stale restrictions and alerts are cleared on success", async () => {
    const fake = createFake(completeSources(), {
      readiness_status: "temporarily_unfit",
      active_restrictions: [{id: "old", level: "absolute"}],
      restriction_count: {absolute: 1, partial: 0, attention: 0},
      open_alerts: [{code: "weight_overdue", severity: "attention", message: "x"}],
      technical_blockers: ["weight_source_inconclusive"],
      projection_status: "unavailable",
    });
    await evaluateHealthReadiness("dog-1", fake.deps);
    const stored = storedSummary(fake);
    assert.deepStrictEqual(stored["active_restrictions"], []);
    assert.deepStrictEqual(stored["restriction_count"], {
      absolute: 0,
      partial: 0,
      attention: 0,
    });
    assert.deepStrictEqual(stored["open_alerts"], []);
    assert.deepStrictEqual(stored["technical_blockers"], []);
    assert.strictEqual(stored["projection_status"], "ready");
  });

  // ── Last-known-good semantics ────────────────────────────────────────────
  await test("LKG technical failure preserves previous clinical fields", async () => {
    const previousUpdatedAt = daysAgo(1);
    const fake = createFake(
      completeSources({
        weight_records: {kind: "failed", reasonCode: "unavailable"},
      }),
      {
        projection_status: "ready",
        readiness_status: "operational",
        readiness_label: "Operacional",
        readiness_reason: "Sem restrições ativas e dados de saúde em dia.",
        readiness_updated_at: previousUpdatedAt,
        technical_blockers: [],
      },
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.operation, "unavailable_preserving");

    const stored = storedSummary(fake);
    // Clinical plane untouched — retained as last-known-good.
    assert.strictEqual(stored["readiness_status"], "operational");
    assert.strictEqual(stored["readiness_label"], "Operacional");
    assert.deepStrictEqual(stored["readiness_updated_at"], previousUpdatedAt);
    // Technical plane updated.
    assert.strictEqual(stored["projection_status"], "unavailable");
    assert.deepStrictEqual(stored["projection_attempted_at"], NOW);
    assert.deepStrictEqual(stored["updated_at"], NOW);
    assert.ok((stored["technical_blockers"] as string[]).length > 0);
  });

  await test("LKG no previous snapshot + failure -> technical metadata only", async () => {
    const fake = createFake(
      completeSources({
        weight_records: {kind: "failed", reasonCode: "unavailable"},
      }),
    );
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.operation, "unavailable_initial");

    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_status"], "unavailable");
    // No clinical claim of any kind.
    assert.strictEqual(stored["readiness_status"], undefined);
    assert.strictEqual(stored["readiness_label"], undefined);
    assert.strictEqual(stored["data_completeness"], undefined);
    assert.deepStrictEqual(Object.keys(stored).sort(), [
      "projection_attempted_at",
      "projection_status",
      "schema_version",
      "technical_blockers",
      "updated_at",
    ]);
  });

  await test("LKG hasPreviousValidReadiness recognizes only a real clinical value", () => {
    assert.strictEqual(hasPreviousValidReadiness(null), false);
    assert.strictEqual(hasPreviousValidReadiness({}), false);
    assert.strictEqual(hasPreviousValidReadiness({readiness_status: ""}), false);
    assert.strictEqual(hasPreviousValidReadiness({readiness_status: "  "}), false);
    assert.strictEqual(hasPreviousValidReadiness({projection_status: "unavailable"}), false);
    assert.strictEqual(
      hasPreviousValidReadiness({readiness_status: "operational"}),
      true,
    );
  });

  // ── Idempotency ──────────────────────────────────────────────────────────
  await test("IDEM same evidence + same now -> identical payload", async () => {
    const first = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", first.deps);
    const second = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", second.deps);
    assert.deepStrictEqual(storedSummary(second), storedSummary(first));
  });

  await test("IDEM repeated refresh keeps exactly one document", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    await evaluateHealthReadiness("dog-1", fake.deps);
    await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(fake.store.size, 1);
  });

  // ── Technical blocker sanitization ───────────────────────────────────────
  await test("BLOCKERS are sanitized, deduplicated and sorted", () => {
    const codes = buildTechnicalBlockers([
      "Weight Source: INCONCLUSIVE",
      "weight_source_inconclusive",
      "  ",
      "nutrition/conflict",
    ]);
    assert.deepStrictEqual(codes, [
      "nutrition_conflict",
      "weight_source__inconclusive",
      "weight_source_inconclusive",
    ]);
    for (const code of codes) {
      assert.ok(/^[a-z0-9_]+$/.test(code), `${code} must be machine-readable`);
    }
  });

  // ── last_evaluated_at derivation ─────────────────────────────────────────
  await test("LAST_EVAL picks the newest factual instant across sources", () => {
    assert.deepStrictEqual(
      deriveLastEvaluatedAt({
        weightAt: daysAgo(10),
        vaccinationAt: daysAgo(3),
        consultationAt: daysAgo(7),
        examAt: daysAgo(20),
      }),
      daysAgo(3),
    );
  });

  await test("LAST_EVAL is null when no factual evidence exists", () => {
    assert.strictEqual(deriveLastEvaluatedAt({}), null);
    assert.strictEqual(
      deriveLastEvaluatedAt({weightAt: null, consultationAt: null}),
      null,
    );
  });

  // ── Authority boundary ───────────────────────────────────────────────────
  await test("AUTHORITY projector never writes outside health_summary/current", async () => {
    const written: string[] = [];
    const fake = createFake(completeSources());
    const wrapped: ProjectorDeps = {
      ...fake.deps,
      firestore: {
        ...fake.deps.firestore,
        writeCurrentSummary: async (dogId, payload) => {
          written.push(dogId);
          await fake.deps.firestore.writeCurrentSummary(dogId, payload);
        },
      },
    };
    await evaluateHealthReadiness("dog-1", wrapped);
    // Exactly one write target, and it is the summary document.
    assert.deepStrictEqual(written, ["dog-1"]);
  });

  await test("AUTHORITY invalid dogId is rejected before any I/O", async () => {
    const fake = createFake(completeSources());
    for (const bad of ["", "   ", "a/b", ".", ".."]) {
      await assert.rejects(
        () => evaluateHealthReadiness(bad, fake.deps),
        /invalid_dog_id/,
        `dogId ${JSON.stringify(bad)} must be rejected`,
      );
    }
  });

  if (failures > 0) {
    console.error(`\n${failures} test(s) failed`);
    process.exitCode = 1;
    return;
  }
  console.log("health_readiness_projector_test: all passed");
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
