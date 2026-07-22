# FASE 5D — GATE 5C.5A
## NUTRITION HISTORY / TIMELINE PROJECTION READINESS AUDIT

**Data:** 2026-07-22
**Branch:** `feature/health-v1-foundation`
**HEAD:** `b16d56f1df4406265d5e4fbdd3199e6717e54e30`
**Status:** R2 AUDIT COMPLETE

---

## 1. EXECUTIVE SUMMARY

A auditoria GATE 5C.5A R2 auditou o estado real da integração de Nutrição com a Timeline do Health v1.0.

**Descoberta central:** A coexistence timeline é um **estado transitório funcional**, não uma "implementação errada". A migração para a arquitetura canônica (projeção server-side) ainda não foi iniciada — O3 permanece aberto e bloqueia o início da implementação.

| Dimensão | Estado |
|-----------|--------|
| Contrato arquitetural (ADR-004) | ✅ DEFINED |
| health_timeline — materialization implementation | ❌ MISSING |
| health_timeline — production materialization | ⚠️ NOT VERIFIED |
| Projection Functions — local implementation | ❌ MISSING |
| Projection Functions — remote identified | ❌ NOT IDENTIFIED |
| Coexistence timeline (client-side) | ✅ FUNCTIONAL |
| O3 (SLA/Custo) | ⚠️ OPEN — GATE BLOCKER |

**Recomendação:** O próximo Gate deve ser **5C.5B — O3 PROJECTION VALIDATION** antes de iniciar a implementação das projeções.

---

## 2. GIT PREFLIGHT

```
Branch:     feature/health-v1-foundation
HEAD:       b16d56f1df4406265d5e4fbdd3199e6717e54e30
Status:     ?? functions/audit_prod.mjs (out of scope)
            ?? docs/health/HEALTH_V1_PHASE_5D_GATE5C5A_...AUDIT.md (new)
Diff:       zero whitespace errors
```

✅ Conforme esperado. Apenas `functions/audit_prod.mjs` fora do escopo.

---

## 3. CANONICAL ARCHITECTURE

### 3.1 Modelo Aprovado (ADR-004)

```
fonte canônica
    ↓
backend projector (Cloud Function)
    ↓
health_timeline (Firestore)
    ↓
reader paginado
    ↓
UI Histórico
```

### 3.2 Fontes Canônicas Faturais

| Fonte | Collection | Writer |
|-------|------------|--------|
| MealLog | `dogs/{dogId}/meal_logs/{mealId}` | Callable backend |
| SupplementLog | `dogs/{dogId}/supplement_logs/{logId}` | Callable backend |

### 3.3 Proibições Arquiteturais

- ❌ Cliente NÃO reconstrói timeline fazendo merge de MealLog/SupplementLog
- ❌ Timeline NÃO é montada client-side a partir de múltiplas coleções
- ❌ meal_logs/supplement_logs NÃO permitem write direto do cliente (Rules: DENY)

### 3.4 health_timeline — Contract Status

| Aspect | Status |
|--------|--------|
| Contract/Schema (ADR-004 + Schema §3.1) | ✅ DEFINED |
| Collection path | ✅ DEFINED: `dogs/{dogId}/health_timeline/{timelineId}` |
| Fields | ✅ DEFINED in Schema §3.1 |
| Deterministic ID formula | ✅ DEFINED: `hash(source_collection + source_id)` |
| Materialization implementation | ❌ MISSING |
| Production materialization | ⚠️ NOT VERIFIED |

---

## 4. CURRENT TIMELINE STACK

### 4.1 Coexistence Timeline (Client-Side) — FUNCIONAL

| Camada | File | Estado |
|--------|------|--------|
| Source | `coexistence_health_timeline_source.dart` | ✅ COMPLETE |
| Readers | `firestore_timeline_readers.dart` | ✅ COMPLETE |
| Mappers | `health_timeline_mappers.dart` | ✅ COMPLETE |
| Paginação | `multi_source_timeline_paginator.dart` | ✅ COMPLETE |
| UI | `health_timeline_screen.dart` | ✅ COMPLETE |
| Controller | `health_timeline_controller.dart` | ✅ COMPLETE |
| Filtros | `health_timeline_filter_*.dart` | ✅ COMPLETE |

**Fontes mapeadas (LEGACY + weight_records):**

```dart
sourceHealthEvents  = 'health_events'      // LEGACY
sourceWeightRecords = 'weight_records'      // CANONICAL (v1)
sourceFeedingEvents = 'feeding_events'      // LEGACY
sourceFeedings      = 'feedings'           // LEGACY
sourceVacinas       = 'vacinas'            // LEGACY
```

