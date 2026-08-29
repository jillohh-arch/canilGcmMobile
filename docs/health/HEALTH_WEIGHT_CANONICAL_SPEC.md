# Health v1 — Canonical Weight Specification

| Field | Value |
|---|---|
| Status | **APPROVED TARGET SPECIFICATION** |
| Date | 2026-08-06 |
| Origin | WEIGHT-00A reconciliation + WEIGHT-00B human approval |
| Current implementation | **PARTIAL** |
| Owner | Health v1 / K9 Ops |
| Related documents | HEALTH_V1_DOMAIN_MODEL, HEALTH_V1_FIRESTORE_SCHEMA, HEALTH_V1_READINESS_POLICY, HEALTH_V1_PERMISSION_MATRIX, HEALTH_V1_MIGRATION_PLAN, HEALTH_V1_TEST_STRATEGY |
| Related ADR | ADR-008 — WeightAssessment Lifecycle |

> This document defines an approved target. Except where a section is explicitly
> labelled **CURRENTLY DEPLOYED**, it MUST NOT be read as evidence that the
> capability, schema, command, projection, UI, Rule or migration is deployed.

## 1. Purpose

Weight is a Health operational aggregate. A `WeightAssessment` MUST remain an
independent routine fact and MUST NOT become a `ClinicalEvent` automatically.
It MAY carry optional links to clinical records.

## 2. Scope

This specification covers Quick Weight, Official Weight, completion, correction,
invalidation, BCS, images, reference range, goal, alerts, routine periodicity,
offline commands, projections, history and optional clinical, nutritional and
preventive integrations.

## 3. Non-goals

- Weight MUST NOT change a nutrition plan, meal or supplement automatically.
- Weight, variation, BCS, approximate reading or delay MUST NOT create an
  operational restriction or unfitness automatically.
- PDF evidence MUST NOT be required for a weight assessment.
- Weight data and attachments MUST NOT be hard-deleted silently.
- Canonical mutations MUST NOT be written directly by Mobile or Web clients.
- Legacy BCS 1–9 MUST NOT be converted automatically to BCS 1–5.
- Web MUST NOT be enabled as the standard operational weight recording channel.

## 4. Deployment-state vocabulary

### 4.1 CURRENTLY DEPLOYED

- Simple create through `healthWeightCreateRecord` in `southamerica-east1`.
- Server-side `health.record_routine` authorization and dog access.
- `weight_records`, operationId, fingerprint, durable receipt, transaction and
  audit log.
- Mobile and Web currently read `dogs/{dogId}/weight_records` directly. Current
  summary, graph, medical-record and history views are composed by those readers.
- The K9 document currently keeps temporary denormalizations in `weight`,
  `_last_weight_kg` and `_last_weight_at`.
- The target Weight projection in `health_summary/current` is not deployed, and
  a materialized target `health_timeline` is not the deployed source of weight.
  Direct readers and K9 denormalizations are temporary compatibility, not the
  final target model.
- Physically homologated Mobile flow.
- Known valid Apolo records: 32.0 kg on 2026-06-17 and 33.3 kg on 2026-08-06.
- No Quick/Official distinction, completion, correction, invalidation, images or
  persistent offline queue.

### 4.2 APPROVED TARGET

All normative lifecycle, command, schema, projection, attachment, offline and
permission rules in sections 5–33 are approved but **NOT YET DEPLOYED**.

### 4.3 LEGACY / TO BE RETIRED

- `adminCreateK9WeightRecord`.
- New writes to `weight_history`.
- K9-registration `appendK9WeightRecord` outside the canonical command contract.
- Client-side writes to `weight_records`.
- Web best-effort writes to K9 weight denormalizations.
- Web `ready=false` derived solely from being outside the reference range.

These writers are blocking debt. Expanded weight features MUST NOT roll out while
they can bypass the canonical backend.

## 5. Terminology

