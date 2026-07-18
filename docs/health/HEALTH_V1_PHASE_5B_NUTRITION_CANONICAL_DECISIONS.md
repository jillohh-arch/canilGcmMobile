# Health v1.0 — Fase 5B — Decisões canônicas de Nutrição

| Campo | Valor |
|-------|-------|
| Status | **ENCERRADA E DOCUMENTADA** (D1–D42 + reconciliação canônica) |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `c8893ed0497623956ab1390da4c020d137268854` |
| Pré-requisito | `HEALTH_V1_PHASE_5A_NUTRITION_AUDIT.md` (§1.1 complemento) |
| Documento canônico 5B | **este arquivo** |
| Escopo | Decisões de contrato (incl. correção final D39–D42) |
| Fora de escopo | Runtime, Rules, Functions, indexes, collections, produção, commit, push, deploy |

```text
5A = o que existe (evidência)
5B = o que fica decidido (contrato)  ← este documento
5C = foundation domínio + read/adapters (ZERO write novo)
```

**Decisões já aprovadas (D1–D38) permanecem.**
**Esta rodada fecha lacunas MAJOR:** ocorrência planejada (D39), plano futuro (D40), autoridade de campos do slot (D41), invariantes de quantidade/acceptance (D42).

---

## 1. Executive summary

Contrato alvo da Nutrição Health v1.0 **congelado** antes de qualquer collection canônica ou write path novo.

| Tema | Escolha |
|------|---------|
| Paths | `nutrition_plans`, `meal_logs`, `supplement_logs` |
| Plano | Web define via backend; Mobile **somente consulta** |
| Plano futuro | **NÃO suportado no v1** (`valid_from <= server_now` na ativação) |
| Execução | MealLog + SupplementLog via **callables** |
| Dual-write | **Proibido** no código novo |
| Ocorrência planejada | `meal_occurrence_id` = dog+plan+slot+local_service_date |
| Unicidade | ≤1 MealLog canônico **não cancelado** por `meal_occurrence_id` |
| Idempotência | transporte (`idempotencyKey`) **≠** identidade semântica da ocorrência |
| Slot fields | **backend authority** (period, scheduled_for, snapshot, occurrence) |
| Quantidades | `offered > 0`; `0 ≤ consumed ≤ offered` se presente |
| Suplementos | Regime ≠ log; **zero** backfill de administração inventada |
| amount_grams legado | offered + consumed null + unknown; **sem** vínculo slot artificial |
| Timeline / Summary / Shell | projeção / read model / Nutrição Hoje (D35–D37) |

**Domain Model / Schema / ADR / Permission Matrix NÃO editados nesta rodada.**
Reconciliação documental canônica = rodada própria **após** fechamento humano da 5B.

---

## 2. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD | `c8893ed0497623956ab1390da4c020d137268854` |
| Tracking | `0/0` |
| Working tree | 5A + este 5B (untracked) |
| Runtime / Rules / Functions / collections / produção | **inalterados** |
| Commit / push / deploy | **NÃO** |

---

## 3. Inputs from Phase 5A

| Input 5A | Implicação 5B |
|----------|----------------|
| Dual-write feedings | D31 zero dual-write novo |
| Dual-read + empty error | D28/D30 |
| addPrescription mobile | D2/D18/D24 |
| Shell placeholder | D37 |
| Summary via NutritionService | D36 |
| Timeline dual collections | D35 |
| supplements em uso ≠ log | D13–D16 |
| só amount_grams | D7–D10 + D42 |
| plano sem slots | D5 + D39 |
| photo_balance_url | D25–D26 |
| M8–M11 migração semântica | backfill conservador |

**Auditoria humana 5B:** lacunas MAJOR de identidade de ocorrência e plano futuro → D39–D42.

---

## 4. Canonical paths

### D1 — Paths (**preservada**)

| Path | Papel |
|------|--------|
| `dogs/{dogId}/nutrition_plans/{planId}` | canônico novo — plano |
| `dogs/{dogId}/meal_logs/{mealId}` | canônico novo — execução refeição |
| `dogs/{dogId}/supplement_logs/{logId}` | canônico novo — administração pontual |

