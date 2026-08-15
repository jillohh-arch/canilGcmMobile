# Health v1.0 — Matriz de Permissões

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-002, ADR-005, HEALTH_V1_DOMAIN_MODEL.md |
| Escopo | Capacidades internas, papéis existentes, separação executor/profissional, matriz de acesso |
| Fora de escopo | Implementação de Rules, custom claims, UI de gestão de papéis |

---

## 1. Princípio fundamental

> **Administração técnica não equivale a autorização clínica.**

O sistema reconhece que decisões clínicas são tomadas por profissionais externos
(veterinários) que NÃO possuem conta no sistema. Os usuários internos
(condutores e admins) são os **executores técnicos** — registram, transcrevem e
executam decisões profissionais, sempre com evidência documental.

---

## 2. Papéis internos (usuários com conta no sistema)

| Papel | Identificação | Onde vive | Natureza |
|-------|--------------|-----------|----------|
| **condutor** | Qualquer usuário autenticado com acesso a K9 | `canAccessDogRecord(dogId)` em Rules | Executor operacional — olhos e mãos do sistema |
| **admin** | Flag ou role no perfil do usuário | Custom claim ou campo em doc de usuário | Gestor administrativo — NÃO tem qualificação clínica |

### 2.1 O que NÃO existe no v1.0

- **Nenhum papel `veterinário` no sistema.** Veterinário é profissional externo identificado nos registros.
- **Nenhum custom claim `vet`.** Não há `isVet()` em Rules.
- **Nenhum login de veterinário.** O profissional não acessa o sistema diretamente.

### 2.2 Profissional externo (sem conta)

| Aspecto | Definição |
|---------|-----------|
| Quem é | Veterinário, nutricionista, ou outro profissional de saúde animal |
| Como aparece | Campo `professional` nos registros (ProfessionalIdentity) |
| Identificação | `name`, `registration_type` (CRMV, CRMV-Z, etc.), `registration_number`, `clinic` |
| Autenticação | Nenhuma — é identificado pelo condutor/admin que registra |
| Evidência | `source_document` (referência ao HealthDocument que comprova a decisão) |
| PII | Sim — nome e registro profissional são dados pessoais com acesso controlado |

---

## 3. Separação executor vs. profissional responsável

Toda ação clínica no sistema tem duas dimensões:

| Dimensão | Campo | Significado | Exemplo |
|----------|-------|-------------|---------|
| **Executor interno** | `recorded_by: {uid, name, internal_role}` | Quem digitou/registrou no sistema | GCM Silva (condutor) |
| **Profissional responsável** | `professional: {name, registration_type, registration_number, clinic}` | Quem tomou a decisão clínica | Dra. Costa (CRMV SP-12345) |

- `recorded_by` é SEMPRE obrigatório (preenchido automaticamente pelo auth)
- `professional` é obrigatório quando a ação requer decisão clínica externa
- Um condutor que registra uma consulta está **transcrevendo**, não **diagnosticando**

---

## 4. Capacidades (capabilities)

Capacidades são permissões granulares atribuídas a perfis de usuário. O mapeamento
capability-para-perfil é **decisão de implementação para fase posterior** (Fase 1B — questão
aberta O1 do Foundation Review). Aqui definimos o contrato: o que cada capability permite,
o que exige e quem pode exercê-la como **executor candidato** (não mapeamento aprovado).

### 4.1 Leitura

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.read` | Visualizar todos os registros de saúde do K9 | condutor, admin | Mobile, Web | — | — |

### 4.2 Registros de rotina

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.record_routine` | Registrar peso, refeição, suplemento | **Pesagem:** `operador_k9` (decisão aprovada em §12); demais usos mantêm seu mapping provisório próprio | Mobile | — | recorded_by obrigatório |

