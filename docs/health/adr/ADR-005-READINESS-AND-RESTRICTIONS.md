# ADR-005 — Prontidão Operacional e Restrições Clínicas

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-003, HEALTH_V1_READINESS_POLICY.md, HEALTH_V1_ARCHITECTURE.md |
| Escopo | Modelo de prontidão, estados, restrições clínicas, precedência, impacto operacional, separação display vs. autorização |
| Fora de escopo | IPO (futuro), IA, score numérico, implementação Dart |

---

## 1. Contexto

O score legado `Dog.calculateReadiness()` calcula um valor 0–100 baseado em vacinação, peso, banho e treino. Ele não representa os estados Health v1.0, não lê restrições clínicas e pode ser atualizado em um tracker do turno. O Health v1.0 Architecture define cinco estados oficiais de prontidão e estabelece que "Bloqueios absolutos sempre prevalecem" e "O IPO nunca poderá sobrescrever restrições clínicas."

Precisamos de um modelo que capture restrições clínicas como entidade própria e derive o estado de prontidão a partir delas, sem depender de score percentual.

---

## 2. Problema

Como modelar a prontidão operacional de forma que restrições clínicas absolutas sempre prevaleçam, sem score numérico, com vigência temporal, responsável identificado, e separação clara entre projeção para exibição e validação canônica para ações operacionais críticas?

---

## 3. Requisitos obrigatórios

1. Usar exatamente os cinco estados oficiais (sem inventar outros).
2. Restrição clínica absoluta SEMPRE prevalece, independente de qualquer outro indicador.
3. Nenhum score percentual substituto para IPO.
4. Restrições possuem vigência (início, término previsto, término real).
5. Restrições possuem responsável profissional identificado no registro e usuário interno que efetua a escrita.
6. Restrições possuem evidências (referência a evento, exame, caso clínico).
7. O estado de prontidão impacta diretamente o turno (K9 pode ou não ser escalado).
8. O estado de prontidão impacta a seleção do K9 em operações.
9. Comportamento definido quando dados estão indisponíveis (offline, erro).
10. Separação clara entre estado clínico atual, restrições ativas e futuro IPO.
11. Separação entre display (health_summary como projeção) e autorização (restrições canônicas validadas server-side).

---

## 4. Opções consideradas

### Opção A — Prontidão como campo derivado no cliente

O cliente lê restrições e calcula o estado localmente. Não há projeção server-side.

### Opção B — Prontidão como projeção server-side (ReadinessSnapshot)

Uma Cloud Function avalia todas as restrições ativas e projeta o estado em `health_summary/current`. O cliente apenas lê.

### Opção C — Prontidão mista (server com override manual)

Function calcula o estado base, mas um usuário autorizado pode fazer override (ex: liberar K9 apesar de restrição parcial para missão crítica).

---

## 5. Comparação das opções

| Critério | A (cliente) | B (server puro) | C (server + override) |
|----------|------------|-----------------|----------------------|
| Consistência | Baixa (cada cliente calcula) | Alta | Alta |
| Latência | Imediata | Eventual (~5s) | Eventual |
| Segurança | Fraca (cliente pode ignorar) | Forte | Forte com auditoria |
| Flexibilidade | Alta | Rígida | Alta |
| Offline | Funciona | Usa último snapshot | Usa último snapshot |
| Auditoria | Difícil | Nativa (Function loga) | Nativa + override auditado |
| Risco operacional | Alto (inconsistência entre dispositivos) | Baixo | Baixo com trilha |

---

## 6. Recomendação

**Opção B — Prontidão como projeção server-side (ReadinessSnapshot).**

O override manual (Opção C) é uma complexidade que pode ser avaliada no futuro se necessário. Para v1.0, a precedência é clara e não há cenário aprovado de "liberar K9 com restrição absoluta". Se surgir necessidade, ela será encerrar a restrição com justificativa, não override do snapshot.

**Separação crítica display vs. autorização:**

- `health_summary/current` é projeção para **exibição** (badges, dashboard, cards).
- Ações operacionais críticas (iniciar turno com K9, trocar K9 durante turno) **DEVEM** validar as restrições canônicas server-side (`operational_restrictions` com `status: active`).
- O summary NÃO pode ser a única barreira de segurança para ações operacionais.