**CRÍTICO:** MealLogs e SupplementLogs **NÃO aparecem** na coexistence timeline — são projetados apenas via Nutrition UI, não via Timeline.

### 4.2 Lacunas (Não Implementadas)

| Componente | Estado | Evidência |
|------------|--------|-----------|
| Materialization implementation | ❌ MISSING | Código local não implementa writer |
| Dedicated projection Functions | ❌ NOT IDENTIFIED | `functions/src/index.ts` sem referências; listagem remota sem matches |
| Firestore triggers | ❌ MISSING | Zero triggers implementados |
| Deterministic ID implementation | ❌ MISSING | Fórmula definida, implementação ausente |
| `reconcileTimeline()` | ❌ MISSING | Sem scheduled function |

### 4.3 Status Transicional

A coexistence timeline é **funcional e correta para seu propósito transitório**. Não é uma implementação "errada" — é a estratégia de migração gradual que permite usar o sistema enquanto a arquitetura canônica é construída.

---

## 5. O3 STATUS

**O3:** Custo/SLA final das projeções — Functions e reconciliação

### 5.1 Tracking Documentado

O Foundation Review (§4.1) registra O3 com subquestões abertas:

- [ ] Granularidade da timeline (item individually vs. grouped)
- [ ] **SLA da projeção:** target ~10s; acceptance window up to 30s com `sync_pending`
- [ ] Frequência da reconciliação automática (proposta: diária)
- [ ] Limite de itens na projeção (proposta: manter tudo; paginação por cursor)

### 5.2 Evidência de Resolução

| Subquestão | Evidência | Status |
|------------|-----------|--------|
| SLA ~10s/30s | ❌ Nenhuma medição em produção | **OPEN** |
| Reconciliação diária | ❌ Nenhuma scheduled function implantada | **OPEN** |
| Cursor pagination (canônica) | ⚠️ Parcial (coexistence) | **PARTIAL** |
| Deterministic ID implementation | ❌ Não implementado localmente | **OPEN** |
| Idempotência (projection) | ⚠️ MealLog/SupplementLog tem receipt, mas sem projection | **PARTIAL** |
| Retry strategy | ❌ Não documentado | **OPEN** |
| Cost estimate | ❌ Não calculado | **OPEN** |

### 5.3 Classificação O3

```
O3 = OPEN
```

**Dependência:** O3 é **GATE BLOCKER** — bloqueia o início da implementação produtiva das projeções.

---

## 6. MEALLOG PROJECTION READINESS

### 6.1 Domain Model

| Componente | File | Estado |
|------------|------|--------|
| MealLog class | `health_v1_models.dart:471+` | ✅ COMPLETE |
| meal_occurrence_id | Algorítmico definido | ⚠️ PARCIAL - "não congelado no Domain Model" |
| Fingerprint | `health_nutrition_logic.ts` | ✅ COMPLETE |

### 6.2 MealLog → Timeline Entry

| Campo | Status | Evidência |
|-------|--------|-----------|
| `timeline_type` | ✅ ARCHITECTURAL CONTRACT | Schema §3.1 define `meal` |
| `source_collection` | ⚠️ FIELD CONTRACT ✅ / EXACT VALUE TBD | canonical MealLog source path — **TO BE FROZEN** (impacta deterministic ID hash) |
| `source_id` | ✅ ARCHITECTURAL CONTRACT | MealLog ID |
| `occurred_at` | ⚠️ SEMANTICALLY EXPECTED | `fed_at` — REQUIRES CONTRACT FREEZE |
| `recorded_at` | ✅ ARCHITECTURAL CONTRACT | Creation timestamp |
| `title` | ⚠️ PROPOSED MAPPING | `"Refeição" + food_name` — TO BE FROZEN |
| `subtitle` | ⚠️ PROPOSED MAPPING | planned/ad_hoc + acceptance — TO BE FROZEN |
| `status` | ✅ ARCHITECTURAL CONTRACT | `"final"` para fatos |

### 6.3 Planned vs Ad Hoc

| Tipo | Source Key | Distinção |
|------|------------|-----------|
| Planned | `mo1_*` | Via NutritionPlan |
| Ad Hoc | `ml1_*` | MealLog avulso |

### 6.4 Readiness

