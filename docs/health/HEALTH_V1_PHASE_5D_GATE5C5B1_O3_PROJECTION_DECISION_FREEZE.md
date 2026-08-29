# FASE 5D — GATE 5C.5B.1
## O3 PROJECTION VALIDATION — ARCHITECTURAL DECISION FREEZE

**Data:** 2026-07-22
**Branch:** `feature/health-v1-foundation`
**HEAD:** `a435aa639248ed15d08710aa9ac727207c5560b0`
**Status:** READY FOR HUMAN AUDIT

---

## 1. EXECUTIVE SUMMARY

Este subgate congela formalmente as decisões operacionais necessárias para retirar O3 do estado OPEN antes da criação da foundation de projeções.

| Decisão | Status |
|---------|--------|
| O3-D1: Granularidade | ✅ FROZEN |
| O3-D2: Retenção | ✅ FROZEN |
| O3-D3: Reconciliação | ✅ FROZEN (deterministic, not count-based) |
| O3-D4: SLA e sync_pending | ✅ FROZEN |
| O3-D5: source_collection | ✅ FROZEN |
| O3-D6: Deterministic ID | ✅ FROZEN |
| O3-D7: Canonical × Legacy Dedupe | ✅ FROZEN (NO SAFE STRONG MATCH by default) |
| O3-D8: nutrition_supplements | ✅ FROZEN FOR MIGRATION |
| occurred_at mapping | ✅ FROZEN |
| Cost Model | ✅ PARAMETERS DEFINED (incremental, free-tier analysis) |
| Prototype Plan | ✅ SCOPE DEFINED |

**Próximo passo:** 5C.5B.2 — O3 Behavior Validation (Emulator)

---

## 2. GIT PREFLIGHT

```
HEAD:       a435aa639248ed15d08710aa9ac727207c5560b0
Branch:     feature/health-v1-foundation
Status:     ?? functions/audit_prod.mjs (out of scope)
Divergence: 0/0 ✅ (sincronizado)
Diff:       zero whitespace errors
```

✅ Conforme esperado.

---

## 3. O3-D1 — GRANULARITY

**Status: FROZEN**

### 3.1 Decisão

```
ONE FACT = ONE PROJECTED TIMELINE ENTRY
```

### 3.2 Justificativa (ADR-004)

> "Granularidade da timeline: cada dose individual aparece ou apenas o protocolo? Proposta: doses aparecem individualmente (sao eventos relevantes operacionalmente)."

Doses/eventos são projetados individualmente. Sem agrupamento na projeção persistida.

### 3.3 Mapeamentos Aprovados

| Fonte | Projeção |
|-------|----------|
| 1 MealLog (planned ou ad hoc) | 1 TimelineEntry |
| 1 SupplementLog | 1 TimelineEntry |
| 1 WeightRecord | 1 TimelineEntry |
| 1 ClinicalEvent | 1 TimelineEntry |
| 1 VaccineRecord | 1 TimelineEntry |

### 3.4 Agrupamento Visual

Agrupamento por dia/período pertence **exclusivamente à apresentação/UI**.

A projeção persiste entries individuais; a UI pode agrupar visualmente sem persistir agregados.

### 3.5 Contrário ao Agrupamento Persistido

**PROIBIDO:** Persistir entries agregadas por dia na `health_timeline`.

---

## 4. O3-D2 — RETENTION

**Status: FROZEN**

### 4.1 Decisão

```
KEEP ALL PROJECTED HISTORY
```

### 4.2 Justificativa (ADR-004)

> "Limite de itens na projecao: limitar a N mais recentes ou manter tudo? Proposta: manter tudo; paginacao e por cursor, nao por tamanho da colecao."

### 4.3 Implicações

| Aspecto | Decisão |
|---------|---------|
| TTL/Expiração | NÃO IMPLEMENTAR |
| Window-based cleanup | NÃO IMPLEMENTAR |
| Escalabilidade de leitura | Cursor pagination + indexes |
| Rastreabilidade operacional | Mantida indefinidamente |

### 4.4 Observação

Para o porte atual do K9 Ops, retenção completa é viável. Revisar se o porte escalar invalidar esta decisão.

---

## 5. O3-D3 — RECONCILIATION

**Status: FROZEN**

### 5.1 Decisão

```
Scheduled reconciliation: DAILY
Manual reconciliation: AVAILABLE TO AUTHORIZED ADMINISTRATIVE FLOW
```

### 5.2 Semântica da Reconciliação

| Aspecto | Definição |
|---------|-----------|
| **O que compara** | Fontes canônicas vs. projeções |
| **O que repara** | Projeções derivadas (cria entries faltantes) |
| **O que NÃO faz** | Nunca altera fonte canônica |
| **Idempotência** | Obrigatória |
| **Auditabilidade** | Resultado deve ser observável/auditável |

### 5.3 Reconciliação Automática (Daily) — BOUNDED + INCREMENTAL

**Princípio:** A reconciliação NÃO escaneia histórico completo diariamente.
O volume de leitura grows unboundedly com o tempo, tornando-se
inviável em produção.

**Modelo: Bounded + Incremental**

