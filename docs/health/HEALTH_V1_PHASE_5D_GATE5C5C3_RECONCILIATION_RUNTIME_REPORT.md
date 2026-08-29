# Health v1 — Phase 5D — Gate 5C.5C.3

## Reconciliation Runtime Foundation Report

Status: **READY FOR HUMAN AUDIT**

Productive deployment: **NOT AUTHORIZED**

## 1. Preflight

The required preflight matched the approved checkpoint:

- branch: `feature/health-v1-foundation`
- HEAD: `501206c627ddca8a09c1ae2827f062f8d0ea73d2`
- subject: `feat(health): add timeline projection runtime foundation`
- divergence: `3 ahead / 0 behind`
- initial status: only `?? functions/audit_prod.mjs`

`functions/audit_prod.mjs` remained unmodified, unstaged, and outside the Gate.

## 2. Files changed

Modified:

- `functions/src/health_timeline_runtime.ts`

Created:

- `functions/src/health_timeline_reconciliation_state.ts`
- `functions/src/health_timeline_reconciliation.ts`
- `functions/src/health_timeline_reconciliation_test.ts`
- `functions/src/health_timeline_reconciliation_emulator_test.ts`
- `docs/health/HEALTH_V1_PHASE_5D_GATE5C5C3_RECONCILIATION_RUNTIME_REPORT.md`

No production entry point, Rules, or index file was changed.

## 3. Existing runtime reuse/refactor

The 5C.5C.2 runtime previously encapsulated `db.runTransaction()`. A minimal
refactor introduced:

```text
project(source)
  -> db.runTransaction(transaction =>
       projectInTransaction(transaction, source))
```

`projectInTransaction()` contains the single implementation of:

- deterministic destination derivation;
- destination read;
- `MISSING -> CREATE`;
- `EQUIVALENT -> NO-OP`;
- `DIVERGENT -> REPAIR`;
- canonical serialization and Timestamp persistence.

Trigger handlers continue to call `project()`. Reconciliation calls
`projectInTransaction()` inside the same transaction that advances its cursor.
There is no nested transaction and no duplicated projection engine.

The 5C.5C.2 unit and Emulator suites remained green after the refactor.

## 4. Physical `recorded_at` audit

Code audit:

- canonical Nutrition commands produce a logical `recorded_at`;
- `health_nutrition_firestore_adapter.ts` classifies `recorded_at` as a
  server-authoritative timestamp;
- `prepareWriteData()` replaces it with
  `FieldValue.serverTimestamp()`;
- Mobile invokes the callable Functions and has no direct write path to
  `meal_logs` or `supplement_logs`.

A minimal read-only production audit selected only `recorded_at` and emitted
aggregate type counts, with no document IDs or payloads:

```text
meal_logs:
  total = 7
  Timestamp = 7
  string = 0
  missing = 0
  other = 0

supplement_logs:
  total = 1
  Timestamp = 1
  string = 0
  missing = 0
  other = 0
```

Therefore there is no current physical Timestamp/string mixture and no blocker
for the single forward lane.

The parser's strict ISO compatibility remains defensive. If an ISO physical
`recorded_at` appears, the forward cursor preserves the exact string query
value, atomically creates an `unsupported-recorded-at-type` discrepancy, and
advances with `skipped_anomaly`. The discrepancy remains open until the
physical field becomes a Timestamp.

## 5. Reconciliation architecture

The local runtime contains five bounded passes:

1. forward freshness per source type;
2. safety overlap per source type;
3. historical integrity per source type;
4. global orphan integrity;
5. global known discrepancy reprocessing.

Every source pass is page-size bounded and processes items sequentially. A
transient item failure stops the page immediately.

No scheduler or productive wrapper invokes this runtime in the current Gate.

## 6. State schema

Backend-only root:

`_health_projection_state/health_timeline_v1`

Subcollections:

- `passes/{passKey}`
- `runs/{runId}`
- `discrepancies/{discrepancyId}`

Pass keys separate both source and responsibility:

