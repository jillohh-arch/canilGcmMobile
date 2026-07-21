# FASE 5D — GATE 5C.3B REPORT: AD HOC MEAL EXECUTION UI ACTIVATION

> **STATUS**: READY FOR HUMAN AUDIT (LOCAL UNCOMMITTED STATE)
> **DATE**: 2026-07-21
> **ENV**: EMULATOR E2E REAL (AUTH + FUNCTIONS + FIRESTORE) & FLUTTER REGRESSION SUITE
> **COMMIT BASE**: `de2bc96dbf9339f9ea3d8077d8272e19f510528a` (`docs(health): close ad hoc meal execution audit gate`)

---

## 1. Executive Summary

O **Gate 5C.3B** realizou a ativação no Mobile do fluxo canônico de registro de refeição avulsa (**Ad Hoc Meal Execution**), desacoplando o Hub de Registros do writer legado e validando a cadeia completa no **Firebase Emulators (Auth + Functions + Firestore)** tanto via **Flutter Integration E2E (UI)** quanto via **Node Real Transport E2E**.

### Principais realizações
1. **Desacoplamento do Hub de Registros**: O ponto de entrada principal de Nutrição no Mobile (`onRegisterNutrition` em `dog_health_prontuario_screen.dart`) foi desacoplado de `FeedingRegistrationScreen` (writer legado) e reconectado diretamente ao fluxo canônico `HealthAdhocMealFormSheet`.
2. **Formulário Canônico Ad Hoc**: Criado `HealthAdhocMealFormSheet` em `lib/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart`, implementando interface responsiva com validações D42 no cliente, seletor de período amigável, time picker com trava de futuro, e payload `mode="adhoc"`.
3. **Reconciliação `dog_id` (Identidade por Path)**:
   - **No Documento Firestore (`/meal_logs/ml1_*`)**: O campo `dog_id` **NÃO é armazenado no corpo do documento** (`m.dog_id === undefined`). A identidade do K9 é determinada estritamente pelo caminho do documento: `dogs/{dogId}/meal_logs/{mealId}`.
   - **Na Camada de Apresentação / Receipt**: `dogId` é mantido apenas em memória e nos objetos de diagnóstico/receipt (`result.dogId`). O backend canônico **não foi alterado**.
4. **Distinção Transporte vs Persistência Auditada**:
   - **Transporte Mobile → Callable**: Chaves de vínculo planejado (`plan_id`, `planned_meal_id`, `meal_occurrence_id`, `scheduled_for`, `prescription_amount_at_time`) estão **rigorosamente AUSENTES** do payload JSON enviado à callable.
   - **Documento Persistido Firestore**: O backend materializa explicitamente `plan_id = null`, `planned_meal_id = null`, `meal_occurrence_id = null`, `scheduled_for = null` e `prescription_amount_at_time = null`.
5. **Comprovação E2E Originada na UI Flutter**:
   - Criado `test/features/health/presentation/nutrition/health_adhoc_meal_emulator_e2e_test.dart` comprovando a cadeia completa a partir da UI Flutter em 2 segundos: `HealthAdhocMealFormSheet` -> `Controller` -> `Gateway Flutter` -> `Functions Emulator (5001)` -> `Firestore Emulator REST API (8080)` -> `Read-after-write UI`.
   - **Gerenciamento de Assincronismo**: Operações I/O de rede no `testWidgets` foram executadas com `tester.runAsync`, permitindo a resolução das chamadas HTTP reais e evitando impasses com o `FakeAsync` do Flutter test.
6. **Comprovação Node Real Transport E2E**:
   - Executado `tools/rules_tests/health_nutrition_callables_emulator_tests.mjs` validando baseline/after, imutabilidade do NutritionPlan, Slot Non-Interference e Replay.
7. **Suíte de Regressão Health Reconciliada**: **1.087 testes aprovados / 4 skips preexistentes / 0 falhas**.

---

## 2. Distinção de Contrato: Transporte vs Persistência & Reconciliação `dog_id`