Legado (coexistência only): `feeding_events`, `feedings`, `nutritional_prescriptions`, `nutrition_prescriptions`, `nutrition_supplements`.

---

## 5. NutritionPlan contract

### D2 — Ownership (**preservada**)

```text
WEB DEFINE · MOBILE CONSULTA · MOBILE EXECUTA
```

### D3 — Lifecycle (**preservada**)

```text
active | superseded | cancelled
```

| Regra | Valor |
|-------|--------|
| Por cão | **no máximo 1** `active` |
| Novo active | anterior `active` → `superseded` (atômico / server-orchestrated na impl.) |
| Cancelamento | `cancelled` com evidência; **não inventar** no backfill |
| Status `scheduled` | **não existe no v1** |

### D4 — Vigência (**preservada** + coerência)

```text
valid_from          obrigatório
valid_until?        null ou > valid_from
timezone            obrigatório no plano (default SP no domínio se legado sem tz)
status, revision, schema_version, recorded_by
```

Adapter legado: `vigent_from→valid_from`, `vigent_until→valid_until`.

**Coerência mínima:**

```text
valid_until == null  OR  valid_until > valid_from
```

Plano `active` **não** pode ser criado já expirado
(`valid_until != null && valid_until <= server_now` na ativação → rejeição).

### D40 — Planos futuros (**NOVA**)

```text
NutritionPlan com início futuro: NÃO SUPORTADO NO V1
```

Na criação/ativação como `active`:

```text
valid_from <= server_now
```

| Alternativa rejeitada | Por quê |
|----------------------|---------|
| Status `scheduled` no v1 | Lifecycle extra sem produto/UX fechados; complica 1-active |
| Aceitar active com valid_from futuro | Dois “planos em vigor” conceitualmente; “hoje” ambíguo |

**Semântica da ativação (reafirmação):**

```text
novo plano → active
plano active anterior → superseded
transição server-orchestrated / atômica
ZERO janela com dois active
```

### Campos de plano (resumo)

```text
food_type, amount_grams_per_day, meals_per_day
meal_schedule[]          // D5
supplements[]            // D14 regimen
valid_from, valid_until?, timezone
status, revision, schema_version, recorded_by
hydration_ml?, special_instructions?
professional?, source_document?, attachment_refs?
legacy_source?, legacy_id?
```

---

## 6. MealSchedule contract

### D5 — Slots (**preservada**)

```text
meal_schedule: [
  {
    id: string,              // estável na versão do plano
    period: MealPeriod,
    scheduled_time: "HH:mm", // timezone do plano
    target_grams: number
  }
]
```

### D6 — MealPeriod (**preservada**)

Wire: `morning | afternoon | evening | night | extra`
Legado: `manha→morning`, `almoco→afternoon`, `noite→night`.

### D11 — Derivação de status do slot (**ATUALIZADA** com D39)

**Não** persistir no slot: `pending|completed|missed`.

Derivação diária usa **`meal_occurrence_id`** (ou equivalência semântica):

```text
slot + local_service_date  →  meal_occurrence_id

slot existe
+ nenhum MealLog canônico NÃO cancelado com essa occurrence
→ pending | late   (late = política temporal de apresentação)

slot existe
+ MealLog canônico NÃO cancelado com essa occurrence
→ completed
```

Correção / soft cancellation de MealLog **entra** na política futura de rederivação (slot volta a pending/late se o log ativo deixa de contar).

`skipped`: não inventado em backfill silencioso.

### D12 — Vínculo (**preservada** + occurrence)

| Caso | plan_id | planned_meal_id | meal_occurrence_id |
|------|---------|-----------------|--------------------|
| Planejado | sim | sim (slot) | **sim** (server-derived) |
| Avulso | null | null | **null** (sem ocorrência de slot) |

---

## 7. MealLog contract

### D7 — Campos (**ATUALIZADO**)

```text
id
dog_id
plan_id?
planned_meal_id?
meal_occurrence_id?            // D39 — somente planejado
period                         // planejado: server; avulso: cliente
scheduled_for?                 // planejado: server-derived
offered_grams
consumed_grams?
acceptance
fed_at
observations?
attachment_refs?
legacy_photo_balance_url?
prescription_amount_at_time?   // planejado: snapshot target_grams do slot
divergence_percent?
divergence_reason?
recorded_by
recorded_at?                   // server
schema_version
revision
source?
legacy_source? / legacy_id?
legacy_amount_grams?
soft cancel / correction (D21)
```