- `meal_forward`
- `supplement_forward`
- `meal_overlap`
- `supplement_overlap`
- `meal_historical`
- `supplement_historical`
- `orphan_global`
- `known_discrepancies_global`

Run documents have a fenced `running -> completed|failed` lifecycle.

## 7. Lease/fencing contract

The root state stores:

- `lease_owner`;
- `lease_expires_at`;
- monotonic `lease_revision`;
- acquisition/release timestamps.

Acquisition is transactional. A valid lease denies another worker. An expired
lease permits takeover with an incremented fencing revision.

Every transaction that projects, repairs, records a discrepancy, advances or
wraps a cursor, starts/finishes a run, or changes an overlap window validates:

- exact owner;
- exact revision;
- unexpired lease.

A stale release requires the exact owner/revision and cannot release a newer
lease.

## 8. Forward pass

Forward executes separately for MealLog and SupplementLog using collection
group queries ordered by:

```text
recorded_at ASC
full document name ASC
```

It uses an injected page size and `startAfter` with both cursor components.
The source is re-read inside each item transaction.

For a valid item, projection/repair/no-op and cursor advancement share the same
transaction. Forward never uses collection counts as a consistency proof.

## 9. Cursor representation

Forward/overlap cursor:

- exact physical `recorded_at` query value;
- normalized ISO instant for overlap/observability;
- full document path used as the `__name__` tie-break.

Historical/orphan/known-discrepancy cursor:

- full document path only.

The persisted cursor round-trip was tested across a recreated runtime/state
adapter. Two dogs with the same local source ID and same `recorded_at` were
both processed exactly once.

## 10. Overlap pass

Overlap owns a separate cursor and a fixed window:

- window start/end are frozen when a cycle begins;
- pages continue that same window until it is exhausted;
- a full page is not treated as completion;
- completion clears the window and increments the cycle;
- a new cycle restarts from the beginning of the current safety window;
- the forward cursor is never written or rewound.

Backlog larger than the page size completed across multiple invocations.
A write inserted behind the current overlap page cursor was discovered by the
next overlap cycle, proving absence of permanent starvation.

## 11. Historical sweep

Historical traversal is ordered by full document name and has its own cursor
per source type.

The Emulator proved:

- page 1 -> page 2 -> confirmed end;
- cursor cleared and cycle incremented;
- next invocation restarted from the beginning;
- an exact multiple of page size required a following empty page before wrap.

No invocation performs an unbounded full scan.

## 12. Orphan safety

Before any source dereference, the orphan pass validates:

1. physical nested path `dogs/{dogId}/health_timeline/{timelineId}`;
2. `entry.dog_id` equals the parent dog;
3. exact same-dog source collection allowlist;
4. safe source ID without slash;
5. matching timeline/source type;
6. recalculated deterministic timeline ID equals the document ID.

Only then is a source ref rebuilt through the closed source-type path builder.
No code performs:

`db.doc(entry.source_collection + "/" + entry.source_id)`.

Cross-dog, unknown/malformed collection, slash ID, dog mismatch, type mismatch,
ID mismatch, and timeline outside the canonical path all produced durable
discrepancies, no crash, no delete, and no arbitrary source read.

If a queried timeline disappears before its transactional re-read, the pass
throws and does not advance its cursor.

## 13. Discrepancy model

Discrepancy IDs are deterministic SHA-256 identities with prefix `hd1_`, based
on:

- target kind;
- closed reason code;
- source type;
- dog ID;
- source ID;
- timeline document path.

Stored fields include:

- sanitized identity;
- closed reason;
- `open|resolved` status;
- `first_seen_at`;
- `last_seen_at`;
- `resolved_at`;
- attempt count;
- sanitized context.

Raw payloads are never copied. Repeated detection updates the same document.
Resolved discrepancies remain as durable history and are never deleted.

## 14. Known discrepancy pass

The pass queries only open discrepancies with an injected limit and independent
cursor.

It reconstructs source refs from the closed source type plus validated dog/source
IDs. A stored timeline path is dereferenced only after canonical path and ID
validation.

