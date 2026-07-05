# SESSAO 2026-07-03 — GUARNIÇÃO PARTE 2 + K9 COMO VÍNCULO

## Entregas implementadas

### ENTREGA 1 — Simplificação do shift_assumption_screen
- Remoção da seção de veículo do shift_assumption_screen
- Fluxo: seleção de cão → "INICIAR TURNO"
- Dog card com status (disponível/ocupado) e badge

### ENTREGA 2 — Fluxo de Assunção de Veículo com Post Board
- Novo arquivo: `vehicle_crew_post_sheet.dart`
- Fluxo em 2 etapas: seleção de veículo → post board
- **Post board: 4 postos (MOT / ENC / AUX1 / AUX2) + LINHA K9 separada**
- K9 como vínculo, não como posto — aparece como linha destacada
- Badge K9 nos slots cujo membro tem `dog_id` preenchido
- Linha K9 mostra: ícone cão, nome do cão, "condutor: [nome]"

### ENTREGA 3 — Dashboard com Cards Separados
- Card Binômio: sem slot de veículo, exibe foto/animal + dados + badge K9
- Card Guarnição: mini-post-board (4 slots + linha K9)
- Remoção do campo `patrulhable` redundante (dados já em `service_dog_id`)

### ENTREGA 4 — Encerramentos com Confirmação
- Confirmação menciona posto e veículo do membro
- `endShift` fecha crew + limpa `service_dog_id` do doc pai
- `leaveVehicle` remove cão do member + limpa `service_dog_id` do doc pai

## Alterações no Modelo K9

### Conceito central: K9 = VÍNCULO (não posto)
- K9 **não é um posto** — é um vínculo
- Qualquer função humana (MOT/ENC/AUX1/AUX2) pode ser condutor de cão
- Badge "K9" aparece ao lado do slot do membro com cão
- 1 cão máximo por guarnição

### Campo `service_dog_id` no documento pai
- Campo `service_dog_id` em `vehicle_crews/{crewId}` — persiste entre ciclos
- Usado para: validação 1 cão, badge K9 no post board, linha K9
- Limpeza obrigatória: `FieldValue.delete()` ao fechar crew ou sair

## Bug corrigido: False-positive na validação 1 cão

### Problema
Ao reutilizar um doc de crew encerrada, `service_dog_id` ainda continha o ID do cão anterior. A validação lia esse campo stale e bloqueava errôneamente ("Guarnição já possui K9 embarcado") mesmo em crews vazias.

### Solução em 2 frentes
1. **Validação com guarda `active == true`:** só valida se a crew está ativa
2. **Limpeza do campo em todas as saídas:**
   - `leaveVehicle`: limpa `service_dog_id` do doc pai se quem sai era o condutor
   - `endShift` / `closeCrew`: limpa `service_dog_id` ao encerrar

### Código da validação (shift_service.dart)
```dart
if (activeDogId.isNotEmpty) {
  final crewDocSnap = await transaction.get(_vehicleCrews.doc(crewId));
  final crewData = crewDocSnap.data();
  final isCrewActive = crewData?['active'] == true;
  if (isCrewActive) {
    final crewDogId = crewData?['service_dog_id']?.toString().trim();
    if (crewDogId != null && crewDogId.isNotEmpty) {
      throw StateError('Guarnição já possui K9 embarcado...');
    }
  }
}
```

## Arquivos alterados

| Arquivo | Mudanças |
|---------|---------|
| `lib/features/shifts/data/shift_service.dart` | Validação 1 cão com guarda `active`, `service_dog_id` cleanup em `leaveVehicle` e `endShift` |
| `lib/features/shifts/presentation/screens/vehicle_crew_post_sheet.dart` | Sheet com fluxo 2 etapas, 4 postos + linha K9, badge K9 |
| `lib/features/shifts/presentation/screens/active_shift_profile_cards.dart` | Badge K9 nos slots, `_MiniK9Line` no mini-post-board, remoção do 5º posto |

## Commit
```
feat(shifts): K9 como vinculo — quadro 4 postos, badge, validacao 1 cao

- Quadro de postos: 4 slots (MOT/ENC/AUX1/AUX2) + linha K9 separada
- Badge K9 nos slots cujo member tem dog_id preenchido
- Linha K9 no quadro completo e mini-quadro do dashboard
- Validação 1 cão: rejeita se crew ativa já tem service_dog_id
- LeaveVehicle: limpa service_dog_id do doc pai ao sair
- EndShift closeCrew: limpa service_dog_id ao fechar guarnição
- Correção false-positive em validacao 1 cão (crew encerrada = ignore)
```
