# HEALTH v1 — Fase 5D Gate 2 — Callable Wiring Report

**Branch:** `feature/health-v1-foundation`  
**Base HEAD (Gate 1):** `832785fb2c67b6253eab249321a88934480ef8cc`  
**Escopo:** Functions only — callables, Firestore adapter, auth, error mapping, Emulator  
**Data:** 2026-07-19  

---

## 1. Executive summary

Gate 2 expõe a mutation foundation canônica de Nutrição (Gate 1) através de duas Firebase Functions callables reais:

| Callable | Operação |
|----------|----------|
| `healthNutritionCreateMealLog` | Create MealLog `planned` \| `adhoc` (discriminador `mode`) |
| `healthNutritionCreateSupplementLog` | Create SupplementLog |

Implementado:

- transport onCall (`southamerica-east1`, paridade Agenda)
- auth obrigatória + `requireAccessPermission(auth, "health", "create")`
- `requireDogRecordAccess` antes do engine
- actor server-authoritative (`recorded_by.internal_role` admin|condutor)
- Firestore Admin adapter (receipt get + transaction)
- server timestamps em campos de autoridade
- error mapping estável → `HttpsError` + `details.code`
- unit tests + handler integration (fake `request.auth`) + Firestore Emulator adapter tests
- **REAL callable transport E2E**: Auth Emulator + Functions Emulator + Firestore Emulator via `httpsCallable`

**ZERO** Flutter / UI / Rules / production deploy / commit / push.

**Status:** GATE 2 APROVADO PARA COMMIT (ZERO BLOCKER, ZERO MAJOR aberto).

---

## 2. Preflight

| Item | Valor |
|------|-------|
| Branch | `feature/health-v1-foundation` |
| HEAD base | `832785fb2c67b6253eab249321a88934480ef8cc` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência (início) | 0/0 |
| Working tree (início) | limpo |
| Node local | **v24.14.0** |
| Node engines (`functions/package.json`) | **22** |
| firebase-functions | `^6.4.0` |
| firebase-admin | `^13.4.0` |
| firebase-tools | `15.20.0` |

### Node 22

Ambiente de desenvolvimento **não possui Node 22 instalado** (somente Node 24 em `C:\Program Files\nodejs`).  
Validação Emulator/testes executada em **Node v24.14.0**.

Classificação: **MINOR** — não mascarado; não afirmar equivalência de runtime ICU/Intl/DST com Node 22 sem evidência.  
Gate 1 logic DST já cobre política; recomendar CI/Functions runtime 22 em deploy futuro (Gate 3+).

---

## 3. Existing Health callable patterns

Auditoria integral de:

- `healthScheduleCreateManual`
- `healthScheduleUpdateOpen`
- `healthScheduleComplete`
- `healthScheduleCancel`

e helpers em `index.ts` / `health_schedule_callables.ts`.

| Aspecto | Padrão Agenda | Nutrição Gate 2 |
|---------|---------------|-----------------|
| Transport | `onCall({region})` | **igual** |
| Region | `southamerica-east1` | **igual** |
| App Check | sem `enforceAppCheck` | **igual** (dívida) |
| Auth | `requireAccessPermission` | **igual** `health.create` |
| Dog access | `requireDogRecordAccess` | **igual** |
| Actor | `CallerIdentity` → `recordedByPayload` | **igual** (`admin`\|`condutor`) |
| Writes | Admin SDK + transaction | **igual** |
| Receipt | subcollection `operations` | dog-level `nutrition_operations` (Gate 1) |
| Audit | `auditLogs` determinístico | **igual** padrão + id `nu_audit_*` |
| Errors | `HttpsError` + `{code}` | **igual** + `detailCode` engine |
| Injection | `rejectInjection` lista | **igual** + campos nutrição |

Não foi criada convenção paralela.

---

## 4. Files changed

### Novos

