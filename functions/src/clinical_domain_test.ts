/**
 * Clinical server-domain parity — exhaustive test matrix (CLIN-WRITER-1.W1).
 *
 * Proves the TypeScript module reproduces the Dart Clinical state machines
 * EXACTLY. The transition matrices below are transcribed independently from the
 * Dart source (health_v1_transitions.dart / health_v1_enums.dart /
 * health_v1_models.dart) so the test is a real cross-check, not a tautology
 * against the module's own tables.
 *
 * Harness idiom matches the existing functions tests: `node:assert`, a local
 * `test()` helper, single `main()`, non-zero exit on failure.
 */

import * as assert from "assert";
import {
  CLINICAL_CASE_OPENING_TYPES,
  CLINICAL_CASE_STATUSES,
  CLINICAL_EVENT_STATUSES,
  CLINICAL_EVENT_TYPES,
  ClinicalCaseStatus,
  ClinicalDomainError,
  ClinicalEventStatus,
  allowedCaseTransitions,
  assertCaseReopen,
  assertCaseReopenConsistency,
  assertCaseTransition,
  assertEventCancellationConsistency,
  assertEventTransition,
  caseReopenDestinations,
  canTransitionCase,
  canTransitionEvent,
  isCaseReopenDestination,
  isEventContentEditable,
  isEventContentImmutable,
  isTerminalCaseStatus,
  isTerminalEventStatus,
  parseClinicalCaseOpeningType,
  parseClinicalCaseStatus,
  parseClinicalEventStatus,
  parseClinicalEventType,
} from "./clinical_domain";

let failed = 0;
let passed = 0;

function test(name: string, body: () => void): void {
  try {
    body();
    passed++;
  } catch (error) {
    failed++;
    console.error(`✗ ${name}`);
    console.error(error);
  }
}

function expectDomainError(
  body: () => void,
  code: string,
  kind: "invalid_value" | "illegal_transition",
): void {
  try {
    body();
  } catch (error) {
    assert.ok(
      error instanceof ClinicalDomainError,
      `expected ClinicalDomainError, got ${error}`,
    );
    assert.strictEqual(error.code, code, "error code mismatch");
    assert.strictEqual(error.kind, kind, "error kind mismatch");
    return;
  }
  throw new assert.AssertionError({message: `expected throw with code ${code}`});
}

const ACTOR = {uid: "u1", name: "Vet", internalRole: "veterinario"};
const T = new Date("2026-08-24T12:00:00.000Z");

// ── Independent transcription of the Dart truth tables ───────────────────────

const DART_CASE_TRANSITIONS: Record<string, string[]> = {
  open: [
    "under_investigation",
    "under_treatment",
    "monitoring",
    "discharged",
    "cancelled",
  ],
  under_investigation: [
    "open",
    "under_treatment",
    "monitoring",
    "discharged",
    "cancelled",
  ],
  under_treatment: ["under_investigation", "monitoring", "discharged", "cancelled"],
  monitoring: ["under_investigation", "under_treatment", "discharged", "cancelled"],
  discharged: [],
  cancelled: [],
};

const DART_CASE_REOPEN_DESTINATIONS = [
  "open",
  "under_investigation",
  "under_treatment",
  "monitoring",
];

// Reopen ORIGIN authority, transcribed independently from the Dart guard in
// health_v1_transitions.dart (`current.status != ClinicalCaseStatus.discharged`
// throws invalid_case_reopen). `cancelled` is terminal and never reopens —
// only `discharged` does.
const DART_CASE_REOPEN_ORIGINS = ["discharged"];

const DART_EVENT_TRANSITIONS: Record<string, string[]> = {
  draft: ["final", "cancelled"],
  final: ["cancelled"],
  cancelled: [],
};

// ── Vocabulary parity ────────────────────────────────────────────────────────

