# FASE 5D — GATE 5C.5B.2
## O3 BEHAVIOR PROTOTYPE VALIDATION REPORT

**Data:** 2026-07-22
**Branch:** `feature/health-v1-foundation`
**Baseline HEAD antes do checkpoint:** `2093e7a58311c0f3c44befef58a07020c4f3f06a` (`docs(health): freeze O3 projection decisions`)
**Status:** ✅ GATE 5C.5B.2 — HUMAN AUDIT APPROVED

---

## 1. EXECUTIVE SUMMARY

Este Gate valida behavior do modelo de projeção `health_timeline` definido e congelado no Gate 5C.5B.1 (O3-D1 a O3-D8 FROZEN).

**Resultado:** O3 BEHAVIOR VALIDATION PASSED

| Componente | Status |
|------------|--------|
| Deterministic Timeline ID | ✅ VALIDATED |
| MealLog Projection | ✅ VALIDATED |
| SupplementLog Projection | ✅ VALIDATED |
| Equivalence Model | ✅ VALIDATED |
| Projection Idempotency | ✅ VALIDATED |
| Reconciliation States | ✅ VALIDATED |
| Equal-Counts Inconsistency Detection | ✅ DETECTED |
| Legacy Classification | ✅ VALIDATED |
| Zero Legacy Writes | ✅ VERIFIED |
| Bounded Reconciliation | ✅ VALIDATED |
| **projected_at Contract** | ✅ **VALIDATED (R3)** |
| **recorded_by Full Comparison** | ✅ **VALIDATED (R5)** |
| **acceptance=unknown** | ✅ **VALIDATED (R5)** |
| **Freshness Cursor Tie-Break** | ✅ **VALIDATED (R5)** |
| **Freshness Pass Pagination (R6)** | ✅ **BOUNDED with LIMIT+startAfter** |
| **Overlap Replay Pass (R6)** | ✅ **BOUNDED + idempotent + forward-cursor-safe** |

**Gate Verdict:** ✅ **GATE 5C.5B.2 — HUMAN AUDIT APPROVED**
**Evidência de execução:** 38 unit + 15 E2E no Emulator Firestore real (`127.0.0.1:8080`), EXIT CODE 0.

---

## 2. GIT PREFLIGHT

```
HEAD:        2093e7a58311c0f3c44befef58a07020c4f3f06a
Subject:     docs(health): freeze O3 projection decisions
Branch:      feature/health-v1-foundation
Baseline:    arquivos do Gate são untracked (novos), sobre HEAD 2093e7a
Divergência: 0/0 contra origin/feature/health-v1-foundation
Diff check: zero whitespace errors (git diff --check limpo)
```

**Nota de baseline:** o preflight final confirmou o worktree Health isolado na
branch `feature/health-v1-foundation`, sobre `2093e7a`. Os arquivos do Gate são
untracked (aparecem em `git status` como `??`) e serão incluídos somente no
commit de checkpoint autorizado.

**Arquivos no escopo (novos):**
- `functions/src/health_timeline_projection.ts` — módulo foundation
- `functions/src/health_timeline_projection_test.ts` — unit tests
- `functions/src/health_timeline_emulator_test.ts` — E2E tests (Emulator)

**Arquivos fora do escopo:**
- `functions/audit_prod.mjs` (acknowledged)

**Confirmado:** Nenhuma alteração em `functions/src/index.ts`, `firestore.rules`, `firestore.indexes.json`, ou código Flutter.

---

## 3. SCOPE BOUNDARIES

### 3.1 Proibido neste Gate

| Ação | Status |
|------|--------|
| Deploy produção | ❌ NÃO EXECUTADO |
| Exportar nova Function | ❌ NÃO FEITO |
| Criar trigger ativo | ❌ NÃO FEITO |
| Modificar Firestore Rules | ❌ NÃO FEITO |
| Modificar firestore.indexes.json | ❌ NÃO FEITO |
| Iniciar backfill | ❌ NÃO FEITO |
| Criar scheduled Function ativa | ❌ NÃO FEITO |
| Modificar dados legados | ❌ NÃO FEITO |
| Commit ou push | ❌ NÃO EXECUTADO |

### 3.2 Permitido neste Gate

- Módulo local não-exportado no source tree
- Testes locais/Emulator
- Validação de comportamento
- Instrumentação de operações

---

## 4. PROTOTYPE ARCHITECTURE

### 4.1 Estrutura de Arquivos

```
functions/src/
├── health_timeline_projection.ts        # Foundation module
│   ├── deriveTimelineId()              # Deterministic ID
│   ├── projectMealLog()               # MealLog → TimelineEntry
│   ├── projectSupplementLog()          # SupplementLog → TimelineEntry
│   ├── compareProjection()             # Equivalence model
│   ├── determineProjectionAction()     # State → Action mapping
│   ├── classifyLegacyEquivalence()     # Legacy classification
│   └── TEST_CONFIG                     # Test values (NOT production)
│
├── health_timeline_projection_test.ts   # Unit tests (Node.js)
│
└── health_timeline_emulator_test.ts    # E2E tests (Firestore Emulator)
```

### 4.2 Módulos Reutilizados

| Módulo | Origem | Uso |
|--------|--------|-----|
| `stableStringify()` | `health_nutrition_logic.ts` | Serialização determinística |
| `sha256Hex()` | `health_nutrition_logic.ts` | Hash SHA-256 |

---

## 5. DETERMINISTIC ID

### 5.1 Fórmula (O3-D6 FROZEN)

```
timelineId = "tl1_" + sha256Hex(stableStringify([
  "health_timeline_v1",
  source_collection,  // "dogs/{dogId}/meal_logs"
  source_id           // document ID only
]))
```

### 5.2 Testes Validados

| Teste | Resultado |
|-------|-----------|
| Mesmos inputs → mesmo ID | ✅ PASSED |
| sourceId diferente → ID diferente | ✅ PASSED |
| sourceCollection diferente → ID diferente | ✅ PASSED |
| dogId diferente no path → ID diferente | ✅ PASSED |
| Array framing evita ambiguidade | ✅ PASSED |
| Prefixo exato `tl1_` | ✅ PASSED |
| Output SHA-256 hex 64 caracteres | ✅ PASSED |

### 5.3 Golden Vector

**Input fixo:**
```typescript
{
  sourceCollection: "dogs/test/meal_logs",
  sourceId: "mo1_golden"
}
```

**Output determinístico:** `tl1_<sha256_hex>` (64 caracteres hex)

### 5.4 NÃO Incluídos no ID

| Campo | Razão |
|-------|-------|
| `occurred_at` | Timestamp — mudaria em reprojeções |
| `recorded_at` | Server time — não determinístico |
| `title` | Apresentação — pode variar |
| `subtitle` | Apresentação — pode variar |

### 5.5 Propriedades Garantidas

