# Health v1.0 — Fase 3C — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD inicial | `42bc2ef74a247d192f4743c40ac0d40636c0b44f` |
| commit esperado | `feat(health): add visual clinical timeline` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree inicial | limpo |

Preflight **OK**.

## 2. Referências utilizadas

- `CLAUDE.md`, flutter-canil-conventions, canil-k9-context
- 3A/3B reports + audits
- Coexistência 2D/2E (summary readers, soft-delete, date parse, vacinação)
- ADR-004, ADR-006, Domain Model, Firestore schema (consulta)

## 3. Inventário real das fontes

| Fonte | Caminho real | Data | Soft-delete | Schema observado |
|-------|--------------|------|-------------|------------------|
| health_events | `dogs/{dogId}/health_events` | `date` | `deleted_at` | type/logType, subtype, healthObservations, vetName, professionalClinic, status, attachmentUrl, mediaAttachments, createdBy, caseId? |
| weight_records | `dogs/{dogId}/weight_records` | `measured_at` | não canônico (só se campo existir) | weight_kg |
| feeding_events | `dogs/{dogId}/feeding_events` | `fed_at` | `deleted_at` | amount_grams |
| feedings | `dogs/{dogId}/feedings` | `fed_at` | `deleted_at` | amount_grams (dual-read com feeding_events) |
| vacinas | `vacinas` (raiz) | `dataAplicacao` | não | caoId, nome (fallback) |

## 4. Matriz SAFE / PARTIAL / UNSAFE

| Fonte | Classificação | Tipos | Data confiável | Soft-delete | Paginação | Observação |
|-------|---------------|-------|----------------|-------------|-----------|------------|
| health_events | **PARTIAL** | multi (mapeados + unknown) | sim (`date`) | sim | orderBy date | Tipo desconhecido → raw |
| weight_records | **SAFE** | weight | sim (`measured_at`) | opcional | orderBy measured_at | Sem tendência inventada |
| feeding_events | **PARTIAL** | meal | sim (`fed_at`) | sim | orderBy fed_at | ID unificado `feeding:{docId}` |
| feedings | **PARTIAL** | meal | sim (`fed_at`) | sim | orderBy fed_at | Dual-read; dedupe por docId |
| vacinas | **PARTIAL** | vaccination | sim (`dataAplicacao`) | não | where caoId + orderBy | Fallback **opt-in** (sem dual-count automático) |

Nenhuma fonte UNSAFE incluída “para volume”.

## 5. Escopo

### Implementado

- `CoexistenceHealthTimelineSource` (HealthTimelineSource)
- readers (Firestore + memory)
- mappers defensivos
- cursor composto self-contained + residual
- paginação global multi-fonte
- testes gate (120, pageSize 1, recreation, falhas, truncado, soft-delete)
- este relatório

### Fora

- wiring shell / UI 3B
- alteração 3A/3B (contratos/UI)
- write / migration / Functions / índices / rules
- timeline canônica `health_timeline`
- filtros visuais / navegação

## 6. Arquitetura de coexistência

```text
Firestore legado
  → FirestoreOrderedTimelineReader (por coleção)
  → HealthTimelineMappers
  → MultiSourceTimelinePaginator
       (cursor opaco base64 + residual)
  → CoexistenceHealthTimelineSource
  → HealthTimelinePage
```

Testes usam `MemoryTimelineSourceReader` + mesma paginação.

## 7. Arquivos criados

| Caminho | Papel |
|---------|-------|
| `lib/.../timeline/coexistence_health_timeline_source.dart` | Source concreta |
| `lib/.../timeline/multi_source_timeline_paginator.dart` | Merge + páginas |
| `lib/.../timeline/coexistence_timeline_cursor_codec.dart` | Cursor composto |
| `lib/.../timeline/health_timeline_source_reader.dart` | Contrato reader |
| `lib/.../timeline/health_timeline_entry_codec.dart` | Residual no cursor |
| `lib/.../timeline/health_timeline_mappers.dart` | Mapping legado |
| `lib/.../timeline/firestore_timeline_readers.dart` | Readers Firestore |
| `lib/.../timeline/memory_timeline_source_reader.dart` | Reader de teste |
| `test/.../timeline/coexistence_health_timeline_source_test.dart` | Gates 1–7 + extras |
| `docs/health/HEALTH_V1_PHASE_3C_REPORT.md` | Este relatório |

## 8. Arquivos modificados

**Nenhum** arquivo 3A/3B/2A–2E versionado.

## 9. Source concreta

`CoexistenceHealthTimelineSource` implementa `HealthTimelineSource.loadPage`.

Factory:

- `forReaders` (testes)
- `forFirestore` (produção futura; fallback vacinas opt-in)

## 10. Readers

- health_events, weight_records, feeding_events, feedings, vacinas (opt-in)
- memory (testes)

## 11–14. Mapping

- **health_events:** type mapeado quando conhecido; senão raw; cancelled só com status; soft-delete exclui
- **weight:** Pesagem + kg; sem impacto/tendência
- **feedings:** dual-read, id `feeding:{docId}`
- **vacinas:** fallback **não** automático (evita dual-count); `resolveVaccinationFallback` / factory

## 15. Identidade global

