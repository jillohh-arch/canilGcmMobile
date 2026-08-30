# Health v1.0 — Fase 3E-B — Relatório (Integração controlada)

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `a1afa1213d7e174372674763aed56d09e69fcd06` |
| commit | `feat(health): add timeline filters and navigation` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree início esperado | só 3E-A |
| working tree **final** | **3E-A + 3E-B** (para auditoria integrada) |

Sem reset / stash / discard / commit / push.

## 2. Estado herdado da 3E-A

Preservado integralmente no working tree:

- `HealthTimelineScreen`, quick chips, footer institucional
- FilterSession APIs (`applyQuickType` / `applyQuickAllTypes`)
- labels, entry card navigation labels
- `HEALTH_V1_PHASE_3E_A_REPORT.md` + testes 3E-A

3E-B **não** reescreveu controller, source, resolver ou shell.

## 3. Fluxo real antes da integração

```text
MainRootScreen (aba Saúde, dogId do binômio)
  └─ shouldUseHealthV1SummaryEntry()?
       true  → HealthV1EntryScreen(key: health-v1-$dogId)
       false → DogHealthProntuarioScreen (rollback)
            └─ HealthShellScreen
                 ├─ resumo → HealthSummaryDashboard + SummaryController
                 ├─ historico → placeholder (antes da 3E-B)
                 ├─ agenda → placeholder
                 └─ nutricao → placeholder
```

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | Dog atual | MainRoot / DogViewModel; Entry recebe `dogId` |
| 2 | Cria HealthShell | `HealthV1EntryScreen` |
| 3 | Summary deps | Controller no Entry; dogContext via DogViewModel |
| 4 | Slots | Builders obrigatórios; IndexedStack lazy por visita |
| 5 | Preserva entre abas | **Sim** (seções visitadas montadas) |
| 6 | Destruição | Saída do Entry (key MainRoot ou dispose) |
| 7 | Composition root Timeline | **`HealthV1EntryScreen`** |

## 4. Composition root escolhido

**`HealthV1EntryScreen`** — mesmo owner do Summary (2E).

- Source / controller / session criados em `initState` (não em `build`)
- First load **lazy** no primeiro `onSectionChanged(historico)`
- Dispose único no `dispose` do Entry

## 5. Ownership / lifecycle

| Objeto | Cria | Dispose |
|--------|------|---------|
| `CoexistenceHealthTimelineSource` | Entry init (`forFirestore` ou inject) | n/a (one-shot) |
| `HealthTimelineController` | Entry init | Entry dispose |
| `HealthTimelineFilterSession` | Entry init | Entry dispose |
| `HealthTimelineDetailResolver` | estático 3D | — |
| `HealthTimelineNavigationCoordinator` | State da Screen | com a Screen |

## 6. Source 3C real

```dart
CoexistenceHealthTimelineSourceFactory.forFirestore()
// enableVaccinationFallback: false (default)
```

Somente no composition root. Nunca em widget visual. Nunca por rebuild.

## 7. Política vacinação fallback

**Default conservador 3C:** `enableVaccinationFallback: false`.

Não ativado na 3E-B. Sem evidência runtime para mudar política.

## 8. Dog real

- Produção: `dogId` do MainRoot + nome via `DogViewModel` / `HealthSummaryDogContextMapper`
- Sem Bono hardcoded em produção
- Subtítulo: `Linha do tempo da saúde de {dogContext.name}`
- Fallback catálogo ausente: `"K9"` / `"Carregando…"` (não Bono)

## 9. Dog change

| Caminho | Comportamento |
|---------|----------------|
| MainRoot key `health-v1-$dogId` | Entry recriado (lifecycle limpo) |
| `didUpdateWidget` dogId | `updateDogId` + `selectDog` se primed |
| Generation 3A | respostas tardias de A ignoradas em B |

## 10. First load

**Lazy** na primeira visita ao Histórico.

- 0 queries se Histórico nunca aberto
- 1 carga inicial no prime
- Retorno à aba **não** re-prime

## 11. Preservação entre abas

Durante a vida do Entry/Shell:

- controller + session + filtros + itens permanecem
- IndexedStack mantém seções visitadas
- sem reload completo em cada troca Resumo↔Histórico

## 12. HealthShell wiring

```dart
historico: (_) => HealthTimelineScreen(
  controller: _timelineController,
  filterSession: _filterSession,
  dogDisplayName: dogContext.name,
  bottomPadding: MainRootNavMetrics.scrollBottomClearance(...),
  onNavigate: _onTimelineNavigate,
)
```

Sem shell paralelo. Sem bottom nav extra. Agenda/Nutrição placeholders intactos.

## 13. Bottom padding / FAB

`MainRootNavMetrics.scrollBottomClearance` (bar 76 + system inset + FAB breathing 28).