```
┌─────────────────────────────────────────────────────────┐
│  DAILY RECONCILIATION CYCLE                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  A. FRESHNESS PASS (always runs)                       │
│     ├── Para cada dogId ativo                           │
│     │     ├── Determinar watermark: max(occurred_at)   │
│     │     │     do último reconciliation run           │
│     │     ├── Para cada fonte canônica                 │
│     │     │     ├── Query: occurred_at > watermark      │
│     │     │     ├── Para cada doc fonte                │
│     │     │     │     ├── derive source_collection    │
│     │     │     │     ├── derive source_id             │
│     │     │     │     ├── expectedTimelineId           │
│     │     │     │     └── read health_timeline/{id}   │
│     │     │     │                                     │
│     │     │     ├── Se entry AUSENTE                  │
│     │     │     │     └── CREATE                      │
│     │     │     └── Se entry PRESENTE                 │
│     │     │           └── Compare conteúdo:            │
│     │     │               CORRECT → NO-OP              │
│     │     │               DIVERGENT → REPAIR          │
│     │     └── Update watermark para este dog           │
│     └── Log: sources checked, created, repaired         │
│                                                         │
│  B. HISTORICAL INTEGRITY SWEEP (periodic, bounded)      │
│     ├── BOUNDED + CURSOR-PAGINATED                   │
│     ├── page size = TO BE CALIBRATED IN 5C.5B.2       │
│     ├── Para cada dogId ativo                          │
│     │     ├── Para cada fonte canônica                 │
│     │     │     └── Source-by-source comparison        │
│     │     │         (same algorithm as freshness pass) │
│     │     └── Log sweep results                        │
│     └── Frequência: weekly (não daily)                 │
│                                                         │
│  C. ORPHAN INTEGRITY SWEEP (periodic, bounded)         │
│     ├── BOUNDED + CURSOR-PAGINATED                   │
│     ├── page size = TO BE CALIBRATED IN 5C.5B.2       │
│     ├── Para cada dogId ativo                          │
│     │     ├── Query health_timeline (cursor-paginated)│
│     │     ├── Para cada entry                          │
│     │     │     ├── Verify source exists              │
│     │     │     │     ├── EXISTS + EQUIVALENT → OK    │
│     │     │     │     ├── EXISTS + DIVERGENT → REPAIR │
│     │     │     │     └── NOT FOUND → ORPHAN         │
│     │     │     └── Update last_orphan_check          │
│     │     └── Log orphan count                        │
│     └── Frequência: daily (lightweight, bounded)      │
│                                                         │
│  D. KNOWN DISCREPANCIES                               │
│     ├── Armazenar em Firestore ou metadata             │
│     │     key = dogId + reconciliation_run_id          │
│     │     value = { missing[], divergent[], orphans[] }│
│     └── Preservar para auditoria                       │
│                                                         │
│  E. MANUAL RECONCILIATION (fluxo administrativo)      │
│     ├── Disponível para administradores               │
│     ├── Trigger explícito por dogId                  │
│     └── Full reconciliation (sem bounded)             │
└─────────────────────────────────────────────────────────┘
```

**Parâmetros Configuráveis:**

| Parâmetro | Descrição | Calibração |
|-----------|-----------|------------|
| `freshness.window` | Janela de overlap para watermark | TO BE CALIBRATED IN 5C.5B.2 |
| `historical.window` | Janela do historical sweep | TO BE CALIBRATED IN 5C.5B.2 |
| `orphan.page_size` | Máximo entries por orphan sweep | TO BE CALIBRATED IN 5C.5B.2 |
| `historical.frequency` | Frequência do sweep histórico | weekly |
| `orphan.frequency` | Frequência do sweep de órfãos | daily |

**Nota:** Os valores numéricos de janela e page size serão calibrados
em 5C.5B.2 via prototype, pois dependem de medição real do volume
de dados e comportamento do Emulator.

**Por que Bounded + Incremental:**

```
Crescimento histórico:

Day 1:    10 meals  → full scan = 10 reads
Day 30:   300 meals → full scan = 300 reads
Day 365:  3,650 meals → full scan = 3,650 reads

Com Bounded + Incremental (freshness + periodic sweep):
Day 365:  freshness = O reads (apenas novos, calibrado)
         historical = H reads (bounded window, calibrado)
         orphan = T reads (bounded page size, calibrado)

Conclusão: O(n) para freshness, O(calibrated_window) para sweep,
evitando full-history scan unbounded.
```

**Garantias:**

| Garantia | Como é Mantida |
|----------|-----------------|
| Missing não fica para sempre | Freshness pass cobre todos os novos |
| Divergente é corrigido | Freshness + periodic sweep |
| Órfão é detectado | Orphan sweep peródico |
| Custo previsível | Bounded reads por ciclo |

**Estados de Comparação (para cada fonte):**

| Estado | Significado | Ação |
|--------|-------------|------|
| `MISSING` | Fonte existe, entry não existe | CREATE |
| `CORRECT` | Fonte + entry existem, conteúdo equivalente | NO-OP |
| `DIVERGENT` | Fonte + entry existem, conteúdo diferente | REPAIR |
| `ORPHAN` | Entry existe, fonte não encontrada | ALERT (no auto-delete) |

### 5.4 Reconciliação Manual

Disponível para fluxo administrativo autorizado em implementação futura.

Detalhes de autorização ficam para o Gate de implementação.

### 5.5 Capacidade de Reparo

A reconciliação pode reparar projeções derivadas ausentes ou divergentes, mas **nunca altera a fonte canônica**.

```
A timeline é derivada — uma projeção divergente pode ser recalculada
a partir da fonte canônica sem alterar a fonte.
```

Correção de dados errôneos na fonte canônica requer fluxo separado.

---

## 6. O3-D4 — SLA AND SYNC_PENDING

**Status: FROZEN**

### 6.1 Decisão

```
UX sync_pending threshold: 30 seconds

Production operational target:
projection normally visible within 10 seconds
```

### 6.2 Fundamentação (ADR-004 + Foundation Review)

> "SLA de 10s em condicoes normais; insercao otimista local cobre o gap; apos 30s sem confirmacao, indicador sync_pending."

> "insercao otimista local com timeout 30s; indicador sync_pending"

### 6.3 Separação de Conceitos

| Conceito | Definição | Validação |
|---------|-----------|-----------|
| **UX threshold** | Após 30s sem confirmação, UI exibe `sync_pending` | Validação de UX |
| **Operational target** | Projeção normalmente visível em ~10s | Validação de produção |

