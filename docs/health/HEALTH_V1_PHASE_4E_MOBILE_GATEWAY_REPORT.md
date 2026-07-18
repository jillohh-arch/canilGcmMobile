# Health v1.0 — Fase 4E Gate 4 — Mobile Gateway

| Campo | Valor |
|-------|-------|
| Status | **Gate 4 pronto para auditoria humana** |
| Data | 2026-07-17 / 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base (início) | `dfa0ac45b29143b907cd9439abf62c7ab494756f` |
| Código Functions em produção | `4b56587ab15d295788e5c9950cacc0030ec8e2aa` |
| Commit nesta rodada | **não** (parou para auditoria) |
| Push nesta rodada | **não** |
| Deploy nesta rodada | **não** |
| Projeto | `canil-gcm` |
| Região callables | `southamerica-east1` |
| Rules alteradas | **não** |
| Functions alteradas | **não** |
| UI de mutação | **não** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD inicial | `dfa0ac45b29143b907cd9439abf62c7ab494756f` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |
| `cloud_functions` | já presente (`^6.3.1`) — **reutilizado** |
| firebase_core / auth | existentes; sem upgrade de Firebase |

---

## 2. Contratos existentes auditados

| Artefato | Papel |
|----------|-------|
| `HealthScheduleMutationGateway` | porta assíncrona create/update/complete/cancel |
| Commands Gate 1 | `CreateManual…`, `UpdateOpen…`, `Complete…`, `Cancel…` |
| Results | `HealthScheduleMutationSuccess` / `ErrorResult` |
| Failures | códigos tipados sem Firebase |
| `HealthScheduleRevision` | token opaco (extraído para arquivo próprio) |
| Mutation engine | puro; não duplicado no gateway |
| `FirestoreHealthScheduleSource` + mapper | read path |
| Composition root | `HealthV1EntryScreen` |
| Handlers Functions | `health_schedule_callables.ts` — wire real |

---

## 3. Arquitetura do gateway

```text
Domain command
  → FirebaseFunctionsHealthScheduleMutationGateway
  → HealthScheduleMutationPayloadCodec (serialize)
  → HealthScheduleCallableInvoker / httpsCallable
  → parse receipt
  → HealthScheduleMutationSuccess | ErrorResult tipado
```

Arquivos novos (data/feature Health):

| Arquivo | Responsabilidade |
|---------|------------------|
| `firebase_functions_health_schedule_mutation_gateway.dart` | implementação permanente |
| `health_schedule_callable_names.dart` | nomes + região |
| `health_schedule_callable_invoker.dart` | seam de transporte |
| `health_schedule_mutation_payload_codec.dart` | wire encode/decode |
| `health_schedule_functions_error_mapper.dart` | Firebase → domínio |
| `health_schedule_revision.dart` | VO de revisão (domain) |

Sem Repository/UseCase/DI global. Backend permanece autoridade final.

---

## 4. Callable names e região

```text
region: southamerica-east1
FirebaseFunctions.instanceFor(region: 'southamerica-east1')
httpsCallable:
  healthScheduleCreateManual
  healthScheduleUpdateOpen
  healthScheduleComplete
  healthScheduleCancel
```

Sem URL HTTP hardcodada. Sem ID token manual. Sem Authorization header.

---

## 5. Serialização — Create Manual

Payload cliente:

```text
dogId, scheduleType (wireName), title, scheduledFor (ISO UTC),
dueUntil? (ISO), timezone, notes?, idempotencyKey
```

**Não** enviados: `source_type`, lifecycle, recorded_by, timestamps, revision,
caseId, clientGeneratedId, completed_*/cancelled_*, actor.

Teste unitário cobre ausência de campos server-owned.

---

## 6. Serialização — Update Open

```text
dogId, scheduleId, expectedRevision (int), operationId,
patch: { title?, scheduledFor?, dueUntil? | clearDueUntil,
         timezone?, notes? | clearNotes }
```

Patch whitelist alinhada ao `parseUpdatePatch` do backend.
`clearDueUntil` / `clearNotes` preservam semântica de limpeza explícita.
Revision inválida localmente → `validation` **antes** da rede.

