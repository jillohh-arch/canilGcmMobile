# Health v1.0 — Fase 4E Gate 6 — Auditoria final de confronto (Agenda Preventiva)

| Campo | Valor |
|-------|-------|
| Status | **Gate 6 encerrado** (remediação temporal + docs + deploy) |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base (Gate 5) | `4da45e5b3279cc1231a7c3ba08131f6a4aecc47e` |
| Correção funcional | `fix(health): enforce preventive schedule creation time` |
| Functions em produção (antes) | `4b56587ab15d295788e5c9950cacc0030ec8e2aa` |
| Commit correção | `3f1778f6066fb4c1475b45c71a1cf0aaf5b1f45a` |
| Functions em produção (após deploy filtrado) | **source branch commit `3f1778f…` — function `healthScheduleCreateManual` atualizada 2026-07-18** |
| Commit / push / deploy nesta rodada | **sim** (filtrado: `healthScheduleCreateManual`) |

```text
GATE 5 COMMIT SHA: 4da45e5b3279cc1231a7c3ba08131f6a4aecc47e
```

---

## 1. Executive summary

Confronto completo da Agenda Preventiva (Gates 1–5) + **remediação** do contrato temporal de create.

**Decisão de produto (aprovada):**

```text
NOVOS AGENDAMENTOS MANUAIS NÃO PODEM NASCER NO PASSADO.
pending / overdue só por passagem do tempo após a criação.
```

**Finding histórico (MAJOR):**

```text
MAJOR encontrado
  → backend aceitava scheduled_for no passado
  → corrigido (assertScheduledForNotInPast + UI create + engine)
  → revalidado (unit + callables + Emulator)
  → fechado
```

Caminho de produção permanece:

```text
UI → MutationController → Gateway → callables Admin SDK → Firestore
(Rules: client CUD false)
```

---

## 2. Git / preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD Gate 5 | `4da45e5b3279cc1231a7c3ba08131f6a4aecc47e` |
| Divergência preflight remediação | `0/0` |
| Working tree preflight | correções Gate 6 locais + relatório (preservadas) |

---

## 3. Scope audited

Domain, codec/gateway, callables, Rules, read path, UI, testes Gates 1–5, docs canônicos, adversarial search, **contrato temporal create**.

---

## 4. Canonical contracts

Documentos reconciliados nesta remediação:

* `HEALTH_V1_DOMAIN_MODEL.md` — create presente/futuro; id determinístico; revision
* `HEALTH_V1_FIRESTORE_SCHEMA.md` — writers client read-only / callables writer
* `HEALTH_V1_PERMISSION_MATRIX.md` — health.create/edit operacional; manage_schedule não operacional
* `HEALTH_V1_ARCHITECTURE.md` — lifecycle vs temporal derivado

---

## 5–16. Confrontos (resumo pós-remediação)

Ver rodada de auditoria anterior para tabelas detalhadas de domain×backend, revision, idempotency, lifecycle, source, auth, Rules, read/write, errors, refresh, UI matrix, audit, App Check.

**Atualização crítica — create temporal:**

| Camada | Comportamento |
|--------|----------------|
| Backend | `assertScheduledForNotInPast(scheduledFor, serverNow)` — `scheduledFor >= startOfUtcMinute(serverNow)` |
| Domain engine | mesma semântica com `trusted.serverNow` (sem `DateTime.now()`) |
| UI create | picker `firstDate=hoje` + validação de minuto local; **update não bloqueia** item já atrasado |
| Erro | `invalid-argument` + `details.code = validation` |

---

## 17. Audit trail

Inalterado: 1 audit canônico por op lógica; zero audit em create rejeitado (passado).

---

## 18. App Check readiness

Inalterado: enforcement off; não BLOCKER para dev; planejar release amplo.

---

## 19. Test evidence matrix

| Suite | Resultado remediação |
|-------|----------------------|
| logic: scheduled_for past/now/future | PASS |
| callables: past zero write; now+future aceito | PASS |
| domain engine past/current minute | PASS |
| Health / global | ver §24 |
| Rules health_schedule | ver §24 |
| Gate 4 Emulator | ver §24 |
| Gate 5 UI E2E Emulator | ver §24 |

---

## 20. Production/deployed source traceability

| Fase | SHA / valor |
|------|-------------|
| Functions pré-correção (Gate 3) | `4b56587ab15d295788e5c9950cacc0030ec8e2aa` |
| Source base remediação | `4da45e5b3279cc1231a7c3ba08131f6a4aecc47e` (Gate 5) |
| Commit correção temporal | `3f1778f6066fb4c1475b45c71a1cf0aaf5b1f45a` |
| Deploy filtrado | `firebase deploy --only functions:healthScheduleCreateManual --project canil-gcm` |
| Região | `southamerica-east1` |
| Resultado deploy | **Successful update operation** (2026-07-18) |
| Endpoint live | HTTP **401** sem auth (function servindo) |
| Smoke prod autenticado create passado | **requer `GATE3_ID_TOKEN`** (sem service account local para mint de custom token nesta máquina) — Emulator já provou validation + zero write |

