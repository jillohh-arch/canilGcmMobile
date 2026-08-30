# Health v1.0 — Fase 5D Gate 5A — Production Read-Only Activation Report

| Campo | Valor |
|-------|-------|
| Status | **CONCLUÍDO, DEPLOYADO, DOCUMENTADO E SINCRONIZADO** |
| Data | 2026-07-19 |
| Branch | `feature/health-v1-foundation` |
| HEAD (durante deploy) | `a93378df6feceb166f6496e45e1c2ef514588ba2` |
| Commit funcional Gate 4 | `cb2e21f07f30109720c0575dc2caab6aa85c7d67` |
| Tracking | `origin/feature/health-v1-foundation` |
| Deploy | **Firestore Rules somente** (concluído) |
| Ruleset production before | `791368c0-58b7-4f47-8a3e-674ab164696e` |
| Ruleset production after | `4340c2f6-ba11-4eea-9d0b-9b213124b6c4` |
| Project | `canil-gcm` |

```text
Gate 4 = canonical readers + Rules locais + Emulator
Gate 5A = production READ-ONLY Rules activation  ← este relatório
Gate 5B = Nutrição Hoje UI / prime de read controller / client Auth smoke
```

---

## 0. Evidence model (reconciliação)

Três fatos **distintos** e não intercambiáveis:

```text
1. Firestore Rules foram realmente publicadas em produção
   (firebase deploy --only firestore:rules → ruleset 4340c2f6-…).

2. O ruleset publicado foi validado pela Rules API Simulator
   (projects/.../rulesets/{id}:test com auth simulado).

3. Não houve Firebase Auth ID token real do aplicativo
   disponível para executar um client read autenticado real
   (FirebaseFirestore + Auth de produção).
```

Portanto:

```text
CANONICAL READ AUTHORIZATION VALIDADA
CONTRA O RULESET PUBLICADO VIA RULES API SIMULATOR.
```

**Não** equivale a:

```text
Firebase client smoke autenticado real no app
```

Esse transporte (`app → Firebase Auth → Firestore`) fica **deferred Gate 5B**.

---

## 1. Executive summary

Rules de leitura canônica de Nutrição **publicadas em produção** no projeto `canil-gcm`.

| Resultado | Status |
|-----------|--------|
| Production drift audit | APROVADO (delta = comentários Agenda + blocks Nutrição) |
| Deploy `firestore:rules` only | OK |
| Post-deploy rules ≡ local | OK (`matchesLocal: true`) |
| Canonical read authz (Rules simulator no ruleset publicado) | ALLOW |
| `nutrition_operations` (simulator) | DENY |
| Direct client writes (simulator only) | DENY |
| Agenda predicado + simulator get | ALLOW |
| Production data writes | **ZERO** |
| Functions / indexes / Storage deploy | **ZERO** |
| Legacy cutover | **ZERO** |
| Rollback snapshot | **preservado fora do repositório** |

**Read activation ≠ write activation.** UI canônica de registro e callables de mutação em produção **não** fazem parte deste Gate.

---

## 2. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD | `a93378df6feceb166f6496e45e1c2ef514588ba2` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência | 0/0 |
| Working tree (antes da execução) | limpo |

---

## 3. Housekeeping

Removido do worktree (não versionado):

```text
temp/g4_nutrition_emulator_fixtures.json
```

Após o deploy e a preservação externa do rollback:

```text
temp/gate5a/  → removido do worktree
```

Snapshots de produção **não** são versionados no Git.

---

## 4. Firebase project verification

| Fonte | Project ID |
|-------|------------|
| `.firebaserc` default | `canil-gcm` |
| `firebase use` / CLI current | `canil-gcm (current)` |
| `android/app/google-services.json` | `canil-gcm` |
| `firebase.json` rules file | `firestore.rules` |
| Deploy target | `canil-gcm` |

CLI Firebase Tools: **15.20.0**.

---

## 5. Production rules snapshot

Captura **antes** do deploy via Firebase Rules API.