| Arquivo | Papel |
|---------|-------|
| `functions/src/health_nutrition_callables.ts` | Handlers + error mapper + transport |
| `functions/src/health_nutrition_firestore_adapter.ts` | Admin Firestore ↔ engine |
| `functions/src/health_nutrition_callables_test.ts` | Unit handlers |
| `functions/src/health_nutrition_firestore_adapter_test.ts` | Adapter unit + emulator |
| `functions/src/health_nutrition_emulator_e2e_test.ts` | E2E Emulator auth real |
| `docs/health/HEALTH_V1_PHASE_5D_GATE2_CALLABLE_WIRING_REPORT.md` | Este relatório |

### Alterados

| Arquivo | Mudança |
|---------|---------|
| `functions/src/index.ts` | deps + exports das 2 callables |
| `functions/src/health_nutrition_engine.ts` | `assertReceiptShape` (malformed ≠ missing) |
| `functions/src/health_nutrition_logic.ts` | forbidden fields extras; `parseInstant` wire robusto |
| `functions/package.json` | scripts test callables / emulator |

### Não alterados (garantia de escopo)

- `lib/**` (Flutter)
- `firestore.rules`
- `firestore.indexes.json`
- `storage.rules`

---

## 5. Callable exports

Entry: `functions/src/index.ts`

```text
export const healthNutritionCreateMealLog
export const healthNutritionCreateSupplementLog
```

- Region: `southamerica-east1`
- Options: `{region}` apenas (sem `enforceAppCheck`)
- Helpers internos **não** exportados

---

## 6. Transport contracts

### MealLog — discriminador obrigatório

```text
mode: "planned" | "adhoc"
```

Não se infere planned/adhoc por presença acidental de campos.

### Planned (payload permitido)

```text
mode, dog_id, plan_id, planned_meal_id,
offered_grams, consumed_grams?, acceptance, fed_at,
observations?, attachment_refs?, operation_id
```

### Planned (rejeitado explicitamente)

```text
period, scheduled_for, meal_occurrence_id, local_service_date,
prescription_amount_at_time, recorded_by, recorded_at, revision,
schema_version, create_fingerprint, entity_semantic_fingerprint, receipt_id
```

### Ad hoc (permitido)

```text
mode="adhoc", dog_id, period,
offered_grams, consumed_grams?, acceptance, fed_at,
observations?, attachment_refs?, operation_id
```

### Ad hoc (rejeitado)

```text
plan_id, planned_meal_id, meal_occurrence_id, scheduled_for,
prescription_amount_at_time
```

### Supplement (permitido)

```text
dog_id, supplement_name, dose (number > 0), unit, administered_at,
nutrition_plan_id?, supplement_regimen_id?,
notes?, batch_number?, protocol_id?, operation_id
```

### Supplement (rejeitado)

```text
recorded_by, recorded_at, revision, schema_version, receipt_id
dose string → validation
```

### Date wire

Preferência e implementação:

1. **ISO-8601 string** (UTC recomendado) — contrato principal  
2. Firestore Timestamp-like (`toDate` / `seconds`) — paridade Agenda  
3. epoch millis numérico  

Rejeita: Invalid Date, NaN, objeto arbitrário sem semântica temporal, valor futuro (`assertNotFuture` no engine).

---

## 7. Unknown/server-authoritative fields

| Classe | Política |
|--------|----------|
| Server-authoritative / injection list | **Rejeitar explicitamente** (`invalid-argument`) |
| Campos desconhecidos genéricos | **Aceitos e ignorados** (paridade Agenda — não inventar strict-unknown) |

Decisão documentada: não endurecer unknown genérico só em Nutrição.

---

## 8. Authentication

```text
request.auth != null
```

via `requireHealthCreate` → `requireAccessPermission(auth, "health", "create")` → `requireAuth`.

Sem auth → `HttpsError("unauthenticated", ...)`.

UID do payload **nunca** é autoridade.

---

## 9. Permission enforcement

Helper real (evidência em `index.ts`):

```text
requireAccessPermission(auth, "health", "create")
```

