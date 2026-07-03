# Sessao de Debug — Turno e Colecoes Legadas

**Data:** 2026-07-02
**Objetivo:** Corrigir PERMISSION_DENIED na abertura de turno e investigar colecoes legadas sem rules

---

## Problema Inicial

Logcat em producao mostrava multiplos `PERMISSION_DENIED` em colecoes de nomenclatura antiga (portugues) durante o fluxo de turno. Sintomas:

1. `W/Firestore: Write failed at active_shifts/691755: PERMISSION_DENIED` na ABERTURA de turno
2. 4+ listeners falhando com `PERMISSION_DENIED` em `atalhos_registro`, `training_specialties`, `alertas`, `documentos`
3. `Unhandled Exception "A request for permissions is already running"` no PermissionHandler
4. Sucesso silencioso mesmo quando o turno falhava (fallback mascarava erros)

---

## Round 1 — Fix de Feedback de Erro (APK 20260702)

### Arquivos modificados

#### 1. `lib/features/profiles/presentation/screens/handler_profile_page.dart`

**Problema:** O metodo `_endShift` mostrava `AppFeedback.success` SEMPRE, mesmo quando `endShift` falhava. O `await shiftVM.endShift()` podia falhar mas a UI nunca sabia.

**Solucao:**
```dart
// ANTES:
await shiftVM.endShift();
AppFeedback.success(context, 'Expediente encerrado...');

// DEPOIS:
await shiftVM.endShift();
if (!context.mounted) return;
final error = shiftVM.error;
if (error != null && error.trim().isNotEmpty) {
  AppFeedback.error(context, error);
} else {
  AppFeedback.success(context, 'Expediente encerrado...');
}
```

---

#### 2. `lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart`

**Problema:** Todos os `catch (e)` nos metodos `startShift`, `switchDog`, `assumeVehicle`, `endShift`, `watchActiveShift` logavam `'$e'` sem contexto de tipo de erro. `FirebaseException` (que tem `.code` como `permission-denied`, `aborted`, `unavailable`) era convertido em string generica.

**Solucao:** Adicionado `on FirebaseException catch (e)` separado em cada metodo, com mensagem incluindo o codigo:

```dart
// Exemplo em startShift:
} on FirebaseException catch (e) {
  _error = 'Falha ao sincronizar turno [${e.code}]: ${e.message}';
  notifyListeners();
} catch (e) {
  _error = 'Falha ao sincronizar turno: $e';
  notifyListeners();
}
```

Metodos afetados:
- `startShift` — "Falha ao sincronizar turno [${e.code}]: ..."
- `switchDog` — "Falha ao sincronizar troca de K9 [${e.code}]: ..."
- `assumeVehicle` — "Falha ao assumir viatura [${e.code}]: ..."
- `endShift` — "Falha ao encerrar turno [${e.code}]: ..."
- `watchActiveShift` onError — "Falha ao carregar turno ativo [${e.code}]: ..."

---

#### 3. `lib/features/shifts/presentation/screens/active_shift_dog_switcher.dart`

**Problema:** `switchDog` era chamado sem verificar se houve erro. Se falhasse, a UI nao mostrava nada.

**Solucao:**
```dart
await shiftVM.switchDog(dog.id);
if (!ctx.mounted) return;
final error = shiftVM.error;
if (error != null && error.trim().isNotEmpty) {
  AppFeedback.error(ctx, error);
}
```

---

### APK Gerado

`canil-gcm-20260702-*.apk` (151.3MB) — copiado para `G:/Meu Drive/apps k9/`

---

## Round 2 — Colecoes Legadas: Mapeamento e Logging

### Investigacao

Grep completo em `lib/` por referencias as colecoes legadas:

| Colecao | Arquivo | Metodo | Tipo |
|---|---|---|---|
| `atalhos_registro` | `dashboard_service.dart:108` | `getQuickActions()` | Future |
| `alertas` | `dashboard_service.dart:121` | `getActiveAlerts()` | Future |
| `alertas` | `dashboard_service.dart:139` | `countActiveAlerts()` | Future |
| `registros` | `dashboard_service.dart:158` | `countTodayRecords()` | Future |
| `climaAtual` | `dashboard_service.dart:151` | `getWeatherData()` | Future |
| `training_specialties` | `training_repository.dart:96` | `_watchRootSpecialties()` | Stream |
| `vacinas` | `dog_profile_service.dart:161` | `getVaccines()` | Future |
| `registros` | `dog_profile_service.dart:234` | `getRecentRecords()` | Future |
| `documentos` | `dog_profile_service.dart:259` | `getDocuments()` | Future |
| `caes/{id}/aptidoes` | `dog_profile_service.dart:204` | `getAptitudes()` | Future |

