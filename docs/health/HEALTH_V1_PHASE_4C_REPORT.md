# Health v1.0 — Fase 4C — Relatório de Implementação

## Integração Read-Only da Agenda Preventiva com Firestore

| Campo | Valor |
|-------|--------|
| Fase | 4C |
| Branch | `feature/health-v1-foundation` |
| Data | 2026-07-17 |
| Status | **PRONTA E APROVADA PARA FECHAMENTO** · ativação em produção bloqueada (Rules/índice/validação) |

---

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `6c989027b73d6c2a61cf4561e8e7d4198cdb3f70` |
| commit | `feat(health): add preventive schedule shell` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0 0` |
| working tree inicial | limpo |

Preflight **OK**.

---

## 2. Objetivo

Implementar source Firestore read-only para `dogs/{dogId}/health_schedule`, mapper canônico, paginação estável, índice versionado, filtro **Hoje** calendário, revisão da presentation policy — **sem writes**.

---

## 3. Inspeção das Rules atuais

Arquivo: `firestore.rules` (canônico do repositório mobile).

- Existe `match /dogs/{dogId}` com subcoleções explícitas (`weight_records`, `health_events`, `feeding_events`, etc.).
- **Não existe** `match /dogs/{dogId}/health_schedule/{scheduleId}`.
- Catch-all final:

```
match /{document=**} {
  allow read, write: if false;
}
```

**Consequência:** qualquer leitura de `health_schedule` por cliente autenticado recebe **permission-denied**.

### Decisão de ativação

Conforme brief 4C:

- Rules **não** foram modificadas (proibido enfraquecer/contornar).
- Composition root de produção **permanece** com `EmptyHealthScheduleSource`.
- Source Firestore real está implementada e testada com `FakeFirebaseFirestore`, pronta para ativação quando Rules read-only forem aprovadas e deployadas em rodada autorizada.

---

## 4. Inspeção dos índices atuais

`firestore.indexes.json` **não** continha `health_schedule` antes da 4C.

### Índice adicionado nesta fase — somente versionado, sem deploy

`lifecycle_status ASC` + `scheduled_for ASC`

Esse é o **único** índice `health_schedule` versionado na Fase 4C, pois é necessário à query operacional atualmente implementada.

O índice:

`schedule_type ASC` + `lifecycle_status ASC` + `scheduled_for ASC`

permanece previsto no Schema para eventual filtragem remota futura por tipo, mas **não foi versionado nesta fase**, pois não possui consumidor real na implementação atual.

Deploy de índices: **não executado nesta fase**.

---

## 5. Source Firestore implementada

`lib/features/health/data/coexistence/schedule/firestore_health_schedule_source.dart`

- Implementa `HealthScheduleSource`.
- Injetável `FirebaseFirestore` (testes com fake).
- Factory `forDefault()` para produção futura.
- **Zero** `set` / `add` / `update` / `delete` / batch / transaction.

---

## 6. Caminho e query

| Item | Valor |
|------|--------|
| Caminho | `dogs/{dogId}/health_schedule` |
| Filtro lifecycle | vazio na query ⇒ **open only**; senão `where` / `whereIn` |
| Ordenação | `scheduled_for ASC` |
| Dual-read | **não** |
| Coleções legadas | **não consultadas** |

Limitação documentada: filtros de **tipo** (chips) continuam locais sobre a página carregada; paginação + filtro local não equivale a busca completa do conjunto.

---

## 7. Paginação / cursor (estratégia final)

### Query Firestore

```text
where lifecycle_status == open   (default operacional)
orderBy scheduled_for ASC
orderBy FieldPath.documentId ASC
limit pageSize+1
```

Páginas seguintes:

```text
startAfterDocument(snapshot do último doc)   // preferido se o doc ainda existe
// ou, se o documento do cursor foi removido:
startAfter([Timestamp(scheduled_for), documentId])
```

### Cursor

| Item | Valor |
|------|--------|
| Tipo presentation | `HealthScheduleCursor` opaco (sem Firebase) |
| Payload | base64url JSON `{v, atMs, id}` via `HealthScheduleCursorCodec` |
| `DocumentSnapshot` | **não vaza** para domain/presentation |
| Avanço | `startAfter` (não `startAt` + filtro corretivo local) |
| Desempate cliente | **removido** — ordenação estável na query |

### Regressão obrigatória

- **15 documentos**, mesmo `scheduled_for`, `pageSize = 5` → 3 páginas, 15 IDs únicos, ordem estável em duas execuções, sem página intermediária vazia com dados restantes.
- Caso misto: timestamps iguais e diferentes.

---

## 8. Parser / mapper

`HealthScheduleDocumentMapper.fromFirestore`

Campos lidos: conforme schema (incl. `migration_batch_id` ignorado no domínio).

`HealthScheduleDateParse`: Timestamp / DateTime / ISO / map seconds.

---

## 9. Documentos inválidos

`HealthScheduleIntegrityException(documentId, reason, field?)`

- Enum desconhecido → integrity (não vira `general`)
- Timestamp obrigatório inválido → integrity
- Timezone inválido → integrity (via domínio)
- Source propaga `HealthScheduleSourceException` observável (não empty)

---

## 10. Erros Firestore

| Cenário | Resultado |
|---------|-----------|
| offline / unavailable | `isOffline: true` |
| permission-denied | `isPermissionDenied: true` (≠ empty) |
| integrity / parsing | SourceException mensagem segura |
| empty collection | `HealthSchedulePage.empty()` |

---

## 11. Integração composition root

`health_v1_entry_screen.dart`:

```dart
_scheduleSource = widget.scheduleSource ?? const EmptyHealthScheduleSource();
```

Comentário explícito do bloqueio Rules. Testes injetam fake/Firestore source.

---

## 12. Destino de `EmptyHealthScheduleSource`

**Mantida** como default de produção até Rules.

Uso legítimo: produção bloqueada + testes/dev sem Firebase.

Não é código morto.

---

## 13–14. Presentation policy (revisão)

`healthSchedulePresentationPolicy()` — **único ponto**.

| schedule_type | toleranceAfterScheduled | upcomingWindow | classificação |
|---------------|-------------------------|----------------|---------------|
| dose | 24h | 7d | **PROVISÓRIO PARA APRESENTAÇÃO** |
| vaccination | 24h | 7d | PROVISÓRIO |
| exam | 24h | 7d | PROVISÓRIO |
| consultation | 24h | 7d | PROVISÓRIO |
| weighing | 24h | 7d | PROVISÓRIO |
| reevaluation | 24h | 7d | PROVISÓRIO |
| deworming | 24h | 7d | PROVISÓRIO |
| bath | 24h | 7d | PROVISÓRIO |
| general | 24h | 7d | PROVISÓRIO |

Nenhum valor **APROVADO EM CONTRATO** institucional. UI não afirma “7 dias”. Não persistido.

---

## 15. Filtro Hoje — decisão final

**Resolvido na 4C (somente UI):**

`Hoje` = `scheduled_for` no **dia civil atual no timezone do item** (itens open carregados).

Inclui temporal `today`, `pending` e `overdue` do mesmo dia.

**Não altera** `HealthScheduleTemporalStatus`.

KPIs inalterados (conjunto completo carregado).

---

## 16. Dual-read

**Ausente.** Somente `health_schedule`.

---

## 17. Testes criados

| Arquivo | Cobertura |
|---------|-----------|
| `health_schedule_document_mapper_test.dart` | completo, opcionais, timestamp inválido, enum desconhecido, timezone, completed/cancelled, system actor, date parse |
| `firestore_health_schedule_source_test.dart` | dogId, open, ordem, pageSize, cursor, mesmo timestamp, empty, integrity, **15 docs mesmo ts / pageSize 5**, paginação mista |
| `health_schedule_today_filter_test.dart` | today/pending/overdue hoje, ontem, amanhã, timezone SP vs UTC |

---

## 18–19. Comandos e resultados

```text
flutter test test/features/health/data/coexistence/schedule
flutter test test/features/health/presentation/schedule
flutter analyze <escopo 4C>
flutter test test/features/health
git diff --check
```

| Suite | Resultado (fechamento 4C — working tree final) |
|-------|------------------------------------------------|
| data/coexistence/schedule | **21 passed** |
| presentation/schedule | **43 passed** |
| Suíte Health | **784 passed** |
| Suíte global `flutter test` | **967 passed**, **1 skipped**, 0 failed |
| Analyze escopo 4C | No issues found |
| `git diff --check` | limpo |
| `firestore.rules` | **não alterado** |
| `firestore.indexes.json` | **1 índice** health_schedule (`lifecycle_status` + `scheduled_for`) |

---

## 20. Validação Firestore autenticada

```text
VALIDAÇÃO FIRESTORE AUTENTICADA PENDENTE
```

Motivo: Rules negam leitura; sem deploy de Rules nesta fase; ambiente não executou query autenticada real. Fakes cobrem o caminho de dados.

---

## 21. Índices necessários

| Índice | Estado |
|--------|--------|
| `lifecycle_status ASC` + `scheduled_for ASC` | **versionado** em `firestore.indexes.json`; **deploy pendente** |
| `schedule_type` + `lifecycle_status` + `scheduled_for` | **não versionado nesta 4C** — sem query remota por tipo; continua previsto no Schema e pode ser adicionado quando a query por `schedule_type` for implementada |

Nota: `orderBy(FieldPath.documentId)` usa o campo especial `__name__`; o índice composto lifecycle + scheduled_for é o consumidor real da query atual (Firestore inclui o desempate por document ID na consulta).

---

## 22. Auditoria adversarial

| Risco | Resultado |
|-------|-----------|
| Firebase no domínio/presentation | **OK** — só data/coexistence |
| DocumentSnapshot no cursor | **OK** — codec opaco |
| Cursor só timestamp com perda | **corrigido** — orderBy documentId + startAfter estável |
| permission-denied como empty | **OK** — flag + mensagem |
| Documento inválido silencioso | **OK** — integrity |
| Enum → general | **OK** — rejeita |
| Dual-read / legado | **OK** — não |
| Filtro Hoje só temporalStatus | **corrigido** — calendário civil |
| Writes na source | **OK** — nenhum |
| Rules modificadas | **OK** — não |
| Recompute com nova query | **OK** — inalterado |
| Production default Empty | **intencional** (Rules) |

---

## 23. Achados fora do escopo

- Deploy Rules / índices.
- Ativação composition com Firestore real.
- Backfill de `health_schedule`.
- Writes / Functions / dual-read.

---

## 24. Diff final (resumo)

```text
 M firestore.indexes.json
 M health_schedule_source.dart (isPermissionDenied)
 M health_schedule_ui_filter.dart (Hoje calendário)
 M health_schedule_view.dart (now no filtro)
 M health_schedule_presentation_policy.dart (tabela provisória)
 M health_v1_entry_screen.dart (comentário bloqueio Rules)
