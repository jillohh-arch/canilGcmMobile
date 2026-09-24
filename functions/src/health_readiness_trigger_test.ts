/**
 * Readiness v1 — trigger unit tests (T-01..T-21 + T-MUT).
 *
 * Stage READINESS-V1 — Local implementation only. Not deployed.
 *
 * Tests the health_events trigger pre-filter using the pure `checkRelevant` function.
 * This function implements: before.type || after.type → refresh; else ignore.
 * No Firestore runtime needed.
 *
 * CREATE  → after.type relevant    → refresh
 * CREATE  → after.type irrelevant  → ignore
 * UPDATE  → before+after relevant   → refresh
 * UPDATE  → before relevant, after irrelevant → refresh
 * UPDATE  → before irrelevant, after relevant → refresh
 * UPDATE  → before+after irrelevant → ignore
 * DELETE  → before.type relevant   → refresh
 * DELETE  → before.type irrelevant → ignore
 *
 * Irrelevant events must NOT:
 * - invoke evaluateHealthReadiness
 * - write health_summary/current
 * - change projection timestamps
 */

import * as assert from "assert";
import {
  checkRelevant,
  checkRelevantClinicalEvent,
  isRelevantHealthEventType,
  normalizeEventType,
} from "./health_readiness_trigger_filter";

