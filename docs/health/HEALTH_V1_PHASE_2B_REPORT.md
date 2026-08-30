# Health v1.0 — Fase 2B — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `9784120f9653f405b42728f76287cb0b813908fd` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0 0` |
| working tree inicial | limpo |

## 2. Referências utilizadas

### Documentos

- `docs/HEALTH_IMPLEMENTATION_ROADMAP.md`
- `docs/HEALTH_V1_ARCHITECTURE.md`
- `docs/health/HEALTH_V1_DOMAIN_MODEL.md` / Readiness Policy / ADR-004 / ADR-005 / ADR-007
- `docs/health/HEALTH_V1_PHASE_2A_REPORT.md` / `AUDIT.md`
- Mockup `01-saude-e-prontidao.png` (apenas para mapear blocos do read model)

### Skills / código existente

- `CLAUDE.md`, convenções Flutter
- `ReadinessStatus` em `health_v1_enums_ext.dart` (5 estados oficiais)
- Foundation 1D (`HealthPresentationStatus` consultado; estado do Resumo é dedicado)
- Shell 2A (não modificado)

## 3. Escopo executado

Camada de **estado e contratos de leitura do Resumo**:

- read models tipados por bloco;
- envelope de dados parciais (`loading` / `available` / `notRecorded` / `unavailable`);
- contrato `HealthSummarySource` observável (`Stream`);
- `HealthSummaryController` com proteção de race por `dogId` + geração;
- estados `initial` / `loading` / `data` / `empty` / `error` / `offline`;
- testes em memória sem Firebase.

**Fora:** Firestore, adapters, UI Dashboard, shell wiring, legado, cálculo de prontidão.

## 4. Arquivos criados

| Caminho | Responsabilidade |
|---------|------------------|
| `lib/.../summary/health_summary_section_status.dart` | Status por bloco + `HealthSummarySectionData<T>` |
| `lib/.../summary/health_summary_block_models.dart` | VOs de prontidão, peso, vacina, tratamentos, atenções, nutrição, tendência, recentes |
| `lib/.../summary/health_summary_source_metadata.dart` | Freshness/origem (`updatedAt`, cache, offline, stale) |
| `lib/.../summary/health_summary_view_data.dart` | Read model composto com `dogId` obrigatório |
| `lib/.../summary/health_summary_state.dart` | Máquina de estado sealed do Resumo |
| `lib/.../summary/health_summary_source.dart` | Interface `watchSummary` + exceção tipada |
| `lib/.../summary/health_summary_controller.dart` | ChangeNotifier keyed por dogId |
| `test/.../summary/fake_health_summary_source.dart` | Fake controlável (só testes) |
| `test/.../summary/health_summary_controller_test.dart` | Suíte 2B |
| `docs/health/HEALTH_V1_PHASE_2B_REPORT.md` | Este relatório |

## 5. Arquivos modificados

Nenhum arquivo preexistente versionado foi modificado.

Shell 2A, foundation 1D, domínio e legado intocados.

## 6. Arquitetura da Fase 2B

```text
HealthSummarySource (contrato Stream)
        ↓
HealthSummaryController (ChangeNotifier)
        ↓
HealthSummaryState (initial|loading|data|empty|error|offline)
        ↓
HealthSummaryViewData (blocos parciais tipados)
        ↓
(futura UI 2C)
```

- Sem Firebase, Maps de domínio, Color/IconData nos read models.
- Controller depende só do contrato + tipos de apresentação.
- Fonte concreta Firestore fica para fase posterior.

## 7. Read models

| Estrutura | Responsabilidade |
|-----------|------------------|
| `HealthSummarySectionData<T>` | Envelope por bloco (status + value + message) |
| `HealthSummaryReadinessView` | Status oficial + reason + restrições resumidas + updatedAt |
| `HealthSummaryWeightView` | peso, data, BCS texto |
| `HealthSummaryVaccinationView` | label resumido, último registro, nextDue |
| `HealthSummaryTreatmentsView` | contagem ativos + resumo principal |
| `HealthSummaryAttentionView` / `Item` | lista prioritária (id, title, subtitle, destinationHint) |
| `HealthSummaryNutritionTodayView` | consumido/meta/refeições |
| `HealthSummaryWeightTrendView` / `Point` | pontos mínimos para gráfico futuro |
| `HealthSummaryRecentRecordsView` / `Record` | poucos registros recentes |
| `HealthSummaryViewData` | composição com `dogId` + metadata |
| `HealthSummarySourceMetadata` | updatedAt, isFromCache, isOffline, isStale |

## 8. Dados parciais

| Status | Significado |
|--------|-------------|
| `loading` | bloco ainda em resolução |
| `available` | valor de apresentação presente |
| `notRecorded` | fonte ok; ausência legítima de registro |
| `unavailable` | falha/impossibilidade de consulta |

O estado **geral** do Resumo pode ser `data` mesmo com blocos `loading`/`unavailable`/`notRecorded`.

## 9. Estado do Resumo