| Propriedade | Status |
|-------------|--------|
| Determinismo | ✅ GARANTIDO |
| Idempotência | ✅ VALIDADA |
| Colisão evitada | ✅ CRYPTOGRAPHICALLY NEGLIGIBLE |

---

## 6. MEALLOG PROJECTION

### 6.1 Mapeamento (O3-D1, O3-D5 FROZEN)

| Campo Timeline | Campo MealLog | Status |
|----------------|---------------|--------|
| `timeline_type` | `"meal"` | FROZEN |
| `source_collection` | `dogs/{dogId}/meal_logs` | FROZEN |
| `source_id` | MealLog document ID | FROZEN |
| `occurred_at` | `fed_at` | FROZEN |
| `status` | `"final"` | FROZEN |
| `recorded_at` | Preserve from source | FROZEN |
| `recorded_by` | Preserve from source | FROZEN |
| `dog_id` | `dogId` from context/path | FROZEN |
| `schema_version` | `1` (canoncial value) | FROZEN |
| `projected_at` | Execution timestamp (NOW) | FROZEN |
| `title` | PROTOTYPE PRESENTATION | VALIDADO |
| `subtitle` | PROTOTYPE PRESENTATION | VALIDADO |

### 6.2 Schema Fields

```
dog_id: dogId do contexto (path dogs/{dogId}/meal_logs)
schema_version: valor canônico = 1
projected_at: execution timestamp gerenciado pelo projector
```

### 6.3 Testes Validados

| Teste | Resultado |
|-------|-----------|
| Planned MealLog → timeline_type = meal | ✅ PASSED |
| Planned MealLog → source_collection correto | ✅ PASSED |
| Planned MealLog → source_id = document ID | ✅ PASSED |
| Planned MealLog → occurred_at = fed_at | ✅ PASSED |
| Planned MealLog → status = final | ✅ PASSED |
| Adhoc MealLog → invariantes mantidos | ✅ PASSED |
| Presentation mappings (title/subtitle) | ✅ VALIDADO |

### 6.3 Presentation Mappings

**PROTOTYPE PRESENTATION MAPPING — NÃO É CONTRATO ARQUITETURAL**

```
title: "{food_name}"
subtitle: "{kindLabel} · {acceptanceLabel}"
```

- `kindLabel`: "Planejada" ou "Avulsa"
- `acceptanceLabel`: "Completa", "Parcial", ou "Recusada"

---

## 7. SUPPLEMENTLOG PROJECTION

### 7.1 Mapeamento (O3-D1, O3-D5 FROZEN)

| Campo Timeline | Campo SupplementLog | Status |
|----------------|---------------------|--------|
| `timeline_type` | `"supplement"` | FROZEN |
| `source_collection` | `dogs/{dogId}/supplement_logs` | FROZEN |
| `source_id` | SupplementLog document ID | FROZEN |
| `occurred_at` | `administered_at` | FROZEN |
| `status` | `"final"` | FROZEN |
| `recorded_at` | Preserve from source | FROZEN |
| `recorded_by` | Preserve from source | FROZEN |
| `dog_id` | `dogId` from context/path | FROZEN |
| `schema_version` | `1` (canoncial value) | FROZEN |
| `projected_at` | Execution timestamp (NOW) | FROZEN |
| `title` | `supplement_name` | PROTOTYPE PRESENTATION |
| `subtitle` | `dose + unit` | PROTOTYPE PRESENTATION |

**PROTOTYPE PRESENTATION MAPPING — NÃO É CONTRATO ARQUITETURAL FROZEN.**

### 7.2 Schema Fields

```
dog_id: dogId do contexto (path dogs/{dogId}/supplement_logs)
schema_version: valor canônico = 1
projected_at: execution timestamp gerenciado pelo projector
```

### 7.3 Testes Validados

| Teste | Resultado |
|-------|-----------|
| SupplementLog → timeline_type = supplement | ✅ PASSED |
| SupplementLog → source_collection correto | ✅ PASSED |
| SupplementLog → source_id = document ID | ✅ PASSED |
| SupplementLog → occurred_at = administered_at | ✅ PASSED |
| SupplementLog → status = final | ✅ PASSED |
| Presentation mapping (title = supplement_name) | ✅ PASSED |
| Presentation mapping (subtitle = dose + unit) | ✅ PASSED |

---

## 8. EQUIVALENCE MODEL (R4)

### 8.1 Campos Comparados vs NÃO Comparados

**CAMPOS QUE PARTICIPAM DA EQUIVALÊNCIA:**

| Campo | Comparado | Razão |
|-------|-----------|-------|
| `timeline_type` | ✅ | Identidade de fonte |
| `source_collection` | ✅ | Identidade de fonte |
| `source_id` | ✅ | Identidade de fonte |
| `occurred_at` | ✅ | Derivado de fonte |
| `status` | ✅ | Derivado de fonte |
| `recorded_at` | ✅ | Preservado de fonte |
| `recorded_by.uid` | ✅ | Preservado de fonte |
| `recorded_by.name` | ✅ | Preservado de fonte (R5) |
| `recorded_by.internal_role` | ✅ | Preservado de fonte (R5) |
| `dog_id` | ✅ | Identidade de contexto |
| `schema_version` | ✅ | Versão do schema |
| `title` | ✅ | Persisted derived field (R4) |
| `subtitle` | ✅ | Persisted derived field (R4) |

**CAMPOS QUE NÃO PARTICIPAM DA EQUIVALÊNCIA:**

| Campo | NÃO Comparado | Razão |
|-------|--------------|-------|
| `projected_at` | ❌ | Execution timestamp — volátil |
| `created_at` | ❌ | Timestamp de execução |
| `updated_at` | ❌ | Timestamp de execução |

### 8.2 R4 Contract Clarification

```
projected_at: EXCLUDED from equivalence
- CREATE: projected_at = NOW
- REPAIR: projected_at = NOW (update)
- NO-OP: projected_at = PRESERVED

title/subtitle: INCLUDED in equivalence
- These are persisted derived fields that SHOULD be corrected on REPAIR
```

### 8.3 Testes Validados

| Teste | Resultado |
|-------|-----------|
| Entries idênticas → equivalent | ✅ PASSED |
| timeline_type diferente → divergent | ✅ PASSED |
| source_collection diferente → divergent | ✅ PASSED |
| source_id diferente → divergent | ✅ PASSED |
| occurred_at diferente → divergent | ✅ PASSED |
| status diferente → divergent | ✅ PASSED |
| Entry null → divergent | ✅ PASSED |
| title/subtitle diferente → divergent (R4: persisted derived fields) | ✅ PASSED |
| dog_id diferente → divergent | ✅ PASSED |
| projected_at diferente → equivalent (R3: volátil, não participa) | ✅ PASSED |
| recorded_by.uid diferente → divergent (R5) | ✅ PASSED |
| recorded_by.name diferente → divergent (R5) | ✅ PASSED |
| recorded_by.internal_role diferente → divergent (R5) | ✅ PASSED |
| schema_version diferente → divergent | ✅ PASSED |

