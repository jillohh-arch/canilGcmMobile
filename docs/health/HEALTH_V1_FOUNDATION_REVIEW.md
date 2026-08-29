# Health v1.0 — Foundation Review

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | Todos os ADRs e documentos desta fase |
| Escopo | Resumo consolidado das decisões, riscos, questões abertas e próximos passos |
| Fora de escopo | Implementação |

> **Estado: Fase 1A aprovada para registro documental.** Esta revisão consolida as decisões humanas H1-H28 e Q1-Q9. O1-O4 permanecem como gates futuros e não bloqueiam esta aprovação.

---

## 1. Decisões humanas já tomadas

Estas decisões foram definidas pela revisão humana das Fases 1A e são a base do contrato.

| # | Decisão humana | ADR / Doc | Implicação |
|---|----------------|-----------|------------|
| H1 | HealthScheduleItem é agregado canônico, não projeção | ADR-001, ADR-004 | Apenas timeline e summary são projeções |
| H2 | Veterinário externo NÃO tem conta no K9 Ops | Permission Matrix, Domain Model | Sem custom claim `role: vet`; profissional identificado no registro; executor interno transcreve |
| H3 | ExamProcess é agregado próprio (subcoleção) com estado persistido | ADR-001, ADR-002, Domain Model | Exames não são apenas eventos tipados |
| H4 | Reabertura é ação, não estado durável | ADR-003, Domain Model | `reopened` removido do enum; recorrência vira novo caso com `recurrence_of_case_id` |
| H5 | **Todos os `health_events` anteriores ao go-live vão para `dogs/{dogId}/legacy_health_records/{recordId}`** (contrato conservador único). Nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/events`. Operações administrativas futuras podem vincular `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando clinicamente justificado. | ADR-003, ADR-006, Domain Model | Não se inventa caso retroativo; não há classificação dual por "caso atribuível" |
| H6 | Prontidão: summary para display, validação canônica para autorização crítica | ADR-005, Readiness Policy | Backend re-valida restrições no início/troca de turno |
| H7 | Ordem de precedência corrigida: `not_evaluated` antes de `operational_attention` por dados incompletos | ADR-005, Readiness Policy | K9 recém-cadastrado não cai em attention prematuramente |
| H8 | Status `final` permanece; amendments são metadados | ADR-002, Domain Model | Sem transição `final→amended`; `has_amendments`, `amendment_count`, `last_amended_at` |
| H9 | TreatmentProtocol tem dose/schedule estruturados | Domain Model, Schema | `dosage_display`/`frequency_display` ficam apenas para apresentação |
| H10 | DoseAdministration tem idempotência via `doseId` determinístico | Domain Model, Schema, Test Strategy | `doseId = hash(protocolId + planned_dose_id)`; `idempotency_key` apenas para rastreabilidade |
| H11 | Anexos: evento tem refs; HealthDocument é canônico | Domain Model, Schema | `attachment_refs` em evento; `storage_path` no documento; URL é derivada |
| H12 | Event payloads são tipados e versionados | Domain Model, Schema | `payload_type`, `payload_version` por evento |
| H13 | Soft delete e auditoria padronizados | Domain Model, Schema | `deleted_at`, `deleted_by`, `delete_reason` em todas as entidades aplicáveis |
| H14 | Migração: controle em `_migrations/health_v1/batches/{batchId}`; manifest distingue `create` e `update`, com `before_image` e `changed_fields` | ADR-006, Migration Plan, Schema | Rollback de create apaga somente documento criado; rollback de update restaura campos anteriores; proibido após uso por usuário ou cutover |
| H15 | Cutover é por agregado, coordenado entre Mobile/Web/Functions/Rules/índices | ADR-006, Migration Plan | Não bloquear writes legados se qualquer produtor ainda grava |
| H16 | Permission Matrix reescrita sem papel vet; baseada em capabilities internas | Permission Matrix | `hasCapability('health.xxx')` em Rules. **Quatro capabilities adicionadas na Rodada 4** (`health.reopen_case`, `health.cancel_case`, `health.complete_treatment`, `health.manage_schedule`) estão catalogadas. O mapeamento capability → perfil real (`condutor`/`admin`) permanece **provisório**, pendente da Fase 1B (O1). A Permission Matrix só pode ser declarada reconciliada e final após esse inventário. |
| H17 | Service accounts/Admin SDK IGNORAM Firestore Rules | Test Strategy, Permission Matrix | Rules bloqueiam clientes; Functions usam Admin SDK (sem validação por Rules) |
| H18 | `clinical_status` muda por ações explícitas server-orchestrated | ADR-003 | Sem inferência genérica a partir de eventos; sem override manual arbitrário |
| H19 | Rascunhos: alerta após 48h; nunca cancelados automaticamente; retomada livre | ADR-003 | |
| H20 | Cancelamento de evento final exige `health.cancel_record` + justificativa; conteúdo preservado | ADR-003, Domain Model | |
| H21 | Estados temporais do HealthScheduleItem SOMENTE derivados na leitura | ADR-004, Domain Model | Nenhuma Function reescreve schedule por passagem de tempo |
| H22 | `due_until` é opcional; tolerância definida por `schedule_type`/configuração | Domain Model, Schema | Sem default universal de 24h |
| H23 | Busca textual fora do v1 | ADR-004, Schema | `searchable_text` removido |
| H24 | Coleções duplicadas legadas preservadas read-only durante todo o v1 | ADR-006 | Arquivamento futuro exige decisão separada |
| H25 | VaccinationRecord é o 13º agregado canônico em `dogs/{dogId}/vaccination_records/{vaccinationId}`. **Estados persistidos: apenas `record_status: final \| cancelled`** (não há `scheduled`/`overdue` em `VaccinationRecord` — planejamento, "próximo", "hoje", "pendente" e "atrasado" vivem exclusivamente em `HealthScheduleItem`). `case_id` é opcional, preenchido **somente quando há vínculo clínico real e documentado** (reação adversa ou vínculo terapêutico); **não** cria ClinicalCase; gera HealthTimeline e HealthScheduleItem para próxima dose. | ADR-001, ADR-006, Domain Model, Schema, ADR-004, Readiness Policy | Pronto para implementação |
| H26 | Política offline consolidada: display refresh >5min; offline degraded ≤12h; >12h exige aceite auditado; `temporarily_unfit` conhecido bloqueia; aceite não é override | ADR-005, Readiness Policy | O ADR-005 removeu qualquer referência a "24h" como contrato |
| H27 | Quatro capabilities adicionadas: `health.reopen_case`, `health.cancel_case`, `health.complete_treatment`, `health.manage_schedule` | Permission Matrix | Mapeamento capability→perfil marcado como provisório, pendente da Fase 1B |
| H28 | Idempotência de dose: contrato único `doseId = hash(protocolId + planned_dose_id)`; `idempotency_key` é rastreabilidade, não garantia | Domain Model, Schema, Test Strategy | Firestore não oferece `unique` em índice; garantia vem de ID determinístico ou create transacional |

