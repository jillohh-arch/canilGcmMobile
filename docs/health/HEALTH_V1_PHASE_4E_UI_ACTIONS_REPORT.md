# Health v1.0 — Fase 4E Gate 5 — UI de mutações da Agenda Preventiva

| Campo | Valor |
|-------|-------|
| Status | **Gate 5 encerrado, commitado e sincronizado** |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD base (início) | `1564245fa29145d9a9176483d89ab3b0e2bc21e3` |
| Commit Gate 4 | `feat(health): connect preventive schedule mutation gateway` |
| Código Functions em produção | `4b56587ab15d295788e5c9950cacc0030ec8e2aa` |
| Commit Gate 5 | `feat(health): add preventive schedule actions` |
| Push nesta rodada | **sim** (`origin/feature/health-v1-foundation`) |
| Deploy nesta rodada | **não** |
| Rules alteradas | **não** |
| Functions alteradas | **não** |
| Indexes alterados | **não** |
| Escritas Firestore diretas na UI | **nenhuma** |

---

## 1. Preflight

| Item | Valor |
|------|-------|
| branch | `feature/health-v1-foundation` |
| HEAD inicial | `1564245fa29145d9a9176483d89ab3b0e2bc21e3` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |
| `functions/` | sem diff |
| `firestore.rules` | sem diff |
| `firestore.indexes.json` | sem diff |

---

## 2. Telas / arquivos alterados

### Novos

| Arquivo | Papel |
|---------|-------|
| `presentation/schedule/health_schedule_action_availability.dart` | Matriz pura de ações (edit/complete/cancel) |
| `presentation/schedule/health_schedule_mutation_user_copy.dart` | Copy UX + mapeamento de failures |
| `presentation/schedule/health_schedule_mutation_outcome.dart` | Outcomes de apresentação (success/failure/blocked) |
| `presentation/schedule/health_schedule_mutation_controller.dart` | Coordenador de mutação + IDs + refresh |
| `presentation/schedule/forms/health_schedule_item_form_screen.dart` | Formulário create/edit |
| `presentation/schedule/widgets/health_schedule_add_button.dart` | CTA “Adicionar agendamento” |
| `presentation/schedule/widgets/health_schedule_complete_dialog.dart` | Confirmação de conclusão |
| `presentation/schedule/widgets/health_schedule_cancel_sheet.dart` | Motivo obrigatório de cancelamento |
| testes `*_action_availability_test.dart` | Matriz de ações |
| testes `*_mutation_controller_test.dart` | Controller / double-submit / refresh failure |
| testes `*_mutation_ui_test.dart` | Widget tests (form, menu, complete, cancel, conflict) |

### Modificados

| Arquivo | Mudança |
|---------|---------|
| `health_schedule_view.dart` | Wire mutações, CTA, empty state com create |
| `health_schedule_screen.dart` | Aceita `mutationController` |
| `health_schedule_item_card.dart` | Menu ⋮ contextual + loading por item |
| `health_schedule_formatters.dart` | Labels canônicos (Dose, Vacinação, …) |
| `health_v1_entry_screen.dart` | Composition root cria/dispose mutation controller |
| `schedule_test_helpers.dart` | Suporte a `revision` nos fixtures |

---

## 3. Arquitetura de presentation

```text
Usuário
  → HealthScheduleView (menu / CTA)
  → HealthScheduleItemFormScreen | CompleteDialog | CancelSheet
  → HealthScheduleMutationController
       · operationId / idempotencyKey estáveis por intenção
       · double-submit block
       · HealthScheduleMutationGateway (callable)
       · refresh obrigatório da HealthScheduleController
  → HealthScheduleMutationUiOutcome
  → feedback (snackbar) + eventual reabertura/invalidação
```

- **Sem** Repository/UseCase/DI global.
- **Sem** escrita Firestore na presentation.
- Receipt remoto **não** vira item canônico; a UI sempre recarrega a source.

---

## 4. Create UX