---

## 8B. projected_at CONTRACT (R3)

### 8B.1 Semântica Operacional

| Operação | projected_at | Status |
|----------|-------------|--------|
| **CREATE** | `= NOW` (timestamp de execução) | ✅ FROZEN |
| **REPAIR** | `= NOW` (update, não preservar) | ✅ FROZEN |
| **NO-OP** | `= PRESERVED` (não atualizar) | ✅ FROZEN |

### 8B.2 NÃO Participa De

| Participação | Razão |
|-------------|-------|
| ID determinístico | ❌ NÃO |
| Equivalência de projeção | ❌ NÃO |

### 8B.3 Validação E2E (TEST 11)

```
11a: CREATE → projected_at = NOW ✓
11b: NO-OP → projected_at = PRESERVED (não atualiza) ✓
11c: FORCE DIVERGENT ✓
11d: REPAIR → projected_at = NOW (update) ✓
11e: timelineId unchanged after repair ✓
11f: NO-OP after REPAIR → projected_at = PRESERVED (não atualiza) ✓
11g: Projection equivalent after repair ✓
```

**Evidência:**
```
projected_at_1 (CREATE): 2026-07-22T21:59:36.090Z
projected_at_2 (REPAIR): 2026-07-22T21:59:36.200Z
projected_at_2 > projected_at_1: true ✅
```

---

---

## 9. PROJECTION IDEMPOTENCY

### 9.1 Testes Unitários

| Teste | Resultado |
|-------|-----------|
| Mesma fonte → mesmo timelineId | ✅ PASSED |
| Reprojeção → entries equivalentes | ✅ PASSED |

### 9.2 Testes Emulator (E2E)

| Teste | Resultado |
|-------|-----------|
| Primeira projeção → created | ✅ PASSED |
| Segunda projeção da mesma fonte → noop | ✅ PASSED |
| Terceira projeção da mesma fonte → noop | ✅ PASSED |
| Apenas 1 documento na timeline | ✅ PASSED |
| Multiple MealLogs idempotentes | ✅ PASSED |
| SupplementLog idempotente | ✅ PASSED |

### 9.3 Critério de Aprovação

```
Repeated projection: NO DUPLICATE
Final document count: 1 per factual source
```

**Status:** ✅ VALIDATED

---

## 10. RECONCILIATION ARCHITECTURE

### 10.1 Modelo (O3-D3 FROZEN)

```
DAILY RECONCILIATION = BOUNDED + INCREMENTAL
```

### 10.2 Componentes

| Componente | Escopo | Status |
|------------|--------|--------|
| A. Freshness Pass | Fontes novas desde cursor + LIMIT page_size | ✅ VALIDATED (R6 BOUNDED) |
| B. Historical Integrity Sweep | Página limitada de fontes históricas | ✅ VALIDATED |
| C. Orphan Integrity Sweep | Página limitada de entries | ✅ VALIDATED |
| D. Known Discrepancies | missing, divergent | ✅ VALIDATED |

### 10.3 Test Configuration (NOT PRODUCTION CONTRACT)

```typescript
const TEST_CONFIG = {
  FRESHNESS_OVERLAP_MS: 60 * 60 * 1000,   // 1 hour (TEST ONLY)
  HISTORICAL_PAGE_SIZE: 3,                  // (TEST ONLY)
  ORPHAN_PAGE_SIZE: 3,                      // (TEST ONLY)
  // NOTE: Frequencies (daily/weekly) are NOT validated by this prototype
  // O3-D3 mandates DAILY reconciliation
};
```

**⚠️ VALORES DE TESTE — NÃO SÃO CONTRATO DE PRODUÇÃO**
**⚠️ Scheduler frequencies NOT validated by prototype**

---

## 11. FRESHNESS PASS (R4, R5, R6)

### 11.1 Algoritmo — CRITICAL: BOUNDED + PAGINATED (R6)

```
Freshness Pass é EXECUTADO com PAGINATION:
1. Obter cursor persitido: (lastRecordedAt, lastDocId, pageCount)
2. Query fontes com:
   - ORDER BY recorded_at ASC, __name__ ASC
   - startAfter(lastRecordedAt, lastDocId) se cursor existir
   - LIMIT page_size
3. Para cada fonte: project ou no-op
4. Salvar cursor: (lastRecordedAt, lastDocId, pageCount)
5. Retornar hasMore = (snap.size === page_size)

CRITICAL: LIMIT page_size é OBRIGATÓRIO
O Freshness Pass NUNCA deve processar documentos ilimitados.
```

### 11.2 Cursor Contract — Pagination-aware

```
Freshness cursor: (recorded_at, documentId)
  recorded_at ASC
  documentId ASC (tie-break determinístico)

Pagination:
  - LIMIT page_size (default: 100)
  - startAfter(lastRecordedAt, lastDocId)
  - hasMore = true se full page returned
```

### 11.3 Cursor para Late Registration

```
Freshness cursor: RECORDED_AT (not occurred_at)
- MealLog: order/cursor by recorded_at + documentId
- SupplementLog: order/cursor by recorded_at + documentId

occurred_at: continua exclusivamente como timestamp factual da TimelineEntry
```

**Por que recorded_at?**

Late registration / backdated facts:
- `fed_at` = when the meal actually happened (factual)
- `recorded_at` = when the operator registered it in the system

Exemplo:
```
cursor atual: lastRecordedAt=22/07 18:00

23/07 10:00:
operador registra refeição que ocorreu em 22/07 12:00

fed_at       = 22/07 12:00
recorded_at  = 23/07 10:00

Freshness Pass deve encontrar o documento por recorded_at (não por fed_at)
```

### 11.4 Safety Overlap — DUAS PASSADAS SEPARADAS (R6)

O auditor R6 identificou corretamente que forward cursor e overlap replay são
**mecanismos distintos** e não podem ser fundidos. A implementação R6 os separa:

```
FORWARD PASS  (freshnessPass)
  → cursor monotônico (recorded_at, documentId)
  → LIMIT page_size + startAfter
  → SEMPRE avança; nunca retrocede nem bloqueia

OVERLAP REPLAY PASS  (overlapReplayPass)
  → janela BOUNDED: [forwardCursor.recorded_at - OVERLAP_MS, forwardCursor.recorded_at]
  → LIMIT page_size + cursor de overlap INDEPENDENTE
  → IDEMPOTENTE: re-projeção de fonte já projetada → NO-OP
  → NÃO lê nem move o forward cursor (forwardCursorUnchanged=true)
```

**Por que separar?** Uma escrita fora de ordem (clock skew, commits quase
simultâneos) pode cair logo atrás do forward cursor e ser pulada para sempre pela
forward pass. O overlap replay re-varre uma janela limitada atrás do cursor para
capturá-la — sem nunca retroceder o forward cursor.