---

## 2. Decisões Q1–Q9 (rodada de revisão humana)

| # | Decisão | Origem |
|---|---------|--------|
| Q1 | **VaccinationRecord**: aprovado como agregado preventivo independente em `dogs/{dogId}/vaccination_records/{vaccinationId}`; pode referenciar `case_id` opcionalmente; gera timeline e agenda; NÃO cria ClinicalCase automaticamente | Decisão humana |
| Q2 | **Thresholds 90/180 dias**: configuráveis (não constantes arquiteturais); aparecem apenas como defaults propostos | Decisão humana |
| Q3 | **Operação offline**: restrição absoluta conhecida BLOQUEIA; incerteza permite modo degradado APENAS com aceite auditado do responsável; aceite NÃO é override clínico | Decisão humana |
| Q4 | **Idade do snapshot**: online/display atualiza quando >5 min; autorização online consulta restrições canônicas; offline usa 12h como default configurável; acima disso, aceite operacional obrigatório; `temporarily_unfit` conhecido bloqueia | Decisão humana |
| Q5 | **Capabilities → perfis reais**: adiado para Fase 1B; requer inventário do modelo de perfis atual | Aberto |
| Q6 | **Coleções duplicadas legadas**: preservadas read-only durante todo o v1; arquivamento futuro exige decisão de governança separada | Decisão humana |
| Q7 | **`searchable_text`**: removido do v1 | Decisão humana |
| Q8 | **Arquitetura interna (ADR-007)**: feature-first compatível com app; organização seletiva; interfaces onde resolvem problema concreto; SEM Clean Architecture global | Aberto (ADR-007) |
| Q9 | **`due_until`**: opcional; tolerância sem `due_until` definida por `schedule_type`/configuração; sem default universal | Decisão humana |

---

