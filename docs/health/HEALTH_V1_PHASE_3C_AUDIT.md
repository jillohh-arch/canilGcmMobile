# Health v1.0 — Fase 3C — Auditoria Técnica Adversarial

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `42bc2ef74a247d192f4743c40ac0d40636c0b44f` |
| commit | `feat(health): add visual clinical timeline` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree | somente arquivos 3C (untracked) |

Preflight **OK**. Nenhuma alteração fora do escopo 3C.

## 2. Arquivos auditados

### Produção

- `lib/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart`
- `lib/features/health/data/coexistence/timeline/multi_source_timeline_paginator.dart`
- `lib/features/health/data/coexistence/timeline/coexistence_timeline_cursor_codec.dart`
- `lib/features/health/data/coexistence/timeline/health_timeline_entry_codec.dart`
- `lib/features/health/data/coexistence/timeline/health_timeline_source_reader.dart`
- `lib/features/health/data/coexistence/timeline/health_timeline_mappers.dart`
- `lib/features/health/data/coexistence/timeline/firestore_timeline_readers.dart`
- `lib/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart`

### Testes

- `test/features/health/data/coexistence/timeline/coexistence_health_timeline_source_test.dart`

### Documentação

- `docs/health/HEALTH_V1_PHASE_3C_REPORT.md`

### Consulta de contexto

- contratos 3A (`HealthTimelineSource`, cursor, query, grouping)
- coexistência 2D (soft-delete, date parse, vacinação, feedings dual-read)
- `NutritionService` (dual-write `feeding_events`/`feedings`)
- `firestore.indexes.json` (índice vacinas)
- UI 3B apenas para boundary (sem alteração)

## 3. Metodologia

Auditoria adversarial focada em:

1. Integridade de paginação multi-fonte e watermark
2. Cursor (privacidade, tamanho, versão, corrupção, fingerprint)
3. Empates de timestamp
4. Source recreation sem memória de instância
5. Filtros esparsos / unmappable / soft-delete sem vazio falso
6. Dedupe feeding e identidade global
7. Fallback vacinação opt-in
8. Semântica de falhas e sanitização
9. Read-only e import boundaries
10. Gates A–K com testes novos

## 4. Achados

### CRÍTICA — Merge multi-fonte emitia residual “inseguro” (ordem/perda lógica)

| Campo | Valor |
|-------|--------|
| problema | O paginator fazia fetch de `pageSize` em **cada** fonte, mesclava tudo e emitia os top-N do residual sem watermark. Com empates de timestamp (ou fontes desbalanceadas), itens de fonte B podiam ser emitidos **antes** de itens ainda não lidos da fonte A que deveriam vir primeiro. |
| cenário | 100 docs com o mesmo `occurredAt` em 4 fontes; `pageSize` 7. Após a 1ª leva, residual continha itens `s1:*` emitidos antes de `s0:*` restantes. |
| impacto | Timeline com ordem global incorreta entre páginas; em casos extremos, percepção de “histórico completo” com prefixo errado. |
| arquivo | `multi_source_timeline_paginator.dart` |
| correção | Emissão **watermark-safe**: só emite itens `X` tais que, para toda fonte aberta com cursor `L_s`, `X` está em ou antes de `L_s` na ordem global. Continua buscando até o prefixo seguro encher a página ou esgotar fontes. |
| aplicada | **sim** |
| regressão | GATE D (100 timestamps iguais), GATE J (randomized), drain continuity assert |

### CRÍTICA — Cursor inválido reiniciava a timeline silenciosamente

| Campo | Valor |
|-------|--------|
| problema | `tryDecode` retornava `null` em cursor corrompido / outra query; o paginator tratava como primeira página (`initial`). |
| cenário | `loadMore` com token podre ou cursor do dog A no dog B → página 1 de novo → **duplicação** sem erro. |
| impacto | Histórico duplicado / inconsistente sem sinal ao usuário. |
| arquivo | `coexistence_timeline_cursor_codec.dart`, `multi_source_timeline_paginator.dart` |
| correção | `decode()` lança `HealthTimelineSourceException` controlada quando o cursor está presente e é inválido / de outra query / versão desconhecida. |
| aplicada | **sim** |
| regressão | GATE H |

### CRÍTICA — Residual serializava PHI/dados clínicos completos

| Campo | Valor |
|-------|--------|
| problema | `HealthTimelineEntryCodec` gravava subtitle (observações), professional, recordedBy, operationalImpact, traceability com paths, attachmentCount, etc. no token base64. |
| cenário | Qualquer página com residual; token em logs/crash/analytics futuras. |
| impacto | Dívida de privacidade; base64 não é proteção. |
| arquivo | `health_timeline_entry_codec.dart` |
| correção | Residual **slim** (v2): id, dogId, type, times, title, status, caseId, flags, detail ids. Sem subtitle/professional/recordedBy/impact/trace. |
| aplicada | **sim** |
| regressão | GATE G |

