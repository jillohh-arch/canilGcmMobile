# Health v1.0 — Fase 3A — Auditoria Técnica Adversarial

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `665cc0d50a32010297b9dc7363ec986ce54e9aec` |
| commit | `feat(health): wire Health v1 summary entry with runtime polish` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree | somente untracked da Fase 3A (+ report/audit) |

Arquivos no escopo:

- `lib/features/health/presentation/timeline/**`
- `test/features/health/presentation/timeline/**`
- `docs/health/HEALTH_V1_PHASE_3A_REPORT.md`
- `docs/health/HEALTH_V1_PHASE_3A_AUDIT.md` (este)

**Nenhuma alteração fora do escopo 3A.** Preflight OK.

## 2. Arquivos auditados

### Produção

- `health_timeline_controller.dart`
- `health_timeline_state.dart`
- `health_timeline_query.dart`
- `health_timeline_entry_view.dart`
- `health_timeline_page.dart`
- `health_timeline_cursor.dart`
- `health_timeline_source.dart`
- `health_timeline_grouping.dart`
- `models/health_timeline_detail_reference.dart`
- `models/health_timeline_traceability.dart`

### Testes (pré-auditoria + adversarial)

- `health_timeline_contracts_test.dart`
- `health_timeline_controller_test.dart`
- `health_timeline_grouping_test.dart`
- `health_timeline_adversarial_audit_test.dart` (**novo**)
- `fake_health_timeline_source.dart`
- `timeline_test_helpers.dart`

### Docs

- `HEALTH_V1_PHASE_3A_REPORT.md`
- ADR-004 / Domain Model (consulta pontual)

## 3. Metodologia

1. Leitura integral do código de produção e testes (não só o relatório).
2. Ataques manuais de raciocínio em: races, paginação, refresh, dispose, imutabilidade, igualdade.
3. Busca por acoplamento Firebase/Firestore/legacy no escopo 3A.
4. Confirmação de isolamento de 2A–2E via `git status` (somente untracked 3A).
5. Correção apenas de bugs claros no escopo.
6. Testes adversariais novos para lacunas e regressão das correções.
7. Revalidação format/analyze/test.

## 4. Achados

### ALTA — A1: Refresh com falha apagava cursor e quebrava loadMore

| Campo | Detalhe |
|-------|---------|
| **Problema** | `refresh()` zerava `_nextCursor` no início. Em falha com lista preservada, `hasMore` permanecia `true` mas o cursor ficava `null` → `loadMore()` virava no-op permanente até um refresh bem-sucedido. |
| **Cenário** | Página 1 com `hasMore` → refresh offline/erro → usuário tenta “carregar mais”. |
| **Impacto** | Paginação silenciosamente morta após refresh falho; corrupção de capacidade de paginação, não de itens. |
| **Arquivo** | `health_timeline_controller.dart` |
| **Correção** | Guardar `cursorBeforeRefresh` e restaurar em `_applyFirstPageFailure` quando dados da mesma identidade são preservados. |
| **Aplicada?** | **Sim** |
| **Regressão** | `loadMore após refresh falho restaura cursor e preserva lastRefreshError` |

### ALTA — A2: Falha de refresh com dados sem sinal semântico para a UI

| Campo | Detalhe |
|-------|---------|
| **Problema** | Após refresh offline/erro com lista preservada, o estado voltava a `HealthTimelineData` “limpo”, sem indicar que o refresh falhou. |
| **Cenário** | Pull-to-refresh falha; lista antiga permanece; 3B não tem como mostrar banner/erro. |
| **Impacto** | Erro silencioso na revalidação; UX futura cega. |
| **Arquivo** | `health_timeline_state.dart`, `health_timeline_controller.dart` |
| **Correção** | Campos `lastRefreshError` + `lastRefreshWasOffline` no snapshot; limpos em 1ª página/refresh bem-sucedido; setados em falha com preserve. |
| **Aplicada?** | **Sim** |
| **Regressão** | grupo `refresh failure semantics` no audit test |

### MÉDIA — A3: loadMore possível com items vazios / estado não-data

| Campo | Detalhe |
|-------|---------|
| **Problema** | `loadMore` checava snapshot interno sem exigir `items.isNotEmpty` nem `state is HealthTimelineData`. Edge case source empty+hasMore poderia deixar cursor residual. |
| **Impacto** | Comportamento indefinido em source inconsistente. |
| **Correção** | Guardas: `items.isEmpty` return; `state is! HealthTimelineData` return; empty first page força `hasMore=false` e cursor null. |
| **Aplicada?** | **Sim** |
| **Regressão** | empty vs error + loadMore guards cobertos indiretamente |

### BAIXA — A4: `lastAmendedAt` com `hasAmendments == false` permitido

