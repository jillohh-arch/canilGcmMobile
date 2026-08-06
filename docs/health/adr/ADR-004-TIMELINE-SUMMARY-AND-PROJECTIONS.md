# ADR-004 — Timeline, Resumo e Projeções

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-002, ADR-003, HEALTH_V1_FIRESTORE_SCHEMA.md |
| Escopo | Estratégia de composição da timeline e health_summary (projeções); health_schedule como agregado canônico; materialização vs. consulta |
| Fora de escopo | Implementação de Functions, índices reais, IPO, IA |

---

## 1. Contexto

A timeline atual é montada inteiramente no cliente: `HistoryScreen` carrega `health_events` (50), `weight_records` (200), `feeding_events` e `feedings`, transforma em `HistoryEntry`, ordena e filtra em memória. Isso gera limitações severas: não há paginação real, filtros são incompletos, documentos e suplementos ficam fora, e a composição é custosa e inconsistente entre telas.

O Health v1.0 Architecture exige "Timeline única" contendo alimentação, pesagem, consulta, vacina, exame, tratamento, dose, intercorrência, alta e documentos. A auditoria recomenda que timeline e resumo sejam projeções server-side.

---

## 2. Problema

Como construir uma timeline clínica completa, paginável, filtrável e consistente, que componha dados de múltiplos agregados sem forçar o cliente a carregar tudo em memória, mantendo custo razoável e suporte offline?

---

## 3. Classificação das coleções

| Coleção | Natureza | Justificativa |
|---------|----------|---------------|
| `health_timeline` | **Projeção** | Derivada das fontes canônicas; reconstruível a qualquer momento |
| `health_summary` | **Projeção** | Agregação de indicadores; reconstruível a partir de restrições, casos, tratamentos, peso, vacinas, nutrição |
| `health_schedule` | **Agregado canônico** | Contém informação que não existe em nenhum outro lugar (agendamentos manuais, decisões de condutor). Não é projeção. |

---

## 4. Requisitos obrigatórios

1. Timeline deve conter TODOS os tipos de registro clínico e de rotina.
2. Paginação real por cursor (não carregar tudo e paginar em memória).
3. Filtros por tipo, período, caso clínico e profissional.
4. Consistência: um registro criado deve aparecer na timeline em tempo razoável (<30s).
5. Suporte offline: dados já carregados devem permanecer disponíveis.
6. Reconstrução: a timeline deve ser reconstruível a partir das fontes canônicas.
7. O resumo (health_summary) deve agregar indicadores sem exigir N queries do cliente.
8. Agenda deve listar próximas ações com estados temporais derivados no cliente.
9. Idempotência: reprocessar o mesmo evento não duplica na timeline.
10. Dados legados migrados devem aparecer na timeline sem tratamento especial no cliente.

---

## 5. Opções consideradas

### Opção A — Timeline montada no cliente (status quo melhorado)

Cliente consulta cada coleção com paginação independente, faz merge e ordena localmente. Melhoria: adicionar paginação real por coleção e incluir tipos faltantes.

### Opção B — Collection group query sobre fontes canônicas

Usar um campo `dog_id` + `timeline_at` padronizado em todos os agregados e consultar via collection group query. Nenhuma coleção de projeção.

### Opção C — Projeção materializada server-side

Cloud Function escuta writes em todas as fontes canônicas e materializa um documento resumido em `dogs/{dogId}/health_timeline/{id}`. Cliente consulta apenas essa coleção.

### Opção D — Modelo híbrido (projeção + inserção otimista local)

Projeção server-side como fonte principal. Cliente insere otimisticamente na lista local durante janela de eventual consistency. Adapters legados alimentam a projeção via backfill.

---

## 6. Comparação das opções

