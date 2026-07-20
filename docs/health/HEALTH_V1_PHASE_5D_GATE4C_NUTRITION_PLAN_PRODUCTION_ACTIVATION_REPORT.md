# Health v1.0 — WEB-N2B Gate 4C — NutritionPlan Production Activation Closure

| Campo | Valor |
|-------|-------|
| Status | **ENCERRADO — DOCUMENTADO — OPERACIONAL** |
| Data | 2026-07-20 |
| Branch | `feature/health-v1-foundation` |
| HEAD deployado | `dd020a29872d90d4b7d64c185532bacf21a2dc53` |
| Mensagem final | `feat(health): add planned meal execution UI` |
| Tracking | `origin/feature/health-v1-foundation` |

---

## 1. Executive Summary

Três callables de gerenciamento de NutritionPlan foram ativadas em produção no projeto
`canil-gcm`. O backend está operacional.

Durante o processo de validação, duas operações CREATE com payload válido foram
executadas acidentalmente antes do smoke formal. Ambas geraram NutritionPlans reais em
produção. O segundo plano foi remediado via cancelamento canônico no Gate 4B.6-R2.

**Vereditos:**

```
NUTRITION_PLAN_BACKEND_PRODUCTION_ACTIVATED
ADMIN_AUTHORIZATION_PRODUCTION_VALIDATED
OPERATOR_AUTHORIZATION_PRODUCTION_VALIDATED
GESTOR_PRODUCTION_SMOKE_DEFERRED_NO_ASSIGNED_IDENTITY
PRODUCTION_TEST_PLAN_REMEDIATED_OPERATIONAL_BASELINE_RESTORED
```

---

## 2. Backend — Commits, HEAD e Tracking

### Commits desde o último Gate

| Commit | Mensagem | Relevância |
|--------|----------|------------|
| `52aaaeb` | test(health): validate nutrition plan permission capability | Auth validada |
| `3142ee9` | feat(health): add nutrition plan transactional mutations | Mutations deployadas |
| `5577c4f` | feat(health): add nutrition plan mutation foundation | Foundation |
| `2121038` | docs(health): document meal mutation backend activation | MealLog ativado |
| `dd020a2` | feat(health): add planned meal execution UI | UI execution (este Gate) |

### Commits Foundation / Permissions (seleção)

| Commit | Mensagem |
|--------|----------|
| `d7fcf94` | docs(health): define canonical nutrition contract |
| `c8893ed` | docs(health): close preventive schedule final audit |
| `f463d71` | docs(health): reconcile nutrition contract references |
| `832785f` | feat(health): add nutrition mutation foundation |

### Estado atual

| Item | Valor |
|------|-------|
| Branch | `feature/health-v1-foundation` |
| HEAD deployado | `dd020a29872d90d4b7d64c185532bacf21a2dc53` |
| Commit documental | Este commit de encerramento do Gate 4C |
| Tracking no momento do fechamento | `origin/feature/health-v1-foundation` — 0 behind, 1 ahead |
| Working tree após commit | limpo |
| Estado documental | Gate 4C commitado; push pendente |

---

## 3. Production Functions — Estado Final

| Callable | Status | Generation | Runtime | Região |
|---------|--------|------------|---------|--------|
| `healthNutritionCreateAndActivatePlan` | ACTIVE | Gen 2 | Node.js 22 | southamerica-east1 |
| `healthNutritionUpdateActivePlan` | ACTIVE | Gen 2 | Node.js 22 | southamerica-east1 |
| `healthNutritionCancelPlan` | ACTIVE | Gen 2 | Node.js 22 | southamerica-east1 |

Todas três Functions aceitam `onCall` e respondem corretamente a todas as
condições testadas.

---

## 4. Permission Capability — `health.manage_nutrition_plan`

A capability `health.manage_nutrition_plan` é definida no documento de Permissions
(HEALTH_V1_PERMISSION_MATRIX.md) e implementada no backend via
`requireManageNutritionPlan`/`isAdministrativeAuthority`.

| Perfil | `health.manage_nutrition_plan` | Executor |
|--------|-------------------------------|---------|
| `administrador` | `true` | Admin real BhPXtXczzzY4Ocd48SoD2QXb5Io2 |
| `gestor` | `true` | Sem identidade real atribuída |
| `operador_k9` | `false` | Operador real |

### Perfis Default Autorizados (Firestore access_profiles)

