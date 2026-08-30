# Health v1.0 — Fase 4A — Relatório de Implementação

## Fundação e contratos da Agenda Preventiva

| Campo | Valor |
|-------|--------|
| Fase | 4A |
| Branch | `feature/health-v1-foundation` |
| Data | 2026-07-17 |
| Status | Pronta para auditoria humana (sem commit) |

---

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `31f6442e3177eabac7af6a4f00ba6bcfc52ad162` |
| commit | `feat(health): complete clinical timeline integration` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência `origin...HEAD` | `0 0` |
| working tree no início desta rodada | **não limpo** — já continha a fundação 4A implementada na sessão anterior (sem commit) |

### Interpretação

O HEAD e a divergência batem com o estado esperado. A working tree **não** estava limpa porque a implementação da 4A já havia sido aplicada localmente e ainda não commitada (conforme instrução da rodada anterior: “não commitar”).

Nenhum `reset`, `stash`, `merge`, `rebase` ou checkout destrutivo foi executado. O trabalho local foi **preservado e consolidado**.

---

## 2. Objetivo da fase

Criar exclusivamente a fundação lógica e os contratos de apresentação da Agenda Preventiva Health v1.0:

- agregado canônico `HealthScheduleItem` (já existente) evoluído;
- derivação **pura** dos estados temporais em tempo de leitura;
- configuração de tolerância e janela `upcoming` **por `schedule_type`**, sem default universal silencioso;
- contrato abstrato de leitura (sem Firestore real);
- estado/controller de apresentação isolado por K9, no padrão das Fases 2 e 3;
- agrupamentos de apresentação (Atrasados / Hoje / Próximos / Programados);
- testes unitários e de estado.

**Fora de escopo (cumprido):** UI final, writes, Rules, Functions, índices, notificações, dual-read/write, migração, legado, push/commit.

---

## 3. Escopo implementado

### Implementado

1. **Domínio**
   - Evolução de `HealthScheduleTemporalPolicy` para config injetável por tipo.
   - `effectiveDueUntil` explícito.
   - Precedência temporal absoluta (lifecycle → overdue → pending → today → upcoming → scheduled).
   - Parse defensivo de `ScheduleType`, `ScheduleSourceType`, `ScheduleLifecycleStatus`.
   - `parseHealthEnum` público para reuso.

2. **Config temporal**
   - `HealthScheduleTypeTemporalConfig` (tolerância + janela upcoming).
   - `HealthScheduleTemporalConfigResolver` / `MapHealthScheduleTemporalConfig`.
   - Falha explícita se tipo sem config (`missing_schedule_type_temporal_config`).

3. **Apresentação (`presentation/schedule/`)**
   - Source abstrata + exception offline.
   - Query / filter identity / cursor / page.
   - `HealthScheduleItemView` (read model com temporal já derivado).
   - `HealthScheduleGroups` + agrupamento puro.
   - Estado sealed: initial / loading / data / empty / error / offline.
   - Controller `ChangeNotifier` com generation token, clock injetável, refresh preservando dados.

4. **Testes**
   - Domínio: lifecycle, overdue/pending, today/upcoming/scheduled, dueUntil, timezone, config, precedência, enums/parsing.
   - Presentation: estados, agrupamentos, isolamento K9, stale success/error, refresh, dispose, clock.

### Não implementado (propositadamente)

- Tela visual / mockup final.
- Acesso Firestore a `health_schedule`.
- Writes (create/complete/cancel/edit).
- Rules, índices, Functions, notificações.
- Integração Timeline/Summary.
- Dual-read/write, migração, adapters de legado.

---

## 4. Arquivos criados

### Produção

| Arquivo | Papel |
|---------|--------|
| `lib/features/health/presentation/schedule/health_schedule_source.dart` | Contrato de leitura abstrato |
| `lib/features/health/presentation/schedule/health_schedule_query.dart` | Query + identidade lógica |
| `lib/features/health/presentation/schedule/health_schedule_cursor.dart` | Cursor opaco de paginação |
| `lib/features/health/presentation/schedule/health_schedule_page.dart` | Página de agregados canônicos |
| `lib/features/health/presentation/schedule/health_schedule_item_view.dart` | View de apresentação |
| `lib/features/health/presentation/schedule/health_schedule_grouping.dart` | Agrupamentos derivados |
| `lib/features/health/presentation/schedule/health_schedule_state.dart` | Estados sealed + snapshot |
| `lib/features/health/presentation/schedule/health_schedule_controller.dart` | Controller race-safe |

### Testes

| Arquivo | Papel |
|---------|--------|
| `test/features/health/presentation/schedule/fake_health_schedule_source.dart` | Fake com hold/race |
| `test/features/health/presentation/schedule/schedule_test_helpers.dart` | Fixtures |
| `test/features/health/presentation/schedule/health_schedule_controller_test.dart` | Estado / race / refresh / dispose |
| `test/features/health/presentation/schedule/health_schedule_grouping_test.dart` | Agrupamento / ordem / anti-duplicação |

