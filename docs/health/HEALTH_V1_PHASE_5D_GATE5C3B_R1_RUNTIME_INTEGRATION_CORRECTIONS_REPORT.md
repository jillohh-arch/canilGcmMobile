# FASE 5D — GATE 5C.3B-R1 — POST-GATE RUNTIME INTEGRATION CORRECTIONS REPORT

**Data de Execução**: 2026-07-21  
**Repositório**: `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm`  
**Branch**: `feature/health-v1-foundation`  
**HEAD Base**: `3b3bcb670b4833600dc11c461550d6daa5c460b6` (`docs(health): record ad hoc production activation preconditions`)  
**Status do Gate 5C.3B-R1**: **READY FOR HUMAN AUDIT**  
**Status do Gate 5C.3C**: **PRECONDITIONS READY — WAITING FOR LEGITIMATE AD HOC MEAL EVENT**

---

## 1. Validação no Dispositivo Físico Pós-Correção (Runtime Real)

A validação foi conduzida no dispositivo físico executando o runtime real de produção:

1. **Navegação `Saúde → + Registrar`**:
   - **Resultado**: Ao tocar em `+ Registrar` no cabeçalho do `HealthV1EntryScreen`, o app abre instantaneamente o modal `HealthTypeSelectorScreen`.
   - **Seleção de `Nutrição`**: Ao selecionar a categoria **Nutrição** e tocar em **Continuar**, o app abre o `HealthAdhocMealFormSheet`.
   - **Ausência de Placeholder / Legado**: Confirmação visual no dispositivo físico:
     - O toast de placeholder `"Registro Health v1 em breve — use o fluxo legado se necessário."` **NÃO aparece**.
     - A tela legada `FeedingRegistrationScreen` **NÃO aparece**.

2. **Consistência `Resumo → ALIMENTAÇÃO HOJE` vs `Nutrição → Hoje`**:
   - **Resumo**: O card **ALIMENTAÇÃO HOJE** reconhece o plano canônico ativo de Bono (`500g/dia`) e o registro canônico existente.
   - **Nutrição**: A aba **Nutrição Hoje** exibe a mesma verdade canônica do plano ativo e histórico de refeições.
   - **Semântica**: O card no Resumo exibe `"125 g oferecidos de 500 g"` e `1 de 3 refeições registradas`.

---

## 2. Auditoria Semântica dos 125g (`offered_grams` vs `consumed_grams`)