### D8 / D9 — offered, consumed, acceptance (**+ D42**)

Ver §7.1 e D42 abaixo.

### D39 — Meal occurrence identity (**NOVA**)

```text
Uma refeição planejada existe como uma ocorrência concreta
de um slot de plano em uma data operacional local.
```

Identidade conceitual:

```text
dog_id + plan_id + planned_meal_id + local_service_date
```

Campo no MealLog planejado:

```text
meal_occurrence_id
```

Representação física futura: ID/hash determinístico — **algoritmo criptográfico NÃO congelado em 5B**.

#### Unicidade

```text
Para uma mesma meal_occurrence_id,
no máximo UM MealLog canônico NÃO cancelado.
```

| Cenário futuro | Comportamento |
|----------------|---------------|
| mesma ocorrência + mesma operação/payload | replay / no-op |
| mesma ocorrência + intenção incompatível | **conflict** |
| retry com nova `idempotencyKey` mas mesma occurrence | **não** cria segundo log ativo |

**Não** confiar **somente** em `idempotencyKey` para unicidade semântica da refeição planejada.

#### `local_service_date`

Derivada no **timezone do plano** (ex.: `America/Sao_Paulo` → `2026-07-18`).

**Não** usar “UTC date” crua como identidade do dia operacional.

Sem plano (avulsa): timezone default do domínio (`America/Sao_Paulo`) para “hoje” de apresentação — **sem** `meal_occurrence_id` de slot.

### D41 — Autoridade dos campos do slot (**NOVA**)

Quando MealLog está vinculado a `plan_id` + `planned_meal_id`:

Cliente **NÃO** é autoridade sobre:

```text
period
scheduled_for
prescription_amount_at_time
meal_occurrence_id
```

Backend **deve**:

1. carregar o plano;
2. validar o plano (status, vigência, timezone);
3. localizar o slot por `planned_meal_id`;
4. validar o slot;
5. usar timezone do plano;
6. derivar `local_service_date` / occurrence;
7. derivar `scheduled_for`;
8. usar `period` do slot;
9. snapshot `target_grams` → `prescription_amount_at_time`.

Cliente envia **identidade do vínculo** + execução; não os derivados como fonte de verdade.

#### Payload conceitual — MealLog **planejado** (cliente)

```text
dog_id
plan_id
planned_meal_id
offered_grams
consumed_grams?
acceptance
fed_at
observations?
attachment input futuro
idempotencyKey
```

#### Server-managed / derived (planejado)

```text
meal_occurrence_id
period
scheduled_for
prescription_amount_at_time
recorded_by
recorded_at
revision
schema_version
source
audit
```

#### Payload conceitual — MealLog **avulso** (cliente)

```text
period
offered_grams
consumed_grams?
acceptance
fed_at
observations?
idempotencyKey
```

**Sem** `plan_id` / `planned_meal_id` / `meal_occurrence_id` de slot.

Backend autoridade: `recorded_by`, `recorded_at`, `revision`, `schema_version`, audit.

### D42 — Invariantes de quantidade e acceptance (**NOVA**)

```text
offered_grams > 0
```

Se `consumed_grams` presente:

```text
0 <= consumed_grams <= offered_grams
```

**Rejeitar:** `consumed_grams < 0` ou `consumed_grams > offered_grams`.

#### Acceptance × consumed

| acceptance | consumed_grams |
|------------|----------------|
| **refused** | **deve ser** `0` |
| **full** | `null` permitido (consumo exato não mensurado); se informado → `== offered_grams` |
| **partial** | `null` permitido se exato não mensurado; se informado → `0 < consumed < offered` |
| **unknown** | preferencialmente `null`; se valor legado/mensurado, só respeitar bounds **sem** forçar acceptance diferente |

UI **não** deve materializar falso `consumed = offered` no documento para “full” sem medição (apresentação pode assumir visualmente; documento permanece honesto).