| Term | Definition |
|---|---|
| `WeightAssessment` | Canonical operational weight aggregate in `weight_records` |
| Quick Weight | Minimal current-time assessment (`quick`) |
| Official Weight | Structured present or retrospective assessment (`official`) |
| `legacy_simple` | Read-model type for a pre-target record whose original type is unknown |
| `valid` | Assessment eligible for current weight, graph and periodicity |
| `invalidated` | Preserved assessment excluded from current calculations |
| revision | Monotonic aggregate version and immutable change snapshot |
| attachment | `HealthDocument` image referenced by ID |
| current weight | Valid assessment selected by the chronology rule |
| `measured_at` | Instant the measurement occurred |
| `recorded_at` | Server instant at which the assessment was recorded |
| recorder | Authenticated internal user represented by `recorded_by` |
| information source | How the recorder obtained the value |
| BCS | Body condition score on the canonical 1–5 scale |
| reference range | Versioned individual minimum and maximum |
| weight goal | Versioned individual target and optional deadline |
| routine status | `current`, `recommended` or `overdue` by 7/14-day policy |
| operational attention | Readiness display state, distinct from restriction |
| receipt | Durable idempotency result for one operationId |
| projection | Rebuildable read model derived from canonical facts |

UX surfaces MUST use the Portuguese labels `Pesagem Rápida`, `Pesagem Oficial`,
`Faixa de referência`, `Meta de peso`, `Escore corporal`, `Leitura aproximada`
and `Registro invalidado`. Persisted contracts and command payloads MUST use the
English names `quick`, `official`, `legacy_simple`, `valid`, `invalidated`,
`measured_at`, `recorded_at`, `information_source`, `reading_quality`,
`equipment_state`, `reference_range`, `weight_goal`, `bcs` and `revision`.

## 6. Authorization

### 6.1 CURRENTLY DEPLOYED

`health.record_routine` permits simple create. Authorization and dog access are
validated server-side.

### 6.2 APPROVED TARGET — NOT YET DEPLOYED

| Capability | Purpose | Target profile |
|---|---|---|
| `health.record_routine` | Quick/Official create, completion and add attachment | `operador_k9` |
| `health.correct_routine` | Correct assessment and audited attachment removal | `operador_k9` |
| `health.invalidate_routine` | Invalidate assessment | `operador_k9` |
| `health.manage_weight_reference` | Manage reference range and weight goal | `operador_k9` |

Every command MUST validate the appropriate capability, an existing and active
K9, dog access, caller identity and request shape server-side. The three new
capabilities are approved targets but are not currently active.

An authorized K9 Operator MAY execute the permitted operation for any existing
and active K9 to which that Operator has access. The Operator MUST NOT need to be
the handler officially linked to the K9, MUST NOT need to have the K9 active in
the current shift and MUST NOT need to be the original `WeightAssessment`
author. The operation-specific capability and dog access remain mandatory; this
rule does not grant unrestricted access to other K9s.

## 7. Quick Weight

Quick Weight MUST require `dogId`, weight, a current measurement instant and
server-side authorship. It MAY include up to three images.

It MUST NOT include BCS, retrospective date, location, condition, equipment,
reading quality or a detailed clinical form. After success, Mobile MUST offer
“Concluir” and “Complementar como Pesagem Oficial”.

## 8. Official Weight

Official Weight MUST require weight, `measured_at`, `information_source`,
`location` and `measurement_condition`. It MAY include equipment, reading
quality, context, notes, free scale identifier, BCS, up to five images and
clinical links. Past and present measurements MUST be accepted; future
measurements MUST be rejected.

## 9. Canonical catalogues

| Field | Values | Rule |
|---|---|---|
| `information_source` | `measured_by_recorder`, `reported_by_other_operator`, `external_document_or_service` | Required for Official |
| `location` | `kennel`, `veterinary_clinic`, `pharmacy`, `other` | `other` MUST include description |
| `measurement_condition` | `fasting`, `after_feeding`, `after_activity_or_training`, `no_specific_condition`, `other` | `other` MUST include description |
| `equipment_state` | `none`, `collar`, `harness_or_operational_equipment`, `not_informed` | Optional |
| `reading_quality` | `stable`, `approximate`, `not_recorded` | Optional |

