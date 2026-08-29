# Health v1.0 — Política de Prontidão Operacional

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-005, HEALTH_V1_DOMAIN_MODEL.md, HEALTH_V1_PERMISSION_MATRIX.md |
| Escopo | Vocabulário oficial, precedência, decisão, expiração, conflitos, casos especiais, política offline, separação display vs. autorização |
| Fora de escopo | IPO numérico, IA, implementação Dart, score legado |

---

## 1. Vocabulário oficial

| Termo | Definição |
|-------|-----------|
| **Prontidão operacional** | Estado consolidado que responde: "O K9 está apto para atividade operacional?" |
| **Restrição clínica** | Limitação imposta por decisão de profissional veterinário, registrada por usuário interno autorizado |
| **Restrição absoluta** | Bloqueio total: K9 não pode operar em nenhuma atividade |
| **Restrição parcial** | Bloqueio seletivo: K9 pode operar exceto em atividades listadas |
| **Atenção** | Ponto de observação que não impede operação, mas exige monitoramento |
| **ReadinessSnapshot** | Projeção server-side do estado consolidado para exibição, atualizada por Function |
| **Restrição canônica** | Documento em `operational_restrictions` com `status: active` — fonte de autoridade para validação de ações críticas |
| **IPO** | Índice de Prontidão Operacional — futuro (v2+), nunca sobrescreve restrição clínica |
| **Score legado** | `Dog.calculateReadiness()` — informativo, não decisor |

---

## 2. Estados oficiais

| # | Enum | Label PT-BR | Semântica | Pode operar? |
|---|------|------------|-----------|--------------|
| 1 | `operational` | Operacional | Nenhuma restrição, dados completos, já avaliado | ✅ Sim |
| 2 | `operational_attention` | Operacional com Atenção | Pode operar, mas há ponto de atenção | ✅ Sim (com alerta) |
| 3 | `fit_with_restrictions` | Apto com Restrições | Pode operar em atividades não restritas | ⚠️ Parcialmente |
| 4 | `temporarily_unfit` | Temporariamente Inapto | Não pode operar (restrição absoluta) | ❌ Não |
| 5 | `not_evaluated` | Não Avaliado | Sem avaliação de saúde registrada | ❓ A critério do responsável |

**Regra cardinal:** nenhum estado adicional pode ser criado. Nenhum score numérico substitui esses estados. O IPO futuro poderá coexistir como indicador complementar, mas jamais sobrescrever uma restrição absoluta.

---

## 3. Matriz de decisão (precedência)

A avaliação é executada sequencialmente — a primeira condição verdadeira determina o estado final:

| Prioridade | Condição | Estado resultante | Justificativa |
|-----------|----------|-------------------|---------------|
| 1 (máxima) | Existe restrição `level: absolute` + `status: active` | `temporarily_unfit` | Bloqueio total prevalece sobre tudo |
| 2 | Existe restrição `level: partial` + `status: active` | `fit_with_restrictions` | K9 pode operar parcialmente |
| 3 | Existe restrição `level: attention` + `status: active` | `operational_attention` | Monitoramento, sem bloqueio |
| 4 | Nenhuma avaliação de saúde registrada no sistema | `not_evaluated` | K9 recém-cadastrado ou sem histórico |
| 5 | Dados incompletos significativos (ver §4) | `operational_attention` | Atenção por ausência de informação |
| 6 | Nenhuma das anteriores | `operational` | Apto sem ressalvas |

**Justificativa da ordem 4 antes de 5:** `not_evaluated` (desconhecimento total) tem prioridade sobre `operational_attention` por dados incompletos (conhecimento parcial com lacunas). Um K9 que nunca foi avaliado no sistema é fundamentalmente diferente de um que já foi avaliado mas possui uma pesagem atrasada. Se o K9 nunca foi avaliado, não faz sentido checar completude de dados que nem existem.

