# Health v1.0 — Fase 3D — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `efeec66b2ea26f335dc2c5f4b59323d974f4518d` |
| commit base | `feat(health): add read-only timeline coexistence` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência inicial | `0/0` |
| working tree inicial | limpo |

Preflight **OK**.

## 2. Referências

- CLAUDE.md, flutter-canil-conventions, canil-k9-context
- HEALTH_V1_PHASE_3A/3B/3C reports + audits
- **HEALTH_V1_PHASE_3D_AUDIT.md** (fonte da verdade pós-auditoria)
- Contratos 3A (`HealthTimelineQuery`, controller, detail reference)
- UI 3B (`HealthTimelineView`, empty, cards)
- Telas reais: `WeightHistoryScreen`, `VaccinationHistoryScreen`, nutrição

## 3. Escopo

### Implementado (pós-auditoria)

- 3D-A filtros (draft/applied, apply no-op, `periodOrigin`, sheet, chips, presets calendário, contextuais idempotentes)
- 3D-B inventário de destinos com kind **relatedHistory** / none
- 3D-C detail resolver tipado + allowlist + type×source mismatch
- 3D-D navigation coordinator (busy seguro)
- 3D-E harness interativo isolado
- testes gates **A–L**
- este relatório + audit

### Fora

- shell / MainRoot / aba Histórico real
- source 3C no app
- busca textual, writes, migration, Functions, índices, rules
- projeção canônica

## 4. 3D-A filtros

Camada `presentation/timeline/filters/`:

- `HealthTimelineFilterSelection` — estado UI sem cursor; inclui `periodOrigin` (metadado visual)
- `HealthTimelineFilterSession` — draft vs applied + apply/clear/contextuais com no-ops
- `HealthTimelinePeriodPresets` — presets com clock injetável; 6m/1a em calendário
- `HealthTimelineFilterSheet` — modal
- `HealthTimelineFilterChipsBar` — chips removíveis

## 5. Modelo draft/applied e apply no-op

| Ação | Efeito |
|------|--------|
| openDraft | draft = cópia defensiva de applied |
| editar draft | **não** altera controller/query |
| cancelDraft | descarta draft |
| clearDraft | limpa draft só (applied intacto até apply) |
| apply | applied = draft; compara `filterIdentity`; **setQuery só se a query mudou** |
| clearApplied | se vazio → **no-op**; senão empty + setQuery |
| remove chip inexistente | **no-op** |
| mesmo caseId / professional | **no-op** (sem reload) |

### Apply semanticamente igual

- `apply()` compara a identidade de filtro da query (`filterIdentity` 3A);
- seleção semanticamente igual **não** dispara `setQuery`;
- `applied` ainda pode refletir metadado visual (ex.: `periodOrigin`) sem recarregar;
- reload ocorre apenas quando a identidade da query realmente muda;
- apply novo (query diferente) reseta cursor via `setQuery` / primeira página.

## 6. Tipos

- Multi-seleção dos `HealthTimelineType` oficiais
- Labels humanas via `HealthTimelineTypeVisuals`
- Vazio = todos os tipos
- Ordem do `Set` irrelevante para equality/query
- Sem opção “Outros” (contrato não representa “todos unknown”)
- Unknown continua na timeline quando sem filtro de tipo

## 7. Períodos

Presets: 7d, 30d, 90d, **6 meses (calendário)**, **1 ano (calendário)**, todo o histórico, personalizado.

### Boundaries (alinhados a 3A; sem mudar o contrato)

| Limite | Semântica |
|--------|-----------|
| **start** | início do dia local, **inclusivo** |
| **end** | fim do dia local **23:59:59.999999**, **inclusivo** |

Custom inválido (`start > end`): feedback humano, não inverte, não aplica.

`now` injetável em session/presets (uma referência por resolve).

### 6 meses / 1 ano

- **6 meses** → aritmética de calendário (`DateTime` month − 6), não 180/183 dias fixos
- **1 ano** → aritmética de calendário (month − 12), não 365 dias fixos
- Cobertura de virada de mês e ano bissexto (ex.: 31/ago; 29/fev)

### periodOrigin (identidade visual)

`HealthTimelineFilterSelection` preserva a **origem visual** do período:

- preset (7d / 30d / 90d / 6m / 1a)
- custom
- all (todo o histórico)

O chip **não** infere preset pela duração.

Exemplo:

| Seleção | Boundaries | Chip |
|---------|------------|------|
| preset 30 dias | janela relativa 30d | `30 DIAS` |
| custom com exatamente 30 dias | mesmas datas possíveis | `PERSONALIZADO` |