### 4.3 Registros preventivos

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.record_preventive` | Registrar vacinação, vermifugação | condutor, admin | Mobile, Web | `ProfessionalIdentity` + `source_document` **obrigatórios quando a informação veio de profissional externo**. Quando a aplicação foi execução interna devidamente autorizada, **não** se inventa `ProfessionalIdentity` externa — o registro fica com `professional: null` e `source_document: null` e a auditoria se faz via `recorded_by`. | recorded_by + (professional quando externo) |

### 4.4 Registros clínicos (transcrição de decisões profissionais)

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.record_incident` | Registrar intercorrência observada (abre caso) | condutor, admin | Mobile, Web | — (observação direta) | recorded_by |
| `health.record_clinical_document` | Transcrever consulta, laudo, evolução | condutor | Mobile, Web | professional obrigatório + source_document recomendado | recorded_by + professional |
| `health.request_exam` | Registrar solicitação externa de exame | condutor, admin | Mobile, Web | professional recomendado | recorded_by |
| `health.interpret_exam` | Registrar interpretação externa de resultado | condutor (provisório) | Web | professional obrigatório + source_document obrigatório | recorded_by + professional |
| `health.create_treatment` | Registrar prescrição externa (protocolo) | condutor (provisório) | Web | professional obrigatório + source_document obrigatório | recorded_by + professional |
| `health.administer_dose` | Executar administração de dose prescrita | condutor, admin | Mobile | — (execução direta) | recorded_by + administered_by |

### 4.5 Restrições e prontidão

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.issue_restriction` | Registrar restrição decidida por profissional externo | condutor, admin | Mobile, Web | professional obrigatório + source_document obrigatório | recorded_by + professional |
| `health.release_restriction` | Registrar liberação decidida por profissional externo | condutor, admin | Mobile, Web | end_professional obrigatório + end_source_document obrigatório (quando representa liberação clínica) + end_reason obrigatório | recorded_by + end_professional + end_reason |
| `health.discharge_case` | Registrar alta clínica do caso | condutor (provisório), admin | Web | **Quando representa alta clínica externa:** `ProfessionalIdentity` + `source_document` obrigatórios. **Quando é cancelamento puramente administrativo:** usa-se `health.cancel_case` com `cancel_reason`. | recorded_by + (professional+source_document quando alta clínica) |
| `health.reopen_case` | Reabrir caso clínico `discharged` retornando a estado clínico | condutor (provisório), admin | Web | `reopen_reason` obrigatório + `ProfessionalIdentity` + `source_document` quando aplicável | recorded_by + (professional+source_document quando aplicável) |
| `health.cancel_case` | Cancelar caso clínico preservando histórico | condutor (provisório), admin | Web | `cancel_reason` obrigatório | recorded_by + reason |

### 4.6 Tratamento e agenda

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.complete_treatment` | Concluir protocolo de tratamento (transição para `monitoring`) | condutor (provisório), admin | Web | professional recomendado | recorded_by + professional |

#### Agenda Preventiva — modelo operacional real (4E, canônico)

Não inventar capabilities `health.schedule_item` / `health.manage_schedule` nesta rodada.
Esses nomes, se aparecerem em tabelas históricas, são **não operacionais**.

| Operação | Autorização real (Functions) | Observação |
|----------|------------------------------|------------|
| **Create manual** | `health.create` + `requireDogRecordAccess` | Callable `healthScheduleCreateManual`; `scheduled_for` presente/futuro (backend) |
| **Update open** | `health.edit` + dog access + manual + open + revision | Callable `healthScheduleUpdateOpen` |
| **Complete** | `health.edit` + dog access | Callable `healthScheduleComplete` |
| **Cancel manual** | `health.edit` + dog access + `cancel_reason` | Callable `healthScheduleCancel` |
| **Cancel automático** | `health.edit` + dog access + **autoridade admin real** | Mesmo callable; UI mobile pode esconder se admin não for determinável no cliente |

> **Histórico (não operacional):** `health.schedule_item` e `health.manage_schedule` eram rótulos provisórios do foundation. A implementação 4E reutiliza `health.create` / `health.edit` existentes.

### 4.7 Correções e gestão

| Capability | Descrição | Executor candidato | Canal | Evidência requerida | Auditoria |
|-----------|-----------|--------------------|-------|--------------------|-----------|
| `health.cancel_record` | Cancelar registro (com justificativa) | condutor (próprios drafts), admin (qualquer) | Mobile, Web | cancel_reason obrigatório | recorded_by + reason |
| `health.amend_record` | Adicionar adendo a registro finalizado | condutor (próprios), admin (qualquer) | Mobile, Web | reason obrigatório + type (correction/addendum/complement) | recorded_by + reason |
| `health.manage_nutrition_plan` | Criar/superseder planos nutricionais | admin | Web → **backend** | professional recomendado | recorded_by |
| `health.audit` | Visualizar trilha de auditoria completa | admin | Web | — | — |