```
MealLog Projection: NOT READY (IMPLEMENTATION GAP)
- Canonical source: ✅ EXISTS
- Projection function: ❌ MISSING
- Trigger: ❌ MISSING
- Deterministic ID: ❌ MISSING (formula defined, implementation missing)
```

---

## 7. SUPPLEMENTLOG PROJECTION READINESS

### 7.1 Domain Model

| Componente | File | Estado |
|------------|------|--------|
| SupplementLog class | `supplement_log.dart` | ✅ COMPLETE |
| administered_at | Factual | ✅ COMPLETE |
| Fingerprint | `health_nutrition_logic.ts` | ✅ COMPLETE |

### 7.2 SupplementLog → Timeline Entry

| Campo | Status | Evidência |
|-------|--------|-----------|
| `timeline_type` | ✅ ARCHITECTURAL CONTRACT | Schema §3.1 define `supplement` |
| `source_collection` | ⚠️ FIELD CONTRACT ✅ / EXACT VALUE TBD | canonical SupplementLog source path — **TO BE FROZEN** (impacta deterministic ID hash) |
| `source_id` | ✅ ARCHITECTURAL CONTRACT | SupplementLog ID |
| `occurred_at` | ⚠️ SEMANTICALLY EXPECTED | `administered_at` — REQUIRES CONTRACT FREEZE |
| `recorded_at` | ✅ ARCHITECTURAL CONTRACT | Creation timestamp |
| `title` | ⚠️ PROPOSED MAPPING | supplement name — TO BE FROZEN |
| `subtitle` | ⚠️ PROPOSED MAPPING | dosage + unit — TO BE FROZEN |
| `status` | ✅ ARCHITECTURAL CONTRACT | `"final"` para fatos |

### 7.3 Readiness

```
SupplementLog Projection: NOT READY (IMPLEMENTATION GAP)
- Canonical source: ✅ EXISTS
- Projection function: ❌ MISSING
- Trigger: ❌ MISSING
- Deterministic ID: ❌ MISSING (formula defined, implementation missing)
```

---

## 8. PRODUCTION EVIDENCE READ-ONLY CHECK

### 8.1 Verificação Remota

#### Cloud Functions Implantadas

```
$ npx firebase functions:list | grep -iE "timeline|project|reconcile|healthTimeline|healthSummary"

Result: No timeline-related functions found in deployment
```

**Conclusão:** Nenhuma Function dedicada relacionada a timeline/projection/reconciliation foi identificada na listagem remota auditada. Isto não constitui prova de ausência de documentos históricos ou de writers antigos/genéricos não rastreáveis pelos critérios de busca utilizados.

#### Firestore Collection health_timeline

**Verificação direta:** NÃO EXECUTADA nesta auditoria (requer acesso de leitura específico)

### 8.2 Evento Real

| Campo | Valor |
|-------|-------|
| Dog | Bono |
| dogId | `4DDeRe7CCjTte6nbUbrC` |
| SupplementLog | `sl1_dbfca803cfece798974cc0ad01ca2858ee0c1fc35a8a0db68a0b8d5b85dc8638` |
| Operation ID | `d0552ca5-baeb-45db-aa60-50246ba31256` |

### 8.3 Análise Separada

| Verificação | Resultado |
|-------------|-----------|
| **Local projection implementation** | ❌ MISSING |
| **Dedicated remote projection Functions (audited naming)** | ❌ NOT IDENTIFIED |
| **Production health_timeline materialization** | ⚠️ NOT VERIFIED |

### 8.4 Conclusão

A auditoria verificou que:
- Nenhum projector foi encontrado no código local auditado
- Nenhuma Function dedicada relacionada foi identificada na listagem remota pesquisada
- A collection produtiva não foi lida diretamente

O estado da materialização em produção permanece **NOT VERIFIED**.

---

## 9. LEGACY/DEDUPE

### 9.1 Legacy Collections

| Collection | Propósito | Status |
|------------|-----------|--------|
| `feeding_events` | Meals legados | Read-only (Rules) |
| `feedings` | Meals legados alt | Read-only (Rules) |
| `nutrition_supplements` | Supplements regime legados | Read-only (Rules) |

### 9.2 Adapter Histórico

| File | Propósito |
|------|-----------|
| `legacy_nutrition_adapters.dart` | `LegacyNutritionAdapter` para meals |
| `legacy_supplement_regimen_adapter.dart` | `nutrition_supplements` → `LegacySupplementRegimenView` |

**CRÍTICO:** `nutrition_supplements` NUNCA vaza para `SupplementLog` (D16).