**Não** introduzido `health.record_routine` nesta rodada.

Documentação granular futura permanece em Gate 3+.

---

## 10. Dog access

```text
requireDogRecordAccess(auth, caller, dogId, dog)
```

após load do documento `dogs/{dogId}`.

Ordem:

```text
1. auth
2. health.create
3. dog access
4. actor resolution
5. engine (receipt-first interno)
```

Usuário sem acesso **não** obtém replay histórico só com `operation_id`.

---

## 11. Actor resolution

Mesmo contrato da Agenda:

```text
uid, email, ra, name  ← token + users
recorded_by.internal_role ← isAdministrativeAuthority → "admin" | "condutor"
```

Cliente **não** fornece actor / recorded_by / role.

---

## 12. Firestore adapter

Arquivo: `health_nutrition_firestore_adapter.ts`

| Capacidade | Implementação |
|------------|---------------|
| read durable receipt | `getDoc` path `dogs/{dogId}/nutrition_operations/{receiptId}` |
| run transaction | `db.runTransaction` |
| tx.get | Admin `transaction.get` |
| tx.set | Admin `transaction.set` + path guard + server timestamps |

**Não** é repository genérico global.

---

## 13. Transaction semantics

Preservado do Gate 1:

```text
recheck receipt
→ tx.get(plan) quando operação nova exige
→ validate snapshot / eligibility / slot
→ derive occurrence
→ read entity
→ create | semantic no-op | conflict
→ write entity + receipt + audit (create real only)
```

Plan **não** é autoridade fora da transaction.

Prova Emulator: `emulator: plan authority is transactional get` (cancel mid-flight → reject).

---

## 14. Receipt registry

Path canônico:

```text
dogs/{dogId}/nutrition_operations/{receiptId}
receiptId = nr1_{hash(actorUid|operationType|operationId)}
```

- Lookup externo receipt-first **após** auth/permission/dog/actor  
- Recheck obrigatório **dentro** da transaction  
- Malformado → `integrity` / `receipt_integrity` (**≠ missing**)

---

## 15. Firestore timestamp authority

| Campo | Persistência |
|-------|----------------|
| `recorded_at`, `processed_at`, `performed_at`, `createdAt` | `FieldValue.serverTimestamp()` via `prepareWriteData` |
| `fed_at`, `administered_at`, `scheduled_for` | fatos cliente/derivados → `Timestamp` Firestore |
| Response DTO | **não** depende de materializar sentinel (revision/entity id síncronos) |

Engine continua testável com ISO em memória; adapter reescreve na borda Admin.

---

## 16. Canonical document decoding

| Doc | Política |
|------|----------|
| Receipt | required fields; fail-closed integrity |
| MealLog existente | exige fingerprint/semântica recuperável; senão integrity |
| NutritionPlan | `parsePlanFromDoc` fail-closed (`nutrition_plan_integrity`) |
| Timestamps Firestore | convertidos para ISO plain no engine boundary |

---

## 17. Audit integration

Path: `auditLogs/{nu_audit_*}` (id determinístico do engine).

| Resultado | Audits novos |
|-----------|--------------|
| Create real | 1 |
| Replay | 0 |
| Semantic no-op | 0 (receipt novo; sem audit de create) |
| Conflict / idempotency | 0 sucesso |

Audit na **mesma transaction** do create.

---

## 18. Error mapping

`mapNutritionError` em `health_nutrition_callables.ts`:

| appCode | HTTP | notes |
|---------|------|-------|
| validation | invalid-argument | |
| unauthenticated | unauthenticated | |
| permission-denied | permission-denied | |
| not-found | not-found | |
| conflict / integrity / failed-precondition | failed-precondition | paridade Agenda |
| idempotency-conflict | failed-precondition | `details.code=idempotency_conflict` |
| default | internal | sem stack / internals |

`details.code` estáveis preservados (`detailCode` do engine):