**Regra de composição:** quando múltiplas restrições coexistem, a de maior prioridade (absolute > partial > attention) determina o estado. As demais são listadas no snapshot para visibilidade, mas não alteram o estado.

---

## 4. Dados incompletos — definição

"Dados incompletos significativos" que geram `operational_attention`:

| Indicador ausente | Threshold proposto | Natureza |
|-------------------|-------------------|----------|
| Sem pesagem registrada | >90 dias desde última pesagem | Configurável |
| Vacinação vencida | `next_due` ultrapassada sem registro posterior | Configurável |
| Sem consulta veterinária | >180 dias (nunca consultado neste sistema) | Configurável |
| Plano alimentar ausente | Nenhum plano `active` | Configurável |

**IMPORTANTE:** estes thresholds são **propostas configuráveis**, NÃO constantes aprovadas. Devem ser validados com a operação real antes de serem fixados. A implementação deve permitir ajuste sem alteração de código.

Essas condições NÃO geram `temporarily_unfit` — apenas sinalizam atenção. A ausência de dados não impede operação, mas demanda resolução.

---

## 5. Origem das evidências

| Evidência | Fonte canônica | Como chega ao snapshot |
|-----------|---------------|----------------------|
| Restrição ativa | `operational_restrictions/{id}` onde `status: active` | Function escuta onCreate/onUpdate |
| Última pesagem | `weight_records/{id}` mais recente por `measured_at` | Function escuta create |
| Vacinação vigente | `vaccination_records/{vaccinationId}` (fonte canônica) | Function escuta create |
| Plano alimentar ativo | `nutrition_plans/{id}` onde `status: active` | Function escuta create/update |
| Última consulta | `clinical_cases/events` com `event_type: consultation` | Function escuta create |

> **Vacinação vigente é lida exclusivamente de `vaccination_records`** — **não** de `clinical_cases/events`. Eventos clínicos do tipo `vaccination` só existem quando há relevância clínica dentro de um caso (reação adversa, complicação) e **referenciam** o `vaccination_record_id` original; não são fonte de vacinação vigente para a prontidão.

---

## 6. Separação: display vs. autorização

### Display (health_summary)

| Aspecto | Regra |
|---------|-------|
| Fonte | `health_summary/current` (projeção) |
| Uso | Badges, dashboard, cards, listas |
| Confiabilidade | Eventual consistency (~5-10s) |
| Pode bloquear ação? | NÃO como única barreira |

### Autorização (restrições canônicas)

| Aspecto | Regra |
|---------|-------|
| Fonte | `operational_restrictions` onde `status: active` |
| Uso | Validação server-side de ações operacionais críticas |
| Confiabilidade | Fonte canônica — sempre atualizada |
| Pode bloquear ação? | SIM — barreira definitiva |

### Ações que exigem validação canônica (não apenas summary)

| Ação | Validação |
|------|-----------|
| Iniciar turno com K9 | Query `operational_restrictions` com `level: absolute` + `status: active` |
| Trocar K9 durante turno | Mesma query |
| Escalar K9 para operação específica | Query + verificação de `activities_restricted` |

O summary é otimização de leitura. As restrições canônicas são a autoridade.

---

## 7. Duração e vigência

### Restrições

| Aspecto | Regra |
|---------|-------|
| Início | `issued_at` — momento do registro da decisão do profissional |
| Fim previsto | `expected_end` — data estimada de reavaliação (opcional) |
| Fim real | `actual_end` — preenchido quando encerrada explicitamente |
| Sem fim previsto | Restrições crônicas/indeterminadas. Permanecem ativas indefinidamente |
| Fim previsto ultrapassado | NÃO encerra automaticamente. Sinalizada como "vencida, aguardando reavaliação" |

### Snapshot

| Aspecto | Regra |
|---------|-------|
| Atualização | Real-time (trigger em fontes relevantes) |
| Validade | Até próxima atualização (não expira sozinho) |
| Offline | Último snapshot em cache permanece válido para exibição |