---

## 7. Serialização — Complete

```text
dogId, scheduleId, operationId?
```

Sem `completed_at` / `completed_by` / lifecycle / revision resultante.

---

## 8. Serialização — Cancel

```text
dogId, scheduleId, operationId, cancelReason
```

Sem `cancelled_at` / `cancelled_by` / lifecycle.

---

## 9. Estratégia de revision

| Camada | Representação |
|--------|----------------|
| Domínio | `HealthScheduleRevision` (token string opaco) |
| Wire backend | inteiro monotônico ≥ 0 |
| Conversão | somente data (`requireWireRevision` / parse receipt) |

Token não numérico no update → falha tipada, sem `dynamic` silencioso.

---

## 10. Read contract — revision disponível

| Fonte | Comportamento |
|-------|----------------|
| `HealthScheduleDocumentMapper` | `revision` do doc → `HealthScheduleRevision` |
| ausente / legado | **0** |
| inválido (tipo/negativo) | **integrity** (sem fallback silencioso) |
| `HealthScheduleItem.revision` | campo de domínio (default `0`) |
| `HealthScheduleItemView.revision` | exposto para Gate 5 |

Derivação temporal da Agenda **não** alterada. Cursor/paginação intactos.

---

## 11. Parse de respostas

Receipt canônico dos quatro callables:

```text
dogId, scheduleId, revision, wasNoOp, lifecycleStatus
```

Mapeado para `HealthScheduleMutationSuccess` (sem `Map` cru para domain/UI).
Payload incompleto → `integrity`.

Nota: callables **não** retornam o item completo; `apply` (snapshot engine)
fica `null` no caminho remoto. Receipt enxuto é o contrato real.

---

## 12. Error mapping

Prioridade: `details.code` (HttpsError backend) → `FirebaseFunctionsException.code`.

| Código | Domínio |
|--------|---------|
| unauthenticated | `Unauthenticated` |
| permission-denied | `PermissionDenied` |
| not-found | `NotFound` |
| conflict | `Conflict` |
| idempotency-conflict | `IdempotencyConflict` (**novo**) |
| already-completed | `AlreadyCompleted` |
| already-cancelled | `AlreadyCancelled` |
| invalid-transition | `InvalidTransition` |
| validation / invalid-argument | `Validation` |
| integrity | `Integrity` (**novo**) |
| unavailable / network… | `Offline` |
| demais | `Unexpected` |

`FirebaseFunctionsException` **não** atravessa o gateway.
Mapeamento por texto humano: **não** usado para lógica.

---

## 13. Test seam

```dart
typedef HealthScheduleCallableInvoker =
  Future<Map<String, dynamic>> Function(String name, Map data);
```

Invoker real lazy (não toca Firebase no construtor — safe em widget tests).
Gateway aceita `invoker:` injetável.

---

## 14. Testes unitários do gateway

Arquivo: `test/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway_test.dart`

Cobertura:

* Create: nome, payload, idempotencyKey, sem server-owned, sucesso, wasNoOp
* Update: revision wire, operationId, patch whitelist, revision inválida pré-rede
* Complete: payload mínimo, completed + wasNoOp
* Cancel: operationId + reason, cancelled + wasNoOp
* Error mapping individual (11 códigos + unknown + não-Firebase + payload inválido)
* Exceção Firebase não vaza

**Resultado:** todos PASS.

---

## 15. Testes de revision no read path

`health_schedule_document_mapper_test.dart`:

* revision = 1
* revision > 1
* ausente → 0
* inválida → integrity

**Resultado:** PASS.

---

## 16. Composition root

`HealthV1EntryScreen`:

```text
default: FirebaseFunctionsHealthScheduleMutationGateway()
injetável: scheduleMutationGateway (testes / FailClosed / spy)
```

`FailClosedHealthScheduleMutationGateway` permanece disponível.
Sem fallback silencioso Firebase → FailClosed.

---

## 17. Auditoria de consumidores

