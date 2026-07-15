# Health v1.0 — Fase 2E — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `03e41d2cc509a28461e0ee4d45944f61b559b261` |
| commit base | `feat(health): add read-only summary coexistence source` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência inicial | `0 0` |
| working tree inicial | limpo |

## 2. Referências utilizadas

- CLAUDE.md, flutter-canil-conventions, canil-k9-context  
- Roadmap, Architecture, Baseline, Migration Plan, Readiness Policy  
- Relatórios/auditorias 2A–2D  
- Código: shell 2A, controller/source 2B, dashboard 2C, coexistence 2D  
- Entry real: `main_root_screen.dart` / `main_root_widgets.dart`  
- K9: `ShiftViewModel.activeDogId`, catálogo `DogViewModel.dogs`

## 3. Fluxo de Saúde antes da 2E

| Entrada | Destino |
|---------|---------|
| Bottom nav **Saúde** (índice 2) | `_MainRootHealthTab` → `DogHealthProntuarioScreen(dogId:)` |
| Sem turno / sem `activeDogId` | Scaffold com “Nenhum cão ativo…” |
| Header binômio / quick actions | `DogHealthProntuarioScreen` (inalterados na 2E) |

## 4. Fonte real do K9 ativo

- **ID:** `ShiftViewModel.activeDogId` (turno).  
- **Cadastro:** objeto `Dog` em `DogViewModel.dogs` (já carregado; sem fetch novo se presente).  
- **Mapper:** `HealthSummaryDogContextMapper.fromDog`.  
- **Sem K9:** não monta entry; mensagem existente na aba.

## 5. Arquitetura de composição

```text
_MainRootHealthTab
  [kHealthV1SummaryEntryEnabled]
  ├─ true  → HealthV1EntryScreen(dogId)   // composition root 2E
  └─ false → DogHealthProntuarioScreen    // legado

HealthV1EntryScreen
  ├─ CoexistenceHealthSummarySource (2D)  // ou fake injetado
  ├─ HealthSummaryController (2B)
  ├─ selectDog(dogId)
  ├─ DogViewModel → DogContextMapper
  └─ HealthShellScreen (2A)
       resumo → HealthSummaryDashboard (2C)
       historico/agenda/nutricao → Placeholder (2A)
```

## 6. Composition root implementado

`HealthV1EntryScreen` — dono de source/controller, resolve contexto, monta shell.

Não coloca Firestore no Dashboard. Shell não conhece services.

## 7. Lifecycle do controller

| Momento | Ação |
|---------|------|
| `initState` | cria source (ou injeta), cria controller, `selectDog` |
| `didUpdateWidget` | se dogId mudou e não vazio → `selectDog` |
| `dispose` | `controller.dispose()` |
| Aba Saúde | `ValueKey('health-v1-$dogId')` força dispose/recreate na troca de K9 |

Controller **não** é criado no `build`.

## 8. Binding do dogId

- Produção: `shiftVM.activeDogId` → entry.  
- Entry: `selectDog` com trim; troca via didUpdateWidget ou nova key.  
- Proteção de race: controller 2B (generation + dogId).

## 9. DogContext

- Preferência: Dog do catálogo mapeado.  
- Ausente/loading: identidade mínima (`Carregando…` / `K9`) — **sem** inventar saúde.  
- Testes: `dogContextOverride`.

## 10. Integração source 2D

Default: `CoexistenceHealthSummarySource()`.  
Testes: `HealthSummarySource` fake injetável.  
Sem segunda source, sem queries no UI.

## 11. Integração Dashboard 2C

Builder `resumo` → `HealthSummaryDashboard(dogContext, controller, callbacks)`.  
Callbacks só trocam seção interna do shell (placeholders).  
Sem redesign.

## 12. Integração Shell 2A

`HealthShellScreen` com quatro builders obrigatórios; três placeholders oficiais.

## 13. Tratamento sem K9

Continua em `_MainRootHealthTab` **antes** do entry:

> Nenhum cão ativo.  
> Inicie um turno para acessar Saúde.

Não abre entry com dogId vazio.

