# Health v1.0 — Fase 4D Gate 2 — Ativação Read-Only da Agenda Preventiva

| Campo | Valor |
|-------|-------|
| Status | Gate 2 executado — pronto para auditoria humana |
| Data | 2026-07-17 |
| Branch | `feature/health-v1-foundation` |
| HEAD base (pré-ativação local) | `295940744f6a96470857bf46fe45b03871be38fe` |
| Commit base | `feat(health): authorize preventive schedule reads` |
| Tracking | `origin/feature/health-v1-foundation` |
| Commit desta rodada | **não** (aguarda auditoria humana) |
| Push | **não** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD | `295940744f6a96470857bf46fe45b03871be38fe` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree | limpo no início |

---

## 2. Alvo Firebase

| Fonte | Valor |
|-------|-------|
| `.firebaserc` default | `canil-gcm` |
| `firebase use` | `canil-gcm` |
| `google-services.json` project_id | `canil-gcm` |
| project_number | `418249404282` |
| CLI autenticado | sim (`jillohh@gmail.com`) |
| Deploy flags | **sempre** `--project canil-gcm` |

```text
ALVO FIREBASE CONFIRMADO: canil-gcm
```

---

## 3. Revisão pré-deploy

### Rules (arquivo local = Gate 1 auditado)