`{sourceKey}:{docId}` ou `feeding:{docId}` unificado.

## 16–17. Traceability / DetailReference

Preenchidos com coleção/id reais; não exibidos na UI.

## 18–20. RecordedBy / Professional / Impact

- recordedBy: não fabricado a partir de UID
- professional: só `vetName` (+ clinic como specialty opcional)
- operationalImpact: sempre null no legado atual (não inferido)

## 21. Soft-delete

`deleted_at != null` → excluído da timeline (≠ cancelled).

## 22. Data parsing / unmappable

Reutiliza `HealthSummaryDateParse` — sem `DateTime.now()` / epoch / created_at como `occurredAt`.

`TimelineMappingResult`:

- **mapped** — entrada válida (inclui type unknown com data válida);
- **ignored** — soft-delete, filtro de tipo/query (irrelevante);
- **invalid** — ativo relevante sem data/estrutura confiável → **leitura inconclusiva** (`HealthTimelineSourceException`), não empty nem sucesso parcial.

Ordem: soft-delete → tipo (se confiável) → data estrutural → demais campos → filtros dependentes de data.

## 23–25. Cursor / buffer / paginação

- Token opaco base64url JSON **v2**
- Residual **slim** (sem PHI clínico desnecessário)
- Posição `after` por fonte + emissão **watermark-safe**
- Fingerprint de filtros (cursor de outra query → **exception**, nunca reinício)
- Limites: max residual 250; max JSON 48KiB
- Recriável sem memória de instância

## 26. Ordenação

`occurredAt DESC`, `id ASC` (mesma 3A). Watermark impede emitir item antes de docs ainda não lidos de fontes abertas.

## 27. Filtros

types / period / caseId / professional aplicados no mapping; professional registration sem name não casa.

## 28–30. Scan truncado / falha / offline

- truncated → `HealthTimelineSourceException` (não empty)
- falha de subfonte → propaga (não parcial como completo)
- Firebase `unavailable` → `isOffline: true` (sanitizado)
- Mensagens públicas sem URL/stack/Firebase raw

## 31–34. Gates (pós-auditoria)

| Gate | Resultado |
|------|-----------|
| A — 120 / 4 fontes / page 20 | **pass** |
| B — pageSize 1 | **pass** |
| C — recreation todas as páginas | **pass** |
| C2 — pageSize 1 + recreation | **pass** |
| D — 100 timestamps iguais | **pass** |
| E — filtro sparse | **pass** |
| F — ignored vs unmappable estrutural | **pass** |
| G — cursor privacy | **pass** |
| H — cursor inválido | **pass** |
| I — 1000 registros | **pass** |
| J — randomized deterministic | **pass** |
| K — feeding ID | **pass** |
| Controller 3A | **pass** |

## 35. Testes

`coexistence_health_timeline_source_test.dart`: **51 passed** (mappers + gates A–K + política unmappable + codec + controller).

Detalhe da auditoria: `docs/health/HEALTH_V1_PHASE_3C_AUDIT.md`.

## 36. Validações (pós-auditoria)

| Check | Resultado |
|-------|-----------|
| format escopo 3C | OK |
| analyze escopo 3C | **No issues found** |
| testes 3C | **51 passed** (pós-microcorreção unmappable) |
| presentation timeline | **179 passed** |
| health | **596 passed** |
| global | **779 passed, 1 skipped** |
| analyze escopo 3C | **No issues found** |
| analyze global | preexistentes fora da 3C; **0** novos na 3C |
| git diff --check | OK |

## 37. Revisão explícita de escopo

| # | Pergunta | Resposta |
|---|----------|----------|
| 1–15 | write, migration, Function, índice, rules, canônica, shell, MainRoot, UI nova, filtros visuais, navegação, busca, alteração 3A/3B, remoção legado | **não** |

Única novidade: source concreta read-only + infraestrutura de paginação multi-fonte.

## 38. Riscos e limitações

1. Fallback `vacinas` opt-in (não prova automática barata de “HE sem vacina”); reader sem índice composto (cap + truncated).
2. orderBy single-field + filtro client-side em empates de data (over-fetch + watermark).
3. ~~Unmappable silencioso~~ — fechado: ativo relevante unmappable → inconclusivo (sem threshold).
4. Sem wiring ao app — validação em produção depende de 3D.
5. Ponte temporária — não é projeção canônica.
6. Title permanece no residual slim (necessário para reemitir linha).

## 39. Pendências 3D / 3E

- Decisão/resolução de fallback vacinação em runtime
- Wiring Histórico + source no shell
- Navegação detail
- Projeção `health_timeline` (futuro server-side)

## 40. Estado final do git

HEAD base: `42bc2ef…` (sem commit 3C). Working tree: somente arquivos 3C novos + auditoria. **Sem commit/push.**

## 41. Conclusão

A 3C implementa a ponte de leitura multi-fonte com paginação global watermark-safe, cursor v2 slim, gates A–K e política **unmappable ativo = inconclusivo**. Correções da auditoria e microcorreção final estão no working tree.

Classificação (pós-auditoria + microcorreção):

# APROVADA PARA COMMIT

Ver `HEALTH_V1_PHASE_3C_AUDIT.md`.