# Health v1.0 — Fase 4E Gate 1 — Fundação de Mutações da Agenda

| Campo | Valor |
|-------|-------|
| Status | Gate 1 pronto para auditoria humana |
| Data | 2026-07-17 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `8ba4441ff45449411585f90821e2417c26621021` |
| Commit base | `feat(health): activate preventive schedule reads` |
| Escopo | Contratos de mutação, autorização, auditoria — **sem writes reais** |
| Commit / push / deploy | **não** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD | `8ba4441ff45449411585f90821e2417c26621021` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |

---

## 2. Objetivo

Definir e implementar a **fundação segura** das mutações da Agenda Preventiva:

* operações canônicas;
* invariantes e transições;
* autoria e timestamps confiáveis;
* concorrência e idempotência;
* contratos Dart tipados;
* decisão client vs backend;
* autorização real (sem inventar capabilities);
* testes puros;
* **zero** writes Firestore, **zero** alteração de Rules, **zero** deploy, **zero** UI de ação.

---

## 3. Operações canônicas

| Código | Operação | Transição / efeito | Hard delete |
|--------|----------|--------------------|-------------|
| `createManualScheduleItem` | Criar item manual | novo item `open` + `source_type=manual` | — |
| `completeScheduleItem` | Concluir | `open → completed` + `completed_*` | — |
| `cancelScheduleItem` | Cancelar | `open → cancelled` + `cancelled_*` + `cancel_reason` | — |
| `updateOpenScheduleItem` | Editar open | patch de campos mutáveis | — |
| hard delete | **PROIBIDO** | — | proibido |

---

## 4. Invariantes e transições

```text
open → completed   (permitido)
open → cancelled   (permitido)
completed → *      (proibido)
cancelled → *      (proibido)
```

* Terminais: `completed`, `cancelled`.
* Não existe transição persistida `overdue → completed`.
* Item visualmente overdue permanece `lifecycle_status=open`; conclusão é `open → completed`.
* Estados temporais **nunca** são persistidos.

Reutilizado e reforçado por:

* `HealthScheduleItemTransitions` (já existente em `health_v1_transitions_v2.dart`);
* `HealthScheduleMutationEngine` (novo).

---

## 5. Campos mutáveis / imutáveis

| Categoria | Campos |
|-----------|--------|
| Editáveis em open **manual** | `title`, `scheduled_for`, `due_until`, `timezone`, `notes` |
| Editáveis em open **automático** | **nenhum** no Gate 1 (só complete/cancel) |
| Imutáveis pós-criação | `schedule_type`, `source_type`, `source_id`, `case_id`, `created_at`, `recorded_by`, `schema_version`, `id`, `dog_id` |
| Só transição | `lifecycle_status`, `completed_at`, `completed_by`, `cancelled_at`, `cancelled_by`, `cancel_reason` |

Sem `Map<String, dynamic>` genérico de update.

`assigned_to` / `assignedToUid` existem no domínio como opcionais, mas **não** entraram no patch do Gate 1 (sem contrato de UI/autorização aprovado).

---

## 6. Auditoria

| Evento | Campos de autoridade | Fonte |
|--------|----------------------|-------|
| create | `created_at`, `recorded_by` | `HealthScheduleTrustedExecutionContext` |
| complete | `completed_at`, `completed_by` | trusted (nunca do form) |
| cancel | `cancelled_at`, `cancelled_by`, `cancel_reason` | timestamps/ator trusted; reason do comando |

Cliente **não** fornece UID de ator, nome de autoria final nem timestamp de auditoria nos commands.

---

## 7. CONCORRÊNCIA DE EDIÇÃO

### Gap corrigido

`expectedLifecycleStatus = open` **sozinho** não impede duas edições concorrentes enquanto o item permanece `open`.

### Contrato

| Mecanismo | Uso |
|-----------|-----|
| `HealthScheduleRevision` (token opaco) | optimistic concurrency neutro de backend |
| `UpdateOpenScheduleItemCommand.expectedRevision` | **obrigatório** |
| `HealthScheduleMutationStateSnapshot.revision` | revisão atual no engine |
| `expectedLifecycleStatus` | complementar (open), **não suficiente** |

Fluxo futuro (callable):

