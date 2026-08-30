# HEALTH v1 — Fase 5D Gate 3 — Flutter Mutation Client Report

**Branch:** `feature/health-v1-foundation`  
**Base HEAD (Gate 2):** `fc6d47bce82e907fd4dd34208a88975434f081ff`  
**Escopo:** Flutter Nutrition mutation gateway + controller (sem cutover operacional)  
**Data:** 2026-07-19  

---

## 1. Executive summary

Gate 3 implementa a camada Flutter canônica de **mutação de Nutrição** consumindo as callables aprovadas no Gate 2:

```text
healthNutritionCreateMealLog
healthNutritionCreateSupplementLog
```

Inclui:

- gateway tipado + implementação Firebase Functions
- commands/results/errors tipados
- transport snake_case + ISO-8601 UTC
- controller com operationId estável, double-submit e retry-safe
- composition root preparado **sem** ativar UI operacional
- fluxo legado `NutritionService` / `FeedingRegistrationScreen` **intacto**

**ZERO** Functions / Rules / deploy / cutover de read canônico.

**Status:** GATE 3 APROVADO PARA COMMIT — ZERO BLOCKER, ZERO MAJOR após auditorias adversariais §§37–39.

---

## 2. Preflight

| Item | Valor |
|------|-------|
| Branch | `feature/health-v1-foundation` |
| HEAD base | `fc6d47bce82e907fd4dd34208a88975434f081ff` |
| Tracking | `origin/feature/health-v1-foundation` · 0/0 |
| Working tree (início) | limpo |
| Flutter | 3.41.6 stable |
| Dart | 3.11.4 |
| cloud_functions | ^6.3.1 |

---

## 3. Existing Flutter mutation patterns

Espelho da Agenda Preventiva (4E):

| Agenda | Nutrição Gate 3 |
|--------|-----------------|
| `HealthScheduleMutationGateway` | `HealthNutritionMutationGateway` |
| `FirebaseFunctionsHealthScheduleMutationGateway` | `FirebaseFunctionsHealthNutritionMutationGateway` |
| `HealthScheduleMutationPayloadCodec` | `HealthNutritionMutationPayloadCodec` |
| `HealthScheduleFunctionsErrorMapper` | `HealthNutritionFunctionsErrorMapper` |
| `HealthScheduleMutationController` | `HealthNutritionMutationController` |
| `southamerica-east1` | **igual** |
| invoker injectável | **igual** |
| FailClosed gateway | **igual** |

Não foi criada convenção paralela.

---

## 4. Existing nutrition consumers audit

| Consumidor | Classificação | Gate 3 |
|------------|---------------|--------|
| `NutritionService` / `addFeeding` | **LEGACY OPERACIONAL** | **intacto** |
| `NutritionViewModel` | LEGACY OPERACIONAL | intacto |
| `FeedingRegistrationScreen` | LEGACY OPERACIONAL | **não alterada** |
| `NutritionFullScreen` | LEGACY OPERACIONAL | intacta |
| `CoexistenceNutritionReadSource` (5C) | HEALTH V1 canônico (read foundation) | não ativado em produção |
| Health shell / Nutrição slot | COMPARTILHADO / placeholder | sem botão canônico de write |

Regra: **nenhum redirecionamento silencioso** do fluxo legado.

---

## 5. Files changed

Fonte de verdade: `git status` / `git ls-files --others` no fechamento.

### Novos

```text
lib/features/health/domain/health_nutrition_mutation_commands.dart
lib/features/health/domain/health_nutrition_mutation_errors.dart
lib/features/health/domain/health_nutrition_mutation_gateway.dart
lib/features/health/data/nutrition/health_nutrition_callable_names.dart
lib/features/health/data/nutrition/health_nutrition_callable_invoker.dart
lib/features/health/data/nutrition/health_nutrition_mutation_payload_codec.dart
lib/features/health/data/nutrition/health_nutrition_functions_error_mapper.dart
lib/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart
lib/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart
lib/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart
lib/features/health/presentation/nutrition/health_nutrition_pending_intent.dart
lib/features/health/presentation/nutrition/health_nutrition_pending_intent_session.dart
test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart
test/features/health/presentation/nutrition/health_nutrition_mutation_controller_test.dart
test/features/health/presentation/nutrition/health_nutrition_pending_intent_session_test.dart
docs/health/HEALTH_V1_PHASE_5D_GATE3_FLUTTER_MUTATION_CLIENT_REPORT.md
```