### ALTA — Mensagens de erro vazavam internals Firebase

| Campo | Valor |
|-------|--------|
| problema | `e.message` / `e.toString()` de `FirebaseException` repassados ao `HealthTimelineSourceException`. |
| cenário | permission-denied, failed-precondition com URL de índice, stack. |
| impacto | UX/diagnóstico com paths, URLs googleapis, ruído técnico. |
| arquivo | `firestore_timeline_readers.dart`, `coexistence_health_timeline_source.dart`, `TimelineErrorSanitizer` |
| correção | Sanitização central; `isOffline` só com critério de rede. |
| aplicada | **sim** |
| regressão | exception sanitization test |

### ALTA — Vacinas raiz com `orderBy(dataAplicacao)` exige índice composto ausente

| Campo | Valor |
|-------|--------|
| problema | Query `where caoId` + `orderBy dataAplicacao` não tem índice em `firestore.indexes.json`. A 2D deliberadamente evita orderBy. |
| cenário | Fallback vacinas opt-in ligado → `failed-precondition` em runtime. |
| impacto | Fallback quebrado se habilitado sem índice. |
| arquivo | `firestore_timeline_readers.dart` |
| correção | Reader legada com `clientSideOrderOnly` (equality + limit + sort cliente); teto cheio → `truncated` (nunca empty falso). Fallback permanece **opt-in desligado** por padrão. |
| aplicada | **sim** (mitigação; sem criar índice) |
| regressão | documentado; fallback opt-in test |

### ALTA — Cursor de feeding no avanço unmappable usava id inconsistente

| Campo | Valor |
|-------|--------|
| problema | Entradas usam `feeding:{docId}`; avanço de lixo usava `{sourceKey}:{docId}` (`feedings:…` / `feeding_events:…`). |
| cenário | Página só com soft-deletes em `feedings` → cursor avança com id errado → skip/dup em empates. |
| correção | `_cursorIdForDoc` unifica `feeding:$docId` para ambas as coleções. |
| aplicada | **sim** |
| regressão | coberto indiretamente por feeding gates + watermark |

### MÉDIA — Residual / token sem limite defensivo

| Campo | Valor |
|-------|--------|
| problema | Residual podia crescer com N fontes × pageSize sem teto. |
| correção | `maxResidualEntries = 250`, `maxTokenUtf8Bytes = 48KiB`; encode lança se exceder. |
| aplicada | **sim** |
| regressão | cursor size test |

### MÉDIA — Data inválida descartada sem sinal → **CORRIGIDA (microcorreção)**

| Campo | Valor |
|-------|--------|
| problema | Unmappable por data inválida some silenciosamente; timeline “completa” com histórico incompleto. |
| política final | `TimelineMappingResult`: mapped / ignored / invalid. Soft-delete e irrelevante por filtro → **ignored**. Ativo relevante com `occurredAt` impossível (ou estrutura obrigatória inválida) → **invalid** → `HealthTimelineSourceException` inconclusiva. **Sem threshold** arbitrário. Sem inventar data. |
| aplicada | **sim** (`timeline_mapping_result.dart`, mappers, readers) |
| regressão | 1/99, 50/100, soft-deleted inválido, tipo irrelevante, period+data, unknown válido, lote só unmappable, loadMore, recreation |

### BAIXA / INFO — Feeding `feeding:{docId}`

| Campo | Valor |
|-------|--------|
| evidência | `NutritionService.addFeeding` faz dual-write com **mesmo** `docRef.id` em `feeding_events` e `feedings`. Summary 2D também dedupe por docId. |
| decisão | Manter id unificado (alinha dual-write real). Colisão acidental de IDs distintos é improvável com auto-ids; documentada como risco residual BAIXO. |
| testes | GATE K |

### INFO — Custo de fetch

| Campo | Valor |
|-------|--------|
| fato | Até `pageSize` por fonte aberta por rodada; watermark pode exigir várias rodadas. |
| aceitável | Temporário na ponte 3C. Residual slim + limites mitigam explosão de token. |

## 5. Correções realizadas

1. Watermark-safe multi-source merge
2. Cursor decode estrito (sem reinício silencioso)
3. Residual slim v2 + proibição de chaves PHI
3b. **Microcorreção:** unmappable ativo relevante = leitura inconclusiva (`TimelineMappingResult`)
4. Limites de residual/token
5. Sanitização de erros + offline criterioso
6. Vacinas sem orderBy composto (client order + truncated)
7. Cursor id unificado para feedings
8. `ScanningMemoryTimelineSourceReader` para gates de scan
9. Suíte de testes adversariais (gates A–K)