- **OVERLAP TEST VALUE:** 1 hora (60 minutos) — `FRESHNESS_OVERLAP_MS`
- **PRODUCTION VALUE:** A ser calibrado em ativação produtiva

**Evidência:** TEST 15 (Emulator real) prova os cinco contratos:
1. forward pass pula a escrita fora de ordem (demonstra o gap);
2. overlap replay a captura dentro da janela bounded;
3. janela é bounded (where recorded_at BETWEEN windowStart AND windowEnd);
4. replay é idempotente (segundo run: created=0, noop=2);
5. forward cursor permanece inalterado após o replay.

### 11.5 Cursor Contract — Tie-Break

```
Freshness cursor: (recorded_at, documentId)
  recorded_at ASC
  documentId ASC (tie-break determinístico)
```

**Evidência:** TEST 13 valida que dois documentos com mesmo `recorded_at` e IDs diferentes são ambos descobertos.

### 11.6 TEST 14: Freshness Pass BOUNDED — CRITICAL R6 REQUIREMENT

```
CRITICAL R6 REQUIREMENT: Freshness Pass MUST be bounded with pagination

Teste com page_size=1 (força multi-page):
- Cria 2 documentos com mesmo recorded_at (pior caso tie-break)
- Reset cursor para antes dos documentos
- PAGE 1: processa 1 documento, hasMore=true
- PAGE 2: processa 1 documento
- PAGE 3: não processa documentos novos (ambos já projetados)

Contratos provados:
✅ BOUNDED: Full backlog NOT processed in one run (page_size=1)
✅ PAGINATION: Documents processed across pages
✅ TIE-BREAK: Both same-recorded_at docs discovered across pages
```

### 11.7 Testes Validados (R6)

| Teste | Resultado |
|-------|-----------|
| Fonte nova após cursor é processada | ✅ PASSED |
| Late registration (fed_at antigo, recorded_at agora) é descoberta | ✅ PASSED (R4) |
| Cursor tie-break (mesmo recorded_at, IDs diferentes) | ✅ PASSED (R5) |
| Freshness pass continuation via cursor | ✅ PASSED (R6) |
| Freshness pass idempotent on repeated calls | ✅ PASSED (R6) |
| recorded_by.name + internal_role preservados | ✅ PASSED (R5) |
| **CRITICAL: page_size=1 forces pagination (TEST 14)** | ✅ **PASSED (R6, Emulator real)** |
| **Overlap replay captura escrita fora de ordem (TEST 15)** | ✅ **PASSED (R6, Emulator real)** |
| **Overlap replay é bounded (janela limitada)** | ✅ **PASSED (R6)** |
| **Overlap replay é idempotente (created=0 no 2º run)** | ✅ **PASSED (R6)** |
| **Overlap replay NÃO move forward cursor** | ✅ **PASSED (R6)** |

---

## 12. HISTORICAL SWEEP

### 12.1 Algoritmo

1. Obter cursor persitido
2. Query página de fontes históricas (`LIMIT page_size`)
3. Processar página
4. Salvar cursor (lastId, pageCount)
5. Se `size < page_size` → sweep completo

### 12.2 Bounded Behavior

```
Run 1 → Processa página 1 (page_size entries)
Run 2 → Processa página 2 (page_size entries)
Run N → Processa última página, completa sweep
Próximo ciclo → Cursor reset ou continua
```

### 12.3 Testes Validados

| Teste | Resultado |
|-------|-----------|
| Cursor avança entre execuções | ✅ PASSED |
| Segunda execução continua do cursor | ✅ PASSED |
| Sweep completo respeita page_size | ✅ PASSED |
| Segunda execução não processa tudo | ✅ PASSED |
| Page size configurável | ✅ PASSED |

### 12.4 Evidência de Bounded

**Teste: `TEST 6: BOUNDED RECONCILIATION — Historical Sweep`**

```
Historical sweep page 1:
   processed: 3
   cursor.pageCount: 1
   completed: false

Historical sweep page 2:
   processed: 3
   cursor.pageCount: 2
   completed: false

Cursor lastId: advances between runs (page1.lastId != page2.lastId)
Second run processing: 3 entries (bounded by HISTORICAL_PAGE_SIZE=3)
```

**Contratos Comprovados:**

| Contrato | Teste | Resultado |
|----------|-------|-----------|
| cursor advances | TEST 6 | ✅ sweep1.cursor.lastId !== sweep2.cursor.lastId |
| second run continues | TEST 6 | ✅ second page processed |
| reaches end | TEST 6 | ✅ completed = (snap.size < pageSize) |
| wraps safely | TEST 6 | ✅ pageCount increment logic |
| page bounded | TEST 6 | ✅ secondRunProcessing ≤ HISTORICAL_PAGE_SIZE |
| full history NOT rescanned | TEST 6 | ✅ first run 3, second run 3 (not full history) |

```
✅ FULL HISTORY IS NOT RESCANNED EVERY RUN
```

---

## 13. ORPHAN SWEEP

### 13.1 Algoritmo

1. Obter cursor persitido
2. Query página de health_timeline entries
3. Para cada entry: verificar se fonte existe
4. Se fonte não existe → ORPHAN (report, NÃO delete)
5. Salvar cursor

### 13.2 NO AUTO-DELETE

```
ORPHAN detected → ALERT / REPORT
Entry permanece existente
⚠️ NO AUTO-DELETE
```

### 13.3 Testes Validados

| Teste | Resultado |
|-------|-----------|
| Orphan detectado quando fonte não existe | ✅ PASSED |
| Orphan NÃO é deletado automaticamente | ✅ PASSED |
| Cursor avança no orphan sweep | ✅ PASSED |
| Sweep permanece bounded | ✅ PASSED |

---

## 14. RECONCILIATION STATES

### 14.1 Estado → Ação

| Estado | Significado | Ação | Status |
|--------|-------------|------|--------|
| MISSING | Fonte existe, entry não existe | CREATE | ✅ VALIDATED |
| EQUIVALENT | Fonte + entry existem, igual | NO-OP | ✅ VALIDATED |
| DIVERGENT | Fonte + entry existem, diferente | REPAIR | ✅ VALIDATED |
| ORPHAN | Entry existe, fonte não existe | ALERT | ✅ VALIDATED |

### 14.2 Testes Validados

| Teste | Resultado |
|-------|-----------|
| MISSING → CREATE | ✅ PASSED |
| EQUIVALENT → NO-OP | ✅ PASSED |
| DIVERGENT → REPAIR | ✅ PASSED |
| ORPHAN → ALERT (no delete) | ✅ PASSED |

### 14.3 Divergent Repair

```
Divergent entry (wrong occurred_at) → REPAIR
After repair:
  compareProjection(expected, actual) → EQUIVALENT
✅ DIVERGENT ENTRY CORRECTED
```

---

## 15. EQUAL-COUNTS INCONSISTENCY TEST

### 15.1 Cenário Crítico

