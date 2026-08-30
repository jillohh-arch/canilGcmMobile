# Health v1 — Phase 5D Gate 5C.3A Ad Hoc Meal Execution Audit & Gap Analysis Report

## 1. Executive Summary

A auditoria técnica e análise de lacunas (Gap Analysis) para a **Execução de Refeição Avulsa (Ad Hoc)** no Health v1.0 foi concluída e totalmente alinhada com as diretrizes adversariais.

### Principais Conclusões:
1. **Backend Completo**: O backend Node 22 (`functions/src/`) já suporta integralmente `mode="adhoc"` na Cloud Function callable `healthNutritionCreateMealLog`, no engine, no parser, no adapter Firestore (`ml1_*`), na geração de receipt (`create_adhoc_meal`) e no audit log com a action exata `health.nutrition.meal_log.create_adhoc` (summary: `Create ad hoc MealLog`).
2. **Dupla Barreira de Injeção**: O backend aplica duas verificações sequenciais no payload:
   - `rejectServerAuthoritativeInjection(data)` rejeita campos controlados pelo servidor (`recorded_by`, `recorded_at`, `revision`, `schema_version`, `source`);
   - `rejectAdhocTransportExtras(data)` rejeita campos incompatíveis com refeições avulsas (`plan_id`/`planId`, `planned_meal_id`/`plannedMealId`, `meal_occurrence_id`/`mealOccurrenceId`, `scheduled_for`/`scheduledFor`, `prescription_amount_at_time`/`prescriptionAmountAtTime`).
3. **Fundação Client Flutter Completa**: O app Flutter já possui suporte completo nas camadas de domínio, data e controller: `CreateAdhocMealLogCommand`, `encodeAdhocMeal`, `createAdhocMealLog` no gateway e `createAdhocMeal` no `HealthNutritionMutationController`.
4. **Lacunas de UI e Testes para o Gate 5C.3B**:
   - **Formulário UI**: O formulário visual para refeição avulsa (`HealthAdhocMealFormSheet`) ainda não existe. O Hub de Registros (`dog_health_prontuario_screen.dart` → `onRegisterNutrition`) atualmente abre a tela legada `FeedingRegistrationScreen`, que faz escritas legadas nas coleções `feedings`/`feeding_events`.
   - **Slot Non-Interference**: A verificação de que `plano ativo + slot pending/late + MealLog ad hoc → slot continua pending/late` é suportada pela lógica de domínio, mas a cobertura por teste automatizado dedicado é **MISSING**, tornando-se requisito obrigatório do Gate 5C.3B.
   - **Firestore Rules**: A mutação canônica ocorre via callable/Admin SDK protegida por autorização (`health.create` + `requireDogAccess`). Testes automatizados no Rules Emulator para bloquear escritas diretas de cliente em `meal_logs` são classificados como **MISSING**.

---

## 2. Git Preflight

| Parâmetro | Valor Auditado | Status |
|---|---|---|
| Repositório | `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm` | OK |
| Branch | `feature/health-v1-foundation` | OK |
| HEAD | `f2e522bc5e2d7f4d00ee9e81928ad6e7fed49b3f` (`docs(health): close production planned meal activation gate`) | OK |
| Tracking Remote | `origin/feature/health-v1-foundation` (`0/0` em sincronia) | OK |
| Working Tree | Limpo (apenas alteração não commitada deste relatório) | OK |

---

## 3. Canonical Contract Reconstruction

### Payload Wire Esperado (`mode = "adhoc"`)
```json
{
  "mode": "adhoc",
  "dog_id": "string",
  "period": "morning | afternoon | evening | night | extra",
  "offered_grams": 125.0,
  "consumed_grams": 100.0,
  "acceptance": "full | partial | refused | unknown",
  "fed_at": "2026-07-21T15:53:00.000Z",
  "observations": "string | null",
  "attachment_refs": ["string"],
  "operation_id": "UUID-v4-string"
}
```

### Arquitetura de Rejeição de Injeção de Campos

O backend impõe duas barreiras rigorosas e separadas antes de processar uma refeição avulsa:

1. **`rejectServerAuthoritativeInjection(data)`**:
   Rejeita qualquer tentativa de injetar campos que pertencem exclusivamente ao servidor para qualquer modo (`recorded_by`/`recordedBy`, `recorded_at`/`recordedAt`, `schema_version`/`schemaVersion`, `revision`, `source`, `create_fingerprint`, `entity_semantic_fingerprint`, `receipt_id`).
