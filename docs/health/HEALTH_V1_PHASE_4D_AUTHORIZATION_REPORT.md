# Health v1.0 — Fase 4D Rodada 1 — Autorização Read-Only da Agenda

| Campo | Valor |
|-------|-------|
| Status | Gate 1 pronto para auditoria humana |
| Data | 2026-07-17 |
| Branch | `feature/health-v1-foundation` |
| HEAD base (preflight) | `a88922f8e298bcab6f0be6f2be55b0a6ecb37ea9` |
| Commit base esperado | `feat(health): add preventive schedule read source` |
| Tracking | `origin/feature/health-v1-foundation` |
| Escopo | Rule read-only `health_schedule`, testes de Rules, revisão de índice e alvo Firebase, plano de deploy **sem** executar |
| Fora de escopo | Ativação da source, deploy, writes, commit, push |

---

## 1. Preflight

| Item | Valor encontrado | Esperado |
|------|------------------|----------|
| branch | `feature/health-v1-foundation` | ok |
| HEAD | `a88922f8e298bcab6f0be6f2be55b0a6ecb37ea9` | ok |
| commit | `feat(health): add preventive schedule read source` | ok |
| tracking | `origin/feature/health-v1-foundation` | ok |
| divergência | `0/0` | ok |
| working tree | limpo no início | ok |

Nenhum reset, merge, rebase, troca de branch ou sincronização com `main` foi executado.

---

## 2. Objetivo

Preparar e validar com rigor a autorização **read-only** de:

```text
dogs/{dogId}/health_schedule/{scheduleId}
```

Garantir:

* Rule mínima de leitura reutilizando política Health/K9 já existente;
* zero writes cliente (create/update/delete);
* testes positivos e negativos de Rules, incluindo query/list operacional;
* índice revisado (sem deploy);
* alvo Firebase confirmado;
* plano de deploy e rollback documentados;
* production source **permanece** `EmptyHealthScheduleSource`.

---

## 3. Autorização Health existente encontrada

### 3.1 Documentação vs implementação real

| Fonte | O que diz |
|-------|-----------|
| `HEALTH_V1_PERMISSION_MATRIX.md` | Propõe `canReadHealth(dogId)` = `isAuthenticated && canAccessDogRecord && hasCapability('health.read')` |
| `HEALTH_V1_CAPABILITIES_INVENTORY.md` | Confirma que **não existe** catálogo real `health.read` implantado; Health legado usa acesso ao K9 |
| `firestore.rules` (código real) | Subcoleções de saúde sob `dogs/{dogId}` usam **`signedIn() && canAccessDogRecord(dogId)`** para leitura |

### 3.2 Helper real utilizado

```text
signedIn() && canAccessDogRecord(dogId)
```

Definições (já existentes, **não modificadas** nesta rodada):

| Helper | Comportamento |
|--------|---------------|
| `signedIn()` | `request.auth != null` |
| `hasOwnRecordsScope()` | autenticado, **não** admin, e claim `access_scope == 'own_records'` |
| `canAccessDogRecord(dogId)` | se **não** está em `own_records` → acesso ao K9 permitido; se está → exige K9 atribuído ao RA (`conductorRa`/`handlerId` etc.) **ou** turno ativo no K9 (`active_shifts/{ra}`) |
| `isAdmin()` | claim `admin`, `role`/`roles` em `admin`/`administrador` — admin **nunca** entra em `own_records` |

### 3.3 Padrão das subcoleções Health equivalentes (real)

Exemplos no mesmo bloco `match /dogs/{dogId}`:

```text
weight_records, health_events, feedings, feeding_events,
nutrition_prescriptions, nutrition_supplements, ...
  allow read: if signedIn() && canAccessDogRecord(dogId);
```

A Rule de `health_schedule` **replica a política de leitura** dessas subcoleções.

**Não** foi introduzido `hasCapability('health.read')` porque essa capability **não está implantada** nas Rules atuais. Inventar capability só para Agenda ampliaria ou quebraria o modelo sem base operacional.

### 3.4 Perfis / capacidades autorizados à leitura

Conforme Rules reais (e matriz conceitual de leitura Health):

| Situação | Leitura `health_schedule` |
|----------|---------------------------|
| Usuário autenticado com escopo global (default: sem `own_records`) | **Permitida** para qualquer `dogId` |
| Admin autenticado | **Permitida** (escopo global efetivo) |
| Usuário `own_records` com K9 atribuído a si | **Permitida** só nesse K9 |
| Usuário `own_records` com turno ativo no K9 | **Permitida** nesse K9 do turno |
| Condutor / operador autenticado no modelo atual | **Permitida** (mesmo padrão de `health_events` / `weight_records`) |

