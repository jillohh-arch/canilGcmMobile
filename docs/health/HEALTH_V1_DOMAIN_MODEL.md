# Health v1.0 — Modelo de Domínio

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-002, ADR-003, ADR-005, HEALTH_V1_FIRESTORE_SCHEMA.md |
| Escopo | Entidades, responsabilidades, estados, transições, invariantes e relacionamentos |
| Fora de escopo | Implementação Dart, DTOs, JSON serialization, IPO |

---

## 1. Visão geral

O domínio Health v1.0 é organizado em quatro camadas de entidades:

1. **Agregados clínicos** — entidades que compõem o ciclo de cuidado (caso, evento, exame, protocolo, dose, restrição).
2. **Agregados de rotina** — registros operacionais independentes de caso clínico (peso, refeição, suplemento, plano alimentar, vacinação preventiva).
3. **Registros legados** — dados migrados do schema anterior, preservados read-only.
4. **Projeções** — dados derivados das fontes canônicas para leitura otimizada (timeline, readiness snapshot).

O Health v1.0 define **13 agregados canônicos** (12 originais + `VaccinationRecord` como agregado preventivo independente) e 2 projeções.

---

## 2. Entidades do domínio

### 2.1 ClinicalCase

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Agrupa um ciclo clínico completo do K9: da abertura (intercorrência ou consulta) até a alta ou cancelamento |
| **Identificador** | `{dogId}/clinical_cases/{caseId}` — UUID gerado no create |
| **Invariantes** | (1) Deve ter ao menos um evento de abertura. (2) Não pode ser reaberto se cancelado. (3) Pode ter múltiplos tratamentos e exames simultâneos. (4) Um K9 pode ter N casos abertos. (5) Reabertura é uma ação, não um estado durável. |
| **Estados** | `open`, `under_investigation`, `under_treatment`, `monitoring`, `discharged`, `cancelled` |
| **Transições** | `open→under_investigation`, `open→under_treatment`, `under_investigation→under_treatment`, `under_treatment→monitoring`, `monitoring→discharged`, qualquer (exceto cancelled)→`cancelled`. Reabertura: `discharged→open \| under_investigation \| under_treatment \| monitoring`, como ação auditada com `reopen_reason`. |
| **Campos obrigatórios** | `clinical_status`, `title`, `opened_at`, `opened_by`, `opening_event_id`, `opening_type`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `closed_at`, `closed_by`, `closure_type`, `closure_reason`, `primary_professional`, `previous_status`, `reopened_at`, `reopened_by`, `reopen_reason`, `reopened_count`, `recurrence_of_case_id`, `related_case_ids` |
| **Valores derivados** | `has_active_restriction`, `has_pending_schedule`, `active_treatments_count`, `last_event_at`, `event_count` |
| **Dados sensíveis** | Professional identity (nome/registro) é PII com acesso controlado |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` |
| **Profissional** | `primary_professional: ProfessionalIdentity { name, registration_type, registration_number, clinic }` |
| **Auditoria** | Transições de status registradas em eventos; derivados atualizados por Function |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

**Reabertura (ação, não estado):**
- Caso `discharged` pode ser reaberto com `reopen_reason` obrigatório
- Campos atualizados: `reopened_at`, `reopened_by`, `previous_status` (era discharged), `reopened_count` (+1)
- Estado de destino permitido (escolhido pelo usuário interno): `open`, `under_investigation`, `under_treatment` ou `monitoring`. Reabertura **nunca** leva diretamente a `cancelled`.
- Caso `cancelled` NÃO pode ser reaberto — criar novo caso se necessário
- Reabertura exige capability `health.reopen_case` do usuário interno, com identificação do profissional externo responsável (`ProfessionalIdentity`) e `source_document` quando a reabertura representa decisão clínica externa. Reaberturas meramente administrativas por erro de fechamento exigem capability, `reopen_reason` e auditoria — sem inventar documento veterinário inexistente.

**Recorrência e relação:**
- `recurrence_of_case_id`: referência a caso anterior com mesma condição
- `related_case_ids`: array de IDs de casos relacionados (complicações, desdobramentos)

---

### 2.2 ClinicalEvent

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registro imutável de um acontecimento clínico dentro de um caso |
| **Identificador** | `{dogId}/clinical_cases/{caseId}/events/{eventId}` — UUID |
| **Invariantes** | (1) Payload clínico (`content`) é imutável após finalização. (2) Adendos são documentos separados, nunca edição do original. (3) Deve pertencer a exatamente um caso. (4) `occurred_at` não pode ser futuro. (5) Status permanece `final` mesmo com amendments — não muda para `amended`. |
| **Estados** | `draft`, `final`, `cancelled` |
| **Transições** | `draft→final`, `draft→cancelled`, `final→cancelled` |
| **Tipos (event_type)** | `consultation`, `incident`, `vaccination`, `exam_request`, `exam_collection`, `exam_result`, `exam_interpretation`, `treatment_start`, `treatment_note`, `dose_note`, `reevaluation`, `discharge`, `reopen`, `restriction_issued`, `restriction_ended`, `surgical_note`, `general_note`, `observation` |
| **Campos obrigatórios** | `event_type`, `status`, `occurred_at`, `recorded_at`, `recorded_by`, `content`, `payload_type`, `payload_version`, `schema_version` |
| **Campos opcionais** | `professional`, `operational_impact`, `attachment_refs`, `source_document`, `finalized_at`, `cancelled_at`, `cancel_reason`, `legacy_source`, `legacy_id` |
| **Metadados de amendment (server-managed)** | `has_amendments` (bool, default false), `amendment_count` (number, default 0), `last_amended_at` (timestamp) |
| **Valores derivados** | Nenhum (eventos são fatos, não cálculos) |
| **Dados sensíveis** | Conteúdo clínico (diagnósticos, condutas) — acesso restrito por Rules |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` (quem registrou no sistema) |
| **Responsável profissional** | `professional: ProfessionalIdentity { name, registration_type, registration_number, clinic }` (profissional externo responsável pela decisão, quando aplicável) |
| **Auditoria** | Imutabilidade enforced; adendos como subcoleção `amendments/{amendId}` |
| **Soft delete** | Via status=cancelled com cancel_reason obrigatório + `deleted_at`, `deleted_by`, `delete_reason` |

