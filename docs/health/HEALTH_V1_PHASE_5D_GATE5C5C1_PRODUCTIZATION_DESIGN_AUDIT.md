# FASE 5D — GATE 5C.5C.1
## PRODUCTIZATION DESIGN & EXPOSURE AUDIT

**Data:** 2026-07-22
**Branch:** `feature/health-v1-foundation`
**Baseline:** `1dde79b0daa006035cfd3b749147624ec4f4ab23`
**Status:** HUMAN AUDIT APPROVED
**Natureza:** auditoria e desenho; nenhuma implementação ou exposição

---

## 1. Preflight

```text
branch:      feature/health-v1-foundation
HEAD:        1dde79b0daa006035cfd3b749147624ec4f4ab23
subject:     feat(health): validate timeline projection behavior
divergence:  1 0 (HEAD...origin/feature/health-v1-foundation)
status:      ?? functions/audit_prod.mjs
```

`functions/audit_prod.mjs` foi preservado, não modificado e não staged. Não havia
outro arquivo inesperado no preflight.

## 2. Sources reviewed

### 2.1 Contratos e decisões

| Fonte | Estado relevante | Uso nesta auditoria |
|---|---|---|
| `docs/HEALTH_V1_ARCHITECTURE.md` | Arquitetura aprovada, jul/2026 | Princípios Health, timeline única e separação Web/Mobile |
| `HEALTH_V1_FIRESTORE_SCHEMA.md` | Aprovado, 2026-07-14 | Paths, campos, writers/readers e índices conceituais |
| `HEALTH_V1_DOMAIN_MODEL.md` | Aprovado, 2026-07-14 | MealLog, SupplementLog e projeções read-only |
| `HEALTH_V1_READINESS_POLICY.md` | Aprovado, 2026-07-14 | Projeção para display não substitui fonte canônica |
| `HEALTH_V1_PERMISSION_MATRIX.md` | Aprovado, com mapping de perfis provisório | `health.read` conceitual e writes de projeção via Function |
| `HEALTH_V1_MIGRATION_PLAN.md` | Aprovado, 2026-07-14 | Migração aditiva, idempotente e sem backfill neste Gate |
| `HEALTH_V1_TEST_STRATEGY.md` | Aprovado, 2026-07-14 | Gates de Functions, Rules, concorrência e regressão |
| `HEALTH_V1_CAPABILITIES_INVENTORY.md` | Proposto, inventário do runtime real | Capabilities granulares Health ainda não implantadas |
| `HEALTH_V1_FOUNDATION_REVIEW.md` | Aprovado | Decisões humanas, O3 e limites de exposição |
| ADR-001 | Aprovado | Limites de domínio e agregados canônicos |
| ADR-002 | Aprovado | Imutabilidade, correções e ausência de hard delete |
| ADR-004 | Aprovado | Timeline materializada server-side e path aninhado |
| ADR-005 | Aprovado | Projeção não é autoridade canônica |
| ADR-006 | Aprovado | Coexistência, zero mutação legada e idempotência |
| ADR-007 | Proposto | Organização interna Mobile; não impõe layout de Functions |
| Relatório 5C.5B.2 | Human Audit Approved, 2026-07-22 | O3-D1–D8 e comportamento congelado/validado |

### 2.2 Código e configuração

- `functions/src/index.ts`;
- `functions/src/health_timeline_projection.ts`;
- `functions/src/health_timeline_projection_test.ts`;
- `functions/src/health_timeline_emulator_test.ts`;
- módulos `health_nutrition_*` e `health_schedule_*`;
- `functions/package.json`, `firebase.json` e tipos instalados de `firebase-functions`;
- `firestore.rules` e `firestore.indexes.json`;
- exposição remota via `firebase functions:list --project canil-gcm`.

### 2.3 Precedência aplicada

1. O relatório 5C.5B.2 prevalece para decisões O3 congeladas: granularidade,
   retenção, cadência diária, `source_collection`, deterministic ID, dedupe e
   tratamento de `nutrition_supplements`.
