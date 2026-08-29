# ADR-003 — Workflow do Caso Clínico

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-002, ADR-005, HEALTH_V1_DOMAIN_MODEL.md |
| Escopo | Estados, transições e ciclo de vida do ClinicalCase |
| Fora de escopo | Implementação Dart, UI de formulários, IPO |

---

## 1. Contexto

O Health v1.0 Architecture define que "Todo evento clínico pertence a um Caso Clínico" e descreve o fluxo: Intercorrência → Consulta → Exame → Tratamento → Reavaliação → Alta → Prontidão Atualizada. Atualmente não existe nenhuma entidade que conecte esses passos. Cada registro clínico é um `health_event` isolado sem vínculo com outros.

Adicionalmente, é necessário definir como tratar a reabertura (erro de alta, encerramento prematuro) vs. recorrência (novo episódio da mesma condição após alta legítima), e preservar todos os `health_events` anteriores ao go-live em `legacy_health_records`.

---

## 2. Problema

Como modelar o ciclo de vida de um caso clínico que conecte eventos heterogêneos (intercorrência, consulta, exame, tratamento, reavaliação, alta), permita múltiplos caminhos, suporte cancelamento, diferencie reabertura de recorrência, e mantenha separação entre status clínico, status operacional e status de agenda?

---

## 3. Requisitos obrigatórios

1. ClinicalCase conecta 1..N ClinicalEvents.
2. Abertura pode ser por intercorrência OU por consulta programada.
3. Caso pode ter múltiplos exames, tratamentos e reavaliações.
4. Alta encerra o caso e pode liberar restrições.
5. Reabertura é uma AÇÃO (não um estado durável) que retorna o caso ao estado clínico aplicável.
6. Reabertura só é permitida quando: alta foi erro, encerramento prematuro, ou mesmo episódio ainda em curso.
7. Recorrência após alta legítima cria um NOVO ClinicalCase com vínculo informativo.
8. Cancelamento por erro preserva o caso e seus eventos (soft).
9. Status clínico, status operacional e status de agenda são independentes.
10. Caso não bloqueia registros de rotina (peso, refeição continuam independentes).
11. Um K9 pode ter múltiplos casos abertos simultaneamente (ex: ortopédico + dermatológico).
12. Todo ClinicalEvent novo SEMPRE pertence a um ClinicalCase real.
13. Todos os `health_events` anteriores ao go-live vão para `legacy_health_records`, independentemente de agrupamento lógico detectável, e NÃO são promovidos automaticamente para `clinical_cases`.

---

## 4. Opções consideradas

### Opção A — Estado único linear

O caso tem um único campo `status` que percorre uma sequência fixa: aberto → em_tratamento → em_reavaliação → encerrado.

### Opção B — Estados compostos (clínico × operacional × agenda)

Três dimensões independentes, cada uma com seus próprios estados. O "status" visível é uma composição.

### Opção C — Estado clínico com flags operacionais (sem estado "reaberto")

Um estado clínico principal (que governa transições) acompanhado de flags/campos que indicam impacto operacional e itens de agenda pendentes. Reabertura é uma ação que retorna ao estado clínico aplicável, não um estado intermediário.

---

## 5. Comparação das opções

| Critério | A (linear) | B (compostos) | C (clínico + flags) |
|----------|-----------|---------------|---------------------|
| Simplicidade de transição | Alta | Baixa (combinatória) | Média |
| Expressividade | Baixa (não cabe "em tratamento E aguardando exame") | Máxima | Alta |
| Complexidade de Rules | Baixa | Alta | Média |
| UX para condutor | Confusa (forçar sequência) | Confusa (muitos estados) | Clara (um estado principal) |
| Queries por status | Simples | Complexas (3 campos) | Simples (1 campo + filtros) |
| Suporte a múltiplos tratamentos | Não modela | Modela | Modela (tratamento é evento, não estado) |
| Reabertura vs. recorrência | Não diferencia | Difícil de expressar | Clara (ação vs. novo caso) |

---

## 6. Recomendação

