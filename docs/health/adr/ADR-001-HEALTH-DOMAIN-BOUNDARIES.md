# ADR-001 — Limites do Domínio Health v1.0

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | HEALTH_V1_ARCHITECTURE.md, HEALTH_MODULE_AUDIT.md, HEALTH_V1_DOMAIN_MODEL.md |
| Escopo | Definição dos agregados, suas responsabilidades e fronteiras |
| Fora de escopo | Implementação Dart, Rules, Functions, IPO, IA |

---

## 1. Contexto

O módulo Saúde atual distribui responsabilidades clínicas entre features desconectadas (health, nutrition, dogs, history, profiles) sem uma fronteira arquitetural única. O Health v1.0 propõe unificar tudo sob um Centro de Prontidão Operacional K9, onde cada agregado tem papel claro, fonte canônica definida e responsabilidade separada entre Mobile e Web.

---

## 2. Problema

Quais são os agregados do domínio Health v1.0, onde começa e termina a responsabilidade de cada um, e como se relacionam entre si, com a timeline, com a agenda e com a prontidão operacional?

---

## 3. Requisitos obrigatórios

1. Todo registro clínico deve pertencer a exatamente um agregado.
2. Cada agregado deve ter uma fonte canônica única (não duplicada).
3. A separação Web define / Mobile executa deve ser clara por agregado.
4. Projeções (timeline, summary) não são agregados — são derivações.
5. Caso Clínico conecta eventos quando aplicável, mas não é obrigatório para registros rotineiros.
6. Nenhum agregado pode depender circularmente de outro.
7. Restrições clínicas devem ser modeladas como agregado próprio, não campo de outro.
8. HealthScheduleItem é agregado canônico (fonte de verdade da agenda), não projeção.
9. ExamProcess é agregado próprio com ciclo de vida independente dentro do caso.
10. Todos os `health_events` anteriores ao go-live têm destino definido (`legacy_health_records`), independentemente de agrupamento lógico detectável.

---

## 4. Opções consideradas

### Opção A — Agregados planos (flat)

Todos os registros vivem como subcoleções diretas de `dogs/{dogId}`, sem hierarquia entre eles. Caso Clínico é apenas um campo `case_id` opcional.

### Opção B — Caso Clínico como agregado-raiz

Caso Clínico é o agregado principal e todos os eventos clínicos são subcoleções dele. Registros rotineiros (peso, refeição) ficam fora.

### Opção C — Modelo híbrido por natureza

Agregados de rotina (peso, nutrição) são independentes. Agregados clínicos (consulta, exame, tratamento) vivem dentro do Caso Clínico. Agenda é agregado canônico. Timeline e summary são projeções.

---

## 5. Comparação das opções

| Critério | A (flat) | B (case-root) | C (híbrido) |
|----------|----------|---------------|-------------|
| Simplicidade de queries | Alta | Baixa (precisa coleção-raiz para rotina) | Média |
| Rastreabilidade clínica | Baixa (case_id solto) | Alta | Alta |
| Custo de migração | Baixo | Alto (reorganizar tudo) | Médio |
| Independência de rotina | Alta | Parcial | Alta |
| Suporte offline | Alta | Complexa (hierarquia profunda) | Média-Alta |
| Consulta por caso | Requer collection group | Nativa | Nativa para clínicos |
| Escalabilidade | Alta | Limitada por documento-raiz | Alta |

---

## 6. Recomendação

**Opção C — Modelo híbrido por natureza.**

Registros de rotina (peso, refeição, suplemento) são agregados independentes sob `dogs/{dogId}`. Registros clínicos estruturados (eventos do caso) vivem como subcoleção de `clinical_cases/{caseId}`. ExamProcess é subcoleção própria do caso com ciclo de vida independente. Protocolos de tratamento são agregados próprios com referência ao caso. HealthScheduleItem é agregado canônico (não projeção). Projeções derivadas são apenas HealthTimeline e ReadinessSnapshot.

---

## 7. Consequências positivas

- Rotina não precisa de caso clínico para existir.
- Caso clínico agrupa naturalmente o ciclo intercorrência → alta.
- ExamProcess como subcoleção própria permite ciclo de vida independente (solicitação → coleta → resultado → impacto).
- HealthScheduleItem como agregado canônico permite criação direta por Mobile/Web sem depender de Function.
- Queries de rotina permanecem simples e paginadas.
- Projeções podem ser reconstruídas sem perda de dados canônicos.
- Cada agregado pode ter suas próprias regras de imutabilidade.
- Todos os `health_events` anteriores ao go-live têm destino claro (`legacy_health_records`), independentemente de agrupamento lógico detectável.

---

## 8. Consequências negativas

