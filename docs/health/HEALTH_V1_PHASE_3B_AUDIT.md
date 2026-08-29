# Health v1.0 — Fase 3B — Auditoria Técnica e Visual Adversarial

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `476bcc65abf76af69661315faceea9efc0993af4` |
| commit base | `feat(health): add timeline foundation and contracts` |
| tracking | `origin/feature/health-v1-foundation` · **0/0** |
| working tree | somente arquivos da Fase 3B (não commitados) |

Preflight **OK**.

## 2. Arquivos auditados

### Produção (3B)

- `lib/features/health/presentation/timeline/widgets/*` (10 arquivos)

### Testes 3B

- `health_timeline_view_test.dart`
- `health_timeline_visual_harness_test.dart`
- `health_timeline_adversarial_3b_test.dart` (**adicionado na auditoria**)

### Referências consultadas

- contratos 3A (state/controller/grouping/entry)
- Domain Model §5 `OperationalImpact` / `OperationalImpactLevel`
- mockup `historico clinico.png` (estrutural)
- padrões 2C (banner/card/skeleton)

## 3. Metodologia

1. Leitura integral dos widgets e testes 3B.
2. Ataque de copy/sanitização com payloads técnicos.
3. Revisão de impact, cancelled, unknown, 14 tipos.
4. Revisão de lazy rendering / IntrinsicHeight / refresh×loadMore.
5. Revisão de a11y, filtros edge, datas/timezone.
6. Correções no escopo 3B + testes de regressão.
7. Validação format/analyze/test.

## 4. Achados

### A1 — ListView eager (não lazy) · **ALTA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | `_DataList` usava `ListView(children: [...])` montando todos os slots de uma vez |
| Cenário | 50–100 itens paginados na UI |
| Impacto | Custo de build/layout linear desnecessário; risco de jank |
| Arquivo | `health_timeline_view.dart` |
| Correção | `ListView.builder` + slots flat (`_TimelineSlot`) |
| Teste | adversarial “100 entries” + “ListView.builder presente” |

### A2 — IntrinsicHeight por entrada · **ALTA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | Cada card forçava multi-pass de layout via `IntrinsicHeight` |
| Cenário | Lista longa com altura variável |
| Impacto | Custo O(n) caro por item |
| Arquivo | `health_timeline_day_section.dart`, `health_timeline_marker.dart` |
| Correção | `Stack` + `CustomPaint(HealthTimelineRailPainter)` dimensionado pela altura do card |
| Teste | 100 entries sem exception; harness visual |

### A3 — Load more visível durante refresh · **MÉDIA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | Com `isRefreshing`, UI ainda podia mostrar **CARREGAR MAIS** (controller já no-op) |
| Cenário | Refresh em andamento com `hasMore` |
| Impacto | Aparência contraditória |
| Arquivo | `health_timeline_view.dart` |
| Correção | Durante refresh: esconde load more, progress e erro local de paginação |
| Teste | “durante refresh não mostra CARREGAR MAIS” |

### A4 — Banner de refresh vs nova tentativa · **MÉDIA** · CORRIGIDO (UI)

| Campo | Detalhe |
|-------|---------|
| Problema | Potencial coexistência visual de erro antigo + barra de refresh |
| Cenário | `lastRefreshError` + `isRefreshing` |
| Impacto | Copy confuso |
| Nota 3A | Controller já limpa `lastRefreshError` ao iniciar refresh |
| Correção UI | Banner só se `hasRefreshFailure && !isRefreshing` |
| Teste | refresh em andamento / banner com falha |

### A5 — Sanitização incompleta · **MÉDIA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | `firestore.googleapis.com` (sem `https://`), paths `dogs/`, `.dart`, multiline não cobertos |
| Impacto | Risco de vazamento técnico em error global |
| Arquivo | `health_timeline_user_copy.dart` |
| Correção | Ampliar padrões; adversarial hostil |
| Teste | grupo sanitização hostil |

### A6 — Opacity global em cancelled · **MÉDIA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | `Opacity(0.62)` no card inteiro reduzia contraste do chip CANCELADO e metadata |
| Impacto | A11y / legibilidade |
| Arquivo | `health_timeline_entry_card.dart` |
| Correção | Remover Opacity; muting seletivo por cor; chip com contraste pleno |
| Teste | cancelled + metadata; semantics CANCELADO |