---

## 7. Consequências positivas

- Todos os dispositivos veem o mesmo estado de prontidão.
- Turno e seleção de K9 consultam uma única fonte para exibição (snapshot).
- Ações críticas validam restrições canônicas server-side — defesa em profundidade.
- Restrições absolutas SEMPRE bloqueiam — não há bypass no cliente.
- Auditoria nativa (Function registra cada cálculo).
- Score legado pode coexistir sem conflito (é apenas informativo, não decisor).

---

## 8. Consequências negativas

- Eventual consistency: entre criar restrição e snapshot atualizar há ~5-10s.
- Se a Function falhar, o snapshot pode ficar desatualizado.
- Offline: o último snapshot pode não refletir restrição recém-criada.
- Necessidade de reconciliação periódica.
- Dupla validação (summary para display + restrictions para autorização) adiciona complexidade.

---

## 9. Compatibilidade com o legado

| Item legado | Tratamento |
|-------------|-----------|
| `Dog.calculateReadiness()` | Mantido como heurística operacional informativa. NÃO é mais fonte de decisão de prontidão clínica. UI pode mostrar ambos durante transição. |
| `readinessStreak` no documento K9 | Mantido como campo legado. Não alimenta o novo snapshot. |
| Ausência de restrições no legado | Estado padrão: `not_evaluated` até que o primeiro snapshot seja gerado. |

---

## 10. Impacto em Mobile

- Dashboard/Resumo mostra o estado de prontidão do snapshot (badge com cor + label).
- Turno consulta `health_summary/current.readiness_status` para **exibição**.
- Ação de escalar K9 no turno **valida server-side** as restrições canônicas ativas (não confia apenas no summary).
- Se `temporarily_unfit` ou restrição absoluta ativa: K9 **não pode iniciar turno** (bloqueio obrigatório, sem bypass).
- Se `operational_attention` ou `fit_with_restrictions`: K9 pode operar com alerta visível.
- Usuário interno autorizado pode emitir restrição transcrevendo decisão clínica externa: registra evento → emite `OperationalRestriction` identificando o profissional externo em `ProfessionalIdentity` → Function atualiza snapshot.

---

## 11. Impacto em Web

- Web mostra painel completo de prontidão com histórico de snapshots.
- Usuários autorizados (condutores, admin) emitem e encerram restrições pela Web, registrando o profissional externo responsável.
- Web pode visualizar precedência aplicada e evidências.
- Futuro: Web será responsável pela configuração do IPO quando implementado.

---

## 12. Impacto em Firestore

### OperationalRestriction

```
dogs/{dogId}/operational_restrictions/{restrictionId}
├── level: "absolute" | "partial" | "attention"
├── category: enum (injury, post_surgical, medication_effect, behavioral,
│                   infectious, chronic, preventive_pending, other)
├── description: string (texto livre da restrição)
├── activities_restricted: [ string ] (ex: ["faro", "busca", "guarda"])
├── issued_at: timestamp
├── recorded_by: RecordedBy { uid, name, internal_role }
│              (usuário interno autorizado que transcreveu a decisão clínica externa)
├── professional: ProfessionalIdentity
│              { name, registration_type, registration_number, clinic, specialty? }
│              (profissional externo que emitiu a restrição)
├── source_document: HealthDocumentRef
│              { health_document_id, description }
│              (laudo/atestado que evidencia a decisão)
├── expected_end: timestamp (nullable — restrições crônicas não têm fim previsto)
├── actual_end: timestamp (nullable — preenchido ao encerrar)
├── ended_by: RecordedBy (nullable — usuário interno que encerra)
├── end_professional: ProfessionalIdentity (nullable — profissional que autorizou encerramento)
├── end_source_document: HealthDocumentRef (nullable — laudo/atestado de liberação)
├── end_reason: string (nullable)
├── evidence: {
│     case_id: string (nullable),
│     event_id: string (nullable),
│     exam_id: string (nullable),
│     description: string
│   }
├── status: "active" | "ended" | "cancelled"
├── schema_version: number
└── (auditoria server-side: ações registradas em log imutável,
    não há audit_trail inline como array mutável pelo cliente)
```

