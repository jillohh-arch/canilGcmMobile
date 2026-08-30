# Health v1.0 — Fase 4E Gate 2 — Callables da Agenda Preventiva

| Campo | Valor |
|-------|-------|
| Status | Gate 2 pronto para auditoria humana |
| Data | 2026-07-17 |
| Branch | `feature/health-v1-foundation` |
| HEAD base | `069560b48a4210ea11087065c7cd9dc040d6242d` |
| Commit | **não** (aguarda auditoria) |
| Deploy Functions | **não** |
| Rules write | **não** |
| Mobile conectado | **não** (gateway fail-closed) |
| UI mutação | **não** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD | `069560b48a4210ea11087065c7cd9dc040d6242d` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |

---

## 2. Política de autorização final

Não se inventou capability. Modelo reutilizado (já implantado nas Functions):

| Check | Helper real |
|-------|-------------|
| Auth | `requireAuth` via `requireAccessPermission` |
| Health create | `requireAccessPermission(auth, "health", "create")` |
| Health edit | `requireAccessPermission(auth, "health", "edit")` |
| Acesso ao K9 | `requireDogRecordAccess` (global / condutor / turno ativo) |
| Autoridade admin real (cancel auto) | `isAdminToken` **ou** `users.accessLevel` admin **ou** `user.admin === true` |

Admin token continua com bypass de profile grants (padrão existente) **e** ainda passa por `requireDogRecordAccess` quando o escopo não é global (admin token → scope global).

---

## 3. Matriz por operação

| Operação | Permissão | Dog access | Source | Extra |
|----------|-----------|------------|--------|-------|
| `healthScheduleCreateManual` | `health.create` | sim | força `manual` | — |
| `healthScheduleUpdateOpen` | `health.edit` | sim | só `manual` + `open` + revision | — |
| `healthScheduleComplete` | `health.edit` | sim | manual ou automático | terminal idempotente |
| `healthScheduleCancel` (manual) | `health.edit` | sim | `manual` | reason obrigatório |
| `healthScheduleCancel` (automático) | `health.edit` + **autoridade admin real** | sim | auto types | operador comum **denied** |

---

## 4. Estratégia de revisão

**Campo canônico:** `revision` (inteiro monotônico).

| Evento | revision |
|--------|----------|
| create | `1` |
| update/complete/cancel bem-sucedidos | `current + 1` |
| documento legado sem campo | interpretado como `0`; primeira mutação grava `1` |

`expectedRevision` em update comparado **dentro da transaction**.

Domínio Dart continua com token opaco `HealthScheduleRevision` (string); backend materializa número.

---

## 5. Idempotência durável (correção final)

### Operation identity

Identidade lógica de uma operação remota:

```text
Operation identity =
  actor_uid + operation_type + operationId
  dentro do escopo dogId + scheduleId
```

O path do receipt permanece:

```text
dogs/{dogId}/health_schedule/{scheduleId}/operations/{operationId}
```

O isolamento por ator e tipo **não** depende do path conter `actor_uid`/`operation_type`.  
Ao encontrar receipt existente, o backend valida obrigatoriamente, nesta ordem:

1. `stored.actor_uid == current authenticated actor uid`
2. `stored.operation_type == requested operation type`
3. `stored.fingerprint == current request fingerprint`

Somente se **todos** coincidirem → **replay / no-op**.  
Qualquer divergência → **`idempotency-conflict`** (nunca replay).

Consequências:

| Colisão | Resultado |
|---------|-----------|
| Operador A e B com mesmo `operationId` e mesmo patch | **conflict** (B não é replay de A) |
| `update` e `cancel` com mesmo `operationId` | **conflict** |
| `complete` e `cancel` com mesmo `operationId` | **conflict** |
| Mesmo ator + mesmo tipo + mesmo fingerprint | **replay** |
| Mesmo ator + mesmo tipo + fingerprint diferente | **conflict** |

Colisão inválida **não**:

* cria audit log
* altera o item
* incrementa revision
* modifica o receipt original

### Operation receipts

Campos: `operation_type`, `actor_uid`, `fingerprint`, `result`, `processed_at`.

**Atomicidade (update e demais mutações):** na mesma transaction  
verificar receipt → validar **actor_uid + operation_type + fingerprint** / revision → mutar → avançar revision → escrever receipt → audit determinístico → commit.

### Fingerprint canônico