**Imutabilidade e amendments:**
- O campo `content` (payload clínico) é IMUTÁVEL após `status=final`
- Amendments são subcoleção separada — nunca alteram o evento original
- O status do evento permanece `final` — campos `has_amendments`, `amendment_count`, `last_amended_at` são metadados server-managed que indicam existência de adendos
- Cancelamento adiciona metadados (`cancelled_at`, `cancel_reason`) sem remover `content`

**Payloads tipados:**
- `payload_type`: identifica o tipo de payload (ex: `consultation_v1`, `incident_v1`, `exam_request_v1`)
- `payload_version`: versão do contrato (ex: 1)
- Cada `event_type` tem um contrato versionado com campos obrigatórios definidos
- Dados brutos legados existem somente em `LegacyHealthRecord.original_payload`. Um `ClinicalEvent` curado criado posteriormente usa payload tipado normal e referencia a origem legada.

**Attachments:**
- `attachment_refs`: array opcional de `health_document_id` (referências a HealthDocument), tratado como `[]` quando ausente
- NÃO armazena URLs inline — URL é derivada do HealthDocument via `storage_path`

---

### 2.3 ExamProcess (agregado próprio — subcoleção de caso)

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Representa o ciclo completo de um exame: solicitação → coleta → resultado → interpretação → impacto. É seu próprio agregado com estado persistido. |
| **Identificador** | `{dogId}/clinical_cases/{caseId}/exams/{examId}` — UUID (ou determinístico para legados) |
| **Invariantes** | (1) Cada transição de estágio produz um ClinicalEvent imutável. (2) Resultado sem solicitação é possível (legado — entrada direta no estágio `resulted`). (3) Interpretação requer resultado. (4) Impacto requer interpretação. (5) Cancelamento é terminal. |
| **Estados** | `requested`, `collected`, `resulted`, `interpreted`, `impact_assessed`, `cancelled` |
| **Transições** | `requested→collected→resulted→interpreted→impact_assessed` (sequência, etapas podem ser puladas para legado). Qualquer (exceto cancelled/impact_assessed)→`cancelled`. |
| **Campos obrigatórios** | `exam_id`, `case_id`, `exam_type`, `current_stage`, `title`, `created_at`, `recorded_by`, `schema_version` |
| **Campos por estágio** | Ver detalhamento abaixo |
| **Valores derivados** | Tempo entre etapas, dias desde última transição |
| **Dados sensíveis** | Resultados laboratoriais — acesso restrito |
| **Autoria** | Cada etapa tem seu próprio `recorded_by` e `professional` |
| **Auditoria** | Cada transição produz ClinicalEvent imutável; ExamProcess persiste estado atual |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

**Campos por estágio:**

| Estágio | Campos adicionados ao ExamProcess | Evento gerado |
|---------|----------------------------------|---------------|
| `requested` | `requested_at`, `requested_by`, `request_professional`, `request_reason`, `urgency`, `lab_name` | `exam_request` |
| `collected` | `collected_at`, `collected_by`, `collection_site`, `collection_notes` | `exam_collection` |
| `resulted` | `resulted_at`, `result_received_by`, `result_document_id`, `result_summary` | `exam_result` |
| `interpreted` | `interpreted_at`, `interpreted_by`, `interpretation_professional`, `interpretation_text`, `interpretation_document_id` | `exam_interpretation` |
| `impact_assessed` | `impact_assessed_at`, `impact_assessed_by`, `operational_impact`, `restrictions_issued` | ClinicalEvent com `operational_impact` |
| `cancelled` | `cancelled_at`, `cancelled_by`, `cancel_reason` | — |

**Relação ExamProcess ↔ ClinicalEvent:**
- ExamProcess responde: "em que estágio este exame está?"
- ClinicalEvent responde: "o que aconteceu, quando e por quem?"
- Cada transição de estágio em ExamProcess gera o ClinicalEvent correspondente
- É possível ter N eventos (ex: 2 interpretaciones distintas por divergência) sem reabrir estado

**Geração de schedule:**
- Ao criar ExamProcess com estágio `requested`, gera HealthScheduleItem do tipo `exam`
- Schedule é completado automaticamente quando estágio avança para `resulted`

**Migração de exames legados:**
- Exames legados sem documento de solicitação recebem ID determinístico: `legacy_{legacy_id}`
- Entram diretamente no estágio correspondente ao dado disponível (geralmente `resulted`)
- Campo `legacy_source` preserva origem

---