### ReadinessSnapshot (dentro de health_summary — PROJEÇÃO PARA EXIBIÇÃO)

```
dogs/{dogId}/health_summary/current
├── readiness_status: "operational" | "operational_attention" |
│                     "fit_with_restrictions" | "temporarily_unfit" |
│                     "not_evaluated"
├── readiness_label: string (para exibição: "Operacional", etc.)
├── readiness_reason: string (resumo da razão do estado atual)
├── active_restrictions: [
│     { id, level, category, description, activities_restricted, since, expected_end }
│   ]
├── restriction_count: { absolute: N, partial: N, attention: N }
├── last_evaluated_at: timestamp
├── evaluated_by: "system" | "function_v1"
├── data_completeness: {
│     has_recent_weight: bool,
│     has_active_nutrition: bool,
│     has_vaccination_current: bool,
│     has_recent_exam: bool
│   }
└── ... (outros campos do summary definidos na ADR-004)
```

**IMPORTANTE:** este snapshot é projeção para exibição. Ações operacionais críticas (iniciar/trocar K9 em turno) DEVEM validar `operational_restrictions` canônicas server-side, não confiar apenas neste documento.

---

## 13. Impacto em segurança

### Quem pode criar/encerrar restrições

- Usuários internos autorizados, com a capability correspondente, podem criar e encerrar restrições.
- O profissional externo (veterinário) é identificado nos campos `professional` / `end_professional` com `ProfessionalIdentity` (nome, tipo de registro, número, clínica).
- NÃO existe custom claim `role: vet`. O controle de acesso é por capability interna.
- A decisão clínica é do profissional externo; o registro no sistema é feito pelo usuário interno autorizado que documenta essa decisão (com evidência documental).

### Dados sensíveis

- Informações do profissional (nome, CRMV) são PII com acesso controlado.
- `health_summary/current` é writable APENAS via operação administrativa backend/Admin SDK.
- Score legado não pode influenciar o snapshot (separação física).
- Condutor pode visualizar restrições do seu K9 mas não pode alterá-las (exceto se autorizado para registro).
- Encerramento de restrição requer justificativa não vazia.

### Validação para ações críticas

- Iniciar turno com K9: backend valida `operational_restrictions` onde `status: active` AND `level: absolute`.
- Trocar K9 durante turno: mesma validação.
- O summary sozinho NÃO é barreira suficiente — é otimização de leitura para display.

---

## 14. Impacto em testes

- Testes de precedência: restrição absoluta → `temporarily_unfit` independente de outros fatores.
- Testes de composição: múltiplas restrições com níveis diferentes.
- Testes de vigência: enquanto `status == active`, a restrição continua afetando o snapshot independente de `expected_end` vencido; `expected_end` vencido **não** encerra automaticamente a restrição e **não** remove seu efeito — apenas aciona `is_overdue: true` (alerta de reavaliação). Encerramento é ação explícita com `health.release_restriction`.
- Testes de Rules: condutor não autorizado não pode criar/editar restrição.
- Testes de turno: K9 com `temporarily_unfit` não pode ser escalado.
- Testes de dados incompletos: ausência de peso/vacina → `operational_attention`.
- Testes de not_evaluated: K9 sem nenhuma avaliação registrada → `not_evaluated`.
- Testes de concorrência: duas restrições criadas simultaneamente.
- Testes de validação server-side: ação crítica valida restrições canônicas, não apenas summary.

---

## 15. Decisões registradas (não mais questões abertas)