2. Schema + ADR-004 + Permission Matrix prevalecem para o **path de destino**:
   o harness não tinha autoridade para trocar a topologia oficial.
3. Código/Rules atuais prevalecem ao descrever região, runtime e autorização
   efetivamente implantada; capabilities documentais não são tratadas como grants reais.
4. ADR-006 e Migration Plan prevalecem para zero mutação de fonte, zero legacy
   write e ausência de backfill neste Gate.

## 3. Canonical timeline path decision

**Decisão inequívoca:**

```text
dogs/{dogId}/health_timeline/{timelineId}
```

Evidência convergente:

- Schema §1 posiciona todas as coleções Health sob `dogs/{dogId}` e lista a
  subcoleção `health_timeline`;
- ADR-004 §13 materializa explicitamente esse path;
- Permission Matrix §7 aplica autorização dog-scoped ao mesmo path;
- Domain Model remete ao Schema para a definição completa da projeção.

O uso de `health_timeline/{timelineId}` no Emulator 5C.5B.2 é uma implementação
de harness. O3-D5 congelou o path da **fonte** em `source_collection`; não congelou
um destino top-level. A productization deve adaptar o destino sem alterar o hash:
o `timelineId` continua derivado de `source_collection + source_id`.

## 4. Current Functions architecture

- Runtime: Node.js 22; Firebase Functions v2; `firebase-admin` inicializado uma vez
  em `index.ts`.
- Região canônica no backend atual: `southamerica-east1`.
- Exposição: exports camelCase em `index.ts`; handlers/engines Health ficam em
  módulos internos e wrappers finos são exportados.
- Triggers existentes usam `onDocumentCreated`/`onDocumentUpdated`; jobs usam
  `onSchedule`; chamadas Health usam `onCall`.
- Logging produtivo usa `firebase-functions/logger`; `console` aparece no harness.
- Erros de callable são convertidos para `HttpsError`; triggers futuros não devem
  usar semântica HTTP.
- Mutações Health/Nutrition usam Admin SDK, transações, receipt durável,
  fingerprint/idempotency key e um audit por operação lógica.
- O SDK instalado suporta `retry` em event handlers e política de retry/backoff em
  scheduler.

Nenhum ciclo existe hoje: `health_timeline_projection.ts` depende apenas de
`crypto`. O layout futuro deve manter `index.ts -> trigger wrappers -> runtime ->
pure projection`; runtime nunca importa `index.ts` nem os callables de Nutrition.

## 5. Trigger integration design

### 5.1 Definições futuras

| Function recomendada | Trigger exato | Opções |
|---|---|---|
| `healthTimelineProjectMealLogCreated` | `dogs/{dogId}/meal_logs/{mealId}` | v2, `southamerica-east1`, `retry: true` |
| `healthTimelineProjectSupplementLogCreated` | `dogs/{dogId}/supplement_logs/{supplementLogId}` | v2, `southamerica-east1`, `retry: true` |

### 5.2 Handler

1. Extrair `dogId` e source ID somente dos params e confirmar que batem com a ref.
2. Fixar o source type pelo wrapper; nunca aceitar `source_collection` do payload.
3. Validar snapshot e campos obrigatórios; normalizar Firestore `Timestamp` para
   ISO apenas na fronteira da função pura.
4. Derivar `source_collection` por enum fechado e calcular o ID O3 congelado.
5. Materializar em `dogs/{dogId}/health_timeline/{timelineId}` usando transação.
6. Dentro da transação: ler entry; MISSING → create; EQUIVALENT → no-op;
   DIVERGENT → repair; preservar `created_at` quando aplicável; atualizar
   `projected_at` somente quando houver write.
7. Serializar campos temporais de volta para Firestore `Timestamp` e persistir
   somente o contrato canônico.

### 5.3 Casos operacionais