### 9.3 Dedupe Strategy Atual (Coexistence)

| Estratégia | Implementação |
|------------|---------------|
| Provenance | `legacySource + legacyId` (não apenas `legacyId`) |
| Precedência | `feeding_events` > `feedings` |
| Backfill | NÃO IMPLEMENTADO |

### 9.4 Risco Canonical × Legacy Duplicate Projection

**⚠️ REQUIRES EXPLICIT STRATEGY BEFORE BACKFILL/CUTOVER**

| Afirmação | Análise |
|-----------|---------|
| "IDs diferentes (mo1_/ml1_) reduzem risco de duplicação" | **INCORRETO** |

**Análise:**
- IDs diferentes não impedem duplicação semântica
- Um registro legado e um MealLog canônico podem representar o **mesmo fato real** com IDs completamente diferentes
- Se ambos forem projetados para `health_timeline`, haverá **duas entries** para o mesmo evento

**ADR-004 previsão:**
- Backfill dos legados
- Rastreabilidade por `source_collection` + `source_id`
- Estratégia de dedupe semântica ainda não definida

**Decisão requerida (futuro Gate):**
- Canonical × legacy deduplication strategy
- Cutover procedure: quando migrar de coexistence para canônica
- Backfill order: legados primeiro vs. canônicos primeiro

### 9.5 nutrition_supplements — Conflito Semântico

**⚠️ ARCHITECTURAL/MIGRATION RECONCILIATION REQUIRED**

| Aspecto | Estado |
|---------|--------|
| Código atual | `nutrition_supplements` → `LegacySupplementRegimenView` (regime/prescrição) |
| ADR-004 (histórico) | Menciona projetar `nutrition_supplements` como "administrações" |
| Decisões D1–D42 | `nutrition_supplements` ≠ administração factual |

**Problema:** A linguagem do ADR-004 sobre backfill de `nutrition_supplements` pode estar semanticamente desatualizada após as decisões de Nutrição.

**Registro:**
- `nutrition_supplements` legado = regime/prescrição (não necessariamente administração real)
- `SupplementLog` canônico = exclusivamente fato real de administração
- Backfill futuro NÃO pode transformar prescrição em administração factual sem evidência

**Não resolver neste Gate. Registrar como dependência de migração.**

---

## 10. TIMELINE UI AUDIT

### 10.1 Health v1 Timeline Screen

| Aspecto | Estado | Notas |
|---------|--------|-------|
| Aba Histórico existe | ✅ | `health_timeline_screen.dart` |
| Usa projeção canônica | ❌ | Usa coexistence (state transitório) |
| MealLogs aparecem | ❌ | `feeding_events` aparece, `meal_logs` NÃO |
| SupplementLogs aparecem | ❌ | Legacy regime aparece, `supplement_logs` NÃO |
| Placeholders/mocks | ❌ | Dados reais de legacy |
| Paginação real | ✅ | `multi_source_timeline_paginator.dart` |
| Filtros reais | ✅ | Por tipo, período, profissional |
| Empty/Loading/Error | ✅ | Handled |
| Permissions | ✅ | Rules validam acesso |

### 10.2 Status

A UI Timeline **EXISTE e FUNCIONA** em modo coexistence. A migração para `health_timeline` canônica será feita quando a infraestrutura de projeção estiver pronta.

---

## 11. PAGINATION/INDEXES

### 11.1 Contrato (ADR-004 / Schema §3.1)

```
dogs/{dogId}/health_timeline
orderBy: occurred_at DESC
paginação: cursor-based
```

### 11.2 Índices Definidos no Contrato

| Índice | Collection Group |
|---------|------------------|
| `occurred_at DESC` | health_timeline |
| `timeline_type ASC, occurred_at DESC` | health_timeline |
| `case_id ASC, occurred_at DESC` | health_timeline |
| `dog_id ASC, occurred_at DESC` | health_timeline |

### 11.3 Status dos Índices

| Verificação | Resultado |
|--------------|-----------|
| Repository configuration (`firestore.indexes.json`) | ❌ NOT PRESENT |
| Remote deployment status | ⚠️ UNVERIFIED |

**Análise:** O arquivo `firestore.indexes.json` no repositório NÃO contém nenhum índice para `health_timeline`. Os índices do Schema §3.1 não estão configurados no repositório.

### 11.4 Cursor Atual (Coexistence)

A coexistence implementa cursor-based pagination, mas opera em collections legadas, não em `health_timeline`.

---

## 12. RULES