### Alterados

```text
lib/features/health/presentation/screens/health_v1_entry_screen.dart
  → gateway/controller Nutrição; holder injetável (sem UI de write)

lib/features/app_shell/presentation/screens/main_root_screen.dart
  → HealthNutritionPendingIntentSession no State do MainRoot

lib/features/app_shell/presentation/screens/main_root_widgets.dart
  → _MainRootHealthTab injeta session.holderFor(dogId) no Entry
```

### Não alterados

```text
functions/**
firestore.rules
firestore.indexes.json
storage.rules
lib/features/nutrition/** (legado)
```

---

## 6. Gateway contract

```dart
abstract interface class HealthNutritionMutationGateway {
  Future<HealthNutritionMutationResult> createPlannedMealLog(...);
  Future<HealthNutritionMutationResult> createAdhocMealLog(...);
  Future<HealthNutritionMutationResult> createSupplementLog(...);
}
```

Sem plan create/update, cancel ou correct neste Gate.

---

## 7. Firebase Functions gateway

`FirebaseFunctionsHealthNutritionMutationGateway`

- `FirebaseFunctions.instanceFor(region: 'southamerica-east1')` (lazy)
- Callables exatas (sem aliases)
- Invoker injectável para testes
- **Zero** dependência de `FirebaseFirestore` para mutation

---

## 8. Planned meal command

`CreatePlannedMealLogCommand`

Campos cliente: dogId, planId, plannedMealId, offeredGrams, consumedGrams?, acceptance, fedAt, observations?, attachmentRefs?, operationId  

**Sem** period, scheduledFor, mealOccurrenceId, localServiceDate, prescriptionAmountAtTime, recordedBy, revision, schemaVersion.

---

## 9. Ad hoc meal command

`CreateAdhocMealLogCommand`

Campos: dogId, period, offeredGrams, consumedGrams?, acceptance, fedAt, observations?, attachmentRefs?, operationId  

**Sem** planId / plannedMealId / mealOccurrenceId.  
Cliente **não** resolve plano ativo.

---

## 10. Supplement command

`CreateSupplementLogCommand`

dose numérica + unit canônica (`SupplementDoseUnit`).  
Regimen sem plan → validation local (`supplement_regimen_requires_plan`); backend continua autoridade final.

---

## 11. Transport mapping

Wire **snake_case** exclusivo no encode:

### Planned

```text
mode, dog_id, plan_id, planned_meal_id, offered_grams, consumed_grams?,
acceptance, fed_at, observations?, attachment_refs?, operation_id
```

### Ad hoc

```text
mode=adhoc, dog_id, period, offered_grams, ...
```

### Supplement

```text
dog_id, supplement_name, dose, unit, administered_at,
nutrition_plan_id?, supplement_regimen_id?, notes?, batch_number?,
protocol_id?, operation_id
```

Nulls opcionais omitidos. Sem camelCase mirrors no request.

---

## 12. Date wire

```text
fedAt / administeredAt → toUtc().toIso8601String()
```

Testado: DateTime local e UTC → mesmo instant ISO.

---

## 13. Result decoding

### Meal

```text
dogId, mealId, revision, wasNoOp, mealOccurrenceId?
```

### Supplement

```text
dogId, supplementLogId, revision, wasNoOp
```

**Precedência:** snake_case canônico vence camelCase espelho.

---

## 14. Response integrity

Fail-closed:

```text
missing meal_id / supplement_log_id
invalid revision (< 1)
invalid was_no_op
mapa ausente
```

→ `HealthNutritionMutationIntegrity` (não sucesso parcial).

---

## 15. Error mapping

`HealthNutritionFunctionsErrorMapper` mapeia `FirebaseFunctionsException`.

Preserva `details.code`. Distingue:

| details.code | Tipo Dart |
|--------------|-----------|
| `idempotency_conflict` | `HealthNutritionMutationIdempotencyConflict` |
| `meal_occurrence_conflict` | `HealthNutritionMutationMealOccurrenceConflict` |

Também: unauthenticated, permission-denied, validation, not-found, unavailable, network, integrity, failed-precondition.

---

## 16. Composition root

Arquitetura **canônica** (única, pós-§38):