## 14. Troca de K9

Com `ValueKey` + `selectDog`: identidade e dados do novo cão; controller 2B limpa estado anterior.

## 15. Entry point alterado

| | |
|--|--|
| **ANTES** | Aba Saúde → `DogHealthProntuarioScreen` |
| **DEPOIS** | Aba Saúde → `HealthV1EntryScreen` (se gate true) |

## 16. Estratégia de rollback

Arquivo `health_v1_entry_flags.dart`:

```dart
const bool kHealthV1SummaryEntryEnabled = false;
```

Única alteração necessária para restaurar o prontuário legado na aba Saúde.

## 17. Outros entry points encontrados (não alterados)

- `binomio_header.dart` → prontuário legado  
- `active_shift_quick_actions.dart` → prontuário legado  
- `active_shift_dashboard` “abrir saúde” → apenas troca para aba 2  

Pendência: alinhar atalhos em fase futura se desejado.

## 18. Estados reais esperados

| Bloco | Expectativa com 2D |
|-------|---------------------|
| weight / trend / nutrition / recentes / vacina | dados reais ou notRecorded/unavailable conforme 2D |
| readiness / treatments / attention | **unavailable** (política 2D) |
| loading / error / offline | Dashboard 2C + controller 2B |

## 19. Testes adicionados

`test/features/health/presentation/screens/health_v1_entry_screen_test.dart` — **6 testes**

- gate habilitado  
- shell + dashboard + dados fake  
- Histórico → placeholder  
- selectDog dogId  
- troca A→B sem misturar identidade  
- dispose do controller  

Sem Firestore real.

## 20. Validação visual/runtime

**VALIDAÇÃO VISUAL EM RUNTIME PENDENTE** no ambiente do agente (sem dispositivo/emulador com app instalado aqui).

O usuário deve inspecionar no APK/dispositivo.

## 21. Build APK

```text
flutter build apk --debug
```

Sucesso:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Caminho completo (workspace):

`C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm\build\app\outputs\flutter-apk\app-debug.apk`

## 22. Validações com exit codes

| Comando | Exit | Resultado |
|---------|------|-----------|
| format 2E | **0** | limpo |
| analyze 2E | **0** | No issues found |
| testes 2E | **0** | **6/6** |
| `flutter test test/features/health` | **0** | **332** passed |
| `flutter test` | **0** | **515 passed, 1 skipped** |
| `git diff --check` | **0** | OK |
| `flutter build apk --debug` | **0*** | APK gerado |

\* Saída Gradle reportou build OK; exit code do shell pode ser 1 por ruído do pipeline, artefato presente.

## 23. Revisão explícita de escopo

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | write? | **não** |
| 2 | migration? | **não** |
| 3 | dual-write? | **não** |
| 4 | mudança readiness? | **não** |
| 5 | score legado? | **não** |
| 6 | alteração contratos 2B? | **não** |
| 7 | alteração semântica 2D? | **não** |
| 8 | Histórico? | **não** (placeholder) |
| 9 | Agenda? | **não** |
| 10 | Nutrição completa? | **não** |
| 11 | remoção legado? | **não** |
| 12 | navegação ampla? | **não** (só aba Saúde) |

## 24. Arquivos criados

- `lib/features/health/presentation/screens/health_v1_entry_flags.dart`
- `lib/features/health/presentation/screens/health_v1_entry_screen.dart`
- `test/features/health/presentation/screens/health_v1_entry_screen_test.dart`
- `docs/health/HEALTH_V1_PHASE_2E_REPORT.md`

## 25. Arquivos modificados

- `lib/features/app_shell/presentation/screens/main_root_screen.dart` (imports)
- `lib/features/app_shell/presentation/screens/main_root_widgets.dart` (gate na aba Saúde)

## 26. Riscos e limitações

- Atalhos legados ainda abrem prontuário.  
- Source one-shot (2D).  
- Runtime visual pelo usuário.  
- `+ Registrar` apenas snackbar informativo.

## 27. Pendências