| Caso | Comportamento |
|---|---|
| Evento duplicado/retry | Mesma transação e ID; segunda entrega termina em no-op |
| Falha transitória de infraestrutura | Throw; entrega deve ser repetida |
| Snapshot ausente por falha transitória | Log estruturado, throw e retry; zero write |
| Payload deterministicamente inválido | Registrar anomaly e retornar sucesso; zero timeline write e zero poison retry |
| Falha ao persistir anomaly | Throw e retry; a anomalia não pode ser perdida silenciosamente |
| Duas invocações iguais | Transação serializa; create + no-op |
| Trigger × reconciliation | Ambos usam a mesma primitiva transacional e convergem |
| Entry equivalente | Zero write; `projected_at` preservado |
| Entry divergente | Repair transacional + warning/métrica |
| Timeout após commit | Retry encontra equivalente e não duplica |
| Fonte canônica | Nunca atualizada, cancelada ou deletada pelo projector |

## 6. ProjectionEngine runtime reuse assessment

### 6.1 Reutilizável diretamente

- `deriveTimelineId` e golden vector;
- `projectMealLog` e `projectSupplementLog` como transformação pura;
- `compareProjection` e `determineProjectionAction`;
- decisões de equivalência e presentation mapping validadas.

### 6.2 Não reutilizável diretamente

- `ProjectionEngine` e `ReconciliationEngine` estão dentro do arquivo E2E;
- eles escrevem em coleção top-level e fazem read-then-write não transacional;
- representam timestamps como strings, enquanto o Schema exige Timestamp;
- `health_timeline_metadata` e `TEST_CONFIG` são harness/test only;
- orphan resolver atual assume MealLog, não valida path e referencia constante de teste;
- o tipo `SourceCollection` aceita `string` arbitrária no derivador e contém nomes
  além do pipeline atual.

### 6.3 Camada legítima

Criar um adapter/runtime Firestore separado. Ele deve:

- validar e converter snapshots;
- construir paths a partir de enums fechados;
- selecionar o path aninhado canônico;
- serializar/deserializar Timestamp;
- executar transações e structured logging;
- receber clock/anomaly sink/config por dependência para testes;
- nunca importar `TEST_CONFIG`.

O adapter pode usar ISO internamente na fronteira com as funções puras, mas deve
persistir `occurred_at`, `recorded_at` e `projected_at` como Firestore `Timestamp`.
O serializer usa allowlist explícita do schema: nenhum helper interno, configuração
de teste, propriedade `undefined` ou campo fora do contrato pode escapar para
`health_timeline`.

Não há justificativa para duplicar o algoritmo O3 ou criar outra projeção paralela.

## 7. Reconciliation persistence/state design

### 7.1 Path interno recomendado

```text
_health_projection_state/health_timeline_v1
  /passes/{sourceType_passName}
  /runs/{runId}
  /discrepancies/{discrepancyId}
```

É estado administrativo backend-only, não timeline e não fonte canônica. O nome
`health_timeline_metadata` do prototype não vira contrato produtivo.

### 7.2 Granularidade

- estado **global por source type e por pass**;
- `meal_logs` e `supplement_logs` nunca compartilham cursor;
- forward, overlap e historical possuem documentos independentes;
- orphan possui cursor próprio sobre collection group `health_timeline`;
- run/lease é global para impedir dois schedulers do mesmo pipeline;
- discrepâncias são documentos independentes e idempotentes.

Queries globais usam collection group e extraem `dogId` da ref real. Isso evita
listar todos os K9 e mantém cada página bounded.

### 7.3 Estado mínimo por pass

- `pipeline_version`, `source_type`, `pass_type`;
- cursor completo (`recorded_at`, full document name) quando temporal;
- `last_document_name` quando histórico/orphan;
- `window_start/window_end` no overlap;
- `cycle`, `completed_at`, `last_success_at`, `last_error_at`;
- `lease_owner`, `lease_expires_at`, `revision`;
- contadores observacionais, nunca usados como prova de consistência.

## 8. Partial failure strategy

- O cursor nunca é gravado antes do item.
- Cada item é re-lido e processado em transação com a entry e o documento de
  cursor. Projeção + avanço do cursor são atômicos.