### Documentação

| Arquivo | Papel |
|---------|--------|
| `docs/health/HEALTH_V1_PHASE_4A_REPORT.md` | Este relatório |

---

## 5. Arquivos modificados

| Arquivo | Motivo |
|---------|--------|
| `lib/features/health/domain/health_schedule_item.dart` | Política temporal com config por tipo; `effectiveDueUntil` |
| `lib/features/health/domain/health_v1_enums.dart` | `parseHealthEnum` público |
| `lib/features/health/domain/health_v1_enums_ext.dart` | `parse` em lifecycle/type/source; wire de temporal |
| `lib/features/health/domain/health_v1_value_objects.dart` | Config temporal + resolver map-based |
| `test/features/health/domain/health_schedule_item_test.dart` | Cobertura temporal expandida |

---

## 6. Contrato de estados temporais

### Persistidos (lifecycle)

| Valor | Significado |
|-------|-------------|
| `open` | Item ativo |
| `completed` | Concluído (terminal) |
| `cancelled` | Cancelado (terminal) |

### Derivados em leitura (`HealthScheduleTemporalStatus`)

| Valor | Condição (ordem absoluta) |
|-------|---------------------------|
| `completed` | `lifecycle == completed` |
| `cancelled` | `lifecycle == cancelled` |
| `overdue` | `now > effective_due_until` |
| `pending` | `now >= scheduled_for` e ainda não overdue |
| `today` | aberto, futuro, mesmo dia civil no timezone do item |
| `upcoming` | aberto, dentro da janela configurada do tipo |
| `scheduled` | aberto, futuro fora da janela upcoming |

### Data efetiva única

```text
effective_due_until =
  due_until
  ?? scheduled_for + config(schedule_type).toleranceAfterScheduled
```

- `due_until` explícito **sempre** prevalece.
- Sem `due_until`, a tolerância vem **somente** da config do tipo.
- Ausência de config → exceção explícita (sem default universal de 24h).
- `now == effective_due_until` **não** é overdue.
- `now == scheduled_for` é **pending**.
- Passagem do tempo **não** gera write.

---

## 7. Decisões de implementação

1. **Reutilizar** `HealthScheduleItem` e enums existentes — sem segunda representação concorrente do agregado.
2. **Seguir Fases 2/3**: source abstrata + sealed state + `ChangeNotifier` + generation token (não repository/use-case genérico).
3. **Config por tipo** em vez de `upcomingWindow` global e typedef simples de tolerância.
4. **Fonte de verdade de itens**: lista canônica no snapshot; grupos **derivados** a cada carga (`groupScheduleItems`), não listas mutáveis paralelas.
5. **Clock**: injetável no controller; `now` obrigatório na política. `DateTime.now()` só no default de produção do clock do controller — **nunca** na regra de domínio.
6. **Timezone**: IANA do item via `package:timezone` (já no projeto); sem fallback silencioso para UTC local da máquina.
7. **Tipos oficiais no enum**: os **9** do Domain Model / Schema (`dose`, `vaccination`, `exam`, `consultation`, `weighing`, `reevaluation`, `deworming`, `bath`, `general`). Ver divergência na §15.

---

## 8. Comportamento de timezone

- Campo `timezone` obrigatório no item.
- Validação IANA no construtor e em `validateTimezone`.
- Dia civil e janela upcoming calculados em `TZDateTime` no timezone do item.
- Testes usam instantes UTC explícitos + zonas `America/Sao_Paulo` / `Etc/UTC` — resultado independente do timezone do host.
- Base IANA inicializada de forma privada/idempotente na política (Health não depende do bootstrap de Push).

---

## 9. Comportamento de `dueUntil`

| Cenário | Resultado |
|---------|-----------|
| `due_until` presente | `effective = due_until` |
| `due_until` ausente | `scheduled_for + tolerance(tipo)` |
| `now <= effective` e `now >= scheduled_for` | `pending` |
| `now > effective` | `overdue` |
| `due_until < scheduled_for` | rejeitado no domínio |
| tipo sem config | `HealthDomainException(missing_schedule_type_temporal_config)` |

Não existe constante global de 24h no domínio. Os testes usam configs explícitas (ex.: 24h uniformes **no teste**, não no produto).

---

## 10. Estratégia race-safe por K9

