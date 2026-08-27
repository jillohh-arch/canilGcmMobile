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
│   ├── clinical_events/{eventId}
│   │   └── clinical_amendments/{amendId}
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

### 1.1 CLIN-WRITER-1.W1b — nomes canônicos das subcoleções clínicas (CONGELADO)

As subcoleções aninhadas do prontuário foram renomeadas para eliminar colisão de
collection-group:

```
ANTES: dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}
       dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}/amendments/{amendId}

AGORA: dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}
       dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}/clinical_amendments/{amendId}
```

Motivo factual: `collectionGroup("events")` já abrange **três** árvores
(`vehicles/{id}/events`, `occurrences/{id}/events`, prontuário) e
`collectionGroup("amendments")` já colide com `occurrences/{id}/amendments`. Um
collection-group clínico futuro seria impossível de gatear sem contaminar
Ocorrências e Viaturas.

**Nenhum alias antigo é retido.** Os paths `/events` e `/amendments` sob
`clinical_cases` deixam de existir no contrato. Não há migração de dados: não
existe nenhum writer canônico e não existe nenhum documento clínico canônico em
produção.

O nome de collection-group `clinical_events` também aparece como *rótulo de
proveniência* da projeção de timeline (`dogs/{dogId}/clinical_events`, string em
`functions/src/health_timeline_projection.ts`). Esse rótulo é **plano e legado ao
contrato**, não corresponde a nenhuma coleção real, e sua correção pertence ao
gate de projeção — não a este gate. Nenhum índice de collection-group clínico é
criado aqui.

### 1.2 Fronteira de escrita do cliente (CONGELADA)

```
ESCRITAS DE CLIENTE NO PRONTUÁRIO CANÔNICO
create = DENY
update = DENY
delete = DENY
PERMANENTEMENTE
```

Toda mutação clínica canônica é de **backend, Admin SDK**. Capabilities
autorizam **comandos callable**, nunca escrita direta de cliente no Firestore:
nenhuma permissão condicional de escrita de cliente será adicionada para
capability futura.

A **leitura** permanece exatamente como congelada pelos gates de leitura
clínica: `health.read` + `canAccessDogRecord(dogId)` estrutural do path, **sem
bypass admin**. Este gate não altera nenhuma semântica de autorização de
leitura.

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
| reopen_reason | string | ❌ | **HISTÓRICO** — motivo da última reabertura (§2.1.1) |
| reopened_at | timestamp | ❌ | **HISTÓRICO** — instante da última reabertura (§2.1.1) |
| reopened_by | RecordedBy | ❌ | **HISTÓRICO** — ator da última reabertura (§2.1.1) |
| previous_status | string | ❌ | **HISTÓRICO** — status imediatamente anterior à última reabertura; sempre `discharged` (§2.1.1) |
| reopened_count | number | ❌ | **HISTÓRICO / CUMULATIVO** — total de reaberturas bem-sucedidas; default 0; nunca reiniciado (§2.1.1) |
| recurrence_of_case_id | string | ❌ | Ref a caso anterior |
| related_case_ids | array of string | ❌ | Refs a casos relacionados |
| has_active_restriction | bool | ❌ | Derivado por Function |
| has_pending_schedule | bool | ❌ | Derivado por Function |
| active_treatments_count | number | ❌ | Derivado por Function |
| last_event_at | timestamp | ❌ | Derivado |
| updated_at | timestamp | ✅ | **METADADO TEMPORAL** apenas (SERVER; §2.1.2). NÃO é token de concorrência |
| revision | number | ✅ | **Token canônico de concorrência otimista** (SERVER; inteiro `>= 1`; nasce em 1; §2.1.2) |
| event_count | number | ❌ | Derivado |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | Se migrado |
| schema_version | number | ✅ | Atual: 1 |

**Escritor:** Mobile (abertura por intercorrência), Web (abertura por consulta/admin), Function (flags derivados).
**Leitor:** Mobile, Web.
**Índices:** `clinical_status ASC, opened_at DESC`; `clinical_status ASC, last_event_at DESC`.

#### 2.1.1 História de reabertura vs. fechamento atual (CONGELADO — CLIN-WRITER-1.W6.P0.D1)

Os dois grupos de metadados do ClinicalCase têm significados **diferentes** e não
devem ser confundidos:

```
reopened_at / reopened_by / reopen_reason / previous_status / reopened_count
  = HISTÓRICO da ÚLTIMA reabertura + contagem acumulada

closed_at / closed_by / closure_type / closure_reason
  = estado de fechamento ATUAL do caso
```

**A tupla de reabertura é histórica.** Sua consistência **não** depende do
`clinical_status` atual. Um caso reaberto e depois novamente encerrado
(`discharged`) ou cancelado (`cancelled`) **preserva** a tupla e o
`reopened_count`. Se o status atual participasse dessa validação, a história
lícita `discharge → reopen → discharge` seria irrepresentável — e não existe
caminho para limpar a tupla, porque `reopened_count > 0` sem tupla também é
inconsistente.

Invariantes at-rest (autoridade: `ClinicalCase` em
`lib/features/health/domain/health_v1_models.dart`, espelhada por
`assertCaseReopenConsistency` em `functions/src/clinical_domain.ts`):

