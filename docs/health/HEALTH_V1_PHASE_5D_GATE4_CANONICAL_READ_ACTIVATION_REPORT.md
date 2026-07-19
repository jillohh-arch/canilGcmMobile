# Health v1.0 — Fase 5D Gate 4 — Canonical Read Activation Report

| Campo | Valor |
|-------|-------|
| Status | **APROVADO PARA COMMIT** (pós-auditoria query integrity) |
| Data | 2026-07-19 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `b8cd0990e63d8979e706455829b88abd9649c877` |
| Mensagem base | `feat(health): add nutrition mutation client foundation` |
| Escopo | Canonical readers Firestore + Rules RO + read controller + RAW + query integrity |
| Commit / push / deploy | **NÃO** |

```text
Gate 1 = backend mutation foundation
Gate 2 = callables + Admin adapter
Gate 3 = Flutter mutation client foundation
Gate 4 = canonical read activation + Rules RO + RAW  ← este relatório
Gate 5 = deploy Rules, UI Nutrição Hoje, cutover write, produção
```

---

## 1. Executive summary

Gate 4 transforma a read foundation 5C em camada Flutter/Firestore real e testável:

| Entrega | Status |
|---------|--------|
| Firestore canonical plan/meal/supplement readers | OK |
| Parsers 5C reutilizados (fail-closed) | OK |
| Active plan integrity (>1 active → conflict) | OK |
| Legacy read-only delegates | OK |
| CoexistenceNutritionReadSource factory produção | OK |
| HealthNutritionReadController (dog-keyed) | OK |
| Stale/dispose protection | OK |
| Composition root Health v1 | OK |
| Read-after-write → read controller | OK |
| Rules RO local (plans/meals/supplements) | OK |
| nutrition_operations DENY total cliente | OK |
| Rules Emulator Nutrição | 10/10 OK |
| Rules Agenda (regressão) | 9/9 OK |
| Health tests | 1035 passed / 4 skipped |
| Full Flutter tests | 1218 passed / 5 skipped |
| Analyze Gate 4 paths | 0 issues |
| Emulator query integrity | OK (client SDK + fixtures Dart) |
| Deploy / commit / push | ZERO |

**Local preparado ≠ produção ativada.** Rules canônicas **não** foram publicadas.

---

## 2. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD | `b8cd0990e63d8979e706455829b88abd9649c877` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência inicial | 0/0 |
| Working tree inicial | limpo |
| Flutter / Dart | 3.41.6 / 3.11.4 |
| `cloud_firestore` | ^6.2.0 |
| `fake_cloud_firestore` | ^4.1.0+1 |

---

## 3. 5C read foundation audit

Contratos preservados (sem redesenho):

| Símbolo | Arquivo |
|---------|---------|
| `NutritionCanonicalPlanReader` | `coexistence_nutrition_read_source.dart` |
| `NutritionLegacyPlanReader` | idem |
| `NutritionCanonicalMealReader` | idem |
| `NutritionLegacyMealReader` | idem |
| `NutritionCanonicalSupplementLogReader` | idem |
| `NutritionLegacySupplementRegimenReader` | idem |
| `CoexistenceNutritionReadSource` | idem |
| `NutritionCoexistenceSnapshot` | `nutrition_read_models.dart` |
| `NutritionReadStatus` / `NutritionReadResult` | `nutrition_read_state.dart` |
| `NutritionActivePlanIntegrityConflict` | `nutrition_read_models.dart` |
| `NutritionMergePolicy` | `nutrition_merge_policy.dart` |
| Parsers | `nutrition_document_parser.dart` |
| Legacy adapters | `legacy_*` |

Gate 3 mutation client (`HealthNutritionMutationController` + `onRefreshAfterSuccess`) permaneceu intacto; apenas o callback foi ligado no composition root.

---

## 4. Existing Rules audit

Agenda preventiva (fonte de predicado):