| Campo | Transporte Mobile (`mode="adhoc"`) | Documento Persistido Firestore (`/meal_logs/ml1_*`) | Rationale / Regra Backend |
| :--- | :--- | :--- | :--- |
| `mode` | `"adhoc"` | *N/A (Campo exclusivo de transporte)* | Define o tipo de mutação no contrato da callable. |
| **`dog_id`** | Presente no transporte (`"dog-nutri-e2e-a"`) | **AUSENTE DO CORPO (`undefined`)** | **Identidade do K9 é estrutural via Path (`dogs/{dogId}/meal_logs/{mealId}`)**. |
| `period` | Presente (ex: `"afternoon"`) | Presente (`"afternoon"`, `"evening"`, etc.) | Período da refeição avulsa. |
| `offered_grams` | Presente (ex: `150`) | Presente (`150`) | Quantidade oferecida (> 0). |
| `consumed_grams` | Opcional | Presente (`150` ou `null`) | Quantidade consumida (D42). |
| `acceptance` | Presente (ex: `"full"`) | Presente (`"full"`, `"unknown"`, etc.) | Nível de aceitação. |
| `fed_at` | Presente (ISO-8601 UTC) | Presente (ISO-8601 UTC) | Instant de alimentação. |
| `operation_id` | Presente (UUID v4) | Presente no Receipt de Operação | Idempotência de transporte. |
| `observations` | Opcional | Presente ou `null` | Observações textuais. |
| `attachment_refs` | Presente (`[]`) | Presente (`[]`) | Lista de anexos. |
| **`plan_id`** | **AUSENTE (Chave omitida)** | **`null`** | Rejeitado se enviado na callable ad hoc; materializado como `null` no documento. |
| **`planned_meal_id`** | **AUSENTE (Chave omitida)** | **`null`** | Rejeitado se enviado na callable ad hoc; materializado como `null` no documento. |
| **`meal_occurrence_id`** | **AUSENTE (Chave omitida)** | **`null`** | Rejeitado se enviado na callable ad hoc; materializado como `null` no documento. |
| **`scheduled_for`** | **AUSENTE (Chave omitida)** | **`null`** | Rejeitado se enviado na callable ad hoc; materializado como `null` no documento. |
| **`prescription_amount_at_time`** | **AUSENTE (Chave omitida)** | **`null`** | Rejeitado se enviado na callable ad hoc; materializado como `null` no documento. |

---

## 3. Evidências de Execução no Firebase Emulators

### 3.1. Flutter Integration E2E (Execução Originada na UI)

- **Arquivo**: `test/features/health/presentation/nutrition/health_adhoc_meal_emulator_e2e_test.dart`
- **Comando Executado**:
  ```powershell
  $env:HEALTH_NUTRITION_EMULATOR_INTEGRATION="1"; $env:FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"; $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"; $env:GCLOUD_PROJECT="canil-gcm"; flutter test test/features/health/presentation/nutrition/health_adhoc_meal_emulator_e2e_test.dart --reporter expanded
  ```
- **Mecanismo de Conexão com Emulators**:
  - **Auth Emulator (`127.0.0.1:9099`)**: Autenticação via REST API do Auth Emulator no `signInOperator` obtendo ID Token de operador real.
  - **Functions Emulator (`127.0.0.1:5001`)**: Invocation HTTP da Callable `healthNutritionCreateMealLog` no Gateway Flutter permanente.
  - **Firestore Emulator (`127.0.0.1:8080`)**: Leitura pós-escrita efetuada via REST API direta (`http://127.0.0.1:8080/v1/projects/...`) para asserção do documento persistido sem depender de plugins nativos.
  - **Gerenciamento I/O**: Executado com `HttpOverrides.global = null` e `tester.runAsync` para tratar conexões socket HTTP do Dart VM.
- **Saída Real do Runner**:
  ```text
  00:00 +0: loading C:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/test/features/health/presentation/nutrition/health_adhoc_meal_emulator_e2e_test.dart
  00:00 +0: Gate 5C.3B Flutter UI Integration E2E (setUpAll)
  [Gate5C3BFlutterE2E] AUTH=127.0.0.1:9099 FS=127.0.0.1:8080 FN=127.0.0.1:5001 project=canil-gcm region=southamerica-east1
  [Gate5C3BFlutterE2E] Submetendo formulário ad hoc via UI...
  [Gate5C3BFlutterE2E] Read-after-write refresh triggered count=1
  [Gate5C3BFlutterE2E] UI recebeu resposta de sucesso. mealId=ml1_479111ee72d9681a1d78930a0f89a475b1dbba6cb009085da78e0ab73d92f554
  [Gate5C3BFlutterE2E] CADEIA INTEGRADA COMPROVADA COM SUCESSO.
  00:02 +1: All tests passed!
  ```
- **Cadeia Comprovada**:
  `HealthAdhocMealFormSheet` (UI) -> `enterText(150)` -> `tap(REGISTRAR ALIMENTAÇÃO AVULSA)` -> `HealthNutritionMutationController.createAdhocMeal` -> `FirebaseFunctionsHealthNutritionMutationGateway` -> `Functions Emulator (5001)` -> `Firestore Emulator (8080)` -> `HealthNutritionMutationUiSuccess` -> `onRefreshAfterSuccess` (Read-after-write na UI).

---

### 3.2. Node Real Transport E2E (Validação de Regras & Registros)

- **Arquivo**: `tools/rules_tests/health_nutrition_callables_emulator_tests.mjs`
- **Comando Executado**:
  ```powershell
  $env:FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"; $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"; $env:FIREBASE_FUNCTIONS_EMULATOR_HOST="127.0.0.1:5001"; $env:GCLOUD_PROJECT="canil-gcm"; node ../tools/rules_tests/health_nutrition_callables_emulator_tests.mjs
  ```
