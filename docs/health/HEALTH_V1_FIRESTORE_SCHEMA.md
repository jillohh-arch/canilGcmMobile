# Health v1.0 — Schema Firestore Proposto

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001 a ADR-006, HEALTH_V1_DOMAIN_MODEL.md |
| Escopo | Estrutura de coleções, campos, tipos, índices e política de acesso |
| Fora de escopo | Implementação de Rules, deploy, Functions |

---

## 1. Organização geral

Todas as coleções de saúde são subcoleções de `dogs/{dogId}`. Exames são subcoleção
de `clinical_cases/{caseId}` (agregado próprio). Registros legados têm coleção
dedicada com write bloqueado para clientes e permissão administrativa auditada via
Admin SDK.

O Health v1.0 define **13 agregados canônicos** (12 originais + `VaccinationRecord`
como agregado preventivo independente) e **2 projeções** (`health_timeline`,
`health_summary`).

```
dogs/{dogId}/
├── clinical_cases/{caseId}
│   ├── events/{eventId}
│   │   └── amendments/{amendId}
│   └── exams/{examId}                   [agregado ExamProcess]
├── treatment_protocols/{protocolId}
│   └── doses/{doseId}
├── weight_records/{id}
├── nutrition_plans/{id}
├── meal_logs/{id}
├── supplement_logs/{id}
├── health_documents/{id}
├── operational_restrictions/{id}
├── vaccination_records/{vaccinationId}  [13º agregado canônico]
├── health_schedule/{scheduleId}
├── legacy_health_records/{recordId}     [read-only para clientes; Admin SDK auditado]
├── health_timeline/{timelineId}         [projeção]
└── health_summary/current               [projeção singleton]
```

Migrações são controladas em:
```
_migrations/health_v1/batches/{batchId}  [metadados de batch de migração]
```

---

## 2. Coleções — fontes canônicas

### 2.1 clinical_cases/{caseId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| clinical_status | string (enum) | ✅ | open, under_investigation, under_treatment, monitoring, discharged, cancelled |
| title | string | ✅ | Ex: "Lesao MPD", "Otite bilateral" |
| opened_at | timestamp | ✅ | |
| opened_by | RecordedBy | ✅ | Ref ao criador original |
| opening_event_id | string | ✅ | Ref ao primeiro evento |
| opening_type | string (enum) | ✅ | incident, consultation, preventive, administrative |
| recorded_by | RecordedBy | ✅ | Executor que registrou (geralmente = opened_by) |
| closed_at | timestamp | ❌ | |
| closed_by | RecordedBy | ❌ | |
| closure_type | string (enum) | ❌ | discharge, cancelled, administrative |
| closure_reason | string | ❌ | |
| primary_professional | ProfessionalIdentity | ❌ | |
| reopen_reason | string | ❌ | Obrigatório em reabertura |
| reopened_at | timestamp | ❌ | Última reabertura |
| reopened_by | RecordedBy | ❌ | Quem reabriu |
| previous_status | string | ❌ | Status anterior ao reopen (= discharged) |
| reopened_count | number | ❌ | Default 0 |
| recurrence_of_case_id | string | ❌ | Ref a caso anterior |
| related_case_ids | array of string | ❌ | Refs a casos relacionados |
| has_active_restriction | bool | ❌ | Derivado por Function |
| has_pending_schedule | bool | ❌ | Derivado por Function |
| active_treatments_count | number | ❌ | Derivado por Function |
| last_event_at | timestamp | ❌ | Derivado |
| event_count | number | ❌ | Derivado |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | Se migrado |
| schema_version | number | ✅ | Atual: 1 |

**Escritor:** Mobile (abertura por intercorrência), Web (abertura por consulta/admin), Function (flags derivados).
**Leitor:** Mobile, Web.
**Índices:** `clinical_status ASC, opened_at DESC`; `clinical_status ASC, last_event_at DESC`.

---

### 2.2 clinical_cases/{caseId}/events/{eventId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| event_type | string (enum) | ✅ | Ver Domain Model §6 |
| status | string (enum) | ✅ | draft, final, cancelled (sem "amended") |
| occurred_at | timestamp | ✅ | Quando aconteceu |
| recorded_at | timestamp | ✅ | Server timestamp |
| updated_at | timestamp | ❌ | Só em draft |
| finalized_at | timestamp | ❌ | |
| cancelled_at | timestamp | ❌ | |
| cancel_reason | string | ❌ | Obrigatório se cancelled |
| recorded_by | RecordedBy | ✅ | Quem registrou no sistema |
| professional | ProfessionalIdentity | ❌ | Quem decidiu clinicamente (externo) |
| payload_type | string (enum) | ✅ | Ver Domain Model §6 |
| payload_version | number | ✅ | Versão do contrato |
| content | map | ✅ | Campos específicos por payload_type |
| operational_impact | map | ❌ | Ver OperationalImpact |
| attachment_refs | array of string | ❌ | IDs de HealthDocument (não URLs); tratado como `[]` quando ausente |
| source_document | HealthDocumentRef | ❌ | Evidência documental |
| has_amendments | bool | ✅ | Server-managed, default false |
| amendment_count | number | ✅ | Server-managed, default 0 |
| last_amended_at | timestamp | ❌ | Server-managed |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | Se migrado |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile/Web (create, update draft). Function (gerencia metadados has_amendments).
**Leitor:** Mobile, Web.
**Soft delete:** via status=cancelled com cancel_reason + campos deleted_*.
**Anexos:** apenas IDs em attachment_refs; URLs são derivadas de HealthDocument.storage_path.
**Sem `exam_group_id`** — relacionamento com exame é via `exam_id` em ExamProcess.
**Índices:** `status ASC, occurred_at DESC`; `event_type ASC, occurred_at DESC`; `payload_type ASC, status ASC`.