> **Nutrição (Fase 5B) — honestidade operacional:** as capabilities `health.read`, `health.record_routine` e `health.manage_nutrition_plan` são a **direção documental** alvo. **Não** estão enforced como catálogo granular nas Rules atuais (acesso a paths legados usa `canAccessDogRecord` + audited create/update). Wiring real = fase de autorização posterior (ou padrão Agenda create/edit se a matriz granular permanecer não implantada).
> **Writers canônicos alvo:** NutritionPlan = backend/Web-originated; MealLog e SupplementLog = **callable backend** (não Firestore client write). Mobile = plan **read-only**.

**Invariantes das capabilities:**

- `health.discharge_case`, `health.reopen_case`, `health.cancel_case`, `health.complete_treatment` exigem `ProfessionalIdentity` preenchida **quando representam decisão clínica externa**. Reaberturas meramente administrativas por erro de fechamento exigem capability, `reopen_reason` e auditoria — sem inventar documento veterinário inexistente.
- Mutações da Agenda (`health.create` / `health.edit` nos callables) operam apenas sobre `health_schedule` — não modificam prontidão, não encerram restrições, não alteram casos.
- `health.reopen_case` é permitido apenas em `ClinicalCase` com `clinical_status == "discharged"`. Estado de destino permitido: `open`, `under_investigation`, `under_treatment` ou `monitoring` (nunca direto a `cancelled`).
- `health.cancel_case` adiciona `cancel_reason` e mantém o histórico completo.
- `health.release_restriction` registra encerramento de restrição. **Reconciliado em ADR-005 E6:** `status == ended` **é** liberação clínica por definição, portanto `end_professional` + `end_source_document` + `end_reason` são obrigatórios **sempre** — não "quando representa decisão clínica externa". Não existe `ended` administrativo. Invalidação administrativa (duplicado, erro material, evidência incorreta) usa `cancelled`, que não é liberação clínica e cuja autoridade permanece pendente (ver ADR-005 E11 item 1).
- `health.issue_restriction` e `health.release_restriction` são autoridades **distintas** e não devem ser fundidas em uma capability genérica, nem substituídas por `health.create`/`health.edit`. A coluna "Canal" indica **iniciadores possíveis** de uma operação cuja autoridade é do backend (channel-agnostic); nenhum cliente escreve `operational_restrictions` diretamente. Ver ADR-005 E1/E2.
- O mapeamento capability → perfil real (`condutor`/`admin`) **permanece provisório até a Fase 1B** (questão O1). As tabelas acima listam **executores candidatos** — não atribuições aprovadas.

---

## 5. Regras de acesso por entidade (mapeamento provisório)

> **Mapeamento provisório:** a atribuição capability → perfil real (`condutor`/`admin`) está adiada para Fase 1B (Q5 do Foundation Review, questão aberta O1). As colunas abaixo descrevem **executores candidatos** baseados em leitura operacional comum — **não** atribuições aprovadas. Toda célula que mencionar `condutor` ou `admin` deve ser lida como "executor candidato / mapeamento provisório, sujeito à decisão da Fase 1B". Ajustes devem ser feitos após o inventário do modelo de perfis real.