```text
MainRootScreen State
  └── HealthNutritionPendingIntentSession
        └── holderFor(dogId)
              └── HealthV1EntryScreen(nutritionPendingIntentHolder: ...)
                    └── HealthNutritionMutationController
                          gateway: FirebaseFunctionsHealthNutritionMutationGateway
                          onRefreshAfterSuccess: null
```

- Entry **não** é o owner de produção do holder (só fallback de teste se null).
- **Sem** botão operacional / form canônico visível.

---

## 17. Mutation controller

`HealthNutritionMutationController`

- `isSubmitting`, `lastResult`, `lastError`
- `createPlannedMeal` / `createAdhocMeal` / `createSupplement`
- UUID v4 via pacote `uuid` (já no projeto)
- fingerprint local de intenção (não enviado ao backend)

---

## 18. Operation ID lifecycle

| Evento | Key / pending |
|--------|----------------|
| primeiro submit intenção A | gera opA, guarda no holder |
| retry **mesmo** fingerprint | **reutiliza** opA |
| fingerprint diferente com pending ativa | **bloqueia** (`pending_intent_incompatible`); **opA intacta** |
| após `discardIntent()` + nova intenção | **nova** key |
| success confirmado | `discardIntent` — encerra pending |
| `dispose()` técnico do controller | **NÃO** limpa pending |
| remount Entry com session holder | restaura opA |

---

## 19. Double-submit protection

`isSubmitting == true` → segundo tap retorna `HealthNutritionMutationUiBlocked` (sem nova operação).

---

## 20. Retry semantics

Política **conservadora** neste Gate (sem distinção uncertain vs deterministic para overwrite):

| Situação | Comportamento |
|----------|----------------|
| pending existe + mesmo fingerprint | retry com **mesma** key |
| pending existe + fingerprint diferente (same ou cross-kind) | **bloqueia** até `discardIntent` |
| unavailable / network / validation / permission / conflict | se pending permanece, key **preservada** |

Não reexecuta automaticamente — UI decide retry ou discard.

---

## 21. Intent change semantics

Fingerprint local: kind/mode + campos semânticos + instants ISO (sem operationId).

```text
pending ativa + fingerprint diferente
→ pending_intent_incompatible
→ NÃO cria operationId B
→ holder permanece com A
```

Nova key só após:

```text
discardIntent()  // semântico
// ou success (pending limpa) e novo submit
```

---

## 22. Refresh semantics

```text
savedAndRefreshed  (refreshFailed=false)
savedButRefreshFailed (refreshFailed=true + warning)
```

wasNoOp = **sucesso** (“Registro salvo com sucesso”).

Default composition: `onRefreshAfterSuccess: null` → não inventa falha de refresh.

---

## 23. Read/write visibility gap

| Write canônico | Read operacional atual |
|----------------|------------------------|
| `meal_logs` / `supplement_logs` | `feeding_events` / `feedings` / `nutrition_supplements` |

Rules ainda não liberam client-read canônico (5C).

**Consequência documentada:** write canônico **≠** visibilidade na UI legada.

Gate 3 **não** mascara esse gap.

---

## 24. UI integration boundary

- Sem tela de registro canônica ativada em produção
- Sem rota operacional nova de write
- Controller/gateway prontos para Gate 4 / harness

---

## 25. Legacy flow preservation

```text
NutritionService.addFeeding — intacto
FeedingRegistrationScreen — intacta
dual-write legado — não removido
```

---

## 26. Zero direct Firestore write

Gateway usa **somente** `FirebaseFunctions` / invoker HTTPS.  
Nenhuma API Firestore no caminho de mutação canônico.

Evidência: testes unitários com invoker fake; ausência de imports `cloud_firestore` nos arquivos de mutation Nutrição.

---

## 27. Gateway tests

`test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart`

- planned/adhoc/supplement payloads  
- ISO UTC  
- snake_case preference  
- integrity (missing id, bad revision)  
- error mappings (permission, idempotency, occurrence, unavailable)  
- **verde**

---

## 28. Controller tests

`test/features/health/presentation/nutrition/health_nutrition_mutation_controller_test.dart`

- success + wasNoOp  
- double-submit  
- retry key reuse (mesmo fingerprint)  
- pending + payload/fingerprint diferente → `pending_intent_incompatible`  
  (operationId anterior preservada)  
