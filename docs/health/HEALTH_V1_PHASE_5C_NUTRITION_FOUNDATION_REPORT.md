# Health v1.0 — Fase 5C — Nutrition Foundation Report

| Campo | Valor |
|-------|-------|
| Status | **IMPLEMENTADA LOCALMENTE — PRONTA PARA AUDITORIA HUMANA** |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `f463d71d29bad36feecad72e3239b517b895a723` |
| Mensagem base | `docs(health): reconcile nutrition contract references` |
| Contrato | D1–D42 (`HEALTH_V1_PHASE_5B_NUTRITION_CANONICAL_DECISIONS.md`) |
| Escopo | Domínio canônico + parsers + legacy adapters + coexistence **READ-ONLY** |
| Commit / push / deploy | **NÃO** |

```text
5A = evidência
5B = contrato D1–D42
5C = foundation domínio + read/adapters  ← este relatório
5D = write path / callables / hash físico
```

---

## 1. Executive summary

Foundation canônica de Nutrição implementada **somente em leitura**, preservando D1–D42.

| Tema | Entrega |
|------|---------|
| NutritionPlan | Campos D4/D5, slots, revision, timezone, D40 `validateForActivation(serverNow)` |
| MealSchedule | VO `MealScheduleSlot` + `ScheduledTimeOfDay` |
| MealLog | offered/consumed/acceptance + D42 + vínculos D12 |
| MealOccurrence | `MealOccurrenceKey` (semântico) ≠ `MealOccurrenceId` (opaco) |
| LocalServiceDate | `YYYY-MM-DD`; TZ explícito do plano via `package:timezone` existente |
| Supplement regimen | `NutritionPlanSupplementRegimen` no plano |
| SupplementLog | dose numérica + unit + revision + relógio injetado |
| Legacy meal | D10 conservador; `almoco→afternoon`; sem occurrence artificial |
| Legacy plan | **`LegacyNutritionPlanView`** — **não** fabrica `NutritionPlan` |
| Legacy supplements | **`LegacySupplementRegimenView`** — **nunca** `SupplementLog` |
| Coexistence | merge determinístico; degraded; erro ≠ empty |
| Write | ZERO write/callable/rules/deploy |

---

## 2. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD | `f463d71d29bad36feecad72e3239b517b895a723` |
| Tracking | `origin/feature/health-v1-foundation` (0/0 no início) |
| Working tree inicial | limpo |
| Flutter / Dart | 3.41.6 / 3.11.4 |
| Timezone | `package:timezone ^0.11.0` (já no `pubspec`; **sem** dependência nova) |

---

## 3. Existing types audit

| Conceito | Decisão | Ação |
|----------|---------|------|
| `NutritionPlan` / `NutritionPlanStatus` | **ESTENDER** | valid_*, schedule, timezone, revision, D40 |
| `MealLog` | **ESTENDER** | offered/consumed/acceptance/D42/revision |
| `SupplementLog` | **ESTENDER** | revision, regimenId, validateAdministeredAt |
| `MealPeriod` | **ESTENDER** | alias `almoco` |
| `MealAcceptance` | **CRIAR** | enum + wire unknown-safe |
| `ParsedHealthEnum` / `RecordedBy` / `LegacyParse*` | **REUTILIZAR** | — |
| `NutritionPlanV2` / `MealLogV2` | **NÃO** | evolução aditiva |
| `LegacyNutritionPlanView` | **CRIAR** | §23 — não fabricar canônico |
| `LegacySupplementRegimenView` | **CRIAR** | §25 |
| `MealOccurrenceKey` / `MealOccurrenceId` | **CRIAR** | separados (§14) |

**Renames de domínio Health** (sem consumidores de produção em `NutritionService` legado):

| Antes | Depois |
|-------|--------|
| `vigentFrom` / `vigentUntil` | `validFrom` / `validUntil` |
| `MealLog.amountGrams` | `MealLog.offeredGrams` |
| `supplementIds: List<String>` | `supplements: List<NutritionPlanSupplementRegimen>` |

Operacional legado (`Feeding`, `NutritionPrescription`, `NutritionService`) **intacto**.

---

## 4. Files changed

### Domain