---

### 2.3 events/{eventId}/amendments/{amendId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| type | string (enum) | ✅ | correction, addendum, complement |
| reason | string | ✅ | |
| payload_type | string | ✅ | Mesmo do evento pai |
| payload_version | number | ✅ | Mesmo do evento pai |
| content | map | ✅ | Apenas campos alterados/adicionados |
| recorded_by | RecordedBy | ✅ | |
| recorded_at | timestamp | ✅ | Server timestamp |
| schema_version | number | ✅ | |

**Escritor:** Mobile/Web (create-only; imutável após criação).
**Leitor:** Mobile, Web.
**Índices:** `recorded_at ASC`.

---

### 2.4 clinical_cases/{caseId}/exams/{examId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| exam_id | string | ✅ | UUID ou `legacy_{legacy_id}` |
| case_id | string | ✅ | Ref ao caso |
| exam_type | string (enum) | ✅ | blood_work, imaging, biopsy, etc. |
| current_stage | string (enum) | ✅ | requested, collected, resulted, interpreted, impact_assessed, cancelled |
| title | string | ✅ | Ex: "Hemograma completo" |
| created_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | Executor da criação |
| requested_at | timestamp | ❌ | Estágio requested |
| requested_by | RecordedBy | ❌ | |
| request_professional | ProfessionalIdentity | ❌ | |
| request_reason | string | ❌ | Indicação clínica |
| urgency | string (enum) | ❌ | routine, urgent, stat |
| lab_name | string | ❌ | |
| collected_at | timestamp | ❌ | Estágio collected |
| collected_by | RecordedBy | ❌ | |
| collection_site | string | ❌ | |
| collection_notes | string | ❌ | |
| resulted_at | timestamp | ❌ | Estágio resulted |
| result_received_by | RecordedBy | ❌ | |
| result_document_id | string | ❌ | Ref a HealthDocument |
| result_summary | string | ❌ | |
| interpreted_at | timestamp | ❌ | Estágio interpreted |
| interpreted_by | RecordedBy | ❌ | |
| interpretation_professional | ProfessionalIdentity | ❌ | |
| interpretation_text | string | ❌ | |
| interpretation_document_id | string | ❌ | Ref a HealthDocument |
| impact_assessed_at | timestamp | ❌ | Estágio impact_assessed |
| impact_assessed_by | RecordedBy | ❌ | |
| operational_impact | OperationalImpact | ❌ | |
| restrictions_issued | array of string | ❌ | IDs de OperationalRestrictions criadas |
| cancelled_at | timestamp | ❌ | |
| cancelled_by | RecordedBy | ❌ | |
| cancel_reason | string | ❌ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile/Web (criar, atualizar estágios). Function (gera schedule, valida transições).
**Leitor:** Mobile, Web.
**Migração:** exames legados sem request recebem ID determinístico (`legacy_{legacy_id}`) e entram diretamente no estágio equivalente.

**Índices:** `current_stage ASC, created_at DESC`; `exam_type ASC, current_stage ASC`; `requested_at DESC`.

---

### 2.5 treatment_protocols/{protocolId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| case_id | string | ✅ | Ref ao caso |
| status | string (enum) | ✅ | active, paused, completed, cancelled |
| medication_name | string | ✅ | |
| dose | DoseBlock | ✅ | Estruturado: { value, unit, per_kg, route } |
| schedule | ScheduleBlock | ✅ | Estruturado: { type, interval_minutes, times_of_day, timezone, tolerance_minutes } |
| dosage_display | string | ❌ | Para apresentação: "10mg/kg" |
| frequency_display | string | ❌ | Para apresentação: "BID" |
| start_date | timestamp | ✅ | |
| end_date | timestamp | ❌ | |
| duration_days | number | ❌ | |
| instructions | string | ❌ | |
| recorded_by | RecordedBy | ✅ | Executor que transcreveu |
| professional | ProfessionalIdentity | ✅ | Quem prescreveu (externo) |
| source_document | HealthDocumentRef | ✅ | Receita original |
| paused_at | timestamp | ❌ | |
| pause_reason | string | ❌ | |
| completed_at | timestamp | ❌ | |
| cancelled_at | timestamp | ❌ | |
| cancel_reason | string | ❌ | |
| doses_administered | number | ❌ | Derivado |
| doses_remaining | number | ❌ | Derivado |
| next_dose_at | timestamp | ❌ | Derivado |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Web (admin transcreve prescrição externa), Function (derivados).
**Leitor:** Mobile, Web.
**Índices:** `case_id ASC, status ASC`; `status ASC, next_dose_at ASC`.