1. **Restrições parciais e turno:** K9 com `fit_with_restrictions` pode iniciar turno, com alerta visível e registro de aceite pelo responsável do turno.
2. **Expiração automática:** restrição com `expected_end` passado **não** é encerrada automaticamente; apenas sinalizada como "vencida, aguardando reavaliação". Encerramento requer ação explícita do usuário interno autorizado, com identificação do profissional externo via `ProfessionalIdentity`.
3. **Dados incompletos → qual estado?** `not_evaluated` = nunca avaliado neste sistema. Dados incompletos com ao menos uma avaliação registrada = `operational_attention`.
4. **Relação com treinamento:** aptidão de treinamento **não** afeta prontidão clínica no v1.0. Training avalia capacidade operacional técnica; Health avalia condição clínica. Ambos alimentarão o IPO futuro.
5. **Histórico de snapshots:** manter versões anteriores é desejável (`dogs/{dogId}/readiness_history/{timestamp}` para auditoria de evolução). Baixa prioridade — pode ser v1.1.
6. **Comportamento ao iniciar turno offline:** ver §16.
7. **Idade máxima do snapshot:** display online atualiza quando snapshot > **5 minutos**; offline usa **12 horas** como janela de "degraded mode" (default configurável). Acima de 12h, exige aceite operacional auditado. Não há "default 24h" — esse valor foi descartado.
8. **Thresholds de dados incompletos:** 90 dias para peso, 180 dias para consulta — são propostas configuráveis, **não** constantes aprovadas. Devem ser validadas com operação real antes de serem fixadas.
9. **Prontidão:** VaccinationRecord é a fonte canônica de vacinação vigente; a prontidão **não** lê vacinação de `clinical_cases/events`. Eventos clínicos de vacinação só existem quando há relevância clínica dentro de um caso.

---

## 16. Política offline e enforcement operacional

### Contrato único

| Cenário | Comportamento | Justificativa |
|---------|---------------|---------------|
| Online — autorização crítica | Backend consulta SEMPRE `operational_restrictions` canônicas (não confia apenas no snapshot) | Eventual consistency do snapshot é inaceitável para bloqueio operacional |
| Online — display | Exibe `health_summary/current`; se idade > **5 minutos**, dispara refresh | Display tolera eventual consistency |
| Offline — snapshot em cache ≤ **12 horas**, estado != `temporarily_unfit` | Permitir com alerta "dados de prontidão podem estar desatualizados" (modo degradado) | Dados recentes; incerteza baixa |
| Offline — snapshot em cache > **12 horas** OU sem snapshot, estado != `temporarily_unfit` | Permitir APENAS com **aceite operacional auditado** do responsável | Dados antigos ou inexistentes; operação pode prosseguir com rastreabilidade explícita |
| Offline — último snapshot mostra `temporarily_unfit` | **BLOQUEAR** | Restrição absoluta conhecida — não é ignorável mesmo offline |

### Idade máxima do snapshot (valores canônicos)

| Aspecto | Política |
|---------|----------|
| Online — display | Refresh automático quando idade > **5 minutos** |
| Online — autorização crítica | Sempre consulta restrições canônicas; idade do snapshot não importa |
| Offline — janela "degraded mode" | Snapshot ≤ **12 horas** (default configurável) |
| Offline — acima da janela | Modo degradado com aceite operacional obrigatório do responsável |

> **Não há "default 24h"** — esse valor foi descartado. Os valores canônicos são 5 minutos (display refresh) e 12 horas (offline degraded mode).

### Natureza do aceite operacional

- O aceite **não** é override clínico.
- O aceite **não** altera nem encerra restrição clínica.
- O aceite **não** modifica `health_summary/current` ou `operational_restrictions`.
- O aceite é apenas um registro auditado de que o sistema não conseguiu consultar o estado atual canônico.

### Princípio

Fail-open para incerteza (sem dados), fail-closed para certeza (restrição absoluta conhecida). A operação não pode parar por falta de conectividade, mas restrições absolutas conhecidas são respeitadas mesmo offline.

---

## 17. Critérios para aprovação

- [ ] Os cinco estados oficiais estão definidos com semântica inequívoca.
- [ ] Precedência de restrições está clara (absolute > partial > attention > not_evaluated > dados incompletos > operational).
- [ ] Bloqueio absoluto impede turno sem bypass.
- [ ] Vigência e encerramento de restrições estão modelados.
- [ ] Comportamento com dados incompletos está definido.
- [ ] Separação do IPO futuro está explícita.
- [ ] Score legado coexiste sem conflito.
- [ ] Separação display (summary) vs. autorização (restrições canônicas) está explícita.
- [ ] Validação server-side para ações críticas está definida.
- [ ] Não existe custom claim `role: vet` — profissional é externo, identificado no registro.
- [ ] Política offline está definida (fail-open com rastreabilidade, fail-closed para restrição conhecida).
- [ ] Thresholds são propostas configuráveis, não constantes aprovadas.