2. **`rejectAdhocTransportExtras(data)`**:
   Rejeita especificamente no modo `adhoc` campos incompatíveis com uma refeição avulsa, incluindo vínculos de plano e metadados de ocorrência planejada:
   - `plan_id` / `planId`
   - `planned_meal_id` / `plannedMealId`
   - `meal_occurrence_id` / `mealOccurrenceId`
   - `scheduled_for` / `scheduledFor`
   - `prescription_amount_at_time` / `prescriptionAmountAtTime`

---

## 4. Backend Inventory

| Componente | Estado Atual | Evidência / Arquivo |
|---|---|---|
| Callable Discriminator | **COMPLETO** | `runHealthNutritionCreateMealLog` em `health_nutrition_callables.ts` valida `mode === "adhoc"`. |
| Proteção de Injeção | **COMPLETO** | `rejectServerAuthoritativeInjection` (global) + `rejectAdhocTransportExtras` (específico adhoc). |
| Command Parser | **COMPLETO** | `parseAdhocMealCommand` em `health_nutrition_logic.ts` valida D42 e re-confirma ausência dos 3 vínculos de plano. |
| Engine Processor | **COMPLETO** | `runCreateAdhocMealLog` em `health_nutrition_engine.ts` grava `MealLog`, receipt e audit log. |
| Firestore Document ID | **COMPLETO** | `adhocMealLogIdV1` gera ID físico com prefixo `ml1_` baseado em `['meal_log_adhoc_v1', actorUid, dogId, idempotencyKey]`. |
| Receipt Operation | **COMPLETO** | Opera sob `create_adhoc_meal` em `dogs/{dogId}/nutrition_operations/{receiptId}`. |
| Audit Log Action | **COMPLETO** | Registra a action exata `health.nutrition.meal_log.create_adhoc` em `auditLogs/` com summary `Create ad hoc MealLog`. |
| Validação D42 | **COMPLETO** | `assertMealQuantities` valida `offered_grams > 0`, limites de `consumed_grams` e compatibilidade de `acceptance`. |
| Idempotência | **COMPLETO** | Mesmo `operation_id` + mesmo payload → replay `wasNoOp: true` sem criar segundo MealLog ou AuditLog. |

---

## 5. Flutter Client Foundation Inventory

| Componente | Estado | Arquivo de Origem |
|---|---|---|
| Domain Command | **COMPLETO** | `CreateAdhocMealLogCommand` em `health_nutrition_mutation_commands.dart` |
| Payload Codec | **COMPLETO** | `HealthNutritionMutationPayloadCodec.encodeAdhocMeal` em `health_nutrition_mutation_payload_codec.dart` |
| Gateway Interface | **COMPLETO** | `createAdhocMealLog` em `health_nutrition_mutation_gateway.dart` |
| Gateway Production Adapter | **COMPLETO** | `createAdhocMealLog` em `firebase_functions_health_nutrition_mutation_gateway.dart` |
| Presentation Controller | **COMPLETO** | `createAdhocMeal` em `health_nutrition_mutation_controller.dart` |
| Form UI Sheet | **GAP (MISSING)** | Nenhum form `HealthAdhocMealFormSheet` existe em `presentation/nutrition/`. |

---

## 6. UI and Navigation Inventory

1. **Hub de Registros (`HealthTypeSelectorScreen`)**:
   * Categoria `nutrition` ("Nutrição", ícone `restaurant_rounded`).
   * Quando selecionada, invoca `widget.onRegisterNutrition?.call(context)`.
2. **Wiring Atual no Prontuário (`dog_health_prontuario_screen.dart`)**:
   * O callback `onRegisterNutrition` executa `_openFeedingRegistration`.
   * `_openFeedingRegistration` abre a tela legada `FeedingRegistrationScreen` (`lib/features/nutrition/presentation/screens/feeding_registration_screen.dart`).
   * `FeedingRegistrationScreen` realiza escritas legadas via `NutritionViewModel` nas coleções legadas `feedings` / `feeding_events`.
3. **Lacuna de Integração (Escopo Gate 5C.3B)**:
   * Criar o widget `HealthAdhocMealFormSheet` em `lib/features/health/presentation/nutrition/`.
   * Re-rotear `onRegisterNutrition` em `dog_health_prontuario_screen.dart` para abrir `HealthAdhocMealFormSheet` alimentado por `HealthNutritionMutationController.createAdhocMeal`.

---