---

### 2.6 treatment_protocols/{protocolId}/doses/{doseId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| planned_dose_id | string | ✅ | ID da dose planejada no schedule |
| schedule_item_id | string | ✅ | Ref ao HealthScheduleItem |
| idempotency_key | string | ✅ | Rastreabilidade — mesmo valor determinístico de `doseId`. Não inclui data, `YYYYMMDD` ou timestamp de relógio. |
| scheduled_for | timestamp | ✅ | |
| status | string (enum) | ✅ | administered, skipped, cancelled |
| administered_at | timestamp | ❌ | Se administered |
| recorded_by | RecordedBy | ✅ | Quem digitou no sistema |
| administered_by | RecordedBy | ❌ | Quem deu a dose (se diferente) |
| recorded_at | timestamp | ✅ | Server |
| skip_reason | string | ❌ | Se skipped |
| observations | string | ❌ | |
| side_effects | string | ❌ | |
| attachment_refs | array of health_document_id | ❌ | Referências a HealthDocument (substitui photo_url) |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile (administração de dose).
**Leitor:** Mobile, Web.
**Idempotência:** `doseId` determinístico = `hash(protocolId + planned_dose_id)` garante unicidade sem depender de timestamp de relógio. A criação usa documento com ID determinístico ou transação backend; `idempotency_key` permanece como campo de rastreabilidade, mas a garantia de unicidade vem do ID determinístico/transação — Firestore index não oferece constraint `unique`.
**Índices:** `scheduled_for DESC`; `status ASC, scheduled_for DESC`; `idempotency_key ASC`.

---

### 2.7 weight_records/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| weight_kg | number | ✅ | > 0 |
| measured_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | |
| context | string (enum) | ❌ | routine, clinical, pre_op, post_op |
| bcs | number | ❌ | 1-9 body condition score |
| notes | string | ❌ | |
| attachment_refs | array of health_document_id | ❌ | Referências a HealthDocument (substitui photo_url) |
| case_id | string | ❌ | |
| ideal_weight_min | number | ❌ | |
| ideal_weight_max | number | ❌ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile.
**Leitor:** Mobile, Web.
**Índices:** `measured_at DESC`; `deleted_at ASC, measured_at DESC`.

---

### 2.8 nutrition_plans/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| status | string (enum) | ✅ | active, superseded, cancelled |
| food_type | string | ✅ | |
| amount_grams_per_day | number | ✅ | |
| meals_per_day | number | ✅ | |
| vigent_from | timestamp | ✅ | |
| vigent_until | timestamp | ❌ | |
| hydration_ml | number | ❌ | |
| special_instructions | string | ❌ | |
| professional | ProfessionalIdentity | ❌ | Se definido por nutricionista |
| source_document | HealthDocumentRef | ❌ | |
| attachment_refs | array of health_document_id | ❌ | Referências a HealthDocument (substitui report_url) |
| recorded_by | RecordedBy | ✅ | Quem registrou |
| created_at | timestamp | ✅ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Web exclusivamente (admin).
**Leitor:** Mobile, Web.
**Índices:** `status ASC, vigent_from DESC`.

---

### 2.9 meal_logs/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| period | string (enum) | ✅ | morning, afternoon, evening, night, extra |
| amount_grams | number | ✅ | |
| fed_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | |
| plan_id | string | ❌ | Ref ao plano vigente |
| prescription_amount_at_time | number | ❌ | Snapshot do plano |
| divergence_percent | number | ❌ | |
| divergence_reason | string | ❌ | |
| attachment_refs | array of health_document_id | ❌ | Referências a HealthDocument (substitui photo_url) |
| observations | string | ❌ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile.
**Leitor:** Mobile, Web.
**Índices:** `deleted_at ASC, fed_at DESC`; `fed_at DESC` (stream do dia).

---

### 2.10 supplement_logs/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| supplement_name | string | ✅ | |
| dose | string | ✅ | Texto descritivo da dose |
| administered_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | |
| notes | string | ❌ | |
| batch_number | string | ❌ | |
| protocol_id | string | ❌ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile.
**Leitor:** Mobile, Web.
**Índices:** `administered_at DESC`.

---

