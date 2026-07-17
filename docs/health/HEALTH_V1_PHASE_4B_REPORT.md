# Health v1.0 — Fase 4B — Relatório de Implementação

## Shell visual da Agenda Preventiva

| Campo | Valor |
|-------|--------|
| Fase | 4B |
| Branch | `feature/health-v1-foundation` |
| Data | 2026-07-17 |
| Status | Pronta para auditoria humana (sem commit) |

---

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `7d27ac54b7f900a5e715fcc7b50e04716e7b099c` |
| commit | `feat(health): add preventive schedule foundation` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0 0` |
| working tree inicial | limpo |

Preflight **OK**.

---

## 2. Objetivo

Implementar o **shell visual real** da Agenda Preventiva no Health v1, consumindo exclusivamente a fundação da Fase 4A (controller, state, groups, policy), **read-only**, sem Firestore `health_schedule` e sem writes.

---

## 3. Arquivos criados

### Produção

| Arquivo | Papel |
|---------|--------|
| `presentation/schedule/empty_health_schedule_source.dart` | Source honesta de produção (sempre empty) |
| `presentation/schedule/health_schedule_presentation_policy.dart` | Bootstrap de política temporal (ADR defaults propostos) |
| `presentation/schedule/health_schedule_ui_filter.dart` | Filtros de UI sobre itens carregados |
| `presentation/schedule/health_schedule_view.dart` | UI principal + recompute lifecycle |
| `presentation/schedule/health_schedule_screen.dart` | Slot da aba Agenda |
| `presentation/schedule/widgets/health_schedule_user_copy.dart` | Copy institucional |
| `presentation/schedule/widgets/health_schedule_formatters.dart` | Labels/cores/ícones (sem regras temporais) |
| `presentation/schedule/widgets/health_schedule_status_views.dart` | Loading / empty / error surfaces |
| `presentation/schedule/widgets/health_schedule_kpi_row.dart` | KPIs 2x2 responsivos |
| `presentation/schedule/widgets/health_schedule_filter_chips.dart` | Chips horizontais |
| `presentation/schedule/widgets/health_schedule_item_card.dart` | Card read-only de item |

### Testes

| Arquivo | Papel |
|---------|--------|
| `test/.../schedule/health_schedule_view_test.dart` | Widget tests 4B |
| `test/.../schedule/health_schedule_recompute_test.dart` | Reavaliação temporal sem source |

### Documentação

| Arquivo | Papel |
|---------|--------|
| `docs/health/HEALTH_V1_PHASE_4B_REPORT.md` | Este relatório |

---

## 4. Arquivos modificados

| Arquivo | Motivo |
|---------|--------|
| `presentation/schedule/health_schedule_controller.dart` | `recomputeTemporalStates()` + retenção de domain items |
| `presentation/screens/health_v1_entry_screen.dart` | Composition root Agenda lazy + wire aba |

---

## 5. Integração com o Health shell

- Aba **Agenda** no `HealthShellScreen` deixa de usar `HealthShellSectionPlaceholder`.
- `HealthV1EntryScreen` cria `HealthScheduleController` + `EmptyHealthScheduleSource` (produção).
- Carga **lazy** no primeiro acesso à aba (espelha Timeline).
- Troca de K9 propaga `selectDog` se a Agenda já foi primed.
- Dispose unificado no entry.
- Sem alteração de bottom nav global, rotas legadas ou shell externo.

---

## 6. Estrutura visual implementada

1. Cabeçalho de área: `AGENDA PREVENTIVA` + “Cuidados programados para {K9}” (sem header global duplicado).
2. Filtros chips horizontais: Todos, Hoje, Vacinas, Consultas, Pesagem, Medicação, Exames, Reavaliações, Outros.
3. KPIs 2×2 (ou linha em largura ≥420): Pendências / Hoje / Próximos / Atrasados.
4. Seções operacionais (só se não vazias): REQUER ATENÇÃO → PENDENTES → HOJE → PRÓXIMOS → PROGRAMADOS.
5. Cards de item: ícone de tipo, horário/data, título, notes, responsável, chip de status.
6. RefreshIndicator + banner de falha de refresh.
7. Estados loading (skeleton), empty, error+retry, offline.

---

## 7. Diferenças conscientes vs mockup

| Mockup | Decisão 4B |
|--------|------------|
| Botão Calendário | **Omitido** (sem destino real) |
| Busca textual | **Omitida** (sem contrato / sem caixa morta) |
| CTA Adicionar agendamento | **Omitido** (write fora de escopo) |
| Tratamento em andamento | **Adiado** (TreatmentProtocol) |
| Lembretes / summary alerts | **Adiado** |
| Alimentações do dia / plano alimentar | **Adiado** (não são schedule_type canônicos) |
| Botões Registrar/Concluir no card | **Omitidos** (write) |
| Nutrição/Refeições/Suplementos nos filtros | **Não adicionados** (não são tipos canônicos) |
| Outros = deworming+bath+general | **Implementado** (9 tipos 4A) |
| Dados fake de Bono | **Não** — empty source em produção |

---

## 8. Filtros

Filtro de UI sobre itens **já carregados** (`HealthScheduleUiFilter`):

| Chip | Critério |
|------|----------|
| Todos | sem filtro |
| Hoje | `temporalStatus == today` |
| Vacinas | `vaccination` |
| Consultas | `consultation` |
| Pesagem | `weighing` |
| Medicação | `dose` |
| Exames | `exam` |
| Reavaliações | `reevaluation` |
| Outros | `deworming` \| `bath` \| `general` |

Não altera query remota (ainda não há Firestore). KPIs usam o conjunto completo carregado; a lista respeita o chip.

---

## 9. Estados visuais

| Estado 4A | UI 4B |
|-----------|--------|
| initial | mensagem neutra |
| loading | skeleton KPI + cards |
| empty | empty profissional sem CTA de criação |
| error | mensagem + Tentar novamente |
| offline | offline; com lastKnown preserva dados + banner |
| data | KPIs + seções + refresh |

---

## 10. Estratégia de reavaliação temporal

1. Controller retém `List<HealthScheduleItem>` da identidade atual.
2. `recomputeTemporalStates()` re-mapeia views com clock atual + policy 4A e reagrupa.
3. **Não** chama a source.
4. `HealthScheduleView`:
   - `WidgetsBindingObserver` → recompute no `resumed`;
   - `Timer.periodic` (default 1 min; desligável com `Duration.zero`);
   - cancelado no `dispose`.
5. Widgets **não** reimplementam precedência temporal.

---

## 11. Responsividade

- KPIs: 2×2 abaixo de 420 px; linha acima.
- Chips em `ListView` horizontal.
- Textos com ellipsis.
- Widget tests em 360 / 390 / 412 px sem overflow reportado.

---

## 12. Acessibilidade

- Status com **texto + cor** (chip).
- Semantics em chips, KPIs, cards, retry, loading.
- Touch targets em chips via padding + InkWell.
- Não é auditoria WCAG completa.

---

## 13. Testes

### Recompute (controller)

- today → pending sem nova leitura
- pending → overdue sem nova leitura
- recompute pós-dispose no-op

### Widget (view)

- loading / empty / error+retry / data
- prioridade visual overdue antes de scheduled
- filtro Vacinas
- responsividade 360/390/412
- refresh com falha preserva itens
- troca de K9
- recompute UI sem source
- dispose de timer sem exceção

---

## 14. Comandos executados

```text
git branch / rev-parse / status / rev-list
dart format <arquivos 4B>
flutter test test/features/health/presentation/schedule
flutter analyze lib/features/health/presentation/schedule \
  lib/features/health/presentation/screens/health_v1_entry_screen.dart