```
Sources:     [A, B, C]
Timeline:    [A, B, X]
Counts:      3 == 3 ✓

But:
  C = MISSING (source exists, no entry)
  X = ORPHAN (entry exists, no source)
```

### 15.2 Resultado do Teste

```
Source count: 3
Timeline count: 3
Counts equal: true

Missing in timeline: [mo1_eqC_<timestamp>]
Orphans in timeline: [mo1_eqX_<timestamp>]

✅ CRITICAL: COUNT EQUALITY ≠ CONSISTENCY
✅ Reconciliation correctly detects both MISSING and ORPHAN
```

### 15.3 Implicação

```
count equality
!=
consistency proof
```

Reconciliação deve comparar fonte-a-fonte, não apenas counts.

---

## 16. LEGACY / DEDUPE CLASSIFICATION

### 16.1 Classificações (O3-D7 FROZEN)

| Classificação | Condição | Auto-Dedupe |
|--------------|----------|-------------|
| STRONG_MATCH | feeding_events × feedings com legacy_id compartilhado | ✅ AUTORIZADO |
| WEAK_MATCH | Coincidência por data/horário/quantidade | ❌ PROIBIDO |
| NO_SAFE_MATCH | Sem vínculo explícito | ❌ PROIBIDO |

### 16.2 Testes Validados

| Teste | Resultado |
|-------|-----------|
| feeding_events com vínculo explícito → strong_match | ✅ PASSED |
| MealLog × feeding_events sem vínculo → no_safe_match | ✅ PASSED |
| Coincidência por data/horário → no_safe_match | ✅ PASSED |
| WEAK_MATCH nunca autoriza auto-dedupe | ✅ PASSED |

### 16.3 O3-D8: nutrition_supplements

```
nutrition_supplements = regime/prescription/configuration
SupplementLog = factual administration

O3-D8 FROZEN: NUNCA converter nutrition_supplements
automaticamente em timeline_type = supplement

✅ nutrition_supplements (regime) ≠ SupplementLog (factual)
```

---

## 17. ZERO LEGACY WRITES

### 17.1 Verificação

O módulo prototype é **PURO** (sem side-effects de write).

Coleções que NÃO devem receber writes neste Gate:

```
- feeding_events
- feedings
- nutrition_supplements
- nutritional_prescriptions
- nutrition_prescriptions
```

### 17.2 Implementação

- Writes são executados apenas no harness de teste Emulator
- Harness escreve APENAS em:
  - `dogs/{dogId}/meal_logs` (fixtures de teste)
  - `dogs/{dogId}/supplement_logs` (fixtures de teste)
  - `health_timeline` (projeção validada)
  - `health_timeline_metadata` (watermarks/cursors de teste)

### 17.3 Status

```
✅ ZERO LEGACY WRITES: VERIFIED
```

---

## 18. OPERATION COUNTS

### 18.1 Instrumentação

```typescript
type OperationCounts = {
  sourceReads: number;      // Leituras de fonte canônica
  timelineReads: number;     // Leituras de timeline
  timelineCreates: number;  // Creates na timeline
  timelineRepairs: number;  // Repairs na timeline
  noOps: number;            // No-ops (equivalent)
  orphanChecks: number;     // Verificações de órfão
};
```

### 18.2 Cenários Instrumentados

| Cenário | source_reads | timeline_reads | timeline_creates | timeline_repairs | noOps | orphan_checks |
|---------|-------------|----------------|-----------------|------------------|-------|---------------|
| **MISSING → CREATE** | 1 | 1 | 1 | 0 | 0 | 0 |
| **NO-OP** (idempotência) | 1 | 1 | 0 | 0 | 1 | 0 |
| **REPAIR** (DIVERGENT) | 1 | 1 | 0 | 1 | 0 | 0 |
| **ORPHAN SWEEP** | 0 | 1 | 0 | 0 | 0 | 1 |
| **HISTORICAL PAGE** | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED |
| **FRESHNESS PASS** | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED | NOT INSTRUMENTED |

**Nota:** HISTORICAL PAGE e FRESHNESS PASS usam ProjectionEngine internamente (que instrumenta), mas o ReconciliationEngine não expõe contadores próprios para cenários compostos.

### 18.3 Counts Absolutos do E2E

**MISSING → CREATE (primeira projeção de uma fonte):**
```
sourceReads: 1
timelineReads: 1
timelineCreates: 1
timelineRepairs: 0
noOps: 0
orphanChecks: 0
```

**NO-OP (segunda/terceira projeção):**
```
sourceReads: 1
timelineReads: 1
timelineCreates: 0
timelineRepairs: 0
noOps: 1
```

**REPAIR (DIVERGENT):**
```
sourceReads: 1
timelineReads: 1
timelineCreates: 0
timelineRepairs: 1
noOps: 0
```

**ORPHAN SWEEP:**
```
orphanChecks: 1 (por entry verificada)
timelineReads: 1 (por entry verificada)
Deletes: 0 (NO AUTO-DELETE)
```

---

## 19. EMULATOR TIMING BASELINE

### 19.1 LOCAL EMULATOR ONLY

```
⚠️  LOCAL EMULATOR BASELINE ONLY
⚠️  NOT PRODUCTION SLA
⚠️  NOT COMPARABLE TO 10s TARGET
```

### 19.2 Timing Samples (ms) — E2E REAL EXECUTION (R4)

| Operação | Samples | Median | Min | Max |
|----------|---------|--------|-----|-----|
| ID derivation | 10+ | 0.01 | 0.00 | 0.05 |
| Single projection (create) | 5 | ~14 | ~12 | ~17 |
| Single projection (noop) | 5 | ~15 | ~13 | ~16 |
| Divergent repair | 5 | ~14 | ~12 | ~17 |

**Nota:** Historical sweep, orphan sweep e freshness pass são compostos (múltiplas operações). Não possuem amostragem de timing por página individual neste prototype.

### 19.3 Observações

- Emulator local tem latência consistente em ambiente controlado
- ID derivation: <1ms (negligível)
- Projeções: ~15ms por operação
- **NÃO** chamar de SLA ou comparar com target produtivo de 10s

---

## 20. TEST RESULTS

### 20.1 Unit Tests (Node.js)