**Produção `healthScheduleCreateManual` não permanece em `4b56587`.** Demais callables de agenda (update/complete/cancel) não foram redeployadas nesta filtragem (não precisam da regra de create).

---

## 21. Global adversarial search

* Único escritor: callables Admin SDK  
* Create passado: **rejeitado backend** (após fix)  
* Zero write em rejeição  
* Lifecycle só open/completed/cancelled  
* Temporais derivados  

---

## 22. Findings

### BLOCKERS

*Nenhum.*

### MAJOR

#### M-1 Create passado aceito no backend (FECHADO)

| | |
|--|--|
| Estado | **MAJOR encontrado → corrigido → revalidado → fechado** |
| Evidência inicial | `runHealthScheduleCreateManual` sem checagem de passado |
| Decisão produto | novos manuais não nascem no passado |
| Correção | `assertScheduledForNotInPast` em logic + callables; engine; UI create |
| Prova | testes unitários + callables zero write + Emulator |

### MINOR (revisados — mantidos)

1. `caseId`/`clientGeneratedId` mortos no command create — **manter** (codec não envia).  
2. Limites de tamanho domínio vs backend — **manter**.  
3. notes UI 1000 vs backend 2000 — **manter** (UI mais restrita, seguro).  
4. unknown keys no patch ignoradas — **manter** (não aplicam; source_* rejeitados).  
5. `details.code` ausente em alguns permission throws de access helper — **manter** (mapper usa transport code).

### DOCUMENTATION

Reconciliada em domain/schema/permission/architecture nesta rodada.

### ACCEPTED LIMITATIONS

* Cancel automático admin escondido na UI mobile.  
* Dual pure-engine (fingerprint durable só no TS).  
* App Check residual.  
* Lista operacional open-only.

---

## 23. Corrections applied

| Item | Arquivos |
|------|----------|
| Create temporal backend | `health_schedule_logic.ts`, `health_schedule_callables.ts` |
| Tests backend | `health_schedule_logic_test.ts`, `health_schedule_callables_test.ts` |
| Engine revision 1 + temporal | `health_schedule_mutation_engine.dart` + tests |
| UI create | form + user copy |
| Docs canônicos | domain, schema, permission, architecture |
| Comentários Gate 6 | query, rules (comment only) |
| Este relatório | atualizado |

---

## 24. Tests / deploy / smoke

| Item | Resultado |
|------|-----------|
| flutter test health | **+878 ~2 PASS** |
| flutter test global | **+1061 ~3 PASS** |
| functions test:health-schedule + build | **PASS** (past zero write; now+future OK) |
| Rules health_schedule | **9/9 PASS** |
| Gate 4 Emulator | **GATE4_EMULATOR_HAPPY_PATH PASS** |
| Gate 5 UI E2E Emulator | **UI E2E FULL EMULATOR PASS** |
| Emulator probe create passado | **HTTP 400** `details.code=validation` |
| Emulator probe create futuro | **HTTP 200** revision=1 |
| git diff --check | **exit 0** |
| Commit SHA | `3f1778f6066fb4c1475b45c71a1cf0aaf5b1f45a` |
| Deploy filtrado | **PASS** — `healthScheduleCreateManual` (southamerica-east1, canil-gcm) |
| Smoke Emulator create passado | **PASS** (400 validation) |
| Smoke prod create passado autenticado | **pendente token humano** (`GATE3_ID_TOKEN`) — comando: `node tools/rules_tests/health_schedule_gate6_prod_past_smoke.mjs` com ADC service account, ou invocar callable com ID token real |

---

## 25. Residual risks

App Check; cancel auto UI; docs legados em relatórios históricos 4E Gate 3/4; MINORs listados.

---

## 26. Final readiness decision

Checklist técnico local/Emulator/deploy:

```text
[x] create passado bloqueado por backend (Emulator + unit + callables)
[x] contrato domain/backend alinhado
[x] documentação canônica reconciliada
[x] testes locais verdes
[x] Emulator verde
[x] deploy filtrado concluído (healthScheduleCreateManual)
[ ] smoke produção autenticado negativo (aguardando GATE3_ID_TOKEN / service account)
[x] zero BLOCKER
[x] zero MAJOR
[x] branch sincronizada (pós-push)
```

**Estado:** remediação implementada, testada, commitada, pushada e **deploy filtrado feito**.  
Fechamento formal **Gate 6 ENCERRADO** fica pendente apenas da confirmação do smoke autenticado em produção com ID token real (sem write feliz).