| Entidade | Create | Read | Update | Soft Delete |
|----------|--------|------|--------|-------------|
| ClinicalCase | health.record_incident (intercorrência) ou capability de consulta [provisório] | health.read | server-orchestrated (transições explícitas) | health.cancel_case + cancel_reason [provisório] |
| ClinicalEvent | health.record_clinical_document (condutor) / health.record_incident (condutor) [provisório] | health.read | autor (se draft); cancelamento por health.cancel_record | autor (draft) [provisório] |
| Amendment | health.amend_record (próprio evento), capability admin (qualquer) [provisório] | health.read | — (imutável) | — |
| ExamProcess | health.request_exam | health.read | transições via capability (a definir; transições server-orchestrated) | capability administrativa [provisório] |
| TreatmentProtocol | health.create_treatment (Web, com evidence profissional) [provisório] | health.read | health.complete_treatment ou health.cancel_record [provisório] | health.cancel_record |
| DoseAdministration | health.administer_dose | health.read | — (imutável) | — |
| WeightAssessment | Backend-only `CreateQuickWeight` / `CreateOfficialWeight` / `CompleteWeightAsOfficial`; `operador_k9` + capability da operação | health.read + dog access | Sem UPDATE CRUD genérico; `CorrectWeight` exige `health.correct_routine`; complemento que muda peso exige também essa capability | Sem DELETE/soft delete genérico; `InvalidateWeight` exige `health.invalidate_routine` |
| NutritionPlan | health.manage_nutrition_plan via **backend** (Web) [provisório; capability **não** enforced no runtime atual] | health.read [doc] / dog access [ops] | backend only; Mobile **ZERO** write | lifecycle cancelled [provisório] |
| MealLog | health.record_routine via **callable** [provisório; não enforced] | health.read [doc] | soft cancel / correction auditada [provisório] | soft cancel — sem hard delete |
| SupplementLog | health.record_routine via **callable** [provisório; não enforced] | health.read [doc] | soft cancel [provisório] | soft cancel — sem hard delete |
| HealthDocument | health.record_clinical_document (quando clinical) ou health.record_preventive (quando preventivo); upload via Web ou Mobile com capability adequada [provisório] | health.read | metadados (autor) [provisório] | health.cancel_record [provisório] |
| OperationalRestriction | health.issue_restriction (com evidence profissional) | health.read | health.release_restriction (com end_professional+end_source_document quando externo, end_reason sempre) | capability administrativa [provisório] |
| VaccinationRecord | health.record_preventive (ProfessionalIdentity+source_document só quando externo; aplicação interna fica sem professional) [provisório] | health.read | metadados (autor) [provisório] | health.cancel_record [provisório] |
| HealthScheduleItem | **Operacional 4E:** `health.create` + dog (create manual via callable); Function (automático). ~~`health.schedule_item`~~ não operacional | health.read (Rules) | **Operacional 4E:** `health.edit` + dog (update/complete/cancel via callable); cancel auto exige admin real. ~~`health.manage_schedule`~~ não operacional | soft cancel via lifecycle (sem hard delete cliente) |
| LegacyHealthRecord | — (Admin SDK apenas, auditado) | health.read | **Read-only para clientes.** Admin SDK auditado pode atualizar `normalized_view`, `case_id`, metadados de reconciliação. `original_payload` é sempre imutável. | — |
| HealthTimeline (projeção) | Function | health.read | Function | Function |
| ReadinessSnapshot (projeção) | Function | health.read | Function | — |

---

## 6. Condições de autorização

| Condição | Pseudocódigo Rules | Propósito |
|----------|-------------------|-----------|
| `isAuthenticated` | `request.auth != null` | Usuário logado |
| `canAccessDogRecord` | Lógica existente em Rules | Acesso ao K9 específico |
| `hasCapability(cap)` | `get(/users/{uid}).data.capabilities.hasAny([cap])` | Usuário possui a capability |
| `canReadHealth(dogId)` | `isAuthenticated() && canAccessDogRecord(dogId) && hasCapability('health.read')` | Leitura comum, aplicada somente a caminhos Health explícitos |
| `isAuthor` | `request.auth.uid == resource.data.recorded_by.uid` | É o autor do registro |
| `hasProfessionalEvidence` | `request.resource.data.professional.name != ''` | Professional identity preenchida |
| `hasEndProfessionalEvidence` | `request.resource.data.end_professional.name != ''` | Professional identity de encerramento preenchida (liberação clínica externa) |
| `hasSourceDocument` | `request.resource.data.source_document != null` | Documento-evidência referenciado |
| `hasCancelReason` | `request.resource.data.cancel_reason != ''` | Justificativa de cancelamento |
| `hasEndReason` | `request.resource.data.end_reason != ''` | Justificativa de encerramento de restrição |
| `hasEndSourceDocument` | `request.resource.data.end_source_document != null` | Evidência documental do encerramento |
| `isDraft` | `resource.data.status == 'draft'` | Registro ainda em rascunho |
| `isFinal` | `resource.data.status == 'final'` | Registro finalizado |

---

## 7. Modelo de autorização proposto em Rules (pseudocódigo)