---

### Impacto Diagnostico

**NO ENCERRAMENTO (endShift):** Nenhum stream de colecao legacy esta no caminho critico. O `endShift` nao e bloqueado por esses listeners.

**NO FLUXO NORMAL:** Os 4+ PERMISSION_DENIED sao reais, mas:
- `training_specialties`: ja tinha `handleError` (silencioso, degradava graciosamente)
- `dashboard` (`getQuickActions`, `getActiveAlerts`, `countActiveAlerts`): `catch (_) {}` vazio — erros engolidos
- `health_prontuario` (`getDocuments`): `catch (_)` vazio
- `dog_profile` (`getVaccines`, `getRecentRecords`, `getDocuments`): sem tratamento de erro

---

### Fix Aplicado — Logging em Todos os Catches

#### 4. `lib/features/shifts/data/dashboard_service.dart`

Adicionado `import 'package:flutter/foundation.dart';` e `on FirebaseException catch` em todos os metodos:

```dart
Future<List<QuickAction>> getQuickActions() async {
  try {
    final snapshot = await _db
        .collection('atalhos_registro')
        .where('ativo', isEqualTo: true)
        .orderBy('ordem')
        .get();
    return snapshot.docs...
  } on FirebaseException catch (e) {
    debugPrint('[STREAM] atalhos_registro falhou [${e.code}]: ${e.message}');
    return [];
  }
}
```

Metodos afetados:
- `getQuickActions()` — log em `atalhos_registro`
- `getActiveAlerts()` — log em `alertas`
- `countActiveAlerts()` — log em `alertas.count`
- `getWeatherData()` — log em `climaAtual`
- `countTodayRecords()` — log em `registros.count`

---

#### 5. `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`

Metodo `_loadDashboardData` — 3 catches agora logam `debugPrint`:

```dart
try {
  quickActions = await _dashboardService.getQuickActions();
} catch (e) {
  debugPrint('[STREAM] getQuickActions falhou: $e');
}
try {
  alerts = await _dashboardService.getActiveAlerts(dogId);
} catch (e) {
  debugPrint('[STREAM] getActiveAlerts falhou: $e');
}
try {
  totalAlerts = await _dashboardService.countActiveAlerts(dogId);
} catch (e) {
  debugPrint('[STREAM] countActiveAlerts falhou: $e');
}
```

---

#### 6. `lib/features/dogs/data/dog_profile_service.dart`

Adicionado `import 'package:flutter/foundation.dart';` e logging nos metodos:

**`getVaccines`** (3 niveis de catch com fallback em cascata):
```dart
} on FirebaseException catch (e) {
  debugPrint('[STREAM] vacinas falhou [${e.code}]: ${e.message}');
  // Fallback 1: sem orderBy
  try {
    ...
  } on FirebaseException catch (e2) {
    debugPrint('[STREAM] vacinas (fallback) falhou [${e2.code}]: ${e2.message}');
    // Fallback 2: busca todas e filtra localmente
    ...
  }
}
```

**`getRecentRecords`**:
```dart
} on FirebaseException catch (e) {
  debugPrint('[STREAM] registros falhou [${e.code}]: ${e.message}');
  return [];
}
```

**`getDocuments`** (com fallback):
```dart
} on FirebaseException catch (e) {
  debugPrint('[STREAM] documentos falhou [${e.code}]: ${e.message}');
  // Fallback sem orderBy...
  } on FirebaseException catch (e2) {
    debugPrint('[STREAM] documentos (fallback) falhou [${e2.code}]: ${e2.message}');
    return [];
  }
}
```

---

### Proposta de Rules para Colecoes Legadas (ARQUIVADA)

Proposta diff foi feita mas **NÃO IMPLEMENTADA** — ficou em espera para auditoria posterior:

```javascript
// Colecoes que precisam de rules (aguardando decisao):
// alertas, atalhos_registro, registros, training_specialties,
// documentos, vacunas, climaAtual
```

Decisao do usuario: **NAO tocar nos legados agora** — foco no turno.

---

### APK Gerado

`canil-gcm-20260702-*.apk` (151.3MB) — copiado para `G:/Meu Drive/apps k9/`

---

## Round 3 — Fallback Silencioso Removido

### Problema: Log de producao