### 6.4 Emulator vs. Produção

**EMULATOR:**
- ✅ Valida comportamento funcional
- ✅ Valida propagação idempotente
- ✅ Valida retry behavior
- ✅ Valida reconciliation algorithm
- ✅ Proporciona baseline local
- ❌ NÃO prova SLA de produção

**PRODUÇÃO:**
- ❌ Requer smoke test controlado
- ❌ SLA real medido em produção

### 6.5 Aprovação Diferida

O SLA operacional de produção será validado posteriormente em ativação produtiva controlada, não neste Gate.

---

## 7. O3-D5 — SOURCE_COLLECTION

**Status: FROZEN**

### 7.1 Decisão

```
Para fontes dog-scoped canônicas:

MealLog:
  source_collection = "dogs/{dogId}/meal_logs"

SupplementLog:
  source_collection = "dogs/{dogId}/supplement_logs"

O valor persistido contém o dogId real do cão.
```

### 7.2 Justificativa

O Schema ADR-004 define `source_collection` como "caminho da fonte canônica" com exemplos:

```json
"source_collection": "dogs/dog_001/clinical_cases/case_abc123/events"
"source_collection": "dogs/{dogId}/weight_records/{id}"
"source_collection": "dogs/{dogId}/meal_logs/{id}"
```

Incluir o dogId no `source_collection` (em vez de usar apenas `meal_logs`) proporciona:

1. **Identidade de origem inequívoca** — sabe-se de qual cão vem o registro
2. **Alinhamento com deterministic ID** — `source_collection` participates do hash
3. **Rastreabilidade** — path completo preserva contexto

### 7.3 Exemplo Persistido

```json
{
  "source_collection": "dogs/4DDeRe7CCjTte6nbUbrC/supplement_logs",
  "source_id": "sl1_dbfca803cfece798974cc0ad01ca2858ee0c1fc35a8a0db68a0b8d5b85dc8638",
  "timelineId": "tl1_..."
}
```

### 7.4 NÃO incluir source_id em source_collection

```
source_collection = "dogs/{dogId}/meal_logs"   ✅ CORRETO
source_id         = "ml1_abc123..."           ✅ CORRETO

source_collection = "dogs/{dogId}/meal_logs/ml1_abc123"  ❌ INCORRETO
```

### 7.5 Impacto no Deterministic ID

Esta serialização participa do `hash(source_collection + source_id)` e, portanto, torna-se **contrato versionado**.

Qualquer alteração no formato de serialização requer version bump.

### 7.6 Resolução de Ambigüidade Histórica

O ADR-004 contém exemplos históricos onde `source_collection` parecia incluir `{id}`:
```json
"source_collection": "dogs/{dogId}/meal_logs/{id}"
```

**O3-D5 resolve esta ambiguidade:**

```
Para Timeline v1:

source_collection = collection path WITHOUT document ID
source_id         = document ID only
```

**Exemplo:**

```
✅ CORRETO:
  source_collection = "dogs/{dogId}/meal_logs"
  source_id         = "ml1_abc123..."

❌ INCORRETO:
  source_collection = "dogs/{dogId}/meal_logs/ml1_abc123..."
  source_id         = (redundante)
```

Esta separação é contrato versionado para o deterministic ID.

---

## 8. O3-D6 — DETERMINISTIC ID

**Status: FORMULA DEFINED, SERIALIZATION FROZEN**

### 8.1 Fórmula Arquitetural

```
timelineId = hash(source_collection + source_id)
```

**Origem:** ADR-004

> "ID deterministico: o `timelineId` e um hash de `source_collection + source_id`, garantindo idempotencia e reconstrucao sem duplicatas."

### 8.2 Algoritmo de Hash

**PADRÃO DO PROJETO:** SHA-256 hex string

```typescript
// health_nutrition_logic.ts:456-458
export function sha256Hex(material: string): string {
  return crypto.createHash("sha256").update(material, "utf8").digest("hex");
}
```

### 8.3 Padrão de Preimage (Stable Stringify)

**PADRÃO DO PROJETO:** `stableStringify()` em array

```typescript
// health_nutrition_logic.ts
export function mealOccurrencePreimage(params: {...}): string {
  return stableStringify([
    "meal_occurrence_v1",
    params.dogId,
    params.planId,
    params.plannedMealId,
    params.localServiceDate,
  ]);
}
```

### 8.4 Serialização Aprovada para Timeline ID

```
timelineId = "tl1_" + sha256Hex(stableStringify([
  "health_timeline_v1",
  source_collection,  // "dogs/{dogId}/meal_logs"
  source_id          // "mo1_abc..." ou "ml1_xyz..."
]))
```

### 8.5 Prefixo Aprovado

```
tl1_  = health_timeline projection entry
```

**Justificativa:**
- Segue padrão existente (`mo1_`, `ml1_`, `sl1_`, `nr1_`)
- `tl1_` indica health timeline projection
- Diferencia de IDs de outros domínios

### 8.6 Exemplo Completo

```typescript
// MealLog → Timeline
const source_collection = "dogs/4DDeRe7CCjTte6nbUbrC/meal_logs";
const source_id = "mo1_abc123def456...";

const preimage = stableStringify([
  "health_timeline_v1",
  source_collection,
  source_id
]);

const timelineId = "tl1_" + sha256Hex(preimage);
// Resultado: "tl1_a1b2c3d4e5f6..."

// SupplementLog → Timeline
const source_collection = "dogs/4DDeRe7CCjTte6nbUbrC/supplement_logs";
const source_id = "sl1_dbfca803cfece798974cc0ad01ca2858...";

const preimage = stableStringify([
  "health_timeline_v1",
  source_collection,
  source_id
]);

const timelineId = "tl1_" + sha256Hex(preimage);
```

### 8.7 Propriedades Garantidas