| Situação | Regra |
|----------|-------|
| Nunca reaberto | `reopened_count = 0` **e** os quatro campos da tupla ausentes |
| Já reaberto | `reopened_count > 0` **e** tupla completa: `reopened_at`, `reopened_by`, `reopen_reason` não vazio, `previous_status = discharged` |
| Status atual | Qualquer um dos seis valores canônicos, terminais incluídos |
| `reopened_count` | Inteiro `>= 0`, cumulativo, **nunca reiniciado** por um fechamento posterior |

Uma nova reabertura bem-sucedida **substitui** o snapshot da última reabertura e
faz `reopened_count = contagem anterior + 1`. O histórico das reaberturas
anteriores permanece nos `ClinicalEvent` imutáveis de `reopen` e no audit.

**Isto não amplia a AÇÃO de reabertura.** Continuam valendo, sem alteração:

```
REOPEN
origem:   discharged APENAS
destinos: open, under_investigation, under_treatment, monitoring
cancelled: terminal
```

São duas perguntas distintas: *"posso executar REOPEN agora?"*
(`assertCaseReopen`) e *"este caso já foi reaberto alguma vez?"*
(`assertCaseReopenConsistency`).

**Separação em relação ao fechamento.** Como `closed_*` representa o fechamento
**atual**, uma reabertura futura para estado ativo deve **DELETAR** `closed_at`,
`closed_by`, `closure_type` e `closure_reason` (deleção de campo, não `null`),
enquanto atualiza a tupla de reabertura e incrementa a contagem. Se o caso for
depois encerrado ou cancelado outra vez, novos `closed_*` são escritos e a tupla
`reopened_*` permanece **preservada**. A alta anterior não se perde: sua história
pertence ao `ClinicalEvent` imutável de alta e ao audit.

O writer de lifecycle que executa essas escritas **não** existe ainda (gate W6);
esta seção congela apenas a semântica.

#### 2.1.2 Autoridade de concorrência otimista do ClinicalCase (CONGELADO — CLIN-WRITER-1.W6.P0.F1.C1)

> **SUCESSOR.** A versão anterior desta seção (F1) declarava `updated_at` como
> autoridade de concorrência. O gate **F1.C0** provou empiricamente que um token
> de relógio de parede **não detecta obsolescência**: duas mutações bem-sucedidas
> no mesmo milissegundo deixam o token observável inalterado, e uma operação
> DISTINTA e obsoleta comparava igual a uma fresca — sendo aceita. O fato
> histórico permanece registrado aqui; a autoridade de concorrência passou a ser
> `revision`. As igualdades temporais de `updated_at` continuam válidas.

O campo `revision` é a autoridade canônica de concorrência otimista do
`ClinicalCase`. `updated_at` permanece **exclusivamente metadado temporal**.

| Operação | `revision` | `updated_at` (temporal) |
|---|---|---|
| **OPEN** (`healthOpenClinicalCase`) | nasce em `1` | `updated_at == opened_at == last_event_at` |
| **APPEND** (`healthAppendClinicalEvent`) | `anterior + 1` | `updated_at == last_event_at == appendedEvent.recorded_at` |
| **Lifecycle Mutations** (futuros writers W6) | `anterior + 1` | `updated_at == mutation server Timestamp` |
| **Replay / Idempotência** | **não avança** (idempotência avaliada ANTES do token) | preservado |
| **Operação rejeitada** | **não avança** | preservado |
| **Event-only mutations** (W4 Finalize/Cancel, W5 Amend) | não alteram `ClinicalCase`, logo **não avançam** | idem |

**Propriedades normativas de `revision`:**
- **Owner**: `SERVER` apenas (inteiro). Nunca aceito do payload do cliente.
- **Piso**: `Number.isSafeInteger(revision) && revision >= 1`. Ausente, `0`,
  negativo, fracionário, não-numérico ⇒ `failed-precondition` / `integrity`.
- **Precondição de Wire (W6)**: `expectedRevision` (inteiro seguro `>= 1`).
  Comparação `storedCase.revision === request.expectedRevision`. Divergente:
  `failed-precondition`. Ausente/malformado: `invalid-argument`.
- **Sem `FieldValue.increment`**: a revisão resultante é calculada explicitamente
  dentro da transação, para que documento, resposta, receipt e audit sejam
  provavelmente o mesmo número.
- **Overflow**: em `Number.MAX_SAFE_INTEGER` a mutação falha fechada
  (`integrity`). Sem wraparound, saturação ou float.
- **Rejeição de Autoridade Externa**: `DocumentSnapshot.updateTime` **não** é
  autoridade.
- **Nenhum retry automático**: conflito falha fechado; o chamador relê e decide.

**Divergência deliberada do Schedule.** `health_schedule_logic.readRevision`
tolera revisão ausente/legada como `0`, porque Schedule **possui** documentos
anteriores à introdução do campo. Clinical **não** possui essa população: todo
aggregate canônico nasce em `1`, logo ausência é corrupção. Aceitar `0` seria um
fail-open gratuito. Não "harmonizar" com Schedule.

**`updated_at` após o sucessor** — metadado temporal apenas:
- **não** é único;
- **não** é monotônico;
- **não** implica ordem de commit;
- **não** participa da decisão fresco/obsoleto.

---

### 2.2 clinical_cases/{caseId}/clinical_events/{eventId}

#### Identidade canônica do evento (CONGELADA — CLIN-WRITER-1.W1b)

Estes campos formam a identidade do ClinicalEvent. A coluna **Origem** é
normativa para o writer: `SERVER` significa derivado do path estrutural, da
autenticação ou do servidor, e **nunca** aceito do payload do cliente.