---

## Estados oficiais de prontidão

| Estado (enum) | Label | Significado | Pode operar? | Cor sugerida |
|---------------|-------|-------------|--------------|--------------|
| `operational` | Operacional | K9 apto sem restrições | ✅ Sim | Verde |
| `operational_attention` | Operacional com Atenção | K9 apto mas com ponto de atenção (vacina próxima, dados incompletos) | ✅ Sim, com alerta | Amarelo |
| `fit_with_restrictions` | Apto com Restrições | K9 pode operar em atividades específicas (restrição parcial) | ⚠️ Parcialmente | Laranja |
| `temporarily_unfit` | Temporariamente Inapto | K9 não pode operar (restrição absoluta ativa) | ❌ Não | Vermelho |
| `not_evaluated` | Não Avaliado | K9 sem avaliação de saúde registrada no sistema | ❓ A critério do responsável | Cinza |

---

## Matriz de precedência

```text
Avaliação de prontidão (executada pela Function):

1. Há restrição ABSOLUTA ativa?
   └─ SIM → temporarily_unfit (FINAL — nenhuma outra avaliação importa)

2. Há restrição PARCIAL ativa?
   └─ SIM → fit_with_restrictions

3. Há restrição de ATENÇÃO ativa?
   └─ SIM → operational_attention

4. Já houve ao menos uma avaliação de saúde registrada?
   └─ NÃO → not_evaluated

5. Há dados incompletos significativos? (sem peso >90d, sem vacina em dia, etc.)
   └─ SIM → operational_attention

6. Nenhuma restrição, dados completos, já avaliado:
   └─ operational
```

**Nota sobre precedência 4 vs. 5:** um K9 que nunca foi avaliado no sistema (`not_evaluated`) tem prioridade sobre um K9 que já foi avaliado mas possui dados incompletos (`operational_attention`). Isso porque `not_evaluated` é um estado de desconhecimento total, enquanto dados incompletos indicam conhecimento parcial com lacunas específicas.

---

## Separação de conceitos

| Conceito | Responsável | Onde vive | Health v1.0? |
|----------|------------|-----------|--------------|
| Estado de prontidão (display) | Function (automático) | `health_summary/current.readiness_status` | ✅ Projeção |
| Restrições clínicas (autoridade) | Usuário autorizado + profissional | `operational_restrictions/{id}` | ✅ Canônico |
| Validação para ações críticas | Backend (Rules/Function) | `operational_restrictions` query | ✅ Server-side |
| Score legado operacional | `Dog.calculateReadiness()` (cliente) | `dogs/{dogId}` campos avulsos | ⚠️ Mantido informativo |
| IPO (Índice de Prontidão Operacional) | Futuro | Não definido | ❌ v2+ |
| Aptidão de treinamento | Módulo Training | `training_*` | ❌ Separado |

O IPO futuro poderá consumir TANTO o estado clínico QUANTO indicadores de treinamento, condicionamento e experiência operacional. Mas **nunca poderá sobrescrever uma restrição clínica absoluta**.

---

## Modelo de responsabilidade: profissional vs. usuário

| Papel | Natureza | Identificação | Ação no sistema |
|-------|----------|---------------|-----------------|
| Profissional externo (veterinário, nutricionista, etc.) | **Externo** | `ProfessionalIdentity { name, registration_type, registration_number, clinic, specialty? }` | Determina a decisão clínica |
| Usuário que registra | **Interno** | `RecordedBy { uid, name, internal_role }` + capability | Registra no sistema a decisão do profissional externo |
| Usuário que encerra | **Interno** | `RecordedBy { uid, name, internal_role }` + capability | Registra no sistema o encerramento autorizado pelo profissional externo |

Não existe custom claim `role: vet`. O profissional é uma entidade externa ao sistema de autenticação. Suas credenciais profissionais são dados registrados no documento (`ProfessionalIdentity`), não claims de autenticação.

---

## Integração de Pesagem (WEIGHT-00C)

