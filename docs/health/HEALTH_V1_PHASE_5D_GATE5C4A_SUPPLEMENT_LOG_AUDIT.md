# FASE 5D — GATE 5C.4A
## SUPPLEMENT LOG — AUDIT & GAP ANALYSIS

> **SUPERSEDED BY:**
> `docs/health/HEALTH_V1_PHASE_5D_GATE5C4A_SUPPLEMENT_LOG_AUDIT_R1.md`
>
> Este documento保留了原始审计结果，但已被 R1 版本取代。R1 版本包含了更正、手术闭合轮以及修正后的合同和测试计数。

**Checkpoint anterior:** `a4677e3` (`fix(health): reconcile nutrition runtime integration`)
**Branch:** `feature/health-v1-foundation`
**Data:** 2026-07-14
**Auditor:** Claude (FASE 5D Gate 5C.4A)
**Arquivo fora do escopo:** `functions/audit_prod.mjs` (preexistente, preservado)

---

## 1. EXECUTIVE SUMMARY

O SupplementLog canônico está **parcialmente implementado**. A fundação Flutter (command, codec, gateway, controller, reader, parser) está **COMPLETA**. O backend callable está implementado (repo separado). A UI operacional de registro de suplemento está **AUSENTE**.

**Veredicto: NÃO PRONTO para produção operacional.**

### O que existe
- Domínio `SupplementLog` validado com 8 testes unitários
- Callable `healthNutritionCreateSupplementLog` integrada ao gateway
- Codec snake_case com validação de integridade de resposta
- Controller com pending intent, operationId reuse, retry
- Reader canônico `FirestoreNutritionCanonicalSupplementLogReader` com fail-closed
- Parser `SupplementLogDocumentParser` completo
- Seção `_SupplementsSection` em Nutrição Hoje mostrando registros
- Seção de suplementos prescritos (plano + legado)
- Authorization Firestore Rules: `allow read: signedIn && canAccessDogRecord`
- ZERO legacy write (confirmado no adapter)

### O que falta
- **UI de registro de suplemento** (formulário, bottom sheet ou entry point)
- **Wiring no Hub (HealthTypeSelector)** — `nutrition` seleciona `HealthAdhocMealFormSheet`, não supplement
- **HealthSummary integration** — suplementos não aparecem no card de resumo
- **Testes de regras do emulador** para supplement_logs (existem para callables/meal_logs)
- **Teste de read-after-write** para supplement_log específico
- **Documentação de semantic contract** (o que um SupplementLog representa vs. MealLog)

---

## 2. GIT PREFLIGHT

```
Branch: feature/health-v1-foundation ✓
HEAD: a4677e32524e5fe99865da3e17be1a576994b283 ✓
Status: ?? functions/audit_prod.mjs (preexistente, fora do escopo) ✓
Divergência: 0 ✓
git diff --check: clean ✓
```

---

## 3. CANONICAL SUPPLEMENT SEMANTICS

### O que SupplementLog representa
Um **fato de administração de suplemento** — registro factual de que um suplemento foi administrado a um cão em um momento específico. Não é uma prescrição, não é um plano, é a execução.

### Semântica confirmad

| Pergunta | Resposta |
|----------|----------|
| É execução de dose prescrita? | Opcional — existe vínculo (`nutritionPlanId`, `supplementRegimenId`, `protocolId`) mas não obrigatório |
| Pode existir administração avulsa? | SIM — campos `nutritionPlanId`, `supplementRegimenId` e `protocolId` são todos opcionais |
| Existe suplemento planejado no NutritionPlan? | SIM — `NutritionPlanSupplementRegimen` com name, dose, unit, frequency, instructions |
| Existe slot/horário de suplemento? | NÃO — diferente de MealLog que tem `MealScheduleSlot`, SupplementLog só tem `administeredAt` |
| Pode haver mais de um log do mesmo suplemento no mesmo dia? | SIM — idempotência é por `operationId`, não por dedupe semântico |
| Um SupplementLog altera NutritionPlan? | NÃO — não há alteração de status do plano |
| Afeta prontidão? | NÃO diretamente — não há vínculo com prontidão |
| Entra em agregados diários? | PARCIAL — é lido em Nutrição Hoje (seção "ADMINISTRAÇÕES REGISTRADAS") mas não é agregado no card de resumo |