?? data/coexistence/schedule/*
?? testes data + today filter
?? HEALTH_V1_PHASE_4C_REPORT.md
```

**firestore.rules:** não alterado.

---

## 25. Estado git final

### Antes do commit de fechamento

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `6c989027b73d6c2a61cf4561e8e7d4198cdb3f70` |
| working tree | alterações exclusivas da Fase 4C |

### Após commit e push

| Item | Valor |
|------|--------|
| mensagem | `feat(health): add preventive schedule read source` |
| push | somente `feature/health-v1-foundation` → `origin` |
| Rules / deploy índice | **não** nesta rodada |

---

## 26. Avaliação próxima subfase

Antes de considerar Agenda “ao vivo” em produção:

1. **Rules** read para `health_schedule` (capability/canAccessDogRecord) — deploy autorizado.
2. Deploy dos índices versionados.
3. Ativar `FirestoreHealthScheduleSource.forDefault()` no entry.
4. Validação autenticada real.
5. Revisar presentation policy com decisão humana.
6. Avaliar query remota por tipo se filtros locais forem insuficientes.

---

## Gate final

### Prontidão da implementação

```text
FASE 4C PRONTA E APROVADA PARA FECHAMENTO
```

A source read-only, mapper, cursor estável (`orderBy scheduled_for` + `documentId` + `startAfter`), filtro Hoje, presentation policy e testes (incl. 15 docs com o mesmo `scheduled_for` e pageSize 5) estão implementados e verificáveis **sem** ativação em produção.

### Ativação em produção

```text
ATIVAÇÃO EM PRODUÇÃO BLOQUEADA
```

| Bloqueio | Detalhe |
|----------|---------|
| 1. Rules | Sem match `health_schedule`; catch-all deny → permission-denied |
| 2. Índice | `lifecycle_status ASC + scheduled_for ASC` versionado; **deploy não executado** |
| 3. Validação autenticada | Pendente até Rules + índice em ambiente real |

Composition root permanece em `EmptyHealthScheduleSource`.  
`FirestoreHealthScheduleSource` **não** está ativada no composition root.