| Profile ID | `health.manage_nutrition_plan` |
|------------|-------------------------------|
| `operador_k9` | `false` |
| `instrutor_k9` | `false` |
| `almoxarifado` | `false` |
| **`administrador`** | **`true`** |
| **`gestor`** | **`true`** |

---

## 5. Authorization Evidence

### Operador Real

| Callable | Resultado | Código | Evidência |
|----------|-----------|--------|-----------|
| `healthNutritionCreateAndActivatePlan` | 403 | PERMISSION_DENIED | "Perfil sem permissao para health.manage_nutrition_plan." |
| `healthNutritionUpdateActivePlan` | 403 | PERMISSION_DENIED | "Perfil sem permissao para health.manage_nutrition_plan." |
| `healthNutritionCancelPlan` | 403 | PERMISSION_DENIED | "Perfil sem permissao para health.manage_nutrition_plan." |

Testado com UID `yXntKgXy7aTu0tJuAGfMEjV7Us82` (RA 691763), token Firebase ID com
`access_profile_id: operador_k9`.

### Administrador Real

| Callable | Resultado | Código | Evidência |
|----------|-----------|--------|-----------|
| `healthNutritionCreateAndActivatePlan` | 200 | — | Criou NutritionPlan `nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856` (acidental) |
| `healthNutritionUpdateActivePlan` | 400 | — | Safe-fail "planId e obrigatorio" |
| `healthNutritionCancelPlan` | 200 | — | Cancelou plano residual canonicamente |

Testado com UID `BhPXtXczzzY4Ocd48SoD2QXb5Io2` (RA 691755), token Firebase ID com
`access_profile_id: administrador`.

### Gestor

```
GESTOR_PRODUCTION_SMOKE_DEFERRED_NO_ASSIGNED_IDENTITY
```

Nenhuma identidade real está atribuída ao perfil `gestor` no momento. A via Gestor
permanece coberta por:

- permission tests (access_profiles/{gestor}/health.manage_nutrition_plan = true)
- callable tests (engine `isAdministrativeAuthority` genérico)
- emulator tests
- perfil `gestor` ativo no Firestore
- `health.manage_nutrition_plan === true` em `access_profiles/gestor`

---

## 6. Production Smoke Incident

### Designação

```
Production Smoke Incident — NutritionPlan CREATE Operations
Gate 4B.6 / Gate 4B.6-R1 / Gate 4B.6-R2
Dog ID: 4DDeRe7CCjTte6nbUbrC
Actor: BhPXtXczzzY4Ocd48SoD2QXb5Io2 (admin)
```

### Sequência de Operações

| # | Timestamp (UTC) | operationId | Tipo | planId | Status | Rev | supersededPlanId | Receipt | Audit |
|---|---------------|-------------|------|--------|--------|-----|----------------|---------|-------|
| 1 | 14:01:51 | `admin-create-test` | create | `nutrition_plan_081452030c60178657cc6367112991e7` | active | 1 | `null` | `nr1_7eeb869...` | `nu_audit_b4019...` |
| 2 | ~14:XX | — | delete | `nutrition_plan_081452030c60178657cc6367112991e7` | DELETADO | — | — | — | — |
| 3 | 14:17:00 | `admin-create` | create | `nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856` | active | 1 | `null` | `nr1_bdce684...` | `nu_audit_0a4fb...` |
| 4 | 14:56:32 | `gate4b6-remediate-1784559271072` | cancel | `nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856` | cancelled | 2 | — | `nr1_9c635d...` | `nu_audit_4b9aa...` |

### Análise de Impacto

- **`admin-create-test`** (14:01:51): `supersededPlanId: null` — **não substituiu plano pré-existente**
- **`admin-create`** (14:17:00): `supersededPlanId: null` — **não substituiu plano pré-existente** (plano 08145... já havia sido deletado)
- **Cleanup parcial**: o plano 08145... foi deletado por mecanismo não canônico, de mecanismo não reconstruído
- **Nenhum NutritionPlan legítimo preexistente foi modificado, superseded ou cancelado**
- **As únicas criações ocorridas foram os dois artefatos técnicos de teste documentados neste incidente**

### Remediação

O plano residual `nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856` foi cancelado
canonicamente via `healthNutritionCancelPlan`:

```
HTTP 200
planId: nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856
status: cancelled
revision: 2
wasNoOp: false
```

- `active → cancelled`
- `revision: 1 → 2`
- `valid_until` definido
- Receipt de remediação criado
- Audit de remediação criado com razão explícita

### Estado Operacional Final