**Opção C — Estado clínico com flags operacionais (sem estado "reaberto").**

O ClinicalCase possui um `clinical_status` principal que governa o ciclo de vida com 6 estados (open, under_investigation, under_treatment, monitoring, discharged, cancelled). Campos derivados (`has_active_restriction`, `has_pending_schedule`, `active_treatments_count`) são atualizados por Functions quando eventos são adicionados.

Reabertura é uma AÇÃO autorizada que transiciona de `discharged` diretamente para o estado clínico aplicável (open, under_investigation, under_treatment, monitoring), com evento imutável de reabertura registrado e metadados atualizados. Não existe estado intermediário "reopened".

Recorrência após alta legítima cria um NOVO ClinicalCase com `recurrence_of_case_id` e `related_case_ids` para manter vínculo informativo.

---

## 7. Consequências positivas

- Um único campo para filtrar/ordenar casos.
- Condutor vê um estado principal claro ("Em tratamento", "Aguardando resultado").
- Múltiplos tratamentos e exames coexistem sem criar estados combinatórios.
- Rules podem validar transições com uma lista finita de pares (from → to).
- Flags operacionais alimentam prontidão sem poluir o estado clínico.
- Sem estado "reaberto" intermediário: o caso volta direto ao estado clínico relevante.
- Diferenciação clara entre reabertura (erro/prematuridade) e recorrência (novo episódio).
- Eventos legados isolados não poluem a estrutura de casos clínicos.

---

## 8. Consequências negativas

- Flags derivados precisam ser mantidos em sincronia por Functions (eventual consistency).
- O estado clínico principal pode não capturar nuances ("em tratamento mas aguardando exame").
- Reabertura exige lógica adicional para determinar o estado de destino.
- Recorrência como novo caso pode dificultar visão unificada de condição crônica (mitigado por related_case_ids).

---

## 9. Compatibilidade com o legado

- **Não há caso clínico no legado.** Eventos existentes NÃO são forçados para dentro de clinical_cases.
- **Todos os `health_events` anteriores ao go-live:** migrados para `dogs/{dogId}/legacy_health_records/{recordId}`, independentemente de agrupamento lógico detectável; read-only para clientes (ver ADR-001).
- **Aparência na timeline:** legacy_health_records aparecem na HealthTimeline como "Registro legado" sem vínculo a caso.
- **Casos clínicos são criados apenas a partir do go-live do Health v1.0.**
- **Novos ClinicalEvents SEMPRE pertencem a um ClinicalCase real** — não existe `case_id: null` para eventos novos.

---

## 10. Impacto em Mobile

- Condutor registra intercorrência → sistema oferece "Abrir caso clínico?".
- Painel do caso mostra status, eventos, tratamentos ativos e próximas ações.
- Condutor pode adicionar eventos ao caso aberto.
- Condutor NÃO pode alterar `clinical_status` diretamente. `clinical_status` muda somente por ações explícitas server-orchestrated e auditadas (`health.discharge_case`, `health.complete_treatment`, etc.) — **não** é derivado de eventos.

---

## 11. Impacto em Web

- Usuário interno com capability pode abrir caso por consulta programada, identificando o profissional externo responsável via `ProfessionalIdentity`.
- Alta clínica e reabertura por decisão clínica externa exigem capability, identificação do profissional externo e evidência documental. Reabertura por erro administrativo exige capability, motivo e auditoria. Cancelamento administrativo exige `health.cancel_case` e `cancel_reason`, sem inventar profissional externo.
- Visão administrativa mostra todos os casos do K9 com filtros.
- Web pode vincular exames e tratamentos a casos.
- Web pode criar novo caso por recorrência com vínculo ao caso anterior.

---

## 12. Impacto em Firestore

