# ADR-002 — Eventos Clínicos, Imutabilidade e Correções

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, HEALTH_V1_DOMAIN_MODEL.md, HEALTH_V1_FIRESTORE_SCHEMA.md |
| Escopo | Modelo de persistência, ciclo de vida, imutabilidade e mecanismo de correção para registros clínicos |
| Fora de escopo | Implementação Dart, IPO, IA, registros de rotina simples (peso, refeição) |

---

## 1. Contexto

O `HealthLogModel` atual permite update genérico de qualquer campo após criação. Isso significa que uma decisão clínica registrada (diagnóstico, conduta, prescrição) pode ser silenciosamente alterada sem rastro. Em saúde animal operacional, perder ou alterar decisões clínicas é um risco para o K9 e para a rastreabilidade institucional.

O Health v1.0 exige que "nenhuma decisão clínica pode ser perdida" e que "histórico é imutável". Precisamos definir como conciliar imutabilidade com a necessidade real de correções (erros de digitação, informação complementar, cancelamento por erro administrativo).

---

## 2. Problema

Como garantir rastreabilidade clínica completa sem impedir correções legítimas, mantendo custo razoável no Firestore e UX aceitável para condutores em campo?

---

## 3. Requisitos obrigatórios

1. Evento clínico concluído não pode ter seu payload clínico alterado.
2. Toda correção deve ser rastreável (quem, quando, o quê, porquê).
3. A versão original deve permanecer acessível e íntegra.
4. Eventos em rascunho (abertos) podem ser editados livremente até conclusão.
5. Cancelamento por erro administrativo não apaga o documento — marca como cancelado preservando todo o conteúdo clínico.
6. Autoria (quem registrou) e responsável profissional (veterinário) são campos separados.
7. Timestamps: `occurred_at` (quando aconteceu), `recorded_at` (quando foi registrado), `updated_at` (última modificação em rascunho).
8. `schema_version` para evoluções futuras.
9. Auditoria deve ser resistente a manipulação pelo cliente (não depender de audit_trail inline editável).
10. Status `final` permanece `final` mesmo após adendos — não existe transição para "amended".
11. Identidade profissional (nome, CRMV) é PII com acesso controlado.

---

## 4. Opções consideradas

### Opção A — Documento mutável com audit_trail inline

O documento é atualizado in-place. Um array `audit_trail` dentro do mesmo documento registra cada alteração (campo, valor anterior, ator, timestamp).

**Modelo atual:** é essencialmente isso que existe hoje.

### Opção B — Evento imutável com adendos separados

O documento, uma vez concluído, nunca é alterado. Correções e complementos são documentos novos (adendos) que referenciam o original.

### Opção C — Modelo híbrido por estado com imutabilidade de payload

- **Rascunho (draft):** documento mutável, sem restrições.
- **Concluído (final):** payload clínico congelado. Metadados server-managed podem ser atualizados de forma restrita (has_amendments, amendment_count, last_amended_at). Qualquer correção de conteúdo gera um adendo.
- **Cancelado (cancelled):** soft delete com justificativa obrigatória, conteúdo clínico preservado integralmente.

---

## 5. Comparação das opções

| Critério | A (mutável + trail) | B (imutável total) | C (híbrido por estado) |
|----------|--------------------|--------------------|----------------------|
| Rastreabilidade | Média (trail editável pelo cliente) | Máxima | Alta (final é imutável no payload) |
| UX em campo | Boa (edita direto) | Ruim (não pode corrigir typo antes de concluir) | Boa (rascunho livre) |
| Custo Firestore | 1 write por edição | N writes para cada alteração | 1 write até concluir; 1 write por adendo |
| Segurança | Fraca (cliente controla trail) | Forte | Forte após conclusão |
| Complexidade de leitura | Baixa | Média (precisa compor original + adendos) | Média |
| Migração do legado | Trivial (já é assim) | Difícil (backfill de estado) | Conservadora: preservar todos os `health_events` pré-go-live em `legacy_health_records` |
| Offline | Simples | Simples | Simples (rascunho local → conclui quando online) |

---

## 6. Recomendação