## 7. Ad Hoc vs Planned Boundary Audit & Slot Non-Interference

* **Isolamento de Slots**: Uma refeição avulsa **nunca** possui `plan_id`, `planned_meal_id` ou `meal_occurrence_id`.
* **Imutabilidade do Plano**: Criar uma refeição avulsa **não muta** o `NutritionPlan` nem altera a revisão do plano.
* **Comportamento de Slots Planejados**: Quando existe um plano ativo e uma refeição avulsa é registrada no mesmo dia civil local:
  - O `MealLog` avulso tem `planned_meal_id = null` e `meal_occurrence_id = null`.
  - O leitor de ocorrências (`MealOccurrence`) não associa o `MealLog` avulso a nenhum slot do plano.
  - Portanto, slots com status `pending` ou `late` **permanecem inalterados (`pending` ou `late`)**.
* **Auditoria de Teste Automatizado**:
  - A regra é garantida pela arquitetura de modelos de domínio.
  - Porém, **não existe teste automatizado explícito** no Flutter provando que `plano ativo + slot pending/late + MealLog ad hoc → slot continua pending/late`.
  - Classificação no relatório: **`MISSING`**. A criação dessa suíte unitária/widget torna-se **requisito obrigatório do Gate 5C.3B**.

---

## 8. Suporte a Anexos (`attachment_refs`)

* **Contrato Backend/Domain/Codec**: **COMPLETO**. O schema do comando `CreateAdhocMealLogCommand`, o codec `encodeAdhocMeal` e a validação do backend aceitam o array `attachment_refs` contendo strings de `health_document_id`.
* **Definição de Escopo para o Gate 5C.3B**:
  - O formulário `HealthAdhocMealFormSheet` **não exporá** um campo de texto técnico para o usuário digitar IDs manualmente.
  - Por padrão, o formulário enviará `attachment_refs` como lista vazia (`[]`), a menos que já exista um seletor canônico de documentos de Saúde comprovadamente pronto e reutilizável.
  - O fluxo completo de upload e nova associação de documentos permanece **fora do escopo** do Gate 5C.3B.

---

## 9. Test Coverage Matrix

| Componente / Cenário | Classificação | Evidência / Arquivo de Teste |
|---|---|---|
| Domain / Logic | **COVERED** | `functions/src/health_nutrition_logic_test.ts`, `meal_log_client_input_test.dart` |
| Engine | **COVERED** | `functions/src/health_nutrition_engine_test.ts` (100% pass) |
| Callable Authorization | **COVERED** | `functions/src/health_nutrition_callables_test.ts` (`health.create` + `requireDogAccess`) |
| Firestore Adapter | **COVERED** | `functions/src/health_nutrition_firestore_adapter_test.ts` (Admin SDK write paths) |
| Emulator E2E | **MISSING** | A ser executado na ativação visual do Gate 5C.3B |
| Flutter Command / Gateway | **COVERED** | `test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart` |
| Flutter Controller | **COVERED** | `test/features/health/presentation/nutrition/health_nutrition_mutation_controller_test.dart` |
| Flutter UI | **MISSING** | Ausência do formulário `HealthAdhocMealFormSheet` |
| Read-After-Write | **COVERED** | `test/features/health/presentation/nutrition/health_nutrition_read_after_write_test.dart` |
| Read Model | **COVERED** | `test/features/health/presentation/nutrition/health_nutrition_today_screen_test.dart` |
| Coexistence | **COVERED** | `test/features/health/data/coexistence/nutrition/nutrition_merge_and_source_test.dart` |
| Slot Non-Interference | **MISSING** | Requisito obrigatório do Gate 5C.3B (`plano ativo + slot pending/late + MealLog ad hoc → slot continua pending/late`) |
| Firestore Rules | **MISSING** | A escrita canônica ocorre via callable/Admin SDK. Testes do Admin SDK não equivalem a Security Rules Emulator. A prova de bloqueio de escrita direta via SDK cliente fica como pendência |

---

## 10. Tests Executed (Execução Real de Testes)

### 1. Backend Node 22 Tests (`functions/`)
* **Comando Executado**: `npm run build && npm run test:health-nutrition`
* **Resultado**: **180 assertions PASS, 0 falhas**.
* **Escopo**: Logic, Engine, Plan Engine, Permissions, Callables (`mode="adhoc"`), Firestore Adapters.