| Propriedade | Status | Comprovação |
|-------------|--------|-------------|
| Determinismo | ✅ GARANTIDO | Mesmos inputs → mesmo ID (função pura) |
| Idempotência | ⏳ PENDING 5C.5B.2 | Requer validação via Emulator tests |
| Colisão evitada | ✅ CRYPTOGRAPHICALLY NEGLIGIBLE | SHA-256 256-bit output space |
| Sem timestamp | ✅ GARANTIDO | Inputs são strings determinísticas |
| Reconstrução | ✅ GARANTIDO | Possível a partir de fontes |

**Nota sobre Idempotência:**

```
Idempotência requer validação prática em 5C.5B.2:
- Re-projeção de fonte idêntica produz mesmo ID
- Conteúdo da entry é estável em retries
- Edge cases (campos opcionais, nulls) são determinísticos
```

### 8.8 NÃO Incluir

| Campo | Razão |
|-------|-------|
| `occurred_at` | Timestamp — mudaria o ID em reprojeções |
| `recorded_at` | Server time — não determinístico |
| `title` | Apresentação — pode mudar |
| `subtitle` | Apresentação — pode mudar |

---

## 9. O3-D7 — CANONICAL × LEGACY DEDUPE

**Status: FROZEN**

### 9.1 Decisão

```
CANONICAL WINS ONLY WHEN FACTUAL EQUIVALENCE IS PROVABLE

Se equivalência factual for comprovável:
  CANONICAL WINS

Se equivalência NÃO puder ser comprovada com segurança:
  DO NOT AUTO-DEDUPLICATE
```

### 9.2 NÃO Deduplicar Automaticamente Por

| Critério | Por quê |
|----------|---------|
| Mesmo dia | Múltiplos eventos no mesmo dia são comuns |
| Horário aproximado | Diferentes momentos de execução |
| Mesma quantidade | Coincidência possível |
| Mesmo nome | Nomes comuns em alimentos/suplementos |

### 9.3 Equivalência Comprovável — Classificação

**feeding_events × feedings com mesmo legacy ID:**

| Classificação | Razão |
|--------------|-------|
| **STRONG MATCH** | Dual-write historicamente conhecido entre estas coleções |

**meal_logs × feeding_events/feedings:**

| Classificação | Razão |
|--------------|-------|
| **NO SAFE STRONG MATCH BY DEFAULT** | feeding_events/feedings não demonstram compartilhar `nutrition_plan_id` e `planned_meal_id` com MealLog |

**Requisito para STRONG MATCH entre MealLog e legacy:**

Existência comprovável de vínculo explícito, como:

- `legacy_source` + `legacy_id` compartilhados
- Migration mapping persistido
- Identificador imutável realmente compartilhado entre as fontes

**Importante:** `nutrition_plan_id` e `planned_meal_id` existem no MealLog canônico, mas **não foram demonstrados** como campos compartilhados com `feeding_events`.

**Sem vínculo explícito comprovável:** NÃO deduplicar automaticamente.

### 9.4 WEAK MATCH — Nunca Usar para Auto-Dedupe

| Critério | Classificação | Uso para Auto-Dedupe |
|----------|--------------|---------------------|
| Mesmo dia | WEAK MATCH | ❌ PROIBIDO |
| Horário aproximado | WEAK MATCH | ❌ PROIBIDO |
| Mesma quantidade | WEAK MATCH | ❌ PROIBIDO |
| Mesmo nome/tipo | WEAK MATCH | ❌ PROIBIDO |
| Tolerância temporal | WEAK MATCH | ❌ PROIBIDO |

**WEAK MATCH apenas sugere possibilidade de equivalência. Não constitui prova.**

### 9.5 Estratégia de Migração

1. **Fase 1:** Projetar apenas fontes canônicas
2. **Fase 2:** Para backfill de legados, avaliar equivalência por identidade explícita
3. **Fase 3:** Legados sem equivalência comprovável são preservados durante coexistência

### 9.6 NÃO Apagar Silenciosamente

> "Nos casos ambíguos, preservar ambos durante migração é preferível a apagar silenciosamente um evento real."

---

## 10. O3-D8 — NUTRITION_SUPPLEMENTS LEGACY

**Status: FROZEN FOR MIGRATION**

### 10.1 Decisão

```
nutrition_supplements legacy
  = regimen/prescription/configuration

SupplementLog
  = factual administration

NÃO converter nutrition_supplements automaticamente em
timeline_type = supplement
```

### 10.2 Fundamentação

| Fonte | Semântica |
|-------|-----------|
| `nutrition_supplements` | Regime/prescrição/configuração (o que deveria ser administrado) |
| `SupplementLog` | Administração factual (o que foi realmente administrado) |

**D16:** `nutrition_supplements` NUNCA vaza para `SupplementLog`.

### 10.3 ADR-004 Histórico

> O ADR-004 contém linguagem histórica mencionando projetar `nutrition_supplements` como "administrações".

Esta linguagem está **desatualizada** semanticamente após as decisões D1–D42 de Nutrição.

### 10.4 Reconciliação Documental

**Requer:** Atualização futura do ADR-004 para refletir a semântica correta.

**Não fazer neste Gate** — depende de autorização posterior.

### 10.5 Quando nutrition_supplements Poderia Entrar na Timeline

**Apenas se existir evidência factual independente** de que uma dose foi realmente administrada.

Exemplo (futuro Gate de implementação):
- Handler scaneou código de administração
- Registro em sistema veterinário
- Outra fonte factual confirmando administração

**Sem evidência:** `nutrition_supplements` permanece como `LegacySupplementRegimenView`, não entra na timeline.

---

## 11. OCCURRED_AT MAPPING

**Status: FROZEN**

### 11.1 Mapeamentos Aprovados