- após `discardIntent` explícito → nova intenção recebe nova key  
- same-kind supplement/adhoc/planned uncertain block  
- fedAt preserved on same-fingerprint retry  
- refresh failure separated  
- dispose técnico não limpa pending  
- session remount / dog isolation  
- **verde**

---

## 29. Emulator/integration validation

Flutter gateway E2E completo (Auth+Functions Emulator) **não** executado neste Gate (sem harness Flutter Auth automatizado dedicado).

Evidência backend: Gate 2 `httpsCallable` E2E real permanece baseline.  
Gateway Flutter coberto por invoker fake + mapeamento de erros idêntico ao wire Gate 2.

Classificação: **MINOR / DEFERRED** se exigido E2E Flutter HTTP — não bloqueia (critério: “não declarar E2E Flutter completo sem executá-lo” — **não declarado**).

---

## 30. Health regression tests

```text
flutter test test/features/health
→ +1014 ~2 All tests passed (fechamento)
```

---

## 31. Full Flutter regression

```text
flutter test
→ +1197 ~3 All tests passed (fechamento)
```

---

## 32. Analyze

```text
flutter analyze
→ issues totais: 46 (info/warning históricos do repo)
→ novos errors Gate 3: 0
→ novos warnings Gate 3: 0
→ Gate 3: apenas 2× info use_super_parameters
  (health_nutrition_mutation_errors.dart)
```

---

## 33. Git diff

Escopo real do Gate 3:

```text
lib/features/health/**          (domain/data/presentation nutrition mutation)
lib/features/app_shell/**       (MainRoot session ownership — mínimo necessário)
test/features/health/**         (gateway/controller/session tests)
docs/health/**                  (este relatório)
```

Confirmações:

```text
ZERO functions/**
ZERO firestore.rules
ZERO firestore.indexes.json
ZERO storage.rules
ZERO lib/features/nutrition/** legacy changes
ZERO deploy
```

---

## 34. Findings

| ID | Severidade | Status |
|----|------------|--------|
| G3-PENDING-DISPOSE | **MAJOR** | Pending intent perdida no dispose do controller → **CORRIGIDO** (§37) |
| G3-HOLDER-OWNER | **MAJOR** | Holder no Entry descartável (dog/turno) → **CORRIGIDO** (§38 MainRoot session) |
| G3-SAME-KIND-OVERWRITE | **MAJOR** | Same-kind fingerprint change sobrescrevendo pending → **CORRIGIDO** (§39; bloqueio fail-closed) |
| G3-MIRROR-MASK | MINOR→fail-closed | Mirrors contraditórios mascarados → **CORRIGIDO** (§37) |
| G3-DOC-RECONCILIATION | **MINOR** | Seções históricas contradiziam contrato final PendingIntent / lista de arquivos incompleta → **CORRIGIDO** (fechamento) |
| G3-RW-GAP | ACCEPTED LEGACY / DEFERRED GATE 4 | Read/write visibility gap documentado; sem cutover |
| G3-FLUTTER-E2E | MINOR | Gateway E2E Flutter+Emulator não executado; Gate 2 backend E2E + unit invoker cobrem contrato |
| G2-N22 / G2-AC | MINOR / HARDENING | Herdados do Gate 2; fora de escopo |
| BLOCKER aberto | — | **0** |
| MAJOR aberto | — | **0** |

---

## 35. Deferred Gate 4

```text
canonical read activation
read-after-write UX
nutrition today canonical UI
feeding registration cutover
supplement administration UI
legacy dual-write retirement
Rules/client-read activation
migration/backfill strategy
production deployment
Flutter Emulator gateway E2E (opcional)
```

---

## 36. Final readiness

```text
[x] typed gateway implementado
[x] Firebase Functions gateway real
[x] planned command sem server-authoritative fields
[x] ad hoc command sem plan links
[x] supplement command correto
[x] ISO date wire
[x] results fail-closed
[x] details.code preservado
[x] idempotency conflict distinguível
[x] occurrence conflict distinguível
[x] controller com operationId estável
[x] double-submit protegido
[x] retry incerto reutiliza key
[x] mudança semântica com pending ativa é bloqueada
[x] operationId anterior permanece preservada
[x] após discard explícito, nova intenção recebe nova key
[x] wasNoOp tratado como sucesso
[x] success + refresh failure separado
[x] zero direct Firestore write novo
[x] legacy NutritionService intacto
[x] FeedingRegistrationScreen produtiva intacta
[x] nenhuma UI operacional cria write canônico invisível
[x] composition root canônico preparado (MainRoot session → Entry)
[x] same-kind fingerprint change com pending → bloqueio (opA intacta)
[x] testes gateway verdes
[x] testes controller verdes
[x] Health tests verdes
[x] analyze sem regressão de erros
[x] ZERO Functions changes
[x] ZERO Rules
[x] ZERO deploy
```

