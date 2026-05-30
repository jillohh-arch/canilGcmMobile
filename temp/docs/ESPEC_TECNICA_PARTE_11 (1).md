# ESPECIFICAÇÃO TÉCNICA — PARTE 11 (v4)
# Equipe por viatura · guarnição por convite · aceite e assinatura
### REVISA o modelo de equipe da PARTE 10

> **⚠️ LEIA ANTES DA PARTE 10.** Substitui a formação de equipe por autocomplete (Parte 10) pelo modelo de **guarnição por viatura, montada por convite+aceite no turno**. **Mantém** da Parte 10 (adaptar, não reimplementar): biometria/senha, `hash_version: 3` (team+signatures), bloqueio de edição pós-selo, aditamento restrito no servidor, PDF, Firestore rules.
>
> Mockups de referência: `turno_dashboard_equipe.html` (3 cards + perfil da equipe + convite), `ocorrencia_telas_novas.html`, `ocorrencia_fluxo_completo_v2.html`.

---

## 11.1 — Decisões confirmadas
1. **A equipe vive no turno.** Gerida na tela de turno via **3 cards simétricos** (cão, condutor, equipe), cada um levando ao seu perfil. A ocorrência apenas **referencia** a equipe.
2. **Guarnição por convite + aceite.** Um condutor da viatura adiciona parceiros (entre os de plantão, não alocados em outra viatura); cada um recebe notificação e **aceita** para entrar. Mesmo padrão de UX da ocorrência.
3. **Só condutores.** Equipe é lista de condutores.
4. **Um cão de serviço por turno.** Escolha livre, operável por qualquer condutor, **trocável durante o turno** (ex: lesão) sem encerrar o plantão — auditado. Gerido no perfil da equipe.
5. **Capacidade do cadastro manda.** `crew_size` da viatura limita os condutores; cheia → não aceita novos convites.
6. **Viatura opcional** no turno (treino sem viatura, assumir depois). Preparado p/ multi-cidade (`unit`).
7. **Dois consentimentos:**
   - **Guarnição (turno):** aceite forte, 1x, ao ser convidado — define quem roda junto.
   - **Ocorrência:** como já é da guarnição (indivisível), o integrante é **incluído automaticamente** e notificado; age só para **recusar com justificativa** (ausência rara — ex.: saiu para consulta médica). *[premissa — confirmar; alternativa: aceite ativo também na ocorrência]*
8. **Edição colaborativa:** enquanto a ocorrência está `open`, qualquer condutor da guarnição pode editar (auditado: quem mudou o quê).
9. **Assinatura com revisão:** ao ser chamado a assinar, o condutor **revisa até o fechamento** e então **concorda e assina** OU **devolve para correção**.
10. **Devolver para correção:** reabre a ocorrência; **invalida as assinaturas coletadas** (o conteúdo vai mudar, histórico preservado); corrige → re-finaliza → re-assina. **Antes do selo, erro se corrige no registro; depois do selo, só por aditamento.**
11. **Notificação de turno > 12h** sugerindo encerrar (não fecha sozinho).

## 11.2 — Entidades
- **Viatura** `vehicles/{id}`: `name`, `prefix`, `model`, `crew_size` (condutores; cão +1), `unit`, `active`.
- **Cão**: campo `matricula`.
- **Turno** `shifts/{id}`: `handler_id`, `vehicle_id` (opcional; null=treino), `service_dog_id` (1), `started_at`.
- **Guarnição** (membros da viatura no turno): vínculo condutor↔viatura com `status: titular|invited|accepted|declined`, `decline_reason?`. Derivar quem é a guarnição ativa dos vínculos `titular|accepted`.
- **Ocorrência**: `vehicle_id`/`vehicle_label`; `team` (snapshot: condutores + 1 cão; um `relator`, demais `integrante`); `participations` por integrante `{handler_id, status: included|declined, decline_reason?, at}`; `signatures` (Parte 10), invalidáveis na devolução com histórico.

## 11.3 — Tela de turno (a equipe vive aqui)
- **3 cards** no dashboard: **Cão** → perfil do cão; **Condutor** → perfil do condutor; **Equipe** → perfil da guarnição.
- **Perfil da equipe:** viatura (capacidade, cão de serviço), lista de condutores com estado (você / na equipe / convite enviado), botão **adicionar parceiro** e trocar cão de serviço.
- **Adicionar parceiro:** lista de condutores de plantão (não em outra viatura) → convidar → ele aceita (notificação) → entra. Respeita `crew_size`.

## 11.4 — Estados da ocorrência
`open` (editável pela guarnição) → `awaiting_signatures` (travada, em revisão/assinatura) → [devolução → volta a `open`, assinaturas invalidadas] → `finalized` (todos assinaram; selo v3; só aditamento) · `finalized_with_pending` (prazo 48h vencido).

## 11.5 — Fluxo de consentimento
**Turno:** convite de guarnição → FCM → aceite (entra na equipe).
**Abertura da ocorrência:** guarnição incluída automaticamente (`participations: included`) → FCM informa → integrante pode **recusar com justificativa**.
**Em andamento:** guarnição edita (colaborativo, auditado).
**Finalização:** `awaiting_signatures` → FCM "Assinatura necessária" abre na **revisão** → **assina** (biometria/senha) ou **devolve** (motivo).
**Devolução:** reabre, invalida assinaturas (histórico), corrige, re-finaliza, re-assina.
**Selo:** todos assinaram → `finalized`, `hash_version: 3` (team + signatures).

## 11.6 — Cão de serviço
Um por turno; membro pleno (matrícula, nomeado, "presença atestada"); não assina; trabalho creditável a ele nas ações; trocável no turno (auditado). Ocorrências já abertas mantêm o cão do snapshot.

## 11.7 — Notificações (FCM — infra nova)
Notificar **outro dispositivo** (convite de guarnição, abertura, assinatura) exige **Firebase Cloud Messaging** — hoje só há `flutter_local_notifications` (próprio aparelho). Notificações **acionáveis** (botões aceitar/recusar) + deep link para a tela certa.

## 11.8 — Critério de pronto
1. `vehicles` cadastrável; `matricula` no cão; viatura opcional no turno; troca de cão (auditada); notificação 12h.
2. Dashboard com **3 cards**; **perfil da equipe** gere a guarnição.
3. Guarnição por **convite + aceite**, respeitando `crew_size`; lista só condutores de plantão livres.
4. Ocorrência captura `team` (snapshot: condutores + 1 cão); guarnição incluída automaticamente; **recusa justificada** auditada.
5. **Edição colaborativa** auditada; **FCM** disparando convites/aberturas/assinaturas acionáveis.
6. Finalização → revisão → assinar **ou devolver para correção** (reabre + invalida assinaturas com histórico).
7. Selo v3 (team + signatures) sem quebrar selos existentes; pós-selo só por aditamento (servidor).
8. Infra da Parte 10 segue funcionando com o novo `team`.
