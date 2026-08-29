# Health v1.0 — Fase 5D Gate 1 — Mutation Foundation Report

| Campo | Valor |
|-------|-------|
| Status | **IMPLEMENTADO LOCALMENTE — PRONTO PARA AUDITORIA HUMANA** |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `e499f92d957d2e1e714fbf4d26fa85d831b13817` |
| Escopo | Backend mutation foundation MealLog + SupplementLog |
| Commit / push / deploy | **NÃO** |

---

## 1. Executive summary

Fundação backend **testável** para create de MealLog (planejado/avulso) e SupplementLog:

- comandos + validação D42
- local_service_date de `fedAt` no TZ do plano (5D-A)
- elegibilidade histórica active/superseded (5D-B)
- `meal_occurrence_id` SHA-256 v1 `mo1_<hex>` (5D-C)
- fingerprints + receipts + audit
- motor transacional com deps injetadas
- **zero** `onCall` exportado, **zero** Flutter, **zero** Rules, **zero** dual-write legado

---

## 2. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD | `e499f92d957d2e1e714fbf4d26fa85d831b13817` |
| Tracking | `0/0` |
| Working tree inicial | limpo |
| Node | v24.14.0 (engines functions: 22) |
| TypeScript | ^5.8.3 |
| firebase-functions | ^6.4.0 |

---

## 3. Existing backend patterns reused

| Padrão Agenda (4E) | Reuso Nutrição |
|--------------------|----------------|
| `normalizeOperationId` / path-safe key | reexport / reuse |
| `stableStringify` | fingerprints + preimages |
| `matchOperationReceipt` | espelhado em `matchNutritionReceipt` |
| `decideCreateManual` | `decideCreateByFingerprint` |
| `recordedByPayload` | espelhado |
| `health.create` + dog access | **documentado** para Gate 2 (engine recebe actor já resolvido) |
| receipts sob entity/operations/{key} | meal_logs / supplement_logs |
| auditLogs canônico | 1 por create novo |

Não copiado cegamente: lifecycle schedule, revision concurrency de update, scheduled_for “not in past” da Agenda.

---

## 4. Files changed

```text
functions/src/health_nutrition_logic.ts       (novo — puro)
functions/src/health_nutrition_engine.ts      (novo — motor)
functions/src/health_nutrition_logic_test.ts  (novo)
functions/src/health_nutrition_engine_test.ts (novo)
functions/package.json                        (scripts test)
docs/health/HEALTH_V1_PHASE_5D_GATE1_MUTATION_FOUNDATION_REPORT.md
```

**Não alterados:** `functions/src/index.ts` (sem export callable), Flutter, Rules, indexes.

---

## 5. Mutation commands

| Comando | Parser |
|---------|--------|
| Planned meal | `parsePlannedMealCommand` |
| Ad hoc meal | `parseAdhocMealCommand` |
| Supplement | `parseSupplementCommand` |

Rejeita injeção de `recorded_by`, `revision`, `schema_version`, e derivados de slot no planned.

---

## 6. Authorization contract

**Permissão operacional real (Agenda / evidence em `index.ts`):**

```text
requireAccessPermission(auth, "health", "create")
+
requireDogRecordAccess(...)
```

**Não** introduz `health.record_routine` como permissão efetiva.

Gate 1: o motor **não** autentica — recebe `NutritionActor` já resolvido.  
Wiring callable + permissões = **DEFERRED GATE 2**.

---

## 7. Actor authority

Backend preenche:

```text
recorded_by { uid, name, internal_role }
recorded_at = serverNow (ISO no motor testável; FieldValue no wiring futuro)
schema_version = 1
revision = 1
```

Cliente não controla autoria.

---

## 8. Temporal authority

```text
fedAt <= serverNow
administeredAt <= serverNow
```

`serverNow` injetado. Sem tolerância arbitrária de minutos.

---

## 9. Backdated semantics

Sem janela 24h/7d/30d. Retroativo ok se:

- não futuro;
- plano histórico elegível;
- `recorded_at` server-side distinto de `fed_at`.

---

## 10. Plan historical eligibility

```text
active     + fedAt in [validFrom, validUntil) → ok
superseded + validUntil set + fedAt in range → ok
superseded + validUntil null → integrity
cancelled → reject
fedAt == validFrom → ok
fedAt == validUntil → reject (intervalo half-open)
```