| Op | Conteúdo do fingerprint (sem valores server) |
|----|-----------------------------------------------|
| create | dogId, scheduleType, title, scheduledFor ISO, dueUntil, timezone, notes |
| update | patch canônico (title/scheduledFor/dueUntil/timezone/notes) |
| cancel | cancelReason normalizado |
| complete | constante `complete` |

### Semântica

| Caso | Código / resultado |
|------|-------------------|
| mesma key + mesmo ator + mesmo tipo + mesmo fingerprint | `wasNoOp=true` (replay) |
| mesma key + qualquer divergência em ator/tipo/fingerprint | **`idempotency-conflict`** |
| update com revision stale (sem receipt) | **`conflict`** |
| cancel terminal por **outra** op | **`already-cancelled`** |
| retry A após B (update, mesmo ator) | receipt de A → **replay**, não conflict |

### Create

- ID determinístico `m_{hash}` a partir de `uid|dogId|create_manual|idempotencyKey` **e** `create_fingerprint` no doc.
- Isolamento natural por ator: material de hash inclui `uid`.
- Mesma key + payload igual → um documento, um audit.
- Mesma key + payload diferente (`create_fingerprint` diverge) → `idempotency-conflict` (não devolve o item antigo como se a nova intenção tivesse sido executada).

### Audit trail idempotente

IDs determinísticos em `auditLogs`:

```text
hs_audit_{sha256(dogId|scheduleId|operationType|operationId)[:40]}
```

Replay **não** cria segundo evento de mutação.  
Colisão inválida de receipt **não** cria audit.

### Autoridade administrativa

Cancel de item automático exige **autoridade admin real** (`isAdminToken` ou `users.accessLevel` admin / `user.admin`).  
Não há helper separado de “gestor” sem mapeamento real no código atual.

---

## 6. Trusted actor

Reconstruído no callable:

```text
recorded_by / completed_by / cancelled_by =
  { uid, name, internal_role: admin|condutor }
timestamps = FieldValue.serverTimestamp()
```

Payload cliente **rejeitado** se tentar injetar autoria, lifecycle, source, timestamps, revision.

---

## 7. Transações

Todas as mutações usam `db.runTransaction`:

1. get item (e dog pré-lido para auth)
2. decidir (lifecycle/source/revision/idempotência)
3. set/update + auditLogs
4. commit atômico

---

## 8. Audit trail

Padrão existente `auditLogs` (como `adminCreateHealthEvent`):

* action: `health_schedule_created|updated|completed|cancelled`
* entity_path, actor, metadata, source=`functions`, server timestamps

---

## 9. Functions implementadas / exportadas localmente

| Export | Arquivo |
|--------|---------|
| `healthScheduleCreateManual` | `functions/src/index.ts` |
| `healthScheduleUpdateOpen` | idem |
| `healthScheduleComplete` | idem |
| `healthScheduleCancel` | idem |
| lógica pura | `functions/src/health_schedule_logic.ts` |
| handlers | `functions/src/health_schedule_callables.ts` |

### Aviso de deploy futuro

O entrypoint `functions` exporta **todas** as functions do `index`. Um futuro:

```text
firebase deploy --only functions
```

publicaria também estes quatro callables, salvo deploy filtrado:

```text
firebase deploy --only functions:healthScheduleCreateManual,functions:healthScheduleUpdateOpen,...
```

**Nenhum deploy foi executado nesta rodada.**

---

## 10. Rules

`firestore.rules` **intacto**:

```text
health_schedule: allow read ...; allow create, update, delete: if false;
```

Callables usam Admin SDK.

---

## 11. Mobile / UI

* `FailClosedHealthScheduleMutationGateway` permanece.
* Sem `FirebaseFunctionsHealthScheduleMutationGateway`.
* Sem botões de mutação na Agenda.

---

## 12. Schema

`HEALTH_V1_FIRESTORE_SCHEMA.md` atualizado com campos do documento
`dogs/{dogId}/health_schedule/{scheduleId}`:

| Campo | Papel |
|-------|-------|
| `revision` | controle de concorrência monotônico |
| `create_operation_id` | chave da criação manual |
| `create_fingerprint` | intenção canônica do create |
| `last_update_operation_id` | atalho auxiliar da última update |
| `last_lifecycle_operation_id` | atalho auxiliar da última complete/cancel |
| `operations/{operationId}` | **subcoleção de receipts** |