### 3.5 Perfis / situações negadas

| Situação | Resultado |
|----------|-----------|
| Não autenticado | **Negado** (get e list) |
| `own_records` sem atribuição e sem turno no K9 alvo | **Negado** (get e list) |
| Qualquer cliente (incluindo admin e leitor autorizado) em **create/update/delete** | **Negado** |

**Não** se assume que “qualquer autenticado lê qualquer K9” sem o helper: o isolamento por `own_records` é parte da política real e foi testado.

---

## 4. Rule adicionada

Arquivo: `firestore.rules` (match local sob `dogs/{dogId}`):

```
match /health_schedule/{scheduleId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

### Garantia de zero writes

* Não há `allow write`, `allow create`, `allow update` ou `allow delete` com condição verdadeira.
* `create`, `update` e `delete` estão **explicitamente** em `if false`.
* Catch-all global `match /{document=**} { allow read, write: if false; }` **não** foi alterado.
* Helpers compartilhados **não** foram modificados.
* Nenhuma outra coleção foi alterada.

Diff líquido de Rules: **+9 linhas**, localizado.

---

## 5. Testes de Rules

### Infraestrutura

* Pacote existente: `tools/rules_tests` + `@firebase/rules-unit-testing` + Firebase Emulator.
* Runner dedicado (escopo 4D): `tools/rules_tests/health_schedule_rules_tests.mjs`
* Script: `npm run test:health-schedule` (ou `firebase emulators:exec --project canil-gcm --only firestore "node health_schedule_rules_tests.mjs"`)

**Motivo do runner dedicado:** a suíte geral `rules_tests.mjs` apresenta **falha preexistente** no cenário `inicio de turno com viatura` (`vehicle_crews` / `vehicleChanges` undefined) — reproduzida **com e sem** a alteração de `health_schedule`. Não faz parte do escopo 4D corrigir vehicle crews.

Seeds usam `withSecurityRulesDisabled` (admin do emulator). Todas as asserções de autorização rodam como **cliente** autenticado ou anônimo.

### Cobertura executada (9/9 ok)

| # | Cenário | Resultado |
|---|---------|-----------|
| 1 | Não autenticado: get + list/query | denied |
| 2 | Autenticado global: get + query operacional | allowed; 2 docs open ordenados |
| 3 | Autenticado global em K9 B | allowed (modelo atual sem isolamento global) |
| 4 | `own_records` sem atribuição/turno no K9 A | get + list denied |
| 5 | `own_records` com K9 A atribuído; K9 B alheio | A allowed; B denied |
| 6 | `own_records` + turno ativo no K9 B | B allowed |
| 7 | Leitor autorizado: create, update, delete | **todos denied** |
| 8 | Admin: read allowed; create/update/delete denied | ok |
| 9 | Coleção vazia: list vazia (empty real, não permission-denied) | ok |

### Query/list operacional (obrigatória)

Mesma forma conceitual da `FirestoreHealthScheduleSource`:

```text
where lifecycle_status == 'open'
orderBy scheduled_for ASC
orderBy documentId ASC
limit 21
```

Validado com sucesso no Emulator (não apenas `get` isolado).

---

## 6. Source + Rules (integração local)

| Camada | O que foi feito |
|--------|-----------------|
| Rules + query operacional | Emulator + cliente JS autenticado (acima) — **prova a autorização da query real** |
| `FirestoreHealthScheduleSource` | Testes unitários com `FakeFirebaseFirestore` (suíte 4C) — **não** impõem Rules |
| Integração Flutter source + Emulator | **Não** existe infraestrutura pronta no repositório para rodar a source Dart contra o Emulator com auth de cliente nesta rodada |

Equivalência de segurança validada no Emulator:

* autorizado → list com dados ou empty real;
* não autorizado → permission-denied (não empty);
* empty autorizado → list size 0 sem erro.

Mapeamento de erro da source (já na 4C): `permission-denied` → `HealthScheduleSourceException(isPermissionDenied: true)` — **não** vira empty silencioso.

---

## 7. Índice revisado

Arquivo: `firestore.indexes.json` (**não modificado nesta rodada**).

```json
{
  "collectionGroup": "health_schedule",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "lifecycle_status", "order": "ASCENDING" },
    { "fieldPath": "scheduled_for", "order": "ASCENDING" }
  ]
}
```

| Check | Status |
|-------|--------|
| Collection group correto | `health_schedule` |
| Escopo | `COLLECTION` (subcoleção por dog, não collection group cross-dog) |
| Campos da query open + orderBy scheduled_for | ok |
| Duplicação | 1 única entrada |
| Segundo índice `schedule_type` | **ausente** (correto para 4C/4D) |
| Índices de outras features | intocados |

**Deploy do índice: não executado.**

---

## 8. Alvo Firebase identificado

| Fonte | Valor |
|-------|-------|
| `.firebaserc` alias `default` | `canil-gcm` |
| `firebase use` (CLI) | `canil-gcm` |
| `android/app/google-services.json` → `project_id` | `canil-gcm` |
| `project_number` (google-services) | `418249404282` |
| Rules tests `PROJECT_ID` | `canil-gcm` |
| CLI autenticado | sim (`firebase projects:list` retornou 6 projetos) |
| Projeto atual marcado | `canil-gcm (current)` |

**Outros projetos na conta CLI (risco de apontar errado se omitir `--project`):**

* `capstone-c1c47`, `casadocodigo-29d29`, `gen-lang-client-0583032481`, `guia-do-aventureiro-66d34`, `project-f4d51f8f-...`

### Veredito

```text
ALVO FIREBASE CONFIRMADO: canil-gcm
```

Próxima rodada de deploy **deve** usar `--project canil-gcm` de forma explícita (não confiar só no default implícito).

---

## 9. Plano exato de deploy — **NÃO EXECUTADO**

Comandos previstos para a **próxima** rodada (após auditoria humana do Gate 1):

### 9.1 Deploy somente Rules

```powershell
& 'C:\npm-global\firebase.cmd' deploy --project canil-gcm --only firestore:rules
```

Arquivo afetado em produção: Rules publicadas a partir de `firestore.rules`.

### 9.2 Deploy somente índices

```powershell
& 'C:\npm-global\firebase.cmd' deploy --project canil-gcm --only firestore:indexes
```

Arquivo afetado: `firestore.indexes.json` (adiciona índice `health_schedule`).

### 9.3 Escopo proibido neste plano

```text
firebase deploy                    # geral — NÃO usar
firebase deploy --only functions
firebase deploy --only hosting
firebase deploy --only storage
```

### 9.4 Ordem aprovada para o Gate 2

```text
1. Deploy do índice
2. Confirmar índice READY
3. Deploy das Rules
4. Validação autenticada real
5. Validar FirestoreHealthScheduleSource real
6. Só então ativar o composition root
```

**Requisito adicional do Gate 2 (obrigatório antes da ativação default):**

> Antes de ativar a source como default de produção, validar a cadeia real  
> **Flutter SDK → Auth → FirestoreHealthScheduleSource → Firestore → Rules → mapper.**

Até o passo 6, produção permanece em `EmptyHealthScheduleSource`.

### 9.5 Riscos do deploy

| Risco | Mitigação |
|-------|-----------|
| Deploy no projeto errado | `--project canil-gcm` obrigatório |
| Ampliar escrita por engano | Rule com create/update/delete `if false`; testes cobrem admin |
| Índice ainda building | UI/query pode falhar com failed-precondition até o índice ficar Ready; source mapeia isso sem empty falso |
| Source ativada antes do deploy | **Bloqueado** — composition root ainda Empty |

---

## 10. Estratégia de rollback

### Rules

* Versão anterior está no Git no commit `a88922f` (sem match `health_schedule`).
* Rollback: restaurar `firestore.rules` da versão anterior e:

```powershell
& 'C:\npm-global\firebase.cmd' deploy --project canil-gcm --only firestore:rules
```

* Efeito: leituras de `health_schedule` voltam a cair no catch-all deny.

### Índice

* Índice adicional **não** altera autorização.
* Em rollback de Rules **não** é necessário remover o índice automaticamente.
* Remoção de índice só se houver motivo operacional explícito (e com consciência de impacto em queries).

### Source / app

* Até ativação futura, produção continua em `EmptyHealthScheduleSource` (rollback de app desnecessário para esta rodada).
* Se a source for ativada depois e houver problema: reverter composition root para `EmptyHealthScheduleSource` e publicar app; Rules read-only podem permanecer.

---

## 11. Composition root — source desativada

Arquivo: `lib/features/health/presentation/screens/health_v1_entry_screen.dart`

```dart
_scheduleSource =
    widget.scheduleSource ?? const EmptyHealthScheduleSource();
