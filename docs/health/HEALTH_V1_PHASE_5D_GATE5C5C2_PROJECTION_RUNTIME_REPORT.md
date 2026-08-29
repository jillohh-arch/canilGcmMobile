# Health v1 — Phase 5D — Gate 5C.5C.2

## Projection Runtime & Trigger Handlers Foundation Report

Status: **READY FOR HUMAN AUDIT**

Production deployment: **NOT AUTHORIZED**

## 1. Preflight

The implementation started only after the required Git preflight matched the
approved baseline:

- branch: `feature/health-v1-foundation`
- HEAD: `be2d124fda848c8918b140f0f9fc9ed388ee057e`
- subject: `docs(health): define timeline productization design`
- divergence from `origin/feature/health-v1-foundation`: `2 ahead / 0 behind`
- pre-existing untracked file: `functions/audit_prod.mjs`
- no other unexpected file existed before implementation

`functions/audit_prod.mjs` remained unmodified, unstaged, and preserved.

## 2. Files changed

Created:

- `functions/src/health_timeline_runtime.ts`
- `functions/src/health_timeline_trigger_handlers.ts`
- `functions/src/health_timeline_runtime_test.ts`
- `functions/src/health_timeline_trigger_emulator_test.ts`
- `docs/health/HEALTH_V1_PHASE_5D_GATE5C5C2_PROJECTION_RUNTIME_REPORT.md`

No pre-existing production file was modified.

## 3. Runtime architecture

The local foundation follows the approved dependency direction:

```text
future thin trigger wrapper (not implemented)
  -> injectable created-event handler
    -> transactional Firestore runtime
      -> approved pure projection functions
```

The runtime reuses `deriveTimelineId`, `projectMealLog`,
`projectSupplementLog`, and `compareProjection`. It does not import
`index.ts`, `TEST_CONFIG`, or any engine from the prototype Emulator harness.

## 4. Closed source types

The public runtime source discriminant is the closed union:

```text
meal | supplement
```

The collection is derived from that discriminant through an internal
allowlist. It is never accepted from source payload data.

Canonical persisted source collections remain:

- `dogs/{dogId}/meal_logs`
- `dogs/{dogId}/supplement_logs`

The O3 deterministic ID formula and golden vector were not changed.

## 5. Path validation

Document IDs are rejected when empty, slash-containing, reserved, or beyond
the Firestore document-ID bound.

Handlers require exact agreement among params, snapshot ID, and snapshot path:

- meal: `dogs/{dogId}/meal_logs/{mealId}`
- supplement: `dogs/{dogId}/supplement_logs/{supplementLogId}`

The destination is constructed only inside the runtime:

`dogs/{dogId}/health_timeline/{timelineId}`

Cross-dog and wrong-collection inputs become deterministic anomalies before
projection. No externally supplied destination path is accepted.

## 6. Timestamp codec

The codec has an explicit boundary:

- source Firestore `Timestamp` -> strict canonical ISO representation used by
  the approved pure functions;
- strict canonical ISO representation -> Firestore `Timestamp` at persistence.

The source parser also accepts strict canonical ISO strings because the
currently approved Nutrition write adapter persists source factual timestamps
in that form. This is compatibility at the source boundary, not permissive
coercion.

Every persisted canonical timeline value below is a Firestore `Timestamp`:

- `occurred_at`
- `recorded_at`
- `projected_at`

Invalid temporal values are deterministic invalid payloads.

## 7. Schema allowlist

The serializer creates a new object from an exact field allowlist:

- `timeline_type`
- `source_collection`
- `source_id`
- `occurred_at`
- `recorded_at`
- `projected_at`
- `title`
- optional `subtitle`
- `dog_id`
- `recorded_by`
- `status`
- `schema_version`

Undefined optional values are omitted. Arbitrary source fields, dependencies,
runtime internals, counters, and `TEST_CONFIG` cannot escape into the stored
document.

## 8. Transaction semantics

The destination read and every timeline write occur inside one Firestore
transaction:

- missing -> `create`;
- equivalent -> no write;
- divergent or structurally malformed existing projection -> `set` repair.

`clock.now()` supplies `projected_at` for create and repair. Because
`projected_at` is excluded from projection equivalence, a retried concurrent
transaction re-reads the committed entry and converges to no-op.

No read-then-write projection path exists outside the transaction.

## 9. Handler design

Two normal, injectable, non-registered handlers were implemented:

- `makeMealLogCreatedHandler`
- `makeSupplementLogCreatedHandler`

The meal handler fixes source type to `meal`; the supplement handler fixes it
to `supplement`. Neither source type nor destination path is payload-driven.

No `onDocumentCreated` wrapper exists in this Gate.

## 10. Error taxonomy

The implemented behavior is:

```text
transient infrastructure/runtime failure
  -> structured error log
  -> throw

deterministic invalid payload/path
  -> structured warning
  -> anomaly sink
  -> zero source/timeline write
  -> successful anomaly result

anomaly sink failure
  -> structured error log
  -> throw
```

Closed enums are validated at the handler boundary, including meal
`acceptance`/`period` and supplement `unit`.

## 11. Anomaly handling

The anomaly contract contains only:

- closed source type;
- sanitized dog/source identifiers;
- reason code;
- timestamp;
- sanitized context.

The full source payload is never copied into an anomaly. The sink remains
injected and in-memory in this Gate. No productive discrepancy path and no
`_health_projection_state` write were introduced.