```
// Helper conceitual. Não usar wildcard recursivo amplo sob dogs/{dogId}.
function canReadHealth(dogId) {
  return isAuthenticated()
         && canAccessDogRecord(dogId)
         && hasCapability('health.read');
}

// Leitura aplicada explicitamente a cada caminho Health.
match /dogs/{dogId}/clinical_cases/{caseId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/clinical_cases/{caseId}/events/{eventId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}/amendments/{amendId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/clinical_cases/{caseId}/exams/{examId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/treatment_protocols/{protocolId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/treatment_protocols/{protocolId}/doses/{doseId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/weight_records/{recordId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/nutrition_plans/{planId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/meal_logs/{logId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/supplement_logs/{logId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/health_documents/{documentId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/operational_restrictions/{restrictionId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/vaccination_records/{vaccinationId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/health_schedule/{scheduleId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/legacy_health_records/{recordId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/health_timeline/{timelineId} { allow read: if canReadHealth(dogId); }
match /dogs/{dogId}/health_summary/current { allow read: if canReadHealth(dogId); }

// Escrita de evento clínico
match /dogs/{dogId}/clinical_cases/{caseId}/events/{eventId} {
  allow create: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.record_clinical_document')
                && hasRequiredEventFields();

  allow update: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && (
                  (isDraft() && isAuthor())
                  || (isFinal() && hasCapability('health.cancel_record')
                      && isCancelling() && hasCancelReason())
                );
}

// Restrições — requer evidence profissional
match /dogs/{dogId}/operational_restrictions/{id} {
  allow create: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.issue_restriction')
                && hasProfessionalEvidence()
                && hasSourceDocument()
                && hasRestrictionFields();

  allow update: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.release_restriction')
                && hasEndProfessionalEvidence()
                && hasEndSourceDocument()
                && hasEndReason()
                && isEndingRestriction();
}

// Tratamentos — transcrição com evidence
match /dogs/{dogId}/treatment_protocols/{protocolId} {
  allow create: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.create_treatment')
                && hasProfessionalEvidence()
                && hasSourceDocument();

  allow update: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.complete_treatment')
                && isStatusTransition();
}

// Doses — execução operacional
match /dogs/{dogId}/treatment_protocols/{protocolId}/doses/{doseId} {
  allow create: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.administer_dose')
                && isProtocolActive(protocolId);
}

// Exames (subcoleção de caso)
match /dogs/{dogId}/clinical_cases/{caseId}/exams/{examId} {
  allow create: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && hasCapability('health.request_exam');

  allow update: if isAuthenticated()
                && canAccessDogRecord(dogId)
                && isValidExamTransition();
}

// Projeções — bloqueadas para clientes; Admin SDK ignora Rules para escritas administrativas
match /dogs/{dogId}/health_timeline/{id} {
  allow read: if canReadHealth(dogId);
  allow write: if false; // bloqueado para clientes; Admin SDK ignora Rules para Functions
}

match /dogs/{dogId}/health_summary/current {
  allow read: if canReadHealth(dogId);
  allow write: if false; // bloqueado para clientes; Admin SDK ignora Rules para Functions
}

// Legacy — somente leitura
match /dogs/{dogId}/legacy_health_records/{id} {
  allow read: if canReadHealth(dogId);
  // Write bloqueado para clientes (Rules). Admin SDK ignora Rules; pode atualizar
  // campos administrativos limitados (normalized_view, case_id, metadados de reconciliação).
  // original_payload permanece sempre imutável.
  allow write: if false;
}
```

---

## 8. Fluxos de evidência

### 8.1 Condutor transcreve consulta veterinária

```
1. Condutor leva K9 ao veterinário (fora do sistema)
2. Veterinário examina, diagnostica, prescreve (decisão clínica EXTERNA)
3. Condutor recebe documento (receita, laudo, atestado)
4. Condutor faz upload do documento → HealthDocument
5. Condutor registra evento clínico:
   - recorded_by: {uid: "condutor_001", name: "GCM Silva", internal_role: "condutor"}
   - professional: {name: "Dra. Costa", registration_type: "CRMV",
                    registration_number: "SP-12345", clinic: "VetK9"}
   - source_document: {health_document_id: "doc_xyz", description: "Receita + laudo"}
   - content: {transcrição da consulta}
```

