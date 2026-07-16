# Health v1.0 — Fase 3A — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD inicial | `665cc0d50a32010297b9dc7363ec986ce54e9aec` |
| commit esperado | `feat(health): wire Health v1 summary entry with runtime polish` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |

Preflight **OK** — implementação iniciada sobre o HEAD esperado.

## 2. Referências utilizadas

### Regras / skills

- `CLAUDE.md`
- `.claude/skills/flutter-canil-conventions/SKILL.md`
- `.claude/skills/canil-k9-context/SKILL.md`

### Documentação Health

- `docs/HEALTH_IMPLEMENTATION_ROADMAP.md`
- `docs/HEALTH_V1_ARCHITECTURE.md`
- `docs/health/HEALTH_V1_DOMAIN_MODEL.md`
- `docs/health/HEALTH_V1_FIRESTORE_SCHEMA.md` (consulta de contrato; sem alteração)
- `docs/health/HEALTH_V1_MIGRATION_PLAN.md`
- `docs/health/HEALTH_V1_READINESS_POLICY.md`
- `docs/health/HEALTH_V1_FOUNDATION_REVIEW.md`
- `docs/health/HEALTH_V1_CAPABILITIES_INVENTORY.md`

### ADRs

- ADR-002 — Clinical Events and Immutability
- ADR-003 — Clinical Case Workflow
- ADR-004 — Timeline, Summary and Projections (**principal**)
- ADR-006 — Legacy Coexistence and Migration
- ADR-007 — Health Internal Organization

### Fases anteriores (reports)

- 1D, 2A–2E reports/audits (padrão de presentation/source/controller do Resumo)

### Código reutilizado

- `HealthTimelineType` (`health_v1_enums_ext.dart`)
- `HealthTimelineItem` (domínio/projeção — **não** duplicado como entidade; 3A cria read model de apresentação)
- `RecordedBy`, `ProfessionalIdentitySummary`, `OperationalImpact`
- Padrão Summary 2B: `ChangeNotifier` + source abstrata + sealed state + exception offline

## 3. Auditoria de tipos existentes

| Conceito | Existente? | Decisão 3A |
|----------|------------|-------------|
| Tipo de timeline | `HealthTimelineType` (14 valores ADR-004) | **Reutilizado** via `HealthTimelineTypeView` (known/unknown + raw) |
| Item de projeção domínio | `HealthTimelineItem` | **Não reutilizado como entidade de UI**; novo `HealthTimelineEntryView` (read model) |
| Status de evento clínico | `ClinicalEventStatus` (draft/final/cancelled) | **Não reutilizado** (draft não entra na timeline); criado `HealthTimelineEntryStatus` (`final` \| `cancelled`) |
| RecordedBy | sim | reutilizado |
| ProfessionalIdentity / Summary | sim | `ProfessionalIdentitySummary` no entry; filtro dedicado `HealthTimelineProfessionalFilter` |
| OperationalImpact | sim | reutilizado (metadata; sem cálculo de prontidão) |
| Amendments | campos em `HealthTimelineItem` | `HealthTimelineAmendmentMetadata` (composição) |
| Timeline controller/source/page | **não** | criados na 3A |
| Busca textual | adiada (Foundation Review / ADR-004) | **não criada** |

## 4. Escopo

### Implementado

- contratos de entrada, tipo, status, cursor, page, query, período, filtro profissional;
- source abstrata;
- state sealed;
- controller (load / refresh / loadMore / filtros / dog / races / dedupe / sort);
- agrupamento puro por dia;
- detail reference + traceability;
- fake de testes + suíte completa;
- relatório desta fase.

### Explicitamente fora

- UI final da timeline;
- wiring no shell / aba Histórico;
- Firestore / source concreta;
- coexistência legado;
- projeção `health_timeline`;
- busca textual;
- write / cancelamento / adendos;
- navegação de detalhes;
- migration / Functions.

## 5. Arquitetura

```text
HealthTimelineSource (Future page; abstrato)
        ↓
HealthTimelineController (ChangeNotifier + generation)
        ↓
HealthTimelineState
  initial | loading | data | empty | error | offline
        ↓
HealthTimelineSnapshot / HealthTimelineEntryView
        ↓
groupTimelineByDay()  →  HealthTimelineDayGroup  (puro; 3B)
```

### Identidade lógica vs cursor

- **Filter identity** = `dogId` + `types` + `period` + `caseId` + `professional` + `pageSize`
- **Cursor** = apenas paginação; **não** altera a identidade
- Refresh / loadMore / race protection usam essa separação