Tested lifecycles:

- malformed source corrected -> projection -> resolved;
- orphan source reappeared -> revalidation/projection -> resolved;
- problem unchanged -> remains open and attempts increase;
- unsupported physical timestamp -> remains open until physical Timestamp;
- transient failure -> transaction aborts and status/cursor do not advance.

Corrective Gate 5C.5C.3.1 explicitly proved eventual revisit with
`page_size = 1` and two still-open discrepancies:

```text
run 1 -> D1 processed -> cursor D1
run 2 -> D2 processed -> cursor D2
run 3 -> empty page confirms END -> cursor reset -> cycle + 1
runtime/state adapter recreated
run 4 -> D1 revisited -> attempts incremented again
```

Both useful pages were exactly full. They did not trigger an early wrap; the
following empty page was required to confirm the end. D1 kept the same
deterministic ID, `first_seen_at`, open status, and durable history. The
discrepancy collection remained at exactly two documents, proving no duplicate
creation and no starvation.

## 15. Partial failure behavior

Transient scenario `A / B / C`:

- A committed;
- B threw;
- C was not processed;
- cursor remained on A;
- retry processed B and C without loss.

Deterministic invalid scenario:

- A projected;
- B created/updated a durable discrepancy;
- B was explicitly counted as `skipped_anomaly`;
- cursor advanced over B in the same transaction;
- C projected.

Injected discrepancy-write failure aborted B's transaction. The discrepancy
was absent, the cursor remained on A, and C was not processed.

## 16. Trigger × reconciliation concurrency

The future-trigger handler and reconciliation processed the same source
concurrently through the shared transaction primitive.

Evidence:

- one final nested TimelineEntry;
- equivalent canonical state;
- no duplicate;
- Firestore `createTime == updateTime`.

This proves that the losing transaction re-evaluated the committed state and
performed no second write or `projected_at` advance.

## 17. Unit results

Command:

`npx tsx src/health_timeline_reconciliation_test.ts`

Result:

- passed: `26/26`
- failed: `0`
- exit code: `0`

Coverage includes state paths, pass separation, cursor serialization, full-name
tie-break, lease decisions, fencing, stale release, overlap independence,
historical cursor, deterministic discrepancy IDs, orphan allowlist, malformed
timeline cases, and arbitrary-path rejection.

## 18. Emulator results

Environment:

- `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`
- `GCLOUD_PROJECT=canil-gcm`

Result:

- passed: `25/25`
- failed: `0`
- exit code: `0`

The suite covers all 18 mandatory scenarios plus:

- overlap starvation prevention across cycles;
- still-open discrepancy history;
- orphan source reappearance;
- Meal/Supplement cursor separation;
- fenced durable run lifecycle;
- unexpected ISO physical cursor/discrepancy lifecycle;
- exact-page-multiple known-discrepancy wrap and post-restart revisit.

## 19. Regression results

Final regression matrix:

- TypeScript build: **PASS**
- 5C.5C.2 runtime unit: **20/20 PASS**
- 5C.5C.2 Emulator: **13/13 PASS**
- O3 prototype unit: **38/38 PASS**
- O3 prototype Emulator: **15/15 PASS**
- `npm run test:health-nutrition`: **PASS**
- failed: `0`

The old prototype fixed-dog harness still emits non-isolated diagnostic
collection counts during Test 10. Those counts are not used as quantitative
evidence for this Gate; the assertions remained 15/15 green. The new
reconciliation suite resets its Emulator namespace fixtures and tears them
down.

## 20. Source immutability

The Emulator captured complete source data and Firestore `updateTime` before
and after reconciliation. Both remained identical.

The reconciliation runtime has no source `set`, `update`, `create`, or
`delete` operation. Fixture mutations used to create/fix/remove test conditions
belong only to the Emulator test harness.

## 21. Zero legacy writes

The reconciliation implementation does not reference legacy collection names.
The Emulator asserted zero documents in:

- `feeding_events`
- `feedings`
- `nutrition_supplements`
- `nutritional_prescriptions`
- `nutrition_prescriptions`

No TimelineEntry is auto-deleted.

## 22. Production isolation

Confirmed:

- no `functions/src/index.ts` change;
- no `firestore.rules` change;
- no `firestore.indexes.json` change;
- no `onSchedule`;
- no `onDocumentCreated`;
- no export;
- no scheduler;
- no backfill;
- no deploy.

A read-only Functions listing returned:

- total remote Functions: `65`
- HealthTimeline/reconciliation matches: `0`

## 23. Index observations/candidates

No physical index was added.

Query shapes to prove in Gate 5C.5C.4:

1. collection-group `meal_logs`:
   `recorded_at ASC, __name__ ASC`;
2. collection-group `supplement_logs`:
   `recorded_at ASC, __name__ ASC`;
3. overlap range on `recorded_at` with `__name__` tie-break;
4. collection-group `health_timeline` ordered by `__name__`;
5. `discrepancies` filtered by `status == open`, ordered by `__name__`.

All executed successfully in the real Firestore Emulator. This is query
evidence, not a claim that production's physical composite-index requirements
are already frozen.

## 24. Findings

Classification:

- BLOCKER: `0`
- MAJOR: `0`
- MINOR: `0`
- OBSERVATION: `5`

Corrective findings closed:

- the former MAJOR about eventual revisit is closed by Emulator Test 25;
- the former MINOR about the next-Gate roadmap is closed by restoring Rules to
  the explicit 5C.5C.4 scope.

Observations:

1. The current production physical audit covered eight canonical factual
   documents, all Timestamp. Future unexpected ISO values are fail-visible
   through durable discrepancies rather than silently treated as the Timestamp
   lane.
2. Productive index requirements remain candidates until Gate 5C.5C.4 executes
   the exact queries against the intended deployment configuration.
3. The anomaly/discrepancy collection is backend-only and intentionally has no
   client Rules in this Gate.
4. Scheduler cadence, lease duration, page budgets, and pass orchestration
   remain productive configuration decisions for later exposure gates.
5. Prototype fixed-dog diagnostic counts retain old harness hygiene debt and
   are not used as quantitative evidence here.

The 18-question adversarial self-audit found no incorrect cursor, fencing,
dereference, mutation, legacy, or exposure behavior.

## 25. Gate verdict

```text
GATE 5C.5C.3 — READY FOR HUMAN AUDIT

BLOCKER: 0
MAJOR: 0
MINOR: 0
OBSERVATION: 5

BUILD: PASS
RECONCILIATION UNIT: 26/26 PASS
RECONCILIATION EMULATOR: 25/25 PASS
5C.5C.2 UNIT: 20/20 PASS
5C.5C.2 EMULATOR: 13/13 PASS
O3 UNIT: 38/38 PASS
O3 EMULATOR: 15/15 PASS
HEALTH/NUTRITION REGRESSION: PASS
FAILED: 0

NO COMMIT
NO PUSH
NO DEPLOY
NO PRODUCTION EXPOSURE
```

## 26. Exact recommended scope for 5C.5C.4

Gate 5C.5C.4 should be **Rules + Query/Index Proof**:

- add dog-scoped read Rules for nested `health_timeline`;
- deny every client write to `health_timeline`;
- deny every client read/write to `_health_projection_state`;
- prove Rules behavior in the Firestore Emulator;
- execute every exact forward, overlap, historical, orphan, and open-discrepancy
  query shape against a controlled Firebase project/configuration;
- capture missing-index errors or successful execution evidence;
- determine the minimum physical index set;
- add only indexes proven necessary;
- test index-compatible global tie-break and restart cursors;
- document index build/readiness requirements and query-cost observations;
- preserve all reconciliation behavior and rerun the complete regression matrix.

Still excluded unless separately authorized:

- productive scheduler export;
- productive trigger export;
- deploy;
- backfill;
- client timeline reader implementation;
- Mobile changes;
- production SLA claims.