O target separa três conceitos: rotina 7/14, `operational_attention` configurável
de 90 dias e `operational_restriction`. Atraso acima de 14 dias gera alertas de
rotina, mas não inaptidão. O threshold de 90 dias pode continuar alimentando
atenção durante a coexistência. Peso fora da faixa, variação, BCS, leitura
aproximada e atraso nunca criam restrição automaticamente. Esta decisão target
ainda não está implantada integralmente. Ver ADR-008.

---

## Emenda — HEALTH-V1-RESTRICTION-WRITER Gate A.2 (2026-08-14)

Esta emenda reconcilia as decisões necessárias para implementar o writer produtivo
de `OperationalRestriction`. Ela **não** altera as decisões aprovadas em 2026-07-13;
resolve ambiguidades que o Gate A (auditoria read-only sobre
`5ebc2e4a9af7b586b1d693ca64fd35294b91922f`) expôs.

### E1. Canal não é autoridade

§10 (Impacto em Mobile) e §11 (Impacto em Web) descrevem ambos a emissão e o
encerramento por usuário interno autorizado. Isso **nunca** significou exclusividade
de canal.

A autoridade de mutação pertence ao **backend**, que é channel-agnostic. Mobile e Web
são iniciadores possíveis da mesma operação autorizada. Nenhum cliente escreve
`operational_restrictions` diretamente: Firestore Rules permanecem deny-all para
writes de cliente, e essa negação é parte do contrato, não uma limitação temporária.

Para o Health Mobile v1, Mobile é o primeiro canal de UI implementado. Web reutilizará
as mesmas callables sem alteração de contrato.

### E2. Vocabulário de autoridade

Emissão e liberação são autoridades **distintas**, com grants independentes:

- `health.issue_restriction`
- `health.release_restriction`

Não reutilizar `health.create`, `health.edit`, `health.manage_nutrition_plan` ou
`health.record_routine` — sob pena de "registrar vacina" passar a implicar "declarar
K9 inapto". Não criar capability genérica `health.manage_restriction`: emitir e
liberar têm impacto operacional oposto e precisam poder divergir.

Autorização é access-profile/capability driven. Não existe autoridade derivada de
`role == gestor | condutor | instrutor` hard-coded.

Admin não é profissional clínico. Onde houver bypass administrativo, o admin continua
sendo apenas o usuário interno que registra a decisão externa — nunca substitui
`ProfessionalIdentity` nem dispensa `source_document`.

### E3. Evidência documental é pré-requisito, não formalidade

`source_document` permanece **obrigatório** na emissão. Não é relaxável.

A coleção legada `documentos` (raiz) **não** é evidência canônica e não será promovida
automaticamente: faltam `storage_path`, `mime_type` e `recorded_by` canônicos, e não
existe regra de derivação segura (conclusão já registrada em
`lib/features/health/legacy/legacy_document_adapter.dart`).

Consequência de sequenciamento: uma **fatia mínima canônica de `HealthDocument`**
precede o writer de restrição. Escopo dessa fatia: criar documento canônico com id
estável, `storage_path`, `mime_type`, `recorded_by` server-authoritative, vínculo ao
K9, tipo/descrição, audit e idempotência — suficiente para produzir um
`HealthDocumentRef` válido. Biblioteca documental, busca, compartilhamento e demais UX
permanecem fora de escopo.

Isso inverte, deliberadamente, a ordem temática do roadmap (Documentos aparece depois
de Prontidão). A inversão é uma dependência de contrato, não uma reordenação de
prioridade de produto.

### E4. ProfessionalIdentity não se infere do legado

Os campos legados `vetName`, `professionalCrmv` e `professionalClinic` (escalares
soltos em `health_events`) **não** são promovidos a `ProfessionalIdentity` por
derivação silenciosa.

Shape canônico inalterado: `name`, `registration_type`, `registration_number`,
`clinic`, `specialty?`.

Em particular, `registration_type` deve existir **explicitamente no payload**. A UI
pode apresentar `CRMV` como valor inicial visível para o caso veterinário, mas o valor
não pode ser assumido apenas porque o campo legado se chamava "CRMV".

Não há registry de profissionais no v1. `ProfessionalIdentity` permanece snapshot
embutido da decisão clínica externa.

### E5. Restrição é agregado próprio, com fluxo próprio