| Campo | Valor |
|-------|--------|
| Timestamp | `2026-07-19T16:48:26.527Z` |
| Project | `canil-gcm` |
| Release | `projects/canil-gcm/releases/cloud.firestore` |
| Ruleset (before) | `projects/canil-gcm/rulesets/791368c0-58b7-4f47-8a3e-674ab164696e` |
| updateTime (before) | `2026-07-17T13:48:28.916576Z` |
| SHA-256 (before) | `da8357bd8c2a96757d44ff17aa4c7b4dc437e305980d192e84fb6fe2f2d582a0` |
| Bytes (before) | 72909 |

Preservação **externa ao repositório** (confirmada íntegra):

```text
C:\Projetos\canil_gcm_mobile_chatgpt\_ops_gate5a_rollback\
  production_rules_before_2026-07-19T16-48-26-525Z.rules
  production_rules_before_meta.json
```

SHA revalidado na cópia externa: **match** com `da8357bd…`.

Conteúdo before:

| Marker | Presente? |
|--------|-----------|
| `health_schedule` | sim |
| `nutrition_plans` | **não** |
| `meal_logs` | **não** |
| `supplement_logs` | **não** |
| `nutrition_operations` | **não** |

---

## 6. Production drift audit

Comparação normalizada (LF):

```text
production published (before)
VS
firestore.rules (branch HEAD)
```

| Diff | Interpretação |
|------|----------------|
| Comentários de `health_schedule` atualizados | Cosmético; predicado **inalterado** |
| Adição `nutrition_plans` / `meal_logs` / `supplement_logs` RO | **Esperado Gate 5A** |
| Adição `nutrition_operations` DENY total | **Esperado Gate 5A** |
| Outros módulos | **Nenhuma** remoção/alteração inesperada |

```text
O deploy local NÃO substituiria regras de produção
que não existem nesta branch.
```

**Sem BLOCKER de drift.**

---

## 7. Pre-deploy test matrix

```text
cd tools/rules_tests
npm run test:health-nutrition   → 10/10 OK
npm run test:health-schedule    → 9/9 OK
npm run test:health-nutrition-readers → ALL OK
```

---

## 8. Exact deploy scope

```text
firebase deploy --only firestore:rules --project canil-gcm --non-interactive
```

| Incluído | Excluído |
|----------|----------|
| Firestore Rules | Functions |
| | Firestore indexes |
| | Storage Rules |
| | Hosting / outros |

Contrato local publicado:

```text
nutrition_plans / meal_logs / supplement_logs:
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;

nutrition_operations:
  allow read, create, update, delete: if false;
```

---

## 9. Rules deploy

| Campo | Valor |
|-------|--------|
| Início | `2026-07-19T13:50:28-03:00` |
| Fim | `2026-07-19T13:50:40-03:00` |
| Duração | ~12 s |
| Project | `canil-gcm` |
| Resultado | **Deploy complete** |
| Ruleset after | `4340c2f6-ba11-4eea-9d0b-9b213124b6c4` |

---

## 10. Post-deploy verification

| Campo | Valor |
|-------|--------|
| Ruleset (after) | `projects/canil-gcm/rulesets/4340c2f6-ba11-4eea-9d0b-9b213124b6c4` |
| updateTime (after) | `2026-07-19T16:52:38.795749Z` |
| SHA-256 (after) | `bbfced6a937e709a0d40edd3ad07bb35f5ac9ae741e5ddb44354f0ec6138fbc4` |
| matchesLocal | **true** |
| nutrition_* markers | **presentes** |

Cópia after também preservada externamente em `_ops_gate5a_rollback/` (não versionada).

---

## 11. Authorized canonical read authorization

### O que foi feito

- **Rules API Simulator** contra o ruleset **efetivamente publicado** (`4340c2f6-…`).
- Auth simulado: `{ ra: '691755' }` (escopo global).
- K9 de referência (descoberta Admin/IAM, sem escrita): `4DDeRe7CCjTte6nbUbrC` (Bono).

| Caso | Expectativa | Resultado |
|------|-------------|-----------|
| get `nutrition_plans/{doc}` | ALLOW | PASS |
| get `meal_logs/{doc}` | ALLOW | PASS |
| get `supplement_logs/{doc}` | ALLOW | PASS |