| Campo | Origem | Autoridade |
|-------|--------|-----------|
| dog_id | SERVER | Derivado do path estrutural `dogs/{dogId}`. Desnormalizado apenas para queryability futura; a autoridade é o path + o writer, nunca o campo. |
| case_id | SERVER | Derivado do path estrutural `clinical_cases/{caseId}` |
| event_id | SERVER | Gerado pelo servidor / determinístico pela autoridade de idempotência |
| entity_kind | SERVER | Constante server-managed, valor `clinical_event` |
| schema_version | SERVER | Server-managed |
| event_type | CLIENTE (validado) | Deve ser wire value de `ClinicalEventType` (18 valores, autoridade `functions/src/clinical_domain.ts`) |
| status | SERVER | Valor de lifecycle server-managed; transições apenas por comando (`draft`→`final`, `draft`→`cancelled`, `final`→`cancelled`) |
| occurred_at | CLIENTE (validado) | Tempo clínico da ocorrência |
| recorded_at | SERVER | Timestamp de servidor |
| recorded_by | SERVER | Derivado do chamador autenticado |

**NUNCA confiado no payload do cliente:** `dog_id`, `case_id`, `event_id`,
`entity_kind`, `schema_version`, `status`, `recorded_at`, `updated_at`,
`recorded_by`.

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| event_type | string (enum) | ✅ | Ver Domain Model §6 |
| status | string (enum) | ✅ | draft, final, cancelled (sem "amended") |
| occurred_at | timestamp | ✅ | Quando aconteceu |
| recorded_at | timestamp | ✅ | Server timestamp |
| updated_at | timestamp | ✅ | **SERVER-MANAGED. METADADO TEMPORAL apenas** — ver §2.2.1. Obrigatório em todo ClinicalEvent v1 criado pelo writer canônico; na criação vale exatamente `recorded_at`; avança a cada mutação canônica bem-sucedida. **NÃO** é token de concorrência (não é único nem monotônico). Nunca aceito do payload |
| revision | number | ✅ | **SERVER-MANAGED. Autoridade canônica de concorrência otimista** — ver §2.2.1. Inteiro seguro `>= 1`; nasce em `1` em todo caminho de criação; avança exatamente +1 por mutação canônica bem-sucedida; nunca via `FieldValue.increment`. Nunca aceito do payload |
| finalized_at | timestamp | ❌ | **SERVER-MANAGED.** Obrigatório quando `status == final`; ausente em `draft`. **Preservado imutável** se um evento `final` for posteriormente cancelado — registra o fato histórico da finalização. Ver §2.2.1 |
| finalized_by | — | — | **NÃO EXISTE no ClinicalEvent v1.** A identidade de quem finalizou é proveniência de `auditLogs` + operation receipt, nunca campo do evento. Ver §2.2.1 |
| cancelled_at | timestamp | ❌ | **SERVER-MANAGED.** Obrigatório quando `status == cancelled` |
| cancelled_by | RecordedBy | ❌ | **SERVER-DERIVED** do chamador autenticado. Obrigatório quando `status == cancelled` |
| cancel_reason | string | ❌ | Obrigatório se cancelled; validado non-blank e **trimmed** |
| recorded_by | RecordedBy | ✅ | Quem registrou no sistema |
| professional | ProfessionalIdentity | ❌ | Quem decidiu clinicamente (externo) |
| payload_type | string (enum) | ✅ | Ver Domain Model §6 |
| payload_version | number | ✅ | Versão do contrato |
| content | map | ✅ | Campos específicos por payload_type |
| operational_impact | map | ❌ | Ver OperationalImpact |
| attachment_refs | array of string | ❌ | IDs de HealthDocument (não URLs); tratado como `[]` quando ausente |
| source_document | HealthDocumentRef | ❌ | Evidência documental |
| has_amendments | bool | ✅ | **DERIVADO / SERVER-MANAGED**, default false |
| amendment_count | number | ✅ | **DERIVADO / SERVER-MANAGED**, default 0 |
| last_amended_at | timestamp | ❌ | **DERIVADO / SERVER-MANAGED** |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | Se migrado |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** **Backend Admin SDK, exclusivamente** (CLIN-WRITER-1.W1b). Cliente
Mobile/Web tem `create, update, delete: if false` — permanentemente. A descrição
anterior ("Mobile/Web create, update draft") descrevia intenção de contrato antes
de existir autoridade de writer e **não** é a fronteira vigente.
**Leitor:** Mobile, Web — via `health.read` + acesso estrutural ao K9, sem bypass admin.
**Soft delete:** via status=cancelled com cancel_reason + campos deleted_*.
**Anexos:** apenas IDs em attachment_refs; URLs são derivadas de HealthDocument.storage_path.
**Sem `exam_group_id`** — relacionamento com exame é via `exam_id` em ExamProcess.
**Índices:** `status ASC, occurred_at DESC`; `event_type ASC, occurred_at DESC`; `payload_type ASC, status ASC`.

---

#### 2.2.1 Mutação de ClinicalEvent — concorrência, finalização e receipts (CONGELADO — CLIN-WRITER-1.W4.P0)

Esta seção é a autoridade para **qualquer comando que altere um ClinicalEvent já
existente**. O writer de criação (W3: `healthOpenClinicalCase` /
`healthAppendClinicalEvent`) não muta eventos; ele apenas garante que todo evento
**nasça** com o token descrito abaixo.

##### Concorrência otimista — `revision` é a autoridade canônica (SUCESSOR — CLIN-WRITER-1.W6.P0.F1.C1)