1. ler atomicamente item + revisão;
2. comparar `expectedRevision`;
3. se divergir → `conflict`;
4. aplicar patch só se coincidir;
5. avançar revisão.

Materialização concreta (contador, updateTime, token) fica para o backend — o domínio não depende de Firestore.

Testes: revision atual ok; stale → conflict; A e B com V1 e lifecycle open → segunda rejeitada.

---

## 8. IDEMPOTÊNCIA POR OPERAÇÃO

| Operação | operationId | Estratégia |
|----------|-------------|------------|
| create manual | **obrigatório** (alias `idempotencyKey`) | dedupe de criação; retry com mesma key → no-op do item existente (sem segundo doc) |
| update open | **obrigatório** | retry da mesma op → no-op; outra op com revision stale → `conflict` |
| complete | **opcional** | terminal semanticamente idempotente: `completed` → no-op **sem** sobrescrever `completed_at` / `completed_by` |
| cancel | **obrigatório** | mesma op processada → no-op preservando reason/at/by; outra op → `alreadyCancelled` (não silencia reason) |

### Detalhe cancel

* Nunca substituir silenciosamente `cancel_reason`, `cancelled_at`, `cancelled_by`.
* Snapshot guarda `lastLifecycleOperationId` para o engine puro; backend persistirá de forma equivalente.

### Detalhe complete no-op

* Retorna o mesmo item; `wasNoOp = true`.
* Garantia testada: trusted com outro ator/tempo **não** altera autoria/timestamp de conclusão.

---

## 8.1 SEMÂNTICA DOS ERROS TERMINAIS

| Código | Quando ocorre | Sucesso? |
|--------|---------------|----------|
| `conflict` | revision stale no update; lifecycle esperado ≠ real (quando aplicável) | não |
| `alreadyCompleted` | update/edit sobre completed; (asSuccess false) | não |
| `alreadyCancelled` | cancel com **outra** operationId sobre item já cancelled; update sobre cancelled | não (`asSuccess: false`) |
| `invalidTransition` | complete em cancelled; cancel em completed; matriz proibida | não |
| `validation` | campos inválidos / domain exception | não |
| `writesNotEnabled` | gateway fail-closed Gate 1 | não |

**Não** confundir:

* complete em already completed → **sucesso no-op** (não é erro `alreadyCompleted`);
* cancel retry mesma operationId → **sucesso no-op**;
* cancel com operationId diferente → **erro** `alreadyCancelled`.

Demais códigos: `unauthenticated`, `permissionDenied`, `notFound`, `offline`, `unexpected`.

---

## 8.2 Trusted execution context

`HealthScheduleTrustedExecutionContext` é contrato do **adapter backend**.

* Preenchido com Auth real + server timestamp confiável.
* **Nunca** aceitar do cliente: actor UID/name finais inventados no form, nem timestamp de auditoria do aparelho.
* Removido `operationId` do trusted context — a chave de op fica **só no command** (semântica por operação).

---

## 9. Modelo de erros tipados (lista)

```text
unauthenticated
permissionDenied
notFound
conflict
alreadyCompleted
alreadyCancelled
invalidTransition
validation
offline
unexpected
writesNotEnabled
```

UI futura não interpreta texto bruto de `FirebaseException`.

---

## 10. Contratos Dart implementados

| Arquivo | Papel |
|---------|-------|
| `health_schedule_mutation_commands.dart` | Commands + trusted context |
| `health_schedule_mutation_errors.dart` | Falhas tipadas |
| `health_schedule_mutation_policy.dart` | Mutabilidade / automáticos |
| `health_schedule_mutation_engine.dart` | Engine puro apply |
| `health_schedule_mutation_gateway.dart` | Porta + `FailClosed…` + `CommandSession` |

Já existente e reutilizado:

* `HealthScheduleItem`
* `HealthScheduleItemTransitions`

Gateway de produção: **não** conectado. Default conceitual: `FailClosedHealthScheduleMutationGateway`.

---

## 11. DECISÃO DE ESTRATÉGIA DE ESCRITA