| Fonte | Campo | Timeline occurred_at |
|-------|-------|---------------------|
| MealLog | `fed_at` | `occurred_at` |
| SupplementLog | `administered_at` | `occurred_at` |
| WeightRecord | `measured_at` | `occurred_at` |
| ClinicalEvent | `occurred_at` | `occurred_at` |

### 11.2 Semântica dos Campos

| Campo | Semântica | Authority |
|-------|-----------|-----------|
| `fed_at` | Momento factual da alimentação | Client (validado pelo server) |
| `administered_at` | Momento factual da administração | Client (validado pelo server) |
| `recorded_at` | Timestamp de registro no servidor | Server (imutável) |

### 11.3 Validação (Domain Model)

```dart
// fed_at não pode ser futuro
void validateFedAt({required DateTime referenceTime}) {
  if (fedAt.isAfter(referenceTime)) {
    throw const HealthDomainException('future_fed_at');
  }
}

// administered_at não pode ser futuro
void validateAdministeredAt({required DateTime referenceTime}) {
  if (administeredAt.isAfter(referenceTime)) {
    throw const HealthDomainException('future_administered_at');
  }
}
```

### 11.4 occurred_at NÃO é recorded_at

```
occurred_at = fed_at / administered_at / measured_at / occurred_at  ✅
occurred_at = recorded_at                                             ❌
```

`occurred_at` representa **quando o evento aconteceu**; `recorded_at` representa **quando o registro foi criado no sistema**.

---

## 12. TITLE / SUBTITLE REQUIREMENTS

**Status: REQUIREMENTS DEFINED**

### 12.1 Requisitos Não Funcionais

| Requisito | Descrição |
|-----------|-----------|
| title | Curto, identificável, não ambíguo |
| subtitle | Secundário, informação adicional |
| planned/ad hoc | Preservar distinção entre refeição planejada e ad hoc |
| quantidade | Não inventar quando desconhecida |
| supplement info | Preservar nome, dose, unidade sem inventar semântica |

### 12.2 Mapeamentos Propostos (Para 5C.5B.2)

| Fonte | title | subtitle |
|-------|-------|----------|
| MealLog (planned) | "Refeição" + food_name | "Planned" + acceptance |
| MealLog (ad hoc) | "Refeição" + food_name | "Ad hoc" |
| SupplementLog | supplement_name | dosage + unit |
| WeightRecord | "Peso" | weight + unit |
| ClinicalEvent | event_type label | clinician/summary |

### 12.3 NÃO São Identidade

`title` e `subtitle` são **apresentação**, não participam do deterministic ID.

**MUDANÇA APÓS MATERIALIZAÇÃO REQUER REPAIR:**

```
┌─────────────────────────────────────────────────────┐
│  Sem entry materializada:                          │
│    Nova projeção usa novo title/subtitle           │
│    ✅ Sem necessidade de repair                    │
│                                                     │
│  COM entry materializada (existente):             │
│    Nova projeção usa novo title/subtitle           │
│    ⚠️ Entry existente mantém title/subtitle antigo │
│    ⚠️ REQUER REPAIR via reconciliation           │
└─────────────────────────────────────────────────────┘
```

**Estratégia de transição para novos title/subtitle:**

1. Decidir novo mapeamento (neste Gate ou futuro)
2. Na primeira reconciliação após mudança:
   - Entries materializadas recebem REPAIR
   - Novo title/subtitle é aplicado
3. Entries novas usam mapeamento correto automaticamente

**Recomendação:** Alterar title/subtitle mapping quando não houver
entries materializadas, ou planejar reconciliation run de repair
imediatamente após mudança.

---

## 13. COST MODEL

**Status: PARAMETERS DEFINED**

### 13.1 Fonte de Preços

```
Firebase Cloud Functions Pricing
Google Cloud Firestore Pricing
Google Cloud Scheduler Pricing

Reference date: 2026-07-22
Region: southamerica-east1
```

### 13.2 Cloud Functions (Gen 2)

| Tier | Volume | Preço |
|------|--------|-------|
| No-cost | 2M invocations/month | $0 |
| Beyond free | Per million invocations | USD 0.40/million |

**Nota:** Gen 2 possui componentes adicionais de compute (GB-seconds) e network que afetam o custo total além do invocation count.

### 13.3 Firestore Standard

**Free Tier (diário):**

| Operações | Cota Gratuita |
|-----------|---------------|
| Document reads | 50,000/day |
| Document writes | 20,000/day |
| Document deletes | 20,000/day |
| Storage | 1 GiB |
| Outbound | 10 GiB/month |

**Beyond free (southamerica-east1):**

| Operações | Preço |
|-----------|-------|
| Document reads | USD 0.03/100K |
| Document writes | USD 0.09/100K |
| Document deletes | USD 0.01/100K |

### 13.4 Cloud Scheduler

| Tier | Volume | Preço |
|------|--------|-------|
| No-cost | 3 jobs/month per billing account | $0 |
| Beyond free | Per job/month | USD 0.10/job/month |

**Para reconciliação diária única:** Dentro da cota gratuita (3 jobs). Não adicionar automaticamente USD 0.10.

### 13.5 Cenários de Volume (K9 Ops)

| Cenário | Dogs Ativos | MealLogs/mês | SupplementLogs/mês | Total Writes/mês |
|---------|-------------|--------------|-------------------|-----------------|
| LOW | 5 | 150 | 50 | ~200 |
| **EXPECTED** | **10** | 300 | 100 | ~400 |
| HIGH | 50 | 1,500 | 500 | ~2,000 |
| STRESS | 100 | 3,000 | 1,000 | ~4,000 |

**Base:** ~1 meal + ~0.3 supplement per dog per day.

### 13.6 Modelo Parametrizado de Custo Incremental

**Variáveis:**

| Variável | Descrição |
|----------|-----------|
| `D` | Número de dogs ativos |
| `M` | MealLogs criados por dia por dog |
| `S` | SupplementLogs criados por dia por dog |
| `W_daily` | Writes de projeção por dia = D × (M + S) |
| `W_monthly` | Writes de projeção por mês = W_daily × 30 |