Origem visual **não** altera desnecessariamente a identidade da query quando os boundaries são equivalentes (`queryEquals` / `filterIdentity`).

### fromQuery — limitação

Ao reconstruir seleção somente a partir de `HealthTimelineQuery`, a origem visual original **não pode ser provada**.

Período ativo desconhecido → tratado visualmente como **custom**.

Não se re-infere preset pela duração.

## 8. Filtros contextuais

- `applyCaseFilter(caseId)` — mesmo valor → **no-op**
- `applyProfessionalFilter(professional)` — igualdade do contrato 3A → **no-op** se igual

Sem seletor global derivado de `snapshot.items`.

Professional usa contrato 3A (`name` / registration quando existir) — nunca `recordedBy`.  
Não colapsa identidades distintas do contrato (case/whitespace conforme 3A).

## 9. Badge/chips

Contagem semântica: types + period + case + professional (máx. 4; não conta cada tipo).

Chips compactos removíveis; alteração de chip gera nova query + cursor null **somente se** a identidade mudar.

Chip de período usa **periodOrigin**, não heurística de duração.

## 10. Empty filtrado

Copy: *Nenhum registro corresponde aos filtros aplicados.*

Ação: **Limpar filtros** (`onClearFilters`).

Empty geral (sem filtros) permanece o da 3B.

Error/offline **não** se disfarçam de empty filtrado (controller 3A).

## 11. Race handling

Controller 3A generation + session `setQuery`:

- Gate D: A lenta / B rápida → só B
- Gate E: loadMore A + filter B → sem mistura
- refresh/apply com generation protegem o estado final

## 12–13. Inventário / matriz de destinos

### Princípio

# NÃO EXISTE EXACT DETAIL NA V1 LEGADA ATUAL

Os destinos existentes são **históricos relacionados** (`relatedHistory`), não detalhe unitário do registro clicado.

Tocar em uma pesagem **não** significa abrir o detalhe unitário da pesagem; significa abrir o **histórico relacionado de peso**. O mesmo vale para nutrição e vacinação.

### Matriz final

| origem | tipo de destino | target | status |
|--------|-----------------|--------|--------|
| `health_events` | none | — | **unsupported** |
| `weight_records` | relatedHistory | `WeightHistoryTarget` | **resolved** |
| `feeding_events` | relatedHistory | `NutritionHistoryTarget` | **resolved** |
| `feedings` | relatedHistory | `NutritionHistoryTarget` | **resolved** |
| `vacinas` | relatedHistory | `VaccinationHistoryTarget` | **resolved** |
| raw desconhecido | none | — | **unsupported** |
| reference inválida | none | — | **unavailable** |
| type × source mismatch | none | — | **unavailable** |

Exemplos de labels honestas: *Abrir histórico de peso / alimentação / vacinação*.

## 14–17. Resolver / allowlist / targets

`HealthTimelineDetailResolver` (puro; sem BuildContext / Navigator / Firestore / import da source 3C data):

- allowlist explícita (constantes locais)
- **única fonte de verdade:** `isNavigable` ⇔ `resolveEntry` retorna `Resolved`
- targets finais: `WeightHistoryTarget`, `NutritionHistoryTarget`, `VaccinationHistoryTarget`
- `kind: relatedHistory` + `navigationActionLabel` honesta
- type×source mismatch → `unavailable` (ex.: type=weight + sourceType=vacinas)

Não existem dois mapas independentes de support (widget vs resolver).

## 18–19. Coordinator / double navigation

`HealthTimelineNavigationCoordinator`:

| Comportamento | Detalhe |
|---------------|---------|
| `_busy = true` | no **início** da operação |
| proteção | **try/finally** em todos os ramos |
| resolved | no máximo 1 callback de navegação |
| unsupported | 0 callbacks; busy liberado |
| unavailable | feedback humano (**sem** “detalhes completos” enganosos; sem raw sourceType/docId) |
| falha sync/async no navigate | busy liberado |
| falha no feedback unavailable | absorvida; busy liberado |
| double tap enquanto busy | máximo **uma** navegação |
| após conclusão/falha | aceita novo tap |

## 20. Harness

`HealthTimelineInteractiveHost`:

TimelineView + FilterSession + chips + sheet + coordinator + callbacks.

Sem MainRoot / Firestore / wiring real.

## 21–22. Acessibilidade / responsividade

- Semantics em filtros, chips, datas, aplicar/limpar
- Teste estrutural 360px sem overflow
- Risco residual: card 3B ainda não anuncia plenamente `navigationActionLabel` do target (não bloqueante; 3E)

## 23. Arquivos criados