```
=== DETERMINISTIC TIMELINE ID TESTS ===
✅ Test 1: Mesmos inputs → mesmo ID
✅ Test 2: sourceId diferente → ID diferente
✅ Test 3: sourceCollection diferente → ID diferente
✅ Test 4: dogId diferente no path → ID diferente
✅ Test 5: Array framing evita ambiguidade
✅ Test 6: Prefixo exato `tl1_`
✅ Test 7: Output SHA-256 hex (64 caracteres)
✅ GOLDEN VECTOR: VALIDATED

=== MEALLOG PROJECTION TESTS ===
✅ Test 1: Planned MealLog — campos obrigatórios corretos (§3.1)
✅ Test 2: Adhoc MealLog — invariantes mantidos
✅ Test 3: Presentation mappings — PROTOTYPE PRESENTATION

=== SUPPLEMENTLOG PROJECTION TESTS ===
✅ Test 1: SupplementLog — campos obrigatórios corretos (§3.1)
✅ Test 2: SupplementLog presentation mapping

=== EQUIVALENCE MODEL TESTS ===
✅ Test 1: Entries idênticas → equivalent
✅ Test 2: timeline_type diferente → divergent
✅ Test 3: source_collection diferente → divergent
✅ Test 4: source_id diferente → divergent
✅ Test 5: occurred_at diferente → divergent
✅ Test 6: status diferente → divergent
✅ Test 7: Entry null → divergent (MISSING → repair)
✅ Test 8: title/subtitle diferente → divergent (persisted derived fields)
✅ Test 8b: dog_id diferente → divergent
✅ Test 8c: projected_at diferente → equivalent (volátil, não participa)
✅ Test 8d: recorded_by.uid diferente → divergent
✅ Test 8e: recorded_by.name diferente → divergent
✅ Test 8f: recorded_by.internal_role diferente → divergent

=== PROJECTION OPERATION TESTS ===
✅ Test 1: MISSING → CREATE
✅ Test 2: EQUIVALENT → NO-OP
✅ Test 3: DIVERGENT → REPAIR

=== IDEMPOTENCY TESTS ===
✅ Test 1: Mesma fonte → mesmo timelineId
✅ Test 2: Reprojeção → entries equivalentes

=== RECONCILIATION STATES TESTS ===
✅ CRITICAL TEST: Count equality != Consistency proof
   MISSING: [mo1_countC]
   ORPHANS: [mo1_orphanX]

=== LEGACY CLASSIFICATION TESTS ===
✅ Test 1: feeding_events com vínculo explícito → strong_match
✅ Test 2: MealLog × feeding_events sem vínculo → no_safe_match
✅ Test 3: Coincidência por data/horário → no_safe_match
✅ Test 4: WEAK_MATCH / NO_SAFE_MATCH nunca autoriza auto-dedupe
✅ Test 5: nutrition_supplements ≠ SupplementLog (O3-D8)

TOTAL: 38 tests PASSED, 0 FAILED, 0 SKIPPED
```

### 20.2 E2E Emulator Tests (Executado em 2026-07-22)

```
=== HEALTH TIMELINE E2E EMULATOR TESTS ===

=== TEST 1: IDEMPOTENCY — Single MealLog ===
✅ First projection → created
✅ Second projection → noop
✅ Third projection → noop
✅ Only 1 timeline document exists
📊 sourceReads: 3, timelineReads: 3, timelineCreates: 1, noOps: 2

=== TEST 2: IDEMPOTENCY — Multiple MealLogs ===
✅ All first projections → created
✅ All second projections → noop
✅ Final document count: 3 (matches 3 sources)

=== TEST 3: SUPPLEMENT LOG IDEMPOTENCY ===
✅ First supplement projection → created
✅ Second supplement projection → noop

=== TEST 4: REPAIR — DIVERGENT ENTRY ===
✅ Divergent entry → repaired
✅ occurred_at corrected
📊 timelineRepairs: 1

=== TEST 5: BOUNDED RECONCILIATION — Freshness Pass ===
✅ Watermark updated after processing
✅ FRESHNESS PASS: BOUNDED (processa apenas novos)

=== TEST 6: BOUNDED RECONCILIATION — Historical Sweep ===
✅ Historical sweep cursor advances
✅ Historical sweep remains BOUNDED (page size = 3)
✅ FULL HISTORY IS NOT RESCANNED EVERY RUN

=== TEST 7: ORPHAN DETECTION ===
✅ ORPHAN DETECTED
✅ NO AUTO-DELETE: Orphan entry preserved
📊 orphanChecks: 3

=== TEST 8: FRESHNESS PASS — Specific Behaviors (R4, R5, R6) ===
✅ 8a: Cursor advances after processing new source (recorded_at based)
✅ 8b: Late registration (backdated fact) discovered by recorded_at cursor
✅ 8c: Freshness pass continuation via cursor validated
✅ 8d: Freshness pass idempotent on repeated calls
✅ 8e: Valid source is NOT skipped
✅ 8f: recorded_by full identity preserved (name + internal_role)

=== TEST 9: HISTORICAL SWEEP — End and Wrap (R4) ===
✅ Cursor advances between runs
✅ Sweep eventually completes
✅ Post-completion run is safe

=== TEST 10: EQUAL-COUNTS INCONSISTENCY DETECTION ===
✅ CRITICAL: COUNT EQUALITY ≠ CONSISTENCY
✅ Reconciliation correctly detects both MISSING and ORPHAN

=== TEST 12: MEALLOG acceptance=unknown (R5) ===
✅ acceptance=unknown projects successfully
📊 acceptance=unknown literal behavior:
   acceptance="unknown" → acceptanceLabel="unknown" (passthrough literal)
   kind="planned" → subtitle="Planejada · unknown"
   food_name="Refeição Desconhecida" → title="Refeição Desconhecida"

=== TEST 13: FRESHNESS CURSOR tie-break (R5) ===
✅ Tie-break doc1 discovered
✅ Tie-break doc2 discovered
✅ Both documents discovered (no document skipped)

=== TEST 14: CRITICAL — Freshness Pass BOUNDED with page_size=1 (R6) ===
🧹 Cleared state for deterministic pagination proof
📝 Created EXACTLY 2 documents with same recorded_at
📝 Page 1: processed=1, hasMore=true
📝 Page 2: processed=1, hasMore=true
📝 Page 3: processed=0, hasMore=false
✅ BOUNDED: page_size=1 → each page processed exactly 1 doc (never the full backlog)
✅ PAGINATION: 2 documents processed across 2 pages via startAfter cursor
✅ NO REPROCESSING: page 3 fetched 0 (cursor advanced past backlog)
✅ TIE-BREAK: both same-recorded_at docs discovered across pages

=== TEST 15: OVERLAP REPLAY PASS — bounded/idempotent/cursor-safe (R6) ===
📝 Forward cursor advanced to: <recorded_at>
📝 15a: Out-of-order write behind forward cursor
   Forward pass processed=0, behind doc projected=false
✅ 15a: Forward pass correctly skips out-of-order write (demonstrates the gap)
📝 15b: Overlap replay — window=[windowStart, windowEnd]
   processed=2, created=1
✅ 15b: Overlap replay catches the out-of-order document
✅ 15c: Replay window is BOUNDED
📝 15d: Second replay — created=0, noop=2
✅ 15d: Overlap replay is idempotent (no duplicates)
✅ 15e: Forward cursor unchanged — never rewound/blocked

🎯 O3 BEHAVIOR VALIDATION: EMULATOR TESTS PASSED (15/15)

✅ All emulator tests completed
```

**Execução real:** Emulator Firestore em `127.0.0.1:8080`, `EXIT CODE: 0`,
comando `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=canil-gcm npx tsx src/health_timeline_emulator_test.ts`.