- Toda mutação de query (`setQuery`, `selectDog`, `applyFilters`, `refresh`) incrementa `_generation`.
- Resposta só aplica se `generation == _generation` **e** `filterIdentity` ativo coincide **e** controller não disposed.
- Troca A→B: loading de B; resposta de A ignorada.
- Erro stale de A após sucesso de B: ignorado.
- Refresh com dados: mantém lista com `isRefreshing`; falha grava `lastRefreshError` sem destruir itens da mesma identidade.
- `_setState` / `_isCurrent` bloqueiam após `dispose`.

---

## 11. Testes criados / expandidos

### Domínio (`health_schedule_item_test.dart`)

- Lifecycle terminal (completed/cancelled + datas atrasadas).
- Overdue / pending / limites (`now == due`, `now == scheduled_for`).
- Today / upcoming / scheduled.
- Janela upcoming e tolerância **por tipo**.
- Config ausente e mapa vazio (sem fallback).
- Timezone (mesmo instante → dias civis distintos; virada de dia em SP).
- Clock totalmente controlável.
- Precedência (pending vs overdue, today vs pending, upcoming vs today, terminais).
- Enums oficiais + parse defensivo (unknown/absent).

### Presentation

- initial → loading → data | empty | error | offline.
- Agrupamentos + ordem ASC + sem duplicação entre grupos.
- Isolamento dois dogIds; troca rápida A→B.
- Resposta antiga de sucesso e de **erro** não sobrescrevem estado novo.
- Refresh sucesso; refresh erro preservando dados.
- Dispose: resposta tardia não promove estado nem notifica.
- Clock injetável na recarga.

---

## 12. Comandos executados

### Implementação / consolidação

```text
git branch --show-current
git rev-parse HEAD
git status --short
git rev-list --left-right --count origin/feature/health-v1-foundation...HEAD
git rev-parse --abbrev-ref @{u}

dart format <arquivos 4A>
flutter analyze <escopo 4A>
flutter test test/features/health/domain/health_schedule_item_test.dart \
  test/features/health/presentation/schedule
flutter test test/features/health
git status --short
git diff --stat
```

### Validação final pré-commit (fechamento formal — 2026-07-17)

Executada sobre o **working tree final consolidado da Fase 4A** (antes do commit de fechamento):

```text
git branch --show-current
git rev-parse HEAD
git status --short
git rev-list --left-right --count origin/feature/health-v1-foundation...HEAD
flutter test
git diff --check
git status --short
git diff --stat
```

---

## 13. Resultados objetivos

### Validação final pré-commit (estado final da 4A)

| Item | Valor |
|------|--------|
| Data / rodada | **2026-07-17** — fechamento formal da Fase 4A |
| HEAD base (antes do commit) | `31f6442e3177eabac7af6a4f00ba6bcfc52ad162` |
| Working tree validado | **estado final consolidado da 4A** (domínio + presentation/schedule + testes + este relatório) |
| Comando | `flutter test` (suíte global do projeto) |
| Aprovados | **921** |
| Ignorados / skipped | **1** |
| Falhas | **0** |
| Exit code | **0** (`All other tests passed!`) |
| `git diff --check` | limpo (exit 0) |

Este resultado **substitui** qualquer menção anterior ambígua à suíte global e corresponde exclusivamente ao working tree final da 4A imediatamente antes do commit de fechamento.

### Validações de escopo (implementação)

| Validação | Resultado |
|-----------|-----------|
| Testes Agenda (domínio + schedule presentation) | **53 passed**, 0 failed, 0 skipped |
| Testes Health (`test/features/health`) | **738 passed**, 0 failed, 0 skipped |
| Analyze escopo 4A | 0 errors; 2 infos preexistentes (`prefer_initializing_formals` em models) |
| Format arquivos Dart 4A | OK |

---

## 14. Auditoria adversarial

| Risco | Resultado |
|-------|-----------|
| Estado temporal persistido no domínio | **OK** — só `lifecycleStatus` no item; temporal só em view/policy |
| `DateTime.now()` na regra de domínio | **OK** — ausente em `HealthScheduleTemporalPolicy` |
| Timezone implícito do host | **OK** — IANA do item; testes com UTC explícito |
| Constante universal 24h no produto | **OK** — config injetável; sem default de domínio |
| Overlap pending ∩ overdue | **OK** — precedência absoluta; testes de fronteira |
| Item em dois grupos | **OK** — switch exaustivo + teste anti-duplicação |
| Listas derivadas como fonte de verdade | **OK** — grupos recalculados a partir de `items` |
| Stale response / vazamento entre K9 | **OK** — generation + identity; testes A→B e erro stale |
| Firebase no domínio/apresentação | **OK** — zero imports Firebase nos contratos 4A |
| Schema / writes acidentais | **OK** — sem service Firestore, sem Rules, sem dual-write |
| Legado alterado | **OK** — sem toques em adapters/legado |
| Abstração genérica prematura | **OK** — padrão local ChangeNotifier como Fases 2/3 |
| Clock default do controller | **Aceito** — só default de produção; injetável e testado |