> **SUCESSOR de W4.P0.** A versão congelada em W4.P0 declarava `updated_at` +
> `expectedUpdatedAt` (epoch ms) como autoridade. O gate **F1.C0** provou que
> duas mutações bem-sucedidas no mesmo milissegundo deixam o token inalterado,
> permitindo que uma operação DISTINTA e obsoleta fosse aceita — inclusive
> violando o contrato congelado do W5 ("exatamente um vencedor"). O contrato
> temporal de `updated_at` (§ Finalização/Cancelamento) permanece; apenas a
> autoridade de concorrência foi substituída.

| Aspecto | Contrato |
|---|---|
| Campo de autoridade | `revision` (inteiro) |
| Owner | **SERVER.** Nunca aceito do payload do cliente |
| Na criação | `revision = 1` (todo ClinicalEvent canônico, por qualquer caminho de criação) |
| Em cada mutação canônica bem-sucedida | `revision = revisão armazenada + 1`, calculada **explicitamente** na transação |
| Token de wire na requisição | `expectedRevision` |
| Unidade de wire | **inteiro seguro `>= 1`** |
| Comparação no servidor | `stored.revision === request.expectedRevision` |
| Divergência (token obsoleto) | `failed-precondition` |
| `expectedRevision` ausente/malformado/`0`/negativo/fracionário | `invalid-argument` |
| `revision` armazenada ausente/malformada/`0` | `failed-precondition` / `integrity` |
| `revision` em `MAX_SAFE_INTEGER` | `integrity` — falha fechada, nunca inteiro inseguro |
| `FieldValue.increment` para `revision` | **PROIBIDO** — documento, resposta, receipt e audit precisam do mesmo número exato |
| `expectedUpdatedAt` | **RETIRADO** do contrato clínico; o vocabulário fechado o rejeita (`invalid-argument`) |
| Retry automático | **NÃO.** O chamador relê e decide |

**Não** usamos `DocumentSnapshot.updateTime` como token. A autoridade precisa ser
um campo do documento que Mobile/Web leiam pelo caminho normal de leitura; depender
de metadata interna do Firestore criaria um contrato paralelo não congelado.

**Resposta / receipt / audit.** As mutações de evento retornam a `revision`
resultante (`Finalize`, `Cancel Event`, `Amend` → revisão do evento pai). O
receipt da operação persiste a mesma `revision`, de modo que um replay retorna
exatamente a revisão que **aquela** operação produziu — nunca uma recalculada do
estado atual. O audit central registra `event_revision`.

**Ordem obrigatória dentro da transação de mutação:**

```
1. ler o operation receipt
2. replay válido  → retornar o resultado original (NÃO checar concorrência)
3. conflito de intenção → failed-precondition / idempotency-conflict
4. ler o evento/estado atual
5. validar expectedRevision (concorrência)
6. validar a transição de estado no domínio congelado
7. escrever revision = anterior + 1
```

O passo 2 **precede** o passo 5 deliberadamente: um retry de rede de uma operação
que já teve sucesso ainda carrega a `expectedRevision` antiga. Checar concorrência
antes do replay rejeitaria como "obsoleto" um retry legítimo.

**`updated_at` no ClinicalEvent após o sucessor** — metadado temporal apenas: não
é único, não é monotônico, não implica ordem de commit e não participa da decisão
fresco/obsoleto. As igualdades `updated_at == recorded_at` (criação),
`== finalized_at`, `== cancelled_at` e `== last_amended_at` permanecem válidas
como fatos temporais.

##### Finalização — `draft → final`

| Campo | Contrato |
|---|---|
| `status` | `final` |
| `finalized_at` | timestamp de **servidor**, obrigatório na finalização |
| `updated_at` | **o mesmo** timestamp da finalização |
| `finalized_by` | **não existe** no ClinicalEvent v1 |
| conteúdo clínico | 100% preservado — `event_type`, `occurred_at`, `payload_type`, `payload_version`, `content`, `professional`, `attachment_refs`, `recorded_at`, `recorded_by` |

O ator que finalizou é registrado em `auditLogs` + na proveniência do operation
receipt. A ausência de `finalized_at` no objeto puro de transição de domínio Dart
(`ClinicalEventTransitions.transition`) **não** invalida sua persistência:
transição de domínio e metadado server-side de persistência são responsabilidades
distintas.

##### Cancelamento — `draft → cancelled` e `final → cancelled`

| Campo | Contrato |
|---|---|
| `status` | `cancelled` (terminal) |
| `cancel_reason` | obrigatório, non-blank, **trimmed** |
| `cancelled_at` | timestamp de **servidor** |
| `cancelled_by` | ator autenticado derivado no **servidor** |
| `updated_at` | o mesmo timestamp do cancelamento |
| `finalized_at` | **preservado imutável** se o evento já era `final`; ausente se veio de `draft` |
| conteúdo clínico | **preservado integralmente** |

Cancelar **não** apaga e **não** reescreve conteúdo. Correção de conteúdo
finalizado é emenda (§2.3), nunca mutação.

##### Escopo dos operation receipts — CASE-SCOPED

Todos os comandos clínicos compartilham o namespace de operações do
**ClinicalCase**:

```
dogs/{dogId}/clinical_cases/{caseId}/operations/{operationId}
```

Vale para `healthOpenClinicalCase`, `healthAppendClinicalEvent`,
`healthFinalizeClinicalEvent`, `healthCancelClinicalEvent` e comandos clínicos
case-scoped posteriores, até que um novo gate explícito de autoridade decida
diferente.