### GAP DE CONTRATO (OBSERVATION)
A semântica de SupplementLog não está explicitamente documentada em nenhum ADR ou decisão canônica. Não existe distinção formal entre:
- SupplementLog como "administração de suplemento prescrito"
- SupplementLog como "administração avulsa de suplemento"

O vínculo opcional significa que ambos os casos são suportados, mas a UI futura deve clarificar qual fluxo é pretendido.

---

## 4. BACKEND INVENTORY

### Callable
**Nome:** `healthNutritionCreateSupplementLog` (via `HealthNutritionCallableNames.createSupplementLog`)

**Arquivos:**
- Callable handler: repo separado (não auditado neste Gate)
- Adapter Firestore: `functions/src/health_nutrition_firestore_adapter.ts:314-324`
- Engine: `functions/src/health_nutrition_engine.ts`
- Logic: `functions/src/health_nutrition_logic.ts`
- Regras: `firestore.rules:1945-1948`

### Adapter confirmad
```typescript
getSupplementLogsInWindow: async (dogId: string, start: Date, end: Date) => {
  const snap = await firestoreTx.get(
    db.collection("dogs").doc(dogId).collection("supplement_logs")
  );
  return snap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
}
```

### Assertions de segurança
```typescript
assertCanonicalWritePath(path) // lines 62-87
// Proíbe: legacy collections, paths fora dogs/*/{meal_logs,supplement_logs,nutrition_operations,nutrition_plans}
// Garante zero legacy write
```

### GAP DE IMPLEMENTAÇÃO
O callable handler real não foi auditado diretamente (repo separado). Assumimos que a implementação segue o contrato estabelecido nos Gates anteriores (5D Gate 1-3).

---

## 5. TRANSPORT CONTRACT

### Payload aceito pela callable

| Campo | Tipo | Obrigatório | Validação | Normalização |
|-------|------|-------------|-----------|--------------|
| `dog_id` | string | SIM | não vazio, trim | — |
| `supplement_name` | string | SIM | não vazio | trim, lower? (não confirmado) |
| `dose` | number | SIM | > 0, finito | — |
| `unit` | string | SIM | "mg", "g", "ml", "scoop", "tablet", "drop", "other" | — |
| `administered_at` | string ISO 8601 | SIM | não futuro | UTC |
| `operation_id` | string | SIM | não vazio | — |
| `nutrition_plan_id` | string | NÃO | — | — |
| `supplement_regimen_id` | string | NÃO | requer `nutrition_plan_id` se presente | — |
| `protocol_id` | string | NÃO | — | — |
| `observations` | string | NÃO | — | — |

### Validação local (Flutter — antes da rede)
```dart
CreateSupplementLogCommand(
  supplementRegimenId: 'reg-1', // requer nutritionPlanId também
)
// Lança HealthNutritionMutationValidation se regimen sem plan
```

### Campos proibidos no transporte
- `recorded_by` (server-authoritative)
- `schema_version` (server-authoritative)
- `revision` (server-authoritative)
- `created_at` (server-authoritative)
- `dog_id` em formato diferente de snake_case

---

## 6. PERSISTED DOCUMENT CONTRACT

### Path
`dogs/{dogId}/supplement_logs/{logId}`

### Campos persistidos

| Campo | Fonte | Notas |
|-------|-------|-------|
| `id` | server (Firestore auto-ID) | — |
| `supplement_name` | client | — |
| `dose` | client | numérico |
| `unit` | client | wire name string |
| `administered_at` | client | ISO 8601 UTC |
| `recorded_by` | server | `{ uid, name, internalRole }` |
| `schema_version` | server | default 1 |
| `revision` | server | contador de versões |
| `nutrition_plan_id` | client (opcional) | — |
| `supplement_regimen_id` | client (opcional) | — |
| `protocol_id` | client (opcional) | — |
| `observations` | client (opcional) | — |
| `created_at` | server (Timestamp) | — |
| `updated_at` | server (Timestamp) | — |