```

| Check | Status |
|-------|--------|
| `EmptyHealthScheduleSource` em produção | **sim** |
| `FirestoreHealthScheduleSource.forDefault()` no entry | **não** |
| Comentário atualizado para 4D Gate 1 | sim (sem ativar) |

---

## 12. Presentation policy

**Não alterada.** Continua provisória:

```text
24h de tolerância
7d de upcoming
```

Sem persistência, sem ligação a Rules/índices.

---

## 13. Auditoria adversarial

| Vetor | Avaliação |
|-------|-----------|
| `allow read` aberto a qualquer autenticado sem helper | **Não** — exige `canAccessDogRecord` |
| Helper errado / capability inventada | **Não** — reutiliza helper real; sem `health.read` fake |
| Acesso mais amplo que outras áreas Health | **Não** — idêntico a `health_events` / `weight_records` |
| Write autorizado acidentalmente | **Não** — create/update/delete `if false`; testado |
| Gestor/admin com write cliente por herança | **Não** — admin só passa em read; writes negados no teste |
| Catch-all alterado | **Não** |
| Helper compartilhado modificado | **Não** |
| Query list não coberta | **Coberta** (query operacional 4C) |
| Rules testando só get | **Não** — get + list em todos os cenários relevantes |
| permission-denied → empty | Source 4C mapeia `isPermissionDenied`; empty só com list autorizada vazia |
| Teste só com admin context fingindo cliente | Seeds admin; asserções em cliente |
| Source ativada antes do deploy | **Não** |
| Project ID ambíguo | Confirmado `canil-gcm`; risco de multi-projeto documentado |
| Deploy geral no plano | **Não** — só `firestore:rules` e `firestore:indexes` |
| Segundo índice desnecessário | **Não** |
| Capabilities / claims alterados | **Não** |
| Mudança fora da Agenda | Apenas comentário no entry + infra de teste Rules |

---

## 14. Comandos executados

```text
# Preflight
git branch --show-current
git rev-parse HEAD
git status -sb
git rev-list --left-right --count HEAD..."origin/feature/health-v1-foundation"