**Não** existe `clinical_events/{eventId}/operations/{operationId}`. Reutilizar o
mesmo `operationId` para um comando/intenção diferente dentro do mesmo caso é
**conflito** (resolvido por `kind`/fingerprint), não motivo para um segundo
namespace.

---

### 2.3 clinical_cases/{caseId}/clinical_events/{eventId}/clinical_amendments/{amendId}

**Modelo de emenda (CONGELADO, P2 v1):** as emendas formam uma **lista causal
plana** contra o ClinicalEvent original. O conteúdo do evento original **nunca**
é reescrito. **Não** há caminho recursivo de emenda-de-emenda. Os contadores
`has_amendments` / `amendment_count` no evento pai são derivados/server-managed
(§2.2); o writer de emenda os atualiza atomicamente (gate W5).

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| type | string (enum) | ✅ | correction, addendum, complement |
| reason | string | ✅ | |
| payload_type | string | ✅ | Mesmo do evento pai |
| payload_version | number | ✅ | Mesmo do evento pai |
| content | map | ✅ | Apenas campos alterados/adicionados |
| recorded_by | RecordedBy | ✅ | SERVER — derivado do chamador autenticado |
| recorded_at | timestamp | ✅ | SERVER timestamp |
| schema_version | number | ✅ | SERVER-managed |

**Escritor:** **Backend Admin SDK, exclusivamente** (create-only; imutável após criação). Cliente `if false`.
**Leitor:** Mobile, Web — via `health.read` + acesso estrutural, sem bypass admin.
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

#### CURRENTLY DEPLOYED

O create simples por `healthWeightCreateRecord` persiste a Pesagem canônica em
`dogs/{dogId}/weight_records/{entityId}` com peso, `measured_at`, autoria
server-side e os metadados de operação/auditoria do contrato implantado. Há
operationId, receipt, fingerprint, idempotência, transação, audit log e projeções
atuais no documento do K9. Não há ainda tipo Quick/Official, lifecycle expandido,
revisions, anexos ou fila offline persistente. O Mobile é o writer operacional
homologado via Backend; a Web não é writer operacional canônica.

#### APPROVED TARGET — NOT YET DEPLOYED

Os campos abaixo exigem implementação, Rules, migração e rollout futuros
(ADR-008). Eles não descrevem o shape atualmente gravado pelo create simples.

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| record_type | string (enum) | ✅ target | `quick` ou `official`; `legacy_simple` existe somente no bridge de leitura |
| origin_record_type | string (enum) | ✅ target | `quick` ou `official`; imutável |
| status | string (enum) | ✅ target | `valid` ou `invalidated` |
| weight_kg | number | ✅ | 1,0–100,0; exatamente uma casa decimal |
| measured_at | timestamp | ✅ | |
| recorded_at | timestamp | ✅ target | Server |
| recorded_by | RecordedBy | ✅ | |
| revision | number | ✅ target | Monotônica; create = 1 |
| information_source | string (enum) | Oficial | Ver especificação canônica |
| location | string (enum) | Oficial | `other` exige descrição |
| measurement_condition | string (enum) | Oficial | `other` exige descrição |
| equipment_state | string (enum) | ❌ | Opcional |
| reading_quality | string (enum) | ❌ | Opcional |
| context | string (enum) | ❌ | routine, clinical, pre_op, post_op |
| bcs | number | ❌ | Target 1–5; somente Oficial |
| bcs_source | string (enum) | Quando BCS presente | Obrigatório com BCS |
| notes | string | ❌ | |
| attachment_refs | array of health_document_id | ❌ | Referências a HealthDocument (substitui photo_url) |
| clinical_links | array | ❌ | Vínculos opcionais; não cria ClinicalEvent automaticamente |
| completion/correction/invalidation metadata | map/campos estruturados | ❌ | Server-managed conforme lifecycle |
| migration_batch_id | string | ❌ | |
| legacy_source | string | ❌ | |
| legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor target:** somente Backend por comandos idempotentes.
**Leitor:** Mobile, Web.
**Índices target:** `status ASC, measured_at DESC, recorded_at DESC` e índices de
filtro documentados na especificação.

Subcoleção target:

```text
dogs/{dogId}/weight_records/{entityId}/revisions/{revisionId}
```

Cada revision é create-only e contém before/after, operation type, justification,
actor, server timestamp, revision number, operationId e receipt reference.

### 2.7.1 weight_configuration/current — APPROVED TARGET

```text
dogs/{dogId}/weight_configuration/current
dogs/{dogId}/weight_configuration/current/revisions/{revisionId}
```

O singleton guarda faixa e meta com lifecycles independentes, revision e autoria.
Sua subcoleção preserva snapshots imutáveis. Estes paths ainda não estão
implantados.

### 2.7.2 Bridge de migração

Registros sem campos target são interpretados somente em leitura como
`record_type=legacy_simple`, `status=valid`, `revision=1`. Não se inferem tipo
Quick/Official nem dados factuais ausentes. BCS legado 1–9 não é convertido.

---

### 2.8 nutrition_plans/{planId}