---

## 8. Expiração e reavaliação

| Cenário | Comportamento |
|---------|---------------|
| Restrição com `expected_end` passado | Function marca `is_overdue: true` no snapshot. Estado NÃO muda automaticamente |
| Reavaliação programada (schedule) | Item de agenda tipo `reevaluation` criado automaticamente |
| Profissional reavalia | Usuário autorizado pode encerrar restrição (→ recalcula estado) ou renovar (nova restrição) |
| Sem reavaliação por >30 dias | Function pode gerar alerta (item de schedule `overdue`) |

**Princípio:** nenhuma restrição expira silenciosamente. Expirações geram visibilidade, não ação automática.

---

## 9. Encerramento de restrições

| Requisito | Obrigatório? |
|-----------|-------------|
| Executante é usuário interno autorizado (executor candidato) | ✅ |
| Profissional que autorizou encerramento identificado (ProfessionalIdentity: name, registration_type, registration_number, clinic, specialty?) | ✅ quando representa decisão clínica externa |
| Campo `end_professional` preenchido (idem ProfessionalIdentity) | ✅ quando o encerramento representa liberação clínica externa |
| Campo `end_source_document` preenchido (HealthDocumentRef) | ✅ quando o encerramento representa liberação clínica externa |
| Campo `end_reason` preenchido | ✅ sempre |
| Campo `actual_end` com timestamp | ✅ |
| Campo `ended_by` com identidade do usuário interno (RecordedBy) | ✅ |
| Registro de encerramento em log imutável server-side | ✅ |

Após encerramento, a Function recalcula o snapshot considerando as restrições restantes.

---

## 10. Modelo de responsabilidade

| Papel | Natureza | Como se identifica | O que faz no sistema |
|-------|----------|-------------------|---------------------|
| Profissional veterinário | **Externo** | `ProfessionalIdentity { name, registration_type, registration_number, clinic, specialty? }` | Toma a decisão clínica |
| Usuário que registra | **Interno** | `RecordedBy { uid, name, internal_role }` | Registra a decisão do profissional |
| Usuário que encerra | **Interno** | `RecordedBy { uid, name, internal_role }` | Registra encerramento autorizado pelo profissional |

**NÃO existe custom claim `role: vet`.** O profissional veterinário é uma entidade externa ao sistema de autenticação. Suas credenciais profissionais são PII registradas no documento da restrição via `ProfessionalIdentity` (bloco completo), com acesso controlado.

**Não há `audit_trail` inline** em documentos clínicos ou de restrição. A auditoria é registrada pelo backend como log imutável, server-side.

**Controle de acesso aos dados do profissional (limitação do Firestore):**

Firestore Security Rules operam no nível do documento: o cliente recebe o documento inteiro ou nada. Regras não ocultam campos isolados. Dados que precisam de autorização diferente devem viver em documento ou subcoleção separada.

Para o Health v1:

- Todo usuário interno com `health.read` pode ler `ProfessionalIdentity` (bloco completo: `name`, `registration_type`, `registration_number`, `clinic`, `specialty?`) quando esse bloco está presente no registro. **Não há ocultação seletiva de campos profissionais por role/perfil dentro do mesmo documento** — promessa que não faz parte do v1.
- Projeções devem carregar apenas o mínimo necessário de ProfessionalIdentity (ex: nome do profissional para a timeline, sem expor `clinic` ou `registration_number` em superfícies de listagem).
- Restrição por perfil a campos específicos de `ProfessionalIdentity` (ex: ocultar `registration_number` ou `clinic` para condutores) **não** é implementada por projeção de campo no mesmo documento. Se for realmente necessária, os campos sensíveis devem ser movidos para uma subcoleção privada — fora do escopo do v1.

---

## 11. Ausência de dados