### FASE 5D — GATE 3 APROVADO PARA COMMIT

---

## 37. Final adversarial audit

### Problema original (MAJOR)

```text
dispose() do controller → endIntent() limpava operationId
```

Após `unavailable` / `network`, se o widget/controller fosse recriado, o retry gerava **nova** operationId.

Para AdHoc / Supplement a identidade física é `ml1_*` / `sl1_*` derivada da key → risco de **duplicação real**.

### Estratégia escolhida

```text
HealthNutritionPendingIntent
  + HealthNutritionPendingIntentHolder (externo ao ChangeNotifier)
  + HealthNutritionPendingIntentSession no MainRoot (owner de produção)
```

- Owner de produção: **MainRoot session** (não o State do Entry).
- Controller lê/escreve no holder.
- `dispose()` técnico: **não** limpa holder.
- `discardIntent()`: descarte **semântico** (usuário abandonou).
- Sucesso confirmado: chama `discardIntent()`.

Controller lifecycle **≠** intent lifecycle.

### Comportamento pós-correção

| Evento | operationId |
|--------|-------------|
| Success | pending encerrada; ação posterior → nova key |
| Erro determinístico | preservada no holder (mesma fingerprint) |
| Erro incerto (unavailable/network) | preservada no holder |
| dispose técnico | **preserva** holder |
| recreate controller + mesmo payload | **mesma** key |
| discardIntent explícito + nova intenção | **nova** key |
| mudança semântica com pending ativa | **pending_intent_incompatible**; key anterior **preservada** |

### Response mirror integrity

Antes: snake vencia silenciosamente em contradição.

Agora:

```text
snake + camel iguais → aceitar (canônico = snake)
snake + camel diferentes → HealthNutritionMutationIntegrity
só camel → aceitar fallback
só snake → aceitar
```

Campos cobertos: dog_id, meal_id, was_no_op, meal_occurrence_id, supplement_log_id (+ mirrors).

### Testes adversarial

```text
supplement unavailable → dispose → recreate → same opId
adhoc network → dispose → recreate → same opId
explicit discard → nova key
success → próxima ação nova key
mirror contradictions → integrity
equivalent mirrors → accept
```

### flutter analyze

```text
flutter analyze → 46 issues (info/warning)
Gate 3: apenas 2× info use_super_parameters em
  health_nutrition_mutation_errors.dart
Sem error novo. Warnings listados são preexistentes
  (shifts, tests schedule/summary, etc.).
```

### Findings finais

| Finding | Antes | Depois |
|---------|-------|--------|
| Pending intent lost on controller dispose | **MAJOR** | **CORRIGIDO** |
| Contradictory response mirrors silently masked | MINOR/MAJOR | **CORRIGIDO** (fail-closed) |
| Read/write visibility gap | DEFERRED G4 | documentado |
| Flutter Emulator gateway E2E | MINOR | não declarado como completo |
| BLOCKER aberto | — | **0** |
| MAJOR aberto | — | **0** |

### Critério final

```text
[x] technical dispose != semantic discard
[x] uncertain mutation preserves operationId across controller restoration
[x] ad hoc retry cannot gain a new key silently
[x] supplement retry cannot gain a new key silently
[x] explicit discard creates a new future intent
[x] confirmed success ends the old intent
[x] semantic payload change with active pending fails closed
[x] explicit discard allows a new operationId
[x] contradictory snake/camel mirrors fail closed
[x] equivalent mirrors are accepted
[x] composition root lifecycle is correct (MainRoot session)
[x] zero direct Firestore write
[x] zero legacy cutover
[x] zero operational canonical UI activation
[x] Health tests green
[x] flutter analyze without Gate 3 error/warning regressions
[x] ZERO Functions / Rules / deploy
```

---

## 38. Pending intent owner lifecycle audit

### Finding

```text
PendingIntentHolder scoped to potentially disposable screen
→ MAJOR
```

### Lifecycle real (evidência de código)