---

## 11. Local service date

```text
local_service_date = civil date of fedAt in plan.timezone
```

Implementação: `Intl.DateTimeFormat` (Node, IANA). **Sem** package novo.  
Não usa device TZ, server UTC date crua, nem `recordedAt`.

---

## 12. ScheduledFor derivation

```text
localServiceDate + slot.scheduled_time + plan.timezone → Date UTC
```

via Intl offset iteration (sem luxon).

---

## 13. Meal occurrence physical identity

Preimage:

```json
["meal_occurrence_v1", dogId, planId, plannedMealId, "YYYY-MM-DD"]
```

```text
SHA-256 → mo1_<hex>
mealId = mealOccurrenceId
```

Golden test no suite.

---

## 14. Ad hoc MealLog identity

```text
["meal_log_adhoc_v1", actorUid, dogId, idempotencyKey]
→ ml1_<hex>
```

Sem plan/occurrence/scheduled_for/prescription snapshot.

---

## 15. SupplementLog identity

```text
["supplement_log_v1", actorUid, dogId, idempotencyKey]
→ sl1_<hex>
```

Dose **numérica** obrigatória (string rejeitada).

---

## 16. Fingerprints

`stableStringify` ordered; exclui recordedBy/at/revision/schema/serverNow.  
Tipos: planned_meal_v1, adhoc_meal_v1, supplement_log_v1.

---

## 17. Durable receipts

**Fonte de verdade única (dog-level registry):**

```text
dogs/{dogId}/nutrition_operations/{receiptId}

receiptId = nr1_<sha256([
  "nutrition_operation_receipt_v1",
  actorUid,
  operationType,
  operationId
])>
```

**Não** há entity-local `meal_logs/.../operations/` (evita dual source of truth e lookup subordinado a occurrence).

Body:

```text
receipt_id, operation_id, operation_type, actor_uid, fingerprint,
entity_type, entity_id, meal_occurrence_id?, result, processed_at
```

Types: `create_planned_meal` | `create_adhoc_meal` | `create_supplement_log`.

**Invariantes:** actor-scoped + dog-scoped; raw key entre atores não colide.

---

## 18. Planned meal transaction semantics

**Ordem receipt-first (durable replay):**

1. parse comando (inputs cliente)  
2. operation fingerprint (somente cliente)  
3. receiptId  
4. **lookup durable receipt** — se existe: replay / idempotency_conflict (**sem loadPlan**)  
5. se missing: serverNow, load plan, eligibility, slot, localServiceDate, scheduledFor, occurrenceId  
6. entity semantic fingerprint  
7. txn: **recheck receipt** → existing meal → create / semantic no-op / conflict  
8. create real: MealLog + durable receipt + **1 audit** (atômico)  
9. semantic no-op: durable receipt novo + **0 audit**  

**Resposta explícita:** o engine **não** decide semantic no-op só com client fingerprint; compara o MealLog canônico materializado (entity semantic fingerprint).

---

## 19. Ad hoc meal transaction semantics

ID por key; sem plano; idempotency via receipt + create_fingerprint.

---

## 20. Supplement transaction semantics

Opcional plan+regimen: valida id de regimen no plano.  
**Zero** write em `nutrition_supplements`.

---

## 21. Audit semantics

| Evento | Audits novos |
|--------|----------------|
| create | 1 |
| replay same key | 0 |
| semantic noop same occurrence | 0 |
| conflict | 0 |

---

## 22. Error taxonomy

| Código / detail | Uso |
|-----------------|-----|
| validation | D42, payload, future time |
| not-found | plan / slot / regimen |
| integrity / failed-precondition | plan integrity, cancelled eligibility |
| conflict | occurrence payload diverge |
| idempotency-conflict | same key different fingerprint |
| unauthenticated / permission-denied | Gate 2 wiring |

detailCode: `nutrition_plan_not_found`, `nutrition_plan_cancelled`, `nutrition_plan_not_effective_at_fed_at`, `nutrition_plan_integrity`, `planned_meal_not_found`, `meal_occurrence_conflict`, `idempotency_conflict`.

---

## 23. Zero dual-write proof

Engine `safeSet` rejeita paths contendo collections legadas.  
Testes assertam writes só em `meal_logs` / `supplement_logs` / `operations` / `auditLogs`.

---

## 24. Tests