### 12.1 Rules Definition

| Regra | Esperado | Status |
|-------|----------|--------|
| READ: cliente autorizado | ✅ | `canAccessDogRecord` existe |
| WRITE: DENY cliente | ✅ | Implicit (ausência de regra WRITE = DENY) |
| Admin SDK / Function | ✅ | Via service account |

### 12.2 Regras Específicas health_timeline

| Verificação | Status |
|-------------|--------|
| Regras definidas para `dogs/{dogId}/health_timeline/{timelineId}` | ⚠️ UNVERIFIED |

**Nota:** Não foi localizada uma verificação explícita do match de regras para `health_timeline` nesta auditoria. A inferência de que regras existem baseando-se na estrutura geral de `canAccessDogRecord` não constitui evidência suficiente.

### 12.3 Rules Test Coverage

| Verificação | Status |
|-------------|--------|
| health_timeline read test coverage | ❌ MISSING |
| health_timeline write DENY test coverage | ❌ MISSING |
| Emulator tests específicos | ❌ MISSING |

### 12.4 Classification

```
Rules definition:         ⚠️ UNVERIFIED (specific match not confirmed)
Rules test coverage:      ❌ MISSING
```

---

## 13. TEST COVERAGE

### 13.1 Timeline Tests (Dart)

| Test File | Cobertura |
|-----------|-----------|
| `health_timeline_controller_test.dart` | Controller, paginação |
| `health_timeline_view_test.dart` | Renderização |
| `health_timeline_grouping_test.dart` | Agrupamento por dia |
| `health_timeline_filters_3d_test.dart` | Filtros |
| `coexistence_health_timeline_source_test.dart` | Multi-source |
| `health_timeline_contracts_test.dart` | Contratos |
| (11+ mais) | Fase 3A-3E |

**Total:** 19+ testes para Timeline coexistence

### 13.2 Projection Tests (MJS)

| Test | Status |
|------|--------|
| timeline parser | ❌ NÃO EXISTE |
| timeline query | ❌ NÃO EXISTE |
| cursor pagination (canônica) | ❌ NÃO EXISTE |
| MealLog projection | ❌ NÃO EXISTE |
| SupplementLog projection | ❌ NÃO EXISTE |
| idempotency (projection) | ❌ NÃO EXISTE |
| deterministic ID | ❌ NÃO EXISTE |
| retry/reconciliation | ❌ NÃO EXISTE |
| Rules (health_timeline) | ❌ NÃO EXISTE |
| Emulator projection | ❌ NÃO EXISTE |

### 13.3 Classification

```
Test Coverage para UI Timeline:  ✅ COMPLETE (19+)
Test Coverage para Projection:   ❌ MISSING
```

---

## 14. HEALTH SUMMARY OBSERVATIONS

### 14.1 Relação com Nutrição

| Componente | Estado | Gap |
|------------|--------|-----|
| Active nutrition plan | ✅ Implementado | Nenhum |
| MealLogs | ⚠️ Domain completo | Projection missing |
| SupplementLogs | ⚠️ Domain completo | Projection missing |
| Timeline integrada | ❌ | health_timeline não materializada |
| health_summary/current | ❌ | NÃO IMPLEMENTADO |

### 14.2 Observação

`health_summary/current` está fora do escopo funcional deste Gate (Nutrition History / Timeline). A ausência é uma **FUTURE PROJECTION GAP**, não um finding do Gate 5C.5A.

---

## 15. GATE 5C.3C INTERACTION

**Gate 5C.3C:** PRECONDITIONS READY — WAITING FOR LEGITIMATE AD HOC MEAL EVENT

### 15.1 Status

```
Gate 5C.3C: ABERTO (aguardando evento real)
```

### 15.2 Impacto na Timeline

| Pergunta | Resposta |
|----------|----------|
| 5C.3C bloqueia desenvolvimento Timeline? | ❌ NÃO |
| 5C.3C bloqueia O3 validation? | ❌ NÃO |
| 5C.3C bloqueia implementação foundation? | ❌ NÃO |
| 5C.3C bloqueia Emulator tests? | ❌ NÃO |

### 15.3 O que 5C.3C bloqueia

- A **ativação produtiva** de MealLog ad hoc → timeline projection
- Until a legitimate ad hoc meal event occurs

### 15.4 Conclusão

A ausência de evento ad hoc legítimo **NÃO bloqueia** o desenvolvimento, auditoria, ou O3 validation da Timeline.

---

## 16. FINDINGS (R2)