- Dois padrões de organização (flat para rotina, hierárquico para clínica).
- Timeline precisa compor dados de múltiplas fontes.
- Migração deve decidir item a item se é rotina ou clínico.
- ExamProcess como subcoleção adiciona um nível de hierarquia dentro do caso.
- HealthScheduleItem canônico exige disciplina de criação (Mobile/Web/Function podem escrever).

---

## 9. Compatibilidade com o legado

- **Contrato conservador único:** todos os `health_events` anteriores ao go-live vão para `dogs/{dogId}/legacy_health_records/{recordId}` como read-only para clientes. **Não** há migração para "agregado correspondente" em `clinical_cases/events` — nenhum `ClinicalEvent` retroativo é criado a partir de `health_events`.
- Todos os `health_events` anteriores ao go-live são migrados para `dogs/{dogId}/legacy_health_records/{recordId}`, independentemente de agrupamento lógico detectável; a coleção é read-only para clientes.
- `weight_records`, `feeding_events`, `nutritional_prescriptions` já são agregados flat e permanecem.
- `vacinas` raiz será lida via adapter até cutover.
- Nenhum `health_event` anterior ao go-live é promovido automaticamente para `clinical_cases`.

---

## 10. Impacto em Mobile

- Mobile lê e escreve registros de rotina diretamente.
- Mobile cria intercorrências que podem abrir casos clínicos.
- Mobile lê casos clínicos e seus eventos.
- Mobile administra doses de protocolos.
- Mobile cria e lê HealthScheduleItems (agenda).
- Mobile pode registrar VaccinationRecord (vacinação aplicada em campo).
- Mobile NÃO cria planos alimentares nem protocolos de tratamento (Web).

---

## 11. Impacto em Web

- Web cria e gerencia planos alimentares.
- Web cria protocolos de tratamento (transcrição de prescrição externa com evidence profissional obrigatória).
- Web pode abrir casos clínicos por consulta programada (com identification do profissional externo).
- Web cria ExamProcess (solicitação de exame).
- Web cria e gerencia HealthScheduleItems.
- Web pode emitir e encerrar restrições mediante transcrição de decisão clínica externa.
- Web tem visão administrativa completa.

---

## 12. Impacto em Firestore

- Novas coleções: `clinical_cases`, `clinical_cases/{caseId}/events`, `clinical_cases/{caseId}/exams`, `treatment_protocols`, `vaccination_records`, `health_schedule`, `health_timeline`, `health_summary`, `health_documents`, `operational_restrictions`, `legacy_health_records`.
- Coleções existentes preservadas: `weight_records`, `feeding_events`, `nutrition_supplements`.
- Coleções a migrar/aposentar: `health_events`, `weight_history`, `feedings`, `nutrition_prescriptions` (legada), `vacinas`, `health_logs`.

---

## 13. Impacto em segurança

- Cada agregado terá regras específicas por capability interna (`health.xxx`) — **nunca** por papel externo.
- A separação é: usuário interno autenticado com capability + (quando aplicável) `ProfessionalIdentity` do profissional externo + evidência documental.
- Imutabilidade por estado deve ser enforced em Rules, não apenas no código.
- Projeções devem ser writable apenas pelo backend.
- HealthScheduleItem (canônico) tem regras de escrita por capability interna (qualquer capability `health.schedule_item`, `health.manage_schedule` etc.). Decisões clínicas relacionadas a itens de agenda são registradas pelo usuário interno com identificação do profissional externo em `professional` e `source_document`.
- legacy_health_records é read-only para clientes; Admin SDK auditado pode atualizar `normalized_view`, `case_id` e metadados de reconciliação.

---

## 14. Impacto em testes

- Testes de domínio por agregado isolado.
- Testes de transição entre estados de cada agregado.
- Testes de integração entre caso clínico e seus eventos/exams.
- Testes de Rules por capability e estado (não por papel).
- Testes de migração para legacy_health_records.

---

## 15. Decisões encerradas (não mais questões abertas)

As decisões abaixo foram encerradas e refletidas nos contratos deste ADR e do Domain Model.

1. **VaccinationRecord:** resolvido nesta rodada como agregado canônico independente em `dogs/{dogId}/vaccination_records/{vaccinationId}`. Não é mais questão aberta — ver §"Definição dos agregados" e Domain Model §7.
2. **Documentos (laudos, receitas)** são agregado próprio com referências opcionais — decidido.
3. **Observação diária** é campo opcional em registros de rotina, não agregado separado — decidido.
4. **13 agregados canônicos e 2 projeções** — definidos e sem sobreposição.
5. **`legacy_health_records`** é read-only para clientes; Admin SDK auditado pode atualizar `normalized_view`, `case_id` e metadados de reconciliação — política consolidada.
6. **`VaccinationRecord.case_id`** é opcional, preenchido **somente** quando há vínculo clínico real e documentado (reação adversa ou vínculo terapêutico). Vacinação registrada **não** cria ClinicalCase.