| Estado | dogId | Notas |
|--------|-------|-------|
| `initial` | null | nenhum K9 selecionado |
| `loading` | sim | troca de K9 limpa dados do anterior |
| `data` | via payload | blocos parciais permitidos |
| `empty` | sim | source emitiu `null` |
| `error` | sim | falha; pode carregar `lastKnownData` do mesmo dogId |
| `offline` | sim | pode carregar `cachedData` do mesmo dogId |

**empty ≠ not_evaluated:** prontidão `notEvaluated` com outros blocos available permanece `data`.

**offline ≠ error:** offline = canal/offline tipado; error = falha não-offline (ambos podem reter snapshot do mesmo dogId).

**retry:** `refresh()` reabre observação do dogId ativo (2C: “Tentar novamente”).

## 10. Troca de K9

Estratégia:

1. `selectDog` / `refresh` incrementam `_generation` e definem `_activeDogId`;
2. cancela `StreamSubscription` anterior;
3. emite `loading` imediatamente para o dogId;
4. handlers (`data` / `error` / `done`) validam `generation` + `dogId` + `!disposed`;
5. payload com `dogId` divergente é ignorado;
6. mesmo dogId com sub ativa → no-op; `refresh()` força reconexão;
7. `onDone` limpa `_subscription` (permite reconectar);
8. erro não-offline após data: `HealthSummaryError` com `lastKnownData` do mesmo dogId;
9. `dispose` cancela sub e bloqueia notifies.

## 11. Contrato da fonte

```dart
abstract interface class HealthSummarySource {
  Stream<HealthSummaryViewData?> watchSummary(String dogId);
}
```

- **Stream** para atualização contínua futura e cancelamento de observação.
- `null` → empty; erro com `HealthSummarySourceException(isOffline: true)` → offline.
- Futura implementação concreta (Firestore/projeção) encaixa sem alterar Controller/UI.
- Zero Firebase no contrato.

## 12. Prontidão

- Reutiliza `ReadinessStatus` (`health_v1_enums_ext.dart`).
- Exatamente 5 valores: operational, operationalAttention, fitWithRestrictions, temporarilyUnfit, notEvaluated.
- Sem cálculo local, sem enum duplicado de apresentação.

## 13. Freshness e origem

Campos: `updatedAt`, `isFromCache`, `isOffline`, `isStale`.

**Não implementados:** thresholds rígidos de 5 min / 12 h, decisão de aptidão operacional, bloqueio de turno.

## 14. Testes

Arquivo: `test/features/health/presentation/summary/health_summary_controller_test.dart`  
Fake: `fake_health_summary_source.dart`

| Cenário | Status |
|---------|--------|
| initial | ok |
| loading → data / empty / error / offline | ok |
| offline com cache do mesmo dogId | ok |
| race A→B emissão tardia de A | ok |
| erro tardio de A não contamina B | ok |
| payload dogId divergente ignorado | ok |
| mesmo dogId sem double watch | ok |
| partial data (estado geral data) | ok |
| notRecorded ≠ unavailable | ok |
| 5 readiness statuses | ok |
| not_evaluated ≠ empty | ok |
| dispose + emissão tardia | ok |
| dispose idempotente | ok |

**27 testes** (pós-auditoria), todos passando. Sem Firebase. Inclui retry/refresh, onDone, erro-após-data, cache cross-dog.

## 15. Validações

| Comando | Exit | Resultado |
|---------|------|-----------|
| `dart format` (summary) | 0 | limpo |
| `flutter analyze` (summary 2B) | **0** | No issues found |
| `flutter test` summary 2B | **0** | **16/16** |
| `flutter test test/features/health` | **0** | suíte Health verde |
| `flutter test` (sem pipe) | **0** | **434 passed, 1 skipped** |
| `git diff --check` | **0** | OK |

Analyze global do projeto mantém issues **preexistentes** fora da 2B (mesmo perfil das fases anteriores).

## 16. Revisão de escopo

| Item | OK |
|------|-----|
| zero Firestore/Firebase | sim |
| zero legado (`HealthService` / `HealthLogModel` / ViewModel) | sim |
| zero adapters concretos / dual-read | sim |
| zero Dashboard / widgets mockup | sim |
| zero integração no shell 2A | sim |
| zero writes | sim |
| zero cálculo de prontidão | sim |
| zero dados fake de produção | sim |

## 17. Estado final

| Item | Valor |
|------|--------|
| HEAD | `9784120f9653f405b42728f76287cb0b813908fd` (inalterado) |
| commit | **não criado** |

### Working tree (untracked)

```text
?? lib/features/health/presentation/summary/
?? test/features/health/presentation/summary/
?? docs/health/HEALTH_V1_PHASE_2B_REPORT.md
```

Tracked modificados: **nenhum**.

## 18. Pendências e riscos

1. **Sem fonte concreta** — esperado; 2C/2D e dual-read vêm depois.
2. **Cache offline em memória no Controller** — leve, por dogId da sessão; não é persistência.
3. **UI 2C ainda não consome o estado** — deliberado.

## 19. Conclusão

### Classificação: **APROVADA TECNICAMENTE**

A Fase 2B entrega contratos tipados, estado keyed por dogId, proteção de race, dados parciais e fonte abstrata testável, sem Firebase, sem UI e sem cálculo de prontidão — pronta para revisão humana e posterior Fase 2C.
