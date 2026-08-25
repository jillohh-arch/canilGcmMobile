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

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed, ${passed} passed`);
    process.exitCode = 1;
    return;
  }
  console.log(`clinical_domain_test: all ${passed} tests passed`);
}

main();
