# ADR-008 — WeightAssessment Lifecycle

| Field | Value |
|---|---|
| Status | **Accepted — Target Architecture** |
| Date | 2026-08-06 |
| Decision source | WEIGHT-00A + human-approved WEIGHT-00B |
| Implementation | **NOT YET DEPLOYED** |
| Canonical specification | `../HEALTH_WEIGHT_CANONICAL_SPEC.md` |

## Context

K9 Ops currently has a physically homologated, simple, backend-mediated weight
create with operationId, receipt, idempotency and audit. It has no Quick/Official
distinction or post-create lifecycle. Earlier Health v1 documents modelled weight
as append-only with optional BCS 1–9 and per-record ideal range. Parallel legacy
writers can still bypass the new callable.

## Problem

The target must support fast and structured capture, retrospective chronology,
completion, correction, invalidation, attachments, BCS 1–5, versioned range/goal,
offline commands and deterministic projections without losing existing records,
changing entity identity or weakening clinical and audit invariants.

## Forces

- Fast Mobile UX and later offline operation.
- Backend-only authorization and idempotent retries.
- Immutable audit with practical current-state reads.
- Correct chronology after retrospective create, correction or invalidation.
- Backward compatibility, including the two known Apolo records.
- No automatic clinical event, nutrition mutation, restriction or unfitness.
- Additive migration and no hard delete.

## Decision

1. `WeightAssessment` is a routine aggregate, not a `ClinicalEvent` by default.
2. Quick and Official share the same `weight_records` aggregate.
3. Completing Quick as Official preserves entityId and `origin_record_type=quick`.
   Unchanged weight requires `health.record_routine`; changing `weight_kg` in the
   same atomic completion also requires `health.correct_routine`, correction
   reason, one revision, one receipt and one reprojection.
4. Current state lives at the root; immutable snapshots live in `revisions`.
   Original `recorded_by` is immutable; each later operation records its own
   operation actor.
5. Invalidation is logical and never hard-deletes the assessment.
6. Current weight is the valid record ordered by `measured_at DESC`, then
   `recorded_at DESC`, then entityId DESC.
7. Reference range and goal live in one versioned configuration aggregate with
   independent lifecycles.
8. Images are `HealthDocument` references identified by `storage_path`.
9. All canonical mutations are backend-only commands with receipts.
10. Offline uses a local command queue and never direct canonical writes.
11. Existing records without target fields are read as `legacy_simple`.
12. New BCS is 1–5; legacy BCS 1–9 is not converted automatically.

This is an accepted target architecture. Only simple create is currently
deployed; the remaining decisions MUST NOT be represented as active runtime.

## Alternatives considered

### Immutable root plus amendments only

Strong immutability, but every reader would need to compose operational numeric
state and projections across amendments. Rejected for the main aggregate.

### Full event sourcing

Maximum history, but excessive operational and migration complexity for the
current platform. Rejected for this lifecycle.

### New replacement document for every correction

Easy append-only behavior, but violates the approved stable entityId and makes
links, attachments and projection identity fragile. Rejected.

### Mutable root plus inline audit only

Simple reads, but audit is vulnerable to silent overwrite and array growth.
Rejected.

### Chosen: current state plus immutable revisions

Provides stable identity and simple readers while preserving complete before/
after history and optimistic concurrency.

## Consequences

Positive consequences include stable links, deterministic projections, auditable
corrections and compatibility defaults. Negative consequences include more
backend commands, transactional recomputation, revision conflicts and expanded
Rules/Emulator coverage.

## Compatibility

Missing target fields are interpreted in the read model as
`record_type=legacy_simple`, `status=valid`, `revision=1`. No factual Official,
Quick, source, location, condition, quality or equipment value is inferred.
Existing IDs, values, dates, available authorship, receipts and history remain.

## Security and privacy

Capabilities and dog access are enforced server-side. Clients cannot write the
canonical aggregate, revisions or projections. Receipts and audits carry minimal
structured actor identity and MUST NOT store e-mail. Existing RA persistence must
be reviewed before implementation. Attachment removal is logical with a permanent
tombstone and 90-day physical retention.

Completion, correction, invalidation and attachment commands MUST preserve the
create author in `recorded_by`; their revision actor identifies the later caller
without reattributing original creation.

## Migration

Migration is additive: bridge first, optional audited lazy migration second and
backfill only after approved inventory/dry-run. Legacy BCS 1–9 is preserved but
not converted. `weight_history` receives no new target writes. Parallel writers
must be retired before expanded rollout.

## Rollout

Rollout follows WEIGHT-01 through WEIGHT-11 in the canonical specification.
Initial Quick/Official rollout may remain online-only. Each phase requires local
tests, Emulator/Rules/Storage proof where relevant, physical Pixel validation,
read-only reconciliation and explicit production authorization.

## Rollback

Rollback disables commands/UI/projection activation while preserving every
created fact, receipt, revision and attachment tombstone. It MUST NOT hard-delete
records or recreate legacy writes.

## Relationship to existing ADRs

- **ADR-002:** clinical-event immutability remains unchanged. Weight revisions
  are a separate routine-aggregate mechanism and do not turn weight into a
  ClinicalEvent.
- **ADR-004:** weight is a canonical source for reconstructable timeline and
  summary projections; chronology uses `measured_at`.
- **ADR-005:** 7/14-day routine status is distinct from configurable 90-day
  operational attention and from canonical restrictions.
- **ADR-006:** `weight_records` remains canonical; legacy writers are retired
  additively and legacy records use the compatibility bridge.