**Projeção (on-write, event-driven):**

```
Reads  = 1 (ler fonte canônica)
Writes = 1 (escrever entry na timeline)

Cost_projection = W_monthly × custo_por_write
```

**Reconciliação (bounded + incremental):**

| Componente | Fórmula | Descrição |
|------------|---------|-----------|
| `N` | dogs processados | D (um por ciclo) |
| `O` | reads freshness pass | D × M × 1 read por fonte |
| `H` | reads historical sweep | D × (window/30) × M |
| `T` | reads orphan sweep | min(orphan.limit × D, total_orphans) |
| `R` | reconciliation runs/month | daily=30, weekly=4 |

```
Reads_reconciliation_monthly = R × (N + O + H + T)
```

**Para K9 Ops (EXPECTED: D=10, M=1, S=0.3, daily reconciliation):**

```
Writes projeção/mês = D × (M + S) × 30 = D × M_total × 30

Reads reconciliação/mês (bounded model):
  N = D (dogs processados por ciclo)
  O = reads freshness pass (TO BE CALIBRATED IN 5C.5B.2)
  H = reads historical sweep (TO BE CALIBRATED IN 5C.5B.2)
  T = reads orphan sweep (TO BE CALIBRATED IN 5C.5B.2)
  R = reconciliation runs/mês (30 = daily, 4 = weekly)

  Reads_total_monthly = R × (N + O + H + T)
```

**Os valores de O, H, T dependem de:**
- Volume real de dados por dog
- Page size calibrado para historical e orphan sweeps
- Watermark overlap configurado para freshness pass

**Dentro do Free Tier:**

| Operações | Cota Gratuita | Observação |
|-----------|---------------|------------|
| Document writes | 50,000/day | Projeção event-driven: D × (M+S) × 30 |
| Document reads | 50,000/day | Reconciliação bounded: depends on O, H, T calibration |

**MODELED BILLED INCREMENTAL COST: $0**
sob a premissa de que as cotas gratuitas compartilhadas do
projeto/conta de faturamento permanecem disponíveis.

**Nota:** Este é um MODELO, não garantia. Fatores que afetam custo real:
- Cotas compartilhadas já consumidas por outras funcionalidades
- Volume acima de STRESS
- orphan.limit muito alto
- Multiple reconciliation runs por dia

### 13.7 Custo Total Compartilhado do Projeto

```
Este modelo calcula custo incremental de projeção.
Não inclui custo total compartilhado do projeto
(reads/writes de outras funcionalidades, storage, etc.)
```

### 13.8 Fatores que Alterariam esta Análise

- Projeto já consumindo cotas gratuitas de outras funcionalidades
- Volume muito acima de STRESS
- Reconciliation muito frequente (além de daily)
- Large payload reads na reconciliação
- Gen 2 compute-intensive projections

### 13.9 NÃO Apresentar Centavos Fictícios

As estimativas "~$0.12", "~$0.22" foram removidas por lack of precision.

Para volumes dentro de free tier, o custo incremental é **$0**.

---

## 14. EMULATOR PROTOTYPE PLAN

**Scope for 5C.5B.2**

### 14.1 Objetivos

Validar localmente (Emulator) antes de produção:

| Objetivo | Comportamento Esperado |
|----------|------------------------|
| Deterministic ID | Same source → same timelineId |
| Idempotência | Retry same trigger → same result |
| No duplicate | Repeated projection → no duplicate entries |
| Missing projection | CREATE from source |
| Correct projection | NO-OP |
| Divergent projection | REPAIR from canonical source |
| Equal counts + missing + orphan | Detect discrepancy (NOT "all good") |
| Orphan projection | ALERT, NO auto-delete |

### 14.2 Testes de Comportamento

```typescript
// 1. Deterministic ID
describe('timelineId derivation', () => {
  it('produces same ID for same source', () => {
    const id1 = deriveTimelineId('dogs/abc/meal_logs', 'mo1_xxx');
    const id2 = deriveTimelineId('dogs/abc/meal_logs', 'mo1_xxx');
    expect(id1).toEqual(id2);
  });

  it('produces different ID for different source', () => {
    const id1 = deriveTimelineId('dogs/abc/meal_logs', 'mo1_xxx');
    const id2 = deriveTimelineId('dogs/abc/meal_logs', 'mo1_yyy');
    expect(id1).not.toEqual(id2);
  });
});

// 2. Idempotency
describe('projection idempotency', () => {
  it('retries do not create duplicates', async () => {
    await projectMealLog(mealLog);
    await projectMealLog(mealLog);
    const entries = await getTimelineEntries(mealLog.dogId);
    expect(entries.length).toEqual(1);
  });
});

// 3. Reconciliation - Missing
describe('reconciliation - missing projection', () => {
  it('detects missing projection', async () => {
    await createMealLog(mealLog);
    // Skip projection
    const result = await reconcileTimeline(mealLog.dogId);
    expect(result.missing).toContain(mealLog.id);
  });

  it('repairs missing projection', async () => {
    await createMealLog(mealLog);
    await reconcileTimeline(mealLog.dogId);
    const entry = await getTimelineEntry(mealLog.dogId, mealLog.id);
    expect(entry).toBeDefined();
  });
});

// 4. Reconciliation - Divergent
describe('reconciliation - divergent projection', () => {
  it('repairs divergent projection', async () => {
    await createMealLog(mealLog);
    await projectMealLogWithWrongData(mealLog.id, { title: 'WRONG' });
    await reconcileTimeline(mealLog.dogId);
    const entry = await getTimelineEntry(mealLog.dogId, mealLog.id);
    expect(entry.title).not.toEqual('WRONG');
  });
});

// 5. Reconciliation - Orphan Detection
describe('reconciliation - orphan detection', () => {
  it('detects orphan even when counts match', async () => {
    // Create: A, B, C
    await createMealLog(logA);
    await createMealLog(logB);
    await createMealLog(logC);

    // Project: A, B, X (C missing, X orphan)
    await projectMealLog(logA);
    await projectMealLog(logB);
    await projectOrphan(logX);

    // Counts are equal (3 = 3) but should detect discrepancy
    const result = await reconcileTimeline(dogId);
    expect(result.missing).toContain(logC.id); // C is missing
    expect(result.orphans).toContain(logX.id); // X is orphan
  });
});

// 6. Reconciliation - No Auto-Delete Orphan
describe('reconciliation - orphan handling', () => {
  it('does NOT auto-delete orphan', async () => {
    await createOrphanTimelineEntry();
    await reconcileTimeline(dogId);
    const orphan = await getTimelineEntry(orphanId);
    expect(orphan).toBeDefined(); // Still exists
  });
});
```