FAB global do MainRoot permanece; clearance evita cobrir Load More / último card / footer.

Footer institucional no **fim do scroll** (não fixo fora — viewport curto no shell).

## 14. FilterSession real

Única fonte de verdade. Quick + modal + clear → `setQuery` no controller.

Sem `_stateSelectedTypes` paralelo no shell.

## 15–17. Navegação

| Target | Tela real |
|--------|-----------|
| `WeightHistoryTarget` | `WeightHistoryScreen(dog:)` |
| `NutritionHistoryTarget` | `NutritionFullScreen(dog:)` |
| `VaccinationHistoryTarget` | `VaccinationHistoryScreen(dog:)` |

- relatedHistory (não exact detail)
- `sourceId` não foca registro unitário
- Dog resolvido por **`target.dogId`** (não closure stale)

## 18. Unsupported health_events

Sem navegação. Allowlist 3D intacta.

## 19. Error / offline / unmappable

- UI usa estados 3A/3B (`Error` / `Offline` / inconclusivo via source)
- Sem SnackBar técnico / FirebaseException na presentation
- Offline **não** vira empty
- Refresh/loadMore: comportamento 3A preservado

## 20. Summary coexistence

Resumo→Histórico→Resumo: dashboard e controllers intactos; timeline controller idêntico.

## 21. Arquivos criados (3E-B)

- `test/.../health_timeline_3e_b_test.dart`
- `docs/health/HEALTH_V1_PHASE_3E_B_REPORT.md`

## 22. Arquivos modificados (3E-B)

- `lib/.../screens/health_v1_entry_screen.dart`
- `lib/.../timeline/health_timeline_screen.dart` (expand + footer no scroll)
- `test/.../health_v1_entry_screen_test.dart`
- `test/.../health_timeline_3e_a_test.dart` (footer scroll)

(+ 3E-A intacta no mesmo tree)

## 23. Testes

Gates formais em `health_timeline_3e_b_test.dart` + entry tests.

## 24. Gates A–L

| Gate | Resultado |
|------|-----------|
| A Composition singleton | **PASS** |
| B First load único (lazy) | **PASS** |
| C Estado entre abas | **PASS** |
| D Dog change | **PASS** |
| E Filters reais | **PASS** |
| F Navegação real | **PASS** |
| G Unsupported | **PASS** |
| H Dispose async | **PASS** |
| I Failure error/offline | **PASS** |
| J Pagination | **PASS** |
| K Race filter | **PASS** |
| L Shell coexistence | **PASS** |
| Bottom padding metrics | **PASS** |
| Dog change + nav B | **PASS** |

## 25. Validações

| Check | Resultado |
|-------|-----------|
| dart format (dart 3E-A/B) | **OK** (0 changed) |
| flutter analyze (entry + timeline) | **No issues found** |
| 3E-A + 3E-B + entry | **37 passed** |
| timeline suite | **241 passed** |
| health suite | **663 passed** |
| global `flutter test` | **846 passed, 1 skipped** |
| analyze global | **40 issues** — todos **preexistentes** (nenhum em entry/timeline 3E-B) |
| build debug APK arm64 | **✓ Built** `app-debug.apk` (exit 1 PowerShell residual conhecido) |
| git diff --check | OK (só avisos CRLF) |
| commit | **não** |

## 26. Escopo negativo

| # | Resposta |
|---|----------|
| 1 Source 3C real | **sim** |
| 2 HealthShell Histórico | **sim** |
| 3 MainRoot alterado | **não** (já usava Entry) |
| 4 Write | **não** |
| 5 Migration | **não** |
| 6 Function | **não** |
| 7 Índice | **não** |
| 8 Rules | **não** |
| 9 Busca | **não** |
| 10 KPI Histórico | **não** |
| 11 Agenda | **não** |
| 12 Nutrição redesign | **não** |
| 13 Summary funcional | **não** |
| 14 Projeção canônica | **não** |
| 15 APK/runtime | **não** |

## 27. Riscos

1. Runtime Firestore autenticado / índices / offline real ainda não validados em dispositivo  
2. Telas destino legadas dependem de providers do MainRoot  
3. Footer no scroll (vs fixo) — trade-off de viewport  

## 28. Pendências 3E-C

- Runtime autenticado / paginação real / offline real  
- Eventual ajuste fine de padding em device  
- Auditoria de integração formal / possível commit 3E-A+3E-B  

## 29. Estado git

HEAD `a1afa12`. Working tree: **3E-A + 3E-B** uncommitted. Tracking `0/0`.

## 30. Conclusão

# PRONTA PARA AUDITORIA DE INTEGRAÇÃO

A aba Histórico real possui source, controller, FilterSession e navegação no ciclo de vida do Health, sem redesign, write ou arquitetura nova.