```text
lib/features/health/presentation/timeline/filters/*
lib/features/health/presentation/timeline/detail/*
lib/features/health/presentation/timeline/health_timeline_interactive_host.dart
test/features/health/presentation/timeline/health_timeline_filters_3d_test.dart
test/features/health/presentation/timeline/health_timeline_detail_3d_test.dart
test/features/health/presentation/timeline/health_timeline_3d_harness_test.dart
docs/health/HEALTH_V1_PHASE_3D_REPORT.md
docs/health/HEALTH_V1_PHASE_3D_AUDIT.md
```

## 24. Arquivos modificados (mínimos 3B)

- `health_timeline_view.dart` — `onClearFilters`, `entryNavigable` (opcionais)
- `health_timeline_status_views.dart` — empty filtrado com limpar
- `health_timeline_user_copy.dart` — copy empty filtrado + clearFilters

### Regressão 3B (confirmada na auditoria)

- parâmetros 3D opcionais
- sem 3D → comportamento anterior preservado
- empty geral preservado
- filtered empty separado
- card sem destino não fica falsamente navegável
- **não** classificado como regressão

3A/3C: **inalterados**.

## 25. Testes

| Gate | Descrição | Resultado |
|------|-----------|-----------|
| A | Draft não altera query | **PASS** |
| B | Apply novo reseta cursor | **PASS** |
| B2 | Apply semanticamente igual = no-op | **PASS** |
| C | Clear correto/idempotente | **PASS** |
| D | Race A/B (generation) | **PASS** |
| E | LoadMore + filter sem mistura | **PASS** |
| F | Empty filtrado vs geral | **PASS** |
| G | Resolver allowlist | **PASS** |
| G2 | Navigability == resolution | **PASS** |
| H | Reference inválida / type-source mismatch | **PASS** |
| I | Double tap / failure recovery do busy | **PASS** |
| J | Harness completo | **PASS** |
| K | Custom mantém identidade visual própria | **PASS** |
| L | Regressão 3B defaults | **PASS** |

**38 passed** nos arquivos 3D dedicados (pós-auditoria).

## 26. Validações (pós-auditoria + revalidação)

| Check | Resultado |
|-------|-----------|
| format 3D | OK |
| analyze timeline presentation | **No issues found** |
| testes 3D dedicados | **38 passed** |
| presentation timeline | **217 passed** |
| health | **634 passed** |
| global | **817 passed, 1 skipped** |
| analyze global | preexistentes; **0** novos da 3D |
| git diff --check | OK |

## 27. Escopo negativo

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | MainRoot alterado? | **não** |
| 2 | Shell alterado? | **não** |
| 3 | Source 3C no app real? | **não** |
| 4–9 | Firestore/write/migration/Function/índice/rules | **não** |
| 10 | Busca textual? | **não** |
| 11 | Edição registro? | **não** |
| 12 | Projeção canônica? | **não** |
| 13 | Alteração 3A? | **não** |
| 14 | Alteração 3B? | **mínima** (clear + navigable; sem regressão) |
| 15 | Alteração 3C? | **não** |

## 28. Riscos residuais

1. Semantics do card 3B ainda não usam plenamente `navigationActionLabel` do destino (**não bloqueante**; pendência 3E).
2. Destinos `relatedHistory` não focam o `sourceId` específico na tela aberta.
3. Reconstrução via `fromQuery` não recupera a origem visual original do período (trata como custom).
4. Wiring real (shell, Dog, rotas) fica para 3E.

Riscos **já corrigidos** (não vigentes): heurística de período por duração; apply reload sempre; targets `*Detail*` enganosos; busy inseguro.

## 29. Pendências 3E

- Wiring da aba Histórico real / MainRoot
- Instanciação real da source 3C
- Integração do host/interação 3D
- Callbacks reais para relatedHistory (com Dog real)
- Semantics contextual de navegação (`navigationActionLabel` no card)
- Validação runtime autenticada (offline/error/pagination/filter/navigation em dispositivo)

## 30. Estado git

HEAD base: `efeec66…`. Working tree com 3D **não commitado**.

## 31. Conclusão

A 3D entrega interação de filtros e navegação contextual isolada do shell, com:

- apply no-op e no-ops idempotentes;
- `periodOrigin` honesto (custom ≠ preset visual);
- destinos **relatedHistory** (sem exact detail legado);
- navigability ⇔ resolver (fonte única);
- coordinator com busy seguro;
- gates A–L e revalidação completa.

Aprovação ocorre **após** auditoria técnica e UX adversarial, correções aplicadas e revalidação.

Classificação final:

# APROVADA PARA COMMIT

Ver `HEALTH_V1_PHASE_3D_AUDIT.md`.