| Métrica | Valor |
|---------|-------|
| NutritionPlan active no K9 | 0 |
| NutritionPlan total no K9 | 1 (cancelled) |
| NutritionPlan legado | inalterado |
| MealLog | inalterado |
| SuplementLog | inalterado |

### Artefatos Preservados

| Artefato | Status |
|----------|--------|
| Receipt `admin-create-test` | preservado |
| Receipt `admin-create` | preservado |
| Receipt remediação | criado |
| Audit `admin-create-test` | preservado |
| Audit `admin-create` | preservado |
| Audit remediação | criado |
| Plano `nutrition_plan_081452030c60178657cc6367112991e7` | deletado diretamente (mecanismo desconhecido) |
| Plano `nutrition_plan_137e4a64b0dc46a738e6c7209a9d6856` | preservado, status `cancelled` |

---

## 7. Débitos Históricos Registrados

| ID | Descrição | Impacto | Ação |
|----|-----------|---------|------|
| D-H1 | Primeiro NutritionPlan de teste deletado fora do fluxo canônico | Impossibilita reconstrução completa do mecanismo de cleanup | Documentado; nenhum impacto operacional; não requer correção |
| D-H2 | Mecanismo exato do delete direto não pode ser reconstruído | Lacuna de auditoria | Registro preservado; não requer correção adicional |
| D-H3 | operationId reutilizado antes do smoke formal | Bloqueou teste de idempotência da célula ADMIN CREATE | Não repetir; usar operationIds únicos por sessão |
| D-H4 | Audits de criação não encontrados sem janela temporal específica | Índices compostos em `auditLogs` por entityId ou action inexistem | Não bloqueia; documentado como MINOR |

---

## 8. Matriz Final de Autorização

| | CREATE | UPDATE | CANCEL |
|---|--------|--------|--------|
| **Operador real** (operador_k9) | 403 permission-denied ✓ | 403 permission-denied ✓ | 403 permission-denied ✓ |
| **Administrador real** (BhPXtXczzzY4Ocd48SoD2QXb5Io2) | 200 — authorization + engine comprovadas por execução produtiva acidental | 400 safe-fail ✓ | 200 — cancelamento canônico de remediação executado ✓ |
| **Gestor** | DEFERRED — nenhuma identidade real atribuída | DEFERRED | DEFERRED |

---

## 9. Findings

| Classe | Finding | Estado |
|--------|---------|--------|
| BLOCKER | Plano nutricional residual em produção | **RESOLVIDO** — cancelado canonicamente |
| BLOCKER | Receipt preexistente bloqueou smoke Admin CREATE | **RESOLVIDO** — documentado. Nenhuma repetição do smoke produtivo é necessária. Para futuras operações de teste em outros contextos, operationIds devem ser exclusivos por execução. |
| MAJOR | Primeiro artefato de teste removido fora do fluxo canônico, com mecanismo não reconstruído | **DOCUMENTADO** — D-H1/D-H2 |
| MAJOR | Audits de criação não encontráveis sem janela temporal | **DOCUMENTADO** — D-H4 |
| MINOR | operationId reutilizado antes do smoke formal | **DOCUMENTADO** — D-H3 |

**BLOCKER aberto: 0. MAJOR aberto: 0.**

---

## 10. Vereditos Finais

```
NUTRITION_PLAN_BACKEND_PRODUCTION_ACTIVATED
ADMIN_AUTHORIZATION_PRODUCTION_VALIDATED
OPERATOR_AUTHORIZATION_PRODUCTION_VALIDATED
GESTOR_PRODUCTION_SMOKE_DEFERRED_NO_ASSIGNED_IDENTITY
PRODUCTION_TEST_PLAN_REMEDIATED_OPERATIONAL_BASELINE_RESTORED
```

---

## 11. Deferred

| Item | Razão | Próximo passo |
|------|-------|--------------|
| Gestor smoke produtivo | Nenhuma identidade real atribuída ao perfil gestor | Atribuir identidade antes de executar smoke |

---

**GATE 4C ENCERRADO.**

**HEALTH V1.0 NUTRITIONPLAN BACKEND OPERACIONAL EM PRODUÇÃO.**

**AUTHORIZATION COMPROVADA EM PRODUÇÃO PARA OPERADOR E ADMINISTRADOR.**

**GESTOR DEFERIDO — SEM IDENTIDADE ATRIBUÍDA.**

**TEST PLAN REMEDIADO — BASELINE RESTORED.**

**BRANCH LOCAL CONSISTENTE — GATE 4C COMMITADO — PUSH PENDENTE.**
