# Health v1.0 — Fase 2D — Relatório de Implementação

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD inicial | `2d7752dac12121ae2fa332ccebd1e1a43b5fd981` |
| commit base | `feat(health): add Health v1 summary dashboard` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0 0` |
| working tree inicial | limpo |

## 2. Referências utilizadas

- CLAUDE.md, flutter-canil-conventions, canil-k9-context
- Roadmap, Architecture, Module Audit, Baseline, Capabilities, Migration Plan, Schema, Domain Model, Readiness Policy, Permission Matrix
- ADR-001 … ADR-007 (especialmente ADR-004, ADR-005, ADR-006)
- Relatórios/auditorias 2A–2C
- Código 2B/2C em `presentation/summary/`
- Services reais: `WeightHistoryService`, `HealthService`, `NutritionService`, `DogProfileService` (vacinas), model `Dog`

## 3. Auditoria das fontes atuais

| Domínio | Onde | Service/model | Stream? | Observação |
|---------|------|---------------|---------|------------|
| Cadastro K9 | `dogs/{id}` | `Dog` | via DogService (não usado no Dashboard) | Campos name/breed/sex/DOB/photo |
| Peso | `dogs/{id}/weight_records` | WeightHistoryService | `watchHistory` | Canônico mobile; legado `weight_history` existe mas **não** mesclado |
| Vacina (eventos) | `dogs/{id}/health_events` type vaccination | HealthService | one-shot | CRUD ativo |
| Vacina (raiz) | `vacinas` + `caoId` | DogProfileService.getVaccines | one-shot | Fallback; status string livre |
| Nutrição | `feeding_events` + `feedings` + prescriptions | NutritionService | watchToday / getFeedings | Dual-read legado já no service |
| Health genérico | `health_events` | HealthService | one-shot | Tipos livres; medicação ≠ protocolo |
| Score/prontidão | `Dog.calculateReadiness` | legado | — | **Proibido** mapear para ReadinessStatus |
| Agenda | não usada na 2D | — | — | Sem fonte segura de “atenções” sem heurística |
| Projeção v1 | vaccination_records, readiness_snapshot | **ainda não populadas no mobile** | — | Fora da coexistência atual |

## 4. Matriz SAFE / PARTIAL / UNSAFE

| Bloco 2B | Fonte | Class. | Estratégia |
|----------|-------|--------|------------|
| weight | weight_records | **SAFE** | latest valid kg>0; vazio→notRecorded; erro→unavailable |
| weightTrend | weight_records | **PARTIAL** | pontos ordenados; sem meta/BCS inventados |
| vaccination | health_events → vacinas | **PARTIAL** | lastRecordLabel + nextDueAt; **sem** summaryLabel inventado |
| nutritionToday | feedings + prescription | **SAFE/PARTIAL** | soma g, refeições, meta da prescrição; zero real vs notRecorded |
| recentRecords | health_events + weight + feedings | **PARTIAL** | composição limitada (8); fatos só |
| readiness | — | **UNSAFE** | `unavailable` (não notEvaluated inventado) |
| treatments | — | **UNSAFE** | `unavailable` (evento genérico ≠ protocolo) |
| attention | — | **UNSAFE** | `unavailable` (sem engine/heurística) |
| dogContext | Dog model | **SAFE** | mapper puro (2E consumirá) |

## 5. Arquitetura implementada

```text
weight_records / health_events / vacinas / feeding_events / prescriptions
        ↓ (somente leitura)
HealthSummary*Reader (coexistence)
        ↓
CoexistenceHealthSummarySource  implements HealthSummarySource
        ↓
HealthSummaryViewData (blocos parciais)
        ↓