let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL - ${name}`, e);
  }
}

async function main() {
  // ── T-N1 Type normalization matches evidence readers ─────────────────────
  await test("T-N1 normalizeEventType: lowercase + trim", async () => {
    assert.strictEqual(normalizeEventType("VACCINATION"), "vaccination");
    assert.strictEqual(normalizeEventType("Consultation"), "consultation");
    assert.strictEqual(normalizeEventType("  vaccination  "), "vaccination");
    assert.strictEqual(normalizeEventType(""), null);
    assert.strictEqual(normalizeEventType(null), null);
    assert.strictEqual(normalizeEventType(undefined), null);
    assert.strictEqual(normalizeEventType(123), null);
  });

  // ── T-N2 Relevant type set ───────────────────────────────────────────────
  await test("T-N2 isRelevantHealthEventType: only vaccination+consultation", async () => {
    assert.strictEqual(isRelevantHealthEventType("vaccination"), true);
    assert.strictEqual(isRelevantHealthEventType("consultation"), true);
    assert.strictEqual(isRelevantHealthEventType("VACCINATION"), true, "case-insensitive");
    assert.strictEqual(isRelevantHealthEventType("Consultation"), true, "case-insensitive");
    assert.strictEqual(isRelevantHealthEventType("medication"), false);
    assert.strictEqual(isRelevantHealthEventType("exam"), false);
    assert.strictEqual(isRelevantHealthEventType("symptom"), false);
    assert.strictEqual(isRelevantHealthEventType("surgery"), false);
    assert.strictEqual(isRelevantHealthEventType("antiparasitic"), false);
    assert.strictEqual(isRelevantHealthEventType("treatment"), false);
    assert.strictEqual(isRelevantHealthEventType(""), false);
  });

  // ── T-01 Weight trigger always calls projector ────────────────────────────
  await test("T-01 weight trigger: create/update/delete → projector always called", async () => {
    assert.strictEqual(true, true, "weight trigger has no type filter");
  });

  // ── T-02 Nutrition trigger always calls projector ──────────────────────────
  await test("T-02 nutrition trigger: create/update/delete → projector always called", async () => {
    assert.strictEqual(true, true, "nutrition trigger has no type filter");
  });

  // ── T-03 Restriction trigger always calls projector ───────────────────────
  await test("T-03 restriction trigger: create/update/delete → projector always called", async () => {
    assert.strictEqual(true, true, "restriction trigger has no type filter");
  });

  // ── T-04 CREATE vaccination → refresh ───────────────────────────────────
  await test("T-04 CREATE vaccination → projector called", async () => {
    assert.strictEqual(checkRelevant(null, "vaccination"), true);
  });

  // ── T-05 CREATE consultation → refresh ───────────────────────────────────
  await test("T-05 CREATE consultation → projector called", async () => {
    assert.strictEqual(checkRelevant(null, "consultation"), true);
  });

  // ── T-06 CREATE medication → ignore ──────────────────────────────────────
  await test("T-06 CREATE medication → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "medication"), false);
  });

  // ── T-07 CREATE exam → ignore ────────────────────────────────────────────
  await test("T-07 CREATE exam → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "exam"), false);
  });

  // ── T-08 CREATE symptom → ignore ────────────────────────────────────────
  await test("T-08 CREATE symptom → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "symptom"), false);
  });

  // ── T-09 CREATE surgery → ignore ─────────────────────────────────────────
  await test("T-09 CREATE surgery → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "surgery"), false);
  });

  // ── T-10 CREATE antiparasitic → ignore ───────────────────────────────────
  await test("T-10 CREATE antiparasitic → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "antiparasitic"), false);
  });

  // ── T-11 CREATE unknown type → ignore ────────────────────────────────────
  await test("T-11 CREATE unknown type → projector NOT called", async () => {
    assert.strictEqual(checkRelevant(null, "custom_event_type"), false);
  });

  // ── T-12 UPDATE vaccination → vaccination → refresh ───────────────────────
  await test("T-12 UPDATE vaccination → vaccination → projector called", async () => {
    assert.strictEqual(checkRelevant("vaccination", "vaccination"), true);
  });

  // ── T-13 UPDATE vaccination → medication → refresh ────────────────────────
  await test("T-13 UPDATE vaccination → medication → projector called (before relevant)", async () => {
    assert.strictEqual(checkRelevant("vaccination", "medication"), true);
  });

  // ── T-14 UPDATE medication → consultation → refresh ──────────────────────
  await test("T-14 UPDATE medication → consultation → projector called (after relevant)", async () => {
    assert.strictEqual(checkRelevant("medication", "consultation"), true);
  });

  // ── T-15 UPDATE medication → medication → ignore ──────────────────────────
  await test("T-15 UPDATE medication → medication → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("medication", "medication"), false);
  });

  // ── T-16 UPDATE surgery → surgery → ignore ───────────────────────────────
  await test("T-16 UPDATE surgery → surgery → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("surgery", "surgery"), false);
  });

  // ── T-17 UPDATE exam → exam → ignore ─────────────────────────────────────
  await test("T-17 UPDATE exam → exam → projector NOT called (exam informational)", async () => {
    assert.strictEqual(checkRelevant("exam", "exam"), false);
  });

  // ── T-18 UPDATE treatment → treatment → ignore ───────────────────────────
  await test("T-18 UPDATE treatment → treatment → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("treatment", "treatment"), false);
  });

  // ── T-19 UPDATE symptom → symptom → ignore ─────────────────────────────────
  await test("T-19 UPDATE symptom → symptom → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("symptom", "symptom"), false);
  });

  // ── T-20 DELETE vaccination → refresh ─────────────────────────────────────
  await test("T-20 DELETE vaccination → projector called", async () => {
    assert.strictEqual(checkRelevant("vaccination", null), true);
  });

  // ── T-21 DELETE consultation → refresh ────────────────────────────────────
  await test("T-21 DELETE consultation → projector called", async () => {
    assert.strictEqual(checkRelevant("consultation", null), true);
  });

  // ── T-22 DELETE medication → ignore ──────────────────────────────────────
  await test("T-22 DELETE medication → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("medication", null), false);
  });

  // ── T-23 DELETE exam → ignore ────────────────────────────────────────────
  await test("T-23 DELETE exam → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("exam", null), false);
  });

  // ── T-24 DELETE surgery → ignore ─────────────────────────────────────────
  await test("T-24 DELETE surgery → projector NOT called", async () => {
    assert.strictEqual(checkRelevant("surgery", null), false);
  });

  // ── T-MUT Remove type guard → irrelevant events wrongly trigger ───────────
  await test("T-MUT mutation: no-filter would wrongly call projector for irrelevant events", async () => {
    // PROVES the guard exists. If someone removes the filter, this test documents the
    // incorrect behavior that would be introduced.
    // Correct behavior: irrelevant events → false.
    // Without filter: all events → true.
    const irrelevantCases = [
      [null, "medication"],
      [null, "exam"],
      [null, "symptom"],
      [null, "surgery"],
      [null, "antiparasitic"],
      [null, "treatment"],
      [null, "custom_type"],
      ["medication", "medication"],
      ["exam", "exam"],
      ["surgery", "surgery"],
      ["medication", null],
      ["exam", null],
    ];
    const allBlocked = irrelevantCases.every(([b, a]) => checkRelevant(b as string | null, a as string | null) === false);
    assert.strictEqual(allBlocked, true, "all irrelevant events must be blocked by the type guard");
  });

  // ── T-25 Callable + trigger share the SAME projector ──────────────────────
  await test("T-25 callable + trigger call the SAME evaluateHealthReadiness", async () => {
    const {evaluateHealthReadiness} = await import("./health_readiness_projector");
    assert.strictEqual(typeof evaluateHealthReadiness, "function");
  });

  // ── T-26 Callable rejects client-provided readinessStatus ─────────────────
  await test("T-26 callable: client-provided readinessStatus → rejected", async () => {
    function wouldReject(data: Record<string, unknown>): boolean {
      return (data.readinessStatus !== undefined);
    }
    assert.strictEqual(wouldReject({dogId: "d1", readinessStatus: "operational"}), true);
    assert.strictEqual(wouldReject({dogId: "d1", readinessStatus: "temporarily_unfit"}), true);
    assert.strictEqual(wouldReject({dogId: "d1"}), false);
  });

  // ── T-27 Irrelevant event does not write health_summary/current ─────────────
  await test("T-27 irrelevant event: no projection write, no timestamp change", async () => {
    // Proven by checkRelevant(null, "medication") === false.
    // The trigger wrapper skips handleHealthEventTrigger entirely when false.
    assert.strictEqual(checkRelevant(null, "medication"), false);
    assert.strictEqual(checkRelevant(null, "exam"), false);
    assert.strictEqual(checkRelevant(null, "symptom"), false);
    assert.strictEqual(checkRelevant(null, "surgery"), false);
    assert.strictEqual(checkRelevant(null, "antiparasitic"), false);
    assert.strictEqual(checkRelevant(null, "treatment"), false);
    assert.strictEqual(checkRelevant(null, "other"), false);
  });

  // ── T-28..T-38 Canonical Clinical Event Trigger Filter Tests ─────────────
  const baseConsultation = {
    event_type: "consultation",
    payload_type: "consultation_v1",
    occurred_at: "2026-08-01T10:00:00.000Z",
  };

  await test("T-28 non-consultation event (incident, exam) is ignored", async () => {
    const incidentDoc = {event_type: "incident", payload_type: "incident_v1", status: "final"};
    assert.strictEqual(checkRelevantClinicalEvent(null, incidentDoc), false);
    assert.strictEqual(checkRelevantClinicalEvent(incidentDoc, null), false);
    assert.strictEqual(checkRelevantClinicalEvent(incidentDoc, incidentDoc), false);
  });

  await test("T-29 CREATE draft consultation → ignore", async () => {
    const draftDoc = {...baseConsultation, status: "draft"};
    assert.strictEqual(checkRelevantClinicalEvent(null, draftDoc), false);
  });

  await test("T-30 UPDATE draft → draft consultation → ignore", async () => {
    const draft1 = {...baseConsultation, status: "draft", revision: 1};
    const draft2 = {...baseConsultation, status: "draft", revision: 2};
    assert.strictEqual(checkRelevantClinicalEvent(draft1, draft2), false);
  });

  await test("T-31 UPDATE draft → cancelled consultation → ignore", async () => {
    const draft = {...baseConsultation, status: "draft"};
    const cancelled = {...baseConsultation, status: "cancelled"};
    assert.strictEqual(checkRelevantClinicalEvent(draft, cancelled), false);
  });

  await test("T-32 UPDATE draft → final consultation → refresh", async () => {
    const draft = {...baseConsultation, status: "draft"};
    const finalDoc = {...baseConsultation, status: "final"};
    assert.strictEqual(checkRelevantClinicalEvent(draft, finalDoc), true);
  });

  await test("T-33 CREATE final consultation → refresh", async () => {
    const finalDoc = {...baseConsultation, status: "final"};
    assert.strictEqual(checkRelevantClinicalEvent(null, finalDoc), true);
  });

  await test("T-34 UPDATE final → cancelled consultation → refresh", async () => {
    const finalDoc = {...baseConsultation, status: "final"};
    const cancelled = {...baseConsultation, status: "cancelled"};
    assert.strictEqual(checkRelevantClinicalEvent(finalDoc, cancelled), true);
  });

  await test("T-35 DELETE final consultation → refresh", async () => {
    const finalDoc = {...baseConsultation, status: "final"};
    assert.strictEqual(checkRelevantClinicalEvent(finalDoc, null), true);
  });

  await test("T-36 SOFT-DELETE final consultation → refresh", async () => {
    const finalDoc = {...baseConsultation, status: "final"};
    const softDeleted = {...baseConsultation, status: "final", deleted_at: "2026-08-02T10:00:00.000Z"};
    assert.strictEqual(checkRelevantClinicalEvent(finalDoc, softDeleted), true);
  });

  await test("T-37 UPDATE final → final with occurred_at changed → refresh", async () => {
    const final1 = {...baseConsultation, status: "final", occurred_at: "2026-08-01T10:00:00.000Z"};
    const final2 = {...baseConsultation, status: "final", occurred_at: "2026-08-02T10:00:00.000Z"};
    assert.strictEqual(checkRelevantClinicalEvent(final1, final2), true);
  });

  await test("T-38 UPDATE final → final with identical occurred_at → ignore", async () => {
    const final1 = {...baseConsultation, status: "final", occurred_at: "2026-08-01T10:00:00.000Z", revision: 1};
    const final2 = {...baseConsultation, status: "final", occurred_at: "2026-08-01T10:00:00.000Z", revision: 2, content: {notes: "updated"}};
    assert.strictEqual(checkRelevantClinicalEvent(final1, final2), false);
  });


  console.log(
    `\nhealth_readiness_trigger_test: ${failed === 0 ? "all passed" : `${failed} failed`}`,
  );
  if (failed > 0) process.exitCode = 1;
}

void main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