- Entrada: botão inferior **“Adicionar agendamento”** (referência mockup) + ação no empty state **“Adicionar à agenda”**.
- Sem FAB global (preserva Hub de Registros / shell).
- Campos: `scheduleType`, `title`, `scheduledFor`, `dueUntil?`, timezone fixo `America/Sao_Paulo`, `notes?`.
- Não expõe: source/lifecycle/revision/recorded_by/timestamps de conclusão.
- Após sucesso: fecha form + refresh + snackbar.
- Sucesso + refresh failure: fecha form + aviso de atualização pendente (não trata como falha de mutação).

---

## 5. Edit UX

- Somente `source_type == manual` e `lifecycle_status == open` com revision lida.
- Campos: title, scheduledFor, dueUntil, timezone, notes.
- Tipo / origem **não** editáveis (tipo exibido read-only).
- `expectedRevision` = revision do item lido.
- Conflito: mensagem + refresh; formulário **não** sobrescreve silenciosamente.

---

## 6. Complete UX

- Disponível para qualquer item `open` (manual ou automático).
- Dialog de confirmação com copy institucional.
- Sem pedir completed_at / completed_by / lifecycle.
- Loading no card; bloqueia cancel no mesmo item durante a operação.

---

## 7. Cancel UX

- Manual open: sheet com motivo obrigatório (trim; max 500 = backend).
- Automático: **não** exibe Cancel para operador (sem helper admin cliente confiável no Gate 5).
- Admin automático: suportado na matriz pura via flag `canCancelAutomaticAsAdmin` (default `false` na UI).

---

## 8. Matriz de ações

| Item | Editar | Concluir | Cancelar |
|------|--------|----------|----------|
| manual / open | sim | sim | sim |
| manual / completed | não | não | não |
| manual / cancelled | não | não | não |
| automatic / open / operator | não | sim | **não** |
| automatic / open / admin comprovado | não | sim | sim (flag) |
| automatic / completed\|cancelled | não | não | não |
| item busy | nenhuma | nenhuma | nenhuma |

---

## 9. Permission visibility

| Capacidade | Status no mobile |
|------------|------------------|
| `health.edit` / grants reais | **não** há helper schedule-específico no cliente |
| Admin cancel automático | **não** determinável com segurança → ação **escondida** |
| Backend | continua autoridade final em todas as callables |

Limitação documentada: UI esconde cancel de automático; backend ainda negar se chamado.

Não inventadas: `health.manage_schedule`, `manager`, `gestor`.

---

## 10. Operation IDs / idempotency keys

| Operação | Estratégia UI |
|----------|---------------|
| create | `Uuid.v4` via `ensureCreateIdempotencyKey()`; preservada em retry; limpa no sucesso / dispose de nova intenção |
| update | `beginUpdateIntent` gera ID; retry reutiliza; limpa no sucesso |
| complete | `ensureCompleteOperationId`; limpa no sucesso |
| cancel | `ensureCancelOperationId`; limpa no sucesso |

Factory injetável nos testes (`operationIdFactory`).

---

## 11. Loading / double-submit

- Create: flag `_createSubmitting`.
- Item: set `_busyScheduleIds` (complete e cancel mutuamente exclusivos no mesmo id).
- `HealthFormController` também serializa submit do formulário.
- Testes: double tap create/complete/cancel → 1 chamada gateway.

---

## 12. Refresh pós-mutação

Sempre após `HealthScheduleMutationSuccess`:

```text
gateway success → scheduleController.refresh() → UI com revision/lifecycle reais
```

---

## 13. Refresh failure pós-sucesso

Detectado por estado `hasRefreshFailure` / Error / Offline após refresh.

Outcome: `HealthScheduleMutationUiSuccess(refreshFailed: true)` com copy:

> Alteração salva, mas não foi possível atualizar a agenda agora. Puxe para atualizar novamente.

**Não** classificado como falha de mutação. Coberto por teste unitário.

---

## 14. Error mapping UX

| Failure | Mensagem (resumo) | Refresh? |
|---------|-------------------|----------|
| Unauthenticated | sessão expirou | não |
| PermissionDenied | sem permissão | não |
| NotFound | item não existe mais | sim |
| Conflict | alterado em outra sessão | sim |
| IdempotencyConflict | não confirmar com segurança | não |
| AlreadyCompleted | já concluído | sim |
| AlreadyCancelled | já cancelado | sim |
| InvalidTransition | ação inválida no estado | sim |
| Validation | mensagem localizável | não |
| Integrity | validar dados | não |
| Offline | sem conexão | não |
| Unexpected | tente novamente | não |