- `lib/features/health/domain/health_v1_enums.dart` — `MealAcceptance`, `almoco`
- `lib/features/health/domain/health_v1_models.dart` — `MealLog` canônico
- `lib/features/health/domain/nutrition_plan.dart` — plano canônico
- `lib/features/health/domain/supplement_log.dart`
- `lib/features/health/domain/meal_schedule_slot.dart` (**novo**)
- `lib/features/health/domain/meal_occurrence.dart` (**novo**)
- `lib/features/health/domain/meal_log_client_input.dart` (**novo**, D41)
- `lib/features/health/domain/nutrition_plan_regimen.dart` (**novo**)
- `lib/features/health/domain/nutrition_document_parser.dart` (**novo**)
- `lib/features/health/domain/nutrition_read_state.dart` (**novo**)
- `lib/features/health/domain/nutrition_read_models.dart` (**novo**)
- `lib/features/health/domain/legacy_nutrition_views.dart` (**novo**)

### Legacy

- `lib/features/health/legacy/legacy_health_adapters.dart` — meal D10
- `lib/features/health/legacy/legacy_nutrition_plan_adapter.dart` (**novo**)
- `lib/features/health/legacy/legacy_supplement_regimen_adapter.dart` (**novo**)

### Coexistence (read-only, delegates)

- `lib/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart`
- `lib/features/health/data/coexistence/nutrition/nutrition_merge_policy.dart`

### Tests

- Domain: plan, D42, period/acceptance, occurrence, parsers, client input, enums, supplement
- Legacy: meal, plan view, regimen
- Coexistence: merge + source scenarios

### Docs

- este arquivo

**Não alterados (propositadamente):**  
`NutritionService`, `NutritionViewModel`, telas de nutrição, AI, `firestore.rules`, indexes, callables.

---

## 5. NutritionPlan implementation

Campos: `id`, `dogId`, `foodType`, `amountGramsPerDay`, `mealsPerDay`, `mealSchedule`, `validFrom`, `validUntil?`, `timezone`, `status`, `recordedBy`, `schemaVersion`, `revision`, opcionais aprovados + `legacySource`/`legacyId`.

Invariantes rígidas:

- `amountGramsPerDay > 0`, `mealsPerDay > 0`, `revision >= 1`
- timezone IANA não vazio (via `package:timezone`)
- `validUntil == null || validUntil > validFrom` (estrito)
- slot ids únicos

**D40:** `validateForActivation(serverNow)` — **sem** `DateTime.now()`; parsing histórico não muta o objeto; sem status `scheduled`.

**Coerência** `mealsPerDay` × `schedule.length` × `sum(targetGrams)`:  
**diagnóstico** via `diagnoseCoherence()` — **não** rejeição rígida (tolerância institucional não congelada).

---

## 6. MealSchedule implementation

`MealScheduleSlot`: `id`, `period` (`ParsedHealthEnum`), `scheduledTime` (`HH:mm` 00:00–23:59), `targetGrams > 0`.  
Identidade = `id` estável, **não** índice do array.  
Sem geração de IDs aleatórios no domínio de leitura.

---

## 7. MealLog implementation

Campos D7 + D39 + soft provenance.  
**D42** em `validateQuantityInvariantsPublic` / construtor.  
**fed_at:** `validateFedAt(referenceTime)` — relógio injetado; parsing legado **não** bloqueia por futuro (validação de criação é distinta).  
Vínculo planejado: plan + slot + occurrence juntos ou nenhum (D12).

---

## 8. MealOccurrence implementation

| Tipo | Papel |
|------|--------|
| `MealOccurrenceKey` | dogId + planId + plannedMealId + localServiceDate; == / hashCode; `diagnosticLabel` |
| `MealOccurrenceId` | string opaca não vazia; **sem** SHA/UUID congelado |

Hash físico = **DEFERRED 5D (Q7)**.

---

## 9. LocalServiceDate

- Valor `YYYY-MM-DD`, sem horário, sem TZ embutido
- `fromIso` / `fromInstant(instant, timezone:)` com TZ **explícito**
- Reutiliza `package:timezone` já presente
- **Não** usa timezone do device
- Instant para backdated (`fed_at` vs `serverNow`) = **DEFERRED 5D**

---

## 10. Supplement regimen