### Classificação Rigorosa

| ID | Categoria | Descrição | Severidade |
|----|-----------|-----------|------------|
| F-01 | IMPLEMENTATION GAP | health_timeline materialization/writer implementation = MISSING | MAJOR |
| F-02 | IMPLEMENTATION GAP | Projector server-side não implementado | MAJOR |
| F-03 | **ARCHITECTURAL DEPENDENCY / GATE BLOCKER** | **O3 permanece OPEN — bloqueia início da implementação produtiva** | **CRITICAL** |
| F-04 | IMPLEMENTATION GAP / UNVERIFIED | Índices health_timeline missing in repository; remote deployment UNVERIFIED | MINOR |
| F-05 | IMPLEMENTATION GAP | MealLog projection ausente | MAJOR |
| F-06 | IMPLEMENTATION GAP | SupplementLog projection ausente | MAJOR |
| F-07 | TRANSITIONAL STATE | UI permanece na coexistence timeline | OBSERVATION |
| F-08 | MISSING TEST | Cobertura de projeção ainda não existe | MAJOR |
| F-09 | IMPLEMENTATION GAP | Deterministic ID implementation missing (formula DEFINED) | MINOR |
| F-10 | OBSERVATION | health_summary/current não implementado | INFO |
| F-11 | OBSERVATION | Coexistence timeline funciona mas está divergente da arquitetura final | INFO |
| F-12 | **ARCHITECTURAL/MIGRATION DEPENDENCY** | Canonical × legacy duplicate projection risk — requer estratégia explícita antes de backfill/cutover | MAJOR |
| F-13 | **ARCHITECTURAL/MIGRATION DEPENDENCY** | Conflito semântico nutrition_supplements vs SupplementLog — ADR-004 pode estar desatualizado | MAJOR |
| F-14 | **UNVERIFIED** | Rules definition para health_timeline não verificada explicitamente | MINOR |
| F-15 | MISSING TEST | Rules test coverage específica para health_timeline | MINOR |

---

## 17. EXACT GAP LIST

### Infraestrutura (Prerequisites)

```
ARCHITECTURAL CONTRACTS: DEFINED ✅
- Collection path: defined
- Fields: defined
- Deterministic ID formula: defined
- Writer semantics: defined

IMPLEMENTATION GAPS:
1. health_timeline materialization/writer implementation
2. Índices para health_timeline (not in repository)
3. Cloud Functions: projectTimelineEntry()
4. Cloud Functions: reconcileTimeline() (scheduled)
5. Deterministic ID: implementation missing
6. Firestore triggers (minimum: onCreate)
7. O3 validation: SLA ~10s, cost estimate, reconciliation frequency
8. Tests: projection MJS tests

ARCHITECTURAL DEPENDENCIES (GATE BLOCKERS):
1. O3 must be resolved before productive implementation

ARCHITECTURAL/MIGRATION DEPENDENCIES:
1. Canonical × legacy dedupe strategy required before backfill
2. nutrition_supplements semantic reconciliation before backfill
```

### Trigger Strategy

**Minimum required:**
- Projection handling for creation of canonical MealLog and SupplementLog (onCreate)

**Additional propagation:**
- Update/delete/amendment/cancellation: TO BE DEFINED according to canonical immutability and amendment contracts
- Não introduzir update/delete direto em fatos imutáveis sem decisão explícita

### MealLog

```
IMPLEMENTATION GAPS:
1. MealLog → timeline_type = "meal" [CONTRACT ✅]
2. occurred_at = fed_at [SEMANTICALLY EXPECTED / TO BE FROZEN]
3. title = "Refeição" + food_name [PROPOSED MAPPING / TO BE FROZEN]
4. subtitle = planned/ad_hoc + acceptance [PROPOSED MAPPING / TO BE FROZEN]
5. source_collection = canonical MealLog source path [FIELD CONTRACT ✅ / EXACT VALUE TO BE FROZEN — impacts deterministic ID hash]
6. Trigger: onCreate em meal_logs [MINIMUM REQUIRED]
```

### SupplementLog

```
IMPLEMENTATION GAPS:
1. SupplementLog → timeline_type = "supplement" [CONTRACT ✅]
2. occurred_at = administered_at [SEMANTICALLY EXPECTED / TO BE FROZEN]
3. title = supplement name [PROPOSED MAPPING / TO BE FROZEN]
4. subtitle = dosage + unit [PROPOSED MAPPING / TO BE FROZEN]
5. source_collection = canonical SupplementLog source path [FIELD CONTRACT ✅ / EXACT VALUE TO BE FROZEN — impacts deterministic ID hash]
6. Trigger: onCreate em supplement_logs [MINIMUM REQUIRED]
```