An `approximate` reading remains valid and SHOULD recommend a new Official
Weight. It MUST NOT create a restriction.

## 10. Weight value

- Public unit and persistence field MUST be kilograms in `weight_kg`.
- Value MUST have exactly one decimal place and be between 1.0 and 100.0 kg.
- Internal validation SHOULD use integer tenths of a kilogram.
- Greater precision MUST be rejected, not silently rounded.
- Only the final confirmed value MUST be recorded.
- Multiple readings and automatic averaging MUST NOT be persisted.

## 11. Lifecycle

```text
CREATE QUICK
  quick / valid / revision 1

CREATE OFFICIAL
  official / valid / revision 1

COMPLETE QUICK AS OFFICIAL
  quick -> official
  origin_record_type remains quick
  entityId remains unchanged
  revision increments

CORRECT
  valid -> valid
  entityId remains unchanged
  revision increments

INVALIDATE
  valid -> invalidated
  entityId remains unchanged
  revision increments
```

Invalid transitions include: completing an Official record, completing or
correcting an invalidated record, invalidating an already invalidated record,
decrementing revision, changing `origin_record_type`, reusing an operationId with
a different fingerprint, or moving `invalidated` back to `valid` without a future
explicit restore contract.

A valid Quick MAY have its weight changed only atomically while it is completed
as Official with both `health.record_routine` and `health.correct_routine`, or by
invalidating it and creating another record. Generic Quick correction is not a
valid transition.

## 12. Completion

Any authorized operator MAY complete a valid Quick Weight. Completion MUST keep
the entityId, original author, origin type and existing images; MUST add the
Official fields and completion author/time; MAY increase total images from three
to five; and MUST create an immutable revision. A changed weight MUST be captured
as an explicit correction in the same operation, never as a silent overwrite.

When `weight_kg` remains exactly unchanged, `CompleteWeightAsOfficial` MUST
require `health.record_routine`, dog access, an active K9, the expected revision
and all required Official fields; it MUST NOT require `health.correct_routine`.

When `weight_kg` changes, the same atomic command MUST additionally require
`health.correct_routine` and a correction reason. It MUST preserve the previous
weight and immutable before/after, record the completion/correction actor,
increment exactly one revision, issue exactly one receipt, run exactly one
reprojection, preserve entityId and `origin_record_type=quick`, set
`record_type=official` and preserve the original `recorded_by`. The human action
MUST NOT be split into independent writes. Without `health.correct_routine`, the
caller MAY complete only with unchanged weight; an attempted weight change MUST
fail authorization with zero partial write.

## 13. Correction

Correction MUST require `health.correct_routine`, current revision and a reason:
`data_entry_error`, `new_scale_reading` or `other`. It MUST preserve immutable
before/after snapshots, actor, server time, revision, operationId and receipt,
then recompute affected projections. It MUST NOT silently overwrite data.

Standalone `CorrectWeight` applies only to an `official` record with
`status=valid`. It MUST NOT correct a Quick directly. A Quick weight can change
only under the atomic completion rule in section 12 or after logical invalidation
followed by a new create.

## 14. Invalidation

Invalidation MUST require `health.invalidate_routine` and a reason:
`wrong_dog`, `defective_scale`, `duplicate`, `irrecoverable_error` or `other`.
It MUST be logical, preserve the document, exclude it from current calculations,
main graph and periodicity, remain available through an explicit filter and
reproject to the previous valid measurement when necessary.

## 15. Multiple measurements on the same day

Multiple valid measurements on the same day MUST be allowed as separate
documents. The UI MUST warn and request confirmation. It MUST NOT merge or
deduplicate by date. Idempotency MUST distinguish a retry from a new legitimate
human operation.

## 16. Variation

