# ESPECIFICAÇÃO TÉCNICA — PARTE 13
# Padrão unificado de treinamento · Formação / Operacional
### Generaliza o fluxo de formação (detecção/Parte 4_1) para todas as modalidades

> Esta parte define **um padrão único** de treino para **Detecção**, **Busca & Captura** e **Guarda & Proteção**. A causa do "não funciona a lógica" em B&C era a ausência desta spec. A **detecção (Parte 4_1) é a referência que funciona** — o padrão a generaliza. **Não reimplementar a detecção**; aplicar o padrão primeiro a B&C, validar, e só então avaliar unificar detecção e G&P no mesmo componente.
>
> Mockups: `treino_v2_sessao_e_promocao.html` (sessão de trilha + promoção co-validada), `padrao_treino_formacao_operacional.html` (abas + módulos).

---

## 13.0 — Conceito
Cada modalidade tem **duas abas**: **Formação** (módulos sequenciais que abrem um a um) e **Operacional** (manutenção, **travada** até a formação concluir). Concluir o último módulo → cão **Operacional** → destrava a aba.

**Mantém:** rastreador GPS (Parte 7/PROMPT_RASTREAMENTO_GPS), notificações/FCM, soft delete, auditoria.
**Princípio:** treino é **registro operacional, não documento selado** — **não** carimba hash de prova (alinhado à Parte 4_1). O selo é exclusivo da ocorrência.

## 13.1 — Conceitos
- **Currículo** (`training_program`): **institucional único**, por modalidade, **versionado**. Cadastrado no **painel web** por instrutor/adestrador; o mobile só **consome**.
- **Módulo:** etapa sequencial; tem ordem, nome, descrição e marcos.
- **Marco:** critério do módulo; **obrigatório** ou **opcional**. É **guia**, não cadeado — quem decide a evolução é o instrutor.
- **Sessão:** registro de um treino (com rastreador quando aplicável).
- **Progressão do cão:** módulo atual + módulos concluídos (cada um um **snapshot imutável**).
- **Promoção:** condutor **solicita**; instrutor **avaliza**.
- **Marco-bônus:** marco adicionado ao currículo depois de o cão já estar formado — oferta **opcional**, **aditiva**, nunca rebaixa.

## 13.2 — Fluxos
**Formação:** módulo atual → N sessões livres (sem trava por número) → condutor marca marcos → **solicita evolução** → instrutor **aprova** (conclui módulo, congela snapshot, libera o próximo) **ou aponta o que faltou** (motivo obrigatório, volta ao condutor como orientação). Se quem conduz já é instrutor/adestrador, **conclui direto**. Último módulo concluído → `operational`.
**Operacional:** manutenção — sessões de reforço, recomendação de frequência. Sem módulos a abrir.
**Marco-bônus:** currículo ganha marco novo → cães já formados recebem notificação de **fase bônus** opcional → ao completar, entra como **camada aditiva** datada (não altera o snapshot original, soma a ele).

## 13.3 — Modelo de dados
**Currículo (configurável no web):**
- `training_programs/{modality}` — `name`, `modality` (deteccao|busca_captura|guarda_protecao), `version`, `active`, `updated_by`, `updated_at`.
- `…/modules/{moduleId}` — `order`, `name`, `description`, `active`.
- `…/modules/{moduleId}/milestones/{milestoneId}` — `order`, `label`, `required` (bool), `active`.

**Progressão do cão:**
- `dogs/{dogId}/training/{modality}` — `status` (in_formation|operational), `current_module_id`, `program_version`, `operational_since?`.
- `…/completed_modules/{moduleId}` *(imutável)* — `module_name`, `completed_at`, `requested_by` (RA), `approved_by` (RA), `program_version`, `milestones_snapshot[]` {label, required, achieved}, `session_count`, `observation?`.
- `…/bonus_milestones/{milestoneId}` *(aditivo)* — `label`, `completed_at`, `by`, `program_version`.
- `…/promotion_requests/{reqId}` — `module_id`, `requested_by`, `requested_at`, `status` (pending|approved|rejected), `decided_by?`, `decided_at?`, `decision_reason?` (**obrigatório se rejected**), `marks_snapshot[]`.