```
dogs/{dogId}/clinical_cases/{caseId}
├── clinical_status: enum (6 estados — ver seção de estados)
├── title: string (resumo curto: "Lesão MPD", "Otite bilateral")
├── opened_at: timestamp
├── opened_by: RecordedBy { uid, name, internal_role }
├── opening_event_id: string (referência ao primeiro evento)
├── opening_type: "incident" | "consultation" | "preventive" | "administrative"
├── closed_at: timestamp (nullable)
├── closed_by: RecordedBy { uid, name, internal_role } (nullable)
├── closure_type: "discharge" | "cancelled" | "administrative" (nullable)
├── closure_reason: string (nullable)
│
│   Reabertura (metadados da última reabertura):
├── reopened_at: timestamp (nullable, última reabertura)
├── reopened_by: RecordedBy { uid, name, internal_role } (nullable)
├── reopen_reason: string (nullable)
├── previous_status: string (nullable, status antes da reabertura — sempre "discharged")
├── reopened_count: number (default 0)
│
│   Recorrência (vínculo informativo):
├── recurrence_of_case_id: string (nullable — aponta para caso anterior se for recorrência)
├── related_case_ids: [ string ] (nullable — vínculos informativos bidirecionais)
│
│   Profissional e flags derivados:
├── primary_professional: ProfessionalIdentity (nullable, PII)
├── has_active_restriction: bool (flag derivado)
├── has_pending_schedule: bool (flag derivado)
├── active_treatments_count: number (flag derivado)
├── last_event_at: timestamp (derivado)
├── event_count: number (derivado)
├── schema_version: number
└── tags: [ string ] (opcional — categorização livre)
```

---

## 13. Impacto em segurança

- Transições de `clinical_status` devem ser validadas em Rules (lista de pares permitidos).
- Alta clínica exige `health.discharge_case`, `ProfessionalIdentity` e `source_document`. Reabertura clínica exige `health.reopen_case`, `reopen_reason`, `ProfessionalIdentity` e `source_document`. Reabertura por erro administrativo exige `health.reopen_case`, `reopen_reason` e auditoria, sem inventar evidência externa. Cancelamento administrativo exige `health.cancel_case` e `cancel_reason`, sem exigir profissional externo.
- Condutor pode abrir caso e adicionar eventos, mas não pode fechar nem reabrir.
- Flags derivados só são writable por backend/Admin SDK (operação administrativa auditada).
- Reabertura requer `reopen_reason` não vazio + capability autorizada + `ProfessionalIdentity` (profissional externo responsável) + `source_document` (evidência documental). Reaberturas meramente administrativas por erro de fechamento exigem capability, reason e auditoria — sem inventar documento veterinário inexistente. Quando a reabertura representa decisão clínica externa, `ProfessionalIdentity` e `source_document` são obrigatórios.
- Mudanças de `clinical_status` são ações explícitas server-orchestrated (não inferência genérica a partir de eventos). Transições típicas:
  - `health.request_exam` → `under_investigation`
  - `health.create_treatment` (ativar protocolo) → `under_treatment`
  - `health.complete_treatment` → `monitoring`
  - `health.discharge_case` → `discharged`
- Cada transição é transacional e auditada. Sem override manual arbitrário.

---

## 14. Impacto em testes

- Testes de transição: todas as transições válidas e inválidas (6 estados).
- Testes de Rules: capability × transição (sem referências a role `vet`).
- Testes de integração: abrir caso → adicionar eventos → alta.
- Testes de reabertura: caso discharged → ação de reabertura → retorna a estado clínico.
- Testes de recorrência: novo caso com recurrence_of_case_id correto.
- Testes de concorrência: dois eventos simultâneos no mesmo caso.
- Testes de legado: todos os `health_events` anteriores ao go-live vão para `legacy_health_records`, independentemente de agrupamento lógico detectável.

---

## 15. Questões abertas

1. **Caso sem alta formal:** K9 melhora e ninguém registra alta. Proposta: Function sinaliza casos sem evento há >30 dias como "estagnado" para revisão, mas NÃO fecha automaticamente.
2. **Limite de reaberturas:** sem limite técnico; UI pode alertar quando `reopened_count > 2` mas **não** bloquear.

---

## 16. Políticas adicionais (Rascunhos e Cancelamento)

### Rascunhos de eventos