### 8.2 Condutor registra intercorrência

```
1. Condutor observa K9 mancando durante treinamento
2. Condutor registra intercorrência (observação própria):
   - recorded_by: {uid: "condutor_001", name: "GCM Silva", internal_role: "condutor"}
   - professional: null (não há profissional envolvido)
   - source_document: null (observação direta)
   - content: {description: "Claudicação MPD durante treinamento de faro"}
3. Sistema abre caso clínico automaticamente
```

### 8.3 Admin emite restrição baseada em laudo

```
1. Veterinário examina K9 e emite laudo com restrição (externo)
2. Admin recebe laudo digitalizado
3. Admin faz upload do laudo → HealthDocument
4. Admin registra restrição:
   - recorded_by: {uid: "admin_001", name: "Cap. Oliveira", internal_role: "admin"}
   - professional: {name: "Dr. Mendes", registration_type: "CRMV",
                    registration_number: "SP-67890", clinic: "HospVet"}
   - source_document: {health_document_id: "doc_abc", description: "Laudo restrição"}
   - level: "absolute"
   - description: "Pós-cirúrgico joelho D — repouso 30 dias"
```

---

## 9. Cenário ilustrativo: o que um admin não pode fazer (provisório)

> **Cenário ilustrativo e provisório, pendente de O1/Fase 1B.** O mapeamento capability → perfil ainda não foi aprovado. A tabela ilustra a separação entre autoridade administrativa e qualificação clínica; não atribui definitivamente capabilities ao perfil `admin`.

| Ação | Admin pode? | Justificativa |
|------|-------------|---------------|
| Criar conteúdo clínico original (diagnóstico) | ❌ | Não é profissional de saúde |
| Interpretar exame | ❌ | Requer conhecimento clínico |
| Criar protocolo de tratamento | ❌ | É prescrição médica |
| Cancelar registro com justificativa | ✅ | Gestão administrativa |
| Dar alta em caso (discharge) | ✅ | Com evidence documental |
| Emitir restrição com laudo profissional | ✅ | Transcrição com evidence |
| Liberar restrição com laudo profissional | ✅ | Transcrição com evidence |
| Visualizar auditoria | ✅ | Função administrativa |
| Gerenciar planos nutricionais | ✅ | Definição operacional |

---

## 10. Mapeamento de capabilities para implementação futura

> **ATENÇÃO — este mapeamento é provisório.** A atribuição capability → perfil real (`condutor`/`admin`) é decisão de implementação **adiada para a Fase 1B** (questão aberta O1 do Foundation Review). As listas abaixo são **propostas candidatas**, **não atribuições aprovadas**. Capabilities candidatas adicionadas no foundation (`health.reopen_case`, `health.cancel_case`, `health.complete_treatment`, etc.) também estão sujeitas a essa revisão.
> **Agenda (4E — operacional real):** `health.schedule_item` e `health.manage_schedule` são **históricos / não operacionais**. Não reintroduzir nas listas de perfil. Contrato real: create manual = `health.create` + dog access; update/complete/cancel = `health.edit` + dog access; cancel automático = `health.edit` + dog access + admin real.

O mapeamento capability → perfil real será definido na implementação. Possibilidades:

| Estratégia | Descrição | Prós | Contras |
|-----------|-----------|------|---------|
| Campo `capabilities[]` no doc | Array de strings no Firestore | Flexível, granular | Leitura extra em Rules |
| Perfis pré-definidos | `condutor` = set fixo, `admin` = superset | Simples, sem leitura extra | Menos flexível |
| Custom claims | JWT claims com array | Rápido em Rules (sem get) | Limite de tamanho do JWT |

**Proposta provisória** (NÃO aprovada, pendente da Fase 1B):

- **condutor (provisório)** → `health.read`, `health.record_routine`, `health.record_preventive`, `health.create` / `health.edit` (Agenda operacional 4E + dog access), `health.record_incident`, `health.record_clinical_document`, `health.request_exam`, `health.administer_dose`, `health.issue_restriction`, `health.release_restriction`, `health.cancel_record` (próprios drafts), `health.amend_record` (próprios)
  — **não** inclui `health.schedule_item` (não operacional)