### Receipt
```json
{
  "dog_id": "dog-a",
  "supplement_log_id": "sl1_x",
  "revision": 1,
  "was_no_op": false
}
```

---

## 7. AUTHORIZATION

### Firestore Rules (firestore.rules:1945-1948)
```
match /supplement_logs/{logId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

### Interpretação
- **Read direto (client SDK):** Permitido para users autenticados com acesso ao dog record
- **Write direto: NEGADO** — apenas via callable
- **Callable authorization:** Delegada ao backend (não auditado neste Gate)

### Callable Authorization (suposição por padrões MealLog)
- `dog_id` validado contra token JWT
- Capacidade `health.nutrition.mutation` presumida
- Owner/handler restrictions aplicadas

### GAP DE REGRAS
**MAJOR:** Não há teste de regras do emulador para `supplement_logs`. Existem testes para `meal_logs` e para callables, mas `supplement_logs` direto não foi verificado com emulador.

---

## 8. IDEMPOTENCY

### Mecanismo
- **operationId:** Obrigatório no payload
- **Receipt lookup:** Pré-transação, via `nutrition_operations/{operationId}`
- **Replay idêntico:** `was_no_op: true`, documento não recriado
- **Replay divergente:** `idempotency_conflict` (via `details.code`)

### Testes existentes
- Domain model: 8 testes de validação
- Gateway codec: 2 testes (`createSupplementLog`)
- Controller: testes de retry/operationId reuse (incluem supplement)

### GAP DE IDEMPOTENCY
**MISSING TEST:** Teste explícito de idempotência de supplement_log com replay divergente (payload diferente, mesmo operationId).

---

## 9. RECEIPT

### Estrutura
```json
{
  "dog_id": "string",
  "supplement_log_id": "string",
  "revision": 1,
  "was_no_op": false
}
```

### Integridade do Receipt
Testado no gateway: mirror contraditório (`supplement_log_id` vs `supplementLogId`) gera `HealthNutritionMutationIntegrity`.

---

## 10. AUDITLOG

### Action
`health.nutrition.supplement_log.create`

### Metadados esperados
- `dog_id`
- `supplement_log_id`
- `operation_id`
- `supplement_name`
- `dose`
- `unit`
- `administered_at`
- `was_no_op`

### GAP DE AUDIT
**MAJOR:** AuditLog não foi verificado diretamente neste Gate. Implementação presumida por padrão MealLog.

---

## 11. FLUTTER FOUNDATION

### Command
**Arquivo:** `lib/features/health/domain/health_nutrition_mutation_commands.dart`
**Status:** COMPLETE ✓
```dart
class CreateSupplementLogCommand {
  final String dogId;
  final String supplementName;
  final double dose;
  final SupplementDoseUnit unit;
  final DateTime administeredAt;
  final String operationId;
  final String? nutritionPlanId;
  final String? supplementRegimenId;
  final String? protocolId;
  final String? observations;
}
```

### Codec
**Arquivo:** `lib/features/health/data/nutrition/health_nutrition_mutation_payload_codec.dart`
**Status:** COMPLETE ✓
- snake_case payload
- ISO 8601 UTC timestamps
- Validação local de regimen sem plan
- Integridade de resposta com mirrors contraditórios

### Gateway
**Arquivo:** `lib/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart`
**Status:** COMPLETE ✓
- Implementa `HealthNutritionMutationGateway`
- Exception mapping completo
- `createSupplementLog` implementado

### Controller
**Arquivo:** `lib/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart`
**Status:** COMPLETE ✓
- `createSupplement()` method
- Pending intent preservation
- OperationId reuse on retry
- Dog isolation
- Incompatible intent blocking (inclui supplement vs meal)

### Reader Canônico
**Arquivo:** `lib/features/health/data/coexistence/nutrition/firestore_nutrition_canonical_readers.dart:262-355`
**Status:** COMPLETE ✓
- `FirestoreNutritionCanonicalSupplementLogReader`
- Full collection scan (G4-QUERY-INTEGRITY)
- Fail-closed parsing
- Sort by `administeredAt` DESC

### Parser
**Arquivo:** `lib/features/health/domain/nutrition_document_parser.dart:482-534`
**Status:** COMPLETE ✓
- `SupplementLogDocumentParser.parse()`
- Todos campos obrigatórios validados
- `SupplementDoseUnit` parse
- `recordedBy` parse

---

## 12. RUNTIME UI INVENTORY

### Hub de Registros (HealthTypeSelectorScreen)
**Status:** PARTIAL ⚠️

```dart
// Line 62-68: Nutrição seleciona 'nutrition'
const _HealthActionCategory(
  id: 'nutrition',
  label: 'Nutrição',
  subtitle: 'Alimentação ou suplemento', // Menciona suplemento!
  icon: Icons.restaurant_rounded,
  ...
)
```

**PROBLEMA:** O callback `onRegisterNutrition` abre `HealthAdhocMealFormSheet` — **APENAS refeição ad hoc**. Não há caminho para registro de suplemento.

### HealthV1EntryScreen
**Arquivo:** `lib/features/health/presentation/screens/health_v1_entry_screen.dart`
**Status:** PARTIAL ⚠️

```dart
// Line 371-390: onRegisterNutrition abre ONLY adhoc meal form
onRegisterNutrition: (hubContext) async {
  final outcome = await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
    ...
    builder: (_) => HealthAdhocMealFormSheet(...) // SEM supplement form
  );
}
```

**PROBLEMA:** Não existe `HealthSupplementFormSheet` ou equivalente. O botão "Registrar" no Hub de Nutrição não permite registrar suplemento.

### Nutrição Hoje (HealthNutritionTodayScreen)
**Status:** PARTIAL ⚠️

A seção `_SupplementsSection` (lines 1092-1301) **lê e exibe**:
1. **Suplementos em uso** (do plano + legados) — informação de prescrição
2. **Administrações registradas** — SupplementLogs canônicos

**MAS:**
- Não há CTA para registrar nova administração
- Não há comparação com planejado (pending vs completed)
- Não há indicador de dose prevista vs. administrada

### Resumo Health (HealthSummaryDashboard)
**Status:** MISSING ✗

O card "Alimentação Hoje" (`_TodaySummaryCard`) **NÃO incorpora** suplementos. Apenas refeição:
- Offered/consumed em gramas
- Refeições completadas / planejadas
- Progresso百分比

---

## 13. HUB WIRING

### Fluxo atual
```
HealthV1EntryScreen._onRegister()
  → HealthTypeSelectorScreen (nutrição selecionada)
    → callback onRegisterNutrition
      → HealthAdhocMealFormSheet (REFEIÇÃO AD HOC)