- Rascunho sem alteração por **48 horas** gera alerta ao `recorded_by`.
- **Nunca** cancelar rascunho automaticamente.
- Retomada é livre; cancelamento é explícito e registrado.

### Cancelamento de eventos

- Autor pode cancelar apenas `draft` próprio.
- Cancelamento de evento `final` exige capability `health.cancel_record`, justificativa (`cancel_reason` não vazio) e registro de profissional externo responsável quando aplicável.
- Conteúdo clínico original permanece preservado (campos `cancelled_at`, `cancelled_by`, `cancel_reason` adicionados; `content` permanece íntegro).

## 17. Critérios para aprovação

- [ ] 6 estados e transições cobrem todos os cenários do fluxo clínico aprovado.
- [ ] A separação entre status clínico, operacional e de agenda está clara.
- [ ] Reabertura está modelada como AÇÃO (não estado) sem perda de histórico.
- [ ] Recorrência está modelada como novo caso com vínculo informativo.
- [ ] Cancelamento preserva caso e eventos.
- [ ] Não há dependência circular entre caso e eventos.
- [ ] Todos os `health_events` anteriores ao go-live vão para `legacy_health_records` (não `clinical_cases`), independentemente de agrupamento lógico detectável.
- [ ] Novos ClinicalEvents sempre pertencem a um ClinicalCase real.

---

## Estados do ClinicalCase — `clinical_status`

| Estado | Label | Descrição | Pode transicionar para |
|--------|-------|-----------|----------------------|
| `open` | Aberto | Caso recém-criado, aguardando primeira avaliação | `under_investigation`, `under_treatment`, `monitoring`, `discharged`, `cancelled` |
| `under_investigation` | Em Investigação | Aguardando resultados de exames ou avaliação | `under_treatment`, `monitoring`, `open`, `discharged`, `cancelled` |
| `under_treatment` | Em Tratamento | Protocolo ativo de medicação/terapia | `monitoring`, `under_investigation`, `discharged`, `cancelled` |
| `monitoring` | Em Acompanhamento | Tratamento concluído, em período de observação/reavaliação | `under_treatment`, `under_investigation`, `discharged`, `cancelled` |
| `discharged` | Alta | Caso encerrado com resolução clínica | `open`, `under_investigation`, `under_treatment`, `monitoring` (via ação de reabertura) |
| `cancelled` | Cancelado | Caso criado por erro, preservado mas inativo | (terminal) |

**Total: 6 estados.** Não existe estado "reopened" — reabertura é uma ação que transiciona diretamente de `discharged` para o estado clínico aplicável.

---

## Reabertura — Definição

### Quando reabrir (vs. criar novo caso)

| Situação | Ação correta |
|----------|-------------|
| Alta foi registrada por erro (K9 ainda está em tratamento) | **Reabrir** o mesmo caso |
| Encerramento prematuro (complicação do mesmo episódio) | **Reabrir** o mesmo caso |
| Mesmo episódio ainda em curso (alta equivocada) | **Reabrir** o mesmo caso |
| Novo episódio da mesma condição após alta legítima | **Novo caso** com `recurrence_of_case_id` |
| Condição diferente | **Novo caso** sem vínculo |

### Requisitos da ação de reabertura

| Requisito | Descrição |
|-----------|-----------|
| `reopen_reason` | Justificativa obrigatória (texto livre) |
| `reopened_at` | Timestamp da reabertura |
| `reopened_by` | `RecordedBy { uid, name, internal_role }` — usuário interno que executou |
| `previous_status` | Sempre `discharged` (registra de onde veio) |
| `reopened_count` | Incrementado a cada reabertura |
| Estado de destino | O usuário interno escolhe: `open`, `under_investigation`, `under_treatment` ou `monitoring` |
| Evento imutável | ClinicalEvent de tipo `reopen` é criado com justificativa e destino |
| Capability | `health.reopen_case` — usuário interno autorizado registra a reabertura; `ProfessionalIdentity` e `source_document` são obrigatórios somente quando representa decisão clínica externa |

### Recorrência — Novo caso com vínculo