```text
npm run test:health-nutrition
→ logic + engine: all passed

npm run test:health-schedule
→ all passed (sem regressão Agenda)
```

---

## 25. Build

```text
npm run build (functions)
→ tsc OK
```

---

## 26. Git diff

```text
Somente functions/src/health_nutrition_* + package.json scripts + este relatório
ZERO Flutter
ZERO index.ts export
ZERO Rules / indexes / storage
ZERO deploy config
git diff --check: OK (ao fechar)
```

---

## 27. Findings

| ID | Classe | Estado |
|----|--------|--------|
| IANA via Intl (sem luxon) | MINOR note | Aceito; coberto por testes SP/UTC |
| Auth wiring não no engine | DEFERRED GATE 2 | Esperado |
| FieldValue.serverTimestamp em prod path | DEFERRED GATE 2 | Motor usa ISO testável |
| cancel/correct meal/supplement | DEFERRED GATE 2+ | Fora do Gate 1 |
| NutritionPlan mutations | DEFERRED | Fora do Gate 1 |

**BLOCKER:** 0  
**MAJOR:** 0  

---

## 28. Deferred Gate 2 items

```text
onCall exports healthNutritionCreateMealLog / SupplementLog
App Check
transport DTO + HttpsError mapping
index.ts wiring health.create + dog access
Emulator callable tests
filtered deploy
authenticated smoke
```

---

## 29. Final readiness

```text
[x] permissões reais auditadas (health.create + dog access — wiring Gate 2)
[x] cliente não controla autoria
[x] fedAt/administeredAt por server clock
[x] localServiceDate de fedAt no TZ do plano
[x] historical plan eligibility
[x] meal occurrence hash v1
[x] planned mealId = occurrence id
[x] ad hoc / supplement IDs determinísticos
[x] fingerprints (operation + entity)
[x] receipts actor-scoped (nr1_*)
[x] occurrence uniqueness + conflict
[x] replay sem audit extra
[x] zero dual-write
[x] zero callable exportada
[x] zero Rules / deploy
[x] testes backend verdes
[x] build Functions verde
```

---

## 30. Final adversarial audit

| Campo | Valor |
|-------|-------|
| Data | 2026-07-18 |
| HEAD base | `e499f92d957d2e1e714fbf4d26fa85d831b13817` |
| Commit desta auditoria | **NÃO** |

### 30.1 MAJOR — receipt path cross-actor (corrigido)

**Bug:** `operations/{idempotencyKey}` colidia entre atores na mesma occurrence.

**Fix:**

```text
receiptId = nr1_sha256(["nutrition_operation_receipt_v1", actorUid, operationType, operationId])
path = operations/{receiptId}
body.operation_id = token lógico do cliente
```

Aplicado a planned, ad hoc e supplement.

Testes: same key actors A/B → 2 receipts, 1 meal, 0 false idempotency conflict.

### 30.2 MAJOR — semantic no-op vs authoritative drift (corrigido)

**Antes:** `decideCreateByFingerprint` usava só `create_fingerprint` (intenção cliente).

**Depois:**

| Fingerprint | Papel |
|-------------|--------|
| `create_fingerprint` / operation fingerprint | transporte / idempotência da key |
| `entity_semantic_fingerprint` | MealLog materializado (plan, slot, occurrence, period, scheduled_for, prescription, offered/consumed/acceptance/fed_at/obs/attachments) |

Semantic no-op exige **entity fingerprint igual**.  
Drift em `scheduled_for` / `period` / `prescription_amount_at_time` → `meal_occurrence_conflict`.

**Resposta:** o engine compara o **MealLog canônico materializado** (entity semantic), não somente o client fingerprint.

### 30.3 IANA / DST policy (formalizada e testada)

| Caso | Política |
|------|----------|
| timezone inválido | validation — **sem** fallback UTC/device/server |
| horário local **inexistente** (spring gap) | integrity `local_scheduled_time_nonexistent` |
| horário local **ambíguo** (fall back) | escolhe UTC **mais cedo** (earlier offset) |
| horário normal | unique instant |

Testes: `America/New_York` 2023-03-12 02:30 (gap), 2023-11-05 01:30 (ambiguous → 05:30Z), winter 07:00.

`America/Sao_Paulo` civil→instant e fedAt→localServiceDate mantidos.

### 30.4 Supplement regimen pairing

