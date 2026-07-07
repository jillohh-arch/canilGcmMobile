# Sessão 2026-07-07 — Multi-membro: 4 correções do teste com 2 usuários reais

## Contexto

Teste real com segundo usuário (Silva) revelou 4 problemas no fluxo multi-membro.
Decisões de negócio tomadas previamente:
- Turno SEM K9 permitido (motorista/apoio)
- Troca de K9: qualquer cão operacional livre (não só titular)
- Sistema de convites: REMOVER por completo

---

## Entrega 1 — Morte do sistema de convites

**Problema:** Silva não conseguia assumir posto vago por "não ter convite".

**Solução:** Remoção completa do sistema de convites. Posto vago + autenticado = pode assumir.

**Arquivos alterados:**
- `lib/features/shifts/data/shift_service.dart`
  - `_validateRoleIsFree`: removido `'pending'` do filtro (só `'active'`)
  - `_crewHasOtherActiveMembers`: idem
  - `_upsertCrewInBatch`: removido campo `responded_at` dos writes
- `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart`
  - Removido: import `VehicleCrewTransitionService`, campo `_transitionService`, `_submitting`
  - Removido: `reservedCount`, `currentMember`, `isTitular` para convites
  - Removido: `_showInviteDialog`, `_respondToInvitation`, `_declineInvitation`, `_cancelInvitation`
  - Removido: widgets `_InvitationResponseCard`, `_AvailableHandlersSheet`
  - Simplificado: `_MemberCard` sem badges CONVITE ENVIADO/RECUSADO
- `lib/features/occurrences/presentation/screens/pending_screen.dart`
  - Removido: import e instância de `VehicleCrewTransitionService`
  - Removido: `_respondToCrewInvitation`, `_declineCrewInvitation`, `_askDeclineReason`
  - Removido: `onAccept`/`onDecline` do `_NotificationCard`
  - Simplificado: `_hasInlineActions` e `_buildInlineActions`
- `lib/core/services/push_notification_service.dart`
  - Removido: import `VehicleCrewTransitionService`
  - Removido: constantes `_crewAcceptActionId`, `_crewDeclineActionId`
  - Removido: `handleBackgroundNotificationResponse` handlers de convite
  - Removido: `_handleCrewAction`, `_respondToCrewInvitation`, `_handleBackgroundCrewAction`
  - Removido: `_markNotificationAsRead`, `_markNotificationAsReadFromPayload`
  - Removido: `_showActionResultNotification`
  - Removido: actions Android/iOS na notificação de convite
  - Removido: `darwinDetails` do category `vehicle_crew_invitation`

**Nota:** `VehicleCrewTransitionService` (arquivo) continua existindo mas é dead code.
Cloud Functions (`inviteVehicleCrewMember`, `respondVehicleCrewInvitation`,
`cancelVehicleCrewInvitation`) continuam no backend — não geram custo se não chamadas.
O campo `responded_at`/`decline_reason` continua no hasOnly das rules (permissivo para
docs antigos).

---

## Entrega 2 — Turno sem K9

**Problema:** `isValidActiveShiftFor` exigia `dogId.size() > 0`, bloqueando turno sem cão.

**Solução:** Rules aceita dogId vazio + Dart/UI com opção "Iniciar sem K9".

**Arquivos alterados:**
- `firestore.rules` (⚠️ DEPLOY COORDENADO COM APK)
  - `isValidActiveShiftFor`: removido `&& request.resource.data.dogId.size() > 0`
  - `isValidShiftLogCreate`: já aceitava string vazia (sem mudança)
- `lib/features/shifts/data/shift_service.dart`
  - `startShift`: `dogId` agora tem default `''` (não mais `required`)
  - `_validateVehicleCanBeAssumed`: conflito K9 só aplica se `serviceDogId.isNotEmpty`
- `lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart`
  - `startShift`: aceita dogId vazio, `serviceDogId` null quando vazio
- `lib/features/shifts/domain/active_shift_session.dart`
  - `isActive`: removido requisito `effectiveServiceDogId.isNotEmpty`
  - Adicionado: `bool get hasK9`
- `lib/features/shifts/presentation/screens/shift_assumption_screen.dart`
  - Estado: `_noK9Selected`, `_startingWithoutK9`
  - Método: `_startShiftWithoutK9()` (envia dogId vazio)
  - ListView: +1 item com `_NoK9SelectionCard`
  - CTA: mostra `_NoK9Cta` quando selecionado sem cão
- `lib/features/shifts/presentation/screens/shift_assumption_dog_card_widgets.dart`
  - Novo: widget `_NoK9SelectionCard`
  - Novo: widget `_NoK9Cta`
- `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`
  - Import: `cloud_firestore`
  - `dogId` vazio agora mostra `_buildNoK9Body` (condutor solo) em vez de `_MissingShiftDogState`
  - Novo: método `_buildNoK9Body` com header simplificado + guarnição se embarcado
- `lib/features/shifts/presentation/screens/active_shift_profile_cards.dart`
  - `_GuarnicaoFaixa.dog`: `Dog` → `Dog?`
  - `_GuarnicaoEmbarcada.dog`: `Dog` → `Dog?`
  - `_VehicleGrid.dog`: `Dog` → `Dog?`
  - `_K9Card.dog`: `Dog` → `Dog?` (com null-check no build)

**Confronto payload × rules:**
- `active_shifts`: `dogId: ''` passa `is string` ✅
- `shift_logs`: `initialDogId: ''`, `currentDogId: ''` passam `is string` ✅
- `members`: `dog_id: ''` na whitelist sem validação de tamanho ✅

---

## Entrega 3 — Troca de K9: qualquer cão operacional livre

**Problema:** Gate UI `titularDogs.length <= 1` bloqueava o switcher.

**Solução:** Removido gate de titularidade. Novo filtro: status Ativo + não embarcado.

**Arquivos alterados:**
- `lib/features/shifts/presentation/screens/active_shift_dog_switcher.dart`
  - Reescrito: removido `isTitularOfSingleDog` e card de warning "Condutor Titular Único"
  - Novo: widget `_AvailableDogsLoader` (StatefulWidget)
    - `_fetchDogsInUse()`: consulta `active_shifts` com `status == 'active'`
    - Filtro: `status == 'Ativo'` + `d.id != activeDogId` + `!dogsInUse.contains(d.id)`
    - Ordenação: titular do usuário primeiro, depois alphabético
  - `_DogSwitchTile`: novo campo `isOwnDog` (visual)
- `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`
  - Import `cloud_firestore` (já adicionado na Entrega 2)

---

## Entrega 4 — Card unificado real-time em todos os aparelhos

**Problema:** `VehicleCrewService()` instanciado inline no `build()` causava nova
referência de stream a cada rebuild → StreamBuilder resetava.

**Solução:** Stream cacheado no State — só recria se crewId mudar.

**Arquivos alterados:**
- `lib/features/shifts/presentation/screens/active_shift_profile_cards.dart`
  - `_GuarnicaoEmbarcadaState`:
    - Novo campo: `final _crewService = VehicleCrewService()`
    - Novo campo: `String? _crewId` + `Stream<List<VehicleCrewMember>>? _membersStream`
    - No `build()`: cache do stream com `if (_crewId != crewId)` guard
    - `FutureBuilder` do status também usa `_crewService` (mesma instância)

---

## Ordem de deploy

1. **Rules primeiro** — seguro, nenhum APK antigo envia `dogId: ''`
2. **APK depois** — novos fluxos passam a funcionar

---

## Commit

```
6a266d8 feat: multi-membro — 4 correções do teste com 2 usuários reais
```

12 files changed, +567 −944 lines.