## 12. Unit test results

Command:

`npx tsx src/health_timeline_runtime_test.ts`

Result:

- passed: `20/20`
- failed: `0`
- exit code: `0`

Coverage includes closed sources, safe paths, nested destination, Timestamp
round-trip and rejection, exact serializer allowlist, fixed handler types,
cross-dog/wrong collection/invalid ID, malformed timestamps and enums,
transient propagation, and anomaly-sink failure propagation.

## 13. Emulator test results

Environment:

- `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`
- `GCLOUD_PROJECT=canil-gcm`

Command:

`npx tsx src/health_timeline_trigger_emulator_test.ts`

Result:

- passed: `13/13`
- failed: `0`
- exit code: `0`

The suite covered MealLog create, SupplementLog create, duplicate delivery,
concurrent delivery, equivalent no-op, divergent repair, malformed payload,
sink failure, transient projector failure, source immutability, cross-dog
rejection, persisted schema allowlist, and zero legacy writes.

Fixtures used a unique dog ID and were removed by the test teardown.

## 14. Concurrency results

Two simultaneous invocations for one source returned exactly:

- one `created`;
- one `noop`.

There was one final timeline document. Its Firestore `createTime` and
`updateTime` were identical, which proves the no-op invocation performed no
second write and did not advance `projected_at`.

The separate equivalent-entry case also preserved both `projected_at` and
Firestore `updateTime`. Repair kept the deterministic ID and advanced
`projected_at`.

## 15. Source immutability evidence

The Emulator test captured each source document before and after projection.
Both the complete document data and Firestore `updateTime` remained identical.

The runtime owns no write/delete path to `meal_logs` or `supplement_logs`.

## 16. Zero legacy writes evidence

The Emulator suite asserted zero documents in:

- `feeding_events`
- `feedings`
- `nutrition_supplements`
- `nutritional_prescriptions`
- `nutrition_prescriptions`

The runtime and handlers do not reference those collection names.

## 17. Prototype regression

Final regression after all implementation changes:

- TypeScript build: **PASS**, exit `0`
- prototype unit: **38/38 PASS**, failed `0`, exit `0`
- prototype Firestore Emulator E2E: **15/15 PASS**, failed `0`, exit `0`
- official `npm run test:health-nutrition`: **PASS**, failed `0`, exit `0`

The prototype E2E fixed test dog still contained historical top-level
HealthTimeline residue from older Emulator runs, visible in diagnostic counts
inside Test 10. The required assertions and all 15 cases passed. The new Gate
suite avoids this shared-fixture condition through a unique dog ID and teardown.

## 18. Production isolation

`git diff -- functions/src/index.ts firestore.rules firestore.indexes.json`
was empty after implementation.

Confirmed:

- no export in `functions/src/index.ts`;
- no registered `onDocumentCreated`;
- no registered `onSchedule`;
- no Rules change;
- no indexes change;
- no deploy;
- no backfill;
- no Mobile change.

A read-only `firebase functions:list --project canil-gcm --json` check returned
65 remote Functions and `0` IDs matching HealthTimeline naming. No productive
Function was created by this Gate.

Physical indexes remain candidates to be proved by real queries in Gate
5C.5C.4.

## 19. Findings

Classification:

- BLOCKER: `0`
- MAJOR: `0`
- MINOR: `0`
- OBSERVATION: `4`

Observations:

1. Strict ISO support at the source boundary is required for compatibility
   with currently persisted Nutrition factual documents; timeline persistence
   is always Firestore `Timestamp`.
2. The anomaly sink intentionally remains injected/test-only; its productive
   persistence contract is not frozen in this Gate.
3. Index definitions intentionally remain unchanged and unproven until real
   query execution in Gate 5C.5C.4.
4. The old prototype E2E fixed dog has historical Emulator residue in
   diagnostic collection counts; the suite still passed 15/15, while the new
   suite is isolated by unique dog ID.

The 14-point adversarial audit found no incorrect runtime behavior and no
production exposure.

## 20. Gate verdict

```text
GATE 5C.5C.2 — READY FOR HUMAN AUDIT

BLOCKER: 0
MAJOR: 0
MINOR: 0
OBSERVATION: 4

BUILD: PASS
PROTOTYPE UNIT: 38/38 PASS
PROTOTYPE E2E: 15/15 PASS
NEW UNIT: 20/20 PASS
NEW EMULATOR: 13/13 PASS
FAILED: 0

NO COMMIT
NO PUSH
NO DEPLOY
NO PRODUCTION EXPOSURE
```

## 21. Exact recommended scope for 5C.5C.3

Gate 5C.5C.3 should be limited to the **Reconciliation Runtime Foundation**:

- reuse the transactional projection primitive implemented here;
- implement bounded, incremental forward freshness traversal ordered by
  `(recorded_at, documentId)`;
- preserve an independent bounded overlap replay cursor/window;
- implement bounded cursor-paginated historical sweep;
- implement bounded cursor-paginated orphan detection with alert-only behavior;
- introduce injected reconciliation state/anomaly dependencies suitable for
  Emulator testing;
- validate restart, cursor monotonicity, page bounds, overlap idempotency,
  source immutability, and orphan no-delete behavior.

Still excluded from 5C.5C.3:

- `index.ts` exports;
- active triggers;
- scheduler registration;
- Rules;
- physical index definitions;
- deploy;
- backfill;
- productive SLA claims.