```text
delta_kg = current_weight - previous_valid_weight
delta_percent = abs(delta_kg) / previous_valid_weight * 100
```

- Up to and including 5%: `normal`.
- Above 5% and up to and including 10%: `warning`.
- Above 10%: `highlighted_alert`.

Internal calculations MUST use persisted numeric values, not presentation-rounded
text. Rounding applies only to display. No previous valid weight means no delta.
Retrospective create, correction and invalidation MUST recompute chronological
neighbours.

## 17. Chronology and current weight

Current weight MUST be selected among valid records by:

1. `measured_at DESC`;
2. `recorded_at DESC`;
3. `entityId DESC`.

Quick and Official have equal precedence. A retrospective record MUST be placed
at its chronological position and MUST NOT replace a later valid measurement.

## 18. Reference range and goal

Target paths:

```text
dogs/{dogId}/weight_configuration/current
dogs/{dogId}/weight_configuration/current/revisions/{revisionId}
```

Reference range MUST have min, max, source, note, `effective_at`, revision and
author. Weight goal MUST have target, optional deadline, source, note, revision
and author. They share one configuration aggregate but have independent
lifecycles. They MUST NOT be duplicated in each weight record as authority.

## 19. BCS

The new canonical scale MUST be 1–5: 1 very low, 2 below ideal, 3 ideal, 4 above
ideal and 5 very high. BCS is recommended but optional and only available in an
Official Weight. When present it MUST include `bcs_source`:
`operator_assessment`, `veterinary_guidance` or
`reported_by_other_operator`.

BCS 2/4 creates attention; BCS 1/5 creates highlighted alert and veterinary
consultation recommendation. Improvement is 1→2/3 or 5→4/3. Attention 2/4 ends
only with a new Official BCS 3 unless explicit veterinary guidance is recorded.
Weight and BCS are independent indicators.

Legacy BCS 1–9 MUST remain labelled legacy, MUST NOT be converted automatically
and MUST NOT feed the canonical 1–5 graph without a later approved policy.

## 20. Images and attachments

Only images from camera or gallery MAY be attached: up to three for Quick and
five for Official. Captions are optional. Content hash MUST participate in local
and server-side dedupe; the same image MUST NOT be attached twice to one record.
Attachments MUST be `HealthDocument` IDs and `storage_path` MUST be their
identity. Inline URLs MUST NOT be identity.

For BCS, UI SHOULD recommend lateral and superior views; neither is mandatory.

Web MAY view images, allowed captions and metadata, history, details and audit.
Web MUST NOT add, remove or replace a Weight image or execute an operational
attachment mutation. Target attachment mutations remain Mobile-initiated through
an authorized backend command. Extraordinary future administrative tooling is
outside this approved target.

## 21. Image removal and retention

Removal MUST immediately hide the image from common views and record reason,
actor, server time and a permanent tombstone. The physical object MUST be retained
for 90 days and MAY then be purged by a controlled process. Silent deletion is
forbidden.

## 22. Offline target — NOT YET DEPLOYED

Quick and Official are approved to support offline operation in a later phase.
The initial expanded rollout MAY remain online-only.

The local queue MUST distinguish `draft`, `pending`, `submitting`, `confirmed`,
`failed_retryable`, `failed_permanent` and `conflict`. operationId, measured_at,
session and actor MUST be frozen once submitted. Confirmation exists only after a
receipt. User switching MUST NOT submit another session’s command. Attachments
MUST use an independent queue. Canonical Firestore writes remain forbidden.

Quick offline is an approved destination, but its clock-trust contract remains a
WEIGHT-08 design task and MUST NOT be described as deployed.

## 23. Periodicity and readiness

`weighing_routine_status` is `current` for 0–7 days, `recommended` for 8–14
days, and `overdue` above 14 days. It drives a routine alert, Mobile badge and Web
highlight but MUST NOT create a restriction.

The separate configurable 90-day incomplete-data threshold MAY feed
`operational_attention` temporarily. It MUST NOT create unfitness. Only an
explicit canonical `operational_restriction` can limit operation.