### 2.11 health_documents/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| document_type | string (enum) | ✅ | Ver Domain Model |
| title | string | ✅ | |
| storage_path | string | ✅ | Identidade canonica no Cloud Storage |
| storage_url | string | ❌ | Derivado/cache - nunca fonte |
| mime_type | string | ✅ | |
| file_size_bytes | number | ❌ | |
| uploaded_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | Quem fez upload |
| case_id | string | ❌ | |
| event_id | string | ❌ | |
| exam_id | string | ❌ | |
| description | string | ❌ | |
| issuer | string | ❌ | |
| issue_date | timestamp | ❌ | |
| expiry_date | timestamp | ❌ | |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**`storage_path`:** identidade canonica (ex: `dogs/dog_001/health/doc_xyz.pdf`).
**`storage_url`:** derivado/cache via Storage API. Alteracoes de bucket/CDN nao invalidam o doc.
**Escritor:** Mobile, Web.
**Leitor:** Mobile, Web.
**Índices:** `deleted_at ASC, uploaded_at DESC`; `document_type ASC, uploaded_at DESC`.

---

### 2.12 operational_restrictions/{id}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| level | string (enum) | ✅ | absolute, partial, attention |
| category | string (enum) | ✅ | Ver Domain Model |
| description | string | ✅ | |
| activities_restricted | array of string | ❌ | |
| issued_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | Executor que transcreveu |
| professional | ProfessionalIdentity | ✅ | Quem emitiu (externo) |
| source_document | HealthDocumentRef | ✅ | Laudo/atestado |
| expected_end | timestamp | ❌ | |
| actual_end | timestamp | ❌ | |
| ended_by | RecordedBy | ❌ | Usuário interno que encerra |
| end_professional | ProfessionalIdentity | ❌ | Profissional externo que autorizou encerramento (obrigatório quando encerramento representa decisão clínica externa) |
| end_source_document | HealthDocumentRef | ❌ | Laudo/atestado de liberação (obrigatório quando encerramento representa decisão clínica externa) |
| end_reason | string | ❌ | Obrigatório quando status=ended |
| evidence | map | ❌ | Ver Evidence |
| status | string (enum) | ✅ | active, ended, cancelled |
| case_id | string | ❌ | |
| event_id | string | ❌ | |
| exam_id | string | ❌ | Origem em ExamProcess.impact_assessed |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Mobile/Web (admin ou condutor com evidence profissional).
**Leitor:** Mobile, Web, Function (para snapshot).
**Índices:** `status ASC, level ASC, issued_at DESC`.

---

### 2.13 vaccination_records/{vaccinationId}

> **VaccinationRecord representa uma vacinação efetivamente registrada.** Não é planejamento nem agenda. Estados temporais (`scheduled`, `today`, `upcoming`, `pending`, `overdue`) **não** são persistidos aqui — vivem exclusivamente em `HealthScheduleItem`. Não se cria `VaccinationRecord scheduled`: o item futuro de vacinação pertence à agenda; a vacinação só vira `VaccinationRecord` quando a aplicação é registrada.

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| vaccine_name | string | ✅ | |
| vaccine_type | string | ❌ | ex: V10, antirrábica, giárdia |
| manufacturer | string | ❌ | |
| batch_number | string | ❌ | |
| dose | string | ❌ | Apresentação da dose aplicada |
| record_status | string (enum) | ✅ | **final** \| **cancelled** — apenas dois valores persistidos. `applied_at` é obrigatório quando `final`. |
| applied_at | timestamp | ❌ | Obrigatório quando `record_status == final` |
| validity_until | timestamp | ❌ | |
| next_due_at | timestamp | ❌ | Deriva geração de item em `health_schedule` (schedule_type: vaccination); nunca classifica `VaccinationRecord` como overdue. |
| recorded_by | RecordedBy | ✅ | Usuário interno que registrou |
| administered_by | RecordedBy | ❌ | Quem efetivamente aplicou (se diferente de recorded_by) |
| professional | ProfessionalIdentity | ❌ | Profissional externo responsável pela aplicação (somente quando aplicável) |
| source_document | HealthDocumentRef | ❌ | Cartão vacinal / atestado |
| case_id | string | ❌ | **Somente** quando há reação adversa ou vínculo terapêutico dentro de um caso |
| notes | string | ❌ | |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| migration_batch_id | string | ❌ | |
| cancelled_at | timestamp | ❌ | Obrigatório quando `record_status == cancelled` |
| cancelled_by | RecordedBy | ❌ | |
| cancel_reason | string | ❌ | Obrigatório quando `record_status == cancelled` |
| schema_version | number | ✅ | |

**Invariante:** VaccinationRecord pode existir sem ClinicalCase. Ter `case_id` preenchido é apenas referência informativa para cenários de reação adversa — **não** torna a vacinação um evento do caso. Quando há reação adversa, registra-se também um `ClinicalEvent` do tipo `vaccination` (com `vaccination_record_id` referenciando este documento) **dentro** do caso; o registro canônico continua aqui. Vacinação registrada **não** cria ClinicalCase automaticamente.