Path: `dogs/{dogId}/nutrition_plans/{planId}`

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| status | string (enum) | ✅ | `active` \| `superseded` \| `cancelled` (sem `scheduled` no v1) |
| food_type | string | ✅ | |
| amount_grams_per_day | number | ✅ | Agregado; coerente com schedule quando completo |
| meals_per_day | number | ✅ | Agregado; tipicamente `meal_schedule.length` |
| meal_schedule | array | ✅ | Slots com `id` estável, `period`, `scheduled_time` ("HH:mm"), `target_grams` |
| supplements | array | ❌ | Regime prescrito embutido (≠ supplement_logs) |
| valid_from | timestamp | ✅ | Ativação `active`: `valid_from <= server_now` (sem plano futuro no v1) |
| valid_until | timestamp | ❌ | null ou `> valid_from` |
| timezone | string | ✅ | Default domínio: `America/Sao_Paulo` |
| hydration_ml | number | ❌ | |
| special_instructions | string | ❌ | |
| professional | ProfessionalIdentity | ❌ | |
| source_document | HealthDocumentRef | ❌ | |
| attachment_refs | array of health_document_id | ❌ | |
| recorded_by | RecordedBy | ✅ | |
| revision | number | ✅ | Create = 1; monotônico |
| created_at | timestamp | ✅ | Server |
| deleted_at | timestamp | ❌ | Preferir lifecycle status |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| legacy_source / legacy_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor canônico:** backend / Web-originated (callable ou server-orchestrated).
**Mobile:** **read-only**. **Não** client write no contrato novo.
**Leitor:** Mobile, Web.
**Índices:** `status ASC, valid_from DESC`.
**Legado (coexistência):** `nutritional_prescriptions` (ops) + `nutrition_prescriptions` (fallback); campos `vigent_*` só no legado/adapter.

---

### 2.9 meal_logs/{mealId}

Path: `dogs/{dogId}/meal_logs/{mealId}`

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| period | string (enum) | ✅ | morning…extra; **planejado: server-derived do slot** |
| offered_grams | number | ✅ | > 0 |
| consumed_grams | number | ❌ | Se presente: `0 <= x <= offered_grams` |
| acceptance | string (enum) | ✅ | full \| partial \| refused \| unknown |
| fed_at | timestamp | ✅ | |
| plan_id | string | ❌ | Vínculo opcional |
| planned_meal_id | string | ❌ | Slot id no plano |
| meal_occurrence_id | string | ❌ | Conceitual: dog+plan+slot+local_service_date; ≤1 log **não cancelado** por occurrence |
| scheduled_for | timestamp | ❌ | **Server-derived** se planejado |
| prescription_amount_at_time | number | ❌ | Snapshot `target_grams` do slot (**server**) |
| divergence_percent | number | ❌ | |
| divergence_reason | string | ❌ | |
| observations | string | ❌ | |
| attachment_refs | array | ❌ | |
| legacy_photo_balance_url | string | ❌ | Coexistência de `photo_balance_url` legado |
| recorded_by | RecordedBy | ✅ | Server |
| revision | number | ✅ | Create = 1 |
| source | string | ❌ | manual \| legacy_migration \| … |
| legacy_amount_grams | number | ❌ | Preserva bruto do legado |
| deleted_at / cancel fields | — | ❌ | Soft cancel; sem hard delete cliente |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor canônico:** **callable backend** (Mobile-initiated). **Não** Firestore client write no contrato novo.
**Leitor:** Mobile, Web.
**Índices:** `fed_at DESC`; `meal_occurrence_id ASC` (unicidade lógica enforced no backend); `deleted_at ASC, fed_at DESC`.
**Legado (coexistência):** `feeding_events` (ops dual-write atual) + `feedings` (espelho). Backfill: `offered=amount_grams`, `consumed=null`, `acceptance=unknown`, **sem** inventar occurrence/plan link.
**Storage futuro:** `dogs/{dogId}/meal_attachments/...` (legado: `feeding_photos` + `photo_balance_url`).

**Identidade:**

```text
idempotencyKey  = transporte/operação
meal_occurrence_id = identidade semântica da refeição planejada no dia local
```

---

### 2.10 supplement_logs/{logId}

Path: `dogs/{dogId}/supplement_logs/{logId}`

| Campo | Tipo | Obrigatório | Notas |
|-------|------|-------------|-------|
| supplement_name | string | ✅ | Snapshot legível |
| dose | number | ✅ | Administração estruturada; **não** texto livre |
| unit | string (enum) | ✅ | Unidade canônica obrigatória com `dose` |
| administered_at | timestamp | ✅ | Administração pontual |
| nutrition_plan_id | string | ❌ | |
| supplement_regimen_id | string | ❌ | Id em plan.supplements[] |
| recorded_by | RecordedBy | ✅ | |
| revision | number | ✅ | Create = 1 |
| notes | string | ❌ | |
| batch_number | string | ❌ | |
| protocol_id | string | ❌ | |
| deleted_at | timestamp | ❌ | Soft cancel |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| migration_batch_id | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor canônico:** **callable backend**.
**Leitor:** Mobile, Web.
**Índices:** `administered_at DESC`.
**Legado:** `nutrition_supplements` = **regime/estado em uso** — **ZERO** backfill automático para `supplement_logs` (não inventar administração).

> **Dose canônica:** o novo `SupplementLog` usa **`dose` numérico + `unit`**. Dose textual livre pertence somente ao legado / regimen adapter (`nutrition_supplements` ou `NutritionPlan.supplements[]` com representation textual legada). Não inventar backfill de administração a partir de dose texto.

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