## 6. Cursor architecture

```text
HealthTimelineCursor.token
  = base64url(JSON{
      v: 2,
      dogId,
      fp,              // fingerprint filtros+pageSize
      sources: { key: { after?: {atMs,id}, exhausted } },
      residual: [ slim entries ],
      vacFb, vacDecided
    })
```

Self-contained: source recreation só precisa do token + mesma query.

## 7. Cursor privacy

| Campo residual | Serializado? |
|----------------|--------------|
| id, dogId, type, times, title, status | sim (mínimo de reemissão) |
| caseId, detail sourceType/sourceId | sim (ids) |
| hasAttachments / hasAmendments | sim (flags) |
| subtitle (observações) | **não** |
| professional / recordedBy | **não** |
| operationalImpact | **não** |
| traceability paths | **não** |
| attachment paths/count | **não** |

`HealthTimelineCursor.toString()` permanece `HealthTimelineCursor(<opaque>)`.

## 8. Cursor size

| Cenário | Observação |
|---------|------------|
| pageSize 1 / 20, 5 fontes | token UTF-8 decodificado << 48KiB |
| residual grande (pageSize 3, 150 itens) | gated por slim + maxResidual |
| crescimento | linear no residual; encode falha se > limites |

## 9. Cursor validation / versioning

- Versão atual: **2**
- v ≠ 2 → exception controlada
- dogId / fingerprint mismatch → exception
- base64/JSON/residual inválido → exception
- Nunca fallback para página 1

## 10. Source recreation

Gates C e C2: nova instância + novos readers a cada página até `hasMore == false`. Cursor carrega posição + residual slim. **Pass.**

## 11. Timestamp ties

- 100 empates multi-fonte, pageSize 7 e 1 → 100 únicos, id ASC
- 100 empates single-source → idem
- Watermark impede emissão prematura de outras fontes

## 12. Firestore pagination

| Fonte | Query | Tie-break |
|-------|-------|-----------|
| subcoleções dog | `orderBy(dateField DESC)` + `startAt(ts)` | client `(time, globalId)` |
| vacinas raiz | `where caoId` **sem** orderBy | sort cliente; cap → truncated |

Limitação: empates massivos no servidor dependem de over-fetch + filtro client; se um único timestamp tiver mais docs que o hard cap sem progresso de data parseável → truncated (conservador).

Não criados índices nesta auditoria.

## 13. Feeding dedupe

- Dual-write comprovado em `NutritionService.addFeeding` (mesmo id).
- Id global: `feeding:{docId}`.
- Mesmo id → uma entrada; ids distintos → ambas.
- Identidade entre outras coleções com mesmo docId permanece distinta (`health_events:abc` ≠ `weight_records:abc` ≠ `feeding:abc` ≠ `vacinas:abc`).

## 14. Residual / buffer

- Residual = itens já lidos, ainda não emitidos (inclui unsafe aguardando watermark).
- Persistido slim no cursor.
- Limite 250 entradas / 48KiB JSON.

## 15. Global ordering

- `occurredAt DESC`, `id ASC` (3A).
- Assert inter-páginas: `compare(last(N-1), first(N)) <= 0`.

## 16. Filters

- types / period / caseId / professional no mapper.
- professional ≠ recordedBy.
- fingerprint ordena types; pageSize na identidade.
- Cursor de outro filtro rejeitado.

## 17. Unmappable records

### Política final (microcorreção)

| Caso | Resultado |
|------|-----------|
| soft-deleted | **ignored** (mesmo com data inválida) |
| tipo/filtro prova irrelevância **antes** da data | **ignored** |
| ativo relevante + data ausente/inválida | **invalid** → source inconclusiva |
| ativo relevante + estrutura obrigatória inválida | **invalid** → inconclusiva |
| tipo unknown + data válida | **mapped** (unknown) |
| period filter + data inválida em ativo relevante | **invalid** (nunca “fora do período”) |

- Uma subfonte invalid invalida a timeline composta.
- Não serializa o doc inválido no residual/cursor.
- Mensagem sanitizada; `debugPrint` só `sourceKey` + reason code.
- Sem threshold, quarantine, write ou telemetria.

## 18. Soft-delete

- `deleted_at != null` → excluído (≠ cancelled).
- Soft-deletes recentes não viram empty se ativos antigos existem (scan + cursor).

## 19. Vaccination fallback