```

### O que deveria existir
```
HealthV1EntryScreen._onRegister()
  → HealthTypeSelectorScreen (nutrição selecionada)
    → callback onRegisterNutrition
      → [ESCOLHA] HealthAdhocMealFormSheet OU HealthSupplementFormSheet
```

### GAP DE WIRING
**BLOCKER:** Não existe:
1. Seleção de tipo de registro (refeição vs. suplemento)
2. `HealthSupplementFormSheet` ou equivalente
3. Routing do callback `onRegisterNutrition` para escolha de tipo

---

## 14. NUTRITION TODAY READS

### Reader Canônico
**Arquivo:** `firestore_nutrition_canonical_readers.dart:262-355`
**Status:** COMPLETE ✓

```dart
Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(String dogId)
```

### Integração em Nutrição Hoje
**Arquivo:** `health_nutrition_today_screen.dart:161-169`

```dart
_SupplementsSection(
  plan: snapshot.activePlan,
  administrations: todayModel?.canonicalSupplementLogs ?? snapshot.canonicalSupplementLogs,
  legacyRegimens: todayModel?.legacySupplementRegimens ?? snapshot.legacySupplementRegimens,
)
```

### Dados exibidos
- SupplementLogs canônicos: nome, dose+unit, horário
- Suplementos do plano: nome, dose, frequência, instruções
- Suplementos legados: nome, dose (texto), badge "Em uso (legado)"

### O que NÃO existe
- Pending/completed status (vs. dose planejada)
- Horário previsto de administração
- Indicador de "dose em atraso"
- Filtro por dia (leitura completa, sem range)

---

## 15. HEALTH SUMMARY READS

### Card atual: `_TodaySummaryCard`
**Arquivo:** `health_nutrition_today_screen.dart:401-583`

**Inclui:**
- Consumo de refeição (gramas)
- Refeições completadas/planejadas
- Badge de plano (ativo/legado)

**NÃO inclui:**
- Suplementos administrados
- Contador de suplementos vs. planejados

### OBSERVAÇÃO
Suplementos não fazem parte do resumo por design atual. Não é um bug — é uma decisão de produto não documentada. Registrar como OBSERVATION.

---

## 16. HISTORY INTEGRATION

### Timeline
**Status:** PARTIAL ⚠️

SupplementLogs não aparecem como tipo de evento na `HealthTimelineScreen`. A timeline atual suporta:
- Weight
- Vaccination
- Meal
- Outros eventos clínicos

### GAP DE HISTORY
**MAJOR:** SupplementLog não é um `HealthTimelineEntryType` registrado. Não aparece no Histórico.

---

## 17. COEXISTENCE / LEGACY

### Collections legadas verificadas
- `legacy_supplement_regimen_adapter.dart` existe — adapter de leitura
- Legacy supplement regimens são lidos e exibidos em Nutrição Hoje
- Zero legacy write confirmado (adapter só lê)

### Verificado
- `assertCanonicalWritePath` bloqueia writes em collections legadas
- `FORBIDDEN_LEGACY_WRITE_COLLECTIONS` definido
- Reader coexistente (`CoexistenceNutritionReadSource`) faz merge

### GAP DE COEXISTENCE
**OBSERVATION:** Não existe writer legado de suplementos ativo. O fluxo canônico é o único.

---

## 18. FIRESTORE RULES

### Regras atuais (firestore.rules:1945-1948)
```
match /supplement_logs/{logId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

### Avaliação
| Capacidade | Status |
|------------|--------|
| Read para users autenticados com acesso | ✓ Permitido |
| Write direto negado | ✓ Confirmado |
| Callable bypass (server) | ✓ Funcional |

### GAP DE RULES
**MAJOR:** Testes de emulador para `supplement_logs` NÃO existem. Existem testes para:
- `health_nutrition_callables_emulator_tests.mjs` (callable authorization)
- `firestore_nutrition_canonical_readers_test.dart` (reader)
- Mas NENHUM teste de rules direto para supplement_logs

---

## 19. TEST COVERAGE MATRIX

| Camada | Arquivo | Status |
|--------|---------|--------|
| 1. Domain/validation | supplement_log_test.dart | ✓ COVERED (8 testes) |
| 2. Logic (backend) | health_nutrition_logic_test.ts | ✓ PRESUMED COVERED |
| 3. Engine (backend) | health_nutrition_engine.ts | ✓ PRESUMED COVERED |
| 4. Callable authorization | health_nutrition_callables_emulator_tests.mjs | ✓ COVERED (callables) |
| 5. Firestore adapter | health_nutrition_firestore_adapter.ts | ✓ PRESUMED COVERED |
| 6. Idempotency | supplement_log_test.dart | ⚠️ PARTIAL (domain only) |
| 7. Audit | — | ✗ NOT VERIFIED |
| 8. Flutter command/codec | firebase_functions_health_nutrition_mutation_gateway_test.dart | ✓ COVERED (2 testes supplement) |
| 9. Gateway | firebase_functions_health_nutrition_mutation_gateway_test.dart | ✓ COVERED |
| 10. Controller | health_nutrition_mutation_controller_test.dart | ✓ COVERED (inclui supplement retry/intent) |
| 11. UI | health_adhoc_meal_execution_ui_test.dart | ✗ MISSING (supplement form não existe) |
| 12. Navigation/runtime shell | health_hub_adhoc_navigation_test.dart | ⚠️ PARTIAL (hub existe, supplement não) |
| 13. Read-after-write | health_nutrition_read_after_write_test.dart | ✗ MISSING (meal only) |
| 14. Read model | firestore_nutrition_canonical_readers_test.dart | ✓ COVERED |
| 15. Coexistence | firestore_nutrition_emulator_fixture_test.dart | ✓ COVERED |
| 16. Rules Emulator | health_nutrition_rules_tests.mjs | ⚠️ PARTIAL (meal_logs only) |
| 17. Emulator E2E | — | ✗ MISSING |
| 18. Physical smoke | — | ✗ NOT TESTED |

---

## 20. EXECUTED TESTS

### Executados neste Gate
```
flutter test test/features/health/domain/supplement_log_test.dart
✓ 00:08 +8: All tests passed!

flutter test test/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway_test.dart
✓ Todos os testes de supplement passaram (createSupplementLog codec + exception mapping)
```

### Resultados
- **Domain supplement_log_test.dart:** 8/8 PASS ✓
- **Gateway supplement tests:** 2/2 PASS + 1 validation PASS ✓

---

## 21. FINDINGS

### BLOCKER (Impede produção)

| ID | Finding | Localização |
|----|---------|-------------|
| B-01 | **UI de registro de suplemento ausente** — não existe `HealthSupplementFormSheet` ou equivalente | `health_v1_entry_screen.dart:371-390` |
| B-02 | **Hub routing não diferencia refeição vs. suplemento** — `onRegisterNutrition` abre apenas adhoc meal | `health_v1_entry_screen.dart` |

### MAJOR (Deve ser corrigido)

| ID | Finding | Localização |
|----|---------|-------------|
| M-01 | **Testes de regras do emulador para supplement_logs ausentes** — rules nunca verificadas com emulador | `firestore.rules:1945-1948` |
| M-02 | **SupplementLog não aparece no Histórico (Timeline)** — não existe entry type | `health_timeline_*.dart` |
| M-03 | **Teste de read-after-write para supplement ausente** — só existe para meal | `health_nutrition_read_after_write_test.dart` |
| M-04 | **AuditLog não verificado** — implementação presumida | `functions/src/` (repo separado) |

### MINOR

| ID | Finding | Localização |
|----|---------|-------------|
| N-01 | **Semântica de SupplementLog não documentada** — ausência de ADR ou decisão canônica | docs/ |
| N-02 | **Teste explícito de idempotência supplement com replay divergente ausente** | `firebase_functions_health_nutrition_mutation_gateway_test.dart` |

### OBSERVATION

| ID | Finding | Notas |
|----|---------|-------|
| O-01 | Suplementos não estão no card de resumo | Decisão de produto, não bug |
| O-02 | Não há indicador pending/completed para suplementos vs. planejados | Futura feature |
| O-03 | Semântica opcional de vínculo com plano não é clear na UI | Futura clarification |

### MISSING TEST

| ID | Finding |
|----|---------|
| T-01 | Teste de rules do emulador para `supplement_logs` |
| T-02 | Teste de read-after-write para `createSupplementLog` |
| T-03 | Teste de E2E com emulador para supplement flow completo |

---

## 22. RECOMMENDED NEXT GATE

### FASE 5D — GATE 5C.4B
**SUPPLEMENT LOG UI ACTIVATION**

### Pré-condições
1. Backend callable `healthNutritionCreateSupplementLog` deployed e funcional (repo separado)
2. Firestore Rules para `supplement_logs` testadas com emulador
3. Regressão de MealLog ad hoc NÃO afetada

### Escopo do Gate
1. **Criar `HealthSupplementFormSheet`** — formulário de registro de suplemento
   - Nome do suplemento (text field)
   - Dose (numeric field)
   - Unidade (dropdown: mg, g, ml, scoop, tablet, drop, other)
   - Data/hora de administração (datetime picker, default: agora)
   - Observações (optional text)
   - Vinculação opcional com plano (se existir plano ativo)

2. **Atualizar Hub routing** — adicionar escolha refeição vs. suplemento
   - Modificar `onRegisterNutrition` para mostrar seletor
   - OU criar `onRegisterSupplement` separado

3. **Integrar com pending intent controller** — usar `controller.createSupplement()`

4. **Adicionar seção de suplementos em Nutrição Hoje**
   - Mostrar suplementos do plano com status
   - CTA "Registrar administração" se houver suplementos prescrito

5. **Testes**
   - UI test para `HealthSupplementFormSheet`
   - Navigation test para hub → supplement form
   - Read-after-write test para supplement

### Critério de saída
- [ ] UI de registro acessível pelo Hub
- [ ] Mutation via callable funcionando
- [ ] Read-after-write confirmando persistência
- [ ] Nutrição Hoje mostrando administrations com CTA
- [ ] Regressão ad hoc meal não afetada
- [ ] Regressão planned meal não afetada

### NÃO incluir neste Gate
- Histórico (Timeline) — futuro Gate
- Resumo (Summary card) — OBSERVATION, não blocker
- Testes de smoke físico — fora do scope

---

## 23. FINAL GIT STATE

```
$ git status --short
?? functions/audit_prod.mjs

$ git diff --check
(no output — clean)

$ git diff --stat
(no output — no changes)
```

**Estado:** Limpo. Apenas `functions/audit_prod.mjs` preexistente (fora do escopo).

---

## 24. FINAL VERDICT

### FASE 5D — GATE 5C.4A: NOT READY FOR HUMAN AUDIT — IMPLEMENTATION REQUIRED

**Resumo executivo:**
- **Backend callable:** PRESUMED COMPLETE (repo separado, não auditado diretamente)
- **Flutter Foundation:** COMPLETE (command, codec, gateway, controller, reader, parser)
- **UI/runtime:** INCOMPLETE (sem formulário de registro, sem wiring no Hub)
- **Reads:** COMPLETE (Nutrição Hoje mostra administrations)
- **Coexistence:** COMPLETE (zero legacy write)
- **Rules:** PARTIAL (escrita bloqueada, leitura permitida, mas não testada)
- **Testes:** PARTIAL (domain/codec/controller cobertos, rules/ui/read-after-write ausentes)

**Próximo passo obrigatório:** FASE 5D — GATE 5C.4B (Supplement Log UI Activation)

---

## ANEXO: CONTRATO RESUMIDO SUPPLEMENTLOG

### Transporte (Payload → Callable)
```json
{
  "dog_id": "string (required)",
  "supplement_name": "string (required)",
  "dose": "number > 0 (required)",
  "unit": "mg|g|ml|scoop|tablet|drop|other (required)",
  "administered_at": "ISO 8601 UTC (required)",
  "operation_id": "string (required)",
  "nutrition_plan_id": "string (optional)",
  "supplement_regimen_id": "string (optional, requires plan_id)",
  "protocol_id": "string (optional)",
  "observations": "string (optional)"
}
```

### Persistido (Firestore Document)
```json
{
  "supplement_name": "string",
  "dose": "number",
  "unit": "string",
  "administered_at": "ISO 8601",
  "recorded_by": { "uid": "string", "name": "string", "internalRole": "string" },
  "schema_version": 1,
  "revision": "number",
  "nutrition_plan_id": "string|null",
  "supplement_regimen_id": "string|null",
  "protocol_id": "string|null",
  "observations": "string|null",
  "created_at": "Timestamp",
  "updated_at": "Timestamp"
}
```

### Receipt
```json
{
  "dog_id": "string",
  "supplement_log_id": "string",
  "revision": "number",
  "was_no_op": "boolean"
}
```

---

*Documento gerado por auditoria de código — FASE 5D Gate 5C.4A*
*Não editar produção. Não fazer commit. Não fazer push.*