**`storage_path`:** identidade canonica no Cloud Storage.
**`storage_url`:** derivado/cache via Storage API. Alteracoes de bucket/CDN nao invalidam o doc.
**Iniciadores:** Mobile, Web (emitem comando; nunca escrevem o agregado).
**Mutation owner:** Backend Function / Admin SDK. Client Firestore writes: **denied**.
`recorded_by` é server-authoritative — jamais aceito do payload. Ver ADR-005 E1/E2 (mesma
separação canal/autoridade aplicada a `operational_restrictions`).
**Leitor:** Mobile, Web.
**Índices:** `deleted_at ASC, uploaded_at DESC`; `document_type ASC, uploaded_at DESC`.

**Storage paths (B0-A.2, corrigido em B0-B.R):**

```text
STAGING    health_document_uploads/{dogId}/{documentId}   ← upload do cliente
CANÔNICO   health_documents/{dogId}/{documentId}          ← selado pelo backend
```

Sem extensão em nenhum dos dois: `documentId` é identidade suficiente, `mime_type` vem do
metadata do objeto, `title` pertence ao agregado e o filename original não é autoridade. Ambos
são determinísticos a partir de `dogId` + `documentId`, e há exatamente um objeto canônico por
`HealthDocument`.

Não confundir com o path **Firestore** do agregado, que é
`dogs/{dogId}/health_documents/{documentId}`.

**Por que existem dois namespaces (correção de contrato B0-B.R).** O B0-A.2 previa upload do
cliente direto no path canônico, assumindo que `allow create` + `allow update: if false`
tornaria os bytes imutáveis. **Essa premissa é falsa:** nas Storage Rules, `create` cobre a
gravação do conteúdo do arquivo, então permitir `create` no path também permite substituir os
bytes de um objeto já existente. Comprovado no emulador — e o comportamento é idêntico em
`health_attachments` e `documentos`, logo é semântica do produto, não de um namespace novo.

Consequência inaceitável para evidência clínica: um `HealthDocument` finalizado continuaria
apontando para o mesmo `storage_path`, mas os bytes por trás dele poderiam ser trocados depois
por qualquer cliente com acesso ao K9. Como esse documento fundamenta
`OperationalRestriction.source_document`, a cadeia termina em "o K9 trabalha ou não" — o
sistema precisa **garantir** integridade, não apenas deixar rastro de que houve alteração.

**Storage Rules (contrato para implementação):**

| Namespace | read | create | update | delete |
|---|---|---|---|---|
| `health_document_uploads/{dogId}/{documentId}` | acesso ao K9 | acesso ao K9 + contentType permitido + ≤ 20 MB | ❌ | ❌ |
| `health_documents/{dogId}/{documentId}` | acesso ao K9 | **❌** | ❌ | ❌ |

O catch-all permanece deny-all. Sobrescrever o **staging** antes do FINALIZE é inócuo: não é
evidência, e o selo se prende à `generation` exata validada.

**Selo backend (staging → canônico).** O FINALIZE valida o objeto de staging, captura sua
`generation` e copia para o path canônico com duas preconditions do Cloud Storage:

- **fonte** presa à `generation` observada — se os bytes mudarem entre validação e cópia, falha;
- **destino** com `ifGenerationMatch: 0` — create-only real, que as Rules não expressam.

`mime_type`, `file_size_bytes` e os checksums do audit descrevem o objeto **canônico** selado.

Upload bem-sucedido **não** prova existência do K9 — `canAccessDogRecord` em `storage.rules`
não verifica `exists(dogPath)`. O finalize backend valida independentemente: existência e
acesso ao K9, path derivado no servidor, existência do objeto, metadata, size, contentType,
`generation` e checksum.

**Selo de intenção (B0-B.R2).** Junto com os bytes, a cópia grava metadata **server-owned** no
objeto canônico:

```text
k9_health_seal_version      "1"
k9_health_seal_fingerprint  SHA256(seal-kind/version | dogId | operationId | finalizeFingerprint)
k9_health_document_id       {documentId}
```

Isso resolve uma janela específica: quando o selo tem sucesso mas a transação Firestore não
commita, **não existe receipt** — logo nada durável no Firestore prova qual intenção produziu
aqueles bytes. Sem o selo, um segundo FINALIZE com o mesmo `operationId` e payload **diferente**
poderia herdar bytes selados pela intenção anterior, furando a promessa
"mesmo `operationId` + payload diferente → conflito" justamente após uma falha parcial.

O fingerprint de selagem é metadata do **protocolo de mutação**, não do domínio clínico: não
entra no `HealthDocument` nem no `HealthDocumentRef`.

**Estado de recuperação legítimo.** Storage e Firestore não compartilham transação, então
"bytes canônicos selados + `HealthDocument` ausente" é possível sem corrupção. A autoridade da
recuperação é o **selo**, não o staging — após um selo bem-sucedido o staging pode ter sido
sobrescrito por um retry ou já apagado pela limpeza best-effort, e exigi-lo tornaria um
documento legitimamente selado irrecuperável.

Fail-closed em: selo ausente (objeto de origem desconhecida), `seal_version` inesperada,
fingerprint ausente ou de outra intenção. Nunca reescreve a metadata para forçar
correspondência. Bytes canônicos sem `HealthDocument` **não são** evidência clínica.

**Camadas do protocolo — cada uma responde uma pergunta diferente:**