**Escritor:** Mobile (aplicação em campo), Web (registro administrativo), Function (criação automática de próxima dose via `health_schedule`).
**Leitor:** Mobile, Web, Function (prontidão e timeline).
**PII:** `professional` é PII; v1 lê todo o bloco para usuários com `health.read`.
**Gera:** entrada em `health_timeline` (timeline_type: vaccination); item em `health_schedule` (schedule_type: vaccination) para próxima dose — **nunca** estados temporais persistidos em `VaccinationRecord`.
**Índices:** `applied_at DESC`; `record_status ASC, applied_at DESC`; `vaccine_type ASC, applied_at DESC`.

---

### 2.14 health_schedule/{scheduleId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| schedule_type | string (enum) | ✅ | dose, vaccination, exam, consultation, weighing, reevaluation, deworming, bath, general |
| title | string | ✅ | |
| scheduled_for | timestamp | ✅ | |
| due_until | timestamp | ❌ | Opcional — quando ausente, tolerância é definida por configuração por `schedule_type`, **sem default universal**. |
| timezone | string | ✅ | Ex: "America/Sao_Paulo"; usado em toda derivação temporal |
| lifecycle_status | string (enum) | ✅ | **open, completed, cancelled** — único campo de estado persistido |
| source_type | string (enum) | ✅ | treatment_protocol, clinical_case, exam_process, preventive, manual |
| source_id | string | ❌ | |
| case_id | string | ❌ | |
| completed_at | timestamp | ❌ | |
| completed_by | RecordedBy | ❌ | |
| cancelled_at | timestamp | ❌ | |
| cancelled_by | RecordedBy | ❌ | |
| cancel_reason | string | ❌ | |
| created_at | timestamp | ✅ | |
| recorded_by | RecordedBy | ✅ | Ou "system" para Function |
| notes | string | ❌ | |
| revision | number | ✅* | Monotônico; criação = 1. Ausente em legado → interpretado como 0 (4E Gate 2). *obrigatório em mutações novas |
| create_operation_id | string | ❌ | Idempotency key da criação manual |
| create_fingerprint | string | ❌ | Fingerprint canônico da intenção de create |
| last_update_operation_id | string | ❌ | Atalho da última update (receipts são a fonte) |
| last_lifecycle_operation_id | string | ❌ | Atalho da última complete/cancel |
| migration_batch_id | string | ❌ | Se migrado |
| schema_version | number | ✅ | Atual: 1 |

**Subcoleção de operation receipts (4E Gate 2):**

```text
dogs/{dogId}/health_schedule/{scheduleId}/operations/{operationId}
```

`operationId` no path = token validado no callable (trim, 1..128, `[A-Za-z0-9][A-Za-z0-9._-]*`, sem `/` nem `.`/`..`). Não é hasheado; o ID lógico validado é o segmento físico.

| Campo | Notas |
|-------|-------|
| operation_id | chave (mesmo token do path) |
| operation_type | create_manual \| update_open \| complete \| cancel |
| actor_uid | escopo do ator |
| fingerprint | intenção canônica (sem timestamps/autoria server) |
| result | scheduleId, revision, lifecycleStatus, wasNoOp |
| processed_at | server timestamp |

**Receipts = fonte durável de idempotência.**
`last_*_operation_id` no documento pai = apenas atalhos auxiliares (não substituem receipts).

Retenção: receipts permanecem enquanto forem necessários para retries legítimos; política de purga futura documentável sem apagar cedo demais.

**Invariante absoluta de persistência:** apenas `lifecycle_status` é persistido. Os valores `scheduled`, `upcoming`, `today`, `pending`, `overdue` são **somente calculados na leitura**. Nenhuma Function, nenhum job periódico, nenhuma reconciliação, nenhuma atualização implícita grava esses valores como campos no documento. Não existe permissão em Rules para criar/atualizar campos temporais derivados. Quaisquer campos derivados existentes em dados migrados devem ser descartados no cutover.

**Data efetiva única (regra absoluta):**

```text
effective_due_until =
  due_until
  ?? resolveTolerance(schedule_type, scheduled_for, timezone)
```

Quando `due_until` está ausente, a tolerância é resolvida por configuração por `schedule_type` — não há default universal.

**Precedência da derivação temporal (avaliada na ordem; primeira condição verdadeira vence):**

1. `lifecycle_status == "completed"` → `completed` (terminal)
2. `lifecycle_status == "cancelled"` → `cancelled` (terminal)
3. `now > effective_due_until` → `overdue`
4. `now >= scheduled_for` → `pending`
5. `scheduled_for` é hoje (mesma data no timezone do item) → `today`
6. item dentro da janela próxima (≤ N dias, configurável por `schedule_type`) → `upcoming`
7. restante → `scheduled`

A regra é única: o primeiro caso verdadeiro vence. Não há caso em que o mesmo item seja classificado simultaneamente como `pending` e `overdue`.

**Escritor:** Function (automático), Mobile/Web (manual).
**Leitor:** Mobile, Web.
**Índices:** `lifecycle_status ASC, scheduled_for ASC`; `schedule_type ASC, lifecycle_status ASC, scheduled_for ASC`.