# Rules tests dedicados (SUCESSO 9/9)
firebase emulators:exec --project canil-gcm --config firebase.json --only firestore
  "node tools/rules_tests/health_schedule_rules_tests.mjs"

# Suíte geral rules_tests.mjs
# FALHA PREEXISTENTE em vehicle_crews (reproduzida com e sem a Rule nova)

# Flutter
flutter test test/features/health/data/coexistence/schedule
flutter test test/features/health/presentation/schedule
flutter test test/features/health   # 784 tests — All tests passed

# Análise / git
dart analyze lib/features/health/presentation/screens/health_v1_entry_screen.dart
git diff --check
git status --short
git diff --stat

# Firebase target
firebase projects:list
firebase use
# leitura: .firebaserc, google-services.json, firestore.indexes.json
```

**Nenhum** `firebase deploy` foi executado.

---

## 15. Resultados

| Validação | Resultado |
|-----------|-----------|
| Rules health_schedule (9 testes Emulator) | **PASS** |
| Query operacional autorizada | **PASS** |
| Writes create/update/delete negados (incl. admin) | **PASS** |
| own_records isolamento | **PASS** |
| schedule coexistence + presentation | **PASS** (64) |
| suíte Health | **PASS** (784) |
| dart analyze entry | **No issues** |
| git diff --check | sem erros de whitespace (avisos CRLF Windows) |
| Suíte geral rules_tests.mjs | **FALHA PREEXISTENTE** (vehicle_crews) — fora do escopo |
| Deploy | **não executado** |

---

## 16. Arquivos modificados

| Arquivo | Mudança |
|---------|---------|
| `firestore.rules` | match read-only `health_schedule` |
| `lib/features/health/presentation/screens/health_v1_entry_screen.dart` | comentário 4D; source Empty preservada |
| `tools/rules_tests/package.json` | script `test:health-schedule` |
| `tools/rules_tests/README.md` | documentação do runner 4D |
| `tools/rules_tests/rules_tests.mjs` | ponteiro para runner dedicado |

## 17. Arquivos criados

| Arquivo | Propósito |
|---------|-----------|
| `tools/rules_tests/health_schedule_rules_tests.mjs` | testes de Rules read-only + query + writes |
| `docs/health/HEALTH_V1_PHASE_4D_AUTHORIZATION_REPORT.md` | este relatório |

## 18. Arquivos **não** alterados (confirmação)

* `firestore.indexes.json`
* composition root source (continua Empty)
* presentation policy
* capabilities / claims
* catch-all / helpers de Rules
* outras features

---

## 19. Estado git final (desta rodada)

```text
branch:     feature/health-v1-foundation
HEAD:       a88922f8e298bcab6f0be6f2be55b0a6ecb37ea9  (sem novo commit)
tracking:   origin/feature/health-v1-foundation
divergência: 0/0 no início; working tree sujo apenas com alterações 4D locais
commit:     NÃO criado
push:       NÃO executado
deploy:     NÃO executado
```

Working tree esperado após a rodada:

```text
 M firestore.rules
 M lib/features/health/presentation/screens/health_v1_entry_screen.dart
 M tools/rules_tests/README.md
 M tools/rules_tests/package.json
 M tools/rules_tests/rules_tests.mjs
