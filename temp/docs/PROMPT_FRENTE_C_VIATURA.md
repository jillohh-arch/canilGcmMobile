# PROMPT — Frente C (v4): equipe por viatura, guarnição por convite, aceite e assinatura
### Colar no Claude Code

Vamos implementar a Frente C: a equipe sai da ocorrência e vai pro **turno** (3 cards no dashboard + perfil da equipe), a guarnição é montada por **convite + aceite**, e a ocorrência ganha **inclusão automática + recusa justificada**, **edição colaborativa** e **assinatura com devolver-para-correção**. Leia `temp/docs/ESPEC_TECNICA_PARTE_11.md` (v4) e mantenha a Parte 10 como base de assinatura. Mockups: `turno_dashboard_equipe.html`, `ocorrencia_telas_novas.html`, `ocorrencia_fluxo_completo_v2.html`. Skills: `canil-k9-context`, `firestore-coexistence`, `audit-trail`.

**Princípio:** "se um gestor questionar o trabalho do condutor 6 meses depois, esse registro o defende?". Auditável, soft delete, nada hardcoded. "Build passou" ≠ validado: cada etapa é testada no celular.

---

## ANTES DE CODAR — diagnóstico (não altere nada; reporte arquivo:linha e ESPERE meu aval)
1. Como o **turno** e o **dashboard** são modelados? Onde entram `vehicle_id` e `service_dog_id`? Onde está o card/resumo do cão hoje?
2. O `team` da ocorrência é populado por autocomplete (`handler_search_dialog`)? Confirme que é o que entra no `hash_version: 3`.
3. Existe **FCM**? (a auditoria indicou só `flutter_local_notifications`). Convite/abertura/assinatura entre dispositivos exigem FCM — reporte o que falta.
4. As `signatures`, pendências e rules da Parte 10 estão prontas? (sim, pela validação) — **não reimplementar**, adaptar.
5. Proponha como modelar a **guarnição por convite** (vínculo condutor↔viatura com status) e a **devolução** (reabrir + invalidar assinaturas) nos estados atuais.

---

## IMPLEMENTAÇÃO — etapas, cada uma validada no celular

### Etapa 1 — Viatura + cão de serviço + troca no turno
- `vehicles/{id}` (name, prefix, model, crew_size, unit, active); `matricula` no cão.
- Turno: `vehicle_id` (opcional — "só com o cão/treino") + `service_dog_id` (1 cão, escolha livre); **trocar o cão no meio do turno** sem encerrar (auditado); notificação > 12h.
- **Validar:** cadastrar Canil 1075; abrir turno com/sem viatura; trocar cão; ver 12h.

### Etapa 2 — Dashboard (3 cards) + perfil da equipe + guarnição por convite
- Dashboard: **3 cards** (cão, condutor, equipe), cada um abre seu perfil. (espelhar `turno_dashboard_equipe.html`)
- **Perfil da equipe:** viatura, cão de serviço, lista de condutores com estado; **adicionar parceiro** (lista de plantonistas livres) → convite.
- Guarnição por **convite + aceite**, respeitando `crew_size` (cheia bloqueia).
- **Validar no celular:** convidar parceiro → ele aparece como pendente → (após FCH na Etapa 3, aceita e entra); capacidade respeitada.

### Etapa 3 — FCM (push entre dispositivos)
- Integrar **Firebase Cloud Messaging**; notificações **acionáveis** (botões) + deep link.
- Liga os convites de guarnição (Etapa 2), as aberturas (Etapa 4) e as assinaturas (Etapa 6).
- **Validar:** convite de guarnição chega no cel do parceiro; ele aceita pela notificação e entra na guarnição.

### Etapa 4 — Ocorrência herda a guarnição + recusa
- Criar ocorrência captura **snapshot** da guarnição → `team` (condutores + 1 cão); remover o "+ Definir equipe" / autocomplete da ocorrência.
- Guarnição **incluída automaticamente** (`participations: included`); FCM informa; integrante pode **recusar com justificativa** (ausência, auditada). *(se preferir aceite ativo na ocorrência, me avise)*
- **Validar:** ocorrência nasce com a guarnição; um integrante recusa com motivo e a recusa fica registrada.

### Etapa 5 — Edição colaborativa
- Enquanto `open`, qualquer condutor da guarnição (não recusado) edita; cada alteração no `audit_trail`.
- **Validar:** dois condutores editam a mesma ocorrência; auditoria registra ambos.

### Etapa 6 — Finalização → revisão → assinatura / devolução
- Finalizar → `awaiting_signatures` (travada) → FCM "Assinatura necessária" abre na **revisão**.
- Revisão até o fechamento → **Concordar e assinar** (biometria/senha, Parte 10) ou **Devolver para correção** (motivo).
- **Devolver:** reabre (`open`); **invalida** assinaturas coletadas (histórico/audit preservado); corrige; re-finaliza; re-assina.
- **Validar no celular:** relator assina; parceiro **devolve** (caso da moto) → reabre → adiciona a moto → re-finaliza → ambos re-assinam → sela.

### Etapa 7 — Selo v3 + aditamento + rules
- Confirmar `hash_version: 3` com o novo `team` (condutores + 1 cão) + `signatures`, **sem quebrar** selos v3 existentes (versionar se preciso).
- Rules: `participations`, guarnição por convite, edição por membro em `open`, devolução, bloqueio pós-selo, aditamento só por relator + assinados.
- **Validar (servidor):** forçar por fora do app — assinar como recusado/não-membro, editar em `awaiting_signatures`, aditar sem assinar — Firestore **recusa**.

---

## REGRAS DO PROJETO
- Branch; `main` buildável; merge `--no-ff` por etapa validada no celular.
- Reuso de componentes; nada hardcoded; tudo auditável.
- **Não reimplementar** assinatura/hash/notif-local/rules da Parte 10 — adaptar.
- **FCM** é pré-requisito do convite (E2), abertura (E4) e assinatura (E6).
- **Hash:** `team` mudou de forma; confirme compatibilidade do v3 sem quebrar selos existentes.

> **Prioridade do projeto:** o **verificador de selo** (recalcular + comparar por versão) continua pendente e é mais crítico que esta frente — sem ele, a integridade é decorativa. Alinhar a ordem com o Jilles antes de pôr a co-assinatura em produção.