**Opção C — Modelo híbrido por estado com imutabilidade de payload.**

Combina a praticidade de edição em campo (rascunho) com a segurança clínica após conclusão (payload clínico imutável enforced por Rules). Adendos são documentos separados, leves e compostos na leitura. O status permanece `final` — metadados de controle (`has_amendments`, `amendment_count`, `last_amended_at`) indicam a existência de adendos sem alterar o estado clínico do evento.

---

## 7. Definição de imutabilidade

### Camadas do documento

| Camada | Exemplos de campos | Mutabilidade após `final` |
|--------|-------------------|---------------------------|
| **Payload clínico** | `content`, `event_type`, `occurred_at`, `recorded_by`, `professional`, `attachment_refs`, `source_document`, `operational_impact` | IMUTÁVEL — nunca pode ser alterado por nenhum cliente |
| **Metadados server-managed** | `has_amendments`, `amendment_count`, `last_amended_at`, `cancelled_at`, `cancelled_by`, `cancel_reason` | Atualizável de forma RESTRITA — apenas por operações específicas (adendo criado, cancelamento) |
| **Metadados de sistema** | `schema_version`, `legacy_source`, `legacy_id` | Imutável após final |

### Regras explícitas

1. **Payload clínico é imutável:** após transição para `final`, nenhum campo de `content`, `event_type`, `occurred_at`, `recorded_by`, `professional`, `attachment_refs`, `source_document` ou `operational_impact` pode ser alterado. Rules bloqueiam qualquer tentativa.
2. **Metadados server-managed podem mudar de forma restrita:** apenas para refletir a existência de adendos (`has_amendments: true`, incremento de `amendment_count`, atualização de `last_amended_at`) ou cancelamento (`cancelled_at`, `cancelled_by`, `cancel_reason`).
3. **Adendos são create-only:** uma vez criado, um amendment não pode ser editado nem deletado.
4. **Cancelamento não remove conteúdo:** adiciona campos de cancelamento ao documento. O payload clínico original permanece intacto e legível. O campo `status` muda para `cancelled`.
5. **Status permanece `final`:** a existência de adendos NÃO muda o status para "amended". O campo `has_amendments: true` sinaliza que há correções/complementos.

---

## 8. Consequências positivas

- Condutor pode salvar parcialmente e completar depois (operação real com K9 é interruptível).
- Após conclusão, nenhum cliente pode alterar o conteúdo clínico — segurança enforced em Rules.
- Adendos são documentos first-class com autoria e justificativa — auditoria verdadeira.
- Status `final` é estável e confiável para queries (não muda para "amended").
- Migração do legado: **todos os `health_events` anteriores ao go-live vão para `dogs/{dogId}/legacy_health_records/{recordId}`** como read-only para clientes. Nenhum `ClinicalEvent` é criado retroativamente a partir de `health_events`. Operações administrativas futuras podem vincular o registro legado a um caso via `case_id`, atualizar `normalized_view` ou criar evento clínico curado quando realmente necessário.
- Cancelamento por erro preserva o documento original visível, apenas marcado.
- Identidade profissional (PII) tem acesso controlado sem comprometer rastreabilidade.

---

## 9. Consequências negativas

- Leitura de um evento com adendos requer compor: original + adendos ordenados.
- Rules mais complexas (verificar estado + camada antes de permitir update).
- UI precisa exibir adendos de forma clara sem confundir o condutor.
- Rascunhos expirados precisam de política (apagar? alertar?).

---

## 10. Compatibilidade com o legado

| Dado legado | Tratamento |
|-------------|-----------|
| `health_events` anteriores ao go-live | Backfill para `dogs/{dogId}/legacy_health_records/{recordId}` com `original_payload` preservado; Admin SDK auditado pode complementar `normalized_view` e `case_id`; nenhum `ClinicalEvent` é criado retroativamente |
| `audit_trail` inline existente | Preservado como campo legado; não é mais a fonte de auditoria |
| Updates que já aconteceram | Não há como reconstruir; aceitar como estado atual final |

---

## 11. Impacto em Mobile