---

### 2.15 legacy_health_records/{recordId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| original_collection | string | ✅ | Nome da coleção original |
| original_id | string | ✅ | ID original no schema legado |
| original_payload | map | ✅ | Payload bruto preservado |
| migration_batch_id | string | ✅ | Ref ao batch que migrou |
| migrated_at | timestamp | ✅ | Quando foi migrado |
| normalized_view | map | ❌ | Tentativa de mapeamento para novos modelos |
| case_id | string | ❌ | Linkagem manual ou automatica |
| dog_id | string | ✅ | |
| occurred_at | timestamp | ❌ | Extraído quando possivel |
| recorded_by | RecordedBy | ❌ | Extraído quando possivel |
| schema_version | number | ✅ | |

**Regras de escrita:**
- `original_payload` é **sempre imutável**.
- Clientes (Mobile, Web) possuem apenas permissão de **read** (Rules bloqueiam write).
- Admin SDK pode atualizar, de forma auditada: `normalized_view`, `case_id`, `migrated_at`, metadados de reconciliação, e metadados de batch.
- Após cutover do agregado correspondente, writes em Rules são bloqueados para clientes; Admin SDK continua permitido para fins administrativos auditados.
- **Não há afirmação absoluta de "nenhum write após o backfill"** — há permissões controladas (Admin SDK auditado).

**Escritor:** Admin SDK (auditável) — apenas para correções de normalização e linkagem de caso.
**Leitor:** Mobile, Web (read-only).
**Aparece na HealthTimeline** quando tem `occurred_at` extraido.
**Indices:** `migration_batch_id ASC`; `case_id ASC, occurred_at DESC`.

---

### 2.16 _migrations/health_v1/batches/{batchId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| started_at | timestamp | ✅ | |
| completed_at | timestamp | ❌ | |
| status | string (enum) | ✅ | running, completed, failed, rolled_back |
| source_collection | string | ✅ | |
| dry_run | bool | ✅ | `true` não grava destinos |
| total_source | number | ✅ | Total lido da origem |
| total_migrated | number | ✅ | Default 0 |
| total_rejected | number | ✅ | Default 0 |
| total_skipped | number | ✅ | Default 0; inclui itens já migrados |
| rejections | array of map | ❌ | `{source_id, reason}` |
| manifest | array of map | ✅ | Cada item: `operation_type`, `target_path`, `target_id`, `before_image` para update, `changed_fields`, `migrated_at`, `checksum_before`, `checksum_after` |
| migration_version | string | ✅ | Ex: "health_v1_2026_07" |
| triggered_by | string | ✅ | UID do admin ou "system" |
| schema_version | number | ✅ | |

**Escritor:** Migration Function exclusivamente.
**Leitor:** Admin (Web), para auditoria de migracao.

---

## 3. Colecoes — projecoes (read-only para clientes)

### 3.1 health_timeline/{timelineId}

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| timeline_type | string (enum) | ✅ | Ver Domain Model |
| source_collection | string | ✅ | Caminho da fonte |
| source_id | string | ✅ | ID do doc fonte |
| occurred_at | timestamp | ✅ | |
| recorded_at | timestamp | ✅ | |
| projected_at | timestamp | ✅ | Quando Function projetou |
| title | string | ✅ | |
| subtitle | string | ❌ | |
| case_id | string | ❌ | |
| case_title | string | ❌ | Snapshot |
| dog_id | string | ✅ | |
| recorded_by | RecordedBy | ✅ | |
| professional | ProfessionalIdentity | ❌ | |
| payload_type | string | ❌ | |
| operational_impact | map | ❌ | |
| status | string | ✅ | `final` ou `cancelled`. Fontes factuais sem lifecycle próprio projetam `final`; fonte cancelada/invalidada projeta `cancelled`; drafts nunca entram. |
| attachment_count | number | ❌ | |
| has_amendments | bool | ❌ | Server-managed |
| amendment_count | number | ❌ | Server-managed |
| last_amended_at | timestamp | ❌ | Server-managed |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** Function exclusivamente.
**Leitor:** Mobile, Web.
**Inclui entradas de LegacyHealthRecord** quando tem occurred_at extraido (badge "Migrado").
**Índices:** `occurred_at DESC`; `timeline_type ASC, occurred_at DESC`; `case_id ASC, occurred_at DESC`; `dog_id ASC, occurred_at DESC`.

---

### 3.2 health_summary/current

Documento singleton. Campos definidos na ADR-004 e ADR-005.
Reapresenta o ReadinessSnapshot consolidado (readiness_status, indicadores, etc.).

**Escritor:** Function exclusivamente.
**Leitor:** Mobile, Web (stream).

---

## 4. Mapeamento schema atual → schema alvo