?? tools/rules_tests/health_schedule_rules_tests.mjs
?? docs/health/HEALTH_V1_PHASE_4D_AUTHORIZATION_REPORT.md
```

---

## 20. Avaliação Gate 2 (próxima fase) — o que ainda falta

Gate 1 **não** ativa produção. Ordem aprovada para Gate 2:

```text
1. Deploy do índice
2. Confirmar índice READY
3. Deploy das Rules
4. Validação autenticada real
5. Validar FirestoreHealthScheduleSource real
6. Só então ativar o composition root
```

**Requisito de cadeia real (Gate 2):**

> Antes de ativar a source como default de produção, validar a cadeia real  
> Flutter SDK → Auth → FirestoreHealthScheduleSource → Firestore → Rules → mapper.

---

## 20.1 Revisão estática de Rules sobrepostas (fechamento Gate 1)

Varredura do ruleset completo por matches que pudessem aplicar writes a `dogs/{dogId}/health_schedule/{scheduleId}`:

| Caminho / match | Aplica a health_schedule? | Conclusão |
|-----------------|---------------------------|-----------|
| `match /dogs/{dogId}` (doc pai) | Não — Rules do documento pai **não** autorizam subcoleções | Sem write herdado |
| `match /health_schedule/{scheduleId}` | Sim — único match explícito | read se `signedIn && canAccessDogRecord`; create/update/delete `if false` |
| Outros `match` sob `dogs/{dogId}` | Outras subcoleções nomeadas | Não cobrem `health_schedule` |
| `match /{document=**}` catch-all | Só caminhos **sem** match mais específico | deny total; **intacto** |
| Qualquer outro `allow write/create/update/delete` no path | **Nenhum** encontrado | Zero writes cliente |

**Resultado:** não há match mais amplo que sobreponha a intenção read-only. Nenhuma alteração de Rules necessária no fechamento.

---

## 20.2 Confirmações de fechamento (pré-commit)

| Item | Status |
|------|--------|
| Nenhum deploy executado | confirmado |
| `EmptyHealthScheduleSource` ativa em produção | confirmado |
| `FirestoreHealthScheduleSource.forDefault()` **não** no composition root | confirmado |
| `firestore.indexes.json` **não** alterado nesta rodada | confirmado |
| Nenhuma capability criada/alterada | confirmado |
| Nenhum helper global de Rules modificado | confirmado |
| Catch-all deny intacto | confirmado |
| Nenhuma outra feature alterada | confirmado |

---

## 21. Gate final

Critérios mínimos Gate 1:

| Critério | Status |
|----------|--------|
| Rule read-only correta | sim |
| Writes negados | sim |
| Testes positivos e negativos | sim |
| Query/list testada | sim |
| Índice revisado | sim (sem deploy) |
| Alvo Firebase confirmado | `canil-gcm` |
| Production source desativada | `EmptyHealthScheduleSource` |
| Nenhum deploy executado | confirmado |

```text
FASE 4D — GATE 1 PRONTO PARA AUDITORIA HUMANA
```

---

## Confirmações explícitas

* **Nenhum deploy** de Rules, índices, functions ou hosting ocorreu nesta rodada.
* **`EmptyHealthScheduleSource` continua ativo** no composition root de produção.
* **Nenhum commit / push / merge / rebase** foi executado.