| Evento | HealthV1EntryScreen State | Pending intent se só no Entry |
|--------|---------------------------|--------------------------------|
| Troca aba MainRoot (`IndexedStack`) | **permanece montado** | OK |
| Full-screen push acima do MainRoot | **permanece** (stack) | OK |
| Troca de seção shell (Resumo/Agenda/…) | **permanece** (filho) | OK |
| `ValueKey('health-v1-$dogId')` troca de K9 | **dispose + novo State** | **PERDIA** intent |
| Sem cão ativo / fim de turno (tab mostra Scaffold) | **dispose Entry** | **PERDIA** intent |

Fonte:

```text
main_root_screen.dart → IndexedStack(children: [..., _MainRootHealthTab, ...])
main_root_widgets.dart → HealthV1EntryScreen(key: ValueKey('health-v1-$dogId'))
```

**Conclusão:** holder **somente** no State do Entry **não** bastava para navegação/turno/dog real.

### Owner corrigido

```text
MainRootScreen State
  └── HealthNutritionPendingIntentSession  (lifecycle = app shell)
        └── holderFor(dogId)  → HealthNutritionPendingIntentHolder
              └── injetado em HealthV1EntryScreen(nutritionPendingIntentHolder: ...)
                    └── HealthNutritionMutationController
```

- **Cria/mantém:** `_MainRootScreenState._nutritionPendingSession`
- **Injeta:** `_MainRootHealthTab` → `session.holderFor(dogId)`
- **Não destrói** com dispose do Entry; limpa intent só via `discardIntent` / success

### Comportamentos

| Cenário | Resultado |
|---------|-----------|
| unavailable → dispose Entry → remount mesmo dog | **mesma operationId** |
| pending dog A → comando dog B | holders isolados; **nunca** reutiliza key A |
| pending Supplement → Adhoc sem discard | `pending_intent_incompatible` (sem overwrite) |
| discardIntent → nova intenção | **nova** key |
| success | intent encerrada |

### Holder singular

Uma pending **por dog** (slot único). Multi-intent concorrente no mesmo dog exige discard explícito. Documentado; sem outbox.

### Testes

```text
health_nutrition_pending_intent_session_test.dart
controller: session remount, dog isolation, incompatible block
```

### Finding status

```text
PendingIntentHolder scoped to potentially disposable screen
→ MAJOR
→ CORRIGIDO (owner = MainRoot session keyed by dogId)
```

### BLOCKER / MAJOR abertos

```text
0 / 0
```

---

## 39. Same-kind incompatible intent audit

### Pergunta

Quando já existe:

```text
kind = supplement (ou adhoc / planned)
fingerprint = A
operationId = opA
```

e chega same-kind com `fingerprint = B` — o sistema **substitui** ou **bloqueia**?

### Resposta (código real)

```text
A. bloqueia como pending_intent_incompatible
```

`ensureOperationIdForIntent` — se pending existe e fingerprint ≠ existente:

```dart
throw HealthNutritionMutationValidation(
  ...,
  detailCode: 'pending_intent_incompatible',
);
// holder permanece com opA
// nenhuma opB gerada
```

Aplica-se a:

| Transição | Protegida |
|-----------|-----------|
| supplement → supplement (dose/unit/at) | **sim** |
| adhoc → adhoc (grams/period/fedAt/acceptance) | **sim** |
| planned → planned | **sim** |
| cross-kind (ex.: supplement → adhoc) | **sim** |

### Uncertain vs deterministic

Política **conservadora** neste Gate: qualquer pending no holder + fingerprint incompatível → bloqueio, sem distinção por tipo de erro.

### Explicit discard

```text
discardIntent()
→ limpa holder
→ nova intenção (mesmo kind/payload alterado) → nova operationId
```

### Testes

```text
same-kind supplement uncertain: dose change blocked; opA preserved
same-kind adhoc uncertain: offeredGrams change blocked; opA preserved
same-kind planned uncertain: acceptance change blocked; opA preserved
payload change after error → blocked until discard; then new key
cross-kind block
dog isolation
```

### Finding

```text
Same-kind semantic change can replace uncertain pending intent
→ MAJOR
→ CORRIGIDO
```

### Docs reconciliadas

§16 composition = MainRoot session; §18/20/21 lifecycle sem “payload diferente → nova key” silenciosa; §37/38/39 sem contradição.