---

## 8. Legacy amount semantics

### D10 — `amount_grams` (**preservada** + occurrence)

Evidência UI: “**Servido** em conformidade…”, foto balança.

```text
offered_grams        = amount_grams
consumed_grams       = null
acceptance           = unknown
legacy_amount_grams  = amount_grams
source               = legacy_migration
```

**Backfill — vínculos de slot:**

```text
plan_id = null
planned_meal_id = null
meal_occurrence_id = null
```

**Não** criar `meal_occurrence_id` artificial para refeições legadas.
Reconciliação a slot só com evidência explícita futura.

---

## 9. Supplement regimen

### D13–D14 (**preservadas**)

Regimen embutido em `NutritionPlan.supplements[]`.
`nutrition_supplements` legado ≠ `supplement_logs`.

---

## 10. SupplementLog

### D15–D16 (**preservadas**)

Administração pontual; **ZERO** backfill de logs inventados.

---

## 11. Writers

### D17–D18 (**preservadas**)

MealLog / SupplementLog / NutritionPlan → **backend callables** / server-orchestrated.

---

## 12. Permissions

### D23–D24 (**preservadas**)

Matriz documental `health.read` / `health.record_routine` / `health.manage_nutrition_plan`.
Runtime atual: capabilities **não** implantadas.
Mobile plan **read-only** no canônico.

---

## 13. Idempotency

### D19 — (**ATUALIZADA**)

```text
IDEMPOTÊNCIA DE TRANSPORTE/OPERAÇÃO
≠
IDENTIDADE SEMÂNTICA DA REFEIÇÃO PLANEJADA
```

| Tipo | Identidades |
|------|-------------|
| **Planned meal** | `meal_occurrence_id` **+** `idempotencyKey` |
| **Ad hoc meal** | `idempotencyKey` apenas |
| **Supplement admin** | `idempotencyKey` |
| **Plan mutations** | `operationId` + `expectedRevision` |

Implementação futura deve garantir **ambos** (quando aplicável).
Durable operation receipt (padrão Agenda 4E) para transporte; unicidade semântica da occurrence é **invariante de domínio** (D39).

---

## 14. Revision / concurrency

### D20–D21 (**preservadas**)

`revision` monotônica create=1.
MealLog/SupplementLog: no hard delete; soft cancel / audited correction; append-only dominante.

Unicidade por `meal_occurrence_id` (D39) é **adicional** à revision/idempotency de transporte.

---

## 15. Audit

### D22 (**preservada**)

`auditLogs` canônico; 1 audit por op lógica; 0 em replay no-op.

---

## 16. Attachments / Storage

### D25–D26 (**preservadas**)

`legacy_photo_balance_url`; path `meal_attachments` novo; sem half-HealthDocument.

---

## 17. Timezone

### D27 (**preservada**)

Default `America/Sao_Paulo`.
`local_service_date` da occurrence = dia no TZ do plano (D39).

---

## 18. Read state

### D28 (**preservada**)

`loading | data | empty | offline | error` — erro ≠ empty.

---

## 19. State ownership

### D29 (**preservada**)

Estado keyed por `dogId`.
`NutritionViewModel` global = legacy adapter.

---

## 20. Coexistence

### D30 (**preservada**)

Dual-read temporário; canônico vence; adapter explícito.

---

## 21. Dual-write prohibition

### D31 (**preservada**)

```text
NOVO CÓDIGO: ZERO dual-write permanente
```

---

## 22. Meal migration strategy

### D32 (**preservada** + occurrence null)

Inventário prod obrigatório antes de backfill.

Transformação:

```text
offered_grams = amount_grams
consumed_grams = null
acceptance = unknown
plan_id = null
planned_meal_id = null
meal_occurrence_id = null
legacy_photo_balance_url = photo_balance_url
revision = 1
source = legacy_migration
```

---

## 23. Plan migration strategy

### D33 (**preservada** + D40)

Inventário prod; 1 active; demais superseded; cancelled **só com evidência**.

Ao materializar active na migração: se `valid_from` no futuro relativo a `server_now` do cutover:

- **não** ativar como active futuro (D40);
- policy de inventário: adiar cutover / ajustar valid_from com evidência / supersede — **DEFERRED UNTIL INVENTORY** se volume > 0.

Schedule inferido: `schedule_origin = legacy_inferred`.

---

## 24. Supplement migration strategy

### D16 (**preservada**)

ZERO `supplement_logs` inventados.

---

## 25. AI coexistence

### D34 (**preservada**)

Fora do core; dual-read → canônico no cutover; não refatorar em 5B.

---

## 26. Timeline integration

### D35 (**preservada**)

Projeção `health_timeline`; não leitura eterna das collections de execução.

---

## 27. Summary integration

### D36 (**preservada**)

Read model Nutrition próprio; estados D28; sem score de prontidão.

---

## 28. Shell/UI direction

### D37–D38 (**preservadas**)

Nutrição Hoje: read + execução; plano consulta; histórico meals + admin logs + plano via timeline.

---

## 29. Historical behavior

Superfícies legadas permanecem até cutover; não estender dual-write.

---

## 30. Decision matrix

| Decisão | Escolha | Alternativa rejeitada | Justificativa |
|---------|---------|----------------------|---------------|
| **D1** Paths | nutrition_plans / meal_logs / supplement_logs | Reusar paths antigos | ADR/docs; separação legado |
| **D2** Ownership | Web define / Mobile executa | Mobile CRUD plano | Domain + risco write |
| **D3** Lifecycle | active/superseded/cancelled | só vigent_until | 1 active explícito |
| **D4** Vigência | valid_* + TZ + until>from | typo vigent no novo | schema limpo |
| **D5** Schedule | slots com id estável | só meals_per_day | UX 07:00/19:00 |
| **D6** Period | EN wire + parse almoco | labels PT persistidos | enums foundation |
| **D7** MealLog | offered/consumed/acceptance + links | só amount_grams | UX + auditoria |
| **D8** offered/consumed | offered obrig.; consumed opcional | forçar consumed | sem falsa precisão |
| **D9** acceptance | full/partial/refused/unknown | inferir full legado | conservador |
| **D10** amount legado | offered + null + unknown | consumed=amount | UI “Servido” |
| **D11** slot status | derivado via occurrence | persistir no plano | sem lifecycle duplo |
| **D12** vínculo | plan/slot opcionais | sempre exigir plano | avulsas |
| **D13–16** sup | regimen vs log; zero backfill admin | backfill → logs | MAJOR semântico |
| **D17–18** writers | backend callables | client write | 4E / autoridade |
| **D19** idempotency | key transporte **≠** occurrence | só idempotencyKey | unicidade semântica |
| **D20–21** rev/imut | rev monotônica; no hard delete | edit livre | histórico |
| **D22** audit | auditLogs | só inline | defesa |
| **D23–24** perm | matriz doc + mobile R/O plan | capability inventada 5B | inventário |
| **D25–26** anexos | legacy URL + meal_attachments | half-HealthDocument | coexistência |
| **D27** TZ | America/Sao_Paulo | device only | dia operacional |
| **D28–29** state | error states; keyed dogId | empty silencioso; VM global | 5A |
| **D30–31** coexist | dual-read temp; zero dual-write | dual eterno | cutover |
| **D32–33** migrate | inventário + conservador | backfill cego | paridade |
| **D34–38** AI/TL/Sum/UI | fora core / projeção / read model / Hoje | misturar regimen/admin | 5A+roadmap |
| **D39** occurrence | dog+plan+slot+local_date; ≤1 log ativo | só idempotency; UTC date | identidade diária |
| **D40** future plan | valid_from≤now; sem scheduled | active futuro / status scheduled | 1 active claro |
| **D41** slot authority | backend deriva period/sched/snapshot/occurrence | cliente manda derivados | anti-spoof / coerência |
| **D42** qty invariants | offered>0; bounds consumed; acceptance rules | consumed livre | integridade |

---

## 31. Open/deferred inventory-dependent questions