| Operação | Estratégia escolhida | Motivo |
|----------|----------------------|--------|
| create manual | **callable / backend (preferencial); pendente de autorização** | Autoria/`created_at` confiáveis; reuso Mobile/Web; hoje não há capability `health.schedule_item` implantada; evita Rules complexas e dualismo com Functions de geração automática |
| edit open | **callable / backend (preferencial); pendente de autorização** | Mesmos motivos; validar source manual vs automático no servidor; concorrência |
| complete | **callable / backend** | Lifecycle crítico; `completed_*` não pode vir do cliente; concorrência atômica; padrão já usado em callables admin de health legado (`adminCreateHealthEvent`) |
| cancel | **callable / backend** | Idem; `cancel_reason` + `cancelled_*` sob autoridade única |

**Client write direto:** rejeitado como estratégia preferencial para complete/cancel.  
Para create/edit, client write só seria reavaliado se Rules + capabilities granulares forem implantadas e auditadas — **não** no Gate 1.

Nenhuma Function foi criada/exportada/deployada nesta rodada.

---

## 12. DECISÃO DE AUTORIZAÇÃO

### Modelo real implantado (evidência)

| Fonte | Achado |
|-------|--------|
| Rules `health_schedule` | **somente read** (`signedIn && canAccessDogRecord`); create/update/delete `if false` |
| Rules subcoleções health legadas | `canAccessDogRecord` + contratos de auditoria genéricos; **sem** `hasAccessPermission('health', …)` por capability v1 |
| Callables admin health | `requireAnyAccessPermission(..., "health", ["create","edit"])` + `requireDogRecordAccess` |
| Permission Matrix | propõe `health.schedule_item`, `health.manage_schedule` — **não implantadas** como catálogo mobile/Rules |
| Capabilities inventory | confirma ausência de catálogo `health.read` / `health.schedule_*` no código |

### Veredito

```text
AUTORIZAÇÃO DE ESCRITA AINDA NÃO DEFINIDA
```

para mutações da Agenda no mobile com capabilities granulares.

Operações permanecem **sem integração remota** (fail-closed).

Não foram inventadas:

* `health.write`
* `health.schedule.manage`
* claims novas

---

## 13. Matriz de autorização (candidatos documentais vs implantado)

| Operação | Operador/condutor | Gestor/Admin | Backend/System |
|----------|-------------------|--------------|----------------|
| criar manual | **REQUER NOVA DECISÃO/CAPABILITY** (matriz propõe condutor/admin; Rules/profiles reais sem grant schedule) | idem | System pode criar automáticos no futuro (já previsto no domínio) |
| editar open | **REQUER NOVA DECISÃO** (manual only; automático bloqueado no engine) | idem | preferencial |
| completar | **REQUER NOVA DECISÃO** (candidato condutor/admin na matriz) | candidato | **preferencial agora** como executor técnico |
| cancelar | **REQUER NOVA DECISÃO** (+ `cancel_reason`) | candidato | **preferencial agora** |

Nenhuma célula “PODE SER AUTORIZADO AGORA” para write cliente em produção: Rules bloqueiam e capability não existe.

Leitura continua: autenticado + `canAccessDogRecord` (já em produção 4D).

---

## 14. Itens automáticos vs manuais

| source_type | create pelo cliente | updateOpen | complete/cancel |
|-------------|---------------------|------------|-----------------|
| `manual` | sim (quando autorizado) | campos de agenda permitidos | sim (quando autorizado) |
| `treatment_protocol`, `clinical_case`, `exam_process`, `preventive` | não (origem Function/agregado) | **bloqueado** no engine Gate 1 | sim (quando autorizado) |

`source_type` / `source_id` imutáveis após criação.

---

## 15. Testes

Arquivo: `test/features/health/domain/health_schedule_mutation_engine_test.dart`

| Grupo | Cobertura |
|-------|-----------|
| lifecycle | open→completed/cancelled; terminais; overdue visual |
| concorrência | stale cancel após complete; expected mismatch |
| idempotência | complete/cancel repetidos |
| create | manual forçado; sem ator no command |
| update | manual ok; auto negado; imutáveis |
| gateway | fail-closed; double-submit session |
| matriz estática | só open→completed/cancelled |

**Resultado:** 28 testes PASS no mutation engine (+ suíte `health_schedule_item`).  
Cobertura adicionada na correção: revision stale, duas edições open, create sem key, retry create, complete no-op sem sobrescrever autoria, cancel mesma/diferente operationId.