- **Resultado do Runner**:
  ```text
  === Health Nutrition Callables — REAL TRANSPORT E2E (Gate 2) ===
  project=canil-gcm
  AUTH_EMULATOR=127.0.0.1:9099
  FIRESTORE_EMULATOR=127.0.0.1:8080
  FUNCTIONS_EMULATOR=127.0.0.1:5001

  ok - Auth Emulator emite ID token real (uid=uid-710001)
  ok - GATE 5C.3B Real E2E: Ad hoc meal creation, baseline/after, slot non-interference, receipt, audit & replay
  failures=0
  REAL_CALLABLE_TRANSPORT_E2E: OK
  ZERO_PRODUCTION: confirmed
  ```

#### Tabela Baseline vs AFTER (Firebase Emulators)

| Coleção / Entidade | BEFORE (Baseline) | AFTER (Primeiro Submit) | Delta | Condição Esperada |
| :--- | :---: | :---: | :---: | :--- |
| `dogs/{dogId}/meal_logs` | `0` | `1` | **+1** | Documento `ml1_*` criado em `/dogs/dog-nutri-e2e-a/meal_logs/` |
| `dogs/{dogId}/nutrition_operations` | `0` | `1` | **+1** | Receipt `nr1_*` (`operation_type = "create_adhoc_meal"`) |
| `auditLogs` | `0` | `1` | **+1** | Audit Log (`action = "health.nutrition.meal_log.create_adhoc"`) |
| `dogs/{dogId}/feeding_events` | `0` | `0` | **0** | Zero dual-write legado |
| `dogs/{dogId}/feedings` | `0` | `0` | **0** | Zero dual-write legado |
| `dogs/{dogId}/nutrition_plans` (`revision`) | `1` | `1` | **0** | NutritionPlan **imutável** |
| Slot Planejado `slot-am` Status | `pending` | `pending` | **0** | **Slot Non-Interference** mantido |

#### Validação do Documento Persistido (`/meal_logs/ml1_*`)
```json
{
  "period": "afternoon",
  "offered_grams": 150,
  "consumed_grams": 150,
  "acceptance": "full",
  "fed_at": "2026-07-21T15:00:00.000Z",
  "observations": "Ad hoc meal via canonical execution UI",
  "attachment_refs": [],
  "plan_id": null,
  "planned_meal_id": null,
  "meal_occurrence_id": null,
  "scheduled_for": null,
  "prescription_amount_at_time": null,
  "recorded_by": {
    "uid": "uid-710001",
    "name": "Operador Nutri E2E",
    "email": "710001@gcm.com.br",
    "ra": "710001"
  },
  "recorded_at": "2026-07-21T17:51:00.000Z",
  "revision": 1,
  "schema_version": 1,
  "source": "mobile_callable"
}
```
*(Nota: `dog_id` não está no corpo do JSON; a identidade é dada pelo path `/dogs/dog-nutri-e2e-a/meal_logs/ml1_*`).*

#### Evidência de Replay Controlado
- Re-execução da mesma callable com o mesmo `operation_id` e payload:
  - Resposta: `was_no_op = true`
  - Delta `meal_logs`: **0**
  - Delta `nutrition_operations`: **0**
  - Delta `auditLogs`: **0**
  - Delta coleções legadas: **0**

---

## 4. Evidências da Suíte de Regressão Health Reconciliada

```bash
# Regressão Completa da Feature Health (Flutter)
$ flutter test test/features/health
Resultado: 00:31 +1087 ~4: All tests passed!
```

- **1.087 APROVADOS**
- **4 SKIPPED** (Skips preexistentes de fixtures que dependem de variáveis de emulador de ambiente):
  1. `firestore_nutrition_canonical_readers_emulator_test.dart`
  2. `firestore_nutrition_emulator_fixture_test.dart`
  3. `firebase_functions_health_schedule_mutation_gateway_emulator_test.dart`
  4. `health_schedule_ui_e2e_emulator_test.dart`
- **0 FALHAS**

---

## 5. Inventário Git Completo (`git status --short`)

```bash
$ git status --short
 M lib/features/health/presentation/screens/dog_health_prontuario_screen.dart
 M test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart
 M tools/rules_tests/health_nutrition_callables_emulator_tests.mjs
?? docs/health/HEALTH_V1_PHASE_5D_GATE5C3B_AD_HOC_MEAL_EXECUTION_UI_REPORT.md
?? lib/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart
?? test/features/health/presentation/nutrition/health_adhoc_meal_emulator_e2e_test.dart
?? test/features/health/presentation/nutrition/health_adhoc_meal_execution_ui_test.dart
?? test/features/health/presentation/nutrition/health_adhoc_slot_non_interference_test.dart
?? test/features/health/presentation/screens/health_hub_adhoc_navigation_test.dart

$ git diff --check
Result: OK (Zero trailing whitespace / zero conflitos)
```

---

## 6. Próximos Passos

O **Gate 5C.3B** está pronto para veredito humano final e commit.

> [!IMPORTANT]
> Nenhum commit, push ou deploy foi realizado.