| Cenário | Estado | Comportamento na UI |
|---------|--------|-------------------|
| K9 recém-cadastrado, sem nenhuma avaliação | `not_evaluated` | Badge cinza "Não Avaliado" |
| K9 com histórico mas sem pesagem recente | `operational_attention` | Badge amarelo + alerta "Pesagem em atraso" |
| Erro de carregamento do snapshot | — | Exibir último cache + indicador de erro |
| Snapshot inexistente (nunca gerado) | `not_evaluated` | Badge cinza + CTA "Registrar primeira avaliação" |

---

## 12. Política offline e enforcement operacional

### Princípio geral

**Fail-open para incerteza, fail-closed para certeza.** A operação K9 não pode parar por falta de conectividade, mas restrições absolutas conhecidas são respeitadas mesmo offline.

### Cenários de início de turno

| Cenário | Comportamento | Justificativa |
|---------|---------------|---------------|
| Online, autorização crítica | Validação server-side SEMPRE consulta restrições canônicas (não confia apenas em snapshot) | Eventual consistency do snapshot é inaceitável para bloqueio operacional |
| Online, display | Exibe `health_summary`; se snapshot > 5 min, dispara refresh | Display pode tolerar eventual consistency |
| Offline, snapshot em cache ≤ 12h, estado != `temporarily_unfit` | Permitir com alerta "dados de prontidão podem estar desatualizados" | Dados recentes; incerteza baixa |
| Offline, snapshot em cache > 12h OU sem snapshot, estado != `temporarily_unfit` | Permitir APENAS com aceite operacional auditado do responsável (registro de aceite, não override clínico) | Dados antigos ou inexistentes; operação pode prosseguir com rastreabilidade explícita |
| Offline, último snapshot mostra `temporarily_unfit` | **BLOQUEAR** | Restrição absoluta conhecida — não é ignorável mesmo offline |

### Idade máxima do snapshot

| Aspecto | Política |
|---------|----------|
| Online — display | Refresh automático quando idade > **5 minutos** |
| Online — autorização crítica | Sempre consulta restrições canônicas; idade do snapshot não importa |
| Offline — janela "degraded mode" | Snapshot ≤ **12 horas** (default configurável) |
| Offline — acima da janela | Modo degradado com aceite operacional obrigatório do responsável |
| Frequência de refresh recomendada | A cada abertura da tela de turno |

**IMPORTANTE:** o threshold de 12h é proposta configurável. A operação real pode exigir valores diferentes por operação. **O aceite operacional não é override clínico** — apenas registra que o sistema não conseguiu consultar o estado atual canônico. Nenhuma restrição clínica é alterada ou encerrada por aceite.

### Reconciliação pós-conexão

Quando a conectividade retorna após operação offline:
1. Snapshot é atualizado automaticamente (trigger nas fontes).
2. Se o estado real diverge do que foi assumido offline, alerta é gerado.
3. Se K9 operou durante restrição absoluta que foi criada durante o período offline, registro de incidente é gerado para revisão.

---

## 13. Falha de carregamento

| Cenário | Comportamento |
|---------|---------------|
| Firestore offline | Usar snapshot em cache local |
| Cache vazio + offline | Exibir "Estado indisponível" sem badge de cor |
| Function falhou (snapshot desatualizado) | Reconciliação periódica detecta e reprocessa |
| Divergência entre restrição visível e snapshot | Snapshot é fonte de exibição; restrições canônicas são fonte de autorização |

**Princípio:** em caso de dúvida sobre o estado real, o sistema erra para o lado seguro (mais restritivo). Se há indício de restrição mas snapshot mostra `operational`, o condutor deve ser alertado.

---

## 14. Conflito entre decisões

| Cenário | Resolução |
|---------|-----------|
| Dois profissionais emitem restrições simultâneas | Ambas coexistem; estado = mais restritivo |
| Usuário A encerra restrição que usuário B registrou | Permitido (encerramento por qualquer usuário autorizado, com profissional identificado) |
| Restrição `absolute` + outra `partial` | Estado = `temporarily_unfit` (absolute prevalece) |
| Restrição parcial atividade X + outra parcial atividade Y | Estado = `fit_with_restrictions`; ambas listadas |
| Admin cancela restrição (erro administrativo) | `status: cancelled`; recalcula estado |