```
match /health_schedule/{scheduleId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

| Check | Status |
|-------|--------|
| Catch-all `match /{document=**}` deny | intacto |
| Helpers globais | não modificados nesta rodada |
| Outras features | não alteradas |
| Writes health_schedule | `create/update/delete: if false` |

### Índice

```text
collectionGroup: health_schedule
queryScope: COLLECTION
lifecycle_status ASC
scheduled_for ASC
(+ __name__ ASC implícito no serviço)
```

Sem índice `schedule_type`. `firestore.indexes.json` **não** alterado no Gate 2 (já versionado na 4C).

---

## 4. Deploy do índice

| Campo | Valor |
|-------|-------|
| comando | `firebase deploy --project canil-gcm --only firestore:indexes` |
| início | 2026-07-17 10:38:01 -03:00 |
| fim | 2026-07-17 10:38:08 -03:00 |
| project ID | `canil-gcm` |
| resultado | **sucesso** (`Deploy complete!`) |
| notas | 2 índices remotos existem fora do arquivo local (não removidos; sem `--force`) |

---

## 5. Confirmação de índice pronto

Operação:

```text
projects/canil-gcm/databases/(default)/operations/S0FZLVVqSmdBQ0lDDCoDIDVhMjY1ODg3NGU1NC04MDRhLTRkMjQtMTYxMi1jYjIwYzY5YyQac2VuaWxlcGlwCQpBEg
```

| Campo | Valor |
|-------|-------|
| index | `.../collectionGroups/health_schedule/indexes/CICAgJjU-YAK` |
| startTime | 2026-07-17T13:40:08.845331Z |
| endTime | 2026-07-17T13:45:59.486649Z |
| metadata.state | `SUCCESSFUL` |
| response.state | **`READY`** |
| fields | `lifecycle_status ASC`, `scheduled_for ASC`, `__name__ ASC` |

```text
ÍNDICE HEALTH_SCHEDULE READY
```

---

## 6. Deploy das Rules

| Campo | Valor |
|-------|-------|
| comando | `firebase deploy --project canil-gcm --only firestore:rules` |
| início | 2026-07-17 10:46:17 -03:00 |
| fim | 2026-07-17 10:46:28 -03:00 |
| project ID | `canil-gcm` |
| resultado | **sucesso** |
| mensagem | `released rules firestore.rules to cloud.firestore` |
| ruleset | `firestore.rules` do HEAD `2959407` (Gate 1) |

Nenhum outro deploy (functions/hosting/storage/geral).

---

## 7. Validação autenticada real (antes de alterar o app)

Aplicação ainda com `EmptyHealthScheduleSource` nesta etapa.

### Método

Script one-shot (removido após uso) com:

1. Service account `canil-gcm` (somente mint de custom token + listagem admin de dogId);
2. Usuário **real** existente no Auth (`*@gcm.com.br`);
3. `createCustomToken(uid)` **sem** alterar claims;
4. Cliente Firebase JS (`signInWithCustomToken`) — **não** Admin SDK para a query;
5. Query operacional idêntica à source.

### Usuário / perfil (redigido)

| Campo | Valor |
|-------|-------|
| e-mail | `69***@gcm.com.br` |
| uid prefix | `BhPXtX` |
| claims presentes | `ra`, `access_scope=global`, `access_profile_id`, roles/admin flags, mobile/web access, training flags |
| claims alteradas no teste | **não** |

### K9 usado

| Campo | Valor |
|-------|-------|
| dogId | `4DDeRe7CCjTte6nbUbrC` |
| critério | primeiro documento de `dogs/` (sem seed) |

### Query real

```text
dogs/{dogId}/health_schedule
where lifecycle_status == open
orderBy scheduled_for ASC
orderBy documentId ASC
limit 21
```

| Resultado | Valor |
|-----------|-------|
| queryError | **null** |
| permission-denied | **não** |
| failed-precondition | **não** |
| size | **0** |
| empty | **true** |
| writes | **0** |
| latência | ~292 ms |

### Empty real

```text
0 documentos — empty autorizado (válido)
```

Nenhum documento `health_schedule` criado em produção.  
Mapper com documentos reais **não** exercitado por ausência legítima de dados; cobertura de mapper permanece nos testes 4C.

---

## 8. Validação da source Dart real

### Estado (pré-runtime Flutter desta rodada)

```text
Infraestrutura e query Firestore reais validadas.
FirestoreHealthScheduleSource Dart real pendente de validação em runtime Flutter autenticado.
```

A evidência JS (cliente Firebase com Auth real + query operacional) **permanece válida** para:

* Rules publicadas;
* índice utilizável (sem failed-precondition);
* empty autorizado;
* zero writes.

Ela **não** substitui a prova de que a classe Dart `FirestoreHealthScheduleSource` executou no host Flutter.

### Host Flutter (tentativas anteriores)

- `flutter test` com Firebase real: falhou por platform channel (`FirebaseCoreHostApi`).
- `flutter run -d windows`: projeto sem suporte desktop configurado.
- Chrome headless: não concluiu de forma útil.

### Runtime Flutter autenticado (esta rodada)

*Ver seção 12 e o bloco “FirestoreHealthScheduleSource Dart” no fechamento desta rodada.*

---

## 9. Gate de ativação (código local)

| Critério | Status na ativação local |
|----------|--------------------------|
| índice deployado | sim |
| índice READY | sim |
| Rules deployadas | sim |
| usuário autorizado executa query real (cliente) | sim |
| empty real ≠ erro | sim |
| permission model coerente | sim |
| **FirestoreHealthScheduleSource Dart em runtime Flutter** | **validada nesta rodada** |
| nenhum write | sim |
| nenhum erro de mapper | n/a (sem docs) |

**Decisão de código local (após infra OK):** composition root aponta para `FirestoreHealthScheduleSource.forDefault()`.  
**Decisão de fechamento/commit:** só após runtime Flutter real da source Dart.

---

## 10. Alteração no composition root

Arquivo: `lib/features/health/presentation/screens/health_v1_entry_screen.dart`

**Antes:**
```dart
widget.scheduleSource ?? const EmptyHealthScheduleSource()
```

**Depois:**
```dart
widget.scheduleSource ?? FirestoreHealthScheduleSource.forDefault()
```

- Injeção `widget.scheduleSource` **preservada** para testes.
- Import de `FirestoreHealthScheduleSource` adicionado.
- Sem fallback `try Firestore catch Empty`.

---

## 11. Destino da EmptyHealthScheduleSource

| Destino | Decisão |
|---------|---------|
| Classe | **mantida** |
| Uso | testes / harness explícitos |
| Produção default | **não** |
| Fallback silencioso de erro | **proibido** |

Comentário da classe atualizado para refletir 4D Gate 2.

---

## 12. Validação no aplicativo — runtime Flutter (rodada final)

### Disponibilidade de host

| Host | Resultado |
|------|-----------|
| Android físico (adb) | **nenhum device** |
| Android Emulator `Pixel_8_Pro` | **falhou** — system image ausente (`android-37.0/...` inválido); `sdkmanager` incompatível (XML v4 vs tools v3) |
| Flutter Chrome (web) | **executado com sucesso** — host Flutter real + Firebase Auth/Firestore plugins |

> Prioridade pedida era Android; na ausência de device/emulator funcional, a prova Dart usou **runtime Flutter Chrome** com a mesma classe `FirestoreHealthScheduleSource` e Auth/Firestore reais.

### Usuário / K9 (redigido)

| Campo | Valor |
|-------|-------|
| auth | custom token de usuário real `69***@gcm.com.br` (claims **não** alteradas) |
| uid prefix | `BhPXtX` |
| dogId A | `4DDeRe7CCjTte6nbUbrC` |
| dogId B | `DcUB2IIugUEPcBU4REWv` |
| source default | `FirestoreHealthScheduleSource.forDefault()` |

### Prova de passagem pela source Dart

Instrumentação **temporária** (removida após a prova):

```text
[Gate2-HS] FirestoreHealthScheduleSource.loadPage dogId=... pageSize=50
```

Chamadas observadas nos logs:

1. loadPage direto após Auth  
2. selectDog A (controller)  
3. refresh A  
4. selectDog B  
5. back to A  

`runtimeType` reportado: **`FirestoreHealthScheduleSource`**.

### Resultados da Agenda (runtime)

| Passo | Estado controller | Erros |
|-------|-------------------|-------|
| select K9 A | `HealthScheduleEmpty` | 0 |
| refresh A | `HealthScheduleEmpty` | 0 |
| recompute temporal | ok (local) | 0 |
| select K9 B | `HealthScheduleEmpty` | 0 |
| back K9 A | `HealthScheduleEmpty` | 0 |

**Verdict JSON (resumo):**

```text
ok=true
emptyState=true
finalState=HealthScheduleEmpty
errors=0
writesPerformed=0
sourceRuntimeType=FirestoreHealthScheduleSource
permission-denied: não
failed-precondition: não
integrity: não
crash: não
dados fake: não
```

UI: `HealthScheduleView` montada com empty copy institucional (`Nenhum cuidado programado`).

### Console

- Sem `permission-denied` / `failed-precondition` / integrity / exceptions de parsing na execução bem-sucedida.
- Erros de path genéricos do shell Windows (`O sistema não pode encontrar o caminho`) no stderr do Flutter CLI — **não** relacionados à Agenda/Firestore.
- Instrumentação temporária e harness `tool/gate2_flutter_runtime_main.dart` **removidos** após a prova.

### Automatizada (complementar)

- Controllers/UI Agenda: suíte presentation/schedule.
- Entry: default Firestore + lazy `selectDog`.
- Recompute temporal local (sem nova leitura).

---

## 12.1 Separação explícita de validação

### Infraestrutura

```text
VALIDADA EM PRODUÇÃO
```

(índice READY, Rules publicadas, query Auth real via cliente, empty autorizado, zero writes)

### FirestoreHealthScheduleSource Dart

```text
VALIDADA EM RUNTIME FLUTTER REAL
```

(host: Flutter Chrome; Auth real; `forDefault()`; controller; UI Agenda; troca K9 A↔B; refresh; recompute local)

---

## 13. Testes (pós-runtime)

| Suite | Resultado |
|-------|-----------|
| Rules `test:health-schedule` | **9/9 PASS** |
| coexistence/schedule + presentation/schedule | **64 PASS** |
| `flutter test test/features/health` | **784 PASS** |
| `flutter test` (global) | **967 PASS**, 1 skipped |
| `dart analyze` arquivos Gate 2 | **No issues** |
| `git diff --check` | avisos CRLF apenas |

---

## 14. Auditoria adversarial

| Vetor | Status |
|-------|--------|
| Source ativada antes da validação real | infra JS antes; runtime Dart após composition root local |
| Fallback silencioso Empty | **não** |
| Firebase em presentation além do composition root | source data layer no entry (composition root) |
| permission-denied → empty | **não** observado; source mapeia flag |
| failed-precondition → empty | **não** |
| índice não READY | READY confirmado |
| projeto errado | `canil-gcm` |
| deploy geral / redeploy nesta rodada | **não** (somente validação) |
| write / seed produção | **zero** |
| harness temporário residual | **removido** |
| log permanente de debug | **removido** |
| K9 hardcoded no app de produção | **não** |
| vazamento entre K9s | troca A↔B com loadPage distintos nos logs |
| recompute → nova leitura | recompute local; refresh explícito sim chama source |

---

## 15. Problemas e correções

| Problema | Tratamento |
|----------|------------|
| Índice INITIALIZING após deploy | polling até `READY` antes das Rules |
| Android emulator sem system image / sdkmanager quebrado | documentado; runtime Flutter em Chrome |
| `dart:io` incompatível com web no harness | reescrito com `--dart-define` |
| Suíte geral Rules `vehicle_crews` preexistente | fora de escopo |

---

## 16. Estado de produção

| Item | Estado |
|------|--------|
| Índice `health_schedule` | **READY** em `canil-gcm` |
| Rules | **read-only publicadas** (`signedIn && canAccessDogRecord`; create/update/delete `if false`) |
| Writes cliente agenda | **negados** (nenhum write autorizado ou executado) |
| Código da branch | `FirestoreHealthScheduleSource.forDefault()` no composition root |
| Aplicação instalada / binário em campo | ainda depende da **publicação futura do novo binário** (APK/store); Rules/índice já ativos no backend |

### Infraestrutura

```text
VALIDADA EM PRODUÇÃO
```

### Source Dart

```text
VALIDADA EM RUNTIME FLUTTER REAL
```

### Observações residuais não bloqueantes

1. **Smoke test Android físico** ainda desejável (runtime Flutter real desta fase usou Chrome por indisponibilidade de device/emulator).
2. **Mapper com documento real** ainda não exercitado porque `health_schedule` está **legitimamente vazio** — sem seed artificial para forçar o caso.

Nenhuma destas observações bloqueia o fechamento do Gate 2.

---

## 17. Diff do fechamento (commit)

Arquivos do pacote Gate 2:

```text
lib/features/health/presentation/screens/health_v1_entry_screen.dart
lib/features/health/presentation/schedule/empty_health_schedule_source.dart
docs/health/HEALTH_V1_PHASE_4D_ACTIVATION_REPORT.md
```

Sem:

* harness temporário;
* logs `[Gate2-HS]`;
* scripts one-shot;
* credenciais / service account / custom tokens;
* alteração de `firestore.rules` / `firestore.indexes.json` no working tree (já deployados no commit Gate 1).

---

## 18. Git — fechamento

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD pré-commit | `295940744f6a96470857bf46fe45b03871be38fe` |
| mensagem | `feat(health): activate preventive schedule reads` |
| deploy nesta rodada de fechamento | **não** |

---

## 19. Gate final

```text
FASE 4D — GATE 2 PRONTO PARA FECHAMENTO E COMMIT
```

Critérios atendidos:

* infraestrutura VALIDADA EM PRODUÇÃO;
* `FirestoreHealthScheduleSource` VALIDADA EM RUNTIME FLUTTER REAL;
* empty state real sem permission-denied / failed-precondition;
* refresh e troca de K9 exercitados;
* instrumentação temporária removida;
* composition root com `forDefault()`;
* zero writes / zero seeds.