```
Novo ClinicalCase:
├── recurrence_of_case_id: "{caseId do caso anterior}"
├── related_case_ids: ["{caseId do caso anterior}"]
└── ... (demais campos normais de abertura)

Caso anterior (atualizado por Function):
├── related_case_ids: ["{caseId do novo caso}"] (append)
```

---

## Diagrama de estados

```text
                         ┌──────────┐
             ┌───────────│   open   │───────────┐
             │           └────┬─────┘           │
             │                │                 │
             ▼                ▼                 │
    ┌─────────────────┐  ┌─────────────────┐   │
    │under_investigation│  │under_treatment │   │
    └────────┬────────┘  └───────┬─────────┘   │
             │   ▲                │   ▲         │
             │   │                │   │         │
             │   └────────────────┘   │         │
             │                        │         │
             ▼                        ▼         │
             ┌──────────────────────────┐       │
             │       monitoring         │       │
             └────────────┬─────────────┘       │
                          │                     │
                          ▼                     ▼
                     ┌──────────┐        ┌───────────┐
                     │discharged│        │ cancelled │
                     └────┬─────┘        └───────────┘
                          │                (terminal)
                          │
           ┌──────────────┼──────────────────┐
           │  REABERTURA  │  (ação, não      │
           │  (com reason │   estado)        │
           │   + autor)   │                  │
           ▼              ▼                  ▼
     ┌──────────┐  ┌─────────────────┐  ┌─────────────────┐
     │   open   │  │under_investigation│  │under_treatment │
     └──────────┘  └─────────────────┘  └─────────────────┘
                         ou monitoring

   Condições para reabertura:
   - Origem: SOMENTE discharged
   - Destino: open | under_investigation | under_treatment | monitoring
   - Requer: reopen_reason + reopened_by + capability autorizada
   - Registra: ClinicalEvent tipo "reopen" (imutável)

   Recorrência (NÃO é reabertura):
   ┌──────────┐                    ┌──────────────────┐
   │discharged│ ─── novo caso ───→ │ ClinicalCase     │
   │(caso A)  │                    │ (caso B)         │
   └──────────┘                    │ recurrence_of:A  │
                                   └──────────────────┘
```

---

## Separação de status

| Dimensão | Fonte | Exemplos | Onde vive |
|----------|-------|----------|-----------|
| **Status clínico** | `clinical_status` do caso | open, under_treatment, discharged | `clinical_cases/{caseId}.clinical_status` |
| **Status operacional** | OperationalRestriction ativa | operational, fit_with_restrictions, temporarily_unfit | `operational_restrictions/{id}` → `health_summary/current` |
| **Status de agenda** | HealthScheduleItems pendentes | próxima dose em 2h, exame agendado para amanhã | `health_schedule/{id}` |

Essas três dimensões são **independentes**: um caso pode estar `under_treatment` (clínico), o K9 estar `operational_attention` (operacional), e haver uma dose pendente para hoje (agenda). Nenhuma dimensão governa as outras diretamente.

---

## Eventos legados — Política definitiva

| Origem | Destino | Justificativa |
|--------|---------|---------------|
| **Todos os `health_events` anteriores ao go-live** (qualquer tipo, com ou sem agrupamento lógico detectável) | `dogs/{dogId}/legacy_health_records/{recordId}` | **Contrato conservador único.** Nenhum `ClinicalEvent` retroativo é criado. Nenhum caso retroativo é criado. Operações administrativas futuras podem vincular `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando clinicamente justificado. |
| Novos registros clínicos (pós go-live) | SEMPRE dentro de um ClinicalCase real | Regra absoluta: não existe `case_id: null` para ClinicalEvents novos |

**Regra:** A partir do go-live do Health v1.0, todo ClinicalEvent OBRIGATORIAMENTE pertence a um ClinicalCase. Se o condutor registra uma intercorrência isolada, o sistema cria um caso clínico automaticamente (ou oferece vincular a caso existente). `health_events` pré-go-live **não** viram ClinicalEvent retroativo.
