# Health v1.0 — Fase 3E-A — Relatório

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `a1afa1213d7e174372674763aed56d09e69fcd06` |
| commit | `feat(health): add timeline filters and navigation` |
| tracking | `0/0` |
| working tree inicial | limpo |

Preflight **OK**.

## 2–3. Mockup analisado

**Caminho exato:**

`docs/health/mockups/historico clinico.png`

Referência visual e de UX (não especificação funcional absoluta).

## 4. Princípio de reconciliação

Arquitetura validada (3A–3D) + dados reais + semântica honesta + UX operacional  
**prevalecem** sobre reprodução literal do mockup.

## 5. Matriz mockup × implementação

| Elemento do mockup | Estado atual | Decisão v1 | Justificativa |
|--------------------|--------------|------------|---------------|
| Título/subtítulo HISTÓRICO CLÍNICO | 3B | **manter** | Alinhado |
| Botão Filtros | 3B/3D | **manter** | Abre FilterSheet 3D |
| Chips rápidos de categoria | ausente → **implementado** | adaptado | Usa FilterSession (types only) |
| KPIs (Consultas/Vacinas/Peso/Alertas) | — | **não implementar** | Pertencem ao Resumo |
| Busca textual | — | **não implementar (v2+)** | Fora do contrato v1 |
| Timeline/rail/cards | 3B | **manter/refinar** | Densidade preservada |
| Chevrons universais | 3B/3D | **adaptado** | Só se `isNavigable` |
| Related history | 3D | **honesto** | Semantics “Abrir histórico…” |
| Bloco institucional | ausente → **implementado** | adaptado | Só se `!hasMore` |
| Bottom navigation / header app | shell | **shell real** | Sem segundo shell |

## 6–9. Elementos

### Mantidos
- Título/subtítulo; Filtros; timeline rail; load more; empty/error/offline; apply no-op 3D.

### Adaptados
- Chips rápidos → FilterSession; chevrons → navigable only; relatedHistory semantics; footer institucional; single-type chip avançado suprimido se redundante.

### Removidos da v1 nesta tela
- KPIs do Histórico; busca textual; chevron universal; “detalhe unitário” falso.

### Adiados
- Busca v2+; KPIs agregados confiáveis; wiring MainRoot/source 3C (3E-B); focus de sourceId nas telas related.

## 10–12. Cabeçalho / quick filters / 3D

- Cabeçalho 3B: `HISTÓRICO CLÍNICO` + subtítulo com `dogDisplayName`.
- Quick chips: Todos, Nutrição, Consultas, Vacinas, Pesagens, Exames, Medicamentos, Intercorrências, Documentos.
- `applyQuickType` / `applyQuickAllTypes` — só `types`; preserva period/case/professional.
- Multi-type avançado → faixa rápida em estado neutro (sem chip único falso).
- Modal 3D intacto.

## 13–16. Timeline / cards / nav

- Timeline 3B preservada.
- Cards: metadata real apenas; chevron se navegável.
- Semantics: `navigationActionLabel` (ex. “Abrir histórico de peso”).
- Unsupported: sem tap/chevron/button.

## 17–18. Bloco institucional / safe area

- Copy: rastreabilidade de origem (+ nome do K9).
- Exibido na `HealthTimelineScreen` quando `Data && !hasMore && items.isNotEmpty`.
- Ordem: lista → load more → footer.
- `bottomPadding` injetável para bottom nav/FAB (3E-B).

## 19–20. Responsividade / a11y

- Quick chips em ListView horizontal; 360 testado.
- Semantics em chips, filtros, cards, footer.

## 21. Tela real preparada

`HealthTimelineScreen`:

- controller + filterSession **injetados** (ownership externo);
- sem Firestore em presentation;
- `onNavigate(HealthTimelineDetailTarget)`;
- pronta para slot `historico:` do `HealthShellScreen` na 3E-B.

`HealthTimelineInteractiveHost` reexporta a mesma composição (compat harness 3D).

## 22–23. Arquivos

### Criados
- `filters/health_timeline_quick_type_chips.dart`
- `widgets/health_timeline_institutional_footer.dart`
- `health_timeline_screen.dart`
- `test/.../health_timeline_3e_a_test.dart`
- `docs/health/HEALTH_V1_PHASE_3E_A_REPORT.md`

### Modificados
- `filter_session.dart` — quick type APIs
- `filter_labels.dart` — suppress single-type chip redundante
- `health_timeline_view.dart` — footer opcional / navigation label
- `entry_card.dart` / `day_section.dart` — navigationActionLabel
- `user_copy.dart` — institutional copy
- `interactive_host.dart` — delega à Screen

## 24–25. Testes e gates

| Gate | Resultado |
|------|-----------|
| A quick type único | **PASS** |
| B Todos preserva period | **PASS** |
| C multi-type neutro | **PASS** |
| D related semantics | **PASS** |
| E unsupported | **PASS** |
| F footer !hasMore | **PASS** |
| G sem busca | **PASS** |
| H sem KPI | **PASS** |
| I 3D não regrediu | **PASS** (suite 3D) |
| J 360 | **PASS** |

## 26. Validações

| Check | Resultado |
|-------|-----------|
| analyze timeline/3E-A | **No issues found** |
| timeline presentation | **224 passed** |
| health | **641 passed** |
| global | **824 passed, 1 skipped** |
| git diff --check | OK |

## 27. Escopo negativo

| # | Resposta |
|---|----------|
| 1–2 MainRoot / app root | **não** |
| 3–4 Source 3C / Firestore timeline | **não** |
| 5–9 write/migration/Function/índice/rules | **não** |
| 10 Busca textual | **não** |
| 11 KPIs Histórico | **não** |
| 12 Projeção canônica | **não** |
| 13 Redesign amplo | **não** |
| 14–15 3A / 3C | **não** |

## 28. Riscos

1. Footer fora do ListView (sempre visível no fim da aba) — se hasMore, some; com lista longa o usuário vê footer só após scroll + fim.
2. Shell padding real (FAB/bottom nav) validado na 3E-B.
3. relatedHistory ainda não foca sourceId na tela destino.

## 29. Pendências 3E-B

- Wiring `historico:` no HealthShell + MainRoot se necessário
- Instanciar source 3C + lifecycle dispose
- Callbacks Dog reais
- Runtime autenticado / offline / paginação real

## 30. Estado git

HEAD base `a1afa12…`. Working tree 3E-A **não commitado**.

## 31. Conclusão

# PRONTA PARA REVISÃO VISUAL

A tela Histórico reconcilia o mockup `historico clinico.png` com a arquitetura 3A–3D: chips rápidos reais, sem busca/KPIs, navegação relatedHistory honesta, footer institucional no fim da paginação, composição pronta para o shell.