- **admin (provisório)** → todas as capabilities de condutor + `health.interpret_exam`, `health.create_treatment`, `health.complete_treatment`, `health.discharge_case`, `health.reopen_case`, `health.cancel_case`, `health.manage_nutrition_plan`, `health.audit`, `health.cancel_record` (qualquer), `health.amend_record` (qualquer)
  — **não** inclui `health.manage_schedule` (não operacional; cancel automático de agenda usa `health.edit` + admin real)

> **Nenhuma capability inclui papel "veterinário"** — veterinário é profissional externo, registrado via `ProfessionalIdentity` quando a ação envolve decisão clínica externa.

> **Atualização da Permission Matrix depende da Fase 1B.** Esta matriz só pode ser declarada reconciliada e final após o inventário do modelo de perfis real (questão O1) e a decisão sobre as quatro capabilities novas adicionadas na Rodada 4.

---

## 11. Questões em aberto

1. **Mapeamento capability → perfil real:** adiado para Fase 1B (Q5 do Foundation Review). O mapping atual é provisório e precisa ser revisado após o inventário do modelo de perfis real.
2. **Condutor pode registrar interpretação de exame?** Proposta: não no v1.0. Interpretação exige transcrição de análise técnica — risco de erro alto. Apenas via Web com capability adequada.
3. **Condutor pode criar protocolo?** Proposta: não. Protocolo é prescrição — capability dedicada transcreve via Web com evidence profissional obrigatória.
4. **Granularidade do source_document:** obrigatório vs. recomendado depende da criticidade. Restrições e tratamentos = obrigatório. Consultas e preventivos = recomendado.
5. **PII profissional:** Firestore não oferece leitura por campo dentro do documento (Rules operam no nível do documento). Para o v1, usuários internos com `health.read` podem ler `ProfessionalIdentity` quando presente no registro. Projeções devem carregar o mínimo necessário. Restrição por perfil a campos específicos (ex: ocultar `crmv` ou `clinic`) **não** está no escopo do v1 — exigiria mover esses campos para uma subcoleção privada. Não há "veterinários autenticados" como readers.

---

## 12. Capabilities de Pesagem aprovadas (WEIGHT-00C)

| Capability | Finalidade | Profile-alvo | Estado atual | Estado-alvo | Risco | Auditoria |
|---|---|---|---|---|---|---|
| `health.record_routine` | Create Quick/Official, completar e adicionar anexo | `operador_k9` | **Ativa somente para create simples** | Reutilizada no lifecycle aprovado | Médio | operationId, receipt, actor, server time |
| `health.correct_routine` | Corrigir e remover anexo auditadamente | `operador_k9` | **NOT YET DEPLOYED** | Capability separada | Alto | before/after, reason, revision |
| `health.invalidate_routine` | Invalidar Pesagem | `operador_k9` | **NOT YET DEPLOYED** | Capability separada | Crítico | estado, reason, revision, reprojeção |
| `health.manage_weight_reference` | Faixa e meta versionadas | `operador_k9` | **NOT YET DEPLOYED** | Capability separada | Alto | config before/after, revision |

Todas exigem K9 existente e ativo, acesso ao K9 e autorização server-side. A
aprovação de destino ao profile não equivale a ativação; profiles/claims não são
alterados pela documentação. Follow-up usa o contrato existente de `health.create`
e somente após confirmação humana.

Para `WeightAssessment`, esta seção substitui as propostas genéricas anteriores
de executor `condutor`, update pelo autor, `health.cancel_record` e soft delete.
Não existe UPDATE CRUD, DELETE ou soft delete genérico: create/completion,
correction, invalidation e gestão de faixa/meta são commands backend-only com o
profile `operador_k9` e a capability indicada acima. `health.cancel_record` não
invalida Pesagem. Somente `health.record_routine` está implantada, limitada ao
create simples; as capabilities adicionais permanecem **APPROVED TARGET — NOT
YET DEPLOYED**.

Qualquer Operador K9 com a capability apropriada MAY operar sobre qualquer K9
existente e ativo ao qual tenha acesso. Não precisa ser o condutor vinculado,
estar com o K9 no turno nem ser o autor original. Alteração de `weight_kg` em
`CompleteWeightAsOfficial` exige simultaneamente `health.record_routine` e
`health.correct_routine`; sem a segunda capability, somente a complementação com
peso idêntico pode prosseguir.