### 2.4 TreatmentProtocol

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Define um protocolo de medicação/terapia com cronograma estruturado e doses previstas |
| **Identificador** | `{dogId}/treatment_protocols/{protocolId}` — UUID |
| **Invariantes** | (1) Sempre referencia um caso clínico. (2) Não pode ser criado sem dose definida (estruturada ou texto). (3) Requer evidence profissional para criação. |
| **Estados** | `active`, `paused`, `completed`, `cancelled` |
| **Transições** | `active→paused`, `paused→active`, `active→completed`, `active→cancelled`, `paused→cancelled` |
| **Campos obrigatórios** | `case_id`, `medication_name`, `dose` (structured), `schedule` (structured), `start_date`, `recorded_by`, `professional`, `source_document`, `status`, `schema_version` |
| **Campos opcionais** | `end_date`, `duration_days`, `instructions`, `dosage_display`, `frequency_display`, `paused_at`, `pause_reason`, `completed_at`, `cancelled_at`, `cancel_reason` |
| **Valores derivados** | `doses_administered`, `doses_remaining`, `next_dose_at`, `adherence_percent` |
| **Dados sensíveis** | Professional identity é PII |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` (quem transcreveu) |
| **Profissional** | `professional: ProfessionalIdentity` (quem prescreveu — externo) |
| **Auditoria** | Mudanças de status registradas como ClinicalEvent; derivados por Function |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

**Dose estruturada (bloco `dose`):**

```
dose: {
  value: number,          // ex: 10
  unit: string,           // ex: "mg", "ml", "comprimido"
  per_kg: bool,           // se true, value e por kg de peso
  route: string           // oral, topical, injectable, inhalation, ophthalmic, otic
}
```

**Schedule estruturado (bloco `schedule`):**

```
schedule: {
  type: string,           // "interval" | "fixed_times" | "prn"
  interval_minutes: number,   // se type=interval (ex: 720 = 12h)
  times_of_day: string[],     // se type=fixed_times (ex: ["08:00", "20:00"])
  timezone: string,           // ex: "America/Sao_Paulo"
  tolerance_minutes: number   // janela aceitavel (ex: 30)
}
```

**Campos de apresentação (legacy/display):**
- `dosage_display`: string formatada para exibição (ex: "10mg/kg")
- `frequency_display`: string formatada para exibição (ex: "BID", "q12h")
- Estes campos são para apresentação e compatibilidade; o bloco estruturado é canônico

---

### 2.5 DoseAdministration

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registra a administração individual de uma dose do protocolo |
| **Identificador** | `{dogId}/treatment_protocols/{protocolId}/doses/{doseId}` — UUID |
| **Invariantes** | (1) Pertence a exatamente um protocolo. (2) `administered_at` não pode ser futuro. (3) Uma vez registrada, não pode ser deletada. (4) Garantia de unicidade via `doseId = hash(protocolId + planned_dose_id)` (ID determinístico + criação idempotente/transacional). |
| **Estados** | `administered`, `skipped`, `cancelled` |
| **Transições** | Criação direta no estado final (não há rascunho para dose) |
| **Campos obrigatórios** | `planned_dose_id`, `schedule_item_id`, `idempotency_key`, `scheduled_for`, `status`, `recorded_by`, `recorded_at`, `schema_version` |
| **Campos opcionais** | `administered_at` (se administered), `administered_by` (quem deu a dose, se diferente de quem registrou), `skip_reason`, `observations`, `side_effects`, `attachment_refs` |
| **Valores derivados** | `is_late` (administered_at > scheduled_for + tolerância) |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` (quem digitou no sistema) |
| **Administrador** | `administered_by: RecordedBy { uid, name, internal_role }` (quem efetivamente deu a dose — apenas se diferente de recorded_by) |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

**Idempotência:**
- `doseId = hash(protocolId + planned_dose_id)` é o contrato canônico determinístico, derivado apenas desses dois valores, sem data nem timestamp de relógio.
- `idempotency_key` é campo de **rastreabilidade** que repete o mesmo valor determinístico de `doseId` — não inclui `date`, `YYYYMMDD` nem timestamp de relógio.
- A garantia de unicidade vem do ID determinístico (criação de documento com `doseId` conhecido) ou de create transacional/idempotente. **Não** vem de `idempotency_key` em si.
- Firestore não oferece constraint `unique` em índice; portanto ID determinístico é o mecanismo.

---

### 2.6 WeightAssessment

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registro canônico de pesagem com escore corporal e contexto |
| **Identificador** | `{dogId}/weight_records/{id}` — UUID |
| **Invariantes** | (1) `weight_kg` > 0. (2) `measured_at` não pode ser futuro. (3) Pode existir sem caso clínico. |
| **Estados** | Nenhum estado além de soft delete |
| **Campos obrigatórios** | `weight_kg`, `measured_at`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `bcs` (body condition score 1-9), `context` (enum: routine, clinical, pre_op, post_op), `notes`, `attachment_refs`, `case_id`, `ideal_weight_min`, `ideal_weight_max`, `legacy_source`, `legacy_id` |
| **Valores derivados** | `delta_from_previous`, `within_ideal_range` |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` |
| **Auditoria** | Append-only |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

---

### 2.7 NutritionPlan

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Plano alimentar vigente definido pela Web, executado pelo Mobile |
| **Identificador** | `{dogId}/nutrition_plans/{id}` — UUID |
| **Invariantes** | (1) Apenas Web pode criar/editar. (2) Apenas um plano pode estar `active` por vez. (3) Ao ativar novo, o anterior vira `superseded`. |
| **Estados** | `active`, `superseded`, `cancelled` |
| **Transições** | `active→superseded` (quando novo plano ativa), `active→cancelled` |
| **Campos obrigatórios** | `food_type`, `amount_grams_per_day`, `meals_per_day`, `vigent_from`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `vigent_until`, `hydration_ml`, `special_instructions`, `professional`, `source_document`, `attachment_refs`, `legacy_source`, `legacy_id` |
| **Valores derivados** | `amount_per_meal` (total / meals_per_day), `is_current` |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` (admin Web) |
| **Auditoria** | Versionamento por documento (novo plano não edita o anterior) |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

---

### 2.8 MealLog

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registro de refeição executada pelo condutor |
| **Identificador** | `{dogId}/meal_logs/{id}` — UUID |
| **Invariantes** | (1) `fed_at` não pode ser futuro. (2) `amount_grams` > 0. (3) Pode referenciar plano vigente no momento. |
| **Estados** | Nenhum estado além de soft delete |
| **Campos obrigatórios** | `period` (enum: morning, afternoon, evening, night, extra), `amount_grams`, `fed_at`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `plan_id`, `prescription_amount_at_time`, `divergence_percent`, `divergence_reason`, `attachment_refs`, `observations`, `legacy_source`, `legacy_id` |
| **Valores derivados** | `is_conforming` (divergence < threshold) |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` |
| **Auditoria** | Append-only |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

---

### 2.9 SupplementLog

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registro de administração de suplemento |
| **Identificador** | `{dogId}/supplement_logs/{id}` — UUID |
| **Invariantes** | (1) Deve referenciar um suplemento conhecido (nome + dose). (2) `administered_at` não pode ser futuro. |
| **Estados** | Nenhum estado além de soft delete |
| **Campos obrigatórios** | `supplement_name`, `dose`, `administered_at`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `notes`, `batch_number`, `protocol_id`, `legacy_source`, `legacy_id` |
| **Valores derivados** | Nenhum |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` |
| **Auditoria** | Append-only |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