```text
validation, nutrition_plan_not_found, nutrition_plan_cancelled,
nutrition_plan_not_effective_at_fed_at, nutrition_plan_integrity,
planned_meal_not_found, meal_occurrence_conflict, idempotency_conflict,
supplement_regimen_requires_plan, supplement_regimen_not_found,
receipt_integrity
```

---

## 19. Response contracts

### MealLog

```json
{
  "dog_id": "...",
  "meal_id": "...",
  "revision": 1,
  "was_no_op": false,
  "meal_occurrence_id": "mo1_... | null",
  "dogId": "...",
  "mealId": "...",
  "wasNoOp": false,
  "mealOccurrenceId": "..."
}
```

Snake_case = contrato Gate 2; camelCase = espelho Agenda.

### SupplementLog

```json
{
  "dog_id": "...",
  "supplement_log_id": "sl1_...",
  "revision": 1,
  "was_no_op": false
}
```

Replay / semantic no-op: `was_no_op = true`, mesmo entity id / revision.

---

## 20. App Check

Agenda Health callables: **sem** `enforceAppCheck: true`.

Nutrição: **paridade** — enforcement off.

Classificação: **ACCEPTED HARDENING DEBT**.

E2E: callable operável no Emulator sem App Check token.

---

## 21. Region

```text
southamerica-east1
```

Confirmado igual a `healthSchedule*`.

---

## 22. Zero legacy write proof

Defesa em camadas:

1. Engine `safeSet` / `assertCanonicalPath` (Gate 1)  
2. Adapter `assertCanonicalWritePath` proíbe  
   `feeding_events`, `feedings`, `nutritional_prescriptions`,  
   `nutrition_prescriptions`, `nutrition_supplements`  
3. E2E conta 0 docs nessas collections após creates  

Writes canônicos apenas:

```text
dogs/{dogId}/meal_logs/{id}
dogs/{dogId}/supplement_logs/{id}
dogs/{dogId}/nutrition_operations/{id}
auditLogs/{id}
```

Admin SDK → Rules **não** são autoridade do write canônico.  
**Nenhuma** abertura de Rules neste Gate.

---

## 23. Unit tests

### `health_nutrition_callables_test.ts`

- unauthenticated  
- permission denied  
- dog access denied  
- planned / adhoc / supplement success  
- malformed mode  
- server-authoritative injection  
- engine validation / conflict / idempotency mapping  
- auth order (zero writes se dog deny)  
- replay no second audit  

### `health_nutrition_firestore_adapter_test.ts` (sem emulator)

- serverTimestamp prepare  
- receipt decode valid/malformed  
- meal decode  

### Gate 1 (regressão)

- logic + engine — **todos verdes**

---

## 24. Emulator setup

### 24.1 Handler integration (in-process) — complementar

```text
Camada: runHealthNutritionCreate* + adapter Admin
Projeto: canil-gcm (somente local)
FIRESTORE_EMULATOR_HOST: 127.0.0.1:8080
Auth: request.auth fabricado no teste + access_profiles no Firestore Emulator
NÃO é prova de transporte onCall
```

```bash
cd functions
npx firebase emulators:exec --project canil-gcm --only firestore \
  "node lib/health_nutrition_emulator_e2e_test.js"
npx firebase emulators:exec --project canil-gcm --only firestore \
  "node lib/health_nutrition_firestore_adapter_test.js"
```

### 24.2 REAL callable transport E2E — prova Gate 2

```text
Camada: httpsCallable (Firebase JS client SDK)
Auth Emulator → ID token JWT real
Functions Emulator → onCall southamerica-east1
Firestore Emulator → persistência Admin SDK
request.auth materializado pelo runtime callable (não fabricado)
```

```bash
npx firebase emulators:exec --project canil-gcm --config firebase.json \
  --only auth,firestore,functions \
  "node tools/rules_tests/health_nutrition_callables_emulator_tests.mjs"
```

Script npm: `test:health-nutrition-callable-transport` (em `functions/package.json`)  
Harness: `tools/rules_tests/health_nutrition_callables_emulator_tests.mjs`