| Consumidor | Mutação automática? |
|------------|---------------------|
| `HealthScheduleController` | **não** (somente leitura) |
| Agenda UI / cards | **não** (sem botões de ação) |
| `HealthV1EntryScreen` open/refresh/dog change | **não** |
| Listeners summary/timeline | **não** |
| Gateway real | default no root; **sem caller de UI** |

---

## 18. Zero chamadas automáticas

`health_schedule_zero_auto_mutation_test.dart` + spy:

```text
abrir Saúde / abrir Agenda / refresh / trocar filtro / trocar K9 (controller)
→ create=0 update=0 complete=0 cancel=0
```

**PASS.**

---

## 19. Smoke real pelo gateway permanente

| Item | Valor |
|------|-------|
| Device | Pixel 10 Pro XL (wireless) Android 17 |
| Modo | **debug** (release falhou com offline transitório na 1ª tentativa) |
| Entrypoint temp | `lib/debug/gate4_smoke_main.dart` (removido após) |
| Gateway | `FirebaseFunctionsHealthScheduleMutationGateway` (permanente) |
| Sessão | Firebase Auth real persistida no device (`auth uid present: true`) |
| K9 | dogId real (length=20; não logado em claro) |
| scheduleId | `nonexistent-schedule-gate4-smoke` |

| Operação | Wire | Domínio |
|----------|------|---------|
| updateOpen | `not-found` | `HealthScheduleMutationNotFound` |
| complete | `not-found` | `HealthScheduleMutationNotFound` |
| cancel | `not-found` | `HealthScheduleMutationNotFound` |

```text
[Gate4Smoke] AGGREGATE: PASS
```

Create válido em produção **não** executado de propósito (risco).  
Happy path create/update/complete/cancel com mutação real: **Emulator** (seção abaixo).

---

## 19b. Happy path integrado Flutter Gateway → Firebase Emulator

### Ambiente

| Item | Valor |
|------|-------|
| Projeto | `canil-gcm` **somente Emulator** (`emulators:exec`) |
| Auth | `127.0.0.1:9099` |
| Firestore | `127.0.0.1:8080` |
| Functions | `127.0.0.1:5001` |
| Região | `southamerica-east1` |
| Orquestrador | `tools/rules_tests/health_schedule_flutter_gateway_emulator_tests.mjs` |
| Teste Dart | `test/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway_emulator_test.dart` |
| Gateway | **`FirebaseFunctionsHealthScheduleMutationGateway` permanente** |
| Codec | `HealthScheduleMutationPayloadCodec` |
| Error mapper | `HealthScheduleFunctionsErrorMapper` |
| Transport | protocol HTTP callable do Functions Emulator + Auth Emulator token (mesmo wire do SDK; `flutter test` sem plugins nativos) |
| Seed | operador `health.create/edit` + K9 acessível (padrão Gate 3) |
| Produção | **zero** — hosts Emulator assertados; `emulators:exec` isola |

Comando:

```powershell
& 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only auth,firestore,functions "node tools/rules_tests/health_schedule_flutter_gateway_emulator_tests.mjs"
```

### Create (gateway permanente)

| Check | Resultado |
|-------|-----------|
| `HealthScheduleMutationSuccess` | **sim** |
| `wasNoOp` | `false` |
| `revision` | **1** |
| `lifecycle` | **open** |
| `scheduleId` retornado | `m_754081049bdd43b5ad7d101fd21f` |
| Firestore: `source_type=manual` | **sim** |
| `lifecycle_status=open` | **sim** |
| `revision=1` | **sim** |
| `schedule_type=vaccination` (wireName) | **sim** |
| `scheduled_for` / `due_until` aceitos (ISO Dart) | **sim** |
| `timezone=America/Sao_Paulo` | **sim** |
| autoria `recorded_by` server-side | **sim** |
| campos server-owned não enviados pelo cliente | **sim** (codec) |

### Create replay

| Check | Resultado |
|-------|-----------|
| `wasNoOp` | **true** |
| mesmo `scheduleId` | **sim** |
| revision permanece **1** | **sim** |
| audit create | **1** (sem duplicar) |

### Update bem-sucedido + revision real