| Mecanismo | Pergunta |
|---|---|
| precondition de fonte (`generation`) | estes são exatamente os bytes que validei? |
| precondition de destino (`ifGenerationMatch: 0`) | ninguém substituiu um objeto canônico? |
| seal fingerprint | estes bytes foram selados para **esta** intenção? |
| receipt | esta mutação já foi commitada? |
| `HealthDocument` | este artefato tem autoridade clínica? |
| `HealthDocumentRef` | qual é a identidade citável? |

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
| end_professional | ProfessionalIdentity | ⚠️ | Profissional externo que autorizou encerramento — **obrigatório quando `status == ended`** (ADR-005 E6) |
| end_source_document | HealthDocumentRef | ⚠️ | Laudo/atestado de liberação — **obrigatório quando `status == ended`** (ADR-005 E6) |
| end_reason | string | ⚠️ | Obrigatório quando `status == ended` |
| cancelled_at | timestamp | ⚠️ | Obrigatório quando `status == cancelled` |
| cancelled_by | RecordedBy | ⚠️ | Obrigatório quando `status == cancelled` — server-authoritative |
| cancel_reason | string | ⚠️ | Obrigatório quando `status == cancelled` |
| evidence | map | ❌ | Ver Evidence |
| status | string (enum) | ✅ | active, ended, cancelled |
| case_id | string | ❌ | |
| event_id | string | ❌ | |
| exam_id | string | ❌ | Origem em ExamProcess.impact_assessed |
| deleted_at | timestamp | ❌ | Soft delete |
| deleted_by | RecordedBy | ❌ | |
| delete_reason | string | ❌ | |
| schema_version | number | ✅ | |

**Escritor:** exclusivamente **backend** (callable/Admin SDK), channel-agnostic. Mobile e
Web são iniciadores da operação autorizada, nunca escritores. Firestore Rules permanecem
deny-all para writes de cliente. Ver ADR-005 E1/E2.
**Leitor:** Mobile, Web, Function (para snapshot).
**Índices:** `status ASC, level ASC, issued_at DESC`.

**Lifecycle e obrigatoriedade condicional (ADR-005 E6/E7):** `ended` é liberação clínica
e exige `actual_end` + `ended_by` + `end_reason` + `end_professional` +
`end_source_document`. `cancelled` é invalidação administrativa (duplicado, erro material,
evidência incorreta) e exige `cancelled_at` + `cancelled_by` + `cancel_reason`; **não** é
liberação clínica e não usa os campos `end_*`. Ambos são terminais. Campos de substância
clínica são imutáveis após emissão — correção é `cancelled` + nova restrição.

> **Nota de coexistência:** `cancelled_at`, `cancelled_by` e `cancel_reason` são campos
> canônicos derivados desta emenda e **ainda não existem** no agregado Dart
> (`OperationalRestriction`) nem em qualquer writer. Ver ADR-005 E11 item 2.

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
| scheduled_for | timestamp | ✅ | Create manual: presente ou futuro (autoridade callable; minuto corrente do servidor aceito). Não nasce no passado. |
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

**Escritores (contrato operacional 4E):**
- **Flutter client:** **read-only** (Rules: `create/update/delete: if false`).
- **Backend callables / Admin SDK:** writer canônico das mutações manuais (`healthScheduleCreateManual`, `healthScheduleUpdateOpen`, `healthScheduleComplete`, `healthScheduleCancel`) e de gerações automáticas futuras.
- Mobile/Web **não** escrevem o documento diretamente; invocam callables autenticados.

**Leitor:** Mobile, Web (cliente autenticado com `canAccessDogRecord`).
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
| `dogs/{dogId}/health_events` (todos os tipos, todos os registros) | `dogs/{dogId}/legacy_health_records/{recordId}` | **Contrato conservador único:** todos os `health_events` anteriores ao go-live vão para `legacy_health_records` com `original_payload` preservado. Nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/clinical_events`. Operações administrativas futuras podem, de forma auditada, vincular `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando clinicamente justificado. |
| `dogs/{dogId}/exams` (se existir como subcollection) | `clinical_cases/{caseId}/exams` | Migração para subcoleção de caso; sem exam_group_id |
| `dogs/{dogId}/weight_records` | `weight_records` (normalizado) | Adicionar campos |
| `dogs/{dogId}/weight_history` | — | Não migrado como fonte canônica; preservado read-only durante todo o v1 |
| `dogs/{dogId}/feeding_events` | `meal_logs` | Rename + normalização conservadora (`offered_grams=amount_grams`, `consumed=null`, `acceptance=unknown`; **sem** inventar plan/occurrence) |
| `dogs/{dogId}/feedings` | — | LEGACY CURRENT espelho; read-only histórico; **não** fonte canônica |
| `dogs/{dogId}/nutritional_prescriptions` | `nutrition_plans` | Rename + normalização (`vigent_*`→`valid_*`; schedule inferido marcado; 1 active) |
| `dogs/{dogId}/nutrition_prescriptions` | — | LEGACY CURRENT fallback; read-only histórico |
| `dogs/{dogId}/nutrition_supplements` | **não** `supplement_logs` automático | Regime/estado em uso → adapter / curadoria de regimen; **ZERO** SupplementLog retroativo |
| `vacinas/{id}` (raiz) | `vaccination_records/{vaccinationId}` (canônico) + `legacy_health_records` (incompletos) | Migração com dados suficientes vai para VaccinationRecord; incompletos permanecem em legacy_health_records read-only. **Não** backfilar para `clinical_cases/clinical_events` nem para "caso preventivo". |
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
  "source_collection": "dogs/dog_001/clinical_cases/case_abc123/clinical_events",
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