| Critério | A (cliente) | B (collection group) | C (projeção pura) | D (híbrido) |
|----------|------------|---------------------|-------------------|-------------|
| Consistência | Baixa (merge imperfeito) | Alta (fonte real) | Eventual (~5s) | Eventual + otimista |
| Paginação | Complexa (N cursores) | Simples (1 cursor) | Simples (1 cursor) | Simples (1 cursor) |
| Filtros | Limitados | Limitados (collection group restringe) | Flexíveis (campos na projeção) | Flexíveis |
| Custo de leitura | Alto (N queries) | Médio (1 query, índice especial) | Baixo (1 query simples) | Baixo |
| Custo de escrita | Zero adicional | Zero adicional | 1 write extra por evento | 1 write extra |
| Offline | Parcial (N caches) | Parcial | Bom (cache de 1 coleção) | Bom |
| Reconstrução | Não aplicável | Não aplicável (é a fonte) | Sim (reprocessa fontes) | Sim |
| Compatibilidade legado | Requer adapters no cliente | Requer campo padronizado em legado | Backfill popula projeção | Backfill + adapter |
| Manutenção | Baixa | Média (schema cross-collection) | Alta (Function para cada fonte) | Alta |

---

## 7. Recomendação

**Opção D — Modelo híbrido (projeção + inserção otimista local).**

Justificativa:

- **Projeção materializada** resolve paginação, filtros e performance de leitura de forma definitiva.
- **Inserção otimista local temporária** cobre o gap de eventual consistency (evento acabou de ser criado e a Function ainda não rodou) sem que o cliente reconstrua a timeline a partir de múltiplas fontes.
- **Backfill** permite migrar dados legados para a timeline sem alterar os documentos originais.
- **Reconstrução** garante que a projeção pode ser regenerada a qualquer momento sem perda.

**A direção arquitetural server-side da timeline e do summary está aprovada.** A implementação permanece condicionada ao gate **O3** de custo, SLA, reconciliação e operação das Functions.

---

## 8. Consequências positivas

- Cliente faz UMA query paginada para timeline, com filtros nativos do Firestore.
- Todos os tipos aparecem uniformemente (inclusive legados após backfill).
- Cache offline é uma única coleção, mais simples de gerenciar.
- Health_summary é atualizado atomicamente pela mesma Function.
- Campos de amendment (has_amendments, amendment_count) na projeção permitem rastrear retificações sem buscar o documento fonte.

---

## 9. Consequências negativas

- Custo de escrita: cada registro gera 1 write adicional na projeção.
- Complexidade operacional: Function precisa escutar N coleções.
- Eventual consistency: há uma janela de 1-5s entre write canônico e aparecimento na timeline.
- Se a Function falhar, a projeção fica desatualizada até retry.
- Necessidade de reconciliação periódica (scheduled Function) para detectar inconsistências.

---

## 10. Compatibilidade com o legado

| Fonte legada | Estratégia |
|--------------|-----------|
| `health_events` (todos os tipos, todos os registros) | **Não** alimentam a timeline diretamente. A projeção legada é feita a partir de `legacy_health_records` (após backfill). Function projeta registros de `legacy_health_records` com `legacy_source` e `legacy_id` preservados. |
| `weight_records` | Backfill: projeta na timeline |
| `feeding_events` / `feedings` | Backfill: deduplica por ID e projeta |
| `nutrition_supplements` | Backfill: projeta administrações |
| `documentos` | Backfill: projeta como tipo "document" (HealthDocument usa `storage_path` canônico) |
| `vacinas` | Backfill: projeta como tipo "vaccination" — entradas originadas em `vaccination_records` (canônico) ou `legacy_health_records` (incompletos) |

Todos os itens projetados carregam `source_collection`, `source_id` e `legacy_source` para rastreabilidade. A direção server-side da projeção está aprovada; a implementação detalhada permanece condicionada ao gate **O3** (custo/SLA final das projeções) do Foundation Review.

---

## 11. Impacto em Mobile

- Timeline: UMA query em `dogs/{dogId}/health_timeline` com `orderBy(occurred_at desc)`, cursor e filtros.
- Resumo: leitura de `dogs/{dogId}/health_summary/current` (documento único, stream).
- Agenda: query em `dogs/{dogId}/health_schedule` com filtros de `lifecycle_status` e `scheduled_for`.
- Inserção otimista local temporária: ao criar um registro, o formulário insere uma entrada temporária na lista local. Se após 30s a projeção não confirmar a entrada, exibir indicador `sync_pending`. O cliente NÃO reconstrói a timeline a partir de múltiplas fontes.
- Fontes factuais sem lifecycle próprio (peso, refeição e suplemento) entram com `status: final`. Fonte posteriormente cancelada ou invalidada entra/é atualizada como `status: cancelled`. Drafts nunca entram na timeline principal.
- Offline: cache do Firestore SDK sobre a coleção de timeline.

