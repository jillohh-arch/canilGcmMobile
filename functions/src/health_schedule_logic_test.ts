/**
 * Testes unitários da lógica pura da Agenda (4E Gate 2 — idempotência).
 * npm run build && node lib/health_schedule_logic_test.js
 */
import * as assert from "assert";
import {
  decideCancel,
  decideComplete,
  decideCreateManual,
  decideUpdateOpen,
  fingerprintCancel,
  fingerprintCreateIntent,
  fingerprintUpdatePatch,
  initialRevision,
  matchOperationReceipt,
  nextRevision,
  parseUpdatePatch,
  readRevision,
  normalizeOperationId,
} from "./health_schedule_logic";

function test(name: string, fn: () => void): void {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (e) {
    console.error(`FAIL - ${name}`);
    throw e;
  }
}

test("revision ausente = 0; next monotônico; create inicia em 1", () => {
  assert.strictEqual(readRevision({}), 0);
  assert.strictEqual(nextRevision(0), 1);
  assert.strictEqual(initialRevision(), 1);
});

test("complete: open muta; completed noop; cancelled invalid", () => {
  assert.strictEqual(decideComplete("open").kind, "mutate");
  assert.strictEqual(decideComplete("completed").kind, "noop");
  const bad = decideComplete("cancelled");
  assert.strictEqual(bad.kind, "error");
});

test("cancel: receipt replay; fingerprint diverge; missing cancelled", () => {
  assert.strictEqual(
    decideCancel({lifecycle: "open", receiptMatch: "missing"}).kind,
    "mutate",
  );
  assert.strictEqual(
    decideCancel({lifecycle: "cancelled", receiptMatch: "replay"}).kind,
    "noop",
  );
  const idc = decideCancel({
    lifecycle: "open",
    receiptMatch: "idempotency-conflict",
  });
  assert.strictEqual(idc.kind, "error");
  if (idc.kind === "error") assert.strictEqual(idc.code, "idempotency-conflict");
  const ac = decideCancel({lifecycle: "cancelled", receiptMatch: "missing"});
  assert.strictEqual(ac.kind, "error");
  if (ac.kind === "error") assert.strictEqual(ac.code, "already-cancelled");
});

test("update: receipt replay tem prioridade sobre revision stale", () => {
  const r = decideUpdateOpen({
    lifecycle: "open",
    sourceType: "manual",
    currentRevision: 5,
    expectedRevision: 1,
    receiptMatch: "replay",
  });
  assert.strictEqual(r.kind, "noop");
});

test("update: revision stale conflict (sem receipt)", () => {
  const stale = decideUpdateOpen({
    lifecycle: "open",
    sourceType: "manual",
    currentRevision: 2,
    expectedRevision: 1,
    receiptMatch: "missing",
  });
  assert.strictEqual(stale.kind, "error");
  if (stale.kind === "error") assert.strictEqual(stale.code, "conflict");
});

test("update: mesma op fingerprint diverge = idempotency-conflict", () => {
  const r = decideUpdateOpen({
    lifecycle: "open",
    sourceType: "manual",
    currentRevision: 2,
    expectedRevision: 1,
    receiptMatch: "idempotency-conflict",
  });
  assert.strictEqual(r.kind, "error");
  if (r.kind === "error") assert.strictEqual(r.code, "idempotency-conflict");
});

test("update: automatic denied", () => {
  const r = decideUpdateOpen({
    lifecycle: "open",
    sourceType: "treatment_protocol",
    currentRevision: 1,
    expectedRevision: 1,
    receiptMatch: "missing",
  });
  assert.strictEqual(r.kind, "error");
  if (r.kind === "error") assert.strictEqual(r.code, "permission-denied");
});

test("create: same key same fingerprint = noop", () => {
  const fp = fingerprintCreateIntent({
    dogId: "d",
    scheduleType: "bath",
    title: "t",
    scheduledForIso: "2026-01-01T00:00:00.000Z",
    dueUntilIso: null,
    timezone: "America/Sao_Paulo",
    notes: null,
  });
  const r = decideCreateManual({
    docExists: true,
    storedFingerprint: fp,
    requestFingerprint: fp,
  });
  assert.strictEqual(r.kind, "noop");
});

test("create: same key different fingerprint = idempotency-conflict", () => {
  const r = decideCreateManual({
    docExists: true,
    storedFingerprint: "fp-a",
    requestFingerprint: "fp-b",
  });
  assert.strictEqual(r.kind, "error");
  if (r.kind === "error") assert.strictEqual(r.code, "idempotency-conflict");
});

test("fingerprints update/cancel determinísticos", () => {
  const a = fingerprintUpdatePatch({title: "X", notes: "n"});
  const b = fingerprintUpdatePatch({title: "X", notes: "n"});
  assert.strictEqual(a, b);
  assert.notStrictEqual(
    fingerprintCancel("a"),
    fingerprintCancel("b"),
  );
});

test("matchOperationReceipt: missing / replay / divergências", () => {
  assert.strictEqual(
    matchOperationReceipt({
      receiptExists: false,
      actorUid: "a",
      operationType: "update_open",
      fingerprint: "fp",
    }),
    "missing",
  );
  assert.strictEqual(
    matchOperationReceipt({
      receiptExists: true,
      storedActorUid: "a",
      storedOperationType: "update_open",
      storedFingerprint: "fp",
      actorUid: "a",
      operationType: "update_open",
      fingerprint: "fp",
    }),
    "replay",
  );
  // actor diverge
  assert.strictEqual(
    matchOperationReceipt({
      receiptExists: true,
      storedActorUid: "a",
      storedOperationType: "update_open",
      storedFingerprint: "fp",
      actorUid: "b",
      operationType: "update_open",
      fingerprint: "fp",
    }),
    "idempotency-conflict",
  );
  // operation_type diverge
  assert.strictEqual(
    matchOperationReceipt({
      receiptExists: true,
      storedActorUid: "a",
      storedOperationType: "update_open",
      storedFingerprint: "fp",
      actorUid: "a",
      operationType: "cancel",
      fingerprint: "fp",
    }),
    "idempotency-conflict",
  );
  // fingerprint diverge
  assert.strictEqual(
    matchOperationReceipt({
      receiptExists: true,
      storedActorUid: "a",
      storedOperationType: "update_open",
      storedFingerprint: "fp-a",
      actorUid: "a",
      operationType: "update_open",
      fingerprint: "fp-b",
    }),
    "idempotency-conflict",
  );
});

test("parseUpdatePatch rejeita injection source_type", () => {
  assert.throws(() => {
    parseUpdatePatch({title: "x", source_type: "manual"});
  });
});

test("operationId obrigatório quando required", () => {
  assert.throws(() => normalizeOperationId("", true));
  assert.strictEqual(normalizeOperationId("abc", true), "abc");
});

test("operationId path-safety: aceita tokens seguros", () => {
  assert.strictEqual(
    normalizeOperationId("upd-A_01.v2", true),
    "upd-A_01.v2",
  );
  assert.strictEqual(
    normalizeOperationId("  create-key-1  ", true),
    "create-key-1",
  );
});

test("operationId path-safety: rejeita inválidos", () => {
  const invalid = [
    "../escape",
    "a/b",
    "a\\b",
    ".",
    "..",
    "has space",
    "op$id",
    "op:id",
    "",
    "   ",
    "x".repeat(129),
  ];
  for (const id of invalid) {
    assert.throws(
      () => normalizeOperationId(id, true),
      (e: Error & {appCode?: string}) => e.appCode === "validation",
    );
  }
});

console.log("\nhealth_schedule_logic_test: all passed");
