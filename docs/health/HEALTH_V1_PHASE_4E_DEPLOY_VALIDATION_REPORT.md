# Health v1.0 — Fase 4E Gate 3 — Deploy & Validação

| Campo | Valor |
|-------|-------|
| Status | **Gate 3 aberto — smoke autenticado real pendente** |
| Data | 2026-07-17 |
| Branch | `feature/health-v1-foundation` |
| HEAD Git inicial | `169b7f57d31fb7a3a9d9dd2d97f7f0e5333259a0` |
| Commit base Gate 2 | `feat(health): add preventive schedule callables` |
| Deploy | **sim** (filtrado, 4 callables) |
| Projeto | `canil-gcm` |
| Região | `southamerica-east1` |
| Runtime | Node.js 22 (2nd Gen) |
| Commit desta rodada | **sim — reconciliação do source publicado** |
| Push desta rodada | **sim — `origin/feature/health-v1-foundation`** |
| Mobile conectado | **não** |
| UI mutação | **não** |
| Rules alteradas | **não** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD | `169b7f57d31fb7a3a9d9dd2d97f7f0e5333259a0` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |
| `.firebaserc` default | `canil-gcm` |
| `firebase use` | `canil-gcm` |
| `google-services.json` project_id | `canil-gcm` |
| CLI | autenticado (`jillohh@gmail.com`) |

---

## 2. HEAD / pacote a publicar

Exports no `functions/src/index.ts` (e carregados pelo Emulator/Deploy):

| Export | Região | Tipo |
|--------|--------|------|
| `healthScheduleCreateManual` | `southamerica-east1` | callable `onCall` |
| `healthScheduleUpdateOpen` | `southamerica-east1` | callable `onCall` |
| `healthScheduleComplete` | `southamerica-east1` | callable `onCall` |
| `healthScheduleCancel` | `southamerica-east1` | callable `onCall` |

Configuração efetiva (defaults Gen2):

* memória: **256Mi**
* CPU: **1**
* timeout: **60s**
* concurrency: **80**
* runtime: **nodejs22**
* secrets/env adicionais: **nenhum** (usa Admin SDK + Firestore do projeto)

Compatível com Functions já publicadas (mesmo codebase `default`, entry `lib/index.js`).

---

## 3. Correção pré-deploy descoberta no Emulator

### Problema

A primeira corrida de integração Auth+Firestore+Functions Emulator falhou em mutações reais com:

```text
Right-hand side of 'instanceof' is not an object
Cannot read properties of undefined (reading 'serverTimestamp')
```

Causa:

* uso de `admin.firestore.Timestamp` / `admin.firestore.FieldValue` no worker do Emulator;
* `err instanceof HttpsError` frágil cross-bundle no `mapLogicError`.

### Correção reconciliada nesta rodada

Arquivo: `functions/src/health_schedule_callables.ts`

* import modular: `FieldValue`, `Timestamp` de `firebase-admin/firestore`;
* `isHttpsError()` por shape (`name` / `httpErrorCode`) em vez de só `instanceof`.

### Impacto no deploy

O **deploy usou o source local já corrigido** (predeploy `tsc`), não apenas o blob idêntico a `169b7f5` sem o fix.

| Referência | Conteúdo |
|------------|----------|
| Git HEAD | `169b7f5` (Gate 2) |
| Source efetivamente publicado | `169b7f5` **+** fix Emulator (FieldValue/Timestamp + isHttpsError) |

O diff foi auditado e não há outra alteração funcional nos quatro callables.

```text
SOURCE LOCAL AUDITADO = SOURCE USADO NO DEPLOY
```

Após commit, push e redeploy filtrado a partir de working tree limpo, o source
publicado passa a corresponder ao `HEAD` versionado desta branch.

---

## 4. Integração Emulator (Auth + Firestore + Functions)

### Comando

```powershell
& 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only auth,firestore,functions "node tools/rules_tests/health_schedule_callables_emulator_tests.mjs"
```

### Isolamento

* projectId: `canil-gcm` (padrão do repo; dados **somente** no Emulator)
* ports: Auth 9099, Firestore 8080, Functions 5001
* seeds via Admin SDK do Emulator
* invocações via **cliente Firebase autenticado** (`httpsCallable`), região `southamerica-east1`

### Resultado

```text
Total: 26  Passed: 26  Failed: 0
```

---

## 5. Cenários Emulator (resumo)

### A. Create

