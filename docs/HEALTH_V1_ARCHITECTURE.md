# K9 Ops — Health Module v1.0

Versão: 1.0
Status: Arquitetura Aprovada
Última atualização: Julho/2026

---

# Objetivo

O módulo Saúde deixa de ser apenas um prontuário veterinário e passa a representar o Centro de Prontidão Operacional do K9.

Seu objetivo é responder continuamente:

> O K9 está apto para atividade operacional?

Toda informação clínica, preventiva e nutricional converge para essa resposta.

---

# Princípios

- Mobile prioriza rapidez operacional.
- Web concentra gestão, planejamento e administração.
- Todo registro possui auditoria.
- Todo evento pertence a um Caso Clínico quando aplicável.
- A saúde influencia diretamente a prontidão operacional.
- Nenhuma decisão clínica pode ser perdida.
- Histórico imutável.
- Fluxo totalmente rastreável.

---

# Estrutura Geral

Centro de Prontidão K9

├── Resumo
├── Histórico Clínico
├── Agenda Preventiva
├── Nutrição
├── Tratamentos
├── Exames
├── Consultas
├── Pesagens
├── Vacinação
├── Documentos
└── Prontidão Operacional

---

# Navegação

Resumo

Histórico

Agenda

Nutrição

Botão superior:

+ Registrar

abre:

Hub de Registros

---

# Hub de Registros

## Rotina

- Alimentação
- Pesagem
- Suplementação
- Observação diária

## Preventivo

- Vacinação
- Antiparasitário
- Agendamento
- Avaliação preventiva

## Clínico

- Consulta veterinária
- Tratamento
- Exame
- Intercorrência

## Documentos

- Receita
- Laudo
- Exame
- Atestado
- PDF
- Foto

---

# Fluxo Clínico

Intercorrência

↓

Consulta Veterinária

↓

Exame

↓

Tratamento

↓

Reavaliação

↓

Alta Clínica

↓

Prontidão Atualizada

---

# Submódulo Nutrição

O Plano Alimentar será administrado pela Web.

O Mobile será responsável apenas por:

- visualizar plano ativo
- registrar refeições
- registrar suplementos
- consultar histórico

Regra:

WEB DEFINE

↓

MOBILE EXECUTA

---

# Saúde Clínica

Contempla:

- Consultas
- Exames
- Vacinas
- Pesagens
- Intercorrências
- Tratamentos
- Reavaliações
- Alta

---

# Exames

Separação obrigatória:

Solicitação

↓

Coleta

↓

Resultado Técnico

↓

Interpretação Veterinária

↓

Impacto Operacional

---

# Tratamentos

Todo tratamento gera um protocolo.

TreatmentProtocol

- medicamento
- doses
- frequência
- responsáveis
- lembretes
- agenda
- evolução
- reavaliação
- encerramento

---

# Histórico Clínico

Timeline única contendo:

- alimentação
- pesagem
- consulta
- vacina
- exame
- tratamento
- dose
- intercorrência
- alta
- documentos

Todos seguem o mesmo contrato de evento.

---

# Agenda Preventiva

Reúne:

- refeições
- suplementos
- doses
- consultas
- exames
- vacinas
- pesagens
- reavaliações

## Lifecycle persistido (documento `health_schedule`)

Somente estes valores são gravados em `lifecycle_status`:

- `open`
- `completed`
- `cancelled`

Create manual: `scheduled_for` deve ser **presente ou futuro** (autoridade backend).
`pending` / `overdue` **não** são valores de create — surgem só com a passagem do tempo.

## Status temporal derivado (somente leitura / UI)

Calculados no cliente a partir de `scheduled_for`, `due_until` e agora:

- `scheduled` (programado)
- `upcoming` (próximo)
- `today` (hoje)
- `pending` (pendente)
- `overdue` (atrasado)

**Nunca** são persistidos como campos do documento.
`completed` / `cancelled` na UI de timeline/status visual refletem o lifecycle terminal, não um campo temporal separado.

---

# Prontidão Operacional

Será calculada futuramente pelo IPO.

O IPO nunca poderá sobrescrever restrições clínicas.

Bloqueios absolutos sempre prevalecem.

Estados:

- Operacional
- Operacional com Atenção
- Apto com Restrições
- Temporariamente Inapto
- Não Avaliado

