# PROMPT — Padrão unificado de treinamento (Parte 13)
### Colar no Claude Code

Vamos implementar o **padrão de treino Formação/Operacional** para as modalidades de treino, começando por **Busca & Captura** (a que está sem lógica hoje). Leia `temp/docs/ESPEC_TECNICA_PARTE_13.md` e use a **detecção (Parte 4_1) como referência que já funciona** — **não reimplemente a detecção**. Mockups: `treino_v2_sessao_e_promocao.html`, `padrao_treino_formacao_operacional.html`. Skills: `canil-k9-context`, `firestore-coexistence`, `audit-trail`.

**Princípio:** "se um gestor questionar a formação do cão 6 meses depois, o registro a defende?". Treino é **registro operacional, não documento selado** — **sem carimbo de hash de prova**. Auditável, soft delete, nada hardcoded. "Build passou" ≠ validado: cada etapa testada no celular.

---

## ANTES DE CODAR — diagnóstico (não altere nada; reporte arquivo:linha e ESPERE meu aval)
1. Como a **detecção** modela formação/fases hoje (o que dá pra generalizar)? Onde está o estado de progressão?
2. Estado do **rastreador/GPS**: o que existe (ver PROMPT_RASTREAMENTO_GPS), funciona offline, registra trajeto/eventos?
3. Como **treinos/sessões** são gravados hoje? Há telas de treino que **carimbam hash** como se fosse ocorrência? (corrigir — Parte 4_1)
4. Existe papel **instrutor/adestrador** (claims/roles)? Como as rules identificam isso?
5. Há qualquer base de **painel web** ou o currículo precisa ser **semeado** no Firebase por enquanto?

---

## IMPLEMENTAÇÃO — etapas, cada uma validada no celular

### Etapa 1 — Currículo no Firebase (consumo + seed)
- Criar `training_programs/{modality}` + `modules` + `milestones` (Parte 13.3).
- **Semear** o currículo de Busca & Captura (3 módulos com os marcos do mockup) — o CRUD admin é do painel web (escopo futuro).
- Mobile **lê** o currículo; nada de marcos hardcoded.
- **Validar:** app mostra os módulos/marcos vindos do Firebase; editar o doc no console reflete no app.

### Etapa 2 — Padrão Formação/Operacional (B&C)
- Duas abas **Formação | Operacional**; Operacional **travada** até formar.
- Formação: módulos **sequenciais** (só o atual aberto; próximos 🔒); marcos do currículo; "Nova sessão" e "Solicitar evolução".
- **Validar:** Thor em formação mostra Módulo 2 aberto, 3 travado; Bono operacional mostra manutenção.

### Etapa 3 — Sessão + rastreador
- Reusar o GPS. Três estados: antes (verificação + config) · ao vivo (mapa, distância/tempo, **eventos**: cão indicou/checagem/perdeu rastro/alvo encontrado/encerrar) · resumo (resultado + vínculo a marco/módulo). **Offline** grava local e sincroniza.
- **Validar no celular real (em campo se possível):** trilha grava trajeto, marca eventos, salva offline e sincroniza; sessão fica vinculada ao módulo.

### Etapa 4 — Promoção co-validada
- Condutor **solicita evolução** (`promotion_requests`, status `pending`) → notificação ao(s) instrutor(es).
- Instrutor **aprova** ou **aponta o que faltou** (`decision_reason` obrigatório no reject; volta ao condutor).
- Se quem conduz já é instrutor/adestrador, **conclui direto**.
- **A aprovação roda em Cloud Function:** monta o `completed_modules` (snapshot dos marcos da versão), avança `current_module`, e no último módulo seta `operational`.
- **Validar:** condutor solicita no cel A; instrutor aprova no cel B; módulo conclui, snapshot gravado, próximo libera. Testar também o reject com motivo.

### Etapa 5 — Marco-bônus
- Currículo ganha marco novo → notificar cães já formados (`training_bonus_milestone_available`).
- Completar grava `bonus_milestones` (aditivo, datado) **sem** rebaixar o status operacional nem alterar snapshots.
- **Validar:** adicionar marco ao currículo; cão formado recebe oferta; completar soma ao histórico sem virar "em formação".

### Etapa 6 — Integridade do histórico + limpeza
- Garantir `completed_modules` **imutável** (correção só com trilha); auditoria de promoções e (quando vier do web) de edição de currículo.
- **Remover o carimbo de hash de prova** das telas/detalhes de treino (detecção/BC/G&P/obediência).

---

## REGRAS DO PROJETO
- Branch; `main` buildável; merge `--no-ff` por etapa validada no celular.
- Reuso de componentes (rastreador, FCM, notificações, padrão de aceite da ocorrência); nada hardcoded.
- Transições sensíveis (aprovar promoção) **no servidor** (Function), não no client.
- **Não reimplementar** a detecção; aplicar o padrão a B&C primeiro e, só depois de validado, avaliar unificar detecção e G&P.
- Currículo é **dado** (Firebase), nunca código.

> Não comece pela UI nem pule o diagnóstico. Reporte o diagnóstico e espere meu aval antes da Etapa 1.