`NutritionPlanSupplementRegimen` no plano: id, name, dose (texto de prescrição), unit, frequency, instructions?, validFrom?, validUntil?.  
**≠** `SupplementLog`. **≠** `nutrition_supplements` legado.

---

## 11. SupplementLog implementation

Dose **numérica** finita `> 0`; unit enum; `revision >= 1`; `validateAdministeredAt(referenceTime)`.  
Opcionais: plan/regimen/protocol/notes/batch/legacy.

---

## 12. Enum/parsers

- `MealPeriod`: wire EN; legado `manha|almoco|noite`
- `MealAcceptance`: full|partial|refused|unknown — unknown-safe
- Parsers de mapa: `NutritionPlanDocumentParser`, `MealLogDocumentParser`, `SupplementLogDocumentParser` — puro Dart, sem Firebase

---

## 13. Legacy meal adapter

`LegacyNutritionAdapter` → `MealLog` (quando autoria suficiente) ou partial view.

| Campo | Mapeamento D10 |
|-------|----------------|
| offeredGrams | amount_grams |
| consumedGrams | null |
| acceptance | unknown |
| plan/slot/occurrence | null |
| legacyAmountGrams | amount_grams |
| legacyPhotoBalanceUrl | photo_balance_url |
| source | `legacy_read` |
| legacySource | collection / feeding_events |

`amount <= 0` / ausente / inválido → **issue explícita** (não corrige para 1).  
Autoria: `recorded_by` completo ou partial com warning (padrão Health v1).

---

## 14. Legacy plan compatibility adapter

`LegacyNutritionPlanAdapter` → **`LegacyNutritionPlanView`** apenas.

- `mealScheduleUnavailable = true`
- **Não** inventa slots, horários, `NutritionPlanStatus` persistido
- `rawStatus` bruto se presente
- Warning `meal_schedule_unavailable`

---

## 15. Legacy supplement regimen adapter

`LegacySupplementRegimenAdapter` → `LegacySupplementRegimenView`.  
Preserva dose **textual**.  
**Nunca** produz `SupplementLog` / `administeredAt`.

---

## 16. Read contracts

Interfaces injetáveis (sem create/save/update/delete):

- `NutritionCanonicalPlanReader` / `NutritionLegacyPlanReader`
- `NutritionCanonicalMealReader` / `NutritionLegacyMealReader`
- `NutritionCanonicalSupplementLogReader` / `NutritionLegacySupplementRegimenReader`

`CoexistenceNutritionReadSource` compõe e normaliza.  
**Não** ligado ao composition root / UI / `NutritionService`.

---

## 17. Coexistence read model

`NutritionCoexistenceSnapshot`:

- `activePlan`: `NutritionActiveCanonicalPlan` | `NutritionActiveLegacyPlan` | none
- meals normalizadas
- **listas separadas:** `canonicalSupplementLogs` vs `legacySupplementRegimens`
- source statuses + merge diagnostics

---

## 18. Merge/dedupe rules

| Regra | Comportamento |
|-------|----------------|
| feeding_events × feedings, mesmo id | **feeding_events vence** + warning se payload divergir |
| Canônico × legado | Canônico vence **somente** com proveniência `legacyId` (+ source quando houver) |
| Sem proveniência | **Não** dedupe por fedAt/amount/period |
| Ordem | `fedAt DESC`, empate `mergeKey ASC` |
| Plano active | Canônico active vence; senão fallback view legado |

---

## 19. Error semantics

`NutritionReadStatus`: loading | data | empty | **degraded** | offline | error

| Cenário | Resultado |
|---------|-----------|
| Ambos ok com dados | data |
| Ambos ok vazios | empty |
| Uma fonte falha + dados da outra | **degraded** |
| Ambas falham | error/offline |
| **Nunca** | catch → [] / erro → empty |

---

## 20. Dependency boundary

```text
domain/          → Dart puro (+ package:timezone já no projeto)
legacy/          → domain + maps; ZERO Firebase
coexistence/     → domain + delegates; ZERO Firebase
presentation/    → não alterada nesta fase
features/nutrition legado → intacto
```

---

## 21. Zero-write proof

Busca em arquivos novos/alterados da foundation por:

```text
FirebaseFirestore, FirebaseFunctions, CollectionReference, DocumentReference,
.set(, .update(, .delete(, runTransaction, writeBatch, httpsCallable
```

**Nenhum write path.** Matches de `.add(` são `List.add` / issues de parse — não Firestore.

Paths canônicos **não** conectados ao app de produção.

---

## 22. Tests

| Suite | Resultado |
|-------|-----------|
| Foundation 5C (domain/legacy/coexistence nutrition) | **PASS** |
| `flutter test test/features/health` | **+955 ~2 — All tests passed** |
| `flutter test` (global) | **+1138 ~3 — All tests passed** |

Cobertura obrigatória: D40, D42, occurrence key, almoco, legacy views, merge §22/§30, degraded, dog isolation, ordering.

---

## 23. Analyze

```text
flutter analyze <arquivos 5C nutrition>
→ No issues found
```

Warnings históricos fora do diff: não atribuídos a 5C.

---

## 24. Git diff

```text
Branch: feature/health-v1-foundation
HEAD: f463d71… (sem commit novo)
git diff --check: OK
```

Somente arquivos da Fase 5C (+ este relatório). Sem temp.

---

## 25. Findings / deferred items

| ID | Classe | Nota |
|----|--------|------|
| Q7 hash occurrence | **DEFERRED 5D** | Identidade semântica ok; físico não congelado |
| fed_at vs local_service_date backdated | **DEFERRED 5D** | |
| Janela late | **DEFERRED** (Q6) | |
| Inventário amount_grams inválido | **DEFERRED UNTIL INVENTORY** | Adapter rejeita; não inventa valor |
| Defaults de horários legado | **DEFERRED** | View sem schedule |
| Dual-write legado feedings | **ACCEPTED LEGACY** | Não estendido; não removido |
| NutritionService writes | **ACCEPTED LEGACY** | Intactos até cutover |

Nenhum **BLOCKER** aberto para fechar 5C foundation.

---

## 26. Final readiness

Checklist:

```text
[x] D1–D42 preservadas
[x] domínio puro sem Flutter/Firebase (timezone package pré-existente)
[x] NutritionPlan canônico completo
[x] MealSchedule completo
[x] MealLog completo + D42
[x] MealOccurrenceKey ≠ MealOccurrenceId
[x] hash físico não congelado
[x] LocalServiceDate explicitada
[x] SupplementLog dose numérica + unit
[x] legacy meal conservador + almoco
[x] legado sem occurrence artificial
[x] legacy plan não fabrica slots / NutritionPlan
[x] nutrition_supplements não vira SupplementLog
[x] coexistence read-only
[x] canônico vence só com proveniência **inequívoca** (source+id)
[x] legacyId sozinho não deduplica
[x] >1 active canônico detectável (integrity conflict)
[x] erro não vira empty (degraded explícito)
[x] nenhum write novo
[x] runtime legado (NutritionService/UI/AI) não alterado
[x] testes Health verdes
[x] analyze sem novo issue nos arquivos 5C
[x] git diff --check OK
[x] sem commit/push/deploy
```

---

## 27. Final adversarial audit

| Campo | Valor |
|-------|-------|
| Data auditoria | 2026-07-18 |
| HEAD base | `f463d71d29bad36feecad72e3239b517b895a723` |
| Escopo | Diff real 5C vs D1–D42 + Domain Model + Schema |
| Commit desta auditoria | **NÃO** |

### 27.1 Preflight

```text
Branch: feature/health-v1-foundation
HEAD:   f463d71d29bad36feecad72e3239b517b895a723
Tracking: origin/feature/health-v1-foundation 0/0
Diff: somente arquivos health nutrition foundation + relatório
NutritionService / UI / rules / indexes: intocados
```

### 27.2 Gate A — provenance dedupe (MAJOR encontrado e **corrigido**)

**Achado (MAJOR):** `mergeCanonicalAndLegacyMeals` aceitava `hitById` com **somente** `legacyId`, mascarando colisões entre collections.

**Correção:**

- `NutritionLegacySourceIdentity.normalize` + `matchesProvenience`
- Dedupe **somente** quando `normalize(legacySource) + legacyId` casa com `normalize(collectionKey) + id`
- `legacyId` sozinho → **ambos preservados** + diagnóstico `insufficient_provenience_same_legacy_id`
- Collections distintas (`feeding_events` vs `feedings` vs `nutritional_prescriptions`) **não** deduplicam

