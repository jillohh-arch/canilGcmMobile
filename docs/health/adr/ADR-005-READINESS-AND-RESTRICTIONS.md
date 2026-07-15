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