### O que **não** foi feito

```text
Firebase Auth ID token real do aplicativo: AUSENTE
FirebaseFirestore client read autenticado real em produção: NÃO EXECUTADO
```

### Descoberta Admin/IAM (inventário; **não** prova Rules)

| Collection | Docs (page) |
|------------|-------------|
| nutrition_plans / meal_logs / supplement_logs | 0 (vazias) |
| feeding_events (legado) | ≥3 |

Canônicos vazios + legado presente → coexistence em **legacy fallback** quando o app ler (Gate 4).

### HTTP sem credencial

```text
GET .../nutrition_plans (sem Authorization) → HTTP 403
```

---

## 12. Nutrition operations deny

| Caso | Expectativa | Resultado |
|------|-------------|-----------|
| get `nutrition_operations/{receipt}` (simulator) | DENY | PASS |
| list `nutrition_operations` (simulator) | DENY | PASS |

Nenhuma escrita em produção.

---

## 13. Unauthorized dog read

| Caso | Expectativa | Resultado |
|------|-------------|-----------|
| get meal_logs com `own_records` + RA sem assignment (simulator) | DENY | PASS |

Identidade real `own_records` de produção **não** usada. Emulator Gate 4 permanece prova complementar.

---

## 14. Agenda Preventiva — regressão de Rules

**Formulação fiel:**

```text
NENHUMA REGRESSÃO DE RULES DETECTADA NA AGENDA PREVENTIVA.

AGENDA PREVENTIVA MANTEVE O PREDICADO PUBLICADO
E PASSOU NA VALIDAÇÃO DO RULESET.
```

Evidências:

| Evidência | Resultado |
|-----------|-----------|
| Drift audit: predicado `health_schedule` inalterado | OK |
| Rules simulator get `health_schedule` ALLOW | PASS |
| Rules Emulator pré-deploy | 9/9 |
| Admin discovery (inventário) | HTTP 200, docs existentes |

Sem mutation. **Não** se afirma smoke completo do aplicativo real da Agenda.

---

## 15. Health existente — regressão de Rules

**Formulação fiel:**

```text
NENHUMA REGRESSÃO DE RULES DETECTADA NO HEALTH EXISTENTE.
```

Evidências:

| Evidência | Resultado |
|-----------|-----------|
| Drift audit: nenhum match block inesperado removido/alterado | OK |
| Predicado compartilhado `canAccessDogRecord` | preservado |
| Agenda simulator ALLOW | PASS |
| Rules Emulator Nutrition + Agenda | 10/10 + 9/9 |

**Não** se afirma regressão zero em todas as telas do app (sem client Auth smoke).

---

## 16. Zero production data writes

```text
ZERO create/update/delete em documentos de produção.
```

Write DENY no simulator (create/update/delete) + Emulator Gate 4. Sem tentativa de escrita real.

---

## 17. Zero Functions / indexes / Storage deploy

```text
comando: firebase deploy --only firestore:rules
```

| Recurso | Deployed? |
|---------|-----------|
| Functions | **NÃO** |
| Indexes | **NÃO** |
| Storage | **NÃO** |
| Hosting | **NÃO** |

---

## 18. Rollback readiness