---

## 16. Critérios para aprovação

- [ ] Todos os 13 agregados canônicos listados têm responsabilidade clara e sem sobreposição.
- [ ] As 2 projeções estão claramente separadas de fontes canônicas.
- [ ] A separação é por capability interna; não há papel `vet`.
- [ ] A relação entre caso clínico e registros de rotina está inequívoca.
- [ ] ExamProcess como subcoleção própria do caso está justificada.
- [ ] HealthScheduleItem como agregado canônico (não projeção) está justificada, com estados temporais somente derivados.
- [ ] VaccinationRecord como agregado canônico independente está justificado.
- [ ] Destino de todos os `health_events` anteriores ao go-live (`legacy_health_records`) está definido, independentemente de agrupamento lógico detectável.
- [ ] Nenhum agregado depende circularmente de outro.

---

## Definição dos agregados

### Agregados canônicos (13 — dados autoritativos)

| # | Agregado | Responsabilidade | Fonte canônica | Pode existir sem caso? | Gerenciado por |
|---|----------|-----------------|----------------|----------------------|----------------|
| 1 | **ClinicalCase** | Agrupa um ciclo clínico completo (abertura → alta) | `dogs/{dogId}/clinical_cases/{caseId}` | N/A (é o caso) | Usuário interno com capability; profissional externo identificado em `ProfessionalIdentity` |
| 2 | **ClinicalEvent** | Registro imutável de acontecimento clínico vinculado a caso | `dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}` | Não | Usuário interno com capability; profissional externo identificado quando aplicável |
| 3 | **ExamProcess** | Ciclo completo de exame (solicitação → coleta → resultado → impacto clínico) | `dogs/{dogId}/clinical_cases/{caseId}/exams/{examId}` | Não (pertence a caso) | Usuário interno com capability; profissional externo identificado em cada etapa |
| 4 | **TreatmentProtocol** | Protocolo de medicação/terapia com cronograma | `dogs/{dogId}/treatment_protocols/{protocolId}` | Não (referencia caso) | Web cria com evidence profissional obrigatória |
| 5 | **DoseAdministration** | Registro de administração individual de dose | `dogs/{dogId}/treatment_protocols/{protocolId}/doses/{doseId}` | Não (pertence a protocolo) | Mobile executa |
| 6 | **WeightAssessment** | Pesagem com escore corporal e medidas | `dogs/{dogId}/weight_records/{id}` | Sim | Mobile |
| 7 | **NutritionPlan** | Plano alimentar vigente com quantidades e frequência | `dogs/{dogId}/nutrition_plans/{id}` | Sim | Web define |
| 8 | **MealLog** | Registro de refeição executada | `dogs/{dogId}/meal_logs/{id}` | Sim | Mobile executa |
| 9 | **SupplementLog** | Registro de suplementação | `dogs/{dogId}/supplement_logs/{id}` | Sim | Mobile executa |
| 10 | **HealthDocument** | Arquivo clínico (laudo, receita, imagem, atestado) | `dogs/{dogId}/health_documents/{id}` | Sim (mas pode referenciar caso/evento) | Mobile/Web |
| 11 | **OperationalRestriction** | Restrição clínica ativa que afeta prontidão | `dogs/{dogId}/operational_restrictions/{id}` | Sim (pode existir por avaliação preventiva) | Usuário interno com capability; profissional externo identificado em `ProfessionalIdentity` |
| 12 | **HealthScheduleItem** | Item canônico de agenda (doses, consultas, vacinas, pesagens, retornos) | `dogs/{dogId}/health_schedule/{id}` | Sim | Mobile/Web cria; Function também pode criar |
| 13 | **VaccinationRecord** | Registro canônico de vacinação preventiva com calendário próprio | `dogs/{dogId}/vaccination_records/{vaccinationId}` | Sim | Mobile/Web cria com evidence profissional quando externa; Function cria próxima dose |

### Destino de migração legada

| # | Coleção | Responsabilidade | Caminho | Características |
|---|---------|-----------------|---------|-----------------|
| — | **legacy_health_records** | Todos os `health_events` anteriores ao go-live, independentemente de agrupamento lógico detectável; também dados incompletos de vacinas | `dogs/{dogId}/legacy_health_records/{recordId}` | Read-only para clientes; Admin SDK auditado pode atualizar `normalized_view`, `case_id` e metadados de reconciliação; `original_payload` imutável |

### Projeções (2 — dados derivados, não autoritativos)