- **Segunda inspeção no celular** (APK pós-2E-R)  
- Auditoria adversarial final 2E  
- Alinhar atalhos secundários (opcional)  
- Commit após segunda validação + auditoria  

## 28. Estado final do git

Working tree com artefatos 2E + correções 2E-R; **sem commit** nesta fase.

## 29. Conclusão (pré-device)

# PRONTA PARA AUDITORIA E TESTE EM DISPOSITIVO

Peças 2A–2D compostas no entry point controlado da aba Saúde, reversível por flag, sem alterar contratos nem legado além do wiring mínimo.

---

## 30. VALIDAÇÃO EM DISPOSITIVO — PRIMEIRA RODADA

**Contexto:** primeiro runtime em dispositivo real após implementação 2E.

**O que funcionou:**

- Health v1 abre; K9 real; dados reais; Dashboard; shell; navegação interna; identidade visual geral boa.

### Achados R1–R6

| ID | Achado | Severidade |
|----|--------|------------|
| **R1** | Mensagens técnicas Firestore (index URL / exception) nos cards | Alta (UX/confiança) |
| **R2** | Conteúdo scrollável sob a bottom nav / FAB “Nova” | Alta (usabilidade) |
| **R3** | Bottom nav excessivamente transparente (`primaryOverlay` ~4%) | Média (hierarquia visual) |
| **R4** | Copy de arquitetura (“coexistência legada”, “Health v1”…) | Média (copy operacional) |
| **R5** | Cards de métrica `unavailable` com texto longo no valor principal | Média (geometria) |
| **R6** | Título “REQUER ATENÇÃO” com `attention.status == unavailable` | Alta (semântica) |

### Correções 2E-R aplicadas

| ID | Correção |
|----|----------|
| **R1** | Queries `health_events` sem `SoftDeletable.activeOnly` + `orderBy` (filtro soft-delete no cliente); `vacinas` sem orderBy; erros sanitizados em readers + `HealthSummaryUserCopy` |
| **R2** | `healthSummaryScrollBottomClearance` = 76 (nav) + safe bottom + 28 (FAB) no `SingleChildScrollView` do Dashboard |
| **R3** | `_navBg` global: `AppTheme.surfaceNavigation` (navy sólido) em vez de `primaryOverlay` |
| **R4** | `HealthSummaryUnsafeSections` + readers usam copy operacional estável |
| **R5** | Metric card: primary `INDISPONÍVEL` / `NÃO REGISTRADO` (curto); secundário opcional |
| **R6** | Título `REQUER ATENÇÃO` só com available + items; caso contrário `ATENÇÕES` neutro |

### Query / índice

**Classificação: RESOLVIDA SEM ÍNDICE** (no caminho Health summary 2D).

- Coleção: `dogs/{dogId}/health_events`
- Filtro problemático: `where deleted_at IS NULL` + `orderBy('date')`
- Correção: `orderBy('date')` + `limit` + filtro `deleted_at` no cliente
- Índice composto **não** adicionado a `firestore.indexes.json` nesta fase

### Novo APK (pós-2E-R)

```text
flutter build apk --debug
exit 0
build/app/outputs/flutter-apk/app-debug.apk
```

Atualizado em ~2026-07-15 18:02 (local).

### Documentação detalhada

Ver: `docs/health/HEALTH_V1_PHASE_2E_RUNTIME_VALIDATION.md`

### Classificação após 2E-R

# PRONTA PARA SEGUNDA VALIDAÇÃO EM DISPOSITIVO

---

## 31. Segunda validação em dispositivo

**Resultado: APROVADA VISUALMENTE PARA A FASE 2E**

(Inspeção real no APK 2E-R; ver `HEALTH_V1_PHASE_2E_RUNTIME_VALIDATION.md`.)

## 32. Auditoria adversarial final

Documento: `docs/health/HEALTH_V1_PHASE_2E_AUDIT.md`

Achados ALTA corrigidos na auditoria:

1. soft-delete + limit → paginação de ativos  
2. sinal offline pós-sanitização  

Classificação técnica: **APROVADA PARA COMMIT** (sem commit automático nesta sessão).