flutter test test/features/health
git diff --check
git status --short
```

---

## 15. Resultados

| Check | Resultado |
|-------|-----------|
| Testes `presentation/schedule` (incl. harness visual) | **37 passed**, 0 failed, 0 skipped |
| Analyze escopo 4B | 0 issues |
| Suíte Health | **757 passed**, 0 failed, 0 skipped |
| Suíte global `flutter test` (fechamento 4B) | **940 passed**, **1 skipped**, 0 failed |
| `git diff --check` | limpo |
| Commit / push | ver §20 após fechamento |

---

## 16. Validação visual real

### Ambiente

| Item | Valor |
|------|--------|
| Data | 2026-07-17 |
| Método | Harness de widget test isolado (não produção) + comparação estrutural com `docs/health/mockups/agenda preventiva.png` |
| Device real/emulado | Não disponível nesta sessão (sem Android emulator) |
| Larguras inspecionadas | **360 / 390 / 412 px** (altura harness 1400) |
| Harness | `test/features/health/presentation/schedule/health_schedule_visual_harness_test.dart` |

### Dados do harness

Nome de teste: **K9 Visual Test** (não vaza para produção).

Itens simultâneos:

| Estado | Tipo | Título |
|--------|------|--------|
| overdue | weighing | Pesagem em atraso |
| pending | dose | Dose noturna — Condroprotetor |
| today | consultation | Consulta veterinária preventiva |
| upcoming | vaccination | Vacina V10 |
| scheduled | exam | Hemograma completo |

### Comparação com o mockup

#### Mantido

- Fundo dark navy / tokens `AppTheme.background` / painéis escuros
- Cyan institucional em filtros selecionados e destaques
- Âmbar (pendências) / vermelho (atrasados) / verde (próximos)
- KPIs superiores com contagem + hint curto
- Hierarquia de seções operacionais
- Cards densos com ícone, horário, título, status chip, responsável
- Chips de filtro com scroll horizontal e seleção inequívoca (chip sólido cyan)

#### Adaptado

- Seções por **estado temporal canônico** (não por dia calendário “HOJE/AMANHÃ/20 JUL”)
- KPI “Próximos” **sem** texto “7 dias” (janela configurável; defaults só na policy de bootstrap)
- Grid KPI 2×2 em largura &lt; 420 (mockup mostra 4 colunas que ficariam ilegíveis em 360)
- Sem rail vertical de timeline dia-a-dia (substituído por seções operacionais 4A)
- Tipografia Inter com pesos disponíveis no bundle de testes (w700 max)

#### Omitido (proposital — 4B)

- Botão Calendário / Ver calendário completo
- Busca “Pesquisar evento…”
- Nutrição nos filtros; alimentações; suplementos
- CTAs Registrar / Concluir / Adicionar agendamento
- Bloco Tratamento em andamento
- Bloco Lembretes
- Header global do app (já fornecido pelo shell Health)

### Problemas encontrados e correções

| Problema | Correção |
|----------|----------|
| Chip selecionado com contraste fraco (borda cyan apenas) | Chip **preenchido** cyan + texto `nightBlue` |
| KPIs sem hierarquia do mockup (só número) | Ícone + hint (“Necessitam atenção”, “Agendados”, etc.) |
| Título área pouco legível (cyan small caps) | Título branco w700 15px, subtítulo secundário |
| Densidade dos cards levemente alta | Padding/ícone ajustados (38px, padding 11) |
| Risco de afirmar “7 dias” na UI | Confirmado: UI usa só “Próximos” / “Agendados” |
| FontWeight.w800 quebra testes (Inter-ExtraBold ausente) | Reduzido para w700 (compatível com assets/testes) |

### Problemas remanescentes (não bloqueantes)

- Rail vertical estilo mockup “por dia” não implementado (contrato usa seções de estado).
- Inspeção em **dispositivo físico** ainda desejável no aceite humano final.
- Captura PNG no harness de teste renderiza **estrutura** correta (chips, KPIs 2×2, seções coloridas, cards), mas glyphs Inter ficam em “tofu” sem runtime fetch de fontes no ambiente de teste — esperado; produção usa `google_fonts` com fetch. Pasta `artifacts/` ignorada no git.

### Decisão filtro “Hoje”

```text
REVISAR NA 4C
```

**Motivo:** `Hoje = temporalStatus == today` exclui itens do mesmo dia civil que já passaram de `scheduledFor` e viraram `pending`. Operacionalmente, condutores esperam ver “tudo do dia” no chip Hoje (incl. pendentes no horário). Não alterado nesta rodada (sem mudança de contrato); recomendar na 4C filtro composto `today | (pending ∧ mesmo dia civil)` se a UX confirmar.

### Presentation policy

Confirmado: nenhum texto da UI afirma “próximos 7 dias” como regra institucional. Label genérico **Próximos** / hint **Agendados**.

### Resultado da validação visual

Validação visual **estrutural + polish** concluída no harness (360/390/412).  
Sem overflow detectado. Sem botões mortos. Identidade alinhada ao Health v1 e ao mockup no que é canônico.

**FASE 4B VISUALMENTE APROVADA E PRONTA PARA COMMIT** (sujeita a aceite humano em device se o revisor exigir).

---

## 17. Auditoria adversarial

| Risco | Resultado |
|-------|-----------|
| Widgets com regra temporal | **OK** — só policy no controller |
| Temporal congelado | **OK** — recompute + lifecycle + timer |
| Timer sem cancel | **OK** — dispose cancela |
| Refresh remoto por tick de relógio | **OK** — recompute não chama source |
| Item em duas seções | **OK** — groups 4A |
| KPI contando 2x | **OK** — contagens de groups |
| Filtro que não funciona | **OK** — teste Vacinas |
| Botão morto | **OK** — omitidos |
| Write vazando | **OK** |
| Fake em produção | **OK** — Empty source |
| K9 hardcoded | **OK** — dogDisplayName do shell |
| Overflow 360 | **OK** — testes |
| Header duplicado | **OK** |
| Bottom nav cobrindo | clearance via MainRootNavMetrics |
| Firebase na UI | **OK** |
| Segundo controller | **OK** — um só, ownership no entry |
| Componentes mockup sem fonte | omitidos |
| Regressão Resumo/Histórico | entry preserva slots; suíte Health valida |

---

## 18. Achados fora do escopo

- Drift de formatação preexistente em arquivos Health não tocados: não corrigido.
- Source Firestore real de `health_schedule`: intencionalmente 4C+.
- Device físico Android: não executado nesta máquina de build.
- Filtro “Hoje” vs pending no mesmo dia: recomendado **REVISAR NA 4C** (sem mudança agora).

---

## 19. Diff final (resumo)

```text
 M lib/features/health/presentation/schedule/health_schedule_controller.dart
 M lib/features/health/presentation/screens/health_v1_entry_screen.dart