| Campo | Detalhe |
|-------|---------|
| **Problema** | Combinação semanticamente estranha permitida. |
| **Impacto** | Baixo; não causa corrupção de timeline. |
| **Correção** | Não aplicada (evitar overengineer). Documentado. |
| **Aplicada?** | Não |

### INFO — A5: Agrupamento depende de timezone do device

| Campo | Detalhe |
|-------|---------|
| **Problema** | `groupTimelineByDay` usa `toLocal` (device). Não há timezone clínico fixo. |
| **Impacto** | Esperado e documentado; labels “Hoje/Ontem” ficam na 3B. |
| **Aplicada?** | N/A — teste UTC com offset simulado adicionado |

### INFO — A6: Period equality é por `DateTime` exato

| Campo | Detalhe |
|-------|---------|
| **Problema** | `DateTime` UTC vs local no mesmo instante podem não ser `==`. |
| **Impacto** | Identidade de filtro pode divergir se sources construírem periods com isUtc diferente. |
| **Aplicada?** | Não — limitação documentada; source futura deve normalizar. |

### INFO — A7: Fake e testes só em `test/`

Confirmado. Zero fake em produção.

## 5. Correções realizadas

1. **`lastRefreshError` / `lastRefreshWasOffline`** no snapshot e getters em `HealthTimelineData`.
2. **Restauração de cursor** após refresh falho com lista preservada.
3. **Guards de loadMore** (items não vazios + estado data).
4. **Empty first page** normaliza `hasMore=false` e cursor null.
5. **Suíte adversarial** (`health_timeline_adversarial_audit_test.dart`).

## 6. Identidade lógica

| Campo | Entra na identity? |
|-------|-------------------|
| dogId | sim (trim) |
| types | sim (Set, ordem irrelevante, vazio = todos) |
| period | sim |
| caseId | sim (trim/null) |
| professional | sim |
| pageSize | sim |
| cursor | **não** |

Ataques cobertos: Set reordenado, types vazio, cursor diferente, pageSize/case/dog/professional.

## 7. Query equality

- `HealthTimelineQuery ==` = filterIdentity + cursor.
- `filterIdentity ==` ignora cursor; types unordered.
- `copyWith(pageSize: 0|101)` revalida no construtor.

## 8. Paginação

Fluxo auditado:

primeira página → nextCursor → loadMore → merge → nextCursor novo

- Cursor correto na 2ª página.
- Cursor limpo no refresh bem-sucedido.
- Cursor **restaurado** no refresh falho com preserve (A1).
- hasMore false encerra loadMore.
- loadMore sem cursor / sem items / não-data: no-op.

## 9. Page invariants

`HealthTimelinePage` construtor enforce:

- hasMore true ⇔ nextCursor != null

Controller não tem `copyWith` de page que viole isso; snapshot.hasMore e `_nextCursor` sincronizados nos caminhos de sucesso/falha documentados.

Itens da page: cópia unmodifiable (imutabilidade testada).

## 10. LoadMore

| Ataque | Resultado |
|--------|-----------|
| loadMore duplo simultâneo | 1 request |
| erro | items+hasMore+cursor preservados; loadMoreError; retry OK |
| loadMore + refresh | resposta loadMore ignorada |
| loadMore + filtro | sem vazamento |
| loadMore + cão | sem vazamento |
| loadMore após refresh falho | cursor restaurado (pós-fix A1) |

## 11. Refresh

| Ataque | Resultado |
|--------|-----------|
| refresh com dados | isRefreshing, lista permanece |
| refresh erro/offline + dados | lista + lastRefreshError |
| refresh sucesso | limpa lastRefreshError e loadMoreError |
| refresh duplo | generation; resultado = mais recente |
| refresh → nova query | refresh antigo ignorado |

## 12. Race protection

Generation token em setQuery/selectDog/applyFilters/refresh.

loadMore captura generation sem incrementar.

Cenários:

- Dog A→B
- Filtro A→B
- loadMore→refresh (ambas ordens de resolução)
- refresh→nova query
- Request 2 antes de Request 1

## 13. Dispose

- dispose no meio de setQuery / loadMore: sem throw, sem notify extra, generation++.
- Testes adversarial dedicados.

## 14. Deduplicação

- chave = `entry.id`
- incoming substitui existing
- merge reordena por occurredAt DESC, id ASC
- página sobreposta A,B,C + C,D,E → C_novo no topo se occurredAt muda

## 15. Ordenação

Regra confirmada e testada com:

- empates de data
- source fora de ordem
- dedupe com mudança de occurredAt no controller

## 16. Datas e agrupamento

- dia local via `toLocal` injetável
- UTC com offset simulado (−3) testado
- meia-noite de fronteira
- **limitação residual:** timezone do device (INFO A5)

## 17. Period

- start==end OK (inclusivo)
- invertido rejeitado
- only start / only end / unbounded OK