function main(): void {
  test("case status vocabulary matches Dart wire values", () => {
    assert.deepStrictEqual([...CLINICAL_CASE_STATUSES], [
      "open",
      "under_investigation",
      "under_treatment",
      "monitoring",
      "discharged",
      "cancelled",
    ]);
  });

  test("event status vocabulary uses wire value 'final' not 'finalised'", () => {
    assert.deepStrictEqual([...CLINICAL_EVENT_STATUSES], ["draft", "final", "cancelled"]);
  });

  test("opening type vocabulary matches Dart", () => {
    assert.deepStrictEqual([...CLINICAL_CASE_OPENING_TYPES], [
      "incident",
      "consultation",
      "preventive",
      "administrative",
    ]);
  });

  test("event type vocabulary is the 18 canonical wire values in order", () => {
    assert.strictEqual(CLINICAL_EVENT_TYPES.length, 18);
    assert.deepStrictEqual([...CLINICAL_EVENT_TYPES], [
      "consultation",
      "incident",
      "vaccination",
      "exam_request",
      "exam_collection",
      "exam_result",
      "exam_interpretation",
      "treatment_start",
      "treatment_note",
      "dose_note",
      "reevaluation",
      "discharge",
      "reopen",
      "restriction_issued",
      "restriction_ended",
      "surgical_note",
      "general_note",
      "observation",
    ]);
  });

  // ── Strict parsers ──────────────────────────────────────────────────────────

  test("parsers accept every canonical value round-trip", () => {
    for (const s of CLINICAL_CASE_STATUSES) assert.strictEqual(parseClinicalCaseStatus(s), s);
    for (const s of CLINICAL_EVENT_STATUSES) assert.strictEqual(parseClinicalEventStatus(s), s);
    for (const t of CLINICAL_EVENT_TYPES) assert.strictEqual(parseClinicalEventType(t), t);
    for (const o of CLINICAL_CASE_OPENING_TYPES) {
      assert.strictEqual(parseClinicalCaseOpeningType(o), o);
    }
  });

  test("parsers reject unknown / non-string as invalid_value (writer is strict)", () => {
    expectDomainError(() => parseClinicalCaseStatus("frobnicate"), "unknown_case_status", "invalid_value");
    expectDomainError(() => parseClinicalCaseStatus("finalised"), "unknown_case_status", "invalid_value");
    expectDomainError(() => parseClinicalEventStatus("finalised"), "unknown_event_status", "invalid_value");
    expectDomainError(() => parseClinicalEventType("weight"), "unknown_event_type", "invalid_value");
    expectDomainError(() => parseClinicalCaseOpeningType("other"), "unknown_case_opening_type", "invalid_value");
    expectDomainError(() => parseClinicalEventStatus(null), "unknown_event_status", "invalid_value");
    expectDomainError(() => parseClinicalEventStatus(3), "unknown_event_status", "invalid_value");
  });

  // ── Case transition matrix (exhaustive 6×6) ──────────────────────────────────

  test("case transition matrix matches Dart exhaustively (all 36 pairs)", () => {
    for (const from of CLINICAL_CASE_STATUSES) {
      const expected = DART_CASE_TRANSITIONS[from];
      // allowedCaseTransitions returns the same SET (order not contractual)
      assert.deepStrictEqual(
        [...allowedCaseTransitions(from)].sort(),
        [...expected].sort(),
        `allowed set mismatch for ${from}`,
      );
      for (const to of CLINICAL_CASE_STATUSES) {
        const shouldAllow = expected.includes(to);
        assert.strictEqual(
          canTransitionCase(from, to as ClinicalCaseStatus),
          shouldAllow,
          `canTransitionCase(${from}, ${to})`,
        );
        if (shouldAllow) {
          assert.doesNotThrow(() => assertCaseTransition(from, to as ClinicalCaseStatus));
        } else {
          expectDomainError(
            () => assertCaseTransition(from, to as ClinicalCaseStatus),
            "invalid_case_transition",
            "illegal_transition",
          );
        }
      }
    }
  });

  test("terminal case statuses are exactly discharged + cancelled", () => {
    for (const s of CLINICAL_CASE_STATUSES) {
      const terminal = s === "discharged" || s === "cancelled";
      assert.strictEqual(isTerminalCaseStatus(s), terminal, `terminal(${s})`);
    }
  });

  // ── Case reopen ───────────────────────────────────────────────────────────────

  test("reopen destinations match Dart (open/investigation/treatment/monitoring)", () => {
    assert.deepStrictEqual([...caseReopenDestinations()].sort(), [...DART_CASE_REOPEN_DESTINATIONS].sort());
    for (const s of CLINICAL_CASE_STATUSES) {
      assert.strictEqual(
        isCaseReopenDestination(s),
        DART_CASE_REOPEN_DESTINATIONS.includes(s),
        `isCaseReopenDestination(${s})`,
      );
    }
  });

  test("reopen only from discharged into a permitted destination", () => {
    for (const dest of DART_CASE_REOPEN_DESTINATIONS as ClinicalCaseStatus[]) {
      const intent = assertCaseReopen("discharged", dest, "  recidiva  ");
      assert.strictEqual(intent.destination, dest);
      assert.strictEqual(intent.reason, "recidiva", "reason must be trimmed");
    }
    // non-discharged origin
    expectDomainError(
      () => assertCaseReopen("open", "under_treatment", "x"),
      "invalid_case_reopen",
      "illegal_transition",
    );
    // discharged but terminal destination
    expectDomainError(
      () => assertCaseReopen("discharged", "cancelled", "x"),
      "invalid_case_reopen",
      "illegal_transition",
    );
    expectDomainError(
      () => assertCaseReopen("discharged", "discharged", "x"),
      "invalid_case_reopen",
      "illegal_transition",
    );
  });

  test("cancelled never reopens into ANY destination (exhaustive origin denial)", () => {
    // Locks the reopen ORIGIN set, not just one representative edge: every
    // non-discharged origin — `cancelled` above all — must be rejected for
    // every one of the four permitted destinations, with a valid non-blank
    // reason so the failure can only come from the origin guard.
    for (const origin of CLINICAL_CASE_STATUSES) {
      if (DART_CASE_REOPEN_ORIGINS.includes(origin)) {
        continue;
      }
      for (const dest of DART_CASE_REOPEN_DESTINATIONS as ClinicalCaseStatus[]) {
        expectDomainError(
          () => assertCaseReopen(origin, dest, "recidiva confirmada"),
          "invalid_case_reopen",
          "illegal_transition",
        );
      }
    }
  });

  test("reopen origin/destination check precedes reason check (Dart order)", () => {
    // Blank reason AND bad origin → must surface the reopen error, not the reason error.
    expectDomainError(
      () => assertCaseReopen("open", "open", "   "),
      "invalid_case_reopen",
      "illegal_transition",
    );
    // Valid origin/destination but blank reason → reason error.
    expectDomainError(
      () => assertCaseReopen("discharged", "open", "   "),
      "missing_reopen_reason",
      "invalid_value",
    );
  });

  // ── Event transition matrix (exhaustive 3×3) ──────────────────────────────────

  test("event transition matrix matches Dart exhaustively (all 9 pairs)", () => {
    for (const from of CLINICAL_EVENT_STATUSES) {
      const expected = DART_EVENT_TRANSITIONS[from];
      for (const to of CLINICAL_EVENT_STATUSES) {
        const shouldAllow = expected.includes(to);
        assert.strictEqual(
          canTransitionEvent(from, to as ClinicalEventStatus),
          shouldAllow,
          `canTransitionEvent(${from}, ${to})`,
        );
      }
    }
  });

  test("terminal event status is exactly cancelled", () => {
    for (const s of CLINICAL_EVENT_STATUSES) {
      assert.strictEqual(isTerminalEventStatus(s), s === "cancelled", `terminal(${s})`);
    }
  });

  test("draft→final is legal and requires NO cancellation metadata", () => {
    const r = assertEventTransition("draft", "final");
    assert.strictEqual(r.cancellation, null);
  });

  test("final→final and cancelled→* are illegal transitions", () => {
    expectDomainError(() => assertEventTransition("final", "final"), "invalid_event_transition", "illegal_transition");
    expectDomainError(() => assertEventTransition("draft", "draft"), "invalid_event_transition", "illegal_transition");
    for (const to of CLINICAL_EVENT_STATUSES) {
      expectDomainError(
        () => assertEventTransition("cancelled", to as ClinicalEventStatus),
        "invalid_event_transition",
        "illegal_transition",
      );
    }
  });

  // ── Cancellation metadata rules on the transition path ───────────────────────

  test("cancel from draft/final requires reason, then instant+actor, in order", () => {
    for (const from of ["draft", "final"] as ClinicalEventStatus[]) {
      // missing reason
      expectDomainError(
        () => assertEventTransition(from, "cancelled", {}),
        "missing_cancel_reason",
        "invalid_value",
      );
      // blank reason still missing
      expectDomainError(
        () => assertEventTransition(from, "cancelled", {cancelReason: "  "}),
        "missing_cancel_reason",
        "invalid_value",
      );
      // reason present but no instant/actor
      expectDomainError(
        () => assertEventTransition(from, "cancelled", {cancelReason: "erro"}),
        "missing_cancellation_metadata",
        "invalid_value",
      );
      expectDomainError(
        () => assertEventTransition(from, "cancelled", {cancelReason: "erro", cancelledAt: T}),
        "missing_cancellation_metadata",
        "invalid_value",
      );
      // full metadata → success, reason trimmed
      const r = assertEventTransition(from, "cancelled", {
        cancelReason: "  duplicado  ",
        cancelledAt: T,
        cancelledBy: ACTOR,
      });
      assert.ok(r.cancellation);
      assert.strictEqual(r.cancellation!.cancelReason, "duplicado");
      assert.strictEqual(r.cancellation!.cancelledAt, T);
      assert.deepStrictEqual(r.cancellation!.cancelledBy, ACTOR);
    }
  });

  test("non-cancel transition forbids ANY cancellation metadata", () => {
    expectDomainError(
      () => assertEventTransition("draft", "final", {cancelReason: "x"}),
      "unexpected_cancellation_metadata",
      "invalid_value",
    );
    expectDomainError(
      () => assertEventTransition("draft", "final", {cancelledAt: T}),
      "unexpected_cancellation_metadata",
      "invalid_value",
    );
    expectDomainError(
      () => assertEventTransition("draft", "final", {cancelledBy: ACTOR}),
      "unexpected_cancellation_metadata",
      "invalid_value",
    );
  });

  // ── At-rest cancellation consistency (constructor invariant) ─────────────────

  test("at-rest: draft/final with no cancellation metadata is consistent", () => {
    assert.doesNotThrow(() => assertEventCancellationConsistency("draft", {}));
    assert.doesNotThrow(() => assertEventCancellationConsistency("final", {}));
  });

  test("at-rest: partial cancellation metadata is incomplete", () => {
    expectDomainError(
      () => assertEventCancellationConsistency("cancelled", {cancelReason: "x", cancelledAt: T}),
      "missing_cancellation_metadata",
      "invalid_value",
    );
  });

  test("at-rest: cancelled status requires full metadata", () => {
    expectDomainError(
      () => assertEventCancellationConsistency("cancelled", {}),
      "missing_cancellation_metadata",
      "invalid_value",
    );
    assert.doesNotThrow(() =>
      assertEventCancellationConsistency("cancelled", {
        cancelReason: "x",
        cancelledAt: T,
        cancelledBy: ACTOR,
      }),
    );
  });

  test("at-rest: non-cancelled status with any metadata is unexpected", () => {
    expectDomainError(
      () => assertEventCancellationConsistency("final", {cancelReason: "x", cancelledAt: T, cancelledBy: ACTOR}),
      "unexpected_cancellation_metadata",
      "invalid_value",
    );
  });

  test("at-rest: cancelled with blank reason fails as missing_cancel_reason", () => {
    expectDomainError(
      () => assertEventCancellationConsistency("cancelled", {cancelReason: "   ", cancelledAt: T, cancelledBy: ACTOR}),
      "missing_cancel_reason",
      "invalid_value",
    );
  });

  // ── Finalization immutability predicate ──────────────────────────────────────

  test("only draft events are content-editable; final and cancelled are immutable", () => {
    assert.strictEqual(isEventContentEditable("draft"), true);
    assert.strictEqual(isEventContentImmutable("draft"), false);
    assert.strictEqual(isEventContentImmutable("final"), true);
    assert.strictEqual(isEventContentImmutable("cancelled"), true);
    assert.strictEqual(isEventContentEditable("final"), false);
    assert.strictEqual(isEventContentEditable("cancelled"), false);
  });

  // ── ClinicalCase reopen HISTORY at rest (CLIN-WRITER-1.W6.P0.D1) ────────────
  //
  // Transcribed independently from the corrected Dart `ClinicalCase` constructor
  // invariants. The load-bearing property: the tuple's validity does NOT depend
  // on the case's current status, so a reopened case can still be discharged or
  // cancelled afterwards without its history becoming unrepresentable.

  const REOPEN_TUPLE = {
    reopenedAt: T,
    reopenedBy: ACTOR,
    previousStatus: "discharged" as ClinicalCaseStatus,
    reopenReason: "Alta prematura",
    reopenedCount: 1,
  };

  test("never reopened: absent tuple with count 0 is consistent", () => {
    assert.strictEqual(assertCaseReopenConsistency(), null);
    assert.strictEqual(assertCaseReopenConsistency({}), null);
    assert.strictEqual(assertCaseReopenConsistency({reopenedCount: 0}), null);
    // Explicit nulls are the same fact as omission.
    assert.strictEqual(
      assertCaseReopenConsistency({
        reopenedAt: null,
        reopenedBy: null,
        previousStatus: null,
        reopenReason: null,
        reopenedCount: null,
      }),
      null,
    );
  });

  test("reopen history is valid under EVERY current case status", () => {
    // The whole point of D1: no status participates in the at-rest check.
    for (const status of CLINICAL_CASE_STATUSES) {
      const history = assertCaseReopenConsistency(REOPEN_TUPLE);
      assert.ok(history, `history must validate while case is ${status}`);
      assert.strictEqual(history.reopenedCount, 1);
      assert.strictEqual(history.previousStatus, "discharged");
      assert.strictEqual(history.reopenReason, "Alta prematura");
      assert.strictEqual(history.reopenedAt, T);
      assert.deepStrictEqual(history.reopenedBy, ACTOR);
    }
  });

  test("post-reopen re-discharge and cancellation histories are representable", () => {
    // discharge #1 → reopen #1 → discharge #2 : count survives the re-closure.
    const rediscarged = assertCaseReopenConsistency(REOPEN_TUPLE);
    assert.strictEqual(rediscarged?.reopenedCount, 1);
    // …and a later cancellation likewise preserves it.
    const cancelled = assertCaseReopenConsistency(REOPEN_TUPLE);
    assert.strictEqual(cancelled?.reopenedCount, 1);
    // Second reopen: cumulative count, never reset.
    const second = assertCaseReopenConsistency({
      ...REOPEN_TUPLE,
      reopenedCount: 2,
    });
    assert.strictEqual(second?.reopenedCount, 2);
    const many = assertCaseReopenConsistency({...REOPEN_TUPLE, reopenedCount: 7});
    assert.strictEqual(many?.reopenedCount, 7);
  });

  test("reopen history: reason is trimmed like the Dart aggregate", () => {
    const history = assertCaseReopenConsistency({
      ...REOPEN_TUPLE,
      reopenReason: "  Alta prematura  ",
    });
    assert.strictEqual(history?.reopenReason, "Alta prematura");
  });

  test("reopen history: negative or non-integer count fails closed", () => {
    // The code is asserted, not merely "some rejection": without this guard the
    // tuple invariants would still reject a negative count, but as
    // `inconsistent_reopen_metadata` / `inconsistent_reopened_count`. The count
    // guard must be the one that answers, in every tuple configuration.
    for (const reopenedCount of [-1, -7]) {
      expectDomainError(
        () => assertCaseReopenConsistency({...REOPEN_TUPLE, reopenedCount}),
        "invalid_reopened_count",
        "invalid_value",
      );
      expectDomainError(
        () => assertCaseReopenConsistency({reopenedCount}),
        "invalid_reopened_count",
        "invalid_value",
      );
      expectDomainError(
        () => assertCaseReopenConsistency({reopenedAt: T, reopenedCount}),
        "invalid_reopened_count",
        "invalid_value",
      );
    }
    for (const reopenedCount of [1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expectDomainError(
        () => assertCaseReopenConsistency({...REOPEN_TUPLE, reopenedCount}),
        "invalid_reopened_count",
        "invalid_value",
      );
    }
  });

  test("reopen history: count 0 with a tuple is inconsistent", () => {
    expectDomainError(
      () => assertCaseReopenConsistency({...REOPEN_TUPLE, reopenedCount: 0}),
      "inconsistent_reopen_metadata",
      "invalid_value",
    );
  });

  test("reopen history: count > 0 without any tuple is inconsistent", () => {
    expectDomainError(
      () => assertCaseReopenConsistency({reopenedCount: 1}),
      "inconsistent_reopened_count",
      "invalid_value",
    );
    expectDomainError(
      () => assertCaseReopenConsistency({reopenedCount: 4}),
      "inconsistent_reopened_count",
      "invalid_value",
    );
  });

  test("reopen history: every partial tuple fails closed", () => {
    const fields = [
      "reopenedAt",
      "reopenedBy",
      "previousStatus",
      "reopenReason",
    ] as const;
    // Each field alone.
    for (const field of fields) {
      expectDomainError(
        () => assertCaseReopenConsistency({[field]: REOPEN_TUPLE[field]}),
        "incomplete_reopen_metadata",
        "invalid_value",
      );
    }
    // Each field missing from an otherwise complete tuple.
    for (const field of fields) {
      const partial: Record<string, unknown> = {...REOPEN_TUPLE};
      delete partial[field];
      expectDomainError(
        () => assertCaseReopenConsistency(partial),
        "incomplete_reopen_metadata",
        "invalid_value",
      );
    }
  });

  test("reopen history: previous_status must be discharged", () => {
    for (const previousStatus of CLINICAL_CASE_STATUSES) {
      if (previousStatus === "discharged") continue;
      expectDomainError(
        () => assertCaseReopenConsistency({...REOPEN_TUPLE, previousStatus}),
        "inconsistent_reopen_metadata",
        "invalid_value",
      );
    }
  });

  test("reopen history: blank reason fails closed", () => {
    for (const reopenReason of ["", "   ", "\t\n"]) {
      expectDomainError(
        () => assertCaseReopenConsistency({...REOPEN_TUPLE, reopenReason}),
        "missing_reopen_reason",
        "invalid_value",
      );
    }
  });

  test("at-rest history consistency is NOT permission to reopen", () => {
    // THE separation D1 exists to prove. A cancelled case may legitimately carry
    // reopen history…
    assert.ok(assertCaseReopenConsistency(REOPEN_TUPLE));
    // …while the reopen ACTION remains denied from cancelled,
    expectDomainError(
      () => assertCaseReopen("cancelled", "open", "Erro de alta"),
      "invalid_case_reopen",
      "illegal_transition",
    );
    // denied from every active status (source must be discharged),
    for (const from of CLINICAL_CASE_STATUSES) {
      if (from === "discharged") continue;
      expectDomainError(
        () => assertCaseReopen(from, "open", "Erro de alta"),
        "invalid_case_reopen",
        "illegal_transition",
      );
    }
    // denied into terminal destinations,
    for (const destination of ["discharged", "cancelled"] as const) {
      expectDomainError(
        () => assertCaseReopen("discharged", destination, "Erro de alta"),
        "invalid_case_reopen",
        "illegal_transition",
      );
    }
    // and allowed from discharged into each active destination.
    for (const destination of caseReopenDestinations()) {
      assert.deepStrictEqual(
        assertCaseReopen("discharged", destination, " Erro de alta "),
        {destination, reason: "Erro de alta"},
      );
    }
  });

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed, ${passed} passed`);
    process.exitCode = 1;
    return;
  }
  console.log(`clinical_domain_test: all ${passed} tests passed`);
}

main();