## 3. Recomendações técnicas adotadas

| # | Recomendação | ADR | Status |
|---|--------------|-----|--------|
| T1 | Modelo de agregados híbrido: rotina flat + clínica hierárquica + exames como subcoleção | ADR-001 | Adotada |
| T2 | Imutabilidade clínica por camadas: payload imutável, metadados server-managed | ADR-002 | Adotada |
| T3 | Caso clínico: estado clínico principal + flags derivadas (transições explícitas, sem inferência genérica) | ADR-003 | Adotada |
| T4 | Timeline como projeção server-side + inserção otimista local temporária (sem reconstrução no cliente) | ADR-004 | Adotada |
| T5 | Prontidão como projeção server-side (display) + validação canônica (autorização) | ADR-005 | Adotada |
| T6 | Migração aditiva com adapters read-only e backfill server-side progressivo | ADR-006 | Adotada |

---

## 4. Questões realmente restantes

Esta lista é provisória até a busca cruzada final. Conforme definido nesta rodada, as únicas questões **verdadeiramente em aberto** são:

| # | Questão | Origem | Decisão pendente |
|---|---------|--------|------------------|
| O1 | Mapeamento de capabilities internas → perfis reais | Q5 | Requer inventário do modelo de perfis (Fase 1B) |
| O2 | ADR-007 de arquitetura interna do Health | Q8 | Requer ADR próprio (Fase 1B) |
| O3 | Custo/SLA final das projeções (Functions e reconciliação) | T4, T5 | Validar antes da implementação (emulador) |
| O4 | Inventário real de produção (Fase 0 do Migration Plan) | T6 | Bloqueador para início da migração |

### 4.1 Subquestões agrupadas sob O3 e O4

Estas subquestões aparecem em ADRs como "Questões abertas" mas pertencem ao guarda-chuva de O3/O4 — não são decisões pendentes separadas. Podem evoluir sem reabrir esta revisão.

**Subquestões de O3** (projeções, SLA, reconciliação):

- Granularidade da timeline (item aparece individualmente vs. agrupado).
- SLA da projeção (alvo: ~10s; janela de aceitação: até 30s com `sync_pending`).
- Frequência da reconciliação automática (proposta: diária).
- Limite de itens na projeção (proposta: manter tudo; paginação por cursor).

**Subquestões de O4** (inventário, storage legado, dual-read, dual-write temporário):

- Inventário de `health_logs` raiz (real ou vazio).
- Inventário de `dogs/{dogId}/documents`.
- Paths antigos em Storage (manter URLs legadas; não mover arquivos).
- Dual-write server-side transitório (proposta: avaliar em Fase 3 para agregados selecionados).
- Período de dual-read (proposta: mínimo 30 dias, máximo 90 dias, pós-paridade).

### 4.2 Parâmetros configuráveis não bloqueadores

Estes thresholds são **parâmetros configuráveis** que evoluem sem reabrir esta revisão:

| Parâmetro | Default proposto | Origem | Natureza |
|-----------|------------------|--------|----------|
| Janela "upcoming" no HealthScheduleItem | 7 dias | Domain Model §2.12 | Configurável por `schedule_type` |
| Limite de alerta de reavaliação após `expected_end` | 30 dias | ADR-005 §15 | Configurável |
| Idade máxima para "fresh snapshot" (display) | 5 minutos | Readiness Policy §12 | Configurável |
| Janela "degraded mode" offline | 12 horas | Readiness Policy §12 | Default configurável |
| Threshold de pesagem ausente | >90 dias | Readiness Policy §4 | Configurável |
| Threshold de consulta ausente | >180 dias | Readiness Policy §4 | Configurável |
| Idade mínima para considerar caso estagnado | >30 dias sem evento | ADR-003 §15 | Configurável |

> **Esta Rodada 4 NÃO declara cobertura completa.** Cobertura efetiva só pode ser confirmada após a busca cruzada final dos 13 documentos e a validação de que nenhum termo proibido permanece como contrato atual.

---

## 5. Riscos identificados

### P0 — Bloqueadores

| # | Risco | Mitigação |
|---|-------|-----------|
| 1 | Validação canônica de restrições no início de turno falhar offline → K9 com restrição absoluta escala | Política fail-closed para restrições conhecidas; verificação local das últimas restrições baixadas; reconcile on reconnect |
| 2 | Function de projeção de timeline falha silenciosamente → timeline desatualizada | Reconciliação periódica + alerting; inserção otimista local com timeout 30s; indicador sync_pending |
| 3 | Rollback destrutivo remove documentos usados por usuários | Manifest por batch; rollback proibido após qualquer update por usuário |