```
W/Firestore: Write failed at active_shifts/691755: PERMISSION_DENIED
I/flutter: [ShiftService] batch bloqueado por regras (permission-denied);
           gravando só log do turno.
```

O codigo de `startShift` tinha um fallback que, ao receber `permission-denied` no batch, gravava SO o `shift_logs` e RETORNAVA COMO SUCESSO:

```dart
// ANTES (shift_service.dart ~linha 207-237):
try {
  await batch.commit();
} on FirebaseException catch (e) {
  if (e.code == 'permission-denied') {
    debugPrint('[ShiftService] batch bloqueado por regras...');
    await logRef.set({ /* so o log */ });
    return;  // <-- mascara o erro!
  }
  rethrow;
}
```

**Impacto:** O usuario ficava em estado parcial (shift_logs existia, active_shifts nao). O fallback mascarou o bug real por 3 rodadas de diagnostico.

---

### Fix Aplicado

#### 7. `lib/features/shifts/data/shift_service.dart`

Fallback removido — agora `rethrow` sempre:

```dart
try {
  await batch.commit();
} on FirebaseException catch (e) {
  debugPrint('[ShiftService] batch bloqueado [${e.code}]: ${e.message}');
  rethrow;
}
```

Qualquer erro de regra agora propaga ate o ViewModel, popula `_error`, e a UI mostra `AppFeedback.error`.

---

### Fix de PermissionHandler

#### 8. `lib/core/services/permission_service.dart`

**Problema:** `Unhandled Exception "A request for permissions is already running"` quando `requestInitialPermissions` era chamado duas vezes rapido.

**Solucao:**
```dart
// ANTES:
static Future<void> requestInitialPermissions() async {
  await [
    Permission.location,
    Permission.storage,
    Permission.photos,
  ].request();
}

// DEPOIS:
static bool _requestInProgress = false;

static Future<void> requestInitialPermissions() async {
  if (_requestInProgress) return;
  _requestInProgress = true;
  try {
    await [
      Permission.location,
      Permission.storage,
      Permission.photos,
    ].request();
  } catch (e) {
    debugPrint('[PermissionService] falhou: $e');
  } finally {
    _requestInProgress = false;
  }
}
```

---

### Verificacao de Rules — Separacao Create/Update

Auditoria das rules que usam `diff().affectedKeys()`:

| Regra | allow create | allow update |
|---|---|---|
| `active_shifts/{ra}` | `keys().hasOnly()` via `isValidActiveShiftFor()` | `diff().affectedKeys().hasOnly()` ✅ |
| `shift_logs/{shiftId}` | `keys().hasOnly()` via `isValidShiftLogCreate()` | `diff().affectedKeys().hasOnly()` ✅ |
| `vehicle_crews/{crewId}` | `keys().hasOnly()` | `diff().affectedKeys().hasOnly()` ✅ |
| `vehicle_crews/{crewId}/members/{ra}` | `keys().hasOnly()` | `diff().affectedKeys().hasOnly()` ✅ |

**Conclusao:** Todas as rules ja tinham a separacao correta. O problema nao estava nas rules.

---

### APK Gerado

`canil-gcm-20260702-*.apk` (151.3MB) — copiado para `G:/Meu Drive/apps k9/`

---

## Round 4 — Causa Raiz: Campo `ended_at` no CREATE de vehicle_crews

### Problema Persistente

Mesmo com o fallback removido e rules corretas, o `PERMISSION_DENIED` continuava:

```
W/Firestore: Write failed at active_shifts/691755: PERMISSION_DENIED
```

### Investigacao: Confronto Payload vs Regra

#### Payload de `vehicle_crews/{crewId}` no `startShift` (batch.set com merge):

O metodo `_crewDocFields` com `clearEndedAt: true` envia:

```dart
final fields = {
  'id': crewId,
  'vehicle_id': vehicle.id,
  // ... outros campos ...
  'ended_at': FieldValue.delete(),  // <-- CHAVE PRESENTE
};
```

#### Regra de `vehicle_crews` CREATE:

```javascript
allow create: if signedIn()
  && emailMatchesRa(request.resource.data.titular_handler_id)
  && request.resource.data.keys().hasOnly([
    'id', 'vehicle_id', 'vehicle_label', 'vehicle_prefix', 'vehicle_model',
    'vehicle_unit', 'crew_size', 'service_dog_id', 'titular_handler_id',
    'active', 'created_at', 'updated_at',
    // ❌ 'ended_at' NAO ESTAVA NA LISTA!
    'dog_changes'
  ]);
```