| Schema atual | Schema alvo | Estrategia |
|-------------|-------------|-----------|
| `dogs/{dogId}/health_events` (todos os tipos, todos os registros) | `dogs/{dogId}/legacy_health_records/{recordId}` | **Contrato conservador único:** todos os `health_events` anteriores ao go-live vão para `legacy_health_records` com `original_payload` preservado. Nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/events`. Operações administrativas futuras podem, de forma auditada, vincular `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando clinicamente justificado. |
| `dogs/{dogId}/exams` (se existir como subcollection) | `clinical_cases/{caseId}/exams` | Migração para subcoleção de caso; sem exam_group_id |
| `dogs/{dogId}/weight_records` | `weight_records` (normalizado) | Adicionar campos |
| `dogs/{dogId}/weight_history` | — | Não migrado como fonte canônica; preservado read-only durante todo o v1 |
| `dogs/{dogId}/feeding_events` | `meal_logs` | Rename + normalização |
| `dogs/{dogId}/feedings` | — | Não migrado como fonte canônica; preservado read-only durante todo o v1 |
| `dogs/{dogId}/nutritional_prescriptions` | `nutrition_plans` | Rename + normalização |
| `dogs/{dogId}/nutrition_supplements` | `supplement_logs` | Normalização |
| `vacinas/{id}` (raiz) | `vaccination_records/{vaccinationId}` (canônico) + `legacy_health_records` (incompletos) | Migração com dados suficientes vai para VaccinationRecord; incompletos permanecem em legacy_health_records read-only. **Não** backfilar para `clinical_cases/events` nem para "caso preventivo". |
| `documentos/{id}` (raiz) | `health_documents` | Backfill com `storage_path` canônico normalizado (URLs antigas preservadas apenas no payload/metadado legado) |
| `dogs/{dogId}/documents` | `health_documents` | Migrar para coleção consolidada |
| `dogs/{dogId}/health_schedule` (com estados temporais persistidos) | `health_schedule` (apenas lifecycle_status) | Migrar lifecycle_status; descartar temporais |
| `treatment_protocols` (com dosage/frequency texto) | `treatment_protocols` (com dose/schedule estruturados) | Tentar parse; fallback para dosage_display + frequency_display |
| `treatment_protocols/{id}/doses` (sem idempotency) | `treatment_protocols/{id}/doses` (com doseId determinístico) | Backfill com chave deterministica |
| `alertas/{id}` (raiz) | `health_schedule` + summary | Substituição funcional |
| `dogs/{dogId}._last_*` | `health_summary/current` | Substituição (campos legados mantidos) |
| Exames legados com `exam_group_id` | `clinical_cases/{caseId}/exams/{examId}` (sem group_id) | Migrar como ExamProcess; eventos relacionados preservados com referencia exam_id |

Documentos migrados recebem `migration_batch_id` que aponta para `_migrations/health_v1/batches/{batchId}`.

---

## 5. Payload conceitual — exemplo

### Evento clinico (consulta veterinaria)

```json
{
  "event_type": "consultation",
  "status": "final",
  "occurred_at": "2026-07-14T10:30:00Z",
  "recorded_at": "2026-07-14T10:45:00Z",
  "finalized_at": "2026-07-14T10:45:00Z",
  "recorded_by": {
    "uid": "uid_001",
    "name": "GCM Silva",
    "internal_role": "condutor"
  },
  "professional": {
    "name": "Dra. Costa",
    "registration_type": "CRMV",
    "registration_number": "SP-12345",
    "clinic": "VetK9"
  },
  "payload_type": "consultation_v1",
  "payload_version": 1,
  "content": {
    "chief_complaint": "Claudicação MPD há 2 dias",
    "examination_findings": "Edema em articulação tarsometatársica",
    "diagnosis": "Entorse grau II",
    "plan": "Repouso 7 dias + anti-inflamatório"
  },
  "operational_impact": {
    "level": "high",
    "description": "Repouso obrigatório 7 dias"
  },
  "attachment_refs": ["doc_xyz789"],
  "source_document": {
    "health_document_id": "doc_xyz789",
    "description": "Receita + laudo"
  },
  "has_amendments": false,
  "amendment_count": 0,
  "schema_version": 1
}
```

### Item de timeline (projecao do evento acima)

```json
{
  "timeline_type": "consultation",
  "occurred_at": "2026-07-14T10:30:00Z",
  "recorded_at": "2026-07-14T10:45:00Z",
  "projected_at": "2026-07-14T10:45:03Z",
  "title": "Consulta — Entorse grau II",
  "subtitle": "Dra. Costa (CRMV SP-12345) • Repouso 7 dias",
  "case_id": "case_abc123",
  "case_title": "Lesao MPD",
  "dog_id": "dog_001",
  "source_collection": "dogs/dog_001/clinical_cases/case_abc123/events",
  "source_id": "evt_xyz789",
  "recorded_by": {
    "uid": "uid_001",
    "name": "GCM Silva",
    "internal_role": "condutor"
  },
  "professional": {
    "name": "Dra. Costa",
    "registration_type": "CRMV",
    "registration_number": "SP-12345",
    "clinic": "VetK9"
  },
  "payload_type": "consultation_v1",
  "operational_impact": {
    "level": "high",
    "description": "Repouso obrigatório 7 dias"
  },
  "status": "final",
  "attachment_count": 1,
  "has_amendments": false,
  "amendment_count": 0,
  "schema_version": 1
}
```