Hosts confirmados:

```text
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
FUNCTIONS_BASE_URL=http://127.0.0.1:5001/canil-gcm/southamerica-east1
GCLOUD_PROJECT=canil-gcm
```

Logs Functions Emulator:

```text
verifications: app=MISSING, auth=VALID   (token Auth Emulator real)
verifications: app=MISSING, auth=MISSING (sem token → unauthenticated)
Loaded: healthNutritionCreateMealLog, healthNutritionCreateSupplementLog
```

---

## 25. Emulator authorization tests

### Handler integration (in-process)

| Caso | Resultado |
|------|-----------|
| unauthenticated | `unauthenticated` |
| auth sem `health.create` | `permission-denied` |
| auth com create + `own_records` sem dog | `permission-denied` |
| auth autorizado | success |

Auth: `request.auth` fabricado. NÃO chamar de "Auth real".

### REAL callable transport (Auth + Functions Emulator)

| Caso | Resultado wire |
|------|----------------|
| sem token | `functions/unauthenticated` |
| user Auth Emulator sem health.create | `functions/permission-denied` + 0 writes |
| user com create + own_records sem dog | `functions/permission-denied` + 0 writes |
| user autorizado (ID token real) | success |

Token: `adminAuth.createUser` + `signInWithEmailAndPassword` → `getIdToken(true)` → `httpsCallable`.

---

## 26. Planned meal E2E

- Seed dog + plan active + slot  
- Invoke `runHealthNutritionCreateMealLog` mode planned  
- Confirmed: 1 meal_logs, ≥1 nutrition_operations, 1 audit, 0 legacy  
- `meal_id === meal_occurrence_id` (`mo1_*`)

---

## 27. Replay E2E

- Mesmo ator + operation_id + payload  
- `was_no_op = true`, mesmo meal_id  
- 1 MealLog, 1 audit  

---

## 28. Durable replay E2E

1. create success  
2. plan → `cancelled` no Emulator  
3. mesma operation  

→ replay success; 0 novo audit de create; 0 novo MealLog.

Prova: wiring preserva receipt-first (não revalida plano no replay).

---

## 29. Idempotency conflict E2E

Mesmo ator + operation_id + payload diferente → `failed-precondition` / idempotency.  
0 segundo MealLog para a intenção divergente.

---

## 30. Semantic no-op E2E

operation_id A e B, mesma materialização:

- 1 MealLog  
- 2 durable receipts  
- 1 audit  
- B: `was_no_op = true`

---

## 31. Occurrence conflict E2E

Mesma occurrence, payload semanticamente incompatível:

- `details.code = meal_occurrence_conflict`  
- sem overwrite  

---

## 32. Ad hoc E2E

- `ml1_*`  
- plan_id / planned_meal_id / meal_occurrence_id / scheduled_for = null  

---

## 33. Supplement E2E

| Caso | Resultado |
|------|-----------|
| sem plan | create `sl1_*` |
| regimen sem plan | validation / `supplement_regimen_requires_plan` |
| regimen inexistente | not-found / `supplement_regimen_not_found` |
| plan + regimen válidos | create |

---

## 34. Node 22 validation

| Item | Status |
|------|--------|
| engines.node package | 22 |
| Node local execução | **24.14.0** |
| Node 22 instalado | **não** |
| Emulator sob Node 22 | **não executado** |
| DST unit tests (logic) | verdes em Node 24 |

**MINOR:** ausência Node 22 local. Runtime de produção Functions continua declarado 22.

---

## 35. Tests and build

Comandos executados:

```bash
cd functions
npm run build                    # verde
npm run test:health-nutrition    # verde (logic+engine+callables+adapter unit)
npm run test:health-schedule     # verde
npm test                         # verde

# Handler integration / adapter (Firestore Emulator only)
npx firebase emulators:exec --project canil-gcm --only firestore \
  "node lib/health_nutrition_emulator_e2e_test.js"   # verde
npx firebase emulators:exec --project canil-gcm --only firestore \
  "node lib/health_nutrition_firestore_adapter_test.js"  # verde

# REAL callable transport (Auth + Firestore + Functions)
npx firebase emulators:exec --project canil-gcm --config ../firebase.json \
  --only auth,firestore,functions \
  "node ../tools/rules_tests/health_nutrition_callables_emulator_tests.mjs"  # verde

git diff --check                 # OK
```