### Mecanismo do Bug

1. Quando o documento `vehicle_crews/{vehicle_id}` NAO existe (primeiro turno da viatura, ou documento deletado), o `batch.set(..., merge: true)` e avaliado como **CREATE**
2. A regra de `allow create` e avaliada
3. `keys().hasOnly([...])` falha porque `ended_at` esta presente no payload
4. Write negado em `vehicle_crews`
5. O BATCH inteiro e desfeito pelo Firestore
6. O erro aparece no logcat como `active_shifts/691755` (primeiro documento do batch), mas a causa real e `vehicle_crews`

### Por que o UPDATE passa (reatribuicao de viatura)

No caminho de reabertura de equipe (documento JA EXISTE), o `FieldValue.delete()` nao aparece como `affectedKey` no `diff()`, entao `ended_at` nao e considerado. Por isso o bug so se manifestava no **primeiro turno** da viatura.

---

### Fix Aplicado

#### 9. `firestore.rules` — `ended_at` no whitelist do CREATE

```diff
match /vehicle_crews/{crewId} {
  allow create: if signedIn()
    && emailMatchesRa(request.resource.data.titular_handler_id)
    && request.resource.data.keys().hasOnly([
      'id',
      'vehicle_id',
      'vehicle_label',
      'vehicle_prefix',
      'vehicle_model',
      'vehicle_unit',
      'crew_size',
      'service_dog_id',
      'titular_handler_id',
      'active',
      'created_at',
      'updated_at',
+     // ended_at entra como FieldValue.delete() no payload de abertura (limpeza
+     // de encerramento anterior) — a key precisa ser aceita tambem no create
+     'ended_at',
      'dog_changes'
    ]);
```

O `allow update` ja inclui `ended_at` no `diff().affectedKeys().hasOnly([...])` (linha 1517).

---

## Resumo de Todos os Arquivos Modificados

| # | Arquivo | Mudanca | Sessao |
|---|---|---|---|
| 1 | `lib/features/profiles/presentation/screens/handler_profile_page.dart` | `AppFeedback` condicional em `_endShift` | R1 |
| 2 | `lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart` | `FirebaseException` com codigo em todos os metodos | R1 |
| 3 | `lib/features/shifts/presentation/screens/active_shift_dog_switcher.dart` | Feedback de erro em `switchDog` | R1 |
| 4 | `lib/features/shifts/data/dashboard_service.dart` | Logging `[STREAM]` em 5 metodos | R2 |
| 5 | `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart` | Logging em `_loadDashboardData` | R2 |
| 6 | `lib/features/dogs/data/dog_profile_service.dart` | Logging em `getVaccines`, `getRecentRecords`, `getDocuments` | R2 |
| 7 | `lib/features/shifts/data/shift_service.dart` | Fallback `permission-denied` removido | R3 |
| 8 | `lib/core/services/permission_service.dart` | `_requestInProgress` guard + catch | R3 |
| 9 | `firestore.rules` | `ended_at` no whitelist do CREATE de `vehicle_crews` | R4 |

---

## Fluxo Completo de startShift (para referencia)

```
1. startShift() chamado
   |
2. _validateVehicleCanBeAssumed() — valida veiculo disponivel
   |
3. Monta batch com 4 writes:
   a) shift_logs/{auto_id}       — CREATE
   b) active_shifts/{ra}         — CREATE
   c) vehicle_crews/{crewId}    — UPSERT (pode ser CREATE se doc nao existe)
   d) members/{ra}              — UPSERT (pode ser CREATE se doc nao existe)
   |
4. batch.commit()
   |
5. Se FirebaseException:
   - debugPrint com codigo
   - rethrow (ANTES: fallback que mascarava erro)
   |
6. ViewModel recibe erro, popula _error
   |
7. UI mostra AppFeedback.error (ANTES: sempre success)
```

---

## APKs Gerados

| Data | Arquivo | Tamanho |
|---|---|---|
| 2026-07-02 | `canil-gcm-20260702-*.apk` | 151.3MB |

Local: `G:/Meu Drive/apps k9/`

---

## Pendencias / Items Archivados

- **Colecoes legadas** (alertas, atalhos_registro, documentos, registros, training_specialties, vacunas, climaAtual): mapeamento completo feito. Proposta de rules pendente auditoria posterior.
- **Investigacao de historico de equipes**: tarefa original (quem estava de servico na viatura X no dia Y) NAO foi abordada nesta sessao — foco foi corrigir o bug de abertura de turno.