- Formulários salvam como rascunho automaticamente (auto-save parcial).
- Botão explícito "Concluir registro" transiciona para final.
- Após conclusão, UI oferece "Adicionar adendo" em vez de "Editar".
- Cancelamento requer justificativa textual obrigatória.
- Indicador visual quando `has_amendments: true` (ícone de adendo no card).

---

## 12. Impacto em Web

- Web pode visualizar e adicionar adendos.
- Web pode cancelar registros com permissão administrativa.
- Web não pode alterar eventos finalizados (mesma regra).

---

## 13. Impacto em Firestore

### Estrutura proposta para ClinicalEvent

```
dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}
├── status: "draft" | "final" | "cancelled"
├── event_type: string (enum)
├── occurred_at: timestamp
├── recorded_at: timestamp (server)
├── updated_at: timestamp (só em draft)
├── finalized_at: timestamp
├── recorded_by: RecordedBy { uid, name, internal_role }
├── professional: ProfessionalIdentity { name, registration_type, registration_number, clinic } (PII — acesso controlado)
├── content: { ... campos específicos por tipo e payload_type }
├── operational_impact: { ... }
├── attachment_refs: [ health_document_id ] (sem URLs inline)
├── source_document: HealthDocumentRef (nullable)
├── payload_type: string (ex: consultation_v1, incident_v1, reopen_v1)
├── payload_version: number
├── schema_version: number
├── legacy_source: string (opcional)
├── legacy_id: string (opcional)
│
│   Metadados de adendos (server-managed, atualizáveis após final):
├── has_amendments: bool (default false)
├── amendment_count: number (default 0)
├── last_amended_at: timestamp (nullable)
│
│   Campos de cancelamento (adicionados na transição final → cancelled):
├── cancelled_at: timestamp (nullable)
├── cancelled_by: RecordedBy { uid, name, internal_role } (nullable)
└── cancel_reason: string (nullable, obrigatório em cancelled)
```

### Adendos (create-only)

```
dogs/{dogId}/clinical_cases/{caseId}/events/{eventId}/amendments/{amendId}
├── type: "correction" | "addendum" | "complement"
├── reason: string (obrigatório)
├── content: { campo: novo_valor } (apenas campos corrigidos/complementados)
├── recorded_by: RecordedBy { uid, name, internal_role }
├── professional: ProfessionalIdentity (opcional, PII)
├── recorded_at: timestamp (server)
└── schema_version: number
```

### Rules simplificadas (pseudocódigo)

```
// ClinicalEvent
allow create: if validDraft() || validFinal();
allow update: if resource.data.status == "draft" && validDraftUpdate();
allow update: if resource.data.status == "final" && onlyCancelling();
// (metadados de adendo são atualizados por Function ao criar amendment)

// Amendments (create-only, imutáveis)
allow create on amendments: if parent.status == "final" && validAmendment();
allow update on amendments: if false; // nunca
allow delete on amendments: if false; // nunca
```

---

## 14. Impacto em segurança

- Update de payload clínico em documento `final` bloqueado em Rules.
- Metadados de adendo (`has_amendments`, `amendment_count`, `last_amended_at`) atualizáveis apenas via operação administrativa backend/Admin SDK (Admin SDK ignora Firestore Rules; o controle vem do backend, não de service account).
- Adendos são create-only (imutáveis após criação).
- `recorded_at` usa `request.time` em Rules (não confiável ao cliente).
- Cancelamento requer campo `cancel_reason` não vazio.
- Rascunhos expirados (>48h sem alteração) são **sinalizados por alerta**; **nunca** são cancelados automaticamente. Retomada é livre; cancelamento é sempre explícito e registrado.
- Identidade profissional (nome, registro, clínica) é PII: acesso restrito por capability; no v1, todo usuário interno com `health.read` pode ler `ProfessionalIdentity` no registro. Projeções devem carregar apenas o mínimo necessário. Restrição por perfil a campos específicos exigiria subcoleção privada separada (fora do escopo do v1). Não existe `role: vet` nem leitor veterinário autenticado.

---

## 15. Impacto em testes