---

### 2.10 HealthDocument

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Arquivo clínico (laudo, receita, atestado, imagem, PDF) com metadados |
| **Identificador** | `{dogId}/health_documents/{id}` — UUID |
| **Invariantes** | (1) `storage_path` é a identidade canônica — URL é derivada. (2) Pode existir sem caso. (3) Pode referenciar evento/caso opcionalmente. (4) Storage path imutável após criação. |
| **Estados** | Nenhum estado além de soft delete |
| **Campos obrigatórios** | `document_type` (enum), `title`, `storage_path` (caminho no Cloud Storage), `mime_type`, `recorded_by`, `uploaded_at`, `schema_version` |
| **Campos opcionais** | `case_id`, `event_id`, `exam_id`, `description`, `issuer`, `issue_date`, `expiry_date`, `file_size_bytes`, `storage_url` (derivado, cache), `legacy_source`, `legacy_id` |
| **Valores derivados** | `is_expired`, `url` (derivada de storage_path) |
| **Dados sensíveis** | O arquivo pode conter dados sensíveis — acesso controlado por Storage Rules |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` |
| **Auditoria** | Soft delete com razão; metadados de upload imutáveis |
| **Soft delete** | `deleted_at`, `deleted_by`, `delete_reason` |

**Enum `document_type`:** `prescription`, `report`, `certificate`, `exam_image`, `exam_pdf`, `photo`, `vaccination_card`, `surgical_report`, `other`

**`storage_path` vs `storage_url`:**
- `storage_path` é a identidade canônica (ex: `dogs/dog_001/health/doc_xyz.pdf`)
- `storage_url` é derivado via Storage API; pode ser cache para performance mas nunca é fonte
- Alterações de bucket/CDN não invalidam o documento — apenas o derivado URL

---

### 2.11 OperationalRestriction

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Restrição clínica ativa que afeta a prontidão operacional do K9 |
| **Identificador** | `{dogId}/operational_restrictions/{id}` — UUID |
| **Invariantes** | (1) Requer evidence profissional para emissão. (2) Restrição `absolute` + `active` = K9 `temporarily_unfit`. (3) Encerramento requer justificativa. (4) Não pode ser deletada, apenas encerrada. |
| **Estados** | `active`, `ended`, `cancelled` |
| **Transições** | `active→ended` (com justificativa), `active→cancelled` (erro administrativo) |
| **Campos obrigatórios** | `level` (enum: absolute, partial, attention), `category` (enum), `description`, `issued_at`, `recorded_by`, `professional`, `source_document`, `status`, `schema_version` |
| **Campos opcionais** | `activities_restricted`, `expected_end`, `actual_end`, `ended_by`, `end_professional`, `end_source_document`, `end_reason`, `evidence`, `case_id`, `event_id`, `exam_id` |
| **Valores derivados** | `is_overdue` (expected_end passado e ainda active) |
| **Dados sensíveis** | Justificativa clínica + professional identity — acesso por capability |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` (usuário interno autorizado que transcreveu a decisão do profissional externo) |
| **Profissional** | `professional: ProfessionalIdentity { name, registration_type, registration_number, clinic, specialty? }` — quem emitiu a restrição externamente |
| **Auditoria** | Append-only; transições via Function |
| **Soft delete** | Status=cancelled, não há hard delete |

---

### 2.12 HealthScheduleItem (aggregate canônico)

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Item de agenda preventiva ou terapêutica (próxima dose, vacina, pesagem, consulta) — agregado canônico persistente |
| **Identificador** | `{dogId}/health_schedule/{scheduleId}` — UUID |
| **Invariantes** | (1) `scheduled_for` deve ser presente ou futuro na criação. (2) Item `completed` não volta a estado anterior. (3) Pode ser criado por Function (automático) ou condutor/admin (manual). |
| **Estados (persisted)** | `lifecycle_status: open \| completed \| cancelled` |
| **Estados temporais (derived at read time)** | `scheduled`, `upcoming` (≤N dias), `today`, `pending` (no horário), `overdue` (atrasado) — NUNCA persistidos, calculados no momento da leitura |
| **Transições** | `open→completed` (manual ou automático), `open→cancelled`, terminal em ambos os casos |
| **Campos obrigatórios** | `schedule_type` (enum), `title`, `scheduled_for`, `timezone`, `lifecycle_status`, `source_type`, `created_at`, `recorded_by`, `schema_version` |
| **Campos opcionais** | `due_until`, `completed_at`, `completed_by: RecordedBy`, `cancelled_at`, `cancelled_by: RecordedBy`, `cancel_reason`, `source_id`, `case_id`, `notes`, `recurrence_rule` |
| **Valores derivados (read-time)** | `temporal_state`, `minutes_until_due`, `is_overdue` |
| **Dados sensíveis** | Nenhum |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` ou `"system"` |
| **Auditoria** | Transição de lifecycle_status registrada em campos próprios (completed_*, cancelled_*) |

**Separação lifecycle vs temporal:**
- `lifecycle_status` é o estado persistido do item (open/completed/cancelled).
- Estados temporais (`scheduled`, `upcoming`, `today`, `pending`, `overdue`) são DERIVADOS no momento da leitura, baseados em `scheduled_for`, `due_until` (quando presente) e `current_time`. **Nenhum desses estados é persistido como campo no documento.**
- A UI/cliente calcula o `temporal_state` localmente. Nenhuma Function reescreve o documento apenas porque o tempo passou.
- Timezone é obrigatório e armazenado no próprio item; toda derivação usa esse timezone.
- Quando `due_until` está ausente, a tolerância é definida por configuração por `schedule_type` — sem default universal.

**Data efetiva única (regra absoluta para evitar contradições entre estados derivados):**

```text
effective_due_until =
  due_until
  ?? resolveTolerance(schedule_type, scheduled_for, timezone)