### A7 — Semantics sem impacto/metadata · **MÉDIA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | Label a11y não incluía impacto, anexos, adendos, professional |
| Impacto | Leitor de tela incompleto |
| Correção | Label único com metadata relevante + `excludeSemantics` |
| Teste | semantics CANCELADO + impacto |

### A8 — Filter count edge · **BAIXA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | `activeFilterCount` negativo / zero com `hasActiveFilters` podia poluir semantics/badge |
| Correção | `normalizeFilterCount`; badge só se `> 0`; semantics sem “-1/0 ativos” enganoso |
| Teste | filtros edge |

### A9 — recordedBy vazio · **BAIXA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Problema | `recordedByLabel('')` gerava string vazia / risco de linha órfã |
| Correção | retorna `null` se name vazio |
| Teste | unit recordedByLabel |

### A10 — Error/Offline com lastKnown · **BAIXA** · CORRIGIDO (defensivo)

| Campo | Detalhe |
|-------|---------|
| Problema | UI ignorava `lastKnown` em Error/Offline |
| Nota 3A | Controller preserva via `HealthTimelineData` na prática |
| Correção | Se `lastKnown.items` não vazio, renderiza lista + banner |
| Teste | coberto indiretamente por data + banner |

### A11 — Operational impact labels · **INFO** · validado

| Campo | Detalhe |
|-------|---------|
| Problema (suspeita) | UI inventou escala? |
| Achado | Escala **oficial** do domínio: `none/low/medium/high/critical` |
| Correção | Labels 1:1 (`baixo/médio/alto/crítico`) + description canônica; `none`/null **não** renderizam “Sem impacto” |
| Teste | grupo operational impact |

### A12 — groupTimelineByDay a cada rebuild · **INFO** · aceito

| Campo | Detalhe |
|-------|---------|
| Observação | `groupTimelineByDay` roda em todo notify de `isLoadingMore`/`isRefreshing` |
| Avaliação | Custo O(n) linear aceitável para páginas (~20–100); sem memoização prematura |
| Ação | Documentado; não otimizado |

### A13 — Evidência PNG · **INFO**

| Campo | Detalhe |
|-------|---------|
| Observação | Sem PNG versionado (runner Windows instável com `toImage`) |
| Mitigação | Harness estrutural 360/390/430 + asserts de conteúdo |

### A14 — Skeleton Semantics · **BAIXA** · CORRIGIDO

| Campo | Detalhe |
|-------|---------|
| Correção | Skeleton decorativo sob `ExcludeSemantics`; label único de loading |

## 5. Correções realizadas

1. Lazy `ListView.builder` com slots flat.
2. Rail via `CustomPaint` (sem `IntrinsicHeight`).
3. Prioridade visual refresh > load more / banner antigo.
4. Sanitização ampliada.
5. Cancelled sem Opacity global.
6. Semantics completos no card.
7. Normalização de contagem de filtros.
8. `recordedByLabel` null-safe.
9. Respeito defensivo a `lastKnown` em Error/Offline.
10. Impact labels alinhados ao enum de domínio.
11. Skeleton excluído da árvore de Semantics.

## 6. User copy / sanitização

- Offline e refresh offline usam copy fixo (não rebaixam offline a erro genérico).
- Load more error usa copy fixo (não exibe raw).
- Error global passa por `sanitizeMessage` reforçado.
- Payloads hostis (FirebaseException, permission-denied, googleapis, paths, stack, texto longo) → fallback operacional.

## 7. Operational impact

| Nível domínio | UI |
|---------------|-----|
| `null` | não renderiza |
| `none` | não renderiza (não inventa “sem impacto”) |
| `low` | Impacto baixo · {description} |
| `medium` | Impacto médio · {description} |
| `high` | Impacto alto · {description} |
| `critical` | Impacto crítico · {description} |

Sem cálculo de readiness. Sem gradação inventada.

## 8. Cancelled

- Visível com chip **CANCELADO** (texto, não só cor).
- Metadata (impact/anexos/adendos/professional) permanece legível.
- Não usa vermelho de restrição no chip.