Sem codes Firebase / stack / operationId na UI.

---

## 15. Feedback de sucesso

`AppFeedback.success` com:

- Item adicionado à agenda.
- Item atualizado.
- Item concluído.
- Item cancelado.

Sem modal de sucesso.

---

## 16. Conflitos

- `HealthScheduleMutationConflict` → mensagem + `shouldRefresh` + form permanece (edit) com erro.
- Sem merge automático de campos.
- Revision stale **não** reutilizada: nova edição exige reabrir item pós-refresh.

---

## 17. Testes controller

Arquivo: `health_schedule_mutation_controller_test.dart`

Cobre create (valid/double/refresh-fail/permission/offline/validation/idempotency), update (revision/conflict/notFound), complete (success/noop/already/invalid/double), cancel (reason/success/already/idempotency/double/concorrência com complete).

---

## 18. Widget tests

Arquivo: `health_schedule_mutation_ui_test.dart`

- empty + CTA create  
- form create validação + save  
- menu manual open (3 ações)  
- menu automático (só complete + “Gerado automaticamente”)  
- terminal sem menu  
- complete dialog  
- cancel reason  
- conflict sem overwrite silencioso  

Matriz: `health_schedule_action_availability_test.dart`

---

## 19. Emulator UI happy path

```text
UI E2E FULL EMULATOR: PASS
```

### Prova executada (2026-07-18)

| Etapa | Resultado |
|-------|-----------|
| AUTH / FIRESTORE / FUNCTIONS | Emulator local `127.0.0.1:9099 / 8080 / 5001` |
| Seed sintético | operador `691755`, dog `dog-gate5-ui-a`, item auto open, terminais |
| `adb reverse` no Pixel | 9099, 8080, 5001 |
| Suite | `test/.../health_schedule_ui_e2e_emulator_test.dart` + `HEALTH_SCHEDULE_UI_E2E=1` |
| Binding | `LiveTestWidgetsFlutterBinding` + HTTP real para Emulators |
| Gateway | `FirebaseFunctionsHealthScheduleMutationGateway` (callable HTTP Emulator) |
| Refresh | source REST no mesmo path `dogs/{dogId}/health_schedule` (open) |

### Fluxos comprovados

| Fluxo | UI → callable → refresh | Inspeção Emulator |
|-------|-------------------------|-------------------|
| **Create** | form Salvar → item aparece | `revision=1`, `manual/open` |
| **Edit** | form Editar → conteúdo novo | `revision 1→2` |
| **Complete** | dialog Concluir → some dos open | `lifecycle=completed`, rev≥3 |
| **Cancel** | sheet + motivo → some dos open | `lifecycle=cancelled`, reason gravado |

Marker da execução:

```text
GATE5_UI_E2E {
  "createId":"m_a69ce50f83ec1e4f3f63602ec8d6",
  "cancelId":"m_0b71dafc256eaa729ad70624fcdc",
  "createRevision":1,
  "editRevision":2,
  "dogId":"dog-gate5-ui-a"
}
```

Verificação Admin/REST pós-teste:

```text
CREATE  lifecycle=completed revision=3 source=manual
CANCEL  lifecycle=cancelled reason=Duplicado no e2e Gate5 revision=2
```

Orquestrador permanente:

```text
tools/rules_tests/health_schedule_ui_e2e_emulator_tests.mjs
```

Widget tests com spy (create/menu/cancel/conflict) continuam verdes em CI sem Emulator.

---

## 20. Android físico

```text
REVISÃO VISUAL/INTERATIVA: CONCLUÍDA
```

| Item | Status |
|------|--------|
| Device | Pixel 10 Pro XL (wireless), Android 17 |
| `adb reverse` Auth/FS/Functions | **ok** (host-30 tcp:9099/8080/5001) |
| Mutação positiva artificial em produção | **não** |
| Dados | somente Emulator sintético |
| Captura device | `temp/gate5_ui_e2e_screenshots/00_device_current.png` (evidência transitória, não versionar) |
| Cleartext localhost | `network_security_config.xml` (somente 127.0.0.1/localhost/10.0.2.2) |