| Combinação | Resultado |
|------------|-----------|
| regimen **sem** plan | **validation** `supplement_regimen_requires_plan` |
| plan **sem** regimen | **permitido** (vínculo fraco intencional) |
| ambos | plan existe + regimen ∈ plan.supplements |

### 30.5 D39 / plan revision

Occurrence key **não** inclui planRevision.  
Mutação futura de slots no mesmo `planId` = requisito do gate de mutação de plano (não reabre D39 aqui).

### 30.6 Validações pós-correção

```text
npm run build                  → OK
npm run test:health-nutrition  → all passed
npm run test:health-schedule   → all passed
git diff --check               → OK
ZERO onCall / ZERO Flutter / ZERO Rules
```

### 30.7 Findings

| ID | Classe | Estado |
|----|--------|--------|
| Receipt path cross-actor | **MAJOR** | **CORRIGIDO** |
| Client-only semantic no-op | **MAJOR** | **CORRIGIDO** |
| DST silent / undefined | **MAJOR** risk | **CORRIGIDO** (política + testes) |
| IANA via Intl | MINOR note | Aceito com política DST |
| Gate 2 callable wiring | DEFERRED GATE 2 | — |

**BLOCKER aberto:** 0  
**MAJOR aberto:** 0  

### 30.8 Critério final

```text
[x] receipt físico actor-scoped
[x] raw key entre atores não colide
[x] operationId lógico preservado
[x] client fingerprint ≠ máscara de drift autoritativo
[x] semantic no-op valida documento materializado
[x] authoritative mismatch → conflict
[x] timezone inválido sem fallback
[x] DST ambíguo/inexistente determinístico
[x] testes DST verdes
[x] supplementRegimenId sem planId rejeitado
[x] zero dual-write / callable / Rules / deploy
[x] testes + build verdes
```

---

## 31. Durable replay final audit

| Campo | Valor |
|-------|-------|
| Data | 2026-07-18 |
| HEAD base | `e499f92d957d2e1e714fbf4d26fa85d831b13817` |
| Commit | **NÃO** |

### 31.1 Problema original (MAJOR)

Receipt era consultado **depois** de `loadPlan` + eligibility + slot.

Retry legítimo com plano já cancelled/superseded (ou loader falho) podia falhar com:

```text
nutrition_plan_cancelled
nutrition_plan_not_effective_at_fed_at
planned_meal_not_found
```

em vez de **replay**.

Causa estrutural: path entity-local exigia `mealId` (= occurrence) e portanto o plano.

### 31.2 Arquitetura escolhida

```text
SOURCE OF TRUTH:
dogs/{dogId}/nutrition_operations/{receiptId}

Entity-local operations/ :
NÃO usado (sem dual-write de receipt)
```

### 31.3 Ordem receipt-first

```text
parse → operation fingerprint → receiptId
→ getDoc(nutrition_operations/{receiptId})
  → match → REPLAY (sem plan loader)
  → mismatch → idempotency_conflict
  → missing → (só então) plan load / materialização / txn
→ txn rechecks receipt
```

Operation fingerprint **não** inclui period/scheduledFor/prescription/status do plano.

### 31.4 Testes de prova

| Cenário | Esperado | Status |
|---------|----------|--------|
| create → plan cancelled → retry | replay, loadPlanCalls=1 | OK |
| create → plan superseded → retry | replay | OK |
| create → plan loader fails on 2nd | replay, loadPlanCalls=1 | OK |
| sequential double-submit | 1 meal, 1 audit, 1 receipt | OK |
| semantic no-op other key | new registry receipt, 0 audit | OK |

### 31.5 Atomicidade

Create real na mesma txn:

```text
MealLog + nutrition_operations receipt + audit
```

Semantic no-op:

```text
nutrition_operations receipt + 0 audit
```

### 31.6 Imutabilidade estrutural de NutritionPlan (DEFERRED)

Após plano `active`, não mutar in-place `timezone` / slot ids / `scheduled_time`.  
Nova versão + supersede. **Não** implementado neste Gate — requisito para gate futuro de mutação de plano. D39 inalterado.

### 31.7 Node runtime note (MINOR / Gate 2)

```text
Dev local: Node 24
Functions engines: Node 22
```

Gate 2: validar Emulator/Intl/DST em Node 22 quando possível.

### 31.8 Validações

