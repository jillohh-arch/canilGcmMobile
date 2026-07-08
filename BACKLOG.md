# BACKLOG — canil_gcm (mobile + web + rules)

> **Antes de propor trabalho novo, consultar este arquivo para pendências conhecidas.**
> Atualizado: 2026-07-06. Fonte única de pendências. Ao concluir um item,
> movê-lo para a seção ✅ com a data.

---

## 🔴 RULES PENDENTES
*(deploy sempre manual, sempre do repo mobile)*

### 1. FAXINA DOS LEGADOS
Coleções pt-BR sem rules: `alertas`, `atalhos_registro`, `registros`,
`documentos`, `vacinas`, `training_specialties`, `climaAtual`.

- **Fase 1:** auditoria de writes por coleção (payload real impresso no
  código, capturado no logcat durante uso real)
- **Fase 2:** rules baseadas na auditoria
- **Sintoma atual:** `permission-denied` em todo boot — degradado com log,
  features silenciosamente quebradas
- **Prompt:** já redigido na sessão de 06/07

### 2. HARDENING users/{ra}
`update` sem whitelist — o próprio RA pode escrever **QUALQUER** campo,
incluindo administrativos (`specialties`, `isK9Instructor`,
`access_profile*`, `accessLevel`) = **escalada de privilégio**.

- **Fix:** campos administrativos só via Cloud Function
  `adminUpsertHuman`; `update` direto do usuário restrito a campos de
  perfil pessoal (whitelist + `diff().affectedKeys()`)

### 3. REMOVER role 'titular' transitório
Remover do `create` E `update` de `vehicle_crews/members`, **APÓS**
rollout completo do APK na equipe (hoje o payload ainda pode enviar
`'titular'`).

### 4. ÍNDICE documentos (collectionGroup caoId + dataUpload)
Criar pelo link do erro no console (1 clique, FAILED_PRECONDITION no
logcat).

---

## 🟡 MOBILE

### 5. Teste multi-membro no plantão real (cenários restantes)
Cenários do `service_dog_id` condicional ainda não validados em campo:
- Condutor encerra turno → crew continua (re-atribuição?)
- Adesão de member legado + APK antigo convivendo
- ⚠️ Deploy rules (dogId vazio) coordenado com APK novo

### 6. Animações Fase 2
- Hero foto do cão (1 par: card → K9ProfilePage)
- `HudAnimatedCount`
- `TacticalButton` (5 críticos + ASSUMIR)
- **Prompt:** pronto na sessão de 06/07. Pré-requisito: nenhum (Fase 1 validada).

### 7. Limpezas menores
- Confirmar remoção do `debugPrint BATCH PAYLOAD` residual
- `'motorista'` hardcoded — morto na Parte 2, confirmar em grep
- `_CrewAvatar` residual após redesign de foto crachá (já removido — verificar)

---

## 🟡 WEB

### 8. Página Histórico de Guarnições
Query `vehicle_crew_history` paginada (`getDocs`, **sem** `onSnapshot`),
filtros viatura + data. Responde "quem era o motorista da viatura X no
dia Y".
- **Prompt:** pronto na sessão de 06/07

### 9. Animações Fase 2 web
- Contadores KPI (`rawValue` no `SummaryCardData`)
- Limpeza `--hud-pulse` duplicado
- Progress bar 500ms tokenizada

### 10. Validação pendente do EquipeCard
- Console sem `permission-denied` na subcoleção `members`
- Anti-re-disparo (log de assinatura)
- Tempo real sem F5

---

## 🟢 PRODUTO / ROADMAP

### 11. Capacitações no app
`specialties` disponíveis no `UserModel` abrem usos futuros:
- `Veterinário` destacado em registros de saúde
- `Condutor K9` nos slots da guarnição ✅ (implementado 06/07)

### 12. Foto real da viatura no card
Asset por viatura — cereja visual do card de viatura.

### 13. Tela de configuração de guarnição para admin
Editores de corporação configuram postos, obrigatórios, condicionais
diretamente na UI.

---

## ✅ CONCLUÍDO

| Data | Item | Resumo |
|---|---|---|
| 07/07 | Sincronização rules mobile↔web | Mobile eleito fonte canônica única. Portado `canUpdateDogDenormalizedStats` do web→mobile, copiado arquivo inteiro mobile→web. CLAUDE.md anotado em ambos. Deploy de rules SOMENTE do mobile. |
| 07/07 | Multi-membro: morte dos convites | Sistema de convites removido por completo (service, push, UI) — posto vago = pode assumir |
| 07/07 | Multi-membro: turno sem K9 | Rules aceita dogId vazio, UI com opção "Iniciar sem K9", dashboard condutor solo |
| 07/07 | Multi-membro: troca K9 livre | Filtro por status Ativo + não embarcado, sem gate de titularidade |
| 07/07 | Multi-membro: card real-time | Stream cacheado no State, zero re-subscribes — atualiza em todos os aparelhos |
| 06/07 | Rules da guarnição | `vehicle_crew_history`, `members`, 8 bugs de rules/payload |
| 06/07 | Card unificado EM SERVIÇO | Binômio + Guarnição, planta baixa da viatura |
| 06/07 | Quadro de postos | Slots ocupados/vagos, redesign com foto crachá |
| 06/07 | EquipeCard web | Subcoleção `members`, `leaveVehicle` |
| 06/07 | Animações Fase 1 | Tokens, stagger, `HudStatusDot` mobile + web |
| 06/07 | Badge CONDUTOR | `specialties.contains('Condutor K9')` no `UserModel` |
| 06/07 | Redesign slots | Foto retangular ~3:4, badges CONDUTOR/K9, K9 em cyan/teal |