### Correções feitas nesta consolidação

- Testes de **refresh** (sucesso e erro com preservação).
- Teste de **erro stale** após requisição nova bem-sucedida.
- Teste de **dispose** (resposta tardia).
- Teste de **não-duplicação** entre grupos.

Nenhum bug de produção encontrado na auditoria adversarial que exigisse mudança de política temporal.

---

## 15. Achados fora do escopo / divergências

### Divergência de tipos (documentação de brief vs canônico)

| Fonte | Tipos |
|-------|--------|
| Brief 4A (lista “inicial”) | 6: dose, vaccination, exam, consultation, weighing, reevaluation |
| Domain Model §2.12 / Schema / enum Dart | **9**: + deworming, bath, general |

**Decisão:** manter os **9** oficiais do Domain Model e Schema (hierarquia: código + docs canônicos > lista resumida do brief). Não se introduziu `meal`/`supplement` no agregado.

### ADR-004 trecho incompleto

Um diagrama no ADR-004 lista menos `schedule_type` e `source_type` do que o Domain Model. Seguiu-se Domain Model + Schema.

### Drift de formatação preexistente

`dart format --set-exit-if-changed lib/features/health test/features/health` reporta arquivos **fora** do 4A com formatação divergente (ex.: `health_service.dart`, testes de timeline 3E). **Não** foram “corrigidos de passagem”.

### Infos/warnings analyzer preexistentes

- `prefer_initializing_formals` em vários models de domínio.
- Unused imports em testes de summary/timeline (fora do 4A).

### `ScheduleToleranceResolver` deprecated

Mantido com `@Deprecated` para compatibilidade simbólica; o caminho canônico é `HealthScheduleTemporalConfigResolver`.

---

## 16. Diff final (resumo)

```text
 M lib/features/health/domain/health_schedule_item.dart
 M lib/features/health/domain/health_v1_enums.dart
 M lib/features/health/domain/health_v1_enums_ext.dart
 M lib/features/health/domain/health_v1_value_objects.dart
 M test/features/health/domain/health_schedule_item_test.dart
?? lib/features/health/presentation/schedule/
?? test/features/health/presentation/schedule/
?? docs/health/HEALTH_V1_PHASE_4A_REPORT.md
```

Sem alterações em: Rules, índices, legado, navegação de produção, Web, Timeline UI, Summary UI (exceto reuso de padrões conceituais).

---

## 17. Estado git final

### Antes do commit de fechamento

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `31f6442e3177eabac7af6a4f00ba6bcfc52ad162` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência commits | `0 0` |
| working tree | mudanças locais exclusivas da Fase 4A |

### Após commit e push (fechamento formal)

| Item | Valor |
|------|--------|
| mensagem | `feat(health): add preventive schedule foundation` |
| escopo do commit | exclusivamente arquivos da Fase 4A + este relatório (validação global 921 passed / 1 skipped / 0 failed) |
| push | somente `feature/health-v1-foundation` → `origin` (sem merge em `main`) |

---

## 18. Avaliação de prontidão para a Fase 4B

### Critérios 4A

| Critério | Status |
|----------|--------|
| Agregado canônico + lifecycle only | ✅ |
| Temporal puro e determinístico | ✅ |
| Config/tolerância por tipo sem default universal | ✅ |
| Timezone do item | ✅ |
| Contrato de leitura abstrato | ✅ |
| Estado presentation + isolamento K9 | ✅ |
| Agrupamentos Atrasados/Hoje/Próximos/Programados | ✅ |
| Testes lifecycle/temporal/dueUntil/tz/state/race/dispose | ✅ |
| Sem UI final / writes / Firestore real | ✅ |
| Relatório formal | ✅ |

### Próximo (4B — fora desta fase)

Esperado tipicamente: wire visual da Agenda, fonte Firestore real (read-only), possível empty/error UI, sem writes até fase autorizada.

### Conclusão

A fundação está coerente com Domain Model, Schema, ADR-004 (precedência) e padrões das Fases 2/3. Testes cobrem o contrato temporal e de estado. Não há writes, UI final ou integração remota.

**FASE 4A PRONTA PARA AUDITORIA HUMANA**

---

## Anexos

### Agrupamentos de apresentação

| Grupo | Temporal | Uso UI |
|-------|----------|--------|
| `overdue` | overdue | Atrasados |
| `pending` | pending | No horário (não misturado com overdue) |
| `today` | today | Hoje |
| `upcoming` | upcoming | Próximos |
| `scheduled` | scheduled | Programados |
| `completed` / `cancelled` | terminais | Disponível no modelo; não dominam o grupo principal |

### Dependências novas

Nenhuma. Reutilizado `package:timezone` já presente no `pubspec.yaml`.