### 20.3 Test Matrix — CLEARLY SEPARATED

**Comandos:**
- Unit tests: `npx tsx src/health_timeline_projection_test.ts`
- E2E tests: `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=canil-gcm npx tsx src/health_timeline_emulator_test.ts`
- Build: `npm run build`

| Suite | Passed | Skipped | Failed | Execução |
|-------|--------|---------|--------|----------|
| **Prototype unit tests** (`health_timeline_projection_test.ts`) | **38** | 0 | 0 | ✅ EXECUTADO (node/tsx) |
| **Prototype Emulator E2E** (`health_timeline_emulator_test.ts`) | **15** | 0 | 0 | ✅ EXECUTADO (Emulator real, EXIT 0) |
| **TypeScript build** (`npm run build`) | ✅ PASSED | — | — | ✅ EXECUTADO |

**Total validado nesta sessão:** 38 unit + 15 E2E (Emulator real) + build verde

### 20.4 Build Status

```
npm run build
✅ tsc: SUCCESS
```

---

## 21. PRODUCTION ISOLATION VERIFICATION

### 21.1 Git Diff — Production Files

```
$ git diff -- functions/src/index.ts firestore.rules firestore.indexes.json
(No output — zero changes)
```

**✅ NENHUMA ALTERAÇÃO EM ARQUIVOS PRODUTIVOS**

### 21.2 Git Status — Untracked (New) Files Only

```
?? docs/health/HEALTH_V1_PHASE_5D_GATE5C5B2_O3_BEHAVIOR_PROTOTYPE_REPORT.md
?? functions/audit_prod.mjs
?? functions/src/health_timeline_emulator_test.ts
?? functions/src/health_timeline_projection.ts
?? functions/src/health_timeline_projection_test.ts
```

**Production isolation: COMPROVADA**

### 21.3 Triggers

| Tipo | Status |
|------|--------|
| onDocumentCreated | ❌ NÃO CRIADO |
| onSchedule | ❌ NÃO CRIADO |
| Callable | ❌ NÃO CRIADO |
| Deploy | ❌ NÃO EXECUTADO |

### 21.4 Rules/Indexes

| Arquivo | Alterado |
|---------|----------|
| firestore.rules | ❌ NÃO |
| firestore.indexes.json | ❌ NÃO |
| functions/src/index.ts | ❌ NÃO |

---

## 22. FINDINGS

### 22.1 Classification

| Finding | Classificação | Detalhes |
|---------|-------------|----------|
| Test configuration values | OBSERVATION | Valores de page_size/overlap são TEST ONLY, não produção |
| Presentation mappings | OBSERVATION | title/subtitle são PROTOTYPE, não contrato arquitetural |
| Emulator timing | OBSERVATION | Não comparável com SLA produtivo |
| No new exports | CONFIRMED | index.ts não modificado |
| No legacy writes | CONFIRMED | Código puro, writes apenas em harness |

### 22.2 BLOCKER / MAJOR

```
BLOCKER: 0
MAJOR: 0
MINOR: 0
```

### 22.3 R5 Resolutions

| Finding | Resolution |
|---------|------------|
| projected_at semantics on REPAIR | ✅ VALIDATED: CREATE=now, REPAIR=now, NO-OP=preserved |
| Freshness cursor based on recorded_at | ✅ VALIDATED: Late registration discovered |
| recorded_by full comparison | ✅ FIXED: compareProjection validates uid+name+role |
| acceptance=unknown | ✅ VALIDATED: TEST 12 |
| Freshness cursor tie-break | ✅ VALIDATED: TEST 13 |

## 23. O3 CLOSURE ASSESSMENT

### 23.1 Decisões O3

| Decisão | Status |
|----------|--------|
| O3-D1: Granularidade | ✅ FROZEN |
| O3-D2: Retenção | ✅ FROZEN |
| O3-D3: Reconciliação | ✅ FROZEN |
| O3-D4: SLA e sync_pending | ✅ FROZEN |
| O3-D5: source_collection | ✅ FROZEN |
| O3-D6: Deterministic ID | ✅ FROZEN |
| O3-D7: Canonical × Legacy Dedupe | ✅ FROZEN |
| O3-D8: nutrition_supplements | ✅ FROZEN |

### 23.2 Validações O3

| Validação | Status |
|-----------|--------|
| O3 ARCHITECTURAL DECISIONS | ✅ FROZEN |
| O3 BEHAVIOR VALIDATION | ✅ VALIDATED |
| O3 projected_at CONTRACT | ✅ VALIDATED (R3) |
| **O3 Freshness Pass BOUNDED with pagination** | ✅ **VALIDATED (R6)** ← CRITICAL |
| O3 architecture/behavior closure | ✅ **HUMAN APPROVED** |

### 23.3 Veredicto Técnico

```
GATE 5C.5B.2 — HUMAN AUDIT APPROVED

BLOCKER: 0
MAJOR: 0
MINOR: 0

O3 architectural decisions: FROZEN
O3 behavior validation: VALIDATED
O3 projected_at contract: VALIDATED (R3)
O3 freshness cursor (recorded_at + tie-break): VALIDATED (R4-R5)
O3 recorded_by full comparison (uid+name+role): VALIDATED (R5)
O3 acceptance=unknown: VALIDATED (R5)
O3 Freshness Pass BOUNDED with pagination: VALIDATED (R6) ← CRITICAL
O3 architecture/behavior closure: HUMAN APPROVED
Production SLA evidence: DEFERRED TO CONTROLLED ACTIVATION
Productive projection deployment: NOT AUTHORIZED
```

### 23.4 R5 Resolutions

| Finding | Resolution |
|---------|------------|
| recorded_by.name/internal_role não comparados | ✅ FIXED: compareProjection agora valida todo recorded_by |
| Equivalence model contradiz R3 | ✅ FIXED: title/subtitle INCLUDED |
| acceptance=unknown sem cobertura de teste | ✅ ADDED: TEST 12 valida |
| Freshness cursor tie-break | ✅ ADDED: TEST 13 valida |

### 23.5 Provisões

```
O3 PRODUCTION SLA EVIDENCE: DEFERRED TO CONTROLLED ACTIVATION
PRODUCTIVE PROJECTION DEPLOYMENT: NOT AUTHORIZED
CHECKPOINT: AUTHORIZED
```

---

## 24. RECOMMENDED NEXT GATE

### 24.1 Próximo Gate

**5C.5C — TIMELINE PROJECTION FOUNDATION**

### 24.2 Justificativa

health_timeline ainda **não possui pipeline produtivo**:

| Dependência | Status |
|-------------|--------|
| Projection trigger (onCreate) | ❌ NÃO EXISTE |
| Reconciliation Cloud Function | ❌ NÃO EXISTE |
| Firestore Rules para health_timeline | ❌ NÃO ATIVADO |
| Firestore indexes para health_timeline | ❌ NÃO CONFIGURADO |
| Deployment controlado | ❌ NÃO AUTORIZADO |