- Falha antes do commit não avança; retry repete o item.
- Falha de resposta depois do commit reprocessa e encontra no-op.
- Erro permanente de payload gera discrepancy durável e permite avanço explícito
  como `skipped_anomaly`; não fica invisível nem bloqueia eternamente o pipeline.
- Scheduler adquire lease transacional com expiração; invocation concorrente sai
  sem executar. Retry é bounded e todo trabalho permanece idempotente.
- Forward recebe orçamento reservado em toda execução. Overlap, historical e
  orphan têm páginas próprias; nenhum consome o cursor/orçamento do forward.
- Overlap usa cursor completo `(recorded_at, documentName)`, janela fixa da rodada
  e reseta somente quando a janela termina; nunca retrocede o forward.
- Historical faz wrap real: página curta encerra o ciclo, incrementa `cycle` e a
  próxima rodada reinicia do início. Nenhuma rodada faz full scan.
- Orphan usa cursor independente e apenas abre/atualiza alerta; nunca deleta.

## 9. Orphan safety model

Allowlist fechada deste pipeline:

```text
meal       -> dogs/{sameDogId}/meal_logs
supplement -> dogs/{sameDogId}/supplement_logs
```

Validações antes de qualquer dereference:

1. A entry precisa estar fisicamente em `dogs/{dogId}/health_timeline/{id}`.
2. `entry.dog_id` deve ser exatamente o mesmo `dogId` do parent.
3. `source_collection` deve ser exatamente um dos dois paths allowlisted com o
   mesmo dogId; não se usa `db.doc(entry.source_collection + ...)`.
4. `source_id` deve ser string não vazia, sem `/`, dentro dos limites de document ID.
5. `timeline_type` deve corresponder ao source type.
6. O timeline ID deve ser recalculado e coincidir com o document ID.

Cross-dog, path malformado, source type desconhecido, source ID inválido ou entry
malformada produzem `ANOMALY/ALERT`, sem crash, delete ou dereference. Apenas após
validação o runtime monta a ref via `dogRef.collection(allowlistedName).doc(id)`.

## 10. Rules design

Path futuro:

```rules
match /dogs/{dogId}/health_timeline/{timelineId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}

match /_health_projection_state/{document=**} {
  allow read, write: if false;
}
```

A Permission Matrix propõe `health.read`, mas o inventário e o runtime atual não
possuem esse grant granular implantado. Agenda, Nutrition e demais reads dog-scoped
usam hoje `signedIn() && canAccessDogRecord(dogId)`. Para não quebrar clientes nem
inventar grants, o Gate 5C.5C.4 deve preservar esse predicado operacional. A futura
adoção de `health.read` exige gate próprio de mapping/migração de profiles.

Leitura deve ser por subcoleção de um K9 específico. Client collection-group query
de todas as timelines não é autorizada. A topologia aninhada permite às Rules provar
o dog scope da query.

## 11. Index design

### QUERY APROVADA / ÍNDICE CANDIDATO A PROVAR

| Query | Candidato para validação no 5C.5C.4 |
|---|---|
| Forward `meal_logs` collection group | Estratégia `recorded_at ASC, __name__ ASC`; definição física ainda não congelada |
| Forward `supplement_logs` collection group | Estratégia `recorded_at ASC, __name__ ASC`; definição física ainda não congelada |
| Overlap dos dois source types | Mesma estratégia de query do forward; reutilização de índice deve ser provada |

### ÍNDICE NÃO ESPERADO, MAS AINDA SUJEITO À PROVA

| Query | Razão |
|---|---|
| Timeline dog-scoped `occurred_at DESC` | Espera-se índice single-field automático |
| Historical por `__name__` | Ordenação apenas por document name |
| Orphan por `__name__` em collection group | Sem filtro composto no desenho inicial |

### AINDA INDEFINIDO / POSTERIOR

- `timeline_type + occurred_at` somente quando o reader com filtro entrar em Gate próprio;
- `case_id + occurred_at` não pertence ao primeiro pipeline Nutrition;
- qualquer índice orientado a busca textual permanece fora do v1.

