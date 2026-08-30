/**
 * Readiness v1 — evidence classification tests (Gate 2).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Covers §11 of the gate: weight, vaccination, consultation, nutrition and
 * operational restrictions, plus the technical-failure semantics that keep
 * "query error", "malformed" and "none recorded" distinguishable.
 */

import * as assert from "assert";
import {
  analyzeWeightCollection,
  classifyHealthEvent,
  classifyWeightDoc,
  compareWeightCanonicalOrder,
  RawDoc,
  RawQuery,
  readInstant,
  resolveConsultationEvidence,
  resolveExamEvidence,
  resolveNutritionEvidence,
  resolveRestrictionsEvidence,
  resolveVaccinationEvidence,
  resolveWeightEvidence,
} from "./health_readiness_evidence_logic";
import {
  DEFAULT_READINESS_CONFIG,
  evaluateReadiness,
} from "./health_readiness_policy";
import {resolveReadinessConfig} from "./health_readiness_config";

const NOW = new Date("2026-08-11T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

function daysAgo(days: number): Date {
  return new Date(NOW.getTime() - days * MILLIS_PER_DAY);
}

function daysAhead(days: number): Date {
  return new Date(NOW.getTime() + days * MILLIS_PER_DAY);
}

/** Minimal Firestore Timestamp stand-in: the pure layer only needs toDate(). */
function ts(date: Date): {toDate: () => Date} {
  return {toDate: () => date};
}

function doc(id: string, data: Record<string, unknown>): RawDoc {
  return {id, data};
}

function docs(...entries: RawDoc[]): RawQuery {
  return {kind: "docs", docs: entries};
}

const EMPTY: RawQuery = {kind: "docs", docs: []};

function failed(reasonCode = "permission_denied"): RawQuery {
  return {kind: "failed", reasonCode};
}

/**
 * DEPLOYED V1 shape — exactly what the canonical writer emits today
 * (health_weight_engine.ts): schema_version 1, no target-v2 field, so
 * `recordedAt` is null by definition and `created_at` is only fallback
 * metadata.
 */
function weightDoc(
  id: string,
  overrides: Record<string, unknown> = {},
): RawDoc {
  return doc(id, {
    dogId: "dog-1",
    dog_id: "dog-1",
    weight_kg: 28.8,
    measured_at: ts(daysAgo(1)),
    recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
    schema_version: 1,
    created_at: ts(daysAgo(1)),
    updated_at: ts(daysAgo(1)),
    ...overrides,
  });
}

/** TARGET V2 shape — carries a FACTUAL recorded_at. */
function weightV2Doc(
  id: string,
  overrides: Record<string, unknown> = {},
): RawDoc {
  return doc(id, {
    dogId: "dog-1",
    dog_id: "dog-1",
    weight_kg: 28.8,
    measured_at: ts(daysAgo(1)),
    recorded_at: ts(daysAgo(1)),
    recorded_by: {uid: "u1", name: "Condutor", internal_role: "condutor"},
    schema_version: 2,
    created_at: ts(daysAgo(1)),
    updated_at: ts(daysAgo(1)),
    ...overrides,
  });
}

/** Recognized health_events writer shape (HealthLogModel.toJson()). */
function eventDoc(
  id: string,
  type: string,
  overrides: Record<string, unknown> = {},
): RawDoc {
  return doc(id, {
    dogId: "dog-1",
    dogName: "Bono",
    date: ts(daysAgo(1)),
    type,
    healthObservations: "",
    audit_trail: [],
    created_at: ts(daysAgo(1)),
    updated_at: ts(daysAgo(1)),
    ...overrides,
  });
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
  // ══ CONFIG OWNER ═════════════════════════════════════════════════════════
  await test("CONFIG resolves ratified defaults from the params source", () => {
    const config = resolveReadinessConfig({
      weightMaxAgeDays: () => 90,
      consultationMaxAgeDays: () => 180,
    });
    assert.deepStrictEqual(config, {
      weightMaxAgeDays: 90,
      consultationMaxAgeDays: 180,
    });
  });

  await test("CONFIG honours an operator override", () => {
    const config = resolveReadinessConfig({
      weightMaxAgeDays: () => 45,
      consultationMaxAgeDays: () => 365,
    });
    assert.strictEqual(config.weightMaxAgeDays, 45);
    assert.strictEqual(config.consultationMaxAgeDays, 365);
  });

  await test("CONFIG falls back to ratified values on unusable input", () => {
    for (const bad of [0, -5, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      const config = resolveReadinessConfig({
        weightMaxAgeDays: () => bad,
        consultationMaxAgeDays: () => bad,
      });
      assert.strictEqual(config.weightMaxAgeDays, 90, `weight for ${bad}`);
      assert.strictEqual(config.consultationMaxAgeDays, 180, `consulta for ${bad}`);
    }
  });

  await test("CONFIG has no exam threshold", () => {
    const config = resolveReadinessConfig({
      weightMaxAgeDays: () => 90,
      consultationMaxAgeDays: () => 180,
    });
    assert.deepStrictEqual(Object.keys(config).sort(), [
      "consultationMaxAgeDays",
      "weightMaxAgeDays",
    ]);
  });

  // ══ SHARED TEMPORAL PARSING ══════════════════════════════════════════════
  await test("readInstant accepts Timestamp and ISO string, rejects the rest", () => {
    assert.deepStrictEqual(readInstant(ts(NOW)), NOW);
    assert.deepStrictEqual(readInstant(NOW.toISOString()), NOW);
    for (const bad of [null, undefined, "", "   ", "not-a-date", 123, {}, []]) {
      assert.strictEqual(readInstant(bad), null, `must reject ${JSON.stringify(bad)}`);
    }
  });

  await test("readInstant rejects a pending serverTimestamp sentinel", () => {
    // A sentinel has no toDate(), so it must not read as a valid instant.
    assert.strictEqual(readInstant({_methodName: "serverTimestamp"}), null);
  });

  // ══ WEIGHT ═══════════════════════════════════════════════════════════════
  await test("WEIGHT canonical current is the newest measured_at", () => {
    const query = docs(
      weightDoc("w-old", {measured_at: ts(daysAgo(30))}),
      weightDoc("w-new", {measured_at: ts(daysAgo(1))}),
      weightDoc("w-mid", {measured_at: ts(daysAgo(10))}),
    );
    const analysis = analyzeWeightCollection(query.kind === "docs" ? query.docs : []);
    assert.strictEqual(analysis.kind, "current");
    assert.strictEqual(analysis.current?.entityId, "w-new");
  });

  // ── Dart/TS parity matrix (P1..P5) ───────────────────────────────────────
  // Parity target: compareWeightCanonicalOrder in
  // lib/features/health/domain/weight_collection_policy.dart, which accepts
  // only (measuredAt, recordedAt, entityId). `created_at` MUST NOT influence
  // current-weight selection: if it did, this server could pick a different
  // current weight than the homologated Mobile card.

  await test("P1 same measured_at, different factual recorded_at -> recorded_at decides", () => {
    const measured = ts(daysAgo(5));
    const analysis = analyzeWeightCollection([
      weightV2Doc("w-a", {measured_at: measured, recorded_at: ts(daysAgo(4))}),
      weightV2Doc("w-b", {measured_at: measured, recorded_at: ts(daysAgo(2))}),
    ]);
    assert.strictEqual(analysis.current?.entityId, "w-b");
  });

  await test("P1b factual recorded_at outranks a contradicting entityId order", () => {
    const measured = ts(daysAgo(5));
    // entityId DESC alone would pick "w-zzz"; recorded_at must win.
    const analysis = analyzeWeightCollection([
      weightV2Doc("w-zzz", {measured_at: measured, recorded_at: ts(daysAgo(9))}),
      weightV2Doc("w-aaa", {measured_at: measured, recorded_at: ts(daysAgo(1))}),
    ]);
    assert.strictEqual(
      analysis.current?.entityId,
      "w-aaa",
      "newer factual recorded_at must beat a higher entityId",
    );
  });

  await test("P2 factual recorded_at beats null recorded_at", () => {
    const measured = ts(daysAgo(5));
    const analysis = analyzeWeightCollection([
      // v1 → recordedAt null by definition.
      weightDoc("w-v1", {measured_at: measured}),
      weightV2Doc("w-v2", {measured_at: measured, recorded_at: ts(daysAgo(7))}),
    ]);
    assert.strictEqual(analysis.current?.entityId, "w-v2");
  });

  await test("P3 v1 null/null tie: created_at is IGNORED, entityId decides", () => {
    const measured = ts(daysAgo(5));
    // created_at order deliberately contradicts entityId order. Under the
    // canonical contract the newer created_at must NOT win.
    const analysis = analyzeWeightCollection([
      weightDoc("w-zzz", {measured_at: measured, created_at: ts(daysAgo(9))}),
      weightDoc("w-aaa", {measured_at: measured, created_at: ts(daysAgo(1))}),
    ]);
    assert.strictEqual(
      analysis.current?.entityId,
      "w-zzz",
      "entityId DESC must decide; created_at must not participate",
    );
    assert.strictEqual(analysis.current?.recordedAt, null);
    // Preserved as compatibility metadata only.
    assert.notStrictEqual(analysis.current?.orderingFallbackAt, null);
  });

  await test("P4 changing either created_at does not change the winner", () => {
    const measured = ts(daysAgo(5));
    const winners = new Set<string>();
    for (const [aCreated, bCreated] of [
      [ts(daysAgo(9)), ts(daysAgo(1))],
      [ts(daysAgo(1)), ts(daysAgo(9))],
      [ts(daysAgo(3)), ts(daysAgo(3))],
      [ts(NOW), ts(daysAgo(400))],
    ] as const) {
      const analysis = analyzeWeightCollection([
        weightDoc("w-zzz", {measured_at: measured, created_at: aCreated}),
        weightDoc("w-aaa", {measured_at: measured, created_at: bCreated}),
      ]);
      winners.add(analysis.current?.entityId ?? "none");
    }
    assert.deepStrictEqual(
      [...winners],
      ["w-zzz"],
      "created_at permutations must never alter the winner",
    );
  });

  await test("P5 v1 null/null tie: reversing entityId reverses the winner", () => {
    const measured = ts(daysAgo(5));
    const created = ts(daysAgo(3));
    const lower = analyzeWeightCollection([
      weightDoc("w-aaa", {measured_at: measured, created_at: created}),
      weightDoc("w-bbb", {measured_at: measured, created_at: created}),
    ]);
    assert.strictEqual(lower.current?.entityId, "w-bbb");

    const higher = analyzeWeightCollection([
      weightDoc("w-yyy", {measured_at: measured, created_at: created}),
      weightDoc("w-zzz", {measured_at: measured, created_at: created}),
    ]);
    assert.strictEqual(higher.current?.entityId, "w-zzz");
  });

  await test("WEIGHT selection is independent of input order", () => {
    const measured = ts(daysAgo(5));
    const a = weightDoc("w-a", {measured_at: measured, created_at: ts(daysAgo(4))});
    const b = weightDoc("w-b", {measured_at: measured, created_at: ts(daysAgo(2))});
    const forward = analyzeWeightCollection([a, b]);
    const reverse = analyzeWeightCollection([b, a]);
    assert.strictEqual(forward.current?.entityId, reverse.current?.entityId);
  });

  // ── Deployed-v1 provenance classification (strict) ───────────────────────
  await test("V1 hybrid v1/v2 shape is malformed", () => {
    // schema_version 1 carrying a target-v2 field — the exact combination that
    // the Mobile parser rejects as hybridV1V2.
    for (const field of ["recorded_at", "revision", "record_type", "status"]) {
      const candidate = classifyWeightDoc(
        weightDoc("w-x", {[field]: ts(NOW)}),
      );
      assert.strictEqual(candidate.kind, "malformed", `${field} must be hybrid`);
    }
  });

  await test("V1 valid weight without canonical recorded_by is malformed", () => {
    // A legacy write can carry weight_kg + measured_at; that is NOT sufficient
    // provenance to be treated as canonical.
    const candidate = classifyWeightDoc(
      doc("w-legacy", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        schema_version: 1,
      }),
    );
    assert.strictEqual(candidate.kind, "malformed");
  });

  await test("V1 incomplete recorded_by envelope is malformed", () => {
    for (const envelope of [
      {uid: "u1", name: "C"},
      {uid: "u1", internal_role: "condutor"},
      {name: "C", internal_role: "condutor"},
      {uid: "", name: "C", internal_role: "condutor"},
      "condutor",
      null,
    ]) {
      const candidate = classifyWeightDoc(
        weightDoc("w-x", {recorded_by: envelope}),
      );
      assert.strictEqual(
        candidate.kind,
        "malformed",
        `envelope ${JSON.stringify(envelope)} must be rejected`,
      );
    }
  });

  await test("V1 missing or invalid schema_version is malformed", () => {
    for (const schema of [undefined, 0, -1, 1.5, "1", null]) {
      const candidate = classifyWeightDoc(
        weightDoc("w-x", {schema_version: schema}),
      );
      assert.strictEqual(candidate.kind, "malformed", `schema ${schema}`);
    }
  });

  await test("WEIGHT schema_version above 2 is unsupported, not malformed", () => {
    const candidate = classifyWeightDoc(weightDoc("w-x", {schema_version: 3}));
    assert.strictEqual(candidate.kind, "unsupported");
  });

  await test("V2 without factual recorded_at is malformed", () => {
    const candidate = classifyWeightDoc(
      doc("w-x", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        schema_version: 2,
        recorded_by: {uid: "u1", name: "C", internal_role: "condutor"},
      }),
    );
    assert.strictEqual(candidate.kind, "malformed");
  });

  await test("WEIGHT embedded dog identity must agree with the path dogId", () => {
    const mismatch = classifyWeightDoc(
      weightDoc("w-x", {dog_id: "outro-dog", dogId: "outro-dog"}),
      "dog-1",
    );
    assert.strictEqual(mismatch.kind, "malformed");

    const agree = classifyWeightDoc(weightDoc("w-x"), "dog-1");
    assert.strictEqual(agree.kind, "valid");
  });

  await test("WEIGHT malformed document escalates the collection to inconclusive", () => {
    const analysis = analyzeWeightCollection([
      weightDoc("w-good"),
      doc("w-bad", {weight_kg: "muito", measured_at: ts(daysAgo(1))}),
    ]);
    assert.strictEqual(analysis.kind, "inconclusive");
    assert.strictEqual(analysis.current, null);
    assert.ok(analysis.blockers.includes("malformed"));
  });

  await test("WEIGHT missing measured_at is malformed, not merely skipped", () => {
    const candidate = classifyWeightDoc(doc("w-x", {weight_kg: 28.8}));
    assert.strictEqual(candidate.kind, "malformed");
  });

  // ── Recognized legacy shapes (NO schema_version key) ─────────────────────
  //
  // Frozen from the first production homologation: this exact shape made the
  // Mobile card render 28.8 kg while readiness published
  // `weight_source_inconclusive` / `projection_status: unavailable`.
  await test("WEIGHT-LEGACY Bono production shape is recognized legacy Mobile", () => {
    const bono = doc("4tR5lSuUNqBaqwK85POO", {
      weight_kg: 28.8,
      measured_at: ts(daysAgo(1)),
      measured_by: "Condutor Responsavel",
      created_at: ts(daysAgo(1)),
      updated_at: ts(daysAgo(1)),
      context: "rotina",
      notes: "",
      audit_trail: [{performed_by: "u1"}],
    });

    const candidate = classifyWeightDoc(bono, "4DDeRe7CCjTte6nbUbrC");
    assert.strictEqual(candidate.kind, "valid");
    // Legacy persists no factual recording instant, and created_at is never
    // promoted to authority — only kept as ordering fallback metadata.
    assert.strictEqual(candidate.recordedAt, null);
    assert.notStrictEqual(candidate.orderingFallbackAt, null);

    // And the collection must become conclusive with weight evidence present.
    const analysis = analyzeWeightCollection([bono], "4DDeRe7CCjTte6nbUbrC");
    assert.strictEqual(analysis.kind, "current");
    assert.deepStrictEqual(analysis.blockers, []);

    const evidence = resolveWeightEvidence(docs(bono), "4DDeRe7CCjTte6nbUbrC");
    assert.strictEqual(evidence.kind, "present");
  });

  await test("WEIGHT-LEGACY web shape (measured_by + performed_by) is valid", () => {
    const candidate = classifyWeightDoc(
      doc("w-web", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(2)),
        measured_by: "Veterinario",
        performed_by: "u-web",
      }),
    );
    assert.strictEqual(candidate.kind, "valid");
  });

  await test("WEIGHT-LEGACY dog-update shape (performed_by only) is valid", () => {
    const candidate = classifyWeightDoc(
      doc("w-dog", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(3)),
        performed_by: "u-dog",
      }),
    );
    assert.strictEqual(candidate.kind, "valid");
  });

  await test("WEIGHT-LEGACY dog-update with narrative fields is NOT recognized", () => {
    // `context`/`notes` never came from the dog-update writer, so this is an
    // unknown shape rather than a tolerated one.
    for (const narrative of [{context: "rotina"}, {notes: "obs"}]) {
      const candidate = classifyWeightDoc(
        doc("w-amb", {
          weight_kg: 28.8,
          measured_at: ts(daysAgo(3)),
          performed_by: "u-dog",
          ...narrative,
        }),
      );
      assert.strictEqual(candidate.kind, "malformed");
    }
  });

  await test("WEIGHT-LEGACY blank/non-string measured_by is NOT recognized", () => {
    for (const bad of ["", "   ", 42, {}]) {
      const candidate = classifyWeightDoc(
        doc("w-blank", {
          weight_kg: 28.8,
          measured_at: ts(daysAgo(1)),
          measured_by: bad,
        }),
      );
      assert.strictEqual(
        candidate.kind,
        "malformed",
        `measured_by=${JSON.stringify(bad)}`,
      );
    }
  });

  await test("WEIGHT-LEGACY legacy carrying recorded_by is NOT recognized", () => {
    const candidate = classifyWeightDoc(
      doc("w-mixed", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        measured_by: "Condutor",
        recorded_by: {uid: "u1", name: "C", internal_role: "condutor"},
      }),
    );
    assert.strictEqual(candidate.kind, "malformed");
  });

  await test("WEIGHT-LEGACY legacy carrying target-v2 field is hybrid malformed", () => {
    const candidate = classifyWeightDoc(
      doc("w-hybrid", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        measured_by: "Condutor",
        bcs: 5,
      }),
    );
    assert.strictEqual(candidate.kind, "malformed");
  });

  await test("WEIGHT-LEGACY broken schema_version stays malformed", () => {
    // Present-but-invalid schema_version must NOT fall through to legacy.
    for (const bad of [0, -1, 1.5, "1", null]) {
      const candidate = classifyWeightDoc(
        doc("w-schema", {
          schema_version: bad,
          weight_kg: 28.8,
          measured_at: ts(daysAgo(1)),
          measured_by: "Condutor",
        }),
      );
      assert.strictEqual(
        candidate.kind,
        "malformed",
        `schema_version=${JSON.stringify(bad)}`,
      );
    }
  });

  await test("WEIGHT-LEGACY cross-dog legacy document is rejected", () => {
    const candidate = classifyWeightDoc(
      doc("w-other", {
        dog_id: "outro-cao",
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        measured_by: "Condutor",
      }),
      "dog-1",
    );
    assert.strictEqual(candidate.kind, "malformed");
  });

  await test("WEIGHT-LEGACY invalidated legacy record still does not block", () => {
    const candidate = classifyWeightDoc(
      doc("w-inv-legacy", {
        weight_kg: 28.8,
        measured_at: ts(daysAgo(1)),
        measured_by: "Condutor",
        deleted_at: ts(daysAgo(1)),
      }),
    );
    assert.strictEqual(candidate.kind, "invalidated");
  });

  await test("WEIGHT-LEGACY ordering: v1 beats legacy on same measured_at", () => {
    // Neither persists a factual recorded_at, so entityId DESC decides — and
    // created_at must not sneak in as a tiebreaker.
    const legacy = doc("w-aaa", {
      weight_kg: 30,
      measured_at: ts(daysAgo(1)),
      measured_by: "Condutor",
      created_at: ts(NOW),
    });
    const deployed = weightDoc("w-zzz", {measured_at: ts(daysAgo(1))});

    const forward = analyzeWeightCollection([legacy, deployed]);
    const reverse = analyzeWeightCollection([deployed, legacy]);
    assert.strictEqual(forward.current?.entityId, "w-zzz");
    assert.strictEqual(reverse.current?.entityId, "w-zzz");
  });

  await test("WEIGHT non-positive weight is malformed", () => {
    for (const bad of [0, -1, Number.NaN]) {
      const candidate = classifyWeightDoc(
        weightDoc("w-x", {weight_kg: bad}),
      );
      assert.strictEqual(candidate.kind, "malformed", `weight_kg=${bad}`);
    }
  });

  await test("WEIGHT invalidated record does not block and does not win", () => {
    const analysis = analyzeWeightCollection([
      weightDoc("w-inv", {
        measured_at: ts(NOW),
        invalidated_at: ts(daysAgo(1)),
      }),
      weightDoc("w-ok", {measured_at: ts(daysAgo(9))}),
    ]);
    assert.strictEqual(analysis.kind, "current");
    assert.strictEqual(analysis.current?.entityId, "w-ok");
  });

  await test("WEIGHT soft-deleted record is treated as invalidated", () => {
    const candidate = classifyWeightDoc(
      weightDoc("w-del", {deleted_at: ts(daysAgo(1))}),
    );
    assert.strictEqual(candidate.kind, "invalidated");
  });

  await test("WEIGHT duplicate entityId is a blocker", () => {
    const analysis = analyzeWeightCollection([
      weightDoc("w-dup"),
      weightDoc("w-dup"),
    ]);
    assert.strictEqual(analysis.kind, "inconclusive");
    assert.ok(analysis.blockers.includes("duplicateEntityId"));
  });

  await test("WEIGHT empty collection is absent, not unreliable", () => {
    assert.deepStrictEqual(resolveWeightEvidence(EMPTY), {kind: "absent"});
  });

  await test("WEIGHT query failure is unreliable, never absent", () => {
    const evidence = resolveWeightEvidence(failed("permission_denied"));
    assert.strictEqual(evidence.kind, "unreliable");
    assert.notStrictEqual(evidence.kind, "absent");
  });

  await test("WEIGHT inconclusive collection is unreliable, never absent", () => {
    const evidence = resolveWeightEvidence(
      docs(weightDoc("w-ok"), doc("w-bad", {weight_kg: 1})),
    );
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("WEIGHT comparator is a strict ordering primitive", () => {
    const base = {
      entityId: "a",
      kind: "valid" as const,
      measuredAt: NOW,
      recordedAt: NOW,
      orderingFallbackAt: NOW,
    };
    assert.strictEqual(compareWeightCanonicalOrder(base, base), 0);
  });

  // ══ VACCINATION ══════════════════════════════════════════════════════════
  await test("VACCINATION coexistence: current dose from health_events", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(
        eventDoc("e-1", "vaccination", {
          subtype: "Antirrábica",
          nextDueDate: ts(daysAhead(365)),
        }),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.deepStrictEqual(evidence.value.nextDueAt, daysAhead(365));
    }
  });

  await test("VACCINATION overdue dose is still present evidence (evaluator judges currency)", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(eventDoc("e-1", "vaccination", {nextDueDate: ts(daysAgo(10))})),
    );
    assert.strictEqual(evidence.kind, "present");
  });

  await test("VACCINATION dose without nextDueDate cannot prove currency", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(eventDoc("e-1", "vaccination")),
    );
    assert.deepStrictEqual(evidence, {kind: "absent"});
  });

  await test("VACCINATION unrelated health_event is ignored (E1)", () => {
    for (const type of ["consultation", "exam", "symptom", "medication", "surgery", "other"]) {
      const evidence = resolveVaccinationEvidence(
        EMPTY,
        docs(eventDoc("e-1", type, {nextDueDate: ts(daysAhead(365))})),
      );
      assert.deepStrictEqual(
        evidence,
        {kind: "absent"},
        `${type} must never read as vaccination`,
      );
    }
  });

  await test("VACCINATION soft-deleted dose does not count", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(
        eventDoc("e-1", "vaccination", {
          nextDueDate: ts(daysAhead(365)),
          deleted_at: ts(daysAgo(1)),
        }),
      ),
    );
    assert.deepStrictEqual(evidence, {kind: "absent"});
  });

  await test("VACCINATION malformed dose is unreliable, not absent", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(eventDoc("e-1", "vaccination", {date: "not-a-date"})),
    );
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("VACCINATION malformed nextDueDate is unreliable, not absent", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(eventDoc("e-1", "vaccination", {nextDueDate: 12345})),
    );
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("VACCINATION latest dose selected deterministically", () => {
    const evidence = resolveVaccinationEvidence(
      EMPTY,
      docs(
        eventDoc("e-old", "vaccination", {
          date: ts(daysAgo(400)),
          nextDueDate: ts(daysAgo(35)),
        }),
        eventDoc("e-new", "vaccination", {
          date: ts(daysAgo(10)),
          nextDueDate: ts(daysAhead(355)),
        }),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.deepStrictEqual(evidence.value.nextDueAt, daysAhead(355));
    }
  });

  await test("VACCINATION type discriminator is case-normalized but not translated", () => {
    const upper = resolveVaccinationEvidence(
      EMPTY,
      docs(eventDoc("e-1", "VACCINATION", {nextDueDate: ts(daysAhead(10))})),
    );
    assert.strictEqual(upper.kind, "present");
    // Portuguese labels are normalized by the writer before persistence, so the
    // adapter must NOT invent them as accepted tokens.
    for (const spelling of ["vacina", "vacinação", "Vacina"]) {
      const evidence = resolveVaccinationEvidence(
        EMPTY,
        docs(eventDoc("e-1", spelling, {nextDueDate: ts(daysAhead(10))})),
      );
      assert.deepStrictEqual(
        evidence,
        {kind: "absent"},
        `${spelling} is not a factual runtime token`,
      );
    }
  });

  await test("VACCINATION canonical source wins; no silent health_events override", () => {
    const evidence = resolveVaccinationEvidence(
      docs(
        doc("v-1", {
          applied_at: ts(daysAgo(5)),
          next_due: ts(daysAhead(360)),
        }),
      ),
      // A coexistence event that would give a different answer is NOT consulted.
      docs(eventDoc("e-1", "vaccination", {nextDueDate: ts(daysAgo(1))})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.deepStrictEqual(evidence.value.nextDueAt, daysAhead(360));
    }
  });

  await test("VACCINATION canonical cancelled record is skipped", () => {
    const evidence = resolveVaccinationEvidence(
      docs(
        doc("v-1", {
          applied_at: ts(daysAgo(5)),
          next_due: ts(daysAhead(360)),
          status: "cancelled",
        }),
      ),
      EMPTY,
    );
    // Canonical collection held records, so the bridge stays unused; the only
    // canonical record was cancelled, hence absent.
    assert.deepStrictEqual(evidence, {kind: "absent"});
  });

  await test("VACCINATION canonical query failure is unreliable", () => {
    const evidence = resolveVaccinationEvidence(failed(), EMPTY);
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("VACCINATION coexistence query failure is unreliable", () => {
    const evidence = resolveVaccinationEvidence(EMPTY, failed());
    assert.strictEqual(evidence.kind, "unreliable");
  });

  // ══ CONSULTATION ═════════════════════════════════════════════════════════
  await test("CONSULTATION valid recent consultation is present", () => {
    const evidence = resolveConsultationEvidence(
      docs(eventDoc("e-1", "consultation", {date: ts(daysAgo(3))})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.deepStrictEqual(evidence.value, daysAgo(3));
    }
  });

  await test("CONSULTATION exam is never read as a consultation (E2)", () => {
    for (const type of ["exam", "vaccination", "symptom", "surgery", "other"]) {
      const evidence = resolveConsultationEvidence(
        docs(eventDoc("e-1", type, {date: ts(NOW)})),
      );
      assert.deepStrictEqual(
        evidence,
        {kind: "absent"},
        `${type} must never read as consultation`,
      );
    }
  });

  await test("CONSULTATION soft-deleted record does not count", () => {
    const evidence = resolveConsultationEvidence(
      docs(
        eventDoc("e-1", "consultation", {
          date: ts(NOW),
          deleted_at: ts(daysAgo(1)),
        }),
      ),
    );
    assert.deepStrictEqual(evidence, {kind: "absent"});
  });

  await test("CONSULTATION malformed consultation-like doc is unreliable", () => {
    const evidence = resolveConsultationEvidence(
      docs(eventDoc("e-1", "consultation", {date: null})),
    );
    assert.strictEqual(evidence.kind, "unreliable");
    assert.notStrictEqual(evidence.kind, "absent");
  });

  await test("CONSULTATION latest valid selected deterministically on date ties", () => {
    const sameDate = ts(daysAgo(4));
    const forward = resolveConsultationEvidence(
      docs(
        eventDoc("e-aaa", "consultation", {date: sameDate}),
        eventDoc("e-zzz", "consultation", {date: sameDate}),
      ),
    );
    const reverse = resolveConsultationEvidence(
      docs(
        eventDoc("e-zzz", "consultation", {date: sameDate}),
        eventDoc("e-aaa", "consultation", {date: sameDate}),
      ),
    );
    assert.deepStrictEqual(forward, reverse);
  });

  await test("CONSULTATION boundary: exactly 180d is recent, 181d is stale", () => {
    const atBoundary = evaluateReadiness({
      now: NOW,
      activeRestrictions: [],
      latestWeightAt: {kind: "present", value: daysAgo(1)},
      vaccination: {kind: "present", value: {nextDueAt: daysAhead(10)}},
      latestConsultationAt: {kind: "present", value: daysAgo(180)},
      nutrition: {kind: "present", value: {activePlanCount: 1}},
      latestExamAt: {kind: "absent"},
      config: DEFAULT_READINESS_CONFIG,
    });
    assert.strictEqual(atBoundary.outcome, "decided");
    if (atBoundary.outcome === "decided") {
      assert.strictEqual(atBoundary.decision.readinessStatus, "operational");
    }

    const pastBoundary = evaluateReadiness({
      now: NOW,
      activeRestrictions: [],
      latestWeightAt: {kind: "present", value: daysAgo(1)},
      vaccination: {kind: "present", value: {nextDueAt: daysAhead(10)}},
      latestConsultationAt: {kind: "present", value: daysAgo(181)},
      nutrition: {kind: "present", value: {activePlanCount: 1}},
      latestExamAt: {kind: "absent"},
      config: DEFAULT_READINESS_CONFIG,
    });
    assert.strictEqual(pastBoundary.outcome, "decided");
    if (pastBoundary.outcome === "decided") {
      assert.strictEqual(
        pastBoundary.decision.readinessStatus,
        "operational_attention",
      );
    }
  });

  await test("CONSULTATION query failure is unreliable", () => {
    assert.strictEqual(resolveConsultationEvidence(failed()).kind, "unreliable");
  });

  await test("CONSULTATION empty is absent", () => {
    assert.deepStrictEqual(resolveConsultationEvidence(EMPTY), {kind: "absent"});
  });

  // ══ EXAM (informational only) ════════════════════════════════════════════
  await test("EXAM reads only exam events and stays informational", () => {
    const evidence = resolveExamEvidence(
      docs(
        eventDoc("e-1", "exam", {date: ts(daysAgo(20))}),
        eventDoc("e-2", "consultation", {date: ts(NOW)}),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.deepStrictEqual(evidence.value, daysAgo(20));
    }
  });

  await test("EXAM classification helper distinguishes match/ignored/malformed", () => {
    assert.strictEqual(
      classifyHealthEvent(eventDoc("e", "exam"), "exam").kind,
      "match",
    );
    assert.strictEqual(
      classifyHealthEvent(eventDoc("e", "symptom"), "exam").kind,
      "ignored",
    );
    assert.strictEqual(
      classifyHealthEvent(eventDoc("e", "exam", {date: 42}), "exam").kind,
      "malformed",
    );
  });

  await test("EXAM missing type field is ignored, not malformed", () => {
    const raw = doc("e", {dogId: "dog-1", date: ts(NOW)});
    assert.strictEqual(classifyHealthEvent(raw, "exam").kind, "ignored");
  });

  // ══ NUTRITION ════════════════════════════════════════════════════════════
  await test("NUTRITION zero active plans -> count 0", () => {
    const evidence = resolveNutritionEvidence(
      docs(doc("p-1", {status: "superseded"}), doc("p-2", {status: "cancelled"})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 0);
    }
  });

  await test("NUTRITION exactly one active plan -> count 1", () => {
    const evidence = resolveNutritionEvidence(
      docs(doc("p-1", {status: "active"}), doc("p-2", {status: "superseded"})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 1);
    }
  });

  await test("NUTRITION multiple active plans are a conflict, reader reports it faithfully", () => {
    const evidence = resolveNutritionEvidence(
      docs(
        doc("p-1", {status: "active"}),
        doc("p-2", {status: "active"}),
        doc("p-3", {status: "active"}),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 3);
    }
  });

  // ── N1 — malformed plan is NOT masked by a valid active plan ──────────────
  await test("N1 1 valid active + 1 malformed/unknown lifecycle -> unreliable", () => {
    const evidence = resolveNutritionEvidence(
      docs(doc("p-1", {status: "active"}), doc("p-2", {status: 42})),
    );
    assert.strictEqual(evidence.kind, "unreliable");
    assert.strictEqual(
      evidence.kind === "unreliable" && evidence.reasonCode,
      "malformed",
    );
  });

  // ── N2 — valid inactive/cancelled/replaced are excluded, not malformed ─────
  await test("N2 1 valid active + 1 valid cancelled -> present, count=1", () => {
    const evidence = resolveNutritionEvidence(
      docs(
        doc("p-1", {status: "active"}),
        doc("p-2", {status: "cancelled"}),
        doc("p-3", {status: "replaced"}),
        doc("p-4", {status: "inactive"}),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 1);
    }
  });

  // ── N3 — >1 active = conflict, faithfully reported ─────────────────────────
  await test("N3 2 valid active -> present with count=2", () => {
    const evidence = resolveNutritionEvidence(
      docs(doc("p-1", {status: "active"}), doc("p-2", {status: "active"})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 2);
    }
  });

  // ── N4 — 0 active, all valid inactive = present(count=0), not absent ───────
  // "absent" from the reader means the collection has no readable plan documents at
  // all (genuinely empty or query failure). A collection of inactive/cancelled plans
  // is a present count of zero — the evaluator then produces the clinical alert.
  await test("N4 0 active, all documents valid inactive/cancelled -> present count=0", () => {
    const evidence = resolveNutritionEvidence(
      docs(
        doc("p-1", {status: "inactive"}),
        doc("p-2", {status: "cancelled"}),
        doc("p-3", {status: "replaced"}),
      ),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 0);
    }
  });

  await test("NUTRITION soft-deleted active plan does not count", () => {
    const evidence = resolveNutritionEvidence(
      docs(doc("p-1", {status: "active", deleted_at: ts(daysAgo(1))})),
    );
    assert.strictEqual(evidence.kind, "present");
    if (evidence.kind === "present") {
      assert.strictEqual(evidence.value.activePlanCount, 0);
    }
  });

  await test("NUTRITION malformed status is not silently promoted or dropped", () => {
    const evidence = resolveNutritionEvidence(docs(doc("p-1", {status: 42})));
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("NUTRITION query failure is unreliable, never zero-active", () => {
    const evidence = resolveNutritionEvidence(failed());
    assert.strictEqual(evidence.kind, "unreliable");
  });

  // ══ OPERATIONAL RESTRICTIONS ═════════════════════════════════════════════
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

  await test("RESTRICTIONS empty collection is a successful empty list", () => {
    const evidence = resolveRestrictionsEvidence(EMPTY);
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.deepStrictEqual(evidence.active, []);
    }
  });

  await test("RESTRICTIONS active absolute is parsed", () => {
    const evidence = resolveRestrictionsEvidence(docs(restrictionDoc("r-1")));
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.strictEqual(evidence.active.length, 1);
      assert.strictEqual(evidence.active[0].level, "absolute");
      assert.strictEqual(evidence.active[0].id, "r-1");
    }
  });

  await test("RESTRICTIONS active partial requires activities_restricted", () => {
    const ok = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-1", {level: "partial", activities_restricted: ["busca"]})),
    );
    assert.strictEqual(ok.kind, "restrictions");

    const missing = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-1", {level: "partial", activities_restricted: []})),
    );
    assert.strictEqual(missing.kind, "unreliable");
  });

  await test("RESTRICTIONS active attention is parsed", () => {
    const evidence = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-1", {level: "attention"})),
    );
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.strictEqual(evidence.active[0].level, "attention");
    }
  });

  await test("RESTRICTIONS ended and cancelled are excluded", () => {
    const evidence = resolveRestrictionsEvidence(
      docs(
        restrictionDoc("r-ended", {status: "ended"}),
        restrictionDoc("r-cancelled", {status: "cancelled"}),
      ),
    );
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.deepStrictEqual(evidence.active, []);
    }
  });

  await test("RESTRICTIONS expected_end in the past stays active", () => {
    const evidence = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-1", {expected_end: ts(daysAgo(2))})),
    );
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.strictEqual(evidence.active.length, 1);
      assert.deepStrictEqual(evidence.active[0].expectedEnd, daysAgo(2));
    }
  });

  await test("RESTRICTIONS malformed restriction never becomes an empty list (E4)", () => {
    const cases: Array<[string, Record<string, unknown>]> = [
      ["missing status", {status: undefined}],
      ["unknown status", {status: "paused"}],
      ["unknown level", {level: "severe"}],
      ["missing description", {description: "   "}],
      ["missing since", {since: null}],
      ["bad activities", {activities_restricted: "busca"}],
      ["bad expected_end", {expected_end: 42}],
    ];
    for (const [name, overrides] of cases) {
      const evidence = resolveRestrictionsEvidence(
        docs(restrictionDoc("r-bad", overrides)),
      );
      assert.strictEqual(evidence.kind, "unreliable", `${name} must be unreliable`);
    }
  });

  await test("RESTRICTIONS a malformed sibling does not hide a valid restriction", () => {
    const evidence = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-ok"), restrictionDoc("r-bad", {level: "severe"})),
    );
    // Fail loudly rather than reporting only what parsed.
    assert.strictEqual(evidence.kind, "unreliable");
  });

  await test("RESTRICTIONS query failure is unreliable, never no-restrictions", () => {
    const evidence = resolveRestrictionsEvidence(failed());
    assert.strictEqual(evidence.kind, "unreliable");
    assert.notStrictEqual(evidence.kind, "restrictions");
  });

  await test("RESTRICTIONS since falls back to issued_at", () => {
    const evidence = resolveRestrictionsEvidence(
      docs(restrictionDoc("r-1", {since: undefined, issued_at: ts(daysAgo(7))})),
    );
    assert.strictEqual(evidence.kind, "restrictions");
    if (evidence.kind === "restrictions") {
      assert.deepStrictEqual(evidence.active[0].since, daysAgo(7));
    }
  });

  // ══ BONO end-to-end fixture ══════════════════════════════════════════════
  await test("BONO equivalent fixture -> operational with no alerts", () => {
    const weight = resolveWeightEvidence(
      docs(weightDoc("w-1", {weight_kg: 28.8, measured_at: ts(NOW)})),
    );
    const vaccination = resolveVaccinationEvidence(
      EMPTY,
      docs(
        eventDoc("e-vac", "vaccination", {
          subtype: "Antirrábica",
          date: ts(NOW),
          nextDueDate: ts(daysAhead(365)),
        }),
      ),
    );
    const consultation = resolveConsultationEvidence(
      docs(eventDoc("e-con", "consultation", {date: ts(NOW)})),
    );
    const nutrition = resolveNutritionEvidence(docs(doc("p-1", {status: "active"})));
    const restrictions = resolveRestrictionsEvidence(EMPTY);
    assert.strictEqual(restrictions.kind, "restrictions");

    const evaluation = evaluateReadiness({
      now: NOW,
      activeRestrictions: restrictions.kind === "restrictions" ? restrictions.active : [],
      latestWeightAt: weight,
      vaccination,
      latestConsultationAt: consultation,
      nutrition,
      // A symptom 5/5 exists on the device but is not an evidence input at all.
      latestExamAt: {kind: "absent"},
      config: resolveReadinessConfig({
        weightMaxAgeDays: () => 90,
        consultationMaxAgeDays: () => 180,
      }),
    });

    assert.strictEqual(evaluation.outcome, "decided");
    if (evaluation.outcome === "decided") {
      assert.strictEqual(evaluation.decision.readinessStatus, "operational");
      assert.deepStrictEqual(evaluation.decision.openAlerts, []);
      assert.deepStrictEqual(evaluation.decision.completeness, {
        hasRecentWeight: true,
        hasVaccinationCurrent: true,
        hasRecentConsultation: true,
        hasActiveNutrition: true,
      });
    }
  });

  if (failures > 0) {
    console.error(`\n${failures} test(s) failed`);
    process.exitCode = 1;
    return;
  }
  console.log("health_readiness_evidence_logic_test: all passed");
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