| Cenário | Resultado |
|---------|----------|
| sem auth | unauthenticated |
| sem `health.create` | permission-denied |
| perm sem acesso ao K9 | permission-denied |
| autorizado | create: `manual`/`open`/revision `1`/autoria/timestamps/receipt/audit |
| same key same payload | replay, 1 audit |
| same key payload diferente | idempotency-conflict |
| concorrente mesma key | 1 único item determinístico |

### B. Update

| Cenário | Resultado |
|---------|----------|
| open + revision ok | sucesso, revision++ |
| A → B → retry A | A replay; B preservado |
| stale revision (sem receipt) | conflict |
| same op patch diferente | idempotency-conflict |
| cross-actor same opId | idempotency-conflict |
| item automático | permission-denied |

### C. Complete

| Cenário | Resultado |
|---------|----------|
| open → completed | completed_at/by, revision++, receipt/audit |
| retry | no-op; sem re-revision/re-audit |
| cancelled → complete | invalid-transition |

### D. Cancel manual

| Cenário | Resultado |
|---------|----------|
| reason + perms | cancelled |
| retry same reason | no-op |
| same op different reason | idempotency-conflict |
| other opId after cancel | already-cancelled |

### E. Cancel automático

| Cenário | Resultado |
|---------|----------|
| operador comum | permission-denied |
| autoridade admin real (`admin` claim / accessLevel admin) | allowed |

### F. Client direct writes

| Operação cliente em `health_schedule` | Resultado |
|---------------------------------------|-----------|
| create / update / delete | **permission-denied** (Rules) |
| callable após deny | **ainda muta** via Admin SDK |

### Receipts físicos

Campos confirmados: `actor_uid`, `operation_type`, `fingerprint`, `processed_at`.

---

## 6. Gate pré-deploy

| Check | Status |
|-------|--------|
| Emulator real passou | ✅ 26/26 |
| auth | ✅ |
| permissions | ✅ |
| dog access | ✅ |
| idempotência | ✅ |
| concorrência | ✅ |
| receipts | ✅ |
| audit idempotente | ✅ |
| client direct writes denied | ✅ |
| build Functions limpo | ✅ |
| alvo canil-gcm confirmado | ✅ |

---

## 7. Deploy filtrado

### Comando exato

```powershell
& 'C:\npm-global\firebase.cmd' deploy --project canil-gcm --only "functions:healthScheduleCreateManual,functions:healthScheduleUpdateOpen,functions:healthScheduleComplete,functions:healthScheduleCancel"
```

### Resultado

```text
+  functions[healthScheduleCreateManual(southamerica-east1)] Successful create operation.
+  functions[healthScheduleUpdateOpen(southamerica-east1)] Successful create operation.
+  functions[healthScheduleComplete(southamerica-east1)] Successful create operation.
+  functions[healthScheduleCancel(southamerica-east1)] Successful create operation.
+  Deploy complete!
Project: canil-gcm
```

### Confirmação `functions:list`

| Function | Version | Trigger | Location | Memory | Runtime |
|----------|---------|---------|----------|--------|---------|
| healthScheduleCreateManual | v2 | callable | southamerica-east1 | 256 | nodejs22 |
| healthScheduleUpdateOpen | v2 | callable | southamerica-east1 | 256 | nodejs22 |
| healthScheduleComplete | v2 | callable | southamerica-east1 | 256 | nodejs22 |
| healthScheduleCancel | v2 | callable | southamerica-east1 | 256 | nodejs22 |

Nenhuma outra Function criada/atualizada neste comando (somente as quatro listadas no `--only`).

Estado: **ACTIVE** (createTime ~ 2026-07-17T17:05–17:06Z UTC).

---

## 8. Smoke real (produção)

### A. Não autenticado (HTTPS callable)

Endpoint:

```text
https://southamerica-east1-canil-gcm.cloudfunctions.net/{functionName}
```

Body: `{"data":{"dogId":"x"}}`

| Function | HTTP | Resposta |
|----------|------|----------|
| healthScheduleCreateManual | **401** | `Autenticacao obrigatoria.` / `UNAUTHENTICATED` |
| healthScheduleUpdateOpen | **401** | idem |
| healthScheduleComplete | **401** | idem |
| healthScheduleCancel | **401** | idem |

Sem write.

### B/C. Autenticado com usuário real

**Não executado nesta sessão** por ausência de token Firebase de usuário
operacional real no ambiente e de sessão autenticada reutilizável no navegador.

Caminho autenticado completo (validation/not-found controlado sem write feliz) permanece coberto pelo **Emulator** e pelos testes unitários de handlers.