### P1 — Altos

| # | Risco | Mitigação |
|---|-------|-----------|
| 4 | Permissões por capability divergem entre Mobile e Web na fase de transição | Capability mapping explícito por canal; testes cruzados antes do cutover |
| 5 | Complexidade de Rules para estados de ClinicalCase | Testes exaustivos + emulador antes de deploy |
| 6 | Período de dual-read muito longo acumula debt | Feature flag com deadline; cutover por agregado |
| 7 | States temporais derivados podem divergir entre clientes com relógios diferentes | Timezone armazenado no item; cliente usa `timezone` para cálculo; aceitável pequena diferença entre clientes |

### P2 — Médios

| # | Risco | Mitigação |
|---|-------|-----------|
| 8 | ExamProcess + ClinicalEvent sincronizados em duplicação | Cada transição de ExamProcess gera evento dentro da mesma transação |
| 9 | legacy_health_records cresce sem governança | Inventory na Fase 0; relatório de cobertura |
| 10 | UX de adendos confunde condutor | Design review antes da Fase 2 do roadmap |

---

## 6. Itens explicitamente adiados para Health v2+

| Item | Razão do adiamento |
|------|-------------------|
| IPO (Índice de Prontidão Operacional) | Requer dados de treinamento + saúde + condicionamento integrados |
| Conta de veterinário externo com login próprio | Decisão de negócio; integração direta fica para v2 |
| Integração direta com clínicas (API, OCR de exames) | Requer padrão de interoperabilidade |
| Fisioterapia / Internação / Cirurgia (workflows) | Extensões do domínio clínico |
| Busca textual na timeline | Mecanismo de indexação dedicado |
| Histórico de snapshots de prontidão | Baixa prioridade para v1.0 |
| Notificações push de Saúde | Após agenda funcional |
| Score numérico de prontidão | Substituído pelos 5 estados categóricos em v1.0 |
| Override manual de prontidão | Complexidade prematura; regras + encerramento de restrição já cobrem cenários |

---

## 7. Mudanças em relação à rodada anterior

Esta seção descreve deltas introduzidos **nesta Rodada 4** em relação à Rodada 3.

| Aspecto | Rodada 3 | Rodada 4 | Origem |
|---------|----------|----------|--------|
| `OperationalRestriction` (ADR-005) | `issued_by/professional {name,crmv}/ended_by/end_professional/audit_trail inline` | `recorded_by` + `ProfessionalIdentity` + `source_document` + `end_source_document`; auditoria server-side | Reconciliação |
| Bloqueio por restrição absoluta | "K9 não pode iniciar turno (ou warning forte)" | Bloqueio obrigatório; restrição absoluta ativa sempre bloqueia, sem bypass | Reconciliação |
| Vigência de restrição | "Restrição expirada não afeta snapshot" | `expected_end` vencido **não** encerra automaticamente; enquanto `status==active` a restrição continua afetando prontidão; apenas aciona `is_overdue`/alerta de reavaliação | Reconciliação |
| Precedência temporal do HealthScheduleItem | `due_until` ausente podia classificar simultaneamente como `pending` e `overdue` | Regra única com `effective_due_until = due_until ?? resolveTolerance(...)`; precedência absoluta; sem contradição | Reconciliação |
| Eventos legados (ADR-002, ADR-006, ADR-003) | `health_events` com caso → `clinical_cases/events`; todos como `final` | **Contrato conservador único:** todos `health_events` pré-go-live → `legacy_health_records`; nenhum `ClinicalCase` retroativo | Reconciliação |
| `legacy_health_records` | "nenhum write após o backfill" (absoluto) | `original_payload` imutável; clientes read-only; Admin SDK auditado pode atualizar `normalized_view`, `case_id`, metadados | Reconciliação |
| Idempotência de dose (Test Strategy §1.5, §1.12) | "via `idempotency_key` ou `planned_dose_id`" | `doseId = hash(protocolId + planned_dose_id)` é o contrato; `idempotency_key` é apenas rastreabilidade | Reconciliação |
| Restrição (Test Strategy §1.12) | "Profissional cria restrição" | Usuário interno autorizado registra restrição emitida pelo profissional externo | Reconciliação |
| Cancelamento de evento final (Test Strategy §1.7) | "cancelamento por admin" | Cancelamento via `health.cancel_record` com justificativa | Reconciliação |
| Mapeamento capability→perfil | Definitivo na Rodada 3 | Marcado como provisório em todos os docs; pendente da Fase 1B | Reconciliação |
| Gate Fase 8 (Test Strategy) | `1.1–1.23` | `1.1–1.26` (incluindo 1.24 VaccinationRecord, 1.25 precedência temporal, 1.26 quatro capabilities novas) | Reconciliação |
| Rascunhos (ADR-002, ADR-003) | "alerta após 48h" + "72h" presente em algumas seções | Apenas 48h para alerta; nunca cancelar automaticamente; substituição de "UID de service account" por backend/Admin SDK | Reconciliação |
| Linguagem Admin SDK (ADR-002, ADR-003, ADR-006) | "UID de service account", "Function ou UID de service account" | "operação administrativa via backend/Admin SDK" | Reconciliação |
| `VaccinationRecord` (ADR-001) | Listado entre 13 agregados mas ausente da lista de "Novas coleções" e do diagrama de agregados independentes | Incluído em `Novas coleções`, no diagrama e no fluxo das projeções | Reconciliação |
| `VaccinationRecord.case_id` (ADR-001 vs Foundation) | Foundation: somente reação adversa; ADR-001: reação adversa ou vínculo terapêutico | Regra única: opcional quando existir vínculo clínico real e documentado | Reconciliação |
| ADR-001 § "Questões abertas" | Lista com decisões já encerradas | Renomeada para "Decisões encerradas" | Reconciliação |
| ADR-001 §14 (testes) | "testes por papel e estado" | "testes por capability e estado" | Reconciliação |