---

## 36. Git diff

```text
Modified:
  functions/package.json
  functions/src/health_nutrition_engine.ts
  functions/src/health_nutrition_logic.ts
  functions/src/index.ts
  tools/rules_tests/package.json

Untracked:
  functions/src/health_nutrition_callables.ts
  functions/src/health_nutrition_callables_test.ts
  functions/src/health_nutrition_emulator_e2e_test.ts
  functions/src/health_nutrition_firestore_adapter.ts
  functions/src/health_nutrition_firestore_adapter_test.ts
  tools/rules_tests/health_nutrition_callables_emulator_tests.mjs
  docs/health/HEALTH_V1_PHASE_5D_GATE2_CALLABLE_WIRING_REPORT.md
```

**Nenhum commit. Nenhum push. Nenhum deploy.**

---

## 37. Findings

| ID | Severidade | Descrição | Status |
|----|------------|-----------|--------|
| G2-FN-EMU | **MAJOR** (reclassificado) | Callable transport E2E não validado — só handler in-process | **CORRIGIDO** — ver §40 |
| G2-N22 | MINOR | Functions engines=Node 22; test runtime local=Node 24 | Aberto (não bloqueia Gate 2) |
| G2-AC | ACCEPTED HARDENING DEBT | App Check não enforced (paridade Agenda; `app=MISSING` nos logs) | Documentado |
| — | BLOCKER aberto | — | **0** |
| — | MAJOR aberto | — | **0** |

---

## 38. Deferred Gate 3

```text
Flutter mutation gateway
mobile controller
UI registration cutover
Rules cleanup dos writers legados
legacy dual-write retirement
production deployment
production smoke
App Check enforcement (módulo Health)
CI Node 22 parity job
```

---

## 39. Final readiness

```text
[x] callables exportadas
[x] auth obrigatória
[x] health.create aplicado
[x] dog access aplicado
[x] actor server-authoritative
[x] Firestore adapter usa Admin SDK
[x] durable replay receipt-first preservado
[x] plan authority continua transacional
[x] canonical decoders fail-closed
[x] server timestamps persistidos
[x] error mapping estável
[x] App Check policy documentada
[x] zero Rules alteradas
[x] zero Flutter alterado
[x] zero legacy write
[x] Auth Emulator realmente utilizado
[x] ID token real do Auth Emulator atravessa a callable
[x] Functions Emulator realmente utilizado
[x] endpoint onCall real invocado (httpsCallable)
[x] unauthenticated validado no transporte real
[x] permission denied validado no transporte real
[x] dog access denied validado no transporte real
[x] planned meal happy path atravessa callable real
[x] replay atravessa callable real
[x] durable replay atravessa callable real
[x] HttpsError code/details atravessam serialização real
[x] SupplementLog atravessa callable real
[x] Node 22 validado quando possível (NÃO — MINOR documentado)
[x] testes Functions verdes
[x] build verde
[x] git diff --check OK
[x] zero produção
```

### FASE 5D — GATE 2 APROVADO PARA COMMIT

---

## 40. Final callable transport audit

### Reclassificação

| Finding | Antes | Depois | Status |
|---------|-------|--------|--------|
| G2-FN-EMU | ACCEPTED HARDENING DEBT | **MAJOR — CALLABLE TRANSPORT E2E NÃO VALIDADO** | **CORRIGIDO** nesta auditoria |

Motivo da reclassificação: Gate 2 existe para provar exposição real

```text
Firebase callable transport + Auth + permission + dog access + handler + Admin Firestore
```

Handler in-process **não** substitui essa prova.