- Testes de Rules: verificar que update de payload clínico em `final` é bloqueado.
- Testes de Rules: verificar que adendo em `draft` é bloqueado.
- Testes de Rules: verificar que amendments são create-only (update/delete bloqueados).
- Testes de Rules: verificar que cancelamento preserva `content` e adiciona campos de cancelamento.
- Testes de domínio: transições de estado válidas e inválidas.
- Testes de UI: fluxo rascunho → conclusão → adendo.
- Testes de migração: `health_events` legados migrados para `legacy_health_records` (read-only para clientes); nenhum ClinicalEvent retroativo criado.

---

## 16. Decisões registradas (não mais questões abertas)

As seguintes decisões humanas já foram tomadas e são refletidas neste documento:

1. **Política de rascunhos expirados:** alerta após **48 horas** sem alteração; rascunhos **nunca** são cancelados automaticamente; retomada é livre e cancelamento é explícito/registrado.
2. **Quem pode cancelar:** apenas o **autor original** pode cancelar `draft` próprio. Cancelamento de evento `final` exige capability `health.cancel_record`, justificativa obrigatória e (quando aplicável) identificação do profissional externo responsável via `ProfessionalIdentity`. Não há papel "veterinário/admin autenticado" — toda ação parte de usuário interno com capability.
3. **Limite de adendos:** sem limite técnico; UI mostra últimos 3 e expande sob demanda.
4. **Acesso a PII profissional:** Firestore não permite leitura por campo dentro do documento. No v1, usuários internos com `health.read` podem ler `ProfessionalIdentity` quando presente no registro. Projeções devem carregar o mínimo necessário. Restrição por perfil a campos específicos (ex: ocultar `crmv` ou `clinic`) **não** está no escopo do v1 — exigiria subcoleção privada separada. Não há "veterinários autenticados" como readers.

---

## 17. Critérios para aprovação

- [ ] Modelo de estados (draft → final, draft → cancelled, final → cancelled) está claro e completo.
- [ ] Status `final` permanece `final` mesmo com adendos (sem transição para "amended").
- [ ] Separação entre payload clínico (imutável) e metadados server-managed (restritamente mutáveis) está explícita.
- [ ] Regra de imutabilidade é enforced em Rules, não apenas em código.
- [ ] Mecanismo de adendo é suficiente para correções reais sem over-engineering.
- [ ] Cancelamento preserva o conteúdo clínico e exige justificativa.
- [ ] Migração do legado é viável sem perda de dados.
- [ ] UX de campo não é prejudicada (rascunho permite edição livre).
- [ ] Tratamento de PII profissional está definido.

---

## Diagrama de estados

```text
                 ┌──────────┐
                 │  draft   │
                 │(editável)│
                 └──┬───┬───┘
                    │   │
          concluir  │   │  cancelar rascunho
                    │   │
                    ▼   ▼
              ┌──────────┐     ┌────────────┐
              │  final   │     │ cancelled  │
              │(payload  │     │(preservado)│
              │ imutável)│     └────────────┘
              └────┬─────┘           ▲
                   │                 │
                   │  cancelar       │
                   │  (com justif.)  │
                   └─────────────────┘

   Adendos em final:
   ┌──────────┐       ┌────────────────────────────┐
   │  final   │──────→│ amendment (create-only)     │
   │          │       │ has_amendments: true        │
   │          │       │ amendment_count++           │
   │          │       │ last_amended_at: now        │
   └──────────┘       └────────────────────────────┘
   (status NÃO muda)


   Transições permitidas:
   draft → final (concluir)
   draft → cancelled (cancelar rascunho)
   final → cancelled (cancelar com justificativa — conteúdo preservado)

   Transições PROIBIDAS:
   final → draft (reverter conclusão)
   final → amended (NÃO EXISTE este estado)
   cancelled → qualquer (terminal)

   Cancelamento:
   - Adiciona: cancelled_at, cancelled_by, cancel_reason
   - NÃO altera: content, event_type, occurred_at, recorded_by, professional,
     attachment_refs, source_document, operational_impact
   - Conteúdo clínico permanece legível e íntegro
```