| Check | Resultado |
|-------|-----------|
| `expectedRevision` Dart `1` → wire int | **sim** |
| patch title aplicado | **sim** |
| revision **1 → 2** | **sim** |
| `wasNoOp` | `false` |
| receipt `update_open` | **sim** |
| audit update | **1** |

Prova completa:

```text
HealthScheduleRevision Dart
→ expectedRevision wire
→ transaction backend Emulator
→ new revision
→ response
→ HealthScheduleRevision Dart
```

### Update replay

| Check | Resultado |
|-------|-----------|
| mesma `operationId` | **sim** |
| `wasNoOp` | **true** |
| revision permanece **2** | **sim** |
| sem 2ª audit update | **sim** |

### Complete bem-sucedido

| Check | Resultado |
|-------|-----------|
| lifecycle **completed** | **sim** |
| revision **2 → 3** | **sim** |
| `wasNoOp` | `false` |
| `completed_at` server-side | **sim** |
| `completed_by` server-side | **sim** |
| receipt + audit | **sim** |

### Complete replay

| Check | Resultado |
|-------|-----------|
| `wasNoOp` | **true** |
| revision permanece **3** | **sim** |
| `completed_at` / `completed_by` inalterados | **sim** |
| audit complete único | **1** |

### Cancel (item separado) + replay

| Check | Resultado |
|-------|-----------|
| create 2º item | **sim** (`m_da1cc1fd8bb033446d1dff4c1800`) |
| open → cancelled | **sim** |
| revision **1 → 2** | **sim** |
| `cancelReason` preservado | **sim** |
| replay `wasNoOp=true` | **sim** |
| audit cancel único | **1** |

### Error mapping integrado (backend real Emulator)

| Cenário | Domínio |
|---------|---------|
| stale revision (`expectedRevision=1` após rev 2) | **`HealthScheduleMutationConflict`** |
| mesma `operationId` com patch diferente | **`HealthScheduleMutationIdempotencyConflict`** |

Wire: `failed-precondition` + `details.code` → mapper permanente.

### Receipts físicos (Admin Emulator)

Path: `health_schedule/{id}/operations/{operationId}`

Confirmado por operação lógica:

* `actor_uid`
* `operation_type` (`create_manual` / `update_open` / `complete` / `cancel`)
* `fingerprint`
* `processed_at`
* `result.revision` / `wasNoOp`

Contagens: complete-path **3** ops; cancel-path **2** ops.

### Audit trail

```text
1 operação lógica → 1 audit lógico
```

| Path | actions |
|------|---------|
| complete | created, updated, completed (**3**) |
| cancel | created, cancelled (**2**) |

Retries **não** criaram auditoria adicional.

### Zero produção

```text
EMULATOR_ONLY_OK project=canil-gcm AUTH=127.0.0.1:9099 FS=127.0.0.1:8080 FN=127.0.0.1:5001
GATE4_EMULATOR_HAPPY_PATH: all checks passed
ZERO_PRODUCTION: emulators:exec only
```

* zero endpoint de produção;
* zero documento em produção;
* zero claim/usuário real;
* dados descartados ao encerrar o Emulator.

### Código permanente desta prova

| Mantido | Papel |
|---------|-------|
| teste Dart (skip se env ausente) | integration isolada |
| orquestrador Node | seed + Admin inspect + flutter test |

Sem bootstrap Emulator em produção, sem flags default ativas, sem UI de teste.

---

## 20. Zero writes (produção)

Smoke de produção usou apenas caminhos pré-mutação `not-found` com scheduleId sintético.

* nenhum create feliz em produção;
* nenhum item materializado em produção;
* nenhum seed/claim/usuário artificial em produção.

Happy path com write: **somente Emulator** (seção 19b).

---

## 21. Logs pós-smoke

| Function | auth | app | Resultado cliente |
|----------|------|-----|-------------------|
| healthScheduleUpdateOpen | **VALID** | INVALID | not-found tipado |
| healthScheduleComplete | **VALID** | INVALID | not-found tipado |
| healthScheduleCancel | **VALID** | INVALID | not-found tipado |

* requests chegaram às Functions corretas;
* sem stack de handler interno nos três;
* enforcement App Check desabilitado → request permitido.

---

## 22. App Check residual

