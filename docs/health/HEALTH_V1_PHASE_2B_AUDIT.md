# Health v1.0 — Fase 2B — Auditoria Técnica Final

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `9784120f9653f405b42728f76287cb0b813908fd` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0 0` |
| working tree | untracked apenas da 2B (+ relatório/auditoria) |
| tracked modificados | nenhum |

Untracked esperado: `lib/.../summary/`, `test/.../summary/`, `docs/health/HEALTH_V1_PHASE_2B_REPORT.md`, e este audit.

## 2. Arquivos auditados

### Produção

- `health_summary_section_status.dart`
- `health_summary_block_models.dart`
- `health_summary_source_metadata.dart`
- `health_summary_view_data.dart`
- `health_summary_state.dart`
- `health_summary_source.dart`
- `health_summary_controller.dart`

### Testes

- `fake_health_summary_source.dart`
- `health_summary_controller_test.dart`

### Relatório

- `docs/health/HEALTH_V1_PHASE_2B_REPORT.md`

## 3. Achados

### A1 — Retry do mesmo dogId após error impossível via `selectDog`

| Campo | Valor |
|-------|--------|
| ID | A1 |
| severidade | **Alta** |
| arquivo | `health_summary_controller.dart` |
| problema | Com `_subscription != null` e mesmo dogId, `selectDog` era no-op. Após erro (`cancelOnError: false`), a sub permanecia ativa → UI sem caminho de “Tentar novamente”. |
| impacto | 2C não conseguiria retry sem trocar de K9 |
| correção | API `refresh()` força reconexão do dogId ativo; documentado que `selectDog` mesmo id só reconecta se sub for nula (`onDone`). |

### A2 — `onDone` não limpa subscription

| Campo | Valor |
|-------|--------|
| ID | A2 |
| severidade | **Média** |
| arquivo | `health_summary_controller.dart` |
| problema | Stream finalizada deixava `_subscription` não-nula → mesmo dogId não reconectava. |
| correção | `onDone` limpa `_subscription` se generation/dogId atuais. |

### A3 — Erro após data descartava payload conhecido

| Campo | Valor |
|-------|--------|
| ID | A3 |
| severidade | **Média** |
| arquivo | `health_summary_state.dart`, controller |
| problema | Erro não-offline após `data` virava `HealthSummaryError` sem último snapshot → UI perdia contexto. |
| correção | Política deliberada: `HealthSummaryError.lastKnownData` (mesmo dogId). Offline continua com `cachedData`. Readiness embutida **não** é recalculada. |

### A4 — Cache cross-dog não testado explicitamente

| Campo | Valor |
|-------|--------|
| ID | A4 |
| severidade | **Média** (gap de prova; implementação já keyed) |
| arquivo | testes |
| problema | Cache por dogId existia, mas isolamento A→B offline não era coberto. |
| correção | Testes: B offline sem cache; B offline com cache só de B. |

### A5 — Invariantes de SectionData / read models fracos em borda

| Campo | Valor |
|-------|--------|
| ID | A5 |
| severidade | **Baixa** |
| arquivo | section_status, block_models |
| problema | Factories já eram privadas no `_`; falta de `valueOrNull` e validação de peso/contagem negativos. |
| correção | Docs + `valueOrNull`; rejeição de `weightKg` inválido e `activeProtocolCount < 0`. |

### A6 — Semântica dual offline / metadata.isOffline pouco documentada

| Campo | Valor |
|-------|--------|
| ID | A6 |
| severidade | **Info** (contrato, não bug) |
| arquivo | controller, metadata, state |
| problema | Dois conceitos offline sem política escrita. |
| correção | Documentado: `State.offline` = canal/UI atual; `metadata.isOffline` = provenance do snapshot. Combinações válidas testadas. |

## 4. Arquitetura geral

| Peça | Avaliação |
|------|-----------|
| Source Stream | Adequada; fakeável; sem Firebase |
| Controller ChangeNotifier | Coerente com o app |
| States sealed | dogId em todos os não-initial |
| Read models | Compostos, tipados, sem Maps |

Não é monolito; não acopla UI/shell.

## 5. Invariantes de dados parciais

### Original

- Factories controladas (`loading` / `available` / `notRecorded` / `unavailable`).
- Construtor público `_` privado.

### Estados impossíveis

Não expressáveis pela API: available sem argumento; loading/notRecorded/unavailable com value.

### Decisão

Manter factories; reforçar docs + `valueOrNull`.

### Correções

Documentação e testes de factories.

## 6. Retry e reconexão

| Situação | Comportamento final |
|----------|---------------------|
| error + `selectDog` mesmo id | no-op se sub ativa |
| error + `refresh()` | nova sub, loading → data possível |
| onDone + `selectDog` mesmo id | reconecta (sub null) |
| refresh sem dogId | `StateError` |
| refresh após A→B | só B |

## 7. Erro após dados válidos

**Política adotada:**

- Offline tipado → `HealthSummaryOffline` + cache do **mesmo** dogId.
- Erro não-offline → `HealthSummaryError` + `lastKnownData` do **mesmo** dogId (se houver).
- Não altera readiness embutida.
- Não usa cache de outro K9.

## 8. Cache por dogId

- Estrutura: `Map<String, HealthSummaryViewData> _lastDataByDogId`.
- Escrita só após validar `payload.dogId == dogId` ativo da geração.
- Offline B sem entradas → `cachedData == null` mesmo se A tiver cache.

## 9. Offline vs metadata

| Conceito | Fonte de verdade |
|----------|------------------|
| `HealthSummaryOffline` | Estado atual do canal para a UI |
| `metadata.isOffline` | Marca do snapshot emitido pela fonte |
| `state=data` + `metadata.isOffline=true` | **Inválido na prática** — controller mapeia esse snapshot para `offline` |
| `state=offline` + `cachedData.metadata.isOffline=false` | **Válido** — cache de quando estava online + canal offline agora |

## 10. Race conditions

Camadas: `cancel()` + `_generation` + `_activeDogId` + match de `payload.dogId`.

`generation` é a barreira definitiva para eventos enfileirados após cancel.

Testado: data/erro/done tardios de A com B ativo.

## 11. Lifecycle e dispose

- Cancel no switch e no dispose.
- `onDone` limpa sub.
- Pós-dispose: `_disposed` bloqueia notify e handlers.
- Dispose idempotente.

## 12. Read models

- Readiness: enum oficial 5 estados, sem cálculo.
- Freshness: transportada, sem thresholds 5min/12h.
- Peso/contagens: rejeição de negativos óbvios.

## 13. Testes

### Original (16)

Cobriam fluxo básico e race principal; **lacunas** em retry, onDone, erro-após-data, cache cross-dog.

### Pós-auditoria

**27 testes**, incluindo:

- retry/refresh
- onDone + reconnect
- erro após data + lastKnownData
- cache A≠B offline
- SectionData factories
- dogId vazio
- metadata.isOffline → offline state

## 14. Dependências e escopo

| Item | OK |
|------|-----|
| zero Firebase/Firestore | sim |
| zero legado | sim |
| zero Dashboard / shell wiring | sim |
| zero cálculo de prontidão | sim |
| zero dados fake em produção | sim |

## 15. Correções realizadas

| Arquivo | Alteração | Motivo |
|---------|-----------|--------|
| `health_summary_controller.dart` | `refresh()`, `onDone`, erro com cache | A1–A3 |
| `health_summary_state.dart` | `lastKnownData` em Error | A3 |
| `health_summary_section_status.dart` | docs + `valueOrNull` | A5 |
| `health_summary_block_models.dart` | validação peso/contagem | A5 |
| `fake_health_summary_source.dart` | `complete()` para onDone | testes |
| `health_summary_controller_test.dart` | suite expandida | A1–A4 |
| `HEALTH_V1_PHASE_2B_REPORT.md` | troca de K9 / refresh | A6 |

## 16. Validações finais

| Comando | Exit | Resultado |
|---------|------|-----------|
| format summary | 0 | limpo |
| `flutter test` summary | **0** | **27 passed** |
| analyze summary | **0** | No issues |
| `flutter test test/features/health` | **0** | **262 passed** |
| `flutter test` | **0** | **445 passed, 1 skipped** |
| `git diff --check` | **0** | OK |
| `flutter analyze` (projeto) | **1** | ~37 issues preexistentes; **0** na 2B |

## 17. Estado final

| Item | Valor |
|------|--------|
| HEAD | `9784120…` (inalterado) |
| commit | **não criado** |

Untracked: summary lib/test + relatórios 2B.

## 18. Diferenças em relação ao relatório original

| Afirmação | Veredito |
|-----------|----------|
| Stream source + ChangeNotifier | Confirmado |
| Race A→B protegida | Confirmado |
| Partial data | Confirmado |
| 5 readiness | Confirmado |
| selectDog no-op mesmo id | Confirmado **com nuance** — bloqueava retry; **corrigido** com `refresh`/`onDone` |
| Erro descarta data | **Corrigido** → lastKnownData |
| 16 testes | **Desatualizado** → 27 |

## 19. Riscos restantes

1. Cache só em memória de sessão — esperado.
2. Fonte concreta ainda inexistente — 2C/2D.
3. UI 2C deve preferir `refresh()` para retry, não re-`selectDog` com sub viva.

## 20. Conclusão

### Classificação: **APROVADA PARA COMMIT**

Achados altos/médios (retry, onDone, erro-após-data, cache tests) foram corrigidos e cobertos por testes. Contrato está apto para a Fase 2C. Zero Firebase/legado/UI. Sem commit nesta auditoria.