### Achados visuais (shell Agenda + mutações)

| Achado | Decisão |
|--------|---------|
| CTA inferior “Adicionar agendamento” | coerente com mockup; mantido |
| Empty: ação surface + CTA inferior | aceitável (mockup também enfatiza create); sem remoção |
| Menu ⋮ contextual | discreto; manual open = 3 ações; auto = só Concluir |
| “Gerado automaticamente” | presente e discreto |
| Complete (verde) / Cancel (vermelho) | contraste destrutivo ok |
| Form sticky Salvar | ok; teclado/`adjustResize` já no scaffold Health |
| Overflow | não observado nos testes 360–430 (suites) + E2E 400×1400 |
| Integração test no device wireless | deploy Gradle flaky via wireless ADB; E2E host+Emulator + reverse no Pixel cobrem o contrato |

Política mantida: happy path mutacional só Emulator.

---

## 21. Zero produção artificial

```text
ZERO_PRODUCTION
```

Nenhum `health_schedule`, receipt, audit, usuário ou claim de **produção** foi criado/alterado.
Todo seed e mutação E2E usou Firebase Emulators + dog/user sintéticos.

---

## 22. Nenhuma escrita direta

Auditoria do package `presentation/schedule`:

- zero `FirebaseFirestore.instance`
- zero `.collection(...).set/update/delete` novos

Toda mutação passa por `HealthScheduleMutationGateway`.

---

## 23. Rules / Functions intactas

```text
git diff -- functions firestore.rules firestore.indexes.json
→ vazio
```

`npm --prefix functions run test:health-schedule` → all passed  
`npm --prefix functions run build` → tsc OK  

---

## 24. App Check residual

Inalterado neste Gate:

```text
app: INVALID em debug sem provider cadastrado
enforcement off
```

Não misturado com UI de Agenda.

---

## 25. Acessibilidade

- Targets de menu / botões ≥ ~48 lógico (FilledButton altura 50; menu icon 22 + padding)
- Semantics em cards, CTA, menu “Ações do item”
- Loading no ícone do card durante mutação
- Cancel destrutivo em vermelho; complete em verde
- Form com labels obrigatórios e proteção de unsaved changes

---

## 26. Visual / UX

Preservado shell aprovado da Agenda:

- dark navy / cyan primário  
- cards arredondados glass  
- CTA inferior cyan “Adicionar agendamento” (mockup)  
- sem redesenho de KPIs/filtros/seções  

Referência: `docs/health/mockups/agenda preventiva.png`  
Precedência: contrato canônico > código > mockup.

### Polimento visual (2026-07-18)

| Item | Antes | Depois |
|------|-------|--------|
| Tipo (Create) | `DropdownButtonFormField` genérico | Campo compacto + **bottom sheet** com ícones (`HealthScheduleTypePickerField`) |
| Ícones | só no card | **mesmo** `HealthScheduleFormatters.typeIcon/typeLabel` no form e sheet |
| Hierarquia Create | Tipo → Título → datas | **Título → Tipo → Agendado → Prazo → Observações** |
| Edit tipo | input desabilitado grande | **header compacto** read-only com ícone + “Item manual” |
| Timezone UI | `America/Sao_Paulo` | **Horário de Brasília** (wire interno inalterado) |
| Date/time pickers | inglês (sem localizations) | **pt-BR** via `flutter_localizations` + `locale: pt_BR` no `MaterialApp` |
| Complete dialog | botões assimétricos | **Row com dois Expanded** (Voltar / Concluir) |

Arquivos novos de UI:

- `widgets/health_schedule_type_picker.dart`

---

## 27. Testes finais (pós polimento)