## 6. Arquivos criados

### Produção

| Caminho | Responsabilidade |
|---------|------------------|
| `lib/.../timeline/health_timeline_entry_view.dart` | Read model + type view + status + amendments |
| `lib/.../timeline/health_timeline_query.dart` | Query, period, professional filter, filter identity |
| `lib/.../timeline/health_timeline_page.dart` | Página paginada + invariantes |
| `lib/.../timeline/health_timeline_cursor.dart` | Cursor opaco |
| `lib/.../timeline/health_timeline_source.dart` | Interface + exception offline |
| `lib/.../timeline/health_timeline_state.dart` | Estados + snapshot |
| `lib/.../timeline/health_timeline_controller.dart` | Orquestração paginada |
| `lib/.../timeline/health_timeline_grouping.dart` | Sort/dedupe/group by day |
| `lib/.../timeline/models/health_timeline_detail_reference.dart` | Ref de detalhe (3D) |
| `lib/.../timeline/models/health_timeline_traceability.dart` | Rastreabilidade canônico/legado |

### Testes

| Caminho | Responsabilidade |
|---------|------------------|
| `test/.../timeline/fake_health_timeline_source.dart` | Fake controlável (hold/race) |
| `test/.../timeline/timeline_test_helpers.dart` | Factories de teste |
| `test/.../timeline/health_timeline_contracts_test.dart` | Contratos |
| `test/.../timeline/health_timeline_controller_test.dart` | Controller / races / isolation |
| `test/.../timeline/health_timeline_grouping_test.dart` | Agrupamento / sort / merge |

### Docs

| Caminho | Responsabilidade |
|---------|------------------|
| `docs/health/HEALTH_V1_PHASE_3A_REPORT.md` | Este relatório |

## 7. Arquivos modificados

**Nenhum arquivo preexistente versionado foi modificado.**

Fases 2A–2E, shell, domínio, Firestore rules, coexistence: **intocados**.

## 8. Timeline entry contract

`HealthTimelineEntryView` — read model de apresentação:

- identidade: `id`, `dogId`
- tipo: `HealthTimelineTypeView` (reusa enum oficial + raw desconhecido)
- tempo: `occurredAt`, `recordedAt`
- display: `title`, `subtitle?`
- status: `final` \| `cancelled`
- caso: `caseId?`, `caseTitle?`
- autoria vs clínica: `RecordedBy?` vs `ProfessionalIdentitySummary?`
- `OperationalImpact?` (metadata)
- anexos: `hasAttachments`, `attachmentCount?`
- `HealthTimelineAmendmentMetadata`
- `HealthTimelineDetailReference?`
- `HealthTimelineTraceability?`

Sem regras clínicas, prontidão ou write.

## 9. Tipos e forward compatibility

- Enum oficial reutilizado: `HealthTimelineType` (14 tipos ADR-004).
- `HealthTimelineTypeView.parse(raw)`:
  - conhecido → `known` preenchido;
  - desconhecido → `isUnknown`, `raw` preservado;
  - **nunca throw** por tipo novo (exceto raw vazio).
- Teste explícito: tipo `brand_new_type` / `future_procedure_v9` não derruba load.

## 10. Status

| Wire | Enum 3A |
|------|---------|
| `final` | `HealthTimelineEntryStatus.finalised` |
| `cancelled` | `HealthTimelineEntryStatus.cancelled` |

- Draft **não** é status de timeline principal.
- Adendos **não** são status; vivem em `HealthTimelineAmendmentMetadata`.

## 11. Query estruturada

`HealthTimelineQuery`:

- `dogId` (obrigatório)
- `types` (set; vazio = todos)
- `period` (`HealthTimelinePeriod` start/end opcionais, **inclusivos**)
- `caseId?`
- `professional?` (`HealthTimelineProfessionalFilter`)
- `cursor?`
- `pageSize` (default **20**, max **100**, > 0)

**Sem** `searchText` / busca textual.

Igualdade:

- `filterIdentity` ignora cursor;
- `==` da query inclui cursor.

## 12. Cursor

`HealthTimelineCursor(token)`:

- imutável, comparável por token;
- `toString()` não expõe o token;
- sem Firestore / DocumentSnapshot / offset.

## 13. Page

`HealthTimelinePage`:

- `items` imutável
- `nextCursor?`
- `hasMore`

Invariantes enforced:

- `hasMore == false` ⇒ `nextCursor == null`
- `hasMore == true` ⇒ `nextCursor != null`

## 14. Source abstrata

