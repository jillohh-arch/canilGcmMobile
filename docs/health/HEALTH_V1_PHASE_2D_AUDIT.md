# Health v1.0 — Fase 2D — Auditoria Técnica Adversarial

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `2d7752dac12121ae2fa332ccebd1e1a43b5fd981` |
| commit | `feat(health): add Health v1 summary dashboard` |
| tracking | `origin/feature/health-v1-foundation` 0/0 |
| working tree | apenas artefatos 2D (+ este audit) |

## 2. Arquivos auditados

### 2D

- `coexistence_health_summary_source.dart`
- `health_summary_weight_reader.dart`
- `health_summary_vaccination_reader.dart`
- `health_summary_nutrition_reader.dart`
- `health_summary_recent_records_reader.dart`
- `health_summary_unsafe_sections.dart`
- `health_summary_dog_context_mapper.dart`
- `health_summary_date_parse.dart` (adicionado na auditoria)
- testes `coexistence_health_summary_source_test.dart`
- `HEALTH_V1_PHASE_2D_REPORT.md`

### Legado consultado

WeightHistoryService, HealthService, NutritionService, DogProfileService/VaccineRecord, Dog, WeightRecord, Feeding, HealthLogModel, firestore_date.

## 3. Metodologia

Auditoria adversarial: provar mentira semântica, falha global escondida, fallback perigoso, inconsistência nutrição/recentes, datas, writes ocultos.  
Relatório original **não** tratado como prova.

## 4. Achados

| ID | Sev. | Problema |
|----|------|----------|
| D1 | **ALTA** | Se **todos** os readers mapeáveis falhavam, o source ainda emitia `HealthSummaryViewData` → controller em `HealthSummaryData` com dashboard “válido” e zero fatos (esconde offline/permission total). |
| D2 | **MÉDIA** | `dataVencimento` (vacinas) mapeado para `nextDueAt` → UI 2C rotula como “Próxima dose” (semântica duvidosa). |
| D3 | **MÉDIA** | Recentes só liam `feeding_events`; Nutrição usa dual-read `feeding_events`+`feedings` → card Alimentação podia divergir dos Recentes. |
| D4 | **MÉDIA** | Fallback vacinas em erro de índice mascarava também `permission-denied`/`unavailable` na 2ª tentativa genérica. |
| D5 | **BAIXA** | Parsers de data incompletos (só Timestamp/DateTime em peso; string/map em alguns paths). |
| D6 | **BAIXA** | Queries duplicadas `weight_records` e `health_events` (peso/recentes; vacina/recentes) — consciente, sem cache compartilhado. |
| D7 | **INFO** | `isFromCache: false` não significa “servidor confirmado”; APIs não expõem metadata. |
| D8 | **INFO** | Stream one-shot: sem live push; refresh reabre (adequado à 2D). |
| D9 | **INFO** | `updatedAt` = max de timestamps de registros, não “summary gerado em”. |

**Writes:** grep em 2D — apenas `List.add` / `Duration.add` / `stamps.add`. Nenhum `set`/`update`/`delete` Firestore.

## 5. Correções

| ID | Correção |
|----|----------|
| D1 | Se weight+vaccination+nutrition+recent todos `unavailable` → `HealthSummarySourceException` (controller error/offline, **não** Data). |
| D2 | Vacinas raiz: `nextDueAt: null`; só `nextDueDate` de health_events alimenta nextDue. |
| D3 | Recentes: dual-read `feeding_events` + `feedings`, dedupe por doc id. |
| D4 | Em vacinas, rethrow `permission-denied` / `unauthenticated` / `unavailable` sem segunda query. |
| D5 | `HealthSummaryDateParse` compartilhado (Timestamp, DateTime, ISO, map seconds; **sem** fallback now). |
| — | Nutrição: ignora gramas negativos; meta ≤0 não exposta. |
| — | Testes de falha global, DOB aniversário, alimentação sem plano, date parse. |