### ExamProcess (hemograma)

```json
{
  "exam_id": "exam_def456",
  "case_id": "case_abc123",
  "dog_id": "dog_001",
  "exam_type": "blood_work",
  "current_stage": "interpreted",
  "title": "Hemograma completo",
  "created_at": "2026-07-14T08:00:00Z",
  "recorded_by": {
    "uid": "uid_001",
    "name": "GCM Silva",
    "internal_role": "condutor"
  },
  "requested_at": "2026-07-14T08:00:00Z",
  "requested_by": { "uid": "uid_001", "name": "GCM Silva", "internal_role": "condutor" },
  "request_professional": {
    "name": "Dra. Costa",
    "registration_type": "CRMV",
    "registration_number": "SP-12345",
    "clinic": "VetK9"
  },
  "request_reason": "Claudicação MPD com suspeita inflamatória",
  "urgency": "routine",
  "lab_name": "LabVet",
  "resulted_at": "2026-07-14T15:00:00Z",
  "result_received_by": { "uid": "uid_001", "name": "GCM Silva", "internal_role": "condutor" },
  "result_document_id": "doc_lab123",
  "result_summary": "Leucocitose discreta",
  "interpreted_at": "2026-07-14T16:00:00Z",
  "interpreted_by": { "uid": "admin_001", "name": "Cap. Oliveira", "internal_role": "admin" },
  "interpretation_professional": {
    "name": "Dra. Costa",
    "registration_type": "CRMV",
    "registration_number": "SP-12345",
    "clinic": "VetK9"
  },
  "interpretation_text": "Leucocitose compatível com processo inflamatório agudo.",
  "interpretation_document_id": "doc_interp789",
  "schema_version": 1
}
```

### TreatmentProtocol estruturado

```json
{
  "case_id": "case_abc123",
  "dog_id": "dog_001",
  "status": "active",
  "medication_name": "Carprofeno",
  "dose": {
    "value": 25,
    "unit": "mg",
    "per_kg": false,
    "route": "oral"
  },
  "schedule": {
    "type": "interval",
    "interval_minutes": 720,
    "times_of_day": [],
    "timezone": "America/Sao_Paulo",
    "tolerance_minutes": 30
  },
  "dosage_display": "1 comprimido 25mg",
  "frequency_display": "q12h",
  "start_date": "2026-07-14T09:00:00Z",
  "recorded_by": {
    "uid": "admin_001",
    "name": "Cap. Oliveira",
    "internal_role": "admin"
  },
  "professional": {
    "name": "Dra. Costa",
    "registration_type": "CRMV",
    "registration_number": "SP-12345",
    "clinic": "VetK9"
  },
  "source_document": {
    "health_document_id": "doc_receita123",
    "description": "Receita carprofeno 7 dias"
  },
  "schema_version": 1
}
```

---

## 6. Notas de implementação

### 6.1 Enum HealthScheduleItem.lifecycle_status

Apenas tres valores persistidos:
- `open` — item pendente
- `completed` — executado (terminal)
- `cancelled` — cancelado (terminal)

### 6.2 Idempotência de doses

Toda DoseAdministration é identificada por `doseId = hash(protocolId + planned_dose_id)`. Esse ID é determinístico e **não** inclui data, `YYYYMMDD` nem timestamp de relógio. A unicidade é garantida pela criação do documento com ID determinístico, ou por create transacional/idempotente no backend. Firestore não oferece constraint `unique` em índice.

O campo `idempotency_key` (quando presente) repete o mesmo valor determinístico de `doseId` — é usado para **rastreabilidade**, não como garantia de unicidade. Não use `idempotency_key` para descrever a garantia principal; a garantia vem do `doseId`.

```
{protocolId}_{planned_dose_id}
```

Function valida que o documento criado tem `doseId` consistente antes de aceitar write.

### 6.3 Storage path identidade canonica

HealthDocument.storage_path é a fonte de verdade.
URL é cache derivado — invalidar manualmente quando storage config muda.

### 6.4 ExamProcess vs ClinicalEvent — separação clara

| Pergunta | Resposta |
|----------|----------|
| "Em que estagio está este exame?" | ExamProcess.current_stage |
| "O que aconteceu neste exame, quando e por quem?" | ClinicalEvent com event_type de exame |
| "Quais restrições foram geradas?" | ExamProcess.restrictions_issued + OperationalRestrictions |

### 6.5 Migração controlada

Toda operação de migracao registra batch em `_migrations/health_v1/batches/{batchId}`.
Documentos migrados ganham `migration_batch_id` para rastreabilidade.
Legacy records preservados em `legacy_health_records/` com payload raw.