```text
Receipts = fonte durável de idempotência.
last_*_operation_id = apenas atalhos auxiliares.
```

`migration_batch_id` e `schema_version` permanecem na tabela do documento pai,
**antes** da subseção de receipts (não fazem parte do schema de receipt).

### Path-safety de `operationId`

Estratégia adotada: **token estrito validado** (não hash físico).

```text
normalizeOperationId:
  - trim
  - obrigatório quando exigido
  - 1..128 caracteres
  - padrão ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$
  - rejeita "/", "\", ".", "..", espaços e símbolos
  - falha = validation (invalid-argument) antes de montar path
```

O `operationId` lógico validado **é** o segmento de path em
`operations/{operationId}`. Não há transformação por hash.

---

## 13. Testes

| Suite | Resultado |
|-------|-----------|
| `npm --prefix functions run test:health-schedule` | **all passed** (15 logic + 13 callables) |
| `npm --prefix functions run build` | **ok** |
| `flutter test .../health_schedule_mutation_engine_test.dart` | **28 passed** |
| `flutter test test/features/health` | **812 passed** |
| `flutter test` (global) | **995 passed, 1 skipped** |
| `git diff --check` | **ok** |

Cobertura de idempotência / receipts / path-safety:

1. retry tardio update A após B → replay  
2. same operationId + same patch (mesmo ator)  
3. same operationId + patch diferente → idempotency-conflict  
4. create key + payload igual  
5. create key + payload diferente → idempotency-conflict  
6. cancel same op + same reason  
7. cancel same op + reason diferente → idempotency-conflict  
8. audit não duplicado em retries  
9. receipts + mutação atômicos (transaction mock)  
10. **cross-actor** same operationId + same patch → idempotency-conflict  
11. **cross-operation** update→cancel same operationId → idempotency-conflict  
12. **cross-operation** complete→cancel same operationId → idempotency-conflict  
13. colisão inválida **não** altera item / revision / receipt / auditoria  
14. **operationId path-unsafe** rejeitado com validation (sem mutar)

Emulator Firebase completo: fake Firestore + deps injetadas (sem suíte Functions preexistente no repo).

---

## 14. Auditoria adversarial

| Vetor | Status |
|-------|--------|
| callable sem auth | denied |
| permission ausente | denied |
| dog access | enforced |
| cancel auto operador | denied |
| actor no payload | rejected |
| timestamp no payload | rejected |
| source_type no payload | rejected |
| operationId path-unsafe (`../`, `/`, etc.) | **validation** |
| idempotência só memória | **não** (doc + deterministic id) |
| revision fora da transaction | **não** |
| Rules write abertas | **não** |
| deploy | **não** |
| mobile conectado | **não** |
| UI | **não** |

---

## 15. Diff / Git

### `functions/lib/*` — decisão

```text
NÃO versionado.
```

Evidência:

* `.gitignore` linha `functions/lib/`
* `git ls-files functions/lib` → 0 arquivos
* `git check-ignore` confirma ignore ativo
* padrão histórico do repo: sources em `functions/src/`, build local via `tsc`

**Não incluir `functions/lib/*` no commit.** Artefatos de build permanecem locais.

### Arquivos do Gate 2

```text
functions/src/health_schedule_logic.ts          (novo)
functions/src/health_schedule_callables.ts      (novo)
functions/src/health_schedule_logic_test.ts     (novo)
functions/src/health_schedule_callables_test.ts (novo)
functions/src/index.ts                          (exports + wiring)
functions/package.json                          (script test:health-schedule)
docs/health/HEALTH_V1_FIRESTORE_SCHEMA.md
docs/health/HEALTH_V1_PHASE_4E_CALLABLES_REPORT.md
```

---

## 16. Recomendação Gate 3

1. Auditoria humana deste pacote.
2. Deploy **filtrado** dos 4 callables.
3. **Cliente deve obter `revision` confiável** antes de `updateOpen` (read model / mapper / resposta de callable — contrato de leitura a revisar, sem solução parcial).
4. Implementar gateway Flutter Functions (ainda fail-closed até lá).
5. UI de ações só após gateway validado.
6. Smoke Android físico.
7. Política de retenção de receipts (sem purga prematura).

---

## 17. Gate final

```text
FASE 4E — GATE 2 PRONTO PARA AUDITORIA HUMANA
```