### Distinção de camadas de teste

| Camada | Arquivo | Auth | Invocação |
|--------|---------|------|-----------|
| Unit handlers | `health_nutrition_callables_test.ts` | `request.auth` fabricado | `runHealthNutritionCreate*` |
| Handler integration + FS Emulator | `health_nutrition_emulator_e2e_test.ts` | `request.auth` fabricado | `runHealthNutritionCreate*` |
| Adapter Emulator | `health_nutrition_firestore_adapter_test.ts` | n/a | engine + Admin adapter |
| **REAL callable transport** | `health_nutrition_callables_emulator_tests.mjs` | **Auth Emulator ID token** | **`httpsCallable` → Functions Emulator** |

### Auth Emulator

- Usuários criados via Admin Auth Emulator (`createUser` + password)
- Login: `signInWithEmailAndPassword`
- Token: `user.getIdToken(true)` — JWT real (3 segmentos; length ~481)
- Seed Firestore: `users`, `access_profiles`, `dogs`, `nutrition_plans`

### Functions Emulator

- Emulators: `auth,firestore,functions`
- Região: `southamerica-east1`
- Base URL: `http://127.0.0.1:5001/canil-gcm/southamerica-east1`
- Exports carregados e HTTP inicializados:

```text
healthNutritionCreateMealLog
healthNutritionCreateSupplementLog
```

### Método de chamada

```text
Firebase JS client SDK
  connectAuthEmulator / connectFirestoreEmulator / connectFunctionsEmulator
  httpsCallable(functions, name)(payload)
```

**Não** invoca `runHealthNutritionCreateMealLog` / `runHealthNutritionCreateSupplementLog` neste harness.

### Matriz auth/access (transporte real) — todos PASS

| Caso | Wire |
|------|------|
| sem token | `functions/unauthenticated` |
| token sem health.create | `functions/permission-denied` + 0 writes |
| token com create sem dog access | `functions/permission-denied` + 0 writes |
| autorizado planned happy path | `meal_id`, `revision=1`, `was_no_op=false`, `meal_occurrence_id` |
| replay same token/op/payload | mesmo `meal_id`, `was_no_op=true`, 1 audit |
| durable replay (plano cancelled) | replay success |
| idempotency_conflict | `functions/failed-precondition` + `details.code=idempotency_conflict` |
| meal_occurrence_conflict | `functions/failed-precondition` + `details.code=meal_occurrence_conflict` |
| fed_at inválido | `functions/invalid-argument` |
| SupplementLog | `supplement_log_id` + persistência canônica |
| App Check ausente | operável (`app=MISSING` nos logs) |

### HttpsError wire serialization (evidência real)

```json
{
  "code": "functions/failed-precondition",
  "detailsCode": "idempotency_conflict",
  "details": { "code": "idempotency_conflict" },
  "message": "Mesma operationId (mesmo ator/tipo) com intenção diferente."
}
```

```json
{
  "code": "functions/failed-precondition",
  "detailsCode": "meal_occurrence_conflict",
  "details": { "code": "meal_occurrence_conflict" }
}
```

Logs callable verification:

```text
auth=VALID (token Auth Emulator)
auth=MISSING (unauthenticated)
app=MISSING (enforcement off — ACCEPTED HARDENING DEBT)
```

### Zero produção

```text
emulators:exec only
GCLOUD_PROJECT=canil-gcm (local)
Nenhum firebase deploy / gcloud deploy
Nenhuma credencial de produção no path de teste
```

### Functions Emulator logs relevantes

- Sem unhandled exception nas callables de nutrição
- Sem serialization failure nos happy paths / erros esperados
- Node host warning: engines 22 vs host 24 (MINOR G2-N22)
- Warning genérico de emulators não iniciados (apphosting/storage/etc.) — irrelevante

### Resultado

```text
failures=0
REAL_CALLABLE_TRANSPORT_E2E: OK
BLOCKER aberto: 0
MAJOR aberto: 0
```