## 24. Alerts, notifications and schedule

Future baseline MUST distinguish persisted alert, summary field, UI badge, push,
schedule item, operational attention and restriction. Persisted alert, Mobile
badge and Web highlight are required; push is configurable; e-mail is optional.

Follow-up MAY be offered for 3, 7, 14 days or a custom date and MUST be created
only after human confirmation. It MUST NOT be created automatically.

## 25. Integrations

An Official Weight MAY link to clinical records but MUST NOT automatically create
a ClinicalEvent. Weight findings MAY offer a nutrition-plan review CTA but MUST
NOT mutate nutrition. No weight finding creates automatic unfitness.

## 26. Approved target projections — NOT YET DEPLOYED

`health_summary/current` SHOULD expose current weight, measurement time, record
ID/type, delta, reference-range result, routine status, current Official BCS and
BCS attention. `health_timeline` MUST keep one deterministic entry per entityId;
completion/correction updates it, invalidation marks it and attachment-only
changes do not add rows. Graphs MUST use `measured_at`, valid current revisions
and distinct Quick/Official presentation; BCS has a separate Official-only graph.

K9 `weight` and `_last_weight_*` fields are temporary compatibility projections,
not canonical authority. The canonical root remains `weight_records`.

## 27. Audit and immutable revisions

Target paths:

```text
dogs/{dogId}/weight_records/{entityId}
dogs/{dogId}/weight_records/{entityId}/revisions/{revisionId}
```

The root contains current aggregate state. Each revision MUST contain immutable
before/after snapshots, operation type, justification, actor, server timestamp,
revision number, operationId and receipt reference. E-mail MUST NOT be persisted.
RA persistence MUST be reviewed against the existing minimization policy before
implementation.

`recorded_by` MUST permanently identify the original create author and MUST NOT
be replaced by completion, correction, invalidation or attachment operations.
Later operations MUST identify their own actor through `completed_by`,
`corrected_by`, `invalidated_by` or the attachment/revision operation actor as
applicable. Every revision MUST preserve the original `recorded_by` in aggregate
state and use `operation_actor` for the current action; before/after MUST NOT
attribute original creation to a later actor. This applies to
`CompleteWeightAsOfficial`, `CorrectWeight`, `InvalidateWeight`,
`AddWeightAttachment` and `RemoveWeightAttachment`.

## 28. Compatibility bridge

Readers MUST interpret missing target fields as:

```text
record_type = legacy_simple
status = valid
revision = 1 // read model only
```

They MUST NOT infer Official, Quick, location, information source, condition,
quality or equipment. entityId, weight, measured_at, available authorship,
receipt and history MUST be preserved, including Apolo 32.0 kg and 33.3 kg.

## 29. Legacy writers — blocking debt

`adminCreateK9WeightRecord`, new `weight_history` writes,
`appendK9WeightRecord`, direct client writes, Web best-effort denormalization and
Web `ready=false` from range alone MUST be retired through controlled phases.
They MUST NOT be treated as acceptable target writers.

## 30. Command contracts

All requests use `{dogId, operationId, expectedRevision?, payloadVersion,
payload}`. All commands MUST use fingerprinted durable receipts, backend
authorization, atomic transactions, server time, minimal structured audit and
deterministic replay. Transient retry MUST reuse operationId; permanent errors
MUST NOT retry automatically; revision conflicts require reload and human action.