Observação residual (não é falha de segurança dos callables):

* smoke autenticado em produção deve ser refeito por humano com sessão real autorizada, ainda sem write feliz artificial.

### Zero seed / zero write feliz em produção

* nenhum item de agenda criado em produção nesta rodada;
* nenhum claim alterado;
* nenhum usuário artificial criado;
* smoke usou apenas falha pré-mutação (unauthenticated).

---

## 9. Logs pós-deploy / smoke

Revisão `firebase functions:log --project canil-gcm --only healthSchedule*`:

* create operations bem-sucedidas (ACTIVE);
* startup TCP probe OK nas quatro Functions;
* invocações smoke: `auth: MISSING` + `Callable request verification passed`;
* **sem** stack trace de inicialização;
* **sem** erro de dependência ausente;
* **sem** indício de permission bypass.

---

## 10. Mobile / UI / Rules

| Item | Status |
|------|--------|
| `FailClosedHealthScheduleMutationGateway` | ativo |
| `FirebaseFunctionsHealthScheduleMutationGateway` | **não existe** |
| composition root mutação Agenda | fail-closed |
| botões Concluir/Cancelar/Editar/Adicionar | **não** |
| `firestore.rules` | **intacto** nesta rodada |
| `firestore.indexes.json` | **intacto** |

---

## 11. Auditoria adversarial

| Vetor | Status |
|-------|--------|
| deploy geral acidental | **não** (filtrado) |
| Function extra publicada | **não** (só as 4) |
| projeto errado | **não** (`canil-gcm`) |
| Emulator → produção | **não** (emulators:exec isolado) |
| teste Admin fingindo cliente no Emulator | **não** (httpsCallable cliente) |
| client writes liberados | **não** (Rules deny confirmado) |
| claim alterada | **não** |
| seed produção | **não** |
| registro técnico permanente em prod | **não** |
| callable sem auth | denied (401) |
| mobile conectado | **não** |
| UI adicionada | **não** |
| idempotência Emulator | **pass** |
| audit não duplicada (Emulator) | **pass** |

---

## 12. Validações finais (pós-trabalho)

| Suite | Resultado |
|-------|-----------|
| `npm --prefix functions run test:health-schedule` | **all passed** (15 + 13) |
| `npm --prefix functions run build` | **ok** |
| Emulator callables integration | **26/26** |
| `flutter test .../health_schedule_mutation_engine_test.dart` | **28 passed** |
| `git diff --check` | **ok** (apenas avisos CRLF) |

---

## 13. Conteúdo do commit de reconciliação

```text
M  firebase.json
     (+ emulators: auth/functions/firestore ports)
M  functions/src/health_schedule_callables.ts
     (fix FieldValue/Timestamp modular + isHttpsError)
M  tools/rules_tests/package.json
M  tools/rules_tests/package-lock.json
     (+ firebase-admin devDep para harness)
?? tools/rules_tests/health_schedule_callables_emulator_tests.mjs
?? tools/rules_tests/health_schedule_prod_smoke.mjs
?? docs/health/HEALTH_V1_PHASE_4E_DEPLOY_VALIDATION_REPORT.md
```

`functions/lib/*` continua **não versionado** (`.gitignore`).

---

## 14. Problemas e correções

| # | Problema | Correção |
|---|----------|----------|
| 1 | Emulator: `Timestamp`/`FieldValue` namespace quebrados no path de mutação | imports modulares `firebase-admin/firestore` |
| 2 | Emulator: `instanceof HttpsError` frágil | `isHttpsError` por shape |
| 3 | Porta 8080 ocupada na 2ª corrida | kill processo stale + reexecução |
| 4 | Smoke autenticado prod sem ADC | documentado residual; Emulator cobre auth path |

---

## 15. Pendência para fechamento

1. Smoke autenticado real em produção (validation/not-found) com usuário real
   autorizado e K9 realmente acessível, sem write feliz artificial.
2. Revisar os logs das quatro Functions após esse smoke.
3. Manter Gate 4, gateway Flutter e UI fora de escopo até o fechamento formal.

---

## 16. Gate final

```text
FASE 4E — GATE 3 AINDA NÃO PRONTO PARA FECHAMENTO
```

Callables da Agenda reconciliados com Git, validados no Emulator integrado e
com smoke unauthenticated em produção. O smoke autenticado real permanece
pendente; por isso o Gate 3 continua aberto.

Mobile **não** conectado. UI **não** adicionada. Rules client write **continuam negadas**.