---

## 15. Impacto operacional

### No turno

| Estado | Comportamento ao escalar K9 |
|--------|----------------------------|
| `operational` | Permitido sem alertas |
| `operational_attention` | Permitido com alerta informativo no dashboard |
| `fit_with_restrictions` | Permitido com warning visível + registro de aceite pelo responsável |
| `temporarily_unfit` | **Bloqueado** — K9 não pode iniciar turno |
| `not_evaluated` | Permitido com warning + recomendação de avaliação |

### Na seleção do K9 para operação

| Estado | Comportamento |
|--------|---------------|
| `operational` | Disponível para qualquer atividade |
| `operational_attention` | Disponível com nota de atenção |
| `fit_with_restrictions` | Disponível apenas para atividades não listadas em `activities_restricted` |
| `temporarily_unfit` | **Indisponível** |
| `not_evaluated` | Disponível com alerta de avaliação pendente |

---

## 16. Separação do futuro IPO

| Aspecto | Prontidão clínica (Health v1.0) | IPO (futuro v2+) |
|---------|--------------------------------|-------------------|
| Natureza | Estado categórico (5 valores) | Índice numérico composto |
| Fonte | Restrições clínicas + dados de saúde | Saúde + treinamento + condicionamento + experiência |
| Decisor | Function baseada em regras explícitas | Algoritmo ponderado (a definir) |
| Pode bloquear turno? | ✅ (temporarily_unfit) | Poderá recomendar, mas NUNCA sobrescrever restrição absoluta |
| Quem define? | Profissional veterinário (via restrição registrada por usuário interno) | Sistema (automático) |
| Disponível em | Health v1.0 | Health v2+ |

**Invariante permanente:** se `readiness_status == temporarily_unfit`, nenhum IPO futuro pode liberar o K9. A restrição clínica é soberana.

---

## 17. Score legado — coexistência

| Aspecto | Score legado | Prontidão Health v1.0 |
|---------|-------------|----------------------|
| Onde vive | `Dog.calculateReadiness()` (cliente) | `health_summary/current.readiness_status` (server) |
| Tipo | Número 0-100 | Enum de 5 estados |
| Autoridade | Informativo | Decisório (display) + Restrições canônicas (autorização) |
| Pode ser exibido? | ✅ (como indicador secundário) | ✅ (como badge principal) |
| Pode bloquear turno? | ❌ (não deveria) | ✅ |
| Quando remover? | Quando IPO estiver implementado ou quando UX confirmar que não agrega | — |

Durante a transição, ambos podem coexistir na UI. O badge principal é o estado Health v1.0. O score legado pode aparecer como "Score operacional" em seção secundária, com nota de que não reflete restrições clínicas.

---

## 18. Pesagem: rotina, atenção e restrição (WEIGHT-00C)

Status: **APPROVED TARGET — NOT YET DEPLOYED**.

```text
weighing_routine_status (7/14 dias)
  != operational_attention (threshold configurável de 90 dias)
  != operational_restriction (autoridade canônica)
```

- 0–7 dias: `current`.
- 8–14 dias: `recommended`.
- Acima de 14 dias: `overdue`.

O status 7/14 gera alerta de rotina, badge Mobile e destaque Web. Não gera
restrição ou inaptidão. O threshold configurável de 90 dias permanece separado e
pode alimentar `operational_attention` durante a coexistência. Ele também não
gera inaptidão. Somente `operational_restrictions` explícitas podem limitar ou
bloquear operação.

Peso fora da faixa, variação elevada, BCS inadequado, leitura aproximada e atraso
de pesagem nunca criam automaticamente uma restrição. Ver
`HEALTH_WEIGHT_CANONICAL_SPEC.md` e ADR-008.