HealthSummaryController (2B) → Dashboard (2C)  [não alterados]
```

Mapper separado:

`HealthSummaryDogContextMapper.fromDog(Dog)` → `HealthSummaryDogContextView`

## 6. Arquivos criados

| Caminho | Papel |
|---------|-------|
| `lib/.../coexistence/summary/coexistence_health_summary_source.dart` | Fonte concreta 2D |
| `health_summary_weight_reader.dart` | Peso + tendência |
| `health_summary_vaccination_reader.dart` | Vacinação conservadora |
| `health_summary_nutrition_reader.dart` | Nutrição do dia |
| `health_summary_recent_records_reader.dart` | Recentes compostos |
| `health_summary_unsafe_sections.dart` | readiness/treatments/attention unavailable |
| `health_summary_dog_context_mapper.dart` | Mapper puro Dog→contexto |
| `test/.../coexistence_health_summary_source_test.dart` | 17 testes |
| `docs/health/HEALTH_V1_PHASE_2D_REPORT.md` | Este relatório |

## 7. Arquivos modificados

**Nenhum** arquivo 2A/2B/2C/legado de produção pré-existente modificado.

## 8. CoexistenceHealthSummarySource

- Implementa `watchSummary(String dogId)`.
- Stream one-shot via `Stream.fromFuture` (refresh/selectDog do controller reabre).
- dogId vazio → `ArgumentError` na stream.
- Payload sempre no dogId solicitado.
- Parallel load de readers; peso atual+tendência em **uma** query (`readBundle`).
- **Falha estrutural:** se weight + vaccination + nutrition + recent estão **todos** `unavailable`, propaga `HealthSummarySourceException` (não emite Data “vazio de fatos”).
- Sem writes.

## 9. Readers/adapters

Injetáveis via `loadSamples` / `loadFacts` / `loadDaySnapshot` / `loadItems` para testes sem Firebase.

Default production path usa Firestore / NutritionService **somente em métodos de leitura**.

## 10. Fonte de peso

`dogs/{dogId}/weight_records` ordenado por `measured_at`.

Descarta kg ≤ 0 ou não finito (protege UI; `WeightRecord.fromJson` pode defaultar 0).

## 11. Evolução do peso

Mesma autoridade; pontos asc; sem targetWeightKg / bodyConditionScore.

## 12. Vacinação

1. health_events type vaccination  
2. fallback vacinas **somente se events vazios com sucesso** (falha estrutural não é mascarada)  
Sem `summaryLabel` (“Em dia”).  
`lastRecordLabel` = nome/subtype.  
`nextDueAt` **somente** de `nextDueDate` em health_events — **não** de `dataVencimento` em vacinas (evita “Próxima dose” falsa na UI 2C).

## 13. Tratamentos

**unavailable** — legado não prova `activeProtocolCount` de protocolo terapêutico.

## 14. Prontidão

**unavailable** — não usa score legado; não inventa `notEvaluated` como “não sabemos”.

## 15. Atenções

**unavailable** — sem fonte prioritária segura sem mini-engine.

## 16. Nutrição

- sem plano e sem refeições → **notRecorded**  
- com plano e 0 refeições → **available** com consumed=0 (zero real)  
- unitLabel `g`  
- sem lista de refeições individuais no VO

## 17. Registros recentes

Composição: health_events + weight_records + dual-read `feeding_events`/`feedings` do dia (alinhado ao NutritionService); dedupe por id; limit 8; sort desc.

## 18. Metadata / cache / offline

| Campo | Valor 2D |
|-------|----------|
| updatedAt | max timestamps disponíveis (peso/recentes) se houver |
| isFromCache | false (não exposto pelas APIs) |
| isOffline | false (exceto se FirebaseException `unavailable` em falha estrutural) |
| isStale | false (sem política aprovada) |

Sem thresholds 5 min / 12 h.

## 19. Contexto do K9

Mapper puro; sem DogService no Dashboard; sem Dog em ViewData.

## 20. Falhas parciais

Cada reader captura erro → section `unavailable`. Source ainda emite `HealthSummaryViewData` completo.

## 21. Falhas globais

`FirebaseException` não capturada no orquestrador → `HealthSummarySourceException` (controller trata offline se `code == unavailable`).

Na prática, readers absorvem a maioria dos erros de bloco.

## 22. Performance / listeners

- Queries one-shot por `watchSummary` / refresh.
- Peso: 1 query (bundle).
- Vacina: até 2 tentativas (events + vacinas).
- Nutrição: feedings (dual coleção via service) + prescription.
- Recentes: 3 queries paralelas.
- **Sem** listeners longos abertos na 2D (evita fan-out; documentado para 2E).

## 23. Testes

Arquivo: `test/features/health/data/coexistence/summary/coexistence_health_summary_source_test.dart`

**23 testes** (pós-auditoria), sem Firebase real:

- mapper dog/idade/aniversário/DOB futura  
- date parse  
- peso valid/empty/fail  
- vacina sem inventar label  
- nutrição zero real / soma / notRecorded / sem plano  
- recentes limit/order  
- unsafe sections  
- source parcial + falha global + controller ≠ Data  
- dogId  

## 24. Validações (exit codes reais)

Pós-auditoria:

| Comando | Exit | Resultado |
|---------|------|-----------|
| `dart format --set-exit-if-changed` (2D) | **0** | limpo |
| `flutter analyze` coexistence 2D | **0** | No issues found |
| `flutter test` coexistence 2D | **0** | **23/23** |
| `flutter test test/features/health` | **0** | **326** passed |
| `flutter test` global | **0** | **509 passed, 1 skipped** |
| `git diff --check` | **0** | OK |

Ver também `docs/health/HEALTH_V1_PHASE_2D_AUDIT.md`.

Analyze global: issues preexistentes fora da 2D; **0 novos** na 2D.

## 25. Revisão explícita de escopo

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | write? | **não** |
| 2 | migration? | **não** |
| 3 | projeção canônica? | **não** |
| 4 | cálculo readiness? | **não** |
| 5 | score legado como readiness? | **não** |
| 6 | wiring produção? | **não** |
| 7 | alteração 2A? | **não** |
| 8 | alteração contratos 2B? | **não** |
| 9 | alteração visual 2C? | **não** |
| 10 | fake em produção? | **não** (só testes) |
| 11 | Rules/Functions/indexes? | **não** |
| 12 | bloco com info não comprovável? | **não** (UNSAFE → unavailable) |

## 26. Riscos e limitações

1. Stream one-shot: UI não atualiza em tempo real até refresh (intencional na 2D).  
2. Índices compostos de `vacinas` podem falhar → fallback sem orderBy.  
3. Dual-coleção de feedings herda comportamento do NutritionService (dedupe).  
4. Recentes de feeding só `feeding_events` do dia (não merge `feedings` na query de recentes) — aceitável e documentado.  
5. `WeightRecord.fromJson` com default 0 é filtrado no reader, não corrigido no model legado.

## 27. Itens deliberadamente não mapeados

- ReadinessStatus a partir de score  
- Tratamentos / protocolos  
- Atenções / alertas heurísticos  
- summaryLabel “Em dia”  
- Meta/BCS no weight trend  
- Refeições individuais no VO de nutrição  

## 28. Pendências Fase 2E

- Wiring do K9 ativo + `DogContext` + `selectDog`  
- Instanciar `CoexistenceHealthSummarySource` no shell real (sem trocar navegação global sem gate)  
- Opcional: streams contínuos peso/nutrição  
- Futuro: trocar por projeção canônica quando existir  

## 29. Estado final do git

Working tree com untracked/modified da 2D apenas (sem commit nesta fase).

## 30. Conclusão técnica

A Fase 2D entrega a **ponte read-only de coexistência** entre fontes reais e os contratos 2B, de forma conservadora: cards SAFE/PARTIAL preenchidos com fatos; blocos UNSAFE explicitamente `unavailable` em vez de mentir.

Classificação:

# PRONTA PARA AUDITORIA