---

## 12. Impacto em Web

- Mesmas queries que Mobile.
- Web pode oferecer filtros avançados (por profissional, por caso, por tipo de impacto).
- Web pode disparar reconciliação manual se detectar inconsistência.

---

## 13. Impacto em Firestore

### health_timeline (projeção)

```
dogs/{dogId}/health_timeline/{timelineId}
├── timeline_type: enum (consultation, vaccination, weight, meal, supplement,
│                        exam, treatment, dose, incident, discharge,
│                        restriction, document, observation, preventive)
├── occurred_at: timestamp (quando aconteceu)
├── recorded_at: timestamp (quando foi registrado)
├── projected_at: timestamp (quando a Function projetou)
├── title: string (resumo curto para exibição)
├── subtitle: string (detalhe secundário)
├── case_id: string (nullable — vínculo com caso clínico)
├── case_title: string (nullable — snapshot para exibição sem join)
├── source_collection: string (caminho da fonte canônica)
├── source_id: string (ID do documento fonte)
├── recorded_by: RecordedBy { uid, name, internal_role }
├── professional: ProfessionalIdentity (nullable)
├── operational_impact: { level, description } (nullable)
├── status: "final" | "cancelled"
├── has_amendments: bool
├── amendment_count: number
├── last_amended_at: timestamp
├── has_attachments: bool
├── schema_version: number
├── legacy_source: string (nullable)
└── legacy_id: string (nullable)
```

**Status na timeline:** apenas registros `final` ou `cancelled` aparecem na timeline principal. Rascunhos não entram. Adendos NÃO criam um novo status — são representados pelos metadados `has_amendments`, `amendment_count`, `last_amended_at`.

**ID determinístico:** o `timelineId` é um hash de `source_collection + source_id`, garantindo idempotência e reconstrução sem duplicatas.

**Busca textual:** fora do escopo do v1. Mecanismo será avaliado em versão futura quando o volume justificar indexação dedicada.

### health_summary (projeção)

```
dogs/{dogId}/health_summary/current
├── readiness_status: enum (5 estados oficiais)
├── readiness_updated_at: timestamp
├── active_restrictions: [ { id, level, description, since } ]
├── active_cases_count: number
├── active_treatments_count: number
├── last_weight: { kg, measured_at, bcs }
├── last_vaccination: { type, date, next_due }
├── last_exam: { type, date, status }
├── last_consultation: { date, professional, case_id }
├── nutrition_plan: { active, food_type, amount_grams }
├── pending_schedule_count: number
├── overdue_schedule_count: number
├── open_alerts: [ { type, message, since } ]
├── updated_at: timestamp
└── schema_version: number
```

### health_schedule (agregado canônico)

```
dogs/{dogId}/health_schedule/{scheduleId}
├── schedule_type: enum (dose, vaccination, exam, consultation, weighing, reevaluation)
├── title: string
├── scheduled_for: timestamp (data/hora programada)
├── due_until: timestamp (nullable — limite de tolerância; após este ponto, considerar atrasado)
├── timezone: string (ex: "America/Sao_Paulo")
├── lifecycle_status: "open" | "completed" | "cancelled"
├── source_type: string (treatment_protocol, clinical_case, preventive, manual)
├── source_id: string
├── case_id: string (nullable)
├── assigned_to: { uid, name } (nullable)
├── completed_at: timestamp (nullable)
├── completed_by: RecordedBy { uid, name, internal_role } (nullable)
├── cancelled_at: timestamp (nullable)
├── cancelled_by: RecordedBy { uid, name, internal_role } (nullable)
├── cancel_reason: string (nullable)
├── created_at: timestamp
├── recorded_by: RecordedBy { uid, name, internal_role } | "system"
├── notes: string (nullable)
└── schema_version: number
```

**Estados temporais derivados no cliente:** o campo `lifecycle_status` persiste apenas o ciclo de vida do agendamento. Os estados de apresentação temporal são derivados no momento da leitura.

**Data efetiva única:**

```text
effective_due_until =
  due_until
  ?? resolveTolerance(schedule_type, scheduled_for, timezone)
```

Quando `due_until` estiver ausente, a tolerância **deve** ser resolvida por configuração por `schedule_type`. Não há default universal — uma configuração válida deve existir para cada `schedule_type`.