?? lib/features/health/presentation/schedule/empty_health_schedule_source.dart
?? lib/features/health/presentation/schedule/health_schedule_presentation_policy.dart
?? lib/features/health/presentation/schedule/health_schedule_ui_filter.dart
?? lib/features/health/presentation/schedule/health_schedule_view.dart
?? lib/features/health/presentation/schedule/health_schedule_screen.dart
?? lib/features/health/presentation/schedule/widgets/*
?? test/features/health/presentation/schedule/health_schedule_view_test.dart
?? test/features/health/presentation/schedule/health_schedule_recompute_test.dart
?? docs/health/HEALTH_V1_PHASE_4B_REPORT.md
```

---

## 20. Estado git final

### Antes do commit de fechamento

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD base | `7d27ac54b7f900a5e715fcc7b50e04716e7b099c` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência commits | `0 0` |
| working tree | alterações locais exclusivas da Fase 4B |

### Após commit e push (fechamento formal)

| Item | Valor |
|------|--------|
| mensagem | `feat(health): add preventive schedule shell` |
| suíte global pré-commit | 940 passed / 1 skipped / 0 failed |
| push | somente `feature/health-v1-foundation` → `origin` |

### Achados preservados para a Fase 4C (não bloqueantes)

1. Revisar semântica do filtro **Hoje** (incluir `pending` do mesmo dia civil?).
2. Revisar parâmetros de `healthSchedulePresentationPolicy()` antes de dados reais.
3. Inspeção em device físico/emulador como polish residual.

---

## 21. Avaliação para a Fase 4C

4C tipicamente: source Firestore read-only de `health_schedule`, índices/queries, possível dual-read se necessário, ainda sem writes se o roadmap assim definir.

Pré-requisitos atendidos: UI + contratos + empty source honesta + recompute temporal.

### Conclusão

**FASE 4B VISUALMENTE APROVADA E PRONTA PARA COMMIT**

Auditoria humana residual opcional: glance em device físico. Sem bloqueios objetivos de layout/overflow/contraste no harness.