| Comando | Resultado |
|---------|-----------|
| UI E2E Emulator (`HEALTH_SCHEDULE_UI_E2E=1`) | **1 passed** + marker GATE5_UI_E2E |
| Widget/controller Gate 5 | **38+ passed** |
| `flutter test test/features/health` | **876 passed + 2 skip** |
| `flutter test` (global) | **1059 passed + 3 skip** |
| `npm --prefix functions run test:health-schedule` | **all passed** |
| `npm --prefix functions run build` | **ok** |
| `flutter analyze` (schedule + main) | **No issues found** |
| `git diff --check` | **ok** (warnings CRLF) |
| Rules / Functions / indexes | **sem diff** |

### APK candidato para teste humano

| Campo | Valor |
|-------|-------|
| Build | `flutter build apk --release` |
| Original | `build/app/outputs/flutter-apk/app-release.apk` |
| Tamanho | **162 614 623 bytes** (~155.1 MB reportados pelo Flutter) |
| mtime | 2026-07-18T00:25:54-03:00 |
| SHA-256 | `393BEBCF1079E32BEB424E7D2E0522FA683F7E91B65A063E64274A6E252A17EA` |
| Cópia Drive | `G:\Meu Drive\K9 Ops\Builds\Health\Gate 5\K9-Ops-Health-Gate5-Candidate-2026-07-18-1564245.apk` |
| Integridade cópia | **SIZE match + SHA-256 match** |
| HEAD base no nome | `1564245` |
| Commit | **não** (working tree Gate 5 local) |

---

## 28. Diff (resumo)

Escopo exclusivo Health schedule presentation + testes + este relatório.

Sem mudanças em:

- Functions  
- Rules  
- indexes  
- contratos wire  
- schema  
- lifecycle engine  

---

## 29. Aprovação humana (APK candidato)

```text
APK candidato testado em dispositivo físico pelo responsável do projeto.

Resultado humano:
APROVADO PARA FECHAMENTO DO GATE 5.
```

---

## 30. Git (fechamento)

| Ação | Status |
|------|--------|
| commit | **sim** — `feat(health): add preventive schedule actions` |
| push | **sim** — `origin/feature/health-v1-foundation` |
| deploy | **não** |

`temp/gate5_ui_e2e_screenshots/` permanece **fora** do Git (transitório).

---

## 31. Riscos residuais

1. **Cancel automático admin**: UI não detecta admin; ação escondida (backend ainda autoriza admin se chamado).  
2. **App Check** debug residual.  
3. Empty: dois pontos de create (surface + CTA) — intencional; densificar só se UX operacional pedir.  
4. `integration_test/` no device wireless: deploy Gradle instável; E2E canônico ficou no host Live+Emulator (mais estável e permanente).  
5. Screenshots em `temp/gate5_ui_e2e_screenshots/` são **transitórias** (não commitar).

---

## 32. Recomendação para auditoria final Gate 6

1. Confronto final read path × write path × Rules × callables × UI matriz.  
2. Decidir se/como expor cancel automático a admin no cliente (sem inventar role).  
3. Opcional: reexecutar `node tools/rules_tests/health_schedule_ui_e2e_emulator_tests.mjs` com Emulators up.

---

## Checklist de conclusão

```text
[x] seletor de tipo visual aprovado (bottom sheet + ícones)
[x] ícones consistentes (Formatters)
[x] Create refinado (hierarquia Título→Tipo→…)
[x] Edit refinado (tipo compacto read-only)
[x] pickers PT-BR (Material localizations)
[x] timezone amigável (Horário de Brasília)
[x] UI create/edit/complete/cancel e2e Emulator
[x] refresh real comprovado (Emulator)
[x] revisão Android (reverse + identidade)
[x] suíte Health verde
[x] suíte global verde
[x] Functions/build verdes
[x] zero produção
[x] harness permanente só E2E gated
[x] APK release gerado
[x] APK copiado ao Google Drive (integridade OK)
[x] Rules/Functions intactas
[x] APK candidato aprovado em dispositivo físico
[x] commit + push Gate 5
```

---

## Declaração

```text
FASE 4E — GATE 5 ENCERRADO, COMMITADO E SINCRONIZADO
```

UI de mutações validada (Create/Edit/Complete/Cancel). Happy path Emulator + APK em dispositivo físico. Nenhuma Function/Rule alterada. Gate 6 não iniciado.