## 6. Arquitetura

Confirmada: readers injetáveis → `CoexistenceHealthSummarySource` → contratos 2B. Dashboard 2C intocado. Sem score legado.

## 7. Escopo read-only

Confirmado. Sem Rules/indexes/Functions/migrations/wiring produção.

## 8. Source orchestration

- dogId trim; vazio → ArgumentError  
- one-shot `Stream.fromFuture`  
- peso bundle 1 query  
- pós-correção: all-unavailable → exception  

## 9. Falhas parciais / globais

| Tipo | Comportamento |
|------|----------------|
| Bloco | `unavailable` local |
| Todos mapeáveis unavailable | **global** SourceException |
| UNSAFE fixos (readiness/treatments/attention) | não contam para “tudo falhou” |

## 10–12. Peso / trend

- Só `weight_records`; kg≤0/NaN descartados → se só inválidos → notRecorded  
- Trend mesma leitura; sem meta/BCS  
- limit 30  

## 13–15. Vacina / tratamentos / prontidão / atenções

- Fallback vacinas só se events **vazios e OK**  
- Sem “Em dia”  
- Tratamentos/prontidão/atenções: **unavailable** explícito  

## 16. Nutrição

- notRecorded: sem plano e sem refeições válidas  
- zero real: plano + 0 refeições  
- sem plano + refeições: available, planned null  
- dual-read via NutritionService  

## 17. Registros recentes

- limit 8, sort desc  
- dual feeding alinhado  
- datas inválidas skip  

## 18–19. Datas / metadata

- DateParse sem inventar now  
- isFromCache/isStale false documentados  
- isOffline via exception/heurística de mensagem  

## 20. Dog context

- Mapper puro; idade com dia/mês; DOB futura → null  

## 21. Segurança queries

| Query | Filtro dog |
|-------|------------|
| weight_records | path dogs/{id}/… |
| health_events | path dogs/{id}/… |
| vacinas | `caoId == dogId` |
| feedings* | path dogs/{id}/… |

Índice vacinas: fallback sem orderBy se erro não estrutural.

## 22. Performance (1 watchSummary)

| Op | Notas |
|----|-------|
| weight_records ×1 (bundle) | + ×1 recentes (redundante consciente) |
| health_events ×1 vac + ×1 recentes | redundante consciente |
| vacinas 0–2 | só se events vazios |
| feedings dual (nutrition) | service |
| prescription | service |
| feedings dual (recentes) | 2 queries dia |

## 23. Testes

**23 testes** (antes 17). Cobrem falha global, partial, dogId, unsafe, nutrição sem plano, DOB, date parse, controller ≠ Data.

## 24. Validações finais

| Comando | Exit |
|---------|------|
| format 2D | **0** |
| analyze 2D | **0** |
| test 2D | **0** (23/23) |
| test/features/health | **0** (326) |
| flutter test | **0** (509 passed, 1 skipped) |
| git diff --check | **0** |

## 25. Diferenças vs relatório original

- “17 testes” → **23**  
- Falha global agora **realmente** propaga (antes mentia)  
- nextDue vacinas raiz **removido**  
- Recentes dual-read feedings  
- Date parse unificado  

## 26. Riscos restantes

- Redundância de queries (D6) sem shared cache  
- isFromCache sempre false  
- One-shot stream  
- Índices Firestore dependentes do ambiente  

## 27. Pendências 2E

- Wiring K9 + source no shell  
- Opcional streams contínuos  
- Shared load health_events/weight entre readers se latência importar  

## 28. Conclusão

# APROVADA PARA COMMIT

Nenhum achado crítico/alto/médio **pendente** após correções D1–D5.  

A pergunta da auditoria — *“pode parecer verdade sem prova?”* — para os blocos mapeáveis: **não** com a política atual; blocos sem prova permanecem **unavailable**.  

**Sem commit** nesta sessão.