- **Default off** (sem resolver injetado).
- Não usa “não veio nesta página de health_events” como prova.
- Opt-in via `resolveVaccinationFallback` / factory.
- Reader vacinas mitigado sem índice composto; truncated se cap.

## 20. Subsource failures

- Exception propaga; não devolve residual como página completa após falha de fetch.
- Truncated → exception.

## 21. Offline

- `unavailable` / `network-request-failed` → `isOffline: true`.
- permission / failed-precondition **não** viram offline.

## 22. Sanitization

- `TimelineErrorSanitizer` remove FirebaseException raw, URLs, `.dart`, stacks longas.

## 23. Read-only proof

Busca por `.set(`, `.update(`, `.delete(`, `writeBatch`, `runTransaction` no pacote 3C: **apenas** `.add` de listas em memória. **Zero writes Firestore.**

## 24. Import boundaries

3C **não** importa:

- `HealthTimelineView` / widgets 3B
- `MainRoot`
- `HealthV1EntryScreen`
- shell / navigation

Pode importar contratos 3A (page, query, source, entry view, grouping).

## 25. Tests added

Gates e cenários adversarial no arquivo único de teste 3C:

- A 120, B pageSize1, C recreation all pages, C2 pageSize1+recreation
- D 100 ties, E sparse filter, F unmappable/trunc
- G privacy, H corrupt/wrong query, I 1000, J randomized, K feeding
- residual grande, falhas, offline, sanitization, cursor size, period/types, controller

**Total testes 3C: 51 passed**

## 26. Gate 120

**PASS** — 120 únicos, ordem global.

## 27. Gate 1000

**PASS** — 1000 / 5 fontes / pageSize 37 / recreation periódica.

## 28. Gate randomized

**PASS** — seed 42 vs sort global em memória.

## 29. Validations

| Check | Resultado |
|-------|-----------|
| `dart format` escopo 3C (dart) | OK |
| `flutter analyze` escopo 3C | **No issues found** |
| testes 3C | **51 passed** |
| `test/features/health/presentation/timeline` | **179 passed** |
| `test/features/health` | **596 passed** |
| `flutter test` global | **779 passed, 1 skipped** |
| `flutter analyze` global | **40 issues** (todos preexistentes; **0** em `coexistence/timeline`) |
| `git diff --check` | OK |

### 29b. Números exatos (pós-auditoria)

| Escopo | Resultado |
|--------|-----------|
| 3C analyze | **No issues found** |
| 3C tests | **51 passed** (pós-microcorreção unmappable) |
| presentation timeline | **179 passed** |
| health | **596 passed** |
| global tests | **779 passed, 1 skipped** |
| global analyze | preexistentes **fora** da 3C; **0** em `coexistence/timeline` |

Critério atendido: **0 novos erros/warnings causados pela 3C.**

## 30. Risks remaining

1. ~~Unmappable silencioso~~ — **fechado**: ativo relevante unmappable → inconclusivo.
2. Empates Firestore extremos > hard cap de batch com datas ilegíveis em docs **ignored-only** → truncated (não empty).
3. Vacinas fallback: sem índice composto, paginação profunda limitada (cap + truncated).
4. Title ainda no residual slim (necessário para reemitir linha; não é observação livre).
5. Ponte temporária — não é projeção canônica `health_timeline`.
6. Sem wiring shell (3D).
7. Colisão acidental feeding id (BAIXO; dual-write intencional).

## 31. Scope

Respeitado: sem 3D, sem shell, sem UI 3B, sem writes, sem migration, sem Functions, sem índices, sem commit/push.

## 32. Git state

```text
branch: feature/health-v1-foundation
HEAD:   42bc2ef74a247d192f4743c40ac0d40636c0b44f
?? docs/health/HEALTH_V1_PHASE_3C_REPORT.md
?? docs/health/HEALTH_V1_PHASE_3C_AUDIT.md
?? lib/features/health/data/coexistence/timeline/
?? test/features/health/data/coexistence/timeline/
```

**Sem commit. Sem push.**

## 33. Conclusion

A auditoria **confirmou e corrigiu** falhas que permitiam timeline visualmente plausível porém logicamente incorreta (merge sem watermark, cursor inválido silencioso, PHI no residual).

A **microcorreção final** fecha a brecha de unmappable ativo silencioso: “não consegui interpretar” não significa “não existe”.

Validações pós-microcorreção (finais):

- 3C analyze: **No issues found**
- 3C tests: **51 passed** (gates A–K + política unmappable)
- timeline presentation: **179 passed**
- Health: **596 passed**
- global: **779 passed, 1 skipped**
- **0** novos issues causados pela 3C

# APROVADA PARA COMMIT

Working tree 3C + auditoria + microcorreção; **sem commit automático**.