---

## 18. RECOMMENDED NEXT GATE

### Análise

| Rota | Condição | Resultado |
|------|----------|-----------|
| A) 5C.5B — TIMELINE PROJECTION FOUNDATION | O3 fechado + infraestrutura missing | ❌ O3 OPEN |
| B) 5C.5B — O3 PROJECTION VALIDATION | O3 aberto | ✅ RECOMENDADO |
| C) 5C.5B — NUTRITION TIMELINE INTEGRATION | O3 fechado + infrastructure ready | ❌ O3 OPEN |
| D) Outro escopo | — | ❌ Não aplicável |

### Recomendação

```
ROTA B: 5C.5B — O3 PROJECTION VALIDATION
```

**Justificativa:**
1. O3 é dependência arquitetural explícita (Foundation Review §4.1)
2. O3 não pode ser resolvido retrospetivamente após implementação
3. A infraestrutura completa (Functions, triggers, indexes) está missing
4. Validar O3 antes de implementar evita rework

### Escopo 5C.5B Proposto (R2 Refinado)

```
PHASE 5C.5B — O3 PROJECTION VALIDATION

Este Gate valida os parâmetros operacionais e comportamento das projeções
via Emulator tests ANTES de iniciar a implementação produtiva.

NÃO:
- Implementar projection functions em produção
- Fazer deploy de triggers ativos
- Modificar dados reais em produção

FAZER:

A. Congelar parâmetros operacionais:
   - Granularidade: item individually vs. grouped
   - Reconciliation frequency: diária vs weekly
   - Retained history: manter tudo vs. janela
   - sync_pending acceptance window: ~30s

B. Criar modelo de custo com volume esperado:
   - Writes/month projetado
   - Função pricing (Blaze plan)
   - Custo mensal/annual

C. Criar prototype/harness EM EMULATOR ONLY:
   - Deterministic ID: hash(source_collection + source_id)
   - Idempotency: retry same trigger → same result
   - Retry behavior: simulate failure → verify retry
   - Reconciliation algorithm: count comparison logic
   - Functional propagation timing: emulator baseline

D. Criar Function skeleton (não ativar):
   - projectTimelineEntry() stub
   - Sem trigger real conectado
   - Para validação de estrutura

E. Documentar limitações:
   - Emulator timing ≠ SLA real de produção
   - Valida comportamento e fornece baseline local
   - Aceitação produtiva SLA confirmada posteriormente em smoke test controlado

F. Definir estratégia dedupe:
   - Canonical × legacy duplicate prevention
   - Ordem de backfill
   - Cutover procedure
```

---

## 19. GIT FINAL STATE

```bash
$ git status --short
?? functions/audit_prod.mjs                          (out of scope)
?? docs/health/HEALTH_V1_PHASE_5D_GATE5C5A_...AUDIT.md (new report)

$ git diff --check
(no output - zero whitespace errors)

$ git diff --stat
docs/health/HEALTH_V1_PHASE_5D_GATE5C5A_...AUDIT.md
```

---

## 20. VERDICT