**Precedência (avaliada na ordem; primeira verdadeira vence):**

| # | Condição | Estado exibido |
|---|----------|----------------|
| 1 | `lifecycle_status == "completed"` | `completed` (terminal) |
| 2 | `lifecycle_status == "cancelled"` | `cancelled` (terminal) |
| 3 | `now > effective_due_until` | `overdue` |
| 4 | `now >= scheduled_for` | `pending` |
| 5 | `scheduled_for` é hoje no timezone do item | `today` |
| 6 | item está dentro da janela próxima (≤ N dias, configurável por `schedule_type`) | `upcoming` |
| 7 | restante | `scheduled` |

A regra é única e absoluta: o primeiro caso verdadeiro vence. Não há caso em que o mesmo item seja simultaneamente `pending` e `overdue`. Toda derivação é pura, sem efeito colateral, e ocorre no momento da renderização. **Estados temporais nunca são persistidos como campos no documento.**

---

## 14. Impacto em segurança

- Projeções (`health_timeline`, `health_summary`) devem ser **read-only para clientes**. Apenas operação administrativa backend/Admin SDK pode escrever.
- Agenda (`health_schedule`) pode ser criada por condutor (ex: agendar pesagem) e por backend (ex: próxima dose de protocolo).
- Rules devem bloquear create/update/delete de timeline e summary por clientes.

---

## 15. Impacto em testes

- Testes de Function: dado um write canônico, verificar que a projeção aparece com campos corretos (incluindo has_amendments, amendment_count).
- Testes de idempotência: reprocessar o mesmo evento não cria duplicata (ID determinístico por hash).
- Testes de reconciliação: deletar projeção e reprocessar regenera corretamente.
- Testes de paginação: cursor funciona com 100+ itens.
- Testes de filtros: cada tipo aparece quando filtrado.
- Testes de inserção otimista: cliente mostra item recém-criado antes da projeção chegar; indicador sync_pending aparece após 30s sem confirmação.
- Testes de legado: item migrado aparece na timeline com tipo correto.
- Testes de derivação temporal: cliente calcula corretamente os estados (upcoming, today, pending, overdue) sem persistência.
- Testes de draft: registros com `status: draft` NÃO aparecem na timeline principal.

---

## 16. Questões abertas

1. **Latência aceitável da projeção:** 5s? 30s? Proposta: SLA de 10s em condições normais; inserção otimista local cobre o gap; após 30s sem confirmação, indicador sync_pending.
2. **Granularidade da timeline:** cada dose individual aparece ou apenas o protocolo? Proposta: doses aparecem individualmente (são eventos relevantes operacionalmente).
3. **Limite de itens na projeção:** limitar a N mais recentes ou manter tudo? Proposta: manter tudo; paginação é por cursor, não por tamanho da coleção.
4. **Reconciliação automática:** com que frequência? Proposta: scheduled Function diária que compara contagens fonte × projeção e reprojeta divergências.
5. **health_summary atualiza em real-time ou batch?** Proposta: real-time (trigger nas fontes relevantes). O documento é pequeno e o custo de 1 write é aceitável.
6. **Thresholds de due_until ausente:** quando `due_until` é null, a tolerância é resolvida por configuração por `schedule_type`. A configuração deve existir para todo `schedule_type` ativo; não há default universal. A janela "upcoming" também é parâmetro configurável (default proposto: 7 dias), e o limite de alerta de reavaliação após `expected_end` (proposta: 30 dias) também. Esses thresholds **não são bloqueadores** — podem evoluir sem reabrir esta ADR.

---

## 17. Critérios para aprovação

- [ ] A classificação de cada coleção está clara (projeção vs. agregado canônico).
- [ ] health_schedule é agregado canônico com estados temporais derivados no cliente.
- [ ] Nenhuma Function reescreve schedule por passagem de tempo.
- [ ] A relação entre timeline, summary e schedule está definida sem ambiguidade.
- [ ] Paginação real por cursor está garantida no design.
- [ ] Inserção otimista local temporária está definida para eventual consistency (sem reconstrução client-side da timeline).
- [ ] ID determinístico (hash de source) garante idempotência.
- [ ] Campos de amendment estão presentes na projeção.
- [ ] Busca textual é mecanismo futuro, não campo v1.0.
- [ ] Dados legados podem ser projetados sem alteração nas fontes originais.