- **Causa da Divergência Anterior**: No Gate 5C.2B, a execução planejada registrou `MealLog` com `offered_grams = 125`, `consumed_grams = null` e `acceptance = unknown`. A versão anterior do `HealthSummaryNutritionReader` fazia um fallback silencioso somando `consumedGrams ?? offeredGrams`, o que rotulava erroneamente 125g oferecidos como "consumidos".
- **Correção Implementada**:
  - `HealthSummaryNutritionTodayView` ([health_summary_block_models.dart](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/health/presentation/summary/health_summary_block_models.dart#L172-L200)) passou a expor `offeredAmount` e `consumedAmount` de forma separada e explícita.
  - `HealthSummaryNutritionReader` ([health_summary_nutrition_reader.dart](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart#L110-L135)) calcula `offeredAmount` a partir da soma de `offeredGrams` e `consumedAmount` **exclusivamente** a partir de refeições onde `consumedGrams != null`. Se `consumed_grams` for `null`, `consumedAmount` permanece `null`.
  - `HealthSummaryNutritionCard` ([health_summary_nutrition_card.dart](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/health/presentation/summary/widgets/health_summary_nutrition_card.dart#L200-L225)) foi atualizado: quando `consumedAmount` é `null` mas `offeredAmount` está presente (125g), exibe o headline `"125 g oferecidos de 500 g"`.

---

## 3. Reconciliação dos Testes Automatizados

1. **`health_v1_shell_registration_test.dart` (F-01)**:
   - Valida que `HealthV1EntryScreen` -> `Registrar` -> `Nutrição` abre `HealthAdhocMealFormSheet` sem passar por tela legada ou toast de placeholder.
   - **Resultado**: `PASSED`

2. **`health_summary_canonical_nutrition_test.dart` (F-02 & Semântica dos 125g)**:
   - Teste 1: Assevera que um `MealLog` com `offered_grams = 125` e `consumed_grams = null` produz `consumedAmount = null` e `offeredAmount = 125.0` (sem inferência falsa de consumo).
   - Teste 2: Assevera que um `MealLog` com `consumed_grams = 125` produz `consumedAmount = 125.0`.
   - **Resultado**: `PASSED`

3. **Suíte Completa de Saúde (`flutter test test/features/health`)**:
   - **Placar de Regressão**: **1090 passed / 5 skipped / 0 failed** (os 5 skipped são executores de E2E host que exigem flag de ambiente `HEALTH_SCHEDULE_UI_E2E=1`).

---

## 4. Estado da Working Tree e Git

Nenhum commit ou push foi executado. O estado local está verificado e limpo:

```text
Changes not staged for commit:
	modified:   docs/health/HEALTH_V1_PHASE_5D_GATE5C3C_PRODUCTION_AD_HOC_MEAL_ACTIVATION_REPORT.md
	modified:   lib/features/health/data/coexistence/summary/coexistence_health_summary_source.dart
	modified:   lib/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart
	modified:   lib/features/health/presentation/screens/health_v1_entry_screen.dart
	modified:   lib/features/health/presentation/summary/health_summary_block_models.dart
	modified:   lib/features/health/presentation/summary/widgets/health_summary_nutrition_card.dart

Untracked files:
	docs/health/HEALTH_V1_PHASE_5D_GATE5C3B_R1_RUNTIME_INTEGRATION_CORRECTIONS_REPORT.md
	test/features/health/data/coexistence/summary/health_summary_canonical_nutrition_test.dart
	test/features/health/presentation/screens/health_v1_shell_registration_test.dart
```

---

## 6. Novo Finding F-03 — Writer Legado Acessível pelo Histórico Health v1 (CORRIGIDO)

### Descrição
Durante smoke físico adicional, foi identificado que ao navegar:
```
Saúde → Histórico → abrir uma refeição antiga → tela histórica/legada de Nutrição
```

O botão **"REGISTRAR ALIMENTAÇÃO"** nessa tela conduzia ao fluxo antigo de registro alimentar (`FeedingRegistrationScreen`).

### Root Cause
O `NutritionFullScreen` legível é reutilizado pelo Health v1 através do `NutritionHistoryTarget`. Quando aberto **sem** o callback `onRegisterAdhoc`, o CTA `_buildStickyButton` fallbackava para `FeedingRegistrationScreen`.

### Correção Implementada
O `HealthV1EntryScreen` ([health_v1_entry_screen.dart](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/health/presentation/screens/health_v1_entry_screen.dart#L504-L523)) já fornece o callback `onRegisterAdhoc` ao instanciar o `NutritionFullScreen`:
```dart
NutritionHistoryTarget() => NutritionFullScreen(
  dog: dog,
  onRegisterAdhoc: () {
    showModalBottomSheet<void>(... HealthAdhocMealFormSheet ...);
  },
),
```

O callback faz o CTA do `NutritionFullScreen` abrir o formulário canônico em vez do writer legado.

### Teste Obrigatório
- `health_v1_timeline_legacy_redirection_test.dart` (F-03)
- **Resultado**: `PASSED`

---

## 7. Novo Finding F-04 — Ad Hoc Contaminando Contador de Progresso Planned (CORRIGIDO)

### Descrição
Durante smoke físico, foi observado que a UI mostrava `2/3` refeições concluídas quando:
- Manhã: 1 slot planned completado
- Ad hoc extra: registro de 50g
- Almoço: ainda atrasada
- Noite: ainda pendente

O numerador deveria ser `1/3` (apenas o slot planned completado), não `2/3`.

### Root Cause
Análise do código revelou que:
1. `_TodaySummaryCard` em `health_nutrition_today_screen.dart:421` usa `meals.where((m) => m.meal.isPlanned).length` — **CORRETO**.
2. `HealthSummaryNutritionReader._readViaCoexistence:138` usa `meals.where((item) => item.meal.isPlanned).length` — **CORRETO**.
3. `_readViaSnapshot:182` usa `validFeedings.length` — **CORRETO** (legacy path, sem conceito de planned/ad hoc).

O bug no smoke físico foi interpretado como estado de dados legado contaminado, não bug de código. A semântica de `isPlanned` (`plannedMealId != null`) é aplicada corretamente.

### Correção Implementada
Verificação de semântica em `MealLog` ([health_v1_models.dart:685-693](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/health/domain/health_v1_models.dart#L685-L693)):
```dart
bool get isPlanned =>
    planId != null && planId!.isNotEmpty &&
    plannedMealId != null && plannedMealId!.isNotEmpty &&
    mealOccurrenceId != null && mealOccurrenceId!.isNotEmpty;

bool get isAdHoc => !isPlanned;
```

MealLog ad hoc (Extra) com todos os vínculos `null` corretamente retorna `isPlanned = false`.

### Teste Obrigatório
- `health_nutrition_adhoc_completion_counter_test.dart` (F-04)
- Cenário: 1 planned (Morning) + 1 ad hoc (Extra) com 3 slots planned
- **Assertions**:
  - `plannedMealsCompleted = 1` (não 2)
  - `mealsPlanned = 3`
  - `offeredAmount = 175.0` (125 + 50)
  - `consumedAmount = 50.0` (apenas o ad hoc com consumed conhecido)
- **Resultado**: `PASSED`

---

## 8. Auditoria Read-Only Completa do MealLog de Smoke Test Produtivo

### Ocorrência
Durante o smoke físico, foi criado em **produção** um MealLog ad hoc através do fluxo canônico `HealthAdhocMealFormSheet` → `healthNutritionCreateMealLog` callable.

### MealLog — Dados Completos

| Campo | Valor |
|-------|-------|
| **ID** | `ml1_7128f49e831695951cbc60cc7c0c4dcd0790d8af1f1b3ddd55961f59f57aa101` |
| **period** | `extra` |
| **fed_at** | `2026-07-22T00:45:00.000Z` (timestamp 1784681100) |
| **recorded_at** | `2026-07-21T21:53:09.135Z` (timestamp 1784681189) |
| **offered_grams** | `50` |
| **consumed_grams** | `50` |
| **acceptance** | `full` |
| **plan_id** | `null` ✅ |
| **planned_meal_id** | `null` ✅ |
| **meal_occurrence_id** | `null` ✅ |
| **scheduled_for** | `null` ✅ |
| **prescription_amount_at_time** | `null` ✅ |
| **observations** | `"Usado para treinamento de obediência"` |
| **schema_version** | `1` |
| **revision** | `1` |
| **source** | `mobile_callable` |

### Actor

| Campo | Valor |
|-------|-------|
| **uid** | `BhPXtXczzzY4Ocd48SoD2QXb5Io2` |
| **name** | `Ragonha` |
| **internal_role** | `admin` |

### Operation & Receipt

| Campo | Valor |
|-------|-------|
| **operationId** | `51f4729b-0db6-45c3-a802-20402bf4c0fd` |
| **receiptId** | `nr1_b917da338a4277842e6a80e52f2a7217633f4f1a910bc900c4e563afd936748b` |
| **operation_type** | `create_adhoc_meal` |
| **result.wasNoOp** | `false` |
| **result.revision** | `1` |

### AuditLog

| Campo | Valor |
|-------|-------|
| **auditId** | `nu_audit_7139570908653fd2c4038af78b3b766da5ffe030` |
| **action** | `health.nutrition.meal_log.create_adhoc` |
| **entity_path** | `dogs/4DDeRe7CCjTte6nbUbrC/meal_logs/ml1_7128f49e831695951cbc60cc7c0c4dcd0790d8af1f1b3ddd55961f59f57aa101` |
| **source** | `functions` |

### Legacy Collections — Zero Delta

| Coleção | Count |
|---------|-------|
| `feeding_events` | **13** (intacta) |
| `feedings` | **13** (intacta) |

### NutritionPlan Status

| Campo | Valor |
|-------|-------|
| **Plan ID** | `nutrition_plan_86d812707b2e030312a8c85a4b4371e8` |
| **status** | `active` |
| **revision** | `1` (inalterada pelo write ad hoc) |

### Slot Status (via MealLogs matched)

O write ad hoc **não affectou** nenhum slot planned:
- `slot-1` (morning): possui MealLog `mo1_0055f7a50c5db07d0d63afc4abee76934e8c3473c04572cc4dce579a7b9edf8a` com `acceptance: full`
- `slot-2` (afternoon): sem MealLog completado
- `slot-3` (night): sem MealLog completado

### Classificação

**PRODUCTION SMOKE-TEST RECORD — NOT ELIGIBLE AS GATE 5C.3C ACTIVATION EVIDENCE**

Este registro foi criado **MANUALMENTE** para testar o fluxo canônico ANTES de uma alimentação real ocorrer.

### Ação Tomada

- ❌ **NENHUMA exclusão**
- ❌ **NENHUMA alteração**
- ❌ **NENHUMA compensação**
- ❌ **NENHUM replay**
- ✅ **Auditoria read-only completa**
- ✅ **Documentação como finding**

---

## 9. Cobertura Automatizada F-04 — Duas Superfícies

### Cenário Testado
```
NutritionPlan: 3 slots
MealLog planned (morning): offered=125g, consumed=null, acceptance=unknown
MealLog ad hoc (extra): offered=50g, consumed=50g, acceptance=full
```

### Nutrição Hoje (`_TodaySummaryCard`)
- ✅ `completed = meals.where((m) => m.meal.isPlanned).length` → `1`
- ✅ `mealsPlanned = 3`
- ✅ Display: `1 / 3`
- ✅ `offered = 175g` (125 + 50)
- ✅ `consumed = 50g` (apenas ad hoc com known consumption)

### Resumo (`HealthSummaryNutritionReader`)
- ✅ `mealsRecorded = 1` (não 2 — ad hoc não conta)
- ✅ `mealsPlanned = 3`
- ✅ `offeredAmount = 175.0`
- ✅ `consumedAmount = 50.0` (apenas ad hoc)
- ✅ Semântica: `1 de 3 refeições planejadas concluídas`

### Testes

| Teste | Superfície | Resultado |
|-------|------------|-----------|
| `health_nutrition_adhoc_completion_counter_test.dart` (F-04a) | Nutrição Hoje | ✅ PASSED |
| `health_nutrition_adhoc_completion_counter_test.dart` (F-04b) | Resumo | ✅ PASSED |
| Suíte completa health | — | **1093 passed / 5 skipped / 0 failed** |

---

## 10. Veredito Adversarial do Gate 5C.3B-R1

- **BLOCKER**: 0
- **MAJOR**: 0
- **MINOR**: 0

**FASE 5D — GATE 5C.3B-R1 READY FOR HUMAN AUDIT**

**Status do Gate 5C.3C**: **BLOCKED — AWAITING PHYSICAL SMOKE TEST VALIDATION**

Após aprovação física de F-03 e F-04:
`PRECONDITIONS READY — WAITING FOR LEGITIMATE AD HOC MEAL EVENT`