```

Quando `due_until` estiver ausente, a tolerância **deve** ser resolvida por configuração por `schedule_type`. Não há default universal. Para cada `schedule_type` ativo deve existir configuração válida de tolerância.

**Precedência da derivação temporal (avaliada na ordem; primeira condição verdadeira vence):**

1. `lifecycle_status == "completed"` → `completed` (terminal)
2. `lifecycle_status == "cancelled"` → `cancelled` (terminal)
3. `now > effective_due_until` → `overdue`
4. `now >= scheduled_for` → `pending`
5. `scheduled_for` é hoje (mesma data no timezone do item) → `today`
6. item dentro da janela próxima (≤ N dias, configurável por `schedule_type`) → `upcoming`
7. restante → `scheduled`

A regra é única e absoluta: o primeiro caso verdadeiro vence. Não há caso em que o mesmo item seja classificado simultaneamente como `pending` e `overdue`. A derivação é pura, sem efeito colateral, e ocorre no momento da renderização.

**Enum `schedule_type`:** `dose`, `vaccination`, `exam`, `consultation`, `weighing`, `reevaluation`, `deworming`, `bath`, `general`

**Enum `source_type`:** `treatment_protocol`, `clinical_case`, `exam_process`, `preventive`, `manual`

---

### 2.13 LegacyHealthRecord (read-only para clientes)

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Preservar dados migrados do schema anterior em formato raw, com view normalizada opcional |
| **Identificador** | `{dogId}/legacy_health_records/{recordId}` — UUID determinístico de migração |
| **Invariantes** | (1) Read-only para clientes. (2) `original_payload` sempre imutável. (3) Admin SDK auditado pode atualizar somente `normalized_view`, `case_id` e metadados administrativos/de reconciliação. (4) Pode opcionalmente linkar a um caso via `case_id`. |
| **Estados** | Nenhum |
| **Campos obrigatórios** | `original_collection`, `original_id`, `original_payload`, `migration_batch_id`, `migrated_at`, `schema_version` |
| **Campos opcionais** | `normalized_view` (mapeamento tentativo para novos modelos), `case_id` (linkagem manual), `dog_id`, `occurred_at` (extraído), `recorded_by` (extraído quando possível) |
| **Dados sensíveis** | Preserva PII do schema original — acesso controlado |
| **Autoria** | Não aplicável (origem é sistema legado) |
| **Auditoria** | `migration_batch_id` aponta para registro de migração |

**View normalizada:**
- `normalized_view` é uma tentativa de mapear o registro legacy para os novos modelos
- É best-effort — pode estar incompleto ou impreciso
- A UI mostra o registro legacy com badge "Migrado" e link para `original_payload`

**Integração com timeline:**
- LegacyHealthRecord aparece na HealthTimeline quando tem `occurred_at` extraído
- `case_id` é opcional — registros sem vínculo confirmado aparecem na timeline geral
- Linkagem manual permite adicionar a um caso posteriormente

**Regras de escrita:**

- `original_payload` é **sempre imutável**.
- Clientes (Mobile, Web) possuem apenas permissão de **read**.
- Admin SDK pode atualizar, de forma auditada: `normalized_view`, `case_id`, `migrated_at`, metadados de reconciliação, e metadados de batch.
- Após cutover do agregado correspondente, writes em Rules são bloqueados para clientes; Admin SDK continua permitido para fins administrativos auditados.
- Resumo: **read-only para clientes**; `original_payload` sempre imutável; **updates administrativos limitados** via Admin SDK auditado. Não há afirmação absoluta de "nenhum write após o backfill" — há permissões controladas (Admin SDK auditado).

---

### 2.14 ReadinessSnapshot (projeção)

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Projeção consolidada do estado de prontidão operacional do K9 (health_summary) |
| **Identificador** | `{dogId}/health_summary/current` — documento singleton |
| **Invariantes** | (1) Writable apenas por backend. (2) Sempre reflete o estado mais recente das restrições. (3) Nunca é fonte canônica — é derivado. |
| **Estados** | N/A (é uma projeção, não tem ciclo de vida próprio) |
| **Transições** | N/A |
| **Campos obrigatórios** | `readiness_status`, `readiness_updated_at`, `evaluated_by`, `schema_version` |
| **Campos opcionais** | Todos os indicadores consolidados (ver ADR-004 e ADR-005) |
| **Valores derivados** | Tudo é derivado |
| **Dados sensíveis** | Resumo de restrições (nível, sem detalhes clínicos completos) |
| **Autoria** | `evaluated_by: "function_v1"` |
| **Auditoria** | `readiness_history` pode manter versões anteriores (futuro) |

---

## 3. Projeções (read-only para clientes)

Apenas duas projeções são definidas no v1.0:

### 3.1 HealthTimeline

Ver HEALTH_V1_FIRESTORE_SCHEMA.md §3.1 para detalhes completos.

### 3.2 ReadinessSnapshot (= health_summary)

Ver §2.14 acima.

---

## 4. Matriz de responsabilidade

> **Mapeamento provisório:** a atribuição capability → perfil real (`condutor`/`admin`) é questão aberta **O1** do Foundation Review e será resolvida na Fase 1B após inventário do modelo de perfis real. As colunas "Executor interno" abaixo listam **executores candidatos** (não atribuições aprovadas). Ajustes devem ser feitos após o inventário.

| Entidade | Origem | Executor interno (candidato) | Profissional envolvido | Mobile cria | Mobile lê | Web cria | Web lê | Timeline | Agenda | Prontidão |
|----------|--------|------------------------------|------------------------|-------------|-----------|----------|--------|----------|--------|-----------|
| ClinicalCase | Evento de abertura | condutor (intercorrência) [prov.], admin [prov.] | pode ter | ✅ | ✅ | ✅ | ✅ | Indiretamente | Via eventos | Via restrições |
| ClinicalEvent | Registro direto | condutor [prov.] | pode ter | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | Indiretamente |
| ExamProcess | Etapas tipadas | condutor [prov.] | pode ter | ✅ | ✅ | ✅ | ✅ | ✅ (cada etapa) | ✅ (pendentes) | ✅ (resultado pode gerar restrição) |
| TreatmentProtocol | Web transcreve | admin [prov.] | obrigatório | ❌ | ✅ | ✅ | ✅ | ✅ (início/fim) | ✅ (doses) | ✅ (restrição se aplicável) |
| DoseAdministration | Mobile executa | condutor [prov.] | não | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ (próxima) | ❌ |
| WeightAssessment | Mobile registra | condutor [prov.] | não | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ (próxima pesagem) | ✅ (dados de completude) |
| NutritionPlan | Web define | admin [prov.] | pode ter | ❌ | ✅ | ✅ | ✅ | ✅ (ativação) | ❌ | ✅ (dados de completude) |
| MealLog | Mobile executa | condutor [prov.] | não | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| SupplementLog | Mobile executa | condutor [prov.] | não | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| HealthDocument | Mobile/Web upload | condutor [prov.], admin [prov.] | não (mas pode referenciar) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| OperationalRestriction | Transcrição de profissional | condutor [prov.], admin [prov.] | obrigatório | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (reavaliação) | ✅✅ (fonte primária) |
| HealthScheduleItem | Function + manual | condutor (manual) [prov.] | não | ✅ (manual) | ✅ | ✅ | ✅ | ❌ | ✅✅ (é a agenda) | ✅ (pendências) |
| VaccinationRecord | Aplicação preventiva | condutor [prov.], admin [prov.] | pode ter (externo) | ✅ | ✅ | ✅ | ✅ | ✅ (vacinação) | ✅ (próxima dose) | ✅ (vacinação vigente) |
| LegacyHealthRecord | Migração | — (Admin SDK apenas) | preserva do legacy | ❌ | ✅ | ❌ | ✅ | ✅ (read-only) | ❌ | ❌ |
| ReadinessSnapshot | Function | — | — | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅✅ (é o snapshot) |

> Nota: "Web transcreve" significa que admin (executor candidato) via Web registra decisão clínica externa do profissional — admin é o executor técnico, não o decisor clínico. Todas as atribuições `condutor`/`admin` acima são provisórias (Fase 1B — O1).

---

## 5. Value Objects compartilhados

| Value Object | Campos | Usado em |
|-------------|--------|----------|
| **RecordedBy** (rename de Actor) | `uid`, `name`, `internal_role` | Todas as entidades (autoria) |
| **ProfessionalIdentity** (rename de Professional) | `name`, `registration_type`, `registration_number`, `clinic` | ClinicalCase, ClinicalEvent, ExamProcess, TreatmentProtocol, NutritionPlan, OperationalRestriction |
| **OperationalImpact** | `level` (none/low/medium/high/critical), `description`, `restrictions_issued` | ClinicalEvent, ExamProcess (estágio impact_assessed) |
| **HealthDocumentRef** | `health_document_id`, `description` | ClinicalEvent (attachment_refs), outras entidades (source_document) |
| **Evidence** | `case_id`, `event_id`, `exam_id`, `description` | OperationalRestriction |
| **LegacyRef** | `legacy_source`, `legacy_id`, `legacy_collection`, `migration_batch_id`, `migration_checksum` | Todas (quando migrado) |
| **DoseBlock** | `value`, `unit`, `per_kg`, `route` | TreatmentProtocol |
| **ScheduleBlock** | `type`, `interval_minutes`, `times_of_day`, `timezone`, `tolerance_minutes` | TreatmentProtocol |
| **AuditEntry** | `action`, `recorded_by`, `at`, `details` | Entidades com audit_trail |

---

## 6. Enums do domínio

| Enum | Valores | Propósito |
|------|---------|-----------|
| `ClinicalCaseStatus` | open, under_investigation, under_treatment, monitoring, discharged, cancelled | Estado do caso (sem "reopened") |
| `ClinicalEventStatus` | draft, final, cancelled | Estado do evento (sem "amended" — gerenciado via metadados) |
| `ClinicalEventType` | consultation, incident, vaccination, exam_request, exam_collection, exam_result, exam_interpretation, treatment_start, treatment_note, dose_note, reevaluation, discharge, reopen, restriction_issued, restriction_ended, surgical_note, general_note, observation | Tipo do evento. `vaccination` é permitido apenas quando há relevância clínica dentro de um caso (referencia `vaccination_record_id`); o registro canônico está em VaccinationRecord. |
| `ExamStage` | requested, collected, resulted, interpreted, impact_assessed, cancelled | Estágio do exame |
| `ExamType` | blood_work, imaging, biopsy, culture, parasitology, urinalysis, cardiology, dermatology, ophthalmology, other | Tipo do exame |
| `TreatmentStatus` | active, paused, completed, cancelled | Estado do protocolo |
| `DoseStatus` | administered, skipped, cancelled | Estado da dose |
| `RestrictionLevel` | absolute, partial, attention | Nível de impacto |
| `RestrictionCategory` | injury, post_surgical, medication_effect, behavioral, infectious, chronic, preventive_pending, other | Categoria |
| `ReadinessStatus` | operational, operational_attention, fit_with_restrictions, temporarily_unfit, not_evaluated | Prontidão |
| `ScheduleLifecycleStatus` | open, completed, cancelled | Lifecycle do item (persisted) |
| `ScheduleType` | dose, vaccination, exam, consultation, weighing, reevaluation, deworming, bath, general | Tipo de agendamento |
| `ScheduleSourceType` | treatment_protocol, clinical_case, exam_process, preventive, manual | Origem do item |
| `DocumentType` | prescription, report, certificate, exam_image, exam_pdf, photo, vaccination_card, surgical_report, other | Tipo de documento |
| `MealPeriod` | morning, afternoon, evening, night, extra | Período da refeição |
| `WeightContext` | routine, clinical, pre_op, post_op | Contexto da pesagem |
| `AmendmentType` | correction, addendum, complement | Tipo de adendo |
| `OpeningType` | incident, consultation, preventive, administrative | Abertura do caso |
| `ClosureType` | discharge, cancelled, administrative | Encerramento do caso |
| `ProfessionalRegistrationType` | CRMV, CRMV-Z, CRN, CRF, CFMV, other | Tipo de registro profissional |
| `DoseRoute` | oral, topical, injectable_subcutaneous, injectable_intramuscular, injectable_intravenous, inhalation, ophthalmic, otic, nasal | Via de administração |
| `DoseUnit` | mg, ml, mcg, g, kg, ui, comprimido, gota, scoop, other | Unidade de dose |
| `ScheduleTypeBlock` | interval, fixed_times, prn | Tipo de schedule estruturado |
| `PayloadType` | consultation_v1, incident_v1, vaccination_v1, exam_request_v1, exam_collection_v1, exam_result_v1, exam_interpretation_v1, treatment_start_v1, treatment_note_v1, dose_note_v1, reevaluation_v1, discharge_v1, reopen_v1, restriction_issued_v1, restriction_ended_v1, surgical_note_v1, general_note_v1, observation_v1 | Tipo de payload do evento (versionado) |
| `InternalRole` | condutor, admin | Role do usuário interno |
| `VaccinationStatus` | final, cancelled | Estado de VaccinationRecord (apenas dois valores persistidos — estados temporais vivem em HealthScheduleItem) |

---

## 7. VaccinationRecord (13º agregado canônico)

| Aspecto | Definição |
|---------|-----------|
| **Responsabilidade** | Registro canônico de vacinação **efetivamente aplicada** do K9. Representa fato, não planejamento. Calendário de próximas doses vive em `HealthScheduleItem`. |
| **Identificador** | `dogs/{dogId}/vaccination_records/{vaccinationId}` — UUID (legado migrado usa ID determinístico). |
| **Invariantes** | (1) Pode existir sem `ClinicalCase`. (2) Quando há relevância clínica dentro de um caso (ex: reação adversa), pode referenciar `case_id` opcionalmente — mas isso **não** torna a vacinação um evento do caso. (3) Vacinação registrada em VaccinationRecord **não cria** ClinicalCase automaticamente. (4) Aplicação registrada cria um `HealthScheduleItem` (schedule_type: vaccination) para a próxima dose. (5) Vacinação também gera entrada na `HealthTimeline` (projeção). (6) `VaccinationRecord` representa fato registrado — estados temporais (`scheduled`, `today`, `upcoming`, `pending`, `overdue`) **não** são persistidos aqui. |
| **Estados persistidos** | `record_status: final \| cancelled` — apenas dois valores. Não há `scheduled` nem `overdue` em `VaccinationRecord`. |
| **Transições** | `final → cancelled` (com `cancelled_at`, `cancelled_by`, `cancel_reason` obrigatórios). Não há criação em `scheduled` — o item futuro de vacinação pertence exclusivamente a `HealthScheduleItem` e vira `VaccinationRecord` somente quando a aplicação é registrada. |
| **Campos obrigatórios** | `vaccine_name`, `applied_at`, `recorded_by`, `record_status`, `schema_version` |
| **Campos opcionais** | `vaccine_type`, `manufacturer`, `batch_number`, `dose`, `administered_by` (RecordedBy), `next_due_at`, `validity_until`, `case_id` (opcional, somente quando há reação adversa ou vínculo terapêutico), `source_document`, `legacy_source`, `legacy_id`, `notes` |
| **Valores derivados** | `is_overdue` (calculado a partir do `HealthScheduleItem` correspondente; **não** persistido em `VaccinationRecord`) |
| **Dados sensíveis** | PII: nome do profissional externo quando aplicável (registrado em `ProfessionalIdentity`). |
| **Autoria** | `recorded_by: RecordedBy { uid, name, internal_role }` — usuário interno que registra a aplicação. |
| **Profissional** | Quando a aplicação é externa: `professional: ProfessionalIdentity` (quem aplicou ou supervisionou). Quando a aplicação foi execução interna devidamente autorizada: `professional: null`. |
| **Auditoria** | Cada transição registra timestamp e `recorded_by`. |
| **Soft delete** | Via `record_status: cancelled` com `cancel_reason` obrigatório. |

**Distinção canônica em relação a ClinicalEvent:**

- `VaccinationRecord` é a **fonte canônica** de toda vacinação **efetivamente registrada** do K9.
- `ClinicalEvent` do tipo `vaccination` existe **somente** quando a vacinação tem relevância clínica dentro de um caso (ex: reação adversa, complicação). Esse evento referencia o `vaccination_record_id` original, mas o registro canônico permanece em VaccinationRecord.
- A prontidão (ADR-005) lê vacinação vigente a partir de `vaccination_records`, **não** de `clinical_cases/events`.

**Relação com demais agregados:**

- VaccinationRecord gera entrada na HealthTimeline (`timeline_type: vaccination`).
- VaccinationRecord gera `HealthScheduleItem` (schedule_type: vaccination) para próxima dose.
- VaccinationRecord **não** cria ClinicalCase.
- OperationalRestriction originada em evento adverso pode referenciar o VaccinationRecord (via `evidence.vaccination_record_id`).

**Migração:**

- Vacinas legadas com dados suficientes (nome, data, profissional) migram para VaccinationRecord com `migration_batch_id`.
- Registros incompletos permanecem em `legacy_health_records` (read-only).
- Vacinas legadas **não** são backfiladas para `clinical_cases/events` nem para "caso preventivo".

---

## 8. Regras de negócio (invariantes globais)

1. **Imutabilidade clínica:** evento `final` nunca tem `content` alterado; correções são adendos. Status permanece `final` mesmo com amendments — metadados `has_amendments`, `amendment_count`, `last_amended_at` indicam existência.
2. **Restrição absoluta prevalece:** se existe qualquer restrição `absolute` + `active`, prontidão = `temporarily_unfit`.
3. **Web transcreve decisões clínicas:** TreatmentProtocol, NutritionPlan, OperationalRestriction são criados pela Web com evidence profissional.
4. **Mobile executa:** DoseAdministration, WeightAssessment, MealLog são criados pelo Mobile.
5. **Nenhum hard delete:** todas as entidades usam soft delete com justificativa.
6. **Auditoria obrigatória:** toda entidade possui `recorded_by` e timestamps server-side.
7. **Um plano ativo por vez:** ao ativar novo NutritionPlan, anterior vira `superseded`.
8. **Caso não obrigatório para rotina:** WeightAssessment, MealLog, SupplementLog existem sem caso.
9. **Projeções não são editáveis:** HealthTimeline e ReadinessSnapshot são read-only para clientes.
10. **Timestamps:** `occurred_at` (fato), `recorded_at` (server_time).
11. **Profissional é externo:** Nenhum profissional externo (veterinário, nutricionista, etc.) possui conta no sistema. Profissionais são identificados nos registros via `ProfessionalIdentity`. Toda ação clínica é registrada por um usuário interno com a capability correspondente, com identificação do profissional externo responsável. Não existe custom claim de role para profissional.
12. **Executor ≠ decisor:** `recorded_by` é quem digitou; `professional` é quem decidiu (PII).
13. **Schedule temporal derivado:** estados temporais (scheduled/upcoming/today/pending/overdue) são calculados no momento da leitura; apenas `lifecycle_status` é persistido. **Nenhum campo temporal é persistido — jamais.**
14. **Exam próprio agregado:** ExamProcess é uma subcoleção com estado; ClinicalEvent registra as transições.
15. **Attachments por referência:** ClinicalEvent armazena apenas `attachment_refs` (IDs); URL derivada de HealthDocument.storage_path.
16. **Payloads versionados:** cada evento tem `payload_type` e `payload_version`. Dados brutos legados permanecem exclusivamente em `LegacyHealthRecord.original_payload`; eventual evento curado usa payload tipado normal e referência de proveniência.
17. **Reabertura é ação, não estado:** `reopened` foi removido — reabertura atualiza `reopened_*` fields e muda status.
18. **VaccinationRecord é o 13º agregado canônico:** toda vacinação preventiva é registrada em `dogs/{dogId}/vaccination_records/{vaccinationId}`. ClinicalEvent do tipo `vaccination` só existe quando há relevância clínica dentro de um caso. VaccinationRecord não cria ClinicalCase automaticamente.
19. **Idempotência de dose:** `doseId = hash(protocolId + planned_dose_id)` é o contrato canônico. O campo `idempotency_key` repete esse valor determinístico para rastreabilidade — **não** inclui data, `YYYYMMDD`, timestamp de relógio, nem é descrito como a garantia principal. A garantia de unicidade vem do ID determinístico ou de create transacional/idempotente.
20. **PII do profissional — limitação do Firestore:** Firestore não oferece leitura por campo dentro do documento (Security Rules operam no nível do documento). Para o v1, todo usuário interno com `health.read` pode ler `ProfessionalIdentity` quando esse campo está no registro. Restrições por perfil a campos específicos (ex: ocultar apenas `crmv` ou `clinic`) exigem mover esses campos para subcoleção privada separada — fora do escopo do v1.
21. **`clinical_status` muda por ações explícitas:** `clinical_status` muda somente por ações server-orchestrated e auditadas (`health.discharge_case`, `health.complete_treatment`, etc.). Não é derivado de eventos; transições são explícitas. Não há override manual arbitrário.
22. **Política offline:** display atualiza quando snapshot > 5 minutos; offline aceita snapshot ≤ 12h em modo degradado com alerta; acima de 12h exige aceite operacional auditado; `temporarily_unfit` conhecido bloqueia mesmo offline. O aceite não é override, não altera nem encerra restrição.
23. **RecordedBy padrão:** `recorded_by: { uid, name, internal_role }` em todas as entidades. Nunca usar `role` solto, `issued_by`, ou mapas diferentes por coleção.
24. **Reabertura — nomenclatura única:** `previous_status`, `reopened_count`, `reopened_at`, `reopened_by`, `reopen_reason`. Não usar `reopen_previous_status` nem `reopen_count`.

---

## 9. Templates de payload por event_type

Cada `event_type` tem um contrato versionado. Templates abaixo ilustram os campos mínimos:

### 9.1 consultation_v1 (payload_type)
```
content: {
  chief_complaint: string,
  examination_findings: string,
  diagnosis: string,
  plan: string,
  ...
}
```

### 9.2 incident_v1
```
content: {
  description: string,
  observed_context: string,
  initial_action_taken: string,
  ...
}
```

### 9.3 exam_request_v1
```
content: {
  exam_type: ExamType,
  urgency: "routine" | "urgent" | "stat",
  clinical_indication: string,
  ...
}
```

### 9.4 treatment_start_v1
```
content: {
  protocol_id: string,    // ref para TreatmentProtocol criado
  start_context: string,
  ...
}
```

### 9.5 reopen_v1
```
content: {
  reopen_reason: string,
  destination_status: "open" | "under_investigation" | "under_treatment" | "monitoring",
  recorded_by: RecordedBy,
  professional: ProfessionalIdentity?, // obrigatório quando decisão clínica externa
  source_document: SourceDocumentRef?  // obrigatório quando decisão clínica externa
}
```