```dart
abstract interface class HealthTimelineSource {
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query);
}
```

+ `HealthTimelineSourceException(message, {isOffline})`.

Sem Firebase, sem stream, sem adapter legado.

## 15. State

| Estado | Significado |
|--------|-------------|
| `initial` | nenhuma timeline ativa |
| `loading` | primeira página da query atual |
| `data` | snapshot com items + hasMore + isRefreshing + isLoadingMore + loadMoreError? |
| `empty` | primeira página conclusivamente vazia |
| `error` | falha global; `lastKnown` só mesma identidade |
| `offline` | separado de error; sem lista na carga inicial |

## 16. Controller

`HealthTimelineController` (`ChangeNotifier`):

| API | Comportamento |
|-----|----------------|
| `setQuery` | identidade nova; loading; 1ª página |
| `selectDog` | troca dog preservando filtros estruturados |
| `applyFilters` | tipos/período/caso/profissional/pageSize |
| `refresh` | mesma identidade; descarta cursor; isRefreshing se há dados |
| `loadMore` | só com data + hasMore; erro local |

## 17. Primeira página

`setQuery` → `loading` → `data` \| `empty` \| `error` \| `offline`.

Nunca reutiliza página de outra identidade.

## 18. Refresh

- incrementa generation (invalida loadMore);
- cursor null durante o attempt (restaurado se falhar com lista preservada — auditoria A1);
- com dados da mesma identidade: lista permanece + `isRefreshing`;
- falha (error/offline) **preserva** dados utilizáveis da mesma identidade;
- sinal semântico: `lastRefreshError` + `lastRefreshWasOffline` no snapshot (auditoria A2);
- sucesso limpa `lastRefreshError` / `loadMoreError`.

## 19. Load more

- usa `nextCursor` correto;
- impede chamadas simultâneas;
- merge + dedupe por id;
- falha → mantém items + hasMore + `loadMoreError`;
- retry permitido.

## 20. Race protection

Generation token em `setQuery` / `selectDog` / `applyFilters` / `refresh`.

| Caso | Resultado |
|------|-----------|
| Dog A → Dog B, A tarda | A ignorada |
| Filtro A → Filtro B, A tarda | A ignorada |
| loadMore → refresh, loadMore tarda | loadMore ignorado |
| refresh → nova query, refresh tarda | refresh antigo ignorado |

## 21. Deduplicação

- chave: `entry.id` apenas;
- colisão: **incoming substitui existing** (payload mais novo do carregamento atual);
- reordenado após merge.

## 22. Ordenação

1. `occurredAt` **DESC**
2. empate: `id` **ASC** (estável)

Não depende da ordem incidental da `List` da source após merge.

## 23. Agrupamento

`groupTimelineByDay` + `HealthTimelineDayGroup(date, entries)`:

- dia calendário local (meia-noite);
- grupos DESC por dia;
- ordem interna preservada;
- **sem** labels “Hoje/Ontem”.

## 24. Detail reference

`HealthTimelineDetailReference(sourceType, sourceId, caseId?)`.

Sem Navigator / rotas / imports de telas.

## 25. Traceability

`HealthTimelineTraceability(sourceCollection?, sourceId?, legacySource?, legacyId?)`.

Canônico e legado no mesmo contrato visual.

## 26. RecordedBy / Professional

- `recordedBy`: quem registrou no sistema (`RecordedBy`)
- `professional`: quem atendeu (`ProfessionalIdentitySummary`)
- Filtro: `HealthTimelineProfessionalFilter` (name / registrationType / registrationNumber) — sem inventar conta/role de veterinário

## 27. Offline / error

- `HealthTimelineSourceException(isOffline: true)` → `HealthTimelineOffline` na 1ª carga
- erro genérico → `HealthTimelineError`
- refresh com dados: preserva `HealthTimelineData` (não destrói lista)

## 28. Testes

**112 testes** na pasta `test/features/health/presentation/timeline/`
(68 originais + suíte adversarial da auditoria 3A).

Cobertura:

- contratos (entry, opcionais, cancelled, amendments, detail, traceability, types known/unknown, page invariants, query equality, pageSize, period);
- primeira página (data/empty/error/offline);
- load more (sucesso, hasMore, simultâneo, erro+retry, dedupe, cursor);
- refresh (cursor, replace, isRefreshing, erro preserva, loadMore não contamina);
- races (dog, filtro, loadMore→refresh, refresh→query);
- isolation (dog, tipos, período, case, profissional);
- grouping (mesmo dia, dias, ordem, meia-noite, empty);
- unknown type + cancelled;
- adversarial: dispose, refresh duplo, out-of-order, loadMore+filtro/cão, imutabilidade, lastRefreshError, cursor restore, UTC grouping.