## 9. Unknown type

Label sempre **REGISTRO DE SAÚDE**. Raws hostis ocultos.

## 10. Tipos visuais

14/14 tipos oficiais mapeados; teste table-driven + render widget.

## 11. Timeline rail

CustomPaint por item; sem IntrinsicHeight; marker excluído de Semantics (card carrega o label).

## 12. Performance / lazy rendering

- Lazy: sim (`SliverChildBuilderDelegate`).
- 100 items: build + scroll + load more OK.
- `groupTimelineByDay` por rebuild: aceito (INFO).

## 13. Estados visuais

| Estado | Comportamento auditado |
|--------|------------------------|
| initial | neutro, não empty/error |
| loading | skeleton + label único |
| empty / empty+filtros | copy seguro |
| error | sanitizado + retry |
| offline | copy offline + retry |
| data | lista + banners/load more |
| error/offline + lastKnown | lista + banner (defensivo) |

## 14. Refresh

- Pull-to-refresh em data e empty.
- Progress linear discreto.
- Banner só com falha e **não** durante nova tentativa.
- Lista preservada.

## 15. Load more

- Botão controlado; progress priorizado; retry único.
- Oculto durante refresh.
- `hasMore == false` → sem botão.

## 16. Filtros visuais

- Sem botão se callback null.
- Badge só com count > 0.
- Count negativo normalizado.

## 17. Callbacks

- Tap único; um InkWell; sem affordance sem callback.

## 18. Acessibilidade

- Label único por card.
- CANCELADO e impacto no label.
- Skeleton não polui Semantics.
- Rail excluído.

## 19. Responsividade

360 / 390 / 430 com textos extremos: sem overflow.

## 20. Textos extremos

Título 220+, subtitle 520+, names longos, impact longo: OK em 360.

## 21. Datas / timezone

- `now` injetável consistente.
- HOJE/ONTEM alinhados a `groupTimelineByDay`.
- Formato histórico estável (`05 JAN 2026`) sem locale de sistema.
- UTC → local: grupo e label no mesmo dia calendário.

## 22. Evidência visual

Harness estrutural; sem PNG versionado (limitação honesta do runner).

## 23. Import boundaries

Zero import de Firebase/Firestore/DogViewModel/MainRoot/HealthV1Entry nos widgets 3B.

## 24. Escopo

| Pergunta | Resposta |
|----------|----------|
| alteração 3A? | **não** |
| alteração 2A–2E? | **não** |
| Firestore/source? | **não** |
| shell/wiring? | **não** |
| filtros funcionais? | **não** |
| navegação real? | **não** |

## 25. Testes adicionados

`health_timeline_adversarial_3b_test.dart` — sanitização, impact, 14 tipos, unknown hostil, cancelled+metadata, 100 items, refresh×loadMore, filtros edge, datas, callbacks/a11y, metadata extrema, lazy builder.

## 26. Validações

| Validação | Resultado |
|-----------|-----------|
| format escopo 3B | OK |
| analyze escopo 3B | **No issues found** |
| testes 3B (view+harness+adversarial) | **67 passed** |
| timeline completa (3A+3B) | **179 passed** |
| `test/features/health` | **545 passed** |
| `flutter test` global | **728 passed, 1 skipped** |
| `git diff --check` | OK |
| analyze global | **40 issues preexistentes**; **0 na 3B** |

## 27. Riscos restantes

1. `groupTimelineByDay` a cada rebuild — aceitável até integrar páginas maiores.
2. Sem golden PNG — evidência estrutural apenas.
3. Wiring real e dados Firestore ficam para 3C/3D.
4. Filtros funcionais e detalhe — 3D.

## 28. Estado final do git

HEAD base inalterado (`476bcc6…`). Working tree: apenas arquivos 3B (+ audit report). **Sem commit.**

## 29. Conclusão

A camada visual foi atacada em semântica, layout, estados concorrentes, a11y e escala. Correções prioritárias (lazy list, rail sem IntrinsicHeight, sanitização, impact, cancelled, refresh/loadMore) aplicadas com regressão.

Classificação:

# APROVADA PARA COMMIT