```text
match /health_schedule/{scheduleId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

Helpers reutilizados:

- `signedIn()`
- `canAccessDogRecord(dogId)` — global vs `own_records` + assignment/turno
- **Não** se criou segundo modelo (`hasAccessPermission('health','read')` etc.)

Legado nutrition (inalterado):

- `feedings`, `feeding_events`, `nutrition_prescriptions`, `nutritional_prescriptions`, `nutrition_supplements` — permissões existentes **não** ampliadas.

---

## 5. Files changed

### Novos (lib)

- `lib/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart`
- `lib/features/health/data/coexistence/nutrition/firestore_nutrition_legacy_readers.dart`
- `lib/features/health/data/coexistence/nutrition/nutrition_firestore_error.dart`
- `lib/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart`
- `lib/features/health/presentation/nutrition/health_nutrition_read_controller.dart`

### Alterados (lib)

- `lib/features/health/presentation/screens/health_v1_entry_screen.dart` — composition root
- `firestore.rules` — match blocks canônicos
- format-only em `coexistence_nutrition_read_source.dart` / `nutrition_merge_policy.dart` (dart format)

### Testes

- `test/.../firestore_nutrition_canonical_readers_test.dart` (novo)
- `test/.../health_nutrition_read_controller_test.dart` (novo)
- `test/.../health_nutrition_read_after_write_test.dart` (novo)
- format-only em testes Gate 3 existentes

### Rules tests

- `tools/rules_tests/health_nutrition_rules_tests.mjs` (novo)
- `tools/rules_tests/package.json` — script `test:health-nutrition`

### Docs

- este relatório

### Explicitamente **não** alterados

- `functions/**`
- `lib/features/nutrition/**`
- `storage.rules`
- `firestore.indexes.json` (ZERO — sem índice composto novo)

---

## 6. Canonical read paths

| Collection | Path |
|------------|------|
| Plans | `dogs/{dogId}/nutrition_plans/{planId}` |
| Meals | `dogs/{dogId}/meal_logs/{mealId}` |
| Supplement admins | `dogs/{dogId}/supplement_logs/{logId}` |
| Operations (backend-only) | `dogs/{dogId}/nutrition_operations/{receiptId}` |

`nutrition_operations` **não** faz parte do read model do cliente.

---

## 7. NutritionPlan Rules

```text
READ:  signedIn && canAccessDogRecord(dogId)
CREATE/UPDATE/DELETE: DENY
```

Mobile = plan read-only. Write futuro = backend/Web.

---

## 8. MealLog Rules

```text
READ:  signedIn && canAccessDogRecord(dogId)
CREATE/UPDATE/DELETE: DENY
```

Write canônico permanece `healthNutritionCreateMealLog` (Admin SDK).

---

## 9. SupplementLog Rules

```text
READ:  signedIn && canAccessDogRecord(dogId)
CREATE/UPDATE/DELETE: DENY
```

Write permanece callable/Admin.

---

## 10. Nutrition operations protection

```text
match /nutrition_operations/{receiptId} {
  allow read, create, update, delete: if false;
}
```

Mesmo admin autenticado no **cliente** não lê receipts (`operation_id`, fingerprints, results internos).

---

## 11. Rules authorization model

| Aspecto | Decisão |
|---------|----------|
| Auth | `signedIn()` |
| Dog access | `canAccessDogRecord(dogId)` |
| Health module permission extra | **Não** — alinhado à Agenda |
| Own records | Herdado de `canAccessDogRecord` |
| Admin client write | Continua DENY em canônicos |

---

## 12. Rules test matrix

Arquivo: `tools/rules_tests/health_nutrition_rules_tests.mjs`  
Comando: `npm run test:health-nutrition` (em `tools/rules_tests`, com `firebase` no PATH)

| Cenário | Resultado |
|---------|-----------|
| Authorized global read plan/meal/supp | allow |
| Unauth get/list | deny |
| own_records sem dog access | deny |
| own_records com dog access | allow |
| Dog A → Dog B (own_records) | deny |
| create/update/delete nas 3 collections | deny |
| Admin client write canônico | deny |
| nutrition_operations get/list/write (user+admin+anon) | deny |

**10/10 OK.** Agenda: **9/9 OK** (sem regressão).

---

## 13. Canonical plan reader

`FirestoreNutritionCanonicalPlanReader`:

- Collection get (sem `where status==active limit 1`)
- Parser: `NutritionPlanDocumentParser`
- Malformado → `NutritionSourceBatch.error` (não empty)

---

## 14. Active plan integrity

| Active count | Comportamento |
|--------------|---------------|
| 0 | none / legacy fallback (merge 5C) |
| 1 | `NutritionActiveCanonicalPlan` |
| >1 | `NutritionActivePlanIntegrityConflict` |

Sem “latest wins” / `limit(1)` silencioso. Teste FakeFirestore + merge obrigatório.

---

## 15. Canonical meal reader

`FirestoreNutritionCanonicalMealReader` (implementação **final** pós G4-QUERY-INTEGRITY):

```text
collection.get()
→ parse de TODOS os documentos (MealLogDocumentParser)
→ fail-closed no primeiro malformado
→ range por fedAt em memória (from/to opcionais)
→ sort fedAt DESC em memória
```

- **Não** usa `orderBy('fed_at')` server-side (ocultaria docs sem o campo)
- Preserva offered/consumed/acceptance/plan links/occurrence/legacy/revision
- Doc inválido (ex.: sem `fed_at`) → `NutritionSourceBatch.error` (não empty)

---

## 16. Canonical supplement reader

`FirestoreNutritionCanonicalSupplementLogReader` (implementação **final**):

```text
collection.get()
→ parse de TODOS (SupplementLogDocumentParser)
→ fail-closed
→ sort administeredAt DESC em memória
```

- **Não** usa `orderBy('administered_at')` server-side
- **Não** mistura com `LegacySupplementRegimenView`
- Doc sem `administered_at` → integrity error

---

## 17. Legacy read delegates

| Delegate | Collections | Write methods |
|----------|-------------|---------------|
| `FirestoreNutritionLegacyPlanReader` | `nutritional_prescriptions` + `nutrition_prescriptions` | ZERO |
| `FirestoreNutritionLegacyMealReader` | `feeding_events` **ou** `feedings` | ZERO |
| `FirestoreNutritionLegacySupplementRegimenReader` | `nutrition_supplements` | ZERO |

Adapters 5C: `LegacyNutritionPlanAdapter`, `LegacyNutritionAdapter`, `LegacySupplementRegimenAdapter`.  
Não dependem de `NutritionService` write-capable.

---

## 18. Coexistence wiring

`CoexistenceNutritionReadSourceFactory.forFirestore()` monta:

```text
canonical plan + meal + supplement
+ legacy plan dual-collection
+ legacy meals feeding_events + feedings
+ legacy supplement regimens
```

Default Health v1 = Firestore real (**não** Empty/fake silencioso).

---

## 19. Dedupe semantics

Preservado 5C/merge policy:

- `feeding_events` × `feedings` mesmo id → events vence + diagnostic se payload diverge
- Canonical × legacy: **somente** `legacySource + legacyId` inequívocos
- Sem heurística fedAt/gramas/period/dia

---

## 20. Error/degraded/offline semantics

| Situação | Resultado |
|----------|-----------|
| canonical fail + legacy data | degraded |
| canonical data + legacy fail | degraded |
| ambas sem dados, sem falha | empty |
| ambas falham | error ou offline |
| offline detection | `unavailable` / network (padrão Health) |
| catch → [] | **proibido** |

---

## 21. Query design

### Final (pós G4-QUERY-INTEGRITY)

| Reader | Collection | Server filters | Server orderBy | Client after parse | limit | pagination | index |
|--------|------------|----------------|----------------|--------------------|-------|------------|-------|
| Plan | nutrition_plans | — | — | — | — | — | nenhum |
| Meal | meal_logs | — (**scan**) | — | range `from`/`to` em `fedAt`; sort fedAt DESC | — | DEFERRED | nenhum |
| Supplement | supplement_logs | — (**scan**) | — | sort administeredAt DESC | — | DEFERRED | nenhum |
| Legacy plan | nutritional_* | — | — | — | — | — | nenhum |
| Legacy meal | feeding_* | optional fed_at range | fed_at DESC | (legado; fora do MAJOR canônico) | — | — | single-field |
| Legacy regimen | nutrition_supplements | — | — | — | — | — | nenhum |

**Decisão transitória de integridade:** meal/supplement canônicos usam `collection.get()` para que **todo** documento alcance o parser fail-closed. Sort/range só após parse OK. Paginação futura **não** pode reintroduzir invisibilidade pré-parser.

---

## 22. Index requirements

| Query | Índice novo? |
|-------|--------------|
| collection.get() (scan) | Não |
| (legado) orderBy single field | Não (single-field auto) |

**ZERO** alterações em `firestore.indexes.json`.

---

## 23. Nutrition read controller

`HealthNutritionReadController`:

- `selectDog` / `refresh` / `ensureDogAndRefresh`
- Estados via `NutritionReadResult` (loading/data/empty/degraded/offline/error)
- Snapshot + today model
- Sem mutation state

---

## 24. Dog-keyed state

- `_activeDogId` explícito
- Não é ViewModel global de Nutrição
- Troca de dog no entry (se primed) chama `selectDog(next)`

---

## 25. Stale result protection

Generation token (`_generation`) + check `_isCurrent(generation, dogId)`.  
Teste: load A lento + B rápido → A não sobrescreve B.

---

## 26. Composition root

`HealthV1EntryScreen`:

- default: `CoexistenceNutritionReadSourceFactory.forFirestore()`
- `HealthNutritionReadController` owned no entry
- lazy prime (`_nutritionReadPrimed`) — evita I/O até refresh pós-mutation / UI futura
- dispose do read controller no dispose do entry
- injeção `nutritionReadSource` para testes

---

## 27. Read-after-write contract

```dart
onRefreshAfterSuccess: () async {
  _nutritionReadPrimed = true;
  await _nutritionReadController.ensureDogAndRefresh(widget.dogId);
}
```

| Outcome | Significado |
|---------|-------------|
| success + refresh OK | `savedAndRefreshed` |
| success + refresh fail | `savedButRefreshFailed` (registro SALVO) |
| failure | mutação falhou |

Testes: `health_nutrition_read_after_write_test.dart`.

**ZERO** ativação de formulário canônico / `FeedingRegistrationScreen`.

---

## 28. Today timezone semantics

Preservado 5C `loadToday`:

- com plano canônico ativo → `plan.timezone`
- conflito multi-active / sem canônico → `NutritionPlan.defaultTimezone` (`America/Sao_Paulo`, D27)
- **não** device timezone / UTC raw date como default silencioso

Controller expõe `todayResult` via `loadToday(serverNow: clock())`.

---

## 29. Planned slot derivation

Foundation 5C inalterada:

- `NutritionSlotDayDerivation` → pending/completed
- Evidência: MealLog canônico com `planned_meal_id` / occurrence
- Sem persistir status de slot no Firestore
- Logs legados **não** vinculados artificialmente a slots

---

## 30. Canonical visibility integration

Três provas **distintas** (não intercambiáveis):

### Adapter / wiring (FakeFirestore)

```text
FakeFirestore
→ FirestoreNutritionCanonical*Reader (Dart concretos)
→ CoexistenceNutritionReadSource
→ HealthNutritionReadController
```

Valida: scan `collection.get()`, parse, coexistence, controller.

### Query semantics real (Firestore Emulator + Client SDK JS)

```text
Firestore Emulator
→ Client SDK autenticado
→ orderBy(campo) omite doc sem o campo
→ collection.get() inclui o mesmo doc
```

Valida: semântica Firestore real (não FakeFirestore).

### Parser integrity com dados do Emulator

```text
Admin seed no Emulator
→ export fixtures JSON
→ parsers Dart 5C (fail-closed)
```

Valida: documentos reais do Emulator rejeitados/aceitos pelo domínio Dart.

**Não** se afirma que `FirebaseFirestore` (plugin Dart) foi executado E2E contra o Emulator neste ambiente (`channel-error`).

---

## 31. Multiple active plan integrity test

| Evidência | Onde | Resultado |
|-----------|------|-----------|
| FakeFirestore concrete plan reader + merge | unitário Dart | 2 active → `NutritionActivePlanIntegrityConflict` |
| Fixture Emulator (2 plans active exportados) + parsers + merge | `firestore_nutrition_emulator_fixture_test.dart` via orchestrator | conflict **Verde** |

**Não** houve E2E Dart `FirebaseFirestore` plugin → Emulator para multi-active.

---

## 32. Malformed canonical test

Status inválido / offered ausente → batch error → com legacy data → **degraded**, não empty saudável.

---

## 33. Degraded state tests

- canonical fail + legacy meals → degraded
- canonical ok + legacy meal fail → degraded + canônico preservado
- both fail → error (nunca empty)

---

## 34. Rules Emulator validation

```text
cd tools/rules_tests
npm run test:health-nutrition   # 10 OK
npm run test:health-schedule    # 9 OK (regressão Agenda)
```

---

## 35. Client read/write prohibition tests

Client SDK (rules-unit-testing, **não** Admin):

- authorized read plan/meal/supp → allow
- direct create/update/delete → permission-denied
- admin claim client write → permission-denied
- operations get/list/write → permission-denied

---

## 36. Health regression

```text
flutter test test/features/health
→ 1035 passed, 4 skipped
```

---

## 37. Full Flutter regression

```text
flutter test
→ 1218 passed, 5 skipped
```

---

## 38. Analyze

```text
# Paths Gate 4
flutter analyze lib/features/health/data/coexistence/nutrition \
  lib/features/health/presentation/nutrition \
  test/features/health/data/coexistence/nutrition \
  test/features/health/presentation/nutrition
→ No issues found!

# Full repo
flutter analyze
→ 0 novos errors atribuíveis ao Gate 4
→ 0 novos warnings atribuíveis ao Gate 4
→ findings históricos permanecem fora do escopo
  (ex.: unused_element shifts, unused_import testes schedule/summary)
```

**Não** se declara repositório globalmente limpo.

---

## 39. Git diff

```text
git diff --check
→ sem erros de whitespace (apenas warnings CRLF do Git no Windows)
```

Escopo: health + rules + tools/rules_tests + docs.  
`lib/features/nutrition/**` e `functions/**`: **sem alterações**.

---

## 40. Findings

| ID | Classe | Item | Status |
|----|--------|------|--------|
| G4-QUERY-INTEGRITY | MAJOR | Canonical malformed documents can be hidden by orderBy/query predicates before parser | **CORRIGIDO** |
| G4-REAL-READER-EMU | MINOR | Concrete readers initially validated only with FakeFirestore | **CORRIGIDO** (camadas 1–3 da §43) |
| G4-EVIDENCE-RECONCILIATION | MINOR | Relatório superestimava E2E Dart/Firestore Emulator e mantinha queries pré-correção em §15/§16 | **CORRIGIDO** |
| G4-DART-FIRESTORE-EMU | MINOR / DEFERRED | Flutter FirebaseFirestore plugin transport não executado diretamente contra o Emulator (`channel-error` no harness unitário Windows) | **DEFERRED** (não bloqueante) |
| — | BLOCKER aberto | — | **0** |
| — | MAJOR aberto | — | **0** |
| — | MINOR | Format-only em arquivos 5C via `dart format` | ACCEPTED |
| — | DEFERRED | Full collection scan performance / pagination | Gate 5+ |
| — | ACCEPTED LEGACY | dual-write NutritionService; Summary card legado | — |

### G4-DART-FIRESTORE-EMU — cobertura substituta

```text
1. query semantics real no Emulator via client SDK JS
2. Emulator fixtures + Dart parsers 5C fail-closed
3. concrete adapters via FakeFirestore (collection.get)
```

Não bloqueia Gate 4: a falha crítica de query visibility foi demonstrada no Emulator real e a correção coberta pelas demais camadas.

---

## 41. Deferred Gate 5

- Deploy real de Rules canônicas
- Ativação read em produção
- UI final **Nutrição Hoje**
- Planned meal execution UI
- Ad hoc feeding cutover canônico
- Supplement administration UI
- Legacy write retirement
- Migration/backfill inventory
- Production deployment + smoke
- **Paginação** que preserve integrity (schema + migration + visibility de malformados)

---

## 42. Final readiness

```text
[x] concrete canonical readers implementados
[x] 5C parsers reutilizados
[x] multiple active plan fail-closed
[x] canonical malformed docs não viram empty
[x] MealLog sem fed_at → integrity (não invisível)
[x] SupplementLog sem administered_at → integrity
[x] real Firestore Emulator query visibility validado
[x] Emulator fixtures → parsers Dart fail-closed
[x] legacy readers são read-only
[x] canonical × legacy dedupe preserva proveniência
[x] degraded/offline/error preservados

[x] read controller keyed por dogId
[x] stale results protegidos
[x] composition root real preparado
[x] read-after-write callback conectado
[x] mutation success + refresh failure distinguido

[x] Rules read-only implementadas localmente
[x] auth real da Agenda/Health reutilizada
[x] dog access aplicado
[x] direct canonical writes negados
[x] nutrition_operations client read negado
[x] Rules Emulator verde

[x] canonical MealLog visível pelo novo reader
[x] canonical SupplementLog separado de legacy regimen
[x] active plan integrity test verde

[x] legacy operational flow intacto
[x] zero Functions changes
[x] zero deploy

[x] Health tests verdes
[x] full Flutter tests verdes
[x] flutter analyze sem regressão Gate 4
[x] git diff --check OK
```

---

## 43. Canonical query visibility adversarial audit

### Problema encontrado (G4-QUERY-INTEGRITY)

Implementação **inicial** (pré-correção) usava:

```text
meal_logs → orderBy('fed_at', descending: true)
supplement_logs → orderBy('administered_at', descending: true)
```

No **Firestore real / Emulator**, documentos **sem** o campo ordenado **não entram** no resultado. O parser fail-closed nunca os via → malformado virava **invisível**.

FakeFirestore **não** reproduz essa omissão de forma fiel.

### Três provas distintas (G4-EVIDENCE-RECONCILIATION)

| # | Prova | O que demonstra | O que **não** demonstra |
|---|-------|-----------------|-------------------------|
| 1 | Firestore Emulator + Client SDK JS | `orderBy` omite; `collection.get` inclui | adapters Dart / plugin Flutter |
| 2 | Fixtures exportadas do Emulator + parsers Dart 5C | fail-closed sobre docs reais do Emulator | plugin FirebaseFirestore Dart |
| 3 | FakeFirestore + adapters Dart concretos | `collection.get` wiring, parse, coexistence, controller | semântica real de orderBy do Emulator |

**Não afirmar:** “FirebaseFirestore Dart concrete readers foram executados diretamente contra o Emulator”.

### Limitação não bloqueante

```text
G4-DART-FIRESTORE-EMU
MINOR / DEFERRED

Flutter FirebaseFirestore plugin transport
não foi executado diretamente contra o Firestore Emulator
neste Gate (channel-error no harness unitário Windows).

Cobertura substituta: provas 1 + 2 + 3 acima.
```

### Estratégia de correção (código final)

```text
collection.get()
→ parse de TODOS os documentos
→ fail-closed no primeiro malformado
→ sort / range em memória só após parse OK
```

Arquivo: `firestore_nutrition_canonical_readers.dart`. Ver §15 / §16 / §21.

### Comando Emulator

```text
cd tools/rules_tests
npm run test:health-nutrition-readers
```

### Casos cobertos

| Caso | Resultado |
|------|-----------|
| MealLog sem `fed_at` | `missing_fed_at` (error batch) |
| SupplementLog sem `administered_at` | `missing_administered_at` |
| Plan status inválido | integrity error |
| 2 plans `active` | `NutritionActivePlanIntegrityConflict` |
| Meal broken + legacy feeding_events | canonical fail; legacy utilizável → degraded |
| Meal válido + range client | range só após parse; broken ainda falha a collection |

### Custo / performance (DEFERRED)

| Item | Status |
|------|--------|
| Full collection scan meal/supplement | DEFERRED Gate 5+ |
| Paginação com integrity | DEFERRED — não pode reintroduzir invisibilidade pré-parser |
| Dart FirebaseFirestore plugin E2E vs Emulator | DEFERRED (G4-DART-FIRESTORE-EMU) |
| Composite indexes | ZERO agora |

---

## Encerramento

```text
FASE 5D — GATE 4 CANONICAL QUERY INTEGRITY AUDIT CONCLUÍDA.

ZERO BLOCKER.

ZERO MAJOR.

CANONICAL MALFORMED DOCUMENTS NÃO PODEM SER OCULTADOS PELA QUERY.

MEALLOG SEM FED_AT É DETECTADO COMO INTEGRITY FAILURE.

SUPPLEMENTLOG SEM ADMINISTERED_AT É DETECTADO COMO INTEGRITY FAILURE.

FIRESTORE QUERY SEMANTICS VALIDADA NO EMULATOR REAL.

EMULATOR FIXTURES VALIDADAS PELOS PARSERS DART FAIL-CLOSED.

CONCRETE DART READERS VALIDADOS COM FAKEFIRESTORE.

DART FIREBASE PLUGIN E2E CONTRA EMULATOR PERMANECE DEFERRED.

MULTIPLE ACTIVE PLAN FAIL-CLOSED VALIDADO (FAKEFIRESTORE + FIXTURES EMULATOR).

READ-AFTER-WRITE FOUNDATION PRESERVADA.

NUTRITION OPERATIONS CONTINUAM PRIVADAS AO BACKEND.

DIRECT CLIENT WRITES CONTINUAM NEGADOS.

ZERO LEGACY CUTOVER.

ZERO FUNCTIONS ALTERADAS.

ZERO DEPLOY.

GATE 4 APROVADO PARA COMMIT.
```