### 14.3 NÃO Medir SLA

Emulator timing **não é** SLA de produção.

Registrar apenas como baseline local e comportamento funcional.

### 14.4 Estrutura do Harness

```
functions/
  └── src/
        └── timeline/
              ├── timeline_id.ts         # deriveTimelineId()
              ├── meal_log_projector.ts # projectMealLog()
              ├── supplement_projector.ts # projectSupplementLog()
              ├── reconcile.ts          # reconcileTimeline()
              └── __tests__/
                    ├── timeline_id.test.ts
                    ├── projector.test.ts
                    └── reconcile.test.ts
```

---

## 15. RULES / INDEX REQUIREMENTS

**For Future Implementation (5C.5B.2+)**

### 15.1 Rules health_timeline

| Regra | Estado Atual | Requisito |
|-------|--------------|-----------|
| READ: cliente autorizado | UNVERIFIED | `canAccessDogRecord` |
| WRITE: DENY cliente | UNVERIFIED | Implicit (ausência = DENY) |
| Admin SDK/Function | ✅ | Via service account |

### 15.2 Requisito de Index

| Query | Index Necessário |
|-------|-----------------|
| `dogs/{dogId}/health_timeline orderBy occurred_at DESC` | `occurred_at DESC` |
| `dogs/{dogId}/health_timeline orderBy timeline_type, occurred_at DESC` | `timeline_type ASC, occurred_at DESC` |

### 15.3 NÃO Modificar neste Gate

Rules e indexes serão configurados no Gate de implementação (5C.5B.2+).

---

## 16. REMAINING OPEN QUESTIONS

### 16.1 Para 5C.5B.2

| # | Questão | Prioridade |
|---|---------|------------|
| Q1 | Estrutura exata do Emulator harness | Alta |
| Q2 | Test coverage threshold | Alta |
| Q3 | Estrutura de alertas de reconciliação | Média |

### 16.2 Para Gates Futuros

| # | Questão | Dependência |
|---|---------|-------------|
| Q4 | Autorização de reconciliação manual | Admin flow TBD |
| Q5 | Estrutura de reconciliation alerts | Monitoring TBD |
| Q6 | ADR-004 update (nutrition_supplements) | Autorização |

---

## 17. O3 CLOSURE ASSESSMENT

### 17.1 Status por Componente

| Componente | Status |
|------------|--------|
| O3-D1: Granularidade | ✅ DECISIONS FROZEN |
| O3-D2: Retenção | ✅ DECISIONS FROZEN |
| O3-D3: Reconciliação | ✅ DECISIONS FROZEN |
| O3-D4: SLA | ✅ DECISIONS FROZEN |
| O3-D5: source_collection | ✅ DECISIONS FROZEN |
| O3-D6: Deterministic ID | ✅ SERIALIZATION FROZEN |
| O3-D7: Dedupe | ✅ DECISIONS FROZEN |
| O3-D8: nutrition_supplements | ✅ FROZEN FOR MIGRATION |
| Cost Model | ✅ PARAMETERS DEFINED |

### 17.2 Classificação O3

```
O3 DECISIONS:                   FROZEN ✅
O3 DECISION BLOCKER FOR 5C.5B.2: REMOVED ✅

O3 BEHAVIOR VALIDATION:         PENDING 5C.5B.2
O3 PRODUCTION SLA VALIDATION:    DEFERRED TO CONTROLLED ACTIVATION
```

### 17.3 Impedimento Removido

```
O3 DECISION BLOCKER FOR 5C.5B.2: REMOVED

Nenhum impedimento documentado bloqueia o início da
implementação da foundation de projeções em 5C.5B.2.
```

### 17.4 Status Geral

```
┌──────────────────────────────────────────────────────────┐
│  O3 OVERALL STATUS:                                    │
│                                                          │
│  ARCHITECTURE CLOSURE:         ✅ COMPLETE            │
│  BEHAVIOR CLOSURE:              ⏳ PENDING 5C.5B.2      │
│                                                          │
│  O3 DECISION BLOCKER FOR 5C.5B.2:                     │
│  ✅ REMOVED                                             │
│                                                          │
│  O3 COMPLETE CLOSURE:                                  │
│  ⏳ PENDING 5C.5B.2                                    │
│                                                          │
│  PRODUCTION SLA EVIDENCE:                               │
│  ⏳ DEFERRED TO CONTROLLED ACTIVATION                   │
│                                                          │
│  PRODUCTIVE PROJECTION IMPLEMENTATION:                   │
│  ⏳ NOT YET AUTHORIZED                                 │
└──────────────────────────────────────────────────────────┘
```

**Significado:**
- **ARCHITECTURE CLOSURE:** Todas as decisões arquiteturais O3 foram
  tomadas e documentadas. Nenhum impedimento arquitetural.