---

## 8. Compatibilidade com a arquitetura atual do app

A Fase 1A permanece **exclusivamente documental**. Nenhuma camada nova obrigatória foi introduzida. As decisões arquiteturais internas do Health (subcamadas, repository interfaces, padrão de serviço) permanecem como **questão aberta O2** a ser decidida em ADR-007 na Fase 1B.

Princípios preservados:
- Feature-first em `lib/features/health/` continua sendo o default
- Provider/ChangeNotifier continua sendo o padrão de estado
- Services acessando Firestore continuam sendo aceitos
- Novas abstrações exigem justificativa caso a caso (problema concreto + alternativa mais simples)

---

## 9. Confirmação de que nenhum código foi implementado

✅ Esta fase é **exclusivamente documental**. Nenhuma das seguintes alterações foi feita:
- ❌ Models Dart
- ❌ DTOs
- ❌ Repositories
- ❌ Services
- ❌ Providers / ViewModels
- ❌ Telas ou componentes
- ❌ Cloud Functions
- ❌ Firestore Rules
- ❌ Storage Rules
- ❌ Índices (deploy)
- ❌ Migrations / scripts de backfill
- ❌ Testes de código
- ❌ Deploy
- ❌ Alteração funcional em qualquer módulo (Training, Shifts, etc.)
- ❌ Alteração em `HEALTH_V1_BASELINE.md` (documento histórico da tag)

---

## 10. Matriz de consistência (atualizada pós-reconciliação)

Esta matriz registra a Fase 1A aprovada arquiteturalmente. O1-O4 permanecem como gates futuros nas fases correspondentes e não bloqueiam o commit documental.