**Sessão de treino:**
- `dogs/{dogId}/training_sessions/{sessionId}` — `modality`, `phase` (formation|maintenance), `module_id?`, `milestone_id?`, `conductor` (RA), `date`, `result` (completa|parcial|sem_exito), `observation?`, e quando rastreador: `track` {distance_m, duration_s, events[] (cao_indicou|checagem|perdeu_rastro|alvo_encontrado), path?, offline_synced}.

## 13.4 — Rastreador (ferramenta de sessão)
Reusar o GPS existente. Três estados: **antes** (verificação GPS/bateria/conexão + config: marco, figurante, objeto, ambiente, orientador) · **ao vivo** (mapa em tempo real, distância/tempo, **botões de evento**: cão indicou / checagem / perdeu rastro / alvo encontrado / encerrar) · **resumo** (resultado + vínculo ao marco/módulo). **Offline:** grava local e sincroniza. A mesma ferramenta serve formação **e** manutenção.

## 13.5 — Painel web (admin de currículo) + papéis
- O **CRUD do currículo** (modalidades, módulos, marcos, ordem, obrigatório/opcional, versão) é do **painel web**, restrito a **instrutor/adestrador**. *(escopo do projeto web; no mobile, semear um currículo inicial e apenas consumir.)*
- **Promoção:** condutor (qualquer membro) **solicita**; **instrutor/adestrador** aprova/reprova; quem aprova fica **registrado**.

## 13.6 — Integridade & histórico
- A conclusão de módulo **congela** o snapshot dos marcos da versão vigente (label, required, achieved) + quem conduziu + quem avalizou + quando + versão. **Imutável**; correção só com trilha, nunca apaga.
- Marco-bônus é **aditivo e datado**; não altera snapshots anteriores.
- Treino **não** gera selo de prova. Remover qualquer carimbo de hash imutável das telas de treino (corrige divergência apontada na validação).

## 13.7 — Notificações (tipos novos)
`training_promotion_requested` (→ instrutores) · `training_promotion_approved` (→ condutor) · `training_promotion_rejected` (→ condutor, com o que faltou) · `training_bonus_milestone_available` (→ condutores de cães formados). Acionáveis + deep link, sobre o FCM já existente.

## 13.8 — Firestore rules / servidor
- `training_programs/**`: leitura autenticada; **escrita só instrutor/adestrador**.
- `promotion_requests`: `create` por membro (próprio RA); `approve/reject` só instrutor; **reject exige `decision_reason`**.
- A **aprovação roda em Cloud Function** (transição sensível no servidor): monta o `completed_modules` (snapshot), avança `current_module`, e — no último módulo — seta `operational`. Garante snapshot íntegro e imutabilidade.
- `completed_modules`: imutável após criado.

## 13.9 — Critério de pronto
1. Modalidade abre nas abas **Formação / Operacional**; Operacional **travada** até formar.
2. Módulos abrem **sequencialmente**; marcos vêm do **currículo (Firebase)**.
3. Sessão registrável; **rastreador** funcionando (antes/ao vivo/resumo) com botões de evento e offline.
4. Condutor **solicita evolução**; instrutor **aprova ou aponta o que faltou** (motivo obrigatório); instrutor conclui direto.
5. Conclusão **congela snapshot**; último módulo → **operacional** → destrava manutenção.
6. **Marco-bônus** notifica cão formado; completar é **aditivo** e não rebaixa.
7. Aprovação via **Function**; rules barram escrita de currículo por não-instrutor e reject sem motivo.
8. Treino **sem** carimbo de hash de prova.

## 13.10 — Etapas de implementação
1. **Diagnóstico** (não codar): como a detecção faz hoje (reaproveitar), estado do rastreador/GPS, como treinos/sessões são modelados, papéis (instrutor/adestrador) e claims, e se há base de painel web.
2. **Currículo:** estrutura `training_programs` + **seed** do currículo de B&C (e detecção/G&P) no Firebase; mobile consome.
3. **Padrão Formação/Operacional** (abas, módulos sequenciais, marcos do currículo) — aplicar a **B&C primeiro**.
4. **Sessão + rastreador** (3 estados, eventos, offline) ligada a marco/módulo.
5. **Promoção co-validada:** solicitar → notificação → aprovar/apontar (Function + rules).
6. **Marco-bônus** (notificação + registro aditivo).
7. **Snapshot/imutabilidade/auditoria** + remover hash de prova das telas de treino.
8. Depois de B&C validado no celular: avaliar migrar **detecção** e **G&P** ao mesmo componente.
