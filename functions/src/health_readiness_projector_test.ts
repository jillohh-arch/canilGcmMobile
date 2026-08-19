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
import {
  decideProjectionApply,
  nextGeneration,
  parseGenerationField,
  parseGenerationState,
  MAX_READINESS_GENERATION,
} from "./health_readiness_generation";

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
  /** Coordination state per dog, mirroring _health_projection_state. */
  readonly generations: Map<string, GenerationDoc>;
  writeCount: number;
}

type GenerationDoc = Record<string, unknown>;

/**
 * In-memory readiness Firestore fake with generation coordination.
 *
 * Reservation and apply mirror the production adapter's transactional guard,
 * so ordering/superseded behavior is exercised without the emulator. An
 * optional `beforeApply` hook lets a test interleave a concurrent execution
 * between another's evaluate and commit — the deterministic way to reproduce an
 * out-of-order write without sleeps.
 */
function createFake(
  sources: FakeSources,
  existingSummary: Record<string, unknown> | null = null,
  options: {beforeApply?: (dogId: string) => Promise<void> | void} = {},
): Fake {
  const store = new Map<string, Record<string, unknown>>();
  if (existingSummary !== null) {
    store.set("dog-1", {...existingSummary});
  }
  const generations = new Map<string, GenerationDoc>();
  const state = {writeCount: 0};

  const firestore: ProjectorFirestore = {
    readSubcollection: async (_dogId, collection) => {
      const query = (sources as Record<string, RawQuery | undefined>)[collection];
      return query ?? EMPTY;
    },
    readCurrentSummary: async (dogId) => store.get(dogId) ?? null,
    reserveProjectionGeneration: async (dogId) => {
      const parsed = parseGenerationState(generations.get(dogId) ?? null);
      const reserved = nextGeneration(parsed.lastReservedGeneration);
      const prev = generations.get(dogId) ?? {};
      generations.set(dogId, {...prev, last_reserved_generation: reserved});
      return reserved;
    },
    applyProjection: async ({dogId, generation, isReady, payload}) => {
      if (options.beforeApply) await options.beforeApply(dogId);
      const parsed = parseGenerationState(generations.get(dogId) ?? null);
      const decision = decideProjectionApply({state: parsed, generation, isReady});
      if (decision.kind === "superseded") return "superseded";

      state.writeCount += 1;
      const patch: Record<string, unknown> = {...payload};
      if (decision.publishReadyGeneration !== null) {
        patch["projection_generation"] = decision.publishReadyGeneration;
      }
      // Emulates set(..., {merge: true}) for the summary...
      const previous = store.get(dogId) ?? {};
      store.set(dogId, {...previous, ...patch});
      // ...committed atomically with the applied-generation bump.
      const prevGen = generations.get(dogId) ?? {};
      generations.set(dogId, {...prevGen, last_applied_generation: generation});
      return decision.outcome;
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
    generations,
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
        applyProjection: async (args) => {
          written.push(args.dogId);
          return fake.deps.firestore.applyProjection(args);
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

  // ── GEN — generation reservation ─────────────────────────────────────────
  await test("GEN first reservation is 1 and reservations are monotonic", async () => {
    const fake = createFake(completeSources());
    assert.strictEqual(
      await fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      1,
    );
    assert.strictEqual(
      await fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      2,
    );
    assert.strictEqual(
      await fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      3,
    );
  });

  await test("GEN concurrent reservations are unique", async () => {
    const fake = createFake(completeSources());
    const reserved = await Promise.all([
      fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      fake.deps.firestore.reserveProjectionGeneration("dog-1"),
    ]);
    assert.strictEqual(new Set(reserved).size, 3, "generations must be unique");
  });

  await test("GEN different dogs reserve independently", async () => {
    const fake = createFake(completeSources());
    assert.strictEqual(
      await fake.deps.firestore.reserveProjectionGeneration("dog-1"),
      1,
    );
    assert.strictEqual(
      await fake.deps.firestore.reserveProjectionGeneration("dog-2"),
      1,
    );
  });

  await test("GEN gaps are tolerated (reserved without applying)", () => {
    // Reserved 5, applied 3: a dead execution leaves a hole, which is fine.
    const state = parseGenerationState({
      last_reserved_generation: 5,
      last_applied_generation: 3,
    });
    assert.strictEqual(state.lastReservedGeneration, 5);
    assert.strictEqual(state.lastAppliedGeneration, 3);
    assert.strictEqual(nextGeneration(state.lastReservedGeneration), 6);
  });

  await test("GEN absent state bootstraps to zero", () => {
    const state = parseGenerationState(null);
    assert.strictEqual(state.lastReservedGeneration, 0);
    assert.strictEqual(state.lastAppliedGeneration, 0);
    assert.strictEqual(parseGenerationField(undefined, "f"), 0);
    assert.strictEqual(parseGenerationField(null, "f"), 0);
  });

  await test("GEN malformed state fails closed, never resets", () => {
    for (const bad of ["3", 1.5, -1, Number.NaN, true, {}, []]) {
      assert.throws(
        () => parseGenerationField(bad, "last_reserved_generation"),
        /invalid_generation_state/,
        `${JSON.stringify(bad)} must fail closed`,
      );
    }
    assert.throws(
      () => parseGenerationState({last_applied_generation: 9, last_reserved_generation: 2}),
      /applied_ahead_of_reserved/,
    );
  });

  await test("GEN exhaustion fails closed instead of wrapping", () => {
    assert.throws(
      () => nextGeneration(MAX_READINESS_GENERATION),
      /generation_exhausted/,
    );
  });

  // ── GUARD — ordering decision ────────────────────────────────────────────
  await test("GUARD superseded when applied generation is equal or newer", () => {
    const state = {lastReservedGeneration: 9, lastAppliedGeneration: 5};
    for (const gen of [1, 4, 5]) {
      assert.strictEqual(
        decideProjectionApply({state, generation: gen, isReady: true}).kind,
        "superseded",
        `generation ${gen} must be superseded by applied 5`,
      );
    }
    assert.strictEqual(
      decideProjectionApply({state, generation: 6, isReady: true}).kind,
      "apply",
    );
  });

  await test("GUARD ready publishes generation, unavailable does not", () => {
    const state = {lastReservedGeneration: 2, lastAppliedGeneration: 0};
    const ready = decideProjectionApply({state, generation: 1, isReady: true});
    assert.strictEqual(ready.kind, "apply");
    assert.strictEqual(
      ready.kind === "apply" ? ready.publishReadyGeneration : "n/a",
      1,
    );
    const unavailable = decideProjectionApply({state, generation: 2, isReady: false});
    assert.strictEqual(unavailable.kind, "apply");
    assert.strictEqual(
      unavailable.kind === "apply" ? unavailable.publishReadyGeneration : "n/a",
      null,
      "unavailable must never advance the client-observable generation",
    );
  });

  // ── ORDER — end-to-end races through the projector ───────────────────────
  const failedWeight: FakeSources = {
    ...completeSources(),
    weight_records: {kind: "failed", reasonCode: "unavailable"},
  };

  await test("ORDER ready publishes projection_generation on the summary", async () => {
    const fake = createFake(completeSources());
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.requiredGeneration, 1);
    assert.strictEqual(result.applyOutcome, "applied_ready");
    assert.strictEqual(storedSummary(fake)["projection_generation"], 1);
  });

  await test("ORDER newer ready advances the generation", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    const second = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(second.requiredGeneration, 2);
    assert.strictEqual(storedSummary(fake)["projection_generation"], 2);
  });

  await test("ORDER stale READY cannot overwrite newer READY", async () => {
    // P1 reserves 1 and evaluates, but a full newer execution (2) commits in
    // the interleaving window before P1 applies.
    let interleaved = false;
    const fake = createFake(completeSources(), null, {
      beforeApply: async () => {
        if (interleaved) return;
        interleaved = true;
        await evaluateHealthReadiness("dog-1", fake.deps);
      },
    });
    const p1 = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(p1.requiredGeneration, 1);
    assert.strictEqual(p1.applyOutcome, "superseded", "stale P1 must not write");
    assert.strictEqual(storedSummary(fake)["projection_generation"], 2);
  });

  await test("ORDER stale UNAVAILABLE cannot overwrite newer READY", async () => {
    // The correction that motivated last_applied_generation: without ordering
    // unavailable writes too, this stale run would merge
    // projection_status/technical_blockers over a newer ready projection.
    let interleaved = false;
    const fake = createFake(failedWeight, null, {
      beforeApply: async () => {
        if (interleaved) return;
        interleaved = true;
        const readyFake = {...fake.deps, firestore: fake.deps.firestore};
        // Newer generation 2 evaluates READY from complete sources.
        await evaluateHealthReadiness("dog-1", {
          ...readyFake,
          firestore: {
            ...fake.deps.firestore,
            readSubcollection: async (_dogId, collection) =>
              (completeSources() as Record<string, RawQuery | undefined>)[collection] ??
              EMPTY,
          },
        });
      },
    });
    const stale = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(stale.operation, "unavailable_initial");
    assert.strictEqual(stale.applyOutcome, "superseded");

    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_status"], "ready");
    assert.strictEqual(stored["projection_generation"], 2);
    assert.deepStrictEqual(stored["technical_blockers"], []);
  });

  await test("ORDER newer UNAVAILABLE keeps the last READY generation", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(storedSummary(fake)["projection_generation"], 1);

    // Generation 2 fails technically: status flips, ready generation must not.
    const unavailable = await evaluateHealthReadiness("dog-1", {
      ...fake.deps,
      firestore: {
        ...fake.deps.firestore,
        readSubcollection: async (_dogId, collection) =>
          (failedWeight as Record<string, RawQuery | undefined>)[collection] ?? EMPTY,
      },
    });
    assert.strictEqual(unavailable.requiredGeneration, 2);
    assert.strictEqual(unavailable.applyOutcome, "applied_unavailable");

    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_status"], "unavailable");
    assert.strictEqual(
      stored["projection_generation"],
      1,
      "an unavailable run must not satisfy causal convergence for generation 2",
    );
    // Last-known-good clinical payload survives untouched.
    assert.strictEqual(stored["readiness_status"], "operational");
  });

  await test("ORDER unavailable on a fresh dog creates no ready generation", async () => {
    const fake = createFake(failedWeight);
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.operation, "unavailable_initial");
    assert.strictEqual(result.applyOutcome, "applied_unavailable");
    const stored = storedSummary(fake);
    assert.ok(
      !("projection_generation" in stored),
      "no fabricated ready generation",
    );
  });

  await test("ORDER stale UNAVAILABLE cannot overwrite newer UNAVAILABLE", async () => {
    let interleaved = false;
    const fake = createFake(failedWeight, null, {
      beforeApply: async () => {
        if (interleaved) return;
        interleaved = true;
        await evaluateHealthReadiness("dog-1", fake.deps);
      },
    });
    const stale = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(stale.requiredGeneration, 1);
    assert.strictEqual(stale.applyOutcome, "superseded");
    assert.strictEqual(
      parseGenerationState(fake.generations.get("dog-1") ?? null)
        .lastAppliedGeneration,
      2,
    );
  });

  await test("ORDER superseded performs zero summary writes", async () => {
    const fake = createFake(completeSources());
    // Reserve two generations, then apply the newer one first so the older is
    // born stale — respecting the reserved >= applied invariant.
    const g1 = await fake.deps.firestore.reserveProjectionGeneration("dog-1");
    const g2 = await fake.deps.firestore.reserveProjectionGeneration("dog-1");
    await fake.deps.firestore.applyProjection({
      dogId: "dog-1",
      generation: g2,
      isReady: false,
      payload: {projection_status: "unavailable"},
    });
    const before = fake.writeCount;
    const outcome = await fake.deps.firestore.applyProjection({
      dogId: "dog-1",
      generation: g1,
      isReady: true,
      payload: {projection_status: "ready"},
    });
    assert.strictEqual(outcome, "superseded");
    assert.strictEqual(fake.writeCount, before, "no write on superseded");
  });

  await test("ORDER apply commits summary and applied generation together", async () => {
    const fake = createFake(completeSources());
    await evaluateHealthReadiness("dog-1", fake.deps);
    const state = parseGenerationState(fake.generations.get("dog-1") ?? null);
    assert.strictEqual(state.lastAppliedGeneration, 1);
    assert.strictEqual(storedSummary(fake)["projection_generation"], 1);
  });

  await test("ORDER legacy summary without generation still accepts a ready apply", async () => {
    const fake = createFake(completeSources(), {
      schema_version: 1,
      readiness_status: "temporarily_unfit",
    });
    const result = await evaluateHealthReadiness("dog-1", fake.deps);
    assert.strictEqual(result.applyOutcome, "applied_ready");
    const stored = storedSummary(fake);
    assert.strictEqual(stored["projection_generation"], 1);
    assert.strictEqual(stored["schema_version"], 1, "schema_version is not bumped");
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