`firestore.indexes.json` atualmente não contém índices de MealLog, SupplementLog ou
HealthTimeline; isso é esperado antes do 5C.5C.4. Nenhuma definição física de índice
fica congelada por esta auditoria: o arquivo final será determinado pelos testes
reais das queries no Emulator.

## 12. Exposure map

### Estado atual confirmado

- prototype não importado/exportado por `functions/src/index.ts`;
- nenhum trigger HealthTimeline existe no código exportado;
- nenhum scheduler HealthTimeline existe no código exportado;
- listagem read-only das Functions publicadas não encontrou `healthTimeline` nem
  `health_timeline`;
- nenhum deploy foi executado nesta auditoria.

### WOULD CHANGE em subgates posteriores

| Subgate | Arquivos |
|---|---|
| 5C.5C.2 | novos `health_timeline_runtime.ts`, `health_timeline_trigger_handlers.ts` e testes; `functions/package.json` apenas para scripts |
| 5C.5C.3 | novos `health_timeline_reconciliation.ts`, state adapter e testes; possível extensão do runtime compartilhado |
| 5C.5C.4 | `firestore.rules`, `firestore.indexes.json` e testes de Rules/queries |
| 5C.5C.5 | `functions/src/index.ts` para os dois triggers e scheduler; testes full-pipeline e scripts |

### WOULD NOT CHANGE por este desenho

- fontes canônicas MealLog/SupplementLog;
- callables Nutrition existentes;
- coleções legadas;
- código Flutter/Mobile;
- contratos O3 e deterministic ID;
- `health_timeline_projection.ts` nesta auditoria;
- deployment config sem autorização separada.

## 13. Test strategy

### 5C.5C.2 — Projection Triggers Local Foundation

- Unit: validação/normalização, fixed source enum, path aninhado e Timestamp codec.
- Emulator: create MealLog/SupplementLog → uma entry; duplicate delivery; retry;
  equivalent no-op; divergent repair; malformed/absent snapshot; source imutável.
- Adversarial: source ID inválido, dog mismatch, tentativa de source_collection arbitrária.
- Aprovação: zero export produtivo; todas as transações idempotentes; 38 unit e 15
  E2E do prototype continuam verdes.

### 5C.5C.3 — Reconciliation Runtime Foundation

- Unit: state machine, leases, cursor tuples, cycle/wrap e anomaly lifecycle.
- Emulator: same `recorded_at` tie-break, late registration, partial failure antes e
  depois do commit, scheduler retry, overlap replay, historical wrap, orphan no-delete.
- Concorrência: trigger × reconciliation e dois reconcilers no mesmo item.
- Aprovação: cursor nunca passa item não resolvido; forward não sofre starvation;
  zero source/legacy mutation.

### 5C.5C.4 — Rules + Indexes Emulator Gate

- Rules: authorized dog read; other-dog deny; anonymous deny; todos os client writes
  deny; state interno deny; queries dog-scoped permitidas.
- Indexes: executar exatamente forward/overlap e timeline query; capturar somente
  índices realmente exigidos pelo Emulator.
- Aprovação: zero broad wildcard e zero client collection-group exposure.

### 5C.5C.5 — Full Pipeline Emulator Integration

- Entrega duplicada, retry after timeout, triggers concorrentes, reconciliation
  concorrente, malformed/cross-dog, orphan no-delete, tie-break, late registration,
  partial failure, overlap, historical wrap.
- Provar zero legacy writes e zero mutation de MealLog/SupplementLog.
- Executar regressões Health Schedule/Nutrition e matriz O3 completa.
- Aprovação: pipeline completo no Emulator, failed 0, sem deploy produtivo automático.

## 14. Files expected to change in later subgates