### 2. Flutter Unit Tests (`canil-gcm`)
* **Comando Executado**:
  ```bash
  flutter test \
    test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart \
    test/features/health/presentation/nutrition/health_nutrition_mutation_controller_test.dart \
    test/features/health/presentation/nutrition/health_nutrition_read_after_write_test.dart \
    test/features/health/domain/nutrition_document_parser_test.dart \
    test/features/health/domain/meal_log_client_input_test.dart \
    test/features/health/data/coexistence/nutrition/nutrition_merge_and_source_test.dart \
    test/features/health/presentation/nutrition/health_nutrition_today_screen_test.dart
  ```
* **Resultado**: **104 tests PASS, 0 falhas** (duração: ~2.5s).

### 3. Verification Commands
* `git diff --check` → **CLEAN** (0 erros de formatação/whitespaces).

---

## 11. Findings

### GAP-UI-01 (MAJOR): Ausência do Formulário Canônico `HealthAdhocMealFormSheet`
O app Flutter possui todo o suporte de backend, domain, data e controller para `createAdhocMeal`, mas não possui a folha de formulário visual (`HealthAdhocMealFormSheet`).

### GAP-UI-02 (MAJOR): Roteamento do Hub para Writer Legado
O callback `onRegisterNutrition` no prontuário (`dog_health_prontuario_screen.dart`) abre a tela legada `FeedingRegistrationScreen`, que grava nas coleções legadas `feedings`/`feeding_events`.

### GAP-TEST-01 (MISSING): Teste Automatizado de Slot Non-Interference
Necessário adicionar teste automatizado garantindo que `plano ativo + slot pending/late + MealLog ad hoc → slot continua pending/late`.

### GAP-RULES-01 (MISSING): Cobertura de Firestore Security Rules no Emulator
A escrita canônica é protegida no nível da Callable por autenticação e autorização (`health.create` + `requireDogAccess`). Não foram executados testes no Rules Emulator para validar restrições de escrita direta de cliente no caminho `dogs/{dogId}/meal_logs/{mealId}`.

* **BLOCKER**: 0
* **MAJOR (Gaps de Implementação para 5C.3B)**: 2
* **MISSING (Testes/Rules para 5C.3B)**: 2
* **MINOR**: 0
* **OBSERVATION**: 0

---

## 12. Recommended Implementation Scope (Gate 5C.3B)

No próximo gate (**Gate 5C.3B — Ad Hoc Meal Execution UI Activation**):
1. **Criar `HealthAdhocMealFormSheet`** em `lib/features/health/presentation/nutrition/`:
   - Seleção de período (`morning`, `afternoon`, `evening`, `night`, `extra`).
   - Gramas oferecidos e consumidos (com validação D42 reativa).
   - `fed_at` com seletor de horário.
   - Observações opcionais.
   - Envio de `attachment_refs: []` por padrão (sem campo de texto técnico nem upload complexo de documentos).
2. **Re-rotear `onRegisterNutrition`**:
   - Conectar o botão "Nutrição" do Hub de Registros (`dog_health_prontuario_screen.dart`) ao `HealthAdhocMealFormSheet`.
3. **Conectar ao Controller**:
   - Usar `HealthNutritionMutationController.createAdhocMeal` com proteção contra double-submit, `operationId` estável, pending intent e callback de `onRefreshAfterSuccess`.
4. **Implementar Teste de Slot Non-Interference**:
   - Adicionar teste automatizado em Flutter provando que o registro de refeição ad hoc preserva os slots do plano como `pending`/`late`.
5. **Execução no Emulator / Dispositivo**:
   - Testar a cadeia completa Flutter → Callable → MealLog → receipt → audit → Read-After-Write no Emulator.

---

## 13. Proposed Next Gate

**FASE 5D — GATE 5C.3B: AD HOC MEAL EXECUTION UI ACTIVATION**

---

## 14. Git Final State

* **Mobile / Backend (`canil-gcm`)**:
  * Branch: `feature/health-v1-foundation`
  * HEAD: `f2e522bc5e2d7f4d00ee9e81928ad6e7fed49b3f`
  * Tracking: `origin/feature/health-v1-foundation` (`0/0` em sincronia)
  * Working Tree: Contém apenas a alteração não commitada deste relatório de auditoria `docs/health/HEALTH_V1_PHASE_5D_GATE5C3A_AD_HOC_MEAL_EXECUTION_AUDIT.md`.

---

## 15. Final Verdict

**FASE 5D — GATE 5C.3A READY FOR HUMAN AUDIT.**