| Requisito | ADR-001 | ADR-002 | ADR-003 | ADR-004 | ADR-005 | ADR-006 | Domain | Schema | Policy | Migration | Permissions | Tests |
|-----------|---------|---------|---------|---------|---------|---------|--------|--------|--------|-----------|-------------|-------|
| Schedule como agregado canônico | ✅ | — | — | ✅ | — | ✅ | ✅ | ✅ | — | ✅ | — | ✅ |
| Apenas timeline + summary são projeções | ✅ | — | — | ✅ | — | ✅ | ✅ | ✅ | — | — | — | — |
| Sem custom claim vet; profissional externo | ✅ | ✅ | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ExamProcess agregado próprio (caminho único) | ✅ | ✅ | — | — | — | ✅ | ✅ | ✅ | — | — | — | ✅ |
| ExamProcess 6 estados (sem sent_to_lab/reviewed) | ✅ | ✅ | — | — | — | ✅ | ✅ | ✅ | — | — | — | ✅ |
| Reabertura é ação; recorrência é novo caso | ✅ | — | ✅ | — | — | ✅ | ✅ | ✅ | — | — | — | — |
| `legacy_health_records` para todos os `health_events` pré-go-live | ✅ | — | ✅ | — | — | ✅ | ✅ | ✅ | — | ✅ | — | ✅ |
| Summary display + validação canônica turno | — | — | — | — | ✅ | — | — | — | ✅ | — | — | ✅ |
| Precedência corrigida (not_evaluated antes de attention) | — | — | — | — | ✅ | — | — | — | ✅ | — | — | — |
| Status final permanece; metadados amendment | — | ✅ | — | ✅ | — | — | ✅ | ✅ | — | — | — | ✅ |
| TreatmentProtocol com dose/schedule estruturados | — | — | — | — | — | — | ✅ | ✅ | — | — | — | ✅ |
| DoseId determinístico (sem índice unique) | — | — | — | — | — | — | ✅ | ✅ | — | — | — | ✅ |
| `attachment_refs` em evento; storage_path em doc | — | ✅ | — | — | — | — | ✅ | ✅ | — | — | — | — |
| Payloads versionados (payload_type/payload_version) | — | — | — | — | — | — | ✅ | ✅ | — | — | — | — |
| Soft delete padronizado | — | — | — | — | — | — | ✅ | ✅ | — | — | — | — |
| Migration control em `_migrations/.../batches/{id}` | — | — | — | — | — | ✅ | — | ✅ | — | ✅ | — | — |
| Cutover por agregado | — | — | — | — | — | ✅ | — | — | — | ✅ | — | ✅ |
| Permissions por capability (sem role vet) | — | ✅ | ✅ | — | — | — | — | — | — | — | ✅ | ✅ |
| Admin SDK ignora Rules; Functions usam Admin SDK | — | — | — | — | — | — | — | — | — | — | ✅ | ✅ |
| `clinical_status` server-orchestrated (sem inferência) | — | — | ✅ | — | — | — | ✅ | — | — | — | — | — |
| Rascunhos alerta 48h; nunca cancelados auto | — | — | ✅ | — | — | — | — | — | — | — | — | — |
| Cancelamento final exige capability + justificativa | — | — | ✅ | — | — | — | ✅ | — | — | — | ✅ | — |
| Estados temporais schedule SOMENTE derivados | — | — | — | ✅ | — | — | ✅ | — | — | — | — | ✅ |
| `due_until` opcional; sem default 24h | — | — | — | ✅ | — | — | ✅ | ✅ | — | — | — | ✅ |
| `searchable_text` removido do v1 | — | — | — | ✅ | — | — | — | ✅ | — | — | — | — |
| Coleções legadas duplicadas preservadas read-only | — | — | — | — | — | ✅ | — | — | — | ✅ | — | — |
| Offline: known unfit bloqueia; degraded exige aceite | — | — | — | — | ✅ | — | — | — | ✅ | — | — | ✅ |
| Snapshot online display > 5 min → refresh | — | — | — | — | ✅ | — | — | — | ✅ | — | — | — |

**Cobertura:** ainda em reconciliação pós-Rodada 4. A matriz será revisitada após a busca cruzada final dos 13 documentos (item 14 do prompt da Rodada 4). Nenhuma declaração de cobertura completa (28/28) deve ser feita antes disso.

---

## 11. Próximos passos sugeridos

| Ordem | Entregável | Dependências | Fase |
|-------|-----------|---------------|------|
| 1 | Aprovação e registro da Fase 1A com O1-O4 carregadas como gates futuros | Esta revisão | Fase 1A |
| 2 | ADR-007 de arquitetura interna (Q8/O2) | Esta revisão aprovada | Fase 1B |
| 3 | Mapeamento capabilities → perfis reais (O1) | Decisões de produto + inventário | Fase 1B |
| 4 | Domain entities + value objects + enums (Dart) | ADR-007 | Fase 1B |
| 5 | Adapters read-only para fontes legadas | Domain entities | Fase 2 |
| 6 | Inventário real (Fase 0 do Migration Plan) — O4 | Aprovação dos contratos | Fase 2 |
| 7 | Rules + índices em emulador | Schema aprovado | Fase 3 |
| 8 | Cloud Functions de projeção | Rules + schema + estimativa de custo (O3) | Fase 2 |
| 9 | Backfill dry-run | Funções + inventário | Fase 4 |
| 10 | Cutover por agregado | Paridade validada | Fase 6+ |