```text
functions/src/health_timeline_runtime.ts                    NEW
functions/src/health_timeline_trigger_handlers.ts           NEW
functions/src/health_timeline_runtime_test.ts               NEW
functions/src/health_timeline_trigger_emulator_test.ts      NEW
functions/src/health_timeline_reconciliation.ts             NEW
functions/src/health_timeline_reconciliation_test.ts        NEW
functions/src/health_timeline_pipeline_emulator_test.ts     NEW
functions/src/index.ts                                      5C.5C.5 only
functions/package.json                                      test scripts only
firestore.rules                                             5C.5C.4
firestore.indexes.json                                      5C.5C.4
tools/rules_tests/health_timeline_rules_tests.mjs           NEW, 5C.5C.4
```

Nomes podem ser condensados durante implementação, mas as responsabilidades não
devem voltar para o arquivo de teste nem para o monólito `index.ts`.

## 15. Findings

### BLOCKER — 0

Nenhum. O path, runtime adapter, estado, falha parcial, orphan safety, Rules,
índices e limites de exposição têm desenho inequívoco.

### MAJOR — 6

1. Harness grava top-level, divergindo do path canônico aninhado.
2. Engines Firestore existem apenas no E2E e fazem read-then-write não transacional.
3. Representação ISO/fields do prototype não coincide diretamente com Timestamp e
   allowlist de campos do Schema.
4. Metadata/test config não são estado produtivo e não cobrem a matriz por source/pass.
5. Orphan resolver do harness não valida allowlist, cross-dog ou malformed entry.
6. `health.read` conceitual não está implantado; Rules atuais usam dog access. O
   desenho preserva compatibilidade e adia a migração granular.

Todos possuem resolução explícita neste relatório e devem ser cobertos nos subgates.

### MINOR — 3

1. Comentários antigos do prototype divergem do compare real de `recorded_by`.
2. `TEST_CONFIG` está exportado pelo módulo puro; runtime não deve importá-lo.
3. O union de source collections contém nomes fora deste primeiro pipeline; adapters
   devem usar um enum fechado próprio.

### OBSERVATION — 6

1. Node 22, Functions v2 e `southamerica-east1` já são padrões efetivos.
2. Não há circular dependency atual.
3. Logging produtivo deve usar `firebase-functions/logger`.
4. Rules/índices da timeline ainda não existem, conforme o gate anterior.
5. Exposição remota da HealthTimeline é zero na data desta auditoria.
6. SLA produtivo e deploy continuam explicitamente não autorizados.

## 16. Gate verdict

```text
GATE 5C.5C.1 — HUMAN AUDIT APPROVED

BLOCKER:    0
MAJOR:      6
MINOR:      3
OBSERVATION: 6

CANONICAL TIMELINE PATH:
dogs/{dogId}/health_timeline/{timelineId}

NO IMPLEMENTATION
NO COMMIT
NO PUSH
NO DEPLOY
```

## 17. Recommended exact scope for 5C.5C.2

Implementar somente a fundação local dos dois trigger handlers, ainda sem export em
`index.ts`:

1. adapter Firestore transacional com path aninhado e Timestamp codec;
2. handlers injetáveis para MealLog/SupplementLog com source enum fechado;
3. deterministic ID e projection functions reutilizados, não duplicados;
4. anomaly sink injetável; sem scheduler/state store produtivo nesta etapa;
5. unit + Emulator cobrindo duplicate, concurrency, malformed, cross-dog, repair,
   no-op, zero source mutation e zero legacy writes;
6. regressão integral do Gate 5C.5B.2;
7. nenhum `index.ts`, Rules, indexes, scheduler, deploy, backfill ou Mobile.

Guardrails humanos obrigatórios:

1. transient infrastructure failure → throw/retry; deterministic invalid payload →
   anomaly/success; anomaly sink failure → throw/retry;
2. persistência exclusiva do schema canônico, com timestamps Firestore e sem
   `undefined`, helpers ou config de teste;
3. estratégia de query aprovada, mas índices físicos somente após prova real no
   5C.5C.4.

O export real fica para 5C.5C.5, depois de reconciliation, Rules/indexes e integração
full-pipeline estarem aprovados no Emulator.