| ID | Questão | Status | Critério |
|----|---------|--------|----------|
| Q1 | Defaults scheduled_time na migração de plano | DEFERRED UNTIL CONFIG | tabela institucional antes do backfill |
| Q2 | amount_grams ≤0 / null | DEFERRED UNTIL INVENTORY | contagem prod |
| Q3 | payloads dual-write divergentes | DEFERRED UNTIL INVENTORY | contagem conflitos |
| Q4 | soft-delete plan → cancelled vs superseded | DEFERRED UNTIL INVENTORY | evidência deleted_reason |
| Q5 | wiring capability vs Agenda create/edit | DEFERRED auth phase | catálogo real |
| Q6 | janela late (minutos) | DEFERRED UI produto | não bloqueia 5C domain |
| Q7 | algoritmo hash de meal_occurrence_id | **DEFERRED 5C/5D** | identidade conceitual já fixa (D39); algo não congelado |
| Q8 | planos legados com vigent_from futuro | DEFERRED UNTIL INVENTORY | volume; não ativar futuro (D40) |
| Q9 | receipts collection naming | DEFERRED 5D | espelhar 4E |
| Q10 | HealthDocument cutover anexos | DEFERRED fase docs | D25/D26 ok |

---

## 32. Phase 5C implementation boundary

### Dentro de 5C

```text
domínio canônico:
  NutritionPlan (+ valid_from <= now na validação de active)
  meal_schedule
  MealLog (+ meal_occurrence_id conceitual / tipo opaco)
  SupplementLog / regimen no plan
  MealOccurrenceId (representação opaca + regra de construção conceitual)
  local_service_date no TZ do plano
  invariantes offered/consumed/acceptance (D42)
  autoridade de campos planejados (modelo: client vs server-derived)
parsers (almoco)
legacy adapters
coexistence read source
testes de domínio / adapters
```

### Fora de 5C

```text
ZERO write novo
ZERO callable
ZERO Rules / indexes deploy
ZERO collections em produção
ZERO backfill prod
ZERO UI shell completa (stubs de contrato ok)
ZERO refator AI
ZERO peso / IPO
```

### Nota não bloqueadora — implementação 5D

```text
IMPLEMENTATION DETAIL FOR 5D
(não reabre D1–D42)
```

A implementação do **write** futuro deve definir precisamente:

* derivação de `local_service_date` (borda de dia / fed_at vs “agora” no TZ do plano);
* validação de vigência histórica do plano no momento da execução (plano active no dia vs supersede);
* comportamento de **late** / registro **backdated** (occurrence no dia de `fed_at` vs dia de registro).

---

## 33. Final readiness decision

### Reconciliação documental canônica

Atualizado na rodada de fechamento 5A/5B:

| Doc | Atualização |
|------|-------------|
| `HEALTH_V1_DOMAIN_MODEL.md` | NutritionPlan / MealLog / SupplementLog / enums |
| `HEALTH_V1_FIRESTORE_SCHEMA.md` | paths, campos, writers, mapeamento legado |
| `HEALTH_V1_PERMISSION_MATRIX.md` | writers backend + honestidade de capabilities |
| `ADR-006-…` | zero dual-write novo; supplements ≠ logs; cutover |
| `HEALTH_IMPLEMENTATION_ROADMAP.md` | subfases 5A–5H |

### Checklist de fechamento 5B

```text
[x] identidade da ocorrência planejada definida (D39)
[x] unicidade semântica definida (≤1 log não cancelado / occurrence)
[x] idempotência distinguida de ocorrência (D19)
[x] plano futuro resolvido (D40)
[x] ativação do plano coerente (1 active atômico)
[x] autoridade dos campos planejados definida (D41)
[x] invariantes offered/consumed definidas (D42)
[x] acceptance coerente com consumo (D42)
[x] backfill legado não cria vínculo falso (D10/D32)
[x] decisões D1–D42 preservadas e documentadas canonicamente
[x] fronteira 5C atualizada
[x] nota 5D implementation detail
```

```text
FASE 5B — ENCERRADA E DOCUMENTADA
```

---

## Encerramento

```text
## ✅ FASE 5B — CONTRATO CANÔNICO COMPLETO

Documento:
docs/health/HEALTH_V1_PHASE_5B_NUTRITION_CANONICAL_DECISIONS.md

D1–D42 APROVADAS E RECONCILIADAS NOS DOCS CANÔNICOS.
```