| Item | Valor |
|------|--------|
| Rollback artifact | **preservado externamente ao repositório** |
| Path externo | `C:\Projetos\canil_gcm_mobile_chatgpt\_ops_gate5a_rollback\` |
| Previous production ruleset ID | `791368c0-58b7-4f47-8a3e-674ab164696e` |
| SHA-256 pré-deploy | `da8357bd8c2a96757d44ff17aa4c7b4dc437e305980d192e84fb6fe2f2d582a0` |
| Current production ruleset ID | `4340c2f6-ba11-4eea-9d0b-9b213124b6c4` |
| Procedimento | restaurar **somente** Firestore Rules; não tocar Functions/indexes/dados |
| Credenciais no relatório | **nenhuma** |

**Rollback não necessário nesta execução.**

---

## 19. Findings

| ID | Classe | Item | Status |
|----|--------|------|--------|
| — | BLOCKER aberto | — | **0** |
| — | MAJOR aberto | — | **0** |
| G5A-EVIDENCE-WORDING | MINOR | Encerramento inicial poderia sugerir Firebase client smoke autenticado real; validação foi Rules API Simulator no ruleset publicado | **CORRIGIDO** |
| G5A-NO-APP-ID-TOKEN | MINOR / DEFERRED GATE 5B | Firebase Auth ID token real do app ausente; sem FirebaseFirestore client read real em produção | **aberto não bloqueante** |
| G4-DART-FIRESTORE-EMU | MINOR / DEFERRED | Plugin Dart FirebaseFirestore E2E vs Emulator (Gate 4) | preservado |
| — | ACCEPTED | Collections canônicas vazias no momento do inventário | esperado pré-write path |

### G5A-NO-APP-ID-TOKEN

```text
Firebase Auth ID token real do aplicativo não estava disponível.

Não foi executado FirebaseFirestore client read real em produção.

A autorização foi validada contra o ruleset efetivamente publicado
via Rules API Simulator.

O transporte real app → Firebase Auth → Firestore
será validado quando a UI canônica for ativada no Gate 5B.
```

---

## 20. Deferred Gate 5B

```text
Nutrição Hoje UI canônica
read controller prime real pela UI
estados loading/data/empty/degraded/offline/error
plano ativo / meal schedule / executions / supplements
Firebase Auth + Firestore client smoke real
visual/UX review
```

**Fora de 5A:**

```text
ad hoc legacy cutover
legacy dual-write retirement
nutrition callables production write activation
```

---

## 21. Final readiness

```text
[x] Firestore Rules publicadas em produção
[x] ruleset after verificado vs fonte local
[x] drift audit sem surpresa
[x] Rules Nutrition 10/10 + Agenda 9/9 + integrity harness
[x] canonical read authz via Rules API Simulator no ruleset publicado
[x] nutrition_operations DENY
[x] nenhuma regressão de Rules detectada na Agenda
[x] nenhuma regressão de Rules detectada no Health existente (drift + predicados)
[x] ZERO production data writes
[x] ZERO Functions / indexes / Storage deploy
[x] ZERO legacy cutover
[x] rollback snapshot externo íntegro
[x] temp/gate5a removido do worktree
[x] G5A-EVIDENCE-WORDING corrigido
[x] G5A-NO-APP-ID-TOKEN deferred Gate 5B
[x] BLOCKER 0 / MAJOR 0
```

---

## Encerramento

```text
FASE 5D — GATE 5A CONCLUÍDA, DEPLOYADA, DOCUMENTADA E SINCRONIZADA.

CANONICAL NUTRITION READ RULES ATIVADAS EM PRODUÇÃO.

PRODUCTION DRIFT AUDIT APROVADO.

FIRESTORE RULESET PUBLICADO E VERIFICADO CONTRA A FONTE LOCAL.

CANONICAL READ AUTHORIZATION VALIDADA
CONTRA O RULESET PUBLICADO VIA RULES API SIMULATOR.

FIREBASE AUTH CLIENT READ REAL PERMANECE DEFERRED PARA O GATE 5B.

NUTRITION OPERATIONS PERMANECEM PRIVADAS AO BACKEND.

NENHUMA REGRESSÃO DE RULES DETECTADA NA AGENDA PREVENTIVA.

NENHUMA REGRESSÃO DE RULES DETECTADA NO HEALTH EXISTENTE.

ZERO PRODUCTION DATA WRITES REALIZADOS.

ZERO FUNCTIONS DEPLOY.

ZERO INDEXES DEPLOY.

ZERO STORAGE DEPLOY.

ZERO LEGACY CUTOVER.

ROLLBACK SNAPSHOT PRESERVADO FORA DO REPOSITÓRIO.

ZERO BLOCKER.

ZERO MAJOR.

BRANCH LIMPA E SINCRONIZADA.

FASE 5D — GATE 5B NÃO INICIADO.
```
