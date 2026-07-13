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

Estados

- Programado
- Próximo
- Hoje
- Pendente
- Atrasado
- Concluído
- Cancelado

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