**Timeline Query Foundation** fica posterior à materialização foundation.

### 24.3 Escopo 5C.5C

**Triggers:**
- MealLog: `onCreate` (factuais não têm update/delete neste Gate)
- SupplementLog: `onCreate` (factuais não têm update/delete neste Gate)

**Reconciliation:**
- Cadência: **DAILY** (O3-D3 FROZEN)
- Bounded + Incremental (validated)
- Sem update/delete trigger até existir contrato explícito de amendment/cancellation

**Integração:**
- Integration do ProjectionEngine
- Rules para health_timeline collection
- Firestore indexes para health_timeline (inclui índice composto recorded_at + __name__ para Freshness/Overlap)
- Emulator tests para trigger
- Ativação controlada (deploy manual pelo usuário, conforme CLAUDE.md)

### 24.4 Fora do Escopo 5C.5C

- Timeline Query Foundation (reader)
- Backfill de dados existentes
- Update/Delete triggers (sem contrato de amendment)
- Production deployment

---

## 25. GIT CHECKPOINT BASELINE

```
HEAD:        2093e7a58311c0f3c44befef58a07020c4f3f06a
Subject:     docs(health): freeze O3 projection decisions
Branch:      feature/health-v1-foundation
Divergência: 0/0 contra origin/feature/health-v1-foundation
```

**Arquivos do Gate 5C.5B.2 (untracked, novos):**
```
functions/src/health_timeline_projection.ts
functions/src/health_timeline_projection_test.ts
functions/src/health_timeline_emulator_test.ts
docs/health/HEALTH_V1_PHASE_5D_GATE5C5B2_O3_BEHAVIOR_PROTOTYPE_REPORT.md
```

**Fora do escopo (não incluir no commit):**
```
functions/audit_prod.mjs (acknowledged, não relacionado)
```

**Não alterados:**
```
functions/src/index.ts (sem novos exports)
firestore.rules (sem alteração)
firestore.indexes.json (sem alteração)
```

---

## 26. VERDICT

### 26.1 Gate 5C.5B.2 Status

```
GATE 5C.5B.2 — HUMAN AUDIT APPROVED
```

### 26.2 Critérios de Aprovação

| Critério | Status | Evidência |
|----------|--------|-----------|
| Deterministic ID validado | ✅ | Unit tests (38) + golden vector |
| Idempotência comprovada | ✅ | TEST 1-3 (Emulator real) |
| MISSING → CREATE aprovado | ✅ | TEST 1 (created→noop→noop) |
| EQUIVALENT → NO-OP aprovado | ✅ | TEST 1-2 |
| DIVERGENT → REPAIR aprovado | ✅ | TEST 4 |
| ORPHAN → ALERT/NO-DELETE aprovado | ✅ | TEST 7 (detected, not deleted) |
| Equal-counts inconsistency detectada | ✅ | TEST 10 |
| Bounded cursors comprovados | ✅ | TEST 6, 9 |
| **Freshness Pass BOUNDED + paginado** | ✅ | **TEST 14 (page_size=1, EXIT 0)** |
| **Overlap Replay bounded/idempotent/cursor-safe** | ✅ | **TEST 15 (forward cursor unchanged)** |
| projected_at contract | ✅ | TEST 11 |
| recorded_by full comparison | ✅ | TEST 8f + unit 8d/8e/8f |
| acceptance=unknown | ✅ | TEST 12 |
| Zero legacy writes | ✅ | Código puro; harness escreve só health_timeline* |
| Testes com 0 failed | ✅ | 38 unit + 15 E2E, EXIT CODE 0 |
| Nenhum export/trigger produtivo | ✅ | index.ts sem novos exports |
| Nenhum deploy realizado | ✅ | Rules/indexes/deploy intocados |
| BLOCKER = 0 | ✅ | R6 blockers resolvidos |
| MAJOR = 0 | ✅ | Overlap replay reconciliado |

### 26.3 Blockers R6 anteriores — Resolução

| Blocker/Major (auditoria anterior) | Resolução R6 |
|-----------------------------------|--------------|
| TEST 14 não executado no Emulator | ✅ EXECUTADO no Emulator real (127.0.0.1:8080, EXIT 0) |
| HEAD/baseline inconsistente | ✅ RECONCILIADO: baseline `2093e7a`, branch `feature/health-v1-foundation` |
| Safety overlap não reconciliado com forward cursor | ✅ IMPLEMENTADO: `overlapReplayPass` separado, TEST 15 prova bounded+idempotent+cursor-safe |
| Relatório stale | ✅ LIMPO: contagens, baseline, seção R2 e onWrite→onCreate |

### 26.4 Bug de isolamento encontrado e corrigido (evidência de execução real)

A execução real no Emulator expôs um bug que a análise estática não pegaria:
`clearTestData` não limpava `health_timeline_metadata`, deixando cursores stale
(pageCount acumulado 45+) vazarem entre execuções e quebrarem TEST 9/14. Corrigido
adicionando limpeza de metadata ao teardown. Esta é exatamente a razão pela qual a
execução real era obrigatória.

### 26.5 Ação Requerida

```
✅ CHECKPOINT AUTORIZADO
✅ NÃO PUSH
✅ NÃO DEPLOY

Commit autorizado: feat(health): validate timeline projection behavior
```

---

## 28. GOLDEN VECTOR — LITERAL

### 28.1 Input

```typescript
{
  sourceCollection: "dogs/test/meal_logs",
  sourceId: "mo1_golden"
}
```

### 28.2 Preimage (stableStringify)

```json
["health_timeline_v1","dogs/test/meal_logs","mo1_golden"]
```

### 28.3 SHA-256 Expected

```
0a1ded9f16cef95b1d3a3de6866c821b0be72f11ca111b01acbcf0cc63252246
```

### 28.4 TimelineId Expected (LITERAL — hardcoded in tests)

```
tl1_0a1ded9f16cef95b1d3a3de6866c821b0be72f11ca111b01acbcf0cc63252246
```

### 28.5 Validação

```
source_collection: dogs/test/meal_logs  → HARDCODED
source_id: mo1_golden                   → HARDCODED
preimage: ["health_timeline_v1","dogs/test/meal_logs","mo1_golden"] → HARDCODED
timelineId: tl1_0a1ded9f...            → HARDCODED (not calculated)
```

**O expected timelineId é hardcoded nos testes, não calculado pela função sob teste.**
---

## APÊNDICE B: TEST COMMANDS

```bash
cd functions

# Build
npm run build

# Unit tests
npx tsx src/health_timeline_projection_test.ts

# Emulator tests (requer Firestore Emulator rodando)
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=canil-gcm npx tsx src/health_timeline_emulator_test.ts
```

---

**Documento gerado em:** 2026-07-22
**Gate:** 5C.5B.2
**Responsável:** Claude Code (Anthropic)