A emissão **não** depende de Consulta, Exame ou Cirurgia estarem canônicos. Em
particular, workflows de Cirurgia estão diferidos para v2+
(`HEALTH_V1_FOUNDATION_REVIEW.md` §6), portanto não podem ser foundation do writer v1.

A primeira superfície Mobile é um fluxo próprio de Restrição Operacional. Esse fluxo
deve **aceitar opcionalmente** contexto clínico (consulta, exame, cirurgia, outro
registro canônico) preenchendo `source_document`, `professional` e referências, sem
**depender** desses fluxos para existir.

### E6. `ended` é liberação clínica; `cancelled` é invalidação administrativa

Esta é a reconciliação semântica central desta emenda. Não existe "encerramento
administrativo" de restrição.

**`active → ended`** representa liberação/encerramento **clínico real** e exige, sempre:

| Campo | Origem |
|-------|--------|
| `end_reason` | não vazio |
| `actual_end` | server-side |
| `ended_by` | server-authoritative (`RecordedBy`) |
| `end_professional` | `ProfessionalIdentity` do profissional externo que liberou |
| `end_source_document` | `HealthDocumentRef` da evidência de liberação |

A mesma separação profissional-externo / usuário-interno que vale na emissão vale na
liberação: o usuário interno registra, o profissional externo decide, o documento
comprova. Isso **substitui** as formulações anteriores que condicionavam
`end_professional` e `end_source_document` a "quando representa decisão clínica
externa" — em `ended`, sempre representa.

**`active → cancelled`** não é liberação clínica. Serve para registro duplicado, erro
material de lançamento, registro inválido ou evidência associada incorretamente.
Preserva documento e dados originais, é terminal, exige motivo explícito, actor e
timestamp. Não há hard delete e `cancelled` nunca retorna a `active`.

Consequência para prontidão: `cancelled` remove o efeito da restrição sem afirmar
liberação clínica. Um `cancelled` indevido é um risco operacional, não um atalho de UX.

### E7. Política de correção — append-oriented

Após a emissão, os campos de substância clínica são **imutáveis**: `level`, `category`,
`description`, `activities_restricted`, `professional`, `source_document`, `issued_at`,
`expected_end` e a evidência clínica material.

- Erro de lançamento: `active → cancelled` e, se necessário, nova restrição correta.
- Nova decisão/reavaliação clínica: encerrar a anterior conforme E6 e emitir nova
  restrição quando houver nova limitação.

Não existe update livre estilo CRUD sobre restrição ativa.

### E8. Compatibilidade de leitor não define o agregado

Os consumidores atuais (`resolveRestrictionsEvidence`, usado tanto pelo readiness
projector quanto pelo guard de turno) leem apenas `status`, `level`, `description`,
`since`/`issued_at`, `activities_restricted`, `expected_end` e `category`.

Esse conjunto é **compatibilidade de consumidor, não definição do agregado**. O writer
deve produzir um documento simultaneamente válido para o Domain Model (provenance e
evidência inclusas), para OP-AUTH, para o projector, e auditável. Não reduzir o
agregado ao shape mínimo do parser.

### E9. Invariante de documento totalmente parseável

O leitor canônico é fail-closed e a query é **sem filtro**: um único documento
malformado torna toda a fonte de restrições daquele K9 `unavailable`, o que **nega**
ações operacionais críticas. Um timestamp ainda não materializado em formato aceito
conta como malformado.

Portanto nenhum documento pode se tornar observável pelo leitor em estado
parcialmente escrito. Escrita parcial é apagão operacional do K9, não leitura
degradada. A implementação disso é decidida no Gate correspondente; a exigência é
contrato.

### E10. `partial` e taxonomia de atividades

`level == partial` continua exigindo `activities_restricted` não vazio.

`activities_restricted` permanece free-form no v1. O taxonomy gap é conhecido e
registrado; não será resolvido nesta vertical. O writer garante apenas a invariante
estrutural.

### E11. Pendências registradas (não resolvidas nesta emenda)