```text
app: INVALID / No AppCheckProvider no harness smoke
enforcement: disabled
```

Débito de hardening já conhecido (Gate 3). **Não** alterado neste Gate.

---

## 23. Harness removido

Removidos integralmente após smoke:

* `lib/debug/gate4_smoke_main.dart`
* `lib/features/health/data/schedule/health_schedule_gate4_smoke.dart`
* pasta `lib/debug/` se vazia

Gateway permanente + testes unitários **permanecem**.

---

## 24. UI ausente

Diff final **sem**:

* botão Adicionar / Editar / Concluir / Cancelar
* formulários de Agenda
* menus de ação / FAB / confirmações
* nova tela de mutação

Gate 5 **não** iniciado.

---

## 25. Rules / Functions

| Item | Status |
|------|--------|
| `firestore.rules` | **intacto** (sem diff) |
| `firestore.indexes.json` | **intacto** |
| `functions/src/**` | **intacto** |
| deploy Functions | **não executado** |
| código prod Functions | permanece `4b56587…` |

---

## 26. Testes finais

| Suite | Resultado |
|-------|-----------|
| gateway unit | **PASS** |
| mapper revision | **PASS** |
| zero auto mutation | **PASS** |
| Emulator happy path (gateway permanente) | **PASS** (`GATE4_EMULATOR_HAPPY_PATH`) |
| `flutter test test/features/health` | **838 passed, 1 skipped** (skip = Emulator integration sem env) |
| `npm --prefix functions run test:health-schedule` | **all passed** |
| `npm --prefix functions run build` | **ok** |
| `flutter test` (global) | **1021 passed, 2 skipped** |
| `git diff --check` | avisos CRLF apenas (sem whitespace error) |

---

## 27. Diff (escopo)

**Modificados:**

* domain: item, revision, commands, errors, gateway, engine (format), models (format)
* data: mapper revision
* presentation: item view revision; entry composition root
* tests: mapper, gateway, zero-auto

**Novos:**

* `lib/features/health/data/schedule/*` (gateway + codec + mapper + invoker + names)
* `lib/features/health/domain/health_schedule_revision.dart`
* testes data/schedule + zero auto mutation
* `firebase_functions_health_schedule_mutation_gateway_emulator_test.dart`
* `tools/rules_tests/health_schedule_flutter_gateway_emulator_tests.mjs`
* este relatório

---

## 28. Git

```text
NÃO commit
NÃO push
NÃO deploy
```

Working tree sujo com implementação Gate 4 — aguarda auditoria humana.

---

## 29. Riscos residuais

1. **App Check** debug/invalid em client sem provider no harness; enforcement off.
2. Receipt remoto não reconstruí `HealthScheduleItem` completo — Gate 5 deve refresh
   da source de leitura após mutação UI.
3. Create feliz em produção **não** revalidado no mobile (proposital; unit + Gate 3).
4. Primeira tentativa smoke **release** retornou offline (ambiente); debug OK.

---

## 30. Recomendação Gate 5

1. UI de ações (Adicionar / Editar / Concluir / Cancelar) consumindo gateway real.
2. Após mutação: recarregar página/item da source (revision fresca).
3. Mapear falhas tipadas → copy de usuário.
4. Hardening App Check (provider debug cadastrado / enforcement planejado).
5. Não reabrir contratos wire sem necessidade.

---

## 31. Checklist Gate 4

```text
[x] gateway unit tests
[x] gateway smoke produção not-found
[x] happy path create via gateway + Emulator
[x] replay create
[x] happy path update + revision real
[x] replay update
[x] happy path complete
[x] replay complete
[x] happy path cancel
[x] replay cancel
[x] conflict backend → domínio
[x] idempotency-conflict backend → domínio
[x] receipts físicos validados
[x] audit idempotente validado
[x] zero produção
[x] harness temporário removido (smoke prod)
[x] integration Emulator permanente e isolado mantido
[x] nenhuma UI de mutação
[x] Rules/Functions intactas
[x] nenhum deploy realizado
```

```text
FASE 4E — GATE 4 PRONTO PARA AUDITORIA HUMANA
```