## 18. Professional filter

- trim name/registrationNumber
- igualdade estrita (sem fuzzy)
- sem role/conta de veterinário

## 19. Forward compatibility

- tipo unknown: raw preservado, não throw, ordena/agrupa
- raw vazio: rejeitado (coerente com parsers Fase 1 que tratam empty como absent no domínio; aqui o type da entry é obrigatório)

## 20. Status

- apenas `final` / `cancelled`
- `draft` → tryParse null
- sem third state

## 21. Amendments

- hasAmendments ↔ count coerente enforced
- lastAmendedAt órfão permitido (BAIXA A4)

## 22. Attachments

- hasAttachments false + count > 0 rejeitado
- hasAttachments true + count null permitido

## 23. Detail reference

- puro; assert sourceType/sourceId não vazios
- sem Navigator/Firebase/telas

## 24. Traceability

- todos opcionais; vazio permitido
- canônico e legado no mesmo contrato
- sem Firestore

## 25. Source abstraction

Busca em produção 3A:

- `firebase` / `firestore` / `DocumentSnapshot` / `FirebaseException` → **apenas comentários**, zero imports
- exception com `isOffline` tipada localmente

## 26. Import boundaries

Produção 3A importa:

- domain enums/models/value objects
- flutter foundation (ChangeNotifier)
- arquivos internos de timeline

Não importa: test, coexistence, legacy services, shell, main, firebase packages.

## 27. Imutabilidade

Testado:

- page items
- query.types
- snapshot.items
- state.items do controller

## 28. State isolation

- Dog A data → Dog B fail → error B sem lastKnown de A
- Query A data → Query B fail → error B sem lastKnown de A

## 29. Offline/error

| Caso | Estado |
|------|--------|
| 1ª carga offline | `HealthTimelineOffline` |
| 1ª carga error | `HealthTimelineError` |
| refresh offline + dados | `HealthTimelineData` + `lastRefreshWasOffline` |
| refresh error + dados | `HealthTimelineData` + `lastRefreshError` |
| loadMore error | data + `loadMoreError` |
| empty sucesso | `HealthTimelineEmpty` (não error) |

## 30. Testes adicionados

Arquivo: `test/.../health_timeline_adversarial_audit_test.dart`

Cobertura nova principal:

- identity / query equality
- imutabilidade
- dedupe+reorder (incl. controller)
- refresh failure semantics + cursor restore
- loadMore+filtro / loadMore+cão
- out-of-order requests
- refresh duplo
- dispose durante request
- flags isRefreshing/isLoadingMore
- empty vs error
- UTC grouping
- period / professional / forward-compat
- notifyListeners em race

**Total timeline após auditoria: 112 testes** (68 originais + ~44 adversarial).

## 31. Validações

| Comando | Exit | Notas |
|---------|------|--------|
| `dart format --set-exit-if-changed` (3A) | 0 | |
| `flutter analyze` timeline | 0 | No issues |
| `flutter test` timeline | 0 | 112 passed |
| `flutter test test/features/health` | 0 | |
| `flutter test` | 0 | |
| `git diff --check` | 0 | |
| `flutter analyze` global | 1 | issues **preexistentes**; 0 novos da 3A |

## 32. Riscos restantes

1. **Source ainda abstrata** — races reais de rede só em 3C+.
2. **Period/DateTime isUtc** — identity sensível a construção inconsistente de DateTime (A6).
3. **Timezone de grouping** — device-local (A5); 3B define labels.
4. **hasAmendments/lastAmendedAt órfão** — BAIXA (A4).
5. **Cursor restaurado após refresh falho** é o cursor **pré-refresh**, não um cursor revalidado server-side — correto para lista preservada, mas a source futura deve tolerar cursor possivelmente stale (retry de página seguinte sobre lista local antiga).

## 33. Escopo confirmado

| Item | |
|------|--|
| Firestore / source concreta | não |
| UI / shell | não |
| coexistência / merge legado | não |
| busca textual | não |
| write / migration / Function | não |
| alteração 2A–2E | não |
| commit / push | não |

## 34. Estado final do git

```
HEAD: 665cc0d (sem commit)
?? docs/health/HEALTH_V1_PHASE_3A_REPORT.md
?? docs/health/HEALTH_V1_PHASE_3A_AUDIT.md
?? lib/features/health/presentation/timeline/
?? test/features/health/presentation/timeline/
```

## 35. Conclusão

A fundação da timeline **sobreviveu a auditoria adversarial** após correção de dois problemas **ALTA**:

1. cursor perdido após refresh falho;
2. falha de refresh sem sinal semântico.

Race protection, isolamento dog/query, dedupe, ordenação e imutabilidade estão corretos e cobertos.

**Classificação: APROVADA PARA COMMIT**

(Commit **não** executado nesta auditoria, conforme instrução.)