```
╔══════════════════════════════════════════════════════════════════════╗
║                    GATE 5C.5A R2 VERDICT                      ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  STATUS:  GATE 5C.5A R2 READY FOR HUMAN AUDIT                 ║
║                                                                      ║
║  STATE:   R2 AUDIT COMPLETE                                       ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  PRODUCTION STATE:                                               ║
║  ───────────────────────────────────────────────────────────────  ║
║  Local projection implementation:        MISSING                   ║
║  Dedicated remote projection Functions: NOT IDENTIFIED            ║
║  Production health_timeline materialization: NOT VERIFIED        ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  ARCHITECTURE:                                                   ║
║  ───────────────────────────────────────────────────────────────  ║
║  • ADR-004 contract: DEFINED                                     ║
║  • health_timeline schema: DEFINED                              ║
║  • Deterministic ID formula: DEFINED                            ║
║  • Materialization implementation: MISSING                       ║
║  • Production materialization: NOT VERIFIED                       ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  FINDINGS SUMMARY:                                               ║
║  ───────────────────────────────────────────────────────────────  ║
║  Product defect BLOCKER: 0                                       ║
║  Gate-blocking architectural dependencies: 1 (O3)                  ║
║  Implementation gaps: 6                                          ║
║  Architectural/migration dependencies: 2                          ║
║  Missing tests: 2                                                ║
║  Unverified: 2                                                  ║
║  Observations: 3                                                 ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  KEY FINDINGS:                                                   ║
║  ───────────────────────────────────────────────────────────────  ║
║  F-03: O3 OPEN — GATE BLOCKER                                   ║
║        Must be resolved before productive implementation          ║
║                                                                      ║
║  F-12: Canonical × legacy dedupe: REQUIRES STRATEGY              ║
║                                                                      ║
║  F-13: nutrition_supplements semantics: CONFLICT DETECTED          ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  RECOMMENDED NEXT GATE:                                           ║
║  ───────────────────────────────────────────────────────────────  ║
║  5C.5B — O3 PROJECTION VALIDATION                               ║
║                                                                      ║
║  Reason: O3 blocks productive activation of projections.             ║
║  Must validate SLA/cost/reconciliation via Emulator before          ║
║  implementing.                                                      ║
║                                                                      ║
║  Scope: O3 validation via Emulator, NOT production implementation.   ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  GATE 5C.3C STATUS:                                              ║
║  ───────────────────────────────────────────────────────────────  ║
║  PRECONDITIONS READY — WAITING FOR LEGITIMATE AD HOC MEAL EVENT  ║
║                                                                      ║
║  Does NOT block: Timeline development, O3 validation, Emulator tests ║
║  DOES block: Productive activation of MealLog ad hoc → timeline     ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  R2 CORRECTIONS APPLIED:                                         ║
║  ───────────────────────────────────────────────────────────────  ║
║  ✅ NOT MATERIALIZED → NOT VERIFIED for production               ║
║  ✅ O3 consolidated to single F-03 (GATE BLOCKER)                ║
║  ✅ health_timeline contract = DEFINED (not missing)             ║
║  ✅ Materialization = MISSING, not "collection definition"       ║
║  ✅ Deterministic ID: formula DEFINED, implementation MISSING   ║
║  ✅ Mappings separated: frozen contracts vs proposed            ║
║  ✅ Trigger strategy: minimum onCreate, additional TBD          ║
║  ✅ Rules: definition UNVERIFIED (specific match not confirmed) ║
║  ✅ Audit trail: corrected to 2026-07-22                          ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## ANEXO: Architecture State Summary (R2)

```
ADR-004 Contract:                    IMPLEMENTATION STATUS:
────────────────────────────────────────────────────────────────
health_timeline contract/schema:     ████████████ DEFINED █████████
health_timeline materialization:     ░░░░░░░░░ MISSING ░░░░░░░░░
Production health_timeline:        ░░░░░░░░░ NOT VERIFIED ░░░░░
health_summary contract:            ████████████ DEFINED █████████
health_summary materialization:     ░░░░░░░░░ MISSING ░░░░░░░░░
Cloud Functions (projection):      ░░░░░░░░░ MISSING ░░░░░░░░░
Dedicated remote Functions:        ░░░░░░░░░ NOT IDENTIFIED ░░░░░
Firestore triggers:                  ░░░░░░░░░ MISSING ░░░░░░░░░
Deterministic ID formula:          ████████████ DEFINED █████████
Deterministic ID implementation:   ░░░░░░░░░ MISSING ░░░░░░░░░
Indexes (repository):               ░░░░░░░░░ MISSING ░░░░░░░░░
Indexes (remote):                 ░░░░░░░░░ UNVERIFIED ░░░░░░░░░
O3 validation:                      ░░░░░░░░░  OPEN   ░░░░░░░░░
Domain models:                      ████████████████████ COMPLETE
Client-side coexistence:            ████████████████████ FUNCTIONAL
UI/presentation layer:              ████████████████████ COMPLETE
Rules definition:                 ░░░░░░░░░ UNVERIFIED ░░░░░░░░░
Rules test coverage:               ░░░░░░░░░  MISSING ░░░░░░░░░
Tests (UI):                        ████████████████████ COMPLETE (19+)
Tests (projection):                 ░░░░░░░░░  ZERO  ░░░░░░░░░
```

---

## AUDIT TRAIL

| Ronde | Data | Status | Observação |
|--------|------|--------|------------|
| Initial | 2026-07-22 | NOT APPROVED | Problemas de integridade identificados |
| R1 | 2026-07-22 | NOT YET APPROVED | 7 correções aplicadas |
| R2 | 2026-07-22 | READY FOR HUMAN AUDIT | 10 correções aplicadas |