1. **Autoridade de `cancelled` — CONFLITO ABERTO.** E2 define autoridades para emitir e
   liberar. `cancelled` não é liberação clínica (E6), portanto `health.release_restriction`
   não é obviamente a autoridade correta, e `health.issue_restriction` tampouco.
   `HEALTH_V1_PERMISSION_MATRIX.md` §5 registra "capability administrativa [provisório]"
   para essa coluna. Decisão pendente antes do Gate que implementar cancel.
   → **RESOLVIDO em E12** (Gate B2-A): a autoridade é `health.cancel_restriction`,
   capability própria e distinta.
2. **Defeito em `OperationalRestrictionTransitions.transition`**
   (`lib/features/health/domain/health_v1_transitions_v2.dart`): valida
   `cancelledAt`/`cancelledBy`/`cancelReason`, campos que o agregado não possui, e
   descarta `endProfessional`/`endSourceDocument` ao construir o objeto encerrado —
   perdendo exatamente a evidência que E6 torna obrigatória. Correção pertence ao Gate
   de implementação. O shape correto é o desta emenda.
3. **Mapeamento capability → perfil real** permanece provisório, como já registrado na
   Permission Matrix (questão O1).

### E12. Autoridade das transições terminais (Gate B2-A)

Resolve o CONFLITO ABERTO de E11 item 1. São **três** poderes distintos, com três
capabilities distintas:

| Transição | Autoridade | Afirmação feita pelo usuário |
|-----------|-----------|------------------------------|
| — → `active` | `health.issue_restriction` | cria impacto operacional |
| `active` → `ended` | `health.release_restriction` | o motivo clínico da restrição terminou |
| `active` → `cancelled` | `health.cancel_restriction` | este registro não é autoridade operacional válida |

`health.cancel_restriction` é capability **própria**. Não reutilizar
`health.release_restriction`, `health.issue_restriction`, `health.create`,
`health.edit`, `health.approve` nem `health.cancel_record`.

**Por que capability própria.** Para `readiness` e OP-AUTH o *efeito* de `ended` e
`cancelled` é o mesmo — a restrição deixa de bloquear. Mas a afirmação é
completamente diferente. Fundir cancel em `health.release_restriction` faria alguém
com poder de corrigir cadastro praticar, pelo sistema, uma liberação clínica. Usar
`health.issue_restriction` seria pior ainda: poder criar uma restrição não deve
implicar poder apagar o efeito dela.

**Risco que justifica o nome próprio.** `cancelled` não afirma melhora clínica, mas
remove o efeito operacional: uma autorização indevida de cancel **recoloca um K9 em
operação**. Não é CRUD administrativo comum, e a capability precisa dizer isso em voz
alta — "esta pessoa tem autoridade para invalidar uma restrição operacional ativa".

**Campos obrigatórios por transição** (consolida E6):

| `active` → `ended` | `active` → `cancelled` |
|---|---|
| `end_reason` — não vazio | `cancel_reason` — não vazio |
| `actual_end` — server | `cancelled_at` — server |
| `ended_by` — server (`RecordedBy`) | `cancelled_by` — server (`RecordedBy`) |
| `end_professional` — obrigatório | **não** exige professional |
| `end_source_document` — obrigatório | **não** exige HealthDocument |

`cancelled` não exige `ProfessionalIdentity` nem `HealthDocumentRef` **por decisão**:
exigi-los transformaria invalidação administrativa numa pseudo-liberação clínica.
Simetricamente, não existe `ended` administrativo (E6).

`end_source_document` é evidência **da liberação** — espera-se um novo HealthDocument
canônico. Não assumir `end_source_document == source_document` original; reutilizar o
documento que originou a restrição só seria legítimo se ele próprio contivesse a
liberação, o que não é o fluxo v1.

**Escopo de `cancelled`.** Invalidação factual do registro: criado por engano,
duplicidade, K9 incorreto, evidência vinculada errada, transcrição materialmente
incorreta, ou outro erro de registro. **Não** é cancel: condição melhorou, tratamento
acabou, prazo venceu, profissional liberou, K9 está apto — esses casos são `ended`
quando houver liberação clínica documentada. Nenhuma taxonomia de motivo é criada:
`cancel_reason` é texto obrigatório, auditável e imutável.

**Concessão a perfis reais permanece fora do código** (E11 item 3 / questão O1).
Vocabulário de capability implementado ≠ grant concedido. As três decisões — quem
emite, quem libera, quem cancela — são independentes e pertencem ao cutover.