## 29. Validações com exit codes

Validações iniciais da implementação + revalidação pós-auditoria adversarial.

| Comando | Exit | Notas |
|---------|------|--------|
| `dart format --set-exit-if-changed` (escopo 3A) | **0** | |
| `flutter analyze lib/features/health/presentation/timeline` | **0** | No issues found |
| `flutter test test/features/health/presentation/timeline` | **0** | **112** passed (pós-auditoria) |
| `flutter test test/features/health` | **0** | |
| `flutter test` (projeto) | **0** | suite completa |
| `git diff --check` | **0** | |
| `flutter analyze` (global) | **1** | issues **preexistentes**; **0 novos** da 3A |

Critério atendido: **0 erros/warnings introduzidos pela Fase 3A**.

Auditoria: `docs/health/HEALTH_V1_PHASE_3A_AUDIT.md` — **APROVADA PARA COMMIT**.

## 30. Revisão explícita de escopo

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | houve Firestore? | **não** |
| 2 | houve source concreta? | **não** |
| 3 | houve coexistência legado? | **não** |
| 4 | houve UI final? | **não** |
| 5 | houve integração no shell? | **não** |
| 6 | houve busca textual? | **não** |
| 7 | houve write? | **não** |
| 8 | houve migration? | **não** |
| 9 | houve alteração das Fases 2A–2E? | **não** |
| 10 | houve timeline canônica? | **não** |
| 11 | houve navegação de detalhes? | **não** |
| 12 | houve regra clínica nova? | **não** |

## 31. Riscos e limitações

1. **Source ainda é abstrata** — sem dados reais até 3C (legado) ou projeção server-side.
2. **Refresh offline/erro com dados** permanece em `data` com `lastRefreshError` / `lastRefreshWasOffline` (corrigido na auditoria) — 3B decide UX de banner.
3. **`HealthTimelineItem` de domínio** coexiste com `HealthTimelineEntryView`; o adapter futuro deve mapear projeção → view, sem colapsar os dois conceitos.
4. **Professional no entry** usa `ProfessionalIdentitySummary` (leve); o filtro usa critérios de identidade sem exigir `ProfessionalIdentity` completa.
5. **pageSize max 100** é conservador de cliente; a source futura ainda valida limites de backend.
6. **Cursor restaurado pós-refresh falho** é o cursor pré-refresh (lista local antiga); source futura deve tolerar retry.
7. **Period equality** depende de `DateTime` exato (isUtc); source deve normalizar.

## 32. Pendências para 3B

- UI da timeline (cards, linha, ícones, empty/loading visuais);
- labels de dia (“Hoje”/“Ontem”) e localização;
- filtros visuais (sem search bar textual);
- consumir `HealthTimelineController` + `groupTimelineByDay`;
- **não** wire no shell ainda se 3B for só apresentação isolada — conforme plano da 3B.

Pendências posteriores:

- **3C**: source de coexistência / adapter legado (sem merge multi-coleção como arquitetura final);
- **3D**: resolução de `HealthTimelineDetailReference` → navegação;
- projeção canônica `health_timeline` (server-side; gate O3).

## 33. Estado final do git

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `665cc0d50a32010297b9dc7363ec986ce54e9aec` (sem commit da 3A) |
| working tree | alterações **não commitadas** (somente 3A) |
| commit | **não realizado** (conforme escopo) |
| push | **não realizado** |

Arquivos untracked esperados:

- `lib/features/health/presentation/timeline/**` (produção 3A)
- `test/features/health/presentation/timeline/**` (testes 3A)
- `docs/health/HEALTH_V1_PHASE_3A_REPORT.md` (report 3A)
- `docs/health/HEALTH_V1_PHASE_3A_AUDIT.md` (audit 3A)

## 34. Conclusão

A Fase 3A entrega a **fundação pura de leitura e estado** da timeline Health:

- contratos tipados sem Firestore;
- paginação com cursor opaco;
- filtros estruturados (sem busca textual);
- controller com race protection, dedupe, ordenação e isolamento por identidade;
- agrupamento puro preparado para UI;
- testes obrigatórios verdes;
- zero impacto em 2A–2E e zero source concreta.

Auditoria adversarial concluída (`HEALTH_V1_PHASE_3A_AUDIT.md`). Commit e push **não** realizados nesta fase.

**Classificação: APROVADA PARA COMMIT**