```text
npm run build                 → OK
npm run test:health-nutrition → all passed
npm run test:health-schedule  → all passed
npm test                      → schedule + nutrition
git diff --check              → OK
ZERO Flutter / ZERO onCall export / ZERO Rules
```

### 31.9 Findings

| ID | Classe | Estado |
|----|--------|--------|
| Durable replay after mutable plan | **MAJOR** | **CORRIGIDO** |
| Node 22 vs 24 | MINOR | Gate 2 |
| Plan structural immutability | DEFERRED | Plan mutation gate |

**BLOCKER:** 0 · **MAJOR aberto:** 0

---

## 32. Transactional plan consistency audit

| Campo | Valor |
|-------|-------|
| Data | 2026-07-18 |
| HEAD base | `e499f92d957d2e1e714fbf4d26fa85d831b13817` |
| Commit | **NÃO** |

### 32.1 TOCTOU encontrado (MAJOR)

**Antes:** para operação nova, `loadPlan` + eligibility + slot + occurrence + entity fingerprint ocorriam **fora** da transaction. Só o write era transacional.

Concorrência possível:

```text
validate active → plan cancel → still write using stale authorization
```

### 32.2 Correção

**Durable replay receipt-first preservado** (sem plan read).

**Operação nova** — autoridade do plano **somente** no snapshot da transaction:

```text
txn:
  recheck receipt
  tx.get(dogs/{dogId}/nutrition_plans/{planId})
  eligibility / slot / localServiceDate / scheduledFor / occurrence
  entity fingerprint
  tx.get meal
  create | semantic no-op | conflict
  atomic writes
```

`loadPlan` removido de `NutritionEngineDeps` (não é autoridade).

### 32.3 Supplement

- `nutritionPlanId` presente → plano **deve existir** (txn)
- + `supplementRegimenId` → regimen ∈ plan.supplements (txn)
- regimen sem plan → validation (parse)
- plan sem regimen → permitido

### 32.4 Testes TOCTOU (beforeTransaction hook)

| Cenário | Resultado |
|---------|-----------|
| active→cancelled no início da txn | reject cancelled; 0 meal/receipt/audit |
| active→superseded covering fedAt | accept |
| active→superseded excluding fedAt | reject not_effective |
| slot removido | planned_meal_not_found |
| regimen some | supplement_regimen_not_found |
| receipt + plan removed | replay (não regredido) |

### 32.5 Validações

```text
npm run build → OK
npm run test:health-nutrition → all passed
npm run test:health-schedule → all passed
npm test → all passed
git diff --check → OK
ZERO Flutter / ZERO onCall / ZERO Rules
```

### 32.6 Findings

| ID | Classe | Estado |
|----|--------|--------|
| Plan validation TOCTOU | **MAJOR** | **CORRIGIDO** |
| Durable replay after mutable plan | MAJOR | CORRIGIDO (anterior) |
| Receipt cross-actor | MAJOR | CORRIGIDO (anterior) |
| Entity semantic drift | MAJOR | CORRIGIDO (anterior) |

**BLOCKER aberto: 0**  
**MAJOR aberto: 0**

### 32.7 Critério final

```text
[x] receipt-first preservado
[x] replay sem estado mutável
[x] nova operação valida plano na transaction
[x] slot/occurrence/fingerprint do snapshot consistente
[x] TOCTOU lifecycle/vigência/slot/regimen observados
[x] atomicidade create/no-op/failure
[x] zero dual-write / callable / Rules / deploy
[x] testes + build verdes
```

---

```text
FASE 5D — GATE 1 TRANSACTIONAL CONSISTENCY AUDIT CONCLUÍDA.

ZERO BLOCKER.

ZERO MAJOR.

DURABLE REPLAY RECEIPT-FIRST PRESERVADO.

NOVAS OPERAÇÕES VALIDAM O ESTADO AUTORITATIVO DENTRO DA TRANSACTION.

MEAL OCCURRENCE DERIVADA DE SNAPSHOT CONSISTENTE.

SUPPLEMENT REGIMEN VALIDADO TRANSACIONALMENTE.

ZERO DUAL-WRITE NOVO.

ZERO CALLABLE EXPORTADA.

ZERO RULES.

ZERO DEPLOY.

GATE 1 APROVADO PARA COMMIT.

NENHUM COMMIT OU PUSH REALIZADO.
```