---

## 16. Comandos executados

```text
git preflight
dart analyze (arquivos mutation)
flutter test test/features/health/domain/health_schedule_mutation_engine_test.dart
flutter test test/features/health/domain/health_schedule_item_test.dart (+ mutation)
git status / diff rules
```

---

## 17. Resultados

| Check | Resultado |
|-------|-----------|
| mutation engine tests | **28 PASS** |
| analyze mutation files | sem errors (infos cosméticas opcionais) |
| `firestore.rules` | **intacto** (sem diff) |
| `firestore.indexes.json` | **intacto** |
| deploy | **zero** |
| writes reais | **zero** |
| UI botões Concluir/Cancelar/Editar/Adicionar | **não adicionados** |

---

## 18. Auditoria adversarial

| Vetor | Status |
|-------|--------|
| write liberado | **não** |
| Rule alterada | **não** |
| Function exportada/deployável | **não** |
| autoria do cliente | **não** (trusted context) |
| timestamp final do cliente no command | **não** |
| update genérico Map | **não** |
| source_type editável | **não** |
| automático → manual | **não** |
| terminal reaberto | **não** |
| hard delete | policy `false` |
| temporal persistido | **não** |
| cancel sem motivo | rejeitado no command |
| last-write-wins | conflict/invalidTransition |
| double submit | `CommandSession` |
| capability inventada | **não** |
| autorização presumida | documentada como **não definida** |

---

## 19. Confirmações

* **Zero writes** reais no Firestore.
* **Rules** de `health_schedule` permanecem read-only.
* **Zero deploy** (Rules, indexes, Functions).
* **Zero UI** de mutação na Agenda.
* Composition root de **leitura** 4D intacto.

---

## 20. Diff / arquivos

### Criados

```text
lib/features/health/domain/health_schedule_mutation_commands.dart
lib/features/health/domain/health_schedule_mutation_errors.dart
lib/features/health/domain/health_schedule_mutation_policy.dart
lib/features/health/domain/health_schedule_mutation_engine.dart
lib/features/health/domain/health_schedule_mutation_gateway.dart
test/features/health/domain/health_schedule_mutation_engine_test.dart
docs/health/HEALTH_V1_PHASE_4E_MUTATION_FOUNDATION_REPORT.md
```

### Modificados

```text
(nenhum arquivo de produção de leitura/Rules)
```

---

## 21. Estado Git (final da rodada)

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD | `8ba4441…` (sem commit novo) |
| tracking | `origin/feature/health-v1-foundation` |
| working tree | sujo apenas com arquivos 4E Gate 1 |

---

## 22. Achados obrigatórios para o Gate 2

1. **`HealthScheduleRevision`** deverá ser **comparada e avançada atomicamente** pelo backend (transaction/precondition); o domínio só carrega o token opaco.
2. **Idempotência de create** deverá possuir **deduplicação durável e atômica** da `operationId`/`idempotencyKey` (índice único ou doc auxiliar), não apenas o no-op in-memory do engine.
3. **IDs de operação** necessários à idempotência (`createOperationId`, `lastLifecycleOperationId`, `lastUpdateOperationId`) deverão **sobreviver entre chamadas** no armazenamento de autoridade.
4. **Autorização de escrita** ainda precisa de **decisão formal** (capabilities / access_profiles) antes de qualquer implementação remota ou alteração de Rules.
5. **Rules** de `health_schedule` **continuam read-only** até autorização e Gate posteriores.

### Recomendação de implementação remota (Gate 2+)

1. Mapping formal `permissions.health.*` ou reuso auditado de grants existentes.
2. Callables com transaction + trusted actor + serverTimestamp.
3. Manter fail-closed no mobile até callable + autorização aprovados.
4. Só então UI de ações.

---

## 23. Gate final / fechamento

```text
FASE 4E — GATE 1 ENCERRADO (contratos commitados na branch)
```

Critérios atendidos: operações definidas; transições fechadas; autoria confiável; concorrência com revision; idempotência por operação; decisão backend/client; autorização mapeada sem invenção; contratos tipados; testes; zero writes reais; zero deploy; Rules intactas.