---

# Framework comum de formulários

Todos os formulários clínicos compartilham:

1. Contexto do K9
2. Dados principais
3. Seções específicas
4. Observações
5. Anexos
6. Responsável
7. Impacto Operacional
8. Auditoria
9. Salvar

---

# Componentes compartilhados

- HealthDogContextCard
- HealthSectionCard
- OperationalImpactCard
- ProfessionalCard
- AttachmentPicker
- AuditCard
- StickySaveBar
- StatusSelector
- ClinicalMetricGrid
- TimelineCard

---

# Modelo lógico (preliminar)

```
dogs/{dogId}
├── health_summary
├── health_timeline
├── weight_records
├── nutrition_plans
├── meal_logs
├── supplement_logs
├── consultations
├── vaccinations
├── clinical_incidents
├── treatment_protocols
├── exam_results
├── health_documents
├── health_schedule
└── clinical_cases
```

---

# Mockups aprovados

01 — Saúde e Prontidão
02 — Hub de Registros
03 — Nutrição
04 — Registrar Alimentação
05 — Plano Alimentar
06 — Histórico Clínico
07 — Agenda Preventiva
08 — Consulta Veterinária
09 — Pesagem
10 — Vacinação
11 — Tratamento
12 — Administração de Dose
13 — Registro Clínico
14 — Intercorrência
15 — Tratamento com Restrição
16 — Reavaliação
17 — Resultado de Exame

---

# Health v1.0

Inclui:

- [x] Dashboard
- [x] Nutrição
- [x] Histórico
- [x] Agenda
- [x] Alimentação
- [x] Pesagem
- [x] Vacinação
- [x] Consulta
- [x] Exames
- [x] Intercorrências
- [x] Tratamentos
- [x] Doses
- [x] Alta
- [x] Auditoria
- [x] Documentos

---

# Health v2

Futuras expansões:

- Fisioterapia
- Internação
- Centro Cirúrgico
- Integração com Estoque
- IA
- IPO
- Prontuário Compartilhado
- Integração com Clínicas

---

# Decisões Arquiteturais

- Web administra planos.
- Mobile executa protocolos.
- Timeline única.
- Caso Clínico conecta registros.
- Auditoria obrigatória.
- Framework comum de formulários.
- Prontidão integrada.
- Arquitetura preparada para expansão futura.

---

# Integração canônica de Pesagem (WEIGHT-00C)

Status: **APPROVED TARGET — NOT YET DEPLOYED**. A fonte normativa é
`health/HEALTH_WEIGHT_CANONICAL_SPEC.md`; lifecycle em
`health/adr/ADR-008-WEIGHT-ASSESSMENT-LIFECYCLE.md`.

O estado implantado continua limitado ao create simples Mobile → callable
`healthWeightCreateRecord` → transação/receipt/audit → `weight_records` e campos
de compatibilidade no K9. Mobile e Web leem diretamente
`dogs/{dogId}/weight_records`; resumo, gráfico, prontuário e histórico atuais são
compostos por esses readers. O documento do K9 mantém temporariamente `weight`,
`_last_weight_kg` e `_last_weight_at`. A projeção-alvo de Pesagem em
`health_summary/current` e uma `health_timeline` materializada como fonte do peso
ainda não estão implantadas. Readers diretos e denormalizações são apenas
compatibilidade temporária.

No target, toda mutação percorre uma command boundary backend-only. Um serviço de
projeção recalcula summary, timeline, gráficos, rotina, faixa e delta a partir de
`weight_records`. Attachments usam `HealthDocument` e fila independente. O
offline futuro usa command queue local com operationId e somente confirma após
receipt; nunca usa write direto.

Web pode visualizar imagens, legendas e metadados permitidos; consultar histórico,
detalhes, auditoria, gráficos e filtros; e administrar faixa/meta quando
autorizada. Web não pode adicionar, remover ou substituir imagens, executar
mutation operacional de attachment nem registrar Pesagem como fluxo operacional
padrão. Mutations de attachment permanecem Mobile-initiated por command backend
autorizado. Ferramentas administrativas extraordinárias futuras não fazem parte
deste target. O writer Web legado deve ser retirado antes do rollout ampliado.