| Command | Capability | Validation and transactional effect | Projection/revision |
|---|---|---|---|
| `CreateQuickWeight` | `health.record_routine` | Quick fields, current time, 1–3 images; create valid rev1 | current/timeline/summary |
| `CreateOfficialWeight` | `health.record_routine` | Official required fields, non-future, up to 5 images | chronological reprojection, rev1 |
| `CompleteWeightAsOfficial` | `health.record_routine`; also `health.correct_routine` iff `weight_kg` changes | valid Quick + expectedRevision; Official fields; changed weight requires reason and atomic before/after; preserve entityId/origin/recorded_by | exactly one revision, receipt and reprojection |
| `CorrectWeight` | `health.correct_routine` | valid Official, expectedRevision, reason, before/after | revision+1, recompute neighbours |
| `InvalidateWeight` | `health.invalidate_routine` | valid record, expectedRevision, reason | invalidated revision, full recompute |
| `AddWeightAttachment` | `health.record_routine` | confirmed HealthDocument, hash, type limit | revision/audit; no new weight |
| `RemoveWeightAttachment` | `health.correct_routine` | active ref and reason | tombstone/revision/audit |
| `SetWeightReferenceRange` | `health.manage_weight_reference` | valid min/max/source/note/effectivity | config revision and range projection |
| `SetWeightGoal` | `health.manage_weight_reference` | target/source/note, optional deadline | config revision and visual projection |
| `CreateWeightFollowUp` | `health.create` | human-confirmed 3/7/14/custom | deduped schedule + audit |

Minimum domain errors are `validation_error`, `k9_not_found`, `k9_inactive`,
`dog_access_denied`, `future_measurement`, `revision_conflict`,
`idempotency_conflict`, `record_not_found`, `record_not_valid`,
`invalid_transition`, `attachment_limit_exceeded`, `attachment_duplicate`,
`reference_range_invalid`, `correction_capability_required` and
`contract_shape_invalid`.

## 31. Delivery phases — NOT STARTED

| Phase | Objective | Dependencies | Deploy/APK | Risk and exit gate |
|---|---|---|---|---|
| WEIGHT-01 | Domain, schema and read bridge | WEIGHT-00C/00D | none | Medium; contract/unit approval |
| WEIGHT-02 | Quick online | 01 | Functions + APK | High; Emulator, Rules, physical Pixel |
| WEIGHT-03 | Official online | 02 | Functions + APK | High; retrospective projection proof |
| WEIGHT-04 | Completion and correction | 03 | Functions + APK | Critical; revision/concurrency proof |
| WEIGHT-05 | Invalidation and reprojection | 04 | Functions + APK | Critical; full recomputation proof |
| WEIGHT-06 | Images and HealthDocument | 05 | Functions, Storage Rules, APK | High; partial upload/retention proof |
| WEIGHT-07 | Range, goal, alerts and BCS | 05 | Functions + Web + APK | High; no automatic restriction proof |
| WEIGHT-08 | Offline synchronization | 02–07 | APK | Critical; multi-device/clock/security soak |
| WEIGHT-09 | History, filters, graphs and Web | 03–08 | Web + APK | Medium; reader parity proof |
| WEIGHT-10 | Clinical, nutrition and schedule links | 07–09 | Functions + Web + APK | High; no implicit mutation proof |
| WEIGHT-11 | Migration and physical closure | all | controlled deploys/APK | Critical; dry-run and reconciliation |

## 32. Rollout gates

Every phase MUST have approved documentation, unit coverage, relevant widget and
integration coverage, Emulator proof, Rules/Storage tests when affected, migration
dry-run when data is affected, physical Pixel validation for Mobile, read-only
reconciliation and rollback that never hard-deletes canonical facts.

Coverage for the corrected integrity findings MUST prove: unchanged-weight
completion with only `health.record_routine`; changed-weight completion with both
capabilities; rejection without `health.correct_routine` and zero partial write;
one revision, receipt and reprojection for atomic completion/correction; immutable
`recorded_by` with separate operation actors; no generic CRUD update/delete;
zero Web attachment mutation; and authorization independent of linked handler or
active shift while still enforcing dog access and active K9.

## 33. Documentation precedence

For Weight, this specification and ADR-008 supersede conflicting weight-specific
statements in earlier Health v1 documents. General clinical immutability,
projection, readiness-authority and additive-migration principles in ADR-002,
ADR-004, ADR-005 and ADR-006 remain authoritative.