| # | Projeção | Responsabilidade | Caminho | Gerado por |
|---|----------|-----------------|---------|-----------|
| 1 | **HealthTimeline** | Projeção paginável de todos os eventos para exibição | `dogs/{dogId}/health_timeline/{id}` | Backend (Function/trigger) |
| 2 | **ReadinessSnapshot** | Estado atual de prontidão operacional do K9 | `dogs/{dogId}/health_summary/current` | Backend (Function/trigger) |

### VaccinationRecord (incluído como agregado canônico)

| # | Agregado | Responsabilidade | Caminho | Justificativa |
|---|----------|-----------------|---------|---------------|
| 13 | **VaccinationRecord** | Registro canônico de vacinação preventiva com calendário próprio | `dogs/{dogId}/vaccination_records/{vaccinationId}` | Vacinação é rotina preventiva com calendário próprio; não depende de caso clínico. Vinculável opcionalmente a um caso via `case_id` quando há reação adversa ou vínculo terapêutico. **Não** cria ClinicalCase. Gera entrada na HealthTimeline e item em HealthScheduleItem para próxima dose. |

---

### Diagrama de relacionamento

```text
                    ┌─────────────────────────┐
                    │      ClinicalCase       │
                    │  (ciclo clínico)        │
                    └──────┬──────────┬───────┘
                           │          │
                   contém 1..N    contém 0..N
                           │          │
              ┌────────────▼───┐  ┌───▼──────────────┐
              │ ClinicalEvent  │  │   ExamProcess    │
              │ (consulta,     │  │ (solicitação →   │
              │  intercorrên-  │  │  coleta →        │
              │  cia, alta)    │  │  resultado →     │
              └────────┬───────┘  │  impacto)        │
                       │          └──────────────────┘
                       │ pode referenciar
          ┌────────────┼────────────────┐
          ▼            ▼                ▼
TreatmentProtocol  HealthDocument  OperationalRestriction
       │
       │ contém 1..N
       ▼
DoseAdministration


   Agregados independentes (rotina + agenda):
   ┌──────────────┐  ┌──────────┐  ┌───────────────┐  ┌──────────────┐
   │WeightAssess- │  │ MealLog  │  │SupplementLog  │  │NutritionPlan │
   │    ment      │  │          │  │               │  │  (Web)       │
   └──────────────┘  └──────────┘  └───────────────┘  └──────────────┘

   ┌────────────────────┐
   │HealthScheduleItem  │ ← AGREGADO CANONICO (não projeção)
   │  (agenda de saúde) │
   └────────────────────┘

   ┌────────────────────┐
   │VaccinationRecord   │ ← 13º AGREGADO CANÔNICO (preventivo independente)
   │  (vacinação        │    gera entrada na HealthTimeline e item em
   │   preventiva)      │    HealthScheduleItem para próxima dose
   └────────────────────┘

   Destino legado (read-only para clientes; Admin SDK auditado):
   ┌────────────────────────┐
   │ legacy_health_records  │ ← todos os health_events pré-go-live
   └────────────────────────┘

   Todos alimentam projeções:
              ┌──────────────────────────────────────┐
              │  HealthTimeline · ReadinessSnapshot   │
              │         (projeções derivadas)         │
              └──────────────────────────────────────┘
```

### Regras de pertencimento

1. **Rotina sem caso:** WeightAssessment, MealLog, SupplementLog, NutritionPlan e HealthDocument podem existir sem ClinicalCase.
2. **Clínico com caso:** ClinicalEvent sempre pertence a um ClinicalCase. ExamProcess sempre pertence a um ClinicalCase. TreatmentProtocol sempre referencia um ClinicalCase.
3. **ExamProcess é agregado próprio:** vive como subcoleção do caso (`clinical_cases/{caseId}/exams/{examId}`), com ciclo de vida independente dos eventos. ClinicalEvents podem referenciar um ExamProcess via `exam_id`.
4. **Restrição flexível:** OperationalRestriction pode ser emitida dentro de um caso ou por avaliação preventiva sem caso.
5. **Vinculação opcional:** WeightAssessment e HealthDocument podem opcionalmente referenciar um ClinicalCase via campo `case_id`.
6. **Agenda é canônica:** HealthScheduleItem é agregado canônico com dados autoritativos. Pode ser criado por Mobile, Web ou Function. Não é projeção.
7. **Projeções não são editáveis pelo cliente:** HealthTimeline e ReadinessSnapshot são escritos exclusivamente por Cloud Functions.
8. **Legado é read-only para clientes:** `legacy_health_records` recebe todos os `health_events` anteriores ao go-live, independentemente de agrupamento lógico detectável. `original_payload` é imutável; Admin SDK auditado pode atualizar campos administrativos limitados.