- **BEHAVIOR CLOSURE:** Requer validação prática via Emulator tests
  (5C.5B.2) para confirmar que a arquitetura implementada se comporta
  conforme especificado.

- **PRODUCTION SLA EVIDENCE:** Requer deployment controlado e
  monitoramento real para confirmar SLA em produção.

---

## 18. RECOMMENDED 5C.5B.2 SCOPE

### 18.1 Título

```
5C.5B.2 — O3 PROJECTION VALIDATION — BEHAVIOR PROTOTYPE
```

### 18.2 Escopo

```
EMULATOR-ONLY VALIDATION — NO PRODUCTION CODE

1. Criar harness de testes em Emulator
   - timeline_id.ts
   - meal_log_projector.ts
   - supplement_projector.ts
   - reconcile.ts (bounded + incremental)

2. Testar comportamento funcional — Deterministic ID
   - Same source → same timelineId (determinismo)
   - Different source → different timelineId
   - Serialização: "health_timeline_v1" + source_collection + source_id

3. Testar comportamento funcional — Projeção
   - Idempotência (retry → same result, same ID)
   - No duplicate on repeated projection

4. Testar comportamento funcional — Reconciliation
   - CREATE: missing projection → entry created
   - NO-OP: correct projection → no change
   - REPAIR: divergent projection → content corrected
   - DETECT orphan even when counts match (CRITICAL)
   - NO auto-delete orphan

5. Testar comportamento funcional — Bounded Reconciliation
   - Freshness pass: watermark + overlap (calibrated in 5C.5B.2)
   - Historical sweep: bounded + cursor-paginated (page size calibrated)
   - Orphan sweep: bounded + cursor-paginated (page size calibrated)
   - Watermark: persisted between runs
   - Incremental: subsequent runs faster than first

6. Medir baseline local (não SLA de produção)
   - Tempo de propagação local
   - Comportamento de retry
   - Reads/writes por reconciliation cycle

7. NÃO fazer deploy
8. NÃO modificar produção
9. NÃO criar triggers ativos em produção
```

### 18.3 Entregável

```
Relatório de comportamento validado:
- Timeline ID derivation verificado
- Idempotência comprovada
- Reconciliation funcional
- Baseline timing local
```

---

## 19. GIT FINAL STATE

```bash
$ git status --short
?? functions/audit_prod.mjs                          (out of scope)
?? docs/health/HEALTH_V1_PHASE_5D_GATE5C5B1_O3_PROJECTION_DECISION_FREEZE.md

$ git diff --check
(no output - zero whitespace errors)

$ git diff --stat
docs/health/HEALTH_V1_PHASE_5D_GATE5C5B1_O3_PROJECTION_DECISION_FREEZE.md
```

---

## 20. VERDICT

```
╔══════════════════════════════════════════════════════════════════════╗
║                  GATE 5C.5B.1 VERDICT                       ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  STATUS:  GATE 5C.5B.1 READY FOR HUMAN AUDIT               ║
║                                                                      ║
║  STATE:   O3 DECISIONS FROZEN                                  ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  DECISIONS FROZEN:                                               ║
║  ─────────────────────────────────────────────────────────────  ║
║  ✅ O3-D1: Granularity = ONE FACT = ONE ENTRY                  ║
║  ✅ O3-D2: Retention = KEEP ALL                                ║
║  ✅ O3-D3: Reconciliation = DAILY + MANUAL                    ║
║  ✅ O3-D4: SLA = 10s target / 30s UX threshold               ║
║  ✅ O3-D5: source_collection = dogs/{dogId}/meal_logs etc.    ║
║  ✅ O3-D6: timelineId = tl1_SHA256(stableStringify([...]))    ║
║  ✅ O3-D7: Canonical × Legacy = CANONICAL WINS IF PROVABLE    ║
║  ✅ O3-D8: nutrition_supplements = NOT BACKFILLED AS FACT     ║
║  ✅ occurred_at = fed_at / administered_at / measured_at        ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  NEXT STEPS:                                                    ║
║  ─────────────────────────────────────────────────────────────  ║
║  Recommended: 5C.5B.2 — O3 BEHAVIOR PROTOTYPE (Emulator)      ║
║                                                                      ║
║  Validates:                                                      ║
║  • Deterministic ID behavior                                     ║
║  • Idempotency                                                  ║
║  • Reconciliation repair                                         ║
║  • Local baseline timing                                         ║
║                                                                      ║
║  Does NOT validate production SLA (deferred)                      ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  O3 STATUS:                                                     ║
║  ─────────────────────────────────────────────────────────────  ║
║  O3 DECISIONS:                FROZEN ✅                       ║
║  O3 DECISION BLOCKER FOR 5C.5B.2: REMOVED ✅                  ║
║  O3 BEHAVIOR VALIDATION:      PENDING 5C.5B.2                  ║
║  O3 PRODUCTION SLA:           DEFERRED                           ║
║                                                                      ║
║  O3 OVERALL:              PARTIALLY RESOLVED                       ║
║  PRODUCTIVE PROJECTION:     NOT YET AUTHORIZED                      ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## ANEXO: Decision Registry

| ID | Decisão | Status | Gate |
|----|---------|--------|------|
| O3-D1 | Granularidade | FROZEN | 5C.5B.1 |
| O3-D2 | Retenção | FROZEN | 5C.5B.1 |
| O3-D3 | Reconciliação | FROZEN | 5C.5B.1 |
| O3-D4 | SLA | FROZEN | 5C.5B.1 |
| O3-D5 | source_collection | FROZEN | 5C.5B.1 |
| O3-D6 | Deterministic ID | FROZEN | 5C.5B.1 |
| O3-D7 | Dedupe | FROZEN | 5C.5B.1 |
| O3-D8 | nutrition_supplements | FROZEN | 5C.5B.1 |
| occurred_at | occurred_at mapping | FROZEN | 5C.5B.1 |