---

## Diagrama de fluxo de dados

```text
┌─────────────────────────── FONTES CANÔNICAS ───────────────────────────┐
│                                                                         │
│  clinical_cases/events  weight_records  meal_logs  supplement_logs      │
│  treatment_protocols/doses  nutrition_plans  health_documents           │
│  operational_restrictions  health_schedule (agregado canônico)          │
│  vaccination_records  clinical_cases/{caseId}/exams                      │
│                                                                         │
└──────────────┬──────────────────────────────────────────────────────────┘
               │
               │  Firestore triggers (onCreate, onUpdate, onDelete)
               ▼
┌─────────────────────────── CLOUD FUNCTIONS ────────────────────────────┐
│                                                                         │
│  projectTimelineEntry()     → health_timeline/{hash(source+id)}        │
│  updateHealthSummary()      → health_summary/current                   │
│  reconcileTimeline()        → scheduled, compara contagens             │
│                                                                         │
│  (Nenhuma Function reescreve health_schedule por passagem de tempo)    │
│                                                                         │
│  (Origem legada: legacy_health_records — health_events pré-go-live      │
│   são projetados a partir desta coleção, NÃO diretamente de            │
│   health_events. Implementação detalhada condicionada ao gate O3.)     │
│                                                                         │
└──────────────┬──────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────── PROJEÇÕES ──────────────────────────────────┐
│                                                                         │
│  health_timeline/{id}        → timeline paginável, filtrável           │
│  health_summary/current      → indicadores consolidados                │
│                                                                         │
└──────────────┬──────────────────────────────────────────────────────────┘
               │
               │  Queries simples (1 coleção, cursor, filtros)
               ▼
┌─────────────────────────── CLIENTES ───────────────────────────────────┐
│                                                                         │
│  Mobile: timeline, resumo, agenda                                      │
│  Web: timeline, resumo, agenda, administração                          │
│                                                                         │
│  Inserção otimista local temporária: item recém-criado inserido na     │
│  lista local até a projeção confirmar.                                 │
│  Após 30s sem confirmação: indicador sync_pending.                     │
│                                                                         │
│  Agenda: estados temporais (scheduled, upcoming, today, pending,       │
│  overdue) derivados no momento da leitura, sem persistência.           │
│                                                                         │
│  Somente registros finalizados aparecem na timeline principal.         │
│  Drafts permanecem em lista separada.                                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Relação entre coleções

| Coleção | Natureza | Alimentada por | Atualização | Uso principal |
|---------|----------|---------------|-------------|---------------|
| `health_timeline` | Projeção | Todas as fontes canônicas | Trigger por write | Tela de histórico, filtros |
| `health_summary` | Projeção | Restrições, casos, tratamentos, peso, vacinas, nutrição | Trigger seletivo | Dashboard, resumo, prontidão |
| `health_schedule` | Agregado canônico | Treatment protocols, clinical cases, registros preventivos, criação manual | Criação mista (Function + condutor) | Tela de agenda, alertas, notificações |

`health_schedule` é **agregado canônico** (não projeção): ele contém informação que não existe em nenhum outro lugar (ex: agendamento manual de pesagem). Seus estados temporais de exibição são derivados pelo cliente no momento da leitura — nenhuma Function periódica reescreve o documento.

`health_timeline` e `health_summary` são **projeções reconstruíveis** a qualquer momento a partir das fontes canônicas.

### Integração de Pesagem — APPROVED TARGET / NOT YET DEPLOYED

`weight_records` permanece a fonte canônica. Peso atual é o registro válido
ordenado por `measured_at DESC`, `recorded_at DESC`, entityId DESC, sem preferência
Quick/Official. Create produz uma entrada determinística; complemento e correção
atualizam a mesma entrada; invalidação preserva a entrada marcada e a oculta no
default; operação exclusiva de attachment não cria nova linha.

`health_summary/current` projeta record ID/type, peso/data atuais, delta, faixa,
rotina 7/14 e BCS Official corrente. Uma retroativa não substitui uma medição
posterior. Correção e invalidação recomputam vizinhos e todas as projeções
afetadas. Campos de peso no documento K9 são compatibilidade temporária, não
autoridade. Ver ADR-008 e `../HEALTH_WEIGHT_CANONICAL_SPEC.md`.