| Caso | Resultado pós-fix |
|------|---------------------|
| A: source+id bate | 1 canônico |
| B: legacyId only | 2 itens |
| C: events canônico × feedings legado | 2 itens |
| C-pipeline: events+feedings colapsam → canônico events | 1 canônico |
| D: outra collection | 2 itens |

### 27.3 Gate B — múltiplos active (MAJOR encontrado e **corrigido**)

**Achado (MAJOR):** `_latestActiveCanonical` escolhia silentemente o active “mais recente”, mascarando violação D3.

**Correção:**

- Reader continua `Future<NutritionSourceBatch<NutritionPlan>>` / lista (não `limit(1)`)
- `resolveActivePlan`:
  - 0 active → fallback legado view
  - 1 active → `NutritionActiveCanonicalPlan`
  - **>1 active → `NutritionActivePlanIntegrityConflict`** (lista completa; sem escolha)
- Diagnostic `multiple_active_nutrition_plans` no snapshot

**Resposta:** SIM — múltiplos active são detectáveis e não mascarados.

### 27.4 Demais gates (sem BLOCKER/MAJOR remanescente)

| Gate | Status |
|------|--------|
| Plano legado = view, não NutritionPlan | OK |
| nutrition_supplements ≠ SupplementLog | OK |
| MealOccurrenceKey ≠ MealOccurrenceId | OK |
| D41 PlannedMealClientInput sem campos server | OK (estrutura sem period/occurrence/recordedBy/revision) |
| D42 + NaN/Infinity | OK |
| Parsers não silenciam corrupção | OK (testes de integrity ampliados) |
| feeding_events × feedings rank fixo | OK (independente de ordem de Futures) |
| Error semantics degraded | OK |
| Dog isolation (stateless + filter dogId) | OK |
| Zero-write domain/legacy/coexistence | OK |
| Timezone: `initializeTimeZones` encapsulado e idempotente em `fromInstant` / plan timezone | OK — determinístico em teste e runtime sem init prévia global do app; **não** usa device TZ |
| package:timezone | ACCEPTED (Dart puro, já no pubspec) |

### 27.5 Findings classificados

| ID | Classe | Estado |
|----|--------|--------|
| Provenance legacyId-only | **MAJOR** | **CORRIGIDO** nesta auditoria |
| Multiple active silent pick | **MAJOR** | **CORRIGIDO** nesta auditoria |
| Hash físico occurrence | DEFERRED 5D | aberto (não bloqueia) |
| fed_at vs local_service_date backdated | DEFERRED 5D | aberto |
| Dual-write operacional legado | ACCEPTED LEGACY | intocado |
| Timezone init encapsulado | MINOR note | aceito; documentado |

**BLOCKER aberto:** zero  
**MAJOR aberto:** zero  

### 27.6 Validações pós-correção

```text
flutter test test/features/health   → +969 ~2 All tests passed
flutter test                        → +1152 ~3 All tests passed
flutter analyze <5C files>          → No issues found
git diff --check                    → OK
```

### 27.7 Critério final

```text
[x] dedupe canônico×legado exige provenance inequívoca
[x] legacyId sozinho nunca causa dedupe falso
[x] múltiplos canonical active são detectáveis
[x] >1 active não é mascarado por limit(1) nem “mais recente”
[x] plano legado continua view
[x] suplemento legado nunca vira SupplementLog
[x] occurrence key ≠ occurrence id
[x] D41 estruturalmente preservada
[x] D42 completa
[x] parsers não silenciam corrupção
[x] timezone dependency auditada
[x] erro nunca vira empty
[x] dog isolation preservada
[x] zero-write comprovado
```

---

```text
FASE 5C — AUDITORIA ADVERSARIAL CONCLUÍDA.

ZERO BLOCKER.

ZERO MAJOR.

FOUNDATION CANÔNICA APROVADA PARA COMMIT.

NENHUM WRITE NOVO.

NENHUMA RULE.

NENHUMA CALLABLE.

NENHUM DEPLOY.

COMMIT E PUSH AINDA NÃO REALIZADOS.
```

